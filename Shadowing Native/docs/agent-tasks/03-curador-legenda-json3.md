# 03: Curador: legenda json3 com tempo por palavra (faixa manual + automática)

## Objetivo
Trocar a lib `youtube-transcript` por um módulo próprio que baixa as legendas no formato **json3**. O json3 traz o tempo de cada palavra (`tOffsetMs`) e permite guardar **as duas faixas** em inglês: a manual (pontuada) e a automática (`kind: "asr"`, com tempo por palavra).

## Por quê
`captionSegments()` em `curator/curator.mjs` usa `YoutubeTranscript.fetchTranscript`, que descarta o tempo por palavra: 0 de 219 candidatos têm `hasWordTiming`. Sem isso, os cortes de frase são estimados (≈) e caem no meio das palavras. O app Swift já faz isso certo em `YouTubeTranscriptService.swift` + `TranscriptJSONParser.swift`; esta tarefa traz a mesma lógica para o JS.

## Arquivos permitidos
- `curator/captions.mjs` (novo), `curator/captions.test.mjs` (novo)
- `curator/curator.mjs`
- `curator/package.json`, `curator/package-lock.json` (só para remover `youtube-transcript`, com `npm uninstall youtube-transcript`)

## Passos

### A. `curator/captions.mjs`
Exporte:

1. `parseJSON3(json)`: tradução **fiel** de `ShadowingNative/Services/TranscriptJSONParser.swift`.
   - `events[].segs[]` com `tOffsetMs` → uma unidade por palavra (`hasWordTiming: true`). Sem offset → uma unidade por evento.
   - O fim de cada unidade é o início da seguinte ou `tStartMs + dDurationMs` (padrão de 2000 ms).
   - Remova duplicatas consecutivas iguais, recorte sobreposições e descarte texto vazio.
   - Limpe HTML e entidades como o `clean(_:)` do Swift.
   - Retorna `[{ text, start, end, hasWordTiming }]` em segundos.
2. `selectEnglishTracks(captionTracks)` → `{ manual, asr }`.
   - `asr`: `kind === 'asr'` e `languageCode` começa com `en`.
   - `manual`: `kind !== 'asr'` e `languageCode` começa com `en`. Prefira `en-US`, depois `en`, depois qualquer `en-*`.
   - Ambos podem ser `null`.
3. `fetchCaptions(videoID, { fetchImpl = fetch } = {})` → `{ title, channel, manual, asr }`, onde `manual`/`asr` são arrays de `parseJSON3` ou `null`.
   - Player: `POST https://www.youtube.com/youtubei/v1/player?prettyPrint=false`, com o mesmo corpo e cabeçalhos de `loadAndroidPlayer` em `YouTubeTranscriptService.swift` (`clientName: ANDROID`, `clientVersion: 20.10.38`, `hl: en`, `gl: US`, `User-Agent` e `X-YouTube-Client-*`).
   - Para cada faixa escolhida: aceite só `baseUrl` em `https://` com host `youtube.com` ou `*.youtube.com`, troque/adicione `fmt=json3` e faça GET.
   - Sem nenhuma faixa em inglês → `Error('Legenda em inglês indisponível')`.
   - Timeout de 20 s por pedido (`AbortSignal.timeout(20000)`).
4. `class RateLimitedError extends Error` com `code = 'RATE_LIMITED'`, lançada quando qualquer resposta for HTTP 429.
5. **Limitador de concorrência** no módulo: no máximo **2** chamadas de rede ao YouTube ao mesmo tempo (uma fila simples com Promises). Exporte `setCaptionConcurrency(n)` só para testes.

### B. `curator/curator.mjs`
1. Remova o import de `youtube-transcript` e a função `captionSegments`.
2. Em `scan() → inspect(...)`, chame `fetchCaptions(videoID)`.
   - Salve a resposta crua em `.state/captions/<videoID>.json` como `{ fetchedAt, manual, asr }`, criando a pasta junto das outras (`stateDirectory`). As próximas tarefas usam isso para reprocessar sem baixar de novo.
   - **Até a tarefa 04**, use `rawSegments = manual ?? asr` em `prepare(...)`, para não mudar o resto do fluxo.
3. No `catch` de `inspect`: se `error.code === 'RATE_LIMITED'`, registre `"YouTube limitou as legendas (429); retomando no próximo ciclo."` e **relance** o erro (interrompe o ciclo, como já acontece com `HTTP 4…`), sem marcar o vídeo como rejeitado.
4. `npm uninstall youtube-transcript`.

### C. Testes (`captions.test.mjs`), sem rede
- `parseJSON3` com um evento de palavras com `tOffsetMs` (ASR): 4 palavras com tempos crescentes e `hasWordTiming: true`.
- `parseJSON3` com eventos sem offset (manual): uma unidade por evento.
- `parseJSON3` com duplicata sobreposta: é removida.
- `selectEnglishTracks` com `[pt-BR, en asr, en-GB manual, en-US manual]` → `manual` = en-US, `asr` = en asr.
- `fetchCaptions` com `fetchImpl` falso que devolve o player e o json3 → retorna as duas faixas.
- `fetchImpl` que devolve status 429 → `RateLimitedError`.
- Concorrência: 6 chamadas com um `fetchImpl` lento que conta as chamadas ativas → o máximo observado é 2.
- `baseUrl` com host fora do YouTube → erro, sem GET.

## Critérios de aceite
- `grep -rn "youtube-transcript" curator --include=*.mjs --include=package.json` não encontra nada.
- `cd curator && npm test` passa, incluindo os testes novos.
- `scripts/verify.sh` → "Tudo passou."

## Não fazer
- Não rodar `scan` de verdade nem acessar a rede nos testes.
- Não alterar `quality.mjs` nesta tarefa.
