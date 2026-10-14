# 08: Catálogo versão 2 (palavras com tempo + frases dos 3 níveis)

## Objetivo
O documento publicado em `approvedShorts` passa a carregar as **palavras com tempo** e as frases **dos 3 níveis** (intervalos de índices de palavras). O app usa as frases do nível do aluno. Documentos v1 continuam funcionando.

## Depende de
Tarefa 06 (`words`, `phrasesByLevel`, `SEGMENTATION_VERSION`).

## Arquivos permitidos
- `curator/quality.mjs`, `curator/quality.test.mjs`, `curator/curator.mjs`
- `ShadowingNative/Services/CatalogPayload.swift` (novo; depois rode `xcodegen generate`)
- `ShadowingNative/Services/SharedShortCatalog.swift`
- `Audits/CatalogPayloadAudit.swift` (novo), `Audits/run-catalog-payload.zsh` (novo)
- `Audits/fixtures/catalog/*.json` (novos)

## Formato v2 (string JSON no campo `payload`)
```json
{
  "version": 2,
  "videoID": "abcdefghijk", "title": "...", "channel": "...", "channelID": "UC...",
  "languageCode": "en", "source": "mac-curator", "level": "intermediate", "interests": ["humor"],
  "timingQuality": "aligned",
  "words": [["Hello,", 0.12, 0.48, 0], ["how", 0.48, 0.61, 0]],
  "phrasesByLevel": { "beginner": [[0, 5], [6, 11]], "intermediate": [[0, 9]], "advanced": [[0, 12]] },
  "affinity": {}
}
```
- `words[i] = [texto, início, fim, timing]`, com `timing`: `0` = palavra (tempo real), `1` = interpolado, `2` = estimado.
- Cada lista de `phrasesByLevel` cobre `0…words.length-1` em ordem, sem buracos.
- Campos do documento Firestore fora do payload: os mesmos de hoje (`status`, `level`, `interests`, `payload`, `verifiedAt`), mais `version: 2`.

## Passos

### A. Curador
1. Em `quality.mjs`, exporte `publishedPayload(prepared)`, uma função pura:
   - se `prepared.words` existir, monta o v2 acima (arredonde tempos para milissegundos; **não** inclua `segments` nem `phrases`);
   - senão, devolve o objeto v1 como hoje.
2. Em `curator.mjs → publishCandidate`, use `JSON.stringify(publishedPayload(prepared))` e grave `version` no documento. Mantenha a checagem de tamanho (750 000 bytes) sobre o payload final.
3. O arquivo local em `.state/review/` continua com `phrases` expandidas (o painel usa) **e** com `words`/`phrasesByLevel`.
4. Gere 2 casos em `Audits/fixtures/catalog/` a partir de um `prepared` sintético:
   - `v2-sample.json`: o payload v2;
   - `v2-sample.expected.json`: `{ "beginner": [{"text","start","end"}...], ... }`, as frases esperadas por nível.
   
   Inclua também `v1-sample.json`, com o formato atual.

### B. App
1. Mova `CatalogSegment`, `CatalogPhrase`, `CatalogPayload` e `PreparedShortLesson` de `SharedShortCatalog.swift` para o novo `CatalogPayload.swift`, que importa **só Foundation**. Crie a função de entrada:
   ```swift
   enum CatalogPayloadDecoder {
       static func lesson(from payload: String, documentID: String, level: EnglishLevel) -> PreparedShortLesson?
   }
   ```
   - Primeiro decodifique um `struct VersionProbe: Decodable { let version: Int }`.
   - `version == 1` → o caminho atual (`preparedLesson()`).
   - `version == 2` → o novo decodificador. Cada palavra é um array heterogêneo: use `init(from:)` com `unkeyedContainer()` lendo `String`, `Double`, `Double`, `Int`.
   - Valide que `videoID == documentID`, os tempos são finitos e crescentes (`end > start`), o nível existe e as faixas de `phrasesByLevel[level.rawValue]` são contíguas e cobrem todas as palavras. Qualquer falha → `nil`.
   - Monte `YouTubeTranscript.segments` a partir das palavras (`hasWordTiming: timing == 0`).
   - Monte as frases do **nível do aluno**: `ShadowingPhrase(text: palavras unidas por espaço, start: words[i].start, end: words[k].end, sourceSegmentCount: k - i + 1, needsExpandedPractice: false, endingHasWordTiming: words[k].timing == 0)`.
2. Em `SharedShortCatalog.nextPage(for:)`, troque a decodificação local por `CatalogPayloadDecoder.lesson(from:documentID:level:)` com `profile.level`. A consulta Firestore não muda.
3. Rode `xcodegen generate` para incluir o arquivo novo no projeto.

### C. Auditoria `Audits/CatalogPayloadAudit.swift` (+ runner no formato dos existentes)
Compile com: `LearningProfile.swift`, `YouTubeTranscript.swift`, `ShadowingPhrase.swift`, `YouTubeShortItem.swift`, `CatalogPayload.swift`. Verifique:
- `v2-sample.json` gera, para cada nível, exatamente as frases de `v2-sample.expected.json` (texto, início e fim com tolerância de 0,001);
- `v1-sample.json` continua decodificando;
- payload com faixa faltando, `videoID` diferente ou tempo decrescente → `nil`.

Imprima `PASS catalog payload v1/v2`.

## Critérios de aceite
- `cd curator && npm test` passa, com um teste de `publishedPayload` (v2 sem `segments`/`phrases`; v1 inalterado).
- `scripts/verify.sh` → "Tudo passou." (ele roda o novo runner automaticamente).

## Não fazer
- Não mudar `firestore.rules` nem os índices.
- Não republicar nada; só o usuário publica.
