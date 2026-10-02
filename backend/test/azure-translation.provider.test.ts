import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { createAzureTranslationProvider } from '../src/providers/azure-translation.provider.ts';
import type { ProviderRequest } from '../src/providers/translation-provider.ts';
import { AppError } from '../src/utils/app-error.ts';
import { azureJson, azureOk, fakeFetch, hang } from './azure-fakes.ts';

const REQUEST_ID = '11111111-2222-4333-8444-555555555555';
const FAKE_KEY = 'chave-ficticia-de-teste';

function provider(fetchFn: typeof fetch, region?: string) {
  return createAzureTranslationProvider({
    apiKey: FAKE_KEY,
    region,
    endpoint: 'https://translator.test',
    fetch: fetchFn,
    attemptTimeoutMs: 50,
    retryDelayMs: 1,
  });
}

function request(overrides: Partial<ProviderRequest> = {}): ProviderRequest {
  return { text: 'Hello', requestId: REQUEST_ID, signal: new AbortController().signal, ...overrides };
}

async function rejectsWith(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (error: unknown) => error instanceof AppError && error.code === code);
}

describe('Azure Translation provider', () => {
  it('detecção automática: envia to=pt sem from, com headers corretos', async () => {
    const { fn, calls } = fakeFetch(() => Promise.resolve(azureOk('Bom dia', 'en')));
    const result = await provider(fn, 'brazilsouth').translate(request({ text: 'Good morning' }));

    assert.deepEqual(result, { translatedText: 'Bom dia', detectedLanguage: 'en' });
    const call = calls[0];
    assert.ok(call);
    const url = new URL(call.url);
    assert.equal(url.origin + url.pathname, 'https://translator.test/translate');
    assert.equal(url.searchParams.get('api-version'), '3.0');
    assert.equal(url.searchParams.get('to'), 'pt');
    assert.equal(url.searchParams.has('from'), false);
    assert.ok(!call.url.includes(FAKE_KEY), 'a chave nunca vai na URL');

    const headers = call.init.headers as Record<string, string>;
    assert.equal(headers['Ocp-Apim-Subscription-Key'], FAKE_KEY);
    assert.equal(headers['Ocp-Apim-Subscription-Region'], 'brazilsouth');
    assert.equal(headers['X-ClientTraceId'], REQUEST_ID);
    assert.deepEqual(JSON.parse(call.init.body as string), [{ text: 'Good morning' }]);
  });

  it('idioma informado: envia from e omite região não configurada', async () => {
    const { fn, calls } = fakeFetch(() => Promise.resolve(azureOk('Bom dia')));
    const result = await provider(fn).translate(request({ text: 'Buenos días', from: 'es' }));

    assert.deepEqual(result, { translatedText: 'Bom dia' });
    const call = calls[0];
    assert.ok(call);
    assert.equal(new URL(call.url).searchParams.get('from'), 'es');
    assert.equal('Ocp-Apim-Subscription-Region' in (call.init.headers as Record<string, string>), false);
  });

  it('cota gratuita esgotada (403001) vira QUOTA_EXCEEDED sem retry', async () => {
    const { fn, calls } = fakeFetch(() => Promise.resolve(azureJson(403, { error: { code: 403001, message: 'quota' } })));
    await rejectsWith(provider(fn).translate(request()), 'QUOTA_EXCEEDED');
    assert.equal(calls.length, 1);
  });

  it('credencial inválida (401) vira PROVIDER_UNAVAILABLE sem retry', async () => {
    const { fn, calls } = fakeFetch(() => Promise.resolve(azureJson(401, { error: { code: 401000, message: 'auth' } })));
    await rejectsWith(provider(fn).translate(request()), 'PROVIDER_UNAVAILABLE');
    assert.equal(calls.length, 1);
  });

  it('faz 1 retry em 5xx e recupera', async () => {
    const { fn, calls } = fakeFetch(
      () => Promise.resolve(azureJson(503, { error: { code: 503000, message: 'x' } })),
      () => Promise.resolve(azureOk('Olá')),
    );
    assert.equal((await provider(fn).translate(request({ from: 'en' }))).translatedText, 'Olá');
    assert.equal(calls.length, 2);
  });

  it('desiste após 2 tentativas com 429', async () => {
    const limited = () => Promise.resolve(azureJson(429, { error: { code: 429000, message: 'x' } }));
    const { fn, calls } = fakeFetch(limited, limited);
    await rejectsWith(provider(fn).translate(request()), 'PROVIDER_UNAVAILABLE');
    assert.equal(calls.length, 2);
  });

  it('faz retry em falha de rede', async () => {
    const { fn, calls } = fakeFetch(
      () => Promise.reject(new TypeError('fetch failed')),
      () => Promise.resolve(azureOk('Olá')),
    );
    assert.equal((await provider(fn).translate(request({ from: 'en' }))).translatedText, 'Olá');
    assert.equal(calls.length, 2);
  });

  it('timeout da tentativa vira PROVIDER_TIMEOUT sem retry', async () => {
    const { fn, calls } = fakeFetch(hang, hang);
    await rejectsWith(provider(fn).translate(request()), 'PROVIDER_TIMEOUT');
    assert.equal(calls.length, 1);
  });

  it('respeita o tempo limite geral do serviço (signal da requisição)', async () => {
    const { fn, calls } = fakeFetch(hang, hang);
    const slow = createAzureTranslationProvider({
      apiKey: FAKE_KEY,
      region: undefined,
      endpoint: 'https://translator.test',
      fetch: fn,
      attemptTimeoutMs: 10_000,
    });
    await rejectsWith(slow.translate(request({ signal: AbortSignal.timeout(30) })), 'PROVIDER_TIMEOUT');
    assert.equal(calls.length, 1);
  });

  it('resposta 200 malformada vira PROVIDER_UNAVAILABLE', async () => {
    const { fn } = fakeFetch(() => Promise.resolve(azureJson(200, [{ translations: [] }])));
    await rejectsWith(provider(fn).translate(request()), 'PROVIDER_UNAVAILABLE');
  });

  it('erros nunca contêm a chave', async () => {
    const { fn } = fakeFetch(() => Promise.resolve(azureJson(401, { error: { code: 401000, message: 'auth' } })));
    try {
      await provider(fn).translate(request());
      assert.fail('deveria falhar');
    } catch (error) {
      assert.ok(error instanceof AppError);
      const dump = JSON.stringify({ message: error.message, cause: String(error.cause), stack: error.stack });
      assert.ok(!dump.includes(FAKE_KEY));
    }
  });
});
