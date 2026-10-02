import type { FastifyError, FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { AppError } from './app-error.ts';

/** Converte qualquer erro (Fastify, validação, provider, inesperado) para o contrato público. */
function toAppError(error: FastifyError | AppError | Error): AppError {
  if (error instanceof AppError) return error;

  const fastifyError = error as Partial<FastifyError>;
  if (fastifyError.validation) {
    const tooLong = fastifyError.validation.some((v) => v.keyword === 'maxLength' && v.instancePath === '/text');
    return new AppError(tooLong ? 'TEXT_TOO_LONG' : 'VALIDATION_ERROR');
  }
  switch (fastifyError.code) {
    case 'FST_ERR_CTP_BODY_TOO_LARGE':
      return new AppError('TEXT_TOO_LONG');
    case 'FST_ERR_CTP_INVALID_MEDIA_TYPE':
      return new AppError('UNSUPPORTED_MEDIA_TYPE');
  }
  if (fastifyError.statusCode === 429) return new AppError('RATE_LIMITED');
  if (fastifyError.statusCode === 400) return new AppError('VALIDATION_ERROR');
  return new AppError('INTERNAL_ERROR', { cause: error });
}

function send(request: FastifyRequest, reply: FastifyReply, error: AppError): void {
  void reply.status(error.statusCode).send({
    error: { code: error.code, message: error.message, requestId: request.id },
  });
}

export function registerErrorHandling(app: FastifyInstance): void {
  app.setErrorHandler((error: FastifyError | Error, request, reply) => {
    const appError = toAppError(error);
    if (appError.statusCode >= 500) {
      // cause carrega o detalhe técnico (status/código do provider); fica só no log.
      request.log.error({ err: error, code: appError.code }, 'falha ao processar requisição');
    } else {
      request.log.warn({ code: appError.code }, 'requisição rejeitada');
    }
    send(request, reply, appError);
  });

  app.setNotFoundHandler((request, reply) => {
    send(request, reply, new AppError('NOT_FOUND'));
  });
}
