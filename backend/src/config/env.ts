/**
 * Leitura e validação das variáveis de ambiente.
 * Falha no boot se algo estiver inválido, para o serviço nunca subir inconsistente.
 * Mensagens de erro citam só o nome da variável, nunca o valor.
 */

import { LOG_LEVELS, type LogLevel } from '../utils/logger.ts';

export interface AppConfig {
  port: number;
  host: string;
  logLevel: LogLevel;
  trustProxy: boolean | number;
  rateLimitMax: number;
  rateLimitWindowMs: number;
  /** Origens web autorizadas no CORS. Vazio = nenhuma (o app mobile não depende de CORS). */
  corsOrigins: string[];
  /** Tempo máximo da chamada ao provider de tradução. */
  translationTimeoutMs: number;
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
    corsOrigins: readCorsOrigins(env.CORS_ORIGINS?.trim()),
    translationTimeoutMs: readInt(env, 'TRANSLATION_TIMEOUT_MS', 10_000, 1_000, 60_000),
  };
}
