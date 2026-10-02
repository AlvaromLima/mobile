import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { createTranslationProvider } from '../src/providers/index.ts';

describe('createTranslationProvider', () => {
  it('seleciona o provider pela configuração', () => {
    assert.equal(createTranslationProvider({ provider: 'mock' }).name, 'mock');
    assert.equal(
      createTranslationProvider({
        provider: 'azure',
        apiKey: 'k',
        region: undefined,
        endpoint: 'https://translator.test',
      }).name,
      'azure',
    );
  });
});
