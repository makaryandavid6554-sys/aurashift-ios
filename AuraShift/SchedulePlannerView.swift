import SwiftUI

struct SchedulePlannerView: View {
    @ObservedObject var ai: AIEngine
    let settings: UserSettings

    @Environment(\.dismiss) private var dismiss
    @State private var horizonDays = 14
    @State private var recommendations: [ShiftRecommendation] = []

    var body: some View {
        NavigationView {
            ZStack {
                VisionBackdropView()

                VStack(spacing: 14) {
                    Picker(NSLocalizedString("Период", comment: "planner horizon picker title"), selection: $horizonDays) {
                        Text("7").tag(7)
                        Text("14").tag(14)
                        Text("30").tag(30)
                    }
                    .pickerStyle(.segmented)
                    // STYLE: Внутренние отступы сегмент-контрола периода.
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    // STYLE: Стеклянная карточка фильтра периода.
                    .visionGlassCard(cornerRadius: 14, opacity: 0.82)
                    .padding(.horizontal)
                    .onChange(of: horizonDays) { _ in loadRecommendations() }

                    if recommendations.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                // STYLE: Размер иконки пустого состояния.
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(AppColors.secondaryText)
                            Text(NSLocalizedString("Нет рекомендаций на выбранный период.", comment: "planner empty state"))
                                .font(.subheadline)
                                .foregroundColor(AppColors.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 34)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(recommendations) { rec in
                                    plannerCard(for: rec)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle(NSLocalizedString("Планировщик графика", comment: "planner screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Готово", comment: "common done action")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear { loadRecommendations() }
    }

    @ViewBuilder
    private func plannerCard(for rec: ShiftRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        // STYLE: Полупрозрачный фон иконки рекомендации.
                        .fill(AppColors.accent.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: rec.workTypeIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.workTypeName)
                        .font(.headline)
                        .foregroundColor(AppColors.text)
                    Text(plannerDateString(rec.date))
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                Spacer()
                Text("~\(settings.formattedCurrency(rec.expectedIncome))")
                    .font(.headline)
                    .foregroundColor(AppColors.accent)
            }

            Text(
                String(
                    format: NSLocalizedString("Уверенность %d%%", comment: "planner confidence"),
                    Int(rec.confidence * 100)
                )
            )
            .font(.caption2.weight(.semibold))
            .foregroundColor(AppColors.secondaryText)

            ForEach(rec.reasons.prefix(2), id: \.self) { reason in
                Text("• \(reason)")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .padding(14)
        // STYLE: Визуальный контейнер карточки рекомендации.
        .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
    }

    private func loadRecommendations() {
        ai.recommendShifts(for: horizonDays) { recs in
            recommendations = recs
        }
    }

    private func plannerDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale()
        formatter.dateFormat = "EEEE, d MMM"
        return formatter.string(from: date).capitalized(with: AppLanguage.currentLocale())
    }
}
