import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { buildApp } from '../src/app.ts';
import { AppError } from '../src/errors/app-error.ts';
import { captureLogs, fakeProvider, testConfig } from './helpers.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

async function post(app: Awaited<ReturnType<typeof buildApp>>, payload: unknown, headers: Record<string, string> = {}) {
  return app.inject({ method: 'POST', url: '/v1/translate', payload: payload as Record<string, unknown>, headers });
}

describe('POST /v1/translate', () => {
  it('traduz com idioma informado', async () => {
    const { provider, calls } = fakeProvider(() => ({ translatedText: 'Olá, mundo' }));
    const app = await buildApp({ config: testConfig(), provider, logStream: captureLogs().stream });

    const res = await post(app, { text: 'Hello, world', sourceLang: 'en' });
    assert.equal(res.statusCode, 200);
    assert.deepEqual(res.json(), { translatedText: 'Olá, mundo', sourceLang: 'en', targetLang: 'pt-BR' });
    assert.equal(calls[0]?.from, 'en');
  });

  it('detecção automática normaliza variante regional', async () => {
    const { provider, calls } = fakeProvider(() => ({ translatedText: 'Olá', detectedLanguage: 'es-MX' }));
    const app = await buildApp({ config: testConfig(), provider, logStream: captureLogs().stream });

    const res = await post(app, { text: 'Hola', sourceLang: 'auto' });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json<{ sourceLang: string }>().sourceLang, 'es');
    assert.equal(calls[0]?.from, undefined);
  });

  it('detecção de idioma fora de EN/ES retorna 422 UNSUPPORTED_LANGUAGE', async () => {
    const { provider } = fakeProvider(() => ({ translatedText: 'Bonjour', detectedLanguage: 'fr' }));
    const app = await buildApp({ config: testConfig(), provider, logStream: captureLogs().stream });

    const res = await post(app, { text: 'Bonjour', sourceLang: 'auto' });
    assert.equal(res.statusCode, 422);
    assert.equal(res.json<{ error: { code: string } }>().error.code, 'UNSUPPORTED_LANGUAGE');
  });

  const invalidBodies: [string, unknown][] = [
    ['texto vazio', { text: '', sourceLang: 'en' }],
    ['texto só com espaços', { text: '   \n ', sourceLang: 'en' }],
    ['idioma não suportado', { text: 'Bonjour', sourceLang: 'fr' }],
    ['campo extra', { text: 'Hello', sourceLang: 'en', targetLang: 'de' }],
    ['texto numérico (sem coerção)', { text: 123, sourceLang: 'en' }],
    ['sem sourceLang', { text: 'Hello' }],
  ];
  for (const [name, body] of invalidBodies) {
    it(`rejeita ${name} com 400 VALIDATION_ERROR`, async () => {
      const { provider, calls } = fakeProvider(() => ({ translatedText: 'x' }));
      const app = await buildApp({ config: testConfig(), provider, logStream: captureLogs().stream });

      const res = await post(app, body);
      assert.equal(res.statusCode, 400);
      assert.equal(res.json<{ error: { code: string } }>().error.code, 'VALIDATION_ERROR');
      assert.equal(calls.length, 0);
    });
  }

  it('rejeita texto acima de 5.000 caracteres com 413 TEXT_TOO_LONG', async () => {
    const { provider } = fakeProvider(() => ({ translatedText: 'x' }));
    const app = await buildApp({ config: testConfig(), provider, logStream: captureLogs().stream });

    assert.equal((await post(app, { text: 'a'.repeat(5_000), sourceLang: 'en' })).statusCode, 200);
    const res = await post(app, { text: 'a'.repeat(5_001), sourceLang: 'en' });
    assert.equal(res.statusCode, 413);
    assert.equal(res.json<{ error: { code: string } }>().error.code, 'TEXT_TOO_LONG');
  });

  it('rejeita Content-Type diferente de JSON com 415', async () => {
    const { provider } = fakeProvider(() => ({ translatedText: 'x' }));
    const app = await buildApp({ config: testConfig(), provider, logStream: captureLogs().stream });

    const res = await app.inject({
      method: 'POST',
      url: '/v1/translate',
      payload: 'text=Hello',
      headers: { 'content-type': 'text/plain' },
    });
    assert.equal(res.statusCode, 415);
    assert.equal(res.json<{ error: { code: string } }>().error.code, 'UNSUPPORTED_MEDIA_TYPE');
  });

  it('erro do provider segue o contrato e não vaza detalhes internos', async () => {
    const { provider } = fakeProvider(() => {
      throw new AppError('QUOTA_EXCEEDED', { cause: new Error('detalhe interno 403001') });
    });
    const app = await buildApp({ config: testConfig(), provider, logStream: captureLogs().stream });

    const res = await post(app, { text: 'Hello', sourceLang: 'en' });
    assert.equal(res.statusCode, 503);
    const body = res.json<{ error: Record<string, string> }>();
    assert.deepEqual(Object.keys(body.error).sort(), ['code', 'message', 'requestId']);
    assert.equal(body.error.code, 'QUOTA_EXCEEDED');
    assert.ok(!res.body.includes('403001'));
  });

  it('erro inesperado vira 500 INTERNAL_ERROR genérico', async () => {
    const { provider } = fakeProvider(() => {
      throw new Error('stack interna');
    });
    const app = await buildApp({ config: testConfig(), provider, logStream: captureLogs().stream });

    const res = await post(app, { text: 'Hello', sourceLang: 'en' });
    assert.equal(res.statusCode, 500);
    assert.equal(res.json<{ error: { code: string } }>().error.code, 'INTERNAL_ERROR');
    assert.ok(!res.body.includes('stack interna'));
  });

  it('propaga X-Request-Id UUID válido e substitui valor inválido', async () => {
    const { provider, calls } = fakeProvider(() => ({ translatedText: 'x' }));
    const app = await buildApp({ config: testConfig(), provider, logStream: captureLogs().stream });
    const id = '0f8fad5b-d9cb-469f-a165-70867728950e';

    const ok = await post(app, { text: 'Hello', sourceLang: 'en' }, { 'x-request-id': id });
    assert.equal(ok.headers['x-request-id'], id);
    assert.equal(calls[0]?.traceId, id);

    const bad = await post(app, { text: 'Hello', sourceLang: 'en' }, { 'x-request-id': 'abc\ninjetado' });
    assert.match(String(bad.headers['x-request-id']), UUID);
    assert.notEqual(bad.headers['x-request-id'], 'abc\ninjetado');
  });

  it('nunca registra o texto original nem a tradução no log', async () => {
    const logs = captureLogs();
    const { provider } = fakeProvider(() => ({ translatedText: 'TRADUCAO-SIGILOSA' }));
    const app = await buildApp({ config: testConfig(), provider, logStream: logs.stream });

    await post(app, { text: 'TEXTO-SIGILOSO', sourceLang: 'en' });
    await post(app, { text: 'TEXTO-SIGILOSO', sourceLang: 'xx' });
    assert.ok(logs.text().includes('tradução concluída'));
    assert.ok(!logs.text().includes('TEXTO-SIGILOSO'));
    assert.ok(!logs.text().includes('TRADUCAO-SIGILOSA'));
  });

  it('aplica headers de segurança', async () => {
    const { provider } = fakeProvider(() => ({ translatedText: 'x' }));
    const app = await buildApp({ config: testConfig(), provider, logStream: captureLogs().stream });

    const res = await post(app, { text: 'Hello', sourceLang: 'en' });
    assert.equal(res.headers['x-content-type-options'], 'nosniff');
    assert.ok(res.headers['strict-transport-security']);
  });
});

describe('rate limit', () => {
  it('bloqueia acima do limite com 429 RATE_LIMITED e não limita /health', async () => {
    const { provider, calls } = fakeProvider(() => ({ translatedText: 'x' }));
    const app = await buildApp({ config: testConfig({ rateLimitMax: 2 }), provider, logStream: captureLogs().stream });

    assert.equal((await post(app, { text: 'a', sourceLang: 'en' })).statusCode, 200);
    assert.equal((await post(app, { text: 'b', sourceLang: 'en' })).statusCode, 200);
    const limited = await post(app, { text: 'c', sourceLang: 'en' });
    assert.equal(limited.statusCode, 429);
    assert.equal(limited.json<{ error: { code: string } }>().error.code, 'RATE_LIMITED');
    assert.ok(limited.headers['retry-after']);
    assert.equal(calls.length, 2);

    for (let i = 0; i < 5; i++) {
      assert.equal((await app.inject({ method: 'GET', url: '/health' })).statusCode, 200);
    }
  });
});

describe('rotas auxiliares', () => {
  it('GET /health responde ok sem chamar o provider', async () => {
    const { provider, calls } = fakeProvider(() => ({ translatedText: 'x' }));
    const app = await buildApp({ config: testConfig(), provider, logStream: captureLogs().stream });

    const res = await app.inject({ method: 'GET', url: '/health' });
    assert.equal(res.statusCode, 200);
    assert.deepEqual(res.json(), { status: 'ok' });
    assert.equal(calls.length, 0);
  });

  it('rota inexistente retorna 404 no formato do contrato', async () => {
    const { provider } = fakeProvider(() => ({ translatedText: 'x' }));
    const app = await buildApp({ config: testConfig(), provider, logStream: captureLogs().stream });

    const res = await app.inject({ method: 'GET', url: '/v1/nao-existe' });
    assert.equal(res.statusCode, 404);
    assert.equal(res.json<{ error: { code: string } }>().error.code, 'NOT_FOUND');
  });
});
