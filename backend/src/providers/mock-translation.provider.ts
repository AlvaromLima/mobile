import type { TranslationProvider } from './translation-provider.ts';

/**
 * Provider simulado, sem rede e sem credencial. Usado até a integração real (etapa 6)
 * e nos testes. Na detecção automática, assume inglês.
 */
export function createMockTranslationProvider({ delayMs = 300 } = {}): TranslationProvider {
  return {
    name: 'mock',
    async translate({ text, from, signal }) {
      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(resolve, delayMs);
        signal.addEventListener('abort', () => {
          clearTimeout(timer);
          reject(signal.reason as Error);
        }, { once: true });
      });
      return from
        ? { translatedText: `[Tradução simulada] ${text}` }
        : { translatedText: `[Tradução simulada] ${text}`, detectedLanguage: 'en' };
    },
  };
}
