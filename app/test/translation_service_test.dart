import 'package:flutter_test/flutter_test.dart';
import 'package:tradutor/core/constants/app_constants.dart';
import 'package:tradutor/core/errors/translation_failure.dart';
import 'package:tradutor/models/translation_request.dart';
import 'package:tradutor/models/translation_result.dart';
import 'package:tradutor/repositories/fake_translation_repository.dart';
import 'package:tradutor/repositories/translation_repository.dart';
import 'package:tradutor/services/translation_service.dart';

class StubRepository implements TranslationRepository {
  StubRepository(this.respond);

  final Future<TranslationResult> Function(TranslationRequest request) respond;
  final requests = <TranslationRequest>[];

  @override
  Future<TranslationResult> translate(TranslationRequest request) {
    requests.add(request);
    return respond(request);
  }
}

TranslationResult result({String source = 'en', String? detected}) => TranslationResult(
      originalText: 'Hello',
      translatedText: 'Olá',
      sourceLanguage: source,
      targetLanguage: 'pt-BR',
      detectedLanguage: detected,
    );

Matcher throwsFailure<T extends TranslationFailure>() => throwsA(isA<T>());

void main() {
  group('DefaultTranslationService', () {
    test('repassa a requisição com destino pt-BR por padrão', () async {
      final repo = StubRepository((_) async => result());
      final service = DefaultTranslationService(repo);

      final translated = await service.translate(text: 'Hello', sourceLanguage: 'en');

      expect(translated.translatedText, 'Olá');
      final request = repo.requests.single;
      expect(request.text, 'Hello');
      expect(request.sourceLanguage, 'en');
      expect(request.targetLanguage, 'pt-BR');
    });

    test('aceita auto, en e es', () async {
      final repo = StubRepository((_) async => result());
      final service = DefaultTranslationService(repo);

      for (final language in ['auto', 'en', 'es']) {
        await service.translate(text: 'Hello', sourceLanguage: language);
      }
      expect(repo.requests.map((r) => r.sourceLanguage), ['auto', 'en', 'es']);
    });

    test('texto vazio ou só com espaços não chama o repositório', () async {
      final repo = StubRepository((_) async => result());
      final service = DefaultTranslationService(repo);

      await expectLater(service.translate(text: '', sourceLanguage: 'en'), throwsFailure<EmptyTextFailure>());
      await expectLater(service.translate(text: '  \n ', sourceLanguage: 'en'), throwsFailure<EmptyTextFailure>());
      expect(repo.requests, isEmpty);
    });

    test('texto acima do limite é rejeitado', () async {
      final repo = StubRepository((_) async => result());
      final service = DefaultTranslationService(repo);

      await expectLater(
        service.translate(text: 'a' * (AppConstants.maxTextLength + 1), sourceLanguage: 'en'),
        throwsFailure<TextTooLongFailure>(),
      );
      expect(repo.requests, isEmpty);
    });

    test('idioma de origem ou destino fora do suportado é rejeitado', () async {
      final repo = StubRepository((_) async => result());
      final service = DefaultTranslationService(repo);

      await expectLater(
        service.translate(text: 'Bonjour', sourceLanguage: 'fr'),
        throwsFailure<UnsupportedLanguageFailure>(),
      );
      await expectLater(
        service.translate(text: 'Hello', sourceLanguage: 'en', targetLanguage: 'es'),
        throwsFailure<UnsupportedLanguageFailure>(),
      );
      expect(repo.requests, isEmpty);
    });

    test('resultado com idioma detectado fora de en/es é rejeitado', () async {
      final service = DefaultTranslationService(StubRepository((_) async => result(source: 'fr', detected: 'fr')));

      await expectLater(
        service.translate(text: 'Bonjour', sourceLanguage: 'auto'),
        throwsFailure<UnsupportedLanguageFailure>(),
      );
    });

    final propagated = <TranslationFailure>[
      const ConnectionFailure(),
      const TimeoutFailure(),
      const ServerUnavailableFailure(),
      const InvalidResponseFailure(),
      const UnsupportedLanguageFailure(),
    ];
    for (final failure in propagated) {
      test('propaga ${failure.runtimeType} do repositório', () async {
        final service = DefaultTranslationService(StubRepository((_) async => throw failure));

        await expectLater(service.translate(text: 'Hello', sourceLanguage: 'en'), throwsA(same(failure)));
      });
    }

    test('erro inesperado do repositório vira UnknownFailure', () async {
      final service = DefaultTranslationService(StubRepository((_) async => throw StateError('detalhe interno')));

      await expectLater(service.translate(text: 'Hello', sourceLanguage: 'en'), throwsFailure<UnknownFailure>());
    });
  });

  group('TranslationResult.fromJson', () {
    test('converte resposta válida', () {
      final parsed = TranslationResult.fromJson({
        'success': true,
        'detectedLanguage': 'en',
        'sourceLanguage': 'en',
        'targetLanguage': 'pt-BR',
        'originalText': 'Good morning',
        'translatedText': 'Bom dia',
      });

      expect(parsed.translatedText, 'Bom dia');
      expect(parsed.detectedLanguage, 'en');
      expect(parsed.sourceLanguage, 'en');
    });

    test('aceita detectedLanguage ausente', () {
      final parsed = TranslationResult.fromJson({
        'sourceLanguage': 'es',
        'targetLanguage': 'pt-BR',
        'originalText': 'Hola',
        'translatedText': 'Olá',
      });
      expect(parsed.detectedLanguage, isNull);
    });

    final invalid = <String, Object?>{
      'não é objeto': ['Bom dia'],
      'nulo': null,
      'sem translatedText': {'sourceLanguage': 'en', 'targetLanguage': 'pt-BR', 'originalText': 'x'},
      'translatedText vazio': {
        'translatedText': '',
        'sourceLanguage': 'en',
        'targetLanguage': 'pt-BR',
        'originalText': 'x',
      },
      'tipo errado': {'translatedText': 1, 'sourceLanguage': 'en', 'targetLanguage': 'pt-BR', 'originalText': 'x'},
      'detectedLanguage com tipo errado': {
        'translatedText': 'Olá',
        'sourceLanguage': 'en',
        'targetLanguage': 'pt-BR',
        'originalText': 'x',
        'detectedLanguage': 7,
      },
    };
    invalid.forEach((name, json) {
      test('rejeita resposta inválida: $name', () {
        expect(() => TranslationResult.fromJson(json), throwsFailure<InvalidResponseFailure>());
      });
    });
  });

  test('TranslationRequest.toJson segue o contrato do backend', () {
    expect(
      const TranslationRequest(text: 'Good morning', sourceLanguage: 'en').toJson(),
      {'text': 'Good morning', 'sourceLanguage': 'en', 'targetLanguage': 'pt-BR'},
    );
  });

  test('FakeTranslationRepository simula sem rede e informa detecção no modo auto', () async {
    const repo = FakeTranslationRepository(delay: Duration.zero);

    final auto = await repo.translate(const TranslationRequest(text: 'Hello', sourceLanguage: 'auto'));
    expect(auto.translatedText, '[Tradução simulada] Hello');
    expect(auto.sourceLanguage, 'en');
    expect(auto.detectedLanguage, 'en');

    final es = await repo.translate(const TranslationRequest(text: 'Hola', sourceLanguage: 'es'));
    expect(es.sourceLanguage, 'es');
    expect(es.detectedLanguage, isNull);
  });
}
