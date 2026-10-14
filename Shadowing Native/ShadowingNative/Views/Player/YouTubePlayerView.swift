import Observation
import os
import SwiftUI
import WebKit

@MainActor
@Observable
final class YouTubePlayerController {
    enum PlaybackState: Int {
        case unstarted = -1
        case ended = 0
        case playing = 1
        case paused = 2
        case buffering = 3
        case cued = 5
    }

    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var hasReachedPhraseEnd = false
    var isReady = false
    var currentTime = 0.0
    var duration = 0.0
    var state: PlaybackState = .unstarted
    var activePhrase: ShadowingPhrase?
    /// Fica falso até o primeiro quadro tocar: a tela mostra a capa do vídeo em vez do player preto.
    private(set) var hasRenderedVideo = false
    var isLoopEnabled = true
    var isWaitingForStudent = false
    var pauseMultiplier = 1.0
    private(set) var isPlaybackRequested = false
    private(set) var playbackError: String?
    private(set) var playbackRate = 1.0
    @ObservationIgnored private var playbackAllowed = true
    @ObservationIgnored private var lastAutomaticRetry: Date?
    func connect(_ webView: WKWebView) {
        self.webView = webView
    }

    func prepareForVideo() {
        pause()
        isReady = false
        currentTime = 0
        duration = 0
        activePhrase = nil
        hasReachedPhraseEnd = false
        playbackError = nil
        hasRenderedVideo = false
        state = .unstarted
    }

    func disconnect() {
        pause()
        webView = nil
        isReady = false
    }

    func setPlaybackAllowed(_ allowed: Bool) {
        playbackAllowed = allowed
        if !allowed { pause() }
        evaluate("setPlaybackAllowed(\(allowed ? "true" : "false"));")
    }

    func play() {
        guard playbackAllowed else { return }
        let wasWaiting = isWaitingForStudent
        cancelWaitingPeriod()
        isPlaybackRequested = true
        playbackError = nil
        if let activePhrase {
            if wasWaiting || hasReachedPhraseEnd || currentTime < activePhrase.start || currentTime >= playbackEnd(of: activePhrase) {
                play(phrase: activePhrase)
            } else {
                configureRange(for: activePhrase)
                evaluate("player && player.playVideo();")
            }
        } else {
            evaluate("player && player.playVideo();")
        }
    }

    func pause() {
        cancelWaitingPeriod()
        isPlaybackRequested = false
        revision += 1
        evaluate("pauseShadowing(\(revision));")
        state = .paused
    }

    func togglePlayPause() {
        isPlaybackRequested || state == .playing ? pause() : play()
    }

    func seek(to seconds: Double, playAfterSeeking: Bool = false) {
        let safeSeconds = max(0, seconds)
        evaluate("player && player.seekTo(\(safeSeconds), true);\(playAfterSeeking ? "player.playVideo();" : "")")
    }

    func play(phrase: ShadowingPhrase) {
        cancelWaitingPeriod()
        activePhrase = phrase
        hasReachedPhraseEnd = false
        guard playbackAllowed else { return }
        isPlaybackRequested = true
        playbackError = nil
        revision += 1
        state = .buffering
        guard isReady else { return }
        evaluate("playShadowingRange(\(phrase.start), \(playbackEnd(of: phrase)), \(revision), \(endAdvanceMilliseconds));")
    }

    func stopLoop() {
        isLoopEnabled = false
        if isWaitingForStudent { pause() }
        cancelWaitingPeriod()
    }

    func startLoop() {
        isLoopEnabled = true
        if let activePhrase {
            play(phrase: activePhrase)
        }
    }

    fileprivate func receive(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            duration = message["duration"] as? Double ?? 0
            evaluate("setPlaybackAllowed(\(playbackAllowed ? "true" : "false"));")
#if DEBUG
            evaluate("shadowingTimingDiagnostics = true;")
            // Só para testes: dispara um erro do player para conferir a nova tentativa automática.
            if let option = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--simulate-playback-error=") }),
               let code = option.split(separator: "=").last {
                let value = Int(code).map(String.init) ?? "'\(code)'"
                evaluate("setTimeout(function(){ send({type:'error', value:\(value)}); }, 6000);")
            }
#endif
            if isPlaybackRequested { play() }
        case "time":
            currentTime = number(message["value"]) ?? currentTime
            duration = number(message["duration"]) ?? duration
        case "phraseEnded":
            guard number(message["revision"]).map(Int.init) == revision else { return }
            currentTime = number(message["value"]) ?? currentTime
            hasReachedPhraseEnd = true
            handlePhraseBoundary()
        case "boundaryTiming":
#if DEBUG
            guard number(message["revision"]).map(Int.init) == revision,
                  let phrase = activePhrase else { return }
            let phase = message["phase"] as? String ?? "unknown"
            let sourceEnd = number(message["sourceEnd"]) ?? phrase.end
            let effectiveEnd = number(message["effectiveEnd"]) ?? sourceEnd
            let observedRequest = number(message["observedAtRequest"]) ?? 0
            let estimatedRequest = number(message["estimatedAtRequest"]) ?? 0
            let observedPause = number(message["observedAtPause"]) ?? -1
            let pauseLatency = number(message["pauseLatencyMilliseconds"]) ?? -1
            let rate = number(message["playbackRate"]) ?? 1
            Logger(subsystem: "ShadowingNative", category: "PlaybackTiming")
                .debug("phase=\(phase, privacy: .public) start=\(phrase.start) phraseEnd=\(phrase.end) sourceEnd=\(sourceEnd) effectiveEnd=\(effectiveEnd) advanceMs=\(self.endAdvanceMilliseconds) requestTime=\(observedRequest) estimate=\(estimatedRequest) pausedTime=\(observedPause) pauseLatencyMs=\(pauseLatency) rate=\(rate) wordTiming=\(phrase.endingHasWordTiming) segments=\(phrase.sourceSegmentCount)")
#endif
        case "state":
            if let rawValue = number(message["value"]).map(Int.init),
               let newState = PlaybackState(rawValue: rawValue) {
                state = newState
                if newState == .playing { hasRenderedVideo = true }
                if newState == .playing, !playbackAllowed {
                    pause()
                } else if newState == .playing, isWaitingForStudent, let activePhrase {
                    play(phrase: activePhrase)
                } else if newState == .playing, !isPlaybackRequested {
                    isPlaybackRequested = true
                    if let activePhrase { play(phrase: activePhrase) }
                } else if newState == .paused, !isWaitingForStudent {
                    isPlaybackRequested = false
                }
            }
        case "rate":
            playbackRate = max(0.25, number(message["value"]) ?? 1)
        case "error":
            let code = message["value"].map { "\($0)" } ?? ""
#if DEBUG
            Logger(subsystem: "ShadowingNative", category: "PlaybackTiming")
                .debug("phase=error value=\(code, privacy: .public)")
#endif
            // Falhas passageiras (busca ignorada durante um redimensionamento, erro 5 do player HTML5)
            // costumam passar numa segunda tentativa: tenta sozinho uma vez antes de mostrar o erro.
            if Self.isTransientError(code), let phrase = activePhrase, playbackAllowed,
               lastAutomaticRetry.map({ Date().timeIntervalSince($0) > 10 }) ?? true {
                lastAutomaticRetry = Date()
                play(phrase: phrase)
                return
            }
            pause()
            playbackError = Self.errorMessage(for: code)
        default:
            break
        }
    }

    private func evaluate(_ script: String) {
        guard isReady else { return }
        webView?.evaluateJavaScript(script)
    }

    private func handlePhraseBoundary() {
        guard let phrase = activePhrase, isPlaybackRequested, playbackAllowed, !isWaitingForStudent else { return }

        state = .paused
        guard isLoopEnabled else {
            isPlaybackRequested = false
            return
        }

        isWaitingForStudent = true
        let pauseDuration = max(0.8, (phrase.duration - Double(endAdvanceMilliseconds) / 1000) / playbackRate * pauseMultiplier)
        let expectedRevision = revision
        loopTask?.cancel()
        loopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(pauseDuration))
            guard !Task.isCancelled, let self, self.isLoopEnabled,
                  self.isPlaybackRequested, self.playbackAllowed,
                  self.revision == expectedRevision, self.activePhrase?.id == phrase.id else { return }
            self.isWaitingForStudent = false
            self.play(phrase: phrase)
        }
    }

    private func configureRange(for phrase: ShadowingPhrase) {
        revision += 1
        evaluate("setShadowingRange(\(phrase.start), \(playbackEnd(of: phrase)), \(revision), \(endAdvanceMilliseconds));")
    }

    /// Ponto de pausa: `playbackEnd` evita tocar o começo da palavra seguinte (ver `PhraseBoundary`).
    private func playbackEnd(of phrase: ShadowingPhrase) -> Double {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--disable-safe-end") { return phrase.end }
#endif
        return phrase.playbackEnd ?? phrase.end
    }

    private var endAdvanceMilliseconds: Int {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let option = arguments.first(where: { $0.hasPrefix("--playback-cutoff-ms=") }),
              let milliseconds = Int(option.split(separator: "=").last ?? ""),
              [0, 50, 100, 150, 200].contains(milliseconds) else { return 0 }
        return milliseconds
#else
        return 0
#endif
    }

    static func isTransientError(_ code: String) -> Bool {
        code == "seek-timeout" || code == "5"
    }

    static func errorMessage(for code: String) -> String {
        switch code {
        case "100": "Este vídeo foi removido ou está indisponível no YouTube."
        case "101", "150": "O dono deste vídeo não permite reproduzi-lo fora do YouTube."
        default: "Não foi possível reproduzir este trecho. Toque em reproduzir para tentar novamente."
        }
    }

    private func cancelWaitingPeriod() {
        loopTask?.cancel()
        loopTask = nil
        isWaitingForStudent = false
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    let controller: YouTubePlayerController
    let allowsAutoplay: Bool

    init(videoID: String, controller: YouTubePlayerController, allowsAutoplay: Bool = false) {
        self.videoID = videoID
        self.controller = controller
        self.allowsAutoplay = allowsAutoplay
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = allowsAutoplay ? [] : .all
        configuration.userContentController.add(context.coordinator, name: "youtube")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        // O aluno controla o trecho só pelos botões do app: tocar no vídeo pularia a linha do tempo e
        // desencontraria a frase. Sem toque, o arrasto também passa direto para a rolagem do feed.
        webView.isUserInteractionEnabled = false
        webView.navigationDelegate = context.coordinator
        controller.connect(webView)
        context.coordinator.videoID = videoID
        load(videoID: videoID, into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.videoID != videoID else { return }
        context.coordinator.videoID = videoID
        controller.prepareForVideo()
        load(videoID: videoID, into: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.controller.disconnect()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "youtube")
        webView.stopLoading()
    }

    private func load(videoID: String, into webView: WKWebView) {
        let origin = "https://shadowingapp.onrender.com"
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
          <meta name="referrer" content="strict-origin-when-cross-origin">
          <style>
            html,body,#player { margin:0; width:100%; height:100%; background:#000; overflow:hidden; }
          </style>
        </head>
        <body>
          <div id="player"></div>
          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            var player;
            function send(payload) {
              payload.videoID = '\(videoID)';
              window.webkit.messageHandlers.youtube.postMessage(payload);
            }
            \(YouTubePlaybackScript.source)
            function disablePlayerCaptions() {
              if (!player) return;
              try { player.setOption('captions', 'track', {}); } catch (_) {}
              try { player.unloadModule('captions'); } catch (_) {}
            }
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                width: '100%', height: '100%', videoId: '\(videoID)',
                playerVars: {
                  playsinline: 1, controls: 0, disablekb: 1, fs: 0, rel: 0,
                  cc_load_policy: 0, iv_load_policy: 3,
                  enablejsapi: 1, origin: '\(origin)'
                },
                events: {
                  onReady: function(event) {
                    disablePlayerCaptions();
                    window.setTimeout(disablePlayerCaptions, 300);
                    send({type:'ready', duration:event.target.getDuration() || 0});
                    window.requestAnimationFrame(monitorShadowingRange);
                  },
                  onStateChange: function(event) {
                    if (event.data === 1) {
                      window.setTimeout(disablePlayerCaptions, 50);
                    }
                    shadowingStateChanged(event.data);
                  },
                  onPlaybackRateChange: function(event) {
                    resetShadowingClock();
                    send({type:'rate', value:event.data});
                  },
                  onError: function(event) { send({type:'error', value:event.data}); }
                }
              });
            }
            setInterval(function() {
              if (player && player.getCurrentTime) {
                send({type:'time', value:player.getCurrentTime() || 0, duration:player.getDuration() || 0});
              }
            }, 150);
          </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: origin))
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let controller: YouTubePlayerController
        var videoID = ""

        init(controller: YouTubePlayerController) {
            self.controller = controller
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let payload = message.body as? [String: Any],
                  payload["videoID"] as? String == videoID else { return }
            controller.receive(payload)
        }
    }
}
