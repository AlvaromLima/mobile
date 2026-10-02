# Backend de tradução

Proxy seguro entre o app e o Azure Translator (plano F0). Guarda a credencial do provider, valida a entrada, limita a taxa de uso e padroniza erros. Não tem estado: sem banco, sem cache, sem sessão.

## Requisitos

- Node.js 24 ou superior
- Recurso Azure Translator (plano F0) com a chave disponível

## Execução local

```bash
npm ci
npm run dev   # lê .env se existir (nunca commitado; ver variáveis abaixo)
```

## Variáveis de ambiente

Em produção, injetar pelo secret manager do host. Localmente, um arquivo `.env` na pasta `backend/` (ignorado pelo git).

| Variável | Obrigatória | Padrão | Descrição |
|---|---|---|---|
| AZURE_TRANSLATOR_KEY | sim | | Chave do recurso Azure Translator (F0) |
| AZURE_TRANSLATOR_REGION | se o recurso for regional | | Ex.: brazilsouth. Vazia para recurso global |
| AZURE_TRANSLATOR_ENDPOINT | não | https://api.cognitive.microsofttranslator.com | Só https é aceito |
| PORT | não | 8080 | |
| HOST | não | 0.0.0.0 | |
| LOG_LEVEL | não | info | fatal, error, warn, info, debug, trace, silent |
| TRUST_PROXY | não | false | true, false ou número de proxies confiáveis à frente do serviço |
| RATE_LIMIT_MAX | não | 30 | Requisições por IP na janela |
| RATE_LIMIT_WINDOW_MS | não | 60000 | Janela do rate limit |

O serviço não sobe se alguma variável estiver ausente ou inválida. A mensagem de erro cita só o nome da variável, nunca o valor.

## Gates

```bash
npm run check   # lint + type-check + testes + build
```

## API

`POST /v1/translate`

```json
{ "text": "Hello, world", "sourceLang": "en" }
```

`sourceLang`: `en`, `es` ou `auto`. Texto com 1 a 5.000 caracteres e ao menos um caractere não branco.

Resposta 200:

```json
{ "translatedText": "Olá, mundo", "sourceLang": "en", "targetLang": "pt-BR" }
```

`sourceLang` na resposta é o idioma efetivo (informado ou detectado).

Erros seguem o formato `{ "error": { "code", "message", "requestId" } }`:

| Código | HTTP | Quando |
|---|---|---|
| VALIDATION_ERROR | 400 | Corpo inválido, texto vazio, idioma fora da lista, campo extra |
| NOT_FOUND | 404 | Rota inexistente |
| TEXT_TOO_LONG | 413 | Texto acima de 5.000 caracteres ou corpo acima de 32 KB |
| UNSUPPORTED_MEDIA_TYPE | 415 | Content-Type diferente de application/json |
| UNSUPPORTED_LANGUAGE | 422 | Detecção automática identificou idioma diferente de EN/ES |
| RATE_LIMITED | 429 | Limite por IP excedido (header Retry-After) |
| INTERNAL_ERROR | 500 | Erro inesperado |
| PROVIDER_UNAVAILABLE | 502 | Azure indisponível, credencial inválida ou resposta malformada |
| QUOTA_EXCEEDED | 503 | Cota gratuita do F0 esgotada (Azure 403001) |
| PROVIDER_TIMEOUT | 504 | Azure não respondeu em 7 s |

`GET /health`: liveness, sem chamar o Azure e fora do rate limit.

O header `X-Request-Id` é aceito se for UUID (caso contrário, é gerado) e sempre devolvido na resposta. O mesmo ID vai para o Azure como `X-ClientTraceId`.

## Segurança

- A chave do Azure existe apenas no ambiente do backend. Nunca no app nem no repositório.
- Logs registram idioma, tamanho do texto, duração e códigos de erro. Nunca o texto nem a tradução.
- No Azure, configurar alerta de consumo no recurso. No F0, ao esgotar a cota o serviço recusa requisições (403001) e não cobra.
- Atrás de load balancer, definir `TRUST_PROXY` com o número de proxies para que o rate limit use o IP real.
