import { Router } from 'express';
import { createTranslateController } from '../controllers/translate.controller.ts';
import type { TranslationService } from '../services/translation.service.ts';
import type { CharacterBudget } from '../utils/character-budget.ts';

export function translateRoutes(service: TranslationService, budget: CharacterBudget): Router {
  const router = Router();
  router.post('/translate', createTranslateController(service, budget));
  return router;
}
