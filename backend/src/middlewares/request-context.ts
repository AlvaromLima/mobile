import { randomUUID } from 'node:crypto';
import type { RequestHandler } from 'express';
import type { Logger } from '../utils/logger.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Atribui o requestId (aceita X-Request-Id do app só se for UUID, evitando injeção em log),
 * devolve no header de resposta e registra o fim da requisição sem query nem corpo.
 */
export function requestContext(logger: Logger): RequestHandler {
  return (req, res, next) => {
    const header = req.get('x-request-id');
    const requestId = header && UUID.test(header) ? header.toLowerCase() : randomUUID();
    const startedAt = performance.now();

    res.locals.requestId = requestId;
    res.locals.log = logger.child({ requestId });
    res.setHeader('X-Request-Id', requestId);

    res.on('finish', () => {
      res.locals.log.info('requisição concluída', {
        method: req.method,
        path: req.originalUrl.split('?')[0],
        status: res.statusCode,
        durationMs: Math.round(performance.now() - startedAt),
      });
    });
    next();
  };
}
