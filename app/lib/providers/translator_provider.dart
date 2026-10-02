import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/translation_failure.dart';
import '../models/source_language.dart';
import '../models/translation_result.dart';
import 'translation_providers.dart';

enum TranslationStatus { initial, loading, success, failure }

class TranslatorState {
  const TranslatorState({
    this.sourceLanguage = SourceLanguage.auto,
    this.status = TranslationStatus.initial,
    this.result,
    this.errorMessage,
  });

  final SourceLanguage sourceLanguage;
  final TranslationStatus status;
  final TranslationResult? result;
  final String? errorMessage;

  bool get isLoading => status == TranslationStatus.loading;
  String? get translatedText => result?.translatedText;
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
      result: state.result,
      errorMessage: state.errorMessage,
    );
  }

  Future<void> translate(String text) async {
    if (state.isLoading) return;

    final requestId = ++_requestId;
    final language = state.sourceLanguage;
    state = TranslatorState(sourceLanguage: language, status: TranslationStatus.loading);

    try {
      final result = await ref.read(translationServiceProvider).translate(
            text: text,
            sourceLanguage: language.code,
          );
      if (requestId != _requestId) return;
      state = TranslatorState(sourceLanguage: state.sourceLanguage, status: TranslationStatus.success, result: result);
    } on TranslationFailure catch (failure) {
      if (requestId != _requestId) return;
      _fail(failure.message);
    } catch (_) {
      if (requestId != _requestId) return;
      _fail(const UnknownFailure().message);
    }
  }

  void _fail(String message) {
    state = TranslatorState(
      sourceLanguage: state.sourceLanguage,
      status: TranslationStatus.failure,
      errorMessage: message,
    );
  }

  /// Volta ao estado inicial, mantendo o idioma escolhido.
  void clear() {
    _requestId++;
    state = TranslatorState(sourceLanguage: state.sourceLanguage);
  }
}
