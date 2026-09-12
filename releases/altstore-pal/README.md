# Source da AltStore PAL

Esta pasta contém a source reutilizável de **Eduardo Romero Apps**. Novos
aplicativos podem ser incluídos adicionando outro objeto ao array `apps` de
`source.json`.

## URL pública planejada

`https://raw.githubusercontent.com/edromeroc-hub/Shadowing/main/releases/altstore-pal/source.json`

## Publicação do ShadowingAI

1. Enviar a versão `1.1.0 (2)` para Notarization no App Store Connect.
2. Aguardar a aprovação e a geração automática do ADP pela Apple.
3. Baixar o ADP pela API da AltStore PAL.
4. Publicar todos os arquivos do ADP sem alterar nomes, hashes ou estrutura.
5. Adicionar a versão ao início de `apps[0].versions` em `source.json`.
6. Publicar a pasta e adicionar a URL pública como source na AltStore PAL.

O campo `downloadURL` de uma versão PAL deve apontar para o `manifest.json` do
ADP ou para a raiz pública do pacote. Um IPA comum não substitui o ADP.

## Novos aplicativos

Cada aplicativo deve ter seu próprio `bundleIdentifier`, `marketplaceID`, ícone,
descrição, permissões e array `versions`. A versão mais recente deve aparecer
primeiro no array.
