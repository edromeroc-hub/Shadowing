# 12: Reprocessar a fila atual (219 candidatos) com o novo pipeline

## Objetivo
Estender `npm run resegment` para refazer os candidatos pendentes com o pipeline novo:
- legendas json3 → alinhamento → segmentação ótima → nível relativo;
- metadados atualizados (categoria, idioma do áudio);
- relatório antes/depois.

O agente implementa e testa. **Quem roda com rede é o usuário.**

## Depende de
Tarefas 03 a 08 e 11.

## Arquivos permitidos
- `curator/curator.mjs` (função `resegment` e o que ela precisar)
- `curator/resegment.mjs` (novo, opcional, para lógica pura testável), `curator/resegment.test.mjs` (novo)
- `curator/package.json` (scripts), `curator/README.md`

## Comportamento de `node curator.mjs resegment [--fetch] [--dry-run]`
1. **Backup obrigatório**, antes de qualquer escrita e exceto em `--dry-run`: copie `.state/review` e `.state/metadata` para `.state/backups/resegment-<AAAAMMDD-HHMMSS>/`. Se a cópia falhar, aborte sem escrever nada.
2. Itens: os arquivos de `.state/review/` sem marcador em `published/` ou `rejected/`.
3. **Legendas:**
   - existe `.state/captions/<id>.json` → use;
   - senão, com `--fetch`, chame `fetchCaptions` (concorrência 2 da tarefa 03) e salve o cache; ao receber `RateLimitedError`, **pare o laço**, grave o progresso e mostre "Retome mais tarde com o mesmo comando";
   - sem `--fetch` e sem cache, use palavras estimadas a partir de `prepared.segments` (`timingQuality: 'estimated'`). A tarefa 11 manda esses itens para revisão.
4. **Metadados:** com `--fetch`, atualize em lotes de 50 por `videos.list` (`part: 'snippet,contentDetails,status,player'`, 1 unidade de cota por lote): `categoryId`, `defaultAudioLanguage` e o resultado de `assessShortsFormat`, como `auditShorts()` já faz.
5. **Refazer** via `prepare(...)` com `timedWords`. Itens que passarem a falhar (aula de inglês, velocidade inválida etc.) vão para `.state/rejected/<id>.json` com o motivo, e `state.processed[id] = 'rejected'`. Nada é apagado.
6. **Relatório** (sempre, inclusive em `--dry-run`):
   - níveis antes × depois;
   - p50/p90 de palavras e segundos por frase, por nível;
   - % de frases com tempo estimado;
   - quantos ficariam publicáveis por `automaticReviewReasons` e os 5 motivos mais comuns;
   - quantos foram rejeitados e por quê.
7. Scripts em `package.json`: `"resegment": "node curator.mjs resegment"` (já existe) e `"resegment:fetch": "node run-service.mjs resegment --fetch"`, pois precisa da chave do YouTube configurada. Confira em `run-service.mjs` como os argumentos são repassados; ajuste se preciso.

## Testes (`resegment.test.mjs`)
Coloque a lógica pura (escolha da fonte de legenda, montagem do relatório) em `resegment.mjs` e teste com um diretório temporário (`fs.mkdtemp`), **nunca** com `.state` real:
- backup criado antes da escrita; `--dry-run` não escreve nada;
- item com cache de legenda usa as palavras alinhadas;
- item sem cache e sem `--fetch` vira `estimated`;
- `RateLimitedError` interrompe o laço e preserva o que já foi feito.

## O agente pode rodar
- `node curator.mjs resegment --dry-run` (offline, só leitura). Cole o relatório no STATUS.

## Não fazer
- Não rodar `--fetch` nem `resegment` sem `--dry-run`. O usuário roda:
  ```bash
  cd curator && npm run resegment:fetch
  ```
