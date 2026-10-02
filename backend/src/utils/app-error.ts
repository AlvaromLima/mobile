/**
 * Erros do contrato público da API. O app mapeia `code` para mensagens e ações.
 * Nunca expor detalhes internos ou mensagens cruas do provider.
 */

export const ERROR_DEFINITIONS = {
  VALIDATION_ERROR: { status: 400, message: 'Requisição inválida.' },
  NOT_FOUND: { status: 404, message: 'Recurso não encontrado.' },
  TEXT_TOO_LONG: { status: 413, message: 'O texto excede o limite de caracteres.' },
  UNSUPPORTED_MEDIA_TYPE: { status: 415, message: 'Content-Type deve ser application/json.' },
  UNSUPPORTED_LANGUAGE: { status: 422, message: 'Não foi possível identificar o texto como inglês ou espanhol.' },
  RATE_LIMITED: { status: 429, message: 'Muitas solicitações. Aguarde alguns segundos e tente novamente.' },
  INTERNAL_ERROR: { status: 500, message: 'Erro inesperado.' },
  PROVIDER_UNAVAILABLE: { status: 502, message: 'Serviço de tradução indisponível no momento.' },
  QUOTA_EXCEEDED: { status: 503, message: 'Limite de uso do serviço de tradução atingido. Tente mais tarde.' },
  PROVIDER_TIMEOUT: { status: 504, message: 'O serviço de tradução demorou a responder.' },
} as const;

export type ErrorCode = keyof typeof ERROR_DEFINITIONS;

export class AppError extends Error {
  override name = 'AppError';
  readonly code: ErrorCode;
  readonly status: number;

  /** `message` permite detalhar erros de validação (sempre texto fixo, nunca dado do usuário). */
  constructor(code: ErrorCode, options?: { message?: string; cause?: unknown }) {
    super(options?.message ?? ERROR_DEFINITIONS[code].message, { cause: options?.cause });
    this.code = code;
    this.status = ERROR_DEFINITIONS[code].status;
  }
}
