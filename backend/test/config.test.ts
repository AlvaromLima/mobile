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

  it('valida faixas numéricas e LOG_LEVEL', () => {
    assert.throws(() => loadConfig({ PORT: 'abc' }), ConfigError);
    assert.throws(() => loadConfig({ RATE_LIMIT_MAX: '0' }), ConfigError);
    assert.throws(() => loadConfig({ TRANSLATION_TIMEOUT_MS: '100' }), ConfigError);
    assert.throws(() => loadConfig({ LOG_LEVEL: 'verbose' }), ConfigError);
  });
});
