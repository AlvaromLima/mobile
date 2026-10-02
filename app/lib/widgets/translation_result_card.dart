import 'package:flutter/material.dart';

import '../providers/translator_provider.dart';
import 'section_label.dart';

/// Área da tradução em português do Brasil, com os estados inicial, carregando, traduzido e erro.
class TranslationResultCard extends StatelessWidget {
  const TranslationResultCard({
    super.key,
    required this.state,
    required this.onCopy,
    required this.onShare,
  });

  final TranslatorState state;
  final VoidCallback onCopy;
  final ValueChanged<Rect?> onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasResult = state.status == TranslationStatus.success;
    final isError = state.status == TranslationStatus.failure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Português do Brasil'),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          color: isError ? theme.colorScheme.errorContainer : theme.colorScheme.surfaceContainerHighest,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(liveRegion: true, child: _content(theme)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: [
            // Leitura em voz alta será implementada na etapa de Text-to-Speech.
            const TextButton(
              onPressed: null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(Icons.volume_up_outlined), SizedBox(width: 8), Text('Ouvir')],
              ),
            ),
            TextButton.icon(
              onPressed: hasResult ? onCopy : null,
              icon: const Icon(Icons.copy),
              label: const Text('Copiar'),
            ),
            Builder(
              builder: (buttonContext) => TextButton.icon(
                onPressed: hasResult ? () => onShare(_originRect(buttonContext)) : null,
                icon: const Icon(Icons.share),
                label: const Text('Compartilhar'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _content(ThemeData theme) {
    switch (state.status) {
      case TranslationStatus.initial:
        return Text(
          'A tradução aparecerá aqui.',
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        );
      case TranslationStatus.loading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(semanticsLabel: 'Traduzindo'),
          ),
        );
      case TranslationStatus.success:
        return SelectableText(state.translatedText ?? '', style: theme.textTheme.bodyLarge);
      case TranslationStatus.failure:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                state.errorMessage ?? 'Erro ao traduzir.',
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        );
    }
  }

  /// Posição do botão, exigida pelo iPad para ancorar a folha de compartilhamento.
  static Rect? _originRect(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}
