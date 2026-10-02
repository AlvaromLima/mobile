/** Contrato público de POST /api/v1/translate. */

export const REQUESTED_SOURCE_LANGUAGES = ['auto', 'en', 'es'] as const;
export type RequestedSourceLanguage = (typeof REQUESTED_SOURCE_LANGUAGES)[number];

/** Idiomas de origem efetivamente suportados (após detecção). */
export type SourceLanguage = Exclude<RequestedSourceLanguage, 'auto'>;

export const TARGET_LANGUAGE = 'pt-BR';
export type TargetLanguage = typeof TARGET_LANGUAGE;

/** Limite de caracteres por tradução, alinhado com o app. */
export const MAX_TEXT_LENGTH = 5_000;

export interface TranslateRequest {
  text: string;
  sourceLanguage: RequestedSourceLanguage;
  targetLanguage: TargetLanguage;
}

export interface TranslateResponse {
  success: true;
  /** Idioma identificado. Quando a origem é informada, repete o idioma informado. */
  detectedLanguage: SourceLanguage;
  /** Idioma de origem efetivo (en ou es). */
  sourceLanguage: SourceLanguage;
  targetLanguage: TargetLanguage;
  originalText: string;
  translatedText: string;
}

export interface ErrorResponse {
  success: false;
  error: { code: string; message: string; requestId: string };
}
