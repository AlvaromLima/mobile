# Revisão de segurança e testes (etapa 14)

Data: 2026-10-02
Escopo: backend (`backend/src`) e app Flutter (`app/lib`, manifest Android, Info.plist iOS), no commit `e1202ca`.
Método: leitura do código, `npm audit`, consulta à base OSV (osv.dev) para os 85 pacotes do `pubspec.lock`, busca por segredos e logs, e auditoria `its-security-review`.

## Evidências gerais

| Verificação | Resultado |
|---|---|
| `npm audit` (backend, todas as dependências) | 0 vulnerabilidades |
| OSV para os 85 pacotes Dart/Flutter | 0 vulnerabilidades conhecidas |
| Chaves, senhas ou tokens no app (`lib`, manifest, Info.plist) | Nenhum |
| `.env` em qualquer commit do histórico | Nenhum |
| `print`/`debugPrint`/logs no app | Nenhum |
| Texto do usuário ou tradução nos logs do backend | Nenhum (coberto por teste) |
| Stack trace ou detalhe do provider na resposta | Nenhum (coberto por teste) |
| Testes chamando APIs pagas | Nenhum; agora bloqueado por guarda de rede no backend |

## Achados

### CRÍTICO

Nenhum.

### ALTO

| # | Achado | Evidência | Situação |
|---|---|---|---|
| A1 | Um único cliente esgota a cota mensal gratuita do Azure em cerca de 13 minutos sem violar o rate limit (30 req/min x 5.000 caracteres = 150 mil caracteres/min contra 2 milhões/mês). O serviço fica indisponível para todos até a renovação. | `backend/src/app.ts:51`, `backend/src/middlewares/rate-limit.ts` | Corrigido: orçamento de caracteres por cliente (20 mil/hora) e global (64 mil/dia), configurável |
| A2 | Build de release do Android assinado com a chave de debug. Impede publicação na Play Store e não garante a cadeia de atualizações. | `app/android/app/build.gradle.kts:36` | Pendente: etapa 15 (configuração de release), exige criar e guardar o keystore |

### MÉDIO

| # | Achado | Evidência | Situação |
|---|---|---|---|
| M1 | Endpoint público sem atestação do app: qualquer pessoa que extraia a URL do APK pode chamar a API. Mitigado por rate limit e orçamento de caracteres. | `backend/src/routes/translate.routes.ts` | Pendente de decisão: Firebase App Check (Play Integrity / App Attest) antes da publicação nas lojas |
| M2 | Atrás de load balancer sem `TRUST_PROXY`, todos os clientes compartilham o IP do proxy e o mesmo limite. | `backend/src/app.ts:43`, `backend/src/config/env.ts` | Corrigido: aviso no log de inicialização em produção; documentado no README |
| M3 | O backend escuta HTTP; HTTPS depende da hospedagem (TLS no load balancer). O header HSTS já é enviado. | `backend/src/server.ts` | Pendente: definição da hospedagem (decisão 5 do plano) |
| M4 | Privacidade: o áudio pode ser processado por Google (Android) ou Apple (iOS), e o texto é enviado à Microsoft (Azure). As lojas exigem política de privacidade para uso de microfone. | `docs/adr/0002-voz-stt-tts.md` | Pendente: política de privacidade com validação do jurídico (LGPD) |

### BAIXO

| # | Achado | Evidência | Situação |
|---|---|---|---|
| B1 | Imagem Docker sem `HEALTHCHECK`. | `backend/Dockerfile` | Corrigido |
| B2 | Imagem base com tag flutuante (`node:24-alpine`). | `backend/Dockerfile:2,11` | Aceito por ora; fixar digest no pipeline de build |
| B3 | iOS: `NSAllowsLocalNetworking` também vale no release. O app já exige HTTPS em release, então o efeito é nulo para o backend. | `app/ios/Runner/Info.plist` | Aceito |
| B4 | `X-Request-Id` enviado pelo cliente é aceito (somente UUID), o que permite ao cliente escolher o ID de correlação. | `backend/src/middlewares/request-context.ts:14` | Aceito: formato validado, sem risco de injeção em log |
| B5 | `.env.example` ausente (regras de permissão desta máquina bloqueiam arquivos `.env*`). O modelo está no README. | `backend/README.md` | Pendente: criar manualmente ou liberar a regra |

## Itens verificados sem achado

Backend: chave apenas em variável de ambiente e somente no header da chamada ao Azure; mensagens de configuração sem valores; CORS fechado por padrão; Helmet e `X-Powered-By` desativado; rate limit por IP antes do parse do corpo; validação estrita (campos extras, tipos, `__proto__`, JSON malformado, Content-Type); limite de 5.000 caracteres e 32 KB; timeouts do provider (10 s), da requisição (30 s) e dos headers (15 s); erros sempre no contrato, sem stack trace; contêiner sem root e com `NODE_ENV=production`.

App: nenhuma credencial; URL do backend centralizada e HTTPS obrigatório em release; HTTP local só no build de debug (Android) e rede local (iOS); permissões mínimas (`INTERNET`, `RECORD_AUDIO`, sem Bluetooth); falhas de rede, servidor, voz e leitura tratadas sem fechar o app; nenhum log.

## Matriz de testes exigidos

Nenhum teste usa APIs pagas: o backend usa provider e Azure simulados (com guarda de rede), e o app usa `MockClient` e dublês de voz.

| Caso | Backend | App |
|---|---|---|
| Inglês para português | `azure.integration.test.ts`: inglês informado; `translation.service.test.ts` | `backend_test.dart`: sucesso do backend; `voice_screen_test.dart`: inglês no modo automático |
| Espanhol para português | `azure.integration.test.ts`: espanhol informado e automático | `voice_screen_test.dart`: espanhol no modo automático |
| Detecção automática | `translation.service.test.ts`, `azure.integration.test.ts` (inclui idioma não suportado sem tradução) | `home_screen_test.dart`, `voice_screen_test.dart` |
| Texto vazio | `translate.routes.test.ts` (vazio e só espaços) | `translation_service_test.dart`, `home_screen_test.dart` |
| Texto muito grande | `translate.routes.test.ts` (5.001 caracteres e corpo acima de 32 KB) | `translation_service_test.dart`, `home_screen_test.dart` (colar acima do limite) |
| API externa indisponível | `azure-translation.provider.test.ts`, `azure.integration.test.ts` (5xx após retry, credencial inválida, cota) | `backend_test.dart` (502 sem JSON, falha de conexão), `home_screen_test.dart` (backend fora do ar) |
| Timeout | `translation.service.test.ts`, `azure-translation.provider.test.ts`, `translate.routes.test.ts` (504) | `backend_test.dart` (TimeoutFailure) |
| Speech-to-Text | não se aplica | `speech_service_test.dart`, `voice_input_test.dart`, `voice_screen_test.dart`, `voice_ui_test.dart` |
| Text-to-Speech | não se aplica | `tts_service_test.dart`, `tts_screen_test.dart` |
