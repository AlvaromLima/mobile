/// Dados enviados para tradução. Idiomas aceitos: auto, en, es. Destino: pt-BR.
class TranslationRequest {
  const TranslationRequest({
    required this.text,
    required this.sourceLanguage,
    this.targetLanguage = defaultTargetLanguage,
  });

  static const defaultTargetLanguage = 'pt-BR';
  static const supportedSourceLanguages = {'auto', 'en', 'es'};

  final String text;
  final String sourceLanguage;
  final String targetLanguage;

  Map<String, dynamic> toJson() => {
        'text': text,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
      };
}
