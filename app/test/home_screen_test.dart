import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradutor/app.dart';
import 'package:tradutor/core/constants/app_constants.dart';
import 'package:tradutor/core/errors/translation_failure.dart';
import 'package:tradutor/models/translation_request.dart';
import 'package:tradutor/models/translation_result.dart';
import 'package:tradutor/providers/translation_providers.dart';
import 'package:tradutor/repositories/translation_repository.dart';

/// Repositório controlado pelo teste: cada chamada fica pendente até ser concluída.
class ControlledRepository implements TranslationRepository {
  final requests = <TranslationRequest>[];
  Completer<TranslationResult> _completer = Completer<TranslationResult>();

  @override
  Future<TranslationResult> translate(TranslationRequest request) {
    requests.add(request);
    _completer = Completer<TranslationResult>();
    return _completer.future;
  }

  void succeed(String translated, {String? detected}) => _completer.complete(
        TranslationResult(
          originalText: requests.last.text,
          translatedText: translated,
          sourceLanguage: requests.last.sourceLanguage == 'auto' ? 'en' : requests.last.sourceLanguage,
          targetLanguage: 'pt-BR',
          detectedLanguage: detected,
        ),
      );

  void fail([Object error = const ConnectionFailure()]) => _completer.completeError(error);
}

Future<void> pumpApp(WidgetTester tester, {TranslationRepository? repository}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [if (repository != null) translationRepositoryProvider.overrideWithValue(repository)],
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
    await pumpApp(tester, repository: ControlledRepository());

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
    await pumpApp(tester, repository: ControlledRepository());

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(isEnabled(tester, 'TRADUZIR'), isFalse);
  });

  testWidgets('fluxo carregando e traduzido', (tester) async {
    final fake = ControlledRepository();
    await pumpApp(tester, repository: fake);

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
    expect(fake.requests.single.text, 'Good morning');
    expect(fake.requests.single.sourceLanguage, 'auto');
    expect(fake.requests.single.targetLanguage, 'pt-BR');
  });

  testWidgets('estado de erro mostra a mensagem da falha', (tester) async {
    final fake = ControlledRepository();
    await pumpApp(tester, repository: fake);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.text('TRADUZIR'));
    await tester.pump();
    fake.fail();
    await tester.pumpAndSettle();

    expect(find.text(const ConnectionFailure().message), findsOneWidget);
    expect(isEnabled(tester, 'Copiar'), isFalse);
    expect(isEnabled(tester, 'TRADUZIR'), isTrue);
  });

  testWidgets('erro inesperado mostra mensagem genérica sem detalhes técnicos', (tester) async {
    final fake = ControlledRepository();
    await pumpApp(tester, repository: fake);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.text('TRADUZIR'));
    await tester.pump();
    fake.fail(StateError('detalhe interno'));
    await tester.pumpAndSettle();

    expect(find.text(const UnknownFailure().message), findsOneWidget);
    expect(find.textContaining('detalhe interno'), findsNothing);
  });

  testWidgets('seletor envia o idioma escolhido', (tester) async {
    final fake = ControlledRepository();
    await pumpApp(tester, repository: fake);

    await tester.tap(find.text('Detectar automaticamente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Espanhol').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hola');
    await tester.pump();
    await tester.tap(find.text('TRADUZIR'));
    await tester.pump();

    expect(fake.requests.single.sourceLanguage, 'es');
    fake.succeed('Olá');
    await tester.pumpAndSettle();
  });

  testWidgets('limpar apaga o texto e volta ao estado inicial', (tester) async {
    final fake = ControlledRepository();
    await pumpApp(tester, repository: fake);

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
    await pumpApp(tester, repository: ControlledRepository());

    await tester.tap(find.text('Colar'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'Texto colado');
    expect(isEnabled(tester, 'TRADUZIR'), isTrue);
  });

  testWidgets('colar respeita o limite de caracteres', (tester) async {
    mockClipboard(tester, initial: 'a' * (AppConstants.maxTextLength + 10));
    await pumpApp(tester, repository: ControlledRepository());

    await tester.tap(find.text('Colar'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text.length, AppConstants.maxTextLength);
    expect(find.textContaining('foi cortado'), findsOneWidget);
  });

  testWidgets('colar com área de transferência vazia avisa o usuário', (tester) async {
    mockClipboard(tester);
    await pumpApp(tester, repository: ControlledRepository());

    await tester.tap(find.text('Colar'));
    await tester.pumpAndSettle();

    expect(find.text('A área de transferência está vazia.'), findsOneWidget);
  });

  testWidgets('copiar envia a tradução para a área de transferência', (tester) async {
    final clipboard = mockClipboard(tester);
    final fake = ControlledRepository();
    await pumpApp(tester, repository: fake);

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

  testWidgets('fluxo completo até o backend (simulado) mostra o idioma detectado', (tester) async {
    late http.Request sent;
    final backend = MockClient((request) async {
      sent = request;
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'success': true,
          'detectedLanguage': 'es',
          'sourceLanguage': 'es',
          'targetLanguage': 'pt-BR',
          'originalText': 'Buenos días',
          'translatedText': 'Bom dia',
        })),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [httpClientProvider.overrideWithValue(backend)],
        child: const TradutorApp(),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Buenos días');
    await tester.pump();
    await tester.tap(find.text('TRADUZIR'));
    await tester.pumpAndSettle();

    expect(sent.url.path, '/api/v1/translate');
    expect(jsonDecode(sent.body), {'text': 'Buenos días', 'sourceLanguage': 'auto', 'targetLanguage': 'pt-BR'});
    expect(find.text('Bom dia'), findsOneWidget);
    expect(find.text('Idioma detectado: Espanhol'), findsOneWidget);
  });

  testWidgets('backend fora do ar mostra mensagem amigável', (tester) async {
    final backend = MockClient((_) async => throw http.ClientException('Connection refused'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [httpClientProvider.overrideWithValue(backend)],
        child: const TradutorApp(),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.text('TRADUZIR'));
    await tester.pumpAndSettle();

    expect(find.text(const ConnectionFailure().message), findsOneWidget);
    expect(find.textContaining('Connection refused'), findsNothing);
  });

  testWidgets('idioma informado manualmente não exibe "Idioma detectado"', (tester) async {
    final fake = ControlledRepository();
    await pumpApp(tester, repository: fake);

    await tester.tap(find.text('Detectar automaticamente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inglês').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.text('TRADUZIR'));
    await tester.pump();
    fake.succeed('Olá', detected: 'en');
    await tester.pumpAndSettle();

    expect(find.text('Olá'), findsOneWidget);
    expect(find.textContaining('Idioma detectado'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('tela pequena (320x568) sem overflow no tema ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final fake = ControlledRepository();
      await pumpApp(tester, repository: fake);
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
