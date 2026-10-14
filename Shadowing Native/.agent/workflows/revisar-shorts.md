---
description: Revisa um Short publicado ou em rascunho, corrige frases e nível, e republica com o OK do usuário
---

Siga `curadoria-gemini/DIRETRIZES.md`. Comandos dentro de `curadoria-gemini/`.

1. Pegue o ID (ou o link) com o usuário. Pergunte também o que ele notou de errado: frase longa, corte no meio, nível, legenda.
2. Se estiver publicado: `node cli.mjs baixar ID` para ver as frases atuais.
3. `node cli.mjs palavras ID` para ter as palavras numeradas com tempo.
4. Compare as frases atuais com as diretrizes e com o problema relatado. Escreva um `trabalho/ID/decisao.json` corrigido; se for um Short do curador automático, crie do zero.
5. `node cli.mjs montar ID` até não haver `ERRO`, e revise como aluno.
6. Mostre ao usuário o antes × depois (frases e nível) e pergunte se pode substituir.
7. Com o OK: `node cli.mjs publicar ID --confirmado --atualizar`. Se o problema for o vídeo em si (aula, impróprio, legenda inutilizável), proponha `node cli.mjs despublicar ID "motivo" --confirmado` e só rode com o OK.
