import test from 'node:test';
import assert from 'node:assert/strict';
import { affinityFor, buildPhrases, classify, normalizeSegments, phrasesArePractical, prepare, topicsFor, words } from './quality.mjs';

const segments = Array.from({ length: 20 }, (_, index) => ({
  text: index % 2 ? 'at the gym today.' : 'We are working',
  start: index * 4,
  end: index * 4 + 3.9,
  hasWordTiming: false,
}));

test('normalizes overlapping caption timestamps', () => {
  const normalized = normalizeSegments([
    { text: 'Hello', start: 0, end: 2 },
    { text: 'world', start: 1.5, end: 3 },
  ]);
  assert.equal(normalized[0].end, 1.5);
});

test('rejects a caption with too few words', () => {
  assert.equal(classify([{ text: 'okay', start: 0, end: 1 }], 'okay'), null);
});

test('rejects malformed timestamp rows rather than silently dropping them', () => {
  assert.throws(() => prepare({
    videoID: 'abcdefghijk', title: 'Gym training', channel: 'Example', channelID: 'channel',
    rawSegments: [...segments, { text: 'broken', start: 100, end: 90 }], seededInterest: 'fitness',
  }), /tempos/);
});

test('prepares a beginner gym lesson with bounded phrases', () => {
  const lesson = prepare({
    videoID: 'abcdefghijk', title: 'Gym training', channel: 'Example', channelID: 'channel',
    rawSegments: segments, seededInterest: 'fitness',
  });
  assert.equal(lesson.level, 'beginner');
  assert.ok(lesson.interests.includes('fitness'));
  assert.ok(lesson.phrases.every((phrase) => phrase.end - phrase.start <= 4.5));
});

test('does not infer an unrelated interest from its seed alone', () => {
  assert.deepEqual(topicsFor('Gym training', segments, 'aviation'), ['fitness']);
});

test('rejects impractical isolated caption phrases', () => {
  const broken = segments.map((segment, index) => ({ ...segment, text: index === 0 ? 'Okay.' : segment.text }));
  assert.throws(() => prepare({
    videoID: 'abcdefghijk', title: 'Gym training', channel: 'Example', channelID: 'channel',
    rawSegments: broken, seededInterest: 'fitness',
  }), /Trechos/);
});

test('keeps phrase intervals increasing', () => {
  const phrases = buildPhrases(normalizeSegments(segments), 'beginner');
  assert.ok(phrases.every((phrase, index) => index === 0 || phrases[index - 1].end <= phrase.start));
});

test('splits a question inside a caption instead of joining it to the next sentence', () => {
  const caption = normalizeSegments([
    { text: 'Why are there three and even four pilots', start: 0.08, end: 2.8 },
    { text: 'on some international flights? Well,', start: 2.8, end: 5.279 },
    { text: 'back in the early days of international', start: 5.279, end: 7.04 },
    { text: 'flying when the 707 was first introduced', start: 7.04, end: 10 },
  ]);
  const phrases = buildPhrases(caption, 'advanced');
  assert.equal(phrases[0].text, 'Why are there three and even four pilots on some international flights?');
  assert.equal(phrases[1].text, 'Well, back in the early days of international flying when the 707 was first introduced');
  assert.equal(phrases[0].sourceSegmentCount, 2);
  assert.equal(phrases[0].timingEstimated, true);
  assert.equal(phrases[0].end, phrases[1].start);
  assert.deepEqual(words(phrases.map((phrase) => phrase.text).join(' ')),
    words(caption.map((part) => part.text).join(' ')));
});

test('keeps an unpunctuated caption bounded without inventing punctuation', () => {
  const caption = normalizeSegments(Array.from({ length: 5 }, (_, index) => ({
    text: 'we can go to the market', start: index * 2, end: index * 2 + 2,
  })));
  const phrases = buildPhrases(caption, 'intermediate');
  assert.ok(phrases.length > 1);
  assert.ok(phrases.every((phrase) => phrase.end - phrase.start <= 5.5));
  assert.ok(phrases.every((phrase) => !phrase.text.endsWith('.')));
  assert.equal(phrasesArePractical(phrases, 'intermediate'), true);
});

test('likes only raise affinity for the same level and interest', () => {
  const prepared = { level: 'beginner', interests: ['fitness', 'cooking'] };
  const scores = affinityFor(prepared, [
    { level: 'beginner', interests: ['fitness'], reaction: 'liked' },
    { level: 'advanced', interests: ['fitness'], reaction: 'liked' },
    { level: 'beginner', interests: ['cooking'], reaction: 'hidden' },
  ]);
  assert.ok(scores.fitness > scores.cooking);
});
