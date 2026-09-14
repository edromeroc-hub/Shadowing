# Backend comercial do ShadowingAI

## Arquitetura entregue

- Supabase Auth para contas reais por e-mail e senha.
- Postgres com RLS para perfis, catálogo, aulas, progresso, biblioteca e limites de IA.
- Supabase Storage privado para mídia, arte e documentos de direitos.
- API Node autenticada que valida o JWT, aplica território/licença e entrega URLs temporárias.
- Chave do Gemini somente no servidor, com limite mensal por usuário e trilha de uso.
- Exclusão de conta dentro do app.
- Rotas de download, legenda e recomendação do YouTube bloqueadas em produção comercial.

## 1. Criar o projeto Supabase

Crie um projeto separado chamado `ShadowingAI Commercial` na organização `edromeroc-hub`, preferencialmente na região `sa-east-1`.

Não reutilize banco, chaves ou buckets de outro aplicativo.

## 2. Aplicar o banco

Aplique a migração:

```text
supabase/migrations/202609130001_commercial_backend.sql
```

Ela cria:

- `profiles`;
- `content_items`, `content_rights` e `content_assets`;
- `lessons` e `lesson_segments`;
- `user_progress` e `user_library`;
- `user_entitlements` e `ai_usage_events`;
- buckets privados `lesson-media`, `lesson-artwork` e `rights-evidence`;
- políticas RLS e funções de controle territorial.

Depois da migração, rode os advisors de segurança e desempenho do Supabase. Nenhuma tabela do schema `public` deve ficar sem RLS.

## 3. Configurar autenticação

Em Supabase Authentication:

1. mantenha e-mail/senha habilitado;
2. configure os URLs do app web e os redirects autorizados;
3. durante testes fechados, escolha conscientemente se a confirmação por e-mail ficará ligada;
4. antes da App Store, configure Sign in with Apple se outro login social for oferecido;
5. nunca use `user_metadata` para definir administradores.

O papel administrativo deve ficar em `app_metadata.role = "admin"` e ser atribuído somente por ambiente seguro.

## 4. Variáveis do servidor

Copie `.env.example` para `.env` somente no ambiente local ou configure as variáveis no provedor:

```text
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
SUPABASE_SECRET_KEY
GEMINI_API_KEY
COMMERCIAL_CLOUD_MODE=true
ENABLE_LEGACY_YOUTUBE=false
APP_ALLOWED_ORIGINS=https://SEU_FRONTEND,capacitor://localhost
```

`SUPABASE_SECRET_KEY` e `GEMINI_API_KEY` nunca entram no frontend, no IPA ou no repositório.

## 5. Variáveis do app

O build web/iOS recebe somente valores públicos:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_PUBLISHABLE_KEY
VITE_COMMERCIAL_CATALOG_MODE=true
VITE_API_URL=https://SUA_API
```

A publishable key não substitui segurança: a proteção efetiva está nas políticas RLS e na validação da API.

## 6. Hospedar a API

Execute:

```bash
npm ci
npm run build
npm start
```

Use Render, Fly.io, Railway, Cloud Run ou VPS com HTTPS. O processo precisa receber as variáveis de servidor e acessar Supabase/Gemini.

O endpoint de verificação é:

```text
GET /api/commercial/health
```

Em produção, o retorno esperado é `configured: true` e `cloudMode: true`.

## 7. Publicar conteúdo

Copie `content/catalog/example-commercial-content.json`, preencha os dados e coloque os arquivos locais nos caminhos indicados.

O manifesto exige:

- titular e fonte original;
- arquivo permanente de evidência;
- hash SHA-256 calculado automaticamente para o vídeo;
- territórios explícitos;
- permissões de streaming, tradução e, separadamente, download offline;
- frases e tempos revisados;
- `legalReviewConfirmed: true` somente depois da revisão documental.

Publique com:

```bash
npm run content:publish -- content/catalog/meu-conteudo.json
```

O comando mantém o item como rascunho durante uploads e só publica depois que direitos, mídia, aula e segmentos terminam sem erro.

## 8. Rotas comerciais

- `GET /api/commercial/me`
- `PUT /api/commercial/me`
- `DELETE /api/commercial/me`
- `GET /api/commercial/catalog`
- `GET /api/commercial/catalog/:slug`
- `GET /api/commercial/catalog/:slug/media`
- `GET /api/commercial/progress`
- `PUT /api/commercial/progress/:contentId`

Todas, exceto `health`, exigem `Authorization: Bearer <Supabase access token>`.

## 9. Critérios antes do lançamento

- projeto Supabase exclusivo do ShadowingAI;
- advisors sem falhas críticas de segurança;
- nenhum segredo dentro do bundle;
- pelo menos um conteúdo aprovado disponível no território da conta de revisão;
- política de privacidade e termos publicados;
- exclusão de conta testada;
- conta de demonstração para a Apple;
- retirada de conteúdo testada mudando `content_items.status` para `archived`;
- build de iPhone e iPad validado contra a API HTTPS.
