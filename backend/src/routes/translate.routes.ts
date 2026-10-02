import { Router } from 'express';
import { createTranslateController } from '../controllers/translate.controller.ts';
import type { TranslationService } from '../services/translation.service.ts';

export function translateRoutes(service: TranslationService): Router {
  const router = Router();
  router.post('/translate', createTranslateController(service));
  return router;
}
