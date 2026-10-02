/// Leitura em voz alta da tradução, em português do Brasil, independente do pacote nativo usado.
abstract interface class TextToSpeechService {
  /// Lê [text] em pt-BR. Completa quando a leitura termina ou é interrompida por [stop].
  /// Falhas são lançadas como VoiceFailure (TTS indisponível, voz pt-BR ausente, erro de reprodução).
  Future<void> speak(String text);

  /// Interrompe a leitura em andamento. Sem efeito se nada estiver sendo lido.
  Future<void> stop();
}
