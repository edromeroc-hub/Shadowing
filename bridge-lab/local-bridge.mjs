import os from 'node:os';

const relayUrl = process.env.RELAY_URL || 'http://localhost:8787';
const localShadowingUrl = process.env.LOCAL_SHADOWING_URL || 'http://localhost:3000';
const bridgeToken = process.env.BRIDGE_TOKEN || 'dev-bridge-token';
const deviceId = process.env.DEVICE_ID || os.hostname();
const pollIntervalMs = Number(process.env.POLL_INTERVAL_MS || 2000);

let stopped = false;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...(options.headers || {}),
    },
  });

  const text = await response.text();
  const data = text ? JSON.parse(text) : {};

  if (!response.ok) {
    throw new Error(data.error || `HTTP ${response.status}`);
  }

  return data;
}

async function getNextTask() {
  const url = new URL('/api/bridge/next', relayUrl);
  url.searchParams.set('deviceId', deviceId);

  return requestJson(url, {
    headers: {
      authorization: `Bearer ${bridgeToken}`,
    },
  });
}

async function fetchTranscript(videoId) {
  return requestJson(`${localShadowingUrl}/api/getEnrichedTranscript`, {
    method: 'POST',
    body: JSON.stringify({ videoId }),
  });
}

async function postResult(taskId, payload) {
  return requestJson(`${relayUrl}/api/bridge/tasks/${taskId}/result`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${bridgeToken}`,
    },
    body: JSON.stringify(payload),
  });
}

async function handleTask(task) {
  console.log(`[bridge:${deviceId}] processing ${task.videoId} (${task.id})`);

  try {
    const result = await fetchTranscript(task.videoId);
    await postResult(task.id, {
      ok: true,
      result,
    });
    console.log(`[bridge:${deviceId}] done ${task.id}: ${Array.isArray(result) ? result.length : 0} phrases`);
  } catch (error) {
    await postResult(task.id, {
      ok: false,
      error: error.message || 'Unknown local bridge error',
    });
    console.error(`[bridge:${deviceId}] failed ${task.id}:`, error.message || error);
  }
}

async function main() {
  console.log(`[bridge:${deviceId}] connected to relay ${relayUrl}`);
  console.log(`[bridge:${deviceId}] using local app ${localShadowingUrl}`);

  while (!stopped) {
    try {
      const { task } = await getNextTask();
      if (task) {
        await handleTask(task);
      } else {
        await sleep(pollIntervalMs);
      }
    } catch (error) {
      console.error(`[bridge:${deviceId}] relay loop error:`, error.message || error);
      await sleep(pollIntervalMs);
    }
  }
}

process.on('SIGINT', () => {
  stopped = true;
  console.log('\nBridge stopping...');
});

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
