import test from 'node:test';
import assert from 'node:assert/strict';
import { assessShortsFormat, secondsFromDuration } from './shorts-format.mjs';

function video({ duration = 'PT58S', width = 405, height = 720, publishedAt = '2024-05-22T23:46:40Z' } = {}) {
  return {
    contentDetails: { duration }, player: { embedWidth: width, embedHeight: height },
    snippet: { publishedAt }, status: { embeddable: true },
  };
}

test('rejects horizontal podcast clips even when they are under four minutes', () => {
  assert.equal(assessShortsFormat(video({ duration: 'PT2M19S', width: 720, height: 405 })).eligible, false);
  assert.match(assessShortsFormat(video({ duration: 'PT2M19S', width: 720, height: 405 })).reason, /horizontal/);
});

test('accepts vertical or square videos within the Shorts duration for their date', () => {
  assert.equal(assessShortsFormat(video()).eligible, true);
  assert.equal(assessShortsFormat(video({ width: 720, height: 720 })).eligible, true);
  assert.equal(assessShortsFormat(video({ duration: 'PT2M59S', publishedAt: '2025-06-01T00:00:00Z' })).eligible, true);
  assert.equal(assessShortsFormat(video({ duration: 'PT3M1S', publishedAt: '2025-06-01T00:00:00Z' })).eligible, false);
  assert.equal(assessShortsFormat(video({ duration: 'PT1M1S' })).eligible, false);
});

test('fails closed when duration, date or aspect ratio cannot be verified', () => {
  assert.equal(assessShortsFormat(video({ width: null })).eligible, false);
  assert.equal(assessShortsFormat(video({ publishedAt: 'invalid' })).eligible, false);
  assert.equal(assessShortsFormat(video({ duration: 'unknown' })).eligible, false);
  assert.equal(assessShortsFormat(null).eligible, false);
  assert.equal(secondsFromDuration('PT2M19S'), 139);
});
