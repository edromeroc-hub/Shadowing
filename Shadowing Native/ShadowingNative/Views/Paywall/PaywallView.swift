import StoreKit
import SwiftUI

struct BetaAccessView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(ShadowingTheme.blue)
                    .accessibilityHidden(true)
                Text("Seu treino está pronto")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Acesso gratuito durante esta versão beta")
                    .font(.headline)
                    .foregroundStyle(ShadowingTheme.mint)
                    .multilineTextAlignment(.center)
                Text("Explore vídeos e Shorts, pratique escuta ativa e salve seu vocabulário. Não é necessário assinar e não haverá cobrança automática ao terminar o beta.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                PrimaryActionButton(title: "Começar a praticar", icon: "play.fill", action: onContinue)
                Text("Encontrou um problema? Envie seu feedback pelo TestFlight ou pelo suporte no Perfil.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                LegalLinksView()
            }
            .frame(maxWidth: 560)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

struct PaywallView: View {
    @Environment(SubscriptionStore.self) private var store
    let onSubscribed: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(ShadowingTheme.violet.opacity(0.22))
                            .frame(width: 130, height: 130)
                            .blur(radius: 18)
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 54))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, ShadowingTheme.violet)
                    }

                    Text("Transforme seu plano\nem fluência real")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Pratique escuta e repetição com vídeos, uma frase por vez.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    PaywallBenefit(icon: "repeat", text: "Repetição de frases no seu ritmo")
                    PaywallBenefit(icon: "ear", text: "Exercícios de escuta ativa")
                    PaywallBenefit(icon: "bookmark.fill", text: "Histórico e vocabulário pessoal")
                }
                .padding(18)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(spacing: 12) {
                    PlanOption(
                        title: "Anual",
                        badge: nil,
                        detail: priceDetail(for: SubscriptionStore.annualID, fallback: "Plano anual"),
                        isSelected: store.selectedProductID == SubscriptionStore.annualID
                    ) { store.selectedProductID = SubscriptionStore.annualID }

                    PlanOption(
                        title: "Mensal",
                        badge: nil,
                        detail: priceDetail(for: SubscriptionStore.monthlyID, fallback: "Plano mensal"),
                        isSelected: store.selectedProductID == SubscriptionStore.monthlyID
                    ) { store.selectedProductID = SubscriptionStore.monthlyID }
                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(ShadowingTheme.coral)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    PrimaryActionButton(
                        title: trialButtonTitle,
                        icon: "sparkles",
                        isEnabled: selectedProduct != nil && !store.isPurchasing,
                        isLoading: store.isPurchasing
                    ) {
                        Task {
                            if await store.purchaseSelected() {
                                onSubscribed()
                            }
                        }
                    }

                    Button("Agora não", action: onNotNow)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Button("Restaurar compras") {
                        Task {
                            await store.restore()
                            if store.isSubscribed { onSubscribed() }
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                Text("A cobrança e a renovação são gerenciadas pela App Store. O valor e a elegibilidade para teste gratuito aparecem conforme sua conta.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                LegalLinksView()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
        .onChange(of: store.isSubscribed) { _, subscribed in
            if subscribed { onSubscribed() }
        }
    }

    private var selectedProduct: Product? {
        store.product(for: store.selectedProductID)
    }

    private var trialButtonTitle: String {
        guard selectedProduct != nil else { return "Planos indisponíveis nesta build" }
        return "Começar meu plano"
    }

    private func priceDetail(for id: String, fallback: String) -> String {
        guard let product = store.product(for: id) else { return fallback }
        return product.displayPrice + (id == SubscriptionStore.annualID ? " por ano" : " por mês")
    }
}

private struct PaywallBenefit: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(ShadowingTheme.mint)
                .frame(width: 26)
            Text(text)
                .font(.subheadline.weight(.medium))
            Spacer()
        }
    }
}

private struct PlanOption: View {
    let title: String
    let badge: String?
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? ShadowingTheme.blue : .secondary)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ShadowingTheme.violet, in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(
                isSelected ? ShadowingTheme.blue.opacity(0.14) : .white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? ShadowingTheme.blue : .white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}
