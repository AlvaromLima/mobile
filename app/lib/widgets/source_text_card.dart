import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import 'section_label.dart';

/// Área do texto original: campo multilinha com contador, colar e limpar.
/// O texto reconhecido pela voz também aparece aqui.
class SourceTextCard extends StatelessWidget {
  const SourceTextCard({
    super.key,
    required this.controller,
    required this.onPaste,
    required this.onClear,
    this.enabled = true,
    this.minLines = 4,
  });

  final TextEditingController controller;
  final VoidCallback onPaste;
  final VoidCallback onClear;

  /// Habilita o campo, colar e limpar.
  final bool enabled;

  /// Altura inicial do campo, em linhas; menor em telas baixas.
  final int minLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Texto original'),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          minLines: minLines,
          maxLines: 8,
          maxLength: AppConstants.maxTextLength,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            hintText: 'Digite, cole ou toque no microfone para falar em inglês ou espanhol',
            alignLabelWithHint: true,
          ),
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: enabled ? onPaste : null,
              icon: const Icon(Icons.content_paste),
              label: const Text('Colar'),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => TextButton.icon(
                onPressed: enabled && value.text.isNotEmpty ? onClear : null,
                icon: const Icon(Icons.clear),
                label: const Text('Limpar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
