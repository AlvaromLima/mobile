import type { FastifyInstance } from 'fastify';
import { translateSchema } from '../schemas/translate.schema.ts';
import type { TranslateInput, TranslationService } from '../services/translation.service.ts';

export function registerTranslateRoute(app: FastifyInstance, service: TranslationService): void {
  app.post<{ Body: TranslateInput }>('/v1/translate', { schema: translateSchema }, async (request) => {
    const startedAt = performance.now();
    const result = await service.translate(request.body, request.id);

    // Nunca registrar o texto original nem a tradução (privacidade / LGPD).
    request.log.info(
      {
        requestedSourceLang: request.body.sourceLang,
        sourceLang: result.sourceLang,
        chars: request.body.text.length,
        durationMs: Math.round(performance.now() - startedAt),
      },
      'tradução concluída',
    );
    return result;
  });
}
