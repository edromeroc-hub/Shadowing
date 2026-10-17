// Pipeline de curadoria e alinhamento para o banco dedicado de Músicas (`approvedMusic`).
// Suporta tanto vídeos completos (`format: "video"`) quanto Shorts musicais (`format: "short"`),
// combinando:
//   1. Legenda manual oficial do YouTube (versos sincronizados pelo artista/gravadora)
//   2. Legenda automática do YouTube (ASR com tempo palavra por palavra)
//   3. Letra oficial sincronizada via LRCLIB (com seleção pela duração exata do clipe!)

import { buildTimedWords, fetchCaptions, speechStats } from './words.mjs';

// Mesma lista de `MusicGenre` no app: estilo sem músicas aparece lá como "em breve".
export const MUSIC_GENRES = [
  'pop',
  'rock',
  'metal',
  'country',
  'rnb',
  'hiphop',
  'indie',
  'acoustic',
  'classics',
  'gospel',
  'jazz',
  'electronic',
  'reggae',
];

const cleanChannel = (channel = '') => String(channel)
  .replace(/\s*-\s*Topic$/i, '')
  .replace(/VEVO$/i, '')
  .replace(/^Official\s+|\s+Official$/i, '')
  .trim();
const sameName = (a = '', b = '') => normWord(a.replace(/\s+/g, '')) === normWord(b.replace(/\s+/g, ''));

// O título do YouTube costuma vir como "Artista - Música (Official Video)"; o app mostra só "Música" e "Artista".
export function cleanMusicEntry({ artist = '', trackTitle = '', channel = '' } = {}) {
  const channelName = cleanChannel(channel);
  let track = String(trackTitle)
    .replace(/\[[^\]]*\]/g, '')
    .replace(/\((?:official|lyric|lyrics|audio|music\s+video|video|visualizer|hd|4k|remaster)[^)]*\)/gi, '')
    .replace(/\s+/g, ' ')
    .trim();
  let name = String(artist).replace(/^Official\s+|\s+Official$/i, '').trim();
  let artistFromTitle = null;
  const dash = track.split(/\s+[-–—]\s+/);
  if (dash.length >= 2) {
    const left = dash[0].trim();
    const right = dash.slice(1).join(' - ').trim();
    const leftIsArtist = [name, channelName].some((candidate) => candidate && (sameName(left, candidate) || left.toLowerCase().includes(candidate.toLowerCase())));
    const rightIsArtist = [name, channelName].some((candidate) => candidate && sameName(right, candidate));
    // Só corta o título quando um dos lados é o artista: "Hello - Live at…" continua inteiro.
    if (leftIsArtist) {
      track = right;
      artistFromTitle = left;
    } else if (rightIsArtist) {
      track = left;
      artistFromTitle = right;
    }
  }
  const nameIsBroken = !name || /unknown artist/i.test(name) || /\s[-–—]\s/.test(name) || sameName(name, trackTitle);
  if (nameIsBroken) name = artistFromTitle && !/\s[-–—]\s/.test(artistFromTitle) ? artistFromTitle : channelName || name;
  return { artist: name, trackTitle: track.replace(/^["'“”]|["'“”]$/g, '').trim() || trackTitle };
}

const nameKey = (name = '') => String(name).toLowerCase().normalize('NFKD').replace(/[^a-z0-9]/g, '');
const splitCamelCase = (name) => (/\s/.test(name) ? name : name.replace(/([a-z])([A-Z])/g, '$1 $2'));

// Escolhe uma grafia por artista ("ImagineDragons", "SAM SMITH" e "Sam Smith" viram um só nome).
// A grafia creditada na letra vale mais que a do canal ("OneRepublic", não "One Republic").
function canonicalNames(credited, channels) {
  const byKey = new Map();
  const add = (raw, weight) => {
    const name = String(raw || '').trim();
    const key = nameKey(name);
    if (!key) return;
    if (!byKey.has(key)) byKey.set(key, new Map());
    byKey.get(key).set(name, (byKey.get(key).get(name) || 0) + weight);
  };
  credited.forEach((name) => add(name, 10));
  channels.forEach((name) => add(splitCamelCase(name), 1));
  const chosen = new Map();
  for (const [key, counts] of byKey) {
    const score = (name) => (/[a-z]/.test(name) && /[A-Z]/.test(name) ? 1000 : 0) + counts.get(name);
    chosen.set(key, [...counts.keys()].sort((a, b) => score(b) - score(a))[0]);
  }
  return chosen;
}

// Resumo leve de `approvedMusic` (`approvedMusic/_index`): o app lê 1 documento para montar busca, estilos e bandas.
// A banda é o canal quando o canal é de um artista (parcerias ficam no canal dono); canais como "NPR Music" usam o creditado.
export function buildMusicIndex(payloads) {
  const valid = payloads.filter((payload) => /^[A-Za-z0-9_-]{11}$/.test(payload?.videoID || ''));
  const cleaned = valid.map((payload) => ({ payload, ...cleanMusicEntry(payload), channelName: cleanChannel(payload.channel) }));
  const names = canonicalNames(cleaned.map((item) => item.artist), cleaned.map((item) => item.channelName));
  const creditedKeys = new Set(cleaned.map((item) => nameKey(item.artist)));
  const seen = new Set();
  const entries = [];
  for (const { payload, artist: credited, trackTitle, channelName } of cleaned) {
    const owner = creditedKeys.has(nameKey(channelName)) ? channelName : credited;
    const artist = names.get(nameKey(owner)) || owner;
    const key = `${nameKey(artist)}|${nameKey(trackTitle)}|${payload.format}`;
    if (seen.has(key)) continue;
    seen.add(key);
    entries.push({
      v: payload.videoID,
      f: payload.format === 'short' ? 'short' : 'video',
      a: artist,
      t: trackTitle,
      g: (payload.genres || []).filter((genre) => MUSIC_GENRES.includes(genre)),
      l: payload.level,
      d: Math.round(payload.durationSeconds || 0),
    });
  }
  return entries;
}

const round = (v) => Math.round(v * 1000) / 1000;
const normWord = (w) => String(w || '').toLowerCase().replace(/[’‘]/g, "'").replace(/[^\p{L}\p{N}']/gu, '');
const unspokenNoise = /\[[^\]]*\]|\([^)]*\)|♪+|♫+|\b(music|applause|cheering|instrumental|intro|outro)\b/gi;

export function parseArtistAndTrack(rawTitle = '', fallbackChannel = '') {
  const cleanedChannel = String(fallbackChannel || '')
    .replace(/\s*-\s*Topic$/i, '')
    .replace(/VEVO$/i, '')
    .replace(/\s*Official$/i, '')
    .trim();

  let title = String(rawTitle || '')
    .replace(/\[[^\]]*\]/g, '')
    .replace(/\((?:official|lyric|lyrics|audio|music\s+video|video|live|hd|4k|remaster|remastered|visualizer|performance|short|shorts)[^)]*\)/gi, '')
    .replace(/#\S+/g, '')
    .replace(/\s*\|\s*.*$/, '')
    .trim();

  const dashParts = title.split(/\s+[-–—]\s+/);
  if (dashParts.length >= 2) {
    const left = dashParts[0].trim();
    const right = dashParts.slice(1).join(' - ').replace(/^["'“”]|["'“”]$/g, '').trim();
    // Ignora sufixos de canal como "- Ed HQ"
    if (/^(?:ed\s*hq|official.*|live.*|shorts?)$/i.test(right)) {
      return { artist: cleanedChannel || left, trackTitle: left };
    }
    if (left && right) return { artist: left, trackTitle: right };
  }

  return {
    artist: cleanedChannel || 'Unknown Artist',
    trackTitle: title.replace(/^["'“”]|["'“”]$/g, '').trim() || rawTitle,
  };
}

export function parseSyncedLrcLines(syncedLyrics = '', totalDuration = 0) {
  const regex = /^\[(\d{2}):(\d{2}(?:\.\d{1,3})?)\]\s*(.*)$/;
  const raw = [];
  for (const line of String(syncedLyrics || '').split('\n')) {
    const m = regex.exec(line.trim());
    if (!m) continue;
    const sec = Number(m[1]) * 60 + Number(m[2]);
    const text = m[3].replace(/\[[^\]]*\]|\([^)]*\)|♪+|♫+/g, ' ').replace(/\s+/g, ' ').trim();
    raw.push({ start: sec, text });
  }
  const phrases = [];
  const words = [];
  for (let i = 0; i < raw.length; i++) {
    const cur = raw[i];
    if (!cur.text || /^\[.*\]$/.test(cur.text)) continue;
    const tokens = cur.text.split(/\s+/).filter(Boolean);
    if (tokens.length < 2 || tokens.length > 18) continue;

    const nextStart = raw[i + 1]?.start ?? (totalDuration > cur.start ? totalDuration : cur.start + 3.5);
    const maxLineDuration = Math.min(6.5, Math.max(1.2, tokens.length * 0.65));
    const end = round(Math.max(cur.start + 0.8, Math.min(nextStart - 0.08, cur.start + maxLineDuration)));
    const start = round(cur.start);
    if (end <= start) continue;

    const totalChars = tokens.reduce((s, t) => s + t.length, 0) || 1;
    let elapsed = 0;
    const fromIdx = words.length;
    tokens.forEach((tok) => {
      const wStart = round(start + (end - start) * (elapsed / totalChars));
      elapsed += tok.length;
      const wEnd = round(start + (end - start) * (elapsed / totalChars));
      words.push({
        text: tok,
        start: wStart,
        end: Math.max(wStart + 0.04, wEnd),
        timing: 'word',
      });
    });
    const toIdx = words.length - 1;
    phrases.push({
      from: fromIdx,
      to: toIdx,
      text: tokens.join(' '),
      start,
      end,
      sourceSegmentCount: tokens.length,
      needsExpandedPractice: false,
      endingHasWordTiming: true,
    });
  }
  return { words, phrases };
}

export async function fetchOfficialLyrics(artist, trackTitle, targetDuration = null) {
  try {
    const query = encodeURIComponent(`${artist} ${trackTitle}`.trim());
    const res = await fetch(`https://lrclib.net/api/search?q=${query}`, {
      headers: { 'User-Agent': 'ImmersiveShadowingCuration/1.0' },
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) return null;
    const list = await res.json();
    if (!Array.isArray(list) || !list.length) return null;

    const withLyrics = list.filter((item) => item.syncedLyrics || item.plainLyrics);
    if (!withLyrics.length) return null;

    if (targetDuration && targetDuration > 60) {
      withLyrics.sort((a, b) => {
        const aHasSync = a.syncedLyrics ? 0 : 1;
        const bHasSync = b.syncedLyrics ? 0 : 1;
        const aDiff = Math.abs((a.duration || 9999) - targetDuration);
        const bDiff = Math.abs((b.duration || 9999) - targetDuration);
        if (Math.abs(aDiff - bDiff) <= 2 && aHasSync !== bHasSync) return aHasSync - bHasSync;
        return aDiff - bDiff;
      });
    }

    const best = withLyrics[0];
    const rawLines = (best.syncedLyrics || best.plainLyrics || '')
      .split('\n')
      .map((line) => line.replace(/^\[\d{2}:\d{2}(?:\.\d{1,3})?\]\s*/, '').trim())
      .filter((line) => line && !/^\[.*\]$/.test(line));

    return {
      artistName: best.artistName || artist,
      trackName: best.trackName || trackTitle,
      duration: best.duration || null,
      lines: rawLines,
      syncedLyrics: best.syncedLyrics || null,
      hasSynced: Boolean(best.syncedLyrics),
    };
  } catch {
    return null;
  }
}

// Alinha linhas de letra (da legenda manual do YouTube ou do LRCLIB) contra as palavras com tempo (`timedWords`).
function buildPhrasesFromLyricLines(lyricLines, timedWords, { minCoverage = 0.5 } = {}) {
  const lineTokens = [];
  lyricLines.forEach((line, lineIdx) => {
    const words = line
      .replace(/\[[^\]]*\]|\([^)]*\)|♪+|♫+/g, ' ')
      .split(/\s+/)
      .filter(Boolean);
    if (words.length < 2) return;
    words.forEach((w, posInLine) => {
      const nw = normWord(w);
      if (nw) lineTokens.push({ text: w, norm: nw, lineIdx, isLastInLine: posInLine === words.length - 1 });
    });
  });

  if (lineTokens.length < 6 || timedWords.length < 6) return null;

  const left = lineTokens.map((t) => t.norm);
  const right = timedWords.map((w) => normWord(w.text));

  if (left.length * right.length > 1_500_000) return null;

  const table = Array.from({ length: left.length + 1 }, () => new Uint16Array(right.length + 1));
  for (let i = 1; i <= left.length; i++) {
    for (let j = 1; j <= right.length; j++) {
      table[i][j] = left[i - 1] && left[i - 1] === right[j - 1]
        ? table[i - 1][j - 1] + 1
        : Math.max(table[i - 1][j], table[i][j - 1]);
    }
  }

  const leftToRight = new Map();
  for (let i = left.length, j = right.length; i > 0 && j > 0;) {
    if (left[i - 1] && left[i - 1] === right[j - 1]) {
      leftToRight.set(i - 1, j - 1);
      i--;
      j--;
    } else if (table[i - 1][j] >= table[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }

  const matchedCount = leftToRight.size;
  const coverageOfTimed = matchedCount / Math.max(right.filter(Boolean).length, 1);
  if (coverageOfTimed < minCoverage) return null;

  const byLine = new Map();
  lineTokens.forEach((tok, idx) => {
    if (!byLine.has(tok.lineIdx)) byLine.set(tok.lineIdx, { tokens: [], matchedIndices: [] });
    const group = byLine.get(tok.lineIdx);
    group.tokens.push(tok.text);
    if (leftToRight.has(idx)) group.matchedIndices.push(leftToRight.get(idx));
  });

  const rawPhrases = [];
  let prevTo = -1;

  for (const [, group] of byLine.entries()) {
    if (group.matchedIndices.length < Math.max(2, Math.ceil(group.tokens.length * 0.5))) continue;
    const from = Math.max(prevTo + 1, Math.min(...group.matchedIndices));
    const to = Math.max(...group.matchedIndices);
    if (to <= from) continue;
    const spanCount = to - from + 1;
    if (spanCount > group.tokens.length + 4 || spanCount > 18) continue;
    const start = timedWords[from].start;
    const end = timedWords[to].end;
    const duration = end - start;
    if (duration < 0.6 || duration > 9.5) continue;

    prevTo = to;
    rawPhrases.push({
      from,
      to,
      text: group.tokens.join(' '),
      start: round(start),
      end: round(end),
      sourceSegmentCount: spanCount,
      needsExpandedPractice: false,
      endingHasWordTiming: timedWords[to].timing === 'word',
    });
  }

  return rawPhrases.length >= 4 ? { phrases: rawPhrases, matchRatio: round(coverageOfTimed) } : null;
}

function buildPhrasesFromManualSegments(manualSegments, timedWords) {
  const cleanLines = (manualSegments || [])
    .map((seg) => seg.text.replace(/\[[^\]]*\]|\([^)]*\)|♪+|♫+/g, ' ').replace(/\s+/g, ' ').trim())
    .filter((line) => {
      const w = line.split(/\s+/).filter(Boolean);
      return w.length >= 2 && w.length <= 16 && !unspokenNoise.test(line);
    });

  return buildPhrasesFromLyricLines(cleanLines, timedWords);
}

export function classifyMusicLevel(stats) {
  if (stats.syllablesPerSecond <= 3.45) return 'beginner';
  if (stats.syllablesPerSecond <= 4.65) return 'intermediate';
  return 'advanced';
}

export async function buildMusicLesson(videoID, { genres = ['pop'], infoOverride = null } = {}) {
  const rawTitle = infoOverride?.title || '';
  const channel = infoOverride?.channel || '';
  const durationSeconds = infoOverride?.short?.seconds || 0;
  const format = durationSeconds > 0 && durationSeconds <= 95 ? 'short' : 'video';

  const { artist: parsedArtist, trackTitle: parsedTrack } = parseArtistAndTrack(rawTitle, channel);
  const lrc = await fetchOfficialLyrics(parsedArtist, parsedTrack, durationSeconds);

  let captions = null;
  try {
    captions = await fetchCaptions(videoID);
  } catch (err) {
    if (err.code === 'RATE_LIMITED' || String(err.message).includes('429')) throw err;
    captions = null;
  }

  let words = [];
  let timingQuality = 'word';
  let phrases = null;
  let lyricsSource = null;
  let lyricsMatchRatio = null;

  if (captions) {
    const timed = buildTimedWords(captions);
    words = timed.words || [];
    timingQuality = timed.timingQuality;
    lyricsMatchRatio = timed.matchRatio || null;

    if (words.length > 0) {
      const lastWord = words[words.length - 1];
      if (lastWord.end - lastWord.start > 1.5) {
        lastWord.end = round(lastWord.start + 0.9);
      }
    }

    // Prioridade 1: Legenda manual oficial do YouTube + tempo palavra por palavra da ASR
    if (captions.manual?.length && captions.asr?.length && timed.timingQuality === 'aligned') {
      const res = buildPhrasesFromManualSegments(captions.manual, words);
      if (res && res.phrases.length >= 4) {
        phrases = res.phrases;
        lyricsSource = 'youtube-manual+asr';
        lyricsMatchRatio = res.matchRatio;
      }
    }

    // Prioridade 2: Letra oficial do LRCLIB + tempo palavra por palavra do YouTube
    if (!phrases && lrc?.lines?.length && words.length >= 16) {
      const res = buildPhrasesFromLyricLines(lrc.lines, words, { minCoverage: format === 'short' ? 0.55 : 0.5 });
      if (res && res.phrases.length >= 4) {
        phrases = res.phrases;
        lyricsSource = 'lrclib+asr';
        lyricsMatchRatio = res.matchRatio;
      }
    }

    // Prioridade 3: Legenda manual oficial do YouTube com versos sincronizados pelo artista
    if (!phrases && captions.manual?.length && words.length >= 16) {
      const res = buildPhrasesFromManualSegments(captions.manual, words);
      if (res && res.phrases.length >= 4) {
        phrases = res.phrases;
        lyricsSource = 'youtube-manual';
        lyricsMatchRatio = res.matchRatio;
      }
    }

    // Prioridade 4 (para Shorts musicais cantados ao vivo/acústicos): ASR com tempo por palavra e cadência musical
    const nonMusicalShortTitle = /\b(interview|behind the scenes|trailer|announcement|podcast|q&a|question|explained|rank these|years since|years ago|costume|unboxing|reacts?|reaction|tour bus|backstage)\b/i;
    if (
      !phrases &&
      format === 'short' &&
      timed.timingQuality === 'word' &&
      words.length >= 25 &&
      !nonMusicalShortTitle.test(rawTitle)
    ) {
      const sStats = speechStats(words);
      const speakerChanges = words.filter((w) => w.speakerChange).length;
      if (sStats.wordsPerMinute <= 170 && speakerChanges <= 2) {
        const cadencePhrases = [];
        let startIdx = 0;
        for (let i = 0; i < words.length; i++) {
          const currentLen = i - startIdx + 1;
          const dur = words[i].end - words[startIdx].start;
          const next = words[i + 1];
          const pauseAfter = next ? next.start - words[i].end : 999;
          const hasPunct = /[.?!,;:]["')\]]*$/.test(words[i].text);
          if (!next || (currentLen >= 4 && pauseAfter >= 0.35) || (currentLen >= 5 && hasPunct && dur >= 1.3) || currentLen >= 9 || dur >= 4.0) {
            if (currentLen >= 3 && dur >= 0.8 && dur <= 7.5) {
              const span = words.slice(startIdx, i + 1);
              cadencePhrases.push({
                from: startIdx,
                to: i,
                text: span.map((w) => w.text).join(' '),
                start: round(words[startIdx].start),
                end: round(words[i].end),
                sourceSegmentCount: span.length,
                needsExpandedPractice: false,
                endingHasWordTiming: words[i].timing === 'word',
              });
            }
            startIdx = i + 1;
          }
        }
        if (cadencePhrases.length >= 5) {
          phrases = cadencePhrases;
          lyricsSource = 'youtube-asr-vocal';
        }
      }
    }
  }

  // Prioridade 4: Se o clipe completo bate em duração (diferença <= 2.5s) com a letra sincronizada (LRC) do LRCLIB
  if (
    !phrases &&
    format === 'video' &&
    lrc?.hasSynced &&
    lrc?.duration &&
    durationSeconds > 60 &&
    Math.abs(durationSeconds - lrc.duration) <= 2.5
  ) {
    const parsedLrc = parseSyncedLrcLines(lrc.syncedLyrics, durationSeconds);
    if (parsedLrc.phrases.length >= 6 && parsedLrc.words.length >= 25) {
      words = parsedLrc.words;
      phrases = parsedLrc.phrases;
      timingQuality = 'aligned';
      lyricsSource = 'lrclib-synced';
      lyricsMatchRatio = 1.0;
    }
  }

  if (!phrases || phrases.length < 4 || words.length < 18) {
    return { ok: false, reason: 'Sem letra musical oficial sincronizada compatível' };
  }

  const stats = speechStats(words);
  const finalTitle = rawTitle || captions?.title || `${lrc?.artistName || parsedArtist} - ${lrc?.trackName || parsedTrack}`;
  const finalChannel = channel || captions?.channel || parsedArtist;
  const finalDuration = durationSeconds || Math.round(words.at(-1).end);
  const level = classifyMusicLevel(stats);
  const validGenres = [...new Set(genres.filter((g) => MUSIC_GENRES.includes(g)))];
  if (!validGenres.length) validGenres.push('pop');

  const payload = {
    version: 1,
    videoID,
    format,
    title: finalTitle,
    artist: lrc?.artistName || parsedArtist,
    trackTitle: lrc?.trackName || parsedTrack,
    channel: finalChannel,
    channelID: infoOverride?.channelID || null,
    durationSeconds: finalDuration,
    languageCode: 'en',
    source: 'antigravity-gemini-music',
    level,
    genres: validGenres,
    interests: ['music'],
    lyricsSource,
    lyricsMatchRatio,
    segments: words.map((w) => ({
      text: w.text,
      start: round(w.start),
      end: round(w.end),
      hasWordTiming: w.timing === 'word',
    })),
    phrases: phrases.map(({ text, start, end, sourceSegmentCount, needsExpandedPractice, endingHasWordTiming }) => ({
      text,
      start,
      end,
      sourceSegmentCount,
      needsExpandedPractice,
      endingHasWordTiming,
    })),
    curation: {
      by: 'antigravity-gemini-music',
      curatedAt: new Date().toISOString(),
      timingQuality,
      lyricsSource,
      syllablesPerSecond: stats.syllablesPerSecond,
      wordsPerMinute: stats.wordsPerMinute,
    },
  };

  return { ok: true, payload };
}
