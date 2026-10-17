import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var appModel
    @Environment(AuthSession.self) private var authSession
    @Environment(StudyProgressStore.self) private var progressStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(CloudStudySync.self) private var cloudStudySync

    var body: some View {
        @Bindable var session = authSession

        ZStack {
            if !authSession.hasResolvedInitialSession {
                ProgressView("Preparando sua conta…")
            } else if authSession.user == nil {
                AccountAccessView(requiresAccount: true)
            } else if appModel.hasCompletedOnboarding {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                OnboardingFlowView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.45), value: appModel.hasCompletedOnboarding)
        .animation(.smooth(duration: 0.3), value: authSession.user?.id)
        .alert("Conta excluída", isPresented: $session.showsAccountDeletionConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sua conta de acesso e os estudos desta versão foram excluídos. Assinaturas da App Store devem ser canceladas separadamente.")
        }
        .onChange(of: authSession.user?.id, initial: true) { _, userID in
            appModel.activateAccount(userID)
            progressStore.activateAccount(userID)
            vocabularyStore.activateAccount(userID)
            Task {
                await cloudStudySync.start(
                    accountID: userID,
                    appModel: appModel,
                    progressStore: progressStore,
                    vocabularyStore: vocabularyStore
                )
            }
        }
        .onChange(of: appModel.profileUpdatedAt) { _, _ in saveToCloud() }
        .onChange(of: progressStore.summaries) { _, _ in saveToCloud() }
        .onChange(of: progressStore.listeningWords) { _, _ in saveToCloud() }
        .onChange(of: progressStore.videos) { _, _ in saveToCloud() }
        .onChange(of: progressStore.shortFeedback) { _, _ in saveToCloud() }
        .onChange(of: progressStore.shortChannels) { _, _ in saveToCloud() }
        .onChange(of: progressStore.shortSearches) { _, _ in saveToCloud() }
        .onChange(of: vocabularyStore.entries) { _, _ in saveToCloud() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, authSession.user != nil else { return }
            Task {
                await cloudStudySync.retry(
                    appModel: appModel,
                    progressStore: progressStore,
                    vocabularyStore: vocabularyStore
                )
            }
        }
    }

    private func saveToCloud() {
        cloudStudySync.scheduleSave(
            appModel: appModel,
            progressStore: progressStore,
            vocabularyStore: vocabularyStore
        )
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var appModel
    var previewItems: [YouTubeShortItem]? = nil
    var previewTranscript: YouTubeTranscript? = nil

    var body: some View {
        @Bindable var model = appModel

        TabView(selection: $model.selectedTab) {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label("Hoje", systemImage: "sparkles") }
            .tag(AppTab.today)

            NavigationStack {
                ExploreView()
            }
            .tabItem { Label("Vídeos", systemImage: "play.square.stack.fill") }
            .tag(AppTab.explore)

            ShortsFeedView(previewItems: previewItems, previewTranscript: previewTranscript)
                .tabItem { Label("Shorts", systemImage: "rectangle.portrait.on.rectangle.portrait.fill") }
                .tag(AppTab.shorts)

            NavigationStack {
                MusicHomeView()
            }
            .tabItem { Label("Músicas", systemImage: "music.note.list") }
            .tag(AppTab.music)

            NavigationStack {
                ProgressViewScreen()
            }
            .tabItem { Label("Progresso", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(AppTab.progress)
        }
        .tint(ShadowingTheme.blue)
        .sheet(isPresented: $model.isProfilePresented) {
            NavigationStack {
                ProfileView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fechar") { appModel.isProfilePresented = false }
                        }
                    }
            }
        }
        .ignoresSafeArea(.keyboard, edges: appModel.selectedTab == .shorts ? .bottom : [])
    }
}
