import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { ConfigError, loadConfig } from '../src/config/env.ts';

describe('loadConfig', () => {
  it('aplica padrões sem nenhuma variável', () => {
    const config = loadConfig({});
    assert.equal(config.port, 8080);
    assert.equal(config.host, '0.0.0.0');
    assert.equal(config.logLevel, 'info');
    assert.equal(config.trustProxy, false);
    assert.equal(config.rateLimitMax, 30);
    assert.equal(config.rateLimitWindowMs, 60_000);
    assert.deepEqual(config.corsOrigins, []);
    assert.equal(config.translationTimeoutMs, 10_000);
  });

  it('interpreta TRUST_PROXY', () => {
    assert.equal(loadConfig({ TRUST_PROXY: 'true' }).trustProxy, true);
    assert.equal(loadConfig({ TRUST_PROXY: '1' }).trustProxy, 1);
    assert.throws(() => loadConfig({ TRUST_PROXY: 'talvez' }), ConfigError);
  });

  it('interpreta CORS_ORIGINS e recusa valores inválidos', () => {
    assert.deepEqual(loadConfig({ CORS_ORIGINS: 'https://a.com, https://b.com' }).corsOrigins, [
      'https://a.com',
      'https://b.com',
    ]);
    assert.throws(() => loadConfig({ CORS_ORIGINS: 'nao-e-url' }), ConfigError);
    assert.throws(() => loadConfig({ CORS_ORIGINS: 'https://a.com/' }), ConfigError);
  });

  it('usa o provider simulado por padrão, sem exigir chave', () => {
    assert.deepEqual(loadConfig({}).translation, { provider: 'mock' });
    assert.deepEqual(loadConfig({ TRANSLATION_PROVIDER: 'mock' }).translation, { provider: 'mock' });
  });

  it('azure exige TRANSLATION_API_KEY', () => {
    assert.throws(() => loadConfig({ TRANSLATION_PROVIDER: 'azure' }), /TRANSLATION_API_KEY/);
    assert.throws(() => loadConfig({ TRANSLATION_PROVIDER: 'azure', TRANSLATION_API_KEY: '   ' }), ConfigError);
  });

  it('azure com chave, região e endpoint padrão', () => {
    const { translation } = loadConfig({
      TRANSLATION_PROVIDER: 'azure',
      TRANSLATION_API_KEY: 'k',
      TRANSLATION_API_REGION: 'brazilsouth',
    });
    assert.deepEqual(translation, {
      provider: 'azure',
      apiKey: 'k',
      region: 'brazilsouth',
      endpoint: 'https://api.cognitive.microsofttranslator.com',
    });
  });

  it('azure sem região (recurso global) e endpoint só https', () => {
    const { translation } = loadConfig({ TRANSLATION_PROVIDER: 'azure', TRANSLATION_API_KEY: 'k' });
    assert.equal(translation.provider === 'azure' ? translation.region : 'n/a', undefined);
    assert.throws(
      () => loadConfig({ TRANSLATION_PROVIDER: 'azure', TRANSLATION_API_KEY: 'k', TRANSLATION_API_ENDPOINT: 'http://x.com' }),
      /https/,
    );
  });

  it('recusa provider desconhecido', () => {
    assert.throws(() => loadConfig({ TRANSLATION_PROVIDER: 'google' }), ConfigError);
  });

  it('mensagens de erro nunca contêm o valor da chave', () => {
    const secret = 'valor-secreto-123';
    for (const env of [
      { TRANSLATION_PROVIDER: 'azure', TRANSLATION_API_KEY: secret, TRANSLATION_API_ENDPOINT: 'http://x.com' },
      { TRANSLATION_PROVIDER: 'azure', TRANSLATION_API_KEY: secret, PORT: 'abc' },
    ]) {
      try {
        loadConfig(env);
        assert.fail('deveria falhar');
      } catch (error) {
        assert.ok(error instanceof ConfigError);
        assert.ok(!error.message.includes(secret));
      }
    }
  });

  it('valida faixas numéricas e LOG_LEVEL', () => {
    assert.throws(() => loadConfig({ PORT: 'abc' }), ConfigError);
    assert.throws(() => loadConfig({ RATE_LIMIT_MAX: '0' }), ConfigError);
    assert.throws(() => loadConfig({ TRANSLATION_TIMEOUT_MS: '100' }), ConfigError);
    assert.throws(() => loadConfig({ LOG_LEVEL: 'verbose' }), ConfigError);
  });
});
