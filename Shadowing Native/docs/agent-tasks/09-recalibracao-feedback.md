# 09: Recalibrar o nível pelo uso ("Muito fácil" / "Muito difícil")

## Objetivo
Os alunos já avaliam a dificuldade no menu do Short ("Muito fácil", "No meu ritmo", "Muito difícil"), mas esse voto só fica no aparelho. Esta tarefa envia o voto junto com o sinal que já vai ao Firestore. A agregação diária do Mac passa a **mover o vídeo de nível** quando houver evidência suficiente.

## Depende de
Tarefa 08.

## Arquivos permitidos
- `ShadowingNative/Services/ShortCatalogSignals.swift`
- `ShadowingNative/Views/Shorts/ShortsFeedView.swift` (só o `onRateDifficulty`)
- `firestore.rules` (**autorizado** apenas para a mudança abaixo; **sem deploy**)
- `curator/quality.mjs`, `curator/quality.test.mjs`, `curator/curator.mjs` (função `aggregate`)

## Passos

### A. App
1. Em `ShortCatalogSignals.record(item:profile:reaction:)`, adicione o parâmetro opcional `difficulty: ShortDifficultyRating? = nil`. Quando vier, grave `fields["difficulty"] = difficulty.rawValue` (`tooEasy` | `justRight` | `tooHard`).
2. No `onRateDifficulty` de `ShortsFeedView` (perto da linha que já chama `progressStore.rateDifficulty(of:as:)`), chame também `Task { await ShortCatalogSignals.record(item: item, profile: appModel.profile, reaction: progressStore.shortFeedback[item.videoID]?.reaction, difficulty: rating) }`.

### B. Regras (sem deploy)
Em `firestore.rules`, bloco `match /votes/{videoID}`:
- inclua `'difficulty'` em `hasOnly([...])`;
- adicione `&& (!('difficulty' in request.resource.data) || request.resource.data.difficulty in ['tooEasy', 'justRight', 'tooHard'])`.

**Não altere mais nada nas regras.** No STATUS, avise: *"o usuário precisa rodar `firebase deploy --only firestore:rules` ANTES de distribuir esta build; senão os votos com dificuldade serão recusados."*

### C. Curador
1. Em `quality.mjs`, exporte a função pura `recalibratedLevel(currentLevel, signals)`:
   - considere só sinais com `difficulty` e com `signal.level === currentLevel` (alunos do mesmo nível do vídeo);
   - com `total ≥ 5`: se `tooHard / total ≥ 0.6` e houver nível acima, sobe um nível; se `tooEasy / total ≥ 0.6` e houver nível abaixo, desce um;
   - senão, mantém;
   - retorna `{ level, changed, votes: { tooEasy, justRight, tooHard } }`.
2. Em `curator.mjs → aggregate()`, depois de calcular a afinidade, aplique `recalibratedLevel(prepared.level, signals)`. Se mudar:
   - atualize `prepared.level`;
   - atualize o campo `level` do documento (`reference.update({ level, payload })`);
   - registre `NÍVEL <id> <antigo> → <novo> (<votos>)`.
   
   Um vídeo muda **no máximo um nível por agregação**. Para documentos v2, as frases dos 3 níveis já estão no payload; nada mais muda.

### D. Testes (`quality.test.mjs`)
- 4 votos `tooHard` → não muda (abaixo do mínimo).
- 5 de 6 `tooHard` em `intermediate` → `advanced`.
- 4 de 6 `tooEasy` em `beginner` → continua `beginner` (não há nível abaixo).
- Votos de alunos de outro nível são ignorados.

## Critérios de aceite
- `scripts/verify.sh` → "Tudo passou."
- STATUS com o aviso de deploy das regras.

## Não fazer
- Não rodar `aggregate:configured` nem fazer deploy.
