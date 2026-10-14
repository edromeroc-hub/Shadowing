# Tarefas do Caminho A (curador automático)

> Há **dois caminhos** que publicam no mesmo catálogo:
> - **Caminho A (estas tarefas):** melhorar o programa `curator/`, que roda sozinho no Mac com regras locais.
> - **Caminho B:** o **Gemini no Antigravity é o curador**. Ele busca, avalia, define o nível, divide as frases e revisa. Veja [`curadoria-gemini/README.md`](../../curadoria-gemini/README.md) e use `/curar-shorts`.
>
> Os dois são independentes; dá para usar o B hoje, enquanto o A é melhorado.

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

Decisões do dono do projeto para o Caminho A: **só regras locais**, **publicação automática com amostragem**, **feed só do catálogo curado**.

## Como usar no Antigravity

1. Abra a pasta **`Shadowing Native/`** como workspace. O Antigravity lê o `AGENTS.md` sozinho.
2. Escolha o modelo **Gemini 3.8 Flash**. Nas tarefas marcadas **alta**, se ele travar, troque por um modelo Pro.
3. No chat do agente, digite:

   > /proxima-tarefa

   O agente pega a próxima tarefa pendente cujas dependências estão feitas, executa, roda `scripts/verify.sh` e atualiza o `STATUS.md`. Para escolher uma tarefa específica: `/proxima-tarefa 05`.
4. Revise o diff no painel de alterações e faça o commit antes de pedir a próxima.
5. Se os comandos `/` não aparecerem, abra *Customizations → Workflows* e confira se `.agent/workflows/` foi reconhecida. Sem eles, peça: "Leia AGENTS.md e execute docs/agent-tasks/NN-....md seguindo o workflow .agent/workflows/proxima-tarefa.md".

O build e o teste no iPhone continuam no Xcode (`ShadowingNative.xcodeproj`); o `verify.sh` compila pelo terminal.

## Rodar o curador de verdade

Depois das tarefas (pelo menos até a 15), digite `/rodar-curadoria`. O agente pergunta o que você quer (reprocessar, buscar e publicar, descobrir canais ou deixar rodando sozinho), roda o comando com as credenciais do Mac **sem ver as chaves** e resume o resultado.

## Ordem

| # | Tarefa | Depende de | Dificuldade |
|---|---|---|---|
| 01 | [Feed só do catálogo](01-feed-so-catalogo.md) | n/a | baixa |
| 02 | *(cancelada: aula de inglês é aceita)* | n/a | n/a |
| 03 | [Curador: legenda json3 com tempo por palavra](03-curador-legenda-json3.md) | n/a | média |
| 04 | [Curador: alinhar legenda manual com a automática](04-curador-alinhamento.md) | 03 | média |
| 05 | *(removida: o Gemini atua pelo Caminho B)* | n/a | n/a |
| 06 | [Curador: segmentação ótima](06-curador-segmentacao-dp.md) | 04 | média |
| 07 | *(removida: o Gemini atua pelo Caminho B)* | n/a | n/a |
| 08 | [Catálogo v2](08-catalogo-v2.md) | 06 | média |
| 09 | [App: mesma segmentação no Swift](09-app-segmentacao-paridade.md) | 06, 08 | média |
| 10 | [Nível relativo ao conteúdo nativo](10-nivel-relativo.md) | 06 | **alta** |
| 11 | [Recalibrar nível pelo uso](11-recalibracao-feedback.md) | 10 | média |
| 12 | [Ajudas para o iniciante](12-ajudas-iniciante.md) | 08, 10 | média |
| 13 | [Publicação automática com amostragem](13-publicacao-automatica.md) | 02, 08, 10 | **alta** |
| 14 | *(removida: o Gemini atua pelo Caminho B)* | n/a | n/a |
| 15 | [Reprocessar a fila de 219](15-reprocessar-fila.md) | 03, 04, 06, 08, 10, 13 | média |
| 16 | [Uploads de canal via playlist de Shorts](16-descoberta-uushorts.md) | 13 | baixa |
| 17 | [Descoberta automática de canais](17-descoberta-canais-automatica.md) | 02, 13, 16 | **alta** |

- **01–02:** resolvem o "professor de inglês" no app.
- **03–15:** enchem o feed com os 219 Shorts nativos já coletados (Team Coco, SubwayTakes, Ringer, StarTalk…), com cortes e níveis melhores.
- **16–17:** aumentam o volume com canais novos, sem você indicar um por um.

## Só o usuário (fora das tarefas)

- Deploy de `firestore.rules`, se a tarefa 11 o alterar: `firebase deploy --only firestore:rules`, **antes** de distribuir a build do app.
- Teste no iPhone físico.
