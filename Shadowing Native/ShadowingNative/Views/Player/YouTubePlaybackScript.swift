import Foundation

enum YouTubePlaybackScript {
    static let source = #"""
    var shadowingRange = null;
    var playbackAllowed = true;
    var sampleTime = null;
    var sampleWallTime = 0;
    var internalPause = false;
    var pendingBoundarySample = null;
    var shadowingTimingDiagnostics = false;

    function resetShadowingClock() {
      sampleTime = null;
      sampleWallTime = performance.now();
    }

    function setPlaybackAllowed(allowed) {
      playbackAllowed = allowed;
      if (!allowed) {
        shadowingRange = null;
        internalPause = true;
        pendingBoundarySample = null;
        if (player && player.pauseVideo) player.pauseVideo();
      }
    }

    function setShadowingRange(start, end, revision, earlyStopMilliseconds) {
      var advance = Math.max(0, earlyStopMilliseconds || 0) / 1000;
      var minimumEnd = start + Math.min(0.1, (end - start) / 2);
      var effectiveEnd = Math.max(minimumEnd, end - advance);
      shadowingRange = {
        start:start, end:effectiveEnd, sourceEnd:end, revision:revision,
        advanceMilliseconds:earlyStopMilliseconds || 0, seeking:false,
        requestedAt:performance.now()
      };
      internalPause = false;
      pendingBoundarySample = null;
      resetShadowingClock();
    }

    function playShadowingRange(start, end, revision, earlyStopMilliseconds) {
      if (!playbackAllowed || !player) return;
      setShadowingRange(start, end, revision, earlyStopMilliseconds);
      shadowingRange.seeking = true;
      player.pauseVideo();
      player.seekTo(start, true);
    }

    function pauseShadowing(revision) {
      shadowingRange = null;
      internalPause = true;
      pendingBoundarySample = null;
      resetShadowingClock();
      if (player && player.pauseVideo) player.pauseVideo();
    }

    function finishShadowing(now) {
      if (!shadowingRange) return;
      var revision = shadowingRange.revision;
      if (shadowingTimingDiagnostics) {
        pendingBoundarySample = {
          revision:revision, sourceEnd:shadowingRange.sourceEnd,
          effectiveEnd:shadowingRange.end,
          advanceMilliseconds:shadowingRange.advanceMilliseconds,
          observedAtRequest:player.getCurrentTime() || 0,
          estimatedAtRequest:now,
          playbackRate:player.getPlaybackRate ? player.getPlaybackRate() : 1,
          requestedAt:performance.now()
        };
        send({
          type:'boundaryTiming', phase:'requested', revision:revision,
          sourceEnd:pendingBoundarySample.sourceEnd,
          effectiveEnd:pendingBoundarySample.effectiveEnd,
          advanceMilliseconds:pendingBoundarySample.advanceMilliseconds,
          observedAtRequest:pendingBoundarySample.observedAtRequest,
          estimatedAtRequest:now,
          playbackRate:pendingBoundarySample.playbackRate
        });
      }
      shadowingRange = null;
      internalPause = true;
      player.pauseVideo();
      send({type:'phraseEnded', value:now, revision:revision});
    }

    function shadowingStateChanged(state) {
      resetShadowingClock();
      if (state === 2 && pendingBoundarySample) {
        var sample = pendingBoundarySample;
        pendingBoundarySample = null;
        send({
          type:'boundaryTiming', phase:'paused', revision:sample.revision,
          sourceEnd:sample.sourceEnd, effectiveEnd:sample.effectiveEnd,
          advanceMilliseconds:sample.advanceMilliseconds,
          observedAtRequest:sample.observedAtRequest,
          estimatedAtRequest:sample.estimatedAtRequest,
          observedAtPause:player.getCurrentTime() || 0,
          playbackRate:sample.playbackRate,
          pauseLatencyMilliseconds:performance.now() - sample.requestedAt
        });
      }
      if (state === 1 && (!playbackAllowed || internalPause)) {
        player.pauseVideo();
        return;
      }
      if (state === 0 && shadowingRange && !shadowingRange.seeking) {
        finishShadowing(player.getCurrentTime() || 0);
      }
      if (state === 2 && (internalPause || (shadowingRange && shadowingRange.seeking))) {
        return;
      }
      send({type:'state', value:state});
    }

    function monitorShadowingRange() {
      if (player && player.getCurrentTime && shadowingRange && playbackAllowed) {
        var now = player.getCurrentTime() || 0;
        var wallTime = performance.now();
        if (shadowingRange.seeking) {
          if (now >= shadowingRange.start - 0.05 &&
              now < Math.min(shadowingRange.end, shadowingRange.start + 0.25)) {
            shadowingRange.seeking = false;
            resetShadowingClock();
            player.playVideo();
          } else if (wallTime - shadowingRange.requestedAt > 8000) {
            pauseShadowing();
            send({type:'error', value:'seek-timeout'});
          } else if (player.getPlayerState() === 1) {
            player.pauseVideo();
          }
        }
        if (shadowingRange && !shadowingRange.seeking && player.getPlayerState() === 1) {
          if (sampleTime === null || now !== sampleTime) {
            sampleTime = now;
            sampleWallTime = wallTime;
          }
          var rate = player.getPlaybackRate ? player.getPlaybackRate() : 1;
          var estimatedTime = now + Math.min(Math.max(0, wallTime - sampleWallTime) / 1000, 0.28) * rate;
          if (estimatedTime >= shadowingRange.end) finishShadowing(estimatedTime);
        }
      }
      window.requestAnimationFrame(monitorShadowingRange);
    }
    """#
}
