# Tradutor (app Flutter)

App Android e iOS que traduz inglês e espanhol para português do Brasil, usando o backend em `../backend`.

## Arquitetura

```
Tela → TranslatorNotifier → TranslationService → BackendTranslationRepository → ApiClient → backend
```

- A tela não faz chamadas HTTP e não conhece a API externa.
- `TranslationService` valida a entrada (texto, limite, idiomas) e o idioma do resultado.
- `BackendTranslationRepository` chama `POST /api/v1/translate` e converte os erros do backend em falhas com mensagem amigável.
- `ApiClient` trata timeout, falta de conexão, falha de TLS e resposta inválida.

## URL do backend

Centralizada em `lib/core/config/app_config.dart`, definida no build por `--dart-define=API_BASE_URL=...`.

| Situação | URL usada |
|---|---|
| Debug sem `API_BASE_URL`, emulador Android | `http://10.0.2.2:8080` (backend na máquina de desenvolvimento) |
| Debug sem `API_BASE_URL`, simulador iOS | `http://localhost:8080` |
| Release | Obrigatório informar `API_BASE_URL` com HTTPS; caso contrário, o app não inicia |

HTTP sem TLS só é aceito em debug e apenas para endereços locais (Android: `network_security_config` do build de debug; iOS: `NSAllowsLocalNetworking`).

Aparelho Android físico via USB: com o backend rodando no computador, execute `adb reverse tcp:8080 tcp:8080` e use `API_BASE_URL=http://localhost:8080`.

## Executar

Flutter em `C:\Users\Alvaro\development\flutter` (fora do PATH). Dentro de `C:\mobile\app`:

```bash
/c/Users/Alvaro/development/flutter/bin/flutter run
```

Com backend publicado:

```bash
/c/Users/Alvaro/development/flutter/bin/flutter run --dart-define=API_BASE_URL=https://api.exemplo.com.br
```

## Gates

```bash
/c/Users/Alvaro/development/flutter/bin/flutter analyze
/c/Users/Alvaro/development/flutter/bin/flutter test
```

Os testes não acessam a rede: o backend é simulado com `MockClient`.
