# Tarefas para o agente (Gemini 3.8 Flash no Xcode)

## Por que estas tarefas existem

Diagnóstico feito em 12/10/2026 com dados reais do curador (`curator/.state/review`, 219 candidatos) e do app:

| Problema | Evidência |
|---|---|
| Feed mostra aula de professor de inglês | O app pesquisa `"English conversation beginner"`, `"easy English"`, `"intermediate listening"`; o feed cai nessa busca porque o catálogo está vazio |
| Catálogo vazio | 0 publicados; 219 esperando revisão manual |
| Nível errado para conteúdo nativo | 210 de 219 (96%) classificados "avançado" por uma régua absoluta de velocidade |
| Curador sem tempo por palavra | A lib `youtube-transcript` descarta `tOffsetMs`: 0 de 219 com `hasWordTiming` |
| Legenda automática sem pontuação | 126 de 219 sem `.?!` → corte no meio da frase ("rather than kind / of be tired") |
| Frases longas ou curtas demais | Corte guloso: mediana 12 palavras / 3,5 s, p90 17 palavras / 5,7 s; 44% das frases com tempo estimado (≈) |

Decisões do dono do projeto: **só regras locais** (sem IA em produção), **publicação automática com amostragem**, **feed só do catálogo curado**.

## Como usar no Xcode 27

1. *Xcode → Settings → Intelligence*: entre com a conta Google e escolha **Gemini 3.8 Flash** (`gemini-3.8-flash`).
2. Abra `ShadowingNative.xcodeproj`. O `AGENTS.md` da pasta do projeto contém as regras.
3. Para cada tarefa, abra uma **conversa nova** no painel de código e peça:

   > Leia AGENTS.md e execute docs/agent-tasks/01-feed-so-catalogo.md. Rode scripts/verify.sh e atualize docs/agent-tasks/STATUS.md.

4. Revise o diff (*Source Control* ou `git diff`) e faça o commit antes da próxima tarefa.
5. Se o agente não ler o `AGENTS.md` sozinho, comece o pedido com "Leia AGENTS.md primeiro".

Fora do Xcode, o Gemini CLI na pasta `Shadowing Native/` carrega as mesmas regras via `GEMINI.md`.

## Ordem

| # | Tarefa | Depende de | Dificuldade |
|---|---|---|---|
| 01 | [Feed só do catálogo](01-feed-so-catalogo.md) | n/a | baixa |
| 02 | [Filtro de conteúdo de aula](02-filtro-conteudo-de-aula.md) | n/a | baixa |
| 03 | [Curador: legenda json3 com tempo por palavra](03-curador-legenda-json3.md) | n/a | média |
| 04 | [Curador: alinhar legenda manual com a automática](04-curador-alinhamento.md) | 03 | média |
| 05 | [Curador: segmentação ótima](05-curador-segmentacao-dp.md) | 04 | média |
| 06 | [Catálogo v2](06-catalogo-v2.md) | 05 | média |
| 07 | [App: mesma segmentação no Swift](07-app-segmentacao-paridade.md) | 05, 06 | média |
| 08 | [Nível relativo ao conteúdo nativo](08-nivel-relativo.md) | 05 | **alta** |
| 09 | [Recalibrar nível pelo uso](09-recalibracao-feedback.md) | 08 | média |
| 10 | [Ajudas para o iniciante](10-ajudas-iniciante.md) | 06, 08 | média |
| 11 | [Publicação automática com amostragem](11-publicacao-automatica.md) | 02, 06, 08 | **alta** |
| 12 | [Reprocessar a fila de 219](12-reprocessar-fila.md) | 03–08, 11 | média |
| 13 | [Uploads de canal via playlist de Shorts](13-descoberta-uushorts.md) | 11 | baixa |
| 14 | [Descoberta automática de canais](14-descoberta-canais-automatica.md) | 02, 11, 13 | **alta** |

As tarefas 01 e 02 já resolvem o "professor de inglês" no app. As de 03 a 12 enchem o feed com os 219 Shorts nativos já coletados (Team Coco, SubwayTakes, Ringer, StarTalk…). As 13 e 14 aumentam o volume. Nas tarefas de dificuldade alta, se o Flash travar, use um modelo maior.

## Depois das tarefas (só o usuário)

- `cd curator && npm run scan:configured` / `publish:configured`, que usam as credenciais do Mac.
- Deploy de `firestore.rules`, se a tarefa 09 o alterar: `firebase deploy --only firestore:rules`.
- Teste no iPhone físico.
