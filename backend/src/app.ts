import { randomUUID } from 'node:crypto';
import type { IncomingMessage } from 'node:http';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import type { AppConfig } from './config/env.ts';
import { AppError } from './errors/app-error.ts';
import { registerErrorHandling } from './errors/error-handler.ts';
import { createAzureTranslator, type TranslationProvider } from './providers/azure-translator.client.ts';
import { registerHealthRoute } from './routes/health.route.ts';
import { registerTranslateRoute } from './routes/translate.route.ts';
import { createTranslationService } from './services/translation.service.ts';

export interface BuildAppOptions {
  config: AppConfig;
  /** Injetável para testes; em produção usa o Azure Translator. */
  provider?: TranslationProvider;
  /** Destino dos logs; injetável para testes de privacidade do log. */
  logStream?: NodeJS.WritableStream;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Aceita o X-Request-Id do app apenas se for UUID (evita injeção em log
 * e garante formato válido para o X-ClientTraceId do Azure).
 */
function genReqId(req: IncomingMessage): string {
  const header = req.headers['x-request-id'];
  return typeof header === 'string' && UUID.test(header) ? header.toLowerCase() : randomUUID();
}

export async function buildApp({ config, provider, logStream }: BuildAppOptions): Promise<FastifyInstance> {
  const app = Fastify({
    logger: logStream ? { level: config.logLevel, stream: logStream } : { level: config.logLevel },
    genReqId,
    // Número = quantidade de proxies confiáveis à frente do serviço (equivalente ao proxy-addr).
    trustProxy:
      typeof config.trustProxy === 'number'
        ? (() => {
            const hops = config.trustProxy;
            return (_address: string, hop: number) => hop < hops;
          })()
        : config.trustProxy,
    // 5.000 caracteres podem ocupar até ~30 KB em JSON com escapes \uXXXX.
    bodyLimit: 32 * 1024,
    requestTimeout: 30_000,
    ajv: { customOptions: { coerceTypes: false, removeAdditional: false } },
  });

  registerErrorHandling(app);
  // A API só aceita JSON; o parser text/plain embutido do Fastify é desnecessário.
  app.removeContentTypeParser('text/plain');

  app.addHook('onRequest', async (request, reply) => {
    void reply.header('x-request-id', request.id);
  });

  await app.register(helmet);
  await app.register(rateLimit, {
    global: true,
    max: config.rateLimitMax,
    timeWindow: config.rateLimitWindowMs,
    errorResponseBuilder: () => new AppError('RATE_LIMITED'),
  });

  const service = createTranslationService(provider ?? createAzureTranslator(config.azure));
  registerHealthRoute(app);
  registerTranslateRoute(app, service);

  return app;
}
