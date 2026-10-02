/**
 * Regras de negócio da tradução: origem restrita a EN/ES, destino fixo pt-BR.
 */

import { AppError } from '../errors/app-error.ts';
import type { SourceLanguage, TranslationProvider } from '../providers/azure-translator.client.ts';

export type RequestedSourceLanguage = SourceLanguage | 'auto';

export interface TranslateInput {
  text: string;
  sourceLang: RequestedSourceLanguage;
}

export interface TranslateOutput {
  translatedText: string;
  /** Idioma de origem efetivo: o informado pelo usuário ou o detectado. */
  sourceLang: SourceLanguage;
  targetLang: 'pt-BR';
}

const SUPPORTED: readonly string[] = ['en', 'es'] satisfies SourceLanguage[];

/** O Azure pode devolver variantes regionais (ex.: es-MX); normaliza para o idioma base. */
function normalize(code: string): string {
  return code.split('-')[0]?.toLowerCase() ?? '';
}

export function createTranslationService(provider: TranslationProvider) {
  return {
    async translate(input: TranslateInput, traceId: string): Promise<TranslateOutput> {
      if (input.sourceLang !== 'auto') {
        const result = await provider.translate({ text: input.text, from: input.sourceLang, traceId });
        return { translatedText: result.translatedText, sourceLang: input.sourceLang, targetLang: 'pt-BR' };
      }

      const result = await provider.translate({ text: input.text, traceId });
      if (result.detectedLanguage === undefined) {
        throw new AppError('PROVIDER_UNAVAILABLE', { cause: new Error('Detecção solicitada sem detectedLanguage na resposta') });
      }
      const detected = normalize(result.detectedLanguage);
      if (!SUPPORTED.includes(detected)) throw new AppError('UNSUPPORTED_LANGUAGE');

      return { translatedText: result.translatedText, sourceLang: detected as SourceLanguage, targetLang: 'pt-BR' };
    },
  };
}

export type TranslationService = ReturnType<typeof createTranslationService>;
