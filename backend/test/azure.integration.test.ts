/**
 * Fluxo completo HTTP → serviço → provider Azure, com o Azure simulado via fetch falso.
 * Nenhuma chamada real ao Azure (sem custo, sem credencial).
 */
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { createAzureTranslationProvider } from '../src/providers/azure-translation.provider.ts';
import { azureDetected, azureJson, azureOk, fakeFetch } from './azure-fakes.ts';
import { type ErrorBody, startServer } from './helpers.ts';

const FAKE_KEY = 'chave-ficticia-integracao';

function azureProvider(fetchFn: typeof fetch) {
  return createAzureTranslationProvider({
    apiKey: FAKE_KEY,
    region: 'brazilsouth',
    endpoint: 'https://translator.test',
    fetch: fetchFn,
    retryDelayMs: 1,
  });
}

function paths(calls: { url: string }[]): string[] {
  return calls.map((c) => {
    const url = new URL(c.url);
    return `${url.pathname}${url.searchParams.has('from') ? `?from=${url.searchParams.get('from') ?? ''}` : ''}`;
  });
}

describe('integração com Azure (simulado)', () => {
  it('inglês informado: uma única chamada ao /translate', async () => {
    const { fn, calls } = fakeFetch(() => Promise.resolve(azureOk('Bom dia')));
    const s = await startServer({ provider: azureProvider(fn) });
    try {
      const res = await s.post({ text: 'Good morning', sourceLanguage: 'en', targetLanguage: 'pt-BR' });
      assert.equal(res.status, 200);
      assert.deepEqual(await res.json(), {
        success: true,
        detectedLanguage: 'en',
        sourceLanguage: 'en',
        targetLanguage: 'pt-BR',
        originalText: 'Good morning',
        translatedText: 'Bom dia',
      });
      assert.deepEqual(paths(calls), ['/translate?from=en']);
    } finally {
      await s.close();
    }
  });

  it('espanhol informado: uma única chamada ao /translate com from=es', async () => {
    const { fn, calls } = fakeFetch(() => Promise.resolve(azureOk('Bom dia')));
    const s = await startServer({ provider: azureProvider(fn) });
    try {
      const res = await s.post({ text: 'Buenos días', sourceLanguage: 'es', targetLanguage: 'pt-BR' });
      assert.equal(res.status, 200);
      const body = (await res.json()) as { sourceLanguage: string; translatedText: string };
      assert.equal(body.sourceLanguage, 'es');
      assert.equal(body.translatedText, 'Bom dia');
      assert.deepEqual(paths(calls), ['/translate?from=es']);
    } finally {
      await s.close();
    }
  });

  it('auto em espanhol: /detect e depois /translate com from=es', async () => {
    const { fn, calls } = fakeFetch(
      () => Promise.resolve(azureDetected('es')),
      () => Promise.resolve(azureOk('Bom dia, como você está?')),
    );
    const s = await startServer({ provider: azureProvider(fn) });
    try {
      const res = await s.post({ text: 'Buenos días, ¿cómo estás?', sourceLanguage: 'auto', targetLanguage: 'pt-BR' });
      assert.equal(res.status, 200);
      const body = (await res.json()) as { detectedLanguage: string; sourceLanguage: string; translatedText: string };
      assert.equal(body.detectedLanguage, 'es');
      assert.equal(body.sourceLanguage, 'es');
      assert.equal(body.translatedText, 'Bom dia, como você está?');
      assert.deepEqual(paths(calls), ['/detect', '/translate?from=es']);
    } finally {
      await s.close();
    }
  });

  it('auto em idioma não suportado: só /detect, 422 e nenhuma tradução', async () => {
    const { fn, calls } = fakeFetch(() => Promise.resolve(azureDetected('fr')));
    const s = await startServer({ provider: azureProvider(fn) });
    try {
      const res = await s.post({ text: 'Bonjour, comment ça va?', sourceLanguage: 'auto' });
      assert.equal(res.status, 422);
      assert.equal(((await res.json()) as ErrorBody).error.code, 'UNSUPPORTED_LANGUAGE');
      assert.deepEqual(paths(calls), ['/detect']);
    } finally {
      await s.close();
    }
  });

  it('cota esgotada retorna 503 QUOTA_EXCEEDED', async () => {
    const { fn } = fakeFetch(() => Promise.resolve(azureJson(403, { error: { code: 403001, message: 'quota' } })));
    const s = await startServer({ provider: azureProvider(fn) });
    try {
      const res = await s.post({ text: 'Hello', sourceLanguage: 'en' });
      assert.equal(res.status, 503);
      assert.equal(((await res.json()) as ErrorBody).error.code, 'QUOTA_EXCEEDED');
    } finally {
      await s.close();
    }
  });

  it('credencial inválida: 502 genérico; chave ausente da resposta e dos logs', async () => {
    const { fn } = fakeFetch(() =>
      Promise.resolve(azureJson(401, { error: { code: 401000, message: 'The request is not authorized' } })),
    );
    const s = await startServer({ provider: azureProvider(fn) });
    try {
      const res = await s.post({ text: 'Hello', sourceLanguage: 'auto' });
      assert.equal(res.status, 502);
      const raw = await res.text();
      assert.equal((JSON.parse(raw) as ErrorBody).error.code, 'PROVIDER_UNAVAILABLE');
      assert.ok(!raw.includes('401000') && !raw.includes('not authorized'), 'sem detalhe do provider na resposta');
      assert.ok(!raw.includes(FAKE_KEY));
      assert.ok(s.logs().includes('401000'), 'detalhe técnico fica no log');
      assert.ok(!s.logs().includes(FAKE_KEY), 'chave nunca no log');
    } finally {
      await s.close();
    }
  });

  it('Azure indisponível após retry retorna 502', async () => {
    const down = () => Promise.resolve(azureJson(503, { error: { code: 503000, message: 'x' } }));
    const { fn, calls } = fakeFetch(down, down);
    const s = await startServer({ provider: azureProvider(fn) });
    try {
      const res = await s.post({ text: 'Hello', sourceLanguage: 'en' });
      assert.equal(res.status, 502);
      assert.equal(calls.length, 2);
    } finally {
      await s.close();
    }
  });
});
