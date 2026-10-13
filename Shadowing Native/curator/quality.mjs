export const limits = {
  beginner: { seconds: 4.5, words: 10, characters: 85 },
  intermediate: { seconds: 5.5, words: 13, characters: 105 },
  advanced: { seconds: 6.5, words: 18, characters: 130 },
};

const keywords = {
  technology: ['tech', 'technology', 'computer', 'phone', 'software', 'internet'],
  business: ['business', 'work', 'company', 'career', 'job', 'money'],
  travel: ['travel', 'trip', 'airport', 'hotel', 'vacation', 'flight'],
  movies: ['movie', 'film', 'actor', 'cinema', 'series', 'tv'],
  news: ['news', 'election', 'government', 'president', 'politics'],
  lifestyle: ['life', 'day', 'friend', 'family', 'home', 'routine'],
  science: ['science', 'physics', 'biology', 'space', 'research'],
  aviation: ['aviation', 'airplane', 'aircraft', 'pilot', 'runway', 'airline'],
  sports: ['sports', 'football', 'basketball', 'soccer', 'athlete'],
  humor: ['funny', 'comedy', 'joke', 'laugh', 'roast', 'conan'],
  gaming: ['game', 'gaming', 'xbox', 'playstation', 'nintendo'],
  fitness: ['gym', 'fitness', 'workout', 'exercise', 'muscle', 'training'],
  cooking: ['cook', 'food', 'recipe', 'kitchen', 'chef', 'steak'],
  streetInterviews: ['interview', 'subway', 'street', 'stranger', 'opinion'],
};

export function words(text) {
  return String(text).match(/[\p{L}']+/gu) || [];
}

export function normalizeSegments(raw) {
  const sorted = raw.map((segment) => ({
    text: String(segment.text || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim(),
    start: Number(segment.start),
    end: Number(segment.end),
    hasWordTiming: Boolean(segment.hasWordTiming),
  })).sort((left, right) => left.start - right.start);
  return sorted.flatMap((segment, index) => {
    const end = Math.min(segment.end, sorted[index + 1]?.start ?? segment.end);
    return segment.text && Number.isFinite(segment.start) && Number.isFinite(end) &&
      segment.start >= 0 && end > segment.start ? [{ ...segment, end }] : [];
  });
}

function splitAtPunctuation(segment) {
  const pieces = segment.text.match(/[^.!?,;:]+[.!?,;:]?(?=\s|$)|[^.!?,;:]+/g)
    ?.map((text) => text.trim()).filter(Boolean) || [segment.text];
  if (pieces.length === 1) return [segment];
  const wordCounts = pieces.map((text) => Math.max(1, words(text).length));
  const totalWords = wordCounts.reduce((total, count) => total + count, 0);
  let elapsedWords = 0;
  return pieces.map((text, index) => {
    const start = segment.start + (segment.end - segment.start) * elapsedWords / totalWords;
    elapsedWords += wordCounts[index];
    const end = index === pieces.length - 1 ? segment.end :
      segment.start + (segment.end - segment.start) * elapsedWords / totalWords;
    return { ...segment, text, start, end, hasWordTiming: false, timingEstimated: true };
  });
}

export function buildPhrases(segments, level) {
  const maximum = limits[level];
  const phrases = [];
  let group = [];
  const flush = () => {
    if (!group.length) return;
    phrases.push({
      text: group.map((part) => part.text).join(' ').replace(/\s+/g, ' '),
      start: group[0].start,
      end: group[group.length - 1].end,
      sourceSegmentCount: new Set(group.map((part) => part.sourceIndex)).size,
      needsExpandedPractice: false,
      endingHasWordTiming: group[group.length - 1].hasWordTiming,
      timingEstimated: group.some((part) => part.timingEstimated),
    });
    group = [];
  };
  for (const segment of segments.flatMap((part, sourceIndex) =>
    splitAtPunctuation({ ...part, sourceIndex }))) {
    const candidate = [...group, segment];
    const text = candidate.map((part) => part.text).join(' ');
    if (group.length && (segment.start - group[group.length - 1].end > 1.15 ||
      segment.end - group[0].start > maximum.seconds ||
      words(text).length > maximum.words || text.length > maximum.characters)) flush();
    group.push(segment);
    if (/[.!?,;:]$/.test(segment.text) &&
      words(group.map((part) => part.text).join(' ')).length >= 4) flush();
  }
  flush();
  return phrases;
}

export function classify(segments, title) {
  if (!segments.length) return null;
  const duration = segments[segments.length - 1].end - segments[0].start;
  const tokens = words(segments.map((segment) => segment.text).join(' '));
  if (duration < 12 || duration > 185 || tokens.length < 30) return null;
  const rate = tokens.length * 60 / duration;
  if (rate >= 270) return null;
  const longShare = tokens.filter((word) => word.length >= 8).length / tokens.length;
  const draft = buildPhrases(segments, 'advanced');
  const lengths = draft.map((phrase) => words(phrase.text).length).sort((a, b) => a - b);
  const typical = lengths[Math.floor(lengths.length / 2)] ?? tokens.length;
  const fastest = Math.max(rate, ...draft.filter((phrase) => words(phrase.text).length >= 8 && phrase.end - phrase.start >= 2)
    .map((phrase) => words(phrase.text).length * 60 / (phrase.end - phrase.start)));
  if (/\b(c1|c2|advanced english|english advanced)\b/i.test(title) || rate >= 165 || longShare >= 0.22 ||
    fastest >= 190 || (rate >= 140 && longShare >= 0.14)) return 'advanced';
  if (!/\b(b1|b2|intermediate english|english intermediate)\b/i.test(title) &&
    rate <= 105 && fastest <= 130 && longShare <= 0.07 && typical <= 12) return 'beginner';
  return 'intermediate';
}

export function topicsFor(title, segments, seededInterest) {
  const titleWords = new Set(words(title.toLowerCase()));
  const transcriptWords = new Set(words(segments.map((segment) => segment.text).join(' ').toLowerCase()));
  const matches = Object.entries(keywords).filter(([, terms]) =>
    terms.some((term) => titleWords.has(term)) || terms.filter((term) => transcriptWords.has(term)).length >= 2)
    .map(([interest]) => interest);
  if (seededInterest && matches.includes(seededInterest)) return [seededInterest, ...matches.filter((item) => item !== seededInterest)];
  return matches;
}

export function prepare({ videoID, title, channel, channelID, rawSegments, seededInterest }) {
  const segments = normalizeSegments(rawSegments);
  if (segments.length !== rawSegments.length) throw new Error('Legenda com tempos ou linhas inválidas');
  const level = classify(segments, title);
  if (!level) throw new Error('Legenda insuficiente ou velocidade inválida');
  const interests = topicsFor(title, segments, seededInterest);
  if (!interests.length) throw new Error('Assunto não identificado');
  const phrases = buildPhrases(segments, level);
  if (!phrasesArePractical(phrases, level)) {
    throw new Error('Trechos longos ou curtos demais');
  }
  return {
    version: 1, segmentationVersion: 2, videoID, title, channel, channelID,
    languageCode: 'en', source: 'mac-curator', level, interests,
    segments, phrases, affinity: {},
  };
}

export function phrasesArePractical(phrases, level) {
  const maximum = limits[level];
  return Boolean(maximum) && phrases.length >= 2 && phrases.every((phrase) =>
    Number.isFinite(phrase.start) && Number.isFinite(phrase.end) &&
    phrase.end > phrase.start && phrase.end - phrase.start <= maximum.seconds &&
    words(phrase.text).length >= 3 && words(phrase.text).length <= maximum.words &&
    phrase.text.length <= maximum.characters);
}

export function affinityFor(prepared, signals) {
  const affinity = {};
  for (const interest of prepared.interests) {
    const relevant = signals.filter((signal) =>
      signal.level === prepared.level && Array.isArray(signal.interests) && signal.interests.includes(interest));
    if (!relevant.length) continue;
    const likes = relevant.filter((signal) => signal.reaction === 'liked').length;
    affinity[interest] = Math.min(15, Math.round(15 * (likes + 1) / (relevant.length + 4)));
  }
  return affinity;
}
