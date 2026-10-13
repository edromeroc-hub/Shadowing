# 04: Curador: alinhar a legenda manual com a automática

## Objetivo
Gerar uma lista de **palavras com tempo real e pontuação**: o texto vem da legenda manual (pontuada e correta) e o tempo, da automática (tempo por palavra). Quando não houver as duas, usar a melhor disponível e registrar a qualidade do tempo.

## Por quê
A legenda manual tem pontuação, mas só tem tempo por bloco. A automática tem tempo por palavra, mas não tem pontuação (126 de 219 candidatos não têm `.?!`). Com as duas juntas, o corte cai em fim de frase **e** no tempo certo, sem estimar (hoje, 44% das frases são estimadas).

## Depende de
Tarefa 03 (`fetchCaptions` e `.state/captions/`).

## Arquivos permitidos
- `curator/align.mjs` (novo), `curator/align.test.mjs` (novo)
- `curator/curator.mjs`, `curator/quality.mjs` (só a assinatura de `prepare`)

## Passos

### A. `curator/align.mjs`
Exporte `buildTimedWords({ manual, asr })` → `{ words, timingQuality, matchRatio }`.
- `words`: `[{ text, start, end, timing }]`, com `timing` ∈ `'word' | 'interpolated' | 'estimated'`.
- `timingQuality` ∈ `'aligned' | 'word' | 'estimated'`.

1. **Tokens:** divida o texto de cada segmento por espaços; cada token mantém a pontuação (`"you?"`). Antes de tudo, remova marcas não faladas: `[...]`, `(...)` e `♪`.
   - Segmento com várias palavras **sem** tempo por palavra: distribua `[start, end]` entre os tokens proporcionalmente ao número de caracteres (`timing: 'estimated'`).
   - Segmento da faixa automática com mais de um token: mesma distribuição, mas com `timing: 'word'`, porque o bloco já é curto.
2. **Normalização para comparar:** minúsculas; remova tudo que não for letra ou dígito (inclusive apóstrofo: `don't` → `dont`). Tokens que ficarem vazios não entram no alinhamento.
3. **Alinhamento:** LCS clássico por programação dinâmica entre os tokens normalizados da manual (`i`) e da automática (`j`).
   - No retrocesso, quando `dp[i-1][j] >= dp[i][j-1]`, recue em `i` (a regra precisa ser determinística).
   - O token manual casado recebe `start`/`end` da palavra automática (`timing: 'word'`).
4. **Lacunas:** uma sequência de tokens manuais sem par, entre duas âncoras casadas, divide o intervalo `[âncoraAnterior.end, próximaÂncora.start]` proporcionalmente aos caracteres (`timing: 'interpolated'`). Sequências no começo ou no fim, sem âncora de um dos lados, mantêm o tempo estimado do passo 1, recortado para não ultrapassar a âncora.
5. `matchRatio = casados / tokensManuaisNormalizáveis`.
6. **Decisão:**
   - `manual && asr && matchRatio >= 0.6` → palavras alinhadas, `timingQuality: 'aligned'`;
   - senão, se há `asr` → tokens da automática, `timingQuality: 'word'` (sem pontuação);
   - senão (só manual) → `'word'` se todos os segmentos têm `hasWordTiming`; caso contrário, distribuição proporcional e `'estimated'`.
7. **Higiene final:** `start` não decrescente; `end = min(end, próximo.start)`; `end >= start + 0.04`; arredonde para milissegundos.

### B. Integração
- `quality.mjs → prepare(...)` aceita `timedWords` e `timingQuality` opcionais e os copia para o resultado (`words`, `timingQuality`). Se vierem, `rawSegments` = palavras convertidas em segmentos `{ text, start, end, hasWordTiming: timing !== 'estimated' }`.
- `curator.mjs → inspect(...)`: `const timed = buildTimedWords(captions)` e passe para `prepare`. O resto do fluxo continua igual até a tarefa 05.

### C. Testes (`align.test.mjs`)
1. Manual `"Hello, how are you doing today?"` (um segmento de 0 a 3 s, sem tempo por palavra) + automática com 6 palavras em tempos conhecidos → 6 palavras com pontuação, tempos da automática, `aligned`, `matchRatio` 1.
2. A automática erra uma palavra (`doin` em vez de `doing`) → essa palavra fica `interpolated` entre as vizinhas; o restante é `word`.
3. Manual e automática quase sem palavras em comum (`matchRatio` < 0,6) → usa a automática, `timingQuality: 'word'`.
4. Só manual sem tempo → `estimated`, com tempos proporcionais dentro do segmento.
5. `[Music]`, `(laughs)` e `♪` não aparecem em `words`.
6. Saída sempre ordenada, sem sobreposição e com `end > start`.

## Critérios de aceite
- `cd curator && npm test` passa.
- `scripts/verify.sh` → "Tudo passou."

## Não fazer
- Não mudar `buildPhrases` nem `classify` (tarefas 05 e 08).
- Não acessar a rede.
