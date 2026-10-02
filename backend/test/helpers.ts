import type { AddressInfo } from 'node:net';
import { buildApp } from '../src/app.ts';
import type { AppConfig } from '../src/config/env.ts';
import type { ProviderRequest, ProviderResult, TranslationProvider } from '../src/providers/translation-provider.ts';
import { createLogger } from '../src/utils/logger.ts';

export function testConfig(overrides: Partial<AppConfig> = {}): AppConfig {
  return {
    port: 0,
    host: '127.0.0.1',
    logLevel: 'info',
    trustProxy: false,
    rateLimitMax: 1_000,
    rateLimitWindowMs: 60_000,
    corsOrigins: [],
    translationTimeoutMs: 2_000,
    ...overrides,
  };
}

/** Provider falso que registra as chamadas. */
export function fakeProvider(respond: (request: ProviderRequest) => ProviderResult | Promise<ProviderResult>) {
  const calls: ProviderRequest[] = [];
  const provider: TranslationProvider = {
    name: 'fake',
    translate: async (request) => {
      calls.push(request);
      return respond(request);
    },
  };
  return { provider, calls };
}

export function captureLogs() {
  const lines: string[] = [];
  return {
    stream: { write: (chunk: string) => lines.push(chunk) },
    text: () => lines.join(''),
  };
}

export interface TestServer {
  url: string;
  logs: () => string;
  post: (body: unknown, headers?: Record<string, string>) => Promise<Response>;
  close: () => Promise<void>;
}

/** Sobe o app numa porta efêmera para testes de integração via fetch nativo. */
export async function startServer(options: { config?: AppConfig; provider?: TranslationProvider } = {}): Promise<TestServer> {
  const config = options.config ?? testConfig();
  const logs = captureLogs();
  const app = buildApp({
    config,
    ...(options.provider ? { provider: options.provider } : {}),
    logger: createLogger({ level: config.logLevel, stream: logs.stream }),
  });

  const server = await new Promise<ReturnType<typeof app.listen>>((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => { resolve(s); });
  });
  const { port } = server.address() as AddressInfo;
  const url = `http://127.0.0.1:${String(port)}`;

  return {
    url,
    logs: logs.text,
    post: (body, headers = {}) =>
      fetch(`${url}/api/v1/translate`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', ...headers },
        body: typeof body === 'string' ? body : JSON.stringify(body),
      }),
    close: () => new Promise<void>((resolve, reject) => {
      server.closeAllConnections();
      server.close((error) => { if (error) reject(error); else resolve(); });
    }),
  };
}

export interface ErrorBody {
  success: false;
  error: { code: string; message: string; requestId: string };
}
