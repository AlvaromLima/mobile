import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { AppError } from '../src/utils/app-error.ts';
import { type ErrorBody, type TestServer, fakeProvider, startServer, testConfig } from './helpers.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

async function errorCode(res: Response): Promise<string> {
  const body = (await res.json()) as ErrorBody;
  assert.equal(body.success, false);
  return body.error.code;
}

describe('POST /api/v1/translate', () => {
  const { provider, calls } = fakeProvider((request) =>
    request.text === 'Bonjour'
      ? { translatedText: 'Olá', detectedLanguage: 'fr' }
      : { translatedText: 'Bom dia', ...(request.from ? {} : { detectedLanguage: 'en' }) },
  );
  let server: TestServer;
  before(async () => { server = await startServer({ provider }); });
  after(() => server.close());

  it('traduz no contrato da especificação', async () => {
    const res = await server.post({ text: 'Good morning', sourceLanguage: 'en', targetLanguage: 'pt-BR' });

    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), {
      success: true,
      detectedLanguage: 'en',
      sourceLanguage: 'en',
      targetLanguage: 'pt-BR',
      originalText: 'Good morning',
      translatedText: 'Bom dia',
    });
  });

  it('targetLanguage é opcional e assume pt-BR', async () => {
    const res = await server.post({ text: 'Hola', sourceLanguage: 'es' });
    assert.equal(res.status, 200);
    assert.equal(((await res.json()) as { targetLanguage: string }).targetLanguage, 'pt-BR');
  });

  it('detecção automática informa o idioma detectado', async () => {
    const res = await server.post({ text: 'Good morning', sourceLanguage: 'auto', targetLanguage: 'pt-BR' });
    assert.equal(res.status, 200);
    const body = (await res.json()) as { detectedLanguage: string; sourceLanguage: string };
    assert.equal(body.detectedLanguage, 'en');
    assert.equal(body.sourceLanguage, 'en');
  });

  it('idioma detectado fora de EN/ES retorna 422 sem tradução', async () => {
    const res = await server.post({ text: 'Bonjour', sourceLanguage: 'auto' });
    assert.equal(res.status, 422);
    const body = (await res.json()) as ErrorBody & { translatedText?: string };
    assert.equal(body.error.code, 'UNSUPPORTED_LANGUAGE');
    assert.equal(body.translatedText, undefined);
  });

  const invalidBodies: [string, unknown][] = [
    ['texto vazio', { text: '', sourceLanguage: 'en' }],
    ['texto só com espaços', { text: '  \n ', sourceLanguage: 'en' }],
    ['texto numérico', { text: 123, sourceLanguage: 'en' }],
    ['sem sourceLanguage', { text: 'Hello' }],
    ['sourceLanguage não suportado', { text: 'Bonjour', sourceLanguage: 'fr' }],
    ['targetLanguage diferente de pt-BR', { text: 'Hello', sourceLanguage: 'en', targetLanguage: 'es' }],
    ['campo extra', { text: 'Hello', sourceLanguage: 'en', extra: true }],
    ['corpo em array', [{ text: 'Hello', sourceLanguage: 'en' }]],
    ['JSON malformado', '{"text": "Hello",'],
  ];
  for (const [name, body] of invalidBodies) {
    it(`rejeita ${name} com 400 VALIDATION_ERROR`, async () => {
      const before = calls.length;
      const res = await server.post(body);
      assert.equal(res.status, 400);
      assert.equal(await errorCode(res), 'VALIDATION_ERROR');
      assert.equal(calls.length, before, 'provider não deve ser chamado');
    });
  }

  it('aceita exatamente 5.000 caracteres e rejeita 5.001 com 413', async () => {
    assert.equal((await server.post({ text: 'a'.repeat(5_000), sourceLanguage: 'en' })).status, 200);
    const res = await server.post({ text: 'a'.repeat(5_001), sourceLanguage: 'en' });
    assert.equal(res.status, 413);
    assert.equal(await errorCode(res), 'TEXT_TOO_LONG');
  });

  it('corpo acima de 32 KB é recusado com 413 antes da validação', async () => {
    const res = await server.post({ text: 'a'.repeat(40_000), sourceLanguage: 'en' });
    assert.equal(res.status, 413);
    assert.equal(await errorCode(res), 'TEXT_TOO_LONG');
  });

  it('Content-Type diferente de JSON retorna 415', async () => {
    const res = await fetch(`${server.url}/api/v1/translate`, {
      method: 'POST',
      headers: { 'content-type': 'text/plain' },
      body: 'text=Hello',
    });
    assert.equal(res.status, 415);
    assert.equal(await errorCode(res), 'UNSUPPORTED_MEDIA_TYPE');
  });

  it('propaga X-Request-Id UUID válido e substitui valor inválido', async () => {
    const id = '0f8fad5b-d9cb-469f-a165-70867728950e';
    const ok = await server.post({ text: 'Hello', sourceLanguage: 'en' }, { 'x-request-id': id });
    assert.equal(ok.headers.get('x-request-id'), id);
    assert.equal(calls.at(-1)?.requestId, id);

    const bad = await server.post({ text: 'Hello', sourceLanguage: 'en' }, { 'x-request-id': 'nao-e-uuid' });
    assert.match(bad.headers.get('x-request-id') ?? '', UUID);
  });

  it('aplica headers de segurança e oculta X-Powered-By', async () => {
    const res = await server.post({ text: 'Hello', sourceLanguage: 'en' });
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.ok(res.headers.get('strict-transport-security'));
    assert.equal(res.headers.get('x-powered-by'), null);
  });

  it('nunca registra o texto original nem a tradução no log', async () => {
    const { provider: secretProvider } = fakeProvider(() => ({ translatedText: 'TRADUCAO-SIGILOSA' }));
    const s = await startServer({ provider: secretProvider });
    try {
      await s.post({ text: 'TEXTO-SIGILOSO', sourceLanguage: 'en' });
      await s.post({ text: 'TEXTO-SIGILOSO', sourceLanguage: 'xx' });
      assert.ok(s.logs().includes('tradução concluída'));
      assert.ok(s.logs().includes('"path":"/api/v1/translate"'), 'log deve ter o caminho completo');
      assert.ok(!s.logs().includes('TEXTO-SIGILOSO'));
      assert.ok(!s.logs().includes('TRADUCAO-SIGILOSA'));
    } finally {
      await s.close();
    }
  });
});

describe('erros do provider', () => {
  it('erro conhecido segue o contrato e não vaza detalhe interno', async () => {
    const { provider } = fakeProvider(() => {
      throw new AppError('QUOTA_EXCEEDED', { cause: new Error('detalhe interno 403001') });
    });
    const s = await startServer({ provider });
    try {
      const res = await s.post({ text: 'Hello', sourceLanguage: 'en' });
      assert.equal(res.status, 503);
      const raw = await res.text();
      const body = JSON.parse(raw) as ErrorBody;
      assert.deepEqual(Object.keys(body.error).sort(), ['code', 'message', 'requestId']);
      assert.equal(body.error.code, 'QUOTA_EXCEEDED');
      assert.ok(!raw.includes('403001'));
      assert.ok(s.logs().includes('403001'), 'detalhe técnico deve ficar no log');
    } finally {
      await s.close();
    }
  });

  it('erro inesperado vira 502 sem stack trace', async () => {
    const { provider } = fakeProvider(() => {
      throw new Error('stack interna');
    });
    const s = await startServer({ provider });
    try {
      const res = await s.post({ text: 'Hello', sourceLanguage: 'en' });
      assert.equal(res.status, 502);
      const raw = await res.text();
      assert.ok(!raw.includes('stack interna'));
      assert.ok(!raw.includes('at '));
    } finally {
      await s.close();
    }
  });

  it('provider lento gera 504 PROVIDER_TIMEOUT', async () => {
    const { provider } = fakeProvider(() => new Promise(() => undefined));
    const s = await startServer({ config: testConfig({ translationTimeoutMs: 1_000 }), provider });
    try {
      const res = await s.post({ text: 'Hello', sourceLanguage: 'en' });
      assert.equal(res.status, 504);
      assert.equal(await errorCode(res), 'PROVIDER_TIMEOUT');
    } finally {
      await s.close();
    }
  });
});

describe('rate limit', () => {
  it('bloqueia acima do limite com 429, Retry-After e sem chamar o provider; /health não é limitado', async () => {
    const { provider, calls } = fakeProvider(() => ({ translatedText: 'x' }));
    const s = await startServer({ config: testConfig({ rateLimitMax: 2 }), provider });
    try {
      assert.equal((await s.post({ text: 'a', sourceLanguage: 'en' })).status, 200);
      assert.equal((await s.post({ text: 'b', sourceLanguage: 'en' })).status, 200);
      const limited = await s.post({ text: 'c', sourceLanguage: 'en' });
      assert.equal(limited.status, 429);
      assert.ok(limited.headers.get('retry-after'));
      assert.equal(await errorCode(limited), 'RATE_LIMITED');
      assert.equal(calls.length, 2);

      for (let i = 0; i < 5; i++) {
        assert.equal((await fetch(`${s.url}/health`)).status, 200);
      }
    } finally {
      await s.close();
    }
  });
});

describe('CORS', () => {
  it('sem origens configuradas, não libera nenhuma origem web', async () => {
    const s = await startServer();
    try {
      const res = await s.post({ text: 'Hello', sourceLanguage: 'en' }, { origin: 'https://site-qualquer.com' });
      assert.equal(res.headers.get('access-control-allow-origin'), null);
    } finally {
      await s.close();
    }
  });

  it('libera apenas a origem configurada, inclusive no preflight', async () => {
    const s = await startServer({ config: testConfig({ corsOrigins: ['https://app.exemplo.com'] }) });
    try {
      const preflight = await fetch(`${s.url}/api/v1/translate`, {
        method: 'OPTIONS',
        headers: {
          origin: 'https://app.exemplo.com',
          'access-control-request-method': 'POST',
          'access-control-request-headers': 'content-type',
        },
      });
      assert.equal(preflight.status, 204);
      assert.equal(preflight.headers.get('access-control-allow-origin'), 'https://app.exemplo.com');

      const other = await s.post({ text: 'Hello', sourceLanguage: 'en' }, { origin: 'https://outro.com' });
      assert.equal(other.headers.get('access-control-allow-origin'), null);
    } finally {
      await s.close();
    }
  });
});

describe('rotas auxiliares', () => {
  it('GET /health responde ok', async () => {
    const s = await startServer();
    try {
      const res = await fetch(`${s.url}/health`);
      assert.equal(res.status, 200);
      assert.deepEqual(await res.json(), { status: 'ok' });
    } finally {
      await s.close();
    }
  });

  it('rota inexistente retorna 404 no contrato', async () => {
    const s = await startServer();
    try {
      const res = await fetch(`${s.url}/api/v1/nao-existe`);
      assert.equal(res.status, 404);
      assert.equal(await errorCode(res), 'NOT_FOUND');
    } finally {
      await s.close();
    }
  });
});
