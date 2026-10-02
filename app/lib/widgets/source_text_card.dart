import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../providers/voice_input_provider.dart';
import 'section_label.dart';

/// Área do texto original: campo multilinha com contador, colar, limpar e microfone.
class SourceTextCard extends StatelessWidget {
  const SourceTextCard({
    super.key,
    required this.controller,
    required this.onPaste,
    required this.onClear,
    required this.voiceStatus,
    required this.onMicPressed,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onPaste;
  final VoidCallback onClear;

  /// Situação da captura de voz; durante a escuta o botão do microfone vira "Parar".
  final VoiceStatus voiceStatus;

  /// Nulo desabilita o microfone.
  final VoidCallback? onMicPressed;

  /// Habilita o campo, colar e limpar.
  final bool enabled;

  static String? _statusLabel(VoiceStatus status) => switch (status) {
        VoiceStatus.requestingPermission => 'Solicitando permissão...',
        VoiceStatus.listening => 'Ouvindo...',
        VoiceStatus.processing => 'Processando...',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isListening = voiceStatus == VoiceStatus.listening;
    final statusLabel = _statusLabel(voiceStatus);

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
            if (isListening)
              IconButton.filled(
                onPressed: onMicPressed,
                tooltip: 'Parar',
                icon: const Icon(Icons.stop),
              )
            else
              IconButton.filledTonal(
                onPressed: onMicPressed,
                tooltip: 'Falar',
                icon: const Icon(Icons.mic_none),
              ),
            if (statusLabel != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
