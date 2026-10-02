import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradutor/app.dart';
import 'package:tradutor/core/constants/app_constants.dart';
import 'package:tradutor/models/source_language.dart';
import 'package:tradutor/services/simulated_translation.dart';

/// Tradução controlada pelo teste: cada chamada fica pendente até ser concluída.
class FakeTranslator {
  final calls = <(String, SourceLanguage)>[];
  Completer<String> _completer = Completer<String>();

  Future<String> call(String text, SourceLanguage source) {
    calls.add((text, source));
    _completer = Completer<String>();
    return _completer.future;
  }

  void succeed(String value) => _completer.complete(value);
  void fail() => _completer.completeError(Exception('falha simulada'));
}

Future<void> pumpApp(WidgetTester tester, {TranslateFn? translate}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [if (translate != null) translateFnProvider.overrideWithValue(translate)],
      child: const TradutorApp(),
    ),
  );
}

ButtonStyleButton button(WidgetTester tester, String label) => tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
    );

bool isEnabled(WidgetTester tester, String label) => button(tester, label).onPressed != null;

/// Simula a área de transferência do sistema.
String? Function() mockClipboard(WidgetTester tester, {String? initial}) {
  String? content = initial;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    switch (call.method) {
      case 'Clipboard.getData':
        return content == null ? null : {'text': content};
      case 'Clipboard.setData':
        content = (call.arguments as Map)['text'] as String?;
        return null;
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return () => content;
}

void main() {
  testWidgets('estado inicial: placeholder e ações desabilitadas', (tester) async {
    await pumpApp(tester, translate: FakeTranslator().call);

    expect(find.text('Tradutor'), findsOneWidget);
    expect(find.text('TEXTO ORIGINAL'), findsOneWidget);
    expect(find.text('PORTUGUÊS DO BRASIL'), findsOneWidget);
    expect(find.text('Detectar automaticamente'), findsOneWidget);
    expect(find.text('A tradução aparecerá aqui.'), findsOneWidget);
    expect(isEnabled(tester, 'TRADUZIR'), isFalse);
    expect(isEnabled(tester, 'Copiar'), isFalse);
    expect(isEnabled(tester, 'Compartilhar'), isFalse);
    expect(isEnabled(tester, 'Ouvir'), isFalse);
  });

  testWidgets('texto só com espaços não habilita TRADUZIR', (tester) async {
    await pumpApp(tester, translate: FakeTranslator().call);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(isEnabled(tester, 'TRADUZIR'), isFalse);
  });

  testWidgets('fluxo carregando e traduzido', (tester) async {
    final fake = FakeTranslator();
    await pumpApp(tester, translate: fake.call);

    await tester.enterText(find.byType(TextField), 'Good morning');
    await tester.pump();
    await tester.tap(find.text('TRADUZIR'));
    await tester.pump();

    expect(find.text('TRADUZINDO...'), findsOneWidget);
    expect(find.bySemanticsLabel('Traduzindo'), findsOneWidget);
    expect(isEnabled(tester, 'TRADUZINDO...'), isFalse);

    fake.succeed('Bom dia');
    await tester.pumpAndSettle();

    expect(find.text('Bom dia'), findsOneWidget);
    expect(find.text('TRADUZIR'), findsOneWidget);
    expect(isEnabled(tester, 'Copiar'), isTrue);
    expect(isEnabled(tester, 'Compartilhar'), isTrue);
    expect(fake.calls.single, ('Good morning', SourceLanguage.auto));
  });

  testWidgets('estado de erro mostra mensagem', (tester) async {
    final fake = FakeTranslator();
    await pumpApp(tester, translate: fake.call);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.text('TRADUZIR'));
    await tester.pump();
    fake.fail();
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível traduzir. Tente novamente.'), findsOneWidget);
    expect(isEnabled(tester, 'Copiar'), isFalse);
    expect(isEnabled(tester, 'TRADUZIR'), isTrue);
  });

  testWidgets('seletor envia o idioma escolhido', (tester) async {
    final fake = FakeTranslator();
    await pumpApp(tester, translate: fake.call);

    await tester.tap(find.text('Detectar automaticamente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Espanhol').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hola');
    await tester.pump();
    await tester.tap(find.text('TRADUZIR'));
    await tester.pump();

    expect(fake.calls.single.$2, SourceLanguage.es);
    fake.succeed('Olá');
    await tester.pumpAndSettle();
  });

  testWidgets('limpar apaga o texto e volta ao estado inicial', (tester) async {
    final fake = FakeTranslator();
    await pumpApp(tester, translate: fake.call);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.text('TRADUZIR'));
    await tester.pump();
    fake.succeed('Olá');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Limpar'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, isEmpty);
    expect(find.text('A tradução aparecerá aqui.'), findsOneWidget);
    expect(isEnabled(tester, 'Limpar'), isFalse);
  });

  testWidgets('colar insere o texto da área de transferência', (tester) async {
    mockClipboard(tester, initial: 'Texto colado');
    await pumpApp(tester, translate: FakeTranslator().call);

    await tester.tap(find.text('Colar'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'Texto colado');
    expect(isEnabled(tester, 'TRADUZIR'), isTrue);
  });

  testWidgets('colar respeita o limite de caracteres', (tester) async {
    mockClipboard(tester, initial: 'a' * (AppConstants.maxTextLength + 10));
    await pumpApp(tester, translate: FakeTranslator().call);

    await tester.tap(find.text('Colar'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text.length, AppConstants.maxTextLength);
    expect(find.textContaining('foi cortado'), findsOneWidget);
  });

  testWidgets('colar com área de transferência vazia avisa o usuário', (tester) async {
    mockClipboard(tester);
    await pumpApp(tester, translate: FakeTranslator().call);

    await tester.tap(find.text('Colar'));
    await tester.pumpAndSettle();

    expect(find.text('A área de transferência está vazia.'), findsOneWidget);
  });

  testWidgets('copiar envia a tradução para a área de transferência', (tester) async {
    final clipboard = mockClipboard(tester);
    final fake = FakeTranslator();
    await pumpApp(tester, translate: fake.call);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.text('TRADUZIR'));
    await tester.pump();
    fake.succeed('Olá');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Copiar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copiar'));
    await tester.pumpAndSettle();
    expect(clipboard(), 'Olá');
    expect(find.text('Tradução copiada.'), findsOneWidget);
  });

  testWidgets('tradução simulada padrão responde após o carregamento', (tester) async {
    await pumpApp(tester);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.text('TRADUZIR'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('[Tradução simulada] Hello'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('tela pequena (320x568) sem overflow no tema ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final fake = FakeTranslator();
      await pumpApp(tester, translate: fake.call);
      await tester.enterText(find.byType(TextField), 'Good morning, how are you? ' * 20);
      await tester.pump();
      await tester.tap(find.text('TRADUZIR'));
      await tester.pump();
      fake.succeed('Bom dia, como você está? ' * 20);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
