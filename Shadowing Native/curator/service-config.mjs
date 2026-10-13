import { readFile, realpath, stat } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

export const configPath = path.join(os.homedir(), '.config', 'shadowing-curator', 'curator.env');

export async function loadServiceConfig(file = configPath, repositoryRoot = process.cwd()) {
  const fileInfo = await stat(file).catch((error) => {
    if (error.code === 'ENOENT') throw new Error(`Crie ${file} a partir de curator.env.example antes de instalar o serviço.`);
    throw error;
  });
  if (fileInfo.mode & 0o077) throw new Error('O arquivo de configuração deve ser privado (chmod 600).');
  const variables = {};
  for (const original of (await readFile(file, 'utf8')).split(/\r?\n/)) {
    const line = original.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator < 1) throw new Error('Configuração inválida: use CHAVE=valor em cada linha.');
    variables[line.slice(0, separator).trim()] = line.slice(separator + 1).trim().replace(/^(["'])(.*)\1$/, '$2');
  }
  if (variables.FIREBASE_PROJECT_ID !== 'shadowing-commercial-edromero') {
    throw new Error('Projeto Firebase incorreto na configuração.');
  }
  if (!variables.YOUTUBE_DATA_API_KEY || variables.YOUTUBE_DATA_API_KEY.includes('COLE_')) {
    throw new Error('Configure uma chave YouTube Data API para o Mac.');
  }
  const credentialPath = variables.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credentialPath || !path.isAbsolute(credentialPath)) {
    throw new Error('GOOGLE_APPLICATION_CREDENTIALS deve apontar para um JSON fora do projeto.');
  }
  const absoluteRepository = await realpath(repositoryRoot);
  const absoluteCredential = await realpath(credentialPath).catch((error) => {
    if (error.code === 'ENOENT') throw new Error('O JSON Firebase não existe no caminho configurado.');
    throw error;
  });
  if (absoluteCredential === absoluteRepository || absoluteCredential.startsWith(`${absoluteRepository}${path.sep}`)) {
    throw new Error('Guarde a credencial Firebase fora do repositório.');
  }
  const credentialInfo = await stat(absoluteCredential);
  if (credentialInfo.mode & 0o077) throw new Error('O JSON Firebase deve ser privado (chmod 600).');
  const credential = JSON.parse(await readFile(absoluteCredential, 'utf8'));
  if (credential.type !== 'service_account' || credential.project_id !== variables.FIREBASE_PROJECT_ID ||
    typeof credential.client_email !== 'string' ||
    typeof credential.private_key !== 'string' || !credential.private_key.includes('BEGIN PRIVATE KEY')) {
    throw new Error('A credencial Firebase não pertence ao projeto esperado.');
  }
  return variables;
}
