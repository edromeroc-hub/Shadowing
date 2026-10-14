---
description: Roda o curador automático (Caminho A) de verdade com as credenciais do Mac
---

Este workflow só roda porque o usuário pediu. Ele usa as credenciais de `~/.config/shadowing-curator/curator.env` e **publica no app real**.

1. Leia `AGENTS.md`. **Nunca** abra, leia ou imprima `~/.config/shadowing-curator/*` nem as chaves; os comandos `:configured` carregam tudo sozinhos.
2. Confira em `docs/agent-tasks/STATUS.md` quais tarefas estão `feita`:
   - Se a **13 (publicação automática)** não estiver feita, avise: "o curador ainda usa o fluxo antigo (níveis errados, cortes estimados, sem publicação automática)". Pergunte se quer mesmo continuar.
3. Pergunte ao usuário qual operação deseja, se ele não disse:
   - **reprocessar** os candidatos já coletados → `cd curator && npm run resegment:fetch` (precisa da tarefa 15);
   - **buscar e publicar** Shorts novos → `cd curator && npm run scan:configured`;
   - **descobrir canais** novos → `cd curator && npm run discover:configured` (precisa da tarefa 17);
   - **deixar rodando** sozinho → `cd curator && npm run service:install` e, depois, `npm run service:status`.
4. Rode o comando escolhido no terminal e acompanhe a saída.
   - Ao ver um limite do YouTube (429), **não repita** o comando. Explique que é um bloqueio temporário e sugira tentar de novo mais tarde.
   - Erro de credencial ou configuração: mostre só a mensagem de erro (que não contém a chave) e indique `curator/README.md`.
5. Resuma para o usuário: quantos vídeos foram inspecionados, publicados, enviados para revisão e rejeitados (com os motivos mais comuns).
6. Lembre que as amostras (1 a cada 10 publicados) ficam no painel em `cd curator && npm run dashboard` → `http://127.0.0.1:4318`, aba "Amostras para ouvir".
