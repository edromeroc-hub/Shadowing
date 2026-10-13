import Foundation
import Observation
import StoreKit

enum BuildAvailability {
    static let purchasesEnabled = false
}

@MainActor
@Observable
final class SubscriptionStore {
    static let monthlyID = "com.edromero.shadowing.pro.monthly"
    static let annualID = "com.edromero.shadowing.pro.annual"

    var products: [Product] = []
    var selectedProductID = annualID
    var isLoading = false
    var isPurchasing = false
    var isSubscribed = false
    var errorMessage: String?
    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?

    func prepare() async {
        guard BuildAvailability.purchasesEnabled else { return }
        if transactionUpdatesTask == nil {
            transactionUpdatesTask = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { return }
                    guard case .verified(let transaction) = result,
                          [Self.monthlyID, Self.annualID].contains(transaction.productID) else { continue }
                    await refreshEntitlements()
                    await transaction.finish()
                }
            }
        }
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        guard BuildAvailability.purchasesEnabled else {
            products = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            products = try await Product.products(for: [Self.monthlyID, Self.annualID])
                .sorted { lhs, rhs in
                    lhs.id == Self.annualID && rhs.id != Self.annualID
                }
        } catch {
            products = []
            errorMessage = "Não foi possível carregar os planos agora."
        }
    }

    func purchaseSelected() async -> Bool {
        guard BuildAvailability.purchasesEnabled else {
            errorMessage = "Esta versão beta é gratuita e não oferece compras."
            return false
        }
        guard !isPurchasing else { return false }
        errorMessage = nil
        guard let product = products.first(where: { $0.id == selectedProductID }) else {
            errorMessage = "Os planos ainda não estão disponíveis nesta build."
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isSubscribed
            case .pending:
                errorMessage = "Compra aguardando aprovação. Seu acesso será atualizado quando a App Store confirmar."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "A compra não pôde ser concluída."
            return false
        }
    }

    func restore() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "Não foi possível restaurar suas compras."
        }
    }

    func refreshEntitlements() async {
        var hasActiveSubscription = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if [Self.monthlyID, Self.annualID].contains(transaction.productID),
               transaction.revocationDate == nil,
               !transaction.isUpgraded,
               transaction.expirationDate.map({ $0 > Date() }) ?? true {
                hasActiveSubscription = true
            }
        }

        isSubscribed = hasActiveSubscription
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): value
        case .unverified:
            throw StoreError.failedVerification
        }
    }
}

private enum StoreError: Error {
    case failedVerification
}
