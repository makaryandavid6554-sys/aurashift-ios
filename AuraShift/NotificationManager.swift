import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private let reminderIdentifier = "daily.financial.reminder"

    private init() {}

    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus

        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func syncReminder(with settings: UserSettings) {
        if settings.dailyReminderEnabled {
            scheduleDailyReminder(hour: settings.dailyReminderHour, minute: settings.dailyReminderMinute)
        } else {
            removeDailyReminder()
        }
    }

    func scheduleDailyReminder(hour: Int, minute: Int) {
        removeDailyReminder()

        let content = UNMutableNotificationContent()
        content.title = "Финансовый день"
        content.body = "Добавьте смены и траты за сегодня, чтобы прогноз оставался точным."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: reminderIdentifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    func removeDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }
}
