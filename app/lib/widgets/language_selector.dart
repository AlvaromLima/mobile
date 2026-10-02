import 'package:flutter/material.dart';

import '../models/source_language.dart';

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final SourceLanguage value;
  final ValueChanged<SourceLanguage> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<SourceLanguage>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Idioma do texto',
        prefixIcon: Icon(Icons.language),
      ),
      items: [
        for (final language in SourceLanguage.values)
          DropdownMenuItem(value: language, child: Text(language.label)),
      ],
      onChanged: enabled
          ? (language) {
              if (language != null) onChanged(language);
            }
          : null,
    );
  }
}
