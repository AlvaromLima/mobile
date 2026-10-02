import { buildApp } from './app.ts';
import { ConfigError, loadConfig } from './config/env.ts';

let config;
try {
  config = loadConfig();
} catch (error) {
  // Mensagem de configuração nunca contém o valor dos segredos, apenas o nome da variável.
  console.error(error instanceof ConfigError ? `Configuração inválida: ${error.message}` : error);
  process.exit(1);
}

const app = await buildApp({ config });

const shutdown = (signal: string) => {
  app.log.info({ signal }, 'encerrando');
  app.close().then(
    () => process.exit(0),
    (error: unknown) => {
      app.log.error({ err: error }, 'falha no encerramento');
      process.exit(1);
    },
  );
};
process.once('SIGTERM', () => { shutdown('SIGTERM'); });
process.once('SIGINT', () => { shutdown('SIGINT'); });

await app.listen({ port: config.port, host: config.host });
