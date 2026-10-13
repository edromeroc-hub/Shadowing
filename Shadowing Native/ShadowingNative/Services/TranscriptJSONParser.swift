import Foundation

enum TranscriptJSONParser {
    static func parse(_ data: Data) -> [YouTubeTranscriptSegment] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }
        var segments: [YouTubeTranscriptSegment] = []

        for event in events {
            guard let milliseconds = number(event["tStartMs"]), milliseconds >= 0,
                  let pieces = event["segs"] as? [[String: Any]] else { continue }
            let start = milliseconds / 1000
            let duration = max(0.04, (number(event["dDurationMs"]) ?? 2000) / 1000)
            let hasOffsets = pieces.contains { (number($0["tOffsetMs"]) ?? 0) > 0 }
            var units: [(text: String, start: Double)] = []

            if hasOffsets {
                for piece in pieces {
                    let text = clean(piece["utf8"] as? String ?? "")
                    guard !text.isEmpty else { continue }
                    let offset = max(0, number(piece["tOffsetMs"]) ?? 0) / 1000
                    let unitStart = start + offset
                    if let previous = units.last, unitStart <= previous.start {
                        units[units.count - 1].text += " " + text
                    } else {
                        units.append((text, unitStart))
                    }
                }
            } else {
                let text = clean(pieces.compactMap { $0["utf8"] as? String }.joined())
                if !text.isEmpty { units.append((text, start)) }
            }

            for (index, unit) in units.enumerated() {
                let end = index + 1 < units.count ? units[index + 1].start : max(unit.start + 0.04, start + duration)
                segments.append(YouTubeTranscriptSegment(
                    text: unit.text, start: unit.start, end: end, hasWordTiming: hasOffsets
                ))
            }
        }

        let sorted = segments.sorted { $0.start < $1.start }
        var unique: [YouTubeTranscriptSegment] = []
        for segment in sorted {
            if let previous = unique.last,
               previous.text == segment.text, segment.start < previous.end {
                continue
            }
            unique.append(segment)
        }
        return unique.enumerated().compactMap { index, segment in
            let nextStart = index + 1 < unique.count ? unique[index + 1].start : segment.end
            let end = min(segment.end, nextStart)
            guard end > segment.start else { return nil }
            return YouTubeTranscriptSegment(
                text: segment.text, start: segment.start, end: end, hasWordTiming: segment.hasWordTiming
            )
        }
    }

    private static func number(_ value: Any?) -> Double? {
        let result = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return result.flatMap { $0.isFinite ? $0 : nil }
    }

    private static func clean(_ value: String) -> String {
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
}
