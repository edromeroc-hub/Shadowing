import assert from 'node:assert/strict';
import test from 'node:test';
import { appWouldAccept, buildLesson } from './lib/lesson.mjs';
import { RateLimitedError, buildTimedWords, fetchCaptions, formatWordsForReading, parseJSON3, speechStats, syllables } from './lib/words.mjs';
import { MUSIC_GENRES, buildMusicIndex, cleanMusicEntry } from './lib/music.mjs';
import { shortsCheck } from './lib/youtube-data.mjs';

const asrEvent = { tStartMs: 1000, dDurationMs: 2000, segs: [
  { utf8: 'hello' }, { utf8: ' how', tOffsetMs: 400 }, { utf8: ' are', tOffsetMs: 700 }, { utf8: ' you', tOffsetMs: 900 },
] };

test('json3 com offsets vira uma unidade por palavra com tempo real', () => {
  const words = parseJSON3({ events: [asrEvent] });
  assert.deepEqual(words.map((word) => word.text), ['hello', 'how', 'are', 'you']);
  assert.ok(words.every((word) => word.hasWordTiming));
  assert.deepEqual(words.map((word) => word.start), [1, 1.4, 1.7, 1.9]);
});

test('alinha a legenda manual pontuada com o tempo da automática', () => {
  const manual = [{ text: 'Hello, how are you?', start: 0.9, end: 3.2, hasWordTiming: false }];
  const asr = parseJSON3({ events: [asrEvent] });
  const timed = buildTimedWords({ manual, asr });
  assert.equal(timed.timingQuality, 'aligned');
  assert.deepEqual(timed.words.map((word) => word.text), ['Hello,', 'how', 'are', 'you?']);
  assert.deepEqual(timed.words.map((word) => word.start), [1, 1.4, 1.7, 1.9]);
});

test('palavra que a automática errou fica interpolada entre as vizinhas', () => {
  const manual = [{ text: 'we are doing great today', start: 0, end: 3, hasWordTiming: false }];
  const asr = [['we', 0], ['are', 0.5], ['doin', 1], ['great', 1.5], ['today', 2]].map(([text, start]) => ({ text, start, end: start + 0.4, hasWordTiming: true }));
  const timed = buildTimedWords({ manual, asr });
  const doing = timed.words[2];
  assert.equal(doing.timing, 'interpolated');
  assert.ok(doing.start >= timed.words[1].end && doing.end <= timed.words[3].start);
});

test('sem a legenda automática, os tempos ficam estimados', () => {
  const timed = buildTimedWords({ manual: [{ text: 'One two three four', start: 0, end: 2, hasWordTiming: false }], asr: null });
  assert.equal(timed.timingQuality, 'estimated');
  assert.ok(timed.words.every((word) => word.timing === 'estimated'));
});

test('marcas não faladas não viram palavras', () => {
  const timed = buildTimedWords({ manual: null, asr: [{ text: '[Music] yeah ♪', start: 0, end: 1, hasWordTiming: true }] });
  assert.deepEqual(timed.words.map((word) => word.text), ['yeah']);
});

test('">>" marca troca de falante em vez de virar palavra', () => {
  const timed = buildTimedWords({ manual: null, asr: [{ text: 'Yeah. >> Thank you.', start: 0, end: 2, hasWordTiming: false }] });
  assert.deepEqual(timed.words.map((word) => word.text), ['Yeah.', 'Thank', 'you.']);
  assert.equal(timed.words[1].speakerChange, true);
  assert.match(formatWordsForReading(timed.words), /0:Yeah\. (‖ )?» 1:Thank/);
});

test('sílabas e estatísticas de fala', () => {
  assert.deepEqual(['cat', 'water', 'beautiful', 'make', 'table', 'the', 'rhythm'].map(syllables), [1, 2, 3, 1, 2, 1, 1]);
  const words = Array.from({ length: 10 }, (_, index) => ({ text: 'water', start: index * 0.5, end: index * 0.5 + 0.4 }));
  // 20 sílabas em 4,9 s de fala (9 intervalos de 0,5 s + a última palavra de 0,4 s).
  assert.equal(speechStats(words).syllablesPerSecond, 4.08);
});

test('o texto de leitura numera palavras e marca pausas', () => {
  const text = formatWordsForReading([{ text: 'Hi.', start: 0, end: 0.3 }, { text: 'Yes', start: 1, end: 1.2 }]);
  assert.equal(text, '[00:00.0] 0:Hi. ‖ 1:Yes');
});

test('429 do YouTube vira RateLimitedError', async () => {
  const fetchImpl = async () => ({ status: 429, ok: false, json: async () => ({}) });
  await assert.rejects(fetchCaptions('abcdefghijk', { fetchImpl }), RateLimitedError);
});

test('Short vertical dentro do limite passa; horizontal não', () => {
  const base = { contentDetails: { duration: 'PT45S' }, snippet: { publishedAt: '2025-01-01T00:00:00Z' }, status: { embeddable: true } };
  assert.equal(shortsCheck({ ...base, player: { embedWidth: 405, embedHeight: 720 } }).ok, true);
  assert.equal(shortsCheck({ ...base, player: { embedWidth: 720, embedHeight: 405 } }).ok, false);
});

const words = 'Hey, what is up? I was walking down the street today, and this guy just stopped me. He asked if I knew the way to the station.'
  .split(' ').map((text, index) => ({ text, start: index * 0.3, end: index * 0.3 + 0.28, timing: 'word' }));
const info = { title: 'Street story', channel: 'Example', channelID: 'UC0123456789012345678901' };

test('monta um documento que o app aceita, com os tempos vindos das palavras', () => {
  const decision = { level: 'intermediate', interests: ['streetInterviews'], reason: 'Conversa natural',
    phrases: [{ from: 0, to: 3 }, { from: 4, to: 10 }, { from: 11, to: 16, text: 'and this guy just stopped me.' }, { from: 17, to: 25 }] };
  const { payload, errors } = buildLesson({ videoID: 'abcdefghijk', info, words, timingQuality: 'aligned', decision });
  assert.deepEqual(errors, []);
  assert.ok(appWouldAccept(payload));
  const round = (value) => Math.round(value * 1000) / 1000;
  assert.equal(payload.phrases[1].start, round(words[4].start));
  assert.equal(payload.phrases[1].end, round(words[10].end));
  assert.equal(payload.source, 'antigravity-gemini');
});

test('recusa frases sobrepostas, longas demais ou com texto diferente das palavras', () => {
  const decision = { level: 'beginner', interests: ['streetInterviews'],
    phrases: [{ from: 0, to: 3 }, { from: 3, to: 6 }, { from: 7, to: 25 }, { from: 0, to: 0, text: 'completely different words here' }] };
  const { payload, errors } = buildLesson({ videoID: 'abcdefghijk', info, words, timingQuality: 'word', decision });
  assert.equal(payload, null);
  assert.ok(errors.some((error) => error.includes('começa antes')));
  assert.ok(errors.some((error) => error.includes('palavras (máximo 9')));
  assert.ok(errors.some((error) => error.includes('não corresponde')));
});

test('nível e temas precisam ser valores conhecidos pelo app', () => {
  const { errors } = buildLesson({ videoID: 'abcdefghijk', info, words, timingQuality: 'word', decision: { level: 'easy', interests: ['comedy'], phrases: [] } });
  assert.ok(errors.some((error) => error.startsWith('level')));
  assert.ok(errors.some((error) => error.startsWith('interests')));
});

test('limpa artista e música vindos do título do YouTube', () => {
  assert.deepEqual(cleanMusicEntry({ artist: 'Adele', trackTitle: 'Adele - Hello (Official Music Video)', channel: 'Adele' }), { artist: 'Adele', trackTitle: 'Hello' });
  assert.deepEqual(cleanMusicEntry({ artist: 'Bohemian Rhapsody - Queen', trackTitle: 'Bohemian Rhapsody - Queen', channel: 'Queen Official' }), { artist: 'Queen', trackTitle: 'Bohemian Rhapsody' });
  assert.deepEqual(cleanMusicEntry({ artist: 'Queen Official', trackTitle: 'Queen - Crazy Little Thing Called Love', channel: 'Queen Official' }), { artist: 'Queen', trackTitle: 'Crazy Little Thing Called Love' });
  assert.equal(cleanMusicEntry({ artist: 'Adele', trackTitle: 'Send My Love (To Your New Lover)', channel: 'Adele' }).trackTitle, 'Send My Love (To Your New Lover)');
  assert.equal(cleanMusicEntry({ artist: 'Adele', trackTitle: 'Hello - Live at the BBC', channel: 'Adele' }).trackTitle, 'Hello - Live at the BBC');
});

test('índice de músicas junta grafias do artista e tira duplicatas', () => {
  const song = (videoID, artist, trackTitle, channel, format = 'video') => ({ videoID, artist, trackTitle, channel, format, genres: ['rock', 'funk'], level: 'beginner', durationSeconds: 212.4 });
  const entries = buildMusicIndex([
    song('aaaaaaaaaaa', 'Imagine Dragons', 'Imagine Dragons - Believer', 'ImagineDragonsVEVO'),
    song('bbbbbbbbbbb', 'Imagine Dragons', 'Imagine Dragons - Believer (Official Video)', 'ImagineDragons'),
    song('ccccccccccc', 'OneRepublic', 'Counting Stars', 'OneRepublicVEVO'),
    song('ddddddddddd', 'Kacey Musgraves', 'Slow Burn', 'NPR Music'),
    song('eeeeeeeeeee', 'Imagine Dragons', 'Believer', 'ImagineDragons', 'short'),
    song('bad id', 'X', 'Y', 'Z'),
  ]);
  assert.deepEqual(entries.map((entry) => entry.v), ['aaaaaaaaaaa', 'ccccccccccc', 'ddddddddddd', 'eeeeeeeeeee']);
  assert.deepEqual(entries[0], { v: 'aaaaaaaaaaa', f: 'video', a: 'Imagine Dragons', t: 'Believer', g: ['rock'], l: 'beginner', d: 212 });
  assert.equal(entries[1].a, 'OneRepublic');
  assert.equal(entries[2].a, 'Kacey Musgraves');
  assert.ok(MUSIC_GENRES.includes('metal'));
});
