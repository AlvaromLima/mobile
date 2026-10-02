import '../models/translation_request.dart';
import '../models/translation_result.dart';

/// Fonte dos dados de tradução. Implementações devem lançar apenas
/// TranslationFailure (conexão, timeout, servidor, resposta inválida, idioma).
abstract interface class TranslationRepository {
  Future<TranslationResult> translate(TranslationRequest request);
}
