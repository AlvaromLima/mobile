/** Limite de caracteres por tradução, alinhado com o app. */
export const MAX_TEXT_LENGTH = 5_000;

export const translateSchema = {
  body: {
    type: 'object',
    required: ['text', 'sourceLang'],
    additionalProperties: false,
    properties: {
      // pattern exige ao menos um caractere não branco
      text: { type: 'string', minLength: 1, maxLength: MAX_TEXT_LENGTH, pattern: '\\S' },
      sourceLang: { type: 'string', enum: ['en', 'es', 'auto'] },
    },
  },
  response: {
    200: {
      type: 'object',
      required: ['translatedText', 'sourceLang', 'targetLang'],
      additionalProperties: false,
      properties: {
        translatedText: { type: 'string' },
        sourceLang: { type: 'string', enum: ['en', 'es'] },
        targetLang: { type: 'string', const: 'pt-BR' },
      },
    },
  },
} as const;
