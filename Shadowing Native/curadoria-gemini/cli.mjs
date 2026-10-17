#!/usr/bin/env node
// Ferramentas do Caminho B: o Gemini no Antigravity faz a curadoria e chama estes comandos.
// Uso: node cli.mjs <comando> [...]. Veja README.md.
import { appendFile, mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { firestore, youtubeKey } from './lib/config.mjs';
import { appWouldAccept, buildLesson } from './lib/lesson.mjs';
import { buildTimedWords, fetchCaptions, formatWordsForReading, speechStats } from './lib/words.mjs';
import { channelShorts, findChannel, searchShorts, videoInfo } from './lib/youtube-data.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const workDirectory = path.join(root, 'trabalho');
const registryPath = path.join(root, 'registro.jsonl');
const [command, ...args] = process.argv.slice(2);
const flags = new Set(args.filter((arg) => arg.startsWith('--')));
const positional = args.filter((arg) => !arg.startsWith('--'));

const readJSON = async (file, fallback = null) => {
  try { return JSON.parse(await readFile(file, 'utf8')); } catch (error) {
    if (error.code === 'ENOENT') return fallback;
    throw new Error(`${path.relative(root, file)} não é um JSON válido: ${error.message}`);
  }
};
const writeJSON = async (file, value) => {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
};
const itemDirectory = (id) => {
  if (!/^[A-Za-z0-9_-]{11}$/.test(id || '')) throw new Error(`ID de vídeo inválido: ${id}`);
  return path.join(workDirectory, id);
};

async function registry() {
  try {
    return (await readFile(registryPath, 'utf8')).split('\n').filter(Boolean).map((line) => JSON.parse(line));
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
}
const record = (entry) => appendFile(registryPath, `${JSON.stringify({ at: new Date().toISOString(), ...entry })}\n`);

async function decided() {
  const latest = new Map();
  for (const entry of await registry()) latest.set(entry.videoID, entry.action);
  return latest;
}

async function inCatalog(ids) {
  try {
    const db = await firestore();
    const snapshots = await db.getAll(...ids.map((id) => db.collection('approvedShorts').doc(id)));
    return new Set(snapshots.filter((snapshot) => snapshot.exists).map((snapshot) => snapshot.id));
  } catch {
    return new Set();
  }
}

async function showCandidates(ids) {
  const key = await youtubeKey();
  const infos = await videoInfo(key, ids);
  const seen = await decided();
  const catalog = await inCatalog(infos.map((info) => info.videoID));
  const rows = infos.map((info) => ({
    ...info,
    status: catalog.has(info.videoID) ? 'já no catálogo' : seen.get(info.videoID) || (info.short.ok ? 'novo' : `ignorar: ${info.short.reason}`),
  }));
  await writeJSON(path.join(workDirectory, 'candidatos.json'), rows);
  for (const row of rows) {
    console.log(`${row.videoID} | ${row.status} | ${row.short.seconds}s | cat ${row.categoryId} | áudio ${row.audioLanguage || '?'} | ${row.views.toLocaleString('en-US')} views | ${row.channel} | ${row.title}`);
  }
  console.log(`\n${rows.filter((row) => row.status === 'novo').length} novo(s) de ${rows.length}. Lista salva em trabalho/candidatos.json.`);
}

const commands = {
  async buscar() {
    const query = positional.join(' ').trim();
    if (!query) throw new Error('Use: node cli.mjs buscar "street interview"');
    const ids = await searchShorts(await youtubeKey(), query, { order: flags.has('--recentes') ? 'date' : 'viewCount' });
    await showCandidates(ids);
  },

  async canal() {
    const target = positional[0];
    if (!target) throw new Error('Use: node cli.mjs canal @TeamCoco  (ou o ID UC...)');
    const key = await youtubeKey();
    let channelID = target;
    if (!/^UC[A-Za-z0-9_-]{22}$/.test(target)) {
      const found = await findChannel(key, target);
      if (!found.length) throw new Error(`Canal não encontrado: ${target}`);
      channelID = found[0].channelID;
      console.log(`Canal: ${found[0].title} (${channelID}${found[0].country ? `, país ${found[0].country}` : ''})\n`);
    }
    const max = flags.has('--todos') ? 300 : 150;
    await showCandidates((await channelShorts(key, channelID, { max })).slice(0, max));
  },

  async info() {
    if (!positional.length) throw new Error('Use: node cli.mjs info ID1 ID2');
    await showCandidates(positional);
  },

  async palavras() {
    const id = positional[0];
    const directory = itemDirectory(id);
    const captions = await fetchCaptions(id);
    const timed = buildTimedWords(captions);
    if (!timed.words.length) throw new Error('A legenda veio vazia.');
    let info = { title: captions.title, channel: captions.channel, channelID: null };
    try { [info] = await videoInfo(await youtubeKey(), [id]); } catch { /* metadados opcionais */ }
    const stats = speechStats(timed.words);
    await writeJSON(path.join(directory, 'palavras.json'), { videoID: id, info, ...timed, stats, hasManual: Boolean(captions.manual), hasAsr: Boolean(captions.asr) });
    await writeFile(path.join(directory, 'leitura.txt'), `${formatWordsForReading(timed.words)}\n`);
    console.log(`${info.title} | ${info.channel}`);
    console.log(`Legenda: ${captions.manual ? 'manual' : 'sem manual'} + ${captions.asr ? 'automática' : 'sem automática'} → tempo "${timed.timingQuality}"${timed.matchRatio != null ? ` (${Math.round(timed.matchRatio * 100)}% alinhado)` : ''}`);
    console.log(`${stats.words} palavras | ${stats.durationSeconds}s | ${stats.wordsPerMinute} palavras/min | ${stats.syllablesPerSecond} sílabas/s`);
    console.log(`\nLeia trabalho/${id}/leitura.txt e escreva trabalho/${id}/decisao.json (formato no README).`);
  },

  async montar() {
    const id = positional[0];
    const directory = itemDirectory(id);
    const words = await readJSON(path.join(directory, 'palavras.json'));
    const decision = await readJSON(path.join(directory, 'decisao.json'));
    if (!words) throw new Error(`Rode antes: node cli.mjs palavras ${id}`);
    if (!decision) throw new Error(`Escreva antes trabalho/${id}/decisao.json`);
    const { payload, errors, warnings } = buildLesson({ videoID: id, info: words.info, words: words.words, timingQuality: words.timingQuality, decision });
    for (const error of errors) console.log(`ERRO   ${error}`);
    for (const warning of warnings) console.log(`AVISO  ${warning}`);
    if (!payload) { process.exitCode = 1; console.log('\nCorrija decisao.json e rode montar de novo.'); return; }
    if (!appWouldAccept(payload)) throw new Error('O documento montado não passaria na validação do app.');
    await writeJSON(path.join(directory, 'documento.json'), payload);
    console.log(`\n${payload.level} | ${payload.interests.join(', ')} | ${payload.phrases.length} frases`);
    for (const phrase of payload.phrases) {
      console.log(`${phrase.start.toFixed(2).padStart(6)}–${phrase.end.toFixed(2).padEnd(6)} ${(phrase.end - phrase.start).toFixed(1)}s ${String(phrase.sourceSegmentCount).padStart(2)}p | ${phrase.text}`);
    }
    console.log(`\nPronto para revisão. Publicar: node cli.mjs publicar ${id} --confirmado (só depois do OK do usuário).`);
  },

  async rejeitar() {
    const [id, ...reason] = positional;
    itemDirectory(id);
    if (!reason.length) throw new Error('Use: node cli.mjs rejeitar ID "motivo"');
    await record({ videoID: id, action: 'rejeitado', reason: reason.join(' ') });
    console.log(`Rejeitado ${id}: ${reason.join(' ')}`);
  },

  async publicar() {
    if (!flags.has('--confirmado')) throw new Error('Publicar altera o app real. Só rode com --confirmado depois do OK do usuário.');
    if (!positional.length) throw new Error('Use: node cli.mjs publicar ID1 ID2 --confirmado');
    const db = await firestore();
    const { FieldValue } = await import('firebase-admin/firestore');
    for (const id of positional) {
      const payload = await readJSON(path.join(itemDirectory(id), 'documento.json'));
      if (!appWouldAccept(payload)) { console.log(`PULADO ${id}: sem documento.json válido (rode montar)`); continue; }
      const reference = db.collection('approvedShorts').doc(id);
      const document = {
        status: 'approved', level: payload.level, interests: payload.interests, version: 1,
        payload: JSON.stringify(payload), verifiedAt: FieldValue.serverTimestamp(), curatedBy: 'antigravity-gemini',
      };
      const existing = await reference.get();
      if (existing.exists && !flags.has('--atualizar')) { console.log(`PULADO ${id}: já está no catálogo (use --atualizar para substituir)`); continue; }
      if (existing.exists) await reference.set(document);
      else await reference.create(document);
      await record({ videoID: id, action: 'publicado', level: payload.level, interests: payload.interests, title: payload.title, channel: payload.channel, updated: existing.exists });
      console.log(`${existing.exists ? 'ATUALIZADO' : 'PUBLICADO'} ${id} (${payload.level}) ${payload.title}`);
    }
  },

  async baixar() {
    const id = positional[0];
    const snapshot = await (await firestore()).collection('approvedShorts').doc(id).get();
    if (!snapshot.exists) throw new Error(`${id} não está no catálogo.`);
    const payload = JSON.parse(snapshot.data().payload);
    await writeJSON(path.join(itemDirectory(id), 'publicado.json'), payload);
    console.log(`${payload.title} | ${payload.level} | origem ${payload.source} | ${payload.phrases.length} frases`);
    for (const phrase of payload.phrases) console.log(`${phrase.start.toFixed(2).padStart(6)}–${phrase.end.toFixed(2).padEnd(6)} | ${phrase.text}`);
  },

  async despublicar() {
    const [id, ...reason] = positional;
    if (!flags.has('--confirmado')) throw new Error('Despublicar altera o app real. Só rode com --confirmado depois do OK do usuário.');
    itemDirectory(id);
    await (await firestore()).collection('approvedShorts').doc(id).delete();
    await record({ videoID: id, action: 'despublicado', reason: reason.join(' ') || null });
    console.log(`DESPUBLICADO ${id}`);
  },

  async situacao() {
    const latest = new Map();
    for (const entry of await registry()) latest.set(entry.videoID, entry);
    const published = [...latest.values()].filter((entry) => entry.action === 'publicado');
    const levels = { beginner: 0, intermediate: 0, advanced: 0 };
    for (const entry of published) levels[entry.level] = (levels[entry.level] || 0) + 1;
    const total = published.length || 1;
    console.log(`Publicados pelo Caminho B: ${published.length} → iniciante ${levels.beginner} (${Math.round(levels.beginner / total * 100)}%), intermediário ${levels.intermediate} (${Math.round(levels.intermediate / total * 100)}%), avançado ${levels.advanced} (${Math.round(levels.advanced / total * 100)}%)`);
    console.log(`Rejeitados: ${[...latest.values()].filter((entry) => entry.action === 'rejeitado').length} | Despublicados: ${[...latest.values()].filter((entry) => entry.action === 'despublicado').length}`);
    const folders = await readdir(workDirectory).catch(() => []);
    const drafts = [];
    for (const folder of folders.filter((name) => /^[A-Za-z0-9_-]{11}$/.test(name))) {
      if (latest.has(folder)) continue;
      const hasDocument = Boolean(await readJSON(path.join(workDirectory, folder, 'documento.json')));
      drafts.push(`${folder} (${hasDocument ? 'montado, aguardando publicação' : 'em análise'})`);
    }
    console.log(`Em andamento: ${drafts.length ? drafts.join(', ') : 'nenhum'}`);
  },
};

try {
  if (!commands[command]) {
    console.log(`Comandos: ${Object.keys(commands).join(', ')}. Veja README.md.`);
    process.exitCode = command ? 1 : 0;
  } else {
    await commands[command]();
  }
} catch (error) {
  console.error(`Erro: ${error.message}`);
  process.exitCode = 1;
}
