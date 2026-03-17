// ProManager.swift
// AuraShift — управление Pro-статусом (подготовка к In-App Purchase)

import Foundation
import SwiftUI
import Combine
import StoreKit

// MARK: - ProManager

/// Централизованное управление Pro-статусом.
/// После подключения StoreKit — ProManager будет верифицировать покупку.
/// Сейчас: читает флаг из UserDefaults (для тестирования).
final class ProManager: ObservableObject {
    static let shared = ProManager()

    private let proKey = "aurashift.isProUser"
    private let debugForceUnlockKey = "aurashift.debugForceUnlockPro"
    private let debugForceFreeKey = "aurashift.debugForceFree"
    private let proProductIDs: Set<String> = [
        "aurashift.pro.monthly",
        "aurashift.pro.yearly",
        "aurashift.pro.lifetime"
    ]

    @Published var isProUser: Bool {
        didSet { UserDefaults.standard.set(isProUser, forKey: proKey) }
    }
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var isPurchaseInProgress: Bool = false
    @Published var storeMessage: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        self.isProUser = UserDefaults.standard.bool(forKey: proKey)
        observeTransactions()
        Task { [weak self] in
            await self?.refreshEntitlements()
            await self?.loadProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Pro Feature Check

    /// Проверить доступность функции. В будущем — верификация через StoreKit.
    func canUse(_ feature: ProFeature) -> Bool {
        switch feature.tier {
        case .free: return true
        case .pro:
            if debugForceFreeEnabled { return false }
            return debugForceUnlockEnabled || isProUser
        }
    }

    var selectedProduct: Product? {
        availableProducts.first
    }

    func loadProducts() async {
        setLoadingProducts(true)
        defer { setLoadingProducts(false) }

        do {
            let products = try await Product.products(for: Array(proProductIDs))
            let sorted = products.sorted { lhs, rhs in
                productRank(lhs.id) < productRank(rhs.id)
            }
            DispatchQueue.main.async {
                self.availableProducts = sorted
            }
        } catch {
            DispatchQueue.main.async {
                self.storeMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        setPurchaseInProgress(true)
        defer { setPurchaseInProgress(false) }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isProUser
            case .pending:
                DispatchQueue.main.async {
                    self.storeMessage = NSLocalizedString("Покупка ожидает подтверждения.", comment: "store purchase pending")
                }
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            DispatchQueue.main.async {
                self.storeMessage = error.localizedDescription
            }
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return isProUser
        } catch {
            DispatchQueue.main.async {
                self.storeMessage = error.localizedDescription
            }
            return false
        }
    }

    func clearStoreMessage() {
        storeMessage = nil
    }

    // MARK: - Тестовый метод (убрать перед релизом)
    func unlockProForTesting() {
        #if DEBUG
        UserDefaults.standard.set(true, forKey: debugForceUnlockKey)
        UserDefaults.standard.set(false, forKey: debugForceFreeKey)
        isProUser = true
        objectWillChange.send()
        #endif
    }

    func disableDebugUnlock() {
        #if DEBUG
        UserDefaults.standard.set(false, forKey: debugForceUnlockKey)
        Task { [weak self] in
            await self?.refreshEntitlements()
        }
        objectWillChange.send()
        #endif
    }

    func enableDebugForcedFree() {
        #if DEBUG
        UserDefaults.standard.set(true, forKey: debugForceFreeKey)
        UserDefaults.standard.set(false, forKey: debugForceUnlockKey)
        isProUser = false
        objectWillChange.send()
        #endif
    }

    func disableDebugForcedFree() {
        #if DEBUG
        UserDefaults.standard.set(false, forKey: debugForceFreeKey)
        Task { [weak self] in
            await self?.refreshEntitlements()
        }
        objectWillChange.send()
        #endif
    }

    var debugForceUnlockEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: debugForceUnlockKey)
        #else
        return false
        #endif
    }

    var debugForceFreeEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: debugForceFreeKey)
        #else
        return false
        #endif
    }

    // MARK: - StoreKit internals

    private func refreshEntitlements() async {
        var hasProEntitlement = false

        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else { continue }
            if proProductIDs.contains(transaction.productID) {
                hasProEntitlement = true
                break
            }
        }

        DispatchQueue.main.async {
            if self.debugForceFreeEnabled {
                self.isProUser = false
            } else {
                self.isProUser = hasProEntitlement || self.debugForceUnlockEnabled
            }
        }
    }

    private func observeTransactions() {
        updatesTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    private func setLoadingProducts(_ value: Bool) {
        DispatchQueue.main.async {
            self.isLoadingProducts = value
        }
    }

    private func setPurchaseInProgress(_ value: Bool) {
        DispatchQueue.main.async {
            self.isPurchaseInProgress = value
        }
    }

    private func productRank(_ id: String) -> Int {
        let lowercased = id.lowercased()
        if lowercased.contains("year") || lowercased.contains("annual") {
            return 0
        }
        if lowercased.contains("month") {
            return 1
        }
        if lowercased.contains("life") {
            return 2
        }
        return 3
    }
}

private enum StoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        NSLocalizedString("Не удалось подтвердить покупку.", comment: "store purchase verification failed")
    }
}

// MARK: - ProFeature

enum ProFeatureTier { case free, pro }

enum ProFeature {
    // Free
    case basicAI, csvExport, appLock, accentColor, goalReminders, haptics, language, appInfo
    // Pro
    case advancedML, externalFactors, budgets, xlsxExport, schedulePlanner, featureImportance

    var tier: ProFeatureTier {
        switch self {
        case .basicAI, .csvExport, .appLock, .accentColor,
             .goalReminders, .haptics, .language, .appInfo:
            return .free
        case .advancedML, .externalFactors, .budgets,
             .xlsxExport, .schedulePlanner, .featureImportance:
            return .pro
        }
    }

    var displayName: String {
        switch self {
        case .basicAI:         return NSLocalizedString("AI-анализ", comment: "pro feature display name: basic AI")
        case .csvExport:       return NSLocalizedString("Экспорт CSV", comment: "pro feature display name: csv export")
        case .appLock:         return NSLocalizedString("Блокировка", comment: "pro feature display name: app lock")
        case .accentColor:     return NSLocalizedString("Цвет темы", comment: "pro feature display name: accent color")
        case .goalReminders:   return NSLocalizedString("Напоминания о целях", comment: "pro feature display name: goal reminders")
        case .haptics:         return NSLocalizedString("Вибрация", comment: "pro feature display name: haptics")
        case .language:        return NSLocalizedString("Язык", comment: "pro feature display name: language")
        case .appInfo:         return NSLocalizedString("О приложении", comment: "pro feature display name: app info")
        case .advancedML:      return NSLocalizedString("Улучшенный AI (Pro)", comment: "pro feature display name: advanced ML")
        case .externalFactors: return NSLocalizedString("Погода и праздники (Pro)", comment: "pro feature display name: external factors")
        case .budgets:         return NSLocalizedString("AI-ориентиры бюджета (Pro)", comment: "pro feature display name: budgets")
        case .xlsxExport:      return NSLocalizedString("Экспорт в Excel (Pro)", comment: "pro feature display name: xlsx export")
        case .schedulePlanner: return "Планировщик графика (Pro)"
        case .featureImportance: return "Анализ факторов (Pro)"
        }
    }

    var proDescription: String {
        switch self {
        case .advancedML:
            return "Random Forest и градиентный бустинг для более точных прогнозов дохода"
        case .externalFactors:
            return "Учёт погоды и праздников при прогнозировании — умнее в нужный момент"
        case .budgets:
            return "AI-ориентиры расходов по категориям, чтобы успевать к цели в срок"
        case .xlsxExport:
            return "Выгрузка отчётов в Excel с графиками и форматированием"
        case .schedulePlanner:
            return "Персональный план работы на неделю/месяц с учётом целей"
        case .featureImportance:
            return "Подробный разбор: какие факторы влияют на ваш доход и насколько"
        default:
            return ""
        }
    }
}

// MARK: - ProGateView

/// Универсальная заглушка-баннер для Pro-функций
struct ProGateView: View {
    let feature: ProFeature
    var onUpgrade: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    // STYLE: Градиентный круг-иконка Pro-блока.
                    .fill(LinearGradient(
                        colors: [Color(hex: "#6C5CE7") ?? .purple,
                                 Color(hex: "#a29bfe") ?? .purple.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    // STYLE: Размер иконки хедера.
                    .frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 6) {
                Text(NSLocalizedString("AuraShift Pro", comment: "pro gate title"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppColors.text)
                Text(feature.proDescription)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: { onUpgrade?() }) {
                Text(NSLocalizedString("Открыть Pro", comment: "pro gate open action"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#6C5CE7") ?? .purple,
                                     Color(hex: "#4834d4") ?? .purple],
                            startPoint: .leading, endPoint: .trailing)
                    )
                    // STYLE: Скругление CTA-кнопки.
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
        // STYLE: Внешние отступы и фон карточки Pro-баннера.
        .padding(24)
        .visionGlassCard(cornerRadius: 20, opacity: 0.84, showRing: true)
        // STYLE: Градиентная обводка карточки.
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(
            LinearGradient(colors: [Color(hex: "#6C5CE7")?.opacity(0.5) ?? .purple.opacity(0.5), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1.5))
        .padding(.horizontal, 16)
    }
}
