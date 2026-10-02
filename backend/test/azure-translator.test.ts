import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { AppError } from '../src/errors/app-error.ts';
import { createAzureTranslator } from '../src/providers/azure-translator.client.ts';

const TRACE_ID = '11111111-2222-4333-8444-555555555555';

type Responder = (url: string, init: RequestInit) => Promise<Response>;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

function okBody(text: string, detected?: string) {
  return [{ ...(detected ? { detectedLanguage: { language: detected, score: 1 } } : {}), translations: [{ text, to: 'pt' }] }];
}

/** fetch falso que consome uma resposta por chamada. */
function fakeFetch(...responders: Responder[]) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fn = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = input instanceof Request ? input.url : String(input);
    calls.push({ url, init: init ?? {} });
    const responder = responders[calls.length - 1];
    if (!responder) throw new Error('chamada inesperada');
    return responder(url, init ?? {});
  }) as typeof fetch;
  return { fn, calls };
}

function client(fetchFn: typeof fetch, region?: string) {
  return createAzureTranslator({
    endpoint: 'https://translator.test',
    key: 'test-key',
    region,
    fetch: fetchFn,
    attemptTimeoutMs: 30,
    retryDelayMs: 1,
  });
}

async function rejectsWith(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (error: unknown) => error instanceof AppError && error.code === code);
}

describe('Azure Translator client', () => {
  it('envia to=pt, sem from na detecção automática, com headers corretos', async () => {
    const { fn, calls } = fakeFetch(() => Promise.resolve(json(200, okBody('Olá', 'en'))));
    const result = await client(fn, 'brazilsouth').translate({ text: 'Hello', traceId: TRACE_ID });

    assert.deepEqual(result, { translatedText: 'Olá', detectedLanguage: 'en' });
    const call = calls[0];
    assert.ok(call);
    const url = new URL(call.url);
    assert.equal(url.origin + url.pathname, 'https://translator.test/translate');
    assert.equal(url.searchParams.get('api-version'), '3.0');
    assert.equal(url.searchParams.get('to'), 'pt');
    assert.equal(url.searchParams.has('from'), false);

    const headers = call.init.headers as Record<string, string>;
    assert.equal(headers['Ocp-Apim-Subscription-Key'], 'test-key');
    assert.equal(headers['Ocp-Apim-Subscription-Region'], 'brazilsouth');
    assert.equal(headers['X-ClientTraceId'], TRACE_ID);
    assert.deepEqual(JSON.parse(call.init.body as string), [{ text: 'Hello' }]);
  });

  it('envia from quando o idioma é informado e omite região não configurada', async () => {
    const { fn, calls } = fakeFetch(() => Promise.resolve(json(200, okBody('Olá'))));
    const result = await client(fn).translate({ text: 'Hola', from: 'es', traceId: TRACE_ID });

    assert.deepEqual(result, { translatedText: 'Olá' });
    const call = calls[0];
    assert.ok(call);
    assert.equal(new URL(call.url).searchParams.get('from'), 'es');
    assert.equal('Ocp-Apim-Subscription-Region' in (call.init.headers as Record<string, string>), false);
  });

  it('cota gratuita esgotada (403001) vira QUOTA_EXCEEDED sem retry', async () => {
    const { fn, calls } = fakeFetch(() => Promise.resolve(json(403, { error: { code: 403001, message: 'quota' } })));
    await rejectsWith(client(fn).translate({ text: 'x', traceId: TRACE_ID }), 'QUOTA_EXCEEDED');
    assert.equal(calls.length, 1);
  });

  it('credencial inválida (401) vira PROVIDER_UNAVAILABLE sem retry', async () => {
    const { fn, calls } = fakeFetch(() => Promise.resolve(json(401, { error: { code: 401000, message: 'auth' } })));
    await rejectsWith(client(fn).translate({ text: 'x', traceId: TRACE_ID }), 'PROVIDER_UNAVAILABLE');
    assert.equal(calls.length, 1);
  });

  it('faz 1 retry em 5xx e recupera', async () => {
    const { fn, calls } = fakeFetch(
      () => Promise.resolve(json(503, { error: { code: 503000, message: 'x' } })),
      () => Promise.resolve(json(200, okBody('Olá'))),
    );
    const result = await client(fn).translate({ text: 'Hello', from: 'en', traceId: TRACE_ID });
    assert.equal(result.translatedText, 'Olá');
    assert.equal(calls.length, 2);
  });

  it('desiste após 2 tentativas com 429', async () => {
    const { fn, calls } = fakeFetch(
      () => Promise.resolve(json(429, { error: { code: 429000, message: 'x' } })),
      () => Promise.resolve(json(429, { error: { code: 429000, message: 'x' } })),
    );
    await rejectsWith(client(fn).translate({ text: 'x', traceId: TRACE_ID }), 'PROVIDER_UNAVAILABLE');
    assert.equal(calls.length, 2);
  });

  it('faz retry em falha de rede', async () => {
    const { fn, calls } = fakeFetch(
      () => Promise.reject(new TypeError('fetch failed')),
      () => Promise.resolve(json(200, okBody('Olá'))),
    );
    const result = await client(fn).translate({ text: 'Hello', from: 'en', traceId: TRACE_ID });
    assert.equal(result.translatedText, 'Olá');
    assert.equal(calls.length, 2);
  });

  it('timeout vira PROVIDER_TIMEOUT sem retry', async () => {
    const hang: Responder = (_url, init) =>
      new Promise((_resolve, reject) => {
        init.signal?.addEventListener('abort', () => { reject(init.signal?.reason as Error); });
      });
    const { fn, calls } = fakeFetch(hang, hang);
    await rejectsWith(client(fn).translate({ text: 'x', traceId: TRACE_ID }), 'PROVIDER_TIMEOUT');
    assert.equal(calls.length, 1);
  });

  it('resposta 200 malformada vira PROVIDER_UNAVAILABLE', async () => {
    const { fn } = fakeFetch(() => Promise.resolve(json(200, [{ translations: [] }])));
    await rejectsWith(client(fn).translate({ text: 'x', traceId: TRACE_ID }), 'PROVIDER_UNAVAILABLE');
  });
});
