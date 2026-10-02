import '../models/source_language.dart';

/// Situação da permissão de microfone (e, no iOS, de reconhecimento de fala).
enum VoicePermission { granted, denied, permanentlyDenied }

/// Texto reconhecido até o momento. `isFinal` indica o resultado definitivo da escuta.
class SpeechRecognitionResult {
  const SpeechRecognitionResult({required this.text, required this.isFinal});

  final String text;
  final bool isFinal;
}

/// Conversão de fala em texto, independente do pacote nativo usado.
///
/// O texto reconhecido não é traduzido aqui: ele segue para o mesmo fluxo
/// da tradução digitada (TranslatorNotifier, TranslationService, TranslationRepository).
abstract interface class SpeechRecognitionService {
  /// Situação atual da permissão, sem perguntar ao usuário.
  Future<VoicePermission> permissionStatus();

  /// Pede a permissão ao usuário e devolve o resultado.
  Future<VoicePermission> requestPermission();

  /// Abre as configurações do app, para quando a permissão foi negada permanentemente.
  Future<void> openPermissionSettings();

  /// Começa a ouvir no idioma informado ([SourceLanguage.en] ou [SourceLanguage.es]).
  ///
  /// Emite resultados parciais e, por último, um resultado com `isFinal = true`;
  /// o stream termina quando a escuta acaba. Falhas chegam como erro do stream,
  /// sempre do tipo VoiceFailure. [SourceLanguage.auto] não é aceito, porque o
  /// reconhecedor nativo precisa do idioma antes de ouvir.
  Stream<SpeechRecognitionResult> listen(SourceLanguage language);

  /// Encerra a escuta e entrega o resultado final do que já foi falado.
  Future<void> stop();

  /// Encerra a escuta descartando o que foi falado.
  Future<void> cancel();
}
