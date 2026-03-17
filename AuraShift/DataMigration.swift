import Foundation
import CoreData

// MARK: - One-time data migrations
// Notes -> Note migration for Income entities.
// Copies legacy `notes` into `note` when `note` is empty.
// Runs only once per installation (guarded by UserDefaults flag).

enum DataMigration {
    private static let migrationKey = "migration.notes_to_note.completed"

    static func migrateIncomeNotesIfNeeded(context: NSManagedObjectContext) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: migrationKey) == false else { return }

        let fetch: NSFetchRequest<Income> = Income.fetchRequest()
        fetch.returnsObjectsAsFaults = false

        do {
            let incomes = try context.fetch(fetch)

            // If the legacy attribute `notes` is no longer present (model updated), finalize and skip.
            if incomes.first?.entity.attributesByName["notes"] == nil {
                defaults.set(true, forKey: migrationKey)
                return
            }

            var updatedCount = 0

            for income in incomes {
                // Use KVC to be resilient to generated property names
                let currentNote = income.value(forKey: "note") as? String
                let legacyNotes = income.value(forKey: "notes") as? String

                let isNoteEmpty = (currentNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                let hasLegacyNotes = !(legacyNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

                if isNoteEmpty, hasLegacyNotes {
                    income.setValue(legacyNotes, forKey: "note")
                    updatedCount += 1
                }
            }

            if context.hasChanges {
                try context.save()
            }
            defaults.set(true, forKey: migrationKey)
            print("✅ DataMigration: перенесено заметок из `notes` в `note`: \(updatedCount)")
        } catch {
            print("❌ DataMigration: ошибка миграции notes→note: \(error)")
        }
    }
}
