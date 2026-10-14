// Legendas do YouTube → palavras com tempo. O Gemini escolhe as frases por índice de palavra;
// os tempos saem sempre daqui, nunca do modelo.

const youtubeHost = /^(?:[a-z0-9-]+\.)*youtube\.com$/i;
let activeRequests = 0;
const waiting = [];

export class RateLimitedError extends Error {
  constructor() {
    super('O YouTube limitou as legendas (HTTP 429). Espere pelo menos 30 minutos antes de tentar de novo.');
    this.code = 'RATE_LIMITED';
  }
}

// No máximo 2 pedidos simultâneos ao YouTube: rajadas maiores levam a um bloqueio de quase 1 hora.
async function limited(task) {
  if (activeRequests >= 2) await new Promise((resolve) => waiting.push(resolve));
  activeRequests += 1;
  try {
    return await task();
  } finally {
    activeRequests -= 1;
    waiting.shift()?.();
  }
}

function clean(text) {
  return String(text)
    .replace(/<[^>]+>/g, ' ')
    .replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/\s+/g, ' ').trim();
}

// Tradução de ShadowingNative/Services/TranscriptJSONParser.swift.
export function parseJSON3(json) {
  const segments = [];
  for (const event of json?.events || []) {
    const startMs = Number(event.tStartMs);
    if (!Number.isFinite(startMs) || startMs < 0 || !Array.isArray(event.segs)) continue;
    const start = startMs / 1000;
    const duration = Math.max(0.04, (Number(event.dDurationMs) || 2000) / 1000);
    const hasOffsets = event.segs.some((piece) => Number(piece.tOffsetMs) > 0);
    const units = [];
    if (hasOffsets) {
      for (const piece of event.segs) {
        const text = clean(piece.utf8 || '');
        if (!text) continue;
        const unitStart = start + Math.max(0, Number(piece.tOffsetMs) || 0) / 1000;
        if (units.length && unitStart <= units.at(-1).start) units.at(-1).text += ` ${text}`;
        else units.push({ text, start: unitStart });
      }
    } else {
      const text = clean(event.segs.map((piece) => piece.utf8 || '').join(''));
      if (text) units.push({ text, start });
    }
    units.forEach((unit, index) => {
      const end = index + 1 < units.length ? units[index + 1].start : Math.max(unit.start + 0.04, start + duration);
      segments.push({ text: unit.text, start: unit.start, end, hasWordTiming: hasOffsets });
    });
  }
  segments.sort((left, right) => left.start - right.start);
  const unique = [];
  for (const segment of segments) {
    const previous = unique.at(-1);
    if (previous && previous.text === segment.text && segment.start < previous.end) continue;
    unique.push(segment);
  }
  return unique.flatMap((segment, index) => {
    const end = Math.min(segment.end, unique[index + 1]?.start ?? segment.end);
    return end > segment.start ? [{ ...segment, end }] : [];
  });
}

export function selectEnglishTracks(tracks = []) {
  const english = tracks.filter((track) => String(track.languageCode || '').toLowerCase().startsWith('en'));
  const manual = english.filter((track) => track.kind !== 'asr');
  const rank = (track) => ['en-us', 'en'].indexOf(String(track.languageCode).toLowerCase());
  manual.sort((left, right) => (rank(left) < 0 ? 9 : rank(left)) - (rank(right) < 0 ? 9 : rank(right)));
  return { manual: manual[0] || null, asr: english.find((track) => track.kind === 'asr') || null };
}

async function fetchJSON(url, options, fetchImpl) {
  const response = await limited(() => fetchImpl(url, { ...options, signal: AbortSignal.timeout(20000) }));
  if (response.status === 429) throw new RateLimitedError();
  if (!response.ok) throw new Error(`YouTube respondeu HTTP ${response.status}`);
  return response.json();
}

export async function fetchCaptions(videoID, { fetchImpl = fetch } = {}) {
  if (!/^[A-Za-z0-9_-]{11}$/.test(videoID)) throw new Error(`ID de vídeo inválido: ${videoID}`);
  const clientVersion = '20.10.38';
  const player = await fetchJSON('https://www.youtube.com/youtubei/v1/player?prettyPrint=false', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': `com.google.android.youtube/${clientVersion} (Linux; U; Android 14)`,
      'X-YouTube-Client-Name': '3',
      'X-YouTube-Client-Version': clientVersion,
    },
    body: JSON.stringify({
      context: { client: { clientName: 'ANDROID', clientVersion, hl: 'en', gl: 'US' } },
      videoId: videoID,
    }),
  }, fetchImpl);
  const { manual, asr } = selectEnglishTracks(player?.captions?.playerCaptionsTracklistRenderer?.captionTracks);
  if (!manual && !asr) throw new Error('Sem legenda em inglês');
  const load = async (track) => {
    if (!track?.baseUrl) return null;
    const url = new URL(track.baseUrl);
    if (url.protocol !== 'https:' || !youtubeHost.test(url.hostname)) throw new Error('Endereço de legenda inesperado');
    url.searchParams.set('fmt', 'json3');
    const segments = parseJSON3(await fetchJSON(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, fetchImpl));
    return segments.length ? segments : null;
  };
  return {
    title: player?.videoDetails?.title || '',
    channel: player?.videoDetails?.author || '',
    manual: await load(manual),
    asr: await load(asr),
  };
}

const unspoken = /\[[^\]]*\]|\([^)]*\)|♪/g;
const normalize = (token) => token.toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');

// ">>" e "-" no início marcam troca de quem fala: não são palavras, mas viram `speakerChange` na seguinte.
function tokens(segments, timing) {
  let pendingChange = false;
  return segments.flatMap((segment) => {
    const raw = segment.text.replace(unspoken, ' ').split(/\s+/).filter(Boolean);
    const parts = [];
    for (const part of raw) {
      if (/^(>>+|-|–|—)$/.test(part)) { pendingChange = true; continue; }
      parts.push({ text: part, speakerChange: pendingChange });
      pendingChange = false;
    }
    const total = parts.reduce((sum, part) => sum + part.text.length, 0) || 1;
    let elapsed = 0;
    return parts.map(({ text, speakerChange }) => {
      const start = segment.start + (segment.end - segment.start) * elapsed / total;
      elapsed += text.length;
      const end = segment.start + (segment.end - segment.start) * elapsed / total;
      const exact = timing === 'word' && (segment.hasWordTiming || parts.length === 1);
      return { text, start, end, timing: exact ? 'word' : 'estimated', ...(speakerChange ? { speakerChange } : {}) };
    });
  });
}

function tidy(words) {
  const result = [];
  for (const word of words) {
    const start = Math.max(word.start, result.at(-1)?.start ?? 0);
    result.push({ ...word, start });
  }
  return result.map((word, index) => {
    const nextStart = result[index + 1]?.start ?? Infinity;
    const end = Math.max(word.start + 0.04, Math.min(word.end, nextStart));
    return { ...word, start: Math.round(word.start * 1000) / 1000, end: Math.round(end * 1000) / 1000 };
  });
}

// Texto da legenda manual (pontuado) com o tempo da automática (por palavra), via LCS.
export function buildTimedWords({ manual, asr }) {
  const manualWords = manual ? tokens(manual, 'block') : [];
  const asrWords = asr ? tokens(asr, 'word') : [];
  if (manualWords.length && asrWords.length) {
    const left = manualWords.map((word) => normalize(word.text));
    const right = asrWords.map((word) => normalize(word.text));
    const table = Array.from({ length: left.length + 1 }, () => new Uint16Array(right.length + 1));
    for (let i = 1; i <= left.length; i++) {
      for (let j = 1; j <= right.length; j++) {
        table[i][j] = left[i - 1] && left[i - 1] === right[j - 1]
          ? table[i - 1][j - 1] + 1 : Math.max(table[i - 1][j], table[i][j - 1]);
      }
    }
    const pairs = new Map();
    for (let i = left.length, j = right.length; i > 0 && j > 0;) {
      if (left[i - 1] && left[i - 1] === right[j - 1]) { pairs.set(i - 1, j - 1); i--; j--; }
      else if (table[i - 1][j] >= table[i][j - 1]) i--;
      else j--;
    }
    const comparable = left.filter(Boolean).length || 1;
    const matchRatio = pairs.size / comparable;
    if (matchRatio >= 0.6) {
      const aligned = manualWords.map((word, index) => pairs.has(index)
        ? { ...word, start: asrWords[pairs.get(index)].start, end: asrWords[pairs.get(index)].end, timing: 'word' }
        : { ...word });
      // Palavras sem par entre duas âncoras dividem o intervalo entre elas.
      for (let index = 0; index < aligned.length;) {
        if (pairs.has(index)) { index++; continue; }
        let stop = index;
        while (stop < aligned.length && !pairs.has(stop)) stop++;
        const before = aligned[index - 1];
        const after = aligned[stop];
        if (before && after) {
          const span = aligned.slice(index, stop);
          const total = span.reduce((sum, word) => sum + word.text.length, 0) || 1;
          let elapsed = 0;
          for (const word of span) {
            word.start = before.end + (after.start - before.end) * elapsed / total;
            elapsed += word.text.length;
            word.end = before.end + (after.start - before.end) * elapsed / total;
            word.timing = 'interpolated';
          }
        }
        index = stop;
      }
      return { words: tidy(aligned), timingQuality: 'aligned', matchRatio };
    }
    return { words: tidy(asrWords), timingQuality: 'word', matchRatio };
  }
  if (asrWords.length) return { words: tidy(asrWords), timingQuality: 'word', matchRatio: null };
  const exact = manual?.every((segment) => segment.hasWordTiming);
  return { words: tidy(tokens(manual || [], exact ? 'word' : 'block')), timingQuality: exact ? 'word' : 'estimated', matchRatio: null };
}

export function syllables(word) {
  const letters = word.toLowerCase().replace(/[^a-z]/g, '');
  if (!letters) return 0;
  const groups = letters.match(/[aeiouy]+/g)?.length ?? 1;
  const silentE = letters.length > 2 && letters.endsWith('e') && !letters.endsWith('le') && groups > 1 ? 1 : 0;
  return Math.max(1, groups - silentE);
}

// Tempo de fala sem as pausas longas (≥ 0,6 s), para a velocidade não cair só porque alguém parou.
export function speechStats(words) {
  if (!words.length) return { durationSeconds: 0, speechSeconds: 0, wordsPerMinute: 0, syllablesPerSecond: 0, words: 0 };
  let speech = 0;
  for (let index = 0; index < words.length; index++) {
    const next = words[index + 1];
    const span = next ? next.start - words[index].start : words[index].end - words[index].start;
    speech += Math.min(span, 0.6);
  }
  const count = words.length;
  const totalSyllables = words.reduce((sum, word) => sum + syllables(word.text), 0);
  return {
    durationSeconds: Math.round((words.at(-1).end - words[0].start) * 10) / 10,
    speechSeconds: Math.round(speech * 10) / 10,
    words: count,
    wordsPerMinute: Math.round(count * 60 / Math.max(speech, 1)),
    syllablesPerSecond: Math.round(totalSyllables / Math.max(speech, 1) * 100) / 100,
  };
}

// Texto para o Gemini ler: índice antes de cada palavra, "‖" nas pausas ≥ 0,3 s, "»" na troca de falante
// e o tempo no início da linha.
export function formatWordsForReading(words) {
  const lines = [];
  let line = [];
  words.forEach((word, index) => {
    if (!line.length) {
      const minutes = Math.floor(word.start / 60);
      const seconds = (word.start % 60).toFixed(1).padStart(4, '0');
      line.push(`[${String(minutes).padStart(2, '0')}:${seconds}]`);
    }
    if (word.speakerChange && index > 0) line.push('»');
    line.push(`${index}:${word.text}`);
    const next = words[index + 1];
    if (next && next.start - word.end >= 0.3) line.push('‖');
    if (line.length >= 14 || !next) {
      lines.push(line.join(' '));
      line = [];
    }
  });
  return lines.join('\n');
}
