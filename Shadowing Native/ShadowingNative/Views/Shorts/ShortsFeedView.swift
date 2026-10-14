import SwiftUI

struct ShortsFeedView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var appModel
    @Environment(StudyProgressStore.self) private var progressStore
    @State private var items: [YouTubeShortItem] = []
    @State private var catalog: [YouTubeShortItem] = []
    @State private var sharedCatalog = SharedShortCatalog()
    @State private var preparedLessons: [String: PreparedShortLesson] = [:]
    @State private var sharedScores: [String: Int] = [:]
    @State private var visiblePage: YouTubeShortItem.ID?
    @State private var discoveryNotice: String?
    @State private var isDiscovering = false
    @State private var canLoadMore = true
    @State private var lastHiddenItem: YouTubeShortItem?
    @State private var lastHiddenWasDifficulty = false
    @State private var isScrolling = false
    @State private var refreshID = 0
    @State private var discoveryRequestID = UUID()
    @State private var isTypingResponse = false
    @State private var isSearchPresented = false
    @State private var pinnedShortIDs: Set<String> = []
    var previewItems: [YouTubeShortItem]? = nil
    var previewTranscript: YouTubeTranscript? = nil

    private var visibleItemID: YouTubeShortItem.ID? {
        guard let visiblePage, items.contains(where: { $0.id == visiblePage }) else { return nil }
        return visiblePage
    }

    private var visibleIndex: Int? {
        items.firstIndex { $0.id == visibleItemID }
    }

    var body: some View {
        ZStack {
            ShadowingTheme.ink.ignoresSafeArea()

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        let index = items.firstIndex(where: { $0.id == item.id }) ?? 0
                        VStack(spacing: 0) {
                        ShortLessonPage(
                            item: item,
                            position: index + 1,
                            total: items.count,
                            isActive: visibleItemID == item.id && appModel.selectedTab == .shorts && scenePhase == .active && !isScrolling && !isSearchPresented,
                            isVisible: visibleItemID == item.id,
                            // O vizinho já abre o player escondido: ao rolar, o vídeo está pronto em vez de preto.
                            shouldLoadPlayer: visibleIndex.map { abs($0 - index) <= 1 } ?? false,
                            preparedTranscript: preparedLessons[item.videoID]?.transcript ?? previewTranscript,
                            preparedPhrases: preparedLessons[item.videoID]?.phrases,
                            isLayoutPreview: preparedLessons[item.videoID] == nil && previewTranscript != nil,
                            onShuffle: shuffleFeed,
                            onSearch: { isSearchPresented = true },
                            onRateDifficulty: { rating in
                                progressStore.rateDifficulty(of: item, as: rating)
                                if rating == .tooHard {
                                    lastHiddenItem = item
                                    lastHiddenWasDifficulty = true
                                }
                            },
                            onReact: { reaction in
                                progressStore.react(to: item, as: reaction)
                                Task { await ShortCatalogSignals.record(item: item, profile: appModel.profile, reaction: progressStore.shortFeedback[item.videoID]?.reaction ?? .neutral) }
                                if reaction == .hidden {
                                    lastHiddenItem = item
                                    lastHiddenWasDifficulty = false
                                }
                            },
                            onTypingChanged: { focused in isTypingResponse = focused }
                        )
                        .id(item.id)
                        }
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .modifier(OneShortPerSwipe())
            .scrollPosition(id: $visiblePage)
            .modifier(FeedScrollActivity(isScrolling: $isScrolling))
            .scrollDismissesKeyboard(.interactively)
            .clipped()

            if items.isEmpty {
                VStack(spacing: 14) {
                    if isDiscovering { ProgressView().tint(ShadowingTheme.blue) }
                    Image(systemName: isDiscovering ? "sparkle.magnifyingglass" : "rectangle.portrait.slash")
                        .font(.largeTitle)
                        .foregroundStyle(ShadowingTheme.blue)
                    Text(isDiscovering ? "Buscando Shorts no seu nível…" : "Ainda não há Shorts prontos para o seu nível.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if !isDiscovering {
                        Text("Use a lupa para buscar um assunto ou canal.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Buscar Shorts ou canais", systemImage: "magnifyingglass") { isSearchPresented = true }
                            .buttonStyle(.borderedProminent)
                        Button("Buscar novamente") { refreshID += 1 }
                            .buttonStyle(.bordered)
                        Button("Explorar vídeos") { appModel.selectedTab = .explore }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(30)
            }

            if let discoveryNotice {
                VStack(spacing: 5) {
                    Text(discoveryNotice)
                        .foregroundStyle(.secondary)
                    if !isDiscovering, !items.isEmpty, canLoadMore {
                        Button("Buscar mais Shorts") {
                            Task { await discoverShorts() }
                        }
                        .fontWeight(.semibold)
                    }
                }
                    .font(.caption2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 54)
            }

            if isDiscovering && !items.isEmpty {
                ProgressView()
                    .font(.caption2)
                    .scaleEffect(0.7)
                    .accessibilityLabel("Preparando próximos Shorts")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 7)
                    .padding(.top, 48)
                    .allowsHitTesting(false)
            }

            if let lastHiddenItem {
                HStack(spacing: 12) {
                    Text("Short ocultado")
                    Button("Desfazer") {
                        if lastHiddenWasDifficulty {
                            progressStore.rateDifficulty(of: lastHiddenItem, as: .justRight)
                        } else {
                            progressStore.react(to: lastHiddenItem, as: .hidden)
                        }
                        self.lastHiddenItem = nil
                    }
                    .fontWeight(.bold)
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 54)
            }

        }
        .ignoresSafeArea(.keyboard)
        .toolbarBackground(.hidden, for: .tabBar)
        .sheet(isPresented: $isSearchPresented, onDismiss: {
            canLoadMore = true
            Task { await discoverShorts() }
        }) {
            ShortsSearchView { item in
                pinnedShortIDs.insert(item.videoID)
                if !catalog.contains(where: { $0.videoID == item.videoID }) { catalog.append(item) }
                rankFeed()
                visiblePage = item.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isTypingResponse = false
        }
        .task(id: DiscoveryRequest(profile: appModel.profile, revision: refreshID)) {
            discoveryRequestID = UUID()
            isDiscovering = false
            canLoadMore = true
            isTypingResponse = false
            catalog = []
            pinnedShortIDs = []
            preparedLessons = [:]
            sharedScores = [:]
            sharedCatalog.reset(for: appModel.profile.level)
            items = []
            visiblePage = nil
            lastHiddenItem = nil
            discoveryNotice = nil
            if let previewItems {
                catalog = previewItems
                shuffleFeed()
                return
            }
            await discoverShorts()
        }
        .onChange(of: visibleItemID) { _, itemID in
            if let item = items.first(where: { $0.id == itemID }) {
                Task { await ShortCatalogSignals.recordView(item: item, profile: appModel.profile) }
            }
            guard let itemID,
                  let index = items.firstIndex(where: { $0.id == itemID }),
                  index >= items.count - 4 else { return }
            Task { await discoverShorts() }
        }
        .onChange(of: progressStore.shortFeedback) { _, _ in
            rankFeed()
        }
        .onChange(of: progressStore.shortChannels) { _, _ in
            rankFeed()
            canLoadMore = true
            Task { await discoverShorts() }
        }
        .onChange(of: progressStore.shortSearches) { _, _ in rankFeed() }
    }

    private func shuffleFeed() {
        let currentID = visibleItemID
        rankFeed(resetPosition: true)
        if items.count > 1, items.first?.id == currentID {
            items.append(items.removeFirst())
            visiblePage = items.first?.id
        }
    }

    private func rankFeed(resetPosition: Bool = false) {
        let previousID = visibleItemID
        let previousIndex = items.firstIndex { $0.id == previousID } ?? 0
        let ranked = ShortsRecommendationEngine().feed(
            for: appModel.profile,
            history: progressStore.recentVideos,
            feedback: progressStore.shortFeedback,
            preferredChannelIDs: Set(progressStore.followedShortChannels.map(\.id)),
            preferredQueries: Set(progressStore.recentShortSearches.map { $0.query.lowercased() }),
            sharedScores: sharedScores,
            pinnedIDs: pinnedShortIDs,
            catalog: catalog
        )
        if resetPosition {
            items = ranked
        } else {
            let eligibleIDs = Set(ranked.map(\.id))
            let visited = items.prefix(previousIndex + 1).filter { eligibleIDs.contains($0.id) }
            let visitedIDs = Set(visited.map(\.id))
            items = visited + ranked.filter { !visitedIDs.contains($0.id) }
        }
        if !resetPosition, let previousID, items.contains(where: { $0.id == previousID }) {
            visiblePage = previousID
        } else {
            visiblePage = items.isEmpty ? nil : items[min(previousIndex, items.count - 1)].id
        }
        if resetPosition {
            visiblePage = items.first?.id
        }
    }

    private func discoverShorts() async {
        guard previewItems == nil, !isDiscovering, canLoadMore else { return }
        let requestID = UUID()
        discoveryRequestID = requestID
        isDiscovering = true
        discoveryNotice = nil
        var shouldContinue = false
        defer {
            if discoveryRequestID == requestID {
                isDiscovering = false
                if shouldContinue { Task { await discoverShorts() } }
            }
        }
        do {
            if sharedCatalog.hasMore {
                let approved: [PreparedShortLesson]
                do {
                    approved = try await sharedCatalog.nextPage(for: appModel.profile)
                } catch {
                    sharedCatalog.markUnavailable()
                    discoveryNotice = "Não foi possível carregar os Shorts. Verifique a conexão e tente novamente."
                    return
                }
                guard !Task.isCancelled, discoveryRequestID == requestID else { return }
                for lesson in approved where !catalog.contains(where: { $0.videoID == lesson.item.videoID }) {
                    catalog.append(lesson.item)
                    preparedLessons[lesson.item.videoID] = lesson
                    sharedScores[lesson.item.videoID] = lesson.item.interests.intersection(appModel.profile.interests)
                        .reduce(0) { $0 + lesson.affinity[$1.rawValue, default: 0] }
                }
                if !approved.isEmpty {
                    rankFeed(resetPosition: items.isEmpty)
                    discoveryNotice = nil
                    let currentIndex = items.firstIndex { $0.id == visibleItemID } ?? 0
                    shouldContinue = sharedCatalog.hasMore && (items.count - currentIndex <= 4)
                    return
                }
                if sharedCatalog.hasMore {
                    shouldContinue = true
                    return
                }
            }
            canLoadMore = false
            discoveryNotice = items.isEmpty ? nil : "Você viu todos os Shorts do seu nível por hoje. Novos chegam todos os dias."
        } catch {
            guard !Task.isCancelled, discoveryRequestID == requestID else { return }
            discoveryNotice = error.localizedDescription
        }
    }
}

private struct DiscoveryRequest: Equatable {
    let profile: LearningProfile
    let revision: Int
}

private struct ShortLessonPage: View {
    @Environment(AppModel.self) private var appModel
    @Environment(StudyProgressStore.self) private var progressStore
    let item: YouTubeShortItem
    let position: Int
    let total: Int
    let isActive: Bool
    let isVisible: Bool
    let shouldLoadPlayer: Bool
    let preparedTranscript: YouTubeTranscript?
    let preparedPhrases: [ShadowingPhrase]?
    /// Só a auditoria de layout troca o vídeo por um retângulo; aulas prontas do catálogo tocam o YouTube.
    let isLayoutPreview: Bool

    /// `item.topic` vem do primeiro tema de um Set (ordem aleatória); mostra um tema em comum com o perfil.
    private var displayTopic: String {
        item.interests.intersection(appModel.profile.interests)
            .sorted { $0.rawValue < $1.rawValue }.first?.title ?? item.topic
    }
    let onShuffle: () -> Void
    let onSearch: () -> Void
    let onRateDifficulty: (ShortDifficultyRating) -> Void
    let onReact: (ShortReaction) -> Void
    let onTypingChanged: (Bool) -> Void

    @State private var playerController = YouTubePlayerController()
    @State private var transcript: YouTubeTranscript?
    @State private var phrases: [ShadowingPhrase] = []
    @State private var selectedPhraseID: ShadowingPhrase.ID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isTranslationVisible = false
    @State private var blankCount = 1
    @State private var phraseTranslations: [UUID: String] = [:]
    @State private var exerciseMode: ExerciseMode = .shadowing
    @State private var difficultWordsForExercise: Set<String> = []
    @State private var transcriptLoadID = UUID()
    @State private var isTypingResponse = false
    @State private var keyboardTop: CGFloat?
    @State private var englishHeight: CGFloat = 68
    @State private var translationHeight: CGFloat = 48
    @State private var dictationHeight: CGFloat = 80

    private var selectedPhrase: ShadowingPhrase? {
        phrases.first { $0.id == selectedPhraseID }
    }

    private var activeListeningExercise: ActiveListeningExercise? {
        guard exerciseMode == .multipleChoice, let selectedPhrase else { return nil }
        return ActiveListeningExerciseBuilder().build(
            phrase: selectedPhrase,
            phraseIndex: phraseIndex,
            lessonPhrases: phrases,
            level: appModel.profile.level,
            difficultWords: difficultWordsForExercise,
            blankCount: blankCount
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let keyboardOverlap = isTypingResponse
                ? max(0, geometry.frame(in: .global).maxY - (keyboardTop ?? geometry.frame(in: .global).maxY))
                : 0
            let isKeyboardPresented = keyboardOverlap > 80
            let usableHeight = max(1, geometry.size.height - keyboardOverlap)
            ZStack {
                background

                VStack(spacing: 6) {
                    header
                        .fixedSize(horizontal: false, vertical: true)
                    GeometryReader { playerGeometry in
                        let height = isKeyboardPresented ? 1 : max(1, min(playerGeometry.size.height, playerGeometry.size.width * 16 / 9))
                        player(height: height)
                            .frame(width: playerGeometry.size.width, height: playerGeometry.size.height, alignment: .bottom)
                    }
                    .frame(height: isKeyboardPresented ? 1 : nil)
                    .opacity(isKeyboardPresented ? 0 : 1)
                    .allowsHitTesting(!isKeyboardPresented)
                    if isKeyboardPresented { Spacer(minLength: 0) }
                    lessonPanel(contentHeight: min(panelContentHeight, max(110, usableHeight - 245), geometry.size.height * 0.43))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 7)
                .padding(.top, 5)
                .padding(.bottom, 4)
                .frame(height: usableHeight)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            keyboardTop = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.minY
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardTop = nil
        }
        .task(id: shouldLoadPlayer) {
            if shouldLoadPlayer {
                await loadTranscriptIfNeeded()
#if DEBUG && targetEnvironment(simulator)
                if isLayoutPreview {
                    let arguments = ProcessInfo.processInfo.arguments
                    isTranslationVisible = arguments.contains("--audit-show-translation")
                    if arguments.contains("--audit-active-listening") { selectActiveListeningMode() }
                    if arguments.contains("--audit-typing-keyboard") { exerciseMode = .typing }
                }
#endif
                startSelectedPhraseIfPossible()
            }
        }
        .onChange(of: isActive, initial: true) { _, active in
            playerController.setPlaybackAllowed(active)
            if active { startSelectedPhraseIfPossible() }
        }
        .onChange(of: playerController.isReady) { _, isReady in
            guard isReady else { return }
            startSelectedPhraseIfPossible()
        }
        .onChange(of: playerController.state) { _, state in
            if state == .playing, isActive, let selectedPhrase {
                progressStore.record(phrase: selectedPhrase, videoID: item.videoID)
            }
        }
        .onDisappear {
            isTypingResponse = false
            onTypingChanged(false)
            playerController.setPlaybackAllowed(false)
        }
        .onChange(of: isVisible) { _, visible in
            if !visible {
                isTypingResponse = false
                onTypingChanged(false)
            }
        }
    }

    private var background: some View {
        ZStack {
            ShadowingTheme.ink
            RadialGradient(
                colors: [ShadowingTheme.blue.opacity(0.28), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 460
            )
            RadialGradient(
                colors: [ShadowingTheme.violet.opacity(0.2), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 420
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SHADOWING SHORTS")
                    .font(.caption2.bold())
                    .tracking(1.5)
                    .foregroundStyle(ShadowingTheme.blue)
                Text("\(item.level.title) • \(displayTopic)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer()

            Text("\(position)/\(total)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Buscar Shorts e canais")

            Button {
                onReact(.liked)
            } label: {
                Image(systemName: progressStore.shortFeedback[item.videoID]?.reaction == .liked ? "heart.fill" : "heart")
                    .foregroundStyle(progressStore.shortFeedback[item.videoID]?.reaction == .liked ? ShadowingTheme.coral : .white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(progressStore.shortFeedback[item.videoID]?.reaction == .liked ? "Descurtir Short" : "Curtir Short")

            Menu {
                if let channelID = item.channelID, let creator = item.creator {
                    let isFollowed = progressStore.shortChannels[channelID]?.isFollowed == true
                    Button(isFollowed ? "Deixar de seguir canal" : "Seguir \(creator)", systemImage: isFollowed ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus") {
                        progressStore.setShortChannel(channelID, title: creator, followed: !isFollowed)
                    }
                }
                Section("Dificuldade deste Short") {
                    Button("Muito fácil", systemImage: "tortoise") { onRateDifficulty(.tooEasy) }
                    Button("No meu ritmo", systemImage: "checkmark") { onRateDifficulty(.justRight) }
                    Button("Muito difícil", systemImage: "hare") { onRateDifficulty(.tooHard) }
                }
                Button("Não quero ver", systemImage: "eye.slash") { onReact(.hidden) }
                Button("Ver outra sugestão", systemImage: "arrow.down", action: onShuffle)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .accessibilityLabel("Opções do Short")
        }
    }

    private func player(height: CGFloat) -> some View {
        Group {
            if isLayoutPreview {
                ZStack {
                    LinearGradient(colors: [.black, ShadowingTheme.blue.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 12) {
                        Image(systemName: "play.rectangle").font(.largeTitle)
                        Text("Prévia de layout").font(.headline)
                        Text("Vídeo vertical · 9:16").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            } else if shouldLoadPlayer {
                YouTubePlayerView(videoID: item.videoID, controller: playerController, allowsAutoplay: true)
                    .overlay {
                        if !playerController.hasRenderedVideo {
                            thumbnail
                                .overlay { if isVisible { ProgressView().tint(.white) } }
                        }
                    }
            } else {
                thumbnail
            }
        }
        .frame(width: max(200, height * 9 / 16), height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var thumbnail: some View {
        AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(item.videoID)/hqdefault.jpg")) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(.black).overlay { Image(systemName: "play.rectangle").foregroundStyle(.secondary) }
        }
        .background(.black)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func lessonPanel(contentHeight: CGFloat) -> some View {
        if isLoading {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(ShadowingTheme.blue)
                Text("Preparando as frases deste Short…")
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .shadowingGlass(cornerRadius: 22)
        } else if let errorMessage {
            VStack(spacing: 7) {
                Label("Short sem legenda acessível", systemImage: "captions.bubble.fill")
                    .font(.headline)
                    .foregroundStyle(ShadowingTheme.coral)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("O vídeo continua disponível. Deslize para o próximo.")
                    .font(.caption.weight(.semibold))
                Button("Tentar legenda novamente") {
                    self.errorMessage = nil
                    Task { await loadTranscriptIfNeeded() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(ShadowingTheme.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
        } else if let phrase = selectedPhrase {
            VStack(spacing: 5) {
                HStack {
                    PracticeModeSelector(
                        isActiveListening: exerciseMode.isActiveListening,
                        onSelectShadowing: selectShadowingMode,
                        onSelectActiveListening: selectActiveListeningMode
                    )
                    Spacer(minLength: 6)
                    Text("\(phraseIndex + 1)/\(phrases.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(panelTitle)
                    .font(.caption2.bold())
                    .tracking(1.3)
                    .foregroundStyle(exerciseMode.isActiveListening ? ShadowingTheme.mint : ShadowingTheme.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if exerciseMode.isActiveListening {
                    ActiveListeningOptionsView(
                        mode: $exerciseMode,
                        blankCount: $blankCount,
                        maximumBlanks: ActiveListeningExerciseBuilder().eligibleWordCount(in: phrase.text)
                    )
                }

                Group {
                    if exerciseMode == .multipleChoice, activeListeningExercise == nil {
                        Text("Não há palavras elegíveis. Use Frase inteira ou avance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let activeListeningExercise {
                        ActiveListeningExerciseView(
                            exercise: activeListeningExercise,
                            compact: true,
                            onReplay: { playerController.play(phrase: phrase) },
                            onResult: { word, isCorrect in
                                progressStore.recordListeningAttempt(word: word, isCorrect: isCorrect)
                            }
                        )
                        .id(activeListeningExercise.id)
                    } else if exerciseMode == .typing {
                        HiddenCaptionDictationView(reference: phrase.text) { focused in
                            isTypingResponse = focused
                            onTypingChanged(focused)
                        }
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { dictationHeight = $0 }
                            .id(phrase.id)
                    } else {
                        PracticeCaptionView(
                            phrase: phrase, font: .body.weight(.semibold),
                            showsTranslation: isTranslationVisible,
                            sourceLanguage: appModel.profile.learningLanguage,
                            targetLanguage: appModel.profile.nativeLanguage,
                            translations: $phraseTranslations,
                            onEnglishHeight: { englishHeight = $0 },
                            onTranslationHeight: { translationHeight = $0 }
                        )
                    }
                }
                .frame(height: contentHeight, alignment: exerciseMode == .typing ? .bottom : .top)

                if let playbackError = playerController.playbackError {
                    Text(playbackError).font(.caption2).foregroundStyle(ShadowingTheme.coral)
                }

                controls
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .shadowingGlass(cornerRadius: 24)
        } else {
            VStack(spacing: 5) {
                Text(item.title)
                    .font(.headline)
                Text(item.hook)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(16)
            .shadowingGlass(cornerRadius: 22)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            controlButton("backward.end.fill", label: "Frase anterior", isEnabled: phraseIndex > 0) {
                movePhrase(by: -1)
            }

            Button {
                playerController.togglePlayPause()
            } label: {
                Image(systemName: playerController.isPlaybackRequested ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 46, height: 46)
                    .foregroundStyle(.white)
                    .background(ShadowingTheme.blue, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerController.isPlaybackRequested ? "Pausar treino" : "Reproduzir")

            controlButton("forward.end.fill", label: "Próxima frase", isEnabled: phraseIndex + 1 < phrases.count) {
                movePhrase(by: 1)
            }

            controlButton(
                playerController.isLoopEnabled ? "repeat.circle.fill" : "repeat.circle",
                label: "Alternar repetição",
                tint: playerController.isLoopEnabled ? ShadowingTheme.blue : .secondary
            ) {
                if playerController.isLoopEnabled {
                    playerController.stopLoop()
                } else {
                    playerController.startLoop()
                }
            }

            if !exerciseMode.isActiveListening {
                controlButton(
                    isTranslationVisible ? "eye.fill" : "eye.slash.fill",
                    label: isTranslationVisible ? "Ocultar tradução" : "Mostrar tradução",
                    tint: isTranslationVisible ? ShadowingTheme.mint : .white
                ) {
                    isTranslationVisible.toggle()
                }
            }
        }
    }

    private var panelTitle: String {
        if exerciseMode.isActiveListening {
            return exerciseMode == .multipleChoice ? "QUAL PALAVRA VOCÊ OUVIU?" : "DIGITE O QUE VOCÊ OUVIU"
        }
        return playerController.isWaitingForStudent ? "SUA VEZ" : "OUÇA E REPITA"
    }

    private var panelContentHeight: CGFloat {
        if exerciseMode == .multipleChoice { return 226 }
        if exerciseMode == .typing { return max(80, dictationHeight + 8) }
        guard let selectedPhrase else { return 68 }
        return max(68, englishHeight + (isTranslationVisible ? max(48, translationHeight + 4) + 6 : 0) + (selectedPhrase.needsExpandedPractice ? 25 : 0) + 18)
    }

    private func controlButton(
        _ systemImage: String,
        label: String,
        tint: Color = .white,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.25))
                .background(.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private var phraseIndex: Int {
        guard let selectedPhraseID,
              let index = phrases.firstIndex(where: { $0.id == selectedPhraseID }) else { return 0 }
        return index
    }

    private func loadTranscriptIfNeeded() async {
        guard transcript == nil, errorMessage == nil else { return }
        let requestID = UUID()
        transcriptLoadID = requestID
        isLoading = true
        defer { if transcriptLoadID == requestID { isLoading = false } }

        do {
            let loadedTranscript: YouTubeTranscript
            if let preparedTranscript {
                loadedTranscript = preparedTranscript
            } else {
                loadedTranscript = try await YouTubeTranscriptService.shared.fetchTranscript(videoID: item.videoID)
            }
            try Task.checkCancellation()
            guard transcriptLoadID == requestID else { return }
            let preparedPhrases = self.preparedPhrases ?? ShadowingLessonBuilder(level: appModel.profile.level).build(from: loadedTranscript)
            guard !preparedPhrases.isEmpty else { throw TranscriptError.emptyCaptions }
            transcript = loadedTranscript
            phrases = preparedPhrases
            let savedStart = progressStore.videos[item.videoID]?.phraseStart
            selectedPhraseID = savedStart.flatMap { start in
                preparedPhrases.min { abs($0.start - start) < abs($1.start - start) }?.id
            } ?? preparedPhrases.first?.id
        } catch {
            if !Task.isCancelled, transcriptLoadID == requestID { errorMessage = error.localizedDescription }
        }
    }

    private func startSelectedPhraseIfPossible() {
        guard isActive, playerController.isReady, let selectedPhrase else { return }
        guard playerController.activePhrase?.id != selectedPhrase.id || !playerController.isPlaybackRequested else { return }
        remember(selectedPhrase)
        playerController.play(phrase: selectedPhrase)
    }

    private func movePhrase(by offset: Int) {
        let nextIndex = phraseIndex + offset
        guard phrases.indices.contains(nextIndex) else { return }
        let phrase = phrases[nextIndex]
        if exerciseMode.isActiveListening {
            difficultWordsForExercise = Set(progressStore.difficultWords.map(\.word))
        }
        selectedPhraseID = phrase.id
        remember(phrase)
        playerController.play(phrase: phrase)
    }

    private func remember(_ phrase: ShadowingPhrase) {
        guard let transcript, let index = phrases.firstIndex(of: phrase) else { return }
        progressStore.rememberVideo(
            videoID: item.videoID,
            title: transcript.title,
            channel: transcript.channel,
            isShort: true,
            phrase: phrase,
            phraseIndex: index,
            phraseCount: phrases.count
        )
    }

    private func selectShadowingMode() {
        exerciseMode = .shadowing
        if let selectedPhrase {
            playerController.play(phrase: selectedPhrase)
        }
    }

    private func selectActiveListeningMode() {
        difficultWordsForExercise = Set(progressStore.difficultWords.map(\.word))
        if !exerciseMode.isActiveListening { exerciseMode = .multipleChoice }
        if let selectedPhrase {
            playerController.play(phrase: selectedPhrase)
        }
    }
}

/// Um Short por gesto, sempre parando alinhado ao topo da página (nunca entre dois Shorts).
private struct OneShortPerSwipe: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        } else {
            content.scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        }
    }
}

private struct FeedScrollActivity: ViewModifier {
    @Binding var isScrolling: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in isScrolling = phase != .idle }
        } else {
            content
        }
    }
}

private struct ShortsSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @Environment(StudyProgressStore.self) private var progressStore
    @State private var query = ""
    @State private var results: ShortsSearchResults?
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var channelTask: Task<Void, Never>?
    @State private var selectedChannel: ShortsChannelResult?
    @State private var channelShorts: [YouTubeShortItem] = []
    @State private var isLoadingChannel = false
    @State private var channelError: String?
    @State private var youtubeQuery: String?
    @State private var hasMoreShorts = false
    @State private var isLoadingMoreShorts = false
    @State private var moreShortsError: String?
    @FocusState private var isSearchFocused: Bool
    let onSelectShort: (YouTubeShortItem) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(ShadowingTheme.blue)
                        TextField("Short, assunto ou canal", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($isSearchFocused)
                            .onSubmit(startSearch)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel("Limpar busca")
                        }
                    }
                    .padding(14)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                    Button(action: startSearch) {
                        Label("Buscar no YouTube", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSearching)

                    if !progressStore.recentShortSearches.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("BUSCAS RECENTES")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            ForEach(progressStore.recentShortSearches, id: \.query) { search in
                                Button {
                                    query = search.query
                                    startSearch()
                                } label: {
                                    Label(search.query, systemImage: "clock.arrow.circlepath")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if isSearching { ProgressView("Buscando canais e verificando legendas…") }
                    if let youtubeQuery,
                       youtubeQuery.caseInsensitiveCompare(query.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame {
                        Label("Buscando em inglês: “\(youtubeQuery)”", systemImage: "character.bubble")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(ShadowingTheme.coral)
                    }

                    if let results {
                        if !isSearching && results.channels.isEmpty && results.shorts.isEmpty {
                            ContentUnavailableView("Nenhum resultado adequado", systemImage: "magnifyingglass", description: Text("Tente um tema mais amplo, como “cooking” ou “street interview”. Os Shorts precisam ter fala com legenda em inglês e nível próximo ao seu."))
                        }

                        if !results.channels.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("CANAIS")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                ForEach(results.channels) { channel in
                                    HStack(spacing: 12) {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(ShadowingTheme.blue)
                                        Text(channel.title)
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Button("Ver Shorts") { openChannel(channel) }
                                            .font(.subheadline.weight(.semibold))
                                            .buttonStyle(.borderedProminent)
                                        Button(progressStore.shortChannels[channel.id]?.isFollowed == true ? "Seguindo" : "Seguir") {
                                            let follows = progressStore.shortChannels[channel.id]?.isFollowed != true
                                            progressStore.setShortChannel(channel.id, title: channel.title, followed: follows)
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .buttonStyle(.bordered)
                                    }
                                    .padding(12)
                                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                                }
                            }
                        }

                        if let selectedChannel {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("SHORTS DE \(selectedChannel.title.uppercased())")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                if isLoadingChannel { ProgressView("Carregando vídeos do canal…") }
                                if let channelError {
                                    Text(channelError).font(.subheadline).foregroundStyle(ShadowingTheme.coral)
                                }
                                if !isLoadingChannel && channelShorts.isEmpty && channelError == nil {
                                    Text("Nenhum Short disponível neste canal.").font(.subheadline).foregroundStyle(.secondary)
                                }
                                if !channelShorts.isEmpty {
                                    Text("A legenda em inglês será verificada ao abrir o vídeo.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(channelShorts) { item in shortRow(item) }
                                }
                            }
                        }

                        if !results.shorts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("SHORTS COM LEGENDA EM INGLÊS")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                ForEach(results.shorts) { item in shortRow(item) }
                            }
                        }

                        if !isSearching && hasMoreShorts {
                            VStack(spacing: 8) {
                                Button(action: loadMoreShorts) {
                                    if isLoadingMoreShorts {
                                        ProgressView().frame(maxWidth: .infinity)
                                    } else {
                                        Label("Carregar mais Shorts", systemImage: "arrow.down.circle")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isLoadingMoreShorts)
                                if let moreShortsError {
                                    Text(moreShortsError).font(.caption).foregroundStyle(ShadowingTheme.coral)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .opaqueTopScrollEdge()
            .background(ShadowingTheme.ink.ignoresSafeArea())
            .navigationTitle("Buscar Shorts")
            .navigationBarTitleDisplayMode(.inline)
            // Sem fundo, o conteúdo rolado passava por baixo do título e as letras se sobrepunham.
            .toolbarBackground(ShadowingTheme.ink, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onDisappear {
            searchTask?.cancel()
            channelTask?.cancel()
        }
    }

    private func shortRow(_ item: YouTubeShortItem) -> some View {
        Button {
            progressStore.rememberShortSearch(String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)))
            onSelectShort(item)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(item.videoID)/hqdefault.jpg")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "play.rectangle.fill").foregroundStyle(ShadowingTheme.blue)
                }
                .frame(width: 76, height: 76)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(item.creator ?? "YouTube").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let levelNote = levelNote(for: item) {
                        Text(levelNote)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "play.fill").foregroundStyle(ShadowingTheme.blue)
            }
            .padding(10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func levelNote(for item: YouTubeShortItem) -> String? {
        let levels = EnglishLevel.allCases
        guard item.level != appModel.profile.level,
              let itemIndex = levels.firstIndex(of: item.level),
              let profileIndex = levels.firstIndex(of: appModel.profile.level) else { return nil }
        return itemIndex > profileIndex ? "Um pouco mais difícil" : "Um pouco mais fácil"
    }

    private func openChannel(_ channel: ShortsChannelResult) {
        channelTask?.cancel()
        selectedChannel = channel
        channelShorts = []
        channelError = nil
        isLoadingChannel = true
        let searchText = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        channelTask = Task {
            do {
                let found = try await ShortsDiscoveryService.shared.searchChannelShorts(channel: channel, query: searchText, level: appModel.profile.level)
                guard !Task.isCancelled else { return }
                channelShorts = found
            } catch {
                if !Task.isCancelled { channelError = error.localizedDescription }
            }
            if !Task.isCancelled { isLoadingChannel = false }
        }
    }

    private func startSearch() {
        let text = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard text.count >= 2 else { return }
        isSearchFocused = false
        searchTask?.cancel()
        channelTask?.cancel()
        results = nil
        selectedChannel = nil
        channelShorts = []
        isLoadingChannel = false
        channelError = nil
        errorMessage = nil
        youtubeQuery = ShortsDiscoveryService.youtubeQuery(for: text)
        hasMoreShorts = false
        isLoadingMoreShorts = false
        moreShortsError = nil
        isSearching = true
        let level = appModel.profile.level
        searchTask = Task {
            // Canais e Shorts em paralelo: a verificação de legendas é a parte lenta.
            async let channelLookup = Self.capture { try await ShortsDiscoveryService.shared.searchChannels(query: text) }
            async let shortLookup = Self.capture { try await ShortsDiscoveryService.shared.searchShorts(query: text, level: level) }
            let channelResult = await channelLookup
            guard !Task.isCancelled else { return }
            let channels = (try? channelResult.get()) ?? []
            results = ShortsSearchResults(channels: channels, shorts: [])
            let shortResult = await shortLookup
            guard !Task.isCancelled else { return }
            switch shortResult {
            case .success(let page):
                results = ShortsSearchResults(channels: channels, shorts: page.items)
                youtubeQuery = page.youtubeQuery
                hasMoreShorts = page.hasMore
                if !channels.isEmpty || !page.items.isEmpty { progressStore.rememberShortSearch(text) }
            case .failure(let error):
                if case .failure(let channelError) = channelResult, channels.isEmpty {
                    errorMessage = channelError.localizedDescription
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isSearching = false
        }
    }

    private func loadMoreShorts() {
        let text = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard text.count >= 2, !isLoadingMoreShorts, let current = results else { return }
        searchTask?.cancel()
        isLoadingMoreShorts = true
        moreShortsError = nil
        let level = appModel.profile.level
        searchTask = Task {
            let result = await Self.capture { try await ShortsDiscoveryService.shared.searchShorts(query: text, level: level, loadMore: true) }
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let page):
                results = ShortsSearchResults(channels: current.channels, shorts: page.items)
                hasMoreShorts = page.hasMore
                if page.items.count == current.shorts.count, page.hasMore {
                    moreShortsError = "Nenhum Short novo nesta rodada. Toque de novo para continuar procurando."
                }
            case .failure(let error):
                moreShortsError = error.localizedDescription
            }
            isLoadingMoreShorts = false
        }
    }

    private static func capture<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async -> Result<Value, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
}
