import SwiftUI

struct MoreHubView: View {
    @ObservedObject var settings: UserSettings
    @State private var activeDestination: Destination?

    private enum Destination: String, Identifiable {
        case history
        case settings

        var id: String { rawValue }
    }

    var body: some View {
        NavigationView {
            ZStack {
                VisionBackdropView()

                VStack(spacing: 14) {
                    Text(NSLocalizedString("Быстрый доступ к истории и настройкам приложения.", comment: "more hub helper text"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    actionRow(
                        icon: "clock",
                        color: .indigo,
                        title: NSLocalizedString("История", comment: "more hub row title: history"),
                        subtitle: NSLocalizedString("Хронология доходов и расходов", comment: "more hub row subtitle: history"),
                        action: { activeDestination = .history }
                    )

                    actionRow(
                        icon: "gearshape.fill",
                        color: .gray,
                        title: NSLocalizedString("Настройки", comment: "more hub row title: settings"),
                        subtitle: NSLocalizedString("Внешний вид, уведомления и данные", comment: "more hub row subtitle: settings"),
                        action: { activeDestination = .settings }
                    )
                }
                // STYLE: Отступы верхнего контента в хабе.
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle(NSLocalizedString("Еще", comment: "more hub title"))
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $activeDestination) { destination in
            switch destination {
            case .history:
                HistoryView(settings: settings)
            case .settings:
                SettingsView(settings: settings)
            }
        }
    }

    @ViewBuilder
    private func actionRow(icon: String, color: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        // STYLE: Подложка иконки с легкой тонировкой цвета секции.
                        .fill(color.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppColors.text)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            // STYLE: Минимальная высота интерактивной строки.
            .frame(minHeight: 56)
            // STYLE: Стеклянная карточка для пункта меню.
            .visionGlassCard(cornerRadius: 14, opacity: 0.84, showRing: true)
        }
        .buttonStyle(.plain)
    }
}
