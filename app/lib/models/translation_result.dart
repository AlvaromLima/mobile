import '../core/errors/translation_failure.dart';

/// Resultado de uma tradução.
class TranslationResult {
  const TranslationResult({
    required this.originalText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.detectedLanguage,
  });

  final String originalText;
  final String translatedText;

  /// Idioma de origem efetivo (en ou es).
  final String sourceLanguage;
  final String targetLanguage;

  /// Preenchido apenas quando a origem foi detectada automaticamente.
  final String? detectedLanguage;

  /// Converte a resposta do backend. Qualquer formato inesperado vira [InvalidResponseFailure].
  factory TranslationResult.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) throw const InvalidResponseFailure();

    final translatedText = json['translatedText'];
    final originalText = json['originalText'];
    final sourceLanguage = json['sourceLanguage'];
    final targetLanguage = json['targetLanguage'];
    final detectedLanguage = json['detectedLanguage'];

    if (translatedText is! String ||
        translatedText.isEmpty ||
        originalText is! String ||
        sourceLanguage is! String ||
        targetLanguage is! String ||
        (detectedLanguage != null && detectedLanguage is! String)) {
      throw const InvalidResponseFailure();
    }

    return TranslationResult(
      originalText: originalText,
      translatedText: translatedText,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      detectedLanguage: detectedLanguage as String?,
    );
  }
}
