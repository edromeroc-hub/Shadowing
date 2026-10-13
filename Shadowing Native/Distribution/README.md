# ShadowingApp — preparação para distribuição

Atualização técnica de 4 de outubro de 2026. As páginas públicas foram publicadas; nada foi enviado ao App Store Connect.

## Estado atual do beta

- Beta gratuito para todos: `BuildAvailability.purchasesEnabled = false`. Onboarding mostra o acesso gratuito, produtos não são carregados e a função de compra recusa checkout. Não há tratamento especial para revisores, detecção de sandbox ou ativação remota de cobrança.
- Nenhuma cobrança automática ao final do beta. Assinaturas futuras exigirão outra implementação validada e compra explícita.
- Site separado: https://shadowingapp-native.web.app — o site da versão comercial foi preservado.
- Privacidade: https://shadowingapp-native.web.app/privacy.html
- Termos: https://shadowingapp-native.web.app/terms.html
- Suporte: https://shadowingapp-native.web.app/support.html
- As quatro páginas responderam HTTP 200 sem autenticação; privacidade/termos publicados conferidos contra os arquivos locais.

Deploy restrito a Hosting, sem alterar plano, regras, Auth ou funções:

```sh
cd "Shadowing Native/Distribution"
npx -y firebase-tools@latest deploy --only hosting --project shadowing-commercial-edromero --config firebase.json --non-interactive
```

## Identidade e projeto

- Nome exibido no aparelho: **ShadowingApp**.
- Projeto/scheme: `ShadowingNative`; produto interno: `Shadowing Native`.
- Bundle ID preservado: `com.edromero.shadowing.next`. Não substituímos a identidade da versão antiga ou comercial.
- Ícone: `../ShadowingNative/Assets.xcassets/AppIcon.appiconset/ShadowingApp-1024.png`, 1024 × 1024, opaco.
- Gerar o projeto exclusivamente a partir de `../project.yml` com XcodeGen; não copiar arquivos de outros projetos Xcode.

## Ícone

Criado com a ferramenta integrada `image_gen.imagegen`. A imagem original foi gerada em 1254 × 1254; `sips` fez apenas o redimensionamento técnico para o catálogo de assets. O fundo quadrado é intencional: o sistema aplica a máscara do ícone.

Prompt utilizado:

> Create a single production-ready iOS app icon for ShadowingApp, an English listening and repeat practice app. Square full-bleed 1024x1024 artwork, opaque midnight navy background across the entire square, no rounded outer corners (iOS applies its own mask), no border, no mockup, no text or lettering. A large centered original minimalist symbol combining an audio waveform with a smooth echo/repetition gesture: five softly rounded vertical waveform bars in luminous electric blue flowing into a single elegant violet curved echo stroke. Restrained dimensional glass-like highlights, precise clean silhouette, high contrast and recognizable at 48 pixels, generous internal safe margin 18%. Premium friendly educational product, uncluttered, no microphone clipart, no YouTube logo, no Apple logo. Deliver just the flat square icon asset, not a device presentation.

## Documentos e privacidade

O app inclui termos, política e suporte em Markdown, acessíveis offline no login, Perfil e conclusão do onboarding, com link para abrir a versão publicada. `legal/` contém as versões HTML publicadas. Antes de submeter:

1. Revisar juridicamente os textos e confirmar o contato `ed.romero@msn.com`.
2. Manter os documentos do app e os HTML sincronizados quando o comportamento mudar.
3. Preencher App Privacy, Support URL e termos no App Store Connect com as URLs acima.
4. Conferir as declarações de coleta de dados com Firebase, YouTube/WKWebView e StoreKit. O manifesto próprio registra UserDefaults/CA92.1; ele não substitui os rótulos de privacidade nem declara que terceiros não coletam dados.

## Exclusão e Firebase compartilhado

O fluxo foi reforçado para não ignorar divergência de conta, aguardar gravações em andamento, impedir regravação durante a exclusão e mostrar confirmação no login. Em falha, a sincronização pode ser retomada. Isso não transforma a operação em uma transação atômica entre Firestore e Auth.

A inspeção remota encontrou apenas `nativeStudy`, com um documento e sem subcoleções. `profiles`, `entitlements`, `progress` e `aiUsage` existem apenas como previsão no código comercial, não no banco inspecionado. As regras publicadas permitem somente o próprio UID em `nativeStudy`; não foram alteradas. Nenhuma conta existente foi apagada. A API Cloud Functions está desabilitada e o projeto permanece sem billing.

Um teste de integração com SDK Firebase cliente criou uma conta descartável, gravou e leu seu documento, confirmou rejeição ao tentar excluir outro UID inexistente, reautenticou, excluiu o próprio documento e a identidade Auth, e confirmou que não era mais possível entrar. A conta e o documento do teste foram removidos. Esse teste valida o backend atual, não substitui testar a interface Swift/Apple/Google nem filmar a exclusão no aparelho físico.

Limitações restantes: Firestore e Auth não formam uma transação única; a proteção contra gravação concorrente implementada é local ao aparelho. Para exclusão robusta envolvendo vários dispositivos ou futuras coleções comerciais, é necessária coordenação no servidor. Novas coleções/subcoleções só podem ser lançadas depois de incluídas na rotina de exclusão. A extensão oficial de remoção não foi instalada, nem foi habilitado billing. Testar interrupções de rede, múltiplos aparelhos e provedores antes da liberação pública.

## Release e pagamentos

Debug e Release incluem opcionalmente `Config/Secrets.xcconfig`, ignorado pelo Git. A chave YouTube no binário **não é segredo**; restringir API/cotas e planejar backend para descoberta. Nenhuma chave de IA foi adicionada.

O StoreKit recebeu observação de transações, correções de estado/restauração e remoção das promessas de avaliação de fala não implementada. **A monetização está desabilitada neste beta**. Para uma versão paga, implementar benefícios reais e controle de acesso, validar produtos, elegibilidade e oferta introdutória. Não basta ligar a flag. Esta etapa não alterou preços nem iniciou uma compra.

## Legendas

O extrator foi mantido por solicitação do responsável. Não é a API oficial de captions. O risco de rejeição, bloqueio e direitos de terceiros permanece; não foi ocultado ou contornado por uma configuração especial de revisão. Consultar `../AUDITORIA_APP_STORE_TESTFLIGHT.md`.

## Pendências externas

Confirmar registro novo versus atualização, concluir assinatura de distribuição e validação com Apple, conferir export compliance, screenshots, classificação etária, privacidade e credenciais de demonstração. A compilação local não garante aprovação nem equivale a um upload TestFlight.

## Validação de empacotamento inicial

- Build Debug para iPhone 17 Simulator: **BUILD SUCCEEDED**.
- Archive Release genérico iOS, sem assinatura: **ARCHIVE SUCCEEDED**. Resultado local: `/tmp/shadowing-native-release-audit/ShadowingApp-store-fixes.xcarchive`.
- Conferido no pacote Release: nome ShadowingApp, bundle original, AppIcon compilado, quatro orientações iPad, retrato iPhone, manifesto próprio e os três documentos legais presentes.
- Chave YouTube presente no Release, verificada apenas como booleano; valor não exibido nos logs desta auditoria.
- PNG validado: 1024 × 1024, sem canal alpha.
- Login e política abertos no simulador com a fixture de auditoria existente, sem criar ou excluir contas.
- Aviso de build: extração de metadados App Intents ignorada, pois o target não usa esse framework.
- Não executados: compras, renovação, exclusão real, login de provedores, instalação física, Validate App ou upload. A compilação não comprova esses fluxos.

## Validação posterior — publicação e beta gratuito

- As páginas foram publicadas exclusivamente no novo site `shadowingapp-native`; quatro respostas HTTP 200 verificadas.
- Build Debug passou; a nova tela de acesso gratuito foi inspecionada no iPhone 17 Simulator.
- Archive Release sem assinatura passou: `/tmp/shadowing-native-release-audit/ShadowingApp-free-beta.xcarchive`. Ainda não é um pacote assinado para upload.
- Teste Swift da flag: `prepare`/`loadProducts` não carregam planos e `purchaseSelected` retorna falso antes de qualquer checkout. Nenhuma compra foi executada.
- Teste de integração Firebase com SDK cliente passou: criar conta descartável → gravar/ler estudo → rejeitar exclusão de outro UID → reautenticar → excluir estudo → excluir Auth → rejeitar novo login. Limpeza do teste concluída.
- Esses testes não equivalem a exclusão por Apple/Google no iPhone nem a teste de concorrência entre aparelhos.
- O site comercial, as contas preexistentes, o plano Firebase e as regras publicadas foram preservados.
- Nova consulta após o teste confirmou o mesmo conjunto de documentos preexistentes, sem documento descartável restante.

## Archive assinado e tentativa de distribuição — 4 de outubro

- Archive Release com assinatura **Apple Development** e perfil de desenvolvimento da equipe `CA26GYKPQP`: **ARCHIVE SUCCEEDED**. O perfil inclui o iPhone conectado. Isso ainda não é assinatura App Store.
- Original verificado com `codesign --verify --deep --strict`: `/tmp/shadowing-native-release-audit/ShadowingApp-signed-beta.xcarchive`.
- Cópia preservada em `builds/2026-10-04/ShadowingApp-signed-beta.xcarchive.zip`; extração em `/tmp` e verificação da assinatura passaram. Preferir esse ZIP: a cópia descompactada `builds/2026-10-04/ShadowingApp.xcarchive` recebeu metadados FinderInfo do provedor de arquivos e não passou na verificação. Não distribuir essa cópia descompactada.
- `ExportOptions-AppStore.plist` prepara exportação, sem upload automático ou incremento automático de versão/build.
- Exportação por `xcodebuild` falhou com `No Accounts` e ausência de perfil App Store para `com.edromero.shadowing.next`, mesmo após baixar os perfis existentes pelo Xcode.
- A conta/equipe aparecem nas configurações gráficas do Xcode. Pelo Organizer, **Validate App** avançou até a solicitação de criar um registro no App Store Connect; a validação não terminou. Nenhum registro foi criado.
- O painel App Store Connect contém o ShadowingAI antigo, mas não um registro para esta versão nativa. Aguardando decisão entre novo registro separado e uma migração planejada; não trocar o bundle para forçar envio ao app antigo.
- Instalação e vídeo de exclusão no aparelho continuam pendentes: a última consulta ao iPhone encontrou o aparelho bloqueado.
- Nenhum IPA de distribuição, upload TestFlight ou submissão foi concluído nesta etapa.

## Envio à Apple — 5 de outubro

- Criado registro separado **ShadowingApp**, App Store Connect ID `6819239699`, para `com.edromero.shadowing.next`, idioma principal português do Brasil. O registro anterior ShadowingAI continua separado.
- O Organizer do Xcode validou o archive assinado: **Validation succeeded** com avisos de dSYM ausente para frameworks binários do Firebase/gRPC. Não houve erro bloqueante na validação.
- **Upload completed with warnings** no Organizer; status do archive: **Uploaded to Apple**. No TestFlight, o upload de **1.0 (1)** aparece como **Complete**, e a build aparece como **Missing Compliance** até concluir a declaração de criptografia.
- Criado grupo interno `Equipe interna`, sem distribuição automática de builds. Nenhum testador foi convidado ainda.
- Categoria principal **Educação** salva no App Store Connect. A versão 1.0 está configurada para **liberação manual** após eventual aprovação; nenhuma revisão pública foi solicitada.
- A mesma build assinada para desenvolvimento foi instalada por cima no iPhone conectado; `devicectl` confirmou `ShadowingApp`, bundle `com.edromero.shadowing.next`, versão **1.0 (1)**. Isso não equivale a teste de login/exclusão em aparelho físico.
- A inspeção do pacote encontrou `openssl_grpc.framework` e uso de `CryptoKit`/`URLSession`. Na pergunta inicial de export compliance, selecionou-se criptografia padrão; a Apple pede declaração adicional se houver distribuição na França. A decisão sobre disponibilizar na França está pendente. Não marcar `ITSAppUsesNonExemptEncryption = NO` sem reavaliar os SDKs.
- O preenchimento de e-mail de contato e URLs no TestFlight foi barrado pela revisão automática de permissões; não foi repetido por outro caminho. A autorização específica do responsável foi solicitada. Não há dados de teste inseridos nessa seção nesta etapa.
- Ainda não houve envio para análise beta externa ou revisão da App Store. O status da versão pública é **Prepare for Submission**.
