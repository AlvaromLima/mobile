import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/voice_failure.dart';
import '../services/flutter_tts_text_to_speech_service.dart';
import '../services/text_to_speech_service.dart';

final textToSpeechServiceProvider = Provider<TextToSpeechService>((ref) {
  final service = FlutterTtsTextToSpeechService();
  ref.onDispose(service.stop);
  return service;
});

enum PlaybackStatus { idle, speaking, failure }

class PlaybackState {
  const PlaybackState({this.status = PlaybackStatus.idle, this.errorMessage});

  final PlaybackStatus status;
  final String? errorMessage;

  bool get isSpeaking => status == PlaybackStatus.speaking;
}

final textToSpeechProvider = NotifierProvider<TextToSpeechNotifier, PlaybackState>(TextToSpeechNotifier.new);

/// Controla a leitura da tradução em voz alta (play/stop). Nenhuma falha escapa daqui.
class TextToSpeechNotifier extends Notifier<PlaybackState> {
  /// Identifica a leitura atual; resultados de leituras anteriores são ignorados.
  int _session = 0;

  TextToSpeechService get _service => ref.read(textToSpeechServiceProvider);

  @override
  PlaybackState build() => const PlaybackState();

  Future<void> play(String text) async {
    if (state.isSpeaking || text.trim().isEmpty) return;
    final session = ++_session;
    state = const PlaybackState(status: PlaybackStatus.speaking);

    try {
      await _service.speak(text);
      if (session == _session) state = const PlaybackState();
    } on VoiceFailure catch (failure) {
      if (session == _session) state = PlaybackState(status: PlaybackStatus.failure, errorMessage: failure.message);
    } catch (_) {
      if (session == _session) {
        state = PlaybackState(
          status: PlaybackStatus.failure,
          errorMessage: const TextToSpeechPlaybackFailure().message,
        );
      }
    }
  }

  /// Interrompe a leitura (botão Parar, nova tradução, microfone ou app em segundo plano).
  Future<void> stop() async {
    _session++;
    // Sem leitura em andamento, não há o que interromper no motor nativo.
    if (!state.isSpeaking) {
      if (state.status != PlaybackStatus.idle) state = const PlaybackState();
      return;
    }
    state = const PlaybackState();
    try {
      await _service.stop();
    } catch (_) {
      // Parar é melhor esforço.
    }
  }

  Future<void> toggle(String text) => state.isSpeaking ? stop() : play(text);
}
