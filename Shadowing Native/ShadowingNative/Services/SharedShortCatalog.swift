import FirebaseAuth
import FirebaseFirestore
import Foundation

struct PreparedShortLesson {
    let item: YouTubeShortItem
    let transcript: YouTubeTranscript
    let phrases: [ShadowingPhrase]
    let affinity: [String: Int]
}

private struct CatalogSegment: Decodable {
    let text: String
    let start: Double
    let end: Double
    let hasWordTiming: Bool
}

private struct CatalogPhrase: Decodable {
    let text: String
    let start: Double
    let end: Double
    let sourceSegmentCount: Int
    let needsExpandedPractice: Bool
    let endingHasWordTiming: Bool
}

private struct CatalogPayload: Decodable {
    let version: Int
    let videoID: String
    let title: String
    let channel: String
    let channelID: String?
    let languageCode: String
    let source: String
    let level: String
    let interests: [String]
    let segments: [CatalogSegment]
    let phrases: [CatalogPhrase]
    let affinity: [String: Int]?

    func preparedLesson() -> PreparedShortLesson? {
        guard version == 1,
              videoID.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil,
              let englishLevel = EnglishLevel(rawValue: level),
              languageCode.lowercased().hasPrefix("en"),
              !segments.isEmpty, !phrases.isEmpty else { return nil }
        var previousStart = -1.0
        for segment in segments {
            guard segment.start.isFinite, segment.end.isFinite,
                  segment.start >= previousStart, segment.end > segment.start,
                  !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            previousStart = segment.start
        }
        let transcript = YouTubeTranscript(
            videoID: videoID, title: title, channel: channel,
            languageCode: languageCode, source: source,
            segments: segments.map {
                YouTubeTranscriptSegment(text: $0.text, start: $0.start, end: $0.end, hasWordTiming: $0.hasWordTiming)
            }
        )
        let preparedPhrases = phrases.compactMap { phrase -> ShadowingPhrase? in
            guard phrase.start.isFinite, phrase.end.isFinite,
                  phrase.end > phrase.start, phrase.start >= 0,
                  !phrase.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return ShadowingPhrase(
                text: phrase.text, start: phrase.start, end: phrase.end,
                sourceSegmentCount: phrase.sourceSegmentCount,
                needsExpandedPractice: phrase.needsExpandedPractice,
                endingHasWordTiming: phrase.endingHasWordTiming
            )
        }
        guard preparedPhrases.count == phrases.count else { return nil }
        let topics = Set(interests.compactMap(LearningInterest.init(rawValue:)))
        return PreparedShortLesson(
            item: YouTubeShortItem(
                videoID: videoID, title: title,
                topic: topics.first?.title ?? "Inglês real",
                hook: "Pratique com uma conversa em inglês.",
                level: englishLevel, interests: topics,
                creator: channel, channelID: channelID
            ),
            transcript: transcript, phrases: preparedPhrases,
            affinity: affinity ?? [:]
        )
    }
}

@MainActor
final class SharedShortCatalog {
    private var level: EnglishLevel?
    private var cursor: DocumentSnapshot?
    private(set) var hasMore = true

    func reset(for level: EnglishLevel) {
        self.level = level
        cursor = nil
        hasMore = true
    }

    func markUnavailable() {
        hasMore = false
    }

    func nextPage(for profile: LearningProfile) async throws -> [PreparedShortLesson] {
        guard Auth.auth().currentUser != nil else {
            markUnavailable()
            return []
        }
        let level = profile.level
        if self.level != level { reset(for: level) }
        guard hasMore else { return [] }
        var query: Query = Firestore.firestore().collection("approvedShorts")
            .whereField("level", isEqualTo: level.rawValue)
            .limit(to: 30)
        let interests = profile.interests.map(\.rawValue).sorted()
        if !interests.isEmpty {
            query = query.whereField("interests", arrayContainsAny: interests)
        }
        if let cursor { query = query.start(afterDocument: cursor) }
        let snapshot = try await query.getDocuments()
        cursor = snapshot.documents.last
        hasMore = snapshot.documents.count == 30
        return snapshot.documents.compactMap { document in
            guard document.data()["status"] as? String == "approved",
                  let payload = document.data()["payload"] as? String,
                  let record = try? JSONDecoder().decode(CatalogPayload.self, from: Data(payload.utf8)),
                  record.videoID == document.documentID,
                  record.level == level.rawValue else { return nil }
            return record.preparedLesson()
        }
    }
}
