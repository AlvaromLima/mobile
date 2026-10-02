import type { SourceLanguage } from '../types/translation.ts';

export interface ProviderRequest {
  text: string;
  /** Ausente = detecção automática pelo provider. */
  from?: SourceLanguage;
  /** UUID da requisição, para correlação com o suporte do provider. */
  requestId: string;
  /** Abortado quando o tempo limite da tradução é atingido. */
  signal: AbortSignal;
}

export interface ProviderResult {
  translatedText: string;
  /** Código bruto retornado pelo provider; presente apenas na detecção automática. */
  detectedLanguage?: string;
}

/** Fornecedor de tradução. Destino sempre pt-BR. Deve lançar AppError em falhas conhecidas. */
export interface TranslationProvider {
  readonly name: string;
  translate(request: ProviderRequest): Promise<ProviderResult>;
}
