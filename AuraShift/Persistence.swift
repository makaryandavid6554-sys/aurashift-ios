//
//  Persistence.swift
//  AuraShift
//
//  Created by David Makarian on 24.02.2026.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let modelName = "MoneyTracker"

        // See FULL_RESTORE_AFTER_DEV_ACCOUNT.md, section "1) iCloud / CloudKit (Core Data sync)" for steps to re-enable.
        // iCloud/CloudKit sync is DISABLED for this build.
        // We always use a local NSPersistentContainer to avoid requiring iCloud entitlements.
        // TODO(iCloud): Re-enable CloudKit path after purchasing a paid Apple Developer account and
        // adding iCloud capability + proper entitlements. Then restore the conditional path that
        // instantiates NSPersistentCloudKitContainer when settings.iCloudSyncEnabled == true.

        let localContainer = NSPersistentContainer(name: modelName)
        Self.configureStoreDescription(for: localContainer, inMemory: inMemory, cloudKitContainerIdentifier: nil)
        guard Self.loadStores(for: localContainer) else {
            fatalError("Unresolved Core Data error: не удалось открыть локальное хранилище.")
        }
        container = localContainer
        Self.configureContext(for: localContainer)
    }
    
    func save() {
        let context = container.viewContext
        if context.hasChanges {
            try? context.save()
        }
    }

    /// Удаляет все финансовые данные пользователя (доходы, расходы, цели)
    /// и локальные планы смен. Настройки приложения не затрагивает.
    func deleteAllData() throws {
        let context = container.viewContext

        let entityNames = ["Income", "Expense", "FinancialGoal"]
        for entityName in entityNames {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeObjectIDs

            let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
            if let objectIDs = result?.result as? [NSManagedObjectID], !objectIDs.isEmpty {
                let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
            }
        }

        UserDefaults.standard.removeObject(forKey: "plannedShifts")
        NotificationCenter.default.post(name: .aurashiftDataDidReset, object: nil)
    }

    // MARK: - Private helpers

    private static func configureStoreDescription(
        for container: NSPersistentContainer,
        inMemory: Bool,
        cloudKitContainerIdentifier: String?
    ) {
        guard let description = container.persistentStoreDescriptions.first else { return }
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }

        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        // Force-disable any CloudKit options while iCloud sync is turned off for this build.
        description.cloudKitContainerOptions = nil
    }

    private static func loadStores(for container: NSPersistentContainer) -> Bool {
        var loadError: NSError?
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                loadError = error
            }
        }
        if let loadError {
            print("❌ Ошибка загрузки persistent store: \(loadError), \(loadError.userInfo)")
            return false
        }
        return true
    }

    private static func configureContext(for container: NSPersistentContainer) {
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

extension Notification.Name {
    static let aurashiftDataDidReset = Notification.Name("aurashift.dataDidReset")
}

