import SwiftUI

struct YouTubeImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var appModel
    @Environment(StudyProgressStore.self) private var progressStore
    private let link: String
    private let previewTranscript: YouTubeTranscript?
    @State private var transcript: YouTubeTranscript?
    @State private var phrases: [ShadowingPhrase] = []
    @State private var selectedPhraseID: ShadowingPhrase.ID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playerController = YouTubePlayerController()
    @State private var exerciseMode: ExerciseMode = .shadowing
    @State private var difficultWordsForExercise: Set<String> = []
    @State private var didAutoLoad = false
    @State private var loadedVideoID: String?
    @State private var loadedIsShort = false
    @State private var estimatedVideoLevel: EnglishLevel?
    @State private var loadRevision = UUID()
    @State private var isPhraseListVisible = false
    @State private var isTranslationVisible = false
    @State private var blankCount = 1
    @State private var isTypingResponse = false
    @State private var phraseTranslations: [UUID: String] = [:]

    private enum Section: Hashable {
        case phrases
    }

    init(initialLink: String = "", previewTranscript: YouTubeTranscript? = nil) {
        link = initialLink
        self.previewTranscript = previewTranscript
    }

    private var videoID: String? {
        YouTubeLinkParser.videoID(from: link)
    }

    private var selectedPhrase: ShadowingPhrase? {
        phrases.first { $0.id == selectedPhraseID }
    }

    private var currentPhrase: ShadowingPhrase? {
        selectedPhrase
    }

    private var currentPhraseIndex: Int {
        guard let currentPhrase,
              let index = phrases.firstIndex(of: currentPhrase) else { return 0 }
        return index
    }

    private var activeListeningExercise: ActiveListeningExercise? {
        guard exerciseMode == .multipleChoice, let currentPhrase else { return nil }
        return ActiveListeningExerciseBuilder().build(
            phrase: currentPhrase,
            phraseIndex: currentPhraseIndex,
            lessonPhrases: phrases,
            level: appModel.profile.level,
            difficultWords: difficultWordsForExercise,
            blankCount: blankCount
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ZStack {
                    AtmosphericBackground()

                    ScrollView {
                        VStack(spacing: 0) {
                            practiceSection(availableHeight: geometry.size.height, availableWidth: min(760, geometry.size.width), scrollProxy: scrollProxy)

                            if transcript != nil {
                                phraseListSection
                                    .id(Section.phrases)
                            }
                        }
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .clipped()
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .sensoryFeedback(.selection, trigger: isPhraseListVisible) { _, visible in visible }
        .task {
            guard !didAutoLoad, !link.isEmpty, videoID != nil else { return }
            didAutoLoad = true
            await loadTranscript()
#if DEBUG && targetEnvironment(simulator)
            if previewTranscript != nil {
                let arguments = ProcessInfo.processInfo.arguments
                isTranslationVisible = arguments.contains("--audit-show-translation")
                if arguments.contains("--audit-active-listening") { selectActiveListeningMode() }
                if arguments.contains("--audit-typing-keyboard") { exerciseMode = .typing }
            }
#endif
        }
        .onDisappear {
            loadRevision = UUID()
            playerController.setPlaybackAllowed(false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playerController.pause() }
        }
        .onChange(of: appModel.profile.repeatPauseExtraPercent, initial: true) { _, percent in
            playerController.repeatPauseExtraPercent = percent
        }
        .onChange(of: playerController.state) { _, state in
            if state == .playing, let phrase = currentPhrase, let loadedVideoID {
                progressStore.record(phrase: phrase, videoID: loadedVideoID)
            }
        }
    }

    private func practiceSection(availableHeight: CGFloat, availableWidth: CGFloat, scrollProxy: ScrollViewProxy) -> some View {
        let compactEditing = isTypingResponse && availableHeight < 550
        let videoHeight = min((availableWidth - 32) * (loadedIsShort ? 16 / 9 : 9 / 16), availableHeight * 0.32)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Voltar")

                Text("PRÁTICA")
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(ShadowingTheme.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !phrases.isEmpty {
                    Text("\(currentPhraseIndex + 1)/\(phrases.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 9) {
                Text(transcript?.title ?? "Preparando seu vídeo…")
                    .font(compactEditing ? .headline : .title3.weight(.bold))
                    .lineLimit(compactEditing ? 1 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Text(transcript?.channel ?? "YouTube")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let estimatedVideoLevel {
                        Text("Nível estimado · \(estimatedVideoLevel.title)")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(ShadowingTheme.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(ShadowingTheme.blue.opacity(0.13), in: Capsule())
                            .accessibilityLabel("Nível estimado do vídeo: \(estimatedVideoLevel.title)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, compactEditing ? 6 : 12)

            if let videoID = loadedVideoID {
                player(videoID: videoID)
                    .frame(height: compactEditing ? 1 : videoHeight)
                    .opacity(compactEditing ? 0 : 1)
                    .allowsHitTesting(!compactEditing)
                    .padding(.top, compactEditing ? 0 : 12)
            }

            if isLoading {
                loadingCard
                    .padding(.top, 12)
            } else if let errorMessage {
                errorCard(errorMessage)
                    .padding(.top, 12)
            } else if transcript != nil, currentPhrase != nil {
                practicePanel
                    .padding(.top, 12)
            }

            if transcript != nil, !compactEditing {
                Button {
                    withAnimation(.smooth) {
                        scrollProxy.scrollTo(Section.phrases, anchor: .top)
                    }
                } label: {
                    Label("Ver todos os trechos", systemImage: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Deslize para baixo para escolher outra frase")
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(height: availableHeight, alignment: .top)
    }

    private func player(videoID: String) -> some View {
        Group {
#if DEBUG && targetEnvironment(simulator)
            if previewTranscript != nil {
                Rectangle()
                    .fill(.black.gradient)
                    .overlay {
                        Label("Prévia de vídeo", systemImage: "play.rectangle")
                            .foregroundStyle(.secondary)
                    }
            } else {
                YouTubePlayerView(videoID: videoID, controller: playerController, allowsAutoplay: true)
            }
#else
            YouTubePlayerView(videoID: videoID, controller: playerController, allowsAutoplay: true)
#endif
        }
            .aspectRatio(loadedIsShort ? 9.0 / 16 : 16.0 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
    }

    private var loadingCard: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(ShadowingTheme.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("Buscando a melhor legenda em inglês")
                    .font(.headline)
                Text("Preparando trechos e conferindo os tempos das palavras.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadowingGlass(cornerRadius: 22)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Legenda não carregada", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(ShadowingTheme.coral)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Tentar novamente") {
                Task { await loadTranscript() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ShadowingTheme.blue)
        }
        .padding(18)
        .background(ShadowingTheme.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var practicePanel: some View {
        Group {
            if let currentPhrase {
                VStack(spacing: 10) {
                    PracticeModeSelector(
                        isActiveListening: exerciseMode.isActiveListening,
                        onSelectShadowing: selectShadowingMode,
                        onSelectActiveListening: selectActiveListeningMode
                    )

                    Text(panelTitle)
                        .font(.caption2.bold())
                        .tracking(1.4)
                        .foregroundStyle(exerciseMode.isActiveListening ? ShadowingTheme.mint : ShadowingTheme.blue)

                    if exerciseMode.isActiveListening {
                        ActiveListeningOptionsView(
                            mode: $exerciseMode,
                            blankCount: $blankCount,
                            maximumBlanks: ActiveListeningExerciseBuilder().eligibleWordCount(in: currentPhrase.text)
                        )
                    }

                    Group {
                    if exerciseMode == .multipleChoice, activeListeningExercise == nil {
                        Text("Não há palavras elegíveis neste trecho. Use Frase inteira ou avance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let activeListeningExercise {
                            ActiveListeningExerciseView(
                                exercise: activeListeningExercise,
                                onReplay: { playerController.play(phrase: currentPhrase) },
                                onResult: { word, isCorrect in
                                    progressStore.recordListeningAttempt(word: word, isCorrect: isCorrect)
                                }
                            )
                            .id(activeListeningExercise.id)
                    } else if exerciseMode == .typing {
                        PracticeTextArea(contentAlignment: .bottom) {
                            HiddenCaptionDictationView(reference: currentPhrase.text) { focused in
                                isTypingResponse = focused
                            }
                                .id(currentPhrase.id)
                        }
                    } else {
                        PracticeCaptionView(
                            phrase: currentPhrase, font: .title3.weight(.semibold),
                            showsTranslation: isTranslationVisible,
                            sourceLanguage: appModel.profile.learningLanguage,
                            targetLanguage: appModel.profile.nativeLanguage,
                            translations: $phraseTranslations
                        )
                    }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)

                    HStack(spacing: 12) {
                        Button {
                            selectPreviousPhrase()
                        } label: {
                            Image(systemName: "backward.end.fill")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(currentPhraseIndex == 0)
                        .accessibilityLabel("Frase anterior")

                        Button {
                            playerController.togglePlayPause()
                        } label: {
                            Image(systemName: playerController.isPlaybackRequested ? "pause.fill" : "play.fill")
                                .frame(width: 52, height: 52)
                                .background(ShadowingTheme.blue, in: Circle())
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel(playerController.isPlaybackRequested ? "Pausar treino" : "Reproduzir")

                        Button {
                            selectNextPhrase()
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(currentPhraseIndex + 1 >= phrases.count)
                        .accessibilityLabel("Próxima frase")

                        Button {
                            if playerController.isLoopEnabled {
                                playerController.stopLoop()
                            } else {
                                playerController.startLoop()
                            }
                        } label: {
                            Image(systemName: playerController.isLoopEnabled ? "repeat.circle.fill" : "repeat.circle")
                                .foregroundStyle(playerController.isLoopEnabled ? ShadowingTheme.blue : .secondary)
                        }

                        if !exerciseMode.isActiveListening {
                            Button {
                                isTranslationVisible.toggle()
                            } label: {
                                Image(systemName: isTranslationVisible ? "eye.fill" : "eye.slash.fill")
                                    .foregroundStyle(isTranslationVisible ? ShadowingTheme.mint : .white)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(isTranslationVisible ? "Ocultar tradução" : "Mostrar tradução")
                        }
                    }
                    .font(.title2)
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: false, vertical: true)
                    if let playbackError = playerController.playbackError {
                        Text(playbackError).font(.caption).foregroundStyle(ShadowingTheme.coral)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .shadowingGlass(cornerRadius: 24)
            }
        }
    }

    private var phraseListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trechos deste vídeo")
                    .font(.title3.bold())
                Spacer()
                Text("\(phrases.count) frases")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .modifier(PhraseListVisibilityModifier(isVisible: $isPhraseListVisible))

            if let transcript {
                Text(transcript.channel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 10) {
                ForEach(Array(phrases.enumerated()), id: \.element.id) { index, phrase in
                    Button {
                        select(phrase)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedPhraseID == phrase.id ? "waveform.circle.fill" : "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(ShadowingTheme.blue)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(phrase.text)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                Text("Frase \(index + 1) • \(timecode(phrase.start)) • \(String(format: "%.1f", phrase.duration))s")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(
                            selectedPhraseID == phrase.id ? ShadowingTheme.blue.opacity(0.13) : .white.opacity(0.045),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadTranscript() async {
        guard let videoID else { return }
        let requestRevision = UUID()
        loadRevision = requestRevision
        if loadedVideoID != videoID {
            playerController.prepareForVideo()
        } else {
            playerController.pause()
            playerController.activePhrase = nil
        }
        loadedVideoID = videoID
        isTypingResponse = false
        loadedIsShort = YouTubeLinkParser.isShortsURL(link)
        playerController.setPlaybackAllowed(true)
        isLoading = true
        transcript = nil
        phrases = []
        selectedPhraseID = nil
        estimatedVideoLevel = nil
        phraseTranslations = [:]
        errorMessage = nil

        do {
            let loadedTranscript: YouTubeTranscript
            if let previewTranscript {
                loadedTranscript = previewTranscript
            } else {
                loadedTranscript = try await YouTubeTranscriptService.shared.fetchTranscript(videoID: videoID)
            }
            guard loadRevision == requestRevision, !Task.isCancelled else { return }
            let preparedPhrases = ShadowingLessonBuilder(level: appModel.profile.level).build(from: loadedTranscript)
            guard !preparedPhrases.isEmpty else { throw TranscriptError.emptyCaptions }
            transcript = loadedTranscript
            phrases = preparedPhrases
            estimatedVideoLevel = estimateVideoLevel(from: loadedTranscript)

            if let firstPhrase = preparedPhrases.first {
                let savedStart = progressStore.videos[videoID]?.phraseStart
                let resumePhrase = savedStart.flatMap { start in
                    preparedPhrases.min { abs($0.start - start) < abs($1.start - start) }
                } ?? firstPhrase
                select(resumePhrase)
            }
#if DEBUG && targetEnvironment(simulator)
            if previewTranscript != nil {
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--audit-full-dictation") {
                    exerciseMode = .typing
                } else if arguments.contains("--audit-active-listening") {
                    exerciseMode = .multipleChoice
                }
                if arguments.contains("--audit-show-translation") {
                    isTranslationVisible = true
                }
            }
#endif
        } catch {
            guard loadRevision == requestRevision, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func select(_ phrase: ShadowingPhrase) {
        isTypingResponse = false
        if exerciseMode.isActiveListening {
            difficultWordsForExercise = Set(progressStore.difficultWords.map(\.word))
        }
        selectedPhraseID = phrase.id
        if let videoID = loadedVideoID {
            if let transcript, let index = phrases.firstIndex(of: phrase) {
                progressStore.rememberVideo(
                    videoID: videoID,
                    title: transcript.title,
                    channel: transcript.channel,
                    isShort: loadedIsShort,
                    phrase: phrase,
                    phraseIndex: index,
                    phraseCount: phrases.count
                )
            }
        }
        playerController.play(phrase: phrase)
    }

    private func selectPreviousPhrase() {
        guard let selectedPhrase,
              let index = phrases.firstIndex(of: selectedPhrase),
              index > phrases.startIndex else { return }
        select(phrases[phrases.index(before: index)])
    }

    private func selectNextPhrase() {
        guard let selectedPhrase,
              let index = phrases.firstIndex(of: selectedPhrase),
              phrases.index(after: index) < phrases.endIndex else { return }
        select(phrases[phrases.index(after: index)])
    }

    private func timecode(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func estimateVideoLevel(from transcript: YouTubeTranscript) -> EnglishLevel? {
        guard let firstStart = transcript.segments.first?.start else { return nil }
        let sample = Array(transcript.segments.prefix { $0.start < firstStart + 180 })
        let sampleTranscript = YouTubeTranscript(
            videoID: transcript.videoID,
            title: transcript.title,
            channel: transcript.channel,
            languageCode: transcript.languageCode,
            source: transcript.source,
            segments: sample
        )
        return ShortDifficultyEstimator.estimate(transcript: sampleTranscript)
    }

    private var panelTitle: String {
        if exerciseMode.isActiveListening {
            return exerciseMode == .multipleChoice ? "QUAL PALAVRA VOCÊ OUVIU?" : "DIGITE O QUE VOCÊ OUVIU"
        }
        return playerController.isWaitingForStudent ? "SUA VEZ" : "OUÇA E REPITA"
    }

    private func selectShadowingMode() {
        exerciseMode = .shadowing
        if let currentPhrase {
            playerController.play(phrase: currentPhrase)
        }
    }

    private func selectActiveListeningMode() {
        difficultWordsForExercise = Set(progressStore.difficultWords.map(\.word))
        if !exerciseMode.isActiveListening { exerciseMode = .multipleChoice }
        if let currentPhrase {
            playerController.play(phrase: currentPhrase)
        }
    }
}

struct PhraseTranslationView: View {
    let phrase: ShadowingPhrase
    let sourceLanguage: SupportedLanguage
    let targetLanguage: SupportedLanguage
    @Binding var translations: [UUID: String]

    @State private var request: VocabularyTranslationRequest?
    @State private var failedPhraseIDs: Set<UUID> = []
    @State private var failure: TranslationFailure?

    var body: some View {
#if targetEnvironment(simulator)
#if DEBUG
        if let fixture = InterfaceAuditPreview.translationFixture(for: phrase.text) {
            translationContent
                .task(id: phrase.id) { translations[phrase.id] = fixture }
        } else {
            simulatorTranslationNotice
        }
#else
        simulatorTranslationNotice
#endif
#else
        Group {
            if #available(iOS 18.0, *) {
                VocabularyTranslationContainer(
                    request: request,
                    onTranslated: { completedRequest, translation in
                        guard request?.id == completedRequest.id else { return }
                        translations[phrase.id] = translation
                        failedPhraseIDs.remove(phrase.id)
                        request = nil
                    },
                    onFailed: { failedRequest in
                        guard request?.id == failedRequest.id else { return }
                        failedPhraseIDs.insert(phrase.id)
                        request = nil
                    },
                    onDiagnostic: { failedRequest, diagnostic in
                        guard request?.id == failedRequest.id else { return }
                        failure = diagnostic
                    }
                ) {
                    translationContent
                }
            } else {
                Text("Tradução disponível no iOS 18 ou superior")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: phrase.id) {
            request = nil
            if translations[phrase.id] == nil { startTranslation() }
        }
        .task(id: request?.id) {
            guard let pendingRequest = request else { return }
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, request?.id == pendingRequest.id else { return }
            failure = TranslationFailure(stage: .preparation, domain: "Timeout", code: 60)
            failedPhraseIDs.insert(phrase.id)
            request = nil
        }
#endif
    }

    private var simulatorTranslationNotice: some View {
        Text("A tradução nativa da Apple não funciona no simulador. Teste no iPhone.")
            .font(.system(size: 13, weight: .regular, design: .rounded).italic())
            .foregroundStyle(.white.opacity(0.72))
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var translationContent: some View {
        if let translation = translations[phrase.id] {
            Text(translation)
                .font(.system(size: 13).italic())
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Tradução: \(translation)")
        } else if failedPhraseIDs.contains(phrase.id) {
            VStack(spacing: 5) {
                Text(failure?.message ?? "Tradução indisponível")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(failure?.stage == .preparation ? "Preparar idiomas e tentar novamente" : "Tentar novamente", action: startTranslation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShadowingTheme.blue)
            }
        } else {
            ProgressView("Traduzindo frase…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func startTranslation() {
        failedPhraseIDs.remove(phrase.id)
        failure = nil
        request = VocabularyTranslationRequest(
            word: phrase.text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
    }
}

private struct PhraseListVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0.15) { visible in
                isVisible = visible
            }
        } else {
            content
        }
    }
}
