# Rodar o tradutor no notebook de casa

Guia para usar o app no celular com a tradução real do Azure, tendo o backend no notebook pessoal (Windows). A chave do Azure fica só no notebook.

## Como funciona

```
Celular (app) --cabo USB--> notebook (backend Node, porta 8080) --internet--> Azure Translator
```

- O celular fala com o backend pelo cabo USB, usando o recurso `adb reverse` do Android. Não precisa de túnel, Wi-Fi compartilhado nem HTTPS.
- O app usado aqui é a versão de teste (debug), configurada para `http://localhost:8080`. Ela só funciona com o celular ligado ao notebook por cabo e com o backend rodando.

## O que instalar no notebook (uma vez)

1. Node.js 24: em nodejs.org, baixe o instalador da versão 24 (LTS) para Windows e instale com as opções padrão.
2. Git: em git-scm.com, baixe e instale com as opções padrão.
3. Android Platform-Tools: em developer.android.com/tools/releases/platform-tools, baixe "SDK Platform-Tools for Windows" e extraia o zip em `C:\platform-tools`. Não precisa instalar nada além disso; o `adb.exe` fica em `C:\platform-tools\adb.exe`.

Para conferir, abra o PowerShell e rode:

```powershell
node --version; git --version; C:\platform-tools\adb.exe version
```

O Node deve mostrar `v24` ou superior.

No PowerShell, use sempre `npm.cmd` em vez de `npm`. O Windows bloqueia o `npm` por política de scripts.

## Baixar o projeto (uma vez)

```powershell
cd $HOME; git clone https://github.com/AlvaromLima/mobile.git tradutor
```

Se o repositório for privado, o Git abre uma janela para entrar na conta do GitHub.

Depois, instale as dependências do backend:

```powershell
cd $HOME\tradutor\backend; npm.cmd ci
```

Para atualizar o projeto no futuro: `cd $HOME\tradutor; git pull` e, em seguida, `npm.cmd ci` dentro de `backend`.

## Configurar a chave do Azure (uma vez)

1. No portal do Azure, abra o recurso Translator, vá em "Chaves e Ponto de Extremidade" e copie a CHAVE 1. Anote também a região, por exemplo `brazilsouth`.
2. Crie o arquivo `.env` na pasta do backend:

```powershell
notepad $HOME\tradutor\backend\.env
```

O Bloco de Notas pergunta se quer criar o arquivo; confirme. Cole o conteúdo abaixo, trocando `COLE_A_CHAVE_AQUI` pela chave:

```
TRANSLATION_PROVIDER=azure
TRANSLATION_API_KEY=COLE_A_CHAVE_AQUI
TRANSLATION_API_REGION=brazilsouth
HOST=127.0.0.1
PORT=8080
```

3. Salve e feche. Confira que o nome ficou `.env` e não `.env.txt`: no Explorador de Arquivos, ative "Exibir > Extensões de nomes de arquivos".

Cuidados com a chave:

- O `.env` não vai para o GitHub (está no `.gitignore`). Nunca renomeie nem copie a chave para outro arquivo do projeto.
- Não envie a chave por chat, WhatsApp ou e-mail.
- `HOST=127.0.0.1` faz o backend aceitar conexões só do próprio notebook (e do celular via cabo). Se o Windows perguntar sobre o firewall, pode negar o acesso de rede.
- Se a chave vazar, gere outra no portal ("Regenerar Chave 1") e atualize o `.env`. No plano F0 não há cobrança: ao atingir 2 milhões de caracteres no mês, a tradução para até o mês seguinte.

## Testar o backend

```powershell
cd $HOME\tradutor\backend; npm.cmd run dev
```

A linha `"servidor iniciado"` deve mostrar `"provider":"azure"`. Deixe essa janela aberta e, em outra janela do PowerShell, rode:

```powershell
Invoke-RestMethod -Method Post -Uri http://localhost:8080/api/v1/translate -ContentType 'application/json' -Body '{"text":"Good morning","sourceLanguage":"en"}'
```

O campo `translatedText` deve vir com "Bom dia". Teste também espanhol (`"text":"Buenos días","sourceLanguage":"es"`) e detecção automática (`"sourceLanguage":"auto"`).

Se aparecer erro de chave inválida, confira a chave e a região no `.env` e reinicie o backend (Ctrl+C na janela e `npm.cmd run dev` de novo).

## Gerar o APK de teste (uma vez)

O notebook não precisa ter Flutter. Gere o APK na máquina de Santo Amaro, pelo VNC, numa janela do PowerShell (tudo numa linha só):

```powershell
$env:GRADLE_OPTS="-Dorg.gradle.daemon=false"; $env:ANDROID_HOME="C:\Users\Alvaro\development\android-sdk"; $env:JAVA_HOME="C:\Users\Alvaro\development\jdk\jdk-21.0.12.1+1"; $env:JAVA_TOOL_OPTIONS="-Djavax.net.ssl.trustStoreType=Windows-ROOT"; cd C:\mobile\app; git pull; C:\Users\Alvaro\development\flutter\bin\flutter.bat pub get; C:\Users\Alvaro\development\flutter\bin\flutter.bat build apk --debug --dart-define=API_BASE_URL=http://localhost:8080
```

O arquivo sai em `C:\mobile\app\build\app\outputs\flutter-apk\app-debug.apk` (cerca de 160 MB). Envie pelo WhatsApp Web.

Este APK aponta para `localhost`, então não precisa ser gerado de novo ao trocar a chave ou reiniciar o backend. Só é preciso gerar outro quando o app mudar.

## Preparar o celular (uma vez)

1. Ative a depuração USB: Configurações > Sobre o telefone > Informações do software, toque 7 vezes em "Número de compilação"; depois Configurações > Opções do desenvolvedor > ative "Depuração USB".
2. Desinstale a versão anterior do Tradutor (a que usava o túnel). Ela foi assinada com outra chave e impede a instalação da versão de teste.
3. Instale o `app-debug.apk` pelo WhatsApp, como da outra vez ("Instalador de pacote" e, se o Play Protect avisar, "Instalar mesmo assim").

## Uso no dia a dia

1. Ligue o celular no notebook pelo cabo USB. Na primeira vez, aceite "Permitir depuração USB" no celular e marque "Sempre permitir".
2. No PowerShell, confira o celular e faça a ponte da porta 8080:

```powershell
C:\platform-tools\adb.exe devices; C:\platform-tools\adb.exe reverse tcp:8080 tcp:8080
```

O celular deve aparecer como `device`. Se aparecer `unauthorized`, desbloqueie a tela e aceite o aviso.

3. Inicie o backend e deixe a janela aberta:

```powershell
cd $HOME\tradutor\backend; npm.cmd run dev
```

4. Abra o Tradutor no celular e use normalmente.

O `adb reverse` precisa ser refeito sempre que o cabo for reconectado ou o celular reiniciar.

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| App mostra "Sem conexão" | Ponte USB desfeita ou backend parado | Rodar `adb reverse` de novo e conferir a janela do backend |
| `adb devices` não lista o celular | Cabo só de carga ou depuração desativada | Trocar o cabo, conferir a depuração USB e aceitar o aviso no celular |
| Instalação falha com "app em conflito" ou "não instalado" | Versão anterior com outra assinatura | Desinstalar o Tradutor antigo e instalar de novo |
| Backend mostra `"provider":"mock"` | `.env` não lido | Conferir o nome `.env` (sem `.txt`) dentro de `backend` |
| Aviso de cota esgotada | Limite do F0 ou do orçamento diário do backend | Aguardar a renovação (o backend limita 64 mil caracteres por dia) |
| Erro no reconhecimento de voz com código | Reconhecedor do aparelho | Tentar de novo; se repetir, anotar o código mostrado |

## Encerrar

Feche a janela do backend (Ctrl+C) e desconecte o cabo. Nada fica exposto na internet: o backend só aceita conexões do próprio notebook.
