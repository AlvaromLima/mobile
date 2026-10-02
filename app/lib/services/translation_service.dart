import '../core/constants/app_constants.dart';
import '../core/errors/translation_failure.dart';
import '../models/translation_request.dart';
import '../models/translation_result.dart';
import '../repositories/translation_repository.dart';

/// Ponto único de tradução usado pela interface (texto digitado e, depois, voz).
abstract interface class TranslationService {
  /// Lança apenas [TranslationFailure].
  Future<TranslationResult> translate({
    required String text,
    required String sourceLanguage,
    String targetLanguage = TranslationRequest.defaultTargetLanguage,
  });
}

class DefaultTranslationService implements TranslationService {
  const DefaultTranslationService(this._repository);

  final TranslationRepository _repository;

  static const _supportedResultLanguages = {'en', 'es'};

  @override
  Future<TranslationResult> translate({
    required String text,
    required String sourceLanguage,
    String targetLanguage = TranslationRequest.defaultTargetLanguage,
  }) async {
    if (text.trim().isEmpty) throw const EmptyTextFailure();
    if (text.length > AppConstants.maxTextLength) throw const TextTooLongFailure();
    if (!TranslationRequest.supportedSourceLanguages.contains(sourceLanguage) ||
        targetLanguage != TranslationRequest.defaultTargetLanguage) {
      throw const UnsupportedLanguageFailure();
    }

    final TranslationResult result;
    try {
      result = await _repository.translate(
        TranslationRequest(text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage),
      );
    } on TranslationFailure {
      rethrow;
    } catch (_) {
      // Erro não previsto pelo repositório: nunca propagar detalhes técnicos à interface.
      throw const UnknownFailure();
    }

    // Garante a regra de negócio mesmo que a origem dos dados falhe em aplicá-la.
    if (!_supportedResultLanguages.contains(result.sourceLanguage)) {
      throw const UnsupportedLanguageFailure();
    }
    return result;
  }
}
