//
//  SubscriptionManager.swift
//  WindWhisper
//
//  订阅管理器 - StoreKit订阅墙
//

import Combine
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    // MARK: - Product IDs

    static let monthlySubscriptionID = "com.windwhisper.premium.monthly"
    static let soundPackID = "com.windwhisper.soundpack.nature"

    private let productIDs: Set<String> = [
        monthlySubscriptionID,
        soundPackID
    ]

    // MARK: - Computed Properties

    var isPremium: Bool {
        purchasedProductIDs.contains(SubscriptionManager.monthlySubscriptionID)
    }

    var hasSoundPack: Bool {
        purchasedProductIDs.contains(SubscriptionManager.soundPackID)
    }

    // MARK: - Singleton

    static let shared = SubscriptionManager()

    private var updateListenerTask: Task<Void, Error>?

    private init() {
        updateListenerTask = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        errorMessage = nil

        do {
            products = try await Product.products(for: productIDs)
            products.sort { $0.price < $1.price }
        } catch {
            errorMessage = "加载产品失败: \(error.localizedDescription)"
            print("加载产品失败: \(error)")
        }

        isLoading = false
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Bool {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()

            // 更新本地存储
            var info = StorageManager.shared.getSubscriptionInfo()
            info.status = .premium
            info.productId = product.id
            if let expirationDate = transaction.expirationDate {
                info.expirationDate = expirationDate
            }
            StorageManager.shared.saveSubscriptionInfo(info)

            return true

        case .userCancelled:
            return false

        case .pending:
            errorMessage = "购买待处理"
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        isLoading = true

        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            errorMessage = "恢复购买失败: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Update Purchased Products

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.revocationDate == nil {
                    purchased.insert(transaction.productID)
                }
            }
        }

        purchasedProductIDs = purchased

        // 更新本地存储
        var info = StorageManager.shared.getSubscriptionInfo()
        if purchased.contains(SubscriptionManager.monthlySubscriptionID) {
            info.status = .premium
        } else {
            info.status = .free
        }
        StorageManager.shared.saveSubscriptionInfo(info)
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updatePurchasedProducts()
                    await transaction.finish()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }

    // MARK: - Verification

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Helper Methods

    func getProduct(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    func formattedPrice(for product: Product) -> String {
        product.displayPrice
    }
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case verificationFailed
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "交易验证失败"
        case .purchaseFailed:
            return "购买失败"
        }
    }
}

// MARK: - Premium Features

extension SubscriptionManager {
    /// 检查是否可以使用某功能
    func canUseFeature(_ feature: PremiumFeature) -> Bool {
        switch feature {
        case .unlimitedRecordings:
            return isPremium
        case .allBGMStyles:
            return isPremium
        case .highQualityExport:
            return isPremium
        case .noAds:
            return isPremium
        case .soundPack:
            return hasSoundPack || isPremium
        }
    }

    /// 免费用户的限制
    var freeUserLimit: FreeUserLimit {
        FreeUserLimit(
            dailyRecordings: 3,
            dailyBGMGenerations: 2,
            availableStyles: [.gentle, .nature]
        )
    }
}

enum PremiumFeature {
    case unlimitedRecordings
    case allBGMStyles
    case highQualityExport
    case noAds
    case soundPack
}

struct FreeUserLimit {
    let dailyRecordings: Int
    let dailyBGMGenerations: Int
    let availableStyles: [BGMStyle]
}
