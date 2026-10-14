import Foundation

@main
struct SegmentationLayoutAudit {
    static func main() {
        let longText = "When I started learning English, I thought that listening to a long conversation would be enough, but after a few weeks I realized that I needed to stop, repeat each sentence, notice the words I had missed, and practice speaking at my own pace before trying to follow the entire conversation again without any help from the subtitles on the screen."
        let cases: [(String, [YouTubeTranscriptSegment])] = [
            ("normal", [YouTubeTranscriptSegment(text: "You can take your time, listen again, and learn something new every time you practice with a conversation that interests you.", start: 0, end: 8)]),
            ("long_atomic", [YouTubeTranscriptSegment(text: longText, start: 0, end: 23)]),
            ("dense_atomic", [YouTubeTranscriptSegment(text: longText, start: 0, end: 6)]),
            ("short", [YouTubeTranscriptSegment(text: "How was your day?", start: 0, end: 2)]),
            ("word_timed", [
                YouTubeTranscriptSegment(text: "How was your day?", start: 0, end: 2, hasWordTiming: true),
                YouTubeTranscriptSegment(text: "It was busy but good.", start: 2, end: 4, hasWordTiming: true)
            ])
        ]
        for (name, segments) in cases {
            let transcript = YouTubeTranscript(videoID: "fixture", title: name, channel: "Local audit", languageCode: "en", source: "fixture", segments: segments)
            let phrases = ShadowingLessonBuilder().build(from: transcript)
            let maximumDuration = phrases.map(\.duration).max() ?? 0
            let maximumWords = phrases.map { $0.text.split(whereSeparator: \.isWhitespace).count }.max() ?? 0
            let maximumCharacters = phrases.map { $0.text.count }.max() ?? 0
            let inputWords = segments.flatMap { $0.text.split(whereSeparator: \.isWhitespace) }.count
            let outputWords = phrases.flatMap { $0.text.split(whereSeparator: \.isWhitespace) }.count
            precondition(inputWords == outputWords, "Lost words: \(name)")
            if name == "long_atomic" || name == "dense_atomic" {
                precondition(phrases.count == 1 && phrases[0].needsExpandedPractice)
                precondition(phrases[0].start == segments[0].start && phrases[0].end == segments[0].end)
            }
            print("\(name): phrases=\(phrases.count) maxDuration=\(maximumDuration)s maxWords=\(maximumWords) maxCharacters=\(maximumCharacters) wordsPreserved=\(inputWords == outputWords) expanded=\(phrases.filter(\.needsExpandedPractice).count)")
        }
        let timedWords = longText.split(whereSeparator: \.isWhitespace).enumerated().map { index, word in
            YouTubeTranscriptSegment(text: String(word), start: Double(index) * 0.4, end: Double(index + 1) * 0.4, hasWordTiming: true)
        }
        let limits: [(EnglishLevel, Int, Double, Int)] = [(.beginner, 10, 4.5, 85), (.intermediate, 16, 6.5, 120), (.advanced, 24, 8.5, 165)]
        for (level, words, duration, characters) in limits {
            let transcript = YouTubeTranscript(videoID: "fixture", title: "timed words", channel: "audit", languageCode: "en", source: "fixture", segments: timedWords)
            let phrases = ShadowingLessonBuilder(level: level).build(from: transcript)
            precondition(phrases.map(\.text).joined(separator: " ") == longText)
            precondition(phrases.allSatisfy { !$0.needsExpandedPractice && $0.duration <= duration + 0.001 && $0.text.count <= characters && $0.text.split(whereSeparator: \.isWhitespace).count <= words })
            for (index, phrase) in phrases.enumerated() {
                precondition(timedWords.contains { abs($0.start - phrase.start) < 0.001 })
                precondition(timedWords.contains { abs($0.end - phrase.end) < 0.001 })
                if index > 0 { precondition(phrases[index - 1].end <= phrase.start) }
            }
            print("PASS \(level.rawValue): \(phrases.count) bounded phrases, exact word order and source timestamps")
        }
        print("PASS segmentation regression checks")

        // Fim seguro: pausar antes da palavra seguinte sem cortar a última palavra da frase.
        func words(_ list: [(String, Double)]) -> [YouTubeTranscriptSegment] {
            list.enumerated().map { index, item in
                YouTubeTranscriptSegment(text: item.0, start: item.1, end: index + 1 < list.count ? list[index + 1].1 : item.1 + 0.4, hasWordTiming: true)
            }
        }
        let contiguous = words([("I", 0), ("like", 0.5), ("this", 1.0), ("guy.", 1.5), ("This", 2.0), ("guy's", 2.4)])
        let phrase = ShadowingPhrase(text: "I like this guy.", start: 0, end: 2.0, sourceSegmentCount: 4)
        precondition(PhraseBoundary.playbackEnd(for: phrase, segments: contiguous) == 1.88, "margem antes da palavra seguinte")

        let silence = words([("I", 0), ("like", 0.5), ("this", 1.0), ("guy.", 1.5), ("This", 2.5)])
        let paused = ShadowingPhrase(text: "I like this guy.", start: 0, end: 2.0, sourceSegmentCount: 4)
        precondition(PhraseBoundary.playbackEnd(for: paused, segments: silence) == nil, "com silêncio depois, o fim fica como está")

        let shortLast = words([("I", 0), ("like", 0.5), ("this", 1.0), ("a", 1.9), ("lot", 2.0)])
        let tight = ShadowingPhrase(text: "I like this a", start: 0, end: 2.0, sourceSegmentCount: 4)
        precondition(PhraseBoundary.playbackEnd(for: tight, segments: shortLast) == 1.96, "última palavra curta usa a margem mínima")

        let lastPhrase = ShadowingPhrase(text: "This guy's", start: 2.0, end: 2.8, sourceSegmentCount: 2)
        precondition(PhraseBoundary.playbackEnd(for: lastPhrase, segments: contiguous) == nil, "sem palavra seguinte, sem ajuste")

        let built = PhraseBoundary.applyingPlaybackEnds(to: [phrase, lastPhrase], segments: contiguous)
        precondition(built.map(\.text) == [phrase.text, lastPhrase.text] && built.allSatisfy { ($0.playbackEnd ?? $0.end) <= $0.end && ($0.playbackEnd ?? $0.end) > $0.start })
        precondition([("cat", 1), ("water", 2), ("beautiful", 3), ("make", 1), ("table", 2), ("rhythm", 1)].allSatisfy { PhraseBoundary.syllables($0.0) == $0.1 })

        let timedTranscript = YouTubeTranscript(videoID: "fixture", title: "timed words", channel: "audit", languageCode: "en", source: "fixture", segments: timedWords)
        let builderPhrases = ShadowingLessonBuilder(level: .intermediate).build(from: timedTranscript)
        precondition(builderPhrases.dropLast().allSatisfy { $0.playbackEnd != nil && $0.playbackEnd! < $0.end }, "frases da lupa também recebem o fim seguro")
        print("PASS playback end keeps a margin before the next word without cutting the last one")
    }
}
