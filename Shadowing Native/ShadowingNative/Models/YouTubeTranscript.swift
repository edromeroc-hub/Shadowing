import Foundation

struct YouTubeTranscript: Sendable {
    let videoID: String
    let title: String
    let channel: String
    let languageCode: String
    let source: String
    let segments: [YouTubeTranscriptSegment]
}

struct YouTubeTranscriptSegment: Identifiable, Hashable, Sendable {
    let id = UUID()
    let text: String
    let start: Double
    let end: Double
    var hasWordTiming = false

    var duration: Double { end - start }
}

enum YouTubeLinkParser {
    static func videoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isVideoID(trimmed) { return trimmed }

        let candidate = trimmed.lowercased().hasPrefix("http") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), let host = url.host?.lowercased() else { return nil }

        if host == "youtu.be" || host == "www.youtu.be" {
            return url.pathComponents.first(where: isVideoID)
        }

        if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "v" })?
                .value,
               isVideoID(value) {
                return value
            }

            let parts = url.pathComponents.filter { $0 != "/" }
            if let marker = parts.firstIndex(where: { ["shorts", "embed", "live"].contains($0.lowercased()) }),
               parts.indices.contains(marker + 1),
               isVideoID(parts[marker + 1]) {
                return parts[marker + 1]
            }
        }

        return nil
    }

    static func isShortsURL(_ input: String) -> Bool {
        input.lowercased().contains("youtube.com/shorts/")
    }

    private static func isVideoID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }
}
