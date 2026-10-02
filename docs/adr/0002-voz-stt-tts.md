# ADR 0002: Voz (Speech-to-Text, Text-to-Speech e permissões)

Data: 2026-10-02
Status: aceito (pendente: comportamento da voz no modo "Detectar automaticamente")

## Contexto

O app precisa capturar fala em inglês ou espanhol, convertê-la em texto, traduzir pelo fluxo já existente (TranslationService, TranslationRepository e backend) e ler a tradução em português do Brasil. Sem backend novo para voz e sem endpoint específico (etapa 11 da especificação). Projeto em Flutter 3.47.6 e Dart 3.13.5, Android e iOS.

## Pacotes avaliados

Dados do pub.dev consultados em 2026-10-02.

| Pacote | Versão | Publicado | SDK Dart | Publisher | Likes | Pontos | Downloads 30 dias | Situação |
|---|---|---|---|---|---|---|---|---|
| speech_to_text | 7.5.0 | 2026-09-14 | ^3.12.0 | csdcorp.com (verificado) | 1.622 | 150/160 | 614.977 | Escolhido para STT |
| flutter_tts | 4.2.5 | 2026-01-05 | >=3.4.0 <4.0.0 | eyedeadevelopment.com (verificado) | 1.601 | 150/160 | 431.330 | Escolhido para TTS |
| permission_handler | 13.0.2 | 2026-09-04 | ^3.6.0 | baseflow.com (verificado) | 6.014 | 160/160 | 3.502.042 | Escolhido para permissões |
| text_to_speech | 0.2.3 | 2021-07-27 | <3.0.0 | sem publisher | 150 | 150/160 | 339 | Descartado: incompatível com Dart 3 e sem manutenção |
| vosk_flutter | 0.3.48 | 2023-04-07 | <3.0.0 | sem publisher | 24 | 110/160 | 853 | Descartado: incompatível com Dart 3, sem iOS |
| sherpa_onnx | 1.13.8 | 2026-09-11 | >=3.2.0 | sem publisher | 121 | 140/160 | 59.115 | Descartado: STT offline exige modelos de dezenas a centenas de MB por idioma |

Compatibilidade verificada com `flutter pub add speech_to_text flutter_tts permission_handler --dry-run`: resolução sem conflito com as dependências atuais.

STT em nuvem (ex.: Azure Speech, com identificação automática de idioma pelo áudio) foi descartado: exigiria enviar áudio a um endpoint novo no backend, contrariando a especificação, além de custo e exposição de dados maiores.

## Decisão

- Speech-to-Text: `speech_to_text`, que usa o reconhecedor nativo do sistema (Android SpeechRecognizer, iOS SFSpeechRecognizer). Sem custo, sem backend novo.
- Text-to-Speech: `flutter_tts`, com o motor nativo do sistema e voz pt-BR.
- Permissões: `permission_handler`, necessário para distinguir "negada" de "negada permanentemente" e abrir as configurações do app. O `speech_to_text` sozinho apenas informa se tem ou não permissão.
- Abstrações `SpeechRecognitionService` e `TextToSpeechService` isolam os pacotes: a tela e o controller não dependem deles, e os testes usam implementações falsas.
- O texto reconhecido entra no mesmo fluxo da tradução digitada (`TranslatorNotifier.translate`), sem duplicar lógica nem criar endpoint.

## Configuração nativa necessária (etapas 10 e 12)

Android:
- `RECORD_AUDIO` no manifest.
- `<queries>` com `android.speech.RecognitionService` (STT) e `android.intent.action.TTS_SERVICE` (TTS), exigidos a partir do Android 11.
- compileSdk 35 (exigência do permission_handler), minSdk 21 ou superior.
- As permissões de Bluetooth sugeridas pelo speech_to_text servem só para fones Bluetooth e não serão incluídas (menor privilégio).

iOS:
- `NSMicrophoneUsageDescription` e `NSSpeechRecognitionUsageDescription` no Info.plist, com textos em pt-BR.
- Macros `PERMISSION_MICROPHONE=1` e `PERMISSION_SPEECH_RECOGNIZER=1` no Podfile (permission_handler).
- Sessão de áudio: parar a leitura antes de iniciar a escuta (conflito de sessão no iOS).

## Consequências e limitações conhecidas

- iOS encerra reconhecimentos com mais de 1 minuto; Android encerra após pausa curta (até cerca de 5 s, varia por aparelho). Tratado como fim da fala.
- Android emite sons de início e fim de escuta; não é configurável.
- Privacidade: o reconhecimento pode ser processado pelos serviços do Google (Android) ou da Apple (iOS), salvo quando o aparelho suporta reconhecimento local. Deve constar na política de privacidade das lojas.
- Aparelhos Android sem os serviços de reconhecimento do Google (ex.: alguns modelos sem Google Play) não terão STT; o app mostra "Reconhecimento de voz indisponível".
- Voz pt-BR depende do motor de TTS do aparelho; sem ela, o app orienta a instalação.
- Simulador iOS não reconhece fala; teste de voz exige aparelho físico.

## Pendente

Reconhecedores nativos exigem o idioma antes de ouvir e não detectam o idioma pelo áudio. Falta definir o comportamento do microfone com "Detectar automaticamente" selecionado (ver relatório da etapa 9).
