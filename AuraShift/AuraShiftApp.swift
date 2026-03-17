// AuraShiftApp.swift

import SwiftUI
import CoreData

@main
struct AuraShiftApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var sessionManager = SessionManager(context: PersistenceController.shared.container.viewContext)

    init() {
        LocalizationManager.shared.apply(language: AppLanguage.current())
        // Регистрация категорий безопасна на старте: не вызывает системный запрос
        NotificationManager.registerGoalReminderCategory()
        AIBackgroundTrainingManager.shared.registerIfNeeded()
        AIBackgroundTrainingManager.shared.scheduleNightTraining()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(sessionManager)
        }
    }
}
