import express, { type Express } from 'express';
import helmet from 'helmet';
import type { AppConfig } from './config/env.ts';
import { corsMiddleware } from './middlewares/cors.ts';
import { errorHandler, notFoundHandler } from './middlewares/error-handler.ts';
import { rateLimitMiddleware } from './middlewares/rate-limit.ts';
import { requestContext } from './middlewares/request-context.ts';
import { createMockTranslationProvider } from './providers/mock-translation.provider.ts';
import type { TranslationProvider } from './providers/translation-provider.ts';
import { healthRoutes } from './routes/health.routes.ts';
import { translateRoutes } from './routes/translate.routes.ts';
import { createTranslationService } from './services/translation.service.ts';
import { createLogger, type Logger } from './utils/logger.ts';

export interface BuildAppOptions {
  config: AppConfig;
  /** Injetável para testes. Padrão nesta etapa: provider simulado. */
  provider?: TranslationProvider;
  logger?: Logger;
}

/**
 * 5.000 caracteres podem ocupar até ~30 KB em JSON com escapes \uXXXX.
 * Acima disso, o corpo é recusado antes da validação.
 */
const BODY_LIMIT = '32kb';

export function buildApp({ config, provider, logger }: BuildAppOptions): Express {
  const log = logger ?? createLogger({ level: config.logLevel });
  const service = createTranslationService(provider ?? createMockTranslationProvider(), {
    timeoutMs: config.translationTimeoutMs,
  });

  const app = express();
  app.disable('x-powered-by');
  // Necessário atrás de load balancer para o rate limit usar o IP real do cliente.
  app.set('trust proxy', config.trustProxy);

  app.use(requestContext(log));
  app.use(helmet());
  app.use(corsMiddleware(config.corsOrigins));

  app.use(healthRoutes());

  app.use('/api', rateLimitMiddleware({ limit: config.rateLimitMax, windowMs: config.rateLimitWindowMs }));
  app.use('/api', express.json({ limit: BODY_LIMIT, strict: true, type: 'application/json' }));
  app.use('/api/v1', translateRoutes(service));

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
