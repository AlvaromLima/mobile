import type { ErrorRequestHandler, RequestHandler, Response } from 'express';
import type { ErrorResponse } from '../types/translation.ts';
import { AppError } from '../utils/app-error.ts';

/** Erros do body-parser do Express trazem `type` e `status`. */
interface ParserError {
  type?: unknown;
  status?: unknown;
}

function toAppError(error: unknown): AppError {
  if (error instanceof AppError) return error;

  const { type, status } = (typeof error === 'object' && error !== null ? error : {}) as ParserError;
  switch (type) {
    case 'entity.too.large':
      return new AppError('TEXT_TOO_LONG');
    case 'entity.parse.failed':
      return new AppError('VALIDATION_ERROR', { message: 'JSON inválido.' });
    case 'encoding.unsupported':
    case 'charset.unsupported':
      return new AppError('UNSUPPORTED_MEDIA_TYPE');
  }
  if (typeof status === 'number' && status >= 400 && status < 500) return new AppError('VALIDATION_ERROR');
  return new AppError('INTERNAL_ERROR', { cause: error });
}

function send(res: Response, error: AppError): void {
  const body: ErrorResponse = {
    success: false,
    error: { code: error.code, message: error.message, requestId: res.locals.requestId },
  };
  res.status(error.status).json(body);
}

/** Tratamento centralizado: resposta sempre no contrato, sem stack trace nem detalhe interno. */
export const errorHandler: ErrorRequestHandler = (error: unknown, _req, res, next) => {
  if (res.headersSent) {
    next(error);
    return;
  }
  const appError = toAppError(error);
  if (appError.status >= 500) {
    // cause carrega o detalhe técnico (ex.: status do provider); fica só no log.
    res.locals.log.error('falha ao processar requisição', { code: appError.code, err: error });
  } else {
    res.locals.log.warn('requisição rejeitada', { code: appError.code });
  }
  send(res, appError);
};

export const notFoundHandler: RequestHandler = (_req, res) => {
  send(res, new AppError('NOT_FOUND'));
};
