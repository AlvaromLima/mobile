import '../constants/app_constants.dart';

/// Falhas da tradução, já com a mensagem pronta para o usuário.
/// A interface só conhece estes tipos, nunca detalhes da API ou do HTTP.
sealed class TranslationFailure implements Exception {
  const TranslationFailure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class EmptyTextFailure extends TranslationFailure {
  const EmptyTextFailure() : super('Digite um texto para traduzir.');
}

final class TextTooLongFailure extends TranslationFailure {
  const TextTooLongFailure()
      : super('O texto excede o limite de ${AppConstants.maxTextLength} caracteres.');
}

final class UnsupportedLanguageFailure extends TranslationFailure {
  const UnsupportedLanguageFailure()
      : super('No momento, o aplicativo aceita somente textos em inglês ou espanhol.');
}

final class ConnectionFailure extends TranslationFailure {
  const ConnectionFailure() : super('Sem conexão com a internet. Verifique sua rede e tente novamente.');
}

final class TimeoutFailure extends TranslationFailure {
  const TimeoutFailure() : super('O serviço demorou a responder. Tente novamente.');
}

final class ServerUnavailableFailure extends TranslationFailure {
  const ServerUnavailableFailure() : super('Serviço de tradução indisponível no momento. Tente mais tarde.');
}

final class RateLimitedFailure extends TranslationFailure {
  const RateLimitedFailure() : super('Muitas solicitações. Aguarde alguns segundos e tente novamente.');
}

final class InvalidResponseFailure extends TranslationFailure {
  const InvalidResponseFailure() : super('Resposta inválida do servidor. Tente novamente.');
}

final class UnknownFailure extends TranslationFailure {
  const UnknownFailure() : super('Não foi possível traduzir. Tente novamente.');
}
