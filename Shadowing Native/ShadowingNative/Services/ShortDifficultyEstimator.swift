import Foundation

struct ShortDifficultyEstimator {
    static func estimate(transcript: YouTubeTranscript, titleHint: String? = nil) -> EnglishLevel? {
        guard let first = transcript.segments.first, let last = transcript.segments.last else { return nil }
        let duration = last.end - first.start
        guard (12...185).contains(duration) else { return nil }

        let words = transcript.segments
            .flatMap { $0.text.split(whereSeparator: { !$0.isLetter && $0 != "'" }) }
            .map(String.init)
            .filter { !$0.isEmpty }
        guard words.count >= 30 else { return nil }

        let wordsPerMinute = Double(words.count) * 60 / duration
        guard wordsPerMinute < 270 else { return nil }
        let longWordShare = Double(words.filter { $0.count >= 8 }.count) / Double(words.count)
        let phrases = ShadowingLessonBuilder().build(from: transcript)
        let phraseLengths = phrases.map {
            $0.text.split(whereSeparator: { !$0.isLetter && $0 != "'" }).count
        }
        let typicalPhraseLength = phraseLengths.sorted().dropFirst(phraseLengths.count / 2).first ?? words.count
        let fastestPhrase = zip(phrases, phraseLengths)
            .filter { $0.1 >= 8 && $0.0.duration >= 2 }
            .map { Double($0.1) * 60 / $0.0.duration }
            .max() ?? wordsPerMinute

        let title = (titleHint ?? transcript.title).lowercased()
        let declaresAdvanced = title.range(of: #"\b(c1|c2|advanced english|english advanced)\b"#, options: .regularExpression) != nil
        let declaresIntermediate = title.range(of: #"\b(b1|b2|intermediate english|english intermediate)\b"#, options: .regularExpression) != nil

        if declaresAdvanced || wordsPerMinute >= 165 || longWordShare >= 0.22 ||
            fastestPhrase >= 190 || (wordsPerMinute >= 140 && longWordShare >= 0.14) {
            return .advanced
        }
        if !declaresIntermediate && wordsPerMinute <= 105 && fastestPhrase <= 130 && longWordShare <= 0.07 && typicalPhraseLength <= 12 {
            return .beginner
        }
        return .intermediate
    }
}
