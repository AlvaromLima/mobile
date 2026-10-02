import 'package:flutter/material.dart';

/// Temas Material 3 claro e escuro gerados a partir da mesma cor semente,
/// para manter a identidade visual consistente entre os modos.
abstract final class AppTheme {
  static const _seedColor = Color(0xFF1E5AA8);

  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(seedColor: _seedColor, brightness: brightness);
    return ThemeData(
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
  }
}
