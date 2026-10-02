/**
 * Provider Azure Translator (Text Translation v3.0) via fetch nativo.
 * Referências:
 * - https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/v3/detect
 * - https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/v3/translate
 *
 * Detecção (/detect) e tradução (/translate) são chamadas separadas: o idioma é validado
 * antes de traduzir, e a detecção avulsa não consome a cota de caracteres.
 *
 * Resiliência (igual para as duas operações):
 * - timeout por tentativa, somado ao tempo limite geral do serviço (AbortSignal da requisição);
 * - no máximo 1 retry, só para falhas rápidas e transitórias (rede, 429, 5xx);
 * - sem retry em timeout, cota esgotada ou credencial inválida.
 *
 * Segurança: a chave vai somente no header; nunca em URL, erro ou log.
 */

import { AppError } from '../utils/app-error.ts';
import type { DetectResult, ProviderResult, TranslationProvider } from './translation-provider.ts';

export interface AzureTranslationProviderOptions {
  apiKey: string;
  /** Obrigatória para recursos regionais (ex.: brazilsouth); ausente para recurso global. */
  region: string | undefined;
  endpoint: string;
  fetch?: typeof fetch;
  attemptTimeoutMs?: number;
  retryDelayMs?: number;
}

/** Código do Azure para "assinatura excedeu a cota gratuita" (plano F0). */
const AZURE_FREE_QUOTA_EXCEEDED = 403001;
/** pt = Português (Brasil) no Azure; pt-PT é Portugal. */
const AZURE_TARGET_LANGUAGE = 'pt';
const MAX_ATTEMPTS = 2;

/** Detalhe técnico anexado como `cause` para o log; nunca vai para o cliente. */
export class ProviderHttpError extends Error {
  override name = 'ProviderHttpError';
  readonly status: number;
  readonly providerCode: number | undefined;

  constructor(status: number, providerCode: number | undefined) {
    super(`Azure Translator respondeu HTTP ${String(status)} (código ${String(providerCode ?? 'n/d')})`);
    this.status = status;
    this.providerCode = providerCode;
  }
}

function isTransientStatus(status: number): boolean {
  return status === 429 || status >= 500;
}

async function readProviderCode(response: Response): Promise<number | undefined> {
  try {
    const body = (await response.json()) as { error?: { code?: unknown } };
    return typeof body.error?.code === 'number' ? body.error.code : undefined;
  } catch {
    return undefined;
  }
}

function firstItem(body: unknown): Record<string, unknown> {
  const first = Array.isArray(body) ? (body[0] as unknown) : undefined;
  if (typeof first !== 'object' || first === null) throw new Error('Resposta do Azure sem itens');
  return first as Record<string, unknown>;
}

function parseDetect(body: unknown): DetectResult {
  const { language } = firstItem(body);
  if (typeof language !== 'string' || language === '') throw new Error('Resposta do Azure sem idioma detectado');
  return { language };
}

function parseTranslate(body: unknown): ProviderResult {
  const { translations } = firstItem(body);
  const translation = Array.isArray(translations) ? (translations[0] as { text?: unknown } | undefined) : undefined;
  if (typeof translation?.text !== 'string') throw new Error('Resposta do Azure sem texto traduzido');
  return { translatedText: translation.text };
}

export function createAzureTranslationProvider(options: AzureTranslationProviderOptions): TranslationProvider {
  const doFetch = options.fetch ?? fetch;
  const attemptTimeoutMs = options.attemptTimeoutMs ?? 7_000;
  const retryDelayMs = options.retryDelayMs ?? 300;

  /** POST ao Azure com retry, timeout e mapeamento de erros. Devolve o JSON já validado por `parse`. */
  async function call<T>(
    path: '/detect' | '/translate',
    query: Record<string, string>,
    text: string,
    requestId: string,
    signal: AbortSignal,
    parse: (body: unknown) => T,
  ): Promise<T> {
    const params = new URLSearchParams({ 'api-version': '3.0', ...query });
    const url = `${options.endpoint}${path}?${params.toString()}`;
    const headers: Record<string, string> = {
      'Ocp-Apim-Subscription-Key': options.apiKey,
      'Content-Type': 'application/json; charset=UTF-8',
      'X-ClientTraceId': requestId,
    };
    if (options.region) headers['Ocp-Apim-Subscription-Region'] = options.region;
    const body = JSON.stringify([{ text }]);

    let lastError: unknown;
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      if (attempt > 1) {
        await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
        if (signal.aborted) break;
      }

      const attemptSignal = AbortSignal.timeout(attemptTimeoutMs);
      let response: Response;
      try {
        response = await doFetch(url, { method: 'POST', headers, body, signal: AbortSignal.any([signal, attemptSignal]) });
      } catch (error) {
        if (signal.aborted || attemptSignal.aborted) throw new AppError('PROVIDER_TIMEOUT', { cause: error });
        lastError = error; // falha de rede: transitória
        continue;
      }

      if (response.ok) {
        try {
          return parse(await response.json());
        } catch (error) {
          throw new AppError('PROVIDER_UNAVAILABLE', { cause: error });
        }
      }

      const providerCode = await readProviderCode(response);
      const httpError = new ProviderHttpError(response.status, providerCode);
      if (providerCode === AZURE_FREE_QUOTA_EXCEEDED) throw new AppError('QUOTA_EXCEEDED', { cause: httpError });
      if (!isTransientStatus(response.status)) throw new AppError('PROVIDER_UNAVAILABLE', { cause: httpError });
      lastError = httpError;
    }

    throw new AppError('PROVIDER_UNAVAILABLE', { cause: lastError });
  }

  return {
    name: 'azure',
    detect: ({ text, requestId, signal }) => call('/detect', {}, text, requestId, signal, parseDetect),
    translate: ({ text, from, requestId, signal }) =>
      call('/translate', { to: AZURE_TARGET_LANGUAGE, from }, text, requestId, signal, parseTranslate),
  };
}
