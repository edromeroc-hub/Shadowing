import Foundation

struct YouTubeShortItem: Identifiable, Hashable, Codable, Sendable {
    let videoID: String
    let title: String
    let topic: String
    let hook: String
    let level: EnglishLevel
    let interests: Set<LearningInterest>
    var creator: String? = nil
    var channelID: String? = nil
    var searchQuery: String? = nil

    var id: String { videoID }

    static let demoCatalog: [YouTubeShortItem] = [
        YouTubeShortItem(
            videoID: "MHeeektLq5A",
            title: "English Conversation Practice",
            topic: "Inglês cotidiano",
            hook: "Treine uma conversa curta com ritmo natural.",
            level: .intermediate,
            interests: [.lifestyle]
        ),
        YouTubeShortItem(
            videoID: "-oguR1g-imQ",
            title: "English Pronunciation Lesson",
            topic: "Pronúncia",
            hook: "Perceba os sons e repita cada frase em voz alta.",
            level: .intermediate,
            interests: [.lifestyle, .movies]
        ),
        YouTubeShortItem(
            videoID: "JUrwfjVJM1E",
            title: "Quick English Conversation",
            topic: "Conversação",
            hook: "Escute, pause e responda no mesmo ritmo.",
            level: .beginner,
            interests: [.lifestyle]
        ),
        YouTubeShortItem(
            videoID: "Busf-Ib0Dk4",
            title: "Everyday English Dialogue",
            topic: "Vocabulário",
            hook: "Aprenda expressões úteis sem sair do feed.",
            level: .intermediate,
            interests: [.lifestyle, .humor]
        )
    ]
}
