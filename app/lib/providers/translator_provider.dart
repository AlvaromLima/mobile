import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/source_language.dart';
import '../services/simulated_translation.dart';

enum TranslationStatus { initial, loading, success, failure }

class TranslatorState {
  const TranslatorState({
    this.sourceLanguage = SourceLanguage.auto,
    this.status = TranslationStatus.initial,
    this.translatedText,
    this.errorMessage,
  });

  final SourceLanguage sourceLanguage;
  final TranslationStatus status;
  final String? translatedText;
  final String? errorMessage;

  bool get isLoading => status == TranslationStatus.loading;
}

final translatorProvider = NotifierProvider<TranslatorNotifier, TranslatorState>(TranslatorNotifier.new);

class TranslatorNotifier extends Notifier<TranslatorState> {
  /// Identifica a requisição mais recente; respostas antigas são descartadas.
  int _requestId = 0;

  @override
  TranslatorState build() => const TranslatorState();

  void setSourceLanguage(SourceLanguage language) {
    state = TranslatorState(
      sourceLanguage: language,
      status: state.status,
      translatedText: state.translatedText,
      errorMessage: state.errorMessage,
    );
  }

  Future<void> translate(String text) async {
    if (text.trim().isEmpty || state.isLoading) return;

    final requestId = ++_requestId;
    final language = state.sourceLanguage;
    state = TranslatorState(sourceLanguage: language, status: TranslationStatus.loading);

    try {
      final translated = await ref.read(translateFnProvider)(text, language);
      if (requestId != _requestId) return;
      state = TranslatorState(
        sourceLanguage: state.sourceLanguage,
        status: TranslationStatus.success,
        translatedText: translated,
      );
    } catch (_) {
      if (requestId != _requestId) return;
      state = TranslatorState(
        sourceLanguage: state.sourceLanguage,
        status: TranslationStatus.failure,
        errorMessage: 'Não foi possível traduzir. Tente novamente.',
      );
    }
  }

  /// Volta ao estado inicial, mantendo o idioma escolhido.
  void clear() {
    _requestId++;
    state = TranslatorState(sourceLanguage: state.sourceLanguage);
  }
}
