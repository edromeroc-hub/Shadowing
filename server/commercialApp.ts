import express from 'express';
import { GoogleGenAI, Schema, Type } from '@google/genai';
import { createCommercialBackend } from './commercialBackend';

const allowedOrigins = new Set([
  'capacitor://localhost',
  'http://localhost',
  'http://localhost:3000',
  'https://shadowing-commercial-edromero.web.app',
  'https://shadowing-commercial-edromero.firebaseapp.com',
  ...String(process.env.APP_ALLOWED_ORIGINS || '').split(',').map((origin) => origin.trim()).filter(Boolean),
]);

export function createCommercialApp() {
  const app = express();
  const backend = createCommercialBackend();

  app.use((req, res, next) => {
    const origin = req.headers.origin;
    if (origin && allowedOrigins.has(origin)) {
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.setHeader('Vary', 'Origin');
      res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
      res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    }
    if (req.method === 'OPTIONS') return res.sendStatus(204);
    return next();
  });
  app.use(express.json({ limit: '4mb' }));
  app.use('/api/commercial', backend.router);

  app.post('/api/analyzePronunciation', backend.protectAi, async (req, res) => {
    const phrase = String(req.body?.phrase || '').trim();
    const base64Data = String(req.body?.audioBase64 || '').replace(/^data:[^;]+;base64,/, '');
    const mimeType = String(req.body?.mimeType || 'audio/webm').split(';')[0].toLowerCase();
    const allowedMimeTypes = new Set(['audio/webm', 'audio/mp4', 'audio/mpeg', 'audio/wav', 'audio/ogg']);
    if (!phrase || phrase.length > 500 || !allowedMimeTypes.has(mimeType)
      || !base64Data || base64Data.length > 2_500_000 || !/^[A-Za-z0-9+/=]+$/.test(base64Data)) {
      return res.status(400).json({ error: 'Áudio ou frase inválida.' });
    }

    const apiKey = String(process.env.GEMINI_API_KEY || '').trim();
    if (!apiKey) return res.status(503).json({ error: 'A avaliação por IA ainda não foi configurada.' });

    const schema: Schema = {
      type: Type.OBJECT,
      properties: {
        score: { type: Type.NUMBER },
        words: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              word: { type: Type.STRING },
              correct: { type: Type.BOOLEAN },
              tip: { type: Type.STRING },
            },
            required: ['word', 'correct', 'tip'],
          },
        },
      },
      required: ['score', 'words'],
    };

    try {
      const ai = new GoogleGenAI({ apiKey });
      const response = await ai.models.generateContent({
        model: process.env.GEMINI_MODEL?.trim() || 'gemini-2.5-flash',
        contents: [
          `Compare a gravação com a frase inglesa: "${phrase}". Avalie cada palavra. Responda dicas curtas em português brasileiro somente quando necessário.`,
          { inlineData: { data: base64Data, mimeType } },
        ],
        config: {
          responseMimeType: 'application/json',
          responseSchema: schema,
          temperature: 0.2,
        },
      });
      if (!response.text) throw new Error('Resposta vazia do modelo.');
      return res.json(JSON.parse(response.text));
    } catch (error) {
      console.error('[commercial] pronunciation failed', error);
      return res.status(502).json({ error: 'Não foi possível avaliar sua pronúncia agora.' });
    }
  });

  app.use((_req, res) => res.status(404).json({ error: 'Rota não encontrada.' }));
  return app;
}
