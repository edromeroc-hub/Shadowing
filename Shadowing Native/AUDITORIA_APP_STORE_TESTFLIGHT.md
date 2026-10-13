# Prontidão para App Store e TestFlight

> Registro da auditoria inicial. As correções posteriores (ícone, Release, documentos publicados, beta gratuito e teste de exclusão no Firebase) estão em [Distribution/README.md](Distribution/README.md). O roteiro atual de envio está em [Distribution/TESTFLIGHT.md](Distribution/TESTFLIGHT.md). Os achados abaixo foram preservados como histórico, não como estado final dessas correções.

Revisão: **04/10/2026**, horário de referência America/Sao_Paulo.

Escopo: `Shadowing Native`, scheme `ShadowingNative`, identificador `com.edromero.shadowing.next`. Revisão de código, documentação oficial vigente e archive Release local. **Não houve upload, submissão, alteração de Firebase ou mudança no comportamento do app.** Não foi acessado o estado atual do App Store Connect. Esta avaliação técnica não garante aprovação nem substitui avaliação jurídica de direitos e contratos.

## Parecer

**Ainda não recomendo enviar esta build para revisão externa.** Ela compila para dispositivo, mas há bloqueios de empacotamento, descoberta de conteúdo, privacidade e monetização. Há também risco contratual relevante na obtenção não oficial de legendas.

TestFlight não é publicação na loja. O caminho sugerido é corrigir a build, validar internamente e só então pedir a primeira revisão beta externa.

## Evidência do archive

Executado `xcodebuild archive`, configuração Release, destino genérico iOS, com `CODE_SIGNING_ALLOWED=NO`. Resultado: **ARCHIVE SUCCEEDED**.

Artefato de diagnóstico: `/tmp/shadowing-native-release-audit/ShadowingNative.xcarchive`. É **sem assinatura**, não um IPA pronto para instalar ou enviar.

| Item inspecionado no aplicativo compilado | Resultado |
| --- | --- |
| Bundle ID | `com.edromero.shadowing.next` |
| Versão / build | `1.0` / `1` |
| SDK / Xcode | iPhoneOS 27.0 / Xcode 27.0 (27A266a) |
| Sistema mínimo / aparelhos | iOS 17.0 / iPhone e iPad |
| Ícone e `CFBundleIcons` | Ausentes |
| `YouTubeDataAPIKey` | Não configurada; valor não exposto neste relatório |
| Manifesto de privacidade do próprio app | Ausente |
| Manifestos de SDKs | Encontrados, incluindo Firebase Auth/Firestore e Google Sign-In |
| Orientações no Info.plist final | Ausentes; archive emitiu aviso de compatibilidade de orientações |
| Declaração de exportação de criptografia | Não definida no Info.plist; questionário/documentação pendentes |

O aviso de App Intents sem dependência do framework não foi erro de compilação. O archive local não executa a validação completa do App Store Connect, assinatura de distribuição ou análise da Apple.

Os requisitos publicados atualmente pedem Xcode 26+ / SDK iOS 26+ e destino mínimo iOS 13+. As versões numéricas usadas atendem esses mínimos; a aceitação do build exato do Xcode ainda deve ser confirmada na validação de distribuição. [Requisitos atuais da Apple](https://developer.apple.com/news/upcoming-requirements/).

## Bloqueios e ações

### P0 — pacote de distribuição incompleto

1. **Adicionar AppIcon real.** O projeto referencia `AppIcon`, mas não há catálogo correspondente nem ícone no archive. Usar arte aprovada e configurar exportação de iPhone/iPad. [Ícone para distribuição](https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon/).
2. **Configurar descoberta no Release.** `project.yml:24` só inclui `Config/Debug.xcconfig`. O archive confirmou ausência da chave. Assim, testes de Debug não representam o feed que o beta receberia. Definir configuração de distribuição segura, restrições/cota ou backend; nunca versionar o segredo.
3. **Adicionar manifesto próprio.** Há uso direto de `UserDefaults` em AppModel, StudyProgressStore, VocabularyStore e ShortsDiscoveryService. Declarar a categoria e o motivo permitido correspondente ao uso real; manifestos de dependências não descrevem o código do app. Conferir o relatório agregado do archive. [APIs com motivo obrigatório](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [SDKs terceiros](https://developer.apple.com/support/third-party-SDK-requirements/).
4. **Corrigir orientações do iPad no Info.plist efetivo.** A configuração fonte não foi suficiente para produzir as chaves no archive. Escolher comportamento suportado, testar rotação e multitarefa; não apenas suprimir o aviso.
5. **Confirmar identidade antes de assinar.** O material local antigo usa `com.edromero.shadowing`; o nativo usa `.next`. Isso não é automaticamente uma atualização do registro antigo. Confirmar app novo versus atualização e alinhar identificador, Firebase, OAuth, Sign in with Apple, assinaturas, versão e provisioning. Não trocar o bundle ID isoladamente.

### P0 — privacidade e informações ao usuário

Não há links de política/termos/suporte nas telas nativas de cadastro, Perfil ou paywall. A política deve estar acessível no app e nos metadados. A autenticação obrigatória merece justificar quais recursos dependem da conta ou oferecer treino local como convidado. [Diretrizes 5.1.1](https://developer.apple.com/app-store/review/guidelines/#privacy).

As páginas públicas existentes retornaram HTTP 200:

- `https://edromeroc-hub.github.io/Shadowing/privacy.html`
- `https://edromeroc-hub.github.io/Shadowing/`

**Mas a política publicada ainda é de 12/09/2026**, não menciona Firebase/Firestore e descreve funcionalidades antigas. O `docs/privacy.html` local, de 01/10, também mistura versões, downloads, microfone e Gemini. Não basta colar esse URL: publicar uma política coerente com este binário, com retenção/exclusão, serviços e contato, sem alterar inadvertidamente a política das outras versões.

Inventário inicial para preparar App Privacy — não é uma declaração pronta para enviar:

| Dado observado no código | Uso / destino |
| --- | --- |
| Nome, e-mail e UID | Autenticação via Firebase, Apple/Google/e-mail |
| Nível, idiomas, interesses e metas | Perfil e personalização; Firestore |
| Links estudados, frase de retomada, acertos, feedback e vocabulário | Histórico, progresso e recomendações; Firestore |
| Dados técnicos dos SDKs | Conferir os manifestos e o comportamento efetivo das dependências |
| Tráfego do player/miniaturas/busca | YouTube/Google; incluir avaliação do WebView e seus terceiros |
| Gravação de voz, chave pessoal Gemini, download de vídeo | Não encontrados no fluxo desta versão; não copiar declarações da versão antiga |

O app não pode declarar simplesmente “nenhum dado coletado”. Dados de WebView também exigem avaliação. Não marcar tracking “sim” ou “não” apenas porque existe um player: verificar coleta, compartilhamento e finalidade, inclusive ATT quando aplicável. [App Privacy](https://developer.apple.com/app-store/app-privacy-details/). Os manifestos Firebase não substituem a declaração dos dados que nós gravamos no Firestore. [Guia Firebase](https://firebase.google.com/docs/ios/app-store-data-collection).

### P0 — assinatura ainda não representa um benefício implementado

Há StoreKit 2 para produtos, compra verificada, restauração e consulta de entitlement. Contudo:

- `SubscriptionStore.isSubscribed` não é consumido para liberar/restringir funcionalidades. “Agora não” conclui a anamnese e dá acesso ao app.
- O paywall promete feedback de fala (`Views/Paywall/PaywallView.swift:37`), mas não há implementação de gravação/reconhecimento/avaliação de fala neste target. Escuta ativa por palavras não equivale a avaliar áudio falado.
- Não há observação contínua de `Transaction.updates`; compra pendente, mudança externa, reembolso e expiração precisam de tratamento e testes.
- A elegibilidade/duração do teste de três dias não é lida/exibida. Não confirmei produtos/oferta introdutória no App Store Connect.
- O selo de melhor valor anual é fixo, sem comparação dos preços carregados.
- A restauração consulta entitlement, mas não conclui automaticamente o paywall quando encontra assinatura ativa. A ação de compra pode ficar habilitada mesmo com apenas o produto não selecionado carregado.

Definir se o primeiro beta será gratuito para todos ou se já testará benefícios pagos reais. Se gratuito, remover a oferta de compra para toda essa versão beta e explicar isso nas notas; não criar comportamento especial só para revisores. Se pago, completar benefícios, estado de assinatura e testes antes de enviar. Não use o pagamento para vender apenas acesso ao player YouTube.

O fluxo de assinatura deve informar benefício, período, preço total de renovação, restauração e links de termos/privacidade. Se houver teste, informar duração e preço posterior; StoreKit deve determinar elegibilidade. [Assinaturas Apple](https://developer.apple.com/app-store/subscriptions/).

### P1 — exclusão de conta implementada, mas não certificada

Pontos positivos: Perfil oferece exclusão permanente; existe confirmação, reautenticação e revogação Apple; há remoção de Firebase Auth, `nativeStudy/{uid}` e dados locais do perfil. Arquivos: `Views/Account/AccountAccessView.swift:230`, `Services/AuthSession.swift:91`, `Services/CloudStudySync.swift:138`.

Pendências concretas:

- O projeto Firebase é compartilhado. O código elimina apenas `nativeStudy/{uid}`, não documentos de outras coleções/versões eventualmente associados ao mesmo UID; ao eliminar Auth, essas versões também podem perder acesso. Mapear dados antes de prometer exclusão integral.
- `CloudStudySync.delete` retorna silenciosamente se o UID ativo não corresponde, permitindo que a etapa posterior elimine Auth sem comprovar a remoção do documento. Trocar esse caso por falha explícita ou operação robusta de backend.
- Confirmar conclusão visível ao usuário, além de simplesmente fechar a tela e voltar ao login.
- Testar falha de rede, gravação em andamento, reautenticação cancelada, Apple com e-mail oculto, Google e senha usando **contas descartáveis**, não a conta pessoal.
- O pedido anterior da Apple exigiu gravação em aparelho físico do fluxo completo. Esse vídeo ainda precisa ser produzido para a nova build.

A Apple exige exclusão da conta e dados associados, não só desativação. Confirmação e reautenticação são permitidas; o usuário deve entender o resultado e o destino da assinatura. [Guia de exclusão](https://developer.apple.com/support/offering-account-deletion-in-your-app/).

### P1 — conteúdo YouTube e legendas: risco de conformidade

O vídeo nativo usa IFrame oficial e não baixa arquivo de vídeo. **A legenda não usa a API oficial de captions:** `Services/YouTubeTranscriptService.swift:65` consulta cliente Android interno e página pública. Ter uma chave Data API para busca não autoriza esse extrator.

As regras Apple 5.2.2/5.2.3 exigem uso autorizado de serviços/conteúdo externos e podem exigir comprovação. A revisão antiga não mencionar downloads não significa aprovação deles ou deste novo fluxo. [Diretrizes Apple](https://developer.apple.com/app-store/review/guidelines/#intellectual-property).

As políticas YouTube proíbem scraping e pedem termos/privacidade apropriados. A API oficial `captions.download` requer autorização e permissão de editar o vídeo, não resolve legendas arbitrárias por uma chave pública. [Políticas YouTube](https://developers.google.com/youtube/terms/developer-policies), [Captions download](https://developers.google.com/youtube/v3/docs/captions/download).

Minha avaliação: **alto risco, sem aprovação garantida**. Para reduzir o risco de forma real, usar legendas fornecidas/licenciadas pelos criadores ou material próprio/autorizado, com identificação clara da origem. Isso é uma mudança de produto ainda não implementada. Não esconder o extrator nas notas nem desativá-lo só durante revisão.

Outras pendências: há `safeSearch=strict` na busca e opção local de ocultar, mas não há canal de denúncia/moderação dentro do app. Link direto contorna a curadoria da busca. Avaliar filtros, denúncia, bloqueio de canal e classificação etária para esse acesso a conteúdo de terceiros; ocultar não envia denúncia. Não classificar como infantil por ser educacional. Referências: seções 1.2 e 2.3 das [diretrizes Apple](https://developer.apple.com/app-store/review/guidelines/).

## O que já está encaminhado

- Interface nativa com valor pedagógico além de um navegador: repetição, exercícios, progresso e vocabulário.
- Login por e-mail, Apple e Google presente no código; Apple usa componente nativo. Validar provedores e assinatura no aparelho.
- Exclusão acessível no Perfil; precisa fechar as lacunas descritas.
- Pagamento usa StoreKit, não checkout externo; falta concluir a oferta funcional.
- Regras locais Firestore restringem `nativeStudy/{uid}` ao proprietário. Não foram verificadas regras efetivamente publicadas nem feito deploy nesta auditoria.
- Nenhuma permissão de câmera/localização/microfone pedida desnecessariamente. Se gravação for adicionada, implementar os purpose strings e tratamento de recusa junto com a função.

## Caminho até o TestFlight

### Etapa 1 — fechar produto e preparar distribuição

- [ ] Confirmar app novo versus atualização do registro antigo.
- [ ] Decidir beta gratuito ou teste de assinatura com benefícios reais.
- [ ] Resolver estratégia autorizada de legendas/conteúdo.
- [ ] Corrigir ícone, manifesto, orientações, configuração Release e URLs legais.
- [ ] Garantir exclusão completa/segura e autenticação no dispositivo.
- [ ] Gerar archive **assinado para distribuição**, usar Validate App e corrigir validações.
- [ ] Preencher export compliance com base na criptografia efetiva e SDKs; não marcar isenção sem verificar.

### Etapa 2 — beta interno

Upload normal para App Store Connect, processamento e grupo TestFlight interno. Até 100 usuários elegíveis do App Store Connect; não dar acesso administrativo a amigos só para testar. Evitar opção **TestFlight Internal Only** se pretendemos aproveitar o mesmo build externamente, porque ela o restringe ao grupo interno. [Testadores internos](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/).

### Etapa 3 — primeira revisão beta externa

Criar grupo externo e cadastrar descrição beta, e-mail de feedback, contato da revisão, instruções e uma conta demonstrativa funcional. Adicionar o build e enviar para TestFlight App Review. A primeira build externa passa por revisão; depois da aprovação, convidar por e-mail/link. Isso **não publica o app na App Store**. [Revisão externa](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/), [informações beta](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/).

O TestFlight permite até 10.000 externos e cada build vale até 90 dias. Sugestão operacional: começar com 10–20 pessoas convidadas, recolher problemas e só ampliar após estabilidade. [Visão geral](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

Compras via TestFlight operam em sandbox, com renovações aceleradas; não servem para validar receita real. Testar compra, cancelamento, restauração, pendência, expiração e reembolso. [Testes de assinaturas](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/).

### Etapa 4 — publicação na loja, separada do beta

Completar categoria, classificação etária atual, descrição, palavras-chave, suporte, privacidade, declarações de dados, screenshots atuais de iPhone/iPad e dados comerciais aplicáveis. Usar as dimensões solicitadas pelo painel atual, não reaproveitar cegamente screenshots da versão antiga. Revisar compras/assinaturas e submeter a versão de loja com notas fiéis ao funcionamento.

## Roteiro de aceite no beta

| Cenário | Critério para liberar |
| --- | --- |
| Instalação limpa e cadastro | Apple, Google e e-mail chegam ao estudo; recusar/cancelar não trava |
| Login e retomada | Histórico/frase retomam após fechar o app; conta B não vê dados de A |
| Exclusão | Auth + dados relacionados removidos; confirmação visível; gravação física do fluxo |
| Release com internet | Busca e legendas funcionam fora do Mac; erros/quota mostram recuperação |
| Shorts | Rolagem rápida não sobrepõe áudio, legenda ou tradução de vídeos distintos |
| Trechos | Pausa não retoma sozinha; frase não corta voz nem inclui fala extra na amostra revisada |
| Tradução no aparelho | Idiomas e download de modelos funcionam; iOS 17 tem limitação/fallback claro |
| Assinatura, se incluída | Benefício real, preço correto, restauração e atualizações de entitlement |
| Rede/permissões | Sem rede, interrupção e cancelamentos deixam caminho de saída/repetição |
| iPad e acessibilidade | Rotação, multitarefa, teclado, texto grande e VoiceOver não bloqueiam o treino |

Nenhum desses testes transacionais em produção foi executado nesta revisão. O archive passou; isso não substitui os cenários acima.

## Texto inicial para “O que testar”

> Teste cadastro e login, escolha de nível/interesses, retomada do último estudo e exclusão de uma conta criada apenas para o beta. Em vídeos e Shorts, confira se o áudio corresponde à frase exibida, se a pausa permanece pausada e se a troca de trecho/Short não mantém texto ou áudio anterior. Envie feedback pelo TestFlight com o link do vídeo, número da frase, modelo do aparelho e descrição do problema. Não use sua conta principal para testar exclusão enquanto a validação de dados compartilhados estiver pendente.

Antes da revisão externa, preparar notas em inglês descrevendo o fluxo real, credenciais de demonstração, URLs funcionais, vídeos de teste autorizados e o estado das compras. Não incluir senha no repositório. Não afirmar que a extração de legendas é oficial ou que a Apple já aprovou o conteúdo.
