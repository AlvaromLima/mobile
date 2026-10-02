import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants/app_constants.dart';
import '../models/source_language.dart';
import '../providers/translator_provider.dart';
import '../providers/voice_input_provider.dart';
import '../widgets/language_selector.dart';
import '../widgets/source_text_card.dart';
import '../widgets/theme_toggle_button.dart';
import '../widgets/translation_result_card.dart';

/// Tela principal do tradutor.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    super.dispose();
  }

  /// App em segundo plano durante a escuta (ligação, troca de app): interrompe a captura.
  /// `inactive` é ignorado porque também ocorre com o diálogo de permissão do sistema.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.paused && lifecycle != AppLifecycleState.hidden) return;
    final status = ref.read(voiceInputProvider).status;
    if (status == VoiceStatus.listening || status == VoiceStatus.processing) {
      ref.read(voiceInputProvider.notifier).interrupt();
    }
  }

  void _showMessage(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> _onMicPressed() async {
    final voice = ref.read(voiceInputProvider);
    final notifier = ref.read(voiceInputProvider.notifier);
    if (voice.status == VoiceStatus.listening) {
      await notifier.stop();
      return;
    }
    if (voice.isActive) return;

    FocusScope.of(context).unfocus();
    final selected = ref.read(translatorProvider).sourceLanguage;
    // O reconhecedor nativo precisa do idioma antes de ouvir; no modo automático, o usuário informa.
    final language = selected == SourceLanguage.auto ? await _askSpokenLanguage() : selected;
    if (language == null || !mounted) return;
    await notifier.start(language);
  }

  Future<SourceLanguage?> _askSpokenLanguage() {
    return showModalBottomSheet<SourceLanguage>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Em qual idioma você vai falar?', style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final language in const [SourceLanguage.en, SourceLanguage.es])
              ListTile(
                leading: const Icon(Icons.record_voice_over_outlined),
                title: Text(language.label),
                onTap: () => Navigator.of(sheetContext).pop(language),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _onVoiceChanged(VoiceInputState? previous, VoiceInputState next) {
    // Texto reconhecido (parcial e final) vai para o campo de texto original.
    if (next.text != previous?.text && (next.isActive || next.status == VoiceStatus.completed)) {
      final text = next.text.length > AppConstants.maxTextLength
          ? next.text.substring(0, AppConstants.maxTextLength)
          : next.text;
      _textController.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }

    final message = next.errorMessage;
    if (next.status == VoiceStatus.failure && previous?.status != VoiceStatus.failure && message != null) {
      _showMessage(
        message,
        action: next.canOpenSettings
            ? SnackBarAction(
                label: 'Abrir configurações',
                onPressed: () => ref.read(voiceInputProvider.notifier).openSettings(),
              )
            : null,
      );
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text;
    if (!mounted) return;
    if (pasted == null || pasted.isEmpty) {
      _showMessage('A área de transferência está vazia.');
      return;
    }

    // Insere na posição do cursor (ou substitui a seleção), respeitando o limite de caracteres.
    final value = _textController.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final available = AppConstants.maxTextLength - (value.text.length - (selection.end - selection.start));
    final insert = pasted.length > available ? pasted.substring(0, available) : pasted;
    final newText = value.text.replaceRange(selection.start, selection.end, insert);
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + insert.length),
    );
    if (insert.length < pasted.length) {
      _showMessage('Texto colado foi cortado no limite de ${AppConstants.maxTextLength} caracteres.');
    }
  }

  void _clear() {
    _textController.clear();
    ref.read(translatorProvider.notifier).clear();
  }

  void _translate() {
    FocusScope.of(context).unfocus();
    ref.read(translatorProvider.notifier).translate(_textController.text);
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _showMessage('Tradução copiada.');
  }

  Future<void> _share(String text, Rect? origin) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text, sharePositionOrigin: origin));
    } catch (_) {
      if (mounted) _showMessage('Não foi possível compartilhar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(translatorProvider);
    final notifier = ref.read(translatorProvider.notifier);
    final voice = ref.watch(voiceInputProvider);
    ref.listen(voiceInputProvider, _onVoiceChanged);

    final busy = state.isLoading || voice.isActive;
    // Microfone fica ativo durante a escuta (para parar), mas não enquanto pede permissão ou processa.
    final micEnabled = !state.isLoading &&
        voice.status != VoiceStatus.requestingPermission &&
        voice.status != VoiceStatus.processing;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appTitle),
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Em tablets, mantém a largura de leitura confortável.
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                LanguageSelector(
                  value: state.sourceLanguage,
                  enabled: !busy,
                  onChanged: notifier.setSourceLanguage,
                ),
                const SizedBox(height: 20),
                SourceTextCard(
                  controller: _textController,
                  enabled: !busy,
                  onPaste: _paste,
                  onClear: _clear,
                  voiceStatus: voice.status,
                  onMicPressed: micEnabled ? _onMicPressed : null,
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textController,
                  builder: (context, value, _) => FilledButton.icon(
                    onPressed: value.text.trim().isEmpty || busy ? null : _translate,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    icon: state.isLoading
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.translate),
                    label: Text(state.isLoading ? 'TRADUZINDO...' : 'TRADUZIR'),
                  ),
                ),
                const SizedBox(height: 24),
                TranslationResultCard(
                  state: state,
                  onCopy: () => _copy(state.translatedText ?? ''),
                  onShare: (origin) => _share(state.translatedText ?? '', origin),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
