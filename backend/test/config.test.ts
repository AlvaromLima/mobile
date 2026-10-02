import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { ConfigError, loadConfig } from '../src/config/env.ts';

describe('loadConfig', () => {
  it('aplica padrões quando só a chave é informada', () => {
    const config = loadConfig({ AZURE_TRANSLATOR_KEY: 'k' });
    assert.equal(config.port, 8080);
    assert.equal(config.trustProxy, false);
    assert.equal(config.rateLimitMax, 30);
    assert.equal(config.azure.endpoint, 'https://api.cognitive.microsofttranslator.com');
    assert.equal(config.azure.region, undefined);
  });

  it('falha sem AZURE_TRANSLATOR_KEY', () => {
    assert.throws(() => loadConfig({}), ConfigError);
    assert.throws(() => loadConfig({ AZURE_TRANSLATOR_KEY: '   ' }), ConfigError);
  });

  it('recusa endpoint sem https', () => {
    assert.throws(
      () => loadConfig({ AZURE_TRANSLATOR_KEY: 'k', AZURE_TRANSLATOR_ENDPOINT: 'http://exemplo.com' }),
      /https/,
    );
  });

  it('não expõe o valor da chave na mensagem de erro', () => {
    try {
      loadConfig({ AZURE_TRANSLATOR_KEY: 'segredo-123', PORT: 'abc' });
      assert.fail('deveria falhar');
    } catch (error) {
      assert.ok(error instanceof ConfigError);
      assert.ok(!error.message.includes('segredo-123'));
    }
  });

  it('interpreta TRUST_PROXY', () => {
    assert.equal(loadConfig({ AZURE_TRANSLATOR_KEY: 'k', TRUST_PROXY: 'true' }).trustProxy, true);
    assert.equal(loadConfig({ AZURE_TRANSLATOR_KEY: 'k', TRUST_PROXY: '1' }).trustProxy, 1);
    assert.throws(() => loadConfig({ AZURE_TRANSLATOR_KEY: 'k', TRUST_PROXY: 'talvez' }), ConfigError);
  });

  it('valida faixas numéricas e LOG_LEVEL', () => {
    assert.throws(() => loadConfig({ AZURE_TRANSLATOR_KEY: 'k', RATE_LIMIT_MAX: '0' }), ConfigError);
    assert.throws(() => loadConfig({ AZURE_TRANSLATOR_KEY: 'k', LOG_LEVEL: 'verbose' }), ConfigError);
  });
});
