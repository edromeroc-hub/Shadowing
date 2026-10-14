---
description: Gemini faz a curadoria de Shorts naturais (busca, avalia, nível, frases, revisão) e mostra para aprovação
---

Você é o curador. Siga `curadoria-gemini/DIRETRIZES.md` à risca. Rode todos os comandos dentro de `curadoria-gemini/`.

1. Leia `curadoria-gemini/DIRETRIZES.md` inteiro.
2. Rode `node cli.mjs situacao` para ver a distribuição de níveis e os rascunhos em andamento. Termine os rascunhos antes de buscar novos.
3. Entenda o pedido do usuário: quantos Shorts (padrão: **5**), nível, tema ou canal. Se não houver preferência, escolha o que mais falta na distribuição (meta de ~30/40/30).
4. **Encontre candidatos:**
   - com canal indicado → `node cli.mjs canal @handle`;
   - senão, prefira canais da lista das diretrizes (`canal`, mais barato) e use `node cli.mjs buscar "consulta"` para temas;
   - só considere linhas com status `novo`;
   - pelo título e canal, descarte o que for obviamente aula, música ou edit (registre com `rejeitar`).
5. **Para cada candidato**, um por vez, até completar a quantidade:
   1. `node cli.mjs palavras ID`. Se der o erro 429, **pare tudo** e avise o usuário.
   2. Leia `trabalho/ID/leitura.txt` inteiro e decida: natural ou aula? adequado? fala suficiente? legenda boa? Se não servir → `node cli.mjs rejeitar ID "motivo em português"` e vá para o próximo.
   3. Decida o nível (velocidade em sílabas/s + vocabulário + clareza) e os temas.
   4. Divida as frases conforme a seção 4 das diretrizes e escreva `trabalho/ID/decisao.json`.
   5. `node cli.mjs montar ID`. Corrija os `ERRO`s e trate os `AVISO`s, repetindo até ficar limpo.
   6. Revise como aluno (seção 6 das diretrizes).
6. **Mostre ao usuário** uma tabela: ID, link `https://youtube.com/shorts/ID`, título, canal, nível, temas, nº de frases, motivo (uma linha) e avisos restantes. Liste também os rejeitados, com o motivo.
7. Pergunte quais publicar. **Não publique** sem resposta explícita; quando ele aprovar, siga `/publicar-shorts`.
