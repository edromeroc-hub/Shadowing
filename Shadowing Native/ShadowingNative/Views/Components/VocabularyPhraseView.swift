import SwiftUI
@preconcurrency import Translation
import os

struct VocabularyPhraseView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(VocabularyStore.self) private var vocabularyStore
    let text: String
    var font: Font = .system(size: 20, weight: .semibold, design: .rounded)

    @State private var translationRequest: VocabularyTranslationRequest?
    @State private var inspectedWordIndex: Int?
    @State private var wordTranslations: [String: String] = [:]
    @State private var failedTranslations: Set<String> = []
    @State private var translationFailures: [String: TranslationFailure] = [:]

    var body: some View {
        translatedWordFlow
            .accessibilityElement(children: .contain)
            .onChange(of: text) { _, _ in
                inspectedWordIndex = nil
                translationRequest = nil
                wordTranslations = [:]
                failedTranslations = []
                translationFailures = [:]
            }
            .task(id: translationRequest?.id) {
                guard let request = translationRequest else { return }
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled,
                      translationRequest?.id == request.id,
                      wordTranslations[request.word] == nil else { return }
                translationFailures[request.word] = TranslationFailure(stage: .preparation, domain: "Timeout", code: 60)
                failedTranslations.insert(request.word)
                translationRequest = nil
            }
    }

    @ViewBuilder
    private var translatedWordFlow: some View {
        if #available(iOS 18.0, *) {
            VocabularyTranslationContainer(
                request: translationRequest,
                onTranslated: { request, translation in
                    guard translationRequest?.id == request.id else { return }
                    vocabularyStore.setTranslation(
                        translation,
                        for: request.word,
                        language: request.targetLanguage
                    )
                    wordTranslations[request.word] = translation
                    failedTranslations.remove(request.word)
                    if translationRequest?.id == request.id { translationRequest = nil }
                },
                onFailed: { request in
                    guard translationRequest?.id == request.id else { return }
                    failedTranslations.insert(request.word)
                    if translationRequest?.id == request.id { translationRequest = nil }
                },
                onDiagnostic: { request, failure in
                    guard translationRequest?.id == request.id else { return }
                    translationFailures[request.word] = failure
                }
            ) {
                wordFlow
            }
        } else {
            wordFlow
        }
    }

    private var wordFlow: some View {
        WordFlowLayout(spacing: 2) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                let normalized = normalize(token)
                let isSaved = vocabularyStore.contains(normalized)

                Text(token)
                    .font(font)
                    .foregroundStyle(isSaved ? ShadowingTheme.mint : .white)
                    .padding(.horizontal, 1)
                    .padding(.vertical, 1)
                    .background(
                        isSaved ? ShadowingTheme.mint.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        LongPressGesture(minimumDuration: 0.45)
                            .exclusively(before: TapGesture())
                            .onEnded { gesture in
                                switch gesture {
                                case .first:
                                    inspect(normalized, at: index)
                                case .second:
                                    toggleSavedWord(normalized)
                                }
                            }
                    )
                    .popover(isPresented: Binding(
                        get: { inspectedWordIndex == index },
                        set: { if !$0, inspectedWordIndex == index { inspectedWordIndex = nil } }
                    )) {
                        translationPopover(for: normalized)
                            .presentationCompactAdaptation(.popover)
                    }
                    .accessibilityLabel(
                        accessibilityLabel(
                            word: normalized,
                            isSaved: isSaved
                        )
                    )
                    .accessibilityHint("Toque para salvar; mantenha pressionado para traduzir")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        toggleSavedWord(normalized)
                    }
                    .accessibilityAction(named: "Mostrar tradução") {
                        inspect(normalized, at: index)
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var tokens: [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private func normalize(_ word: String) -> String {
        word
            .lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N}'-]", with: "", options: .regularExpression)
    }

    private func requestTranslation(for word: String) {
        failedTranslations.remove(word)
        translationFailures[word] = nil
        translationRequest = VocabularyTranslationRequest(
            word: word,
            sourceLanguage: appModel.profile.learningLanguage,
            targetLanguage: appModel.profile.nativeLanguage
        )
    }

    private func toggleSavedWord(_ word: String) {
        guard !word.isEmpty else { return }
        if vocabularyStore.contains(word) {
            _ = vocabularyStore.toggle(word)
            if translationRequest?.word == word {
                translationRequest = nil
            }
        } else {
            _ = vocabularyStore.add(word)
            if let translation = wordTranslations[word] {
                vocabularyStore.setTranslation(translation, for: word, language: appModel.profile.nativeLanguage)
            } else {
                requestTranslation(for: word)
            }
        }
    }

    private func inspect(_ word: String, at index: Int) {
        guard !word.isEmpty else { return }
        inspectedWordIndex = index
        if wordTranslations[word] == nil,
           vocabularyStore.translation(for: word, language: appModel.profile.nativeLanguage) == nil,
           appModel.profile.learningLanguage != appModel.profile.nativeLanguage {
            requestTranslation(for: word)
        }
    }

    private func translationPopover(for word: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(word)
                .font(.headline)
            Text(appModel.profile.nativeLanguage.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let translation = wordTranslations[word] ?? vocabularyStore.translation(
                for: word,
                language: appModel.profile.nativeLanguage
            ) {
                Text(translation)
                    .font(.body)
                    .foregroundStyle(ShadowingTheme.mint)
            } else if appModel.profile.learningLanguage == appModel.profile.nativeLanguage {
                Text(word)
                    .font(.subheadline)
            } else if failedTranslations.contains(word) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(translationFailures[word]?.message ?? "Não foi possível traduzir agora.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(translationFailures[word]?.stage == .preparation ? "Preparar idiomas e tentar novamente" : "Tentar novamente") {
                        requestTranslation(for: word)
                    }
                    .font(.subheadline)
                }
            } else {
#if targetEnvironment(simulator)
                Text("A tradução nativa da Apple não funciona no simulador. Teste no iPhone.")
                    .font(.subheadline)
#else
                if #available(iOS 18.0, *) {
                    ProgressView("Traduzindo…")
                        .font(.subheadline)
                    Text("No primeiro uso, confirme o download dos idiomas quando o iPhone pedir.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tradução disponível no iOS 18 ou superior")
                        .font(.subheadline)
                }
#endif
            }
        }
        .padding(16)
        .frame(minWidth: 170, alignment: .leading)
    }

    private func accessibilityLabel(word: String, isSaved: Bool) -> String {
        if !isSaved { return "Adicionar \(word) ao vocabulário" }
        return "Remover \(word) do vocabulário"
    }
}

struct PracticeModeSelector: View {
    let isActiveListening: Bool
    let onSelectShadowing: () -> Void
    let onSelectActiveListening: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            modeButton(
                title: "Shadowing",
                icon: "waveform",
                isSelected: !isActiveListening,
                action: onSelectShadowing
            )
            modeButton(
                title: "Escuta ativa",
                icon: "ear.fill",
                isSelected: isActiveListening,
                action: onSelectActiveListening
            )
        }
    }

    private func modeButton(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? .white : .secondary)
                .background(isSelected ? ShadowingTheme.blue : .white.opacity(0.055), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ActiveListeningOptionsView: View {
    @Binding var mode: ExerciseMode
    @Binding var blankCount: Int
    let maximumBlanks: Int

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                option("Lacunas", selected: mode == .multipleChoice) { mode = .multipleChoice }
                option("Frase inteira", selected: mode == .typing) { mode = .typing }
            }
            if mode == .multipleChoice {
                HStack(spacing: 8) {
                    Text("Palavras ocultas")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ForEach(1...max(1, min(5, maximumBlanks)), id: \.self) { count in
                        Button("\(count)") { blankCount = count }
                            .font(.caption2.weight(.semibold))
                            .frame(minWidth: 32, minHeight: 32)
                            .background(min(blankCount, max(1, min(5, maximumBlanks))) == count ? ShadowingTheme.blue : .white.opacity(0.08), in: Circle())
                            .buttonStyle(.plain)
                            .accessibilityLabel("Ocultar \(count) palavras")
                    }
                }
            }
        }
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption2.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? .white : .secondary)
            .background(selected ? ShadowingTheme.blue : .white.opacity(0.06), in: Capsule())
            .buttonStyle(.plain)
    }
}

struct ActiveListeningExerciseView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let exercise: ActiveListeningExercise
    var compact = false
    var completedPhrase: ShadowingPhrase? = nil
    let onReplay: () -> Void
    let onResult: (String, Bool) -> Void

    @State private var progress = ListeningExerciseProgress()
    @State private var translationRequest: VocabularyTranslationRequest?
    @State private var isAnswerAnimating = false
    @State private var feedbackRevision = 0
    @State private var successRevision = 0
    @State private var failureRevision = 0
    @State private var lastRejectedChoice: String?
    @State private var completedTranslations: [UUID: String] = [:]
    @Namespace private var wordAnimation

    private var nextBlankIndex: Int? {
        exercise.blanks.indices.first { progress.solvedAnswers[exercise.blanks[$0].tokenIndex] == nil }
    }

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                VocabularyTranslationContainer(
                    request: translationRequest,
                    onTranslated: { request, translation in
                        guard translationRequest?.id == request.id else { return }
                        vocabularyStore.setTranslation(translation, for: request.word, language: request.targetLanguage)
                        translationRequest = nil
                    },
                    onFailed: { request in
                        if translationRequest?.id == request.id { translationRequest = nil }
                    }
                ) {
                    exerciseContent
                }
            } else {
                exerciseContent
            }
        }
        .onChange(of: exercise.id) { _, _ in reset() }
        .sensoryFeedback(.success, trigger: successRevision)
        .sensoryFeedback(.error, trigger: failureRevision)
        .task(id: feedbackRevision) {
            guard isAnswerAnimating else { return }
            do {
                try await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 350))
            } catch { return }
            guard !Task.isCancelled else { return }
            isAnswerAnimating = false
        }
    }

    private var exerciseContent: some View {
        VStack(spacing: compact ? 7 : 12) {
            PracticeTextArea {
                VStack(spacing: 8) {
                WordFlowLayout(spacing: 3) {
                    ForEach(exercise.tokens.indices, id: \.self) { index in
                        sentenceToken(at: index)
                    }
                }
                .font((compact ? Font.subheadline : Font.title3).weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .center)
                if nextBlankIndex == nil, !exercise.blanks.isEmpty,
                   let completedPhrase,
                   appModel.profile.learningLanguage != appModel.profile.nativeLanguage {
                    PhraseTranslationView(
                        phrase: completedPhrase,
                        sourceLanguage: appModel.profile.learningLanguage,
                        targetLanguage: appModel.profile.nativeLanguage,
                        translations: $completedTranslations
                    )
                }
                }
            }
            .id(exercise.id)
            .frame(maxHeight: .infinity)

            if let nextBlankIndex {
                Text("Palavra \(nextBlankIndex + 1) de \(exercise.blanks.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                multipleChoiceGrid(for: nextBlankIndex)
                HStack {
                    Text(lastRejectedChoice == nil ? "Escolha a palavra que você ouviu." : "Tente novamente.")
                    Spacer(minLength: 4)
                    Button(action: onReplay) { Label("Ouvir", systemImage: "speaker.wave.2.fill") }
                        .buttonStyle(.plain)
                }
                .font(.caption2)
                .foregroundStyle(lastRejectedChoice == nil ? .secondary : ShadowingTheme.coral)
            } else {
                Text("\(progress.solvedAnswers.count)/\(exercise.blanks.count) palavras preenchidas")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShadowingTheme.mint)
                Text("\(progress.attempts) \(progress.attempts == 1 ? "tentativa" : "tentativas")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !progress.rejectedChoices.isEmpty {
                    PracticeTextArea {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(exercise.blanks.filter { progress.rejectedChoices[$0.tokenIndex] != nil }) { blank in
                                feedback(for: blank)
                            }
                        }
                    }
                    .frame(height: compact ? 60 : 90)
                }
            }
        }
    }

    @ViewBuilder
    private func sentenceToken(at index: Int) -> some View {
        if let blank = exercise.blanks.first(where: { $0.tokenIndex == index }) {
            let solved = progress.solvedAnswers[index] != nil
            Text(exercise.tokens[index])
                .hidden()
                .overlay {
                    if solved {
                        if reduceMotion {
                            Text(exercise.tokens[index]).foregroundStyle(ShadowingTheme.mint)
                        } else {
                            Text(exercise.tokens[index])
                                .foregroundStyle(ShadowingTheme.mint)
                                .matchedGeometryEffect(id: blank.tokenIndex, in: wordAnimation, properties: .position)
                        }
                    } else {
                        Text(exercise.maskedTokens[index])
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(solved ? exercise.tokens[index] : "Palavra a preencher")
        } else {
            Text(exercise.tokens[index])
        }
    }

    private func multipleChoiceGrid(for index: Int) -> some View {
        let blank = exercise.blanks[index]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(blank.choices, id: \.self) { choice in
                let rejected = progress.rejectedChoices[blank.tokenIndex]?.contains(choice) == true
                Button {
                    submit(choice, for: index)
                } label: {
                    choiceLabel(choice, blank: blank)
                        .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, compact ? 7 : 10)
                        .frame(minHeight: 44)
                        .foregroundStyle(rejected ? ShadowingTheme.coral : .white)
                        .background(rejected ? ShadowingTheme.coral.opacity(0.12) : .white.opacity(0.065), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isAnswerAnimating || rejected)
                .phaseAnimator([0.0, -6, 6, -4, 4, 0], trigger: failureRevision) { content, offset in
                    content.offset(x: !reduceMotion && lastRejectedChoice == choice ? offset : 0)
                } animation: { _ in .linear(duration: 0.045) }
            }
        }
    }

    @ViewBuilder
    private func choiceLabel(_ choice: String, blank: ListeningBlank) -> some View {
        if blank.accepts(choice) && !reduceMotion {
            Text(choice).matchedGeometryEffect(id: blank.tokenIndex, in: wordAnimation, properties: .position)
        } else {
            Text(choice)
        }
    }

    private func feedback(for blank: ListeningBlank) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 8) {
                Label(
                    "Resposta: \(blank.answer)",
                    systemImage: "arrow.uturn.backward.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(ShadowingTheme.coral)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                Button(action: onReplay) {
                    Label("Ouvir", systemImage: "speaker.wave.2.fill")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ShadowingTheme.blue)
            }

            if !vocabularyStore.contains(blank.answer) {
                Button {
                    saveDifficultWord(blank.answer)
                } label: {
                    Label("Salvar \(blank.answer) no vocabulário", systemImage: "bookmark.badge.plus")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ShadowingTheme.blue)
            } else {
                    Label("No seu vocabulário", systemImage: "bookmark.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ShadowingTheme.mint)
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
    }

    private func submit(_ response: String, for index: Int) {
        guard !isAnswerAnimating, exercise.blanks.indices.contains(index) else { return }
        let blank = exercise.blanks[index]
        var updated = progress
        guard let correct = updated.submit(response, for: blank) else { return }
        isAnswerAnimating = true
        lastRejectedChoice = correct ? nil : response
        feedbackRevision += 1
        if correct {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { progress = updated }
            successRevision += 1
        } else {
            progress = updated
            failureRevision += 1
        }
        onResult(blank.answer, correct)
        UIAccessibility.post(notification: .announcement, argument: correct ? "Correto: \(blank.answer)" : "Resposta incorreta. Tente novamente.")
    }

    private func reset() {
        progress = ListeningExerciseProgress()
        isAnswerAnimating = false
        lastRejectedChoice = nil
        feedbackRevision += 1
        translationRequest = nil
        completedTranslations = [:]
    }

    private func saveDifficultWord(_ word: String) {
        guard vocabularyStore.add(word) else { return }
        translationRequest = VocabularyTranslationRequest(
            word: word,
            sourceLanguage: appModel.profile.learningLanguage,
            targetLanguage: appModel.profile.nativeLanguage
        )
    }
}

struct HiddenCaptionDictationView: View {
    let reference: String
    var onFocusChange: (Bool) -> Void = { _ in }

    @State private var response = ""
    @State private var score: Int?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Escreva o que ouviu", text: $response, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...2)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(checkResponse)

                Button(action: checkResponse) {
                    Image(systemName: "checkmark")
                        .font(.body.bold())
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.white)
                        .background(ShadowingTheme.blue, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Conferir o que ouvi")
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
            .padding(.vertical, 4)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

            if let score {
                Text("\(score)% das palavras na ordem correta")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(score >= 80 ? ShadowingTheme.mint : ShadowingTheme.blue)
                    .accessibilityLabel("Você acertou \(score) por cento das palavras na ordem correta")
                DisclosureGroup("Ver frase original") {
                    ScrollView {
                        Text(reference)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 90)
                }
                .font(.caption)
            } else {
                Text("Confira sua resposta ou avance para o próximo trecho.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: response) { _, _ in score = nil }
        .onChange(of: isFocused) { _, focused in onFocusChange(focused) }
        .onDisappear { onFocusChange(false) }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if ProcessInfo.processInfo.arguments.contains("--ui-audit"),
               ProcessInfo.processInfo.arguments.contains("--audit-typing-keyboard") {
                isFocused = true
            }
        }
#endif
    }

    private func checkResponse() {
        isFocused = false
        guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        score = Self.matchPercentage(response, reference: reference)
    }

    static func matchPercentage(_ response: String, reference: String) -> Int {
        func words(in text: String) -> [String] {
            text.replacingOccurrences(of: "’", with: "'")
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
                .map(String.init)
        }

        let expected = words(in: reference)
        let heard = words(in: response)
        guard !expected.isEmpty else { return 0 }

        var previous = Array(repeating: 0, count: heard.count + 1)
        for expectedWord in expected {
            var current = Array(repeating: 0, count: heard.count + 1)
            for (index, heardWord) in heard.enumerated() {
                current[index + 1] = expectedWord == heardWord
                    ? previous[index] + 1
                    : max(previous[index + 1], current[index])
            }
            previous = current
        }
        return Int((Double(previous[heard.count]) / Double(max(expected.count, heard.count)) * 100).rounded())
    }
}

struct PracticeTextArea<Content: View>: View {
    var contentAlignment: Alignment = .top
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 2) {
                ScrollView {
                    content()
                        .frame(maxWidth: .infinity, minHeight: contentAlignment == .bottom ? geometry.size.height : nil, alignment: contentAlignment)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            contentHeight = height
                            onHeightChange(height)
                        }
                }
                .scrollIndicators(.visible)
                .defaultScrollAnchor(.top)
                if contentHeight > geometry.size.height + 1 {
                    Label("Role para ler", systemImage: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

struct PracticeCaptionView: View {
    let phrase: ShadowingPhrase
    let font: Font
    let showsTranslation: Bool
    let sourceLanguage: SupportedLanguage
    let targetLanguage: SupportedLanguage
    @Binding var translations: [UUID: String]
    var onEnglishHeight: (CGFloat) -> Void = { _ in }
    var onTranslationHeight: (CGFloat) -> Void = { _ in }
    @State private var isExpanded = false
    @State private var measuredTranslationHeight: CGFloat = 48

    var body: some View {
        VStack(spacing: 6) {
            if phrase.needsExpandedPractice {
                Button { isExpanded = true } label: {
                    Label("Trecho longo · Ampliar texto", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ShadowingTheme.blue)
                }
                .buttonStyle(.plain)
            }
            GeometryReader { geometry in
                VStack(spacing: 6) {
                    PracticeTextArea(onHeightChange: onEnglishHeight) {
                        VocabularyPhraseView(text: phrase.text, font: font)
                    }
                    if showsTranslation, sourceLanguage != targetLanguage {
                        PracticeTextArea(onHeightChange: { height in
                            measuredTranslationHeight = height
                            onTranslationHeight(height)
                        }) {
                            PhraseTranslationView(
                                phrase: phrase, sourceLanguage: sourceLanguage,
                                targetLanguage: targetLanguage, translations: $translations
                            )
                        }
                        .frame(height: min(max(48, measuredTranslationHeight + 4), max(48, geometry.size.height * 0.38)))
                    }
                }
            }
            .id(phrase.id)
        }
        .sheet(isPresented: $isExpanded) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Este trecho não tem fronteiras de tempo suficientes para uma divisão segura. Você pode lê-lo inteiro ou avançar para a próxima frase.")
                            .font(.callout).foregroundStyle(.secondary)
                        VocabularyPhraseView(text: phrase.text, font: .title3.weight(.semibold))
                        if showsTranslation, sourceLanguage != targetLanguage {
                            PhraseTranslationView(phrase: phrase, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, translations: $translations)
                        }
                    }
                    .padding(20)
                }
                .navigationTitle("Trecho completo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluído") { isExpanded = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct VocabularyTranslationRequest: Equatable {
    let id = UUID()
    let word: String
    let sourceLanguage: SupportedLanguage
    let targetLanguage: SupportedLanguage
}

struct TranslationFailure: Equatable {
    enum Stage: String {
        case availability
        case preparation
        case translation
    }

    let stage: Stage
    let domain: String
    let code: Int

    var message: String {
        switch stage {
        case .availability:
            "Esses idiomas não são compatíveis com a tradução da Apple."
        case .preparation:
            "Não foi possível preparar os idiomas. Verifique a conexão e aceite o download no iPhone. (\(domain) \(code))"
        case .translation:
            "A tradução falhou. Tente novamente. (\(domain) \(code))"
        }
    }
}

private struct WordFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        layout(in: proposal.width ?? 320, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let result = layout(in: bounds.width, subviews: subviews)
        for placement in result.placements {
            placement.subview.place(
                at: CGPoint(x: bounds.minX + placement.point.x, y: bounds.minY + placement.point.y),
                proposal: ProposedViewSize(width: min(bounds.width, placement.width), height: nil)
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, placements: [Placement]) {
        var placements: [Placement] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: max(1, width), height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }

            placements.append(Placement(subview: subview, point: CGPoint(x: x, y: y), width: size.width))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }

        return (CGSize(width: min(width, usedWidth), height: y + lineHeight), placements)
    }

    private struct Placement {
        let subview: LayoutSubview
        let point: CGPoint
        let width: CGFloat
    }
}

@available(iOS 18.0, *)
struct VocabularyTranslationContainer<Content: View>: View {
    let request: VocabularyTranslationRequest?
    let onTranslated: (VocabularyTranslationRequest, String) -> Void
    let onFailed: (VocabularyTranslationRequest) -> Void
    let onDiagnostic: (VocabularyTranslationRequest, TranslationFailure) -> Void
    let content: Content

    @State private var configuration: TranslationSession.Configuration?
    @State private var activeLanguagePair = ""

    init(
        request: VocabularyTranslationRequest?,
        onTranslated: @escaping (VocabularyTranslationRequest, String) -> Void,
        onFailed: @escaping (VocabularyTranslationRequest) -> Void = { _ in },
        onDiagnostic: @escaping (VocabularyTranslationRequest, TranslationFailure) -> Void = { _, _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.request = request
        self.onTranslated = onTranslated
        self.onFailed = onFailed
        self.onDiagnostic = onDiagnostic
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
#if targetEnvironment(simulator)
        content
#else
        content
            .translationTask(configuration) { session in
                guard let request, !request.word.isEmpty else { return }
                let source = Locale.Language(identifier: request.sourceLanguage.translationCode)
                let target = Locale.Language(identifier: request.targetLanguage.translationCode)
                let availability = await LanguageAvailability().status(from: source, to: target)
                Logger(subsystem: "ShadowingNative", category: "Translation")
                    .info("stage=availability status=\(String(describing: availability), privacy: .public)")
                guard availability != .unsupported else {
                    let failure = TranslationFailure(stage: .availability, domain: "LanguageAvailability", code: 0)
                    Logger(subsystem: "ShadowingNative", category: "Translation").error("stage=availability domain=LanguageAvailability code=0")
                    await MainActor.run {
                        onDiagnostic(request, failure)
                        onFailed(request)
                    }
                    return
                }
                do {
                    try await session.prepareTranslation()
                } catch {
                    await report(error, stage: .preparation, request: request)
                    return
                }
                do {
                    let response = try await session.translate(request.word)
                    await MainActor.run {
                        onTranslated(request, response.targetText)
                    }
                } catch {
                    await report(error, stage: .translation, request: request)
                }
            }
            .onChange(of: request?.id) { _, _ in
                guard let request else { return }
                let pair = "\(request.sourceLanguage.rawValue)|\(request.targetLanguage.rawValue)"
                if activeLanguagePair == pair, configuration != nil {
                    configuration?.invalidate()
                } else {
                    activeLanguagePair = pair
                    configuration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: request.sourceLanguage.translationCode),
                        target: Locale.Language(identifier: request.targetLanguage.translationCode)
                    )
                }
            }
#endif
    }

    private func report(_ error: Error, stage: TranslationFailure.Stage, request: VocabularyTranslationRequest) async {
        let nsError = error as NSError
        let failure = TranslationFailure(stage: stage, domain: nsError.domain, code: nsError.code)
        Logger(subsystem: "ShadowingNative", category: "Translation")
            .error("stage=\(stage.rawValue, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
        await MainActor.run {
            onDiagnostic(request, failure)
            onFailed(request)
        }
    }
}
