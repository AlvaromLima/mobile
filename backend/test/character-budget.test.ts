import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { createCharacterBudget } from '../src/utils/character-budget.ts';
import { type ErrorBody, fakeProvider, startServer, testConfig } from './helpers.ts';

function clock(start = 0) {
  let now = start;
  return { now: () => now, advance: (ms: number) => { now += ms; } };
}

describe('orçamento de caracteres', () => {
  it('limita por cliente dentro da janela e libera na janela seguinte', () => {
    const time = clock();
    const budget = createCharacterBudget({
      perClientLimit: 100,
      perClientWindowMs: 1_000,
      globalLimit: 0,
      globalWindowMs: 1_000,
      now: time.now,
    });

    assert.equal(budget.consume('a', 60), 'ok');
    assert.equal(budget.consume('a', 41), 'client-exceeded');
    assert.equal(budget.consume('a', 40), 'ok', 'o pedido recusado não consome orçamento');
    assert.equal(budget.consume('b', 100), 'ok', 'cada cliente tem o próprio orçamento');

    time.advance(1_000);
    assert.equal(budget.consume('a', 100), 'ok');
  });

  it('limita o total do serviço, somando todos os clientes', () => {
    const time = clock();
    const budget = createCharacterBudget({
      perClientLimit: 0,
      perClientWindowMs: 1_000,
      globalLimit: 150,
      globalWindowMs: 10_000,
      now: time.now,
    });

    assert.equal(budget.consume('a', 100), 'ok');
    assert.equal(budget.consume('b', 51), 'global-exceeded');
    assert.equal(budget.consume('b', 50), 'ok');

    time.advance(10_000);
    assert.equal(budget.consume('c', 150), 'ok');
  });

  it('limite 0 desativa', () => {
    const budget = createCharacterBudget({ perClientLimit: 0, perClientWindowMs: 1, globalLimit: 0, globalWindowMs: 1 });
    assert.equal(budget.consume('a', 10_000_000), 'ok');
  });
});

describe('orçamento de caracteres na rota', () => {
  it('cliente acima do orçamento recebe 429 e o provider não é chamado', async () => {
    const { provider, calls } = fakeProvider(() => ({ translatedText: 'x' }));
    const s = await startServer({ config: testConfig({ charLimitPerClient: 10 }), provider });
    try {
      assert.equal((await s.post({ text: 'a'.repeat(10), sourceLanguage: 'en' })).status, 200);
      const res = await s.post({ text: 'b', sourceLanguage: 'en' });
      assert.equal(res.status, 429);
      assert.equal(((await res.json()) as ErrorBody).error.code, 'RATE_LIMITED');
      assert.equal(calls.length, 1);
    } finally {
      await s.close();
    }
  });

  it('orçamento global esgotado responde 503 QUOTA_EXCEEDED', async () => {
    const { provider, calls } = fakeProvider(() => ({ translatedText: 'x' }));
    const s = await startServer({ config: testConfig({ charLimitGlobal: 5 }), provider });
    try {
      assert.equal((await s.post({ text: 'abcde', sourceLanguage: 'en' })).status, 200);
      const res = await s.post({ text: 'f', sourceLanguage: 'es' });
      assert.equal(res.status, 503);
      assert.equal(((await res.json()) as ErrorBody).error.code, 'QUOTA_EXCEEDED');
      assert.equal(calls.length, 1);
    } finally {
      await s.close();
    }
  });

  it('requisição inválida não consome orçamento', async () => {
    const { provider } = fakeProvider(() => ({ translatedText: 'x' }));
    const s = await startServer({ config: testConfig({ charLimitPerClient: 5 }), provider });
    try {
      assert.equal((await s.post({ text: 'a'.repeat(5), sourceLanguage: 'fr' })).status, 400);
      assert.equal((await s.post({ text: 'a'.repeat(5), sourceLanguage: 'en' })).status, 200);
    } finally {
      await s.close();
    }
  });
});

describe('guarda de rede dos testes', () => {
  it('bloqueia acesso a hosts externos', async () => {
    await assert.rejects(fetch('https://api.cognitive.microsofttranslator.com/translate'), /rede externa/);
  });
});
