import '../core/errors/translation_failure.dart';
import '../models/translation_request.dart';
import '../models/translation_result.dart';
import '../services/api_client.dart';
import 'translation_repository.dart';

/// Tradução via backend (POST /api/v1/translate). Mapeia o contrato de erros do backend
/// para [TranslationFailure]; nenhum detalhe técnico chega à interface.
class BackendTranslationRepository implements TranslationRepository {
  const BackendTranslationRepository(this._api);

  static const translatePath = 'api/v1/translate';

  final ApiClient _api;

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    final response = await _api.postJson(translatePath, request.toJson());
    final body = response.body;

    if (response.isSuccess) {
      if (body is! Map<String, dynamic> || body['success'] != true) throw const InvalidResponseFailure();
      return TranslationResult.fromJson(body);
    }
    throw _failureFor(response.statusCode, _errorCode(body));
  }

  static String? _errorCode(Object? body) {
    if (body is! Map<String, dynamic>) return null;
    final error = body['error'];
    if (error is! Map<String, dynamic>) return null;
    final code = error['code'];
    return code is String ? code : null;
  }

  static TranslationFailure _failureFor(int statusCode, String? code) {
    switch (code) {
      case 'TEXT_TOO_LONG':
        return const TextTooLongFailure();
      case 'UNSUPPORTED_LANGUAGE':
        return const UnsupportedLanguageFailure();
      case 'RATE_LIMITED':
        return const RateLimitedFailure();
      case 'PROVIDER_TIMEOUT':
        return const TimeoutFailure();
      case 'QUOTA_EXCEEDED':
      case 'PROVIDER_UNAVAILABLE':
        return const ServerUnavailableFailure();
    }
    // Sem código conhecido: decide pelo status (ex.: proxy, rota inexistente, servidor fora).
    if (statusCode == 429) return const RateLimitedFailure();
    if (statusCode >= 500 || statusCode == 404) return const ServerUnavailableFailure();
    return const UnknownFailure();
  }
}
