import Foundation

struct LearningProfile: Codable, Equatable, Sendable {
    var name: String
    var nativeLanguage: SupportedLanguage
    var learningLanguage: SupportedLanguage
    var level: EnglishLevel
    var goals: Set<LearningGoal>
    var interests: Set<LearningInterest>
    var dailyCommitment: DailyCommitment

    init(
        name: String,
        nativeLanguage: SupportedLanguage,
        learningLanguage: SupportedLanguage,
        level: EnglishLevel,
        goals: Set<LearningGoal>,
        interests: Set<LearningInterest>,
        dailyCommitment: DailyCommitment
    ) {
        self.name = name
        self.nativeLanguage = nativeLanguage
        self.learningLanguage = learningLanguage
        self.level = level
        self.goals = goals
        self.interests = interests
        self.dailyCommitment = dailyCommitment
    }

    static let starter = LearningProfile(
        name: "",
        nativeLanguage: .portugueseBrazil,
        learningLanguage: .english,
        level: .intermediate,
        goals: [.listening, .conversation],
        interests: [.travel, .technology],
        dailyCommitment: .tenMinutes
    )

    private enum CodingKeys: String, CodingKey {
        case name
        case nativeLanguage
        case learningLanguage
        case level
        case goals
        case interests
        case dailyCommitment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        nativeLanguage = try container.decodeIfPresent(SupportedLanguage.self, forKey: .nativeLanguage) ?? .portugueseBrazil
        learningLanguage = try container.decodeIfPresent(SupportedLanguage.self, forKey: .learningLanguage) ?? .english
        level = try container.decodeIfPresent(EnglishLevel.self, forKey: .level) ?? .intermediate
        goals = try container.decodeIfPresent(Set<LearningGoal>.self, forKey: .goals) ?? [.listening, .conversation]
        interests = try container.decodeIfPresent(Set<LearningInterest>.self, forKey: .interests) ?? [.travel, .technology]
        dailyCommitment = try container.decodeIfPresent(DailyCommitment.self, forKey: .dailyCommitment) ?? .tenMinutes
    }
}

enum SupportedLanguage: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case portugueseBrazil
    case spanish
    case japanese
    case korean
    case english

    static let nativeOptions: [Self] = [.portugueseBrazil, .spanish, .japanese, .korean]
    static let learningOptions: [Self] = [.english]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portugueseBrazil: "Português (Brasil)"
        case .spanish: "Español"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .english: "English"
        }
    }

    var subtitle: String {
        switch self {
        case .portugueseBrazil: "Traduções em português brasileiro"
        case .spanish: "Traducciones en español"
        case .japanese: "日本語で翻訳を表示"
        case .korean: "한국어로 번역 표시"
        case .english: "Inglês com vídeos e falas reais"
        }
    }

    var icon: String {
        switch self {
        case .portugueseBrazil: "globe.americas.fill"
        case .spanish: "globe.americas"
        case .japanese: "globe.asia.australia.fill"
        case .korean: "globe.asia.australia"
        case .english: "character.book.closed.fill"
        }
    }

    var translationCode: String {
        switch self {
        case .portugueseBrazil: "pt-BR"
        case .spanish: "es"
        case .japanese: "ja"
        case .korean: "ko"
        case .english: "en"
        }
    }

    var captionCode: String {
        switch self {
        case .portugueseBrazil: "pt"
        case .spanish: "es"
        case .japanese: "ja"
        case .korean: "ko"
        case .english: "en"
        }
    }
}

enum EnglishLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: "Iniciante"
        case .intermediate: "Intermediário"
        case .advanced: "Avançado"
        }
    }

    var subtitle: String {
        switch self {
        case .beginner: "Entendo palavras e frases curtas"
        case .intermediate: "Acompanho conversas com algum esforço"
        case .advanced: "Entendo bem, mas quero soar natural"
        }
    }

    var icon: String {
        switch self {
        case .beginner: "leaf.fill"
        case .intermediate: "figure.walk.motion"
        case .advanced: "bolt.fill"
        }
    }
}

enum LearningGoal: String, CaseIterable, Codable, Identifiable, Sendable {
    case listening
    case conversation
    case pronunciation
    case work
    case travel
    case entertainment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listening: "Entender nativos"
        case .conversation: "Conversar sem travar"
        case .pronunciation: "Melhorar pronúncia"
        case .work: "Inglês para trabalho"
        case .travel: "Viajar com confiança"
        case .entertainment: "Filmes sem legenda"
        }
    }

    var icon: String {
        switch self {
        case .listening: "ear.fill"
        case .conversation: "bubble.left.and.bubble.right.fill"
        case .pronunciation: "waveform"
        case .work: "briefcase.fill"
        case .travel: "airplane"
        case .entertainment: "play.tv.fill"
        }
    }
}

enum LearningInterest: String, CaseIterable, Codable, Identifiable, Sendable {
    case technology
    case business
    case travel
    case movies
    case news
    case lifestyle
    case science
    case aviation
    case sports
    case humor
    case gaming
    case fitness
    case cooking
    case streetInterviews

    var id: String { rawValue }

    var title: String {
        switch self {
        case .technology: "Tecnologia"
        case .business: "Negócios"
        case .travel: "Viagens"
        case .movies: "Cinema & séries"
        case .news: "Notícias"
        case .lifestyle: "Vida real"
        case .science: "Ciência"
        case .aviation: "Aviação"
        case .sports: "Esportes"
        case .humor: "Humor"
        case .gaming: "Vídeo games"
        case .fitness: "Academia"
        case .cooking: "Culinária"
        case .streetInterviews: "Entrevistas de rua"
        }
    }

    var icon: String {
        switch self {
        case .technology: "cpu.fill"
        case .business: "chart.line.uptrend.xyaxis"
        case .travel: "globe.americas.fill"
        case .movies: "film.fill"
        case .news: "newspaper.fill"
        case .lifestyle: "person.2.fill"
        case .science: "atom"
        case .aviation: "airplane.departure"
        case .sports: "sportscourt.fill"
        case .humor: "face.smiling.inverse"
        case .gaming: "gamecontroller.fill"
        case .fitness: "dumbbell.fill"
        case .cooking: "fork.knife"
        case .streetInterviews: "mic.fill"
        }
    }
}

enum DailyCommitment: Int, CaseIterable, Codable, Identifiable, Sendable {
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case twentyMinutes = 20

    var id: Int { rawValue }
    var title: String { "\(rawValue) min" }

    var subtitle: String {
        switch self {
        case .fiveMinutes: "Para criar o hábito"
        case .tenMinutes: "Constância sem pressão"
        case .fifteenMinutes: "Progresso acelerado"
        case .twentyMinutes: "Imersão todos os dias"
        }
    }

    var sessionsPerWeek: Int {
        switch self {
        case .fiveMinutes: 4
        case .tenMinutes: 5
        case .fifteenMinutes, .twentyMinutes: 6
        }
    }
}
