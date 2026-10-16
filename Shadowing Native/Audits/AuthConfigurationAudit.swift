import Foundation

@main
struct AuthConfigurationAudit {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("ShadowingNative")
        let firebase = try dictionary(at: root.appendingPathComponent("GoogleService-Info.plist"))
        let info = try dictionary(at: root.appendingPathComponent("Info.plist"))
        let entitlements = try dictionary(at: root.appendingPathComponent("ShadowingNative.entitlements"))

        precondition(firebase["PROJECT_ID"] as? String == "shadowing-commercial-edromero", "Projeto Firebase incorreto")
        precondition(firebase["BUNDLE_ID"] as? String == "com.edromero.shadowing.next", "Cliente Firebase de outro app")

        let client = firebase["CLIENT_ID"] as? String ?? ""
        let reversedClient = firebase["REVERSED_CLIENT_ID"] as? String ?? ""
        precondition(!client.isEmpty && client.hasSuffix(".apps.googleusercontent.com"), "Cliente Google ausente")
        precondition(reversedClient == client.split(separator: ".").reversed().joined(separator: "."), "Callback Google incompatível com o cliente")
        let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        precondition(schemes.contains(reversedClient), "O app não recebe o retorno do login Google")
        print("PASS Google: cliente iOS e URL de retorno correspondem")

        let apple = entitlements["com.apple.developer.applesignin"] as? [String] ?? []
        precondition(apple.contains("Default"), "Sign in with Apple ausente nos entitlements")
        print("PASS Apple: capacidade declarada no app nativo")
        print("A configuração local não confirma provedores habilitados no Firebase nem um login real.")
    }

    private static func dictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return result
    }
}
