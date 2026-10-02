import '../models/translation_request.dart';
import '../models/translation_result.dart';
import 'translation_repository.dart';

/// Repositório simulado, usado até a integração com o backend.
/// Não faz chamadas de rede.
class FakeTranslationRepository implements TranslationRepository {
  const FakeTranslationRepository({this.delay = const Duration(milliseconds: 800)});

  final Duration delay;

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    await Future<void>.delayed(delay);
    final isAuto = request.sourceLanguage == 'auto';
    return TranslationResult(
      originalText: request.text,
      translatedText: '[Tradução simulada] ${request.text}',
      // Na simulação, a detecção automática assume inglês.
      sourceLanguage: isAuto ? 'en' : request.sourceLanguage,
      targetLanguage: request.targetLanguage,
      detectedLanguage: isAuto ? 'en' : null,
    );
  }
}
