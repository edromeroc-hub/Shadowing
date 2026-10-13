# 01: Feed só do catálogo curado

## Objetivo
A aba Shorts passa a mostrar **apenas** Shorts do catálogo aprovado (`SharedShortCatalog`). Ela deixa de chamar a descoberta no aparelho (`ShortsDiscoveryService.discoverBatch`), que é a origem dos vídeos de professor de inglês.

## Por quê
Quando o catálogo acaba (hoje ele está vazio), `discoverShorts()` chama `discoverBatch`, que pesquisa termos como `"English conversation beginner"`. O conteúdo do catálogo já passou por formato, legenda, nível e frases no Mac.

## Arquivos permitidos
- `ShadowingNative/Views/Shorts/ShortsFeedView.swift`

## Passos
1. Em `ShortsFeedView.discoverShorts()`, remova o bloco que chama `ShortsDiscoveryService.shared.discoverBatch(...)` e o tratamento do resultado (`batch.items`, `emptyBatchCount`, `ShortCatalogSignals.suggest`). Mantenha intacto o bloco de `sharedCatalog.nextPage(for:)`.
2. Quando `sharedCatalog.hasMore == false` e a página voltar vazia:
   - `canLoadMore = false`;
   - `pendingNextFromID = nil`;
   - `discoveryNotice = items.isEmpty ? nil : "Você viu todos os Shorts do seu nível por hoje. Novos chegam todos os dias."`.
3. Se `nextPage` lançar erro, mantenha `sharedCatalog.markUnavailable()` e mostre `discoveryNotice = "Não foi possível carregar os Shorts. Verifique a conexão e tente novamente."`.
4. Estado vazio (o `VStack` com `Image(systemName: isDiscovering ? "sparkle.magnifyingglass" : "rectangle.portrait.slash")`). Troque o texto do caso não-carregando para **"Ainda não há Shorts prontos para o seu nível."**, com o subtítulo "Use a lupa para buscar um assunto ou canal." Mantenha os botões "Buscar Shorts ou canais" e "Buscar novamente".
5. O botão "Buscar mais Shorts" do aviso deve aparecer só quando `canLoadMore` for verdadeiro.
6. Remova `@State emptyBatchCount` e outras variáveis que ficarem sem uso. **Não** apague funções de `ShortsDiscoveryService`: as auditorias ainda as testam.
7. O fechamento da lupa (`.sheet(... onDismiss:)`) continua chamando `discoverShorts()`. Isso está certo: só recarrega o catálogo.

## Critérios de aceite
- `grep -n "discoverBatch" ShadowingNative/Views` não encontra nada.
- O feed continua funcionando com `previewItems` (prévias do Xcode).
- `scripts/verify.sh` → "Tudo passou.", sem avisos novos em `ShortsFeedView.swift`.

## Não fazer
- Não mexer na lupa (`ShortsSearchView`); ela continua buscando no YouTube.
- Não alterar `SharedShortCatalog.swift` nesta tarefa.
