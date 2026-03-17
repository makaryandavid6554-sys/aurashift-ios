// NotificationManager+Goals.swift
// AuraShift — напоминания о дедлайнах целей
//
// Добавь этот файл в проект рядом с существующим NotificationManager.swift
// Метод rescheduleGoalReminders вызывается из SettingsView при сохранении настроек
// и из GoalsView при изменении цели.

import Foundation
import UserNotifications
import CoreData

// MARK: - NotificationManager расширение для целей

extension NotificationManager {

    // MARK: - Перепланирование уведомлений о целях

    /// Пересчитывает и перепланирует все уведомления о дедлайнах целей
    func rescheduleGoalReminders(settings: UserSettings) {
        let isEnabled = UserDefaults.standard.object(forKey: "goalReminderEnabled") as? Bool ?? false
        guard isEnabled else {
            // Если выключено — удаляем все уведомления о целях
            removeAllGoalReminders()
            return
        }
        let daysBefore = max(1, UserDefaults.standard.object(forKey: "goalReminderDaysBefore") as? Int ?? 7)

        // Запрашиваем разрешение (если ещё не дали)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            // Загружаем цели из CoreData
            DispatchQueue.main.async {
                self.scheduleGoalRemindersFromCoreData(
                    daysBefore: daysBefore)
            }
        }
    }

    /// Планирует напоминание для конкретной цели
    func scheduleGoalReminder(goalId: String, goalName: String,
                               deadline: Date, daysBefore: Int) {
        let cal = Calendar.current
        guard let reminderDate = cal.date(byAdding: .day, value: -daysBefore, to: deadline),
              reminderDate > Date() else { return }

        var components = cal.dateComponents([.year, .month, .day], from: reminderDate)
        components.hour = 10  // Уведомление в 10:00
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "📌 Цель близко!"
        content.body  = "До дедлайна «\(goalName)» осталось \(daysBefore) \(daysBefore == 1 ? "день" : daysBefore < 5 ? "дня" : "дней")."
        content.sound = .default
        content.categoryIdentifier = "GOAL_REMINDER"

        let trigger    = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "goal_reminder_\(goalId)_\(daysBefore)d"
        let request    = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Ошибка планирования напоминания о цели: \(error)")
            } else {
                print("✅ Напоминание о цели «\(goalName)» запланировано на \(reminderDate)")
            }
        }
    }

    /// Удаляет все уведомления о целях
    func removeAllGoalReminders() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let goalIds = requests
                .filter { $0.identifier.hasPrefix("goal_reminder_") }
                .map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: goalIds)
            print("🗑 Удалено \(goalIds.count) напоминаний о целях")
        }
    }

    /// Удаляет уведомление для конкретной цели
    func removeGoalReminder(goalId: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.contains("goal_reminder_\(goalId)") }
                .map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Private

    /// Загружает цели из CoreData и планирует уведомления
    private func scheduleGoalRemindersFromCoreData(daysBefore: Int) {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<FinancialGoal>(entityName: "FinancialGoal")
        request.predicate = NSPredicate(format: "isActive == YES")

        do {
            let goals = try context.fetch(request)
            // Сначала удаляем старые
            removeAllGoalReminders()
            // Планируем новые
            for goal in goals {
                guard let deadline = goal.deadline,
                      let name = goal.name,
                      let id = goal.id?.uuidString else { continue }
                scheduleGoalReminder(
                    goalId: id,
                    goalName: name,
                    deadline: deadline,
                    daysBefore: daysBefore)
            }
            print("✅ Перепланировано \(goals.count) напоминаний о целях")
        } catch {
            print("❌ Ошибка загрузки целей: \(error)")
        }
    }
}

// MARK: - Регистрация категории уведомлений
// Вызови в AppDelegate / App.init():
// NotificationManager.registerGoalReminderCategory()

extension NotificationManager {
    static func registerGoalReminderCategory() {
        let openAction = UNNotificationAction(
            identifier: "OPEN_GOALS",
            title: "Открыть цели",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "GOAL_REMINDER",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
