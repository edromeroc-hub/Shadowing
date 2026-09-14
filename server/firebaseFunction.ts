import { defineSecret } from 'firebase-functions/params';
import { onRequest } from 'firebase-functions/v2/https';
import { setGlobalOptions } from 'firebase-functions/v2/options';
import { createCommercialApp } from './commercialApp';

setGlobalOptions({ region: 'southamerica-east1', maxInstances: 10 });

const geminiApiKey = defineSecret('GEMINI_API_KEY');
let app: ReturnType<typeof createCommercialApp> | null = null;

export const api = onRequest({
  memory: '512MiB',
  timeoutSeconds: 120,
  secrets: [geminiApiKey],
}, (request, response) => {
  process.env.COMMERCIAL_CLOUD_MODE = 'true';
  process.env.GEMINI_API_KEY = geminiApiKey.value();
  app ||= createCommercialApp();
  return app(request, response);
});
