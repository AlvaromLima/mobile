/** Dublês do Azure Translator para testes (sem rede). */

export type Responder = (url: string, init: RequestInit) => Promise<Response>;

export function azureJson(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

export function azureOk(text: string, detected?: string): Response {
  return azureJson(200, [
    { ...(detected ? { detectedLanguage: { language: detected, score: 1 } } : {}), translations: [{ text, to: 'pt' }] },
  ]);
}

/** fetch falso que consome uma resposta por chamada. */
export function fakeFetch(...responders: Responder[]) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fn = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = input instanceof Request ? input.url : String(input);
    calls.push({ url, init: init ?? {} });
    const responder = responders[calls.length - 1];
    if (!responder) throw new Error('chamada inesperada');
    return responder(url, init ?? {});
  }) as typeof fetch;
  return { fn, calls };
}

/** Responde só quando a requisição é abortada (simula Azure travado). */
export const hang: Responder = (_url, init) =>
  new Promise((_resolve, reject) => {
    init.signal?.addEventListener('abort', () => { reject(init.signal?.reason as Error); });
  });
