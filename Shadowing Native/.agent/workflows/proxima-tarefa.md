---
description: Executa a próxima tarefa pendente de docs/agent-tasks, verifica e atualiza o STATUS
---

1. Leia `AGENTS.md` inteiro.
2. Leia `docs/agent-tasks/README.md` (tabela "Ordem") e `docs/agent-tasks/STATUS.md`.
3. Escolha a **primeira** tarefa da ordem com status `pendente` cujas dependências estejam todas `feita`. Se o usuário informou um número junto do comando (ex.: `/proxima-tarefa 05`), use essa tarefa, desde que as dependências estejam feitas.
4. Diga ao usuário em uma linha qual tarefa vai executar e por quê. Se alguma estiver `bloqueada`, mostre a nota e pergunte como seguir antes de continuar.
5. Leia o arquivo da tarefa inteiro e execute-o, mudando **só** os arquivos permitidos.
6. Rode `scripts/verify.sh` no terminal. Se falhar, corrija e rode de novo. Se depois de 3 tentativas ainda falhar, marque a tarefa como `bloqueada` no STATUS com o erro resumido e pare.
7. Com "Tudo passou.", atualize a linha da tarefa em `docs/agent-tasks/STATUS.md`: `feita`, a data de hoje e 1 a 3 frases do que mudou (inclua os números pedidos pela tarefa, como relatórios ou distribuições).
8. Termine com um resumo curto: arquivos alterados, resultado do `verify.sh` e a próxima tarefa da ordem. **Não faça commit**: o usuário revisa e faz o commit.
