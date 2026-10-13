import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { getCandidate, listCandidates, validVideoID } from './review-store.mjs';

const execFileAsync = promisify(execFile);
const root = path.dirname(fileURLToPath(import.meta.url));
const staticFiles = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/app.js', ['app.js', 'text/javascript; charset=utf-8']],
  ['/styles.css', ['styles.css', 'text/css; charset=utf-8']],
]);
const securityHeaders = {
  'Cache-Control': 'no-store',
  'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' https://i.ytimg.com; frame-src https://www.youtube-nocookie.com; connect-src 'self'; base-uri 'none'; form-action 'none'",
  'Referrer-Policy': 'origin',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
};

function send(response, status, value, contentType = 'application/json; charset=utf-8') {
  response.writeHead(status, { ...securityHeaders, 'Content-Type': contentType });
  response.end(contentType.startsWith('application/json') ? JSON.stringify(value) : value);
}

async function runAction(action, videoID) {
  const script = action === 'approve' ? 'run-service.mjs' : 'curator.mjs';
  const command = action === 'approve' ? 'publish' : 'reject';
  await execFileAsync(process.execPath, [path.join(root, script), command, videoID], {
    cwd: root, timeout: 60000, maxBuffer: 1024 * 1024,
  });
}

export function createDashboardServer({ stateDirectory = path.join(root, '.state'), actionRunner = runAction } = {}) {
  const token = randomBytes(32);
  const inFlight = new Set();
  return createServer(async (request, response) => {
    const address = request.socket.address();
    const localHost = `127.0.0.1:${address.port}`;
    if (!['127.0.0.1', '::ffff:127.0.0.1'].includes(request.socket.remoteAddress) ||
      request.headers.host !== localHost) {
      send(response, 403, { error: 'Acesso local apenas.' });
      return;
    }

    try {
      const url = new URL(request.url, `http://${localHost}`);
      if (request.method === 'GET' && staticFiles.has(url.pathname)) {
        const [filename, type] = staticFiles.get(url.pathname);
        send(response, 200, await readFile(path.join(root, 'dashboard-public', filename)), type);
        return;
      }
      if (request.method === 'GET' && url.pathname === '/api/session') {
        send(response, 200, { token: token.toString('hex') });
        return;
      }
      if (request.method === 'GET' && url.pathname === '/api/candidates') {
        send(response, 200, await listCandidates(stateDirectory, Object.fromEntries(url.searchParams)));
        return;
      }
      const match = /^\/api\/candidates\/([A-Za-z0-9_-]{11})(?:\/(approve|reject))?$/.exec(url.pathname);
      if (!match || !validVideoID(match[1])) {
        send(response, 404, { error: 'Página não encontrada.' });
        return;
      }
      const [, videoID, action] = match;
      if (request.method === 'GET' && !action) {
        const candidate = await getCandidate(stateDirectory, videoID);
        send(response, candidate ? 200 : 404, candidate || { error: 'Candidato não encontrado.' });
        return;
      }
      if (request.method !== 'POST' || !action) {
        send(response, 405, { error: 'Método inválido.' });
        return;
      }
      const origin = `http://${localHost}`;
      const suppliedToken = request.headers['x-curator-token'];
      const tokenBytes = typeof suppliedToken === 'string' && /^[0-9a-f]{64}$/.test(suppliedToken) ?
        Buffer.from(suppliedToken, 'hex') : Buffer.alloc(0);
      if (request.headers.origin !== origin || request.headers['content-type'] !== 'application/json' ||
        tokenBytes.length !== token.length || !timingSafeEqual(tokenBytes, token)) {
        send(response, 403, { error: 'Confirmação local inválida.' });
        return;
      }
      if (inFlight.has(videoID)) {
        send(response, 409, { error: 'Este candidato já está sendo atualizado.' });
        return;
      }
      const candidate = await getCandidate(stateDirectory, videoID);
      if (!candidate) {
        send(response, 404, { error: 'Candidato não encontrado.' });
        return;
      }
      if (candidate.status !== 'pending') {
        send(response, 409, { error: 'Este candidato já foi revisado.' });
        return;
      }
      inFlight.add(videoID);
      try {
        await actionRunner(action, videoID);
        send(response, 200, { status: action === 'approve' ? 'published' : 'rejected' });
      } finally {
        inFlight.delete(videoID);
      }
    } catch (error) {
      console.error('Falha no painel de curadoria:', error);
      send(response, 500, { error: 'Não foi possível concluir. Confira o terminal do curador.' });
    }
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.CURATOR_DASHBOARD_PORT || 4318);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Porta inválida.');
  const server = createDashboardServer();
  server.listen(port, '127.0.0.1', () => {
    console.log(`Painel de curadoria: http://127.0.0.1:${port}`);
  });
}
