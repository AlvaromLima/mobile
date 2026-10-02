import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradutor/app.dart';
import 'package:tradutor/models/translation_request.dart';
import 'package:tradutor/models/translation_result.dart';
import 'package:tradutor/providers/text_to_speech_provider.dart';
import 'package:tradutor/providers/translation_providers.dart';
import 'package:tradutor/providers/voice_input_provider.dart';
import 'package:tradutor/repositories/translation_repository.dart';
import 'package:tradutor/widgets/translation_result_card.dart';
import 'package:tradutor/widgets/voice_button.dart';

import 'support/fake_speech_service.dart';
import 'support/fake_tts_service.dart';

/// Repositório cuja resposta o teste libera, para observar o estado "Traduzindo...".
class PendingRepository implements TranslationRepository {
  Completer<TranslationResult>? _pending;

  @override
  Future<TranslationResult> translate(TranslationRequest request) {
    _pending = Completer<TranslationResult>();
    return _pending!.future;
  }

  void succeed(String text) => _pending!.complete(TranslationResult(
        originalText: 'Good morning, how are you?',
        translatedText: text,
        sourceLanguage: 'en',
        targetLanguage: 'pt-BR',
        detectedLanguage: 'en',
      ));
}

Future<(ControlledSpeechService, PendingRepository)> pumpApp(WidgetTester tester, {bool reduceMotion = true}) async {
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  final speech = ControlledSpeechService();
  final repository = PendingRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        speechRecognitionServiceProvider.overrideWithValue(speech),
        translationRepositoryProvider.overrideWithValue(repository),
        textToSpeechServiceProvider.overrideWithValue(ControlledTtsService()),
      ],
      child: const TradutorApp(),
    ),
  );
  return (speech, repository);
}

Future<void> startListeningInEnglish(WidgetTester tester, {bool settle = true}) async {
  await tester.ensureVisible(find.byTooltip('Falar'));
  await tester.pump();
  await tester.tap(find.byTooltip('Falar'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Inglês'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Com o pulso ativo a tela nunca "assenta"; avança alguns quadros.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
}

ButtonStyleButton button(WidgetTester tester, String label) => tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
    );

void main() {
  group('rótulos do botão principal de microfone', () {
    testWidgets('normal, ouvindo, processando, traduzindo e resultado', (tester) async {
      final (speech, repository) = await pumpApp(tester);
      expect(find.text('Toque para falar'), findsOneWidget);

      await startListeningInEnglish(tester);
      expect(find.text('Ouvindo...'), findsOneWidget);

      speech.emitPartial('Good morning');
      await tester.pump();
      await tester.tap(find.byTooltip('Parar'));
      await tester.pump();
      expect(find.text('Processando...'), findsOneWidget);

      await speech.emitFinal('Good morning, how are you?');
      await tester.pump();
      await tester.pump();
      expect(find.text('Traduzindo...'), findsOneWidget);

      repository.succeed('Bom dia, como você está?');
      await tester.pumpAndSettle();
      expect(find.text('Toque para falar'), findsOneWidget);
      expect(find.text('Bom dia, como você está?'), findsOneWidget);
    });

    test('mapeamento de rótulos', () {
      String label(VoiceStatus status, {bool translating = false}) =>
          VoiceButton.labelFor(status, isTranslating: translating);
      expect(label(VoiceStatus.idle), 'Toque para falar');
      expect(label(VoiceStatus.completed), 'Toque para falar');
      expect(label(VoiceStatus.failure), 'Toque para falar');
      expect(label(VoiceStatus.requestingPermission), 'Solicitando permissão...');
      expect(label(VoiceStatus.listening), 'Ouvindo...');
      expect(label(VoiceStatus.processing), 'Processando...');
      expect(label(VoiceStatus.completed, translating: true), 'Traduzindo...');
    });
  });

  group('animação do microfone ativo', () {
    testWidgets('pulsa somente durante a escuta', (tester) async {
      final (speech, _) = await pumpApp(tester, reduceMotion: false);
      expect(find.byKey(const ValueKey('voice-pulse')), findsNothing);

      await startListeningInEnglish(tester, settle: false);
      final pulse = find.byKey(const ValueKey('voice-pulse'));
      expect(pulse, findsOneWidget);
      final first = tester.getSize(pulse);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(pulse), isNot(first), reason: 'o anel muda de tamanho enquanto ouve');

      await speech.emitError(Exception('fim'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('voice-pulse')), findsNothing);
    });

    testWidgets('com "reduzir movimento" ativo, o anel fica parado', (tester) async {
      await pumpApp(tester);
      await startListeningInEnglish(tester);

      final pulse = find.byKey(const ValueKey('voice-pulse'));
      final first = tester.getSize(pulse);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(pulse), first);
    });
  });

  testWidgets('resultado mostra idioma detectado, texto reconhecido, tradução e as ações', (tester) async {
    final (speech, repository) = await pumpApp(tester);
    await startListeningInEnglish(tester);
    // Modo automático: o texto vai como "auto" e o backend confirma o idioma.
    await speech.emitFinal('Good morning, how are you?');
    // Tradução pendente: indicadores de carregamento giram, então avança quadro a quadro.
    await tester.pump();
    await tester.pump();
    repository.succeed('Bom dia, como você está?');
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Good morning, how are you?');
    expect(find.text('Idioma detectado: Inglês'), findsOneWidget);
    expect(find.text('Bom dia, como você está?'), findsOneWidget);
    for (final action in ['Ouvir', 'Copiar', 'Compartilhar']) {
      expect(button(tester, action).onPressed, isNotNull, reason: '$action habilitado');
    }
  });

  testWidgets('tradução fica visível na tela ao chegar, mesmo em celular pequeno', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (speech, repository) = await pumpApp(tester);
    await startListeningInEnglish(tester);
    await speech.emitFinal('Good morning, how are you?');
    // Tradução pendente: indicadores de carregamento giram, então avança quadro a quadro.
    await tester.pump();
    await tester.pump();
    repository.succeed('Bom dia, como você está?');
    await tester.pumpAndSettle();

    final screen = tester.getRect(find.byType(Scaffold));
    final copy = tester.getRect(find.text('Copiar'));
    expect(screen.contains(copy.center), isTrue, reason: 'ações da tradução visíveis sem rolar manualmente');
  });

  const sizes = {
    'celular pequeno 320x568': Size(320, 568),
    'celular 375x667': Size(375, 667),
    'celular grande 430x932': Size(430, 932),
    'tablet 768x1024': Size(768, 1024),
    'celular deitado 812x375': Size(812, 375),
  };
  sizes.forEach((name, size) {
    for (final brightness in Brightness.values) {
      testWidgets('$name, tema ${brightness.name}: ouvindo e resultado sem overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        final (speech, repository) = await pumpApp(tester);
        await startListeningInEnglish(tester);
        expect(find.text('Ouvindo...'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await speech.emitFinal('Good morning, how are you? ' * 8);
        await tester.pump();
        await tester.pump();
        repository.succeed('Bom dia, como você está? ' * 8);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // Conteúdo limitado a 640 px de largura em telas largas.
        final resultCard = find.descendant(of: find.byType(TranslationResultCard), matching: find.byType(Card));
        expect(tester.getSize(resultCard).width, lessThanOrEqualTo(640));
      });
    }
  });

  testWidgets('celular deitado (812x375): microfone visível sem rolar', (tester) async {
    tester.view.physicalSize = const Size(812, 375);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    final screen = tester.getRect(find.byType(Scaffold));
    expect(screen.contains(tester.getCenter(find.byTooltip('Falar'))), isTrue);
  });

  testWidgets('telas baixas usam o microfone compacto', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    expect(tester.widget<VoiceButton>(find.byType(VoiceButton)).diameter, 60);

    tester.view.physicalSize = const Size(430, 932);
    await tester.pumpAndSettle();
    expect(tester.widget<VoiceButton>(find.byType(VoiceButton)).diameter, 72);
  });
}
