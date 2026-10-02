import type { AddressInfo } from 'node:net';
import { buildApp } from '../src/app.ts';
import type { AppConfig } from '../src/config/env.ts';
import type {
  DetectRequest,
  DetectResult,
  ProviderRequest,
  ProviderResult,
  TranslationProvider,
} from '../src/providers/translation-provider.ts';
import { createLogger } from '../src/utils/logger.ts';

export function testConfig(overrides: Partial<AppConfig> = {}): AppConfig {
  return {
    port: 0,
    host: '127.0.0.1',
    logLevel: 'info',
    trustProxy: false,
    rateLimitMax: 1_000,
    rateLimitWindowMs: 60_000,
    // Orçamento de caracteres desativado por padrão nos testes (0); testes específicos ativam.
    charLimitPerClient: 0,
    charLimitPerClientWindowMs: 3_600_000,
    charLimitGlobal: 0,
    charLimitGlobalWindowMs: 86_400_000,
    corsOrigins: [],
    translationTimeoutMs: 2_000,
    translation: { provider: 'mock' },
    ...overrides,
  };
}

/**
 * Provider falso que registra as chamadas. `calls` são as traduções; `detectCalls`, as detecções.
 * Por padrão, a detecção responde inglês.
 */
export function fakeProvider(
  translate: (request: ProviderRequest) => ProviderResult | Promise<ProviderResult>,
  detect: (request: DetectRequest) => DetectResult | Promise<DetectResult> = () => ({ language: 'en' }),
) {
  const calls: ProviderRequest[] = [];
  const detectCalls: DetectRequest[] = [];
  const provider: TranslationProvider = {
    name: 'fake',
    detect: async (request) => {
      detectCalls.push(request);
      return detect(request);
    },
    translate: async (request) => {
      calls.push(request);
      return translate(request);
    },
  };
  return { provider, calls, detectCalls };
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
