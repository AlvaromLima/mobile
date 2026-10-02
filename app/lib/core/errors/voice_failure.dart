/// Falhas de voz, já com a mensagem pronta para o usuário.
/// A interface só conhece estes tipos, nunca detalhes dos pacotes nativos.
sealed class VoiceFailure implements Exception {
  const VoiceFailure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

// Speech-to-Text

final class MicrophonePermissionDeniedFailure extends VoiceFailure {
  const MicrophonePermissionDeniedFailure()
      : super('Permissão de microfone negada. Toque no microfone novamente para permitir.');
}

final class MicrophonePermissionPermanentlyDeniedFailure extends VoiceFailure {
  const MicrophonePermissionPermanentlyDeniedFailure()
      : super('O acesso ao microfone está bloqueado. Libere nas configurações do aparelho.');
}

final class MicrophoneUnavailableFailure extends VoiceFailure {
  const MicrophoneUnavailableFailure()
      : super('Microfone indisponível. Verifique se outro aplicativo está usando o microfone.');
}

final class SpeechUnavailableFailure extends VoiceFailure {
  const SpeechUnavailableFailure() : super('Reconhecimento de voz indisponível neste aparelho.');
}

final class SpeechLanguageUnavailableFailure extends VoiceFailure {
  const SpeechLanguageUnavailableFailure(String languageLabel)
      : super('Reconhecimento de voz em $languageLabel indisponível neste aparelho.');
}

final class NoSpeechDetectedFailure extends VoiceFailure {
  const NoSpeechDetectedFailure() : super('Nenhuma fala detectada. Toque no microfone e fale novamente.');
}

final class SpeechNotRecognizedFailure extends VoiceFailure {
  const SpeechNotRecognizedFailure()
      : super('Não foi possível entender a fala. Tente novamente, falando perto do microfone.');
}

final class SpeechInterruptedFailure extends VoiceFailure {
  const SpeechInterruptedFailure() : super('O reconhecimento de voz foi interrompido. Tente novamente.');
}

final class SpeechServiceFailure extends VoiceFailure {
  const SpeechServiceFailure() : super('Erro no serviço de reconhecimento de voz. Tente novamente.');
}

// Text-to-Speech

final class TextToSpeechUnavailableFailure extends VoiceFailure {
  const TextToSpeechUnavailableFailure() : super('Leitura em voz alta indisponível neste aparelho.');
}

final class TextToSpeechLanguageUnavailableFailure extends VoiceFailure {
  const TextToSpeechLanguageUnavailableFailure()
      : super('Voz em português do Brasil não instalada. Instale nas configurações de texto para fala do aparelho.');
}

final class TextToSpeechPlaybackFailure extends VoiceFailure {
  const TextToSpeechPlaybackFailure() : super('Não foi possível reproduzir o áudio. Tente novamente.');
}
