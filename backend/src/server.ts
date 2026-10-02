import { buildApp } from './app.ts';
import { ConfigError, loadConfig } from './config/env.ts';
import { createLogger } from './utils/logger.ts';

let config;
try {
  config = loadConfig();
} catch (error) {
  console.error(error instanceof ConfigError ? `Configuração inválida: ${error.message}` : error);
  process.exit(1);
}

const logger = createLogger({ level: config.logLevel });
const app = buildApp({ config, logger });

if (process.env.NODE_ENV === 'production' && config.trustProxy === false) {
  // Atrás de load balancer sem TRUST_PROXY, todos os clientes compartilham o IP do proxy:
  // o rate limit e o orçamento de caracteres passariam a valer para todos juntos.
  logger.warn('TRUST_PROXY=false em produção: defina o número de proxies à frente do serviço');
}

const server = app.listen(config.port, config.host, () => {
  // Registra só o nome do provider; a configuração completa contém a chave e nunca é logada.
  logger.info('servidor iniciado', { host: config.host, port: config.port, provider: config.translation.provider });
});
// Timeouts do servidor HTTP contra conexões lentas (slowloris) e requisições penduradas.
server.requestTimeout = 30_000;
server.headersTimeout = 15_000;

const shutdown = (signal: string) => {
  logger.info('encerrando', { signal });
  server.close((error) => {
    if (error) logger.error('falha no encerramento', { err: error });
    process.exit(error ? 1 : 0);
  });
  // Força a saída se conexões não fecharem a tempo.
  setTimeout(() => process.exit(1), 10_000).unref();
};
process.once('SIGTERM', () => { shutdown('SIGTERM'); });
process.once('SIGINT', () => { shutdown('SIGINT'); });
