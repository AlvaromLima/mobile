import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradutor/app.dart';
import 'package:tradutor/core/errors/translation_failure.dart';
import 'package:tradutor/core/errors/voice_failure.dart';
import 'package:tradutor/models/source_language.dart';
import 'package:tradutor/models/translation_request.dart';
import 'package:tradutor/models/translation_result.dart';
import 'package:tradutor/providers/translation_providers.dart';
import 'package:tradutor/providers/voice_input_provider.dart';
import 'package:tradutor/repositories/translation_repository.dart';
import 'package:tradutor/services/speech_recognition_service.dart';

import 'support/fake_speech_service.dart';

/// Traduções conhecidas pelo backend simulado: texto original -> (idioma detectado, tradução).
const _knownTranslations = {
  'Good morning, how are you?': ('en', 'Bom dia, como você está?'),
  'Buenos días, ¿cómo estás?': ('es', 'Bom dia, como você está?'),
  'Hello': ('en', 'Olá'),
};

/// Backend simulado no nível HTTP: exercita ApiClient, BackendTranslationRepository e TranslationService reais.
class FakeBackend {
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final text = body['text'] as String;
    final known = _knownTranslations[text];
    if (known == null) {
      return _json(422, {
        'success': false,
        'error': {'code': 'UNSUPPORTED_LANGUAGE', 'message': 'x', 'requestId': 'x'},
      });
    }
    final requested = body['sourceLanguage'] as String;
    final effective = requested == 'auto' ? known.$1 : requested;
    return _json(200, {
      'success': true,
      'detectedLanguage': effective,
      'sourceLanguage': effective,
      'targetLanguage': 'pt-BR',
      'originalText': text,
      'translatedText': known.$2,
    });
  });

  Map<String, dynamic> lastBody() => jsonDecode(requests.last.body) as Map<String, dynamic>;

  static http.Response _json(int status, Object body) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}

/// Repositório que só registra as chamadas, para provar que a voz usa o mesmo repositório da digitação.
class RecordingRepository implements TranslationRepository {
  final requests = <TranslationRequest>[];

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    requests.add(request);
    return TranslationResult(
      originalText: request.text,
      translatedText: 'Olá',
      sourceLanguage: 'en',
      targetLanguage: 'pt-BR',
    );
  }
}

Future<ControlledSpeechService> pumpApp(
  WidgetTester tester, {
  ControlledSpeechService? speech,
  FakeBackend? backend,
  TranslationRepository? repository,
}) async {
  final service = speech ?? ControlledSpeechService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        speechRecognitionServiceProvider.overrideWithValue(service),
        httpClientProvider.overrideWithValue((backend ?? FakeBackend()).client),
        if (repository != null) translationRepositoryProvider.overrideWithValue(repository),
      ],
      child: const TradutorApp(),
    ),
  );
  return service;
}

/// Toca no microfone, escolhe o idioma na folha (modo automático) e fala o texto.
Future<void> speakWithSheet(WidgetTester tester, ControlledSpeechService speech, String sheetLanguage, String text) async {
  await tester.tap(find.byTooltip('Falar'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(sheetLanguage));
  await tester.pumpAndSettle();
  speech.emitPartial(text.split(' ').first);
  await tester.pump();
  await speech.emitFinal(text);
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;

Future<void> selectLanguage(WidgetTester tester, String label) async {
  await tester.tap(find.text('Detectar automaticamente'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('modo automático pergunta o idioma da fala e ouve em espanhol', (tester) async {
    final speech = await pumpApp(tester);

    await tester.tap(find.byTooltip('Falar'));
    await tester.pumpAndSettle();
    expect(find.text('Em qual idioma você vai falar?'), findsOneWidget);

    await tester.tap(find.text('Espanhol'));
    await tester.pumpAndSettle();

    expect(speech.language, SourceLanguage.es);
    expect(find.text('Ouvindo...'), findsOneWidget);
    expect(find.byTooltip('Parar'), findsOneWidget);
  });

  testWidgets('fechar a pergunta de idioma não inicia a escuta', (tester) async {
    final speech = await pumpApp(tester);

    await tester.tap(find.byTooltip('Falar'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // toque fora da folha
    await tester.pumpAndSettle();

    expect(speech.language, isNull);
    expect(find.text('Ouvindo...'), findsNothing);
  });

  testWidgets('idioma escolhido no seletor é usado direto, sem perguntar', (tester) async {
    final speech = await pumpApp(tester);
    await selectLanguage(tester, 'Inglês');

    await tester.tap(find.byTooltip('Falar'));
    await tester.pumpAndSettle();

    expect(find.text('Em qual idioma você vai falar?'), findsNothing);
    expect(speech.language, SourceLanguage.en);
  });

  testWidgets('texto reconhecido aparece no campo durante e ao fim da fala', (tester) async {
    final speech = await pumpApp(tester);
    await selectLanguage(tester, 'Inglês');
    await tester.tap(find.byTooltip('Falar'));
    await tester.pumpAndSettle();

    speech.emitPartial('Good');
    await tester.pump();
    expect(fieldText(tester), 'Good');

    await speech.emitFinal('Good morning, how are you?');
    await tester.pumpAndSettle();

    expect(fieldText(tester), 'Good morning, how are you?');
    expect(find.text('Ouvindo...'), findsNothing);
    expect(find.byTooltip('Falar'), findsOneWidget);
  });

  testWidgets('durante a escuta, campo e TRADUZIR ficam bloqueados', (tester) async {
    await pumpApp(tester);
    await selectLanguage(tester, 'Inglês');
    await tester.tap(find.byTooltip('Falar'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    final translate = tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text('TRADUZIR'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
    );
    expect(translate.onPressed, isNull);
  });

  testWidgets('parar mostra "Processando..." e pede o resultado final', (tester) async {
    final speech = await pumpApp(tester);
    await selectLanguage(tester, 'Inglês');
    await tester.tap(find.byTooltip('Falar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Parar'));
    await tester.pump();

    expect(speech.stops, 1);
    expect(find.text('Processando...'), findsOneWidget);

    await speech.emitFinal('Hello');
    await tester.pumpAndSettle();
    expect(fieldText(tester), 'Hello');
  });

  testWidgets('permissão bloqueada mostra aviso com atalho para as configurações', (tester) async {
    final speech = ControlledSpeechService()..status = VoicePermission.permanentlyDenied;
    await pumpApp(tester, speech: speech);
    await selectLanguage(tester, 'Inglês');

    await tester.tap(find.byTooltip('Falar'));
    await tester.pumpAndSettle();

    expect(find.text(const MicrophonePermissionPermanentlyDeniedFailure().message), findsOneWidget);
    await tester.tap(find.text('Abrir configurações'));
    await tester.pumpAndSettle();
    expect(speech.settingsOpened, 1);
  });

  testWidgets('permissão recusada mostra aviso e o app continua funcionando', (tester) async {
    final speech = ControlledSpeechService()
      ..status = VoicePermission.denied
      ..afterRequest = VoicePermission.denied;
    await pumpApp(tester, speech: speech);
    await selectLanguage(tester, 'Espanhol');

    await tester.tap(find.byTooltip('Falar'));
    await tester.pumpAndSettle();

    expect(find.text(const MicrophonePermissionDeniedFailure().message), findsOneWidget);
    expect(find.text('Abrir configurações'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fala não reconhecida mostra aviso sem fechar o app', (tester) async {
    final speech = await pumpApp(tester);
    await selectLanguage(tester, 'Inglês');
    await tester.tap(find.byTooltip('Falar'));
    await tester.pumpAndSettle();

    await speech.emitError(const SpeechNotRecognizedFailure());
    await tester.pumpAndSettle();

    expect(find.text(const SpeechNotRecognizedFailure().message), findsOneWidget);
    expect(find.byTooltip('Falar'), findsOneWidget, reason: 'pode tentar de novo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('app em segundo plano interrompe a escuta e avisa', (tester) async {
    final speech = await pumpApp(tester);
    await selectLanguage(tester, 'Inglês');
    await tester.tap(find.byTooltip('Falar'));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(speech.cancels, 1);
    expect(find.text(const SpeechInterruptedFailure().message), findsOneWidget);
  });

  group('etapa 11: voz traduzida automaticamente pelo fluxo existente', () {
    testWidgets('inglês no modo automático: detecta Inglês e mostra a tradução', (tester) async {
      final backend = FakeBackend();
      final speech = await pumpApp(tester, backend: backend);

      await speakWithSheet(tester, speech, 'Inglês', 'Good morning, how are you?');

      expect(speech.language, SourceLanguage.en, reason: 'reconhecimento ouviu em inglês');
      expect(backend.requests, hasLength(1));
      expect(backend.requests.single.url.path, '/api/v1/translate', reason: 'mesmo endpoint da digitação');
      expect(backend.lastBody(), {
        'text': 'Good morning, how are you?',
        'sourceLanguage': 'auto',
        'targetLanguage': 'pt-BR',
      });
      expect(find.text('Idioma detectado: Inglês'), findsOneWidget);
      expect(find.text('Bom dia, como você está?'), findsOneWidget);
      expect(fieldText(tester), 'Good morning, how are you?');
    });

    testWidgets('espanhol no modo automático: detecta Espanhol e mostra a tradução', (tester) async {
      final backend = FakeBackend();
      final speech = await pumpApp(tester, backend: backend);

      await speakWithSheet(tester, speech, 'Espanhol', 'Buenos días, ¿cómo estás?');

      expect(speech.language, SourceLanguage.es);
      expect(backend.lastBody()['sourceLanguage'], 'auto');
      expect(find.text('Idioma detectado: Espanhol'), findsOneWidget);
      expect(find.text('Bom dia, como você está?'), findsOneWidget);
    });

    testWidgets('idioma escolhido no seletor é enviado como está', (tester) async {
      final backend = FakeBackend();
      final speech = await pumpApp(tester, backend: backend);
      await selectLanguage(tester, 'Inglês');

      await tester.tap(find.byTooltip('Falar'));
      await tester.pumpAndSettle();
      await speech.emitFinal('Hello');
      await tester.pumpAndSettle();

      expect(backend.lastBody()['sourceLanguage'], 'en');
      expect(find.text('Olá'), findsOneWidget);
      expect(find.textContaining('Idioma detectado'), findsNothing);
    });

    testWidgets('voz usa o mesmo TranslationRepository da tradução digitada', (tester) async {
      final repository = RecordingRepository();
      final speech = await pumpApp(tester, repository: repository);

      await speakWithSheet(tester, speech, 'Inglês', 'Good morning, how are you?');
      expect(repository.requests.single.text, 'Good morning, how are you?');

      // A tradução digitada passa pelo mesmo repositório.
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      await tester.tap(find.text('TRADUZIR'));
      await tester.pumpAndSettle();
      expect(repository.requests.map((r) => r.text), ['Good morning, how are you?', 'Hello']);
    });

    testWidgets('sem fala reconhecida, nada é enviado ao backend', (tester) async {
      final backend = FakeBackend();
      final speech = await pumpApp(tester, backend: backend);
      await selectLanguage(tester, 'Inglês');

      await tester.tap(find.byTooltip('Falar'));
      await tester.pumpAndSettle();
      await speech.emitError(const NoSpeechDetectedFailure());
      await tester.pumpAndSettle();

      expect(backend.requests, isEmpty);
      expect(find.text(const NoSpeechDetectedFailure().message), findsOneWidget);
    });

    testWidgets('fala em idioma não suportado mostra o aviso do backend', (tester) async {
      final backend = FakeBackend();
      final speech = await pumpApp(tester, backend: backend);

      await speakWithSheet(tester, speech, 'Inglês', 'Bonjour tout le monde');

      expect(backend.requests, hasLength(1));
      expect(find.text(const UnsupportedLanguageFailure().message), findsOneWidget);
    });
  });
}
