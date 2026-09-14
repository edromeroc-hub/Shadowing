# Backend comercial Firebase do ShadowingAI

## Projeto criado

- Firebase Project ID: `shadowing-commercial-edromero`
- Região do Firestore e das Functions: `southamerica-east1`
- Aplicativo Web: `ShadowingAI Commercial Web`
- Aplicativo iOS: `ShadowingAI Commercial iOS`
- Bundle ID: `com.edromero.shadowing`

## Arquitetura

- Firebase Authentication com e-mail e senha.
- Firestore Standard para perfis, catálogo, aulas, progresso, direitos, planos e auditoria de IA.
- Cloud Storage privado para vídeos, áudios, imagens e documentos de direitos.
- Cloud Functions de segunda geração para a API Node autenticada.
- Firebase Hosting para o aplicativo React e encaminhamento de `/api/**` para a função `api`.
- Gemini acessível somente pela função, usando Secret Manager e quota por usuário.

O cliente não consulta Firestore ou Storage diretamente. Ele recebe um Firebase ID token, envia esse token para a API e a API valida conta, plano, território e licença antes de liberar qualquer mídia.

## Estado atual

Já estão provisionados no plano Spark:

- projeto Firebase exclusivo;
- aplicativo Web e aplicativo iOS registrados;
- Firebase Authentication com e-mail/senha;
- Firestore Standard em São Paulo;
- regras Firestore publicadas com acesso direto negado;
- configuração de Firebase Hosting.

O projeto ainda está sem faturamento. Projetos novos precisam do plano Blaze para criar o bucket do Cloud Storage e publicar Cloud Functions. Ativar Blaze não significa cobrança fixa, mas libera faturamento por uso acima das franquias gratuitas.

## Segurança do Firestore

As regras em `firestore.rules` usam `default deny`. O aplicativo comercial não recebe permissão direta para ler ou gravar nenhuma coleção. Somente o Firebase Admin SDK da API acessa:

- `profiles/{uid}`;
- `contentItems/{contentId}`;
- `lessons/{lessonId}`;
- `progress/{uid_contentId}`;
- `entitlements/{uid}`;
- `aiUsage/{requestId}`.

Administradores são definidos por ambiente confiável e nunca por dados editáveis do usuário.

## Segurança do Storage

As regras em `storage.rules` negam acesso direto a todos os objetos. Depois de validar direitos e território, a API gera uma URL assinada com validade curta.

Pastas utilizadas:

- `lesson-assets/<slug>/video.mp4`;
- `lesson-assets/<slug>/artwork.webp`;
- `lesson-assets/<slug>/captions.vtt`;
- `rights-evidence/<slug>/documento.pdf`.

## Variáveis públicas do aplicativo

O arquivo local `.env` está ignorado pelo Git. O build web/iOS utiliza apenas os valores públicos do Firebase Web SDK:

```text
VITE_FIREBASE_API_KEY
VITE_FIREBASE_AUTH_DOMAIN
VITE_FIREBASE_PROJECT_ID
VITE_FIREBASE_STORAGE_BUCKET
VITE_FIREBASE_MESSAGING_SENDER_ID
VITE_FIREBASE_APP_ID
VITE_COMMERCIAL_CATALOG_MODE=true
VITE_API_URL=
```

Esses identificadores públicos não concedem acesso ao banco; a proteção efetiva está nas regras e na API.

## Credenciais do servidor

No Cloud Functions, o Firebase Admin usa credenciais automáticas. Para executar a API ou o publicador localmente, defina:

```text
FIREBASE_PROJECT_ID=shadowing-commercial-edromero
FIREBASE_STORAGE_BUCKET=shadowing-commercial-edromero.firebasestorage.app
GOOGLE_APPLICATION_CREDENTIALS=/caminho/privado/firebase-admin.json
COMMERCIAL_CLOUD_MODE=true
ENABLE_LEGACY_YOUTUBE=false
```

O JSON administrativo nunca deve entrar no repositório, bundle web ou IPA.

## Ativação final após Blaze

1. Vincular uma conta de faturamento ao projeto `shadowing-commercial-edromero`.
2. Criar o bucket padrão do Cloud Storage na região desejada.
3. Configurar o segredo do Gemini:

```bash
npx -y firebase-tools@latest functions:secrets:set GEMINI_API_KEY --project shadowing-commercial-edromero
```

4. Construir e publicar:

```bash
npm run build
npm run build:function
npx -y firebase-tools@latest deploy --only storage,functions,hosting --project shadowing-commercial-edromero
```

5. Confirmar:

```text
GET https://shadowing-commercial-edromero.web.app/api/commercial/health
```

O retorno esperado contém `configured: true`, `cloudMode: true` e `provider: firebase`.

## Publicação de conteúdo

Copie `content/catalog/example-commercial-content.json`, preencha os dados e coloque os arquivos nos caminhos locais indicados. O manifesto exige:

- titular e fonte original;
- arquivo permanente de evidência;
- hash SHA-256 calculado automaticamente;
- territórios explícitos;
- autorização comercial, streaming e tradução;
- autorização separada para download offline;
- frases e tempos revisados;
- `legalReviewConfirmed: true` somente depois da revisão documental.

Publique com:

```bash
npm run content:publish -- content/catalog/meu-conteudo.json
```

O publicador mantém o conteúdo como rascunho durante os uploads e só aponta a aula publicada quando mídia, direitos e segmentos terminam sem erro.

## Rotas comerciais

- `GET /api/commercial/health`
- `GET /api/commercial/me`
- `PUT /api/commercial/me`
- `DELETE /api/commercial/me`
- `GET /api/commercial/catalog`
- `GET /api/commercial/catalog/:slug`
- `GET /api/commercial/catalog/:slug/media`
- `GET /api/commercial/progress`
- `PUT /api/commercial/progress/:contentId`
- `POST /api/analyzePronunciation`

Todas, exceto `health`, exigem `Authorization: Bearer <Firebase ID token>`.

## Critérios antes do lançamento

- Blaze e alertas de orçamento configurados;
- regras Firestore e Storage revisadas;
- nenhum segredo dentro do bundle;
- pelo menos um conteúdo aprovado para `BR`;
- exclusão de conta testada;
- política de privacidade e termos publicados;
- conta de demonstração para revisão;
- build de iPhone e iPad validado contra a API HTTPS.
