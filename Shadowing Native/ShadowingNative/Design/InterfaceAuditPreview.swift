#if DEBUG && targetEnvironment(simulator)
import SwiftUI

struct InterfaceAuditPreview: View {
    @State private var model: AppModel
    @State private var progress: StudyProgressStore
    @State private var vocabulary: VocabularyStore
    @State private var videoPreviewPath = ["practice"]
    private let screen: String

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        screen = arguments.first { $0.hasPrefix("--audit-screen=") }?.components(separatedBy: "=").last ?? "shorts"
        let defaults = UserDefaults(suiteName: "shadowing.interface-audit")!
        let appModel = AppModel(defaults: defaults)
        appModel.profile = .starter
        appModel.profile.interests = [.lifestyle, .technology]
        if let level = arguments.first(where: { $0.hasPrefix("--audit-level=") })?.split(separator: "=").last,
           let selectedLevel = EnglishLevel(rawValue: String(level)) {
            appModel.profile.level = selectedLevel
        }
        if let topics = arguments.first(where: { $0.hasPrefix("--audit-topics=") })?.split(separator: "=").last {
            let interests = Set(topics.split(separator: ",").compactMap { LearningInterest(rawValue: String($0)) })
            if !interests.isEmpty { appModel.profile.interests = interests }
        }
        appModel.profile.name = "Prévia"
        appModel.selectedTab = switch screen {
        case "today": .today
        case "explore": .explore
        case "progress": .progress
        case "profile": .profile
        default: .shorts
        }
        _model = State(initialValue: appModel)
        _progress = State(initialValue: StudyProgressStore(defaults: defaults))
        _vocabulary = State(initialValue: VocabularyStore(defaults: defaults))
    }

    var body: some View {
        Group {
            if screen == "onboarding" {
                OnboardingFlowView()
            } else if screen == "login" {
                AccountAccessView(requiresAccount: true)
            } else if screen == "privacy" {
                LegalDocumentView(document: .privacy)
            } else if screen == "terms" {
                LegalDocumentView(document: .terms)
            } else if screen == "beta" {
                ZStack {
                    AtmosphericBackground()
                    BetaAccessView(onContinue: {})
                }
            } else if screen == "video" {
                NavigationStack(path: $videoPreviewPath) {
                    ZStack {
                        AtmosphericBackground()
                        Button("Abrir prévia de prática") {
                            videoPreviewPath.append("practice")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .navigationDestination(for: String.self) { _ in
                        YouTubeImportView(initialLink: "https://youtube.com/watch?v=dQw4w9WgXcQ", previewTranscript: transcript)
                    }
                }
            } else {
                if ProcessInfo.processInfo.arguments.contains("--audit-live") {
                    MainTabView()
                } else {
                    MainTabView(previewItems: previewItems, previewTranscript: transcript)
                }
            }
        }
        .environment(model)
        .environment(progress)
        .environment(vocabulary)
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("--audit-large-text") ? .xxxLarge : .large)
    }

    private var transcript: YouTubeTranscript {
        if ProcessInfo.processInfo.arguments.contains("--audit-long-caption") {
            return YouTubeTranscript(
                videoID: "preview", title: "Auditoria: legenda longa", channel: "Cenário sintético local", languageCode: "en", source: "fixture",
                segments: [
                    YouTubeTranscriptSegment(text: "When I started learning English, I thought that listening to a long conversation would be enough, but after a few weeks I realized that I needed to stop, repeat each sentence, notice the words I had missed, and practice speaking at my own pace before trying to follow the entire conversation again without any help from the subtitles on the screen.", start: 0, end: 23),
                    YouTubeTranscriptSegment(text: "How was your day?", start: 23, end: 25),
                    YouTubeTranscriptSegment(text: "It was busy but good.", start: 25, end: 27)
                ]
            )
        }
        return YouTubeTranscript(
            videoID: "preview", title: "Treino de enquadramento", channel: "Prévia local", languageCode: "en", source: "fixture",
            segments: [
                YouTubeTranscriptSegment(text: "You can take your time, listen again, and learn something new every time you practice with a conversation that interests you.", start: 0, end: 8),
                YouTubeTranscriptSegment(text: "How was your day?", start: 8, end: 10),
                YouTubeTranscriptSegment(text: "It was busy but good.", start: 10, end: 12)
            ]
        )
    }

    private var previewItems: [YouTubeShortItem] {
        guard ProcessInfo.processInfo.arguments.contains("--audit-many-shorts") else { return YouTubeShortItem.demoCatalog }
        return (1...20).map { index in
            YouTubeShortItem(
                videoID: "audit-\(index)", title: "Short de teste \(index)", topic: "Teste de paginação",
                hook: "Cenário local sem rede", level: model.profile.level, interests: model.profile.interests
            )
        }
    }

    static func translationFixture(for text: String) -> String? {
        guard ProcessInfo.processInfo.arguments.contains("--audit-translation-fixture") else { return nil }
        if text.hasPrefix("When I started") {
            return "Quando comecei a aprender inglês, pensei que ouvir uma conversa longa seria suficiente, mas depois de algumas semanas percebi que precisava parar, repetir cada frase, observar as palavras que havia perdido e praticar a fala no meu próprio ritmo antes de tentar acompanhar toda a conversa novamente, sem ajuda das legendas na tela."
        }
        if text.hasPrefix("You can take") {
            return "Você pode ir no seu ritmo, ouvir novamente e aprender algo novo toda vez que praticar com uma conversa que lhe interessa."
        }
        return text.hasPrefix("How was") ? "Como foi o seu dia?" : "Foi corrido, mas bom."
    }
}
#endif
