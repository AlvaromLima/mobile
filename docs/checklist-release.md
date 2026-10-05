# Checklist de release (etapa 15)

Data: 2026-10-02
Versão: 1.0.0 (código 1), `br.com.itscs.tradutor`

## Evidências

- Gates: `flutter analyze` sem problemas; `flutter test` com 176 testes; backend `npm run check` com 83 testes.
- Builds: `app-debug.apk` (teste), `app-release.apk` (50,5 MB) e `app-release.aab` (49,2 MB).
- Assinatura: APK e AAB de release assinados pela chave de upload (`CN=ITS Customer Service, O=ITSCS, C=BR`, SHA-256 `2D:C1:1E:87:5D:D1:72:6A:23:54:03:50:98:E1:EF:E9:FC:6B:C1:19:AF:DD:19:52:6A:0B:7F:3A:81:7A:6C:AA`).
- Manifest de release: `targetSdk` 36, `compileSdk` 37, permissões `INTERNET` e `RECORD_AUDIO`, sem liberação de HTTP.
- Varredura do APK: nenhuma chave, nenhum endereço do Azure, nenhum endereço de desenvolvimento.
- Emulador Android 16 (API 36, Google Play): app de teste e de release instalados e abertos sem falha; tradução digitada contra o backend local (provider simulado); folha de idioma do microfone; permissão de microfone; escuta iniciada; leitura iniciada; compartilhar; tema escuro; ícone no lançador.
- Aparelho físico Samsung Galaxy A14 5G (Android 15), em 2026-10-05: APK de release (commit 4542b6a) instalado por arquivo, com o backend local em modo simulado exposto por túnel HTTPS temporário (Cloudflare) aberto só durante o teste. Validados: tradução digitada; microfone com Speech-to-Text em inglês e em espanhol, com tradução automática da fala; leitura em voz alta pt-BR (Ouvir). Na primeira tentativa de voz o reconhecedor do aparelho retornou erro uma vez; desde o commit 4542b6a o app mostra o código técnico de erros desconhecidos e mensagens próprias para falta de internet e reconhecedor ocupado.
- Os builds de release usaram a URL de validação `https://tradutor-api.invalid`, porque o backend ainda não está publicado. Servem para validar assinatura e configuração, não para distribuição.

## Itens

| Item | Status | Observação |
|---|---|---|
| Tradução Inglês → Português | PENDENTE | Fluxo validado com provider simulado e Azure simulado nos testes; falta testar com o Azure real (chave da TI) |
| Tradução Espanhol → Português | PENDENTE | Idem |
| Detecção automática | PENDENTE | Idem; lógica de detecção antes da tradução coberta por testes |
| Digitação | OK | Validada no emulador e no aparelho físico |
| Colar texto | OK | Testes de tela (inclui limite de caracteres) |
| Limpar | OK | Testes de tela |
| Copiar | OK | Testes de tela |
| Compartilhar | OK | Folha de compartilhamento do Android aberta no emulador |
| Microfone | OK | Permissão e escuta validadas no emulador e no aparelho físico |
| Speech-to-Text | OK | Inglês e espanhol validados no Samsung Galaxy A14 5G (Android 15) |
| Tradução da fala | OK | Fala reconhecida e enviada automaticamente ao backend no aparelho físico (provider simulado) |
| Text-to-Speech pt-BR | OK | Leitura em voz alta pt-BR validada no aparelho físico |
| Tema claro/escuro | OK | Validado no emulador (release) e em testes de vários tamanhos |
| Tratamento de erros | OK | Sem conexão, falha de leitura e ausência de fala exibidos sem travar no emulador |
| Backend protegido | OK | Revisão da etapa 14; orçamento de caracteres e rate limit |
| API Key protegida | OK | Só no backend; ausente do APK (varredura) |
| HTTPS | PENDENTE | App exige HTTPS em release; falta publicar o backend com TLS |
| Testes | OK | 176 no app e 83 no backend, sem APIs pagas |
| APK | OK | Teste e release gerados, assinados e executados no emulador e no aparelho físico |
| AAB | OK | Gerado e assinado com a chave de upload; envio à Play Store depende da URL de produção |

Nenhum item em ERRO.

## Pendências para publicação

1. Chave do Azure Translator F0 (TI) e teste real de tradução.
2. Hospedagem do backend com HTTPS e URL de produção; gerar novamente APK/AAB com `--dart-define=API_BASE_URL=<url>`.
3. Repetir o teste em aparelho físico com o Azure real (tradução de verdade) e com o backend publicado.
4. Backup do keystore e do `android/key.properties` no cofre da TI; ativar o Play App Signing.
5. Política de privacidade (microfone, Google/Apple/Microsoft) validada pelo jurídico.
6. Decisão sobre atestação do app (Firebase App Check).
7. iOS: build e teste exigem Mac com Xcode (não validados nesta máquina).
8. Ícone definitivo com a identidade visual da ITS, se desejado (o atual é provisório).
