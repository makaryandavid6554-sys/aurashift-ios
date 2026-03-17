import Foundation
import Combine
import CoreData

// NOTE(iCloud): Helper that reflects iCloud account availability and runtime store state.
// CloudKit persistence is currently disabled in Persistence.swift for this build.
// See FULL_RESTORE_AFTER_DEV_ACCOUNT.md, section "1) iCloud / CloudKit (Core Data sync)" for re-enable steps.
final class ICloudSyncManager: ObservableObject {
    static let shared = ICloudSyncManager()

    enum Status {
        case disabled
        case available
        case unavailable
    }

    @Published private(set) var status: Status = .disabled
    @Published private(set) var lastUpdated: Date = Date()

    private init() {}

    var statusTitle: String {
        switch status {
        case .disabled:
            return NSLocalizedString("Отключено", comment: "iCloud sync status title: disabled")
        case .available:
            return NSLocalizedString("Готово к синхронизации", comment: "iCloud sync status title: available")
        case .unavailable:
            return NSLocalizedString("iCloud не доступен", comment: "iCloud sync status title: unavailable")
        }
    }

    var statusDescription: String {
        switch status {
        case .disabled:
            return NSLocalizedString("Синхронизация выключена", comment: "iCloud sync status description: disabled")
        case .available:
            if isRuntimeCloudSyncActive {
                return NSLocalizedString("iCloud аккаунт найден. Синхронизация CloudKit активна.", comment: "iCloud sync status description: active")
            }
            return NSLocalizedString("iCloud аккаунт найден. Подключение CloudKit готово. Для активации синхронизации перезапустите приложение.", comment: "iCloud sync status description: available requires restart")
        case .unavailable:
            return NSLocalizedString("Проверьте вход в iCloud на устройстве.", comment: "iCloud sync status description: unavailable")
        }
    }

    func refresh(isEnabled: Bool) {
        defer { lastUpdated = Date() }
        guard isEnabled else {
            status = .disabled
            return
        }
        status = FileManager.default.ubiquityIdentityToken == nil ? .unavailable : .available
    }

    private var isRuntimeCloudSyncActive: Bool {
        let description = PersistenceController.shared.container.persistentStoreDescriptions.first
        return description?.cloudKitContainerOptions != nil
    }
}

