import Foundation

struct ShadowingPhrase: Identifiable, Hashable, Sendable {
    let id = UUID()
    let text: String
    let start: Double
    let end: Double
    let sourceSegmentCount: Int
    var needsExpandedPractice = false
    var endingHasWordTiming = false
    /// Onde o player deve pausar. Fica antes de `end` quando a próxima palavra começa colada ao fim da frase.
    var playbackEnd: Double? = nil

    var duration: Double { end - start }
}

/// A legenda automática do YouTube só marca o início de cada palavra, então o fim de uma frase costuma ser
/// exatamente o início da palavra seguinte (96% das frases do catálogo). Como o player sempre pausa um pouco
/// depois do pedido, pausar em `end` deixa vazar o começo dessa palavra. Este cálculo recua o ponto de pausa
/// sem cortar a última palavra da frase.
enum PhraseBoundary {
    /// Distância mantida antes do início da palavra seguinte.
    static let nextWordMargin = 0.12
    /// Margem mínima aceita quando a última palavra é curta demais para a margem cheia.
    static let tightMargin = 0.04

    static func applyingPlaybackEnds(to phrases: [ShadowingPhrase], segments: [YouTubeTranscriptSegment]) -> [ShadowingPhrase] {
        let ordered = segments.sorted { $0.start < $1.start }
        return phrases.map { phrase in
            var phrase = phrase
            phrase.playbackEnd = playbackEnd(for: phrase, segments: ordered)
            return phrase
        }
    }

    static func playbackEnd(for phrase: ShadowingPhrase, segments ordered: [YouTubeTranscriptSegment]) -> Double? {
        let tolerance = 0.005
        guard let next = ordered.first(where: { $0.start >= phrase.end - tolerance && $0.start > phrase.start + tolerance }) else {
            return nil
        }
        let gapToNext = next.start - phrase.end
        guard gapToNext < nextWordMargin else { return nil }
        let last = ordered.last { $0.start >= phrase.start - tolerance && $0.start < phrase.end - tolerance }
        let lastStart = last?.start ?? phrase.start
        let lastWord = last?.text.split(separator: " ").last.map(String.init) ?? ""
        // A última palavra precisa de pelo menos esse tempo para ser ouvida inteira.
        let minimumEnd = lastStart + max(0.18, Double(syllables(lastWord)) * 0.11)
        let comfortable = next.start - nextWordMargin
        let tight = next.start - tightMargin
        let end = comfortable >= minimumEnd ? comfortable : min(minimumEnd, tight)
        guard end > phrase.start + 0.1 else { return nil }
        return min(phrase.end, (end * 1000).rounded() / 1000)
    }

    static func syllables(_ word: String) -> Int {
        let letters = word.lowercased().filter { $0.isASCII && $0.isLetter }
        guard !letters.isEmpty else { return 0 }
        var groups = 0
        var previousWasVowel = false
        for character in letters {
            let isVowel = "aeiouy".contains(character)
            if isVowel && !previousWasVowel { groups += 1 }
            previousWasVowel = isVowel
        }
        let silentE = letters.count > 2 && letters.hasSuffix("e") && !letters.hasSuffix("le") && groups > 1 ? 1 : 0
        return max(1, max(groups, 1) - silentE)
    }
}

enum ExerciseMode: String, CaseIterable, Identifiable, Sendable {
    case shadowing
    case multipleChoice
    case typing

    var id: String { rawValue }

    var isActiveListening: Bool { self != .shadowing }

}

struct ListeningBlank: Identifiable, Hashable, Sendable {
    let tokenIndex: Int
    let answer: String
    let choices: [String]

    var id: Int { tokenIndex }

    func accepts(_ response: String) -> Bool {
        ActiveListeningExercise.normalize(response) == ActiveListeningExercise.normalize(answer)
    }
}

struct ActiveListeningExercise: Identifiable, Hashable, Sendable {
    let id: String
    let maskedText: String
    let blanks: [ListeningBlank]
    let tokens: [String]

    var maskedTokens: [String] { maskedText.split(whereSeparator: \.isWhitespace).map(String.init) }

    static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}']", with: "", options: .regularExpression)
            .lowercased()
    }
}

struct ListeningExerciseProgress: Equatable, Sendable {
    private(set) var solvedAnswers: [Int: String] = [:]
    private(set) var rejectedChoices: [Int: Set<String>] = [:]
    private(set) var attempts = 0

    mutating func submit(_ response: String, for blank: ListeningBlank) -> Bool? {
        guard solvedAnswers[blank.tokenIndex] == nil,
              blank.choices.contains(response),
              rejectedChoices[blank.tokenIndex]?.contains(response) != true else { return nil }
        attempts += 1
        let correct = blank.accepts(response)
        if correct {
            solvedAnswers[blank.tokenIndex] = response
        } else {
            rejectedChoices[blank.tokenIndex, default: []].insert(response)
        }
        return correct
    }
}

enum RepeatPauseTiming {
    static func duration(start: Double, end: Double, playbackRate: Double, extraPercent: Int) -> Double {
        let extra = Double(min(100, max(0, extraPercent))) / 100
        return max(0.8, max(0, end - start) / max(0.25, playbackRate) * (1 + extra))
    }
}

struct ShortPracticeLayout {
    let videoHeight: CGFloat
    let contentHeight: CGFloat

    init(height: CGFloat, width: CGFloat, headerHeight: CGFloat, panelChromeHeight: CGFloat, desiredContentHeight: CGFloat, editing: Bool) {
        let available = max(1, height - headerHeight - panelChromeHeight - 27)
        let desired = editing ? min(desiredContentHeight, 110) : min(desiredContentHeight, height * 0.43)
        let minimumVideo = min(editing ? 96 : 120, max(1, available - 60))
        contentHeight = max(1, min(max(60, desired), max(1, available - minimumVideo)))
        videoHeight = max(1, min(width * 16 / 9, available - contentHeight))
    }
}

struct ActiveListeningExerciseBuilder: Sendable {
    private struct Candidate: Hashable {
        let tokenIndex: Int
        let display: String
        let normalized: String
    }

    private let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "do", "does", "did",
        "for", "from", "had", "has", "have", "he", "her", "hers", "him", "his", "how", "i",
        "if", "in", "is", "it", "its", "me", "my", "of", "on", "or", "our", "ours", "she",
        "so", "that", "the", "their", "them", "they", "this", "to", "us", "was", "we", "were",
        "what", "when", "where", "which", "who", "why", "will", "with", "would", "you", "your"
    ]

    func eligibleWordCount(in text: String) -> Int {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let preferred = candidates(in: tokens, excludesLikelyNames: true)
        return preferred.isEmpty ? candidates(in: tokens, excludesLikelyNames: false).count : preferred.count
    }

    func build(
        phrase: ShadowingPhrase,
        phraseIndex: Int,
        lessonPhrases: [ShadowingPhrase],
        level: EnglishLevel,
        difficultWords: Set<String> = [],
        blankCount: Int = 1
    ) -> ActiveListeningExercise? {
        let tokens = phrase.text.split(whereSeparator: \.isWhitespace).map(String.init)
        let preferredCandidates = candidates(in: tokens, excludesLikelyNames: true)
        let availableCandidates = preferredCandidates.isEmpty
            ? candidates(in: tokens, excludesLikelyNames: false)
            : preferredCandidates
        guard !availableCandidates.isEmpty else { return nil }

        let seed = phraseIndex + Int((phrase.start * 10).rounded())
        let reviewCandidates = availableCandidates.filter { difficultWords.contains($0.normalized) }
        let selectionPool = reviewCandidates + availableCandidates.filter { !reviewCandidates.contains($0) }
        let count = min(max(blankCount, 1), 5, selectionPool.count)
        let selected = (0..<count).map { selectionPool[positiveModulo(seed + $0, selectionPool.count)] }
            .sorted { $0.tokenIndex < $1.tokenIndex }
        var maskedTokens = tokens
        for target in selected {
            maskedTokens[target.tokenIndex] = mask(target: target, in: tokens)[target.tokenIndex]
        }
        let blanks = selected.enumerated().map { index, target in
            ListeningBlank(
                tokenIndex: target.tokenIndex,
                answer: target.display,
                choices: makeChoices(answer: target.display, lessonPhrases: lessonPhrases, seed: seed + index, level: level)
            )
        }

        return ActiveListeningExercise(
            id: "\(phrase.id.uuidString)|\(blanks.map(\.tokenIndex))",
            maskedText: maskedTokens.joined(separator: " "),
            blanks: blanks,
            tokens: tokens
        )
    }

    private func candidates(in tokens: [String], excludesLikelyNames: Bool) -> [Candidate] {
        tokens.enumerated().compactMap { index, token in
            let display = strippedWord(token)
            let normalized = ActiveListeningExercise.normalize(display)
            guard normalized.count >= 3, !stopWords.contains(normalized) else { return nil }
            if excludesLikelyNames, index > 0, display.first?.isUppercase == true {
                return nil
            }
            return Candidate(tokenIndex: index, display: display, normalized: normalized)
        }
    }

    private func makeChoices(
        answer: String,
        lessonPhrases: [ShadowingPhrase],
        seed: Int,
        level: EnglishLevel
    ) -> [String] {
        let normalizedAnswer = ActiveListeningExercise.normalize(answer)
        let lessonWords = lessonPhrases
            .flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) }
            .map(strippedWord)
            .filter { word in
                let normalized = ActiveListeningExercise.normalize(word)
                return normalized.count >= 3 && normalized != normalizedAnswer && !stopWords.contains(normalized)
            }

        let fallbackWords: [String] = switch level {
        case .beginner:
            ["today", "people", "really", "good", "home", "work", "time", "friend"]
        case .intermediate:
            ["usually", "important", "different", "probably", "experience", "because", "already", "around"]
        case .advanced:
            ["eventually", "remarkable", "perspective", "particularly", "significant", "approach", "despite", "throughout"]
        }

        var seen = Set<String>()
        let distractors = (lessonWords + fallbackWords)
            .filter { word in
                let normalized = ActiveListeningExercise.normalize(word)
                return normalized != normalizedAnswer && seen.insert(normalized).inserted
            }
            .sorted { left, right in
                let leftDistance = abs(left.count - answer.count)
                let rightDistance = abs(right.count - answer.count)
                return leftDistance == rightDistance ? left.localizedCaseInsensitiveCompare(right) == .orderedAscending : leftDistance < rightDistance
            }
            .prefix(3)

        var values = [answer] + distractors
        guard values.count > 1 else { return values }
        let shift = positiveModulo(seed, values.count)
        values = Array(values[shift...]) + Array(values[..<shift])
        return values
    }

    private func mask(target: Candidate, in tokens: [String]) -> [String] {
        var maskedTokens = tokens
        let token = tokens[target.tokenIndex]
        if let range = token.range(of: target.display, options: [.caseInsensitive, .diacriticInsensitive]) {
            maskedTokens[target.tokenIndex].replaceSubrange(
                range,
                with: String(repeating: "_", count: min(max(target.display.count, 4), 10))
            )
        } else {
            maskedTokens[target.tokenIndex] = "______"
        }
        return maskedTokens
    }

    private func strippedWord(_ token: String) -> String {
        token.replacingOccurrences(of: "^[^\\p{L}\\p{N}']+|[^\\p{L}\\p{N}']+$", with: "", options: .regularExpression)
    }

    private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
