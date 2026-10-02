import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart' as stt;
import 'package:speech_to_text/speech_to_text.dart';

import '../core/errors/voice_failure.dart';
import '../models/source_language.dart';
import 'speech_recognition_service.dart';

/// Reconhecimento de voz com o motor nativo (Android SpeechRecognizer / iOS SFSpeechRecognizer),
/// via `speech_to_text`, e permissões via `permission_handler`.
class SpeechToTextRecognitionService implements SpeechRecognitionService {
  SpeechToTextRecognitionService({SpeechToText? speech, bool? requiresSpeechPermission})
      : _speech = speech ?? SpeechToText(),
        _requiresSpeechPermission = requiresSpeechPermission ?? (!kIsWeb && Platform.isIOS);

  final SpeechToText _speech;

  /// No iOS, além do microfone, o reconhecimento de fala tem permissão própria.
  final bool _requiresSpeechPermission;

  /// Tempo máximo de escuta (o iOS encerra sessões acima de 1 minuto).
  static const _listenFor = Duration(seconds: 60);

  /// Silêncio que encerra a escuta.
  static const _pauseFor = Duration(seconds: 4);

  /// Locales preferidos por idioma; se nenhum existir, usa qualquer variante do idioma.
  static const _preferredLocales = {
    SourceLanguage.en: ['en_US', 'en_GB', 'en_AU', 'en_CA'],
    SourceLanguage.es: ['es_MX', 'es_US', 'es_ES', 'es_419'],
  };

  StreamController<SpeechRecognitionResult>? _session;
  String _lastWords = '';

  // Permissões

  List<Permission> get _permissions => [Permission.microphone, if (_requiresSpeechPermission) Permission.speech];

  static VoicePermission _combine(Iterable<PermissionStatus> statuses) {
    if (statuses.every((s) => s.isGranted || s.isLimited || s.isProvisional)) return VoicePermission.granted;
    // restricted (controle parental/MDM) também não pode ser alterado pelo app.
    if (statuses.any((s) => s.isPermanentlyDenied || s.isRestricted)) return VoicePermission.permanentlyDenied;
    return VoicePermission.denied;
  }

  @override
  Future<VoicePermission> permissionStatus() async =>
      _combine([for (final permission in _permissions) await permission.status]);

  @override
  Future<VoicePermission> requestPermission() async {
    final statuses = <PermissionStatus>[];
    for (final permission in _permissions) {
      final status = await permission.request();
      statuses.add(status);
      if (!status.isGranted) break; // não insiste na segunda permissão se a primeira foi negada
    }
    return _combine(statuses);
  }

  @override
  Future<void> openPermissionSettings() async {
    await openAppSettings();
  }

  // Escuta

  @override
  Stream<SpeechRecognitionResult> listen(SourceLanguage language) {
    if (language == SourceLanguage.auto) throw ArgumentError.value(language, 'language', 'informe en ou es');

    _discardSession();
    final controller = StreamController<SpeechRecognitionResult>();
    _session = controller;
    _lastWords = '';
    controller.onListen = () => _start(language, controller);
    return controller.stream;
  }

  Future<void> _start(SourceLanguage language, StreamController<SpeechRecognitionResult> controller) async {
    try {
      final available = await _speech.initialize(onError: _onError, onStatus: _onStatus);
      if (!available) throw const SpeechUnavailableFailure();
      final localeId = await _localeFor(language);
      if (_session != controller) return; // cancelado durante a preparação

      await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: _listenFor,
          pauseFor: _pauseFor,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } on VoiceFailure catch (failure) {
      _finishWithError(controller, failure);
    } catch (_) {
      _finishWithError(controller, const SpeechServiceFailure());
    }
  }

  Future<String> _localeFor(SourceLanguage language) async {
    final ids = (await _speech.locales()).map((l) => l.localeId).toList();
    final preferred = _preferredLocales[language]!;
    String normalize(String id) => id.replaceAll('-', '_').toLowerCase();

    // Alguns aparelhos não listam locales; nesse caso tenta o preferido e deixa o motor decidir.
    if (ids.isEmpty) return preferred.first;

    for (final candidate in preferred) {
      final match = ids.where((id) => normalize(id) == candidate.toLowerCase()).firstOrNull;
      if (match != null) return match;
    }
    final anyVariant = ids
        .where((id) => normalize(id) == language.code || normalize(id).startsWith('${language.code}_'))
        .firstOrNull;
    if (anyVariant != null) return anyVariant;
    throw SpeechLanguageUnavailableFailure(language.label.toLowerCase());
  }

  void _onResult(stt.SpeechRecognitionResult result) {
    final controller = _session;
    if (controller == null || controller.isClosed) return;

    _lastWords = result.recognizedWords;
    if (!result.finalResult) {
      controller.add(SpeechRecognitionResult(text: _lastWords, isFinal: false));
      return;
    }
    if (_lastWords.trim().isEmpty) {
      _finishWithError(controller, const NoSpeechDetectedFailure());
      return;
    }
    controller.add(SpeechRecognitionResult(text: _lastWords, isFinal: true));
    _closeSession(controller);
  }

  void _onStatus(String status) {
    final controller = _session;
    if (status != SpeechToText.doneStatus || controller == null || controller.isClosed) return;

    // Fim da escuta sem resultado final explícito.
    if (_lastWords.trim().isEmpty) {
      _finishWithError(controller, const NoSpeechDetectedFailure());
    } else {
      controller.add(SpeechRecognitionResult(text: _lastWords, isFinal: true));
      _closeSession(controller);
    }
  }

  void _onError(SpeechRecognitionError error) {
    final controller = _session;
    // Erros não permanentes não encerram a escuta.
    if (!error.permanent || controller == null || controller.isClosed) return;
    _finishWithError(controller, mapError(error.errorMsg));
  }

  /// Converte os códigos de erro do speech_to_text (Android e iOS) em falhas com mensagem amigável.
  @visibleForTesting
  static VoiceFailure mapError(String errorMsg) {
    switch (errorMsg) {
      case 'error_permission':
      case 'error_insufficient_permissions':
        return const MicrophonePermissionDeniedFailure();
      case 'error_audio_error':
      case 'error_audio':
        return const MicrophoneUnavailableFailure();
      case 'error_speech_timeout':
        return const NoSpeechDetectedFailure();
      case 'error_no_match':
        return const SpeechNotRecognizedFailure();
      case 'error_client':
      case 'error_server_disconnected':
        return const SpeechInterruptedFailure();
      case 'error_speech_recognizer_disabled':
        return const SpeechUnavailableFailure();
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        return const SpeechLanguageUnavailableFailure('o idioma escolhido');
    }
    return const SpeechServiceFailure();
  }

  @override
  Future<void> stop() async {
    // O speech_to_text entrega o resultado final (ou o último parcial) após o stop.
    if (_session == null) return;
    await _speech.stop();
  }

  @override
  Future<void> cancel() async {
    _discardSession();
    await _speech.cancel();
  }

  void _finishWithError(StreamController<SpeechRecognitionResult> controller, VoiceFailure failure) {
    if (controller.isClosed) return;
    controller.addError(failure);
    _closeSession(controller);
  }

  void _closeSession(StreamController<SpeechRecognitionResult> controller) {
    if (_session == controller) _session = null;
    unawaited(controller.close());
  }

  void _discardSession() {
    final previous = _session;
    _session = null;
    if (previous != null && !previous.isClosed) unawaited(previous.close());
  }
}
