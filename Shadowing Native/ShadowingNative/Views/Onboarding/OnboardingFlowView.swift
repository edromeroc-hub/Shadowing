import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var appModel
    @State private var step: OnboardingStep = .welcome
    @State private var direction = 1

    var body: some View {
        @Bindable var model = appModel

        ZStack {
            AtmosphericBackground()

            VStack(spacing: 0) {
                if step != .welcome {
                    OnboardingHeader(
                        progress: step.progress,
                        backAction: goBack
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                Group {
                    switch step {
                    case .welcome:
                        WelcomeStep(onStart: goForward, onSkip: useSmartDefaults)
                    case .languages:
                        LanguagesStep(
                            nativeLanguage: $model.profile.nativeLanguage,
                            learningLanguage: $model.profile.learningLanguage
                        )
                    case .level:
                        LevelStep(level: $model.profile.level)
                    case .goals:
                        GoalsStep(goals: $model.profile.goals)
                    case .interests:
                        InterestsStep(interests: $model.profile.interests)
                    case .commitment:
                        CommitmentStep(commitment: $model.profile.dailyCommitment)
                    case .plan:
                        PlanStep(profile: model.profile)
                    case .paywall:
                        if BuildAvailability.purchasesEnabled {
                            PaywallView(onSubscribed: finish, onNotNow: finish)
                        } else {
                            BetaAccessView(onContinue: finish)
                        }
                    }
                }
                .id(step)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
                    )
                )

                if step.showsFooter {
                    footer
                }
            }
        }
        .foregroundStyle(.white)
        .animation(.smooth(duration: 0.42), value: step)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            PrimaryActionButton(
                title: step == .plan ? "Ver meu plano" : "Continuar",
                isEnabled: canContinue,
                action: goForward
            )
            Text(step.footerHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var canContinue: Bool {
        switch step {
        case .goals: !appModel.profile.goals.isEmpty
        case .interests: appModel.profile.interests.count >= 2
        default: true
        }
    }

    private func goForward() {
        guard let next = step.next else { return }
        direction = 1
        step = next
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        direction = -1
        step = previous
    }

    private func useSmartDefaults() {
        appModel.profile = .starter
        step = .plan
    }

    private func finish() {
        appModel.completeOnboarding()
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case languages
    case level
    case goals
    case interests
    case commitment
    case plan
    case paywall

    var next: Self? { Self(rawValue: rawValue + 1) }
    var previous: Self? { Self(rawValue: rawValue - 1) }
    var progress: Double { Double(rawValue) / Double(Self.allCases.count - 1) }
    var showsFooter: Bool { self != .welcome && self != .paywall }

    var footerHint: String {
        switch self {
        case .languages: "Começaremos com inglês; novos idiomas chegarão depois"
        case .interests: "Escolha pelo menos 2 temas"
        case .commitment: "Você poderá mudar isso a qualquer momento"
        case .plan: "Seu plano se adapta conforme você pratica"
        default: "Leva menos de 1 minuto"
        }
    }
}

private struct LanguagesStep: View {
    @Binding var nativeLanguage: SupportedLanguage
    @Binding var learningLanguage: SupportedLanguage

    var body: some View {
        OnboardingScroll(
            title: "Quais idiomas fazem parte da sua jornada?",
            subtitle: "Usaremos seu idioma nativo nas traduções e o inglês nos vídeos e exercícios."
        ) {
            onboardingSectionTitle("EU FALO")

            ForEach(SupportedLanguage.nativeOptions) { language in
                SelectionCard(
                    title: language.title,
                    subtitle: language.subtitle,
                    icon: language.icon,
                    isSelected: nativeLanguage == language
                ) {
                    nativeLanguage = language
                }
            }

            onboardingSectionTitle("QUERO APRENDER")
                .padding(.top, 8)

            ForEach(SupportedLanguage.learningOptions) { language in
                SelectionCard(
                    title: language.title,
                    subtitle: "Disponível agora • \(language.subtitle)",
                    icon: language.icon,
                    isSelected: learningLanguage == language
                ) {
                    learningLanguage = language
                }
            }

            Label("Francês, espanhol e outros idiomas de estudo chegarão em novas versões.", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private func onboardingSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .tracking(1.5)
            .foregroundStyle(ShadowingTheme.blue)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingHeader: View {
    let progress: Double
    let backAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: backAction) {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .shadowingGlass(cornerRadius: 21, interactive: true)

            ProgressView(value: progress)
                .tint(ShadowingTheme.blue)
        }
    }
}

private struct WelcomeStep: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(ShadowingTheme.blue.opacity(0.2))
                    .frame(width: 230, height: 230)
                    .blur(radius: 28)

                VStack(spacing: 16) {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 64, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, ShadowingTheme.blue)

                    HStack(spacing: 5) {
                        ForEach(0..<7, id: \.self) { index in
                            Capsule()
                                .fill(index.isMultiple(of: 2) ? ShadowingTheme.blue : ShadowingTheme.violet)
                                .frame(width: 8, height: CGFloat(18 + (index % 4) * 10))
                        }
                    }
                }
                .frame(width: 210, height: 210)
                .shadowingGlass(cornerRadius: 52)
            }

            VStack(spacing: 16) {
                Text("Pare de estudar inglês.\nComece a falar.")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Treine com vídeos reais, uma frase por vez, até o ritmo do inglês virar natural.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 28)

            Spacer()

            VStack(spacing: 14) {
                PrimaryActionButton(title: "Criar meu plano", action: onStart)

                Button("Explorar com um plano sugerido", action: onSkip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: 600)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

private struct LevelStep: View {
    @Binding var level: EnglishLevel

    var body: some View {
        OnboardingScroll(title: "Como está seu inglês hoje?", subtitle: "Vamos ajustar velocidade, vocabulário e tamanho das frases.") {
            ForEach(EnglishLevel.allCases) { option in
                SelectionCard(
                    title: option.title,
                    subtitle: option.subtitle,
                    icon: option.icon,
                    isSelected: level == option
                ) { level = option }
            }
        }
    }
}

private struct GoalsStep: View {
    @Binding var goals: Set<LearningGoal>

    var body: some View {
        OnboardingScroll(title: "O que você quer conquistar?", subtitle: "Escolha tudo que importa. Seu treino vai priorizar esses resultados.") {
            ForEach(LearningGoal.allCases) { goal in
                SelectionCard(
                    title: goal.title,
                    subtitle: nil,
                    icon: goal.icon,
                    isSelected: goals.contains(goal)
                ) {
                    if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) }
                }
            }
        }
    }
}

private struct InterestsStep: View {
    @Binding var interests: Set<LearningInterest>

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        OnboardingScroll(title: "Sobre o que você gosta de ouvir?", subtitle: "Quanto mais interessante o vídeo, maior a chance de você voltar amanhã.") {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(LearningInterest.allCases) { interest in
                    Button {
                        if interests.contains(interest) { interests.remove(interest) } else { interests.insert(interest) }
                    } label: {
                        VStack(alignment: .leading, spacing: 18) {
                            Image(systemName: interest.icon)
                                .font(.title2)
                                .foregroundStyle(interests.contains(interest) ? .white : ShadowingTheme.blue)
                            Text(interest.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .frame(minHeight: 112)
                        .background(
                            interests.contains(interest) ? ShadowingTheme.blue.opacity(0.22) : .white.opacity(0.045),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(interests.contains(interest) ? ShadowingTheme.blue : .white.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CommitmentStep: View {
    @Binding var commitment: DailyCommitment

    var body: some View {
        OnboardingScroll(title: "Qual compromisso cabe na sua rotina?", subtitle: "Metas menores e constantes vencem sessões longas que nunca acontecem.") {
            ForEach(DailyCommitment.allCases) { option in
                SelectionCard(
                    title: option.title,
                    subtitle: option.subtitle,
                    icon: option == .tenMinutes ? "star.fill" : "timer",
                    isSelected: commitment == option
                ) { commitment = option }
            }
        }
    }
}

private struct PlanStep: View {
    let profile: LearningProfile

    var body: some View {
        OnboardingScroll(title: "Seu caminho está pronto", subtitle: "Um plano curto, pessoal e construído para manter o ritmo.") {
            VStack(spacing: 14) {
                PlanMetric(icon: "calendar.badge.checkmark", value: "\(profile.dailyCommitment.sessionsPerWeek)x", label: "por semana")
                PlanMetric(icon: "timer", value: profile.dailyCommitment.title, label: "por sessão")
                PlanMetric(icon: "play.rectangle.fill", value: "3", label: "vídeos iniciais")
            }
            .padding(18)
            .shadowingGlass(cornerRadius: 28)

            VStack(alignment: .leading, spacing: 14) {
                Label("O que você recebe", systemImage: "sparkles")
                    .font(.headline)
                FeatureRow(icon: "scissors", text: "Frases divididas no ponto certo para repetir")
                FeatureRow(icon: "waveform", text: "Treino de fala e escuta com feedback")
                FeatureRow(icon: "wand.and.stars", text: "Sugestões baseadas nos seus interesses")
                FeatureRow(icon: "flame.fill", text: "Sequência diária para transformar intenção em hábito")
            }
            .padding(18)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

private struct PlanMetric: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(ShadowingTheme.blue)
                .frame(width: 32)
            Text(value)
                .font(.title2.bold())
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ShadowingTheme.mint)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(ShadowingTheme.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct OnboardingScroll<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)

                VStack(spacing: 12) {
                    content
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }
}
