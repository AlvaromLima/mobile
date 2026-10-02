import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/source_language.dart';

/// Tradução simulada, usada apenas para validar a interface.
/// Será substituída pela camada de tradução real (TranslationService/Repository).
typedef TranslateFn = Future<String> Function(String text, SourceLanguage source);

final translateFnProvider = Provider<TranslateFn>((ref) => _simulateTranslation);

Future<String> _simulateTranslation(String text, SourceLanguage source) async {
  await Future<void>.delayed(const Duration(milliseconds: 800));
  return '[Tradução simulada] $text';
}
