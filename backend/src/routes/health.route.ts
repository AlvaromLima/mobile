import type { FastifyInstance } from 'fastify';

/** Liveness: não chama o provider, para não consumir cota nem acoplar disponibilidade. */
export function registerHealthRoute(app: FastifyInstance): void {
  app.get('/health', { config: { rateLimit: false } }, () => ({ status: 'ok' }));
}
