# Backend de tradução

API Express + TypeScript entre o app e o serviço de tradução. Protege a credencial do provider, valida a entrada, limita a taxa de uso e padroniza erros. Não tem estado: sem banco, sem cache, sem sessão.

Nesta etapa (5) o endpoint usa um provider simulado. A integração real com o Azure Translator F0 entra na etapa 6.

## Requisitos

- Node.js 24 ou superior (TypeScript executado nativamente em desenvolvimento e testes)

## Execução local

```bash
npm ci
npm run dev
```

O servidor sobe em `http://localhost:8080`. O script `dev` carrega o arquivo `.env` da pasta `backend/`, se existir.

## Arquivo .env

O `.env` nunca é commitado (está no `.gitignore`). Em produção, as variáveis vêm do secret manager do host. Modelo para criar o `.env` local:

```dotenv
PORT=8080
HOST=0.0.0.0
LOG_LEVEL=info
TRUST_PROXY=false
RATE_LIMIT_MAX=30
RATE_LIMIT_WINDOW_MS=60000
CORS_ORIGINS=
TRANSLATION_TIMEOUT_MS=10000
```

| Variável | Padrão | Descrição |
|---|---|---|
| PORT | 8080 | Porta HTTP |
| HOST | 0.0.0.0 | Interface de rede |
| LOG_LEVEL | info | error, warn, info, debug ou silent |
| TRUST_PROXY | false | true, false ou número de proxies à frente do serviço (ex.: 1 atrás de load balancer) |
| RATE_LIMIT_MAX | 30 | Requisições por IP na janela |
| RATE_LIMIT_WINDOW_MS | 60000 | Janela do rate limit |
| CORS_ORIGINS | vazio | Origens web autorizadas, separadas por vírgula. Vazio bloqueia todas. O app mobile não depende de CORS |
| TRANSLATION_TIMEOUT_MS | 10000 | Tempo máximo da chamada ao provider |

O serviço não sobe se alguma variável estiver inválida. A mensagem cita só o nome da variável, nunca o valor.

## Endpoint

`POST /api/v1/translate`

Entrada (`Content-Type: application/json`):

```json
{
  "text": "Good morning",
  "sourceLanguage": "en",
  "targetLanguage": "pt-BR"
}
```

- `text`: obrigatório, 1 a 5.000 caracteres, ao menos um caractere não branco.
- `sourceLanguage`: `auto`, `en` ou `es`.
- `targetLanguage`: opcional; se enviado, deve ser `pt-BR`.
- Campos extras são recusados.

Saída 200:

```json
{
  "success": true,
  "detectedLanguage": "en",
  "sourceLanguage": "en",
  "targetLanguage": "pt-BR",
  "originalText": "Good morning",
  "translatedText": "Bom dia"
}
```

`sourceLanguage` na saída é o idioma efetivo. Com `auto`, `detectedLanguage` é o idioma identificado; com idioma informado, repete o informado.

Erros:

```json
{
  "success": false,
  "error": { "code": "VALIDATION_ERROR", "message": "O campo text é obrigatório.", "requestId": "..." }
}
```

| Código | HTTP | Quando |
|---|---|---|
| VALIDATION_ERROR | 400 | Corpo inválido, JSON malformado, texto vazio, idioma fora da lista, campo extra |
| NOT_FOUND | 404 | Rota inexistente |
| TEXT_TOO_LONG | 413 | Texto acima de 5.000 caracteres ou corpo acima de 32 KB |
| UNSUPPORTED_MEDIA_TYPE | 415 | Content-Type diferente de application/json |
| UNSUPPORTED_LANGUAGE | 422 | Detecção identificou idioma diferente de inglês ou espanhol |
| RATE_LIMITED | 429 | Limite por IP excedido (header Retry-After) |
| INTERNAL_ERROR | 500 | Erro inesperado |
| PROVIDER_UNAVAILABLE | 502 | Provider indisponível ou resposta inesperada |
| QUOTA_EXCEEDED | 503 | Cota do provider esgotada |
| PROVIDER_TIMEOUT | 504 | Provider não respondeu dentro de TRANSLATION_TIMEOUT_MS |

`GET /health`: liveness, sem chamar o provider e fora do rate limit.

O header `X-Request-Id` é aceito se for UUID (caso contrário, é gerado) e sempre devolvido na resposta. Use-o para localizar a requisição nos logs.

## Testar o endpoint

Com o servidor rodando (`npm run dev`):

```bash
curl -s -X POST http://localhost:8080/api/v1/translate -H "Content-Type: application/json" -d '{"text":"Good morning","sourceLanguage":"en","targetLanguage":"pt-BR"}'
```

No PowerShell:

```powershell
Invoke-RestMethod -Method Post -Uri http://localhost:8080/api/v1/translate -ContentType 'application/json' -Body '{"text":"Good morning","sourceLanguage":"auto","targetLanguage":"pt-BR"}'
```

## Gates

```bash
npm run check   # lint + type-check + testes + build
```

## Estrutura

```
src/
  config/        variáveis de ambiente validadas
  controllers/   orquestra validação, serviço e resposta
  routes/        /api/v1/translate e /health
  services/      regras de tradução, detecção e timeout
  providers/     interface TranslationProvider e implementações
  middlewares/   requestId e log, CORS, rate limit, erros
  validators/    validação da entrada
  types/         contrato da API
  utils/         logger e AppError
```

## Segurança

- Credenciais do provider existem apenas no ambiente do backend. Nunca no app nem no repositório.
- Helmet (headers de segurança), X-Powered-By desativado, CORS fechado por padrão.
- Limite de corpo de 32 KB e de 5.000 caracteres por texto.
- Timeouts: provider (TRANSLATION_TIMEOUT_MS), requisição HTTP (30 s) e headers (15 s).
- Logs em JSON com requestId, método, caminho, status e duração. Nunca registram o texto, a tradução, a query string ou o IP.
