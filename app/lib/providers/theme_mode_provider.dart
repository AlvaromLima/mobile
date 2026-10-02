import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tema da sessão: começa seguindo o sistema e alterna manualmente entre claro e escuro.
/// A escolha não é persistida (sem armazenamento local).
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  /// Alterna a partir do brilho efetivamente exibido, que no modo sistema depende do aparelho.
  void toggle(Brightness current) {
    state = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
  }
}
