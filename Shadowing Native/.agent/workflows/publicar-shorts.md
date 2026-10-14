---
description: Publica no app os Shorts curados que o usuário aprovou
---

1. Confirme na conversa **quais IDs** o usuário aprovou. Se não estiver claro, pergunte e **não publique**.
2. Em `curadoria-gemini/`, garanta que cada um tem `trabalho/ID/documento.json`, rodando `node cli.mjs montar ID` de novo se mudou algo.
3. Rode `node cli.mjs publicar ID1 ID2 … --confirmado`. Use `--atualizar` só se o usuário pediu para substituir um que já está no catálogo.
4. Mostre o resultado de cada um (PUBLICADO, ATUALIZADO ou PULADO, com o motivo) e rode `node cli.mjs situacao`.
5. Lembre: o app mostra os novos Shorts para alunos do mesmo nível e com algum dos temas em comum. Se o usuário quiser conferir no iPhone, o nível do perfil dele precisa bater.
