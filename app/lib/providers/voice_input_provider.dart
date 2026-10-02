import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/voice_failure.dart';
import '../models/source_language.dart';
import '../services/speech_recognition_service.dart';
import '../services/speech_to_text_recognition_service.dart';

final speechRecognitionServiceProvider = Provider<SpeechRecognitionService>(
  (ref) {
    final service = SpeechToTextRecognitionService();
    ref.onDispose(service.cancel);
    return service;
  },
);

/// Estados da captura de voz: parado, solicitando permissão, ouvindo, processando, concluído e erro.
enum VoiceStatus { idle, requestingPermission, listening, processing, completed, failure }

class VoiceInputState {
  const VoiceInputState({
    this.status = VoiceStatus.idle,
    this.text = '',
    this.errorMessage,
    this.canOpenSettings = false,
  });

  final VoiceStatus status;

  /// Texto reconhecido até o momento (parcial ou final).
  final String text;
  final String? errorMessage;

  /// Permissão negada permanentemente: a interface oferece abrir as configurações.
  final bool canOpenSettings;

  bool get isActive =>
      status == VoiceStatus.requestingPermission ||
      status == VoiceStatus.listening ||
      status == VoiceStatus.processing;
}

final voiceInputProvider = NotifierProvider<VoiceInputNotifier, VoiceInputState>(VoiceInputNotifier.new);

/// Controla a captura de voz. Nenhuma falha escapa daqui: todas viram estado de erro
/// com mensagem amigável, sem fechar o app.
class VoiceInputNotifier extends Notifier<VoiceInputState> {
  StreamSubscription<SpeechRecognitionResult>? _subscription;

  /// Identifica a sessão atual; eventos de sessões anteriores são ignorados.
  int _session = 0;

  SpeechRecognitionService get _service => ref.read(speechRecognitionServiceProvider);

  @override
  VoiceInputState build() {
    ref.onDispose(() => _subscription?.cancel());
    return const VoiceInputState();
  }

  /// Verifica e, se preciso, solicita a permissão; depois começa a ouvir no idioma informado (en ou es).
  Future<void> start(SourceLanguage language) async {
    if (state.isActive) return;
    final session = ++_session;
    state = const VoiceInputState(status: VoiceStatus.requestingPermission);

    try {
      var permission = await _service.permissionStatus();
      if (permission == VoicePermission.denied) permission = await _service.requestPermission();
      if (session != _session) return;

      if (permission == VoicePermission.permanentlyDenied) {
        _fail(const MicrophonePermissionPermanentlyDeniedFailure(), canOpenSettings: true);
        return;
      }
      if (permission != VoicePermission.granted) {
        _fail(const MicrophonePermissionDeniedFailure());
        return;
      }

      state = const VoiceInputState(status: VoiceStatus.listening);
      await _subscription?.cancel();
      _subscription = _service.listen(language).listen(
            (result) => _onResult(session, result),
            onError: (Object error) => _onError(session, error),
            onDone: () => _onDone(session),
            cancelOnError: true,
          );
    } on VoiceFailure catch (failure) {
      if (session == _session) _fail(failure);
    } catch (_) {
      if (session == _session) _fail(const SpeechServiceFailure());
    }
  }

  void _onResult(int session, SpeechRecognitionResult result) {
    if (session != _session || !state.isActive) return;
    state = VoiceInputState(
      status: result.isFinal ? VoiceStatus.completed : state.status,
      text: result.text,
    );
  }

  void _onError(int session, Object error) {
    if (session != _session) return;
    _fail(error is VoiceFailure ? error : const SpeechServiceFailure());
  }

  void _onDone(int session) {
    if (session != _session || !state.isActive) return;
    // Stream encerrado sem resultado final.
    if (state.text.trim().isEmpty) {
      _fail(const NoSpeechDetectedFailure());
    } else {
      state = VoiceInputState(status: VoiceStatus.completed, text: state.text);
    }
  }

  /// Usuário pediu para parar: o reconhecedor entrega o resultado final.
  Future<void> stop() async {
    if (state.status != VoiceStatus.listening) return;
    state = VoiceInputState(status: VoiceStatus.processing, text: state.text);
    try {
      await _service.stop();
    } catch (_) {
      _fail(const SpeechServiceFailure());
    }
  }

  /// Descarta a escuta em andamento e volta ao estado parado.
  Future<void> cancel() async {
    _detach();
    state = const VoiceInputState();
    await _cancelService();
  }

  /// Interrupção externa (app em segundo plano, ligação): encerra e informa o usuário.
  Future<void> interrupt() async {
    if (!state.isActive) return;
    _detach();
    _fail(const SpeechInterruptedFailure());
    await _cancelService();
  }

  /// Desliga a sessão atual imediatamente; eventos que ainda chegarem dela são ignorados.
  void _detach() {
    _session++;
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
  }

  Future<void> _cancelService() async {
    try {
      await _service.cancel();
    } catch (_) {
      // Cancelamento é melhor esforço; nada a mostrar ao usuário.
    }
  }

  Future<void> openSettings() async {
    try {
      await _service.openPermissionSettings();
    } catch (_) {
      // Sem configurações disponíveis no aparelho: nada a fazer.
    }
  }

  void _fail(VoiceFailure failure, {bool canOpenSettings = false}) {
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
    state = VoiceInputState(
      status: VoiceStatus.failure,
      errorMessage: failure.message,
      canOpenSettings: canOpenSettings,
    );
  }
}
