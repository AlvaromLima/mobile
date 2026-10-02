/**
 * Carregado antes de cada arquivo de teste (node --import): bloqueia qualquer acesso de rede
 * que não seja o servidor local dos próprios testes. Garante que nenhum teste chame APIs pagas.
 */
const realFetch = globalThis.fetch;
const LOCAL_HOSTS = new Set(['127.0.0.1', 'localhost', '[::1]']);

globalThis.fetch = (input: string | URL | Request, init?: RequestInit) => {
  const url = new URL(input instanceof Request ? input.url : String(input));
  if (!LOCAL_HOSTS.has(url.hostname)) {
    return Promise.reject(new Error(`Teste tentou acessar a rede externa (${url.host}); use um fetch falso.`));
  }
  return realFetch(input, init);
};
