import type { Request, Response } from 'express';
import type { TranslationService } from '../services/translation.service.ts';
import { validateTranslateRequest } from '../validators/translate.validator.ts';

export function createTranslateController(service: TranslationService) {
  return async (req: Request, res: Response): Promise<void> => {
    const input = validateTranslateRequest(req);
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
