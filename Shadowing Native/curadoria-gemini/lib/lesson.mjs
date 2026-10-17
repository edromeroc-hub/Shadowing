// Monta e confere o documento do catálogo no formato v1 que o app já lê
// (ShadowingNative/Services/SharedShortCatalog.swift → CatalogPayload.preparedLesson).

export const LEVELS = {
  beginner: { maxWords: 9, maxSeconds: 3.5 },
  intermediate: { maxWords: 13, maxSeconds: 4.5 },
  advanced: { maxWords: 18, maxSeconds: 6.0 },
};

export const INTERESTS = [
  'technology', 'business', 'career', 'finance', 'travel', 'livingAbroad', 'shopping',
  'movies', 'music', 'news', 'history', 'lifestyle', 'health', 'science',
  'engineering', 'cars', 'aviation', 'agriculture', 'sports', 'humor', 'gaming',
  'fitness', 'cooking', 'streetInterviews',
];

const weakEndings = new Set(['the', 'a', 'an', 'to', 'of', 'my', 'your', 'his', 'her', 'our', 'their', 'is', 'are',
  'was', 'were', 'in', 'on', 'at', 'for', 'with', 'from', 'and', 'but', 'or', 'so', 'which', 'because', 'that',
  'i', 'we', 'they', 'he', 'she', "i'm", "it's", "don't", "didn't", 'gonna', 'wanna', 'just', 'really', 'very']);

const normalize = (token) => token.toLowerCase().replace(/[’]/g, "'").replace(/[^\p{L}\p{N}']/gu, '');
const tokens = (text) => String(text).split(/\s+/).map(normalize).filter(Boolean);

function overlap(left, right) {
  const table = Array.from({ length: left.length + 1 }, () => new Uint16Array(right.length + 1));
  for (let i = 1; i <= left.length; i++) {
    for (let j = 1; j <= right.length; j++) {
      table[i][j] = left[i - 1] === right[j - 1] ? table[i - 1][j - 1] + 1 : Math.max(table[i - 1][j], table[i][j - 1]);
    }
  }
  return table[left.length][right.length];
}

const round = (value) => Math.round(value * 1000) / 1000;

export function buildLesson({ videoID, info, words, timingQuality, decision, now = new Date() }) {
  const errors = [];
  const warnings = [];
  const level = decision?.level;
  const limits = LEVELS[level];
  if (!/^[A-Za-z0-9_-]{11}$/.test(videoID || '')) errors.push('videoID inválido');
  if (!limits) errors.push(`level deve ser beginner, intermediate ou advanced (veio "${level}")`);
  const interests = [...new Set(decision?.interests || [])];
  if (!interests.length || interests.some((item) => !INTERESTS.includes(item))) {
    errors.push(`interests deve ter 1 ou mais de: ${INTERESTS.join(', ')}`);
  }
  if (!Array.isArray(words) || !words.length) errors.push('sem palavras (rode o comando words antes)');
  const phrases = Array.isArray(decision?.phrases) ? decision.phrases : [];
  if (phrases.length < 3) errors.push('são necessárias pelo menos 3 frases');

  let previousEnd = -1;
  let covered = 0;
  const built = [];
  phrases.forEach((phrase, index) => {
    const label = `frase ${index + 1} (${phrase?.from}-${phrase?.to})`;
    const { from, to } = phrase || {};
    if (!Number.isInteger(from) || !Number.isInteger(to) || from < 0 || to < from || to >= (words?.length || 0)) {
      errors.push(`${label}: from/to devem ser índices válidos de palavras, com from ≤ to`);
      return;
    }
    if (from <= previousEnd) errors.push(`${label}: começa antes do fim da frase anterior (${previousEnd})`);
    previousEnd = to;
    const span = words.slice(from, to + 1);
    covered += span.length;
    const start = words[from].start;
    const end = words[to].end;
    if (limits && span.length > limits.maxWords) errors.push(`${label}: ${span.length} palavras (máximo ${limits.maxWords} em ${level})`);
    if (limits && span.length > 1 && end - start > limits.maxSeconds + 0.001) {
      errors.push(`${label}: ${(end - start).toFixed(1)} s (máximo ${limits.maxSeconds} s em ${level})`);
    }
    if (span.length < 2) warnings.push(`${label}: só 1 palavra`);
    const last = words[to].text;
    if (!/[.?!,;:]["')\]]*$/.test(last) && weakEndings.has(normalize(last))) warnings.push(`${label}: termina em "${last}"`);
    if (span.some((word) => word.timing !== 'word')) warnings.push(`${label}: tempo interpolado/estimado, ouça antes de publicar`);
    const spanText = span.map((word) => word.text).join(' ');
    let text = spanText;
    if (typeof phrase.text === 'string' && phrase.text.trim()) {
      const expected = tokens(spanText);
      const given = tokens(phrase.text);
      const ratio = overlap(expected, given) / Math.max(expected.length, given.length, 1);
      if (ratio < 0.8) errors.push(`${label}: o texto não corresponde às palavras ${from}-${to} (${Math.round(ratio * 100)}% iguais)`);
      else text = phrase.text.trim().replace(/\s+/g, ' ');
    }
    built.push({
      text, start: round(start), end: round(end), sourceSegmentCount: span.length,
      needsExpandedPractice: false, endingHasWordTiming: words[to].timing === 'word',
    });
  });
  if (words?.length && covered / words.length < 0.7) warnings.push(`só ${Math.round(covered / words.length * 100)}% das palavras viraram frases`);
  if (timingQuality === 'estimated') warnings.push('legenda sem tempo por palavra: todos os cortes são estimados');

  const payload = errors.length ? null : {
    version: 1, videoID, title: info.title, channel: info.channel, channelID: info.channelID || null,
    languageCode: 'en', source: 'antigravity-gemini', level, interests,
    segments: words.map((word) => ({ text: word.text, start: round(word.start), end: round(word.end), hasWordTiming: word.timing === 'word' })),
    phrases: built,
    affinity: {},
    curation: {
      by: 'antigravity-gemini', curatedAt: now.toISOString(), timingQuality,
      reason: String(decision.reason || '').slice(0, 300), notes: String(decision.notes || '').slice(0, 500),
    },
  };
  if (payload && Buffer.byteLength(JSON.stringify(payload), 'utf8') > 750000) {
    return { payload: null, errors: ['documento grande demais para o Firestore'], warnings };
  }
  return { payload, errors, warnings };
}

// Mesmas checagens que o app faz antes de aceitar um documento do catálogo.
export function appWouldAccept(payload) {
  if (!payload || payload.version !== 1 || !/^[A-Za-z0-9_-]{11}$/.test(payload.videoID)) return false;
  if (!LEVELS[payload.level] || !payload.languageCode.startsWith('en')) return false;
  if (!payload.segments.length || !payload.phrases.length) return false;
  let previous = -1;
  for (const segment of payload.segments) {
    if (!(segment.start >= previous && segment.end > segment.start && segment.text.trim())) return false;
    previous = segment.start;
  }
  return payload.phrases.every((phrase) => phrase.start >= 0 && phrase.end > phrase.start && phrase.text.trim());
}
