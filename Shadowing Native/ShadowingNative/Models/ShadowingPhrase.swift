import Foundation

struct ShadowingPhrase: Identifiable, Hashable, Sendable {
    let id = UUID()
    let text: String
    let start: Double
    let end: Double
    let sourceSegmentCount: Int
    var needsExpandedPractice = false
    var endingHasWordTiming = false

    var duration: Double { end - start }
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

    static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}']", with: "", options: .regularExpression)
            .lowercased()
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
            blanks: blanks
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
