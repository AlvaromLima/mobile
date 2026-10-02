import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradutor/app.dart';
import 'package:tradutor/providers/theme_mode_provider.dart';

void main() {
  testWidgets('exibe a tela principal com o título', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TradutorApp()));

    expect(find.text('Tradutor'), findsOneWidget);
    expect(find.text('Inglês e espanhol para português do Brasil'), findsOneWidget);
  });

  testWidgets('alterna entre tema claro e escuro', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const ProviderScope(child: TradutorApp()));
    BuildContext context() => tester.element(find.text('Tradutor'));
    expect(Theme.of(context()).brightness, Brightness.light);

    await tester.tap(find.byTooltip('Usar tema escuro'));
    await tester.pumpAndSettle();
    expect(Theme.of(context()).brightness, Brightness.dark);

    await tester.tap(find.byTooltip('Usar tema claro'));
    await tester.pumpAndSettle();
    expect(Theme.of(context()).brightness, Brightness.light);
  });

  test('tema começa seguindo o sistema', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system);
    container.read(themeModeProvider.notifier).toggle(Brightness.light);
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
