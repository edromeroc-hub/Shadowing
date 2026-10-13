# AGENTS.md: Shadowing Native

Instruções permanentes para agentes de código (Gemini no Xcode, Gemini CLI, Codex, Claude). Leia este arquivo inteiro antes de qualquer tarefa.

## Produto

App iOS (SwiftUI) de **shadowing**: o aluno ouve um trecho curto de um YouTube Short, pausa e repete em voz alta. Público: brasileiros aprendendo inglês.

**Regra de ouro do conteúdo:** os vídeos são **inglês nativo e natural**, o que o americano rola no dia a dia: talk show, late night, entrevista de rua, humor, podcast, esporte, culinária, vlog. **Nunca** usar aula, dica ou professor de inglês, **nem para iniciante**. Exemplos proibidos: "learn English", ESL, IELTS, phrasal verbs, pronúncia, vocabulário.

**Nível é relativo:** iniciante = os ~30% mais fáceis *dentro do conteúdo nativo* (fala mais lenta e clara, palavras comuns). O iniciante recebe ajudas na prática (frases curtas, velocidade 0,75×), não vídeos didáticos.

## Mapa do código

| Caminho | O que é |
|---|---|
| `ShadowingNative/` | App SwiftUI (iOS 17+, Swift 6, concorrência estrita) |
| `ShadowingNative/Services/SharedShortCatalog.swift` | Lê o catálogo aprovado (`approvedShorts` no Firestore). **Fonte do feed.** |
| `ShadowingNative/Services/ShortsDiscoveryService.swift` | Busca no YouTube Data API: lupa da aba Shorts e descoberta antiga |
| `ShadowingNative/Services/YouTubeTranscriptService.swift` + `TranscriptJSONParser.swift` | Baixa legendas (player Android → `captionTracks` → `fmt=json3`, com tempo por palavra `tOffsetMs`) |
| `ShadowingNative/Services/ShadowingLessonBuilder.swift` | Divide a legenda em frases de prática |
| `ShadowingNative/Services/ShortDifficultyEstimator.swift` | Estimativa de nível no aparelho (fallback da lupa) |
| `ShadowingNative/Services/ShortsRecommendationEngine.swift` | Ordena o feed |
| `ShadowingNative/Views/Shorts/ShortsFeedView.swift` | Aba Shorts (feed + `ShortsSearchView`, a lupa) |
| `ShadowingNative/Views/Player/YouTubePlayerView.swift` | Player IFrame do YouTube em `WKWebView` |
| `curator/` | Curador em Node 20 (ESM) que roda no Mac: busca Shorts, baixa legendas, classifica, divide em frases e publica no Firestore |
| `curator/quality.mjs` | Normalização, frases, nível, temas, regras de praticidade |
| `curator/workflow.mjs` | Orçamento de buscas e regras de publicação automática |
| `curator/curator.mjs` | Comandos: `scan`, `publish`, `reject`, `resegment`, `aggregate`, `audit-shorts`… |
| `curator/dashboard.mjs` + `dashboard-public/` | Painel local de revisão (`127.0.0.1:4318`) |
| `curator/.state/` | Estado local: `review/` (candidatos), `metadata/`, `published/`, `rejected/` |
| `Audits/` | Auditorias executáveis (Swift via `swiftc`, JS via `node`) |
| `docs/agent-tasks/` | **Tarefas para você executar**, uma por arquivo, e `STATUS.md` |

O projeto Xcode é gerado por **XcodeGen** a partir de `project.yml`. Prefira editar arquivos Swift existentes. Se criar um arquivo `.swift` novo dentro de `ShadowingNative/`, rode `xcodegen generate`.

## Comandos

```bash
scripts/verify.sh          # verificação completa: rode SEMPRE ao fim de cada tarefa
scripts/verify.sh --quick  # sem o build do Xcode, para iterar rápido
cd curator && npm test     # só os testes do curador (node --test)
zsh Audits/run-recommendations.zsh
zsh Audits/run-segmentation-layout.zsh
```

Uma auditoria Swift nova precisa de um runner `Audits/run-<nome>.zsh` no mesmo formato dos existentes. O `verify.sh` roda automaticamente todo `Audits/run-*.zsh`.

## Regras de segurança (obrigatórias)

1. **Não baixar** vídeo nem áudio do YouTube. Só metadados e legendas.
2. **Não ler, imprimir nem copiar** `Config/Secrets.xcconfig`, `~/.config/shadowing-curator/*`, chaves de API ou contas de serviço.
3. **Não publicar** no Firestore e não rodar `npm run publish:configured`, `scan:configured`, `aggregate:configured`, `service:install` ou `dashboard:install`. Só o usuário roda comandos `:configured`.
4. **Não fazer deploy** de nada (`firebase deploy`, TestFlight etc.).
5. `firestore.rules`: só altere se a tarefa autorizar explicitamente, e nunca faça deploy.
6. **Legendas do YouTube:** no máximo 2 pedidos simultâneos. Ao receber HTTP 429, pare e espere (o bloqueio dura mais de 40 min). Testes automáticos **não** acessam a rede: use respostas simuladas, como `FixtureURLProtocol` em `Audits/RecommendationAudit.swift`.
7. Não apague nada em `curator/.state/`. Antes de reprocessar, faça backup (a tarefa explica como).
8. Não instale dependências novas sem a tarefa autorizar.
9. Não faça `git commit`, `push` ou `reset`. O usuário revisa o diff e faz o commit.

## Convenções

- Textos de interface em **português do Brasil**. Identificadores de código em inglês.
- Siga o estilo do arquivo ao redor: mesma densidade de comentários (poucos, curtos, em português, explicando o *porquê*).
- Swift 6: tipos `Sendable`, `actor` para serviços com estado, `@MainActor` em views e modelos de UI. O build não pode ter avisos novos nos arquivos alterados.
- JS do curador: ESM, funções puras exportadas e testadas em `*.test.mjs` com `node:test`.
- **Segmentação idêntica nos dois lados:** a mesma entrada de palavras deve gerar as mesmas frases no JS (`curator/segment.mjs`) e no Swift (`ShadowingLessonBuilder`). Os casos compartilhados ficam em `Audits/fixtures/segmentation/`.

## Fluxo de trabalho

1. Execute **uma tarefa por vez**, na ordem de `docs/agent-tasks/README.md`. Confira em `STATUS.md` se as dependências estão concluídas.
2. Leia a tarefa inteira antes de começar. Mude **só os arquivos listados** em "Arquivos permitidos".
3. Escreva ou ajuste os testes pedidos nos critérios de aceite.
4. Rode `scripts/verify.sh`. Só considere a tarefa pronta com "Tudo passou."
5. Atualize `docs/agent-tasks/STATUS.md`: status, data e 1–3 linhas do que mudou.
6. Se algo na tarefa estiver ambíguo ou impossível, **não improvise**: marque "bloqueada" no STATUS com a dúvida e pare.
