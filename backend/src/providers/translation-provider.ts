import type { SourceLanguage } from '../types/translation.ts';

interface ProviderCall {
  text: string;
  /** UUID da requisição, para correlação com o suporte do provider. */
  requestId: string;
  /** Abortado quando o tempo limite da operação é atingido. */
  signal: AbortSignal;
}

export type DetectRequest = ProviderCall;

export interface DetectResult {
  /** Código bruto do idioma (ex.: en, es-MX, fr). */
  language: string;
}

export interface ProviderRequest extends ProviderCall {
  /** Idioma de origem já definido (informado pelo usuário ou detectado antes). */
  from: SourceLanguage;
}

export interface ProviderResult {
  translatedText: string;
}

/**
 * Fornecedor de tradução. Destino sempre pt-BR. Deve lançar AppError em falhas conhecidas.
 * A detecção é separada da tradução para que idiomas não suportados nunca sejam traduzidos.
 */
export interface TranslationProvider {
  readonly name: string;
  detect(request: DetectRequest): Promise<DetectResult>;
  translate(request: ProviderRequest): Promise<ProviderResult>;
}
