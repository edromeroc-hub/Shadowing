import { readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { automaticReviewReasons } from './workflow.mjs';

const videoIDPattern = /^[A-Za-z0-9_-]{11}$/;

async function readJSON(file, fallback = null) {
  try {
    return JSON.parse(await readFile(file, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return fallback;
    throw error;
  }
}

async function filenames(directory) {
  try {
    return await readdir(directory);
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
}

export function validVideoID(videoID) {
  return videoIDPattern.test(videoID);
}

export async function candidateStatus(stateDirectory, videoID) {
  const filename = `${videoID}.json`;
  const exists = async (file) => {
    try {
      await stat(file);
      return true;
    } catch (error) {
      if (error.code === 'ENOENT') return false;
      throw error;
    }
  };
  const [published, rejected] = await Promise.all([
    exists(path.join(stateDirectory, 'published', filename)),
    exists(path.join(stateDirectory, 'rejected', filename)),
  ]);
  return published ? 'published' : rejected ? 'rejected' : 'pending';
}

export async function getCandidate(stateDirectory, videoID) {
  if (!validVideoID(videoID)) return null;
  const filename = `${videoID}.json`;
  const prepared = await readJSON(path.join(stateDirectory, 'review', filename));
  if (!prepared) {
    const progress = await readJSON(path.join(stateDirectory, 'progress.json'), {});
    const queued = progress.pending?.find((item) => item.videoID === videoID);
    return queued ? {
      videoID, title: `Short ${videoID}`, channel: 'Aguardando legenda',
      level: null, interests: queued.interest ? [queued.interest] : [],
      phrases: [], segments: [], status: 'queued', scannedAt: null,
      sourceKind: 'queue', automationReasons: [],
    } : null;
  }
  if (prepared.videoID !== videoID) return null;
  const [metadata, trustedChannels, status] = await Promise.all([
    readJSON(path.join(stateDirectory, 'metadata', filename)),
    readJSON(path.join(stateDirectory, 'trusted-channels.json'), []),
    candidateStatus(stateDirectory, videoID),
  ]);
  const rejection = status === 'rejected' ? await readJSON(path.join(stateDirectory, 'rejected', filename)) : null;
  return {
    ...prepared,
    status,
    rejectionReason: rejection?.reason || null,
    scannedAt: metadata?.scannedAt || null,
    sourceKind: metadata?.source || 'legacy',
    automationReasons: automaticReviewReasons(prepared, metadata, trustedChannels),
  };
}

export async function listCandidates(stateDirectory, options = {}) {
  const statusFilter = ['pending', 'published', 'rejected', 'queued'].includes(options.status) ? options.status : 'pending';
  const levelFilter = ['beginner', 'intermediate', 'advanced'].includes(options.level) ? options.level : '';
  const query = String(options.query || options.q || '').trim().toLocaleLowerCase();
  const page = Math.max(1, Math.min(100000, Number.parseInt(options.page, 10) || 1));
  const pageSize = 40;
  const reviewFiles = (await filenames(path.join(stateDirectory, 'review')))
    .filter((filename) => filename.endsWith('.json') && validVideoID(filename.slice(0, -5)));
  const published = new Set(await filenames(path.join(stateDirectory, 'published')));
  const rejected = new Set(await filenames(path.join(stateDirectory, 'rejected')));
  const summaries = [];

  for (let offset = 0; offset < reviewFiles.length; offset += 40) {
    const batch = await Promise.all(reviewFiles.slice(offset, offset + 40).map(async (filename) => {
      const videoID = filename.slice(0, -5);
      const metadata = await readJSON(path.join(stateDirectory, 'metadata', filename));
      const prepared = metadata?.title && metadata?.level ? metadata :
        await readJSON(path.join(stateDirectory, 'review', filename));
      if (!prepared || prepared.videoID !== videoID) return null;
      return {
        videoID, title: prepared.title, channel: prepared.channel,
        level: prepared.level, interests: prepared.interests || [],
        phraseCount: prepared.phraseCount ?? prepared.phrases?.length ?? 0,
        scannedAt: metadata?.scannedAt || null,
        status: published.has(filename) ? 'published' : rejected.has(filename) ? 'rejected' : 'pending',
      };
    }));
    summaries.push(...batch.filter(Boolean));
  }

  const progressPath = path.join(stateDirectory, 'progress.json');
  const progress = await readJSON(progressPath, {});
  const queued = (progress.pending || []).filter((item) => validVideoID(item.videoID))
    .map((item) => ({
      videoID: item.videoID, title: `Short ${item.videoID}`, channel: 'Aguardando legenda',
      level: null, interests: item.interest ? [item.interest] : [],
      phraseCount: 0, scannedAt: null, status: 'queued',
    }));
  const counts = { pending: 0, published: 0, rejected: 0, queued: queued.length };
  for (const candidate of summaries) counts[candidate.status] += 1;
  const filtered = (statusFilter === 'queued' ? queued : summaries).filter((candidate) => candidate.status === statusFilter &&
    (!levelFilter || candidate.level === levelFilter) &&
    (!query || `${candidate.title} ${candidate.channel} ${candidate.videoID} ${candidate.interests.join(' ')}`
      .toLocaleLowerCase().includes(query)));
  if (statusFilter !== 'queued') {
    filtered.sort((left, right) => (right.scannedAt || '').localeCompare(left.scannedAt || '') ||
      left.videoID.localeCompare(right.videoID));
  }

  const progressInfo = await stat(progressPath).catch(() => null);
  const processed = Object.values(progress.processed || {});
  return {
    items: filtered.slice((page - 1) * pageSize, page * pageSize),
    total: filtered.length,
    page,
    pageSize,
    counts,
    progress: {
      inspected: processed.length,
      automaticallyRejected: processed.filter((value) => value === 'rejected').length,
      queued: progress.pending?.length || 0,
      searchesToday: progress.searchCount || 0,
      nextChannel: (progress.seedIndex || 0) + 1,
      updatedAt: progressInfo?.mtime.toISOString() || null,
    },
  };
}
