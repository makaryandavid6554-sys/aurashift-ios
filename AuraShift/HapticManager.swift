// HapticManager.swift
// AuraShift — централизованное управление тактильной отдачей

import UIKit
import SwiftUI

// MARK: - HapticManager

final class HapticManager {
    static let shared = HapticManager()
    private init() {}

    // Ленивое создание генераторов: не инициализируем CoreHaptics до реального нажатия.
    private var lightGenerator: UIImpactFeedbackGenerator?
    private var mediumGenerator: UIImpactFeedbackGenerator?
    private var heavyGenerator: UIImpactFeedbackGenerator?
    private var notifyGenerator: UINotificationFeedbackGenerator?
    private var selectionGenerator: UISelectionFeedbackGenerator?

    // Нужно ли воспроизводить хаптику (читается из настроек)
    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    func prepare() {
        guard enabled else { return }
        impactGenerator(.light).prepare()
        impactGenerator(.medium).prepare()
        notificationGenerator().prepare()
        selectionFeedbackGenerator().prepare()
    }

    // MARK: - Публичный API

    /// Лёгкий тап — выбор элемента, нажатие кнопки
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard enabled else { return }
        impactGenerator(style).impactOccurred()
    }

    /// Успех — добавление смены, сохранение
    func success() {
        guard enabled else { return }
        notificationGenerator().notificationOccurred(.success)
    }

    /// Ошибка — удаление, предупреждение
    func error() {
        guard enabled else { return }
        notificationGenerator().notificationOccurred(.error)
    }

    /// Предупреждение
    func warning() {
        guard enabled else { return }
        notificationGenerator().notificationOccurred(.warning)
    }

    /// Смена выбора (например, переключение вкладки, дня)
    func selection() {
        guard enabled else { return }
        selectionFeedbackGenerator().selectionChanged()
    }

    private func impactGenerator(_ style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .light:
            if let generator = lightGenerator { return generator }
            let generator = UIImpactFeedbackGenerator(style: .light)
            lightGenerator = generator
            return generator
        case .medium:
            if let generator = mediumGenerator { return generator }
            let generator = UIImpactFeedbackGenerator(style: .medium)
            mediumGenerator = generator
            return generator
        case .heavy:
            if let generator = heavyGenerator { return generator }
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            heavyGenerator = generator
            return generator
        default:
            if let generator = lightGenerator { return generator }
            let generator = UIImpactFeedbackGenerator(style: .light)
            lightGenerator = generator
            return generator
        }
    }

    private func notificationGenerator() -> UINotificationFeedbackGenerator {
        if let generator = notifyGenerator { return generator }
        let generator = UINotificationFeedbackGenerator()
        notifyGenerator = generator
        return generator
    }

    private func selectionFeedbackGenerator() -> UISelectionFeedbackGenerator {
        if let generator = selectionGenerator { return generator }
        let generator = UISelectionFeedbackGenerator()
        selectionGenerator = generator
        return generator
    }
}

// MARK: - Удобный псевдоним для совместимости с существующим кодом
// В коде уже используется HapticEngine.impact(.light) — добавляем alias
enum HapticEngine {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        HapticManager.shared.impact(style)
    }
    static func success() { HapticManager.shared.success() }
    static func error()   { HapticManager.shared.error()   }
    static func selection() { HapticManager.shared.selection() }
}
