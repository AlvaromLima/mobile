/**
 * Orçamento de caracteres em memória (serviço sem banco), complementar ao rate limit por requisição.
 *
 * Motivo: dentro do rate limit (30 req/min x 5.000 caracteres), um único cliente esgotaria
 * a cota mensal gratuita do provider em cerca de 13 minutos, deixando o serviço indisponível
 * para todos. O orçamento limita caracteres por cliente e no total do serviço.
 *
 * Janelas fixas; limite 0 desativa. Em várias instâncias, cada uma controla o próprio orçamento.
 */

export interface CharacterBudgetOptions {
  /** Caracteres por cliente (IP) por janela. 0 desativa. */
  perClientLimit: number;
  perClientWindowMs: number;
  /** Caracteres no total do serviço por janela. 0 desativa. */
  globalLimit: number;
  globalWindowMs: number;
  now?: () => number;
}

export type BudgetVerdict = 'ok' | 'client-exceeded' | 'global-exceeded';

interface Window {
  start: number;
  used: number;
}

/** Acima deste número de clientes, janelas vencidas são descartadas para limitar memória. */
const PRUNE_THRESHOLD = 10_000;

export function createCharacterBudget(options: CharacterBudgetOptions) {
  const now = options.now ?? Date.now;
  const clients = new Map<string, Window>();
  let global: Window = { start: now(), used: 0 };

  function current(window: Window | undefined, windowMs: number, at: number): Window {
    return window && at - window.start < windowMs ? window : { start: at, used: 0 };
  }

  function prune(at: number): void {
    if (clients.size < PRUNE_THRESHOLD) return;
    for (const [key, window] of clients) {
      if (at - window.start >= options.perClientWindowMs) clients.delete(key);
    }
  }

  return {
    /** Reserva `chars` para o cliente, se couber nos dois limites. Nada é consumido quando recusado. */
    consume(clientKey: string, chars: number): BudgetVerdict {
      const at = now();
      const globalWindow = current(global, options.globalWindowMs, at);
      const clientWindow = current(clients.get(clientKey), options.perClientWindowMs, at);

      if (options.perClientLimit > 0 && clientWindow.used + chars > options.perClientLimit) return 'client-exceeded';
      if (options.globalLimit > 0 && globalWindow.used + chars > options.globalLimit) return 'global-exceeded';

      prune(at);
      global = { start: globalWindow.start, used: globalWindow.used + chars };
      clients.set(clientKey, { start: clientWindow.start, used: clientWindow.used + chars });
      return 'ok';
    },
  };
}

export type CharacterBudget = ReturnType<typeof createCharacterBudget>;
