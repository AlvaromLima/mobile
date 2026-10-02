import type { Request } from 'express';
import {
  MAX_TEXT_LENGTH,
  REQUESTED_SOURCE_LANGUAGES,
  TARGET_LANGUAGE,
  type RequestedSourceLanguage,
  type TranslateRequest,
} from '../types/translation.ts';
import { AppError } from '../utils/app-error.ts';

const ALLOWED_FIELDS = new Set(['text', 'sourceLanguage', 'targetLanguage']);

function invalid(message: string): AppError {
  return new AppError('VALIDATION_ERROR', { message });
}

/** Valida o corpo de POST /api/v1/translate. Lança AppError com mensagem fixa (nunca ecoa dado do cliente). */
export function validateTranslateRequest(req: Request): TranslateRequest {
  if (!req.is('application/json')) throw new AppError('UNSUPPORTED_MEDIA_TYPE');

  const body: unknown = req.body;
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    throw invalid('O corpo da requisição deve ser um objeto JSON.');
  }

  const fields = body as Record<string, unknown>;
  if (Object.keys(fields).some((key) => !ALLOWED_FIELDS.has(key))) {
    throw invalid('A requisição contém campos não permitidos.');
  }

  const { text, sourceLanguage, targetLanguage = TARGET_LANGUAGE } = fields;

  if (typeof text !== 'string' || text.trim() === '') throw invalid('O campo text é obrigatório.');
  if (text.length > MAX_TEXT_LENGTH) throw new AppError('TEXT_TOO_LONG');

  if (typeof sourceLanguage !== 'string' || !(REQUESTED_SOURCE_LANGUAGES as readonly string[]).includes(sourceLanguage)) {
    throw invalid('O campo sourceLanguage deve ser auto, en ou es.');
  }
  if (targetLanguage !== TARGET_LANGUAGE) throw invalid('O campo targetLanguage deve ser pt-BR.');

  return { text, sourceLanguage: sourceLanguage as RequestedSourceLanguage, targetLanguage: TARGET_LANGUAGE };
}
