import UIKit
import Capacitor
import AVKit
import Security

private struct YouTubeTranscriptSegment {
    let text: String
    let start: Double
    let end: Double
}

private struct YouTubeTranscriptPayload {
    let segments: [YouTubeTranscriptSegment]
    let title: String?
    let channel: String?
    let languageCode: String?
    let source: String
}

private enum YouTubeCaptionError: LocalizedError {
    case invalidVideoID
    case invalidResponse
    case requestFailed(Int)
    case captionsUnavailable
    case emptyCaptions
    case streamUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidVideoID:
            return "O link do YouTube não possui um código de vídeo válido."
        case .invalidResponse:
            return "O YouTube retornou uma resposta inválida."
        case .requestFailed(let statusCode):
            return "O YouTube recusou a solicitação (código \(statusCode))."
        case .captionsUnavailable:
            return "Este vídeo não possui uma legenda acessível."
        case .emptyCaptions:
            return "A faixa de legenda foi encontrada, mas veio vazia."
        case .streamUnavailable:
            return "O YouTube não forneceu um formato de vídeo compatível para reprodução."
        }
    }
}

@objc(YouTubeCaptionPlugin)
public class YouTubeCaptionPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "YouTubeCaptionPlugin"
    public let jsName = "YouTubeCaptions"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "offlineLibrary", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "downloadVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "aiSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "generateLesson", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "searchVideos", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "fetchTranscript", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "mountPlayer", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updatePlayerFrame", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "destroyPlayer", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "playVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pauseVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "seekTo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getCurrentTime", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPlayerState", returnType: CAPPluginReturnPromise)
    ]

    private var playerController: AVPlayerViewController?
    private var playerVideoID: String?
    private var playerTimeObserver: Any?
    private var playerStatusObserver: NSKeyValueObservation?
    private var playerLoadID = UUID()
    private var lastReportedPlayerState = -99
    private var downloadingVideo = false

    private func libraryDirectory() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var directory = root.appendingPathComponent("ShadowingLibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory
    }

    @objc public func offlineLibrary(_ call: CAPPluginCall) {
        do {
            let root = try libraryDirectory()
            let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            let videos: [[String: Any]] = directories.compactMap { directory in
                guard directory.lastPathComponent.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil,
                      FileManager.default.fileExists(atPath: directory.appendingPathComponent("video.mp4").path),
                      let data = try? Data(contentsOf: directory.appendingPathComponent("lesson.json")),
                      let lesson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                return ["videoId": directory.lastPathComponent, "path": directory.appendingPathComponent("video.mp4").absoluteString, "lesson": lesson]
            }
            call.resolve(["videos": videos])
        } catch { call.reject(error.localizedDescription) }
    }

    @objc public func downloadVideo(_ call: CAPPluginCall) {
        guard let videoID = call.getString("videoId"), videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil,
              let lesson = call.getObject("lesson"), let phrases = lesson["phrases"] as? [[String: Any]], !phrases.isEmpty else {
            call.reject("Vídeo ou aula inválida para download.")
            return
        }
        DispatchQueue.main.async {
            guard !self.downloadingVideo else { call.reject("Aguarde o download atual terminar."); return }
            self.downloadingVideo = true
            Task {
                var staging: URL?
                do {
                    let root = try self.libraryDirectory()
                    let destination = root.appendingPathComponent(videoID, isDirectory: true)
                    let temporary = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    staging = temporary
                    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                    let stream = try await self.loadVideoStreamURL(videoID: videoID)
                    let configuration = URLSessionConfiguration.default
                    configuration.timeoutIntervalForRequest = 60
                    configuration.timeoutIntervalForResource = 3600
                    let downloadSession = URLSession(configuration: configuration)
                    defer { downloadSession.finishTasksAndInvalidate() }
                    let (file, response) = try await downloadSession.download(from: stream)
                    defer { try? FileManager.default.removeItem(at: file) }
                    try self.validate(response: response)
                    let asset = AVURLAsset(url: file)
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    let audio = try await asset.loadTracks(withMediaType: .audio)
                    guard !tracks.isEmpty, !audio.isEmpty else { throw YouTubeCaptionError.streamUnavailable }
                    try FileManager.default.moveItem(at: file, to: temporary.appendingPathComponent("video.mp4"))
                    try JSONSerialization.data(withJSONObject: lesson).write(to: temporary.appendingPathComponent("lesson.json"), options: .atomic)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
                    } else {
                        try FileManager.default.moveItem(at: temporary, to: destination)
                    }
                    call.resolve(["videoId": videoID, "path": destination.appendingPathComponent("video.mp4").absoluteString, "lesson": lesson])
                } catch {
                    if let staging { try? FileManager.default.removeItem(at: staging) }
                    call.reject(error.localizedDescription)
                }
                await MainActor.run { self.downloadingVideo = false }
            }
        }
    }

    private var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.edromero.shadowing.gemini", kSecAttrAccount as String: "api-key"]
    }

    private func geminiKey() -> String? {
        var query = keyQuery
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @objc public func aiSettings(_ call: CAPPluginCall) {
        if let key = call.getString("apiKey") {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { call.reject("Informe sua chave Gemini."); return }
            let data = Data(trimmed.utf8)
            var status = SecItemUpdate(keyQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var query = keyQuery
                query[kSecValueData as String] = data
                query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(query as CFDictionary, nil)
            }
            guard status == errSecSuccess else { call.reject("Não foi possível guardar a chave no dispositivo."); return }
        }
        call.resolve(["configured": geminiKey() != nil])
    }

    @objc public func generateLesson(_ call: CAPPluginCall) {
        guard let key = geminiKey(), let prompt = call.getString("prompt"), prompt.count < 100_000 else {
            call.reject("Configure a chave Gemini para preparar a aula.")
            return
        }
        Task {
            do {
                let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 120
                request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                var inputParts: [[String: Any]] = [["text": prompt]]
                if let audio = call.getString("audioBase64"), let mimeType = call.getString("mimeType") {
                    guard audio.count <= 20_000_000, mimeType.hasPrefix("audio/") else {
                        call.reject("Gravação muito grande ou formato de áudio inválido.")
                        return
                    }
                    inputParts.append(["inlineData": ["data": audio, "mimeType": mimeType]])
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "contents": [["parts": inputParts]],
                    "generationConfig": ["responseMimeType": "application/json", "temperature": 0.1]
                ])
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    call.reject("A IA recusou a solicitação. Confira sua chave, conexão e cota Gemini.")
                    return
                }
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let candidates = root?["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else { throw YouTubeCaptionError.invalidResponse }
                call.resolve(["text": parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined()])
            } catch { call.reject("Não foi possível preparar a aula com IA: \(error.localizedDescription)") }
        }
    }

    @objc public func searchVideos(_ call: CAPPluginCall) {
        guard let query = call.getString("query"), !query.isEmpty, query.count < 500 else {
            call.reject("Informe um tema para buscar vídeos.")
            return
        }
        Task {
            do {
                var components = URLComponents(string: "https://www.youtube.com/results")!
                components.queryItems = [URLQueryItem(name: "search_query", value: query), URLQueryItem(name: "hl", value: "en")]
                var request = URLRequest(url: components.url!)
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                try validate(response: response)
                let html = String(decoding: data, as: UTF8.self)
                guard let json = extractJSONObject(after: "var ytInitialData =", in: html),
                      let payload = json.data(using: .utf8) else { throw YouTubeCaptionError.invalidResponse }
                let root = try JSONSerialization.jsonObject(with: payload)
                var videos: [[String: Any]] = []
                var ids = Set<String>()
                func label(_ value: Any?) -> String {
                    guard let text = value as? [String: Any] else { return "" }
                    return text["simpleText"] as? String ?? (text["runs"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
                }
                func visit(_ value: Any) {
                    if let object = value as? [String: Any] {
                        if let renderer = object["videoRenderer"] as? [String: Any],
                           let id = renderer["videoId"] as? String, !ids.contains(id), videos.count < 8 {
                            ids.insert(id)
                            videos.append(["id": id, "title": label(renderer["title"]), "channel": label(renderer["ownerText"]), "thumbnail": "https://i.ytimg.com/vi/\(id)/mqdefault.jpg", "duration": label(renderer["lengthText"])])
                        }
                        for child in object.values { visit(child) }
                    } else if let array = value as? [Any] {
                        for child in array { visit(child) }
                    }
                }
                visit(root)
                call.resolve(["videos": videos])
            } catch { call.reject(error.localizedDescription) }
        }
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        configuration.httpCookieAcceptPolicy = .always
        return URLSession(configuration: configuration)
    }()

    @objc public func fetchTranscript(_ call: CAPPluginCall) {
        guard let videoID = call.getString("videoId"), videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else {
            call.reject(YouTubeCaptionError.invalidVideoID.localizedDescription)
            return
        }

        let preferredLanguage = call.getString("language") ?? "en"
        Task {
            do {
                let payload = try await loadTranscript(videoID: videoID, preferredLanguage: preferredLanguage)
                let segments: [[String: Any]] = payload.segments.map {
                    ["text": $0.text, "start": $0.start, "end": $0.end]
                }
                call.resolve([
                    "segments": segments,
                    "title": payload.title ?? "",
                    "channel": payload.channel ?? "",
                    "languageCode": payload.languageCode ?? "",
                    "source": payload.source
                ])
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc public func mountPlayer(_ call: CAPPluginCall) {
        guard let videoID = call.getString("videoId"), videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else {
            call.reject(YouTubeCaptionError.invalidVideoID.localizedDescription)
            return
        }

        if playerVideoID == videoID, let controller = playerController {
            DispatchQueue.main.async {
                controller.view.frame = self.playerFrame(from: call)
                call.resolve()
            }
            return
        }

        let loadID = UUID()
        playerLoadID = loadID
        Task {
            do {
                let streamURL = try await loadVideoStreamURL(videoID: videoID)
                await MainActor.run {
                    guard self.playerLoadID == loadID else { call.reject("A abertura do vídeo foi cancelada."); return }
                    guard let hostController = self.bridge?.viewController else {
                        call.reject("Não foi possível abrir o player nativo.")
                        return
                    }

                    self.removePlayer()
                    let controller = AVPlayerViewController()
                    controller.player = AVPlayer(url: streamURL)
                    controller.showsPlaybackControls = true
                    controller.videoGravity = .resizeAspect
                    controller.view.frame = self.playerFrame(from: call)
                    controller.view.backgroundColor = .black
                    controller.view.layer.cornerRadius = 16
                    controller.view.clipsToBounds = true

                    hostController.addChild(controller)
                    hostController.view.addSubview(controller.view)
                    controller.didMove(toParent: hostController)

                    self.playerController = controller
                    self.playerVideoID = videoID
                    self.startPlayerStateObservation()
                    self.notifyListeners("playerReady", data: [:])
                    call.resolve()
                }
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc public func updatePlayerFrame(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.playerController?.view.frame = self.playerFrame(from: call)
            call.resolve()
        }
    }

    @objc public func destroyPlayer(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.playerLoadID = UUID()
            self.removePlayer()
            call.resolve()
        }
    }

    @objc public func playVideo(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let player = self.playerController?.player else {
                call.reject("Player nativo indisponível.")
                return
            }
            player.play()
            call.resolve()
        }
    }

    @objc public func pauseVideo(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.playerController?.player?.pause()
            call.resolve()
        }
    }

    @objc public func seekTo(_ call: CAPPluginCall) {
        let time = max(0, call.getDouble("time") ?? 0)
        DispatchQueue.main.async {
            guard let player = self.playerController?.player else {
                call.reject("Player nativo indisponível.")
                return
            }
            let target = CMTime(seconds: time, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in call.resolve() }
        }
    }

    @objc public func getCurrentTime(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let seconds = self.playerController?.player?.currentTime().seconds ?? 0
            call.resolve(["value": seconds.isFinite ? seconds : 0])
        }
    }

    @objc public func getPlayerState(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(["value": self.currentPlayerState()])
        }
    }

    deinit {
        removePlayer()
    }

    private func playerFrame(from call: CAPPluginCall) -> CGRect {
        CGRect(
            x: call.getDouble("x") ?? 0,
            y: call.getDouble("y") ?? 0,
            width: max(1, call.getDouble("width") ?? 1),
            height: max(1, call.getDouble("height") ?? 1)
        )
    }

    private func loadVideoStreamURL(videoID: String) async throws -> URL {
        let player = try await loadAndroidPlayer(videoID: videoID)
        guard let streamingData = player["streamingData"] as? [String: Any],
              let formats = streamingData["formats"] as? [[String: Any]] else {
            throw YouTubeCaptionError.streamUnavailable
        }

        let compatible = formats.filter { format in
            guard let mimeType = format["mimeType"] as? String,
                  mimeType.lowercased().contains("video/mp4"),
                  format["audioQuality"] != nil,
                  format["url"] as? String != nil else { return false }
            return true
        }
        let selected = compatible.first(where: { number($0["itag"]) == 18 })
            ?? compatible.sorted { (number($0["height"]) ?? 0) > (number($1["height"]) ?? 0) }.first
        guard let urlString = selected?["url"] as? String, let url = URL(string: urlString) else {
            throw YouTubeCaptionError.streamUnavailable
        }
        return url
    }

    private func startPlayerStateObservation() {
        guard let player = playerController?.player else { return }
        lastReportedPlayerState = -99
        playerStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let state = self.currentPlayerState()
                self.lastReportedPlayerState = state
                self.notifyListeners("playerState", data: ["state": state])
            }
        }
        playerTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] _ in
            guard let self else { return }
            let state = self.currentPlayerState()
            if state != self.lastReportedPlayerState {
                self.lastReportedPlayerState = state
                self.notifyListeners("playerState", data: ["state": state])
            }
        }
    }

    private func currentPlayerState() -> Int {
        guard let player = playerController?.player else { return -1 }
        if player.currentItem?.status == .failed { return 5 }
        if player.timeControlStatus == .waitingToPlayAtSpecifiedRate { return 3 }
        return player.timeControlStatus == .playing ? 1 : 2
    }

    private func removePlayer() {
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
        if let observer = playerTimeObserver, let player = playerController?.player {
            player.removeTimeObserver(observer)
        }
        playerTimeObserver = nil
        playerController?.player?.pause()
        playerController?.willMove(toParent: nil)
        playerController?.view.removeFromSuperview()
        playerController?.removeFromParent()
        playerController = nil
        playerVideoID = nil
        lastReportedPlayerState = -99
    }

    private func loadTranscript(videoID: String, preferredLanguage: String) async throws -> YouTubeTranscriptPayload {
        var errors: [Error] = []

        do {
            let player = try await loadAndroidPlayer(videoID: videoID)
            return try await transcript(from: player, preferredLanguage: preferredLanguage, source: "youtube-ios-android-player")
        } catch {
            errors.append(error)
        }

        do {
            let player = try await loadWatchPagePlayer(videoID: videoID)
            return try await transcript(from: player, preferredLanguage: preferredLanguage, source: "youtube-ios-watch-page")
        } catch {
            errors.append(error)
        }

        throw errors.last ?? YouTubeCaptionError.captionsUnavailable
    }

    private func loadAndroidPlayer(videoID: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            throw YouTubeCaptionError.invalidResponse
        }

        let clientVersion = "20.10.38"
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "ANDROID",
                    "clientVersion": clientVersion,
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "videoId": videoID
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("com.google.android.youtube/\(clientVersion) (Linux; U; Android 14)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await requestJSONObject(request)
    }

    private func loadWatchPagePlayer(videoID: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)&hl=en") else {
            throw YouTubeCaptionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        guard let html = String(data: data, encoding: .utf8),
              let json = extractJSONObject(after: "ytInitialPlayerResponse", in: html),
              let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw YouTubeCaptionError.invalidResponse
        }
        return object
    }

    private func transcript(from player: [String: Any], preferredLanguage: String, source: String) async throws -> YouTubeTranscriptPayload {
        guard let captions = player["captions"] as? [String: Any],
              let renderer = captions["playerCaptionsTracklistRenderer"] as? [String: Any],
              let tracks = renderer["captionTracks"] as? [[String: Any]],
              let track = pickTrack(tracks, preferredLanguage: preferredLanguage),
              let baseURL = track["baseUrl"] as? String else {
            throw YouTubeCaptionError.captionsUnavailable
        }

        let segments = try await fetchCaptionSegments(baseURL: baseURL)
        guard !segments.isEmpty else { throw YouTubeCaptionError.emptyCaptions }

        let details = player["videoDetails"] as? [String: Any]
        return YouTubeTranscriptPayload(
            segments: segments,
            title: details?["title"] as? String,
            channel: details?["author"] as? String,
            languageCode: track["languageCode"] as? String,
            source: source
        )
    }

    private func pickTrack(_ tracks: [[String: Any]], preferredLanguage: String) -> [String: Any]? {
        let preferred = preferredLanguage.lowercased()
        let matching = tracks.filter { track in
            let languageCode = (track["languageCode"] as? String)?.lowercased() ?? ""
            let vssID = (track["vssId"] as? String)?.lowercased() ?? ""
            let label = trackLabel(track).lowercased()
            return languageCode.hasPrefix(preferred) || vssID.contains(".\(preferred)") || (preferred == "en" && label.contains("english"))
        }
        let candidates = matching.isEmpty ? tracks : matching
        return candidates.first(where: { ($0["kind"] as? String) != "asr" })
            ?? candidates.first(where: { ($0["kind"] as? String) == "asr" })
            ?? candidates.first
    }

    private func trackLabel(_ track: [String: Any]) -> String {
        guard let name = track["name"] as? [String: Any] else { return "" }
        if let simpleText = name["simpleText"] as? String { return simpleText }
        let runs = name["runs"] as? [[String: Any]] ?? []
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    private func fetchCaptionSegments(baseURL: String) async throws -> [YouTubeTranscriptSegment] {
        guard let url = URL(string: baseURL), url.scheme == "https",
              let host = url.host, host == "youtube.com" || host.hasSuffix(".youtube.com") else { throw YouTubeCaptionError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("com.google.android.youtube/20.10.38 (Linux; U; Android 14)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        if let segments = parseJSON3(data), !segments.isEmpty {
            return segments
        }
        if let xml = String(data: data, encoding: .utf8) {
            return parseXMLCaptions(xml)
        }
        throw YouTubeCaptionError.emptyCaptions
    }

    private func parseJSON3(_ data: Data) -> [YouTubeTranscriptSegment]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else {
            return nil
        }

        var raw: [(text: String, start: Double, duration: Double)] = []
        for event in events {
            guard let startMilliseconds = number(event["tStartMs"]),
                  let pieces = event["segs"] as? [[String: Any]] else { continue }
            let text = cleanText(pieces.compactMap { $0["utf8"] as? String }.joined())
            guard !text.isEmpty else { continue }
            raw.append((text, startMilliseconds / 1000, (number(event["dDurationMs"]) ?? 0) / 1000))
        }

        return raw.enumerated().map { index, item in
            let nextStart = index + 1 < raw.count ? raw[index + 1].start : nil
            let estimatedEnd = item.duration > 0 ? item.start + item.duration : (nextStart ?? item.start + 2)
            let end = nextStart.map { min(estimatedEnd, $0) } ?? estimatedEnd
            return YouTubeTranscriptSegment(text: item.text, start: item.start, end: max(end, item.start + 0.35))
        }
    }

    private func parseXMLCaptions(_ xml: String) -> [YouTubeTranscriptSegment] {
        let srv3 = xml.contains("<p ")
        let pattern = srv3 ? #"<p\b([^>]*)>([\s\S]*?)</p>"# : #"<text\b([^>]*)>([\s\S]*?)</text>"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)

        return expression.matches(in: xml, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: xml),
                  let textRange = Range(match.range(at: 2), in: xml) else { return nil }
            let attributes = String(xml[attributesRange])
            let scale = srv3 ? 1000.0 : 1.0
            guard let rawStart = attribute(srv3 ? "t" : "start", in: attributes).flatMap(Double.init) else { return nil }
            let start = rawStart / scale
            let duration = (attribute(srv3 ? "d" : "dur", in: attributes).flatMap(Double.init) ?? (2 * scale)) / scale
            let text = cleanText(String(xml[textRange]))
            guard !text.isEmpty else { return nil }
            return YouTubeTranscriptSegment(text: text, start: start, end: start + max(duration, 0.35))
        }
    }

    private func attribute(_ name: String, in attributes: String) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))=\"([^\"]+)\""
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: attributes, range: NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)),
              let valueRange = Range(match.range(at: 1), in: attributes) else { return nil }
        return String(attributes[valueRange])
    }

    private func cleanText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func requestJSONObject(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YouTubeCaptionError.invalidResponse
        }
        return object
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeCaptionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw YouTubeCaptionError.requestFailed(httpResponse.statusCode)
        }
    }

    private func extractJSONObject(after marker: String, in text: String) -> String? {
        guard let markerRange = text.range(of: marker),
              let start = text[markerRange.upperBound...].firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

@objc(MainViewController)
public class MainViewController: CAPBridgeViewController {
    public override func capacitorDidLoad() {
        bridge?.registerPluginInstance(YouTubeCaptionPlugin())
    }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Called when the app was launched with a url. Feel free to add additional processing here,
        // but if you want the App API to support tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links.
        // Feel free to add additional processing here, but if you want the App API to support
        // tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

}
