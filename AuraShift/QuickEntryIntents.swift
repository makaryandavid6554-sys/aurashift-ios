import AppIntents
import CoreData
import Foundation

@available(iOS 17.0, *)
struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Добавить расход"
    static var description = IntentDescription("Быстро добавляет расход в трекер.")
    static var openAppWhenRun = false

    @Parameter(title: "Сумма")
    var amount: Double

    @Parameter(title: "Категория", default: "Другое")
    var category: String

    @Parameter(title: "Комментарий", default: "")
    var note: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            return .result(dialog: "Сумма должна быть больше нуля.")
        }

        let context = PersistenceController.shared.container.viewContext
        let expense = Expense(context: context)
        expense.id = UUID()
        expense.date = Calendar.current.startOfDay(for: Date())
        expense.amount = amount
        expense.category = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Другое" : category
        expense.notes = note
        try context.save()

        let currency = UserDefaults.standard.string(forKey: "defaultCurrency") ?? "₽"
        return .result(dialog: IntentDialog("Добавлен расход \(Int(amount.rounded())) \(currency)."))
    }
}

@available(iOS 17.0, *)
struct AddIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Добавить доход"
    static var description = IntentDescription("Быстро добавляет доход в трекер.")
    static var openAppWhenRun = false

    @Parameter(title: "Сумма")
    var amount: Double

    @Parameter(title: "Источник", default: "Доход")
    var source: String

    @Parameter(title: "Комментарий", default: "")
    var note: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            return .result(dialog: "Сумма должна быть больше нуля.")
        }

        let context = PersistenceController.shared.container.viewContext
        let income = Income(context: context)
        income.id = UUID()
        income.date = Calendar.current.startOfDay(for: Date())
        income.type = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Доход" : source
        income.hoursWorked = 0
        income.hourlyRate = 0
        income.floatingAmount = amount
        income.tips = 0
        income.note = note
        try context.save()

        let currency = UserDefaults.standard.string(forKey: "defaultCurrency") ?? "₽"
        return .result(dialog: IntentDialog("Добавлен доход \(Int(amount.rounded())) \(currency)."))
    }
}

@available(iOS 17.0, *)
struct QuickEntryShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Добавь расход в \(.applicationName)",
                "Запиши трату в \(.applicationName)"
            ],
            shortTitle: "Новый расход",
            systemImageName: "creditcard"
        )
        
        AppShortcut(
            intent: AddIncomeIntent(),
            phrases: [
                "Добавь доход в \(.applicationName)",
                "Запиши доход в \(.applicationName)"
            ],
            shortTitle: "Новый доход",
            systemImageName: "rublesign.circle"
        )
    }
}
