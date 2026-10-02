import type { Logger } from '../utils/logger.ts';

declare global {
  namespace Express {
    interface Locals {
      /** UUID da requisição, devolvido no header X-Request-Id. */
      requestId: string;
      /** Logger já vinculado ao requestId. */
      log: Logger;
    }
  }
}

export {};
