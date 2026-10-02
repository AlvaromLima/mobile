import { Writable } from 'node:stream';
import type { AppConfig } from '../src/config/env.ts';
import type { ProviderRequest, ProviderResult, TranslationProvider } from '../src/providers/azure-translator.client.ts';

export function testConfig(overrides: Partial<AppConfig> = {}): AppConfig {
  return {
    port: 0,
    host: '127.0.0.1',
    logLevel: 'info',
    trustProxy: false,
    rateLimitMax: 1_000,
    rateLimitWindowMs: 60_000,
    azure: { endpoint: 'https://translator.test', key: 'test-key', region: undefined },
    ...overrides,
  };
}

/** Provider falso que registra as chamadas e responde conforme a função dada. */
export function fakeProvider(respond: (request: ProviderRequest) => ProviderResult | Promise<ProviderResult>) {
  const calls: ProviderRequest[] = [];
  const provider: TranslationProvider = {
    translate(request) {
      calls.push(request);
      return Promise.resolve(respond(request));
    },
  };
  return { provider, calls };
}

/** Stream que acumula as linhas de log para inspeção. */
export function captureLogs() {
  const lines: string[] = [];
  const stream = new Writable({
    write(chunk: Buffer, _encoding, callback) {
      lines.push(chunk.toString());
      callback();
    },
  });
  return { stream, text: () => lines.join('') };
}
