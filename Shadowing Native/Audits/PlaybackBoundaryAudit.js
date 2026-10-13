import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const auditDirectory = path.dirname(fileURLToPath(import.meta.url));

const swiftSource = fs.readFileSync(
  path.join(auditDirectory, '../ShadowingNative/Views/Player/YouTubePlaybackScript.swift'),
  'utf8'
);
const scriptSource = swiftSource.match(/#"""([\s\S]*?)"""#/)[1];

function makeHarness() {
  const messages = [];
  const calls = { pause: 0, play: 0, seek: [] };
  let wallTime = 0;
  let videoTime = 0;
  let playerState = 2;
  let playbackRate = 1;
  const player = {
    pauseVideo() { calls.pause += 1; playerState = 2; },
    playVideo() { calls.play += 1; playerState = 1; },
    seekTo(seconds) { calls.seek.push(seconds); videoTime = seconds; },
    getCurrentTime() { return videoTime; },
    getPlayerState() { return playerState; },
    getPlaybackRate() { return playbackRate; }
  };
  const context = vm.createContext({
    player,
    performance: { now: () => wallTime },
    window: { requestAnimationFrame() {} },
    send: message => messages.push(message)
  });
  vm.runInContext(scriptSource, context);
  return {
    context, calls, messages,
    position(seconds) { videoTime = seconds; },
    wall(milliseconds) { wallTime = milliseconds; },
    state(value) { playerState = value; },
    rate(value) { playbackRate = value; }
  };
}

const early = makeHarness();
early.context.shadowingTimingDiagnostics = true;
early.context.playShadowingRange(10, 12, 1, 50);
assert.equal(early.calls.seek[0], 10);
early.context.monitorShadowingRange();
assert.equal(early.calls.play, 1);
early.position(11.94);
early.wall(1940);
early.context.monitorShadowingRange();
assert.equal(early.messages.filter(message => message.type === 'phraseEnded').length, 0);
early.position(11.95);
early.wall(1950);
early.context.monitorShadowingRange();
assert.equal(early.messages.filter(message => message.type === 'phraseEnded').length, 1);
assert.equal(early.messages.find(message => message.phase === 'requested').effectiveEnd, 11.95);
early.wall(2010);
early.context.shadowingStateChanged(2);
const acknowledged = early.messages.find(message => message.phase === 'paused');
assert.equal(acknowledged.pauseLatencyMilliseconds, 60);
assert.equal(acknowledged.observedAtPause, 11.95);
early.state(1);
const pauseCount = early.calls.pause;
early.context.shadowingStateChanged(1);
assert.equal(early.calls.pause, pauseCount + 1);
assert.equal(early.messages.filter(message => message.type === 'phraseEnded').length, 1);

const unchanged = makeHarness();
unchanged.context.playShadowingRange(0, 2, 2, 0);
unchanged.context.monitorShadowingRange();
unchanged.position(2);
unchanged.context.monitorShadowingRange();
assert.equal(unchanged.messages.find(message => message.type === 'phraseEnded').revision, 2);

const short = makeHarness();
short.context.setShadowingRange(3, 3.04, 3, 200);
assert.ok(short.context.shadowingRange.end > 3);
assert.ok(short.context.shadowingRange.end < 3.04);

const buffering = makeHarness();
buffering.context.playShadowingRange(0, 2, 4, 100);
buffering.context.monitorShadowingRange();
buffering.position(2);
buffering.state(3);
buffering.context.monitorShadowingRange();
assert.equal(buffering.messages.filter(message => message.type === 'phraseEnded').length, 0);
buffering.context.shadowingStateChanged(3);
buffering.state(1);
buffering.context.monitorShadowingRange();
assert.equal(buffering.messages.filter(message => message.type === 'phraseEnded').length, 1);

const accelerated = makeHarness();
accelerated.context.shadowingTimingDiagnostics = true;
accelerated.rate(1.5);
accelerated.context.playShadowingRange(4, 6, 8, 100);
accelerated.context.monitorShadowingRange();
accelerated.position(5.75);
accelerated.wall(100);
accelerated.context.monitorShadowingRange();
assert.equal(accelerated.messages.filter(message => message.type === 'phraseEnded').length, 0);
accelerated.wall(200);
accelerated.context.monitorShadowingRange();
assert.equal(accelerated.messages.find(message => message.phase === 'requested').playbackRate, 1.5);
assert.equal(accelerated.messages.find(message => message.type === 'phraseEnded').revision, 8);

const replaced = makeHarness();
replaced.context.shadowingTimingDiagnostics = true;
replaced.context.playShadowingRange(0, 2, 9, 0);
replaced.context.monitorShadowingRange();
replaced.position(2);
replaced.context.monitorShadowingRange();
replaced.context.playShadowingRange(3, 5, 10, 0);
replaced.context.monitorShadowingRange();
replaced.context.shadowingStateChanged(2);
assert.equal(replaced.messages.filter(message => message.phase === 'paused').length, 0);
assert.equal(replaced.context.shadowingRange.revision, 10);

const manual = makeHarness();
manual.context.playShadowingRange(0, 2, 5, 0);
manual.context.monitorShadowingRange();
manual.context.pauseShadowing(6);
manual.state(1);
const manualPauseCount = manual.calls.pause;
manual.context.shadowingStateChanged(1);
assert.equal(manual.calls.pause, manualPauseCount + 1);
manual.context.playShadowingRange(0, 2, 7, 0);
manual.context.monitorShadowingRange();
assert.equal(manual.calls.play, 2);

assert.ok(!scriptSource.includes('setVolume'));
assert.ok(!scriptSource.includes('fade'));
console.log('PASS boundary timing: zero/early cutoff, pause acknowledgment, 1.5x playback, replacement, buffering, short ranges and manual pause');
