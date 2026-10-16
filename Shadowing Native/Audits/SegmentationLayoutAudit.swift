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
        precondition(abs(RepeatPauseTiming.duration(start: 0, end: 1.5, playbackRate: 1, extraPercent: 30) - 1.95) < 0.001)
        precondition(RepeatPauseTiming.duration(start: 0, end: 2, playbackRate: 1, extraPercent: 0) == 2)
        precondition(RepeatPauseTiming.duration(start: 0, end: 2, playbackRate: 1, extraPercent: 100) == 4)
        precondition(abs(RepeatPauseTiming.duration(start: 1, end: 3, playbackRate: 0.5, extraPercent: 30) - 5.2) < 0.001)
        precondition(RepeatPauseTiming.duration(start: 0, end: 0.1, playbackRate: 1, extraPercent: 30) == 0.8)
        precondition(RepeatPauseTiming.duration(start: 2, end: 1, playbackRate: 1, extraPercent: 30) == 0.8)
        let encoded = try! JSONEncoder().encode(LearningProfile.starter)
        var legacy = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "repeatPauseExtraPercent")
        let legacyProfile = try! JSONDecoder().decode(LearningProfile.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(legacyProfile.repeatPauseExtraPercent == 30)
        for invalid in [-10, 200, 35, "invalid"] as [Any] {
            legacy["repeatPauseExtraPercent"] = invalid
            let decoded = try! JSONDecoder().decode(LearningProfile.self, from: JSONSerialization.data(withJSONObject: legacy))
            precondition(decoded.repeatPauseExtraPercent == 30)
        }
        var savedProfile = LearningProfile.starter
        savedProfile.repeatPauseExtraPercent = 80
        precondition(savedProfile.hasSameRecommendationPreferences(as: .starter))
        var changedLevel = savedProfile
        changedLevel.level = .advanced
        precondition(!savedProfile.hasSameRecommendationPreferences(as: changedLevel))
        let decodedProfile = try! JSONDecoder().decode(LearningProfile.self, from: JSONEncoder().encode(savedProfile))
        precondition(decodedProfile.repeatPauseExtraPercent == 80)
        print("PASS repeat pause duration, playback speed, minimum time, legacy profiles and saved preferences")

        let blanks = [
            ListeningBlank(tokenIndex: 0, answer: "Guess", choices: ["Guess", "Ask", "Turn", "Stay"]),
            ListeningBlank(tokenIndex: 2, answer: "big", choices: ["big", "small", "near", "far"]),
            ListeningBlank(tokenIndex: 4, answer: "really", choices: ["really", "usually", "never", "always"])
        ]
        var listening = ListeningExerciseProgress()
        precondition(listening.submit("Ask", for: blanks[0]) == false)
        precondition(listening.solvedAnswers.isEmpty && listening.attempts == 1)
        precondition(listening.submit("Ask", for: blanks[0]) == nil && listening.attempts == 1)
        precondition(listening.submit("invalid", for: blanks[0]) == nil && listening.attempts == 1)
        precondition(listening.submit("Guess", for: blanks[0]) == true)
        precondition(listening.submit("Guess", for: blanks[0]) == nil && listening.attempts == 2)
        precondition(listening.submit("small", for: blanks[1]) == false)
        precondition(listening.submit("big", for: blanks[1]) == true)
        precondition(listening.submit("really", for: blanks[2]) == true)
        precondition(listening.solvedAnswers.count == 3 && listening.attempts == 5)
        let exerciseBuilder = ActiveListeningExerciseBuilder()
        let punctuated = ShadowingPhrase(text: "Guess how big Antarctica really is, really!", start: 0, end: 4, sourceSegmentCount: 7)
        for count in 1...5 {
            let exercise = exerciseBuilder.build(phrase: punctuated, phraseIndex: 0, lessonPhrases: [punctuated], level: .intermediate, blankCount: count)!
            precondition(exercise.tokens.joined(separator: " ") == punctuated.text)
            precondition(exercise.tokens.count == exercise.maskedTokens.count)
            precondition(exercise.blanks.count == min(count, exerciseBuilder.eligibleWordCount(in: punctuated.text)))
            precondition(Set(exercise.blanks.map(\.tokenIndex)).count == exercise.blanks.count)
        }
        listening = ListeningExerciseProgress()
        precondition(listening.attempts == 0 && listening.solvedAnswers.isEmpty && listening.rejectedChoices.isEmpty)
        print("PASS retry after errors, rejected-choice deduplication, single success per blank, punctuation and repeated-word positions")

        for height: CGFloat in [390, 460, 650, 900] {
            let chrome: CGFloat = height < 500 ? 115 : 165
            let layout = ShortPracticeLayout(height: height, width: 360, headerHeight: 48, panelChromeHeight: chrome, desiredContentHeight: 85, editing: height < 500)
            precondition(layout.videoHeight >= 96 && layout.contentHeight >= 60)
            precondition(layout.videoHeight + layout.contentHeight + 48 + chrome + 27 <= height + 0.001)
        }
        print("PASS Shorts keyboard layout retains visible video, answer field and controls within the usable screen")
        for width: CGFloat in [320, 390, 768] {
            let availableVideoWidth = width - 114
            let layout = ShortPracticeLayout(height: 650, width: availableVideoWidth, headerHeight: 24, panelChromeHeight: 165, desiredContentHeight: 85, editing: false)
            precondition(layout.videoHeight * 9 / 16 <= availableVideoWidth + 0.001)
            precondition(layout.videoHeight + layout.contentHeight + 24 + 165 + 27 <= 650.001)
        }
        print("PASS compact Shorts header and external action rail fit small iPhone, iPhone and iPad widths")
    }
}
