# 17: Descoberta automática de canais nativos dos EUA

## Objetivo
O curador passa a **encontrar canais novos sozinho**, sem o dono indicar um por um:
1. rodízio de buscas por gêneros de conteúdo natural americano + vídeos em alta nos EUA;
2. avaliação do canal (país, idioma, não didático, tamanho);
3. período de prova com 5 Shorts;
4. promoção automática para `seeds.json`, ou rebaixamento se o canal der problema.

## Por quê
Hoje `seeds.json` tem 18 canais escolhidos à mão; para crescer, o dono precisa indicar canais. O objetivo é o "Short que o americano rola no dia a dia": talk show, entrevista de rua, humor, podcast, esporte, culinária.

## Depende de
Tarefas 13 e 16.

## Arquivos permitidos
- `curator/discovery.mjs`, `curator/discovery.test.mjs`
- `curator/curator.mjs`, `curator/workflow.mjs`, `curator/package.json` (scripts), `curator/README.md`
- `curator/seeds.json` (**só** pelo código de promoção/rebaixamento; não edite à mão)

## Passos

### A. Lógica pura em `discovery.mjs`
1. `GENRE_QUERIES`:
   ```js
   ['late night show', 'talk show interview', 'podcast clip', 'street interview', 'stand up comedy',
    'sketch comedy', 'prank', 'storytime', 'celebrity interview', 'sports interview', 'mic d up',
    'cooking', 'gym', 'day in my life', 'funny moments', 'reaction', 'hot take', 'roast']
   ```
   `nextGenreQuery(state)` faz o rodízio com `state.genreIndex`.
2. `POPULAR_CATEGORY_IDS = ['23', '24', '17', '22', '26']` (Comedy, Entertainment, Sports, People & Blogs, Howto & Style).
3. `evaluateChannel(channel)` recebe um item de `channels.list` (`snippet`, `statistics`) e retorna `{ ok, reason }`. Reprova se:
   - `snippet.country` existe e é diferente de `'US'`;
   - `snippet.country` está ausente **e** `snippet.defaultLanguage` não começa com `en`;
   - `statistics.hiddenSubscriberCount !== true` e `Number(statistics.subscriberCount) < 50000`.
4. `promotionDecision(probationResults)`: recebe a lista de `{ videoID, publishable: boolean, interests: [] }` dos Shorts de prova. Promove se houver ≥ 5 resultados e ≥ 3 publicáveis. O `interest` da semente é o tema mais frequente entre os publicáveis (empate → ordem alfabética). Retorna `{ promote, interest, reason }`.
5. `demotionDecision({ unpublishedCount, hiddenVotes, totalVotes })`: rebaixa se `unpublishedCount >= 3` **ou** (`totalVotes >= 20` e `hiddenVotes / totalVotes >= 0.4`).

### B. Integração em `curator.mjs`
1. Novo comando `discover-channels` (precisa da chave do YouTube; não é `localCommand`). Script `"discover:configured": "node run-service.mjs discover-channels"`.
2. **Coleta:**
   - até **15** `search.list` por dia (`type: 'video'`, `videoDuration: 'short'`, `regionCode: 'US'`, `relevanceLanguage: 'en'`, `order: 'viewCount'`, `publishedAfter` = agora − 90 dias, `safeSearch: 'strict'`, `maxResults: 50`), dentro de `dailySearchLimit`;
   - 1 chamada `videos.list` com `chart: 'mostPopular'`, `regionCode: 'US'`, `part: 'snippet,contentDetails'` por categoria de `POPULAR_CATEGORY_IDS`, mantendo só duração ≤ 180 s (`secondsFromDuration`);
   - junte os `channelId` que não estão em `seeds.json` nem em `.state/channel-blocklist.json`, e grave em `.state/channel-candidates.json` (`{ [channelID]: { firstSeenAt, source, query, hits } }`).
3. **Avaliação:** `channels.list` (`part: 'snippet,statistics'`, até 50 IDs por chamada, 1 unidade) → `evaluateChannel`. Reprovados vão para `.state/channel-blocklist.json` com o motivo.
4. **Prova:** para cada aprovado (no máximo 10 novos por dia), pegue a 1ª página de `listChannelVideos` (tarefa 16) e coloque os 5 primeiros vídeos em `state.pending`, com `source: 'probation'` e `channelID`. O `scan()` normal processa a fila; registre o resultado de cada um (`publishable` = sem motivos em `automaticReviewReasons`) em `.state/channel-candidates.json`.
5. **Decisão:** quando um canal tiver 5 resultados de prova, aplique `promotionDecision`.
   - Se promover: acrescente em `seeds.json` `{ interest, channelID, source: 'auto', addedAt }` (escrita atômica, como `saveJSON`) e registre `CANAL PROMOVIDO <id> <título>`.
   - Senão: mande para o blocklist.
6. **Rebaixamento** (uma vez por dia, depois de `aggregate`): para sementes com `source: 'auto'`, conte os despublicados (`.state/rejected/*.json` com `reason: 'Despublicado na amostragem'` do canal) e os votos `hidden`. Se `demotionDecision` mandar, remova de `seeds.json` e adicione ao blocklist. **Sementes manuais (sem `source`) nunca são removidas.**
7. No laço `continuous()`, rode `discover-channels` uma vez por dia (`state.lastDiscoveryDay`, como já é feito com `lastAggregateDay`).

### C. Testes (`discovery.test.mjs`)
- O rodízio de `nextGenreQuery` volta ao início.
- `evaluateChannel`: canal dos EUA grande passa; país `BR` reprova; sem país e com `defaultLanguage: 'en-US'` passa; 10 mil inscritos reprova; inscritos ocultos passa.
- `promotionDecision`: 3 de 5 promove com o tema mais frequente; 2 de 5 não; 4 resultados ainda não decide.
- `demotionDecision`: 3 despublicados rebaixa; 8 de 20 escondidos rebaixa; 7 de 20 não.

## Critérios de aceite
- `cd curator && npm test` e `scripts/verify.sh` → "Tudo passou."
- README do curador: como funciona a descoberta, limites de cota (≈ 15 × 100 + poucas unidades por dia), onde ver os candidatos e o blocklist, e como tirar um canal à mão (remover de `seeds.json` e pôr no blocklist).

## Não fazer
- Não rodar `discover-channels` de verdade (precisa de rede e chave).
- Não editar `seeds.json` à mão nem remover sementes manuais.
