import type { Request, Response } from 'express';
import type { TranslationService } from '../services/translation.service.ts';
import { AppError } from '../utils/app-error.ts';
import type { CharacterBudget } from '../utils/character-budget.ts';
import { validateTranslateRequest } from '../validators/translate.validator.ts';

export function createTranslateController(service: TranslationService, budget: CharacterBudget) {
  return async (req: Request, res: Response): Promise<void> => {
    const input = validateTranslateRequest(req);

    // Orçamento de caracteres antes de chamar o provider (protege a cota contra abuso).
    const verdict = budget.consume(req.ip ?? 'desconhecido', input.text.length);
    if (verdict === 'client-exceeded') throw new AppError('RATE_LIMITED');
    if (verdict === 'global-exceeded') throw new AppError('QUOTA_EXCEEDED');

    const startedAt = performance.now();
    const result = await service.translate(input, res.locals.requestId);

    // Nunca registrar o texto original nem a tradução (privacidade / LGPD).
    res.locals.log.info('tradução concluída', {
      requestedSourceLanguage: input.sourceLanguage,
      sourceLanguage: result.sourceLanguage,
      chars: input.text.length,
      durationMs: Math.round(performance.now() - startedAt),
    });
    res.status(200).json(result);
  };
}
