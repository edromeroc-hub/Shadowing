import SwiftUI

struct PrimaryActionButton: View {
    let title: String
    var icon: String? = "arrow.right"
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.headline)
                    if let icon {
                        Image(systemName: icon)
                            .font(.headline.weight(.semibold))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .disabled(!isEnabled || isLoading)
        .modifier(PrimaryButtonAppearance(isEnabled: isEnabled))
        .accessibilityLabel(title)
    }
}

private struct PrimaryButtonAppearance: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .tint(ShadowingTheme.blue.opacity(isEnabled ? 1 : 0.4))
        } else {
            content
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    ShadowingTheme.blue.opacity(isEnabled ? 1 : 0.4),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
    }
}

struct SelectionCard: View {
    let title: String
    let subtitle: String?
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : ShadowingTheme.blue)
                    .frame(width: 42, height: 42)
                    .background(
                        isSelected ? AnyShapeStyle(ShadowingTheme.blue) : AnyShapeStyle(.white.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? ShadowingTheme.blue : .secondary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? ShadowingTheme.blue.opacity(0.12) : Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? ShadowingTheme.blue.opacity(0.8) : .white.opacity(0.08), lineWidth: 1)
        }
    }
}

