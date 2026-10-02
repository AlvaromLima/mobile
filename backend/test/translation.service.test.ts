import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { createMockTranslationProvider } from '../src/providers/mock-translation.provider.ts';
import type { TranslationProvider } from '../src/providers/translation-provider.ts';
import { createTranslationService } from '../src/services/translation.service.ts';
import type { RequestedSourceLanguage } from '../src/types/translation.ts';
import { AppError } from '../src/utils/app-error.ts';
import { fakeProvider } from './helpers.ts';

const REQUEST_ID = '0f8fad5b-d9cb-469f-a165-70867728950e';

function input(text: string, sourceLanguage: RequestedSourceLanguage) {
  return { text, sourceLanguage, targetLanguage: 'pt-BR' as const };
}

function rejectsWith(promise: Promise<unknown>, code: string) {
  return assert.rejects(promise, (error: unknown) => error instanceof AppError && error.code === code);
}

describe('TranslationService', () => {
  it('idioma informado: traduz direto, sem detecção, e repete o idioma em detectedLanguage', async () => {
    const { provider, calls, detectCalls } = fakeProvider(() => ({ translatedText: 'Bom dia' }));
    const service = createTranslationService(provider, { timeoutMs: 1_000 });

    const result = await service.translate(input('Good morning', 'en'), REQUEST_ID);

    assert.deepEqual(result, {
      success: true,
      detectedLanguage: 'en',
      sourceLanguage: 'en',
      targetLanguage: 'pt-BR',
      originalText: 'Good morning',
      translatedText: 'Bom dia',
    });
    assert.equal(detectCalls.length, 0);
    const call = calls[0];
    assert.ok(call);
    assert.equal(call.from, 'en');
    assert.equal(call.requestId, REQUEST_ID);
  });

  it('auto em inglês: detecta, depois traduz com from=en', async () => {
    const { provider, calls, detectCalls } = fakeProvider(
      () => ({ translatedText: 'Bom dia' }),
      () => ({ language: 'en' }),
    );
    const service = createTranslationService(provider, { timeoutMs: 1_000 });

    const result = await service.translate(input('Good morning', 'auto'), REQUEST_ID);

    assert.equal(result.detectedLanguage, 'en');
    assert.equal(result.sourceLanguage, 'en');
    assert.equal(detectCalls.length, 1);
    assert.equal(calls[0]?.from, 'en');
  });

  it('auto em espanhol: normaliza variante regional (es-MX) e traduz com from=es', async () => {
    const { provider, calls } = fakeProvider(
      () => ({ translatedText: 'Bom dia' }),
      () => ({ language: 'es-MX' }),
    );
    const service = createTranslationService(provider, { timeoutMs: 1_000 });

    const result = await service.translate(input('Buenos días', 'auto'), REQUEST_ID);

    assert.equal(result.detectedLanguage, 'es');
    assert.equal(calls[0]?.from, 'es');
  });

  for (const language of ['fr', 'pt', 'de', 'it']) {
    it(`auto com idioma não suportado (${language}): 422 e a tradução nunca é chamada`, async () => {
      const { provider, calls } = fakeProvider(() => ({ translatedText: 'não deveria' }), () => ({ language }));
      const service = createTranslationService(provider, { timeoutMs: 1_000 });

      await rejectsWith(service.translate(input('Texto', 'auto'), REQUEST_ID), 'UNSUPPORTED_LANGUAGE');
      assert.equal(calls.length, 0, 'idioma não suportado não pode ser traduzido');
    });
  }

  it('falha na detecção não chama a tradução', async () => {
    const { provider, calls } = fakeProvider(
      () => ({ translatedText: 'x' }),
      () => {
        throw new AppError('QUOTA_EXCEEDED');
      },
    );
    const service = createTranslationService(provider, { timeoutMs: 1_000 });

    await rejectsWith(service.translate(input('Hello', 'auto'), REQUEST_ID), 'QUOTA_EXCEEDED');
    assert.equal(calls.length, 0);
  });

  it('o tempo limite vale para a operação inteira (detecção + tradução)', async () => {
    const slow = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));
    const { provider } = fakeProvider(
      async () => {
        await slow(40);
        return { translatedText: 'x' };
      },
      async () => {
        await slow(40);
        return { language: 'en' };
      },
    );
    const service = createTranslationService(provider, { timeoutMs: 60 });

    await rejectsWith(service.translate(input('Hello', 'auto'), REQUEST_ID), 'PROVIDER_TIMEOUT');
  });

  it('timeout mesmo com provider que ignora o AbortSignal', async () => {
    const stuck: TranslationProvider = {
      name: 'stuck',
      detect: () => new Promise(() => undefined),
      translate: () => new Promise(() => undefined),
    };
    const service = createTranslationService(stuck, { timeoutMs: 30 });

    await rejectsWith(service.translate(input('Hello', 'en'), REQUEST_ID), 'PROVIDER_TIMEOUT');
    await rejectsWith(service.translate(input('Hello', 'auto'), REQUEST_ID), 'PROVIDER_TIMEOUT');
  });

  it('erro inesperado do provider vira PROVIDER_UNAVAILABLE', async () => {
    const { provider } = fakeProvider(() => {
      throw new TypeError('fetch failed');
    });
    const service = createTranslationService(provider, { timeoutMs: 1_000 });

    await rejectsWith(service.translate(input('Hello', 'en'), REQUEST_ID), 'PROVIDER_UNAVAILABLE');
  });

  it('AppError do provider é preservado', async () => {
    const { provider } = fakeProvider(() => {
      throw new AppError('QUOTA_EXCEEDED');
    });
    const service = createTranslationService(provider, { timeoutMs: 1_000 });

    await rejectsWith(service.translate(input('Hello', 'en'), REQUEST_ID), 'QUOTA_EXCEEDED');
  });
});

describe('provider simulado', () => {
  const service = createTranslationService(createMockTranslationProvider({ delayMs: 1 }), { timeoutMs: 1_000 });

  it('detecta inglês por padrão', async () => {
    const result = await service.translate(input('Good morning', 'auto'), REQUEST_ID);
    assert.equal(result.detectedLanguage, 'en');
    assert.equal(result.translatedText, '[Tradução simulada] Good morning');
  });

  it('detecta espanhol por palavras-chave', async () => {
    const result = await service.translate(input('Buenos días, ¿cómo estás?', 'auto'), REQUEST_ID);
    assert.equal(result.detectedLanguage, 'es');
  });

  it('simula idioma não suportado (francês)', async () => {
    await rejectsWith(service.translate(input('Bonjour, merci', 'auto'), REQUEST_ID), 'UNSUPPORTED_LANGUAGE');
  });
});
