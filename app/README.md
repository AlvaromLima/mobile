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
- Botão principal de microfone abaixo do campo de texto, com status: "Toque para falar", "Ouvindo..." (anel pulsando), "Processando..." e "Traduzindo...". O pulso é desligado quando o aparelho pede para reduzir movimento.
- Telas baixas (menos de 640 px de altura) usam microfone e campo menores para o TRADUZIR caber sem rolar; ao chegar a tradução, a tela rola até ela.
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

## Build Android

Ferramentas (instaladas fora do PATH):

| Ferramenta | Local |
|---|---|
| Flutter 3.47.6 | `C:\Users\Alvaro\development\flutter` |
| JDK 21 (Temurin) | `C:\Users\Alvaro\development\jdk\jdk-21.0.12.1+1` |
| Android SDK (plataforma 36, build-tools 36.0.0, NDK 28.2) | `C:\Users\Alvaro\development\android-sdk` |

O Flutter já está configurado (`flutter config --android-sdk ... --jdk-dir ...`).

### Chave de assinatura (upload key)

- Keystore: `C:\Users\Alvaro\development\keys\tradutor-upload.jks` (alias `upload`, RSA 4096, validade de 10.000 dias). Fora do repositório.
- Credenciais: `android/key.properties`, ignorado pelo git. Formato: `storeFile`, `keyAlias`, `storePassword`, `keyPassword`.
- Sem `key.properties`, o APK de release é assinado com a chave de debug (só para teste local) e o AAB falha de propósito.
- Backup obrigatório: o keystore e o `key.properties` devem ir para o cofre da TI. Sem eles não é possível publicar atualizações.
- Recomendado: ativar o Play App Signing no Play Console. A chave de assinatura final fica com o Google e esta passa a ser só a chave de upload, que pode ser substituída se for perdida.

### Comandos

APK de teste (debug, aponta para o backend local):

```bash
/c/Users/Alvaro/development/flutter/bin/flutter build apk --debug
```

APK release (exige URL HTTPS do backend publicado):

```bash
/c/Users/Alvaro/development/flutter/bin/flutter build apk --release --dart-define=API_BASE_URL=https://SEU-BACKEND
```

Android App Bundle para a Play Store (exige `key.properties`):

```bash
/c/Users/Alvaro/development/flutter/bin/flutter build appbundle --release --dart-define=API_BASE_URL=https://SEU-BACKEND
```

Saídas: `build/app/outputs/flutter-apk/app-debug.apk`, `build/app/outputs/flutter-apk/app-release.apk` e `build/app/outputs/bundle/release/app-release.aab`.

Para instalar um APK num celular Android por USB (depuração USB ativada):

```bash
/c/Users/Alvaro/development/android-sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Ícone e abertura

- Ícone provisório (símbolo de tradução sobre o azul do tema), gerado por `flutter test tool/generate_icons_test.dart`. Para trocar pela arte oficial, substituir os PNGs em `android/app/src/main/res/mipmap-*` e `ios/Runner/Assets.xcassets/AppIcon.appiconset`.
- Abertura: cor da superfície do tema (clara `#F9F9FF`, escura `#111318`) no Android e no iOS; no Android 12+ o sistema mostra o ícone sobre essa cor.

## Gates

```bash
/c/Users/Alvaro/development/flutter/bin/flutter analyze
/c/Users/Alvaro/development/flutter/bin/flutter test
```

Os testes não acessam a rede: o backend é simulado com `MockClient`.
