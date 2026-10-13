# 10: Ajudas para o iniciante (0,75× e pular frases difíceis)

## Objetivo
O iniciante pratica com conteúdo **nativo**, mas com duas ajudas:
1. velocidade padrão **0,75×**, com um botão para alternar 0,75× / 1×;
2. opção **"Pular frases difíceis"**, que usa a dificuldade por frase da tarefa 08.

## Depende de
Tarefas 06 (decodificador v2) e 08 (`phraseDifficultyByLevel` opcional).

## Arquivos permitidos
- `ShadowingNative/Views/Player/YouTubePlayerView.swift`
- `ShadowingNative/Services/CatalogPayload.swift`
- `ShadowingNative/Views/Shorts/ShortsFeedView.swift`
- `Audits/CatalogPayloadAudit.swift`, `Audits/fixtures/catalog/*.json`

## Passos

### A. Velocidade (`YouTubePlayerView.swift` → `YouTubePlayerController`)
1. Adicione `var preferredPlaybackRate = 1.0` e `func setPlaybackRate(_ rate: Double)`. A função guarda o valor (limitado a 0,5…1,0) e roda `evaluate("player && player.setPlaybackRate && player.setPlaybackRate(\(rate));")`.
2. No `case "ready":` de `receive(_:)`, depois do código atual, reaplique `preferredPlaybackRate` quando ela for diferente de 1.
3. O tempo de espera do aluno já usa `playbackRate`, que é atualizado pelo evento `onPlaybackRateChange`. Não mude essa lógica.

### B. Preferência e botão (`ShortsFeedView.swift` → `ShortLessonPage`)
1. Use `@AppStorage("shadowing.shorts.playbackRate") private var storedRate: Double = 0`. O valor 0 significa "ainda não escolhido", e nesse caso o padrão é `appModel.profile.level == .beginner ? 0.75 : 1.0`.
2. Ao preparar o player (onde hoje se conecta o controller ou no `onAppear` da página), chame `playerController.setPlaybackRate(rate)`.
3. Na barra de controles (perto de "Frase anterior"/"Próxima frase", com o mesmo `controlButton`), adicione um botão com o texto `0,75×` ou `1×` e a acessibilidade "Velocidade de reprodução". Ele alterna, grava em `storedRate` e chama `setPlaybackRate`.

### C. Pular frases difíceis
1. Em `CatalogPayload.swift`, inclua `phraseDifficulty: [Int]?` em `PreparedShortLesson`, preenchido por `phraseDifficultyByLevel[level]`, quando existir e tiver o mesmo tamanho das frases.
2. Em `ShortsFeedView`, passe `preparedLessons[item.videoID]?.phraseDifficulty` para `ShortLessonPage` (novo parâmetro `phraseDifficulty: [Int]?`).
3. Em `ShortLessonPage`, use `@AppStorage("shadowing.shorts.skipHardPhrases") private var skipHard = false`, com o padrão `true` para iniciante na primeira vez (mesma técnica do 0 = não escolhido, usando um `Int`).
   - Quando ativo e `phraseDifficulty` existir, `movePhrase(by:)` pula os índices com valor `2`.
   - Se **todas** as próximas forem difíceis, não pule.
4. No menu "…" do Short, adicione o toggle "Pular frases difíceis", visível só quando `phraseDifficulty` existir.
5. Mostre um selo pequeno "difícil" ao lado do contador `x/y` quando a frase atual tiver dificuldade 2.

### D. Auditoria
Em `Audits/CatalogPayloadAudit.swift`: inclua `phraseDifficultyByLevel` em `v2-sample.json` e confira que `phraseDifficulty` chega com o tamanho certo. Um array de tamanho errado → `phraseDifficulty == nil`, mas a lição continua válida.

## Critérios de aceite
- `scripts/verify.sh` → "Tudo passou.", sem avisos novos.
- Textos da interface em português.

## Não fazer
- Não mudar `endAdvanceMilliseconds` nem a lógica de limite do player (ver `Audits/PlaybackBoundaryCalibration.md`).
