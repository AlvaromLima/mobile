/**
 * Regras de negócio da tradução: origem restrita a EN/ES, destino fixo pt-BR,
 * tempo limite único para a operação inteira (detecção + tradução).
 *
 * Modo automático: detecta primeiro e só traduz se o idioma for EN/ES.
 * Idioma não suportado nunca é enviado para tradução.
 */

import type { TranslationProvider } from '../providers/translation-provider.ts';
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

/** Executa uma chamada ao provider convertendo falhas não tipadas em AppError. */
async function callProvider<T>(operation: (signal: AbortSignal) => Promise<T>, signal: AbortSignal): Promise<T> {
  try {
    return await withTimeout(operation(signal), signal);
  } catch (error) {
    if (error instanceof AppError) throw error;
    if (signal.aborted) throw new AppError('PROVIDER_TIMEOUT', { cause: error });
    throw new AppError('PROVIDER_UNAVAILABLE', { cause: error });
  }
}

export interface TranslationServiceOptions {
  timeoutMs: number;
}

export function createTranslationService(provider: TranslationProvider, { timeoutMs }: TranslationServiceOptions) {
  return {
    async translate(input: TranslateRequest, requestId: string): Promise<TranslateResponse> {
      const { text } = input;
      const signal = AbortSignal.timeout(timeoutMs);

      let from: SourceLanguage;
      if (input.sourceLanguage === 'auto') {
        const detection = await callProvider((s) => provider.detect({ text, requestId, signal: s }), signal);
        const detected = normalize(detection.language);
        if (!SUPPORTED.includes(detected)) throw new AppError('UNSUPPORTED_LANGUAGE');
        from = detected as SourceLanguage;
      } else {
        from = input.sourceLanguage;
      }

      const result = await callProvider((s) => provider.translate({ text, from, requestId, signal: s }), signal);

      return {
        success: true,
        detectedLanguage: from,
        sourceLanguage: from,
        targetLanguage: input.targetLanguage,
        originalText: text,
        translatedText: result.translatedText,
      };
    },
  };
}

export type TranslationService = ReturnType<typeof createTranslationService>;
