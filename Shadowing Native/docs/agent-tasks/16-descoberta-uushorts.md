# 16: Uploads de canal pela playlist de Shorts (1 unidade de cota em vez de 100)

## Objetivo
Trocar `searchChannel()` (`search.list` com `q: '#shorts'`, **100 unidades** da cota diária de 10.000) pela playlist só de Shorts do canal, via `playlistItems.list` (**1 unidade**). Se ela não existir, usar a playlist de uploads.

## Por quê
- Com `search.list`, o curador gasta a cota em poucos canais (limite de 20 buscas/dia). Com playlists, cabem centenas de canais por dia.
- A hashtag `#shorts` puxa vídeos sem fala. Na lupa, tirar `#shorts` levou "travel" de 0/10 para até 14/15 vídeos com legenda em inglês.

## Depende de
Tarefa 13 (o fluxo de publicação já é automático).

## Arquivos permitidos
- `curator/discovery.mjs` (novo), `curator/discovery.test.mjs` (novo)
- `curator/curator.mjs` (`searchChannel`, `scan`, `queueChannels`), `curator/workflow.mjs`, `curator/README.md`

## Passos
1. Em `curator/discovery.mjs`, exporte:
   - `shortsPlaylistID(channelID)` → `'UUSH' + channelID.slice(2)`;
   - `uploadsPlaylistID(channelID)` → `'UU' + channelID.slice(2)`.
   
   Ambas exigem `/^UC[A-Za-z0-9_-]{22}$/` (senão lançam erro). A playlist `UUSH…` é um **atalho não oficial** do YouTube; escreva isso num comentário.
2. Exporte `async function listChannelVideos({ channelID, pageToken, playlistKind, request })`. `request(pathname, params)` é injetado: em produção, é a função `youtube` de `curator.mjs`.
   - Chama `playlistItems` com `{ part: 'contentDetails', playlistId, maxResults: 50, pageToken }`.
   - `playlistKind` começa em `'shorts'`. Se a chamada lançar erro com `HTTP 404`, tente `'uploads'` (só na primeira página) e retorne o tipo usado.
   - Retorna `{ videoIDs, nextPageToken, playlistKind }`, filtrando IDs com `/^[A-Za-z0-9_-]{11}$/`.
3. Em `curator.mjs`, substitua `searchChannel(seed, pageToken)` por `listChannelVideos` e guarde `state.playlistKind` junto de `state.pageToken` para continuar na mesma playlist. `finishSearchPage` continua controlando páginas por canal (`maximumPagesPerChannel`).
4. **Cota:** o laço de `scan()` deixa de incrementar `state.searchCount` para playlists. Crie `state.playlistCount` (zerado em `refreshSearchBudget`) com um limite de 500 por dia, configurável por `CURATOR_PLAYLIST_PAGES_PER_DAY`. `dailySearchLimit` passa a valer só para `search.list` (usado na tarefa 17 e em `queueChannels`).
5. Em `queueChannels()`, use também `listChannelVideos` (primeira página) no lugar de `searchChannel`.
6. A playlist de uploads (`UU`) traz vídeos horizontais. O filtro `assessShortsFormat` em `metadata()` já os rejeita; não mude isso.

## Testes (`discovery.test.mjs`), com `request` falso
- IDs das playlists corretos; ID de canal inválido lança erro.
- Playlist `UUSH` existente → `playlistKind: 'shorts'` e IDs filtrados.
- `UUSH` com `HTTP 404` → tenta `UU`, retorna `playlistKind: 'uploads'`.
- `nextPageToken` é repassado.
- Erro diferente de 404 (ex.: `HTTP 403`) propaga, sem fallback.

## Critérios de aceite
- `grep -n "q: '#shorts'" curator/curator.mjs` não encontra nada.
- `cd curator && npm test` e `scripts/verify.sh` → "Tudo passou."
- README do curador explica a mudança de cota.
