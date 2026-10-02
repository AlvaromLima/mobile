import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants/app_constants.dart';
import '../providers/translator_provider.dart';
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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
                  enabled: !state.isLoading,
                  onChanged: notifier.setSourceLanguage,
                ),
                const SizedBox(height: 20),
                SourceTextCard(
                  controller: _textController,
                  enabled: !state.isLoading,
                  onPaste: _paste,
                  onClear: _clear,
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textController,
                  builder: (context, value, _) => FilledButton.icon(
                    onPressed: value.text.trim().isEmpty || state.isLoading ? null : _translate,
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
