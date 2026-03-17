// AIAdvisorView.swift
// AuraShift
// Экран AI-помощника — совместим с AIEngine.swift

import SwiftUI
import CoreData
import Charts
import Combine

// MARK: - AIAdvisorView

struct AIAdvisorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var ai: AIEngine
    @ObservedObject var settings: UserSettings
    @StateObject private var proManager = ProManager.shared

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Income.date, ascending: true)])
    private var incomes: FetchedResults<Income>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Expense.date, ascending: true)])
    private var expenses: FetchedResults<Expense>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \FinancialGoal.deadline, ascending: true)])
    private var goals: FetchedResults<FinancialGoal>

    @State private var selectedInsight: AIInsight?
    @State private var showInsightDetail = false
    @State private var showPlannerSheet = false
    @State private var showForecastQualitySheet = false

    // Вычисляем количество смен из heatmap
    private var totalShifts: Int {
        ai.weekdayHeatmap.reduce(0) { $0 + $1.shiftsCount }
    }
    
    // Static width for forecast metric cards (2 columns with 10pt spacing in a 16pt-padded container).
    private var forecastMetricTileWidth: CGFloat {
        let horizontalPadding: CGFloat = 32
        let interItemSpacing: CGFloat = 10
        let width = (UIScreen.main.bounds.width - horizontalPadding - interItemSpacing) / 2
        return max(width, 140)
    }

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            ZStack {
                VisionBackdropView()
                ScrollView {
                    VStack(spacing: 20) {
                        heroHeader
                        if ai.isAnalyzing {
                            loadingView
                        } else if !ai.hasEnoughData {
                            emptyStateView
                        } else {
                            forecastSection
                            if shouldShowForecastQualityShortcut {
                                forecastQualityShortcutRow
                            }
                            insightsSection
                            if proManager.canUse(.featureImportance) {
                                featureImportanceSection
                            }
                            if proManager.canUse(.schedulePlanner) {
                                plannerPreviewSection
                            }
                            weekdayHeatmapSection
                            trendSection
                            hourlyHeatmapSection
                            behavioralSection
                        }
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear { runAnalysis() }
        .onChange(of: incomes.count)  { _ in runAnalysis() }
        .onChange(of: expenses.count) { _ in runAnalysis() }
        .onChange(of: goals.count) { _ in runAnalysis() }
        .onReceive(sessionManager.$plannedShifts.dropFirst()) { _ in
            runAnalysis()
        }
        .onReceive(settings.$workTypes.dropFirst()) { _ in
            runAnalysis()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)) { notification in
            guard shouldRefreshAI(for: notification) else { return }
            runAnalysis()
        }
        .sheet(isPresented: $showInsightDetail) {
            if let insight = selectedInsight {
                InsightDetailSheet(insight: insight)
            }
        }
        .sheet(isPresented: $showPlannerSheet) {
            SchedulePlannerView(
                ai: ai,
                settings: settings
            )
        }
        .sheet(isPresented: $showForecastQualitySheet) {
            NavigationView {
                ZStack {
                    VisionBackdropView()
                    ScrollView {
                        VStack(spacing: 0) {
                            forecastQualitySection
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                }
                .navigationTitle(NSLocalizedString("Качество прогноза", comment: "AI section: forecast quality"))
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    trailing: Button(NSLocalizedString("Закрыть", comment: "common close action")) {
                        showForecastQualitySheet = false
                    }
                )
            }
        }
    }

    // MARK: - Hero

    // STYLE: `heroHeader` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [Color(hex:"#1C2E4A") ?? AppColors.accent,
                             Color(hex:"#2E4A72") ?? AppColors.accent],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(height: 130)
                .overlay(
                    ZStack {
                        Circle().fill(Color.white.opacity(0.04)).frame(width: 180).offset(x: 80, y: -30)
                        Circle().fill(Color.white.opacity(0.06)).frame(width: 100).offset(x: 130, y: 30)
                    }
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text(NSLocalizedString("AuraShift AI", comment: "AI hero title"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }

                if ai.hasEnoughData {
                    Text(String(format: NSLocalizedString("Проанализировано %d смен · Всё на устройстве", comment: "AI hero analyzed shifts"), totalShifts))
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.65))
                    // Тренд роста
                    let gr = ai.profile.growthRate
                    if abs(gr) >= 2 {
                        HStack(spacing: 5) {
                            Image(systemName: gr > 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 11, weight: .semibold))
                            Text(
                                gr > 0
                                ? String(format: NSLocalizedString("Рост %.1f%%/мес", comment: "AI hero growth rate"), gr)
                                : String(format: NSLocalizedString("Снижение %.1f%%/мес", comment: "AI hero decline rate"), abs(gr))
                            )
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                        .padding(.top, 2)
                    }
                } else {
                    Text(NSLocalizedString("Интеллектуальный финансовый помощник", comment: "AI hero subtitle"))
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.65))
                }
            }
            .padding(18)
        }
    }

    // MARK: - Loading / Empty

    // STYLE: `loadingView` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: AppColors.accent)).scaleEffect(1.3)
            Text(NSLocalizedString("Анализируем данные...", comment: "AI loading state")).font(.subheadline).foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    // STYLE: `emptyStateView` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(AppColors.accentGradient).frame(width: 72, height: 72)
                Image(systemName: "brain").font(.system(size: 30, weight: .semibold)).foregroundColor(.white)
            }
            Text(NSLocalizedString("Нужно больше данных", comment: "AI empty state title")).font(.headline).foregroundColor(AppColors.text)
            Text(NSLocalizedString("Добавьте минимум 5 смен, и AI начнёт строить прогнозы, определять тренды и давать персональные советы.", comment: "AI empty state description"))
                .font(.subheadline).foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center).padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }

    // MARK: - Прогноз

    // STYLE: `forecastSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var forecastSection: some View {
        let fc = ai.forecast
        return VStack(spacing: 0) {
            sectionHeader(title: NSLocalizedString("Прогноз на месяц", comment: "AI section: monthly forecast"), icon: "calendar.badge.clock")
            VStack(spacing: 10) {
                if proManager.canUse(.advancedML) {
                    forecastModeRow
                }
                if fc.hasCurrentProgressComparison || fc.hasForecastEndComparison {
                    monthComparisonCompactCard(fc)
                }
                HStack(spacing: 10) {
                    metricTile(
                        label: NSLocalizedString("Доход (прогноз)", comment: "AI metric: forecast income"),
                        value: fc.monthForecast,
                        sub: nil,
                        color: AppColors.positive,
                        fixedHeight: 120,
                        fixedWidth: forecastMetricTileWidth
                    )
                    metricTile(
                        label: NSLocalizedString("Следующая смена", comment: "AI metric: next shift"),
                        value: fc.shiftPrediction,
                        sub: String(format: NSLocalizedString("уверенность %d%%", comment: "AI metric confidence"), Int(fc.confidence * 100)),
                        color: AppColors.accent,
                        fixedHeight: 120,
                        fixedWidth: forecastMetricTileWidth
                    )
                }
                HStack(spacing: 10) {
                    metricTile(
                        label: NSLocalizedString("Вероятность высокого дохода", comment: "AI metric: high income probability"),
                        value: nil,
                        pct: fc.highIncomeProbability,
                        sub: nil,
                        color: AppColors.accent,
                        fixedHeight: 120,
                        fixedWidth: forecastMetricTileWidth
                    )
                    if !goals.filter({ $0.isActive }).isEmpty {
                        metricTile(
                            label: NSLocalizedString("Вероятность достижения цели в срок", comment: "AI metric: goal on time probability"),
                            value: nil,
                            pct: fc.goalProbability,
                            sub: nil,
                            color: AppColors.positive,
                            fixedHeight: 120,
                            fixedWidth: forecastMetricTileWidth
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    // STYLE: `monthComparisonCompactCard(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private func monthComparisonCompactCard(_ forecast: AIForecast) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                comparisonColumn(
                    title: NSLocalizedString("Факт сейчас", comment: "AI month comparison factual title"),
                    value: forecast.hasCurrentProgressComparison
                        ? signedPercentString(forecast.currentProgressChange)
                        : NSLocalizedString("Недостаточно данных", comment: "AI month comparison not enough data"),
                    subtitle: forecast.hasCurrentProgressComparison
                        ? String(
                            format: NSLocalizedString("Первые %d дн. vs прошлый месяц", comment: "AI month comparison factual subtitle"),
                            max(forecast.currentProgressDays, 1)
                        )
                        : nil,
                    color: forecast.hasCurrentProgressComparison
                        ? trendColor(for: forecast.currentProgressChange)
                        : AppColors.secondaryText
                )

                Divider()
                    .frame(maxHeight: 44)
                    .opacity(0.4)

                comparisonColumn(
                    title: NSLocalizedString("Прогноз к концу", comment: "AI month comparison forecast title"),
                    value: forecast.hasForecastEndComparison
                        ? signedPercentString(forecast.forecastEndMonthChange)
                        : NSLocalizedString("Недостаточно данных", comment: "AI month comparison not enough data"),
                    subtitle: forecast.hasForecastEndComparison
                        ? String(
                            format: NSLocalizedString("К прошлому полному месяцу · %d смен", comment: "AI month comparison forecast subtitle with window"),
                            max(forecast.forecastEndComparisonWindow, 1)
                        )
                        : (forecast.forecastEndComparisonMessage ?? NSLocalizedString("Точный прогноз появится после ввода минимум 3 смен", comment: "AI month comparison insufficient planned shifts")),
                    color: forecast.hasForecastEndComparison
                        ? trendColor(for: forecast.forecastEndMonthChange)
                        : AppColors.secondaryText
                )
            }
            if let explanation = forecast.forecastEndComparisonExplanation, forecast.hasForecastEndComparison {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.top, 1)
                    Text(explanation)
                        .font(.caption2)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .visionGlassCard(cornerRadius: 12, opacity: 0.82, showRing: true)
    }

    // STYLE: `comparisonColumn(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private func comparisonColumn(title: String, value: String, subtitle: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signedPercentString(_ value: Double) -> String {
        let intValue = Int(value.rounded())
        return String(format: intValue >= 0 ? "+%d%%" : "%d%%", intValue)
    }

    private func trendColor(for value: Double) -> Color {
        value >= 0 ? AppColors.positive : AppColors.negative
    }

    // STYLE: `forecastModeRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var forecastModeRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(forecastModeColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Режим прогноза: Авто", comment: "AI forecast mode title"))
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                Text(forecastModeText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(forecastModeColor)
                Text(NSLocalizedString("Переключается автоматически по объёму и качеству данных.", comment: "AI forecast mode subtitle"))
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .visionGlassCard(cornerRadius: 12, opacity: 0.82)
    }

    private var forecastModeText: String {
        switch ai.forecastModelMode {
        case .standard:
            return NSLocalizedString("Стабильный", comment: "AI forecast mode standard")
        case .blended:
            return NSLocalizedString("Сбалансированный", comment: "AI forecast mode blended")
        case .enhanced:
            return NSLocalizedString("Повышенная точность", comment: "AI forecast mode enhanced")
        }
    }

    private var forecastModeColor: Color {
        switch ai.forecastModelMode {
        case .standard:
            return AppColors.secondaryText
        case .blended:
            return AppColors.accent
        case .enhanced:
            return AppColors.positive
        }
    }

    private var shouldShowForecastQualityShortcut: Bool {
        ai.forecastQuality.hasShiftMetrics
    }

    // STYLE: `forecastQualityShortcutRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var forecastQualityShortcutRow: some View {
        let quality = ai.forecastQuality
        let subtitle = quality.hasShiftMetrics
            ? String(
                format: NSLocalizedString("Оценено на %d сменах", comment: "AI forecast quality sample count"),
                quality.sampleCount
            )
            : NSLocalizedString("Недостаточно данных для оценки качества.", comment: "AI forecast quality empty state")

        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)

            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString("Качество прогноза", comment: "AI section: forecast quality"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(NSLocalizedString("Подробнее", comment: "common details action")) {
                showForecastQualitySheet = true
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(AppColors.accent)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .visionGlassCard(cornerRadius: 12, opacity: 0.82)
    }

    // STYLE: `forecastQualitySection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var forecastQualitySection: some View {
        let quality = ai.forecastQuality
        let shiftSampleInfo = String(
            format: NSLocalizedString("Оценено на %d сменах", comment: "AI forecast quality sample count"),
            quality.sampleCount
        )
        return VStack(spacing: 0) {
            sectionHeader(title: NSLocalizedString("Качество прогноза", comment: "AI section: forecast quality"), icon: "checkmark.seal")
            if !quality.hasShiftMetrics {
                Text(NSLocalizedString("Недостаточно данных для оценки качества.", comment: "AI forecast quality empty state"))
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .visionGlassCard(cornerRadius: 12, opacity: 0.84, showRing: true)
            } else {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        metricTile(
                            label: NSLocalizedString("MAE по сменам", comment: "AI forecast quality metric: shift MAE"),
                            value: quality.mae,
                            sub: String(
                                format: NSLocalizedString("Среднее отклонение прогноза на смену. %@", comment: "AI forecast quality MAE explainer with sample count"),
                                shiftSampleInfo
                            ),
                            color: AppColors.accent
                        )
                        metricTile(
                            label: NSLocalizedString("RMSE по сменам", comment: "AI forecast quality metric: shift RMSE"),
                            value: quality.rmse,
                            sub: NSLocalizedString("Сильнее учитывает крупные ошибки прогноза.", comment: "AI forecast quality RMSE explainer"),
                            color: AppColors.positive
                        )
                    }
                    HStack(spacing: 10) {
                        metricTile(
                            label: NSLocalizedString("MAPE", comment: "AI forecast quality metric: MAPE"),
                            value: nil,
                            pct: quality.mape,
                            sub: NSLocalizedString("Средняя ошибка в процентах: чем меньше, тем лучше.", comment: "AI forecast quality MAPE explainer"),
                            color: .orange
                        )
                        if quality.hasMonthlyMetrics {
                            metricTile(
                                label: NSLocalizedString("Средняя ошибка месяца", comment: "AI forecast quality metric: monthly MAE"),
                                value: quality.monthlyMAE,
                                sub: String(
                                    format: NSLocalizedString("Отклонение прогноза по итогу месяца. Месяцев в проверке: %d", comment: "AI forecast quality monthly MAE explainer with sample count"),
                                    quality.monthlySampleCount
                                ),
                                color: AppColors.accent
                            )
                        } else {
                            metricTile(
                                label: NSLocalizedString("Средняя ошибка месяца", comment: "AI forecast quality metric: monthly MAE"),
                                value: nil,
                                sub: NSLocalizedString("Отклонение прогноза по итогу месяца. Пока мало данных.", comment: "AI forecast quality monthly low data with explainer"),
                                color: AppColors.secondaryText
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metricTile(
        label: String,
        value: Double?,
        pct: Double? = nil,
        sub: String?,
        color: Color,
        fixedHeight: CGFloat? = nil,
        fixedWidth: CGFloat? = nil
    ) -> some View {
        let tile = VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundColor(AppColors.secondaryText).lineLimit(2)
            if let v = value {
                Text("\(Int(v)) \(settings.defaultCurrency)")
                    .font(.system(size: 18, weight: .bold)).foregroundColor(color)
                    .minimumScaleFactor(0.7)
            }
            if let p = pct {
                Text("\(Int(p * 100))%")
                    .font(.system(size: 22, weight: .bold)).foregroundColor(color)
                ProgressView(value: p).tint(color)
                    .scaleEffect(x: 1, y: 1.4, anchor: .center)
            }
            if let s = sub {
                Text(s).font(.system(size: 10)).foregroundColor(color.opacity(0.8))
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .visionGlassCard(cornerRadius: 12, opacity: 0.82)

        if let fixedHeight, let fixedWidth {
            tile.frame(
                minWidth: fixedWidth,
                maxWidth: fixedWidth,
                minHeight: fixedHeight,
                maxHeight: fixedHeight,
                alignment: .topLeading
            )
        } else if let fixedHeight {
            tile.frame(maxWidth: .infinity, minHeight: fixedHeight, maxHeight: fixedHeight, alignment: .topLeading)
        } else if let fixedWidth {
            tile.frame(width: fixedWidth, alignment: .topLeading)
        } else {
            tile.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Инсайты

    // STYLE: `insightsSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var insightsSection: some View {
        VStack(spacing: 0) {
            sectionHeader(title: NSLocalizedString("Персональные советы", comment: "AI section: personal tips"), icon: "lightbulb.fill")
            LazyVStack(spacing: 10) {
                ForEach(ai.insights) { insight in
                    InsightCard(insight: insight)
                        .onTapGesture {
                            selectedInsight = insight
                            showInsightDetail = true
                        }
                }
            }
        }
    }

    // STYLE: `featureImportanceSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var featureImportanceSection: some View {
        VStack(spacing: 0) {
            sectionHeader(title: NSLocalizedString("Что влияет на доход", comment: "AI section: feature importance"), icon: "slider.horizontal.3")
            if ai.featureImportance.isEmpty {
                Text(NSLocalizedString("Пока мало данных для оценки факторов.", comment: "AI feature importance empty state"))
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .visionGlassCard(cornerRadius: 12, opacity: 0.82)
            } else {
                VStack(spacing: 10) {
                    ForEach(ai.featureImportance.prefix(5)) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppColors.text)
                                Spacer()
                                Text("\(Int(item.weight * 100))%")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(AppColors.accent)
                            }
                            ProgressView(value: item.weight)
                                .tint(AppColors.accent)
                                .scaleEffect(x: 1, y: 1.3, anchor: .center)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(12)
                        .visionGlassCard(cornerRadius: 12, opacity: 0.82)
                    }
                }
            }
        }
    }

    // STYLE: `plannerPreviewSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var plannerPreviewSection: some View {
        VStack(spacing: 0) {
            sectionHeader(title: NSLocalizedString("Новый план", comment: "AI section: planner preview"), icon: "calendar.badge.plus")
            if ai.shiftRecommendations.isEmpty {
                Text(NSLocalizedString("Нет свободных слотов в ближайшие дни или мало данных для прогноза.", comment: "AI planner empty state"))
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .visionGlassCard(cornerRadius: 12, opacity: 0.82)
            } else {
                VStack(spacing: 10) {
                    ForEach(ai.shiftRecommendations.prefix(4)) { rec in
                        HStack(alignment: .top, spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.accent.opacity(0.15))
                                    .frame(width: 34, height: 34)
                                Image(systemName: rec.workTypeIcon)
                                    .foregroundColor(AppColors.accent)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(rec.workTypeName) · \(plannerDateString(rec.date))")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppColors.text)
                                    .lineLimit(1)
                                Text("~\(settings.formattedCurrency(rec.expectedIncome))")
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.accent)
                                    .fontWeight(.medium)
                                if let reason = rec.reasons.first {
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                        }
                        .padding(12)
                        .visionGlassCard(cornerRadius: 12, opacity: 0.82)
                    }

                    Button(action: { showPlannerSheet = true }) {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                            Text(NSLocalizedString("Открыть планировщик", comment: "AI planner open button"))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .visionGlassCard(cornerRadius: 10, opacity: 0.82)
                    }
                }
            }
        }
    }

    // MARK: - Heatmap по дням недели

    // STYLE: `weekdayHeatmapSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var weekdayHeatmapSection: some View {
        VStack(spacing: 0) {
            sectionHeader(title: NSLocalizedString("Доход по дням недели", comment: "AI section: weekday income"), icon: "calendar")
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(ai.weekdayHeatmap) { point in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(point.avgIncome > 0
                                      ? AppColors.accent.opacity(0.18 + 0.78 * point.intensity)
                                      : Color.white.opacity(0.14))
                                .frame(height: 52)
                                .overlay(
                                    Group {
                                        if point.shiftsCount > 0 {
                                            Text(shortAmount(point.avgIncome))
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(point.intensity > 0.5 ? .white : AppColors.text)
                                                .minimumScaleFactor(0.5)
                                        } else {
                                            Image(systemName: "minus").font(.system(size: 9))
                                                .foregroundColor(AppColors.secondaryText.opacity(0.35))
                                        }
                                    }
                                )
                            Text(point.weekdayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(14)
                .visionGlassCard(cornerRadius: 14, opacity: 0.84, showRing: true)

                HStack {
                    Text(NSLocalizedString("Меньше", comment: "AI heatmap legend low value")).font(.caption2).foregroundColor(AppColors.secondaryText)
                    LinearGradient(colors: [AppColors.accent.opacity(0.18), AppColors.accent],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 6).cornerRadius(3)
                    Text(NSLocalizedString("Больше", comment: "AI heatmap legend high value")).font(.caption2).foregroundColor(AppColors.secondaryText)
                }.padding(.horizontal, 14)
            }
        }
    }

    // MARK: - Тренд

    // STYLE: `trendSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var trendSection: some View {
        let realPoints = ai.trendPoints.filter { !$0.isPredicted }
        let predPoints = ai.trendPoints.filter { $0.isPredicted }
        guard realPoints.count >= 2 else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 0) {
                sectionHeader(title: NSLocalizedString("Долгосрочный тренд + прогноз", comment: "AI section: long trend and forecast"), icon: "chart.line.uptrend.xyaxis")
                VStack(alignment: .leading, spacing: 12) {
                    if #available(iOS 16.0, *) {
                        Chart {
                            // Площадь под скользящей средней (сглаженная, без шипов)
                            ForEach(realPoints) { p in
                                AreaMark(
                                    x: .value(NSLocalizedString("Дата", comment: "AI trend chart axis: date"), p.date),
                                    yStart: .value(NSLocalizedString("Ноль", comment: "AI trend chart axis: zero"), 0.0),
                                    yEnd: .value(NSLocalizedString("СС", comment: "AI trend chart series: moving average"), max(0, p.movingAverage))
                                )
                                .foregroundStyle(LinearGradient(
                                    colors: [AppColors.positive.opacity(0.22), AppColors.positive.opacity(0.03)],
                                    startPoint: .top, endPoint: .bottom))
                                // Сглаженная линия MA
                                LineMark(
                                    x: .value(NSLocalizedString("Дата", comment: "AI trend chart axis: date"), p.date),
                                    y: .value(NSLocalizedString("СС", comment: "AI trend chart series: moving average"), max(0, p.movingAverage))
                                )
                                    .foregroundStyle(AppColors.positive)
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                // Тонкие вертикальные метки фактических значений
                                PointMark(
                                    x: .value(NSLocalizedString("Дата", comment: "AI trend chart axis: date"), p.date),
                                    y: .value(NSLocalizedString("Факт", comment: "AI trend chart series: actual"), max(0, p.value))
                                )
                                    .foregroundStyle(AppColors.positive.opacity(0.4))
                                    .symbolSize(12)
                            }
                            // Пунктирная линия прогноза
                            ForEach(predPoints) { p in
                                LineMark(
                                    x: .value(NSLocalizedString("Дата", comment: "AI trend chart axis: date"), p.date),
                                    y: .value(NSLocalizedString("Прогноз", comment: "AI trend chart series: forecast"), max(0, p.value))
                                )
                                    .foregroundStyle(AppColors.accent.opacity(0.6))
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: true))
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                                    .font(.caption2).foregroundStyle(AppColors.secondaryText)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { v in
                                AxisValueLabel {
                                    if let d = v.as(Double.self) {
                                        Text(shortAmount(d)).font(.caption2).foregroundColor(AppColors.secondaryText)
                                    }
                                }
                            }
                        }
                        .frame(height: 190).padding(.horizontal, 4)
                    }
                    HStack(spacing: 16) {
                        legendLine(color: AppColors.positive, label: NSLocalizedString("Скольз. средняя", comment: "AI chart legend: moving average"), dashed: false)
                        legendLine(color: AppColors.positive.opacity(0.4), label: NSLocalizedString("Факт. доход", comment: "AI chart legend: factual income"), dashed: false)
                        legendLine(color: AppColors.accent.opacity(0.6), label: NSLocalizedString("Прогноз", comment: "AI chart legend: forecast"), dashed: true)
                    }.padding(.horizontal, 4)
                }
                .padding(14)
                .visionGlassCard(cornerRadius: 14, opacity: 0.84, showRing: true)
            }
        )
    }

    // MARK: - Heatmap по часам

    // STYLE: `hourlyHeatmapSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var hourlyHeatmapSection: some View {
        let points = ai.hourlyHeatmap.sorted { $0.hour < $1.hour }
        guard !points.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 0) {
                sectionHeader(title: NSLocalizedString("Доход по часам начала смены", comment: "AI section: hourly income"), icon: "clock.fill")
                VStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(points) { p in
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(AppColors.accent.opacity(0.15 + 0.8 * p.intensity))
                                        .frame(width: 38, height: 44)
                                    Text("\(p.hour)").font(.system(size: 9))
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    .visionGlassCard(cornerRadius: 14, opacity: 0.84, showRing: true)

                    if let best = points.max(by: { $0.avgIncome < $1.avgIncome }) {
                        HStack(spacing: 7) {
                            Image(systemName: "clock.badge.checkmark.fill").font(.caption).foregroundColor(AppColors.accent)
                            Text(String(format: NSLocalizedString("Лучшее время: %d:00 · средний доход %d %@", comment: "AI hourly best time"), best.hour, Int(best.avgIncome), settings.defaultCurrency))
                                .font(.caption).foregroundColor(AppColors.secondaryText)
                        }.padding(.horizontal, 4)
                    }
                }
            }
        )
    }

    // MARK: - Поведенческий профиль

    // STYLE: `behavioralSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var behavioralSection: some View {
        let bp = ai.profile
        return VStack(spacing: 0) {
            sectionHeader(title: NSLocalizedString("Поведенческий анализ", comment: "AI section: behavioral analysis"), icon: "brain.head.profile")
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    profileTile(icon: "clock", label: NSLocalizedString("Оптимальная длительность", comment: "AI profile: optimal duration"),
                                value: "\(String(format:"%.0f",bp.optimalShiftDuration)) \(NSLocalizedString("ч", comment: "hours short unit"))",
                                color: AppColors.accent)
                    profileTile(icon: "checkmark.seal.fill", label: NSLocalizedString("Стабильность", comment: "AI profile: consistency"),
                                value: "\(Int(bp.consistencyScore * 100))%",
                                color: bp.consistencyScore > 0.6 ? AppColors.positive : .orange)
                }
                if !bp.bestWeekdays.isEmpty {
                    let names = localizedWeekdayNames()
                    let bestNames = bp.bestWeekdays.compactMap { day in
                        guard day >= 1 && day <= 7 else { return nil }
                        return names[day - 1]
                    }.joined(separator: ", ")
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill").font(.caption).foregroundColor(.yellow)
                        Text(String(format: NSLocalizedString("Лучшие дни для смен: %@", comment: "AI profile: best weekdays"), bestNames))
                            .font(.caption).foregroundColor(AppColors.secondaryText)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .visionGlassCard(cornerRadius: 10, opacity: 0.84, showRing: true)
                }
                if bp.tipsContribution > 0.02 {
                    HStack(spacing: 8) {
                        Image(systemName: "banknote").font(.caption).foregroundColor(.orange)
                        Text(String(format: NSLocalizedString("Чаевые составляют %d%% дохода", comment: "AI profile: tips contribution"), Int(bp.tipsContribution * 100)))
                            .font(.caption).foregroundColor(AppColors.secondaryText)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .visionGlassCard(cornerRadius: 10, opacity: 0.84, showRing: true)
                }
            }
        }
    }

    @ViewBuilder
    // STYLE: `profileTile(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private func profileTile(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption).foregroundColor(color)
                Text(label).font(.caption).foregroundColor(AppColors.secondaryText).lineLimit(2)
            }
            Text(value).font(.system(size: 22, weight: .bold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .visionGlassCard(cornerRadius: 12, opacity: 0.84, showRing: true)
    }

    // MARK: - Helpers

    @ViewBuilder
    // STYLE: `sectionHeader(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(AppColors.accent)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(AppColors.text)
            Spacer()
        }
        .padding(.bottom, 10)
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    // STYLE: `legendLine(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private func legendLine(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            if dashed {
                RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 14, height: 2)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(label).font(.caption2).foregroundColor(AppColors.secondaryText)
        }
    }

    private func localizedWeekdayNames() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale()
        var symbols = formatter.standaloneWeekdaySymbols ?? formatter.weekdaySymbols ?? []
        if symbols.count == 7 {
            let sunday = symbols.removeFirst()
            symbols.append(sunday)
        }
        return symbols.map { $0.capitalized(with: AppLanguage.currentLocale()) }
    }

    private func runAnalysis() {
        ai.analyze(
            incomes: Array(incomes),
            expenses: Array(expenses),
            settings: settings,
            goals: Array(goals),
            plannedShifts: sessionManager.plannedShifts
        )
    }

    private func plannerDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func shortAmount(_ v: Double) -> String {
        if v >= 1_000_000 { return "\(Int(v/1_000_000))\(NSLocalizedString("М", comment: "short amount suffix million"))" }
        if v >= 1_000 { return "\(Int(v/1_000))\(NSLocalizedString("к", comment: "short amount suffix thousand"))" }
        return "\(Int(v))"
    }

    private func shouldRefreshAI(for notification: Notification) -> Bool {
        let keys: [String] = [
            NSInsertedObjectsKey,
            NSUpdatedObjectsKey,
            NSDeletedObjectsKey,
            NSRefreshedObjectsKey
        ]
        for key in keys {
            guard let objects = notification.userInfo?[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: { $0 is Income || $0 is Expense || $0 is FinancialGoal }) {
                return true
            }
        }
        return false
    }
}

// MARK: - InsightCard

struct InsightCard: View {
    let insight: AIInsight
    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(insight.accentColor.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: insight.icon).font(.system(size: 16, weight: .semibold))
                    .foregroundColor(insight.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title).font(.system(size: 14, weight: .semibold)).foregroundColor(AppColors.text)
                Text(insight.body).font(.system(size: 12)).foregroundColor(AppColors.secondaryText)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if insight.confidence > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill").font(.system(size: 8))
                        Text(String(format: NSLocalizedString("Уверенность: %d%%", comment: "AI insight confidence"), Int(insight.confidence * 100))).font(.system(size: 9))
                    }
                    .foregroundColor(AppColors.secondaryText.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12))
                .foregroundColor(AppColors.secondaryText.opacity(0.35))
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [insight.accentColor.opacity(0.08), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .visionGlassCard(cornerRadius: 14, opacity: 0.84, showRing: true)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(insight.accentColor.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - InsightDetailSheet

struct InsightDetailSheet: View {
    let insight: AIInsight
    @Environment(\.presentationMode) var presentationMode

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            ZStack {
                VisionBackdropView()
                ScrollView {
                    VStack(spacing: 24) {
                        ZStack {
                            Circle().fill(insight.accentColor.opacity(0.15)).frame(width: 88, height: 88)
                            Image(systemName: insight.icon).font(.system(size: 38, weight: .semibold))
                                .foregroundColor(insight.accentColor)
                        }.padding(.top, 24)

                        VStack(spacing: 12) {
                            Text(insight.title).font(.system(size: 22, weight: .bold))
                                .foregroundColor(AppColors.text).multilineTextAlignment(.center)
                            Text(insight.body).font(.system(size: 16))
                                .foregroundColor(AppColors.secondaryText)
                                .multilineTextAlignment(.center).padding(.horizontal, 20)
                        }

                        // Уверенность
                        if insight.confidence > 0 {
                            VStack(spacing: 8) {
                                HStack {
                                    Text(NSLocalizedString("Уверенность AI", comment: "AI insight confidence label")).font(.caption).foregroundColor(AppColors.secondaryText)
                                    Spacer()
                                    Text("\(Int(insight.confidence * 100))%").font(.caption.weight(.semibold))
                                        .foregroundColor(AppColors.accent)
                                }
                                ProgressView(value: insight.confidence).tint(AppColors.accent)
                            }
                            .padding(16)
                            .visionGlassCard(cornerRadius: 14, opacity: 0.82)
                            .padding(.horizontal, 20)
                        }

                        typeBadge
                    }
                }
            }
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Закрыть", comment: "common close action")) { presentationMode.wrappedValue.dismiss() }
                        .foregroundColor(AppColors.accent)
                }
            }
        }
    }

    // STYLE: `typeBadge` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var typeBadge: some View {
        let (lbl, ico): (String, String) = {
            switch insight.type {
            case .recommendation: return (NSLocalizedString("Рекомендация", comment: "AI insight type badge"),"lightbulb.fill")
            case .anomaly:        return (NSLocalizedString("Аномалия", comment: "AI insight type badge"),"exclamationmark.triangle.fill")
            case .trend:          return (NSLocalizedString("Тренд", comment: "AI insight type badge"),"chart.line.uptrend.xyaxis")
            case .achievement:    return (NSLocalizedString("Достижение", comment: "AI insight type badge"),"checkmark.seal.fill")
            case .warning:        return (NSLocalizedString("Предупреждение", comment: "AI insight type badge"),"exclamationmark.circle")
            case .forecast:       return (NSLocalizedString("Прогноз", comment: "AI insight type badge"),"calendar.badge.clock")
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: ico).font(.caption)
            Text(lbl).font(.caption.weight(.medium))
        }
        .foregroundColor(insight.accentColor)
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(insight.accentColor.opacity(0.12)).clipShape(Capsule())
    }
}

// MARK: - AICompactBlock (для DailyView)

struct AICompactBlock: View {
    @ObservedObject var ai: AIEngine
    let settings: UserSettings
    let onTapInsight: (AIInsight) -> Void
    let onTapMore: () -> Void

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        VStack(spacing: 0) {
            // Шапка
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    Text(NSLocalizedString("AI Помощник", comment: "AI compact block title")).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                }
                Spacer()
                Button(action: onTapMore) {
                    HStack(spacing: 3) {
                        Text(NSLocalizedString("Подробнее", comment: "common details action")).font(.caption).foregroundColor(.white.opacity(0.8))
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(LinearGradient(
                colors: [Color(hex:"#1C2E4A") ?? AppColors.accent, Color(hex:"#2E4A72") ?? AppColors.accent],
                startPoint: .leading, endPoint: .trailing
            ))
            .cornerRadius(14, corners: [.topLeft, .topRight])

            // Мини-метрики прогноза
            if ai.hasEnoughData {
                HStack(spacing: 0) {
                    miniMetric(label: NSLocalizedString("Прогноз месяц", comment: "AI compact metric label"),
                               value: ai.forecast.monthForecast > 0 ? "\(Int(ai.forecast.monthForecast))" : "—",
                               icon: "chart.bar.fill", color: AppColors.positive)
                    Divider().frame(height: 32)
                    miniMetric(label: NSLocalizedString("Следующая смена", comment: "AI compact metric label"),
                               value: ai.forecast.shiftPrediction > 0 ? "~\(Int(ai.forecast.shiftPrediction))" : "—",
                               icon: "sparkles", color: AppColors.accent)
                    Divider().frame(height: 32)
                    let gr = ai.profile.growthRate
                    miniMetric(label: abs(gr) < 1 ? NSLocalizedString("Стабильно", comment: "AI compact trend stable") : (gr > 0 ? NSLocalizedString("Рост", comment: "AI compact trend up") : NSLocalizedString("Снижение", comment: "AI compact trend down")),
                               value: abs(gr) >= 1 ? "\(String(format:"%.1f",abs(gr)))%" : "",
                               icon: gr > 0 ? "arrow.up.right" : (gr < -1 ? "arrow.down.right" : "minus"),
                               color: gr > 0 ? AppColors.positive : (gr < -1 ? AppColors.negative : AppColors.accent))
                }
                .padding(.vertical, 8)
                .visionGlassCard(cornerRadius: 0, opacity: 0.76, showRing: false)
            }

            // Топ инсайт
            if let top = ai.insights.first {
                Button(action: { onTapInsight(top) }) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(top.accentColor.opacity(0.15)).frame(width: 32, height: 32)
                            Image(systemName: top.icon).font(.system(size: 13)).foregroundColor(top.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(top.title).font(.system(size: 12, weight: .semibold)).foregroundColor(AppColors.text)
                            Text(top.body).font(.system(size: 11)).foregroundColor(AppColors.secondaryText).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10))
                            .foregroundColor(AppColors.secondaryText.opacity(0.4))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .visionGlassCard(cornerRadius: 0, opacity: 0.78, showRing: false)
                .buttonStyle(PlainButtonStyle())
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").font(.caption).foregroundColor(AppColors.secondaryText)
                    Text(ai.isAnalyzing ? NSLocalizedString("Анализируем...", comment: "AI compact loading") : NSLocalizedString("Добавьте 5+ смен для AI советов", comment: "AI compact no data"))
                        .font(.caption).foregroundColor(AppColors.secondaryText)
                }
                .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                .visionGlassCard(cornerRadius: 0, opacity: 0.76, showRing: false)
            }
        }
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    @ViewBuilder
    // STYLE: `miniMetric(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private func miniMetric(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
            if !value.isEmpty {
                Text(value).font(.system(size: 12, weight: .bold)).foregroundColor(color).minimumScaleFactor(0.7)
            }
            Text(label).font(.system(size: 9)).foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Corner radius helper

extension View {
    // STYLE: `cornerRadius(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat; var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
