import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import Observation
import Security
import UIKit

struct AccountUser: Equatable {
    enum Provider: Equatable {
        case apple
        case google
        case password
    }

    let id: String
    let name: String
    let email: String?
    let provider: Provider
}

@MainActor
@Observable
final class AuthSession {
    private(set) var user: AccountUser?
    private(set) var hasResolvedInitialSession = false
    var showsAccountDeletionConfirmation = false
    private var listener: AuthStateDidChangeListenerHandle?

    func start() {
        guard listener == nil else { return }
        user = Auth.auth().currentUser.map(Self.accountUser)
        hasResolvedInitialSession = true
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                self?.user = firebaseUser.map(Self.accountUser)
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(
            withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            password: password
        )
        user = Self.accountUser(from: result.user)
    }

    func createAccount(name: String, email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(
            withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            password: password
        )
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty {
            let change = result.user.createProfileChangeRequest()
            change.displayName = displayName
            try? await change.commitChanges()
        }
        user = Self.accountUser(from: result.user)
    }

    func signInWithGoogle() async throws {
        let credential = try await googleCredential()
        let result = try await Auth.auth().signIn(with: credential)
        user = Self.accountUser(from: result.user)
    }

    func signInWithApple() async throws {
        let authorization = try await AppleAuthorizationCoordinator.shared.authorize()
        let credential = OAuthProvider.appleCredential(
            withIDToken: authorization.identityToken,
            rawNonce: authorization.rawNonce,
            fullName: authorization.fullName
        )
        let result = try await Auth.auth().signIn(with: credential)
        user = Self.accountUser(from: result.user)
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func signOut() throws {
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        user = nil
    }

    func deleteCurrentAccount(
        password: String?,
        beforeDelete: @MainActor (String) async throws -> Void = { _ in }
    ) async throws -> String {
        guard let firebaseUser = Auth.auth().currentUser else {
            throw AccountError.notSignedIn
        }

        let providers = Set(firebaseUser.providerData.map(\.providerID))
        if providers.contains("apple.com") {
            let authorization = try await AppleAuthorizationCoordinator.shared.authorize()
            let credential = OAuthProvider.appleCredential(
                withIDToken: authorization.identityToken,
                rawNonce: authorization.rawNonce,
                fullName: authorization.fullName
            )
            try await reauthenticate(firebaseUser, with: credential)
            guard let code = authorization.authorizationCode else {
                throw AccountError.missingAppleAuthorizationCode
            }
            try await Auth.auth().revokeToken(withAuthorizationCode: code)
        } else if providers.contains("google.com") {
            try await reauthenticate(firebaseUser, with: googleCredential())
        } else {
            guard let email = firebaseUser.email, let password, !password.isEmpty else {
                throw AccountError.passwordRequired
            }
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await reauthenticate(firebaseUser, with: credential)
        }

        let deletedUserID = firebaseUser.uid
        guard Auth.auth().currentUser?.uid == deletedUserID else {
            throw AccountError.notSignedIn
        }
        try await beforeDelete(deletedUserID)
        guard Auth.auth().currentUser?.uid == deletedUserID else {
            throw AccountError.notSignedIn
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            firebaseUser.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        GIDSignIn.sharedInstance.signOut()
        user = nil
        return deletedUserID
    }

    static func message(for error: Error) -> String {
        if let accountError = error as? AccountError {
            return accountError.localizedDescription
        }
        let errorCode = (error as NSError).code
        switch errorCode {
        case 17007: return "Este e-mail já está cadastrado."
        case 17008: return "Digite um e-mail válido."
        case 17009, 17011, 17004: return "E-mail ou senha incorretos."
        case 17014: return "Entre novamente na conta antes de tentar excluir."
        case 17020: return "Sem conexão. Verifique a internet e tente novamente."
        case 17026: return "Use uma senha com pelo menos 6 caracteres."
        default:
            if (error as NSError).domain == ASAuthorizationError.errorDomain,
               errorCode == ASAuthorizationError.canceled.rawValue {
                return "Autorização cancelada."
            }
            return error.localizedDescription
        }
    }

    private static func accountUser(from firebaseUser: FirebaseAuth.User) -> AccountUser {
        let providers = Set(firebaseUser.providerData.map(\.providerID))
        let provider: AccountUser.Provider = providers.contains("apple.com")
            ? .apple : (providers.contains("google.com") ? .google : .password)
        let name = firebaseUser.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name?.isEmpty == false ? name : nil)
            ?? firebaseUser.email?.components(separatedBy: "@").first
            ?? "Aluno"
        return AccountUser(
            id: firebaseUser.uid,
            name: displayName,
            email: firebaseUser.email,
            provider: provider
        )
    }

    private func googleCredential() async throws -> AuthCredential {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AccountError.missingGoogleConfiguration
        }
        guard let presenter = UIApplication.shared.accountTopViewController else {
            throw AccountError.missingPresentationContext
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AccountError.missingGoogleToken
        }
        return GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
    }

    private func reauthenticate(_ firebaseUser: FirebaseAuth.User, with credential: AuthCredential) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            firebaseUser.reauthenticate(with: credential) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private enum AccountError: LocalizedError {
    case notSignedIn
    case passwordRequired
    case missingAppleAuthorizationCode
    case missingAppleToken
    case missingGoogleToken
    case missingGoogleConfiguration
    case missingPresentationContext
    case authorizationInProgress
    case unableToGenerateNonce

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Entre na conta para excluí-la."
        case .passwordRequired: "Confirme sua senha para excluir a conta."
        case .missingAppleAuthorizationCode: "A Apple não retornou autorização para revogar o acesso."
        case .missingAppleToken: "A Apple não retornou uma credencial válida."
        case .missingGoogleToken, .missingGoogleConfiguration: "O login Google não está configurado corretamente."
        case .missingPresentationContext: "Não foi possível abrir a tela de login."
        case .authorizationInProgress: "Já existe uma autorização em andamento."
        case .unableToGenerateNonce: "Não foi possível iniciar o login seguro com a Apple."
        }
    }
}

private struct AppleAuthorization {
    let identityToken: String
    let rawNonce: String
    let authorizationCode: String?
    let fullName: PersonNameComponents?
}

@MainActor
private final class AppleAuthorizationCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = AppleAuthorizationCoordinator()

    private var continuation: CheckedContinuation<AppleAuthorization, Error>?
    private var nonce: String?
    private var controller: ASAuthorizationController?

    func authorize() async throws -> AppleAuthorization {
        guard continuation == nil else { throw AccountError.authorizationInProgress }
        let rawNonce = try Self.randomNonce()
        nonce = rawNonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(rawNonce.utf8))
            .map { String(format: "%02x", $0) }.joined()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { reset() }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: AccountError.missingAppleToken)
            return
        }
        continuation?.resume(returning: AppleAuthorization(
            identityToken: token,
            rawNonce: nonce,
            authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
            fullName: credential.fullName
        ))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { reset() }
        continuation?.resume(throwing: error)
    }

    private func reset() {
        continuation = nil
        nonce = nil
        controller = nil
    }

    private static func randomNonce(length: Int = 32) throws -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        while result.count < length {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw AccountError.unableToGenerateNonce
            }
            for byte in bytes where Int(byte) < characters.count && result.count < length {
                result.append(characters[Int(byte)])
            }
        }
        return result
    }
}

private extension UIApplication {
    var accountTopViewController: UIViewController? {
        let root = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: \.isKeyWindow)?.rootViewController
        var presenter = root
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        return presenter
    }
}
