# 11: Publicação automática com amostragem

## Objetivo
O curador publica **sozinho** todo candidato que passar nos critérios automáticos, sem depender de "canal confiável". Um a cada 10 publicados vira **amostra** para o dono ouvir no painel, que ganha os botões **Manter** e **Despublicar**.

## Por quê
Hoje há 0 publicados e 219 parados na revisão manual. `automaticReviewReasons` exige canal confiável (`trust-channel` após 3 publicações manuais) e recusa iniciantes. O feed (só catálogo, tarefa 01) fica vazio.

## Depende de
Tarefas 02 (filtro de aula), 06 (v2) e 08 (nível com confiança).

## Arquivos permitidos
- `curator/workflow.mjs`, `curator/workflow.test.mjs`
- `curator/curator.mjs` (`metadata`, `autoPublish`, `review`, novos comandos)
- `curator/review-store.mjs`, `curator/dashboard.mjs`, `curator/dashboard.test.mjs`, `curator/dashboard-public/*`
- `curator/run-service.mjs` (só se precisar repassar o comando novo), `curator/README.md`

## Passos

### A. Metadados
Em `curator.mjs → metadata(videoID)`, devolva também `categoryId: item.snippet.categoryId` e `defaultAudioLanguage: item.snippet.defaultAudioLanguage || item.snippet.defaultLanguage || null`. Grave esses campos no arquivo de `.state/metadata/` em `scan()`.

### B. Critérios: `automaticReviewReasons(prepared, metadata)`
Remova o terceiro parâmetro (`trustedChannelIDs`) e atualize os chamadores (`curator.mjs`, `review-store.mjs`). Retorne a lista de motivos (vazia = publicável):
1. `metadata.shortsFormatPassed !== true` → "Formato Short não verificado".
2. `isTeachingContent({ title, channel })` → "Conteúdo de aula de inglês".
3. Sem `prepared.words` **ou** `timingQuality === 'estimated'` → "Sem tempo real por palavra".
4. Mais de 10% das frases do próprio nível com `timingEstimated` → "Muitos cortes interpolados".
5. Algum nível de `phrasesByLevel` não passa em `phrasesArePractical` → "Trechos pouco práticos (<nível>)".
6. `metadata.categoryId === '27'` (Education) → "Categoria Educação".
7. `defaultAudioLanguage` preenchido e sem começar com `en` → "Áudio não está em inglês".
8. `prepared.difficulty?.confidence < 0.2` → "Nível no limite: conferir".
9. `prepared.interests` vazio → "Assunto não identificado".
10. Mantenha as checagens atuais de duração (20–185 s) e de "Tempos da legenda suspeitos".

**Remova:** "Canal não revisado", "Nível iniciante requer revisão", "Origem sem revisão de canal" e "Assunto do canal não confirmado". Os comandos `trust-channel`/`untrust-channel` podem continuar existindo, mas não afetam mais a publicação; diga isso no `curator/README.md`.

### C. Amostragem
1. Em `workflow.mjs`, exporte `isSample(videoID)`, determinística: `parseInt(sha1(videoID).slice(0, 8), 16) % 10 === 0`, com `node:crypto`.
2. Em `autoPublish()`:
   - remova o retorno antecipado `if (!trusted.length)`;
   - publique quem tiver `automaticReviewReasons(...).length === 0`;
   - grave no marcador `.state/published/<id>.json` também `{ automatic: true, sample: isSample(id), sampleReviewedAt: null }`.
   
   O limite por ciclo continua (`Math.min(requestLimit, 25)`).
3. Novos comandos em `curator.mjs`:
   - `unpublish <id>` (precisa do Firebase, então não entra em `localCommand`):
     - exige que o marcador publicado exista;
     - apaga o documento `approvedShorts/<id>`;
     - grava `.state/rejected/<id>.json` com `{ rejectedAt, reason: 'Despublicado na amostragem' }`;
     - remove o marcador de `.state/published/` (só este comando faz isso);
     - marca `state.processed[id] = 'rejected'`.
   - `keep-sample <id>` (local; inclua em `localCommand`): grava `sampleReviewedAt` no marcador publicado.

### D. Painel
1. Em `review-store.mjs → listCandidates`, crie o filtro `status=samples`: publicados com `sample === true` e `sampleReviewedAt` vazio. Inclua `samples` em `counts`.
2. Em `dashboard.mjs`:
   - aceite as ações `unpublish` e `keep` na regex de rota;
   - permita `unpublish`/`keep` só quando o candidato estiver `published` (as demais regras de status continuam);
   - em `runAction`: `unpublish` → `run-service.mjs unpublish <id>`; `keep` → `curator.mjs keep-sample <id>`.
   
   Mantenha **todas** as proteções atuais: só `127.0.0.1`, token, `Origin` e `content-type`.
3. Em `dashboard-public/`, crie a aba **"Amostras para ouvir"** com o contador. No detalhe de uma amostra, mostre os botões **Manter** e **Despublicar**; Despublicar pede confirmação ("Remover este Short do app?").
4. `dashboard.test.mjs`: teste a rota nova com `actionRunner` falso (sem rede); teste que `unpublish` em candidato pendente devolve 409.

### E. Testes (`workflow.test.mjs`)
- Candidato v2 perfeito → sem motivos.
- Um caso para cada motivo de B (1 a 9).
- `isSample` é determinística e marca ~10% de 1.000 IDs sintéticos (entre 7% e 13%).

## Critérios de aceite
- `cd curator && npm test` e `scripts/verify.sh` → "Tudo passou."
- `curator/README.md` atualizado (publicação automática, amostras, despublicar).

## Não fazer
- Não rodar `publish:configured`, `scan:configured` ou o serviço. Nada é publicado durante a tarefa.
