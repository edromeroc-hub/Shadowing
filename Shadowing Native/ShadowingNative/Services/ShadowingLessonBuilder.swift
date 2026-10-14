import Foundation

struct ShadowingLessonBuilder: Sendable {
    private let maximumDuration: Double
    private let preferredMaximumDuration: Double
    private let maximumCharacters: Int
    private let maximumWords: Int
    private let minimumDuration = 1.35
    private let minimumWords = 4
    private let maximumGap = 1.15

    init(level: EnglishLevel = .advanced) {
        switch level {
        case .beginner:
            maximumDuration = 4.5
            preferredMaximumDuration = 3.5
            maximumCharacters = 85
            maximumWords = 10
        case .intermediate:
            maximumDuration = 6.5
            preferredMaximumDuration = 5
            maximumCharacters = 120
            maximumWords = 16
        case .advanced:
            maximumDuration = 8.5
            preferredMaximumDuration = 6.5
            maximumCharacters = 165
            maximumWords = 24
        }
    }

    func build(from transcript: YouTubeTranscript) -> [ShadowingPhrase] {
        let normalized = normalize(transcript.segments)
        guard !normalized.isEmpty else { return [] }

        var groups: [PhraseGroup] = []
        var current: PhraseGroup?

        for segment in normalized {
            guard var group = current else {
                current = PhraseGroup(segment)
                continue
            }

            if shouldMerge(group, with: segment) {
                group.append(segment)
                current = group
            } else {
                groups.append(group)
                current = PhraseGroup(segment)
            }
        }

        if let current { groups.append(current) }
        groups = repairTightBoundaries(repairShortGroups(groups))

        let phrases = groups.enumerated().compactMap { index, group -> ShadowingPhrase? in
            guard !group.text.isEmpty else { return nil }
            let nextGroup = index + 1 < groups.count ? groups[index + 1] : nil
            let nextStart = nextGroup?.start
            let start = group.start
            let end = min(nextStart ?? group.end, group.end)

            guard end > start else { return nil }
            return ShadowingPhrase(
                text: group.text,
                start: rounded(start),
                end: rounded(end),
                sourceSegmentCount: group.segmentCount,
                needsExpandedPractice: !fits(text: group.text, duration: end - start),
                endingHasWordTiming: group.lastSegmentHasWordTiming
            )
        }
        return PhraseBoundary.applyingPlaybackEnds(to: phrases, segments: normalized)
    }

    private func fits(text: String, duration: Double) -> Bool {
        duration <= maximumDuration && text.count <= maximumCharacters && wordCount(text) <= maximumWords
    }

    private func shouldMerge(_ group: PhraseGroup, with segment: YouTubeTranscriptSegment) -> Bool {
        let gap = segment.start - group.end
        let combinedText = join(group.text, segment.text)
        let combinedDuration = segment.end - group.start

        guard gap <= maximumGap,
              fits(text: combinedText, duration: combinedDuration) else {
            return false
        }

        if gap >= 0.4, !isTooShort(group) { return false }
        if isIncomplete(group.text) { return true }
        if isTooShort(group) { return true }
        if isFiller(group.text) { return true }

        return combinedDuration < preferredMaximumDuration && endsWithSoftPause(group.text)
    }

    private func repairShortGroups(_ groups: [PhraseGroup]) -> [PhraseGroup] {
        var result: [PhraseGroup] = []

        for group in groups {
            guard let previous = result.last else {
                result.append(group)
                continue
            }

            let combinedText = join(previous.text, group.text)
            let combinedDuration = group.end - previous.start
            let canMerge = fits(text: combinedText, duration: combinedDuration)
                && group.start - previous.end <= 1.6

            if canMerge && (isTooShort(previous) || isTooShort(group) || isFiller(group.text)) {
                result[result.count - 1] = previous.merged(with: group)
            } else {
                result.append(group)
            }
        }

        if result.count > 1, let last = result.last, isTooShort(last) {
            let previous = result[result.count - 2]
            let combinedDuration = last.end - previous.start
            let combinedText = join(previous.text, last.text)
            if fits(text: combinedText, duration: combinedDuration) {
                result.removeLast(2)
                result.append(previous.merged(with: last))
            }
        }

        return repairOrphans(result)
    }

    private func repairTightBoundaries(_ groups: [PhraseGroup]) -> [PhraseGroup] {
        var result: [PhraseGroup] = []

        for group in groups {
            guard let previous = result.last,
                  previous.lastSegmentHasWordTiming,
                  group.firstSegmentHasWordTiming,
                  group.start - previous.end < 0.08,
                  isIncomplete(previous.text),
                  group.end - previous.start <= preferredMaximumDuration,
                  fits(text: join(previous.text, group.text), duration: group.end - previous.start) else {
                result.append(group)
                continue
            }

            result[result.count - 1] = previous.merged(with: group)
        }

        return result
    }

    private func repairOrphans(_ groups: [PhraseGroup]) -> [PhraseGroup] {
        var repaired: [PhraseGroup] = []
        var index = 0

        while index < groups.count {
            let group = groups[index]
            let hasNext = index + 1 < groups.count

            if isTooShort(group), hasNext {
                let next = groups[index + 1]
                let combinedDuration = next.end - group.start
                let combinedText = join(group.text, next.text)
                let canMergeForward = fits(text: combinedText, duration: combinedDuration)
                    && next.start - group.end <= 2.5

                if canMergeForward {
                    repaired.append(group.merged(with: next))
                    index += 2
                    continue
                }
            }

            repaired.append(group)
            index += 1
        }

        return repaired
    }

    private func normalize(_ segments: [YouTubeTranscriptSegment]) -> [YouTubeTranscriptSegment] {
        let cleaned = segments.compactMap { segment -> YouTubeTranscriptSegment? in
            let text = clean(segment.text)
            guard !text.isEmpty,
                  segment.start.isFinite,
                  segment.end.isFinite,
                  segment.end > segment.start else { return nil }
            return YouTubeTranscriptSegment(
                text: text,
                start: rounded(segment.start),
                end: rounded(segment.end),
                hasWordTiming: segment.hasWordTiming
            )
        }
        .sorted { $0.start < $1.start }

        return cleaned.enumerated().map { index, segment in
            let nextStart = index + 1 < cleaned.count ? cleaned[index + 1].start : nil
            let end: Double
            if let nextStart, nextStart > segment.start {
                end = min(segment.end, nextStart)
            } else {
                end = segment.end
            }
            return YouTubeTranscriptSegment(
                text: segment.text,
                start: segment.start,
                end: end,
                hasWordTiming: segment.hasWordTiming
            )
        }
    }

    private func isTooShort(_ group: PhraseGroup) -> Bool {
        wordCount(group.text) < minimumWords || group.duration < minimumDuration
    }

    private func isFiller(_ text: String) -> Bool {
        let pattern = "^(ok(?:ay)?|yeah|yes|no|right|well|so|uh|um|hmm|all right|you know)[,.!? ]*$"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func isIncomplete(_ text: String) -> Bool {
        guard let last = text.last else { return true }
        return !".!?".contains(last)
    }

    private func endsWithSoftPause(_ text: String) -> Bool {
        text.range(of: "[,;:][\"')\\]]?$", options: .regularExpression) != nil
    }

    private func wordCount(_ text: String) -> Int {
        text
            .replacingOccurrences(of: "[^\\p{L}\\p{N}'-]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .count
    }

    private func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\[[^\\]]+\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func join(_ first: String, _ second: String) -> String {
        "\(first) \(second)"
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }
}

private struct PhraseGroup: Sendable {
    var text: String
    var start: Double
    var end: Double
    var segmentCount: Int
    var firstSegmentHasWordTiming: Bool
    var lastSegmentHasWordTiming: Bool
    var lastSegmentStart: Double

    init(_ segment: YouTubeTranscriptSegment) {
        text = segment.text
        start = segment.start
        end = segment.end
        segmentCount = 1
        firstSegmentHasWordTiming = segment.hasWordTiming
        lastSegmentHasWordTiming = segment.hasWordTiming
        lastSegmentStart = segment.start
    }

    var duration: Double { end - start }

    mutating func append(_ segment: YouTubeTranscriptSegment) {
        text = "\(text) \(segment.text)"
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        end = segment.end
        segmentCount += 1
        lastSegmentHasWordTiming = segment.hasWordTiming
        lastSegmentStart = segment.start
    }

    func merged(with other: PhraseGroup) -> PhraseGroup {
        PhraseGroup(
            text: "\(text) \(other.text)"
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            start: start,
            end: other.end,
            segmentCount: segmentCount + other.segmentCount,
            firstSegmentHasWordTiming: firstSegmentHasWordTiming,
            lastSegmentHasWordTiming: other.lastSegmentHasWordTiming,
            lastSegmentStart: other.lastSegmentStart
        )
    }

    private init(
        text: String,
        start: Double,
        end: Double,
        segmentCount: Int,
        firstSegmentHasWordTiming: Bool,
        lastSegmentHasWordTiming: Bool,
        lastSegmentStart: Double
    ) {
        self.text = text
        self.start = start
        self.end = end
        self.segmentCount = segmentCount
        self.firstSegmentHasWordTiming = firstSegmentHasWordTiming
        self.lastSegmentHasWordTiming = lastSegmentHasWordTiming
        self.lastSegmentStart = lastSegmentStart
    }
}
