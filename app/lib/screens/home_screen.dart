import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../widgets/theme_toggle_button.dart';

/// Tela principal. Nesta etapa contém apenas a estrutura base;
/// a interface do tradutor é construída na etapa seguinte.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appTitle),
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.translate, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Inglês e espanhol para português do Brasil',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
