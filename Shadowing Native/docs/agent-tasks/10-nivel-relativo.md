# 10: Nível relativo ao conteúdo nativo (regras locais)

## Objetivo
Substituir `classify()` (régua absoluta) por uma **pontuação de dificuldade 0–100** feita com características medidas no próprio vídeo. O nível sai do **percentil** dessa pontuação dentro do catálogo: ~30% iniciante, ~40% intermediário, ~30% avançado. Cada frase também recebe uma dificuldade (fácil/média/difícil).

## Por quê
`classify` em `curator/quality.mjs` e `ShortDifficultyEstimator.swift` usam limites pensados para conteúdo didático: ≥ 165 palavras/min = avançado. Fala nativa quase sempre passa disso: 210 de 219 candidatos (96%) saíram "avançado". Assim o iniciante fica sem conteúdo nativo, e o app acabava buscando aula de inglês.

## Depende de
Tarefa 06 (palavras e frases por nível).

## Arquivos permitidos
- `curator/difficulty.mjs` (novo), `curator/difficulty.test.mjs` (novo)
- `curator/data/en-top10k.txt` (novo, gerado), `curator/data/README.md` (novo), `curator/data/level-thresholds.json` (gerado)
- `curator/scripts/calibrate-levels.mjs` (novo); script `"calibrate-levels"` em `curator/package.json`
- `curator/quality.mjs`, `curator/quality.test.mjs`, `curator/workflow.mjs`
- `ShadowingNative/Services/CatalogPayload.swift` (só para aceitar o campo opcional novo)

## Passos

### A. Lista de frequência (dependência autorizada só para gerar o arquivo)
```bash
python3 -m venv "${TMPDIR:-/tmp}/wordfreq-venv"
"${TMPDIR:-/tmp}/wordfreq-venv/bin/pip" install wordfreq
"${TMPDIR:-/tmp}/wordfreq-venv/bin/python" -c "from wordfreq import top_n_list; print('\n'.join(top_n_list('en', 10000)))" > curator/data/en-top10k.txt
```
Uma palavra por linha, em ordem de frequência. Em `curator/data/README.md`, registre a origem e a licença: *wordfreq*, de Robyn Speer, dados sob **CC BY-SA 4.0**, com o link `https://github.com/rspeer/wordfreq`. Se a instalação falhar, marque a tarefa como **bloqueada** no STATUS; não invente uma lista.

### B. `curator/difficulty.mjs`
```js
export function syllables(word) {
  const w = word.toLowerCase().replace(/[^a-z]/g, '');
  if (!w) return 0;
  const groups = w.match(/[aeiouy]+/g)?.length ?? 1;
  const silentE = w.length > 2 && w.endsWith('e') && !w.endsWith('le') && groups > 1 ? 1 : 0;
  return Math.max(1, groups - silentE);
}
const clamp01 = (x) => Math.min(1, Math.max(0, x));
const scale = (x, low, high) => clamp01((x - low) / (high - low));
export const SLANG = new Set(["gonna","wanna","gotta","kinda","sorta","y'all","ain't","lowkey","highkey","bro","dude",
  "nah","yo","bruh","lit","sus","cap","deadass","finna","tryna","lemme","gimme","dunno","bet","vibe","vibes"]);
```
`videoFeatures({ words, phrasesAdvanced, timingQuality, matchRatio, rank })` → objeto com:
- `syllablesPerSecond`: soma de sílabas ÷ soma das durações das frases avançadas (exclui pausas longas);
- `p90PhraseSyllablesPerSecond`: p90 das frases avançadas com ≥ 4 palavras (`0` se não houver);
- `rareShare2k` / `rareShare5k`: proporção de tokens alfabéticos normalizados (minúsculas, `’` → `'`) cujo `rank` (posição na lista; ausente = ∞) é ≥ 2000 / ≥ 5000;
- `slangShare`: tokens em `SLANG` ÷ total;
- `mismatch`: `1 - matchRatio` se `timingQuality === 'aligned'`; `0.25` se `'word'`; `0.35` se `'estimated'`.

`difficultyScore(f)`:
```js
100 * clamp01(
  0.40 * scale(f.syllablesPerSecond, 2.5, 6.0) +
  0.15 * scale(f.p90PhraseSyllablesPerSecond, 3.0, 7.5) +
  0.25 * scale(f.rareShare5k, 0.02, 0.15) +
  0.10 * scale(f.slangShare, 0, 0.04) +
  0.10 * scale(f.mismatch, 0, 0.4))
```
Arredonde para 1 casa decimal.

`levelFor(score, thresholds = { beginnerMax: 35, intermediateMax: 60 })`:
- `score ≤ beginnerMax` → `beginner`; `≤ intermediateMax` → `intermediate`; senão `advanced`;
- `levelConfidence = clamp01(distância até o limite mais próximo / 10)`.

`phraseDifficulty(phraseWords, rank)` → `0` fácil, `1` média, `2` difícil:
```js
50 * scale(sílabas/duração, 2.5, 7.0) + 50 * scale(rareShare5k da frase, 0, 0.25)
```
com cortes `< 40` → 0, `< 65` → 1, senão 2.

`loadRank()` lê `data/en-top10k.txt` e devolve `Map(palavra → posição)`. `loadThresholds()` lê `data/level-thresholds.json` ou usa o padrão.

### C. Integração em `prepare(...)`
Quando houver `words`:
- calcule `features`, `difficultyScore`, `level` e `levelConfidence`;
- guarde `difficulty: { score, confidence, features }`;
- guarde `phraseDifficultyByLevel: { beginner: [0,1,…], intermediate: […], advanced: […] }`, alinhado a `phrasesByLevel`;
- **não** chame `classify`.

Mantenha a checagem de sanidade: rejeite com `'Legenda insuficiente ou velocidade inválida'` se a duração for < 12 s ou > 185 s, se houver < 30 palavras ou se a velocidade for > 300 palavras/min (música ou legenda quebrada). `classify` fica só para itens antigos sem `words`.

`publishedPayload` (tarefa 08) passa a incluir `phraseDifficultyByLevel` e `difficulty.score`. Em `CatalogPayload.swift`, aceite `phraseDifficultyByLevel` como **opcional** (a tarefa 12 usa).

### D. Calibração
`npm run calibrate-levels` (`scripts/calibrate-levels.mjs`) lê `.state/review` e `.state/published` (só leitura). Para cada item, usa `words` se houver; senão, palavras estimadas a partir de `segments`, como no relatório da tarefa 06. Depois:
- calcula as pontuações;
- grava `data/level-thresholds.json` com `{ beginnerMax: p30, intermediateMax: p70, sampleSize, calibratedAt }`;
- imprime a distribuição antiga (`level` gravado) × a nova.

Rode uma vez e cole a saída no STATUS.

### E. Testes (`difficulty.test.mjs`)
- `syllables`: cat 1, water 2, beautiful 3, make 1, table 2, the 1, rhythm 1.
- Pontuação monotônica: aumentar a velocidade, a proporção de palavras raras ou a gíria (mantendo o resto) nunca diminui a pontuação.
- `levelFor` com os limites padrão: 20 → beginner, 50 → intermediate, 80 → advanced; confiança 0 exatamente no limite.
- Calibração com pontuações sintéticas de 1 a 100 → limites ≈ 30 e 70.
- `prepare` com `words` sintéticos lentos e de vocabulário comum → `beginner` (com limites padrão).

## Critérios de aceite
- Distribuição nova nos 219 itens perto de 30/40/30 (por construção do percentil). Os iniciantes devem ser de fato os de fala mais lenta: no STATUS, liste 5 títulos iniciantes e 5 avançados para conferência humana.
- `cd curator && npm test` e `scripts/verify.sh` → "Tudo passou."

## Fora do escopo
A lupa do app continua usando `ShortDifficultyEstimator`. Portar esta pontuação para o Swift (com a lista de palavras no app) fica para uma tarefa futura.
