import SwiftUI

enum LegalDocument: String, Identifiable {
    case privacy = "PrivacyPolicy"
    case terms = "TermsOfUse"
    case support = "Support"

    var id: String { rawValue }

    var webURL: URL {
        let page: String = switch self {
        case .privacy: "privacy"
        case .terms: "terms"
        case .support: "support"
        }
        return URL(string: "https://shadowingapp-native.web.app/\(page).html")!
    }

    var title: String {
        switch self {
        case .privacy: "Política de Privacidade"
        case .terms: "Termos de Uso"
        case .support: "Ajuda e suporte"
        }
    }

    var content: String? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let content = document.content {
                        ForEach(Array(content.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                            if paragraph.hasPrefix("# ") {
                                Text(String(paragraph.dropFirst(2)))
                                    .font(.title2.bold())
                                    .accessibilityAddTraits(.isHeader)
                            } else if paragraph.hasPrefix("## ") {
                                Text(String(paragraph.dropFirst(3)))
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                            } else {
                                Text((try? AttributedString(markdown: paragraph)) ?? AttributedString(paragraph))
                                    .textSelection(.enabled)
                            }
                        }
                    } else {
                        Text("Não foi possível abrir o documento. Entre em contato com o suporte.")
                        Link("ed.romero@msn.com", destination: URL(string: "mailto:ed.romero@msn.com")!)
                    }
                    Link("Abrir versão publicada no navegador", destination: document.webURL)
                        .font(.footnote)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(22)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}

struct LegalLinksView: View {
    @State private var selectedDocument: LegalDocument?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { links }
            VStack(spacing: 8) { links }
        }
        .font(.footnote)
        .sheet(item: $selectedDocument) { LegalDocumentView(document: $0) }
    }

    private var links: some View {
        Group {
            Button("Privacidade") { selectedDocument = .privacy }
            Button("Termos de Uso") { selectedDocument = .terms }
            Button("Suporte") { selectedDocument = .support }
        }
        .buttonStyle(.plain)
        .foregroundStyle(ShadowingTheme.blue)
        .padding(.vertical, 8)
    }
}
