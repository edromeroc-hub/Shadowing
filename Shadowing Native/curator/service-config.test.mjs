import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { loadServiceConfig } from './service-config.mjs';

test('service config accepts private credentials outside the repository', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'shadowing-curator-'));
  try {
    const repository = path.join(directory, 'repository');
    const credential = path.join(directory, 'firebase.json');
    const config = path.join(directory, 'curator.env');
    await mkdir(repository);
    await writeFile(credential, JSON.stringify({
      type: 'service_account', project_id: 'shadowing-commercial-edromero',
      client_email: 'test@example.invalid', private_key: '-----BEGIN PRIVATE KEY-----',
    }), { mode: 0o600 });
    await writeFile(config, `FIREBASE_PROJECT_ID=shadowing-commercial-edromero\nGOOGLE_APPLICATION_CREDENTIALS=${credential}\nYOUTUBE_DATA_API_KEY=private-value\n`, { mode: 0o600 });
    const variables = await loadServiceConfig(config, repository);
    assert.equal(variables.FIREBASE_PROJECT_ID, 'shadowing-commercial-edromero');
    assert.equal(variables.YOUTUBE_DATA_API_KEY, 'private-value');
    const inside = path.join(repository, 'firebase.json');
    await writeFile(inside, JSON.stringify({
      type: 'service_account', project_id: 'shadowing-commercial-edromero',
      client_email: 'test@example.invalid', private_key: '-----BEGIN PRIVATE KEY-----',
    }), { mode: 0o600 });
    await writeFile(config, `FIREBASE_PROJECT_ID=shadowing-commercial-edromero\nGOOGLE_APPLICATION_CREDENTIALS=${inside}\nYOUTUBE_DATA_API_KEY=private-value\n`, { mode: 0o600 });
    await assert.rejects(loadServiceConfig(config, repository), /fora do repositório/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
