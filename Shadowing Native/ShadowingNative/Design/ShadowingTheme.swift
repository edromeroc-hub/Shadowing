import SwiftUI

enum ShadowingTheme {
    static let blue = Color(red: 0.23, green: 0.55, blue: 1.00)
    static let violet = Color(red: 0.58, green: 0.36, blue: 0.98)
    static let coral = Color(red: 1.00, green: 0.37, blue: 0.45)
    static let mint = Color(red: 0.18, green: 0.82, blue: 0.68)
    static let ink = Color(red: 0.025, green: 0.035, blue: 0.065)

    static func gradient(for accent: SuggestionAccent) -> LinearGradient {
        let colors: [Color] = switch accent {
        case .blue: [blue, Color.cyan]
        case .purple: [violet, Color.indigo]
        case .coral: [coral, Color.orange]
        case .mint: [mint, Color.teal]
        case .amber: [Color.orange, Color.yellow]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct AtmosphericBackground: View {
    var body: some View {
        ZStack {
            ShadowingTheme.ink
            RadialGradient(
                colors: [ShadowingTheme.blue.opacity(0.28), .clear],
                center: .topLeading,
                startRadius: 30,
                endRadius: 520
            )
            RadialGradient(
                colors: [ShadowingTheme.violet.opacity(0.22), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 500
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    @ViewBuilder
    func shadowingGlass(cornerRadius: CGFloat = 24, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(
                    .regular.tint(.white.opacity(0.04)).interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else {
                self.glassEffect(
                    .regular.tint(.white.opacity(0.04)),
                    in: .rect(cornerRadius: cornerRadius)
                )
            }
        } else {
            self.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
    }
}

