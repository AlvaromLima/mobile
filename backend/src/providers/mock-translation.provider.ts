import type { TranslationProvider } from './translation-provider.ts';

const SPANISH_HINTS = /[ñ¿¡]|\b(hola|buenos|buenas|gracias|cómo|qué|está|estás|por favor|el|los|las|una|muy)\b/i;
const FRENCH_HINTS = /\b(bonjour|merci|oui|je suis|c'est|très|beaucoup)\b/i;

function delay(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(resolve, ms);
    signal.addEventListener('abort', () => {
      clearTimeout(timer);
      reject(signal.reason as Error);
    }, { once: true });
  });
}

/**
 * Provider simulado, sem rede e sem credencial, para desenvolvimento e testes.
 * Detecção por palavras-chave (não é detecção real): espanhol, francês (para testar
 * idioma não suportado) ou, por padrão, inglês.
 */
export function createMockTranslationProvider({ delayMs = 300 } = {}): TranslationProvider {
  return {
    name: 'mock',
    async detect({ text, signal }) {
      await delay(delayMs / 2, signal);
      if (SPANISH_HINTS.test(text)) return { language: 'es' };
      if (FRENCH_HINTS.test(text)) return { language: 'fr' };
      return { language: 'en' };
    },
    async translate({ text, signal }) {
      await delay(delayMs, signal);
      return { translatedText: `[Tradução simulada] ${text}` };
    },
  };
}
