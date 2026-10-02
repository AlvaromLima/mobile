import 'package:flutter/material.dart';

import '../providers/voice_input_provider.dart';

/// Botão principal de microfone com o status da captura de voz logo abaixo.
///
/// Durante a escuta, um anel pulsa atrás do botão (animação leve, uma única
/// AnimationController). Desligada quando o aparelho pede para reduzir movimento.
class VoiceButton extends StatefulWidget {
  const VoiceButton({
    super.key,
    required this.status,
    required this.isTranslating,
    required this.onPressed,
    this.diameter = 72,
  });

  final VoiceStatus status;

  /// Tradução em andamento (inclusive a disparada pela fala).
  final bool isTranslating;

  /// Nulo desabilita o botão.
  final VoidCallback? onPressed;

  /// Diâmetro do botão; menor em telas baixas.
  final double diameter;

  /// Rótulo de status exibido abaixo do botão.
  static String labelFor(VoiceStatus status, {required bool isTranslating}) {
    if (isTranslating) return 'Traduzindo...';
    return switch (status) {
      VoiceStatus.requestingPermission => 'Solicitando permissão...',
      VoiceStatus.listening => 'Ouvindo...',
      VoiceStatus.processing => 'Processando...',
      _ => 'Toque para falar',
    };
  }

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  bool get _isListening => widget.status == VoiceStatus.listening;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(VoiceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_isListening && !reduceMotion) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_pulse.isAnimating || _pulse.value != 0) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = widget.isTranslating ||
        widget.status == VoiceStatus.requestingPermission ||
        widget.status == VoiceStatus.processing;
    final label = VoiceButton.labelFor(widget.status, isTranslating: widget.isTranslating);

    final background = _isListening ? colors.error : colors.primary;
    final foreground = _isListening ? colors.onError : colors.onPrimary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          // Espaço reservado para o anel, para o layout não "pular" ao começar a ouvir.
          dimension: widget.diameter * 1.4,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_isListening)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => Container(
                    key: const ValueKey('voice-pulse'),
                    width: widget.diameter * (1 + 0.4 * _pulse.value),
                    height: widget.diameter * (1 + 0.4 * _pulse.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.error.withValues(alpha: 0.35 * (1 - _pulse.value)),
                    ),
                  ),
                ),
              SizedBox.square(
                dimension: widget.diameter,
                child: Tooltip(
                  message: _isListening ? 'Parar' : 'Falar',
                  child: FilledButton(
                    onPressed: widget.onPressed,
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                      backgroundColor: background,
                      foregroundColor: foreground,
                    ),
                    child: busy
                        ? SizedBox.square(
                            dimension: 28,
                            child: CircularProgressIndicator(strokeWidth: 3, color: colors.onSurfaceVariant),
                          )
                        : Icon(_isListening ? Icons.stop_rounded : Icons.mic_rounded, size: 34),
                  ),
                ),
              ),
            ],
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: _isListening ? colors.error : colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
