import cors from 'cors';
import type { RequestHandler } from 'express';

/**
 * CORS restrito a uma lista explícita de origens web.
 * O app mobile não envia Origin e não depende de CORS; com a lista vazia,
 * nenhum navegador de outra origem consegue chamar a API.
 */
export function corsMiddleware(allowedOrigins: string[]): RequestHandler {
  const allowed = new Set(allowedOrigins);
  return cors({
    origin: (origin, callback) => { callback(null, origin !== undefined && allowed.has(origin)); },
    methods: ['GET', 'POST'],
    allowedHeaders: ['Content-Type', 'X-Request-Id'],
    exposedHeaders: ['X-Request-Id'],
    maxAge: 600,
  });
}
