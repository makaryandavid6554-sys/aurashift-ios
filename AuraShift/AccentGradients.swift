// AccentGradients.swift
// Centralized palette of restrained, human-centric gradients inspired by Microsoft 2024 design trends.
// Use for accents: text, borders, subtle fills.

import SwiftUI

public enum AccentGradients {
    // Единая сдержанная палитра: все градиенты построены вокруг одного акцента.
    public static var calmIndigoBlue: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.accent.opacity(0.95),
                AppColors.accent.opacity(0.78)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Второй вариант оставлен для совместимости, но без отдельной цветовой темы.
    public static var warmSunset: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.accent.opacity(0.84),
                AppColors.accent.opacity(0.64)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Низкоконтрастный акцентный градиент для мягких индикаторов.
    public static var softVioletBlue: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.accent.opacity(0.80),
                AppColors.accent.opacity(0.60)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // System-aware вариант остается единым по тону, меняется только прозрачность.
    public static func systemAdaptive(colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    AppColors.accent.opacity(0.56),
                    AppColors.accent.opacity(0.34)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    AppColors.accent.opacity(0.40),
                    AppColors.accent.opacity(0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
