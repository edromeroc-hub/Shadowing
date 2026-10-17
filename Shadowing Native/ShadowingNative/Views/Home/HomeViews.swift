import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(StudyProgressStore.self) private var progressStore
    @State private var importRequest: YouTubeImportRequest?
    @State private var discoveredVideos: [VideoSuggestion] = []
    @State private var isDiscoveringVideos = false
    @State private var videoDiscoveryError: String?
    @State private var videoDiscoveryRequestID = UUID()
    @State private var loadedProfile: LearningProfile?

    private var recommendations: [VideoSuggestion] {
        appModel.recommendations(
            history: progressStore.recentVideos,
            feedback: progressStore.shortFeedback,
            catalog: discoveredVideos
        )
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greeting
                    continueSection
                    dailySession
                    customVideoShortcut
                    recommendationSection
                    commitmentCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() }
        }
        .navigationDestination(item: $importRequest) { request in
            YouTubeImportView(initialLink: request.link)
        }
        .task(id: appModel.profile) { await loadSuggestedVideos() }
    }

    private var continueSection: some View {
        Group {
            if !progressStore.recentVideos.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Continue de onde parou")
                        .font(.title2.bold())
                    ForEach(progressStore.recentVideos.prefix(3)) { video in
                        Button {
                            importRequest = YouTubeImportRequest(link: video.link)
                        } label: {
                            HStack(spacing: 13) {
                                AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(video.videoID)/hqdefault.jpg")) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "play.rectangle.fill")
                                        .foregroundStyle(ShadowingTheme.blue)
                                }
                                .frame(width: 92, height: 62)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(video.title).font(.subheadline.bold()).lineLimit(2)
                                    Text("\(video.channel) · frase \(video.phraseIndex + 1) de \(video.phraseCount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "play.fill").foregroundStyle(ShadowingTheme.blue)
                            }
                            .padding(10)
                            .shadowingGlass(cornerRadius: 18, interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greetingText)
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(ShadowingTheme.blue)
            Text("Seu inglês, uma frase por vez.")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 10)
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "BOM DIA"
        case 12..<18: "BOA TARDE"
        default: "BOA NOITE"
        }
    }

    private var dailySession: some View {
        Button {
            if let suggestion = recommendations.first {
                importRequest = YouTubeImportRequest(link: "https://www.youtube.com/watch?v=\(suggestion.videoID)")
            } else {
                appModel.selectedTab = .explore
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SESSÃO DE HOJE")
                            .font(.caption.bold())
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.72))
                        Text("Seu treino de \(appModel.profile.dailyCommitment.rawValue) minutos")
                            .font(.title3.bold())
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 44))
                        .symbolRenderingMode(.hierarchical)
                }

                HStack {
                    Label(appModel.profile.level.title, systemImage: "text.quote")
                    Spacer()
                    Label(
                        recommendations.isEmpty ? "Ver vídeos" : "Começar",
                        systemImage: "play.fill"
                    )
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(
                LinearGradient(
                    colors: [ShadowingTheme.blue, ShadowingTheme.violet],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .shadow(color: ShadowingTheme.blue.opacity(0.28), radius: 24, y: 12)
        }
        .buttonStyle(.plain)
    }

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Escolhidos para você")
                        .font(.title2.bold())
                    Text("Com base nos temas e no seu nível")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Ver todos") { appModel.selectedTab = .explore }
                    .font(.subheadline.weight(.semibold))
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(recommendations.prefix(5)) { suggestion in
                        RecommendationCard(suggestion: suggestion) {
                            importRequest = YouTubeImportRequest(link: "https://www.youtube.com/watch?v=\(suggestion.videoID)")
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 1, for: .scrollContent)
            .scrollIndicators(.hidden)
            if isDiscoveringVideos {
                ProgressView("Buscando vídeos com legenda no seu nível…")
                    .tint(ShadowingTheme.blue)
            } else if recommendations.isEmpty {
                Text(videoDiscoveryError ?? "Ainda não encontramos vídeos com legenda adequados ao seu nível e temas. Você também pode colar um link.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Buscar novamente") {
                    Task { await loadSuggestedVideos(refresh: true) }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func loadSuggestedVideos(refresh: Bool = false) async {
        let profile = appModel.profile
        let requestID = UUID()
        videoDiscoveryRequestID = requestID
        isDiscoveringVideos = true
        videoDiscoveryError = nil
        if loadedProfile != profile { discoveredVideos = [] }
        defer { if videoDiscoveryRequestID == requestID { isDiscoveringVideos = false } }
        do {
            let videos = try await ShortsDiscoveryService.shared.discoverVideos(for: profile, refresh: refresh)
            guard !Task.isCancelled, videoDiscoveryRequestID == requestID else { return }
            discoveredVideos = videos
            loadedProfile = profile
        } catch {
            guard !Task.isCancelled, videoDiscoveryRequestID == requestID else { return }
            videoDiscoveryError = error.localizedDescription
        }
    }

    private var customVideoShortcut: some View {
        Button {
            appModel.selectedTab = .explore
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "link.badge.plus")
                    .font(.title3)
                    .foregroundStyle(ShadowingTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(ShadowingTheme.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tem um vídeo em mente?")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Busque pelo tema, canal ou cole o link.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(15)
            .shadowingGlass(cornerRadius: 22, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private var commitmentCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.title)
                .foregroundStyle(.orange)
                .frame(width: 52, height: 52)
                .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Primeiro dia da sequência")
                    .font(.headline)
                Text("Faça a sessão de hoje para acender seu ritmo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadowingGlass(cornerRadius: 24)
    }
}

struct RecommendationCard: View {
    let suggestion: VideoSuggestion
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    YouTubeThumbnailView(suggestion: suggestion)
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.82)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    HStack {
                        Label(suggestion.source.rawValue, systemImage: "play.fill")
                        Spacer()
                        if let durationMinutes = suggestion.durationMinutes {
                            Text("\(durationMinutes) min")
                        }
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(14)
                }
                .frame(height: 145)

                VStack(alignment: .leading, spacing: 7) {
                    Text(suggestion.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(suggestion.creator)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(suggestion.hook)
                        .font(.caption)
                        .foregroundStyle(ShadowingTheme.blue)
                        .lineLimit(1)
                }
                .padding(15)
            }
            .frame(width: 258)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct YouTubeThumbnailView: View {
    let suggestion: VideoSuggestion

    var body: some View {
        AsyncImage(url: suggestion.thumbnailURL, transaction: Transaction(animation: .easeInOut)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                fallback
            case .empty:
                ZStack {
                    fallback
                    ProgressView().tint(.white)
                }
            @unknown default:
                fallback
            }
        }
        .clipped()
    }

    private var fallback: some View {
        ZStack {
            ShadowingTheme.gradient(for: suggestion.accent)
            Image(systemName: suggestion.source == .shorts ? "rectangle.portrait.fill" : "play.rectangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

struct ExploreView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(StudyProgressStore.self) private var progressStore
    @State private var selectedInterest: LearningInterest?
    @State private var searchText = ""
    @State private var importRequest: YouTubeImportRequest?
    @State private var discoveredVideos: [VideoSuggestion] = []
    @State private var isDiscoveringVideos = false
    @State private var videoDiscoveryError: String?
    @State private var videoDiscoveryRequestID = UUID()
    @State private var loadedProfile: LearningProfile?
    @FocusState private var isSearchFocused: Bool

    private var suggestions: [VideoSuggestion] {
        let interestFiltered: [VideoSuggestion]
        if let selectedInterest {
            interestFiltered = appModel.recommendations(
                history: progressStore.recentVideos,
                feedback: progressStore.shortFeedback,
                catalog: discoveredVideos
            ).filter { $0.interests.contains(selectedInterest) }
        } else {
            interestFiltered = appModel.recommendations(
                history: progressStore.recentVideos,
                feedback: progressStore.shortFeedback,
                catalog: discoveredVideos
            )
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, YouTubeLinkParser.videoID(from: query) == nil else { return interestFiltered }

        return interestFiltered.filter { suggestion in
            let searchableText = [
                suggestion.title,
                suggestion.creator,
                suggestion.hook,
                suggestion.level.title,
                suggestion.interests.map(\.title).joined(separator: " ")
            ].joined(separator: " ")
            return searchableText.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text("Vídeos que combinam\ncom você")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    searchCard

                    if !progressStore.recentVideos.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Seu histórico")
                                .font(.title2.bold())
                            ForEach(progressStore.recentVideos.prefix(4)) { video in
                                Button {
                                    importRequest = YouTubeImportRequest(link: video.link)
                                } label: {
                                    HStack(spacing: 12) {
                                        AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(video.videoID)/hqdefault.jpg")) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            Image(systemName: "play.rectangle.fill")
                                                .foregroundStyle(ShadowingTheme.blue)
                                        }
                                        .frame(width: 88, height: 60)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(video.title).font(.subheadline.bold()).lineLimit(2)
                                            Text("\(video.channel) · frase \(video.phraseIndex + 1) de \(video.phraseCount)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.up.right")
                                            .foregroundStyle(ShadowingTheme.blue)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .shadowingGlass(cornerRadius: 22)
                    }

                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            FilterChip(title: "Para você", isSelected: selectedInterest == nil) {
                                selectedInterest = nil
                            }
                            ForEach(appModel.profile.interests.sorted(by: { $0.title < $1.title })) { interest in
                                FilterChip(title: interest.title, isSelected: selectedInterest == interest) {
                                    selectedInterest = interest
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    if isDiscoveringVideos && suggestions.isEmpty {
                        ProgressView("Encontrando vídeos com legenda…")
                            .tint(ShadowingTheme.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)
                    } else if suggestions.isEmpty {
                        ContentUnavailableView(
                            videoDiscoveryError == nil ? "Nenhum vídeo compatível" : "Busca indisponível",
                            systemImage: "play.rectangle",
                            description: Text(videoDiscoveryError ?? "Tente outro tema ou cole um link direto do YouTube.")
                        )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)
                        Button("Buscar novamente") {
                            Task { await loadSuggestedVideos(refresh: true) }
                        }
                        .font(.subheadline.weight(.semibold))
                    } else {
                        ForEach(suggestions) { suggestion in
                            Button {
                                importRequest = YouTubeImportRequest(link: "https://www.youtube.com/watch?v=\(suggestion.videoID)")
                            } label: {
                                HStack(spacing: 14) {
                                    YouTubeThumbnailView(suggestion: suggestion)
                                        .frame(width: 118, height: 82)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .overlay {
                                            Image(systemName: "play.fill")
                                                .font(.headline)
                                                .foregroundStyle(.white)
                                                .frame(width: 38, height: 38)
                                                .background(.black.opacity(0.45), in: Circle())
                                        }
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(suggestion.title)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                        Text(suggestion.durationMinutes.map { "\(suggestion.creator) • \($0) min" } ?? suggestion.creator)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(suggestion.hook)
                                            .font(.caption)
                                            .foregroundStyle(ShadowingTheme.blue)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .opaqueTopScrollEdge()
        }
        .navigationTitle("Vídeos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() } }
        // Fundo visível: sem ele, o conteúdo rolado passava por baixo do título e do relógio.
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: appModel.profile.interests) { _, interests in
            if let selectedInterest, !interests.contains(selectedInterest) {
                self.selectedInterest = nil
            }
        }
        .navigationDestination(item: $importRequest) { request in
            YouTubeImportView(initialLink: request.link)
        }
        .task(id: appModel.profile) { await loadSuggestedVideos() }
    }

    private func loadSuggestedVideos(refresh: Bool = false) async {
        let profile = appModel.profile
        let requestID = UUID()
        videoDiscoveryRequestID = requestID
        isDiscoveringVideos = true
        videoDiscoveryError = nil
        if loadedProfile != profile { discoveredVideos = [] }
        defer { if videoDiscoveryRequestID == requestID { isDiscoveringVideos = false } }
        do {
            let videos = try await ShortsDiscoveryService.shared.discoverVideos(for: profile, refresh: refresh)
            guard !Task.isCancelled, videoDiscoveryRequestID == requestID else { return }
            discoveredVideos = videos
            loadedProfile = profile
        } catch {
            guard !Task.isCancelled, videoDiscoveryRequestID == requestID else { return }
            videoDiscoveryError = error.localizedDescription
        }
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Busque do seu jeito")
                    .font(.headline)
                Text("Digite um tema, canal ou título — ou cole um link do YouTube.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Image(systemName: isDirectLink ? "link" : "magnifyingglass")
                    .foregroundStyle(ShadowingTheme.blue)

                TextField("Ex.: aviação, Marques Brownlee ou youtube.com…", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(isDirectLink ? .go : .search)
                    .focused($isSearchFocused)
                    .onSubmit { submitSearch() }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: submitSearch) {
                    Image(systemName: isDirectLink ? "arrow.up.right.circle.fill" : "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(ShadowingTheme.blue)
                }
                .buttonStyle(.plain)
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(isDirectLink ? "Abrir link" : "Buscar")
            }
            .padding(14)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if isDirectLink {
                Label("Link reconhecido. Toque na seta para preparar vídeo e legenda.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(ShadowingTheme.mint)
            }
        }
        .padding(16)
        .shadowingGlass(cornerRadius: 24)
    }

    private var isDirectLink: Bool {
        YouTubeLinkParser.videoID(from: searchText) != nil
    }

    private func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearchFocused = false
        if YouTubeLinkParser.videoID(from: query) != nil {
            importRequest = YouTubeImportRequest(link: query)
        }
    }
}

struct YouTubeImportRequest: Identifiable, Hashable {
    let id = UUID()
    let link: String
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? ShadowingTheme.blue : .white.opacity(0.06), in: Capsule())
            .buttonStyle(.plain)
    }
}

struct ProgressViewScreen: View {
    @Environment(AppModel.self) private var appModel
    @Environment(StudyProgressStore.self) private var progressStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @State private var difficultWordTranslationRequest: VocabularyTranslationRequest?

    private var wordGoal: Int {
        max(100, appModel.profile.dailyCommitment.rawValue * 20)
    }

    private var goalProgress: Double {
        min(Double(progressStore.today.words) / Double(wordGoal), 1)
    }

    private var currentStreak: Int {
        var streak = 0
        for day in progressStore.recentDays.reversed() {
            guard day.words > 0 else { break }
            streak += 1
        }
        return streak
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Seu inglês cresce\npalavra por palavra.")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Cada frase nova entra automaticamente no seu progresso.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(progressStore.today.words)")
                                .font(.system(size: 58, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())
                            Text("palavras\npraticadas hoje")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "text.word.spacing")
                                .font(.system(size: 34))
                                .foregroundStyle(ShadowingTheme.blue)
                        }

                        ProgressView(value: goalProgress)
                            .tint(ShadowingTheme.blue)
                            .scaleEffect(y: 1.7)

                        HStack {
                            Text("Meta diária: \(wordGoal) palavras")
                            Spacer()
                            Text("\(Int(goalProgress * 100))%")
                                .monospacedDigit()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(
                        LinearGradient(
                            colors: [ShadowingTheme.blue.opacity(0.24), ShadowingTheme.violet.opacity(0.13)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }

                    HStack(spacing: 12) {
                        progressMetric(
                            value: "\(progressStore.today.phrases)",
                            title: "frases hoje",
                            icon: "quote.bubble.fill",
                            color: ShadowingTheme.mint
                        )
                        progressMetric(
                            value: "\(currentStreak)",
                            title: currentStreak == 1 ? "dia seguido" : "dias seguidos",
                            icon: "flame.fill",
                            color: .orange
                        )
                    }

                    if progressStore.today.listeningAttempts > 0 {
                        progressMetric(
                            value: "\(progressStore.today.listeningAccuracy)%",
                            title: "acertos na escuta ativa • \(progressStore.today.listeningAttempts) tentativas",
                            icon: "ear.badge.checkmark",
                            color: ShadowingTheme.blue
                        )
                    }

                    weeklyChart
                    if #available(iOS 18.0, *) {
                        VocabularyTranslationContainer(
                            request: difficultWordTranslationRequest,
                            onTranslated: { request, translation in
                                vocabularyStore.setTranslation(
                                    translation,
                                    for: request.word,
                                    language: request.targetLanguage
                                )
                            }
                        ) {
                            difficultWordsSection
                        }
                    } else {
                        difficultWordsSection
                    }
                    vocabularySection
                }
                .padding(20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .opaqueTopScrollEdge()
        }
        .navigationTitle("Progresso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() } }
        // Fundo visível: sem ele, o conteúdo rolado passava por baixo do título e do relógio.
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func progressMetric(value: String, title: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold().monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadowingGlass(cornerRadius: 22)
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Últimos 7 dias")
                    .font(.title3.bold())
                Text("Palavras praticadas por dia")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 9) {
                ForEach(progressStore.recentDays) { day in
                    let ratio = min(Double(day.words) / Double(wordGoal), 1)
                    VStack(spacing: 7) {
                        Text(day.words > 0 ? "\(day.words)" : "")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(height: 12)

                        Capsule()
                            .fill(day.words > 0 ? ShadowingTheme.blue : .white.opacity(0.08))
                            .frame(height: max(7, 86 * ratio))

                        if let date = StudyProgressStore.date(from: day.dayKey) {
                            Text(date, format: .dateTime.weekday(.narrow))
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 125, alignment: .bottom)
        }
        .padding(19)
        .shadowingGlass(cornerRadius: 24)
    }

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Meu vocabulário")
                        .font(.title3.bold())
                    Text("Palavras que você marcou durante o shadowing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(vocabularyStore.entries.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(ShadowingTheme.mint)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(ShadowingTheme.mint.opacity(0.12), in: Capsule())
            }

            if vocabularyStore.entries.isEmpty {
                Label("Toque em qualquer palavra no quadro “Ouça e repita” para começar.", systemImage: "hand.tap.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(vocabularyStore.recentEntries.prefix(8)) { entry in
                        HStack {
                            Text(entry.word)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            let translation = entry.translation(for: appModel.profile.nativeLanguage)
                            Text(translation ?? "Sem tradução")
                                .font(.subheadline)
                                .foregroundStyle(translation == nil ? Color.secondary : ShadowingTheme.mint)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(19)
        .shadowingGlass(cornerRadius: 24)
    }

    private var difficultWordsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Palavras para revisar", systemImage: "ear.badge.waveform")
                .font(.title3.bold())
                .foregroundStyle(ShadowingTheme.blue)

            if progressStore.difficultWords.isEmpty {
                Text("As palavras que você errar na Escuta Ativa aparecerão aqui.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Cada erro pede dois acertos para sair da revisão.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(progressStore.difficultWords.prefix(8)) { performance in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(performance.word)
                                .font(.headline)
                            Text("\(performance.mistakes) \(performance.mistakes == 1 ? "erro" : "erros") · \(performance.correct) \(performance.correct == 1 ? "acerto" : "acertos")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 4)

                        if vocabularyStore.contains(performance.word) {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(ShadowingTheme.mint)
                                .accessibilityLabel("\(performance.word) no vocabulário")
                        } else {
                            Button {
                                saveDifficultWord(performance.word)
                            } label: {
                                Image(systemName: "bookmark.badge.plus")
                                    .font(.title3)
                                    .foregroundStyle(ShadowingTheme.blue)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Adicionar \(performance.word) ao vocabulário")
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(19)
        .shadowingGlass(cornerRadius: 24)
    }

    private func saveDifficultWord(_ word: String) {
        guard vocabularyStore.add(word) else { return }
        difficultWordTranslationRequest = VocabularyTranslationRequest(
            word: word,
            sourceLanguage: appModel.profile.learningLanguage,
            targetLanguage: appModel.profile.nativeLanguage
        )
    }
}

struct ProfileView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AuthSession.self) private var authSession
    @Environment(StudyProgressStore.self) private var progressStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(CloudStudySync.self) private var cloudStudySync
    @Environment(\.openURL) private var openURL
    @State private var showAuth = false
    @State private var showDeletion = false
    @State private var accountError: String?
    @State private var showInterests = false

    var body: some View {
        @Bindable var model = appModel

        ZStack {
            AtmosphericBackground()
            List {
                Section("Idiomas") {
                    Picker("Eu falo", selection: $model.profile.nativeLanguage) {
                        ForEach(SupportedLanguage.nativeOptions) { language in
                            Text(language.title).tag(language)
                        }
                    }

                    LabeledContent("Estou aprendendo", value: model.profile.learningLanguage.title)

                    Text("As traduções das frases e do vocabulário usam o idioma escolhido aqui.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Seu plano") {
                    Picker("Nível", selection: $model.profile.level) {
                        ForEach(EnglishLevel.allCases) { level in Text(level.title).tag(level) }
                    }
                    Picker("Meta diária", selection: $model.profile.dailyCommitment) {
                        ForEach(DailyCommitment.allCases) { commitment in Text(commitment.title).tag(commitment) }
                    }
                    Button("Interesses · \(appModel.profile.interests.count) \(appModel.profile.interests.count == 1 ? "tema" : "temas")") { showInterests = true }
                    Text("Ajuste seu nível quando o treino parecer fácil ou difícil demais.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Treino") {
                    Stepper(value: $model.profile.repeatPauseExtraPercent, in: 0...100, step: 10) {
                        LabeledContent("Tempo extra para repetir", value: "+\(model.profile.repeatPauseExtraPercent)%")
                    }
                    Text("Trecho de 2 segundos → pausa de \((2 * (1 + Double(model.profile.repeatPauseExtraPercent) / 100)).formatted(.number.precision(.fractionLength(1)))) segundos. Vale para vídeos e Shorts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Conta") {
                    if let account = authSession.user {
                        LabeledContent("Conectado como", value: account.name)
                        if let email = account.email {
                            Text(email).font(.footnote).foregroundStyle(.secondary)
                        }
                        switch cloudStudySync.status {
                        case .signedOut:
                            EmptyView()
                        case .loading:
                            Label("Carregando seus estudos da nuvem…", systemImage: "icloud.and.arrow.down")
                        case .pending:
                            Label("Salvando seus estudos na nuvem…", systemImage: "icloud.and.arrow.up")
                        case .synced:
                            Label("Estudos sincronizados", systemImage: "icloud.fill")
                                .foregroundStyle(ShadowingTheme.mint)
                        case .failed(let message):
                            VStack(alignment: .leading, spacing: 8) {
                                Text(message).font(.caption).foregroundStyle(ShadowingTheme.coral)
                                Button("Tentar sincronizar novamente") {
                                    Task {
                                        await cloudStudySync.retry(
                                            appModel: appModel,
                                            progressStore: progressStore,
                                            vocabularyStore: vocabularyStore
                                        )
                                    }
                                }
                            }
                        }
                        Button("Sair da conta", systemImage: "rectangle.portrait.and.arrow.right") {
                            do {
                                try authSession.signOut()
                            } catch {
                                accountError = AuthSession.message(for: error)
                            }
                        }
                        Button("Excluir minha conta", systemImage: "trash", role: .destructive) {
                            showDeletion = true
                        }
                    } else {
                        Button("Entrar ou criar conta", systemImage: "person.badge.key.fill") {
                            showAuth = true
                        }
                    }
                    Button("Gerenciar assinatura", systemImage: "creditcard.fill") {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            openURL(url)
                        }
                    }
                    if let accountError {
                        Text(accountError).foregroundStyle(ShadowingTheme.coral)
                    }
                }

                Section("Personalização") {
                    Button("Refazer personalização", systemImage: "arrow.counterclockwise") {
                        appModel.resetOnboarding()
                    }
                    .foregroundStyle(ShadowingTheme.coral)
                }

                Section("ShadowingApp") {
                    if !BuildAvailability.purchasesEnabled {
                        Label("Beta gratuito · sem compras nesta versão", systemImage: "gift.fill")
                            .foregroundStyle(ShadowingTheme.mint)
                    }
                    LegalLinksView()
                    LabeledContent("Versão", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }
            }
            .scrollContentBackground(.hidden)
            .onChange(of: model.profile) { _, _ in
                appModel.saveProfile()
            }
        }
        .navigationTitle("Perfil")
        .sheet(isPresented: $showAuth) { AccountAccessView() }
        .sheet(isPresented: $showDeletion) { AccountDeletionView() }
        .sheet(isPresented: $showInterests) {
            NavigationStack {
                List(LearningInterest.allCases) { interest in
                    let selected = model.profile.interests.contains(interest)
                    Button {
                        if selected {
                            model.profile.interests.remove(interest)
                        } else {
                            model.profile.interests.insert(interest)
                        }
                    } label: {
                        HStack {
                            Label(interest.title, systemImage: interest.icon)
                            Spacer()
                            if selected { Image(systemName: "checkmark.circle.fill") }
                        }
                    }
                    .disabled(selected && model.profile.interests.count == 1)
                }
                .navigationTitle("Seus interesses")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Concluir") { showInterests = false }
                    }
                }
            }
        }
    }
}

private struct PracticePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let suggestion: VideoSuggestion
    @State private var isPlaying = false

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground()
                VStack(spacing: 26) {
                    YouTubeThumbnailView(suggestion: suggestion)
                        .aspectRatio(16 / 10, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay {
                            Button {
                                isPlaying.toggle()
                            } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white)
                                    .frame(width: 76, height: 76)
                                    .background(.black.opacity(0.28), in: Circle())
                            }
                        }

                    VStack(spacing: 12) {
                        Text("I want to make this sound natural.")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("Eu quero fazer isso soar natural.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(1.2)
                    }

                    HStack(spacing: 28) {
                        Button("Anterior", systemImage: "backward.end.fill") { }
                        Button("Gravar", systemImage: "mic.fill") { }
                        Button("Próxima", systemImage: "forward.end.fill") { }
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .buttonStyle(.bordered)
                    .tint(ShadowingTheme.blue)

                    Text("Prévia funcional da experiência. O player e a segmentação serão conectados na próxima etapa.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .navigationTitle(suggestion.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}
