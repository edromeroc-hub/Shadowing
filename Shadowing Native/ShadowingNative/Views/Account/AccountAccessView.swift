import AuthenticationServices
import GoogleSignIn
import SwiftUI

struct AccountAccessView: View {
    var requiresAccount = false
    @Environment(AuthSession.self) private var authSession
    @Environment(\.dismiss) private var dismiss
    @State private var isCreatingAccount = true
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var message: String?
    @State private var hasAcceptedTerms = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, email, password
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 48))
                            .foregroundStyle(ShadowingTheme.blue)
                        Text("Seu inglês começa aqui")
                            .font(.largeTitle.bold())
                        Text("Entre ou crie sua conta para salvar seus estudos e receber vídeos no seu nível.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Acesso", selection: $isCreatingAccount) {
                            Text("Entrar").tag(false)
                            Text("Criar conta").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .disabled(isBusy)

                        if isCreatingAccount {
                            TextField("Seu nome", text: $name)
                                .textContentType(.name)
                                .focused($focusedField, equals: .name)
                                .accountField()
                        }
                        TextField("E-mail", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .accountField()
                        SecureField("Senha", text: $password)
                            .textContentType(isCreatingAccount ? .newPassword : .password)
                            .focused($focusedField, equals: .password)
                            .accountField()

                        LegalLinksView()
                        Toggle("Aceito os Termos de Uso e estou ciente da Política de Privacidade.", isOn: $hasAcceptedTerms)
                            .font(.footnote)
                            .tint(ShadowingTheme.blue)
                            .disabled(isBusy)

                        if let message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(ShadowingTheme.coral)
                                .accessibilityIdentifier("account.message")
                        }

                        Button {
                            run {
                                if isCreatingAccount {
                                    try await authSession.createAccount(name: name, email: email, password: password)
                                } else {
                                    try await authSession.signIn(email: email, password: password)
                                }
                            }
                        } label: {
                            Text(isCreatingAccount ? "Criar conta" : "Entrar")
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ShadowingTheme.blue)
                        .disabled(isBusy || email.isEmpty || password.isEmpty || !hasAcceptedTerms)

                        if !isCreatingAccount {
                            Button("Esqueci minha senha") {
                                run {
                                    try await authSession.sendPasswordReset(email: email)
                                    message = "Enviamos um link para redefinir sua senha."
                                } dismissOnSuccess: { false }
                            }
                            .font(.footnote)
                            .disabled(isBusy || email.isEmpty)
                        }

                        HStack {
                            Rectangle().frame(height: 1)
                            Text("ou continue com").font(.caption)
                                .fixedSize()
                            Rectangle().frame(height: 1)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)

                        VStack(spacing: 12) {
                            NativeAppleSignInButton {
                                run { try await authSession.signInWithApple() }
                            }
                            .frame(height: 50)
                            .accessibilityIdentifier("account.apple")

                            NativeGoogleSignInButton {
                                run { try await authSession.signInWithGoogle() }
                            }
                            .frame(height: 50)
                            .accessibilityIdentifier("account.google")
                        }
                        .disabled(isBusy || !hasAcceptedTerms)

                    }
                    .padding(24)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Conta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !requiresAccount {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fechar") { dismiss() }
                    }
                }
            }
            .overlay {
                if isBusy {
                    ProgressView()
                        .padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func run(
        _ operation: @escaping () async throws -> Void,
        dismissOnSuccess: @escaping () -> Bool = { true }
    ) {
        guard !isBusy else { return }
        focusedField = nil
        isBusy = true
        message = nil
        Task {
            defer { isBusy = false }
            do {
                try await operation()
                if dismissOnSuccess() { dismiss() }
            } catch {
                if !AuthSession.isCancellation(error) {
                    message = AuthSession.message(for: error)
                }
            }
        }
    }
}

struct AccountDeletionView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(CloudStudySync.self) private var cloudStudySync
    @Environment(AppModel.self) private var appModel
    @Environment(StudyProgressStore.self) private var progressStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isDeleting = false
    @State private var showConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(ShadowingTheme.coral)
                        Text("Excluir minha conta")
                            .font(.largeTitle.bold())
                        Text("A exclusão é permanente. Sua conta Firebase e os dados de estudo desta versão, no aparelho e no Firestore, serão removidos. Não é apenas desativação.")
                            .foregroundStyle(.secondary)
                        Text("Uma assinatura ativa deve ser cancelada separadamente nos ajustes da App Store.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if authSession.user?.provider == .password {
                            SecureField("Confirme sua senha", text: $password)
                                .textContentType(.password)
                                .accountField()
                        } else {
                            Text("Você confirmará sua identidade novamente com \(authSession.user?.provider == .apple ? "a Apple" : "o Google").")
                                .font(.subheadline)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(ShadowingTheme.coral)
                        }

                        Button(role: .destructive) {
                            showConfirmation = true
                        } label: {
                            Label(isDeleting ? "Excluindo…" : "Excluir conta permanentemente", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ShadowingTheme.coral)
                        .disabled(isDeleting || (authSession.user?.provider == .password && password.isEmpty))
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Excluir conta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .confirmationDialog(
                "Excluir sua conta e os dados de estudo?",
                isPresented: $showConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sim, excluir permanentemente", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("Esta ação não pode ser desfeita.")
            }
            .interactiveDismissDisabled(isDeleting)
        }
    }

    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            let deletedUserID = try await authSession.deleteCurrentAccount(password: password) { userID in
                try await cloudStudySync.delete(accountID: userID)
            }
            appModel.deleteAccountData(for: deletedUserID)
            progressStore.deleteAccountData(for: deletedUserID)
            vocabularyStore.deleteAccountData(for: deletedUserID)
            authSession.showsAccountDeletionConfirmation = true
            dismiss()
        } catch {
            await cloudStudySync.resumeAfterFailedDeletion(
                appModel: appModel,
                progressStore: progressStore,
                vocabularyStore: vocabularyStore
            )
            errorMessage = AuthSession.message(for: error)
        }
    }
}

private struct NativeGoogleSignInButton: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> GIDSignInButton {
        let button = GIDSignInButton()
        button.style = .wide
        button.colorScheme = .light
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ view: GIDSignInButton, context: Context) {
        context.coordinator.action = action
        view.isEnabled = context.environment.isEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) { self.action = action }

        @objc func tapped() { action() }
    }
}

private struct NativeAppleSignInButton: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: .white)
        button.cornerRadius = 12
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ view: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        view.isEnabled = context.environment.isEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) { self.action = action }

        @objc func tapped() { action() }
    }
}

private extension View {
    func accountField() -> some View {
        padding(15)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
