import SwiftUI
import UIKit

struct AppColors {
    static let unifiedAccentHex = "#1A52C7"

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    // MARK: - Base Backgrounds
    static var background: Color {
        dynamic(
            light: UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0),
            dark: UIColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1.0)
        )
    }

    static var surface: Color {
        dynamic(
            light: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
            dark: UIColor(red: 0.14, green: 0.17, blue: 0.22, alpha: 1.0)
        )
    }
    
    // MARK: - Accent
    static var accent: Color {
        dynamic(
            light: UIColor(red: 0.10, green: 0.32, blue: 0.78, alpha: 1.0),
            dark: UIColor(red: 0.53, green: 0.69, blue: 1.0, alpha: 1.0)
        )
    }
    
    static func updateAccent(hex: String) {
        // Единая палитра: пользовательский акцент намеренно не применяется.
        _ = hex
    }
    
    // MARK: - Gradient Accent
    static let accentGradient: LinearGradient = {
        return LinearGradient(
            colors: [accent.opacity(0.95), accent.opacity(0.80)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }()
    
    static func cardGradient(from color: Color) -> LinearGradient {
        _ = color
        return LinearGradient(
            colors: [
                surface.opacity(0.94),
                surface.opacity(0.88)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static func premiumStroke(from color: Color) -> LinearGradient {
        _ = color
        return LinearGradient(
            colors: [
                border.opacity(0.95),
                border.opacity(0.70)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static let metallicSheen = LinearGradient(
        colors: [
            Color.white.opacity(0.24),
            Color.white.opacity(0.10),
            .clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // MARK: - Text
    static var text: Color {
        dynamic(
            light: UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0),
            dark: UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1.0)
        )
    }

    static var secondaryText: Color {
        dynamic(
            light: UIColor(red: 0.39, green: 0.43, blue: 0.50, alpha: 1.0),
            dark: UIColor(red: 0.70, green: 0.75, blue: 0.82, alpha: 1.0)
        )
    }
    
    // MARK: - UI
    static var border: Color {
        dynamic(
            light: UIColor.black.withAlphaComponent(0.10),
            dark: UIColor.white.withAlphaComponent(0.22)
        )
    }
    
    // MARK: - Status
    static var positive: Color {
        dynamic(
            light: UIColor(red: 0.10, green: 0.72, blue: 0.39, alpha: 1.0),
            dark: UIColor(red: 0.31, green: 0.91, blue: 0.58, alpha: 1.0)
        )
    }

    static var negative: Color {
        dynamic(
            light: UIColor(red: 0.88, green: 0.30, blue: 0.30, alpha: 1.0),
            dark: UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0)
        )
    }
}

enum UIRuntimeConfig {
    // Облегченный интерфейс включен по умолчанию: минимум анимаций и декора.
    static let lightweightInterface = false
    static let reduceAnimations = true
}

@inline(__always)
func performUIUpdate(_ animation: Animation? = .default, _ updates: @escaping () -> Void) {
    guard !UIRuntimeConfig.reduceAnimations else {
        updates()
        return
    }
    if let animation {
        withAnimation(animation, updates)
    } else {
        withAnimation(.default, updates)
    }
}

extension View {
    @ViewBuilder
    func lightweightAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        if UIRuntimeConfig.reduceAnimations {
            self
        } else {
            self.animation(animation, value: value)
        }
    }
}
