# AGENTS.md: Shadowing Native

Instruções permanentes para agentes de código. O ambiente principal é o **Google Antigravity com Gemini**, aberto na pasta `Shadowing Native/`; o arquivo também vale para Xcode, Gemini CLI, Codex e Claude. Leia este arquivo inteiro antes de qualquer tarefa.

## Produto

App iOS (SwiftUI) de **shadowing**: o aluno ouve um trecho curto de um YouTube Short, pausa e repete em voz alta. Público: brasileiros aprendendo inglês.

**Regra de ouro do conteúdo:** o foco são vídeos de **inglês nativo e natural**, o que o americano rola no dia a dia: talk show, late night, entrevista de rua, humor, podcast, esporte, culinária, vlog. **Decisão do dono (14/10/2026):** Shorts de **professores de inglês também são aceitos** (Rachel's English, AccurateEnglish, Speak English With Vanessa etc.), desde que a fala seja clara e o vídeo tenha frases boas para repetir. Eles são minoria: o catálogo continua dominado por conteúdo nativo natural.

**Nível é relativo:** iniciante = os ~30% mais fáceis *dentro do conteúdo nativo* (fala mais lenta e clara, palavras comuns). O iniciante recebe ajudas na prática (frases curtas, velocidade 0,75×), não vídeos didáticos.

**Dois caminhos independentes publicam no mesmo catálogo (`approvedShorts`):**
- **Caminho A, curador automático** (`curator/`): programa Node com regras locais, melhorado pelas tarefas de `docs/agent-tasks/`.
- **Caminho B, curadoria pelo Gemini** (`curadoria-gemini/`): **você (Gemini no Antigravity) é o curador**. Você busca, avalia, define o nível, divide as frases e revisa, seguindo `curadoria-gemini/DIRETRIZES.md`, com os comandos `/curar-shorts`, `/publicar-shorts` e `/revisar-shorts`. Você escolhe frases por **índice de palavra**; os tempos sempre saem das palavras da legenda, nunca de você.

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
| `curadoria-gemini/` | Caminho B: `DIRETRIZES.md`, ferramentas `node cli.mjs …` e `registro.jsonl` |
| `curator/workflow.mjs` | Orçamento de buscas e regras de publicação automática |
| `curator/curator.mjs` | Comandos: `scan`, `publish`, `reject`, `resegment`, `aggregate`, `audit-shorts`… |
| `curator/dashboard.mjs` + `dashboard-public/` | Painel local de revisão (`127.0.0.1:4318`) |
| `curator/.state/` | Estado local: `review/` (candidatos), `metadata/`, `published/`, `rejected/` |
| `Audits/` | Auditorias executáveis (Swift via `swiftc`, JS via `node`) |
| `docs/agent-tasks/` | **Tarefas para você executar**, uma por arquivo, e `STATUS.md` |
| `.agent/workflows/` | Comandos do Antigravity: `/proxima-tarefa`, `/rodar-curadoria` (Caminho A) e `/curar-shorts`, `/publicar-shorts`, `/revisar-shorts` (Caminho B) |

O projeto Xcode é gerado por **XcodeGen** a partir de `project.yml`. Prefira editar arquivos Swift existentes. Se criar um arquivo `.swift` novo dentro de `ShadowingNative/`, rode `xcodegen generate`.

## Comandos

```bash
scripts/verify.sh          # verificação completa: rode SEMPRE ao fim de cada tarefa
scripts/verify.sh --quick  # sem o build do Xcode, para iterar rápido
cd curator && npm test     # só os testes do curador (node --test)
cd curadoria-gemini && npm test   # só as ferramentas do Caminho B
zsh Audits/run-recommendations.zsh
zsh Audits/run-segmentation-layout.zsh
```

Uma auditoria Swift nova precisa de um runner `Audits/run-<nome>.zsh` no mesmo formato dos existentes. O `verify.sh` roda automaticamente todo `Audits/run-*.zsh`.

## Regras de segurança (obrigatórias)

1. **Não baixar** vídeo nem áudio do YouTube. Só metadados e legendas.
2. **Não ler, imprimir nem copiar** `Config/Secrets.xcconfig`, `~/.config/shadowing-curator/*`, chaves de API ou contas de serviço. Os comandos `:configured` e `curadoria-gemini/cli.mjs` carregam as credenciais sozinhos; você nunca precisa vê-las.
3. **Comandos que usam as credenciais** (`npm run *:configured`, `resegment:fetch`, `service:install`, `dashboard:install`) publicam no app real e gastam cota. Rode-os **somente** quando o usuário pedir explicitamente nesta conversa ou executar o workflow `/rodar-curadoria`, e **nunca** durante uma tarefa de `docs/agent-tasks/`.
4. **Não fazer deploy** de nada (`firebase deploy`, TestFlight etc.).
5. `firestore.rules`: só altere se a tarefa autorizar explicitamente, e nunca faça deploy.
6. **Publicar pelo Caminho B** (`node cli.mjs publicar … --confirmado`) só quando o usuário aprovar aqueles IDs ou pedir publicação automática (regras na seção 7 de `curadoria-gemini/DIRETRIZES.md`). **Despublicar** só com o OK explícito do usuário. Nunca escreva tempos à mão nem edite `documento.json` direto: mude `decisao.json` e rode `montar`.
7. **Legendas do YouTube:** no máximo 2 pedidos simultâneos. Ao receber HTTP 429, pare e espere (o bloqueio dura mais de 40 min). Testes automáticos **não** acessam a rede: use respostas simuladas, como `FixtureURLProtocol` em `Audits/RecommendationAudit.swift`.
8. Não apague nada em `curator/.state/`. Antes de reprocessar, faça backup (a tarefa explica como).
9. Não instale dependências novas sem a tarefa autorizar.
10. Não faça `git commit`, `push` ou `reset`. O usuário revisa o diff e faz o commit.

## Convenções

- Textos de interface em **português do Brasil**. Identificadores de código em inglês.
- Siga o estilo do arquivo ao redor: mesma densidade de comentários (poucos, curtos, em português, explicando o *porquê*).
- Swift 6: tipos `Sendable`, `actor` para serviços com estado, `@MainActor` em views e modelos de UI. O build não pode ter avisos novos nos arquivos alterados.
- JS do curador: ESM, funções puras exportadas e testadas em `*.test.mjs` com `node:test`.
- **Segmentação idêntica nos dois lados:** a mesma entrada de palavras deve gerar as mesmas frases no JS (`curator/segment.mjs`) e no Swift (`ShadowingLessonBuilder`). Os casos compartilhados ficam em `Audits/fixtures/segmentation/`.

## Fluxo de trabalho

1. Execute **uma tarefa por vez**, na ordem de `docs/agent-tasks/README.md` (no Antigravity: `/proxima-tarefa`). Confira em `STATUS.md` se as dependências estão concluídas.
2. Leia a tarefa inteira antes de começar. Mude **só os arquivos listados** em "Arquivos permitidos".
3. Escreva ou ajuste os testes pedidos nos critérios de aceite.
4. Rode `scripts/verify.sh`. Só considere a tarefa pronta com "Tudo passou."
5. Atualize `docs/agent-tasks/STATUS.md`: status, data e 1–3 linhas do que mudou.
6. Se algo na tarefa estiver ambíguo ou impossível, **não improvise**: marque "bloqueada" no STATUS com a dúvida e pare.
