import SwiftUI
import UIKit

struct VisionBackdropView: View {
    @AppStorage(UserSettings.wallpaperStyleKey) private var wallpaperRawValue = UserSettings.WallpaperStyle.gradientZipDefault.rawValue

    private var wallpaperStyle: UserSettings.WallpaperStyle {
        UserSettings.WallpaperStyle(rawValue: wallpaperRawValue) ?? .gradientZipDefault
    }

    private var descriptor: GradientManager.GradientDescriptor {
        GradientManager.shared.descriptor(for: wallpaperStyle)
    }

    var body: some View {
        ZStack {
            if UIRuntimeConfig.lightweightInterface {
                AppColors.background
            } else {
                wallpaperFill(named: descriptor.assetName, fallbackColors: descriptor.fallbackColors)

                LinearGradient(
                    colors: [Color.black.opacity(0.14), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [Color.black.opacity(0.10), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            }
        }
        .background(AppColors.background)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func wallpaperFill(named assetName: String, fallbackColors: [Color]) -> some View {
        if let uiImage = UIImage(named: assetName) {
            GeometryReader { proxy in
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        } else {
            LinearGradient(
                colors: fallbackColors,
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

final class GradientManager {
    struct GradientDescriptor: Identifiable {
        let style: UserSettings.WallpaperStyle
        let assetName: String
        let fallbackColors: [Color]
        let textureOpacity: Double
        let topReadabilityScrim: Double
        let bottomReadabilityScrim: Double

        var id: String { style.rawValue }
    }

    static let shared = GradientManager()

    let gradients: [GradientDescriptor] = [
        GradientDescriptor(
            style: .gradientZipDefault,
            assetName: "GradientZipDefault",
            fallbackColors: [Color(red: 0.29, green: 0.36, blue: 0.49), Color(red: 0.63, green: 0.69, blue: 0.80)],
            textureOpacity: 0.25,
            topReadabilityScrim: 0.34,
            bottomReadabilityScrim: 0.20
        ),
        GradientDescriptor(
            style: .gradientZipBlue,
            assetName: "GradientZipBlue",
            fallbackColors: [Color(red: 0.04, green: 0.12, blue: 0.23), Color(red: 0.29, green: 0.43, blue: 0.59)],
            textureOpacity: 0.22,
            topReadabilityScrim: 0.38,
            bottomReadabilityScrim: 0.24
        ),
        GradientDescriptor(
            style: .gradientZipBerry,
            assetName: "GradientZipBerry",
            fallbackColors: [Color(red: 0.21, green: 0.04, blue: 0.16), Color(red: 0.63, green: 0.21, blue: 0.44)],
            textureOpacity: 0.20,
            topReadabilityScrim: 0.36,
            bottomReadabilityScrim: 0.22
        ),
        GradientDescriptor(
            style: .gradientZipGraphite,
            assetName: "GradientZipGraphite",
            fallbackColors: [Color(red: 0.10, green: 0.10, blue: 0.12), Color(red: 0.35, green: 0.35, blue: 0.38)],
            textureOpacity: 0.18,
            topReadabilityScrim: 0.42,
            bottomReadabilityScrim: 0.26
        ),
        GradientDescriptor(
            style: .gradientZipPastel,
            assetName: "GradientZipPastel",
            fallbackColors: [Color(red: 0.88, green: 0.94, blue: 0.95), Color(red: 0.82, green: 0.72, blue: 0.90)],
            textureOpacity: 0.24,
            topReadabilityScrim: 0.28,
            bottomReadabilityScrim: 0.18
        ),
        GradientDescriptor(
            style: .universal,
            assetName: "WallpaperUniversal",
            fallbackColors: [Color(red: 0.82, green: 0.90, blue: 0.88), Color(red: 0.67, green: 0.88, blue: 0.95), Color(red: 0.82, green: 0.70, blue: 0.90)],
            textureOpacity: 0.34,
            topReadabilityScrim: 0.28,
            bottomReadabilityScrim: 0.16
        ),
        GradientDescriptor(
            style: .valleyPair,
            assetName: "WallpaperValleyPair",
            fallbackColors: [Color(red: 0.15, green: 0.24, blue: 0.48), Color(red: 0.37, green: 0.56, blue: 0.82), Color(red: 0.72, green: 0.55, blue: 0.78)],
            textureOpacity: 0.22,
            topReadabilityScrim: 0.34,
            bottomReadabilityScrim: 0.20
        ),
        GradientDescriptor(
            style: .alpinePair,
            assetName: "WallpaperAlpinePair",
            fallbackColors: [Color(red: 0.10, green: 0.16, blue: 0.32), Color(red: 0.17, green: 0.28, blue: 0.50), Color(red: 0.40, green: 0.62, blue: 0.88)],
            textureOpacity: 0.24,
            topReadabilityScrim: 0.38,
            bottomReadabilityScrim: 0.24
        )
    ]

    var selectableStyles: [UserSettings.WallpaperStyle] {
        gradients.map(\.style)
    }

    func descriptor(for style: UserSettings.WallpaperStyle) -> GradientDescriptor {
        gradients.first(where: { $0.style == style })
        ?? gradients.first(where: { $0.style == .gradientZipDefault })!
    }
}

struct VisionGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var opacity: Double = 0.9
    var showRing: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let fillOpacity = min(max(opacity, 0.55), 0.95)

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppColors.surface.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        showRing
                        ? AppColors.accent.opacity(colorScheme == .dark ? 0.34 : 0.28)
                        : AppColors.border.opacity(colorScheme == .dark ? 0.36 : 0.46),
                        lineWidth: showRing ? 1.2 : 1
                    )
            )
    }
}

struct VisionAuraCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .visionGlassCard(
                cornerRadius: cornerRadius,
                opacity: 0.86,
                showRing: true
            )
    }
}

struct VisionSelectionHighlightModifier: ViewModifier {
    var isSelected: Bool
    var cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let ringWidth: CGFloat = isSelected ? 2 : 0
        let ringColor = isSelected
            ? AppColors.accent.opacity(colorScheme == .dark ? 0.70 : 0.58)
            : .clear

        return content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ringColor, lineWidth: ringWidth)
            )
            .lightweightAnimation(.easeOut(duration: 0.12), value: isSelected)
    }
}

extension View {
    // STYLE: Применяет универсальный стеклянный стиль карточки.
    func visionGlassCard(cornerRadius: CGFloat = 16, opacity: Double = 0.9, showRing: Bool = false) -> some View {
        modifier(VisionGlassCardModifier(cornerRadius: cornerRadius, opacity: opacity, showRing: showRing))
    }

    // STYLE: Применяет фирменный фон приложения.
    func visionAppBackground() -> some View {
        background(VisionBackdropView())
    }

    // STYLE: Прозрачный фон формы поверх фирменного бэкдропа.
    func visionFormBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(VisionBackdropView())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    // STYLE: Применяет карточку с дополнительным aura-градиентом.
    func visionAuraCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(VisionAuraCardModifier(cornerRadius: cornerRadius))
    }

    // STYLE: Единый стеклянный стиль для системных List-контейнеров.
    func visionListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(VisionBackdropView())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    // STYLE: Выделение карточки/строки при выборе.
    func visionSelectionHighlight(isSelected: Bool, cornerRadius: CGFloat = 16) -> some View {
        modifier(VisionSelectionHighlightModifier(isSelected: isSelected, cornerRadius: cornerRadius))
    }
}

struct VisionPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.accent.opacity(configuration.isPressed ? 0.72 : 0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColors.accent.opacity(0.35), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .lightweightAnimation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct VisionSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            // STYLE: Вторичная кнопка использует glass-карточку с реакцией на нажатие.
            .visionGlassCard(cornerRadius: 14, opacity: configuration.isPressed ? 0.72 : 0.84)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .lightweightAnimation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct GlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let opacity: Double
    private let showRing: Bool
    private let content: Content

    init(
        cornerRadius: CGFloat = 16,
        opacity: Double = 0.86,
        showRing: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.showRing = showRing
        self.content = content()
    }

    var body: some View {
        content
            .visionGlassCard(cornerRadius: cornerRadius, opacity: opacity, showRing: showRing)
    }
}

struct GlassPanel<Content: View>: View {
    private let cornerRadius: CGFloat
    private let opacity: Double
    private let content: Content

    init(
        cornerRadius: CGFloat = 22,
        opacity: Double = 0.88,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.content = content()
    }

    var body: some View {
        content
            .visionGlassCard(cornerRadius: cornerRadius, opacity: opacity, showRing: true)
    }
}

extension View {
    // STYLE: Универсальный glass-модификатор для карточек/ячеек/панелей.
    func glassBackground(cornerRadius: CGFloat = 16, opacity: Double = 0.86, showRing: Bool = true) -> some View {
        visionGlassCard(cornerRadius: cornerRadius, opacity: opacity, showRing: showRing)
    }
}
