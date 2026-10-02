/**
 * Logger estruturado (JSON por linha), sem dependências.
 * Regra: nunca registrar texto do usuário, tradução ou segredos.
 */

export const LOG_LEVELS = ['error', 'warn', 'info', 'debug', 'silent'] as const;
export type LogLevel = (typeof LOG_LEVELS)[number];

type Fields = Record<string, unknown>;

export interface Logger {
  error(msg: string, fields?: Fields): void;
  warn(msg: string, fields?: Fields): void;
  info(msg: string, fields?: Fields): void;
  debug(msg: string, fields?: Fields): void;
  child(bindings: Fields): Logger;
}

const SEVERITY: Record<Exclude<LogLevel, 'silent'>, number> = { error: 0, warn: 1, info: 2, debug: 3 };

function serializeError(error: unknown, depth = 0): unknown {
  if (!(error instanceof Error)) return error;
  return {
    type: error.name,
    message: error.message,
    stack: error.stack,
    ...(error.cause !== undefined && depth < 3 ? { cause: serializeError(error.cause, depth + 1) } : {}),
  };
}

export interface LoggerOptions {
  level: LogLevel;
  stream?: { write(chunk: string): unknown };
  bindings?: Fields;
}

export function createLogger({ level, stream = process.stdout, bindings = {} }: LoggerOptions): Logger {
  const threshold = level === 'silent' ? -1 : SEVERITY[level];

  const write = (lineLevel: keyof typeof SEVERITY, msg: string, fields: Fields = {}) => {
    if (SEVERITY[lineLevel] > threshold) return;
    const { err, ...rest } = fields;
    const entry = {
      time: new Date().toISOString(),
      level: lineLevel,
      msg,
      ...bindings,
      ...rest,
      ...(err !== undefined ? { err: serializeError(err) } : {}),
    };
    stream.write(`${JSON.stringify(entry)}\n`);
  };

  return {
    error: (msg, fields) => { write('error', msg, fields); },
    warn: (msg, fields) => { write('warn', msg, fields); },
    info: (msg, fields) => { write('info', msg, fields); },
    debug: (msg, fields) => { write('debug', msg, fields); },
    child: (extra) => createLogger({ level, stream, bindings: { ...bindings, ...extra } }),
  };
}
