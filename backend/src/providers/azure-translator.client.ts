/**
 * Cliente do Azure Translator (Text Translation v3.0) via fetch nativo.
 * Referência: https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/v3/translate
 *
 * Política de resiliência:
 * - timeout por tentativa;
 * - no máximo 1 retry, só para falhas rápidas e transitórias (rede, 429, 5xx);
 * - sem retry em timeout (estouraria o orçamento de tempo do app) e em cota esgotada.
 */

import { AppError } from '../errors/app-error.ts';

export type SourceLanguage = 'en' | 'es';

export interface ProviderRequest {
  text: string;
  /** Ausente = detecção automática pelo Azure. */
  from?: SourceLanguage;
  /** GUID repassado como X-ClientTraceId para correlação com o suporte do Azure. */
  traceId: string;
}

export interface ProviderResult {
  translatedText: string;
  /** Código bruto retornado pelo Azure; presente apenas na detecção automática. */
  detectedLanguage?: string;
}

export interface TranslationProvider {
  translate(request: ProviderRequest): Promise<ProviderResult>;
}

export interface AzureTranslatorOptions {
  endpoint: string;
  key: string;
  region: string | undefined;
  fetch?: typeof fetch;
  attemptTimeoutMs?: number;
  retryDelayMs?: number;
}

/** Código do Azure para "assinatura excedeu a cota gratuita" (plano F0). */
const AZURE_FREE_QUOTA_EXCEEDED = 403001;
/** pt = Português (Brasil) no Azure; pt-PT é Portugal. */
const TARGET_LANGUAGE = 'pt';
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

function isTimeout(error: unknown): boolean {
  return error instanceof DOMException && (error.name === 'TimeoutError' || error.name === 'AbortError');
}

async function readProviderCode(response: Response): Promise<number | undefined> {
  try {
    const body = (await response.json()) as { error?: { code?: unknown } };
    return typeof body.error?.code === 'number' ? body.error.code : undefined;
  } catch {
    return undefined;
  }
}

function parseResult(body: unknown): ProviderResult {
  const first = Array.isArray(body) ? (body[0] as unknown) : undefined;
  if (typeof first !== 'object' || first === null) throw new Error('Resposta do Azure sem itens');

  const item = first as { translations?: unknown; detectedLanguage?: { language?: unknown } };
  const translation = Array.isArray(item.translations) ? (item.translations[0] as { text?: unknown } | undefined) : undefined;
  if (typeof translation?.text !== 'string') throw new Error('Resposta do Azure sem texto traduzido');

  const detected = item.detectedLanguage?.language;
  return typeof detected === 'string'
    ? { translatedText: translation.text, detectedLanguage: detected }
    : { translatedText: translation.text };
}

export function createAzureTranslator(options: AzureTranslatorOptions): TranslationProvider {
  const doFetch = options.fetch ?? fetch;
  const attemptTimeoutMs = options.attemptTimeoutMs ?? 7_000;
  const retryDelayMs = options.retryDelayMs ?? 300;

  return {
    async translate({ text, from, traceId }) {
      const params = new URLSearchParams({ 'api-version': '3.0', to: TARGET_LANGUAGE });
      if (from) params.set('from', from);
      const url = `${options.endpoint}/translate?${params.toString()}`;

      const headers: Record<string, string> = {
        'Ocp-Apim-Subscription-Key': options.key,
        'Content-Type': 'application/json; charset=UTF-8',
        'X-ClientTraceId': traceId,
      };
      if (options.region) headers['Ocp-Apim-Subscription-Region'] = options.region;
      const body = JSON.stringify([{ text }]);

      let lastError: unknown;
      for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
        if (attempt > 1) await new Promise((resolve) => setTimeout(resolve, retryDelayMs));

        let response: Response;
        try {
          response = await doFetch(url, {
            method: 'POST',
            headers,
            body,
            signal: AbortSignal.timeout(attemptTimeoutMs),
          });
        } catch (error) {
          if (isTimeout(error)) throw new AppError('PROVIDER_TIMEOUT', { cause: error });
          lastError = error; // falha de rede: transitória
          continue;
        }

        if (response.ok) {
          try {
            return parseResult(await response.json());
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
    },
  };
}
