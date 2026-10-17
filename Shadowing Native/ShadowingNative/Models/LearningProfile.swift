import Foundation

struct LearningProfile: Codable, Equatable, Sendable {
    var name: String
    var nativeLanguage: SupportedLanguage
    var learningLanguage: SupportedLanguage
    var level: EnglishLevel
    var goals: Set<LearningGoal>
    var interests: Set<LearningInterest>
    var dailyCommitment: DailyCommitment
    var repeatPauseExtraPercent: Int

    init(
        name: String,
        nativeLanguage: SupportedLanguage,
        learningLanguage: SupportedLanguage,
        level: EnglishLevel,
        goals: Set<LearningGoal>,
        interests: Set<LearningInterest>,
        dailyCommitment: DailyCommitment,
        repeatPauseExtraPercent: Int = 30
    ) {
        self.name = name
        self.nativeLanguage = nativeLanguage
        self.learningLanguage = learningLanguage
        self.level = level
        self.goals = goals
        self.interests = interests
        self.dailyCommitment = dailyCommitment
        self.repeatPauseExtraPercent = Self.validPausePercent(repeatPauseExtraPercent)
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
        case repeatPauseExtraPercent
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
        repeatPauseExtraPercent = Self.validPausePercent((try? container.decode(Int.self, forKey: .repeatPauseExtraPercent)) ?? 30)
    }

    private static func validPausePercent(_ value: Int) -> Int {
        (0...100).contains(value) && value.isMultiple(of: 10) ? value : 30
    }

    func hasSameRecommendationPreferences(as other: Self) -> Bool {
        level == other.level && interests == other.interests && goals == other.goals
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
    case career
    case finance
    case travel
    case livingAbroad
    case shopping
    case movies
    case music
    case news
    case history
    case lifestyle
    case health
    case science
    case engineering
    case cars
    case aviation
    case agriculture
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
        case .career: "Carreira & trabalho"
        case .finance: "Economia & finanças"
        case .travel: "Viagens"
        case .livingAbroad: "Morar fora"
        case .shopping: "Compras & restaurantes"
        case .movies: "Cinema & séries"
        case .music: "Música & cultura pop"
        case .news: "Notícias"
        case .history: "História & geografia"
        case .lifestyle: "Vida real"
        case .health: "Saúde & medicina"
        case .science: "Ciência"
        case .engineering: "Engenharia & obras"
        case .cars: "Carros & motores"
        case .aviation: "Aviação"
        case .agriculture: "Agro & campo"
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
        case .career: "briefcase.fill"
        case .finance: "dollarsign.circle.fill"
        case .travel: "globe.americas.fill"
        case .livingAbroad: "house.and.flag.fill"
        case .shopping: "bag.fill"
        case .movies: "film.fill"
        case .music: "music.mic"
        case .news: "newspaper.fill"
        case .history: "globe.desk.fill"
        case .lifestyle: "person.2.fill"
        case .health: "cross.case.fill"
        case .science: "atom"
        case .engineering: "wrench.and.screwdriver.fill"
        case .cars: "car.fill"
        case .aviation: "airplane.departure"
        case .agriculture: "leaf.fill"
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
