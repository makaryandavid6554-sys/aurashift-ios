// DailyView.swift — AuraShift
// Кешированные вычисления, компактная шапка, встроенный AI-баннер

import SwiftUI
import CoreData
import Combine
import UIKit

// MARK: - DisplayItem
enum DisplayItem: Identifiable {
    case session(WorkSession)
    case planned(PlannedShift)

    private static let plannedTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    var id: UUID {
        switch self { case .session(let s): return s.id; case .planned(let p): return p.id }
    }
    var isPlanned: Bool {
        switch self { case .planned: return true; case .session: return false }
    }
    var workTypeName: String {
        switch self { case .session(let s): return s.workTypeName; case .planned(let p): return p.workTypeName }
    }
    var icon: String {
        switch self { case .session(let s): return s.icon; case .planned(let p): return p.icon }
    }
    var hasHourlyRate: Bool {
        switch self { case .session(let s): return s.hasHourlyRate; case .planned: return false }
    }
    var hasFixedRate: Bool {
        switch self { case .session(let s): return s.hasFixedRate; case .planned: return false }
    }
    var hasFloatingRate: Bool {
        switch self { case .session(let s): return s.hasFloatingRate; case .planned: return false }
    }
    var hasTips: Bool {
        switch self { case .session(let s): return s.hasTips; case .planned(let p): return p.hasTips }
    }
    var note: String? {
        switch self { case .session(let s): return s.note; case .planned(let p): return p.note }
    }
    var timeRange: String {
        switch self {
        case .session(let s): return s.timeRange
        case .planned(let p):
            return "\(Self.plannedTimeFormatter.string(from: p.startTime))–\(Self.plannedTimeFormatter.string(from: p.endTime))"
        }
    }
    var sortStartMinute: Int {
        switch self {
        case .session(let s): return s.startHour * 60 + s.startMinute
        case .planned(let p):
            let c = Calendar.current.dateComponents([.hour, .minute], from: p.startTime)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }
    var totalEarning: Double {
        switch self { case .session(let s): return s.totalEarning; case .planned: return 0 }
    }
}

// MARK: - DailyView
struct DailyView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var settings: UserSettings
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var ai: AIEngine

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \FinancialGoal.deadline, ascending: true)])
    private var goals: FetchedResults<FinancialGoal>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Expense.date, ascending: true)])
    private var expenseEntities: FetchedResults<Expense>

    // MARK: UI State
    @State private var selectedDate = Date()
    @State private var showingAddWorkSheet = false
    @State private var editingItem: DisplayItem?
    @State private var expenses: [ExpenseItem] = []
    @State private var editingExpense: ExpenseItem?
    @State private var showingAddExpense = false
    @State private var showMessage = false
    @State private var messageText = ""
    @State private var keyboardHeight: CGFloat = 0
    @State private var pendingSaveWorkItem: DispatchWorkItem?
    @State private var pendingMetricsWorkItem: DispatchWorkItem?
    @State private var metricsComputationToken: Int = 0
    @State private var isSavingInProgress = false
    @State private var saveRequestedWhileSaving = false
    @State private var showingAIDetail = false
    @State private var selectedAIInsight: AIInsight?
    @State private var showAIInsightSheet = false
    @State private var auroraWaveAngle: Double = 0
    @State private var didStartAuroraWaveAnimation = false
    @State private var showDayPanel = false
    @State private var visibleMonthDate = Date()

    // MARK: Кешированные метрики (обновляются только при изменении данных)
    @State private var cachedTodayIncome: Double = 0
    @State private var cachedMonthIncome: Double = 0
    @State private var cachedRemaining: Double = 0
    @State private var cachedGoalPace: String = "—"
    @State private var cachedDisplayItems: [DisplayItem] = []
    @State private var cachedGoalsEmpty: Bool = true

    // MARK: Formatters (создаются один раз)
    private let yearFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy"; return f
    }()
    private let metricsQueue = DispatchQueue(label: "com.aurashift.daily.metrics", qos: .utility)

    // MARK: Simple computed (дешёвые, не кешируем)
    private var sessionsForDate: [WorkSession] { sessionManager.getSessionsForDate(selectedDate) }
    private var plannedShiftsForDate: [PlannedShift] { sessionManager.getPlannedShiftsForDate(selectedDate) }
    private var isFutureDate: Bool { selectedDate > Date() }
    private var activeGoals: [FinancialGoal] { goals.filter { $0.isActive } }
    private var remainingTileColor: Color {
        if cachedGoalsEmpty {
            return AppColors.secondaryText
        }
        return cachedRemaining > 0 ? AppColors.accent : AppColors.positive
    }

    // displayItems кешируется в cachedDisplayItems, обновляется через refreshDisplayItems()

    private var availableExpenseCategories: [String] {
        let cats = settings.expenseCategories.map { settings.normalizedExpenseCategoryName($0) }.filter { !$0.isEmpty }
        return cats.isEmpty ? [NSLocalizedString("Другое", comment: "default expense category fallback")] : cats
    }
    private var defaultExpenseCategory: String {
        availableExpenseCategories.first ?? NSLocalizedString("Другое", comment: "default expense category fallback")
    }

    private func formattedAmount(_ v: Double) -> String { settings.formattedCurrency(v) }
    private func incomeForDate(_ date: Date) -> Double { sessionManager.getSessionsForDate(date).reduce(0) { $0 + $1.totalEarning } }

    // MARK: Тяжёлые вычисления (вызываются только для кеша)
    private func scheduleMetricsRecompute(delay: TimeInterval = 0.06) {
        pendingMetricsWorkItem?.cancel()

        let sessionSnapshots = sessionManager.workSessions.map { ($0.date, $0.totalEarning) }
        let expenseSnapshots: [(Date, Double)] = expenseEntities.compactMap { expense in
            guard let date = expense.date else { return nil }
            return (date, expense.amount)
        }
        let goalSnapshots = activeGoals.map { ($0.targetAmount, $0.currentAmount) }
        let formatter = settings
        let token = metricsComputationToken + 1
        metricsComputationToken = token

        let workItem = DispatchWorkItem {
            metricsQueue.async {
                let calendar = Calendar.current
                let today = Date()

                let todayIncome = sessionSnapshots.reduce(0.0) { partial, session in
                    calendar.isDate(session.0, inSameDayAs: today) ? partial + session.1 : partial
                }

                let monthIncome: Double = {
                    guard let interval = calendar.dateInterval(of: .month, for: today) else { return 0 }
                    return sessionSnapshots.reduce(0.0) { partial, session in
                        (session.0 >= interval.start && session.0 < interval.end) ? partial + session.1 : partial
                    }
                }()

                let totalTarget = goalSnapshots.reduce(0.0) { $0 + $1.0 }
                let totalCurrent = goalSnapshots.reduce(0.0) { $0 + $1.1 }
                let totalIncome = sessionSnapshots.reduce(0.0) { $0 + $1.1 }
                let totalExpense = expenseSnapshots.reduce(0.0) { $0 + $1.1 }
                let netProfit = totalIncome - totalExpense
                let withProfit = totalCurrent + max(netProfit, 0)
                let remaining = max(totalTarget - withProfit, 0)

                let goalPaceText: String = {
                    if goalSnapshots.isEmpty {
                        guard let windowStart = calendar.date(byAdding: .day, value: -27, to: calendar.startOfDay(for: today)) else {
                            return formatter.formattedCurrency(monthIncome)
                        }
                        let recent = sessionSnapshots.filter {
                            let day = calendar.startOfDay(for: $0.0)
                            return day >= windowStart && day <= today && $0.1 > 0
                        }
                        guard !recent.isEmpty, let daysInMonth = calendar.range(of: .day, in: .month, for: today)?.count else {
                            return formatter.formattedCurrency(monthIncome)
                        }
                        let avg = recent.reduce(0.0) { $0 + $1.1 } / Double(recent.count)
                        let shiftsPerDay = Double(recent.count) / 28.0
                        let projected = avg * shiftsPerDay * Double(daysInMonth)
                        let forecast = max(monthIncome, projected.isFinite ? projected : monthIncome)
                        return formatter.formattedCurrency(forecast)
                    }

                    guard remaining > 0 else {
                        return NSLocalizedString("Цель закрыта", comment: "goal pace: goal reached")
                    }
                    guard let windowStart = calendar.date(byAdding: .day, value: -59, to: today) else {
                        return NSLocalizedString("Мало данных", comment: "goal pace: not enough data")
                    }
                    let recent = sessionSnapshots.filter {
                        let day = calendar.startOfDay(for: $0.0)
                        return day >= calendar.startOfDay(for: windowStart) && day <= calendar.startOfDay(for: today)
                    }
                    guard !recent.isEmpty else {
                        return NSLocalizedString("Мало данных", comment: "goal pace: not enough data")
                    }

                    let recentIncome = recent.reduce(0.0) { $0 + $1.1 }
                    let recentExpense = expenseSnapshots.reduce(0.0) { partial, expense in
                        let day = calendar.startOfDay(for: expense.0)
                        guard day >= calendar.startOfDay(for: windowStart), day <= calendar.startOfDay(for: today) else {
                            return partial
                        }
                        return partial + expense.1
                    }
                    let recentNet = recentIncome - recentExpense
                    let avgPerShift = recentNet / Double(recent.count)
                    guard avgPerShift > 0 else {
                        return NSLocalizedString("Темп ниже расходов", comment: "goal pace: negative net pace")
                    }
                    let shiftsNeeded = Int(ceil(remaining / avgPerShift))
                    let monthlyNet = (recentNet / 60.0) * 30.0
                    let shiftsUnit = NSLocalizedString("смен", comment: "goal pace unit: shifts")
                    guard monthlyNet > 0 else { return "\(shiftsNeeded) \(shiftsUnit)" }

                    let months = remaining / monthlyNet
                    let monthText = months >= 100 ? "\(Int(months.rounded()))" : String(format: "%.1f", months)
                    let monthsUnit = NSLocalizedString("мес", comment: "goal pace unit: months")
                    return "\(shiftsNeeded) \(shiftsUnit)\n≈\(monthText) \(monthsUnit)"
                }()

                DispatchQueue.main.async {
                    guard token == metricsComputationToken else { return }
                    cachedTodayIncome = todayIncome
                    cachedMonthIncome = monthIncome
                    cachedRemaining = remaining
                    cachedGoalPace = goalPaceText
                    cachedGoalsEmpty = goalSnapshots.isEmpty
                    refreshDisplayItems()
                }
            }
        }

        pendingMetricsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func refreshDisplayItems() {
        var items = sessionsForDate.map { DisplayItem.session($0) }
        items += plannedShiftsForDate.map { DisplayItem.planned($0) }
        cachedDisplayItems = items.sorted {
            $0.sortStartMinute == $1.sortStartMinute
                ? $0.workTypeName < $1.workTypeName
                : $0.sortStartMinute < $1.sortStartMinute
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // STYLE: Главный "обойный" фон экрана (градиенты/блики в VisionBackdropView).
            VisionBackdropView()

            VStack(spacing: 0) {
                headerSection
                    .layoutPriority(2)
                    .fixedSize(horizontal: false, vertical: true)
                // STYLE: Основной календарный блок растянут на доступную высоту экрана.
                calendarSection
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            if showMessage { toastOverlay }
        }
        .navigationBarHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) {
            if let r = $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect { keyboardHeight = r.height }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .scrollDismissesKeyboard(.immediately)
        .onAppear {
            loadExpensesForDate()
            scheduleMetricsRecompute()
            startAuroraWaveAnimationIfNeeded()
            showDayPanel = false
        }
        .onDisappear {
            pendingSaveWorkItem?.cancel()
            pendingSaveWorkItem = nil
            pendingMetricsWorkItem?.cancel()
            pendingMetricsWorkItem = nil
            saveDayData()
        }
        .onChange(of: selectedDate) { _ in loadExpensesForDate(); refreshDisplayItems() }
        .onChange(of: sessionManager.workSessions.count) { _ in scheduleMetricsRecompute(); refreshDisplayItems() }
        .onChange(of: expenseEntities.count) { _ in scheduleMetricsRecompute() }
        .sheet(isPresented: $showingAddWorkSheet) {
            AddWorkSheet(ai: ai, sessionManager: sessionManager, settings: settings,
                         selectedDate: selectedDate, isFuture: isFutureDate) {
                saveDayData(showMessage: true)
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseSheet(expenses: $expenses, settings: settings,
                            categories: availableExpenseCategories) {
                saveDayData(showMessage: true)
            }
        }
        .sheet(item: $editingItem) { item in
            UnifiedShiftEditorSheet(
                item: item,
                settings: settings,
                sessionManager: sessionManager,
                onSave: { saveDayData(showMessage: true) },
                onDelete: { deleteItem(item) }
            )
        }
        .sheet(item: $editingExpense) { expense in
            EditExpenseSheet(expense: expense, settings: settings,
                             categories: availableExpenseCategories) { updateExpense($0) }
        }
        .sheet(isPresented: $showingAIDetail) {
            AuroraView(settings: settings).environmentObject(ai)
        }
        .sheet(isPresented: $showAIInsightSheet) {
            if let insight = selectedAIInsight { InsightDetailSheet(insight: insight) }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // STYLE: Крупный размер месяца (52) задает акцент шапки.
                Text(monthTitle(for: visibleMonthDate))
                    .font(.system(size: 52, weight: .bold))
                    .foregroundColor(AppColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                // STYLE: Год вторичным цветом и меньшим размером.
                Text(yearFormatter.string(from: visibleMonthDate))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer(minLength: 0)
        }
        // STYLE: Внешние отступы шапки (позиция блока вверху экрана).
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = settings.appLanguage.locale
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date).capitalized
    }

    private func aiBannerTitle(for insight: AIInsight) -> String {
        if isRussianInterfaceLanguage {
            return insight.title
        }
        switch insight.type {
        case .recommendation:
            return NSLocalizedString("Персональный совет", comment: "AI banner title: recommendation")
        case .forecast:
            return NSLocalizedString("Прогноз AI", comment: "AI banner title: forecast")
        case .anomaly:
            return NSLocalizedString("Аномалия", comment: "AI banner title: anomaly")
        case .trend:
            return NSLocalizedString("Тренд", comment: "AI banner title: trend")
        case .achievement:
            return NSLocalizedString("Достижение", comment: "AI banner title: achievement")
        case .warning:
            return NSLocalizedString("Предупреждение", comment: "AI banner title: warning")
        }
    }

    private func compactAIBannerTitle(for insight: AIInsight) -> String {
        var title = aiBannerTitle(for: insight)
        let compactReplacements: [(String, String)] = [
            (
                NSLocalizedString("Вероятность достижения цели в срок: ", comment: "daily ai compact title source: goal on time probability"),
                NSLocalizedString("Цель в срок: ", comment: "daily ai compact title replacement: goal on time short")
            ),
            (
                NSLocalizedString("Добавь смену — ", comment: "daily ai compact title source: add shift"),
                NSLocalizedString("Смена: ", comment: "daily ai compact title replacement: shift short")
            ),
            (
                NSLocalizedString("Умный прогноз чистой прибыли", comment: "daily ai compact title source: smart net forecast"),
                NSLocalizedString("Прогноз чистой прибыли", comment: "daily ai compact title replacement: net forecast")
            )
        ]
        for (source, replacement) in compactReplacements {
            title = title.replacingOccurrences(of: source, with: replacement)
        }
        if title.count > 34 {
            if let dash = title.firstIndex(of: "—") {
                let head = title[..<dash].trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(head)…"
            }
            return "\(title.prefix(31))…"
        }
        return title
    }

    private var isRussianInterfaceLanguage: Bool {
        switch settings.appLanguage {
        case .russian:
            return true
        case .system:
            return Locale.autoupdatingCurrent.identifier.lowercased().hasPrefix("ru")
        default:
            return false
        }
    }

    private func startAuroraWaveAnimationIfNeeded() {
        guard !didStartAuroraWaveAnimation else { return }
        didStartAuroraWaveAnimation = true
        performUIUpdate(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
            auroraWaveAngle = 16
        }
    }

    // MARK: AI inline баннер — одна строка вместо отдельного блока
    @ViewBuilder
    private var aiInlineBanner: some View {
        Button(action: { showingAIDetail = true }) {
            HStack(spacing: 8) {
                // Иконка AI
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppColors.surface.opacity(0.9))
                        .frame(width: 28, height: 28)
                    Image(systemName: "hand.wave.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.text)
                        .rotationEffect(.degrees(auroraWaveAngle))
                }

                if ai.isAnalyzing {
                    Text(NSLocalizedString("Аврора анализирует данные...", comment: "daily aurora loading state"))
                        .font(.system(size: 12)).foregroundColor(AppColors.secondaryText)
                    Spacer()
                    ProgressView().scaleEffect(0.7)
                } else if !ai.hasEnoughData {
                    Text(NSLocalizedString("Аврора: добавьте 5+ смен для анализа", comment: "daily aurora not enough data"))
                        .font(.system(size: 12)).foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10)).foregroundColor(AppColors.secondaryText.opacity(0.4))
                } else if let top = ai.insights.first {
                    // Показываем топ инсайт
                    let bannerTitle = compactAIBannerTitle(for: top)
                    Image(systemName: top.icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(top.accentColor)
                        .frame(width: 20, height: 20)
                        .visionGlassCard(cornerRadius: 6, opacity: 0.78)
                    Text(bannerTitle)
                        // STYLE: Размер 14 и semibold для главного текста баннера.
                        .font(.system(size: 14, weight: .semibold, design: .default)).foregroundColor(AppColors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.95)
                        .layoutPriority(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10)).foregroundColor(AppColors.secondaryText.opacity(0.4))
                } else {
                    Text(NSLocalizedString("Аврора", comment: "daily ai assistant title"))
                        .font(.system(size: 12)).foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10)).foregroundColor(AppColors.secondaryText.opacity(0.4))
                }
            }
            // STYLE: Габариты и плотность баннера.
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 46)
            // STYLE: Стеклянный фон баннера.
            .visionGlassCard(cornerRadius: 10, opacity: 0.78)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                SimpleCalendarView(
                    selectedDate: $selectedDate,
                    visibleMonthDate: $visibleMonthDate,
                    plannedShifts: sessionManager.plannedShifts,
                    allSessions: sessionManager.workSessions,
                    onSelectDate: { _ in
                        performUIUpdate(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showDayPanel = true
                        }
                    },
                    colorForWorkType: { name in
                        (settings.workTypes.first(where: { $0.name == name })
                            .flatMap { Color(hex: $0.colorHex) }) ?? .blue
                    }
                )

                if showDayPanel && keyboardHeight == 0 {
                    // STYLE: Панель дня фиксируется у нижнего края, чтобы не ломаться при вертикальном скролле месяцев.
                    dayActionsPanel
                        .frame(
                            width: min(max(290, proxy.size.width * 0.9), proxy.size.width - 14),
                            height: min(dayPanelPreferredHeight, max(180, proxy.size.height * 0.56)),
                            alignment: .top
                        )
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(2)
                }
            }
        }
        // STYLE: Внешняя геометрия календарной карточки.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
        // STYLE: Стеклянный контейнер календаря.
        .visionGlassCard(cornerRadius: 20, opacity: 0.84, showRing: true)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var dayPanelPreferredHeight: CGFloat {
        if cachedDisplayItems.isEmpty && expenses.isEmpty {
            return 190
        }
        return 360
    }

    private var dividerLine: some View {
        Divider().background(AppColors.border).padding(.horizontal, 16).padding(.vertical, 4)
    }

    // MARK: - Shifts Section

    @ViewBuilder
    private var shiftsSection: some View {
        if cachedDisplayItems.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 28)).foregroundColor(AppColors.secondaryText.opacity(0.45))
                Text(NSLocalizedString("День пустой", comment: "daily empty day title"))
                    .font(.subheadline).foregroundColor(AppColors.secondaryText)
                Text(NSLocalizedString("Добавить смену или расход", comment: "daily empty day subtitle"))
                    .font(.caption).foregroundColor(AppColors.secondaryText.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            List {
                ForEach(cachedDisplayItems, id: \.id) { item in
                    DisplayCard(
                        item: item, settings: settings,
                        onUpdateFloating: { v in
                            if case .session(let s) = item { updateSession(s, floatingAmount: v) }
                        },
                        onUpdateTips: { v in
                            if case .session(let s) = item { updateSession(s, tips: v) }
                        },
                        onEdit: { editingItem = item }
                    )
                    .scrollDismissesKeyboard(.immediately)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deleteItem(item) } label: {
                            Label(NSLocalizedString("Удалить", comment: "common delete action"), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            editingItem = item
                        } label: {
                            Label(NSLocalizedString("Редактировать", comment: "common edit action"), systemImage: "pencil")
                        }
                        .tint(AppColors.accent)
                    }
                }
            }
            .listStyle(PlainListStyle())
            .frame(maxHeight: .infinity, alignment: .top)
            .layoutPriority(1)
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Expenses Row

    @ViewBuilder
    private var expensesRow: some View {
        if !expenses.isEmpty && keyboardHeight == 0 {
            Divider().background(AppColors.border).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(expenses) { expense in
                        ExpenseCard(expense: expense, settings: settings,
                                    onEdit: { editingExpense = expense },
                                    onDelete: { deleteExpense(expense) })
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
    }

    private var daySummaryText: String {
        let shiftsText = String(
            format: NSLocalizedString("%d смен", comment: "daily day panel summary: shifts count"),
            cachedDisplayItems.count
        )
        let expensesText = String(
            format: NSLocalizedString("%d расходов", comment: "daily day panel summary: expenses count"),
            expenses.count
        )
        return "\(shiftsText) · \(expensesText)"
    }

    private var selectedDateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale()
        formatter.dateFormat = "d MMMM, EEEE"
        return formatter.string(from: selectedDate).capitalized
    }

    private func colorForWorkType(_ name: String) -> Color {
        (settings.workTypes.first(where: { $0.name == name })
            .flatMap { Color(hex: $0.colorHex) }) ?? AppColors.accent
    }

    private var dayActionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    // STYLE: Заголовок даты в панели дня.
                    Text(selectedDateTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.text)
                    // STYLE: Подпись с количеством смен/расходов.
                    Text(daySummaryText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer(minLength: 0)

                Button(NSLocalizedString("Свернуть", comment: "daily day panel action collapse")) {
                    performUIUpdate(.easeInOut(duration: 0.2)) {
                        showDayPanel = false
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                // STYLE: Стеклянный вид кнопки сворачивания.
                .visionGlassCard(cornerRadius: 12, opacity: 0.82)
                .buttonStyle(.plain)
            }

            if cachedDisplayItems.isEmpty && expenses.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                    Text(NSLocalizedString("На выбранную дату нет записей. Добавьте смену или расход.", comment: "daily day panel empty state"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } else {
                List {
                    if !cachedDisplayItems.isEmpty {
                        Section {
                            ForEach(cachedDisplayItems, id: \.id) { item in
                                HStack(spacing: 10) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(colorForWorkType(item.workTypeName))
                                        .frame(width: 30, height: 30)
                                        .visionGlassCard(cornerRadius: 9, opacity: 0.78)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.workTypeName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(AppColors.text)
                                            .lineLimit(1)
                                        Text(item.timeRange)
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(AppColors.secondaryText)
                                    }

                                    Spacer(minLength: 0)

                                    if !item.isPlanned {
                                        Text(formattedAmount(item.totalEarning))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AppColors.positive)
                                    }

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText.opacity(0.6))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                // STYLE: Каждая строка в панели дня оформлена отдельной стеклянной карточкой.
                                .visionGlassCard(cornerRadius: 12, opacity: 0.80)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingItem = item
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        editingItem = item
                                    } label: {
                                        Label(NSLocalizedString("Редактировать", comment: "common edit action"), systemImage: "pencil")
                                    }
                                    .tint(AppColors.accent)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteItem(item)
                                    } label: {
                                        Label(NSLocalizedString("Удалить", comment: "common delete action"), systemImage: "trash")
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            Text(NSLocalizedString("Смены", comment: "daily day panel section title: shifts"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }

                    if !expenses.isEmpty {
                        Section {
                            ForEach(expenses) { expense in
                                HStack(spacing: 10) {
                                    Image(systemName: "creditcard.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppColors.negative)
                                        .frame(width: 30, height: 30)
                                        .visionGlassCard(cornerRadius: 9, opacity: 0.78)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(expense.category)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(AppColors.text)
                                        if !expense.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(expense.note)
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundColor(AppColors.secondaryText)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer(minLength: 0)

                                    Text(settings.formattedCurrency(-expense.amount))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppColors.negative)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .visionGlassCard(cornerRadius: 12, opacity: 0.80)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingExpense = expense
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        editingExpense = expense
                                    } label: {
                                        Label(NSLocalizedString("Редактировать", comment: "common edit action"), systemImage: "pencil")
                                    }
                                    .tint(AppColors.accent)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteExpense(expense)
                                    } label: {
                                        Label(NSLocalizedString("Удалить", comment: "common delete action"), systemImage: "trash")
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            Text(NSLocalizedString("Расходы", comment: "daily day panel section title: expenses"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                // STYLE: Ограничение высоты списка, чтобы не занимал всю панель.
                .frame(maxHeight: 230)
            }

            HStack(spacing: 10) {
                Button(action: { showingAddWorkSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text(NSLocalizedString("Смена", comment: "daily primary action: shift"))
                    }
                    .foregroundColor(AppColors.text)
                }
                .buttonStyle(VisionPrimaryButtonStyle())

                Button(action: { showingAddExpense = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "creditcard")
                        Text(NSLocalizedString("Расход", comment: "daily primary action: expense"))
                    }
                    .foregroundColor(AppColors.text)
                }
                .buttonStyle(VisionSecondaryButtonStyle())
            }
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // STYLE: Внешний стиль popup-панели дня.
        .visionGlassCard(cornerRadius: 18, opacity: 0.88, showRing: true)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: { showingAddWorkSheet = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(NSLocalizedString("Смена", comment: "daily primary action: shift"))
                }
                .foregroundColor(AppColors.text)
            }
            .buttonStyle(VisionPrimaryButtonStyle())
            Button(action: { showingAddExpense = true }) {
                HStack {
                    Image(systemName: "creditcard")
                    Text(NSLocalizedString("Расход", comment: "daily primary action: expense"))
                }
                .foregroundColor(AppColors.text)
            }
            .buttonStyle(VisionSecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Toast

    private var toastOverlay: some View {
        VStack {
            Spacer()
            Text(messageText)
                .font(.caption2).foregroundColor(AppColors.accent)
                .padding(.horizontal, 16).padding(.vertical, 8)
                // STYLE: Фон тоста и мягкая тень.
                .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
                .shadow(radius: 2)
                .padding(.bottom, 80)
        }
    }

    // MARK: - Summary Metric Subviews

    // Компактная плитка — одна строка 4 ячейки
    @ViewBuilder
    private func compactTile(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppColors.secondaryText)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        // STYLE: Единый размер компактной метрики.
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .visionGlassCard(cornerRadius: 8, opacity: 0.74)
    }

    // MARK: - Data Loading & Saving

    private func loadExpensesForDate() {
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let req: NSFetchRequest<Expense> = Expense.fetchRequest()
        req.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        do {
            expenses = try viewContext.fetch(req).map {
                ExpenseItem(id: $0.id ?? UUID(), amount: $0.amount,
                            category: $0.category ?? defaultExpenseCategory, note: $0.notes ?? "")
            }
        } catch { print("❌ Ошибка загрузки расходов: \(error)") }
    }

    private func scheduleSaveDayData() {
        pendingSaveWorkItem?.cancel()
        let w = DispatchWorkItem { saveDayData() }
        pendingSaveWorkItem = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
    }

    private func saveDayData(showMessage flag: Bool = false) {
        guard !isSavingInProgress else { saveRequestedWhileSaving = true; return }
        pendingSaveWorkItem?.cancel(); pendingSaveWorkItem = nil
        isSavingInProgress = true
        defer {
            isSavingInProgress = false
            if saveRequestedWhileSaving {
                saveRequestedWhileSaving = false
                DispatchQueue.main.async { saveDayData() }
            }
        }
        print("💾 Сохраняем данные на \(selectedDate)...\n   Смен: \(sessionsForDate.count)")
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: selectedDate)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!

        let iReq: NSFetchRequest<Income> = Income.fetchRequest()
        iReq.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        if let old = try? viewContext.fetch(iReq) { old.forEach { viewContext.delete($0) } }

        let eReq: NSFetchRequest<Expense> = Expense.fetchRequest()
        eReq.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        if let old = try? viewContext.fetch(eReq) { old.forEach { viewContext.delete($0) } }

        for session in sessionsForDate where session.totalEarning > 0 {
            let income = Income(context: viewContext)
            income.id = UUID(); income.date = session.date
            income.type = session.workTypeName; income.tips = session.tips; income.note = session.note
            if session.hasHourlyRate {
                income.hoursWorked = session.calculatedHours; income.hourlyRate = session.hourlyRate; income.floatingAmount = 0
            } else if session.hasFixedRate {
                income.hoursWorked = 0; income.hourlyRate = 0; income.floatingAmount = session.fixedAmount
            } else if session.hasFloatingRate {
                income.hoursWorked = 0; income.hourlyRate = 0; income.floatingAmount = session.floatingAmount
            }
        }
        for expense in expenses where expense.amount > 0 {
            let e = Expense(context: viewContext)
            e.id = expense.id; e.date = startOfDay
            e.amount = expense.amount; e.category = expense.category; e.notes = expense.note
        }
        do {
            try viewContext.save()
            if flag {
                HapticEngine.success()
                SoundManager.shared.play(.success)
                showMessage(NSLocalizedString("✓ Данные обновлены", comment: "daily save toast: data updated"))
            }
            print("✅ Сохранение завершено")
            scheduleMetricsRecompute()
        } catch {
            if flag {
                HapticEngine.error()
                SoundManager.shared.play(.error)
                showMessage(NSLocalizedString("✗ Не удалось сохранить", comment: "daily save toast: failed"))
            }
            print("❌ Ошибка сохранения: \(error)")
        }
    }

    // MARK: - Helpers

    private func showMessage(_ text: String) {
        messageText = text
        withAnimation { showMessage = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { showMessage = false } }
    }

    private func updateSession(_ session: WorkSession, floatingAmount: Double? = nil, tips: Double? = nil, note: String? = nil) {
        if let index = sessionManager.workSessions.firstIndex(where: { $0.id == session.id }) {
            var updated = sessionManager.workSessions[index]
            if let v = floatingAmount { updated.floatingAmount = v }
            if let v = tips { updated.tips = v }
            if let v = note { updated.note = v }
            sessionManager.updateWorkSession(at: index, with: updated)
            scheduleSaveDayData()
        }
    }

    private func deleteItem(_ item: DisplayItem) {
        switch item {
        case .session(let session):
            if let index = sessionManager.workSessions.firstIndex(where: { $0.id == session.id }) {
                let req: NSFetchRequest<Income> = Income.fetchRequest()
                req.predicate = NSPredicate(format: "date == %@ AND type == %@", session.date as NSDate, session.workTypeName)
                if let results = try? viewContext.fetch(req) {
                    results.forEach { viewContext.delete($0) }
                    try? viewContext.save()
                }
                sessionManager.removeWorkSession(at: index)
                showMessage(NSLocalizedString("✓ Запись удалена", comment: "daily delete toast: entry deleted"))
            }
        case .planned(let planned):
            sessionManager.removePlannedShift(planned)
            showMessage(NSLocalizedString("✓ План удален", comment: "daily delete toast: plan deleted"))
        }
    }

    private func deleteExpense(_ expense: ExpenseItem) {
        withAnimation { expenses.removeAll { $0.id == expense.id } }
        HapticEngine.selection()
        SoundManager.shared.play(.tap)
        saveDayData()
        showMessage(NSLocalizedString("✓ Расход удален", comment: "daily expense toast: deleted"))
    }

    private func updateExpense(_ expense: ExpenseItem) {
        if let i = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[i] = expense
            HapticEngine.selection()
            SoundManager.shared.play(.tap)
            saveDayData()
            showMessage(NSLocalizedString("✓ Расход обновлен", comment: "daily expense toast: updated"))
        }
    }
}

private struct DayPopoverArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - DisplayCard
struct DisplayCard: View {
    let item: DisplayItem
    let settings: UserSettings
    let onUpdateFloating: (Double) -> Void
    let onUpdateTips: (Double) -> Void
    let onEdit: () -> Void

    @State private var floatingAmount: Double
    @State private var tips: Double

    init(item: DisplayItem, settings: UserSettings,
         onUpdateFloating: @escaping (Double) -> Void,
         onUpdateTips: @escaping (Double) -> Void,
         onEdit: @escaping () -> Void) {
        self.item = item; self.settings = settings
        self.onUpdateFloating = onUpdateFloating; self.onUpdateTips = onUpdateTips; self.onEdit = onEdit
        if case .session(let s) = item {
            _floatingAmount = State(initialValue: s.floatingAmount)
            _tips = State(initialValue: s.tips)
        } else {
            _floatingAmount = State(initialValue: 0); _tips = State(initialValue: 0)
        }
    }

    private var workTypeColor: Color? {
        guard !item.isPlanned, case .session(let s) = item,
              let wt = settings.workTypes.first(where: { $0.name == s.workTypeName })
        else { return nil }
        return Color(hex: wt.colorHex)
    }
    // STYLE: Градиент фона карточки смены, завязан на цвет типа работы.
    private var cardGradient: LinearGradient { AppColors.cardGradient(from: workTypeColor ?? AppColors.accent) }
    // STYLE: Цвет обводки карточки в том же тоне, что и градиент.
    private var cardBorderGradient: LinearGradient { AppColors.premiumStroke(from: workTypeColor ?? AppColors.accent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.icon)
                    .foregroundColor(item.isPlanned ? AppColors.secondaryText : AppColors.accent)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.workTypeName).font(.headline)
                        .foregroundColor(item.isPlanned ? AppColors.secondaryText : AppColors.text)
                    Text(item.timeRange).font(.caption).foregroundColor(AppColors.secondaryText)
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: item.isPlanned ? "calendar.badge.clock" : "pencil.circle")
                        .font(.title3)
                        .foregroundColor(item.isPlanned ? AppColors.secondaryText : AppColors.accent)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if !item.isPlanned, case .session(let session) = item {
                Divider()
                if session.hasHourlyRate {
                    HStack {
                        Text(NSLocalizedString("Часы:", comment: "session card hourly label: hours")).font(.caption).foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text(String(
                            format: NSLocalizedString("%.1f ч", comment: "session card hours format"),
                            session.calculatedHours
                        ))
                        .font(.subheadline)
                        .foregroundColor(AppColors.text)
                    }
                    HStack {
                        Text(NSLocalizedString("Ставка:", comment: "session card hourly label: rate")).font(.caption).foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text(String(
                            format: NSLocalizedString("%@/ч", comment: "session card hourly rate format"),
                            settings.formattedCurrency(session.hourlyRate)
                        ))
                        .font(.subheadline)
                        .foregroundColor(AppColors.accent)
                    }
                }
                if session.hasFixedRate {
                    HStack {
                        Text(NSLocalizedString("За смену:", comment: "session card fixed label: per shift")).font(.caption).foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text(settings.formattedCurrency(session.fixedAmount)).font(.subheadline).foregroundColor(AppColors.accent)
                    }
                }
                if session.hasFloatingRate {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NSLocalizedString("Заработок:", comment: "session card floating label: earnings")).font(.caption).foregroundColor(AppColors.secondaryText)
                        NumberField(
                            title: "",
                            value: $floatingAmount,
                            currency: settings.defaultCurrency,
                            onEditingEnd: { onUpdateFloating($0) }
                        )
                    }
                }
                if session.hasTips {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NSLocalizedString("Чаевые:", comment: "session card tips label")).font(.caption).foregroundColor(AppColors.secondaryText)
                        NumberField(
                            title: "",
                            value: $tips,
                            currency: settings.defaultCurrency,
                            onEditingEnd: { onUpdateTips($0) }
                        )
                    }
                }
                if let note = session.note, !note.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text").font(.caption2).foregroundColor(AppColors.accent)
                        Text(note).font(.caption).foregroundColor(AppColors.text).lineLimit(1)
                    }
                }
                Divider()
                HStack {
                    Text(NSLocalizedString("ИТОГО:", comment: "session card total label")).font(.caption).fontWeight(.medium).foregroundColor(AppColors.text)
                    Spacer()
                    Text(settings.formattedCurrency(session.totalEarning))
                        .foregroundColor(AppColors.positive).fontWeight(.bold)
                }
            } else if item.isPlanned, case .planned(let p) = item {
                Text(NSLocalizedString("Запланировано", comment: "planned session label")).font(.caption).foregroundColor(AppColors.secondaryText)
                if let note = p.note, !note.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text").font(.caption2).foregroundColor(AppColors.accent)
                        Text(note).font(.caption).foregroundColor(AppColors.text).lineLimit(1)
                    }
                }
            }
        }
        .padding()
        // STYLE: Слоистый фон карточки (glass + фирменный градиент + металлический отблеск).
        .background(ZStack {
            cardGradient.allowsHitTesting(false)
            AppColors.metallicSheen.opacity(0.4).allowsHitTesting(false)
        })
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .visionGlassCard(cornerRadius: 10, opacity: 0.84, showRing: true)
        // STYLE: Геометрия карточки: скругление и обводка.
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorderGradient, lineWidth: 1))
        // STYLE: Запланированные смены специально бледнее.
        .opacity(item.isPlanned ? 0.82 : 1.0)
    }
}

// MARK: - EditItemSheet
struct EditItemSheet: View {
    @Environment(\.presentationMode) var presentationMode
    let item: DisplayItem
    let settings: UserSettings
    let sessionManager: SessionManager
    let onSave: () -> Void
    let onDelete: () -> Void

    @State private var selectedWorkTypeName: String
    @State private var startHour: Int
    @State private var startMinute: Int
    @State private var endHour: Int
    @State private var endMinute: Int
    @State private var floatingAmount: Double
    @State private var tips: Double
    @State private var noteText: String
    @State private var validationAlert: ValidationAlertContext?

    private struct ShiftTypeSnapshot {
        let id: UUID
        let name: String
        let icon: String
        let hasHourlyRate: Bool
        let hasFixedRate: Bool
        let hasFloatingRate: Bool
        let hasTips: Bool
        let hourlyRate: Double
        let fixedRate: Double
    }

    private enum ValidationAlertKind {
        case invalidDuration
        case overlapWarning
    }

    private struct ValidationAlertContext: Identifiable {
        let id = UUID()
        let kind: ValidationAlertKind
        let title: String
        let message: String
    }

    init(
        item: DisplayItem,
        settings: UserSettings,
        sessionManager: SessionManager,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.settings = settings
        self.sessionManager = sessionManager
        self.onSave = onSave
        self.onDelete = onDelete
        _selectedWorkTypeName = State(initialValue: item.workTypeName)

        switch item {
        case .session(let session):
            _startHour = State(initialValue: session.startHour)
            _startMinute = State(initialValue: session.startMinute)
            _endHour = State(initialValue: session.endHour)
            _endMinute = State(initialValue: session.endMinute)
            _floatingAmount = State(initialValue: session.hasFixedRate ? session.fixedAmount : session.floatingAmount)
            _tips = State(initialValue: session.tips)
            _noteText = State(initialValue: session.note ?? "")
        case .planned(let planned):
            let calendar = Calendar.current
            _startHour = State(initialValue: calendar.component(.hour, from: planned.startTime))
            _startMinute = State(initialValue: calendar.component(.minute, from: planned.startTime))
            _endHour = State(initialValue: calendar.component(.hour, from: planned.endTime))
            _endMinute = State(initialValue: calendar.component(.minute, from: planned.endTime))
            _floatingAmount = State(initialValue: 0)
            _tips = State(initialValue: 0)
            _noteText = State(initialValue: planned.note ?? "")
        }
    }

    var body: some View {
        let shiftType = resolvedShiftType()

        return NavigationView {
            Form {
                Section(header: Text(NSLocalizedString("Смена", comment: "edit item section header: shift"))) {
                    Picker(NSLocalizedString("Тип", comment: "work type editor picker label: type"), selection: $selectedWorkTypeName) {
                        ForEach(availableWorkTypeNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(availableWorkTypeNames.count <= 1)

                    HStack(spacing: 10) {
                        Image(systemName: shiftType.icon)
                            .foregroundColor(AppColors.accent)
                        Text(shiftType.name)
                            .font(.headline)
                    }
                }

                Section(header: Text(NSLocalizedString("Время", comment: "edit item section header: time"))) {
                    timePicker(
                        label: NSLocalizedString("Начало", comment: "edit item time label: start"),
                        hour: $startHour,
                        minute: $startMinute
                    )
                    timePicker(
                        label: NSLocalizedString("Конец", comment: "edit item time label: end"),
                        hour: $endHour,
                        minute: $endMinute
                    )
                }

                if case .session = item {
                    if shiftType.hasHourlyRate {
                        Section(header: Text(NSLocalizedString("Почасовая оплата", comment: "edit item section header: hourly payment"))) {
                            HStack {
                                Text(NSLocalizedString("Часы", comment: "edit item sheet label: hours"))
                                Spacer()
                                Text(String(format: "%.1f", editedHours))
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text(NSLocalizedString("Ставка", comment: "edit item sheet label: rate"))
                                Spacer()
                                Text(settings.formattedCurrency(shiftType.hourlyRate))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if shiftType.hasFixedRate {
                        Section(header: Text(NSLocalizedString("Фиксированная оплата", comment: "edit item section header: fixed payment"))) {
                            NumberField(
                                title: NSLocalizedString("Сумма", comment: "edit item number field title: amount"),
                                value: $floatingAmount,
                                currency: settings.defaultCurrency
                            )
                        }
                    }

                    if shiftType.hasFloatingRate {
                        Section(header: Text(NSLocalizedString("Плавающий заработок", comment: "edit item section header: flexible earnings"))) {
                            NumberField(
                                title: NSLocalizedString("Заработок", comment: "edit item number field title: earnings"),
                                value: $floatingAmount,
                                currency: settings.defaultCurrency
                            )
                        }
                    }

                    if shiftType.hasTips {
                        Section(header: Text(NSLocalizedString("Чаевые", comment: "edit item section header: tips"))) {
                            NumberField(
                                title: NSLocalizedString("Чаевые", comment: "edit item number field title: tips"),
                                value: $tips,
                                currency: settings.defaultCurrency
                            )
                        }
                    }
                }

                Section(header: Text(NSLocalizedString("Заметка", comment: "edit item section header: note"))) {
                    TextField(
                        NSLocalizedString("Важная информация...", comment: "edit item sheet note placeholder"),
                        text: $noteText
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                Section {
                    Button(role: .destructive) {
                        onDelete()
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text(NSLocalizedString("Удалить", comment: "common delete action"))
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .visionFormBackground()
            .navigationTitle(NSLocalizedString("Редактировать", comment: "common edit screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Отмена", comment: "common cancel action")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(AppColors.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Сохранить", comment: "common save action")) {
                        validateAndSave()
                    }
                    .foregroundColor(AppColors.accent)
                }
            }
        }
        .accentColor(AppColors.accent)
        .onChange(of: selectedWorkTypeName) { _ in
            syncInputsWithSelectedType()
        }
        .alert(item: $validationAlert) { context in
            switch context.kind {
            case .invalidDuration:
                return Alert(
                    title: Text(context.title),
                    message: Text(context.message),
                    dismissButton: .default(Text(NSLocalizedString("Ок", comment: "common ok action")))
                )
            case .overlapWarning:
                return Alert(
                    title: Text(context.title),
                    message: Text(context.message),
                    primaryButton: .destructive(Text(NSLocalizedString("Сохранить", comment: "common save action"))) {
                        applyChangesAndDismiss()
                    },
                    secondaryButton: .cancel(Text(NSLocalizedString("Отмена", comment: "common cancel action")))
                )
            }
        }
    }

    private var availableWorkTypeNames: [String] {
        let activeNames = settings.workTypes
            .filter { $0.isActive }
            .map(\.name)

        if activeNames.isEmpty {
            return [selectedWorkTypeName]
        }
        if activeNames.contains(selectedWorkTypeName) {
            return activeNames
        }
        return [selectedWorkTypeName] + activeNames
    }

    private var editedHours: Double {
        let startTotal = startHour * 60 + startMinute
        let endTotal = endHour * 60 + endMinute
        var diff = endTotal - startTotal
        if diff < 0 { diff += 24 * 60 }
        return Double(diff) / 60.0
    }

    private var editedStartMinuteOfDay: Int {
        startHour * 60 + startMinute
    }

    private var editedEndMinuteOfDay: Int {
        endHour * 60 + endMinute
    }

    private var normalizedNote: String? {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolvedShiftType() -> ShiftTypeSnapshot {
        if let selected = settings.workTypes.first(where: { $0.name == selectedWorkTypeName }) {
            return ShiftTypeSnapshot(
                id: selected.id,
                name: selected.name,
                icon: selected.icon,
                hasHourlyRate: selected.hasHourlyRate,
                hasFixedRate: selected.hasFixedRate,
                hasFloatingRate: selected.hasFloatingRate,
                hasTips: selected.hasTips,
                hourlyRate: selected.hourlyRate,
                fixedRate: selected.fixedRate
            )
        }

        switch item {
        case .session(let session):
            return ShiftTypeSnapshot(
                id: session.workTypeId,
                name: session.workTypeName,
                icon: session.icon,
                hasHourlyRate: session.hasHourlyRate,
                hasFixedRate: session.hasFixedRate,
                hasFloatingRate: session.hasFloatingRate,
                hasTips: session.hasTips,
                hourlyRate: session.hourlyRate,
                fixedRate: session.fixedAmount
            )
        case .planned(let planned):
            return ShiftTypeSnapshot(
                id: planned.workTypeId,
                name: planned.workTypeName,
                icon: planned.icon,
                hasHourlyRate: planned.hourlyRate > 0,
                hasFixedRate: false,
                hasFloatingRate: false,
                hasTips: planned.hasTips,
                hourlyRate: planned.hourlyRate,
                fixedRate: 0
            )
        }
    }

    private func syncInputsWithSelectedType() {
        let shiftType = resolvedShiftType()
        if shiftType.hasFixedRate {
            floatingAmount = shiftType.fixedRate
        } else if !shiftType.hasFloatingRate {
            floatingAmount = 0
        }
        if !shiftType.hasTips {
            tips = 0
        }
    }

    private func validateAndSave() {
        if editedStartMinuteOfDay == editedEndMinuteOfDay {
            validationAlert = ValidationAlertContext(
                kind: .invalidDuration,
                title: NSLocalizedString("Проверьте время смены", comment: "edit shift validation title: invalid duration"),
                message: NSLocalizedString("Длительность смены не может быть 0 часов. Измените время начала или окончания.", comment: "edit shift validation message: invalid duration")
            )
            return
        }

        if let overlapMessage = overlapWarningMessage() {
            validationAlert = ValidationAlertContext(
                kind: .overlapWarning,
                title: NSLocalizedString("Есть пересечения по времени", comment: "edit shift validation title: overlaps"),
                message: overlapMessage
            )
            return
        }

        applyChangesAndDismiss()
    }

    private func applyChangesAndDismiss() {
        applyChanges()
        presentationMode.wrappedValue.dismiss()
    }

    private func overlapWarningMessage() -> String? {
        let calendar = Calendar.current
        let day = editedItemDate
        let newStart = editedStartMinuteOfDay
        let newEnd = editedEndMinuteOfDay

        var conflicts: [String] = []

        for session in sessionManager.workSessions {
            guard calendar.isDate(session.date, inSameDayAs: day) else { continue }
            if case .session(let current) = item, current.id == session.id { continue }

            let sessionStart = session.startHour * 60 + session.startMinute
            let sessionEnd = session.endHour * 60 + session.endMinute
            guard intervalsOverlap(startA: newStart, endA: newEnd, startB: sessionStart, endB: sessionEnd) else { continue }
            conflicts.append("\(session.workTypeName) \(formattedTimeRange(startMinute: sessionStart, endMinute: sessionEnd))")
        }

        for planned in sessionManager.plannedShifts {
            guard calendar.isDate(planned.date, inSameDayAs: day) else { continue }
            if case .planned(let current) = item, current.id == planned.id { continue }

            let compsStart = calendar.dateComponents([.hour, .minute], from: planned.startTime)
            let compsEnd = calendar.dateComponents([.hour, .minute], from: planned.endTime)
            let plannedStart = (compsStart.hour ?? 0) * 60 + (compsStart.minute ?? 0)
            let plannedEnd = (compsEnd.hour ?? 0) * 60 + (compsEnd.minute ?? 0)
            guard intervalsOverlap(startA: newStart, endA: newEnd, startB: plannedStart, endB: plannedEnd) else { continue }
            conflicts.append("\(planned.workTypeName) \(formattedTimeRange(startMinute: plannedStart, endMinute: plannedEnd))")
        }

        guard !conflicts.isEmpty else { return nil }

        let shownConflicts = conflicts.prefix(3).map { "• \($0)" }.joined(separator: "\n")
        let hasMore = conflicts.count > 3
            ? String(
                format: NSLocalizedString("и ещё %d", comment: "edit shift overlaps more items"),
                conflicts.count - 3
            )
            : ""
        let suffix = hasMore.isEmpty ? "" : "\n\(hasMore)"
        return "\(NSLocalizedString("Эта смена пересекается с другими сменами в этот день:", comment: "edit shift overlap warning intro"))\n\(shownConflicts)\(suffix)\n\n\(NSLocalizedString("Сохранить изменения всё равно?", comment: "edit shift overlap warning question"))"
    }

    private var editedItemDate: Date {
        switch item {
        case .session(let session):
            return session.date
        case .planned(let planned):
            return planned.date
        }
    }

    private func formattedTimeRange(startMinute: Int, endMinute: Int) -> String {
        "\(formattedMinute(startMinute))-\(formattedMinute(endMinute))"
    }

    private func formattedMinute(_ minuteOfDay: Int) -> String {
        let normalized = (minuteOfDay % (24 * 60) + (24 * 60)) % (24 * 60)
        let hour = normalized / 60
        let minute = normalized % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private func intervalsOverlap(startA: Int, endA: Int, startB: Int, endB: Int) -> Bool {
        let segmentsA = minuteSegments(start: startA, end: endA)
        let segmentsB = minuteSegments(start: startB, end: endB)

        for segmentA in segmentsA {
            for segmentB in segmentsB {
                if max(segmentA.start, segmentB.start) < min(segmentA.end, segmentB.end) {
                    return true
                }
            }
        }
        return false
    }

    private func minuteSegments(start: Int, end: Int) -> [(start: Int, end: Int)] {
        let dayMinutes = 24 * 60
        let normalizedStart = (start % dayMinutes + dayMinutes) % dayMinutes
        let normalizedEnd = (end % dayMinutes + dayMinutes) % dayMinutes

        if normalizedStart == normalizedEnd {
            return []
        }
        if normalizedEnd > normalizedStart {
            return [(normalizedStart, normalizedEnd)]
        }
        return [(normalizedStart, dayMinutes), (0, normalizedEnd)]
    }

    @ViewBuilder
    private func timePicker(label: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            DatePicker(
                "",
                selection: timeBinding(hour: hour, minute: minute),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .clipped()
            .visionGlassCard(cornerRadius: 12, opacity: 0.72)
        }
    }

    private func timeBinding(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                var comps = DateComponents()
                comps.hour = hour.wrappedValue
                comps.minute = minute.wrappedValue
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                hour.wrappedValue = comps.hour ?? 0
                minute.wrappedValue = comps.minute ?? 0
            }
        )
    }

    private func applyChanges() {
        let shiftType = resolvedShiftType()

        switch item {
        case .session(let session):
            guard let index = sessionManager.workSessions.firstIndex(where: { $0.id == session.id }) else { return }

            var updated = sessionManager.workSessions[index]
            updated.workTypeId = shiftType.id
            updated.workTypeName = shiftType.name
            updated.icon = shiftType.icon
            updated.hasHourlyRate = shiftType.hasHourlyRate
            updated.hasFixedRate = shiftType.hasFixedRate
            updated.hasFloatingRate = shiftType.hasFloatingRate
            updated.hasTips = shiftType.hasTips
            updated.startHour = startHour
            updated.startMinute = startMinute
            updated.endHour = endHour
            updated.endMinute = endMinute
            updated.hourlyRate = shiftType.hasHourlyRate ? shiftType.hourlyRate : 0

            if shiftType.hasFixedRate {
                updated.fixedAmount = floatingAmount
                updated.floatingAmount = 0
            } else if shiftType.hasFloatingRate {
                updated.floatingAmount = floatingAmount
                updated.fixedAmount = 0
            } else {
                updated.fixedAmount = 0
                updated.floatingAmount = 0
            }

            updated.tips = shiftType.hasTips ? tips : 0
            updated.note = normalizedNote

            sessionManager.updateWorkSession(at: index, with: updated)
            onSave()

        case .planned(let planned):
            sessionManager.removePlannedShift(planned)

            let calendar = Calendar.current
            var comps = calendar.dateComponents([.year, .month, .day], from: planned.date)
            comps.hour = startHour
            comps.minute = startMinute
            let newStart = calendar.date(from: comps) ?? planned.startTime

            comps.hour = endHour
            comps.minute = endMinute
            let newEnd = calendar.date(from: comps) ?? planned.endTime

            sessionManager.addPlannedShift(
                PlannedShift(
                    date: planned.date,
                    workTypeId: shiftType.id,
                    workTypeName: shiftType.name,
                    icon: shiftType.icon,
                    startTime: newStart,
                    endTime: newEnd,
                    hourlyRate: shiftType.hourlyRate,
                    hasTips: shiftType.hasTips,
                    note: normalizedNote
                )
            )
            onSave()
        }
    }
}

// MARK: - SimpleCalendarView
struct SimpleCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var visibleMonthDate: Date
    let plannedShifts: [PlannedShift]
    let allSessions: [WorkSession]
    let onSelectDate: (Date) -> Void
    let colorForWorkType: (String) -> Color
    @Environment(\.colorScheme) private var colorScheme

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let staticMonthsWindow = 120
    @State private var monthAnchor = Date()
    @State private var lastScrolledMonth: Date?
    @State private var scrollPositionMonth: Date?

    private struct CalendarCell: Identifiable {
        let id: Int
        let date: Date?
    }

    private struct CalendarEvent: Identifiable {
        let id: String
        let time: String
        let color: Color
    }

    private var localizedWeekdays: [String] {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale()
        var symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        if symbols.count == 7 {
            let sunday = symbols.removeFirst()
            symbols.append(sunday)
        }
        return symbols.map { $0.replacingOccurrences(of: ".", with: "") }
    }

    private func startOfMonth(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func calendarCells(for monthStart: Date) -> [CalendarCell] {
        let wd = calendar.component(.weekday, from: monthStart)
        let firstWeekdayOffset = wd == 1 ? 6 : wd - 2
        guard let daysRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }
        let daysInMonth = daysRange.count
        let slots = firstWeekdayOffset + daysInMonth
        let rowCount = Int(ceil(Double(slots) / 7.0))
        let cellCount = rowCount * 7

        return (0..<cellCount).map { index in
            let dayNumber = index - firstWeekdayOffset + 1
            guard dayNumber >= 1 && dayNumber <= daysInMonth else {
                return CalendarCell(id: index, date: nil)
            }
            var components = calendar.dateComponents([.year, .month], from: monthStart)
            components.day = dayNumber
            let date = calendar.date(from: components)
            return CalendarCell(id: index, date: date)
        }
    }

    private var eventsByDate: [Date: [CalendarEvent]] {
        var events: [Date: [CalendarEvent]] = [:]

        for session in allSessions {
            let day = calendar.startOfDay(for: session.date)
            let time = String(format: "%02d:%02d", session.startHour, session.startMinute)
            let event = CalendarEvent(
                id: "\(day.timeIntervalSince1970)-session-\(session.id.uuidString)",
                time: time,
                color: colorForWorkType(session.workTypeName)
            )
            events[day, default: []].append(event)
        }

        for planned in plannedShifts {
            let day = calendar.startOfDay(for: planned.date)
            let comps = calendar.dateComponents([.hour, .minute], from: planned.startTime)
            let time = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
            let event = CalendarEvent(
                id: "\(day.timeIntervalSince1970)-planned-\(planned.id.uuidString)",
                time: time,
                color: colorForWorkType(planned.workTypeName).opacity(0.78)
            )
            events[day, default: []].append(event)
        }

        return events.mapValues { items in
            items.sorted { $0.time < $1.time }
        }
    }

    private var visibleMonthStarts: [Date] {
        (-staticMonthsWindow...staticMonthsWindow).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: monthAnchor).map(startOfMonth(for:))
        }
    }

    @ViewBuilder
    private func monthGrid(
        monthStart: Date,
        cellHeight: CGFloat,
        eventsLookup: [Date: [CalendarEvent]]
    ) -> some View {
        let monthCells = calendarCells(for: monthStart)
        let gridFill = colorScheme == .dark
            ? AppColors.surface.opacity(0.34)
            : Color(red: 0.52, green: 0.62, blue: 0.74).opacity(0.34)
        let gridStroke = colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.24)

        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(monthCells) { cell in
                    if let date = cell.date {
                        let dayStart = calendar.startOfDay(for: date)
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        let isToday = calendar.isDateInToday(date)
                        let events = eventsLookup[dayStart] ?? []

                        Button {
                            selectedDate = date
                            onSelectDate(date)
                        } label: {
                            ZStack(alignment: .top) {
                                Rectangle()
                                    .fill(gridFill)

                                if isSelected {
                                    Rectangle()
                                        .fill(AppColors.accent.opacity(colorScheme == .dark ? 0.62 : 0.76))
                                }

                                VStack(spacing: 5) {
                                    Text("\(calendar.component(.day, from: date))")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(
                                            isSelected ? .white :
                                            isToday ? AppColors.accent : AppColors.text
                                        )
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.top, 10)

                                    HStack(spacing: 3) {
                                        ForEach(Array(events.prefix(3).indices), id: \.self) { index in
                                            Circle()
                                                .fill(events[index].color.opacity(isSelected ? 0.95 : 0.82))
                                                .frame(width: 5, height: 5)
                                        }
                                        if events.count > 3 {
                                            Text(String(format: NSLocalizedString("+%d", comment: "daily calendar extra events count"), events.count - 3))
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(isSelected ? .white.opacity(0.92) : AppColors.secondaryText)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)

                                    Spacer(minLength: 4)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: cellHeight)
                            .overlay(
                                Rectangle()
                                    .stroke(gridStroke, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Rectangle()
                            .fill(gridFill)
                            .frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: cellHeight)
                            .overlay(
                                Rectangle()
                                    .stroke(gridStroke, lineWidth: 0.5)
                            )
                    }
                }
            }
        }
        .background(gridFill)
    }

    var body: some View {
        GeometryReader { proxy in
            let weekdayHeaderHeight: CGFloat = 56
            // STYLE: В видимой зоне помещается ровно 42 ячейки (6x7): растягиваем высоту дня от доступной высоты.
            let scrollTopInset: CGFloat = 0
            let scrollBottomInset: CGFloat = 0
            let availableForMonth = max(
                360,
                proxy.size.height - weekdayHeaderHeight - scrollTopInset - scrollBottomInset
            )
            let cellHeight = max(
                56,
                floor(availableForMonth / 6.0)
            )
            let eventsLookup = eventsByDate
            let headerFill = colorScheme == .dark
                ? AppColors.surface.opacity(0.78)
                : Color.white.opacity(0.90)
            let headerStroke = colorScheme == .dark
                ? Color.white.opacity(0.16)
                : Color.black.opacity(0.24)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(localizedWeekdays.enumerated()), id: \.offset) { index, day in
                        ZStack {
                            Rectangle()
                                .fill(headerFill)

                            Text(day)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(AppColors.text.opacity(0.86))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: weekdayHeaderHeight)
                        .overlay(
                            Rectangle()
                                .stroke(headerStroke, lineWidth: 0.5)
                        )
                    }
                }

                ScrollViewReader { reader in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleMonthStarts, id: \.self) { monthStart in
                                monthGrid(monthStart: monthStart, cellHeight: cellHeight, eventsLookup: eventsLookup)
                                    .id(monthStart)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.top, scrollTopInset)
                        .padding(.bottom, scrollBottomInset)
                    }
                    // STYLE: Привязка прокрутки к началу месяца — при отпускании скролл останавливается на ближайшем месяце.
                    .scrollTargetBehavior(.viewAligned)
                    .onAppear {
                        let selectedMonth = startOfMonth(for: selectedDate)
                        monthAnchor = selectedMonth
                        visibleMonthDate = selectedMonth
                        scrollPositionMonth = selectedMonth
                        guard lastScrolledMonth == nil else { return }
                        lastScrolledMonth = selectedMonth
                        DispatchQueue.main.async {
                            reader.scrollTo(selectedMonth, anchor: .top)
                        }
                    }
                    .onChange(of: selectedDate) { newValue in
                        let selectedMonth = startOfMonth(for: newValue)
                        if !visibleMonthStarts.contains(selectedMonth) {
                            monthAnchor = selectedMonth
                        }
                        guard selectedMonth != lastScrolledMonth else { return }
                        lastScrolledMonth = selectedMonth
                        visibleMonthDate = selectedMonth
                        scrollPositionMonth = selectedMonth
                        DispatchQueue.main.async {
                            performUIUpdate(.easeInOut(duration: 0.22)) {
                                reader.scrollTo(selectedMonth, anchor: .top)
                            }
                        }
                    }
                    .onChange(of: scrollPositionMonth) { newMonth in
                        guard let newMonth else { return }
                        guard newMonth != lastScrolledMonth else { return }
                        lastScrolledMonth = newMonth
                        visibleMonthDate = newMonth
                    }
                    .scrollPosition(id: $scrollPositionMonth, anchor: .top)
                }
            }
            // STYLE: Единая внешняя форма календаря.
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
            )
        }
    }
}

// MARK: - ExpenseCard
struct ExpenseCard: View {
    let expense: ExpenseItem; let settings: UserSettings
    let onEdit: () -> Void; let onDelete: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "creditcard").font(.caption).foregroundColor(AppColors.negative)
                Text(expense.category).font(.caption).fontWeight(.medium).foregroundColor(AppColors.text)
                Text(settings.formattedCurrency(-expense.amount)).font(.caption).fontWeight(.semibold).foregroundColor(AppColors.negative)
                Spacer(minLength: 6)
            }
            .contentShape(Rectangle()).onTapGesture { onEdit() }
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain).contentShape(Rectangle())
        }
        // STYLE: Компактный размер и ритм карточки расхода.
        .padding(.horizontal, 12).padding(.vertical, 8)
        // STYLE: Нейтральный фон + красный градиентный акцент для расхода.
        .visionGlassCard(cornerRadius: 8, opacity: 0.82, showRing: true)
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 1).allowsHitTesting(false) }
    }
}

// MARK: - AddWorkSheet
struct AddWorkSheet: View {
    @Environment(\.presentationMode) var presentationMode
    let ai: AIEngine
    let sessionManager: SessionManager; let settings: UserSettings
    let selectedDate: Date; let isFuture: Bool; let onAdd: () -> Void
    @State private var showWorkTypeEditor = false
    @State private var editorMode: WorkTypeEditorMode = .create
    @State private var addShiftAlert: AddShiftAlertContext?
    @State private var pendingWorkTypeForAdd: WorkType?

    private enum AddShiftAlertKind {
        case invalidDuration
        case overlapWarning
    }

    private struct AddShiftAlertContext: Identifiable {
        let id = UUID()
        let kind: AddShiftAlertKind
        let title: String
        let message: String
    }

    var body: some View {
        NavigationView {
            List {
                let activeWorkTypes = settings.workTypes.enumerated().filter { $0.element.isActive }
                if activeWorkTypes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "briefcase")
                            .font(.title2)
                            .foregroundColor(AppColors.secondaryText)
                        Text(NSLocalizedString("Нет активных типов смен", comment: "add shift empty state title"))
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)
                        Text(NSLocalizedString("Нажмите +, чтобы добавить новый тип", comment: "add shift empty state subtitle"))
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(activeWorkTypes, id: \.element.id) { wt in
                        workTypeRow(wt.element)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    editorMode = .edit(index: wt.offset)
                                    showWorkTypeEditor = true
                                } label: {
                                    Label(NSLocalizedString("Редактировать", comment: "common edit action"), systemImage: "pencil")
                                }
                                .tint(AppColors.accent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    archiveWorkType(at: wt.offset)
                                } label: {
                                    Label(NSLocalizedString("Удалить", comment: "common delete action"), systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle(
                isFuture
                    ? NSLocalizedString("Новый план", comment: "add work sheet title: new plan")
                    : NSLocalizedString("Новая смена", comment: "add work sheet title: new shift")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        editorMode = .create
                        showWorkTypeEditor = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(AppColors.accent)
                    .accessibilityLabel(NSLocalizedString("Добавить тип смены", comment: "add work accessibility label: add shift type"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Закрыть", comment: "common close action")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                        .foregroundColor(AppColors.accent)
                }
            }
        }
        .sheet(isPresented: $showWorkTypeEditor) {
            WorkTypeEditorSheet(settings: settings, mode: editorMode)
        }
        .alert(item: $addShiftAlert) { context in
            switch context.kind {
            case .invalidDuration:
                return Alert(
                    title: Text(context.title),
                    message: Text(context.message),
                    dismissButton: .default(Text(NSLocalizedString("Ок", comment: "common ok action")))
                )
            case .overlapWarning:
                return Alert(
                    title: Text(context.title),
                    message: Text(context.message),
                    primaryButton: .destructive(Text(NSLocalizedString("Сохранить", comment: "common save action"))) {
                        if let pendingWorkTypeForAdd {
                            commitAddShift(pendingWorkTypeForAdd)
                        }
                    },
                    secondaryButton: .cancel(Text(NSLocalizedString("Отмена", comment: "common cancel action")))
                )
            }
        }
        .accentColor(AppColors.accent)
    }

    @ViewBuilder
    private func workTypeRow(_ wt: WorkType) -> some View {
        Button(action: { validateAndAddShift(wt) }) {
            HStack(spacing: 12) {
                workTypeIcon(wt)
                workTypeInfo(wt)
                Spacer()
                Image(systemName: "plus.circle").foregroundColor(AppColors.accent)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func workTypeIcon(_ wt: WorkType) -> some View {
        let color = Color(hex: wt.colorHex) ?? AppColors.accent
        ZStack {
            Circle().fill(color.opacity(0.18)).frame(width: 38, height: 38)
            Image(systemName: wt.icon).font(.system(size: 16, weight: .semibold)).foregroundColor(color)
        }
    }

    @ViewBuilder
    private func workTypeInfo(_ wt: WorkType) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(wt.name).font(.headline).foregroundColor(AppColors.text)
            workTypeForecast(wt)
        }
    }

    @ViewBuilder
    private func workTypeForecast(_ wt: WorkType) -> some View {
        let weekday = Calendar.current.component(.weekday, from: selectedDate)
        let weekdayMon = weekday == 1 ? 7 : weekday - 1
        let hours = defaultShiftHours(for: wt)
        let locationManager = DeviceLocationManager.shared
        let locationCity = locationManager.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let weatherCity = locationCity.isEmpty ? settings.proWeatherCity : locationCity
        let fc = ai.forecastShift(workTypeName: wt.name, weekday: weekdayMon,
                                   startHour: wt.startHour,
                                   durationHours: max(hours, 1),
                                   date: selectedDate,
                                   considerExternalFactors: ProManager.shared.canUse(.externalFactors),
                                   weatherCity: weatherCity,
                                   weatherCoordinates: locationManager.coordinate,
                                   allowLiveWeather: settings.proUseLiveWeather,
                                   holidayRegionCode: settings.proHolidayRegionCode)
        if let fc = fc {
            let perWT = ai.perWorkTypeForecast[wt.name]
            let isLowData = (perWT?.basedOn ?? 0) < 5
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 9))
                    .foregroundColor(isLowData ? AppColors.secondaryText : AppColors.accent)
                if isLowData {
                    Text(
                        String(
                            format: NSLocalizedString("~%@ · мало данных", comment: "work type forecast low data"),
                            settings.formattedCurrency(fc.predicted)
                        )
                    )
                        .font(.system(size: 11)).foregroundColor(AppColors.secondaryText)
                } else {
                    Text(
                        String(
                            format: NSLocalizedString("~%@ · %d%% выше ср.", comment: "work type forecast above average"),
                            settings.formattedCurrency(fc.predicted),
                            Int(fc.probHigh * 100)
                        )
                    )
                        .font(.system(size: 11)).foregroundColor(AppColors.accent)
                }
            }
        } else if let baseline = baselineEstimate(for: wt) {
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 9))
                    .foregroundColor(AppColors.secondaryText)
                Text(
                    String(
                        format: NSLocalizedString("~%@ · базовая оценка", comment: "work type forecast baseline"),
                        settings.formattedCurrency(baseline)
                    )
                )
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText)
            }
        } else if (ai.perWorkTypeForecast[wt.name]?.basedOn ?? 0) > 0 {
            Text(NSLocalizedString("Мало данных для прогноза", comment: "work type forecast: not enough data"))
                .font(.system(size: 11))
                .foregroundColor(AppColors.secondaryText)
        } else {
            Text(NSLocalizedString("Прогноз появится после 2 смен", comment: "work type forecast: appears after 2 shifts"))
                .font(.system(size: 11))
                .foregroundColor(AppColors.secondaryText)
        }
    }

    private func defaultShiftHours(for wt: WorkType) -> Double {
        let start = wt.startHour * 60 + wt.startMinute
        let end = wt.endHour * 60 + wt.endMinute
        var diff = end - start
        if diff <= 0 { diff += 24 * 60 }
        return max(Double(diff) / 60.0, 1)
    }

    private func baselineEstimate(for wt: WorkType) -> Double? {
        let hours = defaultShiftHours(for: wt)
        var amount = 0.0
        if wt.hasHourlyRate {
            amount += wt.hourlyRate * hours
        }
        if wt.hasFixedRate {
            amount += wt.fixedRate
        }
        // Для плавающего типа без истории нет надёжной базовой оценки.
        return amount > 0 ? amount : nil
    }

    private func validateAndAddShift(_ wt: WorkType) {
        pendingWorkTypeForAdd = wt

        let newStart = wt.startHour * 60 + wt.startMinute
        let newEnd = wt.endHour * 60 + wt.endMinute
        if newStart == newEnd {
            addShiftAlert = AddShiftAlertContext(
                kind: .invalidDuration,
                title: NSLocalizedString("Проверьте время смены", comment: "add shift validation title: invalid duration"),
                message: NSLocalizedString("У выбранного типа смены длительность равна 0 часов. Отредактируйте тип смены.", comment: "add shift validation message: invalid duration")
            )
            return
        }

        if let overlapMessage = overlapWarningMessage(forStartMinute: newStart, endMinute: newEnd) {
            addShiftAlert = AddShiftAlertContext(
                kind: .overlapWarning,
                title: NSLocalizedString("Есть пересечения по времени", comment: "add shift validation title: overlaps"),
                message: overlapMessage
            )
            return
        }

        commitAddShift(wt)
    }

    private func commitAddShift(_ wt: WorkType) {
        pendingWorkTypeForAdd = nil
        if isFuture {
            let cal = Calendar.current
            let start = cal.date(bySettingHour: wt.startHour, minute: wt.startMinute, second: 0, of: selectedDate) ?? selectedDate
            let end   = cal.date(bySettingHour: wt.endHour,   minute: wt.endMinute,   second: 0, of: selectedDate) ?? selectedDate
            sessionManager.addPlannedShift(PlannedShift(
                date: selectedDate, workTypeId: wt.id, workTypeName: wt.name,
                icon: wt.icon, startTime: start, endTime: end,
                hourlyRate: wt.hourlyRate, hasTips: wt.hasTips, note: nil))
        } else {
            sessionManager.addWorkSession(WorkSession(workType: wt, date: selectedDate))
        }
        HapticEngine.impact(.light); onAdd(); presentationMode.wrappedValue.dismiss()
    }

    private func overlapWarningMessage(forStartMinute newStart: Int, endMinute newEnd: Int) -> String? {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: selectedDate)

        var conflicts: [String] = []

        for session in sessionManager.workSessions {
            guard calendar.isDate(session.date, inSameDayAs: day) else { continue }
            let existingStart = session.startHour * 60 + session.startMinute
            let existingEnd = session.endHour * 60 + session.endMinute
            guard intervalsOverlap(startA: newStart, endA: newEnd, startB: existingStart, endB: existingEnd) else { continue }
            conflicts.append("\(session.workTypeName) \(formattedTimeRange(startMinute: existingStart, endMinute: existingEnd))")
        }

        for planned in sessionManager.plannedShifts {
            guard calendar.isDate(planned.date, inSameDayAs: day) else { continue }
            let startComps = calendar.dateComponents([.hour, .minute], from: planned.startTime)
            let endComps = calendar.dateComponents([.hour, .minute], from: planned.endTime)
            let existingStart = (startComps.hour ?? 0) * 60 + (startComps.minute ?? 0)
            let existingEnd = (endComps.hour ?? 0) * 60 + (endComps.minute ?? 0)
            guard intervalsOverlap(startA: newStart, endA: newEnd, startB: existingStart, endB: existingEnd) else { continue }
            conflicts.append("\(planned.workTypeName) \(formattedTimeRange(startMinute: existingStart, endMinute: existingEnd))")
        }

        guard !conflicts.isEmpty else { return nil }

        let shownConflicts = conflicts.prefix(3).map { "• \($0)" }.joined(separator: "\n")
        let moreLine = conflicts.count > 3
            ? "\n\(String(format: NSLocalizedString("и ещё %d", comment: "add shift overlaps more items"), conflicts.count - 3))"
            : ""
        return "\(NSLocalizedString("Эта смена пересекается с другими сменами в этот день:", comment: "add shift overlap warning intro"))\n\(shownConflicts)\(moreLine)\n\n\(NSLocalizedString("Сохранить смену всё равно?", comment: "add shift overlap warning question"))"
    }

    private func formattedTimeRange(startMinute: Int, endMinute: Int) -> String {
        "\(formattedMinute(startMinute))-\(formattedMinute(endMinute))"
    }

    private func formattedMinute(_ minuteOfDay: Int) -> String {
        let normalized = (minuteOfDay % (24 * 60) + (24 * 60)) % (24 * 60)
        let hour = normalized / 60
        let minute = normalized % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private func intervalsOverlap(startA: Int, endA: Int, startB: Int, endB: Int) -> Bool {
        let segmentsA = minuteSegments(start: startA, end: endA)
        let segmentsB = minuteSegments(start: startB, end: endB)

        for segmentA in segmentsA {
            for segmentB in segmentsB {
                if max(segmentA.start, segmentB.start) < min(segmentA.end, segmentB.end) {
                    return true
                }
            }
        }
        return false
    }

    private func minuteSegments(start: Int, end: Int) -> [(start: Int, end: Int)] {
        let dayMinutes = 24 * 60
        let normalizedStart = (start % dayMinutes + dayMinutes) % dayMinutes
        let normalizedEnd = (end % dayMinutes + dayMinutes) % dayMinutes

        if normalizedStart == normalizedEnd {
            return []
        }
        if normalizedEnd > normalizedStart {
            return [(normalizedStart, normalizedEnd)]
        }
        return [(normalizedStart, dayMinutes), (0, normalizedEnd)]
    }

    private func archiveWorkType(at index: Int) {
        guard settings.workTypes.indices.contains(index) else { return }
        settings.workTypes.remove(at: index)
        settings.saveSettings()
        HapticManager.shared.selection()
        SoundManager.shared.play(.tap)
    }
}

enum WorkTypeEditorMode {
    case create
    case edit(index: Int)
}

enum WorkTypePaymentMode: String, CaseIterable {
    case hourly
    case fixed
    case floating

    var title: String {
        switch self {
        case .hourly:
            return NSLocalizedString("Почасовая", comment: "work type payment mode: hourly")
        case .fixed:
            return NSLocalizedString("Фикс", comment: "work type payment mode: fixed")
        case .floating:
            return NSLocalizedString("Свободная", comment: "work type payment mode: floating")
        }
    }
}

struct WorkTypeManagerSheet: View {
    @ObservedObject var settings: UserSettings
    @Environment(\.presentationMode) private var presentationMode
    @State private var editorMode: WorkTypeEditorMode = .create
    @State private var showEditor = false

    private var indexedWorkTypes: [(index: Int, workType: WorkType)] {
        settings.workTypes.enumerated().map { (index: $0.offset, workType: $0.element) }
            .sorted { $0.workType.name.localizedCaseInsensitiveCompare($1.workType.name) == .orderedAscending }
    }

    var body: some View {
        NavigationView {
            List {
                if indexedWorkTypes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .foregroundColor(AppColors.secondaryText)
                        Text(NSLocalizedString("Пока нет типов смен", comment: "work type manager empty state title"))
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(indexedWorkTypes, id: \.workType.id) { item in
                        Button(action: {
                            editorMode = .edit(index: item.index)
                            showEditor = true
                        }) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill((Color(hex: item.workType.colorHex) ?? AppColors.accent).opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Image(systemName: item.workType.icon)
                                            .foregroundColor(Color(hex: item.workType.colorHex) ?? AppColors.accent)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.workType.name)
                                        .font(.headline)
                                        .foregroundColor(AppColors.text)
                                    Text(rateDescription(for: item.workType))
                                        .font(.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                }

                                Spacer()

                                if !item.workType.isActive {
                                    Text(NSLocalizedString("Неактивна", comment: "work type status inactive"))
                                        .font(.caption2)
                                        .foregroundColor(AppColors.secondaryText)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppColors.border.opacity(0.35))
                                        .cornerRadius(8)
                                }

                                Image(systemName: "pencil")
                                    .foregroundColor(AppColors.accent)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Типы смен", comment: "work type manager title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        editorMode = .create
                        showEditor = true
                    }) {
                        Image(systemName: "plus")
                    }
                    .foregroundColor(AppColors.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Закрыть", comment: "common close action")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                        .foregroundColor(AppColors.accent)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            WorkTypeEditorSheet(settings: settings, mode: editorMode)
        }
    }

    private func rateDescription(for wt: WorkType) -> String {
        if wt.hasHourlyRate {
            return String(
                format: NSLocalizedString("%@/ч", comment: "work type row hourly rate format"),
                settings.formattedCurrency(wt.hourlyRate)
            )
        }
        if wt.hasFixedRate {
            return settings.formattedCurrency(wt.fixedRate)
        }
        return NSLocalizedString("Свободная сумма", comment: "work type rate description: floating amount")
    }
}

struct WorkTypeEditorSheet: View {
    @ObservedObject var settings: UserSettings
    let mode: WorkTypeEditorMode

    @Environment(\.presentationMode) private var presentationMode

    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColorHex: String
    @State private var paymentMode: WorkTypePaymentMode
    @State private var rateValue: Double
    @State private var hasTips: Bool
    @State private var isActive: Bool
    @State private var startHour: Int
    @State private var startMinute: Int
    @State private var endHour: Int
    @State private var endMinute: Int
    @State private var showValidationAlert = false
    @State private var validationMessage = ""

    private let iconOptions: [String] = [
        "wineglass", "bicycle", "car", "bus", "fork.knife", "house", "briefcase",
        "cart", "wrench.and.screwdriver", "hammer", "bag", "figure.walk"
    ]

    init(settings: UserSettings, mode: WorkTypeEditorMode) {
        self.settings = settings
        self.mode = mode

        if case .edit(let index) = mode, settings.workTypes.indices.contains(index) {
            let wt = settings.workTypes[index]
            _name = State(initialValue: wt.name)
            _selectedIcon = State(initialValue: wt.icon)
            _selectedColorHex = State(initialValue: wt.colorHex)
            if wt.hasHourlyRate {
                _paymentMode = State(initialValue: .hourly)
                _rateValue = State(initialValue: wt.hourlyRate)
            } else if wt.hasFixedRate {
                _paymentMode = State(initialValue: .fixed)
                _rateValue = State(initialValue: wt.fixedRate)
            } else {
                _paymentMode = State(initialValue: .floating)
                _rateValue = State(initialValue: 0)
            }
            _hasTips = State(initialValue: wt.hasTips)
            _isActive = State(initialValue: wt.isActive)
            _startHour = State(initialValue: wt.startHour)
            _startMinute = State(initialValue: wt.startMinute)
            _endHour = State(initialValue: wt.endHour)
            _endMinute = State(initialValue: wt.endMinute)
        } else {
            let fallbackColor = settings.lightColors.first ?? "#5E5CE6"
            _name = State(initialValue: "")
            _selectedIcon = State(initialValue: "briefcase")
            _selectedColorHex = State(initialValue: fallbackColor)
            _paymentMode = State(initialValue: .hourly)
            _rateValue = State(initialValue: 0)
            _hasTips = State(initialValue: false)
            _isActive = State(initialValue: true)
            _startHour = State(initialValue: 9)
            _startMinute = State(initialValue: 0)
            _endHour = State(initialValue: 17)
            _endMinute = State(initialValue: 0)
        }
    }

    private var availableColors: [String] {
        switch settings.colorTheme {
        case .light:
            return settings.lightColors
        case .dark:
            return settings.darkColors
        case .system:
            return UITraitCollection.current.userInterfaceStyle == .dark ? settings.darkColors : settings.lightColors
        }
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var requiresRate: Bool {
        paymentMode != .floating
    }

    private var canSave: Bool {
        !normalizedName.isEmpty && (!requiresRate || rateValue > 0)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(NSLocalizedString("Название", comment: "work type editor section header: name"))) {
                    TextField(NSLocalizedString("Например: Бар", comment: "work type editor name placeholder"), text: $name)
                        .autocapitalization(.sentences)
                }

                Section(header: Text(NSLocalizedString("Иконка", comment: "work type editor section header: icon"))) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(iconOptions, id: \.self) { icon in
                                Button(action: { selectedIcon = icon }) {
                                    Image(systemName: icon)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(selectedIcon == icon ? AppColors.accent : AppColors.secondaryText)
                                        .frame(width: 42, height: 42)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(selectedIcon == icon ? AppColors.accent.opacity(0.14) : Color.white.opacity(0.16))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text(NSLocalizedString("Цвет в аналитике", comment: "work type editor section header: analytics color"))) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(availableColors, id: \.self) { hex in
                                Button(action: { selectedColorHex = hex }) {
                                    Circle()
                                        .fill(Color(hex: hex) ?? AppColors.accent)
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.8), lineWidth: selectedColorHex == hex ? 2 : 0)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text(NSLocalizedString("Тип заработка", comment: "work type editor section header: payment type"))) {
                    Picker(NSLocalizedString("Тип", comment: "work type editor picker label: type"), selection: $paymentMode) {
                        ForEach(WorkTypePaymentMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if paymentMode == .hourly {
                        NumberField(title: NSLocalizedString("Ставка", comment: "work type editor rate title"), value: $rateValue, currency: settings.defaultCurrency)
                    } else if paymentMode == .fixed {
                        NumberField(title: NSLocalizedString("За смену", comment: "work type editor fixed amount title"), value: $rateValue, currency: settings.defaultCurrency)
                    }

                    Toggle(NSLocalizedString("Есть чаевые", comment: "work type editor toggle: tips enabled"), isOn: $hasTips)
                        .tint(AppColors.accent)
                }

                Section(header: Text(NSLocalizedString("График по умолчанию", comment: "work type editor section header: default schedule"))) {
                    timePickerRow(title: NSLocalizedString("Начало", comment: "work type editor default schedule start"), hour: $startHour, minute: $startMinute)
                    timePickerRow(title: NSLocalizedString("Конец", comment: "work type editor default schedule end"), hour: $endHour, minute: $endMinute)
                }

                Section {
                    Toggle(NSLocalizedString("Активна в списке смен", comment: "work type editor toggle: active in list"), isOn: $isActive)
                        .tint(AppColors.accent)
                }
            }
            .visionFormBackground()
            .navigationTitle(modeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button(NSLocalizedString("Отмена", comment: "common cancel action")) { presentationMode.wrappedValue.dismiss() }
                    .foregroundColor(AppColors.accent),
                trailing: Button(NSLocalizedString("Сохранить", comment: "common save action")) {
                    save()
                }
                .disabled(!canSave)
                .foregroundColor(canSave ? AppColors.accent : AppColors.secondaryText)
            )
            .alert(NSLocalizedString("Проверьте данные", comment: "work type editor validation alert title"), isPresented: $showValidationAlert) {
                Button(NSLocalizedString("Ок", comment: "common ok action"), role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    private var modeTitle: String {
        switch mode {
        case .create:
            return NSLocalizedString("Новая смена", comment: "work type editor title: create")
        case .edit:
            return NSLocalizedString("Редактировать смену", comment: "work type editor title: edit")
        }
    }

    @ViewBuilder
    private func timePickerRow(title: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            DatePicker(
                "",
                selection: timeBinding(hour: hour, minute: minute),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .clipped()
            .visionGlassCard(cornerRadius: 12, opacity: 0.72)
        }
        .padding(.vertical, 2)
    }

    private func timeBinding(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                var comps = DateComponents()
                comps.hour = hour.wrappedValue
                comps.minute = minute.wrappedValue
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                hour.wrappedValue = comps.hour ?? 0
                minute.wrappedValue = comps.minute ?? 0
            }
        )
    }

    private func save() {
        guard !normalizedName.isEmpty else {
            validationMessage = NSLocalizedString("Введите название смены.", comment: "work type validation: empty name")
            showValidationAlert = true
            return
        }
        if requiresRate && rateValue <= 0 {
            validationMessage = NSLocalizedString("Укажите ставку больше нуля.", comment: "work type validation: invalid rate")
            showValidationAlert = true
            return
        }

        let isDuplicate = settings.workTypes.enumerated().contains { pair in
            if case .edit(let index) = mode, pair.offset == index {
                return false
            }
            return pair.element.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(normalizedName) == .orderedSame
        }
        if isDuplicate {
            validationMessage = NSLocalizedString("Смена с таким названием уже существует.", comment: "work type validation: duplicate name")
            showValidationAlert = true
            return
        }

        switch mode {
        case .create:
            let workType = WorkType(
                name: normalizedName,
                icon: selectedIcon,
                colorHex: selectedColorHex,
                hasHourlyRate: paymentMode == .hourly,
                hasFixedRate: paymentMode == .fixed,
                hasFloatingRate: paymentMode == .floating,
                hasTips: hasTips,
                isActive: isActive,
                hourlyRate: paymentMode == .hourly ? rateValue : 0,
                fixedRate: paymentMode == .fixed ? rateValue : 0,
                startHour: startHour,
                startMinute: startMinute,
                endHour: endHour,
                endMinute: endMinute
            )
            settings.workTypes.append(workType)
        case .edit(let index):
            guard settings.workTypes.indices.contains(index) else {
                return
            }
            settings.workTypes[index].name = normalizedName
            settings.workTypes[index].icon = selectedIcon
            settings.workTypes[index].colorHex = selectedColorHex
            settings.workTypes[index].hasHourlyRate = paymentMode == .hourly
            settings.workTypes[index].hasFixedRate = paymentMode == .fixed
            settings.workTypes[index].hasFloatingRate = paymentMode == .floating
            settings.workTypes[index].hasTips = hasTips
            settings.workTypes[index].isActive = isActive
            settings.workTypes[index].hourlyRate = paymentMode == .hourly ? rateValue : 0
            settings.workTypes[index].fixedRate = paymentMode == .fixed ? rateValue : 0
            settings.workTypes[index].startHour = startHour
            settings.workTypes[index].startMinute = startMinute
            settings.workTypes[index].endHour = endHour
            settings.workTypes[index].endMinute = endMinute
        }

        settings.saveSettings()
        HapticManager.shared.success()
        SoundManager.shared.play(.success)
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - AddExpenseSheet
struct AddExpenseSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var expenses: [ExpenseItem]
    let settings: UserSettings; let categories: [String]; let onAdd: () -> Void

    @State private var amount = ""; @State private var category = ""; @State private var note = ""
    @StateObject private var speechInput = ExpenseSpeechInputManager()

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text(NSLocalizedString("Сумма", comment: "add expense field label: amount"))
                        Spacer()
                        TextField(NSLocalizedString("0", comment: "add expense amount placeholder"), text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(settings.defaultCurrency)
                    }
                    if categories.isEmpty {
                        Text(NSLocalizedString("Сначала добавьте категории в настройках", comment: "add expense empty categories message"))
                            .foregroundColor(AppColors.secondaryText)
                    } else {
                        Picker(NSLocalizedString("Категория", comment: "add expense picker label: category"), selection: $category) {
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    TextField(NSLocalizedString("Комментарий", comment: "add expense note placeholder"), text: $note)
                }
                Section(header: Text(NSLocalizedString("Голосовой ввод", comment: "add expense section header: voice input")).foregroundColor(AppColors.secondaryText)) {
                    Button(action: toggleSpeech) {
                        HStack {
                            Image(systemName: speechInput.isRecording ? "stop.circle.fill" : "mic.fill")
                            Text(
                                speechInput.isRecording
                                    ? NSLocalizedString("Остановить", comment: "voice input action: stop")
                                    : NSLocalizedString("Продиктовать расход", comment: "voice input action: dictate expense")
                            )
                            Spacer()
                        }
                    }
                    .foregroundColor(speechInput.isRecording ? AppColors.negative : AppColors.accent)
                    if !speechInput.recognizedText.isEmpty {
                        Text(speechInput.recognizedText).font(.caption).foregroundColor(AppColors.secondaryText).lineLimit(3)
                        Button(NSLocalizedString("Применить", comment: "voice input action: apply")) {
                            applySpeech()
                        }
                        .foregroundColor(AppColors.accent)
                    }
                    if let err = speechInput.errorText {
                        Text(err).font(.caption).foregroundColor(AppColors.negative)
                    }
                }
            }
            .visionFormBackground()
            .navigationTitle(NSLocalizedString("Новый расход", comment: "add expense screen title"))
            .navigationBarItems(
                leading: Button(NSLocalizedString("Отмена", comment: "common cancel action")) {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button(NSLocalizedString("Сохранить", comment: "common save action")) {
                    if let v = Double(amount), v > 0 {
                        let cat = category.isEmpty
                            ? (categories.first ?? NSLocalizedString("Другое", comment: "default expense category fallback"))
                            : category
                        expenses.append(ExpenseItem(amount: v, category: cat, note: note))
                        HapticEngine.impact(.light); onAdd(); presentationMode.wrappedValue.dismiss()
                    }
                }.disabled(amount.isEmpty || categories.isEmpty)
            )
            .onAppear {
                if category.isEmpty {
                    category = categories.first ?? NSLocalizedString("Другое", comment: "default expense category fallback")
                }
            }
            .onDisappear { speechInput.stopRecording() }
        }
    }
    private func toggleSpeech() {
        if speechInput.isRecording { speechInput.stopRecording() } else { Task { await speechInput.startRecording() } }
    }
    private func applySpeech() {
        let p = ExpenseSpeechParser.parse(text: speechInput.recognizedText, categories: categories)
        if let a = p.amount, a > 0 { amount = String(format: "%.0f", a) }
        if let c = p.category { category = c }
    }
}

// MARK: - EditExpenseSheet
struct EditExpenseSheet: View {
    @Environment(\.presentationMode) var presentationMode
    let expense: ExpenseItem; let settings: UserSettings
    let categories: [String]; let onSave: (ExpenseItem) -> Void

    @State private var amount: String; @State private var category: String; @State private var note: String
    @StateObject private var speechInput = ExpenseSpeechInputManager()

    init(expense: ExpenseItem, settings: UserSettings, categories: [String], onSave: @escaping (ExpenseItem) -> Void) {
        self.expense = expense; self.settings = settings; self.onSave = onSave
        var cats = categories
        if !cats.contains(expense.category) { cats.insert(expense.category, at: 0) }
        if cats.isEmpty { cats = [NSLocalizedString("Другое", comment: "default expense category fallback")] }
        self.categories = cats
        _amount = State(initialValue: String(format: "%.0f", expense.amount))
        _category = State(
            initialValue: cats.contains(expense.category)
                ? expense.category
                : (cats.first ?? NSLocalizedString("Другое", comment: "default expense category fallback"))
        )
        _note = State(initialValue: expense.note)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text(NSLocalizedString("Сумма", comment: "edit expense field label: amount"))
                        Spacer()
                        TextField(NSLocalizedString("0", comment: "edit expense amount placeholder"), text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(settings.defaultCurrency)
                    }
                    if categories.isEmpty {
                        Text(NSLocalizedString("Сначала добавьте категории в настройках", comment: "edit expense empty categories message"))
                            .foregroundColor(AppColors.secondaryText)
                    } else {
                        Picker(NSLocalizedString("Категория", comment: "edit expense picker label: category"), selection: $category) {
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    TextField(NSLocalizedString("Комментарий", comment: "edit expense note placeholder"), text: $note)
                }
                Section(header: Text(NSLocalizedString("Голосовой ввод", comment: "edit expense section header: voice input")).foregroundColor(AppColors.secondaryText)) {
                    Button(action: toggleSpeech) {
                        HStack {
                            Image(systemName: speechInput.isRecording ? "stop.circle.fill" : "mic.fill")
                            Text(
                                speechInput.isRecording
                                    ? NSLocalizedString("Остановить", comment: "voice input action: stop")
                                    : NSLocalizedString("Продиктовать расход", comment: "voice input action: dictate expense")
                            )
                            Spacer()
                        }
                    }
                    .foregroundColor(speechInput.isRecording ? AppColors.negative : AppColors.accent)
                    if !speechInput.recognizedText.isEmpty {
                        Text(speechInput.recognizedText).font(.caption).foregroundColor(AppColors.secondaryText).lineLimit(3)
                        Button(NSLocalizedString("Применить", comment: "voice input action: apply")) {
                            applySpeech()
                        }
                        .foregroundColor(AppColors.accent)
                    }
                    if let err = speechInput.errorText {
                        Text(err).font(.caption).foregroundColor(AppColors.negative)
                    }
                }
            }
            .visionFormBackground()
            .navigationTitle(NSLocalizedString("Редактировать расход", comment: "edit expense sheet title"))
            .navigationBarItems(
                leading: Button(NSLocalizedString("Отмена", comment: "common cancel action")) {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button(NSLocalizedString("Сохранить", comment: "common save action")) {
                    if let v = Double(amount), v > 0 {
                        let cat = category.isEmpty
                            ? (categories.first ?? NSLocalizedString("Другое", comment: "default expense category fallback"))
                            : category
                        onSave(ExpenseItem(id: expense.id, amount: v, category: cat, note: note))
                        presentationMode.wrappedValue.dismiss()
                    }
                }.disabled(amount.isEmpty || categories.isEmpty)
            )
            .onDisappear { speechInput.stopRecording() }
        }
    }
    private func toggleSpeech() {
        if speechInput.isRecording { speechInput.stopRecording() } else { Task { await speechInput.startRecording() } }
    }
    private func applySpeech() {
        let p = ExpenseSpeechParser.parse(text: speechInput.recognizedText, categories: categories)
        if let a = p.amount, a > 0 { amount = String(format: "%.0f", a) }
        if let c = p.category { category = c }
    }
}
