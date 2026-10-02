import type { RequestHandler } from 'express';
import { rateLimit } from 'express-rate-limit';
import { AppError } from '../utils/app-error.ts';

/**
 * Limite por IP, em memória (serviço sem estado, sem banco).
 * Com várias instâncias, cada uma limita separadamente; para limite global, usar WAF/gateway.
 */
export function rateLimitMiddleware({ limit, windowMs }: { limit: number; windowMs: number }): RequestHandler {
  return rateLimit({
    windowMs,
    limit,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    // Retry-After já foi definido pelo middleware; o erro segue o contrato padrão.
    handler: (_req, _res, next) => { next(new AppError('RATE_LIMITED')); },
  });
}
