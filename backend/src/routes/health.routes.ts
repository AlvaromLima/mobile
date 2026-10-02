import { Router } from 'express';

/** Liveness: não chama o provider (não consome cota) e fica fora do rate limit. */
export function healthRoutes(): Router {
  const router = Router();
  router.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });
  return router;
}
