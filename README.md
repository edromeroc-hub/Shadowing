# ShadowingAI — versão comercial App Store

> Branch isolada: `commercial-appstore`. A versão funcional atual permanece na branch `main` e não deve ser alterada a partir desta pasta.

Esta cópia prepara a migração do app para um catálogo próprio de vídeos e legendas com direitos comerciais comprovados. Consulte `COMMERCIAL_VERSION_PLAN.md`, `CONTENT_RIGHTS_POLICY.md` e `docs/commercial-content-sources.md` antes de implementar ingestão ou publicar conteúdo.

<div align="center">
<img width="1200" height="475" alt="GHBanner" src="https://ai.google.dev/static/site-assets/images/share-ais-513315318.png" />
</div>

# Run and deploy your AI Studio app

## Aplicativo para Mac

Consulte `MAC_SETUP.md` para instalar e atualizar a versão desktop com servidor local integrado.

This contains everything you need to run your app locally.

View your app in AI Studio: https://ai.studio/apps/82e3d454-8325-419f-b3cf-57f2052a5fa7

## Run Locally

**Prerequisites:**  Node.js


1. Install dependencies:
   `npm install`
2. Set the `GEMINI_API_KEY` in [.env.local](.env.local) to your Gemini API key
3. Run the app:
   `npm run dev`
