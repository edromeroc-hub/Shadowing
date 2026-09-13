# ShadowingAI para Mac

## Instalação

1. Abra `releases/mac/ShadowingAI-1.0.2-mac-arm64.dmg`.
2. Arraste o ShadowingAI para a pasta Aplicativos.
3. Na primeira abertura, clique com o botão direito no app e escolha **Abrir**.

Esta versão foi criada para Macs com processador Apple Silicon.

## Inteligência artificial

O app funciona sem chave usando a segmentação local. Para ativar tradução e segmentação pelo Gemini:

1. Abra o ShadowingAI.
2. Clique no botão de engrenagem no canto superior direito.
3. Cole sua chave da API Google Gemini.
4. Clique em **Salvar chave neste Mac**.

A chave e os vídeos baixados ficam somente na pasta local do ShadowingAI dentro da Biblioteca do usuário.

## Atualizações

Depois de alterar o código, gere um novo instalador com:

```bash
npm run mac:dmg
```
