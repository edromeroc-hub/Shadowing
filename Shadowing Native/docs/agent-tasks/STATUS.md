# Status das tarefas

Atualize ao terminar ou travar uma tarefa. Status: `pendente`, `feita`, `bloqueada`, `cancelada` (pule as canceladas).

| # | Tarefa | Status | Data | Notas do agente |
|---|---|---|---|---|
| 01 | Feed só do catálogo | feita | 13/10/2026 | Removido discoverBatch do feed; feed restrito a SharedShortCatalog; estados de aviso e vazio atualizados. |
| 02 | *(cancelada: aula de inglês é aceita)* | cancelada | 14/10/2026 | Decisão do dono: vídeos de professor de inglês com fala clara ficam no catálogo. Não rejeitar por isso. |
| 03 | Curador: legenda json3 | pendente | | |
| 04 | Curador: alinhamento | pendente | | |
| 05 | *(removida: Caminho B)* | cancelada | 13/10/2026 | |
| 06 | Curador: segmentação ótima | pendente | | |
| 07 | *(removida: Caminho B)* | cancelada | 13/10/2026 | |
| 08 | Catálogo v2 | pendente | | |
| 09 | App: segmentação igual | pendente | | |
| 10 | Nível relativo | pendente | | |
| 11 | Recalibração pelo uso | pendente | | |
| 12 | Ajudas para o iniciante | pendente | | |
| 13 | Publicação automática | pendente | | |
| 14 | *(removida: Caminho B)* | cancelada | 13/10/2026 | |
| 15 | Reprocessar a fila | pendente | | |
| 16 | Playlist de Shorts | pendente | | |
| 17 | Descoberta de canais | pendente | | |

## Histórico anterior (Claude)

- 12/10/2026: lupa da aba Shorts corrigida (consulta sem `#shorts`, termos em português traduzidos por `ShortsDiscoveryService.youtubeQuery`, nível vizinho aceito com selo, verificação de legenda de 3 em 3, "Carregar mais Shorts", mensagem clara para o 429 do YouTube). Criados `AGENTS.md`, `GEMINI.md`, `scripts/verify.sh` e as tarefas.
- 13/10/2026: Antigravity como ambiente do agente; tarefas renumeradas (as antigas 05–14 viraram 06, 08–13 e 15–17). Workflows `/proxima-tarefa` e `/rodar-curadoria`.
- 13/10/2026: criado o **Caminho B** em `curadoria-gemini/`, em que o Gemini no Antigravity é o curador (`/curar-shorts`, `/publicar-shorts`, `/revisar-shorts`). As tarefas 05, 07 e 14 (Gemini dentro do programa curador) foram canceladas.
- 14/10/2026: auditoria no simulador (`Audits/AUDITORIA_SIMULADOR_2026_10_14.md`). **Atenção nas tarefas 08 e 09:** `SharedShortCatalog.swift` e `ShadowingLessonBuilder.swift` agora preenchem `ShadowingPhrase.playbackEnd` com `PhraseBoundary.applyingPlaybackEnds` (evita vazar a palavra seguinte), e o catálogo começa num ID sorteado e dá a volta. Preserve os dois comportamentos ao reescrever esses arquivos.
