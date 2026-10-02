import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradutor/app.dart';
import 'package:tradutor/core/errors/voice_failure.dart';
import 'package:tradutor/models/source_language.dart';
import 'package:tradutor/providers/voice_input_provider.dart';
import 'package:tradutor/services/speech_recognition_service.dart';

import 'support/fake_speech_service.dart';

Future<ControlledSpeechService> pumpApp(WidgetTester tester, {ControlledSpeechService? speech}) async {
  final service = speech ?? ControlledSpeechService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [speechRecognitionServiceProvider.overrideWithValue(service)],
      child: const TradutorApp(),
    ),
  );
  return service;
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
    final translate = tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text('TRADUZIR'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
    );
    expect(translate.onPressed, isNotNull, reason: 'texto reconhecido pode ser traduzido');
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
}
