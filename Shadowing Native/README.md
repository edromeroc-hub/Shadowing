# Shadowing Native

Nome público: **ShadowingApp**. A build atual é um beta gratuito, com compras desativadas para todos. Páginas públicas, testes realizados e pendências: [Distribuição](Distribution/README.md). Dados para preencher o painel: [TestFlight](Distribution/TESTFLIGHT.md).

Nova versão 100% SwiftUI do Shadowing AI, isolada em código e projeto Xcode das versões React/Capacitor e comercial. A autenticação usa o mesmo projeto Firebase `shadowing-commercial-edromero`, com um cliente iOS próprio.

## Identidade de desenvolvimento

- Projeto: `ShadowingNative.xcodeproj`
- Scheme: `ShadowingNative`
- Bundle ID: `com.edromero.shadowing.next`
- iOS mínimo: 17.0
- Visual: componentes nativos e Liquid Glass no iOS 26+

## Conta Firebase

- Cliente iOS registrado com Bundle ID `com.edromero.shadowing.next` e configuração em `ShadowingNative/GoogleService-Info.plist`.
- Cadastro por e-mail/senha, Google ou Apple abre antes da anamnese; quem já tem conta pode escolher Entrar. A sessão Firebase persiste entre aberturas do app.
- O acesso Google usa o URL scheme do cliente nativo em `ShadowingNative/Info.plist`.
- A exclusão fica em **Perfil → Excluir minha conta**, pede confirmação e nova autenticação. No caso Apple, o token é revogado antes da exclusão da conta Firebase.
- Após confirmação do servidor, o app remove o documento `nativeStudy/{uid}`, os sinais de Shorts da conta e os dados locais desse perfil. Os dados locais são separados por UID; dados de convidado migram para a primeira conta acessada.
- Histórico, frase atual, perfil, progresso e vocabulário são salvos localmente e sincronizados em um documento privado do Firestore após o login. Ao entrar em outro aparelho, os registros são mesclados com os dados locais. Sem conexão, o app mantém os dados locais e mostra o erro de sincronização no Perfil para permitir nova tentativa. A sincronização usa o banco Firestore Standard já existente; não requer Blaze.
- O app consulta a nuvem novamente ao voltar para o primeiro plano. Uso simultâneo em vários aparelhos ainda pode gerar conflito de última gravação; o limite atual do documento é 850 KB e deve ser substituído por dados paginados antes de escalar.
- As recomendações usam nível/interesses escolhidos e temas/canais dos vídeos já estudados; não usam algoritmo ou histórico da conta YouTube. O catálogo de vídeos inclui a primeira leva de links com legenda tecnicamente testada em `CURADORIA_PODCASTS.md`; esses vídeos ainda exigem revisão editorial de áudio, alinhamento e linguagem.
- `firestore.rules` mantém `default deny`: cada usuário só grava os próprios sinais; o catálogo aprovado é somente leitura para usuários autenticados e só o curador do Mac o publica. `firebase.json` também declara o índice do catálogo. O projeto Firebase continua compartilhado com a versão comercial.
- A exclusão da conta não cancela uma assinatura da App Store. O botão de gerenciamento abre a página de assinaturas da Apple.

Para testar no iPhone, confirme no Apple Developer que o identificador `com.edromero.shadowing.next` tem **Sign in with Apple** habilitado e que os provedores Apple, Google e e-mail/senha estão ativos no Firebase Authentication. Antes de enviar uma atualização à Apple, grave em aparelho físico o fluxo de criação/login → Perfil → exclusão → confirmação, como solicitado na revisão. Se houver documentos da mesma conta criados pelo backend comercial, a exclusão desses dados na nuvem deve ser implementada no backend antes de declarar a remoção completa da conta compartilhada.

## Gerar o projeto

```bash
xcodegen generate
```

Os produtos de assinatura esperados são:

- `com.edromero.shadowing.pro.monthly`
- `com.edromero.shadowing.pro.annual`

Esses IDs estão reservados no código para uma versão paga futura. A build beta atual não carrega os produtos nem permite iniciar compras; não promete teste de três dias ou conversão automática em assinatura.

## YouTube

O catálogo compartilhado de Shorts é servido pelo Firestore com legenda e trechos preparados. O app carrega primeiro os aprovados no nível e interesses do aluno; a descoberta no aparelho só complementa o feed. A curadoria local, revisão e publicação estão documentadas em [Curador de Shorts](curator/README.md). O índice composto pode levar algum tempo para ficar pronto após o deploy. Likes são pessoais imediatamente e entram na pontuação por perfil após o Mac executar a agregação. A política de privacidade local foi atualizada; publique também a página de privacidade usada pelo TestFlight antes de distribuir uma build com esta coleta.

- Auditoria de interface, player e recomendações: [resultados, limites e próximos passos](AUDITORIA_INTERFACE_SINCRONIZACAO.md).
- A reprodução usa o player oficial IFrame dentro de `WKWebView`.
- Links comuns, `youtu.be`, `/shorts/`, `/embed/` e `/live/` compartilham o mesmo parser de `videoId`.
- A legenda é carregada por um serviço não oficial e isolado, com duas estratégias: resposta do player Android e página pública do vídeo.
- Nenhum arquivo de vídeo é baixado pelo fluxo novo.
- A extração preserva offsets internos de JSON3 quando disponíveis e prioriza faixas em inglês com esse detalhamento. Não é aplicado um atraso global: legendas sem alinhamento acústico continuam sendo aproximadas. Repetição e seek usam revisão do trecho para descartar términos antigos; pausa manual cancela a retomada agendada.
- Mudanças internas do YouTube podem exigir atualização apenas em `YouTubeTranscriptService.swift`.
- A aba Shorts usa o player oficial. Consulta primeiro aulas já preparadas no Firestore e, quando necessário, busca Shorts novos com a chave YouTube Data API. A descoberta no aparelho tem limite diário; aceita legenda inglesa acessível e nível estimado, mas não prova sincronismo acústico. O filtro `closedCaption` não é usado porque excluiu legendas automáticas nos testes; `#shorts` e duração também são aproximações, não prova de vídeo vertical. Sem item compatível, o app informa a falta em vez de misturar níveis.
- Curtir e Não quero ver são sinais exclusivos do ShadowingApp, separados por UID Firebase; não alteram o YouTube. Eles personalizam o feed imediatamente e são registrados para agregação por nível e interesse no Mac. Ocultar remove o Short da recomendação pessoal; likes de outros usuários só acrescentam um bônus limitado e nunca superam o filtro de nível.
- A lupa na aba Shorts busca canais e vídeos curtos no YouTube. Resultados de vídeo só entram após verificação de legenda inglesa e estimativa de nível; a busca manual aceita o nível do aluno ou um vizinho, mostra o nível exato primeiro e marca os demais como "um pouco mais fácil/difícil". A consulta não leva `#shorts` (a hashtag trazia edits, música e ASMR sem fala); termos de tema em português são traduzidos para inglês antes da busca. A verificação de legendas roda três vídeos por vez para evitar o limite 429 do YouTube, e "Carregar mais Shorts" continua da mesma página/consulta. Seguir um canal ou buscar um tema informa a próxima rodada de recomendações; essas preferências ficam por conta e sincronizam com o progresso. O usuário pode deixar de seguir pelo resultado da busca ou pelo menu de um Short.
- O menu do Short também permite avaliar a dificuldade: Muito difícil oculta aquele vídeo; Muito fácil reduz sua prioridade. A ordem do trecho já visitado do feed é preservada ao curtir. Nível, meta e interesses podem ser editados no Perfil.
- Para habilitar descoberta dinâmica no build de desenvolvimento, ative YouTube Data API v3 no Google Cloud e cole a chave apenas em `Config/Secrets.xcconfig`, na linha `YOUTUBE_DATA_API_KEY =`. Esse arquivo é ignorado pelo Git; `Config/Debug.xcconfig` o inclui opcionalmente e `project.yml` injeta o valor em `YouTubeDataAPIKey` do Info.plist. Gere o projeto com `xcodegen generate` e reinstale o app para aplicar a chave. Restrinja a chave à YouTube Data API v3 e ao app iOS `com.edromero.shadowing.next`; a requisição inclui `X-Ios-Bundle-Identifier`. Para produção, mova a busca para um backend com cota, cache e moderação centralizados; uma chave embutida no app não é segredo e a restrição por bundle ID pode ser contornada.
- O YouTube pode exibir anúncios no player oficial; o app não bloqueia, substitui nem oculta publicidade.
