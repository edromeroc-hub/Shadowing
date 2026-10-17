#!/usr/bin/env node
// CLI e gerenciador do banco separado de Músicas (`approvedMusic` no Firestore).
// Suporta tanto vídeos musicais completos (`format: "video"`) quanto Shorts musicais (`format: "short"`).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { firestore, youtubeKey } from './lib/config.mjs';
import { buildMusicIndex, buildMusicLesson } from './lib/music.mjs';
import { findChannel, videoInfo } from './lib/youtube-data.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const workDir = path.join(root, 'trabalho-musica');
const registryPath = path.join(root, 'registro-musica.jsonl');

export function getMusicRegistry() {
  if (!fs.existsSync(registryPath)) return [];
  return fs
    .readFileSync(registryPath, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => {
      try { return JSON.parse(line); } catch { return null; }
    })
    .filter(Boolean);
}

export function getMusicPublishedMap() {
  const latest = new Map();
  for (const entry of getMusicRegistry()) {
    latest.set(entry.videoID, entry);
  }
  return latest;
}

export function recordMusicEntry(entry) {
  fs.appendFileSync(registryPath, `${JSON.stringify({ at: new Date().toISOString(), ...entry })}\n`);
}

export async function fetchArtistPlaylistItems(key, channelID, prefix = 'UULP', max = 25) {
  const playlistID = `${prefix}${channelID.slice(2)}`;
  const url = new URL('https://www.googleapis.com/youtube/v3/playlistItems');
  url.searchParams.set('part', 'contentDetails,snippet');
  url.searchParams.set('playlistId', playlistID);
  url.searchParams.set('maxResults', String(Math.min(50, max)));
  url.searchParams.set('key', key);

  const res = await fetch(url);
  if (!res.ok) return [];
  const data = await res.json();
  return (data.items || [])
    .map((item) => item.contentDetails?.videoId)
    .filter((id) => /^[A-Za-z0-9_-]{11}$/.test(id || ''));
}

export async function curateAndPublishMusicVideo(videoID, { genres = ['pop'], infoOverride = null } = {}) {
  const seen = getMusicPublishedMap();
  if (seen.has(videoID)) {
    return { ok: false, skipped: true, reason: `Já processado (${seen.get(videoID).action})` };
  }

  let res;
  try {
    res = await buildMusicLesson(videoID, { genres, infoOverride });
  } catch (err) {
    const msg = err.message || 'Erro ao buscar legenda';
    if (err.code === 'RATE_LIMITED' || msg.includes('429')) {
      throw err;
    }
    recordMusicEntry({ videoID, action: 'rejeitado', reason: msg });
    return { ok: false, reason: msg };
  }

  if (!res.ok) {
    recordMusicEntry({ videoID, action: 'rejeitado', reason: res.reason });
    return { ok: false, reason: res.reason };
  }

  const payload = res.payload;
  const itemDir = path.join(workDir, videoID);
  fs.mkdirSync(itemDir, { recursive: true });
  fs.writeFileSync(path.join(itemDir, 'documento.json'), `${JSON.stringify(payload, null, 2)}\n`);

  const db = await firestore();
  const { FieldValue } = await import('firebase-admin/firestore');
  await db.collection('approvedMusic').doc(videoID).set({
    status: 'approved',
    format: payload.format, // "video" ou "short"
    level: payload.level,
    artist: payload.artist,
    trackTitle: payload.trackTitle,
    genres: payload.genres,
    lyricsSource: payload.lyricsSource,
    durationSeconds: payload.durationSeconds,
    version: 1,
    payload: JSON.stringify(payload),
    verifiedAt: FieldValue.serverTimestamp(),
    curatedBy: 'antigravity-gemini-music',
  });

  recordMusicEntry({
    videoID,
    action: 'publicado',
    format: payload.format,
    level: payload.level,
    artist: payload.artist,
    trackTitle: payload.trackTitle,
    genres: payload.genres,
    lyricsSource: payload.lyricsSource,
    phrasesCount: payload.phrases.length,
  });

  return { ok: true, payload };
}

export async function curateArtistChannel(handle, genres = ['pop'], { maxVideos = 12, maxShorts = 10 } = {}) {
  const key = await youtubeKey();
  const found = await findChannel(key, handle);
  if (!found.length) {
    console.log(`Canal de artista não encontrado: ${handle}`);
    return { videosPublished: 0, shortsPublished: 0 };
  }
  const channel = found[0];
  console.log(`\n🎵 Artista/Canal: ${channel.title} (${handle} | ${channel.channelID}) — Gêneros: [${genres.join(', ')}]`);

  // 1. Vídeos musicais completos populares (UULP + UU)
  const popularIDs = maxVideos > 0 ? await fetchArtistPlaylistItems(key, channel.channelID, 'UULP', maxVideos * 2) : [];
  const uploadIDs = maxVideos > 0 ? await fetchArtistPlaylistItems(key, channel.channelID, 'UU', maxVideos * 2) : [];
  // 2. Shorts musicais do canal (UUSH)
  const shortIDs = maxShorts > 0 ? await fetchArtistPlaylistItems(key, channel.channelID, 'UUSH', maxShorts * 3) : [];

  const allIDs = [...new Set([...popularIDs, ...uploadIDs, ...shortIDs])];
  const seen = getMusicPublishedMap();
  const unseenIDs = allIDs.filter((id) => !seen.has(id));
  if (!unseenIDs.length) {
    console.log(`  Nenhum vídeo/Short inédito para ${handle}.`);
    return { videosPublished: 0, shortsPublished: 0 };
  }

  const infos = await videoInfo(key, unseenIDs);
  const infoMap = new Map(infos.map((i) => [i.videoID, i]));

  let videosPublished = 0;
  let shortsPublished = 0;

  for (const id of unseenIDs) {
    const info = infoMap.get(id);
    if (!info || info.short?.reason === 'não incorporável') continue;
    const isShort = info.short?.ok || info.short?.seconds <= 95;
    if (isShort && shortsPublished >= maxShorts) continue;
    if (!isShort && videosPublished >= maxVideos) continue;
    // Ignora vídeos muito longos (> 8 min) ou muito curtos (< 15s)
    if (info.short?.seconds > 480 || info.short?.seconds < 15) continue;

    const result = await curateAndPublishMusicVideo(id, { genres, infoOverride: info });
    if (result.ok) {
      const p = result.payload;
      if (p.format === 'short') shortsPublished++;
      else videosPublished++;
      console.log(`  ✅ PUBLICADO [${p.videoID}] (${p.format.toUpperCase()} | ${p.level} | ${p.lyricsSource}): ${p.artist} — "${p.trackTitle}" (${p.phrases.length} versos)`);
    } else if (!result.skipped) {
      console.log(`  ❌ PULADO [${id}] "${info.title}": ${result.reason}`);
    }
  }

  return { videosPublished, shortsPublished };
}

// Grava `approvedMusic/_index` a partir dos documentos publicados (cópias locais em trabalho-musica/).
export function localMusicIndex() {
  const published = [...getMusicPublishedMap().values()].filter((entry) => entry.action === 'publicado');
  const payloads = published
    .map((entry) => path.join(workDir, entry.videoID, 'documento.json'))
    .filter((file) => fs.existsSync(file))
    .map((file) => JSON.parse(fs.readFileSync(file, 'utf8')));
  return buildMusicIndex(payloads);
}

export async function publishMusicIndex() {
  const entries = localMusicIndex();
  fs.writeFileSync(path.join(workDir, '_index.json'), `${JSON.stringify(entries, null, 2)}\n`);
  const db = await firestore();
  const { FieldValue } = await import('firebase-admin/firestore');
  await db.collection('approvedMusic').doc('_index').set({ version: 1, count: entries.length, entries, updatedAt: FieldValue.serverTimestamp() });
  console.log(`🗂️  Índice de músicas publicado: ${entries.length} músicas, ${new Set(entries.map((entry) => entry.a)).size} artistas.`);
  return entries;
}

export function printMusicStatus() {
  const latest = getMusicPublishedMap();
  const published = [...latest.values()].filter((e) => e.action === 'publicado');
  const rejected = [...latest.values()].filter((e) => e.action === 'rejeitado');

  const byFormat = { video: 0, short: 0 };
  const byLevel = { beginner: 0, intermediate: 0, advanced: 0 };
  const byGenre = {};
  const bySource = {};

  for (const p of published) {
    byFormat[p.format || 'video'] = (byFormat[p.format || 'video'] || 0) + 1;
    byLevel[p.level] = (byLevel[p.level] || 0) + 1;
    bySource[p.lyricsSource || 'unknown'] = (bySource[p.lyricsSource || 'unknown'] || 0) + 1;
    for (const g of p.genres || []) {
      byGenre[g] = (byGenre[g] || 0) + 1;
    }
  }

  console.log(`======================================================`);
  console.log(`🎵 DATABASE DE MÚSICAS (approvedMusic): ${published.length} publicados (Rejeitados: ${rejected.length})`);
  console.log(`Formato : Vídeos Completos = ${byFormat.video || 0} | Shorts Musicais = ${byFormat.short || 0}`);
  console.log(`Níveis  : Iniciante = ${byLevel.beginner || 0} | Intermediário = ${byLevel.intermediate || 0} | Avançado = ${byLevel.advanced || 0}`);
  console.log(`Fontes  : ${JSON.stringify(bySource)}`);
  console.log(`Gêneros : ${JSON.stringify(byGenre)}`);
  console.log(`======================================================`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [cmd, arg1, arg2] = process.argv.slice(2);
  if (cmd === 'situacao') {
    printMusicStatus();
  } else if (cmd === 'artista' && arg1) {
    const genres = (arg2 || 'pop').split(',').map((s) => s.trim());
    curateArtistChannel(arg1, genres).then(() => publishMusicIndex()).then(() => printMusicStatus());
  } else if (cmd === 'indice') {
    publishMusicIndex();
  } else {
    console.log('Uso: node musica_cli.mjs situacao | node musica_cli.mjs artista @Handle genero1,genero2 | node musica_cli.mjs indice');
  }
}
