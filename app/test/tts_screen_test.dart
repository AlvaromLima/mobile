import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradutor/app.dart';
import 'package:tradutor/core/errors/voice_failure.dart';
import 'package:tradutor/models/translation_request.dart';
import 'package:tradutor/models/translation_result.dart';
import 'package:tradutor/providers/text_to_speech_provider.dart';
import 'package:tradutor/providers/translation_providers.dart';
import 'package:tradutor/providers/voice_input_provider.dart';
import 'package:tradutor/repositories/translation_repository.dart';

import 'support/fake_speech_service.dart';
import 'support/fake_tts_service.dart';

class InstantRepository implements TranslationRepository {
  @override
  Future<TranslationResult> translate(TranslationRequest request) async => TranslationResult(
        originalText: request.text,
        translatedText: 'Tradução de ${request.text}',
        sourceLanguage: 'en',
        targetLanguage: 'pt-BR',
      );
}

Future<ControlledTtsService> pumpApp(WidgetTester tester, {ControlledTtsService? tts, ControlledSpeechService? speech}) async {
  final service = tts ?? ControlledTtsService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        textToSpeechServiceProvider.overrideWithValue(service),
        translationRepositoryProvider.overrideWithValue(InstantRepository()),
        speechRecognitionServiceProvider.overrideWithValue(speech ?? ControlledSpeechService()),
      ],
      child: const TradutorApp(),
    ),
  );
  return service;
}

Future<void> translate(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.text('TRADUZIR'));
  await tester.pumpAndSettle();
}

ButtonStyleButton button(WidgetTester tester, String label) => tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
    );

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets('Ouvir fica desabilitado sem tradução', (tester) async {
    await pumpApp(tester);
    expect(button(tester, 'Ouvir').onPressed, isNull);
  });

  testWidgets('Ouvir lê a tradução e vira Parar; Parar interrompe', (tester) async {
    final tts = await pumpApp(tester);
    await translate(tester, 'Hello');

    await tapVisible(tester, find.text('Ouvir'));
    expect(tts.spoken, ['Tradução de Hello']);
    expect(find.text('Parar'), findsOneWidget);

    await tapVisible(tester, find.text('Parar'));
    await tester.pumpAndSettle();
    expect(tts.stops, greaterThanOrEqualTo(1));
    expect(find.text('Ouvir'), findsOneWidget);
  });

  testWidgets('ao terminar a leitura, o botão volta para Ouvir', (tester) async {
    final tts = await pumpApp(tester);
    await translate(tester, 'Hello');

    await tapVisible(tester, find.text('Ouvir'));
    tts.finish();
    await tester.pumpAndSettle();

    expect(find.text('Ouvir'), findsOneWidget);
    expect(find.text('Parar'), findsNothing);
  });

  testWidgets('voz pt-BR ausente mostra orientação sem travar', (tester) async {
    final tts = ControlledTtsService()..speakThrows = const TextToSpeechLanguageUnavailableFailure();
    await pumpApp(tester, tts: tts);
    await translate(tester, 'Hello');

    await tapVisible(tester, find.text('Ouvir'));
    await tester.pumpAndSettle();

    expect(find.text(const TextToSpeechLanguageUnavailableFailure().message), findsOneWidget);
    expect(find.text('Ouvir'), findsOneWidget, reason: 'pode tentar de novo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('erro inesperado na leitura vira mensagem de reprodução', (tester) async {
    final tts = ControlledTtsService()..speakThrows = StateError('motor quebrou');
    await pumpApp(tester, tts: tts);
    await translate(tester, 'Hello');

    await tapVisible(tester, find.text('Ouvir'));
    await tester.pumpAndSettle();

    expect(find.text(const TextToSpeechPlaybackFailure().message), findsOneWidget);
  });

  testWidgets('nova tradução interrompe a leitura em andamento', (tester) async {
    final tts = await pumpApp(tester);
    await translate(tester, 'Hello');
    await tapVisible(tester, find.text('Ouvir'));
    final stopsBefore = tts.stops;

    await translate(tester, 'Bye');

    expect(tts.stops, greaterThan(stopsBefore));
    expect(find.text('Ouvir'), findsOneWidget);
  });

  testWidgets('tocar no microfone interrompe a leitura', (tester) async {
    final speech = ControlledSpeechService();
    final tts = await pumpApp(tester, speech: speech);
    await tester.tap(find.text('Detectar automaticamente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inglês').last);
    await tester.pumpAndSettle();
    await translate(tester, 'Hello');
    await tapVisible(tester, find.text('Ouvir'));
    final stopsBefore = tts.stops;

    await tester.ensureVisible(find.byTooltip('Falar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Falar'));
    await tester.pumpAndSettle();

    expect(tts.stops, greaterThan(stopsBefore));
    expect(speech.isListening, isTrue);
  });

  testWidgets('app em segundo plano interrompe a leitura', (tester) async {
    final tts = await pumpApp(tester);
    await translate(tester, 'Hello');
    await tapVisible(tester, find.text('Ouvir'));
    final stopsBefore = tts.stops;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(tts.stops, greaterThan(stopsBefore));
    expect(find.text('Ouvir'), findsOneWidget);
  });
}
