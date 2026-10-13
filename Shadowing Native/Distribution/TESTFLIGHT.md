# Preparação do primeiro beta — ShadowingApp

## Identidade

- Bundle ID desta build: `com.edromero.shadowing.next`.
- Scheme: `ShadowingNative`.
- Nome público: `ShadowingApp`.
- Não enviar esta build para o registro antigo com `com.edromero.shadowing`. Confirmar o registro correspondente no App Store Connect, sem trocar bundle/Firebase para forçar uma atualização.
- Esta build é gratuita para todos; compras estão desativadas em código, sem uma configuração específica para revisores.

## URLs para os campos do painel

- Privacy Policy URL: https://shadowingapp-native.web.app/privacy.html
- Support URL: https://shadowingapp-native.web.app/support.html
- Terms: https://shadowingapp-native.web.app/terms.html
- Marketing URL, opcional: https://shadowingapp-native.web.app
- Feedback email: ed.romero@msn.com

## What to Test

Teste cadastro e login, personalização do nível/interesses, retomada de estudos e vocabulário. Nos vídeos e Shorts, verifique o sincronismo entre a fala e a frase, a pausa para repetição e a troca de vídeo sem áudio anterior. Teste escuta ativa e traduções. No Perfil, confira sincronização e exclusão de uma conta criada somente para o teste. O beta é gratuito, sem assinatura ou cobrança automática. Envie feedback pelo TestFlight com o modelo do aparelho, link do vídeo, trecho e passos para reproduzir o problema.

## Rascunho de notas para revisão — revisar antes de enviar

ShadowingApp is a native English listening and repetition practice app. This build is free for all beta participants. In-app purchases and subscription checkout are disabled for everyone in this build. No automatic charge starts at the end of the beta.

Sign in, choose your native language, English level, interests and daily goal, then use Today, Explore or Shorts. The app plays embedded YouTube videos online using the official IFrame player. Captions are obtained through an unofficial public-transcript integration; this is not the authorized YouTube Captions API. Availability varies by video. This build does not download video files and does not record or automatically score spoken audio.

Account deletion is available at Profile → Delete my account. The user confirms and reauthenticates; the app removes the native study document, Firebase Authentication identity and the local study profile on that device. Cancel any pre-existing App Store subscription separately. The current beta database contains only native study documents and no commercial user-data collections.

Provide the working demo account credentials directly in App Review Information, never in this repository. Attach a physical-device recording showing sign-in, navigation to account deletion, confirmation and the completion message.

## Ainda não cumprido por este documento

Estado em 4 de outubro: archive de desenvolvimento assinado e ZIP verificado disponíveis; exportação por comando falhou por conta/perfil App Store. No Organizer, a validação chegou ao pedido de criar um registro separado para `com.edromero.shadowing.next`. Aguardando confirmação antes de criar esse registro. Ainda não há IPA de distribuição nem upload.

Atualização de 5 de outubro: registro `6819239699` criado; validação no Organizer aprovada com avisos de dSYM, upload **1.0 (1)** concluído e build recebida no TestFlight. A build está em **Missing Compliance** pela declaração de criptografia. O grupo interno `Equipe interna` está vazio. Esta versão também foi instalada no iPhone conectado para teste; login e exclusão ainda precisam ser verificados no próprio aparelho. A revisão automática bloqueou o preenchimento do contato/URLs no TestFlight, aguardando autorização específica. Nenhum envio à revisão da App Store foi feito.

Atualização posterior de 5 de outubro: declaração de criptografia concluída, build **1.0 (1)** adicionada ao grupo externo `Beta público` e enviada à **Beta App Review**; estado atual **Waiting for Review**. As informações de teste e contato foram salvas no App Store Connect com autorização explícita do responsável. Link público criado com limite de 100 testadores: https://testflight.apple.com/join/1zZmCfsW. O próprio painel avisa que testadores não podem entrar até haver uma build aprovada. Foi criada uma conta exclusiva para a revisão no Firebase; a senha está somente no App Store Connect e na conversa, nunca neste repositório. E-mail/senha e Apple foram ativados como provedores Firebase; ainda é preciso testar os logins e a exclusão no aparelho físico. Nenhuma revisão de publicação na App Store foi solicitada.

A categoria principal foi salva como Educação e a versão pública foi definida para liberação manual após eventual aprovação.

- Confirmar registro correto, versão e build disponíveis no App Store Connect.
- Archive com assinatura de distribuição, Validate App, export compliance e upload.
- Login Apple/Google e exclusão filmada em iPhone/iPad físico.
- Exclusão com vários dispositivos concorrentes e falhas de rede.
- Revisar os rótulos App Privacy com os dados reais do Firebase/YouTube/WKWebView; não marcar coleta zero.
- Classificação etária, screenshots atuais e contato de revisão.
- Aprovação e permissões de conteúdo: manter o extrator por decisão de produto não garante aprovação Apple/YouTube.

Enviar para revisão beta externa no TestFlight é diferente de publicar na App Store. Nada foi enviado nesta etapa.
