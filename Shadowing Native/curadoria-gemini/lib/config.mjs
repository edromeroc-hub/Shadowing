import { readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

// Usa as mesmas credenciais que o Mac já tem para o curador. Nada aqui é impresso.
export const configPath = path.join(os.homedir(), '.config', 'shadowing-curator', 'curator.env');

export async function loadConfig() {
  let text;
  try {
    text = await readFile(configPath, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') throw new Error(`Configuração não encontrada em ${configPath}. Veja curator/README.md.`);
    throw error;
  }
  const values = {};
  for (const line of text.split('\n')) {
    const match = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line);
    if (match && !line.trim().startsWith('#')) values[match[1]] = match[2].replace(/^["']|["']$/g, '');
  }
  return values;
}

export async function youtubeKey() {
  const key = (await loadConfig()).YOUTUBE_DATA_API_KEY;
  if (!key || key.includes('COLE_')) throw new Error('YOUTUBE_DATA_API_KEY ausente no curator.env.');
  return key;
}

export async function firestore() {
  const values = await loadConfig();
  if (values.FIREBASE_PROJECT_ID !== 'shadowing-commercial-edromero' || !values.GOOGLE_APPLICATION_CREDENTIALS) {
    throw new Error('FIREBASE_PROJECT_ID ou GOOGLE_APPLICATION_CREDENTIALS ausentes no curator.env.');
  }
  const { initializeApp, cert, getApps } = await import('firebase-admin/app');
  const { getFirestore } = await import('firebase-admin/firestore');
  if (!getApps().length) {
    const credential = JSON.parse(await readFile(values.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
    initializeApp({ credential: cert(credential), projectId: values.FIREBASE_PROJECT_ID });
  }
  return getFirestore();
}
