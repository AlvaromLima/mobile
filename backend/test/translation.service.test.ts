import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { createMockTranslationProvider } from '../src/providers/mock-translation.provider.ts';
import type { TranslationProvider } from '../src/providers/translation-provider.ts';
import { createTranslationService } from '../src/services/translation.service.ts';
import { AppError } from '../src/utils/app-error.ts';
import { fakeProvider } from './helpers.ts';

const REQUEST_ID = '0f8fad5b-d9cb-469f-a165-70867728950e';

function rejectsWith(promise: Promise<unknown>, code: string) {
  return assert.rejects(promise, (error: unknown) => error instanceof AppError && error.code === code);
}

describe('TranslationService', () => {
  it('idioma informado: não pede detecção e repete o idioma em detectedLanguage', async () => {
    const { provider, calls } = fakeProvider(() => ({ translatedText: 'Bom dia' }));
    const service = createTranslationService(provider, { timeoutMs: 1_000 });

    const result = await service.translate(
      { text: 'Good morning', sourceLanguage: 'en', targetLanguage: 'pt-BR' },
      REQUEST_ID,
    );

    assert.deepEqual(result, {
      success: true,
      detectedLanguage: 'en',
      sourceLanguage: 'en',
      targetLanguage: 'pt-BR',
      originalText: 'Good morning',
      translatedText: 'Bom dia',
    });
    const call = calls[0];
    assert.ok(call);
    assert.equal(call.from, 'en');
    assert.equal(call.requestId, REQUEST_ID);
  });

  it('auto: usa o idioma detectado, normalizando variante regional', async () => {
    const { provider, calls } = fakeProvider(() => ({ translatedText: 'Bom dia', detectedLanguage: 'es-MX' }));
    const service = createTranslationService(provider, { timeoutMs: 1_000 });

    const result = await service.translate({ text: 'Buenos días', sourceLanguage: 'auto', targetLanguage: 'pt-BR' }, REQUEST_ID);

    assert.equal(result.detectedLanguage, 'es');
    assert.equal(result.sourceLanguage, 'es');
    assert.equal(calls[0]?.from, undefined);
  });

  it('auto: idioma fora de EN/ES gera UNSUPPORTED_LANGUAGE', async () => {
    const { provider } = fakeProvider(() => ({ translatedText: 'Bonjour', detectedLanguage: 'fr' }));
    const service = createTranslationService(provider, { timeoutMs: 1_000 });

    await rejectsWith(
      service.translate({ text: 'Bonjour', sourceLanguage: 'auto', targetLanguage: 'pt-BR' }, REQUEST_ID),
      'UNSUPPORTED_LANGUAGE',
    );
  });

  it('auto sem idioma detectado na resposta gera PROVIDER_UNAVAILABLE', async () => {
    const { provider } = fakeProvider(() => ({ translatedText: 'x' }));
    const service = createTranslationService(provider, { timeoutMs: 1_000 });

    await rejectsWith(
      service.translate({ text: 'Hello', sourceLanguage: 'auto', targetLanguage: 'pt-BR' }, REQUEST_ID),
      'PROVIDER_UNAVAILABLE',
    );
  });

  it('timeout mesmo com provider que ignora o AbortSignal', async () => {
    const stuck: TranslationProvider = { name: 'stuck', translate: () => new Promise(() => undefined) };
    const service = createTranslationService(stuck, { timeoutMs: 30 });

    await rejectsWith(
      service.translate({ text: 'Hello', sourceLanguage: 'en', targetLanguage: 'pt-BR' }, REQUEST_ID),
      'PROVIDER_TIMEOUT',
    );
  });

  it('erro inesperado do provider vira PROVIDER_UNAVAILABLE', async () => {
    const { provider } = fakeProvider(() => {
      throw new TypeError('fetch failed');
    });
    const service = createTranslationService(provider, { timeoutMs: 1_000 });

    await rejectsWith(
      service.translate({ text: 'Hello', sourceLanguage: 'en', targetLanguage: 'pt-BR' }, REQUEST_ID),
      'PROVIDER_UNAVAILABLE',
    );
  });

  it('AppError do provider é preservado', async () => {
    const { provider } = fakeProvider(() => {
      throw new AppError('QUOTA_EXCEEDED');
    });
    const service = createTranslationService(provider, { timeoutMs: 1_000 });

    await rejectsWith(
      service.translate({ text: 'Hello', sourceLanguage: 'en', targetLanguage: 'pt-BR' }, REQUEST_ID),
      'QUOTA_EXCEEDED',
    );
  });

  it('provider simulado responde sem rede e assume inglês no modo auto', async () => {
    const service = createTranslationService(createMockTranslationProvider({ delayMs: 1 }), { timeoutMs: 1_000 });

    const result = await service.translate({ text: 'Hello', sourceLanguage: 'auto', targetLanguage: 'pt-BR' }, REQUEST_ID);
    assert.equal(result.translatedText, '[Tradução simulada] Hello');
    assert.equal(result.detectedLanguage, 'en');
  });
});
