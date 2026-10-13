import test from 'node:test';
import assert from 'node:assert/strict';
import {
  automaticReviewReasons, beginCycle, canTrustChannel, finishSearchPage, markCycleComplete,
  cycleIntervalMs, refreshSearchBudget,
} from './workflow.mjs';

const prepared = {
  videoID: 'abcdefghijk', channelID: 'trusted', level: 'intermediate', interests: ['fitness'], segmentationVersion: 2,
  segments: Array.from({ length: 10 }, (_, index) => ({
    text: 'We are working today', start: index * 3, end: index * 3 + 2.8,
  })),
  phrases: Array.from({ length: 10 }, (_, index) => ({
    text: 'We are working today', start: index * 3, end: index * 3 + 2.8,
  })),
};

test('the final channel starts a new cycle only after its cooldown', () => {
  const state = { seedIndex: 2, pending: [], nextCycleAt: null };
  markCycleComplete(state, 2, 100);
  assert.equal(state.nextCycleAt, 100 + cycleIntervalMs);
  assert.equal(beginCycle(state, 2, 101), false);
  assert.equal(beginCycle(state, 2, state.nextCycleAt), true);
  assert.equal(state.seedIndex, 0);
  const queued = { seedIndex: 2, pending: [{ videoID: 'abcdefghijk' }], nextCycleAt: 100 };
  assert.equal(beginCycle(queued, 2, 50), true);
  assert.equal(queued.seedIndex, 2);
});

test('each channel has bounded pagination and keeps queued candidates', () => {
  const state = { seedIndex: 0, pagesForSeed: 2, currentInterest: 'fitness', pending: [] };
  finishSearchPage(state, { videoIDs: ['abcdefghijk'], nextPageToken: 'more' });
  assert.equal(state.seedIndex, 1);
  assert.equal(state.pageToken, null);
  assert.deepEqual(state.pending, [{ videoID: 'abcdefghijk', interest: 'fitness' }]);
});

test('only a vetted seeded intermediate or advanced candidate qualifies', () => {
  assert.deepEqual(automaticReviewReasons(prepared, { source: 'seed', seededInterest: 'fitness', shortsFormatPassed: true }, ['trusted']), []);
  assert.ok(automaticReviewReasons(prepared, { source: 'seed', seededInterest: 'fitness' }, ['trusted'])
    .includes('Formato Short não verificado'));
  assert.ok(automaticReviewReasons(prepared, { source: 'suggestion' }, ['trusted']).length);
  assert.ok(automaticReviewReasons(prepared, null, ['trusted']).length);
  assert.ok(automaticReviewReasons(prepared, { source: 'seed', seededInterest: 'fitness' }, []).length);
  assert.ok(automaticReviewReasons({ ...prepared, level: 'beginner' },
    { source: 'seed', seededInterest: 'fitness' }, ['trusted']).length);
});

test('suspect timings stay in manual review', () => {
  const faulty = { ...prepared, segments: prepared.segments.map((segment, index) =>
    index === 3 ? { ...segment, end: segment.start + 0.01 } : segment) };
  assert.ok(automaticReviewReasons(faulty, { source: 'seed', seededInterest: 'fitness' }, ['trusted'])
    .some((reason) => reason.includes('Tempos')));
});

test('estimated cuts and outdated phrases do not auto-publish', () => {
  const metadata = { source: 'seed', seededInterest: 'fitness', shortsFormatPassed: true };
  const estimated = { ...prepared, phrases: prepared.phrases.map((phrase, index) =>
    index === 0 ? { ...phrase, timingEstimated: true } : phrase) };
  assert.ok(automaticReviewReasons(estimated, metadata, ['trusted'])
    .some((reason) => reason.includes('estimados')));
  assert.ok(automaticReviewReasons({ ...prepared, segmentationVersion: 1 }, metadata, ['trusted'])
    .some((reason) => reason.includes('nova divisão')));
});

test('a channel requires three distinct manual examples', () => {
  const samples = [0, 1, 2].map((index) => ({ videoID: `video${index}`, channelID: 'trusted' }));
  assert.equal(canTrustChannel(samples.slice(0, 2), 'trusted'), false);
  assert.equal(canTrustChannel([...samples, samples[0]], 'trusted'), true);
  assert.equal(canTrustChannel(samples, 'other'), false);
});

test('search quota only resets on the next UTC day', () => {
  const state = { searchDay: '2026-10-12', searchCount: 20, prioritySearchCount: 3 };
  refreshSearchBudget(state, Date.parse('2026-10-12T23:59:59Z'));
  assert.equal(state.searchCount, 20);
  assert.equal(state.prioritySearchCount, 3);
  refreshSearchBudget(state, Date.parse('2026-10-13T00:00:00Z'));
  assert.equal(state.searchCount, 0);
  assert.equal(state.prioritySearchCount, 0);
});
