// AppColors+Accent.swift
// AuraShift — расширение AppColors для динамического акцентного цвета
//
// Добавь в свой существующий AppColors.swift следующее:
//
// 1. Замени статический `accent` на динамический через NotificationCenter
// 2. Добавь метод updateAccent(hex:)
// 3. В UserSettings добавь @Published var accentColorHex: String

// ─────────────────────────────────────────────────────────────────────────────
// ПАТЧ ДЛЯ AppColors.swift
// ─────────────────────────────────────────────────────────────────────────────
//
// В существующем AppColors добавь/замени:
//
//   // БЫЛО:
//   static let accent = Color(hex: "#5E5CE6") ?? .blue
//
//   // СТАЛО:
//   static var accent: Color {
//       let hex = UserDefaults.standard.string(forKey: "accentColorHex") ?? "#5E5CE6"
//       return Color(hex: hex) ?? Color(hex: "#5E5CE6") ?? .blue
//   }
//
//   static func updateAccent(hex: String) {
//       UserDefaults.standard.set(hex, forKey: "accentColorHex")
//       // Уведомляем всё приложение о смене цвета
//       NotificationCenter.default.post(name: .accentColorChanged, object: nil)
//   }
//
// В NotificationCenter.Name добавь:
//   extension Notification.Name {
//       static let accentColorChanged = Notification.Name("aurashift.accentColorChanged")
//   }

import SwiftUI
import Combine

// MARK: - Notification для обновления акцента

extension Notification.Name {
    static let accentColorChanged = Notification.Name("aurashift.accentColorChanged")
}

// MARK: - AccentColorProvider
// Используй этот ObservableObject в ContentView как @StateObject,
// чтобы SwiftUI перерисовал весь граф при смене акцента.

final class AccentColorProvider: ObservableObject {
    static let shared = AccentColorProvider()

    @Published var current: Color = {
        let hex = UserDefaults.standard.string(forKey: "accentColorHex") ?? "#5E5CE6"
        return Color(hex: hex) ?? Color(hex: "#5E5CE6") ?? .blue
    }()

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(colorChanged),
            name: .accentColorChanged,
            object: nil
        )
    }

    @objc private func colorChanged() {
        DispatchQueue.main.async {
            let hex = UserDefaults.standard.string(forKey: "accentColorHex") ?? "#5E5CE6"
            self.current = Color(hex: hex) ?? Color(hex: "#5E5CE6") ?? .blue
        }
    }
}

// MARK: - UserSettings расширение (добавь в UserSettings.swift)
//
// @Published var accentColorHex: String = UserDefaults.standard.string(forKey: "accentColorHex") ?? "#5E5CE6" {
//     didSet {
//         UserDefaults.standard.set(accentColorHex, forKey: "accentColorHex")
//         AppColors.updateAccent(hex: accentColorHex)
//     }
// }
//
// @Published var hapticsEnabled: Bool = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true {
//     didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled") }
// }
//
// @Published var goalReminderEnabled: Bool = UserDefaults.standard.object(forKey: "goalReminderEnabled") as? Bool ?? false {
//     didSet { UserDefaults.standard.set(goalReminderEnabled, forKey: "goalReminderEnabled") }
// }
//
// @Published var goalReminderDaysBefore: Int = UserDefaults.standard.object(forKey: "goalReminderDaysBefore") as? Int ?? 7 {
//     didSet { UserDefaults.standard.set(goalReminderDaysBefore, forKey: "goalReminderDaysBefore") }
// }
