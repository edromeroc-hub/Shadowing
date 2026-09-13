# Source do ShadowingAI — AltStore Classic

Esta source distribui o IPA 1.0 (build 1) gerado em 3 de agosto de 2026. Ela não funciona na AltStore PAL, que exige um pacote ADP notarizado.

## Endereço público da source

https://github.com/edromeroc-hub/Shadowing/releases/download/altstore-source/source.json

Na AltStore Classic, adicione esse endereço em Sources. O aplicativo aparece em Browse depois de adicionar a source. Instalação e renovação exigem AltServer.

## Publicação

Publicado em 7 de setembro de 2026: IPA e `icon.png` na release `ios-classic-1.0-1`; `source.json` na release separada `altstore-source`, mantendo um endereço estável. Os três arquivos foram baixados sem autenticação para verificar acesso público, formato e integridade. A instalação no iPhone ainda precisa ser testada.

## Atualizações

1. Gere um IPA com versão ou build diferente no projeto Xcode.
2. Confira o Info.plist e os entitlements do IPA final; inclua todas as permissões do aplicativo e de extensões na source.
3. Publique o IPA em uma nova release, com URL própria. Não substitua o IPA antigo.
4. Acrescente a versão no início de `versions`, preenchendo versão, build, URL, tamanho exato em bytes, SHA-256 e iOS mínimo conforme o pacote.
5. Substitua apenas o asset `source.json` na release `altstore-source`. Preserve esse endereço para os usuários receberem atualizações.

Documentação: https://faq.altstore.io/developers/make-a-source
