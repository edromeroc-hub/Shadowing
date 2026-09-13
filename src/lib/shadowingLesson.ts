export type TranscriptSegment = {
  text: string;
  start: number;
  end: number;
};

export type ShadowingPhrase = TranscriptSegment & {
  translation: string;
};

const LEAD_IN_SECONDS = 0.18;
const TRAILING_SECONDS = 0.32;
const MAX_SECONDS = 8;
const MAX_CHARS = 160;
const MIN_SECONDS = 0.55;
const MIN_IDEAL_SECONDS = 1.4;
const MIN_WORDS = 4;

function cleanText(value: string) {
  return value
    .replace(/<[^>]*>/g, ' ')
    .replace(/\[[^\]]+\]/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeSegments(segments: TranscriptSegment[]) {
  return segments
    .map((segment) => ({
      text: cleanText(String(segment.text || '')),
      start: Number(Number(segment.start).toFixed(3)),
      end: Number(Number(segment.end).toFixed(3)),
    }))
    .filter((segment) => segment.text && Number.isFinite(segment.start) && Number.isFinite(segment.end) && segment.end > segment.start)
    .sort((left, right) => left.start - right.start)
    .map((segment, index, normalized) => {
      const nextStart = normalized[index + 1]?.start;
      const end = Number.isFinite(nextStart) && nextStart > segment.start + 0.25
        ? Math.min(segment.end, nextStart)
        : segment.end;
      return { ...segment, end: Math.max(end, segment.start + 0.35) };
    });
}

function countWords(text: string) {
  return text.replace(/[^\w\s'-]/g, ' ').split(/\s+/).filter(Boolean).length;
}

function isTooShort(segment: TranscriptSegment) {
  const fillerOnly = /^(ok(?:ay)?|yeah|yes|no|right|well|so|uh|um|hmm|all right)[,.!? ]*$/i.test(segment.text.trim());
  return fillerOnly || countWords(segment.text) < MIN_WORDS || segment.end - segment.start < MIN_IDEAL_SECONDS;
}

function endsAtPause(text: string) {
  return /[,.;:!?]["')\]]?$/.test(text.trim());
}

function mergeShortPhrases(phrases: TranscriptSegment[]) {
  const repaired: TranscriptSegment[] = [];

  for (const phrase of phrases) {
    const previous = repaired[repaired.length - 1];
    const combinedText = previous ? `${previous.text} ${phrase.text}`.replace(/\s+/g, ' ').trim() : '';
    const canMerge = Boolean(
      previous
      && phrase.end - previous.start <= MAX_SECONDS
      && combinedText.length <= MAX_CHARS
      && phrase.start - previous.end <= 1.8,
    );

    if (previous && canMerge && (isTooShort(previous) || isTooShort(phrase))) {
      repaired[repaired.length - 1] = {
        text: combinedText,
        start: previous.start,
        end: phrase.end,
      };
    } else {
      repaired.push({ ...phrase });
    }
  }

  return repaired;
}

export function buildLocalShadowingLesson(rawSegments: TranscriptSegment[], limit = 60): ShadowingPhrase[] {
  const segments = normalizeSegments(rawSegments);
  const phrases: TranscriptSegment[] = [];
  let current: TranscriptSegment | null = null;

  for (const segment of segments) {
    if (!current) {
      current = { ...segment };
      continue;
    }

    const combinedText = `${current.text} ${segment.text}`.replace(/\s+/g, ' ').trim();
    const combinedDuration = segment.end - current.start;
    const shouldMerge = (
      segment.start - current.end <= (isTooShort(current) ? 1.8 : 1.1)
      && combinedDuration <= MAX_SECONDS
      && combinedText.length <= MAX_CHARS
      && (isTooShort(current) || !endsAtPause(current.text))
    );

    if (shouldMerge) {
      current = { text: combinedText, start: current.start, end: segment.end };
    } else {
      phrases.push(current);
      current = { ...segment };
    }
  }

  if (current) phrases.push(current);

  const repaired = mergeShortPhrases(phrases);
  return repaired
    .map((phrase, index) => {
      const previous = repaired[index - 1];
      const next = repaired[index + 1];
      const start = Math.max(previous?.end ?? 0, phrase.start - LEAD_IN_SECONDS);
      const end = Math.min(next?.start ?? phrase.end + TRAILING_SECONDS, phrase.end + TRAILING_SECONDS);
      return {
        ...phrase,
        start: Number(start.toFixed(3)),
        end: Number(Math.max(end, start + MIN_SECONDS).toFixed(3)),
        translation: '',
      };
    })
    .filter((phrase) => phrase.end - phrase.start >= MIN_SECONDS)
    .slice(0, limit);
}
