import Foundation

struct VideoSuggestion: Identifiable, Hashable, Codable, Sendable {
    let videoID: String
    let title: String
    let creator: String
    let source: VideoSource
    let durationMinutes: Int?
    let level: EnglishLevel
    let interests: Set<LearningInterest>
    let goals: Set<LearningGoal>
    let accent: SuggestionAccent
    let hook: String

    var id: String { videoID }
    var thumbnailURL: URL? { URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg") }

    init(
        videoID: String,
        title: String,
        creator: String,
        source: VideoSource,
        durationMinutes: Int?,
        level: EnglishLevel,
        interests: Set<LearningInterest>,
        goals: Set<LearningGoal>,
        accent: SuggestionAccent,
        hook: String
    ) {
        self.videoID = videoID
        self.title = title
        self.creator = creator
        self.source = source
        self.durationMinutes = durationMinutes
        self.level = level
        self.interests = interests
        self.goals = goals
        self.accent = accent
        self.hook = hook
    }
}

enum VideoSource: String, Hashable, Codable, Sendable {
    case youtube = "YouTube"
    case shorts = "Shorts"
}

enum SuggestionAccent: String, Hashable, Codable, Sendable {
    case blue
    case purple
    case coral
    case mint
    case amber
}

extension VideoSuggestion {
    static let catalog: [VideoSuggestion] = [
        .init(
            videoID: "MHeeektLq5A",
            title: "English Conversation Practice",
            creator: "English to Fluency",
            source: .shorts,
            durationMinutes: 1,
            level: .beginner,
            interests: [.lifestyle, .travel],
            goals: [.listening, .conversation],
            accent: .mint,
            hook: "Diálogo curto com ritmo cotidiano"
        ),
        .init(
            videoID: "-oguR1g-imQ",
            title: "English Pronunciation Lesson",
            creator: "POC English",
            source: .shorts,
            durationMinutes: 1,
            level: .intermediate,
            interests: [.lifestyle, .movies],
            goals: [.listening, .pronunciation],
            accent: .blue,
            hook: "Pronúncia prática em poucos segundos"
        ),
        .init(
            videoID: "9aSKMf5nCk0", title: "Powerful New Macs Are Coming!", creator: "Waveform Clips",
            source: .youtube, durationMinutes: 12, level: .intermediate,
            interests: [.technology], goals: [.listening, .work], accent: .blue,
            hook: "Tecnologia em conversa natural"
        ),
        .init(
            videoID: "ls9be-9C-uk", title: "6 BEST Pieces Of Business Advice That Made Me Millions | E103", creator: "The Diary Of A CEO",
            source: .youtube, durationMinutes: 30, level: .advanced,
            interests: [.business], goals: [.listening, .work], accent: .purple,
            hook: "Entrevista longa para escuta avançada"
        ),
        .init(
            videoID: "WYcl7WOe9SI", title: "Prue Leith on the Bake Off Leak, Bhutan & Her Wildest Travels", creator: "The Travel Diaries Podcast",
            source: .youtube, durationMinutes: 30, level: .intermediate,
            interests: [.travel, .lifestyle], goals: [.listening, .travel], accent: .coral,
            hook: "Histórias de viagem em inglês britânico"
        ),
        .init(
            videoID: "3r63TF3Ob9w", title: "The Best Moments From Our First 250 Movies on 'The Rewatchables' Podcast", creator: "Ringer Movies",
            source: .youtube, durationMinutes: 10, level: .advanced,
            interests: [.movies, .humor], goals: [.listening, .entertainment], accent: .amber,
            hook: "Cinema e conversa espontânea"
        ),
        .init(
            videoID: "eogS70nCT2k", title: "Martin Short Roasted Conan For Wearing Shorts | Conan O'Brien Needs A Friend", creator: "Team Coco",
            source: .youtube, durationMinutes: 10, level: .advanced,
            interests: [.humor, .lifestyle], goals: [.listening, .entertainment], accent: .coral,
            hook: "Humor, gírias e fala rápida"
        ),
        .init(
            videoID: "6La50pZAcBo", title: "What We've Been Playing - Kinda Funny Gamescast", creator: "Kinda Funny Games",
            source: .youtube, durationMinutes: 30, level: .advanced,
            interests: [.gaming], goals: [.listening, .entertainment], accent: .purple,
            hook: "Gamescast com conversa entre amigos"
        ),
        .init(
            videoID: "uKHinvo6li0", title: "EL AL 777 Tells JFK Tower: \"We Can't Go Around\" | Captain Steeeve", creator: "Captain Steeeve",
            source: .youtube, durationMinutes: 10, level: .advanced,
            interests: [.aviation, .travel], goals: [.listening], accent: .blue,
            hook: "Aviação e inglês técnico real"
        ),
        .init(
            videoID: "yi8WGth7Hhs", title: "I Tried EVERY Way To Build Muscle", creator: "Will Tennyson",
            source: .youtube, durationMinutes: 20, level: .intermediate,
            interests: [.fitness], goals: [.listening], accent: .mint,
            hook: "Treino com humor e inglês natural"
        ),
        .init(
            videoID: "aSV2zd-qch0", title: "Training at the World’s Most Dangerous Gym (Diamond Gym)", creator: "Jesse James West",
            source: .youtube, durationMinutes: 20, level: .intermediate,
            interests: [.fitness, .lifestyle], goals: [.listening], accent: .amber,
            hook: "Academia e conversas com convidados"
        ),
        .init(
            videoID: "XL_A1rt_qz4", title: "I Tried VIRAL Celebrity Foods and I'm insulted!", creator: "Guga Foods",
            source: .youtube, durationMinutes: 15, level: .intermediate,
            interests: [.cooking, .lifestyle], goals: [.listening], accent: .coral,
            hook: "Culinária, experimentos e opiniões"
        )
    ]
}
