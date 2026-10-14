> **CANCELADA em 14/10/2026.** O dono decidiu aceitar vídeos de professores de inglês no catálogo. **Não execute esta tarefa.** O arquivo fica só como referência.

# 02: Filtro de conteúdo de aula de inglês (app + curador)

## Objetivo
1. O app para de **pedir** aula de inglês ao YouTube.
2. App e curador **rejeitam** vídeos e canais didáticos com a mesma regra, testada pelos mesmos casos.

## Por quê
`ShortsDiscoveryService` monta consultas como `"\(beginnerQuery) English conversation beginner"`, `"street interview easy English"` e `"English \(discoveryQuery) intermediate listening"`. Elas trazem professores de inglês, e o produto quer só conteúdo nativo (ver `AGENTS.md`).

## Arquivos permitidos
- `ShadowingNative/Services/ShortsDiscoveryService.swift`
- `curator/quality.mjs`, `curator/quality.test.mjs`
- `Audits/fixtures/teaching-content.json` (novo)
- `Audits/RecommendationAudit.swift`

## Passos

### A. Lista compartilhada: `Audits/fixtures/teaching-content.json`
```json
{
  "titleTerms": ["learn english", "learning english", "english lesson", "english lessons", "english class",
    "english teacher", "english tutor", "esl", "efl", "ielts", "toefl", "toeic", "cefr", "phrasal verb",
    "phrasal verbs", "idiom", "idioms", "vocabulary", "vocab", "grammar", "pronunciation", "how to pronounce",
    "how to say", "speak english", "speaking practice", "english speaking", "fluent english", "sound like a native",
    "american accent", "british accent", "accent training", "english tips", "english conversation practice",
    "listening practice", "shadowing", "aprenda inglês", "aprender inglês", "aula de inglês", "dica de inglês", "inglês"],
  "channelTerms": ["english", "inglês", "ingles", "teacher", "tutor", "learn", "lesson", "fluency", "fluent", "idioma"],
  "transcriptMarkers": ["repeat after me", "in english we say", "this word means", "the meaning of", "how do you say",
    "let's practice", "today's lesson", "in this lesson", "pronounce it", "say it with me"],
  "cases": [
    {"title": "Learn English with Friends", "channel": "Some Channel", "teaching": true},
    {"title": "5 Phrasal Verbs Natives Use", "channel": "Some Channel", "teaching": true},
    {"title": "How to pronounce WATER in American English", "channel": "Some Channel", "teaching": true},
    {"title": "IELTS Speaking Band 9", "channel": "Some Channel", "teaching": true},
    {"title": "Aula de inglês: verb to be", "channel": "Some Channel", "teaching": true},
    {"title": "Funny moment", "channel": "English with Lucy", "teaching": true},
    {"title": "Funny moment", "channel": "mmmEnglish", "teaching": true},
    {"title": "Conan Can't Stop Laughing", "channel": "Team Coco", "teaching": false},
    {"title": "Would you rather fight 100 ducks?", "channel": "Jubilee", "teaching": false},
    {"title": "Gordon Ramsay tries street food", "channel": "Gordon Ramsay", "teaching": false},
    {"title": "NBA player trash talk mic'd up", "channel": "NBA", "teaching": false},
    {"title": "Hot dogs are sandwiches", "channel": "SubwayTakes with Kareem Rahma", "teaching": false}
  ]
}
```

### B. Regra (idêntica nos dois lados)
Primeiro normalize o texto: minúsculas, `’` → `'`.
- **Título:** é aula se contém algum `titleTerms` como palavra/expressão inteira. A comparação usa limites de palavra, ou seja, a regex `(^|[^\p{L}])termo($|[^\p{L}])`.
- **Canal:** é aula se contém algum `channelTerms` como **substring** (assim `mmmEnglish` é pego).
- **Transcrição (opcional):** é aula se ≥ 2 marcadores **distintos** de `transcriptMarkers` aparecem no texto.

Resultado: aula = título **ou** canal **ou** transcrição.

### C. Swift (`ShortsDiscoveryService.swift`)
1. Crie `nonisolated static func isTeachingContent(title: String, channel: String, transcript: String? = nil) -> Bool`, com as três listas como `static let`, copiadas **exatamente** do JSON.
2. Remova as consultas didáticas:
   - em `search(...)`, o ramo de `interest` usa sempre `$0.discoveryQuery`, sem `beginnerQuery`/"English conversation beginner";
   - em `searchVideos(...)`, `query = interest.discoveryQuery` para todos os níveis.
   
   Apague `beginnerQuery` se ficar sem uso. Troque `discoveryQuery` de `.streetInterviews` para `"street interview"` e de `.news` para `"news"`.
3. Aplique o filtro antes de pedir legenda:
   - `searchShorts` (junto com `titleSuggestsNoSpeech`);
   - candidatos de `discoverBatch`;
   - `verifyVideos`, por título e canal;
   - `searchChannels`, removendo canais cujo título seja didático.
   
   Depois de baixar a transcrição, em `verifySearchResult` e `verifyVideos`, rejeite também quando `isTeachingContent(..., transcript:)` for verdadeiro.

### D. JS (`curator/quality.mjs`)
1. Exporte `isTeachingContent({ title, channel, transcript })`. Leia as listas de `../Audits/fixtures/teaching-content.json` com `fs.readFileSync` + `JSON.parse`, usando um caminho relativo a `import.meta.url`.
2. Em `prepare(...)`, antes de `classify`, lance `new Error('Conteúdo de aula de inglês')` quando o texto juntado dos segmentos, o título ou o canal indicarem aula.

### E. Testes
- `quality.test.mjs`: um teste percorre `cases` e confere `teaching`. Outro confere que um texto com 2 marcadores é aula e com 1 não é.
- `RecommendationAudit.swift`: leia `Audits/fixtures/teaching-content.json` (o runner roda na raiz do projeto) e faça `precondition` em cada caso. Imprima `PASS teaching-content filter (N cases)`.

## Critérios de aceite
- `grep -rn "English conversation beginner\|easy English\|intermediate listening" ShadowingNative` não encontra nada.
- Os mesmos 12 casos passam no JS e no Swift.
- `scripts/verify.sh` → "Tudo passou."

## Não fazer
- Não filtrar por nome de canal específico (lista de bloqueio manual); use só a regra.
