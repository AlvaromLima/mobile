import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';
import 'package:tradutor/core/errors/voice_failure.dart';
import 'package:tradutor/models/source_language.dart';
import 'package:tradutor/services/speech_recognition_service.dart';
import 'package:tradutor/services/speech_to_text_recognition_service.dart';

/// Substitui a ponte nativa do speech_to_text.
class FakeSpeechPlatform extends SpeechToTextPlatform {
  bool initResult = true;
  Object? initError;
  List<String> localeList = ['en_US:English (United States)', 'es_MX:Español (México)'];
  String? listenedLocale;
  int stops = 0;
  int cancels = 0;

  @override
  Future<bool> initialize({debugLogging = false, List<SpeechConfigOption>? options}) async {
    if (initError != null) throw initError!;
    return initResult;
  }

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    listenedLocale = localeId;
    return true;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<List<dynamic>> locales() async => localeList;

  @override
  Future<bool> hasPermission() async => true;

  void emitResult(String words, {bool isFinal = false}) => onTextRecognition?.call(jsonEncode({
        'alternates': [
          {'recognizedWords': words, 'recognizedPhrases': null, 'confidence': 0.9},
        ],
        'resultType': isFinal ? 2 : 0,
      }));

  void emitError(String errorMsg, {bool permanent = true}) =>
      onError?.call(jsonEncode({'errorMsg': errorMsg, 'permanent': permanent}));

  void emitStatus(String status) => onStatus?.call(status);
}

/// Substitui a ponte nativa do permission_handler.
class FakePermissionPlatform extends PermissionHandlerPlatform {
  final statuses = <Permission, PermissionStatus>{};
  final afterRequest = <Permission, PermissionStatus>{};
  final requested = <Permission>[];
  bool settingsOpened = false;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      statuses[permission] ?? PermissionStatus.denied;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(List<Permission> permissions) async {
    requested.addAll(permissions);
    return {for (final p in permissions) p: afterRequest[p] ?? statuses[p] ?? PermissionStatus.denied};
  }

  @override
  Future<bool> openAppSettings() async => settingsOpened = true;
}

class Collected {
  final results = <SpeechRecognitionResult>[];
  final errors = <Object>[];
  final done = Completer<void>();

  Future<void> finished() => done.future.timeout(const Duration(seconds: 1));
  List<(String, bool)> get events => [for (final r in results) (r.text, r.isFinal)];
}

Matcher emitsFailure<T extends VoiceFailure>() => emitsError(isA<T>());

void main() {
  late FakeSpeechPlatform speech;
  late FakePermissionPlatform permissions;

  SpeechToTextRecognitionService service({bool ios = false}) => SpeechToTextRecognitionService(
        // ignore: invalid_use_of_visible_for_testing_member
        speech: SpeechToText.withMethodChannel(),
        requiresSpeechPermission: ios,
      );

  /// Inicia a escuta, coleta os eventos e aguarda a preparação (initialize, locales, listen).
  Future<Collected> startListening(SpeechToTextRecognitionService s, SourceLanguage language) async {
    final collected = Collected();
    s.listen(language).listen(collected.results.add, onError: collected.errors.add, onDone: collected.done.complete);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return collected;
  }

  setUp(() {
    speech = FakeSpeechPlatform();
    permissions = FakePermissionPlatform();
    SpeechToTextPlatform.instance = speech;
    PermissionHandlerPlatform.instance = permissions;
  });

  group('permissões', () {
    test('Android: só o microfone é verificado', () async {
      permissions.statuses[Permission.microphone] = PermissionStatus.granted;
      expect(await service().permissionStatus(), VoicePermission.granted);
    });

    test('iOS: microfone e reconhecimento de fala precisam estar concedidos', () async {
      permissions.statuses[Permission.microphone] = PermissionStatus.granted;
      permissions.statuses[Permission.speech] = PermissionStatus.denied;
      expect(await service(ios: true).permissionStatus(), VoicePermission.denied);

      permissions.statuses[Permission.speech] = PermissionStatus.granted;
      expect(await service(ios: true).permissionStatus(), VoicePermission.granted);
    });

    test('negada permanentemente ou restrita vira permanentlyDenied', () async {
      permissions.statuses[Permission.microphone] = PermissionStatus.permanentlyDenied;
      expect(await service().permissionStatus(), VoicePermission.permanentlyDenied);

      permissions.statuses[Permission.microphone] = PermissionStatus.restricted;
      expect(await service().permissionStatus(), VoicePermission.permanentlyDenied);
    });

    test('iOS: se o microfone for negado, não pede o reconhecimento de fala', () async {
      permissions.afterRequest[Permission.microphone] = PermissionStatus.permanentlyDenied;

      expect(await service(ios: true).requestPermission(), VoicePermission.permanentlyDenied);
      expect(permissions.requested, [Permission.microphone]);
    });

    test('iOS: pede microfone e depois reconhecimento de fala', () async {
      permissions.afterRequest[Permission.microphone] = PermissionStatus.granted;
      permissions.afterRequest[Permission.speech] = PermissionStatus.granted;

      expect(await service(ios: true).requestPermission(), VoicePermission.granted);
      expect(permissions.requested, [Permission.microphone, Permission.speech]);
    });

    test('abre as configurações do app', () async {
      await service().openPermissionSettings();
      expect(permissions.settingsOpened, isTrue);
    });
  });

  group('escolha do idioma de reconhecimento', () {
    test('inglês usa en_US', () async {
      final s = service();
      await startListening(s, SourceLanguage.en);
      expect(speech.listenedLocale, 'en_US');
      await s.cancel();
    });

    test('espanhol prefere es_MX', () async {
      final s = service();
      await startListening(s, SourceLanguage.es);
      expect(speech.listenedLocale, 'es_MX');
      await s.cancel();
    });

    test('espanhol aceita qualquer variante disponível (formato iOS)', () async {
      speech.localeList = ['en-US:English', 'es-AR:Español (Argentina)'];
      final s = service();
      await startListening(s, SourceLanguage.es);
      expect(speech.listenedLocale, 'es-AR');
      await s.cancel();
    });

    test('sem lista de idiomas no aparelho, tenta o preferido', () async {
      speech.localeList = [];
      final s = service();
      await startListening(s, SourceLanguage.es);
      expect(speech.listenedLocale, 'es_MX');
      await s.cancel();
    });

    test('idioma não instalado no aparelho vira SpeechLanguageUnavailableFailure', () async {
      speech.localeList = ['en_US:English'];
      expect(service().listen(SourceLanguage.es), emitsFailure<SpeechLanguageUnavailableFailure>());
    });

    test('modo automático não é aceito', () {
      expect(() => service().listen(SourceLanguage.auto), throwsArgumentError);
    });
  });

  group('escuta', () {
    test('reconhecimento indisponível no aparelho', () async {
      speech.initResult = false;
      expect(service().listen(SourceLanguage.en), emitsFailure<SpeechUnavailableFailure>());
    });

    test('exceção nativa vira falha do serviço com o código do erro', () async {
      speech.initError = PlatformException(code: 'recognizerNotAvailable');
      await expectLater(
        service().listen(SourceLanguage.en),
        emitsError(isA<SpeechServiceFailure>()
            .having((f) => f.message, 'message', contains('código: recognizerNotAvailable'))),
      );
    });

    test('emite parciais e termina no resultado final', () async {
      final s = service();
      final collected = await startListening(s, SourceLanguage.en);

      speech.emitResult('Good');
      speech.emitResult('Good morning', isFinal: true);
      await collected.finished();

      expect(collected.events, [('Good', false), ('Good morning', true)]);
      expect(collected.errors, isEmpty);
    });

    test('resultado final vazio vira "nenhuma fala detectada"', () async {
      final s = service();
      final stream = s.listen(SourceLanguage.en);
      final expectation = expectLater(stream, emitsFailure<NoSpeechDetectedFailure>());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      speech.emitResult('', isFinal: true);
      await expectation;
    });

    test('ao parar sem resultado final da plataforma, entrega o último parcial como final', () async {
      final s = service();
      final collected = await startListening(s, SourceLanguage.en);

      speech.emitResult('Hello there');
      await s.stop();
      // O speech_to_text promove o último parcial a final após SpeechToText.defaultFinalTimeout.
      await collected.done.future.timeout(SpeechToText.defaultFinalTimeout + const Duration(seconds: 1));

      expect(collected.events.last, ('Hello there', true));
    });

    test('fim da escuta sem fala vira "nenhuma fala detectada"', () async {
      final s = service();
      final stream = s.listen(SourceLanguage.en);
      final expectation = expectLater(stream, emitsFailure<NoSpeechDetectedFailure>());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Status enviado pela plataforma quando a escuta termina sem nenhuma fala.
      speech.emitStatus('doneNoResult');
      await expectation;
    });

    final errorCases = <String, Matcher>{
      'error_no_match': emitsFailure<SpeechNotRecognizedFailure>(),
      'error_speech_timeout': emitsFailure<NoSpeechDetectedFailure>(),
      'error_permission': emitsFailure<MicrophonePermissionDeniedFailure>(),
      'error_audio_error': emitsFailure<MicrophoneUnavailableFailure>(),
      'error_network': emitsFailure<SpeechNetworkFailure>(),
      'error_network_timeout': emitsFailure<SpeechNetworkFailure>(),
      'error_busy': emitsFailure<SpeechBusyFailure>(),
      'error_server': emitsFailure<SpeechServiceFailure>(),
    };
    errorCases.forEach((errorMsg, matcher) {
      test('erro nativo $errorMsg é mapeado', () async {
        final s = service();
        final stream = s.listen(SourceLanguage.en);
        final expectation = expectLater(stream, matcher);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        speech.emitError(errorMsg);
        await expectation;
      });
    });

    test('erro não permanente não encerra a escuta', () async {
      final s = service();
      final collected = await startListening(s, SourceLanguage.en);

      speech.emitError('error_no_match', permanent: false);
      speech.emitResult('Hello', isFinal: true);
      await collected.finished();

      expect(collected.errors, isEmpty);
      expect(collected.events, [('Hello', true)]);
    });

    test('parar aciona o stop nativo; cancelar encerra sem resultado', () async {
      final s = service();
      final collected = await startListening(s, SourceLanguage.en);

      await s.stop();
      expect(speech.stops, 1);

      await s.cancel();
      expect(speech.cancels, 1);
      await collected.finished();
      expect(collected.results, isEmpty);
    });
  });

  test('mapeamento de erros desconhecidos cai em falha do serviço', () {
    final unknown = SpeechToTextRecognitionService.mapError('error_unknown (42)');
    expect(unknown, isA<SpeechServiceFailure>());
    expect(unknown.message, contains('código: error_unknown (42)'), reason: 'o código ajuda o suporte a diagnosticar');
    expect(SpeechToTextRecognitionService.mapError('error_client'), isA<SpeechInterruptedFailure>());
    expect(
      SpeechToTextRecognitionService.mapError('error_language_unavailable'),
      isA<SpeechLanguageUnavailableFailure>(),
    );
  });
}
