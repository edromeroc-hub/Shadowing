# Auditoria no simulador: entrega de Shorts, recomendações, visual e cortes (14/10/2026)

Ambiente:
- iPhone 17 (iOS 26.5, 402 × 874 pt), app Debug, conta real conectada;
- catálogo com 682 Shorts publicados pelo Caminho B.

O perfil da conta foi trocado durante os testes e **restaurado ao original** (avançado; tecnologia, vida real e aviação; 10 min). A restauração foi conferida no armazenamento do app. Prints em `Audits/simulador-2026-10-14/`.

## Resumo

| # | Gravidade | Problema | Situação |
|---|---|---|---|
| 1 | **P0** | Shorts do catálogo mostravam o retângulo "Prévia de layout" **no lugar do vídeo** | ✅ corrigido |
| 2 | **P1** | O vídeo vazava o começo da palavra seguinte ao fim de cada frase | ✅ corrigido e medido |
| 3 | **P1** | Todo aluno do mesmo perfil via sempre os mesmos Shorts primeiro (ordem alfabética de ID) | ✅ corrigido |
| 4 | P2 | Aba Vídeos pedia 12 legendas ao YouTube ao mesmo tempo (risco de bloqueio 429) | ✅ corrigido |
| 5 | P2 | Lupa: busca de canais em português trazia canais brasileiros sem legenda em inglês | ✅ corrigido |
| 6 | P2 | Conteúdo rolado passava por baixo do título (lupa, Vídeos e Progresso) | ✅ corrigido |
| 7 | P3 | "Interesses · 1 temas" (plural) | ✅ corrigido |
| 8 | P3 | Rótulo de tema podia mostrar um tema fora do perfil | ✅ corrigido |
| 9 | P3 | Com o início sorteado, a primeira página podia vir com poucos itens ("1/5") | ✅ corrigido |
| 10 | P2 | Legenda queimada no vídeo entrega a resposta em Lacunas e Frase inteira | 📋 decisão de produto |
| 11 | P2 | Erro "Não foi possível reproduzir este trecho" uma vez, ao ligar a tradução | ✅ corrigido (nova tentativa automática) |
| 12 | P3 | Demais observações (abaixo) | 📋 relatado |

## 1. P0: "Prévia de layout" no lugar do vídeo

- **Causa:** `ShortLessonPage.player(height:)` exibia o retângulo da auditoria de layout sempre que `preparedTranscript != nil`. Só que o catálogo também entrega a legenda pronta. Com o feed só do catálogo, **nenhum Short tocaria vídeo para os alunos**. O bug já existia no commit `0392903`; só não aparecia porque o catálogo estava vazio.
- **Correção:** novo parâmetro `isLayoutPreview`, que é verdadeiro só quando não há aula do catálogo e existe a legenda fixa da prévia (`ShortsFeedView.swift`).
- **Evidência:** prints `01` (antes) e `02` (depois, vídeo tocando).

## 2. P1: vazamento da palavra seguinte

**Causa:**
- A legenda automática só marca o **início** de cada palavra, então o fim da frase é exatamente o início da próxima. Isso vale para 96% das 11.536 frases com palavra seguinte no catálogo.
- O player pausa sempre um pouco depois do pedido.
- Não havia margem: `endAdvanceMilliseconds` = 0.

**Correção** (vale para os 682 publicados, a lupa e os links importados, sem republicar):
- `PhraseBoundary.applyingPlaybackEnds` (`Models/ShadowingPhrase.swift`) calcula `playbackEnd`:
  - 120 ms antes da palavra seguinte;
  - ou 40 ms quando a última palavra é curta demais, sem cortá-la (duração mínima estimada por sílabas).
- O fim seguro é preenchido em `CatalogPayload.preparedLesson()` e `ShadowingLessonBuilder.build`.
- O player usa `playbackEnd` no intervalo. Texto, progresso e pausa continuam usando `end`.
- Em DEBUG, `--disable-safe-end` volta ao comportamento antigo, para comparação.

**Medição no simulador** (logs `PlaybackTiming`; posição da pausa em relação ao início da palavra seguinte):

| | Antes | Depois |
|---|---|---|
| Amostras (frases distintas) | 32 (6) | 21 (7) |
| Pausas **depois** do início da palavra seguinte | **32 (100%)** | **0 (0%)** |
| Mediana | 14 ms depois | 106 ms antes |
| Pior caso | 33 ms depois | 67 ms antes |
| Latência do player (mediana) | 10 ms | 7 ms |

- **Evidência visual:** print `03`. Pausado em 4,17 s, a legenda queimada do vídeo já mostra "and there's nowhere", e a frase termina em 4,16 s, onde começa "and". No print `04`, pausado dentro da frase, a legenda mostra "As fans crowded onto the escalator,".
- **Nas 12.039 frases reais:** o fim é recuado em 92%. A última palavra fica com pelo menos 80 ms (p1) e mediana de 440 ms.
- **Testes:** `Audits/SegmentationLayoutAudit.swift` cobre palavras coladas, silêncio depois da frase, última palavra curta, frase sem palavra seguinte e frases da lupa.
- **Pendente:** ouvir 10 frases no iPhone físico. A latência do aparelho pode diferir da do simulador, e o tempo da legenda automática tem erro próprio.

## 3. P1: mesmos Shorts primeiro para todos

- **Causa:** o Firestore devolve em ordem de ID, e o motor desempata por ID. Os primeiros vídeos de qualquer aluno eram os de ID `-…` e `0…`.
- **Correção:** `SharedShortCatalog` começa num ID sorteado por sessão (`order(by: documentID).start(at:)`), volta ao começo (`end(before:)`) e completa a primeira página na mesma chamada.
- **Verificação:**
  - a consulta foi testada no Firestore real com o índice atual;
  - o verificador simulou 54 perfis × 5 sorteios: sem duplicatas, 100% de cobertura, primeiros vídeos diferentes a cada sessão;
  - no simulador, o primeiro Short mudou entre aberturas.

## 4 a 9. Correções menores

- **4.** `ShortsDiscoveryService.verifyVideos`: no máximo 3 legendas por vez; para ao achar os 2 vídeos que a tela usa. A auditoria de recomendações continua passando.
- **5.** `searchChannels` usa `youtubeQuery` ("viagem" → "travel"), como a busca de Shorts. Evidência: print `06`.
- **6.** `opaqueTopScrollEdge()` (`ShadowingTheme.swift`) aplica o efeito de borda "hard" no iOS 26, que ignora `toolbarBackground`. Também foi acrescentado `toolbarBackground(.visible)` para iOS 17 e 18. Evidência: prints `07`/`11` (antes) e `12` (depois).
- **7.** "1 tema" / "N temas" (`HomeViews.swift`). Evidência: print `08`.
- **8.** `displayTopic`: mostra um tema em comum com o perfil, em vez de `item.topic` (primeiro item de um Set, em ordem aleatória). Observação honesta: o "Culinária" visto no teste vinha de um tema marcado sem querer por um toque meu, mas o problema existe para vídeos com vários temas.
- **9.** Coberto pela correção 3.

## 11. P2: erro intermitente "Não foi possível reproduzir este trecho"

Apareceu uma vez ao ligar a tradução, quando o vídeo encolheu (print `09`). Não voltou em 9 tentativas de estresse.

**Causa:** o app desistia na primeira falha, em dois caminhos:
- **Busca do trecho ignorada:** `playShadowingRange` pedia `seekTo` ao YouTube **uma vez** e, se o pedido fosse ignorado (o que acontece durante um redimensionamento do player), esperava 8 s e mostrava o erro (`seek-timeout`);
- **Erro momentâneo do YouTube** (`onError` código 5, falha do player HTML5): o app também mostrava o erro de imediato.

**Correção:**
- `YouTubePlaybackScript.swift`: enquanto espera a busca, repete o `seekTo` a cada 1,5 s; o tempo-limite de 8 s continua como último recurso.
- `YouTubePlayerView.swift`: para falhas passageiras (`seek-timeout` e código 5), tenta de novo sozinho uma vez, com no máximo uma tentativa a cada 10 s, para não entrar em loop. Só então mostra a mensagem.
- Falhas permanentes ganham mensagens específicas:
  - 100: "vídeo removido ou indisponível";
  - 101/150: "o dono não permite reproduzir fora do YouTube".
- DEBUG: o código do erro é registrado (`phase=error value=…`), e `--simulate-playback-error=<código>` injeta uma falha para teste.

**Verificação:**
- `Audits/PlaybackBoundaryAudit.js` ganhou dois casos: a busca ignorada é repetida e toca quando chega ao início; quando o player fica travado, há várias tentativas e o erro só aparece após 8 s.
- No simulador, com falha injetada:
  - **código 5:** erro às 09:23:03, nova tentativa automática, trecho concluído 3 s depois, loop normal e **nenhuma mensagem** para o aluno (print `14`);
  - **código 150:** mensagem específica, sem novas tentativas (print `15`).

## Entrega e recomendação (sem simulador, com o motor real)

- Catálogo exportado e passado pelo `ShortsRecommendationEngine.feed` real, simulando a paginação do app, em 54 perfis (3 níveis × 14 temas + 4 combinações).
- **Resultado:** nenhuma duplicata, nenhum Short de nível ou tema errado, 100% do elegível alcançado. Os 682 documentos decodificam com o código do app.
- **Combinações vazias:** iniciante + aviação e iniciante + entrevistas de rua. No app, o estado vazio aparece corretamente, com a lupa e sem cair em vídeos de fora do catálogo (print `05`).
- **Combinações com menos de 5 vídeos:** iniciante em tecnologia (4), negócios (2), fitness (4) e culinária (2).
- **Concentração de canal:** em aviação intermediário, o Boldmethod aparece até 9 vezes seguidas. É falta de variedade no catálogo, não bug.
- 9 frases se sobrepõem por 10 a 40 ms (arredondamento da curadoria). São inofensivas, e o fim seguro já resolve.

## Relatado, sem correção (decisão de produto ou fora do escopo)

- **Legenda queimada entrega a resposta (P2):** em Lacunas, o próprio vídeo mostra "about learning" com a lacuna "about" (print `10`). Muitos Shorts têm legenda embutida. Sugestão: cobrir o terço inferior do vídeo nos modos de Escuta ativa.
- **Recomendações de vídeos ralas:** a aba Vídeos mostra 2 por tema, vindos da busca ao vivo no YouTube. Com um tema só, aparecem só 2. O selo "Inglês real sobre aviação" aparece em vídeos de professor.
- **Lupa:** o campo não recebe foco ao abrir; é preciso tocar nele antes de digitar.
- **Texto grande (xxxLarge):** o cabeçalho "SHADOWING SHORTS" quebra em 2 linhas e corta o tema ("Intermediário • Vi…"), como mostra o print `13`. O restante da tela se adapta.
- **O tamanho do vídeo muda entre os modos** (Shadowing, tradução, Lacunas, Frase inteira), o que causa um "pulo" visual.
- **Quando o vídeo pausa**, o player do YouTube mostra a própria interface por cima (logo Shorts, curtidas, título). Isso vem do player oficial.
- **A tradução da Apple não roda no simulador** (o app avisa); só dá para testar no aparelho.

## Pendências

1. **iPhone 16e e iPad não foram auditados:** o acesso a esses simuladores não foi liberado. O iPhone 16e tinha sido auditado em 07/10.
2. **Teste de ouvido** em 10 frases no iPhone físico, para confirmar que a última palavra não é cortada.
3. **Efeitos dos testes na conta real:** cerca de 157 palavras e 14 frases entraram no progresso de hoje, alguns Shorts aparecem em "Seu histórico" e houve sinais de visualização no Firestore. Nenhuma curtida, ocultação ou avaliação foi feita.
4. Sem commit. Arquivos alterados:
   - `Models/ShadowingPhrase.swift`
   - `Services/SharedShortCatalog.swift`, `ShadowingLessonBuilder.swift`, `ShortsDiscoveryService.swift`
   - `Views/Player/YouTubePlayerView.swift`, `YouTubePlaybackScript.swift`
   - `Views/Shorts/ShortsFeedView.swift`
   - `Views/Home/HomeViews.swift`
   - `Design/ShadowingTheme.swift`
   - `Audits/SegmentationLayoutAudit.swift`, `PlaybackBoundaryAudit.js`
   - `docs/agent-tasks/STATUS.md`

## Verificação

`scripts/verify.sh` → "Tudo passou.": testes do curador e da curadoria-gemini, auditorias de recomendação, segmentação (com os casos de `PhraseBoundary`) e limites de reprodução, e o build do Xcode.
