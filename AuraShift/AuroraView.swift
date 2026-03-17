import SwiftUI
import CoreData
import Combine
import UIKit

struct AuroraView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var ai: AIEngine
    @ObservedObject var settings: UserSettings

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Income.date, ascending: true)])
    private var incomes: FetchedResults<Income>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Expense.date, ascending: true)])
    private var expenses: FetchedResults<Expense>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \FinancialGoal.deadline, ascending: true)])
    private var goals: FetchedResults<FinancialGoal>

    @State private var expandedCardIDs: Set<String> = []
    @State private var selectedInsight: AIInsight?
    @State private var showInsightDetail = false
    @State private var showFeedbackComposer = false
    @State private var showGreetingBubble = false
    @State private var didStartGreetingAnimations = false
    @State private var showAllMetricCards = false
    @State private var showAllInsightCards = false
    @State private var showAllPlannerCards = false
    @StateObject private var proManager = ProManager.shared
    @StateObject private var feedbackStore = AuroraFeedbackStore()
    @StateObject private var engagementTracker = AuroraEngagementTracker()

    private let feedbackAnalyzer = AuroraFeedbackAnalyzer()

    private let metricPreviewLimit = 6
    private let insightPreviewLimit = 3
    private let plannerPreviewLimit = 2

    private var cardColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
        return [GridItem(.flexible(), spacing: 12)]
    }

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            ZStack {
                VisionBackdropView()
                ScrollView {
                    VStack(spacing: 16) {
                        heroBanner
                        auroraConversationSection
                        feedbackRecommendationSection
                        cardsSection
                        recommendationsSection
                        plannerSection
                        Spacer(minLength: 16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 22)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            engagementTracker.registerOpen()
            runAnalysis()
            startGreetingAnimations()
        }
        .onChange(of: incomes.count) { _ in runAnalysis() }
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
        .onReceive(NotificationCenter.default.publisher(for: .weatherManagerDidUpdateForecast)) { _ in
            runAnalysis()
        }
        .sheet(isPresented: $showInsightDetail) {
            if let selectedInsight {
                InsightDetailSheet(insight: selectedInsight)
            }
        }
        .sheet(isPresented: $showFeedbackComposer) {
            AuroraFeedbackComposer(
                dayMessage: greetingMessage,
                onSend: { text, manualMood in
                    handleFeedbackSubmit(text: text, manualMood: manualMood)
                }
            )
        }
    }

    // MARK: - Header

    // STYLE: `heroBanner` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var heroBanner: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                    Text(NSLocalizedString("Аврора", comment: "Aurora title"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppColors.text)
                }

                Text(NSLocalizedString("Встроенный AI AuraShift: прогнозы, показатели и персональные советы в одном месте.", comment: "Aurora subtitle"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    heroChip(text: String(format: NSLocalizedString("Смен: %d", comment: "Aurora hero chip: analyzed shifts"), totalShiftCount))
                    heroChip(text: String(format: NSLocalizedString("Уверенность: %d%%", comment: "Aurora hero chip: confidence"), Int(ai.forecast.confidence * 100)))
                    heroChip(text: streakBadgeText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(auroraAssistantAssetName)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.26), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.20), radius: 6, x: 0, y: 3)
                .accessibilityHidden(true)
                .padding(.bottom, 2)
        }
        .padding(18)
        .frame(minHeight: 188)
        .visionGlassCard(cornerRadius: 24, opacity: 0.86, showRing: true)
    }

    // STYLE: `heroChip(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private func heroChip(text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AppColors.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            .visionGlassCard(cornerRadius: 10, opacity: 0.80, showRing: true)
    }

    private var streakStage: AuroraStreakStage {
        engagementTracker.stage
    }

    private var streakBadgeText: String {
        let days = max(engagementTracker.streakDays, 0)
        return String(
            format: NSLocalizedString("Серия: %d дн.", comment: "Aurora streak chip text"),
            days
        )
    }

    private func resolveAssetName(candidates: [String], fallback: String = "AuroraMaster") -> String {
        for name in candidates where UIImage(named: name) != nil {
            return name
        }
        return fallback
    }

    private var auroraAssistantAssetName: String {
        if ai.isAnalyzing {
            return resolveAssetName(candidates: ["AuroraAnalyzing"] + streakStage.assetCandidates)
        }
        let baseByStreak = resolveAssetName(candidates: streakStage.assetCandidates)
        guard let latest = feedbackStore.latestEntry else { return baseByStreak }

        switch latest.detectedMood {
        case .negative:
            return resolveAssetName(candidates: ["AuroraSupportive", baseByStreak], fallback: baseByStreak)
        case .positive where streakStage.rawValue >= AuroraStreakStage.fourToSeven.rawValue:
            return resolveAssetName(candidates: ["AuroraCelebration", baseByStreak], fallback: baseByStreak)
        case .positive, .neutral:
            return baseByStreak
        }
    }

    // MARK: - Conversation

    // STYLE: `auroraConversationSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var auroraConversationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    showFeedbackComposer = true
                } label: {
                    HStack(spacing: 8) {
                        Image(auroraAssistantAssetName)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
                            )
                        Text(NSLocalizedString("Аврора", comment: "Aurora conversation button title"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.text)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .visionGlassCard(cornerRadius: 12, opacity: 0.86, showRing: true)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    showFeedbackComposer = true
                } label: {
                    Text(NSLocalizedString("Ответить", comment: "Aurora conversation answer action"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .visionGlassCard(cornerRadius: 12, opacity: 0.84, showRing: true)
                }
                .buttonStyle(.plain)
            }

            if showGreetingBubble {
                HStack(alignment: .top, spacing: 10) {
                    Image(auroraAssistantAssetName)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.30), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.14), radius: 4, x: 0, y: 2)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(greetingMessage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppColors.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(NSLocalizedString("Нажмите и поделитесь настроением, впечатлениями и важными моментами дня.", comment: "Aurora greeting helper text"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .visionGlassCard(cornerRadius: 14, opacity: 0.86, showRing: true)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // STYLE: `feedbackRecommendationSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var feedbackRecommendationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("Персональные рекомендации после заметки", comment: "Aurora feedback recommendations section title"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppColors.text)
                Spacer()
                if let latest = feedbackStore.latestEntry {
                    moodBadge(latest.detectedMood)
                }
            }

            if let latest = feedbackStore.latestEntry {
                if !latest.keyMoments.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("Ключевые моменты дня", comment: "Aurora key moments section title"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)

                        ForEach(Array(latest.keyMoments.enumerated()), id: \.offset) { _, moment in
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(AppColors.accent)
                                    .padding(.top, 3)
                                Text(moment)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(AppColors.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .visionGlassCard(cornerRadius: 14, opacity: 0.84)
                }

                VStack(spacing: 10) {
                    ForEach(latest.recommendations) { recommendation in
                        AuroraFeedbackRecommendationCard(
                            recommendation: recommendation,
                            isExpanded: expandedCardIDs.contains(feedbackCardID(for: recommendation.id))
                        ) {
                            toggleExpandedFeedbackCard(id: recommendation.id)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Image("EmptyStateNoAIData")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 88)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        )
                    Text(NSLocalizedString("Отправьте заметку Авроре, и здесь сразу появятся персональные рекомендации.", comment: "Aurora feedback recommendations empty state"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .visionGlassCard(cornerRadius: 14, opacity: 0.84)
            }
        }
    }

    // STYLE: `moodBadge(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private func moodBadge(_ mood: AuroraMood) -> some View {
        HStack(spacing: 5) {
            Image(systemName: mood.icon)
                .font(.system(size: 12, weight: .semibold))
            Text(mood.title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(mood.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .visionGlassCard(cornerRadius: 999, opacity: 0.82, showRing: true)
    }

    // MARK: - Cards

    // STYLE: `cardsSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var cardsSection: some View {
        let visibleCards = showAllMetricCards
            ? auroraCards
            : Array(auroraCards.prefix(metricPreviewLimit))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("Показатели Авроры", comment: "Aurora cards section title"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppColors.text)
                Spacer()
                if auroraCards.count > metricPreviewLimit {
                    Button(showAllMetricCards
                           ? NSLocalizedString("Свернуть", comment: "Aurora section action collapse")
                           : NSLocalizedString("Показать все", comment: "Aurora section action show all")) {
                        performUIUpdate(.easeInOut(duration: 0.2)) {
                            showAllMetricCards.toggle()
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: cardColumns, spacing: 12) {
                ForEach(visibleCards) { card in
                    AuroraMetricCard(
                        card: card,
                        isExpanded: expandedCardIDs.contains(card.id)
                    ) {
                        performUIUpdate(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if expandedCardIDs.contains(card.id) {
                                expandedCardIDs.remove(card.id)
                            } else {
                                expandedCardIDs.insert(card.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // STYLE: `recommendationsSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var recommendationsSection: some View {
        let visibleInsights = showAllInsightCards
            ? ai.insights
            : Array(ai.insights.prefix(insightPreviewLimit))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("Советы Авроры", comment: "Aurora recommendations section title"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppColors.text)
                Spacer()
                if ai.isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                if ai.insights.count > insightPreviewLimit {
                    Button(showAllInsightCards
                           ? NSLocalizedString("Свернуть", comment: "Aurora section action collapse")
                           : NSLocalizedString("Показать все", comment: "Aurora section action show all")) {
                        performUIUpdate(.easeInOut(duration: 0.2)) {
                            showAllInsightCards.toggle()
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                }
            }

            if ai.insights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image("EmptyStateNoAIData")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 102)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        )
                    Text(NSLocalizedString("Советы появятся после анализа первых смен.", comment: "Aurora empty recommendations"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                    Text(NSLocalizedString("Добавьте минимум 5 смен для полноценного AI-анализа.", comment: "Aurora empty recommendations details"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(AppColors.secondaryText.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .visionGlassCard(cornerRadius: 14, opacity: 0.84, showRing: true)
            } else {
                VStack(spacing: 10) {
                    ForEach(visibleInsights) { insight in
                        Button {
                            selectedInsight = insight
                            showInsightDetail = true
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: insight.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(insight.accentColor)
                                    .frame(width: 34, height: 34)
                                    .visionGlassCard(cornerRadius: 10, opacity: 0.78)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(insight.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(AppColors.text)
                                        .lineLimit(2)
                                    Text(insight.body)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(3)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppColors.secondaryText.opacity(0.55))
                                    .padding(.top, 4)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .visionGlassCard(cornerRadius: 14, opacity: 0.84, showRing: true)
                    }
                }
            }
        }
    }

    // STYLE: `plannerSection` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var plannerSection: some View {
        let visibleRecommendations = showAllPlannerCards
            ? ai.shiftRecommendations
            : Array(ai.shiftRecommendations.prefix(plannerPreviewLimit))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("Оптимальные смены", comment: "Aurora planner section title"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppColors.text)
                Spacer()
                if ai.shiftRecommendations.count > plannerPreviewLimit {
                    Button(showAllPlannerCards
                           ? NSLocalizedString("Свернуть", comment: "Aurora section action collapse")
                           : NSLocalizedString("Показать все", comment: "Aurora section action show all")) {
                        performUIUpdate(.easeInOut(duration: 0.2)) {
                            showAllPlannerCards.toggle()
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                }
            }

            if ai.shiftRecommendations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image("EmptyStateNoShifts")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 94)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        )
                    Text(NSLocalizedString("Пока нет готовых рекомендаций по сменам. Добавьте данные или проверьте активные типы работ.", comment: "Aurora planner empty state"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .visionGlassCard(cornerRadius: 14, opacity: 0.84)
            } else {
                VStack(spacing: 10) {
                    ForEach(visibleRecommendations) { recommendation in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: recommendation.workTypeIcon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppColors.accent)
                                Text(recommendation.workTypeName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AppColors.text)
                                Spacer()
                                Text(settings.formattedCurrency(recommendation.expectedIncome))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(AppColors.positive)
                            }

                            HStack(spacing: 10) {
                                Text(plannerDateString(recommendation.date))
                                Text(String(format: NSLocalizedString("уверенность %d%%", comment: "Aurora planner confidence"), Int(recommendation.confidence * 100)))
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)

                            if let reason = recommendation.reasons.first {
                                Text(reason)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .visionGlassCard(cornerRadius: 14, opacity: 0.82)
                    }
                }
            }
        }
    }

    private var auroraCards: [AuroraMetricCardData] {
        let forecast = ai.forecast
        let tipsShare = ai.profile.tipsContribution

        let monthlyIncomeValue = currentMonthIncome > 0
            ? settings.formattedCurrency(currentMonthIncome)
            : NSLocalizedString("Недостаточно данных", comment: "Aurora card: not enough data")

        let monthForecastValue = forecast.monthForecast > 0
            ? settings.formattedCurrency(forecast.monthForecast)
            : NSLocalizedString("Недостаточно данных", comment: "Aurora card: not enough data")

        let nextShiftValue = forecast.shiftPrediction > 0
            ? settings.formattedCurrency(forecast.shiftPrediction)
            : NSLocalizedString("Недостаточно данных", comment: "Aurora card: not enough data")

        let tipsValue: String = {
            if tipsShare <= 0.0001 {
                return NSLocalizedString("Нет данных", comment: "Aurora card: no tips data")
            }
            return "\(Int(tipsShare * 100))%"
        }()

        let bestDayText = bestWeekday?.weekdayName ?? NSLocalizedString("Недостаточно данных", comment: "Aurora card: not enough data")
        let bestHourText = bestHour.map { "\($0.hour):00" } ?? NSLocalizedString("Недостаточно данных", comment: "Aurora card: not enough data")

        let goalActive = goals.contains(where: { $0.isActive })
        let goalProbability = goalActive
            ? "\(Int(forecast.goalProbability * 100))%"
            : NSLocalizedString("Цель не активна", comment: "Aurora card: goal inactive")

        let trendValue = trendSummaryText
        let seasonalValue = seasonalSummaryValue

        var cards: [AuroraMetricCardData] = [
            AuroraMetricCardData(
                id: "income",
                icon: "banknote.fill",
                title: NSLocalizedString("Доход за месяц", comment: "Aurora card title: monthly income"),
                value: monthlyIncomeValue,
                tone: NSLocalizedString("Аврора следит за вашим темпом в реальном времени.", comment: "Aurora card tone: monthly income"),
                tint: Color(red: 0.12, green: 0.70, blue: 0.47),
                details: [
                    String(format: NSLocalizedString("Суммарный доход: %@", comment: "Aurora card details: total income"), settings.formattedCurrency(totalIncome)),
                    String(format: NSLocalizedString("Средняя смена: %@", comment: "Aurora card details: average shift"), averageShiftIncome > 0 ? settings.formattedCurrency(averageShiftIncome) : NSLocalizedString("Недостаточно данных", comment: "Aurora card: not enough data"))
                ]
            ),
            AuroraMetricCardData(
                id: "forecast",
                icon: "calendar.badge.clock",
                title: NSLocalizedString("Прогноз на месяц", comment: "Aurora card title: month forecast"),
                value: monthForecastValue,
                tone: NSLocalizedString("Прогноз обновляется после каждой новой смены.", comment: "Aurora card tone: month forecast"),
                tint: Color(red: 0.24, green: 0.50, blue: 0.98),
                details: [
                    String(format: NSLocalizedString("Уверенность: %d%%", comment: "Aurora card details: forecast confidence"), Int(forecast.confidence * 100)),
                    String(format: NSLocalizedString("Изменение к прошлому месяцу: %.0f%%", comment: "Aurora card details: month over month"), forecast.monthOverMonthChange)
                ]
            ),
            AuroraMetricCardData(
                id: "next_shift",
                icon: "clock.badge.checkmark",
                title: NSLocalizedString("Следующая смена", comment: "Aurora card title: next shift"),
                value: nextShiftValue,
                tone: NSLocalizedString("Аврора оценивает ожидаемый доход и вероятность сильной смены.", comment: "Aurora card tone: next shift"),
                tint: Color(red: 0.32, green: 0.63, blue: 0.96),
                details: [
                    String(format: NSLocalizedString("Вероятность высокого дохода: %d%%", comment: "Aurora card details: high income probability"), Int(forecast.highIncomeProbability * 100)),
                    String(format: NSLocalizedString("Уверенность модели: %d%%", comment: "Aurora card details: model confidence"), Int(forecast.confidence * 100))
                ]
            ),
            AuroraMetricCardData(
                id: "tips",
                icon: "banknote",
                title: NSLocalizedString("Чаевые", comment: "Aurora card title: tips"),
                value: tipsValue,
                tone: NSLocalizedString("Чаевые сильно влияют на итоговый доход в ваших сменах.", comment: "Aurora card tone: tips"),
                tint: Color(red: 0.86, green: 0.45, blue: 0.56),
                details: [
                    String(format: NSLocalizedString("Всего чаевых: %@", comment: "Aurora card details: total tips"), totalTips > 0 ? settings.formattedCurrency(totalTips) : NSLocalizedString("Недостаточно данных", comment: "Aurora card: not enough data")),
                    String(format: NSLocalizedString("Влияние на доход: %d%%", comment: "Aurora card details: tips influence"), Int(tipsShare * 100))
                ]
            ),
            AuroraMetricCardData(
                id: "best_time",
                icon: "calendar",
                title: NSLocalizedString("Лучшие дни и часы", comment: "Aurora card title: best days and hours"),
                value: "\(bestDayText) · \(bestHourText)",
                tone: NSLocalizedString("Работайте в сильные слоты, чтобы ускорить рост дохода.", comment: "Aurora card tone: best time"),
                tint: Color(red: 0.30, green: 0.49, blue: 0.94),
                details: [
                    String(format: NSLocalizedString("Лучший день: %@", comment: "Aurora card details: best day"), bestDayText),
                    String(format: NSLocalizedString("Лучший час старта: %@", comment: "Aurora card details: best hour"), bestHourText)
                ]
            ),
            AuroraMetricCardData(
                id: "trend",
                icon: "chart.line.uptrend.xyaxis",
                title: NSLocalizedString("Исторический тренд", comment: "Aurora card title: trend"),
                value: trendValue,
                tone: NSLocalizedString("Аврора сопоставляет историю и прогноз, чтобы показать направление.", comment: "Aurora card tone: trend"),
                tint: Color(red: 0.55, green: 0.41, blue: 0.96),
                details: [
                    String(format: NSLocalizedString("Точек в тренде: %d", comment: "Aurora card details: trend point count"), ai.trendPoints.filter { !$0.isPredicted }.count),
                    String(format: NSLocalizedString("Прогнозных точек: %d", comment: "Aurora card details: predicted point count"), ai.trendPoints.filter { $0.isPredicted }.count)
                ]
            ),
            AuroraMetricCardData(
                id: "seasonality",
                icon: "sparkles.square.filled.on.square",
                title: NSLocalizedString("Праздники и сезонность", comment: "Aurora card title: seasonality"),
                value: seasonalValue,
                tone: NSLocalizedString("Внешние факторы учитываются в рекомендациях и прогнозах.", comment: "Aurora card tone: seasonality"),
                tint: Color(red: 0.70, green: 0.38, blue: 0.92),
                details: seasonalDetails
            ),
            AuroraMetricCardData(
                id: "goal",
                icon: "target",
                title: NSLocalizedString("Цель в срок", comment: "Aurora card title: goal probability"),
                value: goalProbability,
                tone: NSLocalizedString("Аврора оценивает шанс достижения цели и подсказывает, как ускориться.", comment: "Aurora card tone: goal"),
                tint: Color(red: 0.19, green: 0.71, blue: 0.49),
                details: goalDetails(goalActive: goalActive, forecast: forecast)
            ),
            AuroraMetricCardData(
                id: "streak",
                icon: "flame.fill",
                title: NSLocalizedString("Серия посещений", comment: "Aurora card title: streak"),
                value: String(format: NSLocalizedString("%d дней · %@", comment: "Aurora streak card value"), max(engagementTracker.streakDays, 0), streakStage.title),
                tone: NSLocalizedString("Эмоции и стиль Авроры адаптируются к вашей серии и активности.", comment: "Aurora card tone: streak"),
                tint: Color(red: 0.50, green: 0.55, blue: 0.98),
                details: [
                    streakStage.greetingPrefix,
                    NSLocalizedString("Чем длиннее серия, тем ярче визуальные акценты и персонализация рекомендаций.", comment: "Aurora streak card details")
                ]
            )
        ]

        if let topInsight = ai.insights.first {
            cards.append(
                AuroraMetricCardData(
                    id: "top_advice",
                    icon: topInsight.icon,
                    title: NSLocalizedString("Персональный совет", comment: "Aurora card title: personal advice"),
                    value: topInsight.title,
                    tone: NSLocalizedString("Это главный фокус от Авроры на ближайший период.", comment: "Aurora card tone: personal advice"),
                    tint: topInsight.accentColor,
                    details: [topInsight.body]
                )
            )
        }

        return cards
    }

    private var totalIncome: Double {
        incomes.reduce(0) { partial, income in
            partial + incomeAmount(income)
        }
    }

    private var currentMonthIncome: Double {
        let calendar = Calendar.current
        return incomes.reduce(0) { partial, income in
            guard let date = income.date,
                  calendar.isDate(date, equalTo: Date(), toGranularity: .month),
                  calendar.isDate(date, equalTo: Date(), toGranularity: .year) else {
                return partial
            }
            return partial + incomeAmount(income)
        }
    }

    private var totalTips: Double {
        incomes.reduce(0) { partial, income in
            partial + max(income.tips, 0)
        }
    }

    private var averageShiftIncome: Double {
        guard !incomes.isEmpty else { return 0 }
        return totalIncome / Double(incomes.count)
    }

    private var totalShiftCount: Int {
        ai.weekdayHeatmap.reduce(0) { $0 + $1.shiftsCount }
    }

    private var bestWeekday: WeekdayHeatmapRow? {
        ai.weekdayHeatmap
            .filter { $0.shiftsCount > 0 }
            .max(by: { $0.avgIncome < $1.avgIncome })
    }

    private var bestHour: HourlyHeatmapRow? {
        ai.hourlyHeatmap
            .filter { $0.shiftsCount > 0 }
            .max(by: { $0.avgIncome < $1.avgIncome })
    }

    private var trendSummaryText: String {
        let actualPoints = ai.trendPoints.filter { !$0.isPredicted }
        guard actualPoints.count >= 2,
              let firstValue = actualPoints.first?.movingAverage,
              let lastValue = actualPoints.last?.movingAverage,
              firstValue > 0 else {
            return NSLocalizedString("Недостаточно данных", comment: "Aurora card: not enough data")
        }

        let changePercent = ((lastValue - firstValue) / firstValue) * 100
        if abs(changePercent) < 1 {
            return NSLocalizedString("Стабильно", comment: "Aurora trend stable")
        }
        return changePercent > 0
            ? String(format: NSLocalizedString("Рост %.0f%%", comment: "Aurora trend up"), changePercent)
            : String(format: NSLocalizedString("Снижение %.0f%%", comment: "Aurora trend down"), abs(changePercent))
    }

    private var seasonalSummaryValue: String {
        if let holidayInsight {
            return holidayInsight.title
        }
        if let holiday = todayHolidayInfo {
            return holiday.title
        }
        if proManager.canUse(.externalFactors) {
            let precipitation = Int((todayWeather.precipitationChance * 100).rounded())
            if todayWeather.condition == .rain || todayWeather.condition == .snow || precipitation >= 55 {
                return String(
                    format: NSLocalizedString("Погодный фактор: %d%% осадков", comment: "Aurora card summary weather precipitation"),
                    precipitation
                )
            }
        }
        if !proManager.canUse(.externalFactors) {
            return NSLocalizedString("Недоступно в текущем тарифе", comment: "Aurora card: external factors unavailable")
        }
        return NSLocalizedString("Ярких событий не найдено", comment: "Aurora card: no seasonal highlights")
    }

    private var seasonalDetails: [String] {
        if let holidayInsight {
            return [holidayInsight.body]
        }
        if let holiday = todayHolidayInfo {
            let impact = Int((holiday.percent * 100).rounded())
            return [
                String(
                    format: NSLocalizedString("%@: влияние около %+d%% к доходу.", comment: "Aurora card details holiday with impact"),
                    holiday.title,
                    impact
                ),
                String(
                    format: NSLocalizedString("Сезон: %@.", comment: "Aurora card details season label"),
                    seasonLabel(for: Date())
                )
            ]
        }
        if proManager.canUse(.externalFactors) {
            return [
                weatherDetailsText,
                String(
                    format: NSLocalizedString("Сезон: %@.", comment: "Aurora card details season label"),
                    seasonLabel(for: Date())
                )
            ]
        }
        if !proManager.canUse(.externalFactors) {
            return [NSLocalizedString("Включите Pro-функцию погоды и праздников, чтобы Аврора учитывала внешний спрос.", comment: "Aurora card details: external factors unavailable")]
        }
        return [NSLocalizedString("Аврора продолжит отслеживать календарные и сезонные эффекты по мере накопления данных.", comment: "Aurora card details: no seasonal highlights")]
    }

    private var holidayInsight: AIInsight? {
        ai.insights.first { insight in
            let title = insight.title.lowercased()
            let body = insight.body.lowercased()
            let patterns = ["празд", "holiday", "сезон", "season"]
            return patterns.contains(where: { title.contains($0) || body.contains($0) })
        }
    }

    private var resolvedWeatherCity: String {
        let city = DeviceLocationManager.shared.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !city.isEmpty { return city }
        return settings.proWeatherCity
    }

    private var todayWeather: DailyWeatherContext {
        let today = Calendar.current.startOfDay(for: Date())
        return WeatherManager.shared.context(
            for: today,
            cityName: resolvedWeatherCity,
            coordinates: DeviceLocationManager.shared.coordinate,
            allowLive: settings.proUseLiveWeather && proManager.canUse(.externalFactors)
        )
    }

    private var todayHolidayInfo: HolidayManager.HolidayImpactInfo? {
        HolidayManager.shared.impactInfo(for: Date(), regionCode: settings.proHolidayRegionCode)
    }

    private var weatherDetailsText: String {
        let precipitationPercent = Int((todayWeather.precipitationChance * 100).rounded())
        let conditionText: String
        switch todayWeather.condition {
        case .clear:
            conditionText = NSLocalizedString("Ясно", comment: "Aurora weather condition clear")
        case .cloudy:
            conditionText = NSLocalizedString("Облачно", comment: "Aurora weather condition cloudy")
        case .rain:
            conditionText = NSLocalizedString("Дождь", comment: "Aurora weather condition rain")
        case .snow:
            conditionText = NSLocalizedString("Снег", comment: "Aurora weather condition snow")
        case .unknown:
            conditionText = NSLocalizedString("Неопределенно", comment: "Aurora weather condition unknown")
        }
        return String(
            format: NSLocalizedString("Погода сегодня: %@, осадки %d%%.", comment: "Aurora weather details line"),
            conditionText,
            precipitationPercent
        )
    }

    private func seasonLabel(for date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 12, 1, 2:
            return NSLocalizedString("Зима", comment: "Aurora season label winter")
        case 3, 4, 5:
            return NSLocalizedString("Весна", comment: "Aurora season label spring")
        case 6, 7, 8:
            return NSLocalizedString("Лето", comment: "Aurora season label summer")
        default:
            return NSLocalizedString("Осень", comment: "Aurora season label autumn")
        }
    }

    private var incomeDeltaLast14Days: Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start14 = calendar.date(byAdding: .day, value: -13, to: today),
              let start7 = calendar.date(byAdding: .day, value: -6, to: today),
              let prevStart = calendar.date(byAdding: .day, value: -13, to: start14),
              let prevEnd = calendar.date(byAdding: .day, value: -1, to: start14) else {
            return 0
        }

        let currentValue = incomes.reduce(0.0) { partial, income in
            guard let date = income.date else { return partial }
            let day = calendar.startOfDay(for: date)
            guard day >= start7 && day <= today else { return partial }
            return partial + incomeAmount(income)
        }

        let previousValue = incomes.reduce(0.0) { partial, income in
            guard let date = income.date else { return partial }
            let day = calendar.startOfDay(for: date)
            guard day >= prevStart && day <= prevEnd else { return partial }
            return partial + incomeAmount(income)
        }

        guard previousValue > 0 else { return 0 }
        return ((currentValue - previousValue) / previousValue) * 100
    }

    private var tipsShareLast30Days: Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -29, to: today) else { return 0 }

        var totalIncomeWindow: Double = 0
        var totalTipsWindow: Double = 0
        for income in incomes {
            guard let date = income.date else { continue }
            let day = calendar.startOfDay(for: date)
            guard day >= start && day <= today else { continue }
            let amount = incomeAmount(income)
            totalIncomeWindow += max(amount, 0)
            totalTipsWindow += max(income.tips, 0)
        }
        guard totalIncomeWindow > 0 else { return 0 }
        return totalTipsWindow / totalIncomeWindow
    }

    private var greetingMessage: String {
        let dayContext = dayContextToday
        let dayPrompt: String
        if dayContext.hasShiftToday {
            dayPrompt = NSLocalizedString("Расскажи, как прошла твоя смена сегодня.", comment: "Aurora greeting for workday with shift")
        } else if dayContext.isWeekend {
            dayPrompt = NSLocalizedString("Расскажи, как ты провел выходной сегодня.", comment: "Aurora greeting for weekend")
        } else {
            dayPrompt = NSLocalizedString("Расскажи, как прошёл твой день?", comment: "Aurora default greeting")
        }
        return "\(streakStage.greetingPrefix) \(dayPrompt)"
    }

    private var dayContextToday: AuroraDayContext {
        let calendar = Calendar.current
        let sessionsToday = sessionManager.getSessionsForDate(Date())
        let hasIncomeToday = incomes.contains { income in
            guard let date = income.date else { return false }
            return calendar.isDate(date, inSameDayAs: Date())
        }
        return AuroraDayContext(
            isWeekend: calendar.isDateInWeekend(Date()),
            hasShiftToday: !sessionsToday.isEmpty || hasIncomeToday,
            shiftCountToday: sessionsToday.count + (hasIncomeToday ? 1 : 0),
            dayDate: calendar.startOfDay(for: Date())
        )
    }

    private func startGreetingAnimations() {
        guard !didStartGreetingAnimations else { return }
        didStartGreetingAnimations = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            performUIUpdate(.spring(response: 0.34, dampingFraction: 0.85)) {
                showGreetingBubble = true
            }
        }
    }

    private func handleFeedbackSubmit(text: String, manualMood: AuroraMood?) {
        let anomalyDetected = ai.insights.contains(where: { insight in
            if insight.type == .anomaly { return true }
            let combined = "\(insight.title.lowercased()) \(insight.body.lowercased())"
            return combined.contains("аномал") || combined.contains("anomal")
        })

        let externalFactors = AuroraExternalFactorsContext(
            weatherCondition: todayWeather.condition,
            precipitationChance: todayWeather.precipitationChance,
            holidayTitle: todayHolidayInfo?.title,
            holidayImpactPercent: todayHolidayInfo?.percent ?? 0,
            isPublicHoliday: todayHolidayInfo?.isPublicHoliday ?? false,
            seasonLabel: seasonLabel(for: Date()),
            anomalyDetected: anomalyDetected
        )

        let aiContext = AuroraAIContext(
            forecast: ai.forecast,
            profile: ai.profile,
            bestWeekday: bestWeekday,
            bestHour: bestHour,
            topInsight: ai.insights.first,
            currency: settings.defaultCurrency,
            recentIncomeDeltaPercent: incomeDeltaLast14Days,
            recentTipsShare: tipsShareLast30Days,
            externalFactors: externalFactors
        )

        let analysis = feedbackAnalyzer.analyze(
            text: text,
            manualMood: manualMood,
            dayContext: dayContextToday,
            ai: aiContext,
            recentEntries: feedbackStore.entries
        )

        let entry = AuroraFeedbackEntry(
            text: text,
            manualMood: manualMood,
            detectedMood: analysis.mood,
            keyMoments: analysis.keyMoments,
            dayContext: dayContextToday,
            recommendations: analysis.recommendations
        )
        feedbackStore.add(entry)
    }

    private func feedbackCardID(for recommendationID: UUID) -> String {
        "feedback-\(recommendationID.uuidString)"
    }

    private func toggleExpandedFeedbackCard(id recommendationID: UUID) {
        let cardID = feedbackCardID(for: recommendationID)
        performUIUpdate(.easeInOut(duration: 0.2)) {
            if expandedCardIDs.contains(cardID) {
                expandedCardIDs.remove(cardID)
            } else {
                expandedCardIDs.insert(cardID)
            }
        }
    }

    private func goalDetails(goalActive: Bool, forecast: AIForecast) -> [String] {
        guard goalActive else {
            return [NSLocalizedString("Активируйте цель во вкладке «Цели», чтобы Аврора считала вероятность выполнения срока.", comment: "Aurora card details: no active goal")]
        }

        let probability = Int(forecast.goalProbability * 100)
        let recommendation: String
        if forecast.goalProbability >= 0.8 {
            recommendation = NSLocalizedString("Темп отличный: сохраняйте текущий ритм.", comment: "Aurora goal details high probability")
        } else if forecast.goalProbability >= 0.5 {
            recommendation = NSLocalizedString("Хороший шанс: добавьте 1 сильную смену в неделю для запаса.", comment: "Aurora goal details medium probability")
        } else {
            recommendation = NSLocalizedString("Нужна коррекция: сместите график в лучшие дни и часы.", comment: "Aurora goal details low probability")
        }

        return [
            String(format: NSLocalizedString("Текущая вероятность: %d%%", comment: "Aurora goal details probability"), probability),
            recommendation
        ]
    }

    private func plannerDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func incomeAmount(_ income: Income) -> Double {
        income.hoursWorked * income.hourlyRate + income.tips + income.floatingAmount
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

private struct AuroraMetricCardData: Identifiable {
    let id: String
    let icon: String
    let title: String
    let value: String
    let tone: String
    let tint: Color
    let details: [String]
}

private struct AuroraMetricCard: View {
    let card: AuroraMetricCardData
    let isExpanded: Bool
    let onTap: () -> Void

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: card.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(card.tint)
                        .frame(width: 30, height: 30)
                        .visionGlassCard(cornerRadius: 9, opacity: 0.78)

                    Spacer(minLength: 0)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                }

                Text(card.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)

                Text(card.value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppColors.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(card.tone)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(isExpanded ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if isExpanded, !card.details.isEmpty {
                    Divider()
                        .overlay(AppColors.border)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(card.details, id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 4, weight: .semibold))
                                    .foregroundColor(card.tint)
                                    .padding(.top, 5)
                                Text(item)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(AppColors.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: isExpanded ? 224 : 176, alignment: .topLeading)
            .visionGlassCard(cornerRadius: 16, opacity: 0.86, showRing: true)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .lightweightAnimation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

private struct AuroraFeedbackRecommendationCard: View {
    let recommendation: AuroraFeedbackRecommendation
    let isExpanded: Bool
    let onTap: () -> Void

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: recommendation.mood.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(recommendation.mood.color)
                        .frame(width: 30, height: 30)
                        .visionGlassCard(cornerRadius: 9, opacity: 0.78)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recommendation.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.text)
                            .lineLimit(2)
                        Text(recommendation.body)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(isExpanded ? 4 : 2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText.opacity(0.75))
                }

                if isExpanded, !recommendation.details.isEmpty {
                    Divider()
                        .overlay(AppColors.border)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(recommendation.details, id: \.self) { detail in
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(recommendation.mood.color)
                                    .padding(.top, 2)
                                Text(detail)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(AppColors.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .visionGlassCard(cornerRadius: 14, opacity: 0.84, showRing: true)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AuroraFeedbackComposer: View {
    let dayMessage: String
    let onSend: (_ text: String, _ manualMood: AuroraMood?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var selectedMood: ComposerMood = .auto

    enum ComposerMood: String, CaseIterable, Identifiable {
        case auto
        case positive
        case neutral
        case negative

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto:
                return NSLocalizedString("Авто", comment: "Aurora composer mood auto")
            case .positive:
                return NSLocalizedString("Позитив", comment: "Aurora composer mood positive")
            case .neutral:
                return NSLocalizedString("Нейтрально", comment: "Aurora composer mood neutral")
            case .negative:
                return NSLocalizedString("Негатив", comment: "Aurora composer mood negative")
            }
        }

        var manualMood: AuroraMood? {
            switch self {
            case .auto:
                return nil
            case .positive:
                return .positive
            case .neutral:
                return .neutral
            case .negative:
                return .negative
            }
        }
    }

    private var canSend: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6
    }

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            ZStack {
                VisionBackdropView()
                VStack(alignment: .leading, spacing: 12) {
                    Text(dayMessage)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(AppColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .visionGlassCard(cornerRadius: 14, opacity: 0.86, showRing: true)

                    Text(NSLocalizedString("Выберите настроение (или оставьте авто):", comment: "Aurora composer mood picker title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)

                    Picker("", selection: $selectedMood) {
                        ForEach(ComposerMood.allCases) { mood in
                            Text(mood.title).tag(mood)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextEditor(text: $text)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(AppColors.text)
                        .frame(minHeight: 180, maxHeight: 230)
                        .padding(8)
                        .visionGlassCard(cornerRadius: 12, opacity: 0.84, showRing: true)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(NSLocalizedString("Например: сегодня было спокойно, но в вечернюю смену устал. Хорошо сработали чаевые и быстрый старт.", comment: "Aurora composer placeholder"))
                                    .font(.system(size: 14))
                                    .foregroundColor(AppColors.secondaryText.opacity(0.7))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 16)
                            }
                        }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .navigationTitle(NSLocalizedString("Обратная связь Авроре", comment: "Aurora composer title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Отмена", comment: "common cancel action")) {
                        dismiss()
                    }
                    .foregroundColor(AppColors.secondaryText)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Отправить", comment: "common send action")) {
                        guard canSend else { return }
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSend(trimmed, selectedMood.manualMood)
                        dismiss()
                    }
                    .foregroundColor(canSend ? AppColors.accent : AppColors.secondaryText)
                    .disabled(!canSend)
                }
            }
        }
    }
}

#Preview {
    AuroraView(settings: UserSettings())
}
