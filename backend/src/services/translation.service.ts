/**
 * Regras de negócio da tradução: origem restrita a EN/ES, destino fixo pt-BR,
 * tempo limite aplicado a qualquer provider.
 */

import type { ProviderResult, TranslationProvider } from '../providers/translation-provider.ts';
import type { SourceLanguage, TranslateRequest, TranslateResponse } from '../types/translation.ts';
import { AppError } from '../utils/app-error.ts';

const SUPPORTED: readonly string[] = ['en', 'es'] satisfies SourceLanguage[];

/** Providers podem devolver variantes regionais (ex.: es-MX); normaliza para o idioma base. */
function normalize(code: string): string {
  return code.split('-')[0]?.toLowerCase() ?? '';
}

/** Garante o tempo limite mesmo que o provider ignore o AbortSignal. */
function withTimeout<T>(promise: Promise<T>, signal: AbortSignal): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const onAbort = () => { reject(new AppError('PROVIDER_TIMEOUT', { cause: signal.reason })); };
    if (signal.aborted) {
      onAbort();
      return;
    }
    signal.addEventListener('abort', onAbort, { once: true });
    promise.then(resolve, reject).finally(() => { signal.removeEventListener('abort', onAbort); });
  });
}

export interface TranslationServiceOptions {
  timeoutMs: number;
}

export function createTranslationService(provider: TranslationProvider, { timeoutMs }: TranslationServiceOptions) {
  async function callProvider(text: string, from: SourceLanguage | undefined, requestId: string): Promise<ProviderResult> {
    const signal = AbortSignal.timeout(timeoutMs);
    try {
      return await withTimeout(provider.translate({ text, ...(from ? { from } : {}), requestId, signal }), signal);
    } catch (error) {
      if (error instanceof AppError) throw error;
      if (signal.aborted) throw new AppError('PROVIDER_TIMEOUT', { cause: error });
      throw new AppError('PROVIDER_UNAVAILABLE', { cause: error });
    }
  }

  return {
    async translate(input: TranslateRequest, requestId: string): Promise<TranslateResponse> {
      const requested = input.sourceLanguage === 'auto' ? undefined : input.sourceLanguage;
      const result = await callProvider(input.text, requested, requestId);

      let effective: SourceLanguage;
      if (requested) {
        effective = requested;
      } else {
        if (result.detectedLanguage === undefined) {
          throw new AppError('PROVIDER_UNAVAILABLE', { cause: new Error('Detecção solicitada sem idioma na resposta') });
        }
        const detected = normalize(result.detectedLanguage);
        // Idioma fora de EN/ES: não devolver tradução.
        if (!SUPPORTED.includes(detected)) throw new AppError('UNSUPPORTED_LANGUAGE');
        effective = detected as SourceLanguage;
      }

      return {
        success: true,
        detectedLanguage: effective,
        sourceLanguage: effective,
        targetLanguage: input.targetLanguage,
        originalText: input.text,
        translatedText: result.translatedText,
      };
    },
  };
}

export type TranslationService = ReturnType<typeof createTranslationService>;
