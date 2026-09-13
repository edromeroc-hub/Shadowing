# ShadowingAI no iOS

## Estado atual

- Capacitor 8.4.1 instalado.
- Projeto Xcode criado em `ios/App/App.xcodeproj`.
- Bundle ID provisório: `com.edromero.shadowing`.
- Interface React sincronizada com o projeto iOS.
- Swift Package Manager configurado; CocoaPods não é necessário.
- Plugin Swift busca legendas e metadados pelo IP do iPhone.
- Player nativo reproduz o fluxo MP4 e aceita play, pause e busca por tempo.
- Segmentador local mantém o treino funcional sem o servidor do Mac.

## Preparar o Xcode neste Mac

O Xcode 26.6 está instalado, mas os componentes de primeira inicialização ainda precisam ser concluídos. Execute no Terminal do Mac:

```bash
sudo xcodebuild -runFirstLaunch
```

Depois, abra o projeto:

```bash
npm run ios:open
```

No Xcode, escolha o target `App`, abra `Signing & Capabilities` e selecione sua equipe Apple.

## Comandos do projeto

```bash
npm run ios:sync
npm run ios:open
npm run ios:run
```

`ios:sync` recompila o React e copia a versão mais recente para o aplicativo iOS.

## Fase 1 — aplicativo no iPhone

1. Abrir o projeto no Xcode.
2. Selecionar um iPhone conectado ou um simulador.
3. Escolher a equipe de assinatura.
4. Executar o app e validar todas as telas.

Nesta fase o link, a legenda, o player e a segmentação local já funcionam sem o servidor Node do Mac. Tradução, Gemini e recomendações online ainda dependem de uma API HTTPS.

## Fase 2 — download offline nativo

O próximo módulo do plugin Swift terá estas responsabilidades:

- receber o link e a qualidade escolhida pelo React;
- obter a URL temporária do MP4 e a legenda;
- baixar com `URLSessionDownloadTask`, sem carregar o vídeo inteiro na memória;
- salvar em `Application Support/Shadowing/VIDEO_ID/`;
- publicar progresso, conclusão, cancelamento e erros para o React;
- listar e excluir vídeos baixados;
- devolver uma URL local para o player.

O processamento Gemini continuará em uma API protegida. A chave não deve ficar embutida no IPA.

## Fase 3 — IPA privado

Para testes com poucos aparelhos:

1. Criar um Archive no Xcode.
2. Assinar com a conta Apple Developer.
3. Exportar o IPA de desenvolvimento ou Ad Hoc.
4. Instalar pelo Xcode ou AltStore Classic.

## Fase 4 — AltStore PAL no Brasil

Para aparecer como aplicativo distribuível pela AltStore PAL:

1. Ter uma assinatura paga do Apple Developer Program.
2. Aceitar os termos atuais de distribuição alternativa no Brasil.
3. Criar o app em App Store Connect com o mesmo Bundle ID.
4. Registrar o Developer ID e o token do marketplace fornecido pela AltStore.
5. Enviar a build para Notarization da Apple.
6. Baixar e hospedar o pacote ADP sem alterar sua estrutura.
7. Publicar o arquivo de source da AltStore com metadados e URL do pacote.

Apps alternativos no Brasil exigem iOS 26.5 ou posterior e ainda passam pela Notarization básica de segurança e funcionamento da Apple.
