//
//  Persistence.swift
//  AuraShift
//
// 

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        let modelName = "MoneyTracker"
        let iCloudEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        
        if iCloudEnabled {
            let cloudContainer = NSPersistentCloudKitContainer(name: modelName)
            Self.configureStoreDescription(
                for: cloudContainer,
                inMemory: inMemory,
                cloudKitContainerIdentifier: "iCloud.\(Bundle.main.bundleIdentifier!)"
            )
            if Self.loadStores(for: cloudContainer) {
                container = cloudContainer
                Self.configureContext(for: cloudContainer)
                return
            } else {
                print("⚠️ CloudKit store недоступен, переключаемся на локальный store.")
            }
        }
        
        let localContainer = NSPersistentContainer(name: modelName)
        Self.configureStoreDescription(for: localContainer, inMemory: inMemory, cloudKitContainerIdentifier: nil)
        guard Self.loadStores(for: localContainer) else { fatalError("Unresolved Core Data error") }
        container = localContainer
        Self.configureContext(for: localContainer)
    }
    
    private static func configureStoreDescription(
        for container: NSPersistentContainer,
        inMemory: Bool,
        cloudKitContainerIdentifier: String?
    ) {
        guard let description = container.persistentStoreDescriptions.first else { return }
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }
        if let identifier = cloudKitContainerIdentifier,
           container is NSPersistentCloudKitContainer {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: identifier)
            description.cloudKitContainerOptions = options
        } else {
            description.cloudKitContainerOptions = nil
        }
    }
    
    private static func loadStores(for container: NSPersistentContainer) -> Bool {
        var loadedSuccessfully = false
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            if let error = error {
                print("❌ Error loading store: \(error.localizedDescription)")
                loadedSuccessfully = false
            } else {
                loadedSuccessfully = true
            }
            semaphore.signal()
        }
        semaphore.wait()
        return loadedSuccessfully
    }
    
    private static func configureContext(for container: NSPersistentContainer) {
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
