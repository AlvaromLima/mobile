/// Idioma do texto original. O destino é sempre português do Brasil.
enum SourceLanguage {
  auto('auto', 'Detectar automaticamente'),
  en('en', 'Inglês'),
  es('es', 'Espanhol');

  const SourceLanguage(this.code, this.label);

  /// Código enviado ao backend.
  final String code;

  /// Nome exibido na interface.
  final String label;
}
