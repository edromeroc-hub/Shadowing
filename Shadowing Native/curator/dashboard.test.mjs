import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createDashboardServer } from './dashboard.mjs';
import { getCandidate, listCandidates } from './review-store.mjs';

async function fixture() {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'shadowing-dashboard-'));
  for (const name of ['review', 'metadata', 'published', 'rejected']) {
    await mkdir(path.join(directory, name));
  }
  const videoID = 'AbCdEfGh123';
  const prepared = {
    videoID, title: 'A short English conversation', channel: 'Example Channel',
    channelID: 'UC1234567890123456789012', level: 'intermediate', interests: ['lifestyle'],
    phrases: Array.from({ length: 5 }, (_, index) => ({
      text: 'We are talking about ordinary life.', start: index * 4, end: index * 4 + 3,
    })),
    segments: Array.from({ length: 10 }, (_, index) => ({
      text: 'We are talking about ordinary life.', start: index * 2, end: index * 2 + 1.5,
    })),
  };
  await writeFile(path.join(directory, 'review', `${videoID}.json`), JSON.stringify(prepared));
  await writeFile(path.join(directory, 'metadata', `${videoID}.json`), JSON.stringify({
    videoID, title: prepared.title, channel: prepared.channel, level: prepared.level,
    interests: prepared.interests, phraseCount: prepared.phrases.length,
    scannedAt: '2026-10-12T12:00:00.000Z', source: 'seed', seededInterest: 'lifestyle',
  }));
  await writeFile(path.join(directory, 'progress.json'), JSON.stringify({
    pending: [{ videoID: 'OtherVideo1' }], searchCount: 2,
    processed: { [videoID]: 'review', OtherVideo1: 'rejected' },
  }));
  return { directory, videoID };
}

test('lists reviewed candidates without returning transcript in the list', async (context) => {
  const { directory, videoID } = await fixture();
  context.after(() => rm(directory, { recursive: true, force: true }));
  const list = await listCandidates(directory, { status: 'pending', query: 'example', level: 'intermediate' });
  assert.equal(list.counts.pending, 1);
  assert.equal(list.progress.inspected, 2);
  assert.equal(list.items[0].videoID, videoID);
  assert.equal(list.items[0].phrases, undefined);
  assert.equal((await getCandidate(directory, videoID)).phrases.length, 5);
  assert.equal((await listCandidates(directory, { level: 'advanced' })).total, 0);
  assert.equal((await listCandidates(directory, { query: 'missing' })).total, 0);
  assert.equal((await listCandidates(directory, { q: 'missing' })).total, 0);
  const queue = await listCandidates(directory, { status: 'queued' });
  assert.equal(queue.counts.queued, 1);
  assert.equal(queue.items[0].videoID, 'OtherVideo1');
  assert.equal((await getCandidate(directory, 'OtherVideo1')).status, 'queued');
  await writeFile(path.join(directory, 'rejected', `${videoID}.json`), JSON.stringify({ reason: 'Vídeo horizontal, não é Short' }));
  assert.equal((await getCandidate(directory, videoID)).rejectionReason, 'Vídeo horizontal, não é Short');
});

test('manual actions require the local origin and session token', async (context) => {
  const { directory, videoID } = await fixture();
  context.after(() => rm(directory, { recursive: true, force: true }));
  const actions = [];
  const server = createDashboardServer({
    stateDirectory: directory,
    actionRunner: async (action, id) => {
      actions.push([action, id]);
      await writeFile(path.join(directory, action === 'approve' ? 'published' : 'rejected', `${id}.json`), '{}');
    },
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  context.after(() => new Promise((resolve) => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  const token = (await (await fetch(`${base}/api/session`)).json()).token;
  const endpoint = `${base}/api/candidates/${videoID}/approve`;
  const headers = { 'Content-Type': 'application/json', 'X-Curator-Token': token };
  assert.equal((await fetch(endpoint, { method: 'POST', headers, body: '{}' })).status, 403);
  assert.equal((await fetch(endpoint, { method: 'POST', headers: { ...headers, Origin: 'https://evil.example' }, body: '{}' })).status, 403);
  assert.equal((await fetch(endpoint, { method: 'POST', headers: { ...headers, Origin: base, 'X-Curator-Token': 'x' }, body: '{}' })).status, 403);
  assert.equal(actions.length, 0);
  const approved = await fetch(endpoint, { method: 'POST', headers: { ...headers, Origin: base }, body: '{}' });
  assert.equal(approved.status, 200);
  assert.deepEqual(actions, [['approve', videoID]]);
  assert.equal((await fetch(endpoint, { method: 'POST', headers: { ...headers, Origin: base }, body: '{}' })).status, 409);
  assert.equal((await listCandidates(directory, { status: 'published' })).counts.published, 1);
  assert.equal((await fetch(`${base}/api/candidates/../../etc/passwd`)).status, 404);
});
