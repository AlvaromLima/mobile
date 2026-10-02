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

## Voz (Speech-to-Text)

- Reconhecimento nativo do aparelho via `speech_to_text`; permissões via `permission_handler`. Decisões em [ADR 0002](../docs/adr/0002-voz-stt-tts.md).
- No modo "Detectar automaticamente", o microfone pergunta o idioma da fala (inglês ou espanhol).
- O texto reconhecido aparece no campo "Texto original" enquanto a pessoa fala.
- Ao fim da fala, a tradução é disparada automaticamente pelo mesmo fluxo da tradução digitada (TranslatorNotifier, TranslationService, TranslationRepository e `POST /api/v1/translate`). Não existe endpoint nem serviço específico para voz.
- Teste de voz exige aparelho físico: o simulador iOS não reconhece fala, e emuladores Android dependem do microfone do computador e do app Google.
- iOS com CocoaPods: incluir `PERMISSION_MICROPHONE=1` e `PERMISSION_SPEECH_RECOGNIZER=1` no `post_install` do `ios/Podfile` (gerado no primeiro build num Mac).

## Leitura em voz alta (Text-to-Speech)

- Botão "Ouvir" na área "Português do Brasil", via `flutter_tts` com o motor nativo do aparelho, sempre em pt-BR. Durante a leitura o botão vira "Parar".
- Voz escolhida automaticamente: a melhor voz pt-BR que funciona sem internet (qualidade premium/enhanced no iOS; very high/high no Android).
- Textos acima de 3.900 caracteres são lidos em trechos (limite de 4.000 do Android), quebrando no fim das frases.
- A leitura para ao tocar no microfone, ao traduzir de novo, ao limpar e quando o app vai para segundo plano.
- Sem voz pt-BR instalada, o app orienta a instalar nas configurações de texto para fala do aparelho.
- iOS: a leitura toca mesmo com o aparelho no modo silencioso.

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
