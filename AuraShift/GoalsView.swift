//
//  GoalsView.swift
//  AuraShift
//
//  Created by David Makarian on 24.02.2026.
//
import SwiftUI
import CoreData
import UIKit
// TODO(AppGroups): After enabling App Groups, uncomment the import below to call WidgetCenter.reloadAllTimelines().
// See FULL_RESTORE_AFTER_DEV_ACCOUNT.md, section "2) App Groups"
//import WidgetKit

struct GoalsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var settings: UserSettings
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FinancialGoal.deadline, ascending: true)],
        animation: .default
    )
    private var goals: FetchedResults<FinancialGoal>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Income.date, ascending: false)],
        animation: .default
    )
    private var incomes: FetchedResults<Income>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Expense.date, ascending: false)],
        animation: .default
    )
    private var expenses: FetchedResults<Expense>
    
    @State private var showingAddGoal = false
    @State private var selectedGoal: FinancialGoal?
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    
    private var totalNetProfitAllTime: Double {
        let allIncomes = incomes.reduce(0) { $0 + ($1.hoursWorked * $1.hourlyRate) + $1.tips + $1.floatingAmount }
        // Учитываем только расходы, дата которых <= сегодня
        let pastExpenses = expenses.filter { $0.date ?? Date() <= Date() }
        let allExpenses = pastExpenses.reduce(0) { $0 + $1.amount }
        return allIncomes - allExpenses
    }
    
    private var activeGoals: [FinancialGoal] {
        goals.filter { $0.isActive }
    }
    
    private var totalGoalTarget: Double {
        activeGoals.reduce(0) { $0 + $1.targetAmount }
    }
    
    private var totalGoalCurrent: Double {
        activeGoals.reduce(0) { $0 + $1.currentAmount }
    }
    
    private var totalGoalCurrentWithProfit: Double {
        totalGoalCurrent + (totalNetProfitAllTime > 0 ? totalNetProfitAllTime : 0)
    }
    
    private var totalGoalProgress: Double {
        guard totalGoalTarget > 0 else { return 0 }
        return (min(totalGoalCurrentWithProfit, totalGoalTarget) / totalGoalTarget) * 100
    }
    
    private var averageNetPerShift: Double {
        let calendar = Calendar.current
        let today = Date()
        guard let start = calendar.date(byAdding: .day, value: -59, to: today) else { return 0 }
        
        let recent = incomes.filter {
            guard let date = $0.date else { return false }
            return date >= start && date <= today
        }
        
        guard !recent.isEmpty else { return 0 }
        
        let incomeTotal = recent.reduce(0) { $0 + ($1.hoursWorked * $1.hourlyRate) + $1.tips + $1.floatingAmount }
        let expenseTotal = expenses.filter {
            guard let date = $0.date else { return false }
            return date >= start && date <= today
        }
        .reduce(0) { $0 + $1.amount }
        
        let net = incomeTotal - expenseTotal
        return net / Double(recent.count)
    }
    
    private var monthlyNetPace: Double {
        let calendar = Calendar.current
        let today = Date()
        guard let start = calendar.date(byAdding: .day, value: -59, to: today) else { return 0 }
        
        let recent = incomes.filter {
            guard let date = $0.date else { return false }
            return date >= start && date <= today
        }
        
        let incomeTotal = recent.reduce(0) { $0 + ($1.hoursWorked * $1.hourlyRate) + $1.tips + $1.floatingAmount }
        let expenseTotal = expenses.filter {
            guard let date = $0.date else { return false }
            return date >= start && date <= today
        }
        .reduce(0) { $0 + $1.amount }
        
        let net = incomeTotal - expenseTotal
        return (net / 60.0) * 30.0
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // STYLE: Глобальный фон экрана целей растянут на весь экран без зазоров.
                VisionBackdropView()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        if goals.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "target")
                                    .font(.system(size: 34, weight: .semibold))
                                    .foregroundColor(AppColors.accent)
                                    .frame(width: 84, height: 84)
                                    .visionGlassCard(cornerRadius: 24, opacity: 0.84, showRing: true)
                                Text(NSLocalizedString("Пока нет целей", comment: "goals empty state title"))
                                    .font(.title2)
                                    .foregroundColor(AppColors.text)
                                Text(NSLocalizedString("Добавьте финансовый план, чтобы видеть динамику", comment: "goals empty state subtitle"))
                                    .font(.body)
                                    .foregroundColor(AppColors.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            // STYLE: Смещает пустое состояние ниже, чтобы оно визуально было по центру экрана.
                            .padding(.top, 100)
                        } else {
                            if activeGoals.count > 1 {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(NSLocalizedString("Общий прогресс", comment: "goals summary title: overall progress"))
                                            .font(.headline)
                                            .foregroundColor(AppColors.text)
                                        
                                        Spacer()
                                        
                                        Text("\(Int(totalGoalProgress))%")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(AppColors.accent)
                                    }
                                    
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            // STYLE: Фон полосы прогресса общего плана.
                                            Rectangle()
                                                .fill(AppColors.border)
                                                .frame(width: geometry.size.width, height: 8)
                                                .cornerRadius(4)

                                            // STYLE: Заполнение полосы прогресса акцентным цветом.
                                            Rectangle()
                                                .fill(AppColors.accent)
                                                .frame(width: geometry.size.width * CGFloat(min(totalGoalProgress / 100, 1.0)), height: 8)
                                                .cornerRadius(4)
                                                .lightweightAnimation(.spring(), value: totalGoalProgress)
                                        }
                                    }
                                    .frame(height: 8)
                                    
                                    HStack {
                                        Text(NSLocalizedString("Накоплено:", comment: "goals summary label: saved"))
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(AppColors.secondaryText)
                                        Spacer()
                                        Text("\(Int(totalGoalCurrentWithProfit)) \(settings.defaultCurrency)")
                                            .font(.system(size: 15, weight: .semibold))
                                            .fontWeight(.medium)
                                            .foregroundColor(AppColors.accent)
                                    }
                                    
                                    HStack {
                                        Text(NSLocalizedString("Требуется:", comment: "goals summary label: required"))
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(AppColors.secondaryText)
                                        Spacer()
                                        Text("\(Int(totalGoalTarget)) \(settings.defaultCurrency)")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                }
                                .padding()
                                // STYLE: Стеклянная карточка общего прогресса с единым скруглением.
                                .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
                                .padding(.horizontal)
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text(
                                    activeGoals.count > 1
                                        ? NSLocalizedString("Планы в работе", comment: "goals section title: multiple active goals")
                                        : NSLocalizedString("Текущий план", comment: "goals section title: current plan")
                                )
                                    .font(.headline)
                                    .foregroundColor(AppColors.text)
                                    .padding(.horizontal)
                                
                                ForEach(activeGoals) { goal in
                                    Button {
                                        selectedGoal = goal
                                    } label: {
                                        GoalProgressView(
                                            goal: goal,
                                            settings: settings,
                                            totalNetProfit: totalNetProfitAllTime,
                                            averageNetPerShift: averageNetPerShift,
                                            monthlyNetPace: monthlyNetPace
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint(Text(NSLocalizedString("Открыть редактирование цели", comment: "goals card accessibility hint: open edit goal")))
                                }
                            }
                        }
                    }
                    // STYLE: Базовые отступы контента внутри скролла.
                    .padding()
                }
            }
            .navigationTitle(NSLocalizedString("Финпланы", comment: "goals screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: prepareShareCard) {
                        Image(systemName: "square.and.arrow.up")
                            // STYLE: Иконка шаринга тускнеет, когда нет активных целей.
                            .foregroundColor(activeGoals.isEmpty ? AppColors.secondaryText : AppColors.accent)
                    }
                    .disabled(activeGoals.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddGoal = true }) {
                        Image(systemName: "plus")
                            // STYLE: Акцентная кнопка добавления новой цели.
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
            .accentColor(AppColors.accent)
            .sheet(isPresented: $showingAddGoal) {
                AddGoalView(settings: settings)
            }
            .sheet(item: $selectedGoal) { goal in
                EditGoalView(goal: goal, settings: settings)
            }
            .sheet(isPresented: $showingShareSheet) {
                GoalShareSheet(activityItems: shareItems)
            }
        }
    }
    
    private func prepareShareCard() {
        guard !activeGoals.isEmpty else { return }
        
        if #available(iOS 16.0, *) {
            let card = GoalShareCard(
                progress: totalGoalProgress,
                target: totalGoalTarget,
                current: totalGoalCurrentWithProfit,
                currency: settings.defaultCurrency
            )
            // STYLE: Размер карточки для шеринга фиксирован для предсказуемого рендера.
            .frame(width: 320)
            .padding()
            // STYLE: Фон карточки перед рендером в изображение (glass-friendly градиент).
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.18, blue: 0.30),
                        Color(red: 0.24, green: 0.35, blue: 0.50)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            let renderer = ImageRenderer(content: card)
            renderer.scale = UIScreen.main.scale
            
            if let image = renderer.uiImage {
                shareItems = [image]
                showingShareSheet = true
            }
        } else {
            let text = String(
                format: NSLocalizedString("Мой прогресс: %d / %d %@ (%d%%)", comment: "goal share fallback text"),
                Int(totalGoalCurrentWithProfit),
                Int(totalGoalTarget),
                settings.defaultCurrency,
                Int(totalGoalProgress)
            )
            shareItems = [text]
            showingShareSheet = true
        }
    }
}
// MARK: - Widget Data Update (Goals)

// Временная запись метрик целей для виджета в UserDefaults.standard (без App Groups виджет это не увидит)
private func updateWidgetGoalMetrics(context: NSManagedObjectContext, settings: UserSettings) {
    let fetch: NSFetchRequest<FinancialGoal> = FinancialGoal.fetchRequest()
    fetch.returnsObjectsAsFaults = false
    do {
        let allGoals = try context.fetch(fetch)
        let active = allGoals.filter { $0.isActive }
        let totalGoalTarget = active.reduce(0) { $0 + $1.targetAmount }
        let totalGoalCurrent = active.reduce(0) { $0 + $1.currentAmount }
        let remaining = max(totalGoalTarget - totalGoalCurrent, 0)
        let progress = totalGoalTarget > 0 ? (totalGoalCurrent / totalGoalTarget) * 100 : 0

        // TODO(AppGroups): Replace with shared suite when App Groups are enabled.
        // See FULL_RESTORE_AFTER_DEV_ACCOUNT.md, section "2) App Groups" for the final code snippet and steps.
        // Example:
        // let defaults = UserDefaults(suiteName: "group.com.yourcompany.AuraShift") ?? .standard
        let defaults = UserDefaults.standard
        defaults.set(remaining, forKey: "remainingGoals")
        defaults.set(progress, forKey: "goalProgress")
        defaults.set(settings.defaultCurrency, forKey: "currency")
        // TODO(AppGroups): After writing shared defaults, reload widget timelines.
        // See FULL_RESTORE_AFTER_DEV_ACCOUNT.md, section "2) App Groups".
        // Requires: import WidgetKit
        // if #available(iOS 14.0, *) {
        //     WidgetCenter.shared.reloadAllTimelines()
        // }
    } catch {
        print("⚠️ Не удалось обновить метрики целей для виджета: \(error)")
    }
}

struct GoalProgressView: View {
    @ObservedObject var goal: FinancialGoal
    let settings: UserSettings
    let totalNetProfit: Double
    let averageNetPerShift: Double
    let monthlyNetPace: Double
    
    var currentWithProfit: Double {
        goal.currentAmount + (totalNetProfit > 0 ? totalNetProfit : 0)
    }
    
    var progress: Double {
        guard goal.targetAmount > 0 else { return 0 }
        return (min(currentWithProfit, goal.targetAmount) / goal.targetAmount) * 100
    }
    
    var remaining: Double {
        max(goal.targetAmount - currentWithProfit, 0)
    }
    
    var shiftsLeftEstimate: Int? {
        guard averageNetPerShift > 0, remaining > 0 else { return nil }
        return Int(ceil(remaining / averageNetPerShift))
    }
    
    var monthsLeftEstimate: Double? {
        guard monthlyNetPace > 0, remaining > 0 else { return nil }
        return remaining / monthlyNetPace
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(goal.name ?? NSLocalizedString("Без названия", comment: "goal fallback title"))
                    .font(.headline)
                    .foregroundColor(AppColors.text)
                Spacer()
                if let deadline = goal.deadline {
                    Text(deadline, style: .date)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // STYLE: Подложка прогресс-бара карточки цели.
                    Rectangle()
                        .frame(width: geometry.size.width, height: 8)
                        .foregroundColor(AppColors.border)
                        .cornerRadius(4)

                    // STYLE: Зеленое заполнение прогресса цели.
                    Rectangle()
                        .frame(width: geometry.size.width * CGFloat(min(progress / 100, 1.0)), height: 8)
                        .foregroundColor(AppColors.positive)
                        .cornerRadius(4)
                        .lightweightAnimation(.spring(), value: progress)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text(NSLocalizedString("Текущий:", comment: "goal card label: current"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                Text("\(Int(currentWithProfit)) \(settings.defaultCurrency)")
                    .font(.system(size: 15, weight: .semibold))
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.positive)
                
                Spacer()
                
                Text(NSLocalizedString("Цель:", comment: "goal card label: target"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                Text("\(Int(goal.targetAmount)) \(settings.defaultCurrency)")
                    .font(.system(size: 15, weight: .semibold))
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.accent)
            }
            
            HStack {
                Text(NSLocalizedString("Выполнено:", comment: "goal card label: completed"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                Text(String(format: "%.1f%%", progress))
                    .font(.title3)
                    .fontWeight(.semibold)
                    // STYLE: Цвет процента меняется по состоянию выполнения.
                    .foregroundColor(progress >= 100 ? AppColors.positive : AppColors.accent)
                
                Spacer()
                
                if progress >= 100 {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                } else if remaining > 0 {
                    Text(
                        String(
                            format: NSLocalizedString("Осталось: %d %@", comment: "goal remaining amount"),
                            Int(remaining),
                            settings.defaultCurrency
                        )
                    )
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            if totalNetProfit > 0 && progress < 100 {
                HStack {
                    Text(NSLocalizedString("+ Чистая прибыль:", comment: "goal card label: net profit"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                    Text("\(Int(totalNetProfit)) \(settings.defaultCurrency)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.positive)
                        .fontWeight(.semibold)
                }
                .padding(.top, 4)
            }
            
            if progress < 100 {
                if let shiftsLeftEstimate {
                    Text(
                        String(
                            format: NSLocalizedString("Осталось примерно %d смен", comment: "goal remaining shifts estimate"),
                            shiftsLeftEstimate
                        )
                    )
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
                
                if let monthsLeftEstimate {
                    Text(
                        String(
                            format: NSLocalizedString("или ~%.1f месяца при текущем темпе", comment: "goal remaining months estimate"),
                            monthsLeftEstimate
                        )
                    )
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(AppColors.secondaryText)
                } else if monthlyNetPace <= 0 {
                    Text(NSLocalizedString("Текущий темп ниже расходов", comment: "goal pace below expenses warning"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
        .padding()
        // STYLE: Визуальный контейнер карточки цели в общем стеклянном стиле.
        .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
    }
}

struct AddGoalView: View {
    @Environment(\.presentationMode) var presentationMode
    let settings: UserSettings
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var name = ""
    @State private var amount = ""
    @State private var deadline = Date()
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                // STYLE: Цвет заголовка секции формы.
                Section(header: Text(NSLocalizedString("Название цели", comment: "add goal section header: title")).foregroundColor(AppColors.secondaryText)) {
                    TextField(NSLocalizedString("Например: Накопить на отпуск", comment: "add goal title placeholder"), text: $name)
                        .foregroundColor(AppColors.text)
                }

                Section(header: Text(NSLocalizedString("Сумма", comment: "add goal section header: amount")).foregroundColor(AppColors.secondaryText)) {
                    HStack {
                        TextField(NSLocalizedString("Желаемая сумма", comment: "add goal amount placeholder"), text: $amount)
                            .keyboardType(.numberPad)
                            .foregroundColor(AppColors.text)
                        Text(settings.defaultCurrency)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }

                Section(header: Text(NSLocalizedString("Срок", comment: "add goal section header: deadline")).foregroundColor(AppColors.secondaryText)) {
                    DatePicker(NSLocalizedString("Достичь до", comment: "add goal date picker label"), selection: $deadline, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        // STYLE: Высота колеса даты внутри секции.
                        .frame(height: 150)
                        .clipped()
                        .accentColor(AppColors.accent)
                        // STYLE: Стеклянная карточка для DatePicker.
                        .visionGlassCard(cornerRadius: 12, opacity: 0.82, showRing: true)
                }
            }
            // STYLE: Единый фон формы для экранов ввода.
            .visionFormBackground()
            .navigationTitle(NSLocalizedString("Новая цель", comment: "add goal screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button(NSLocalizedString("Отмена", comment: "common cancel action")) {
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(AppColors.accent),
                trailing: Button(NSLocalizedString("Сохранить", comment: "common save action")) {
                    saveGoal()
                }
                .disabled(name.isEmpty || amount.isEmpty)
                // STYLE: Кнопка "Сохранить" визуально неактивна, пока форма неполная.
                .foregroundColor((name.isEmpty || amount.isEmpty) ? AppColors.secondaryText : AppColors.accent)
            )
            .alert(NSLocalizedString("Ошибка", comment: "add goal error alert title"), isPresented: $showingAlert) {
                Button(NSLocalizedString("Ок", comment: "common ok action"), role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
        .accentColor(AppColors.accent)
    }
    
    private func saveGoal() {
        guard let targetAmount = Double(amount), targetAmount > 0 else {
            alertMessage = NSLocalizedString("Введите корректную сумму", comment: "add goal validation message: invalid amount")
            showingAlert = true
            return
        }
        
        guard !name.isEmpty else {
            alertMessage = NSLocalizedString("Введите название цели", comment: "add goal validation message: empty name")
            showingAlert = true
            return
        }
        
        let goal = FinancialGoal(context: viewContext)
        goal.id = UUID()
        goal.name = name
        goal.targetAmount = targetAmount
        goal.currentAmount = 0
        goal.deadline = deadline
        goal.isActive = true
        
        do {
            try viewContext.save()
            NotificationManager.shared.rescheduleGoalReminders(settings: settings)
            updateWidgetGoalMetrics(context: viewContext, settings: settings)
            // TODO(AppGroups): With App Groups enabled, the widget will read these metrics from the shared suite.
            print("✅ Цель добавлена: \(name)")
            presentationMode.wrappedValue.dismiss()
        } catch {
            alertMessage = String(
                format: NSLocalizedString("Ошибка сохранения: %@", comment: "goal save error message with details"),
                error.localizedDescription
            )
            showingAlert = true
            print("❌ Ошибка сохранения цели: \(error)")
        }
    }
}

struct EditGoalView: View {
    @ObservedObject var goal: FinancialGoal
    let settings: UserSettings
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var showingDeleteAlert = false
    @State private var currentAmount = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(NSLocalizedString("Информация", comment: "edit goal section header: info")).foregroundColor(AppColors.secondaryText)) {
                    HStack {
                        Text(NSLocalizedString("Название", comment: "edit goal field label: name"))
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text(goal.name ?? "")
                            .foregroundColor(AppColors.text)
                    }
                    
                    HStack {
                        Text(NSLocalizedString("Цель", comment: "edit goal field label: target"))
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text(String(format: "%.0f %@", goal.targetAmount, settings.defaultCurrency))
                            .foregroundColor(AppColors.accent)
                    }
                }

                Section(header: Text(NSLocalizedString("Прогресс", comment: "edit goal section header: progress")).foregroundColor(AppColors.secondaryText)) {
                    HStack {
                        Text(NSLocalizedString("Уже накоплено", comment: "edit goal field label: current amount"))
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        TextField(NSLocalizedString("0", comment: "edit goal amount placeholder"), text: $currentAmount)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(AppColors.text)
                        Text(settings.defaultCurrency)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    if let current = Double(currentAmount), current > 0 {
                        let progress = (current / goal.targetAmount) * 100
                        HStack {
                            Text(NSLocalizedString("Выполнено", comment: "edit goal field label: completion"))
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text(String(format: "%.1f%%", progress))
                                // STYLE: Цвет процента прогресса в зависимости от достижения цели.
                                .foregroundColor(progress >= 100 ? AppColors.positive : AppColors.accent)
                                .fontWeight(.semibold)
                        }
                    }
                }
                
                if let deadline = goal.deadline {
                    Section(header: Text(NSLocalizedString("Срок", comment: "edit goal section header: deadline")).foregroundColor(AppColors.secondaryText)) {
                        HStack {
                            Text(NSLocalizedString("Достичь до", comment: "edit goal field label: reach by"))
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text(deadline, style: .date)
                                .foregroundColor(AppColors.text)
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text(NSLocalizedString("Удалить цель", comment: "edit goal action: delete"))
                                .foregroundColor(AppColors.negative)
                            Spacer()
                        }
                    }
                }
            }
            // STYLE: Единый стеклянный фон формы редактирования.
            .visionFormBackground()
            .navigationTitle(NSLocalizedString("Редактировать", comment: "common edit screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(NSLocalizedString("Сохранить", comment: "common save action")) {
                saveChanges()
                presentationMode.wrappedValue.dismiss()
            }
            .foregroundColor(AppColors.accent))
            .alert(NSLocalizedString("Удалить цель?", comment: "goal delete confirmation title"), isPresented: $showingDeleteAlert) {
                Button(NSLocalizedString("Отмена", comment: "common cancel action"), role: .cancel) { }
                Button(NSLocalizedString("Удалить", comment: "common delete action"), role: .destructive) {
                    deleteGoal()
                }
            } message: {
                Text(NSLocalizedString("Это действие нельзя отменить", comment: "goal delete confirmation message"))
            }
            .onAppear {
                currentAmount = String(format: "%.0f", goal.currentAmount)
            }
        }
        .accentColor(AppColors.accent)
    }
    
    private func saveChanges()
    {
        if let current = Double(currentAmount) {
            goal.currentAmount = current
        }
        
        do {
            try viewContext.save()
            NotificationManager.shared.rescheduleGoalReminders(settings: settings)
            updateWidgetGoalMetrics(context: viewContext, settings: settings)
            // TODO(AppGroups): With App Groups enabled, the widget will read these metrics from the shared suite.
       //     updateWidgetData()
            print("✅ Цель обновлена")
        } catch {
            print("❌ Ошибка сохранения: \(error)")
        }
    }
    
    private func deleteGoal() {
        viewContext.delete(goal)
        do {
            try viewContext.save()
            NotificationManager.shared.rescheduleGoalReminders(settings: settings)
            updateWidgetGoalMetrics(context: viewContext, settings: settings)
            // TODO(AppGroups): With App Groups enabled, the widget will read these metrics from the shared suite.
         //   updateWidgetData()
            presentationMode.wrappedValue.dismiss()
            print("✅ Цель удалена")
        } catch {
            print("❌ Ошибка удаления: \(error)")
        }
    }
}

@available(iOS 16.0, *)
private struct GoalShareCard: View {
    let progress: Double
    let target: Double
    let current: Double
    let currency: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("Мой финансовый прогресс", comment: "goal share card title"))
                .font(.headline)
                .foregroundColor(AppColors.text)
            
            Text("\(Int(current)) / \(Int(target)) \(currency)")
                .font(.title2.weight(.bold))
                .foregroundColor(AppColors.accent)
            
            ZStack(alignment: .leading) {
                // STYLE: Подложка прогресс-бара на share-карточке.
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColors.border)
                    .frame(height: 10)

                // STYLE: Градиентное заполнение прогресса в share-карточке.
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.48))
                    .frame(width: 280 * CGFloat(min(progress / 100, 1.0)), height: 10)
            }
            // STYLE: Фиксированная ширина полосы для стабильного экспорта изображения.
            .frame(width: 280, height: 10)
            
            Text(String(
                format: NSLocalizedString("Выполнено: %d%%", comment: "goal share card completion percentage"),
                Int(progress)
            ))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.positive)
            
            Text(NSLocalizedString("Продолжаю путь к цели", comment: "goal share card footer"))
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
        }
        .padding(18)
        // STYLE: Основной стеклянный контейнер share-карточки.
        .visionGlassCard(cornerRadius: 18, opacity: 0.84, showRing: true)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.border, lineWidth: 1))
    }
}

private struct GoalShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    
    

    }
