import type { TranslationConfig } from '../config/env.ts';
import { createAzureTranslationProvider } from './azure-translation.provider.ts';
import { createMockTranslationProvider } from './mock-translation.provider.ts';
import type { TranslationProvider } from './translation-provider.ts';

/** Seleciona o provider pela configuração (TRANSLATION_PROVIDER). */
export function createTranslationProvider(config: TranslationConfig): TranslationProvider {
  switch (config.provider) {
    case 'mock':
      return createMockTranslationProvider();
    case 'azure':
      return createAzureTranslationProvider({
        apiKey: config.apiKey,
        region: config.region,
        endpoint: config.endpoint,
      });
  }
}
