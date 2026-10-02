/**
 * Leitura e validação das variáveis de ambiente.
 * Falha no boot se algo estiver inválido, para o serviço nunca subir inconsistente.
 * Mensagens de erro citam só o nome da variável, nunca o valor.
 */

import { LOG_LEVELS, type LogLevel } from '../utils/logger.ts';

export const TRANSLATION_PROVIDERS = ['mock', 'azure'] as const;

export type TranslationConfig =
  | { provider: 'mock' }
  | {
      provider: 'azure';
      apiKey: string;
      /** Obrigatória para recurso regional; ausente para recurso global. */
      region: string | undefined;
      endpoint: string;
    };

export interface AppConfig {
  port: number;
  host: string;
  logLevel: LogLevel;
  trustProxy: boolean | number;
  rateLimitMax: number;
  rateLimitWindowMs: number;
  /** Orçamento de caracteres por cliente e global (protege a cota do provider). 0 desativa. */
  charLimitPerClient: number;
  charLimitPerClientWindowMs: number;
  charLimitGlobal: number;
  charLimitGlobalWindowMs: number;
  /** Origens web autorizadas no CORS. Vazio = nenhuma (o app mobile não depende de CORS). */
  corsOrigins: string[];
  /** Tempo máximo da chamada ao provider de tradução. */
  translationTimeoutMs: number;
  translation: TranslationConfig;
}

export class ConfigError extends Error {
  override name = 'ConfigError';
}

type Env = Record<string, string | undefined>;

function readInt(env: Env, name: string, fallback: number, min: number, max: number): number {
  const raw = env[name]?.trim();
  if (!raw) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new ConfigError(`${name} deve ser inteiro entre ${String(min)} e ${String(max)}`);
  }
  return value;
}

function readTrustProxy(raw: string | undefined): boolean | number {
  if (!raw || raw === 'false') return false;
  if (raw === 'true') return true;
  const hops = Number(raw);
  if (Number.isInteger(hops) && hops >= 1 && hops <= 10) return hops;
  throw new ConfigError('TRUST_PROXY deve ser true, false ou o número de proxies (1 a 10)');
}

function readCorsOrigins(raw: string | undefined): string[] {
  if (!raw) return [];
  return raw
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
    .map((item) => {
      let url: URL;
      try {
        url = new URL(item);
      } catch {
        throw new ConfigError('CORS_ORIGINS deve conter apenas origens válidas separadas por vírgula');
      }
      if (url.origin !== item) throw new ConfigError('CORS_ORIGINS deve conter origens sem caminho nem barra final');
      return url.origin;
    });
}

const AZURE_DEFAULT_ENDPOINT = 'https://api.cognitive.microsofttranslator.com';

function readTranslation(env: Env): TranslationConfig {
  const provider = env.TRANSLATION_PROVIDER?.trim() || 'mock';
  if (!(TRANSLATION_PROVIDERS as readonly string[]).includes(provider)) {
    throw new ConfigError(`TRANSLATION_PROVIDER deve ser ${TRANSLATION_PROVIDERS.join(' ou ')}`);
  }
  if (provider === 'mock') return { provider: 'mock' };

  const apiKey = env.TRANSLATION_API_KEY?.trim();
  if (!apiKey) throw new ConfigError('TRANSLATION_API_KEY é obrigatória quando TRANSLATION_PROVIDER=azure');

  const rawEndpoint = env.TRANSLATION_API_ENDPOINT?.trim() || AZURE_DEFAULT_ENDPOINT;
  let endpoint: URL;
  try {
    endpoint = new URL(rawEndpoint);
  } catch {
    throw new ConfigError('TRANSLATION_API_ENDPOINT inválida');
  }
  if (endpoint.protocol !== 'https:') throw new ConfigError('TRANSLATION_API_ENDPOINT deve usar https');

  return {
    provider: 'azure',
    apiKey,
    region: env.TRANSLATION_API_REGION?.trim() || undefined,
    endpoint: endpoint.origin,
  };
}

export function loadConfig(env: Env = process.env): AppConfig {
  const logLevel = env.LOG_LEVEL?.trim() || 'info';
  if (!(LOG_LEVELS as readonly string[]).includes(logLevel)) throw new ConfigError('LOG_LEVEL inválido');

  return {
    port: readInt(env, 'PORT', 8080, 1, 65535),
    host: env.HOST?.trim() || '0.0.0.0',
    logLevel: logLevel as LogLevel,
    trustProxy: readTrustProxy(env.TRUST_PROXY?.trim()),
    rateLimitMax: readInt(env, 'RATE_LIMIT_MAX', 30, 1, 10_000),
    rateLimitWindowMs: readInt(env, 'RATE_LIMIT_WINDOW_MS', 60_000, 1_000, 3_600_000),
    // Padrões: 20 mil caracteres por cliente por hora; 64 mil por dia no total
    // (cota mensal do Azure F0, 2 milhões, dividida por 31 dias).
    charLimitPerClient: readInt(env, 'CHAR_LIMIT_PER_CLIENT', 20_000, 0, 10_000_000),
    charLimitPerClientWindowMs: readInt(env, 'CHAR_LIMIT_PER_CLIENT_WINDOW_MS', 3_600_000, 60_000, 86_400_000),
    charLimitGlobal: readInt(env, 'CHAR_LIMIT_GLOBAL', 64_000, 0, 1_000_000_000),
    charLimitGlobalWindowMs: readInt(env, 'CHAR_LIMIT_GLOBAL_WINDOW_MS', 86_400_000, 60_000, 2_678_400_000),
    corsOrigins: readCorsOrigins(env.CORS_ORIGINS?.trim()),
    translationTimeoutMs: readInt(env, 'TRANSLATION_TIMEOUT_MS', 10_000, 1_000, 60_000),
    translation: readTranslation(env),
  };
}
