const relayUrl = process.env.RELAY_URL || 'http://localhost:8787';
const appToken = process.env.APP_TOKEN || 'dev-app-token';
const videoId = process.argv[2];

if (!videoId) {
  console.error('Usage: npm run test -- VIDEO_ID');
  process.exit(1);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      'content-type': 'application/json',
      'x-app-token': appToken,
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

const task = await requestJson(`${relayUrl}/api/tasks`, {
  method: 'POST',
  body: JSON.stringify({ videoId }),
});

console.log(`Task created: ${task.id}`);

for (let attempt = 1; attempt <= 120; attempt += 1) {
  const current = await requestJson(`${relayUrl}/api/tasks/${task.id}`);

  if (current.status === 'done') {
    const phrases = Array.isArray(current.result) ? current.result : [];
    console.log(`Done: ${phrases.length} phrases`);
    console.log('First phrase:', phrases[0] || null);
    process.exit(0);
  }

  if (current.status === 'error') {
    console.error('Task failed:', current.error);
    process.exit(1);
  }

  console.log(`Waiting: ${current.status}`);
  await sleep(1000);
}

console.error('Timed out waiting for bridge result.');
process.exit(1);
