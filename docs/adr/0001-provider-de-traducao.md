# ADR 0001: Provider de tradução

Data: 2026-10-02
Status: aceito

## Contexto

O app traduz inglês e espanhol para português do Brasil, com detecção automática do idioma de origem. A chamada ao serviço de tradução passa pelo backend, que guarda a credencial. Requisito de custo: começar sem gasto.

## Alternativas avaliadas

| Opção | Cota gratuita | pt-BR | Detecção na mesma chamada | Observações |
|---|---|---|---|---|
| Azure AI Translator F0 | 2 milhões de caracteres por mês | Sim (`pt` = Brasil; `pt-PT` = Portugal) | Sim (omitir `from`) | Ao esgotar a cota, recusa (403001) em vez de cobrar |
| Google Cloud Translation | 500 mil caracteres por mês | Sim | Sim | Exige conta de faturamento; acima da cota cobra |
| DeepL API Free | 500 mil caracteres por mês (fontes divergentes) | Sim (`PT-BR`) | Sim | Disponibilidade de novas adesões e política de dados do plano gratuito não confirmadas |
| Google ML Kit (no aparelho) | Sem limite | Português genérico | Detecção separada | Elimina o backend; qualidade declarada como "casual" |

Fontes: páginas oficiais de preço e limites de cada fornecedor, consultadas em 2026-10-02.

## Decisão

Azure AI Translator, plano F0, chamado pelo backend via REST (Text Translation v3.0) com `fetch` nativo do Node, sem SDK.

## Consequências

- Custo zero dentro da cota; sem risco de cobrança surpresa no F0.
- No modo automático, detecção (`/detect`) e tradução (`/translate`) são chamadas separadas: o idioma é validado antes, e texto fora de `en`/`es` nunca é traduzido (exigência da especificação, etapa 8). A detecção avulsa não é cobrada por caracteres (resposta da Microsoft no Microsoft Q&A, consultada em 2026-10-02), então o desenho também evita gastar cota com idioma não suportado. Custo: uma chamada a mais, cerca de 150 a 300 ms, só no modo automático.
- O provider fica atrás da interface `TranslationProvider`; trocar de fornecedor afeta um arquivo e a configuração.
- Chave estática no backend (`TRANSLATION_API_KEY`), injetada por variável de ambiente ou secret manager. Deve ser rotacionada se houver suspeita de vazamento.

## Riscos

- Cota mensal e limite de 2 milhões de caracteres por hora do F0. Acima disso, o app recebe `QUOTA_EXCEEDED` até a renovação. Mitigação: rate limit por IP no backend e alerta de consumo no Azure.
- Detecção instável em textos muito curtos. Mitigação: o usuário pode escolher o idioma manualmente.
- Dependência de um recurso Azure gerido pela TI da ITS (pendente de criação em 2026-10-02).
