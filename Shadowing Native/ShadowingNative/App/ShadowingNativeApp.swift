import FirebaseCore
import GoogleSignIn
import SwiftUI

@main
struct ShadowingNativeApp: App {
    @State private var appModel = AppModel()
    @State private var authSession = AuthSession()
    @State private var subscriptionStore = SubscriptionStore()
    @State private var progressStore = StudyProgressStore()
    @State private var vocabularyStore = VocabularyStore()
    @State private var cloudStudySync = CloudStudySync()

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--ui-audit") {
                    InterfaceAuditPreview()
                } else {
                    RootView()
                }
#else
                RootView()
#endif
            }
                .environment(appModel)
                .environment(authSession)
                .environment(subscriptionStore)
                .environment(progressStore)
                .environment(vocabularyStore)
                .environment(cloudStudySync)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task {
#if DEBUG && targetEnvironment(simulator)
                    if ProcessInfo.processInfo.arguments.contains("--ui-audit") { return }
#endif
                    authSession.start()
                    await subscriptionStore.prepare()
                }
        }
    }
}
