import Foundation
import Observation

struct ListeningWordPerformance: Codable, Identifiable, Hashable {
    let word: String
    var attempts: Int
    var correct: Int
    var lastPracticedAt: Date

    var id: String { word }
    var mistakes: Int { attempts - correct }
    var needsReview: Bool { mistakes > 0 && correct < mistakes * 2 }
}

struct StudiedVideo: Codable, Identifiable, Hashable {
    let videoID: String
    var title: String
    var channel: String
    var isShort: Bool
    var phraseStart: Double
    var phraseIndex: Int
    var phraseCount: Int
    var lastStudiedAt: Date

    var id: String { videoID }
    var link: String { "https://www.youtube.com/watch?v=\(videoID)" }
    var progress: Double { phraseCount > 0 ? Double(phraseIndex + 1) / Double(phraseCount) : 0 }
}

enum ShortReaction: String, Codable, Sendable {
    case liked
    case hidden
    case neutral
}

struct ShortFeedback: Codable, Equatable, Sendable {
    let videoID: String
    let creator: String?
    let interests: Set<LearningInterest>
    let reaction: ShortReaction
    let updatedAt: Date
    var difficulty: ShortDifficultyRating? = nil
}

struct ShortChannelPreference: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let isFollowed: Bool
    let updatedAt: Date
}

struct ShortSearchPreference: Codable, Equatable, Sendable {
    let query: String
    let count: Int
    let updatedAt: Date
}

enum ShortDifficultyRating: String, Codable, Sendable {
    case tooEasy
    case justRight
    case tooHard
}

@MainActor
@Observable
final class StudyProgressStore {
    struct DailySummary: Codable, Identifiable, Hashable {
        let dayKey: String
        var words: Int
        var phrases: Int
        var listeningAttempts: Int
        var listeningCorrect: Int

        var id: String { dayKey }

        var listeningAccuracy: Int {
            guard listeningAttempts > 0 else { return 0 }
            return Int((Double(listeningCorrect) / Double(listeningAttempts) * 100).rounded())
        }

        init(
            dayKey: String,
            words: Int,
            phrases: Int,
            listeningAttempts: Int = 0,
            listeningCorrect: Int = 0
        ) {
            self.dayKey = dayKey
            self.words = words
            self.phrases = phrases
            self.listeningAttempts = listeningAttempts
            self.listeningCorrect = listeningCorrect
        }

        private enum CodingKeys: String, CodingKey {
            case dayKey
            case words
            case phrases
            case listeningAttempts
            case listeningCorrect
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            dayKey = try container.decode(String.self, forKey: .dayKey)
            words = try container.decodeIfPresent(Int.self, forKey: .words) ?? 0
            phrases = try container.decodeIfPresent(Int.self, forKey: .phrases) ?? 0
            listeningAttempts = try container.decodeIfPresent(Int.self, forKey: .listeningAttempts) ?? 0
            listeningCorrect = try container.decodeIfPresent(Int.self, forKey: .listeningCorrect) ?? 0
        }
    }

    private(set) var summaries: [String: DailySummary]
    private(set) var listeningWords: [String: ListeningWordPerformance]
    private(set) var videos: [String: StudiedVideo]
    private(set) var shortFeedback: [String: ShortFeedback]
    private(set) var shortChannels: [String: ShortChannelPreference]
    private(set) var shortSearches: [String: ShortSearchPreference]
    private var recordedPhraseKeys: Set<String>

    private let defaults: UserDefaults
    private let summariesKey = "shadowing.native.progress.summaries"
    private let phrasesKey = "shadowing.native.progress.recorded-phrases"
    private let listeningWordsKey = "shadowing.native.progress.listening-words"
    private let videosKey = "shadowing.native.progress.videos"
    private let shortFeedbackKey = "shadowing.native.progress.short-feedback"
    private let shortChannelsKey = "shadowing.native.progress.short-channels"
    private let shortSearchesKey = "shadowing.native.progress.short-searches"
    private var activeAccountID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        summaries = Self.decode([String: DailySummary].self, key: summariesKey, defaults: defaults) ?? [:]
        listeningWords = Self.decode([String: ListeningWordPerformance].self, key: listeningWordsKey, defaults: defaults) ?? [:]
        videos = Self.decode([String: StudiedVideo].self, key: videosKey, defaults: defaults) ?? [:]
        shortFeedback = Self.decode([String: ShortFeedback].self, key: shortFeedbackKey, defaults: defaults) ?? [:]
        shortChannels = Self.decode([String: ShortChannelPreference].self, key: shortChannelsKey, defaults: defaults) ?? [:]
        shortSearches = Self.decode([String: ShortSearchPreference].self, key: shortSearchesKey, defaults: defaults) ?? [:]
        recordedPhraseKeys = Self.decode(Set<String>.self, key: phrasesKey, defaults: defaults) ?? []
    }

    var difficultWords: [ListeningWordPerformance] {
        listeningWords.values
            .filter(\.needsReview)
            .sorted {
                let firstPriority = $0.mistakes * 2 - $0.correct
                let secondPriority = $1.mistakes * 2 - $1.correct
                if firstPriority != secondPriority { return firstPriority > secondPriority }
                if $0.mistakes != $1.mistakes { return $0.mistakes > $1.mistakes }
                return $0.lastPracticedAt > $1.lastPracticedAt
            }
    }

    var today: DailySummary {
        summaries[Self.dayKey(for: Date())] ?? DailySummary(dayKey: Self.dayKey(for: Date()), words: 0, phrases: 0)
    }

    var recentDays: [DailySummary] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = Self.dayKey(for: date)
            return summaries[key] ?? DailySummary(dayKey: key, words: 0, phrases: 0)
        }
    }

    var recentVideos: [StudiedVideo] {
        videos.values.sorted { $0.lastStudiedAt > $1.lastStudiedAt }
    }

    func activateAccount(_ accountID: String?) {
        guard activeAccountID != accountID else { return }
        let nextSummariesKey = storageKey(summariesKey, accountID: accountID)
        let nextPhrasesKey = storageKey(phrasesKey, accountID: accountID)
        let nextListeningKey = storageKey(listeningWordsKey, accountID: accountID)
        let nextVideosKey = storageKey(videosKey, accountID: accountID)
        let nextFeedbackKey = storageKey(shortFeedbackKey, accountID: accountID)
        let nextChannelsKey = storageKey(shortChannelsKey, accountID: accountID)
        let nextSearchesKey = storageKey(shortSearchesKey, accountID: accountID)

        if activeAccountID == nil, accountID != nil {
            for (source, destination) in [
                (summariesKey, nextSummariesKey),
                (phrasesKey, nextPhrasesKey),
                (listeningWordsKey, nextListeningKey),
                (videosKey, nextVideosKey),
                (shortFeedbackKey, nextFeedbackKey),
                (shortChannelsKey, nextChannelsKey),
                (shortSearchesKey, nextSearchesKey)
            ] {
                if defaults.object(forKey: destination) == nil, let data = defaults.data(forKey: source) {
                    defaults.set(data, forKey: destination)
                    defaults.removeObject(forKey: source)
                }
            }
        }

        activeAccountID = accountID
        summaries = Self.decode([String: DailySummary].self, key: nextSummariesKey, defaults: defaults) ?? [:]
        recordedPhraseKeys = Self.decode(Set<String>.self, key: nextPhrasesKey, defaults: defaults) ?? []
        listeningWords = Self.decode([String: ListeningWordPerformance].self, key: nextListeningKey, defaults: defaults) ?? [:]
        videos = Self.decode([String: StudiedVideo].self, key: nextVideosKey, defaults: defaults) ?? [:]
        shortFeedback = Self.decode([String: ShortFeedback].self, key: nextFeedbackKey, defaults: defaults) ?? [:]
        shortChannels = Self.decode([String: ShortChannelPreference].self, key: nextChannelsKey, defaults: defaults) ?? [:]
        shortSearches = Self.decode([String: ShortSearchPreference].self, key: nextSearchesKey, defaults: defaults) ?? [:]
    }

    func deleteAccountData(for accountID: String) {
        defaults.removeObject(forKey: storageKey(summariesKey, accountID: accountID))
        defaults.removeObject(forKey: storageKey(phrasesKey, accountID: accountID))
        defaults.removeObject(forKey: storageKey(listeningWordsKey, accountID: accountID))
        defaults.removeObject(forKey: storageKey(videosKey, accountID: accountID))
        defaults.removeObject(forKey: storageKey(shortFeedbackKey, accountID: accountID))
        defaults.removeObject(forKey: storageKey(shortChannelsKey, accountID: accountID))
        defaults.removeObject(forKey: storageKey(shortSearchesKey, accountID: accountID))
        if activeAccountID == accountID {
            activeAccountID = nil
            summaries = [:]
            recordedPhraseKeys = []
            listeningWords = [:]
            videos = [:]
            shortFeedback = [:]
            shortChannels = [:]
            shortSearches = [:]
        }
    }

    func rememberVideo(
        videoID: String,
        title: String,
        channel: String,
        isShort: Bool,
        phrase: ShadowingPhrase,
        phraseIndex: Int,
        phraseCount: Int
    ) {
        videos[videoID] = StudiedVideo(
            videoID: videoID,
            title: title,
            channel: channel,
            isShort: isShort,
            phraseStart: phrase.start,
            phraseIndex: phraseIndex,
            phraseCount: phraseCount,
            lastStudiedAt: Date()
        )
        save()
    }

    func react(to item: YouTubeShortItem, as reaction: ShortReaction) {
        let selectedReaction: ShortReaction = shortFeedback[item.videoID]?.reaction == reaction ? .neutral : reaction
        shortFeedback[item.videoID] = ShortFeedback(
            videoID: item.videoID,
            creator: item.creator,
            interests: item.interests,
            reaction: selectedReaction,
            updatedAt: Date(),
            difficulty: shortFeedback[item.videoID]?.difficulty
        )
        save()
    }

    var followedShortChannels: [ShortChannelPreference] {
        shortChannels.values.filter(\.isFollowed).sorted { $0.updatedAt > $1.updatedAt }
    }

    var recentShortSearches: [ShortSearchPreference] {
        shortSearches.values.sorted { $0.updatedAt > $1.updatedAt }.prefix(5).map { $0 }
    }

    func setShortChannel(_ id: String, title: String, followed: Bool) {
        guard !id.isEmpty else { return }
        shortChannels[id] = ShortChannelPreference(id: id, title: title, isFollowed: followed, updatedAt: Date())
        save()
    }

    func rememberShortSearch(_ text: String) {
        let query = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard query.count >= 2 else { return }
        let key = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        shortSearches[key] = ShortSearchPreference(query: query, count: (shortSearches[key]?.count ?? 0) + 1, updatedAt: Date())
        save()
    }

    func rateDifficulty(of item: YouTubeShortItem, as rating: ShortDifficultyRating) {
        shortFeedback[item.videoID] = ShortFeedback(
            videoID: item.videoID,
            creator: item.creator,
            interests: item.interests,
            reaction: shortFeedback[item.videoID]?.reaction ?? .neutral,
            updatedAt: Date(),
            difficulty: rating
        )
        save()
    }

    func merge(_ remote: StudyProgressSnapshot) {
        for (key, summary) in remote.summaries {
            if let local = summaries[key] {
                summaries[key] = DailySummary(
                    dayKey: key,
                    words: max(local.words, summary.words),
                    phrases: max(local.phrases, summary.phrases),
                    listeningAttempts: max(local.listeningAttempts, summary.listeningAttempts),
                    listeningCorrect: max(local.listeningCorrect, summary.listeningCorrect)
                )
            } else {
                summaries[key] = summary
            }
        }
        recordedPhraseKeys.formUnion(remote.recordedPhraseKeys)
        var recordedByDay: [String: (words: Int, phrases: Int)] = [:]
        for key in recordedPhraseKeys {
            let parts = key.split(separator: "|", maxSplits: 3)
            guard parts.count == 4 else { continue }
            let day = String(parts[0])
            let words = parts[3]
                .replacingOccurrences(of: "[^\\p{L}\\p{N}'-]", with: " ", options: .regularExpression)
                .split(whereSeparator: \.isWhitespace)
                .count
            recordedByDay[day, default: (0, 0)].words += words
            recordedByDay[day, default: (0, 0)].phrases += 1
        }
        for (day, recorded) in recordedByDay {
            var summary = summaries[day] ?? DailySummary(dayKey: day, words: 0, phrases: 0)
            summary.words = max(summary.words, recorded.words)
            summary.phrases = max(summary.phrases, recorded.phrases)
            summaries[day] = summary
        }
        for (key, word) in remote.listeningWords {
            if let local = listeningWords[key], local.lastPracticedAt > word.lastPracticedAt { continue }
            listeningWords[key] = word
        }
        for (key, video) in remote.videos {
            if let local = videos[key], local.lastStudiedAt > video.lastStudiedAt { continue }
            videos[key] = video
        }
        for (key, feedback) in remote.shortFeedback {
            if let local = shortFeedback[key], local.updatedAt > feedback.updatedAt { continue }
            shortFeedback[key] = feedback
        }
        for (key, channel) in remote.shortChannels {
            if let local = shortChannels[key], local.updatedAt > channel.updatedAt { continue }
            shortChannels[key] = channel
        }
        for (key, search) in remote.shortSearches {
            if let local = shortSearches[key], local.updatedAt > search.updatedAt { continue }
            shortSearches[key] = search
        }
        save()
    }

    var snapshot: StudyProgressSnapshot {
        StudyProgressSnapshot(
            summaries: summaries,
            listeningWords: listeningWords,
            recordedPhraseKeys: recordedPhraseKeys,
            videos: videos,
            shortFeedback: shortFeedback,
            shortChannels: shortChannels,
            shortSearches: shortSearches
        )
    }

    func record(phrase: ShadowingPhrase, videoID: String) {
        let day = Self.dayKey(for: Date())
        let phraseKey = "\(day)|\(videoID)|\(Int((phrase.start * 1000).rounded()))|\(phrase.text.lowercased())"
        guard recordedPhraseKeys.insert(phraseKey).inserted else { return }

        let wordCount = phrase.text
            .replacingOccurrences(of: "[^\\p{L}\\p{N}'-]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .count

        var summary = summaries[day] ?? DailySummary(dayKey: day, words: 0, phrases: 0)
        summary.words += wordCount
        summary.phrases += 1
        summaries[day] = summary
        save()
    }

    func recordListeningAttempt(word: String, isCorrect: Bool) {
        let normalizedWord = ActiveListeningExercise.normalize(word)
        guard !normalizedWord.isEmpty else { return }

        let day = Self.dayKey(for: Date())
        var summary = summaries[day] ?? DailySummary(dayKey: day, words: 0, phrases: 0)
        summary.listeningAttempts += 1
        if isCorrect {
            summary.listeningCorrect += 1
        }
        summaries[day] = summary

        var performance = listeningWords[normalizedWord] ?? ListeningWordPerformance(
            word: normalizedWord,
            attempts: 0,
            correct: 0,
            lastPracticedAt: Date()
        )
        performance.attempts += 1
        if isCorrect {
            performance.correct += 1
        }
        performance.lastPracticedAt = Date()
        listeningWords[normalizedWord] = performance
        save()
    }

    static func date(from dayKey: String) -> Date? {
        keyFormatter.date(from: dayKey)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(summaries) {
            defaults.set(data, forKey: storageKey(summariesKey, accountID: activeAccountID))
        }
        if let data = try? JSONEncoder().encode(recordedPhraseKeys) {
            defaults.set(data, forKey: storageKey(phrasesKey, accountID: activeAccountID))
        }
        if let data = try? JSONEncoder().encode(listeningWords) {
            defaults.set(data, forKey: storageKey(listeningWordsKey, accountID: activeAccountID))
        }
        if let data = try? JSONEncoder().encode(videos) {
            defaults.set(data, forKey: storageKey(videosKey, accountID: activeAccountID))
        }
        if let data = try? JSONEncoder().encode(shortFeedback) {
            defaults.set(data, forKey: storageKey(shortFeedbackKey, accountID: activeAccountID))
        }
        if let data = try? JSONEncoder().encode(shortChannels) {
            defaults.set(data, forKey: storageKey(shortChannelsKey, accountID: activeAccountID))
        }
        if let data = try? JSONEncoder().encode(shortSearches) {
            defaults.set(data, forKey: storageKey(shortSearchesKey, accountID: activeAccountID))
        }
    }

    private func storageKey(_ base: String, accountID: String?) -> String {
        accountID.map { "\(base).\($0)" } ?? base
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, key: String, defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func dayKey(for date: Date) -> String {
        keyFormatter.string(from: date)
    }

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct StudyProgressSnapshot: Codable {
    var summaries: [String: StudyProgressStore.DailySummary]
    var listeningWords: [String: ListeningWordPerformance]
    var recordedPhraseKeys: Set<String>
    var videos: [String: StudiedVideo]
    var shortFeedback: [String: ShortFeedback]
    var shortChannels: [String: ShortChannelPreference]
    var shortSearches: [String: ShortSearchPreference]

    private enum CodingKeys: String, CodingKey {
        case summaries, listeningWords, recordedPhraseKeys, videos, shortFeedback, shortChannels, shortSearches
    }

    init(
        summaries: [String: StudyProgressStore.DailySummary],
        listeningWords: [String: ListeningWordPerformance],
        recordedPhraseKeys: Set<String>,
        videos: [String: StudiedVideo],
        shortFeedback: [String: ShortFeedback],
        shortChannels: [String: ShortChannelPreference] = [:],
        shortSearches: [String: ShortSearchPreference] = [:]
    ) {
        self.summaries = summaries
        self.listeningWords = listeningWords
        self.recordedPhraseKeys = recordedPhraseKeys
        self.videos = videos
        self.shortFeedback = shortFeedback
        self.shortChannels = shortChannels
        self.shortSearches = shortSearches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summaries = try container.decode([String: StudyProgressStore.DailySummary].self, forKey: .summaries)
        listeningWords = try container.decode([String: ListeningWordPerformance].self, forKey: .listeningWords)
        recordedPhraseKeys = try container.decode(Set<String>.self, forKey: .recordedPhraseKeys)
        videos = try container.decode([String: StudiedVideo].self, forKey: .videos)
        shortFeedback = try container.decodeIfPresent([String: ShortFeedback].self, forKey: .shortFeedback) ?? [:]
        shortChannels = try container.decodeIfPresent([String: ShortChannelPreference].self, forKey: .shortChannels) ?? [:]
        shortSearches = try container.decodeIfPresent([String: ShortSearchPreference].self, forKey: .shortSearches) ?? [:]
    }
}
