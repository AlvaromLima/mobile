import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import 'section_label.dart';

/// Área do texto original: campo multilinha com contador, colar, limpar e microfone.
class SourceTextCard extends StatelessWidget {
  const SourceTextCard({
    super.key,
    required this.controller,
    required this.onPaste,
    required this.onClear,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onPaste;
  final VoidCallback onClear;
  final bool enabled;

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
          minLines: 4,
          maxLines: 8,
          maxLength: AppConstants.maxTextLength,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            hintText: 'Digite ou cole um texto em inglês ou espanhol',
            alignLabelWithHint: true,
          ),
        ),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
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
            // Captura de voz será implementada nas etapas de Speech-to-Text.
            const IconButton.filledTonal(
              onPressed: null,
              tooltip: 'Microfone (em breve)',
              icon: Icon(Icons.mic_none),
            ),
          ],
        ),
      ],
    );
  }
}
