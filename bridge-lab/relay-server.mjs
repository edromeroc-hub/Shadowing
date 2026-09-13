import http from 'node:http';
import crypto from 'node:crypto';

const port = Number(process.env.RELAY_PORT || 8787);
const bridgeToken = process.env.BRIDGE_TOKEN || 'dev-bridge-token';
const appToken = process.env.APP_TOKEN || 'dev-app-token';

const tasks = new Map();
const bridges = new Map();

function sendJson(response, status, payload) {
  const body = JSON.stringify(payload);
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'content-type,authorization,x-app-token',
  });
  response.end(body);
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let body = '';
    request.on('data', (chunk) => {
      body += chunk;
      if (body.length > 5_000_000) {
        reject(new Error('Payload too large'));
        request.destroy();
      }
    });
    request.on('end', () => {
      if (!body.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch {
        reject(new Error('Invalid JSON'));
      }
    });
    request.on('error', reject);
  });
}

function requireAppAuth(request, response) {
  if (request.headers['x-app-token'] === appToken) return true;
  sendJson(response, 401, { error: 'Invalid app token' });
  return false;
}

function requireBridgeAuth(request, response) {
  const header = request.headers.authorization || '';
  if (header === `Bearer ${bridgeToken}`) return true;
  sendJson(response, 401, { error: 'Invalid bridge token' });
  return false;
}

function publicTask(task) {
  return {
    id: task.id,
    videoId: task.videoId,
    status: task.status,
    assignedDeviceId: task.assignedDeviceId,
    createdAt: task.createdAt,
    updatedAt: task.updatedAt,
    result: task.result,
    error: task.error,
  };
}

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url || '/', `http://${request.headers.host}`);

  if (request.method === 'OPTIONS') {
    sendJson(response, 200, { ok: true });
    return;
  }

  try {
    if (request.method === 'GET' && url.pathname === '/health') {
      sendJson(response, 200, {
        ok: true,
        tasks: tasks.size,
        bridges: [...bridges.values()],
      });
      return;
    }

    if (request.method === 'GET' && url.pathname === '/api/bridges') {
      if (!requireAppAuth(request, response)) return;
      sendJson(response, 200, {
        bridges: [...bridges.values()].map((bridge) => ({
          ...bridge,
          online: Date.now() - bridge.lastSeenAt < 10_000,
        })),
      });
      return;
    }

    if (request.method === 'POST' && url.pathname === '/api/tasks') {
      if (!requireAppAuth(request, response)) return;
      const body = await readJson(request);
      const videoId = String(body.videoId || '').trim();

      if (!videoId) {
        sendJson(response, 400, { error: 'videoId is required' });
        return;
      }

      const now = Date.now();
      const task = {
        id: crypto.randomUUID(),
        videoId,
        status: 'pending',
        assignedDeviceId: null,
        createdAt: now,
        updatedAt: now,
        result: null,
        error: null,
      };

      tasks.set(task.id, task);
      sendJson(response, 202, publicTask(task));
      return;
    }

    const taskMatch = url.pathname.match(/^\/api\/tasks\/([^/]+)$/);
    if (request.method === 'GET' && taskMatch) {
      if (!requireAppAuth(request, response)) return;
      const task = tasks.get(taskMatch[1]);
      if (!task) {
        sendJson(response, 404, { error: 'Task not found' });
        return;
      }
      sendJson(response, 200, publicTask(task));
      return;
    }

    if (request.method === 'GET' && url.pathname === '/api/bridge/next') {
      if (!requireBridgeAuth(request, response)) return;
      const deviceId = String(url.searchParams.get('deviceId') || 'unknown-device').trim();
      const now = Date.now();

      bridges.set(deviceId, {
        deviceId,
        lastSeenAt: now,
      });

      const task = [...tasks.values()].find((candidate) => candidate.status === 'pending');
      if (!task) {
        sendJson(response, 200, { task: null });
        return;
      }

      task.status = 'running';
      task.assignedDeviceId = deviceId;
      task.updatedAt = now;
      sendJson(response, 200, {
        task: {
          id: task.id,
          videoId: task.videoId,
        },
      });
      return;
    }

    const bridgeResultMatch = url.pathname.match(/^\/api\/bridge\/tasks\/([^/]+)\/result$/);
    if (request.method === 'POST' && bridgeResultMatch) {
      if (!requireBridgeAuth(request, response)) return;
      const task = tasks.get(bridgeResultMatch[1]);
      if (!task) {
        sendJson(response, 404, { error: 'Task not found' });
        return;
      }

      const body = await readJson(request);
      task.status = body.ok ? 'done' : 'error';
      task.result = body.ok ? body.result : null;
      task.error = body.ok ? null : String(body.error || 'Unknown bridge error');
      task.updatedAt = Date.now();

      sendJson(response, 200, publicTask(task));
      return;
    }

    sendJson(response, 404, { error: 'Not found' });
  } catch (error) {
    sendJson(response, 500, { error: error.message || 'Internal error' });
  }
});

server.listen(port, () => {
  console.log(`Shadowing Relay Lab running on http://localhost:${port}`);
  console.log('This is an in-memory prototype. Do not use these dev tokens in production.');
});
