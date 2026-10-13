import { access, readFile, readdir, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { YoutubeTranscript } from 'youtube-transcript';
import { affinityFor, buildPhrases, phrasesArePractical, prepare } from './quality.mjs';
import { assessShortsFormat } from './shorts-format.mjs';
import {
  automaticReviewReasons, beginCycle, canTrustChannel, finishSearchPage,
  markCycleComplete, refreshSearchBudget, scanIntervalMs,
} from './workflow.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const stateDirectory = path.join(root, '.state');
const reviewDirectory = path.join(stateDirectory, 'review');
const metadataDirectory = path.join(stateDirectory, 'metadata');
const publishedDirectory = path.join(stateDirectory, 'published');
const rejectedDirectory = path.join(stateDirectory, 'rejected');
const statePath = path.join(stateDirectory, 'progress.json');
const trustPath = path.join(stateDirectory, 'trusted-channels.json');
const manualPath = path.join(stateDirectory, 'manual-publications.json');
const command = process.argv[2];
const localCommand = ['review', 'reject', 'trust-channel', 'untrust-channel', 'audit-shorts', 'resegment', 'queue-channels'].includes(command);
const offline = process.env.CURATOR_OFFLINE === '1' || localCommand;
const projectID = process.env.FIREBASE_PROJECT_ID;
const youtubeKey = process.env.YOUTUBE_DATA_API_KEY;
const requestLimit = Math.min(1000, Math.max(1, Number(process.env.CURATOR_LIMIT || 100)));
const dailySearchLimit = Math.min(100, Math.max(1, Number(process.env.CURATOR_SEARCHES_PER_DAY || 20)));

if (!['scan', 'review', 'reject', 'publish', 'trust-channel', 'untrust-channel', 'aggregate', 'audit-shorts', 'resegment', 'queue-channels'].includes(command)) {
  throw new Error('Use scan, review, reject, publish, trust-channel, untrust-channel, aggregate, audit-shorts, resegment ou queue-channels.');
}
if (!localCommand && projectID !== 'shadowing-commercial-edromero') {
  throw new Error('Defina FIREBASE_PROJECT_ID=shadowing-commercial-edromero para evitar publicar no projeto errado.');
}
if (['scan', 'audit-shorts', 'queue-channels'].includes(command) && !youtubeKey) throw new Error('Defina YOUTUBE_DATA_API_KEY.');
if (process.env.CURATOR_OFFLINE === '1' && !['scan', 'review', 'reject', 'trust-channel', 'untrust-channel', 'audit-shorts', 'resegment', 'queue-channels'].includes(command)) {
  throw new Error('O modo local não publica nem agrega.');
}

if (!offline) initializeApp({ credential: applicationDefault(), projectId: projectID });
const database = offline ? null : getFirestore();
await mkdir(reviewDirectory, { recursive: true });
await mkdir(metadataDirectory, { recursive: true });
await mkdir(publishedDirectory, { recursive: true });
await mkdir(rejectedDirectory, { recursive: true });

async function readJSON(file, fallback) {
  try { return JSON.parse(await readFile(file, 'utf8')); } catch (error) {
    if (error.code === 'ENOENT') return fallback;
    throw error;
  }
}

async function saveJSON(file, value) {
  const temporary = `${file}.${process.pid}.${randomUUID()}.tmp`;
  await writeFile(temporary, JSON.stringify(value, null, 2));
  const { rename } = await import('node:fs/promises');
  await rename(temporary, file);
}

async function markerExists(directory, videoID) {
  try {
    await access(path.join(directory, `${videoID}.json`));
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    throw error;
  }
}

async function youtube(pathname, parameters) {
  const url = new URL(`https://www.googleapis.com/youtube/v3/${pathname}`);
  for (const [key, value] of Object.entries(parameters)) {
    if (value != null) url.searchParams.set(key, String(value));
  }
  url.searchParams.set('key', youtubeKey);
  const response = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (!response.ok) throw new Error(`YouTube ${pathname}: HTTP ${response.status}`);
  return response.json();
}

async function metadata(videoID) {
  const response = await youtube('videos', {
    part: 'snippet,contentDetails,status,player', id: videoID, maxHeight: 720, maxWidth: 720,
  });
  const item = response.items?.[0];
  const format = assessShortsFormat(item);
  if (!format.eligible) throw new Error(format.reason);
  return {
    videoID, title: item.snippet.title, channel: item.snippet.channelTitle,
    channelID: item.snippet.channelId, shortsFormat: format.evidence,
  };
}

async function captionSegments(videoID) {
  const result = await YoutubeTranscript.fetchTranscript(videoID, { lang: 'en' });
  if (!result.length) throw new Error('Legenda em inglês indisponível');
  return result.map((part) => ({
    text: part.text,
    start: Number(part.offset) / 1000,
    end: (Number(part.offset) + Math.max(40, Number(part.duration))) / 1000,
    hasWordTiming: false,
  }));
}

async function suggestions() {
  if (offline) return [];
  const results = await database.collectionGroup('suggestions').get();
  return [...new Set(results.docs.flatMap((document) => document.data().videoIDs || []))]
    .filter((videoID) => /^[A-Za-z0-9_-]{11}$/.test(videoID))
    .map((videoID) => ({ videoID }));
}

async function searchChannel(seed, pageToken) {
  const response = await youtube('search', {
    part: 'snippet', type: 'video', channelId: seed.channelID,
    q: '#shorts', videoDuration: 'short', videoEmbeddable: 'true',
    safeSearch: 'strict', relevanceLanguage: 'en', maxResults: 50, pageToken,
  });
  return {
    videoIDs: response.items?.map((item) => item.id?.videoId)
      .filter((videoID) => /^[A-Za-z0-9_-]{11}$/.test(videoID || '')) || [],
    nextPageToken: response.nextPageToken || null,
  };
}

async function queueChannels() {
  const selectedIDs = [...new Set(process.argv.slice(3))];
  const seeds = await readJSON(path.join(root, 'seeds.json'), []);
  if (!selectedIDs.length || selectedIDs.some((channelID) => !seeds.some((seed) => seed.channelID === channelID))) {
    throw new Error('Informe IDs de canais já cadastrados em seeds.json.');
  }
  const state = await readJSON(statePath, { seedIndex: 0, pending: [], processed: {} });
  state.pending ||= [];
  state.processed ||= {};
  refreshSearchBudget(state, Date.now());
  if (state.prioritySearchCount + selectedIDs.length > 8) {
    throw new Error('Limite de 8 buscas prioritárias por dia atingido; aguarde a próxima rodada.');
  }
  let queued = 0;
  for (const channelID of selectedIDs) {
    const seed = seeds.find((item) => item.channelID === channelID);
    state.prioritySearchCount += 1;
    await saveJSON(statePath, state);
    const result = await searchChannel(seed, null);
    const alreadyQueued = new Set(state.pending.map((item) => item.videoID));
    for (const videoID of result.videoIDs) {
      if (state.processed[videoID] || alreadyQueued.has(videoID)) continue;
      state.pending.push({ videoID, interest: seed.interest });
      alreadyQueued.add(videoID);
      queued += 1;
    }
    await saveJSON(statePath, state);
    console.log(`${channelID}: ${result.videoIDs.length} encontrados; ${queued} novos na fila até agora.`);
  }
  console.log(`${queued} Shorts colocados na fila de triagem; nenhuma publicação realizada.`);
}

async function scan() {
  const seeds = await readJSON(path.join(root, 'seeds.json'), []);
  const state = await readJSON(statePath, { seedIndex: 0, pageToken: null, pending: [], processed: {} });
  state.pending ||= [];
  state.processed ||= {};
  if (!beginCycle(state, seeds.length, Date.now())) {
    console.log(`Próxima rodada de canais: ${new Date(state.nextCycleAt).toISOString()}.`);
    return;
  }
  refreshSearchBudget(state, Date.now());
  let inspected = 0;
  let accepted = 0;
  const queue = await suggestions();
  async function inspect(videoID, seededInterest, source) {
    if (inspected >= requestLimit || state.processed[videoID] ||
      await markerExists(publishedDirectory, videoID) || await markerExists(rejectedDirectory, videoID)) return;
    inspected += 1;
    try {
      const details = await metadata(videoID);
      const rawSegments = await captionSegments(videoID);
      const prepared = prepare({ ...details, rawSegments, seededInterest });
      const payload = JSON.stringify(prepared);
      if (Buffer.byteLength(payload, 'utf8') > 750000) throw new Error('Transcrição grande demais para um documento');
      await saveJSON(path.join(reviewDirectory, `${videoID}.json`), prepared);
      await saveJSON(path.join(metadataDirectory, `${videoID}.json`), {
        source, seededInterest: seededInterest || null, scannedAt: new Date().toISOString(),
        videoID, title: prepared.title, channel: prepared.channel, level: prepared.level,
        interests: prepared.interests, phraseCount: prepared.phrases.length,
        shortsFormatPassed: true, shortsFormat: details.shortsFormat,
      });
      state.processed[videoID] = 'review';
      accepted += 1;
      console.log(`APROVÁVEL ${videoID} ${prepared.level} ${prepared.interests.join(',')} ${prepared.title}`);
    } catch (error) {
      if (/HTTP 4|quota|fetch failed|timeout/i.test(error.message)) throw error;
      state.processed[videoID] = 'rejected';
      console.log(`REJEITADO ${videoID} ${error.message}`);
    }
    await saveJSON(statePath, state);
  }
  for (const item of queue) await inspect(item.videoID, null, 'suggestion');
  while (inspected < requestLimit && (state.pending.length || state.seedIndex < seeds.length)) {
    if (state.pending.length) {
      const candidate = state.pending[0];
      await inspect(candidate.videoID, candidate.interest, 'seed');
      state.pending.shift();
      await saveJSON(statePath, state);
      continue;
    }
    if (state.searchCount >= dailySearchLimit) {
      console.log(`Limite diário de buscas alcançado (${dailySearchLimit}); retome amanhã.`);
      break;
    }
    const seed = seeds[state.seedIndex];
    state.searchCount += 1;
    await saveJSON(statePath, state);
    const result = await searchChannel(seed, state.pageToken);
    state.currentInterest = seed.interest;
    finishSearchPage(state, result);
    await saveJSON(statePath, state);
  }
  markCycleComplete(state, seeds.length, Date.now());
  await saveJSON(statePath, state);
  console.log(`Inspecionados ${inspected}; para revisão ${accepted}; buscas hoje ${state.searchCount}/${dailySearchLimit}; próximo canal ${Math.min(state.seedIndex + 1, seeds.length)}/${seeds.length}.`);
}

async function reviewedCandidate(videoID) {
  if (!/^[A-Za-z0-9_-]{11}$/.test(videoID)) throw new Error(`ID inválido: ${videoID}`);
  const prepared = await readJSON(path.join(reviewDirectory, `${videoID}.json`), null);
  if (!prepared || prepared.videoID !== videoID) throw new Error(`Candidato não encontrado: ${videoID}`);
  return prepared;
}

async function publishCandidate(prepared) {
  if (prepared.segmentationVersion !== 2 || prepared.segmentationReviewRequired ||
    !phrasesArePractical(prepared.phrases, prepared.level)) {
    throw new Error(`Trechos de ${prepared.videoID} precisam ser refeitos antes da publicação.`);
  }
  const record = await readJSON(path.join(metadataDirectory, `${prepared.videoID}.json`), null);
  if (!record?.shortsFormatPassed || await markerExists(rejectedDirectory, prepared.videoID)) {
    throw new Error(`Formato Short não confirmado para ${prepared.videoID}; execute a auditoria primeiro.`);
  }
  const reference = database.collection('approvedShorts').doc(prepared.videoID);
  const existing = await reference.get();
  let created = false;
  if (existing.exists) {
    if (existing.data().status !== 'approved') throw new Error(`Documento existente não aprovado: ${prepared.videoID}`);
  } else {
    try {
      await reference.create({
        status: 'approved', level: prepared.level, interests: prepared.interests,
        payload: JSON.stringify(prepared), verifiedAt: FieldValue.serverTimestamp(),
      });
      created = true;
    } catch (error) {
      if (error.code !== 6) throw error;
    }
  }
  await saveJSON(path.join(publishedDirectory, `${prepared.videoID}.json`), {
    channelID: prepared.channelID, publishedAt: new Date().toISOString(),
  });
  if (created) console.log(`PUBLICADO ${prepared.videoID}`);
  return created;
}

async function review() {
  const filenames = (await readdir(reviewDirectory)).filter((name) => /^[A-Za-z0-9_-]{11}\.json$/.test(name));
  const state = await readJSON(statePath, { processed: {} });
  const trusted = await readJSON(trustPath, []);
  const published = new Set(await readdir(publishedDirectory));
  const rejected = new Set(await readdir(rejectedDirectory));
  let pending = 0;
  for (const filename of filenames) {
    const videoID = filename.slice(0, -5);
    if (['published', 'rejected'].includes(state.processed?.[videoID]) ||
      published.has(filename) || rejected.has(filename)) continue;
    pending += 1;
    if (pending > 30) continue;
    const prepared = await reviewedCandidate(videoID);
    const metadata = await readJSON(path.join(metadataDirectory, filename), null);
    const reasons = automaticReviewReasons(prepared, metadata, trusted);
    console.log(`${videoID} | ${prepared.level} | ${prepared.channel} | ${prepared.title}`);
    console.log(`  https://www.youtube.com/shorts/${videoID} | ${prepared.phrases.length} trechos | ${reasons.join('; ') || 'elegível após confiança no canal'}`);
  }
  console.log(`${pending} candidato(s) aguardando revisão/publicação; exibidos até 30.`);
}

async function auditShorts() {
  const files = (await readdir(reviewDirectory)).filter((name) => /^[A-Za-z0-9_-]{11}\.json$/.test(name));
  const published = new Set(await readdir(publishedDirectory));
  const rejected = new Set(await readdir(rejectedDirectory));
  const pending = files.filter((name) => !published.has(name) && !rejected.has(name));
  const decisions = [];
  for (let offset = 0; offset < pending.length; offset += 50) {
    const batch = pending.slice(offset, offset + 50);
    const response = await youtube('videos', {
      part: 'snippet,contentDetails,status,player', id: batch.map((name) => name.slice(0, -5)).join(','),
      maxHeight: 720, maxWidth: 720,
    });
    const returned = new Map((response.items || []).map((item) => [item.id, item]));
    for (const filename of batch) {
      const videoID = filename.slice(0, -5);
      decisions.push({ videoID, filename, format: assessShortsFormat(returned.get(videoID)) });
    }
  }
  const state = await readJSON(statePath, { processed: {} });
  state.processed ||= {};
  let retained = 0;
  let removed = 0;
  for (const { videoID, filename, format } of decisions) {
    if (format.eligible) {
      const file = path.join(metadataDirectory, filename);
      const existing = await readJSON(file, {});
      await saveJSON(file, { ...existing, shortsFormatPassed: true, shortsFormat: format.evidence });
      retained += 1;
    } else {
      await saveJSON(path.join(rejectedDirectory, filename), {
        rejectedAt: new Date().toISOString(), reason: format.reason, shortsFormat: format.evidence,
      });
      state.processed[videoID] = 'rejected';
      removed += 1;
    }
  }
  await saveJSON(statePath, state);
  console.log(`Auditoria concluída: ${retained} candidato(s) compatíveis com Shorts; ${removed} retirados da revisão.`);
}

async function resegment() {
  const filenames = (await readdir(reviewDirectory)).filter((name) => /^[A-Za-z0-9_-]{11}\.json$/.test(name));
  const published = new Set(await readdir(publishedDirectory));
  const rejected = new Set(await readdir(rejectedDirectory));
  let updated = 0;
  let needsReview = 0;
  for (const filename of filenames) {
    if (published.has(filename) || rejected.has(filename)) continue;
    const file = path.join(reviewDirectory, filename);
    const prepared = await readJSON(file, null);
    if (!prepared || prepared.segmentationVersion === 2) continue;
    const phrases = buildPhrases(prepared.segments, prepared.level);
    const segmentationReviewRequired = !phrasesArePractical(phrases, prepared.level);
    await saveJSON(file, { ...prepared, phrases, segmentationVersion: 2, segmentationReviewRequired });
    const metadataFile = path.join(metadataDirectory, filename);
    const record = await readJSON(metadataFile, null);
    if (record) await saveJSON(metadataFile, { ...record, phraseCount: phrases.length });
    updated += 1;
    if (segmentationReviewRequired) needsReview += 1;
  }
  console.log(`${updated} candidato(s) com novos trechos; ${needsReview} precisam de revisão da divisão.`);
}

async function publish() {
  const videoIDs = process.argv.slice(3);
  if (!videoIDs.length) throw new Error('Informe explicitamente os IDs revisados: npm run publish -- ID1 ID2');
  const manual = await readJSON(manualPath, []);
  for (const videoID of videoIDs) {
    const prepared = await reviewedCandidate(videoID);
    await publishCandidate(prepared);
    if (!manual.some((item) => item.videoID === videoID)) {
      manual.push({ videoID, channelID: prepared.channelID, reviewedAt: new Date().toISOString() });
      await saveJSON(manualPath, manual);
    }
  }
}

async function reject() {
  const videoIDs = process.argv.slice(3);
  if (!videoIDs.length) throw new Error('Informe os IDs rejeitados: npm run reject -- ID1 ID2');
  const state = await readJSON(statePath, { processed: {} });
  for (const videoID of videoIDs) {
    await reviewedCandidate(videoID);
    if (state.processed?.[videoID] === 'published' || await markerExists(publishedDirectory, videoID)) {
      throw new Error(`Já publicado: ${videoID}`);
    }
    await saveJSON(path.join(rejectedDirectory, `${videoID}.json`), { rejectedAt: new Date().toISOString() });
    console.log(`REJEITADO MANUALMENTE ${videoID}`);
  }
}

async function trustChannel() {
  const channelID = process.argv[3];
  if (!/^UC[A-Za-z0-9_-]{22}$/.test(channelID || '')) throw new Error('Informe um ID de canal válido.');
  const manual = await readJSON(manualPath, []);
  if (!canTrustChannel(manual, channelID)) {
    throw new Error('Revise e publique manualmente pelo menos três Shorts distintos deste canal antes de confiar nele.');
  }
  const trusted = await readJSON(trustPath, []);
  if (!trusted.includes(channelID)) {
    trusted.push(channelID);
    await saveJSON(trustPath, trusted);
  }
  console.log(`Canal revisado: ${channelID}`);
}

async function untrustChannel() {
  const channelID = process.argv[3];
  if (!/^UC[A-Za-z0-9_-]{22}$/.test(channelID || '')) throw new Error('Informe um ID de canal válido.');
  const trusted = await readJSON(trustPath, []);
  await saveJSON(trustPath, trusted.filter((item) => item !== channelID));
  console.log(`Publicação automática desativada para ${channelID}`);
}

async function autoPublish() {
  const trusted = await readJSON(trustPath, []);
  if (!trusted.length) return console.log('Publicação automática aguardando revisão de canais.');
  const state = await readJSON(statePath, { processed: {} });
  const filenames = (await readdir(reviewDirectory)).filter((name) => /^[A-Za-z0-9_-]{11}\.json$/.test(name));
  const publishedFiles = new Set(await readdir(publishedDirectory));
  const rejectedFiles = new Set(await readdir(rejectedDirectory));
  let published = 0;
  for (const filename of filenames) {
    if (published >= Math.min(requestLimit, 25)) break;
    const videoID = filename.slice(0, -5);
    if (state.processed?.[videoID] !== 'review' ||
      publishedFiles.has(filename) || rejectedFiles.has(filename)) continue;
    const prepared = await reviewedCandidate(videoID);
    const metadata = await readJSON(path.join(metadataDirectory, filename), null);
    if (automaticReviewReasons(prepared, metadata, trusted).length) continue;
    if (await publishCandidate(prepared)) published += 1;
  }
  console.log(`Publicação automática: ${published} Short(s).`);
}

async function aggregate() {
  const votes = await database.collectionGroup('votes').get();
  const byVideo = new Map();
  for (const snapshot of votes.docs) {
    const vote = snapshot.data();
    if (!/^[A-Za-z0-9_-]{11}$/.test(vote.videoID || '') || !Array.isArray(vote.interests)) continue;
    if (!byVideo.has(vote.videoID)) byVideo.set(vote.videoID, []);
    byVideo.get(vote.videoID).push(vote);
  }
  let updated = 0;
  for (const [videoID, signals] of byVideo) {
    const reference = database.collection('approvedShorts').doc(videoID);
    const snapshot = await reference.get();
    if (!snapshot.exists) continue;
    const prepared = JSON.parse(snapshot.data().payload);
    const affinity = affinityFor(prepared, signals);
    if (JSON.stringify(prepared.affinity || {}) === JSON.stringify(affinity)) continue;
    prepared.affinity = affinity;
    await reference.update({ payload: JSON.stringify(prepared) });
    updated += 1;
  }
  console.log(`Afinidade atualizada em ${updated} Shorts.`);
}

async function continuous() {
  while (true) {
    for (const [name, step] of [['busca', scan], ['publicação', autoPublish]]) {
      try { await step(); } catch (error) { console.error(`${name}: ${error.message}`); }
    }
    try {
      const state = await readJSON(statePath, { processed: {} });
      const day = new Date().toISOString().slice(0, 10);
      if (state.lastAggregateDay !== day) {
        await aggregate();
        state.lastAggregateDay = day;
        await saveJSON(statePath, state);
      }
    } catch (error) {
      console.error(`agregação: ${error.message}`);
    }
    await new Promise((resolve) => setTimeout(resolve, scanIntervalMs));
  }
}

if (command === 'scan' && process.env.CURATOR_CONTINUOUS === '1') {
  if (offline) throw new Error('Modo contínuo requer Firebase para publicar e agregar.');
  await continuous();
}
if (command === 'scan' && process.env.CURATOR_CONTINUOUS !== '1') await scan();
if (command === 'review') await review();
if (command === 'audit-shorts') await auditShorts();
if (command === 'queue-channels') await queueChannels();
if (command === 'resegment') await resegment();
if (command === 'reject') await reject();
if (command === 'publish') await publish();
if (command === 'trust-channel') await trustChannel();
if (command === 'untrust-channel') await untrustChannel();
if (command === 'aggregate') await aggregate();
