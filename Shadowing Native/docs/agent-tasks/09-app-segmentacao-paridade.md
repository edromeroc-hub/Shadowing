# 09: App: a mesma segmentação no Swift (paridade com o curador)

## Objetivo
Reescrever `ShadowingLessonBuilder` com **exatamente** o algoritmo da tarefa 06. Vídeos abertos pela lupa ou por link importado são divididos no aparelho e precisam ficar iguais aos do catálogo.

## Por quê
O builder atual só **junta** blocos de legenda: nunca divide um bloco longo, então legendas manuais de 2 linhas viram frases enormes (`needsExpandedPractice`). Ter duas lógicas diferentes também faz o mesmo vídeo ser dividido de um jeito no catálogo e de outro na lupa.

## Depende de
Tarefas 06 (especificação e casos em `Audits/fixtures/segmentation/`) e 08.

## Arquivos permitidos
- `ShadowingNative/Services/ShadowingLessonBuilder.swift`
- `ShadowingNative/Services/ShortDifficultyEstimator.swift` (só se necessário; ver "Atenção")
- `Audits/SegmentationLayoutAudit.swift`
- `Audits/SegmentationParityAudit.swift` (novo), `Audits/run-segmentation-parity.zsh` (novo)

## Passos
1. Em `ShadowingLessonBuilder.swift`, mantenha a API pública: `init(level: EnglishLevel = .advanced)` e `func build(from transcript: YouTubeTranscript) -> [ShadowingPhrase]`. Os chamadores (`ShortsFeedView`, `ShortDifficultyEstimator`) não mudam.
2. Crie `struct TimedWord: Sendable, Equatable { text: String; start: Double; end: Double; timing: Timing }`, com `enum Timing { case word, interpolated, estimated }`.
3. **Segmentos → palavras** (a mesma regra do passo 1 da tarefa 04):
   - remova `[...]`, `(...)` e `♪`;
   - divida por espaços;
   - com mais de um token por segmento, distribua `[start, end]` proporcionalmente aos caracteres;
   - `timing = .word` se `segment.hasWordTiming`, senão `.estimated`;
   - aplique a higiene: `start` não decrescente, `end = min(end, próximo.start)`, `end >= start + 0.04`, arredondado para milissegundos.
4. Exponha `static func segmentWords(_ words: [TimedWord], level: EnglishLevel) -> [ClosedRange<Int>]`, uma tradução **linha a linha** de `segmentWords` em `curator/segment.mjs`:
   - mesmas constantes, conjuntos e regexes;
   - `norm` com a mesma regra: `’` → `'`, minúsculas, remover das pontas o que não for letra/dígito/`'`;
   - laço com `i` crescente e comparação `total < best[end] - 1e-9`;
   - use `Double` e a mesma ordem de somas que o JS.
5. `build(from:)`: palavras → `segmentWords(words, level)` → `ShadowingPhrase`:
   - `text` = palavras unidas por espaço; `start` = primeira palavra; `end` = última palavra;
   - `sourceSegmentCount` = número de palavras;
   - `needsExpandedPractice` = (`count == 1 && duration > maxSeconds`);
   - `endingHasWordTiming` = última palavra é `.word`.
6. Remova o código antigo (`PhraseGroup`, `repair*` etc.) que ficar sem uso.

## Auditorias
- **Nova** `Audits/SegmentationParityAudit.swift` + `run-segmentation-parity.zsh`. Compile com `LearningProfile.swift`, `YouTubeTranscript.swift`, `ShadowingPhrase.swift`, `ShadowingLessonBuilder.swift`. Para cada `Audits/fixtures/segmentation/*.json`:
  - decodifique `words` em `TimedWord` (`timing` como string `word`/`interpolated`/`estimated`);
  - confira `segmentWords` == `expected` em cada nível;
  - imprima `PASS segmentation parity (N fixtures × 3 levels)`.
  
  Qualquer diferença → `preconditionFailure` mostrando o nome do caso, o nível e as duas listas.
- **Ajustar** `Audits/SegmentationLayoutAudit.swift`. As expectativas antigas de "bloco atômico vira 1 frase com `needsExpandedPractice`" deixam de valer. Mantenha as garantias de: nenhuma palavra perdida; ordem preservada; frases sem sobreposição; frases com ≥ 2 palavras dentro de `maxWords`/`maxSeconds` do nível; início e fim de frase coincidindo com o início ou fim de alguma palavra.

## Atenção
`ShortDifficultyEstimator` usa `ShadowingLessonBuilder().build` para medir o tamanho típico de frase. Se `Audits/run-recommendations.zsh` falhar por isso, ajuste **apenas** o estimador para manter os resultados esperados pela auditoria. Por exemplo, calcule `typicalPhraseLength` e `fastestPhrase` sobre os segmentos da legenda em vez das frases. Registre no STATUS o que mudou. Não altere as `precondition` da auditoria de recomendações.

## Critérios de aceite
- A paridade passa em todos os casos e níveis.
- `scripts/verify.sh` → "Tudo passou.", sem avisos novos de concorrência.

## Não fazer
- Não mudar as constantes do algoritmo sem mudá-las também em `curator/segment.mjs` e regenerar os casos de teste (isso seria outra tarefa).
