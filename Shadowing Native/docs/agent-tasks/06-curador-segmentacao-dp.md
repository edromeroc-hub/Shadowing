# 06: Curador: segmentação ótima por programação dinâmica

## Objetivo
Substituir o corte guloso (`buildPhrases` em `curator/quality.mjs`) por uma segmentação **ótima** sobre as palavras com tempo (tarefa 04). Ela escolhe, entre todas as divisões possíveis, a de menor custo: frases no tamanho certo para cada nível e limites em fim de frase, vírgula ou pausa de respiração, nunca depois de "the", "to", "my"… O resultado sai para os 3 níveis.

## Por quê
O corte atual vai juntando até estourar um limite fixo. Sem pontuação, corta onde o limite manda ("rather than kind / of be tired"). Nos 219 candidatos: mediana de 12 palavras / 3,5 s e p90 de 17 palavras / 5,7 s (longo demais para repetir), com 8% de frases curtas demais.

## Depende de
Tarefa 04 (`words` com `{ text, start, end, timing }`).

## Arquivos permitidos
- `curator/segment.mjs` (novo), `curator/segment.test.mjs` (novo)
- `curator/scripts/generate-segmentation-fixtures.mjs` (novo), `curator/scripts/segmentation-report.mjs` (novo)
- `Audits/fixtures/segmentation/*.json` (novos)
- `curator/quality.mjs`, `curator/quality.test.mjs`, `curator/workflow.mjs`, `curator/workflow.test.mjs`

## Especificação (seguir exatamente: o Swift da tarefa 09 vai reproduzir bit a bit)

### Constantes
```js
export const SEGMENTATION_VERSION = 3;
export const LEVELS = {
  beginner:     { minWords: 3, idealMaxWords: 7,  maxWords: 9,  idealMaxSeconds: 2.5, maxSeconds: 3.5 },
  intermediate: { minWords: 4, idealMaxWords: 10, maxWords: 13, idealMaxSeconds: 3.5, maxSeconds: 4.5 },
  advanced:     { minWords: 5, idealMaxWords: 14, maxWords: 18, idealMaxSeconds: 4.5, maxSeconds: 6.0 },
};
const PAUSE = 0.30, MAX_INTERNAL_GAP = 1.2;
const SEGMENT_COST = 1, SHORT_PENALTY = 3, LONG_WORD_PENALTY = 1, LONG_TIME_PENALTY = 2;
const COST_STRONG = 0, COST_MEDIUM = 1, COST_MARKER = 2.5, COST_NONE = 5, COST_FORBIDDEN = 12;
const DISCOURSE_NEXT = new Set(['and','but','so','because','cause','then','which','when','if','actually','like','or']);
const DISCOURSE_BIGRAMS = new Set(['you know','i mean']);
const FORBIDDEN_AFTER = new Set(['the','a','an','to','of','my','your','his','her','our','their','its','is','are','was',
  'were','am',"i'm","you're","we're","they're","it's",'gonna','wanna','gotta','in','on','at','for','with','from',
  'and','but','or','so','very','really','just','which','because','cause','if','when','than',
  'that','i','we','they','he','she',"don't","didn't","doesn't","can't","won't","isn't","wasn't","aren't"]);
```

### Normalização de palavra
```js
function norm(text) {
  return text.replace(/’/g, "'").toLowerCase().replace(/^[^\p{L}\p{N}']+|[^\p{L}\p{N}']+$/gu, '');
}
```

### Custo do limite depois da palavra `j` (`0 ≤ j < n`)
```js
function boundaryCost(words, j) {
  if (j === words.length - 1) return 0;
  const raw = words[j].text;
  const gap = words[j + 1].start - words[j].end;
  if (/[.?!]["')\]]*$/.test(raw)) return COST_STRONG;
  if (/[,;:]["')\]]*$/.test(raw)) return COST_MEDIUM;
  if (gap >= PAUSE) return COST_MEDIUM;
  if (FORBIDDEN_AFTER.has(norm(raw))) return COST_FORBIDDEN;
  const next = norm(words[j + 1].text);
  const next2 = j + 2 < words.length ? norm(words[j + 2].text) : '';
  if (DISCOURSE_NEXT.has(next) || DISCOURSE_BIGRAMS.has(`${next} ${next2}`)) return COST_MARKER;
  return COST_NONE;
}
```

### Custo da frase `[i..k]` (inclusive)
```js
function phraseCost(words, i, k, L) {
  const count = k - i + 1;
  const duration = words[k].end - words[i].start;
  if (count > 1 && (count > L.maxWords || duration > L.maxSeconds)) return Infinity;
  for (let j = i; j < k; j++) if (words[j + 1].start - words[j].end >= MAX_INTERNAL_GAP) return Infinity;
  let cost = SEGMENT_COST + boundaryCost(words, k);
  if (count < L.minWords) cost += SHORT_PENALTY * (L.minWords - count);
  if (count > L.idealMaxWords) cost += LONG_WORD_PENALTY * (count - L.idealMaxWords);
  if (duration > L.idealMaxSeconds) cost += LONG_TIME_PENALTY * (duration - L.idealMaxSeconds);
  return cost;
}
```

### Programação dinâmica
```js
export function segmentWords(words, level) {
  const L = LEVELS[level];
  const n = words.length;
  const best = new Array(n + 1).fill(Infinity), from = new Array(n + 1).fill(-1);
  best[0] = 0;
  for (let end = 1; end <= n; end++) {
    const k = end - 1;
    for (let i = Math.max(0, end - L.maxWords); i <= k; i++) {   // i crescente
      const total = best[i] + phraseCost(words, i, k, L);
      if (total < best[end] - 1e-9) { best[end] = total; from[end] = i; }   // empate: fica o menor i
    }
  }
  const ranges = [];
  for (let end = n; end > 0; end = from[end]) ranges.unshift([from[end], end - 1]);
  return ranges;   // [[primeiraPalavra, últimaPalavra], ...]
}
export function segmentAllLevels(words) {
  return Object.fromEntries(Object.keys(LEVELS).map((level) => [level, segmentWords(words, level)]));
}
export function phrasesFromRanges(words, ranges) {
  return ranges.map(([i, k]) => ({
    text: words.slice(i, k + 1).map((w) => w.text).join(' '),
    start: words[i].start, end: words[k].end, firstWord: i, lastWord: k,
    timingEstimated: words.slice(i, k + 1).some((w) => w.timing !== 'word'),
  }));
}
```
Uma frase de uma palavra é sempre válida, então sempre existe solução. Não arredonde custos.

> Validado por Claude em 12/10/2026 com um protótipo deste código nos 219 candidatos (palavras estimadas, sem pausas reais). Mediana / p90 de palavras: iniciante 7 / 9, intermediário 9 / 11, avançado 12 / 15; segundos p90: 2,9 / 3,7 / 4,8. Antes: 12 / 17 palavras e 5,7 s. Com o tempo real por palavra (pausas), os limites ficam ainda melhores. Ajustes finos vão nas listas `FORBIDDEN_AFTER`/`DISCOURSE_NEXT`; ao mudá-las, regenere os casos de teste e atualize o Swift.

## Integração
1. `quality.mjs → prepare(...)`, quando houver `words`:
   - `phrasesByLevel = segmentAllLevels(words)`;
   - `phrases = phrasesFromRanges(words, phrasesByLevel[level])`, com os campos que o resto do código usa: `sourceSegmentCount: lastWord - firstWord + 1`, `needsExpandedPractice: false`, `endingHasWordTiming: words[lastWord].timing === 'word'`;
   - `segmentationVersion = SEGMENTATION_VERSION`.
   
   Sem `words` (itens antigos), mantenha o `buildPhrases` legado.
2. `phrasesArePractical(phrases, level)` passa a usar `LEVELS`. É prático quando:
   - há ≥ 2 frases;
   - toda frase com ≥ 2 palavras tem duração ≤ `maxSeconds` e no máximo `maxWords` palavras;
   - no máximo 15% das frases têm menos de 2 palavras.
   
   Remova o antigo `limits` se ficar sem uso.
3. `workflow.mjs → automaticReviewReasons`: aceite `segmentationVersion` 2 **ou** 3. Troque a checagem `words(phrase.text).length < 4` por "mais de 15% das frases com menos de 2 palavras".

## Casos compartilhados com o Swift
`curator/scripts/generate-segmentation-fixtures.mjs` grava em `Audits/fixtures/segmentation/<nome>.json`:
```json
{ "version": 3, "name": "...", "words": [{"text":"Hello,","start":0,"end":0.4,"timing":"word"}],
  "expected": { "beginner": [[0,2],[3,6]], "intermediate": [[...]], "advanced": [[...]] } }
```
Gere pelo menos estes 8 casos sintéticos:
1. Frases pontuadas curtas.
2. Fala longa sem pontuação com pausas de 0,35 s.
3. Fala corrida sem pausa nem pontuação (força limites por marcador).
4. "I want to go to the store" encostado em outra frase (testa os limites proibidos).
5. Pausa longa de 1,5 s no meio.
6. Uma palavra muito longa isolada (> `maxSeconds`).
7. "Yeah." solto entre duas frases.
8. Texto com `you know` / `I mean`.

Inclua também 3 casos reais, cada um com as **80 primeiras** palavras de candidatos em `curator/.state/review` (converta `segments` em palavras com distribuição proporcional e `timing: 'estimated'`). Os arquivos devem ser determinísticos (mesma entrada → mesmo JSON).

## Relatório
`node curator/scripts/segmentation-report.mjs` lê `curator/.state/review/*.json` (só leitura) e imprime, por nível: número de frases, p50/p90 de palavras e segundos, e % de limites em pontuação/pausa. Para itens antigos, use palavras estimadas a partir de `segments`.

## Testes (`segment.test.mjs`)
- Todos os fixtures: `segmentWords(words, level)` igual a `expected`.
- Propriedades em todos os fixtures e níveis:
  - as frases cobrem todas as palavras, em ordem, sem buracos;
  - nenhuma frase com ≥ 2 palavras passa de `maxWords`/`maxSeconds`;
  - nenhum limite fica depois de uma palavra de `FORBIDDEN_AFTER` quando havia alternativa sem custo proibido.
- No caso 1: todos os limites caem em pontuação.
- Ajuste os testes antigos de `quality.test.mjs` e `workflow.test.mjs` que dependiam de `limits`/`buildPhrases`, mantendo o que eles verificam.

## Critérios de aceite
- `cd curator && npm test` passa e o relatório roda sem erro (cole o resumo no STATUS).
- `scripts/verify.sh` → "Tudo passou."

## Não fazer
- Não alterar o Swift (tarefa 09) nem `.state/review` (tarefa 15).
