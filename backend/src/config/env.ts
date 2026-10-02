/**
 * Leitura e validação das variáveis de ambiente.
 * Falha no boot se algo obrigatório estiver ausente ou inválido,
 * para que o serviço nunca suba em estado inconsistente.
 */

export interface AppConfig {
  port: number;
  host: string;
  logLevel: string;
  trustProxy: boolean | number;
  rateLimitMax: number;
  rateLimitWindowMs: number;
  azure: {
    endpoint: string;
    key: string;
    region: string | undefined;
  };
}

const LOG_LEVELS = ['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'];

export class ConfigError extends Error {
  override name = 'ConfigError';
}

function readInt(env: NodeJS.ProcessEnv, name: string, fallback: number, min: number, max: number): number {
  const raw = env[name];
  if (raw === undefined || raw === '') return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new ConfigError(`${name} deve ser inteiro entre ${String(min)} e ${String(max)}`);
  }
  return value;
}

function readTrustProxy(raw: string | undefined): boolean | number {
  if (raw === undefined || raw === '' || raw === 'false') return false;
  if (raw === 'true') return true;
  const hops = Number(raw);
  if (Number.isInteger(hops) && hops >= 1 && hops <= 10) return hops;
  throw new ConfigError('TRUST_PROXY deve ser true, false ou o número de proxies (1 a 10)');
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const key = env.AZURE_TRANSLATOR_KEY?.trim();
  if (!key) throw new ConfigError('AZURE_TRANSLATOR_KEY é obrigatória');

  const endpoint = env.AZURE_TRANSLATOR_ENDPOINT?.trim() || 'https://api.cognitive.microsofttranslator.com';
  let url: URL;
  try {
    url = new URL(endpoint);
  } catch {
    throw new ConfigError('AZURE_TRANSLATOR_ENDPOINT inválida');
  }
  if (url.protocol !== 'https:') throw new ConfigError('AZURE_TRANSLATOR_ENDPOINT deve usar https');

  const logLevel = env.LOG_LEVEL?.trim() || 'info';
  if (!LOG_LEVELS.includes(logLevel)) throw new ConfigError(`LOG_LEVEL inválido: ${logLevel}`);

  return {
    port: readInt(env, 'PORT', 8080, 1, 65535),
    host: env.HOST?.trim() || '0.0.0.0',
    logLevel,
    trustProxy: readTrustProxy(env.TRUST_PROXY?.trim()),
    rateLimitMax: readInt(env, 'RATE_LIMIT_MAX', 30, 1, 10_000),
    rateLimitWindowMs: readInt(env, 'RATE_LIMIT_WINDOW_MS', 60_000, 1_000, 3_600_000),
    azure: {
      endpoint: url.origin,
      key,
      region: env.AZURE_TRANSLATOR_REGION?.trim() || undefined,
    },
  };
}
