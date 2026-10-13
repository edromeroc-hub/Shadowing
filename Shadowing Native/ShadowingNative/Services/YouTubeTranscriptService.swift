import Foundation

actor YouTubeTranscriptService {
    static let shared = YouTubeTranscriptService()

    private let session: URLSession
    private var cache: [String: (savedAt: Date, transcript: YouTubeTranscript)] = [:]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        configuration.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: configuration)
    }

    func fetchTranscript(videoID: String, preferredLanguage: String = "en") async throws -> YouTubeTranscript {
        try Task.checkCancellation()
        let cacheKey = "\(videoID)|\(preferredLanguage)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.savedAt) < 3600 {
            return cached.transcript
        }
        var lastError: Error = TranscriptError.captionsUnavailable

        do {
            let player = try await loadAndroidPlayer(videoID: videoID)
            let result = try await transcript(
                from: player,
                videoID: videoID,
                preferredLanguage: preferredLanguage,
                source: "youtube-android-player"
            )
            remember(result, key: cacheKey)
            return result
        } catch {
            try Task.checkCancellation()
            lastError = error
        }

        do {
            let player = try await loadWatchPagePlayer(videoID: videoID)
            let result = try await transcript(
                from: player,
                videoID: videoID,
                preferredLanguage: preferredLanguage,
                source: "youtube-watch-page"
            )
            remember(result, key: cacheKey)
            return result
        } catch {
            try Task.checkCancellation()
            // Se a primeira estratégia levou 429, esse é o motivo real; não mascarar com o erro da página.
            if case TranscriptError.requestFailed(429) = lastError {} else { lastError = error }
        }

        throw lastError
    }

    private func remember(_ transcript: YouTubeTranscript, key: String) {
        if cache.count >= 60, let oldest = cache.min(by: { $0.value.savedAt < $1.value.savedAt })?.key {
            cache.removeValue(forKey: oldest)
        }
        cache[key] = (Date(), transcript)
    }

    private func loadAndroidPlayer(videoID: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            throw TranscriptError.invalidResponse
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
        request.setValue("3", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validate(response)

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptError.invalidResponse
        }
        return object
    }

    private func loadWatchPagePlayer(videoID: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)&hl=en") else {
            throw TranscriptError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        guard let html = String(data: data, encoding: .utf8),
              let json = extractJSONObject(after: "ytInitialPlayerResponse", in: html),
              let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw TranscriptError.invalidResponse
        }
        return object
    }

    private func transcript(
        from player: [String: Any],
        videoID: String,
        preferredLanguage: String,
        source: String
    ) async throws -> YouTubeTranscript {
        guard let captions = player["captions"] as? [String: Any],
              let renderer = captions["playerCaptionsTracklistRenderer"] as? [String: Any],
              let tracks = renderer["captionTracks"] as? [[String: Any]] else {
            throw TranscriptError.captionsUnavailable
        }

        let candidates = matchingTracks(tracks, preferredLanguage: preferredLanguage)
        var selected: (track: [String: Any], segments: [YouTubeTranscriptSegment])?
        var lastError: Error = TranscriptError.captionsUnavailable
        for track in candidates.prefix(3) {
            try Task.checkCancellation()
            guard let baseURL = track["baseUrl"] as? String else { continue }
            do {
                let segments = try await fetchSegments(baseURL: baseURL)
                guard !segments.isEmpty else { continue }
                if segments.contains(where: \.hasWordTiming) {
                    selected = (track, segments)
                    break
                }
                if selected == nil || (track["kind"] as? String) != "asr" {
                    selected = (track, segments)
                }
            } catch {
                try Task.checkCancellation()
                lastError = error
            }
        }
        guard let selected else { throw lastError }

        let details = player["videoDetails"] as? [String: Any]
        return YouTubeTranscript(
            videoID: videoID,
            title: details?["title"] as? String ?? "Vídeo do YouTube",
            channel: details?["author"] as? String ?? "YouTube",
            languageCode: selected.track["languageCode"] as? String ?? preferredLanguage,
            source: source,
            segments: selected.segments
        )
    }

    private func matchingTracks(_ tracks: [[String: Any]], preferredLanguage: String) -> [[String: Any]] {
        let preferred = preferredLanguage.lowercased()
        let matching = tracks.filter { track in
            let languageCode = (track["languageCode"] as? String)?.lowercased() ?? ""
            let vssID = (track["vssId"] as? String)?.lowercased() ?? ""
            let label = trackLabel(track).lowercased()
            return languageCode.hasPrefix(preferred)
                || vssID.contains(".\(preferred)")
                || (preferred == "en" && label.contains("english"))
        }
        return matching.filter { ($0["kind"] as? String) == "asr" }
            + matching.filter { ($0["kind"] as? String) != "asr" }
    }

    private func trackLabel(_ track: [String: Any]) -> String {
        guard let name = track["name"] as? [String: Any] else { return "" }
        if let simpleText = name["simpleText"] as? String { return simpleText }
        let runs = name["runs"] as? [[String: Any]] ?? []
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    private func fetchSegments(baseURL: String) async throws -> [YouTubeTranscriptSegment] {
        guard var components = URLComponents(string: baseURL),
              components.scheme == "https",
              let host = components.host,
              host == "youtube.com" || host.hasSuffix(".youtube.com") else {
            throw TranscriptError.invalidResponse
        }

        var queryItems = (components.queryItems ?? []).filter { $0.name != "fmt" }
        queryItems.append(URLQueryItem(name: "fmt", value: "json3"))
        components.queryItems = queryItems

        guard let url = components.url else { throw TranscriptError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(Self.mobileUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        let jsonSegments = TranscriptJSONParser.parse(data)
        if !jsonSegments.isEmpty { return jsonSegments }

        if let xml = String(data: data, encoding: .utf8) {
            let xmlSegments = parseXML(xml)
            if !xmlSegments.isEmpty { return xmlSegments }
        }

        throw TranscriptError.emptyCaptions
    }

    private func parseXML(_ xml: String) -> [YouTubeTranscriptSegment] {
        let usesMilliseconds = xml.contains("<p ")
        let pattern = usesMilliseconds ? #"<p\b([^>]*)>([\s\S]*?)</p>"# : #"<text\b([^>]*)>([\s\S]*?)</text>"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)

        return expression.matches(in: xml, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: xml),
                  let textRange = Range(match.range(at: 2), in: xml) else { return nil }

            let attributes = String(xml[attributesRange])
            let scale = usesMilliseconds ? 1000.0 : 1.0
            guard let rawStart = attribute(usesMilliseconds ? "t" : "start", in: attributes).flatMap(Double.init) else {
                return nil
            }

            let start = rawStart / scale
            let rawDuration = attribute(usesMilliseconds ? "d" : "dur", in: attributes).flatMap(Double.init) ?? (2 * scale)
            let text = cleanText(String(xml[textRange]))
            guard !text.isEmpty else { return nil }
            return YouTubeTranscriptSegment(text: text, start: start, end: start + max(rawDuration / scale, 0.35))
        }
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw TranscriptError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw TranscriptError.requestFailed(http.statusCode) }
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
                if depth == 0 { return String(text[start...index]) }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func attribute(_ name: String, in attributes: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        guard let expression = try? NSRegularExpression(pattern: "\\b\(escapedName)=\"([^\"]+)\""),
              let match = expression.firstMatch(
                in: attributes,
                range: NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
              ),
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

    private static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 Version/27.0 Mobile/15E148 Safari/604.1"
}

enum TranscriptError: LocalizedError {
    case invalidResponse
    case requestFailed(Int)
    case captionsUnavailable
    case emptyCaptions

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "O YouTube retornou uma resposta que o app ainda não reconhece."
        case .requestFailed(let statusCode):
            "O YouTube recusou a legenda (código \(statusCode))."
        case .captionsUnavailable:
            "Este vídeo não expôs uma faixa de legenda acessível."
        case .emptyCaptions:
            "A faixa foi encontrada, mas chegou vazia."
        }
    }
}
