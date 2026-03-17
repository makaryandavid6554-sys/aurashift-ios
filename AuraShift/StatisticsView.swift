//
//  StatisticsView.swift
//  AuraShift
//
//  Created by David Makarian on 24.02.2026.
//
import SwiftUI
import CoreData
import Charts

struct StatisticsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var settings: UserSettings
    @StateObject private var proManager = ProManager.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Income.date, ascending: true)],
        animation: .default
    )
    private var incomes: FetchedResults<Income>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Expense.date, ascending: true)],
        animation: .default
    )
    private var expenses: FetchedResults<Expense>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FinancialGoal.deadline, ascending: true)],
        animation: .default
    )
    private var goals: FetchedResults<FinancialGoal>
    
    @State private var selectedPeriodIndex = 0
    @State private var selectedChart = 0
    @State private var selectedDataType = 0
    @State private var customStartDate = Date().addingTimeInterval(-30*24*60*60)
    @State private var customEndDate = Date()
    @State private var showBudgetSettings = false
    @State private var showAllInsights = false
    @State private var showAllBudgetItems = false
    
    private var periods: [String] {
        [
            NSLocalizedString("Неделя", comment: "stats period: week"),
            NSLocalizedString("Месяц", comment: "stats period: month"),
            NSLocalizedString("Год", comment: "stats period: year"),
            NSLocalizedString("Период", comment: "stats period: custom")
        ]
    }

    private var charts: [String] {
        [
            NSLocalizedString("График", comment: "stats chart type: line"),
            NSLocalizedString("Круговая", comment: "stats chart type: pie")
        ]
    }

    private var dataTypes: [String] {
        [
            NSLocalizedString("Всё", comment: "stats data type: all"),
            NSLocalizedString("Доходы", comment: "stats data type: income"),
            NSLocalizedString("Расходы", comment: "stats data type: expense")
        ]
    }
    
    // Цвета из AppColors
    let incomeColor = AppColors.positive
    let expenseColor = AppColors.negative
    let tipsColor = Color.orange

    private func formatCurrency(_ value: Double) -> String {
        settings.formattedCurrency(value)
    }
    
    private func colorForWorkType(_ type: String) -> Color {
        if let workType = settings.workTypes.first(where: { $0.name == type }) {
            return Color(hex: workType.colorHex) ?? .blue
        }
        return .blue
    }
    
    private func colorForExpenseCategory(_ category: String) -> Color {
        settings.colorForExpenseCategory(category)
    }
    
    private func iconForExpenseCategory(_ category: String) -> String {
        settings.iconForExpenseCategory(category)
    }
    
    private var startDate: Date {
        switch selectedPeriodIndex {
        case 0:
            return Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        case 1:
            return Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date()
        case 2:
            return Calendar.current.date(byAdding: .day, value: -364, to: Date()) ?? Date()
        case 3:
            return customStartDate
        default:
            return Date()
        }
    }
    
    private var endDate: Date {
        if selectedPeriodIndex == 3 {
            return customEndDate
        }
        return Date()
    }
    
    private var periodBounds: (start: Date, endExclusive: Date) {
        let calendar = Calendar.current
        let start = min(startDate, endDate)
        let end = max(startDate, endDate)
        let startOfDay = calendar.startOfDay(for: start)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        return (startOfDay, endExclusive)
    }
    
    private var totalNetProfitAllTime: Double {
        let allIncomes = incomes.reduce(0) { $0 + ($1.hoursWorked * $1.hourlyRate) + $1.tips + $1.floatingAmount }
        let pastExpenses = expenses.filter { $0.date ?? Date() <= Date() }
        let allExpenses = pastExpenses.reduce(0) { $0 + $1.amount }
        return allIncomes - allExpenses
    }
    
    private var filteredIncomes: [Income] {
        incomes.filter { income in
            guard let date = income.date else { return false }
            return date >= periodBounds.start && date < periodBounds.endExclusive
        }
    }
    
    private var filteredExpenses: [Expense] {
        return expenses.filter {
            guard let date = $0.date else { return false }
            return date >= periodBounds.start && date < periodBounds.endExclusive
        }
    }
    
    private var totalIncome: Double {
        filteredIncomes.reduce(0) { $0 + ($1.hoursWorked * $1.hourlyRate) + $1.tips + $1.floatingAmount }
    }
    
    private var totalExpenses: Double {
        filteredExpenses.reduce(0) { $0 + $1.amount }
    }
    
    private var netProfit: Double {
        totalIncome - totalExpenses
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
    
    private var goalProgress: Double {
        guard totalGoalTarget > 0 else { return 0 }
        return (min(totalGoalCurrentWithProfit, totalGoalTarget) / totalGoalTarget) * 100
    }
    
    private var incomesByType: [String: Double] {
        var result: [String: Double] = [:]
        for income in filteredIncomes {
            let type = income.type ?? NSLocalizedString("Другое", comment: "stats fallback type/category")
            let amount = (income.hoursWorked * income.hourlyRate) + income.tips + income.floatingAmount
            result[type, default: 0] += amount
        }
        return result
    }
    
    private var tipsTotal: Double {
        filteredIncomes.reduce(0) { $0 + $1.tips }
    }
    
    private var floatingTotal: Double {
        filteredIncomes.reduce(0) { $0 + $1.floatingAmount }
    }
    
    private var expensesByCategory: [String: Double] {
        var result: [String: Double] = [:]
        for expense in filteredExpenses {
            let category = expense.category ?? NSLocalizedString("Другое", comment: "stats fallback type/category")
            result[category, default: 0] += expense.amount
        }
        return result
    }
    
    private var sortedIncomes: [(name: String, amount: Double, color: Color)] {
        incomesByType.map { (name: $0.key, amount: $0.value, color: colorForWorkType($0.key)) }
            .sorted { $0.amount > $1.amount }
    }
    
    private var sortedExpenses: [(name: String, amount: Double, color: Color, icon: String)] {
        expensesByCategory.map {
            (name: $0.key,
             amount: $0.value,
             color: colorForExpenseCategory($0.key),
             icon: iconForExpenseCategory($0.key))
        }.sorted { $0.amount > $1.amount }
    }
    
    private var bestWeekdayInsight: String? {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredIncomes) { income -> Int in
            calendar.component(.weekday, from: income.date ?? Date())
        }
        
        let totals = grouped.mapValues { incomes in
            incomes.reduce(0) { $0 + ($1.hoursWorked * $1.hourlyRate) + $1.tips + $1.floatingAmount }
        }
        
        guard let best = totals.max(by: { $0.value < $1.value }) else { return nil }
        return weekdayName(best.key)
    }
    
    private var averageIncomePerHourInsight: Double {
        let totalIncomeValue = filteredIncomes.reduce(0) { $0 + ($1.hoursWorked * $1.hourlyRate) + $1.tips + $1.floatingAmount }
        let totalHours = filteredIncomes.reduce(0) { $0 + $1.hoursWorked }
        guard totalHours > 0 else { return 0 }
        return totalIncomeValue / totalHours
    }
    
    private var tipsShareInsight: Double {
        guard totalIncome > 0 else { return 0 }
        return (tipsTotal / totalIncome) * 100
    }
    
    private var bestExpenseWeekdayInsight: String? {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredExpenses) { expense -> Int in
            calendar.component(.weekday, from: expense.date ?? Date())
        }
        
        let totals = grouped.mapValues { items in
            items.reduce(0) { $0 + $1.amount }
        }
        
        guard let best = totals.max(by: { $0.value < $1.value }), best.value > 0 else { return nil }
        return weekdayName(best.key)
    }
    
    private struct IncomeSnapshot {
        let date: Date
        let amount: Double
        let hours: Double
    }

    private struct ExpenseSnapshot {
        let date: Date
        let amount: Double
        let category: String
    }

    private struct MonthlyProjection {
        let income: Double
        let expenses: Double
        let confidence: Double
    }

    private var allIncomeSnapshots: [IncomeSnapshot] {
        incomes.compactMap { income in
            guard let date = income.date else { return nil }
            let amount = (income.hoursWorked * income.hourlyRate) + income.tips + income.floatingAmount
            guard amount > 0 else { return nil }
            return IncomeSnapshot(date: date, amount: amount, hours: estimatedShiftHours(for: income))
        }
    }

    private var allExpenseSnapshots: [ExpenseSnapshot] {
        expenses.compactMap { expense in
            guard let date = expense.date, expense.amount > 0 else { return nil }
            return ExpenseSnapshot(
                date: date,
                amount: expense.amount,
                category: expense.category ?? NSLocalizedString("Другое", comment: "stats fallback type/category")
            )
        }
    }

    private var forecastAnchorDate: Date {
        selectedPeriodIndex == 3 ? customEndDate : Date()
    }

    private var forecastMonthStart: Date {
        monthStart(for: forecastAnchorDate)
    }

    private var monthlyProjection: MonthlyProjection {
        projectMonth(for: forecastMonthStart)
    }

    private func monthlyTotalsSeries(from points: [(date: Date, amount: Double)], months: Int, anchorMonth: Date) -> [Double] {
        let calendar = Calendar.current
        guard months > 0 else { return [] }
        guard let startMonthDate = calendar.date(byAdding: .month, value: -(months - 1), to: anchorMonth),
              let startMonth = calendar.dateInterval(of: .month, for: startMonthDate)?.start
        else { return [] }

        var totals = Array(repeating: 0.0, count: months)
        for point in points where point.amount > 0 {
            let monthIndex = calendar.dateComponents([.month], from: startMonth, to: point.date).month ?? -1
            guard monthIndex >= 0, monthIndex < months else { continue }
            totals[monthIndex] += point.amount
        }
        return totals
    }

    private func emaForecast(values: [Double], alpha: Double = 0.45) -> Double {
        guard let first = values.first else { return 0 }
        var ema = first
        for value in values.dropFirst() {
            ema = alpha * value + (1 - alpha) * ema
        }
        return max(ema, 0)
    }

    private func monthStart(for date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }

    private func estimatedShiftHours(for income: Income) -> Double {
        if income.hoursWorked > 0 { return income.hoursWorked }
        guard let typeName = income.type,
              let wt = settings.workTypes.first(where: { $0.name == typeName }) else {
            return 8
        }
        let start = wt.startHour * 60 + wt.startMinute
        let end = wt.endHour * 60 + wt.endMinute
        var diff = end - start
        if diff <= 0 { diff += 24 * 60 }
        return max(Double(diff) / 60.0, 1)
    }

    private func linearSlopeXY(_ points: [(x: Double, y: Double)]) -> Double {
        let n = Double(points.count)
        guard n > 1 else { return 0 }
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        let sumXY = points.reduce(0) { $0 + $1.x * $1.y }
        let sumXX = points.reduce(0) { $0 + $1.x * $1.x }
        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return 0 }
        return (n * sumXY - sumX * sumY) / denominator
    }

    private func projectMonth(for monthStartDate: Date) -> MonthlyProjection {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthStartDate) else {
            return MonthlyProjection(income: 0, expenses: 0, confidence: 0)
        }

        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let currentMonthStart = monthStart(for: now)
        let isPastMonth = monthInterval.end <= currentMonthStart
        let isCurrentMonth = calendar.isDate(monthStartDate, equalTo: now, toGranularity: .month)
        let monthsAhead = max(calendar.dateComponents([.month], from: currentMonthStart, to: monthStartDate).month ?? 0, 0)

        let actualLimit: Date
        if isPastMonth {
            actualLimit = monthInterval.end
        } else if isCurrentMonth {
            actualLimit = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        } else {
            actualLimit = monthInterval.start
        }

        let monthIncomeByDay = Dictionary(grouping: allIncomeSnapshots.filter { $0.date >= monthInterval.start && $0.date < monthInterval.end }) {
            calendar.startOfDay(for: $0.date)
        }.mapValues { $0.reduce(0) { $0 + $1.amount } }

        let monthExpenseByDay = Dictionary(grouping: allExpenseSnapshots.filter { $0.date >= monthInterval.start && $0.date < monthInterval.end }) {
            calendar.startOfDay(for: $0.date)
        }.mapValues { $0.reduce(0) { $0 + $1.amount } }

        let actualIncome = monthIncomeByDay
            .filter { $0.key < actualLimit }
            .reduce(0) { $0 + $1.value }
        let actualExpenses = monthExpenseByDay
            .filter { $0.key < actualLimit }
            .reduce(0) { $0 + $1.value }

        if isPastMonth {
            return MonthlyProjection(income: actualIncome, expenses: actualExpenses, confidence: 1)
        }

        let historyEnd = min(monthInterval.start, actualLimit)
        let historyStart = calendar.date(byAdding: .month, value: -6, to: historyEnd) ?? calendar.date(byAdding: .day, value: -180, to: historyEnd) ?? historyEnd
        let historyStartDay = calendar.startOfDay(for: historyStart)
        let historyEndDay = calendar.startOfDay(for: historyEnd)

        let historyIncomes = allIncomeSnapshots.filter { $0.date >= historyStartDay && $0.date < historyEndDay }
        let historyExpenses = allExpenseSnapshots.filter { $0.date >= historyStartDay && $0.date < historyEndDay }

        let incomeByDay = Dictionary(grouping: historyIncomes) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        let hoursByDay = Dictionary(grouping: historyIncomes) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.hours } }
        let expenseByDay = Dictionary(grouping: historyExpenses) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.amount } }

        var weekdayOccurrences: [Int: Int] = [:]
        var weekdayIncomeTotal: [Int: Double] = [:]
        var weekdayExpenseTotal: [Int: Double] = [:]
        var weekdayShiftDays: [Int: Int] = [:]
        var weekdayShiftHours: [Int: Double] = [:]
        var trainingPairs: [(x: Double, y: Double)] = []
        var historyDaysCount = 0
        var shiftDaysCount = 0

        var cursor = historyStartDay
        while cursor < historyEndDay {
            historyDaysCount += 1
            let wd = calendar.component(.weekday, from: cursor)
            weekdayOccurrences[wd, default: 0] += 1

            let dayIncome = incomeByDay[cursor] ?? 0
            let dayExpense = expenseByDay[cursor] ?? 0
            let dayHours = hoursByDay[cursor] ?? 0

            weekdayIncomeTotal[wd, default: 0] += dayIncome
            weekdayExpenseTotal[wd, default: 0] += dayExpense
            if dayHours > 0 {
                shiftDaysCount += 1
                weekdayShiftDays[wd, default: 0] += 1
                weekdayShiftHours[wd, default: 0] += dayHours
            }
            trainingPairs.append((x: dayHours, y: dayExpense))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let totalHistoryIncome = historyIncomes.reduce(0) { $0 + $1.amount }
        let totalHistoryExpense = historyExpenses.reduce(0) { $0 + $1.amount }
        let safeHistoryDays = max(historyDaysCount, 1)
        let globalIncomePerDay = totalHistoryIncome / Double(safeHistoryDays)
        let globalExpensePerDay = totalHistoryExpense / Double(safeHistoryDays)
        let globalShiftProbability = Double(shiftDaysCount) / Double(safeHistoryDays)
        let globalHoursIfShift = shiftDaysCount > 0
            ? hoursByDay.values.reduce(0, +) / Double(shiftDaysCount)
            : 8

        let weekdayIncomePerDay = (1...7).reduce(into: [Int: Double]()) { result, wd in
            let occ = max(weekdayOccurrences[wd] ?? 0, 1)
            result[wd] = (weekdayIncomeTotal[wd] ?? 0) / Double(occ)
        }
        let weekdayExpensePerDay = (1...7).reduce(into: [Int: Double]()) { result, wd in
            let occ = max(weekdayOccurrences[wd] ?? 0, 1)
            result[wd] = (weekdayExpenseTotal[wd] ?? 0) / Double(occ)
        }
        let weekdayShiftProbability = (1...7).reduce(into: [Int: Double]()) { result, wd in
            let occ = max(weekdayOccurrences[wd] ?? 0, 1)
            let shifts = weekdayShiftDays[wd] ?? 0
            result[wd] = min(max(Double(shifts) / Double(occ), 0), 1)
        }
        let weekdayHoursIfShift = (1...7).reduce(into: [Int: Double]()) { result, wd in
            let shifts = max(weekdayShiftDays[wd] ?? 0, 1)
            let totalHours = weekdayShiftHours[wd] ?? 0
            result[wd] = shifts > 0 ? totalHours / Double(shifts) : globalHoursIfShift
        }

        let shiftDayExpenseValues = expenseByDay.compactMap { day, expense -> Double? in
            (hoursByDay[day] ?? 0) > 0 ? expense : nil
        }
        let offDayExpenseValues = expenseByDay.compactMap { day, expense -> Double? in
            (hoursByDay[day] ?? 0) == 0 ? expense : nil
        }
        let avgExpenseWorkDay = shiftDayExpenseValues.isEmpty
            ? globalExpensePerDay
            : shiftDayExpenseValues.reduce(0,+) / Double(shiftDayExpenseValues.count)
        let avgExpenseOffDay = offDayExpenseValues.isEmpty
            ? globalExpensePerDay
            : offDayExpenseValues.reduce(0,+) / Double(offDayExpenseValues.count)
        let expensePerHourSlope = max(0, linearSlopeXY(trainingPairs))

        let recurringPatternStrength: Double = {
            let grouped = Dictionary(grouping: historyExpenses) { snap -> String in
                let weekday = calendar.component(.weekday, from: snap.date)
                return "\(snap.category)|\(weekday)"
            }
            let repeating = grouped.values.filter { $0.count >= 2 }.count
            return min(Double(repeating) * 0.015, 0.18)
        }()

        let incomeSeries = monthlyTotalsSeries(
            from: allIncomeSnapshots.map { ($0.date, $0.amount) },
            months: 6,
            anchorMonth: monthStartDate
        )
        let expenseSeries = monthlyTotalsSeries(
            from: allExpenseSnapshots.map { ($0.date, $0.amount) },
            months: 6,
            anchorMonth: monthStartDate
        )
        let incomeTrend = incomeSeries.count > 1 ? linearSlopeXY(Array(incomeSeries.enumerated()).map { (x: Double($0.offset), y: $0.element) }) : 0
        let expenseTrend = expenseSeries.count > 1 ? linearSlopeXY(Array(expenseSeries.enumerated()).map { (x: Double($0.offset), y: $0.element) }) : 0
        let incomeMean = max(incomeSeries.reduce(0, +) / Double(max(incomeSeries.count, 1)), 1)
        let expenseMean = max(expenseSeries.reduce(0, +) / Double(max(expenseSeries.count, 1)), 1)
        let incomeTrendFactor = min(max(1 + (incomeTrend / incomeMean) * Double(monthsAhead) * 0.5, 0.75), 1.35)
        let expenseTrendFactor = min(max(1 + (expenseTrend / expenseMean) * Double(monthsAhead) * 0.45, 0.8), 1.3)

        var forecastIncome = actualIncome
        var forecastExpenses = actualExpenses

        cursor = monthInterval.start
        while cursor < monthInterval.end {
            let day = calendar.startOfDay(for: cursor)
            if day < actualLimit {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                cursor = next
                continue
            }

            let wd = calendar.component(.weekday, from: day)
            let shiftProb = weekdayShiftProbability[wd] ?? globalShiftProbability
            let expectedHours = (weekdayHoursIfShift[wd] ?? globalHoursIfShift) * shiftProb

            var predictedIncomeDay = weekdayIncomePerDay[wd] ?? globalIncomePerDay
            if predictedIncomeDay <= 0, !historyIncomes.isEmpty {
                let avgIncomePerShift = historyIncomes.reduce(0) { $0 + $1.amount } / Double(historyIncomes.count)
                predictedIncomeDay = avgIncomePerShift * shiftProb
            }
            predictedIncomeDay = max(0, predictedIncomeDay * incomeTrendFactor)

            let baseExpense = weekdayExpensePerDay[wd] ?? globalExpensePerDay
            let workMix = shiftProb * avgExpenseWorkDay + (1 - shiftProb) * avgExpenseOffDay
            let durationAdjustment = expensePerHourSlope * expectedHours
            var predictedExpenseDay = max(0, baseExpense * 0.55 + workMix * 0.45 + durationAdjustment * 0.25)
            predictedExpenseDay *= expenseTrendFactor
            predictedExpenseDay *= (1 + recurringPatternStrength * 0.35)

            forecastIncome += predictedIncomeDay
            forecastExpenses += predictedExpenseDay
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            cursor = next
        }

        let confidenceBase = Double(historyIncomes.count + historyExpenses.count) / 220.0
        let confidence = max(0.15, min(1.0, confidenceBase))
        return MonthlyProjection(income: max(forecastIncome, actualIncome),
                                 expenses: max(forecastExpenses, actualExpenses),
                                 confidence: confidence)
    }

    private var currentMonthIncome: Double {
        monthlyProjection.income
    }

    private var currentMonthExpenses: Double {
        monthlyProjection.expenses
    }

    private var monthlyForecastIncome: Double {
        monthlyProjection.income
    }

    private var monthlyForecastExpenses: Double {
        monthlyProjection.expenses
    }

    private var smartMonthlyIncomeForecast: Double {
        let points = allIncomeSnapshots.map { (date: $0.date, amount: $0.amount) }
        let series = monthlyTotalsSeries(from: points, months: 6, anchorMonth: forecastMonthStart)
        guard !series.isEmpty else { return monthlyForecastIncome }
        let ema = emaForecast(values: series, alpha: 0.5)
        let isFutureMonth = forecastMonthStart > monthStart(for: Date())
        let blended = isFutureMonth
            ? (monthlyForecastIncome * 0.72 + ema * 0.28)
            : max(monthlyForecastIncome, ema * 0.92)
        return max(0, blended)
    }

    private var smartMonthlyExpensesForecast: Double {
        let points = allExpenseSnapshots.map { (date: $0.date, amount: $0.amount) }
        let series = monthlyTotalsSeries(from: points, months: 6, anchorMonth: forecastMonthStart)
        guard !series.isEmpty else { return monthlyForecastExpenses }

        let ema = emaForecast(values: series, alpha: 0.52)
        let isFutureMonth = forecastMonthStart > monthStart(for: Date())
        let blended = isFutureMonth
            ? (monthlyForecastExpenses * 0.74 + ema * 0.26)
            : max(monthlyForecastExpenses, ema * 0.9)
        return max(0, blended)
    }

    private var smartMonthlyNetForecast: Double {
        smartMonthlyIncomeForecast - smartMonthlyExpensesForecast
    }
    
    private var expenseAnomalyInsight: String? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let recentStart = calendar.date(byAdding: .day, value: -13, to: today),
              let historyStart = calendar.date(byAdding: .day, value: -120, to: today)
        else { return nil }
        
        var historyByCategory: [String: [Double]] = [:]
        var recentByCategory: [String: Double] = [:]
        
        for expense in expenses {
            guard let date = expense.date else { continue }
            let amount = expense.amount
            let category = expense.category ?? NSLocalizedString("Другое", comment: "stats fallback type/category")
            if date >= historyStart, date < recentStart {
                historyByCategory[category, default: []].append(amount)
            } else if date >= recentStart, date <= today {
                recentByCategory[category, default: 0] += amount
            }
        }
        
        var strongest: (category: String, zScore: Double, recent: Double, average: Double)?
        for (category, recentValue) in recentByCategory where recentValue > 0 {
            let history = historyByCategory[category] ?? []
            guard history.count >= 5 else { continue }
            
            let mean = history.reduce(0, +) / Double(history.count)
            let variance = history.reduce(0) { $0 + pow($1 - mean, 2) } / Double(history.count)
            let std = sqrt(max(variance, 1))
            let zScore = (recentValue - mean) / std
            if zScore > 1.85, recentValue > mean * 1.3 {
                if strongest == nil || zScore > (strongest?.zScore ?? 0) {
                    strongest = (category: category, zScore: zScore, recent: recentValue, average: mean)
                }
            }
        }
        
        guard let strongest else { return nil }
        let deltaPercent = Int(((strongest.recent - strongest.average) / max(strongest.average, 1)) * 100)
        return String(
            format: NSLocalizedString("%@: +%d%% к обычному уровню", comment: "stats expense anomaly detail"),
            strongest.category,
            deltaPercent
        )
    }
    
    private struct InsightItem: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let value: String
        let tint: Color
        let priority: Int = 1
    }
    
    private var insightItems: [InsightItem] {
        var result: [InsightItem] = []
        
        if let bestWeekdayInsight {
            result.append(
                InsightItem(
                    icon: "calendar",
                    title: NSLocalizedString("Самый прибыльный день", comment: "stats insight title"),
                    value: bestWeekdayInsight,
                    tint: AppColors.accent
                )
            )
        }
        
        if averageIncomePerHourInsight > 0 {
            result.append(
                InsightItem(
                    icon: "clock.fill",
                    title: NSLocalizedString("Средний доход в час", comment: "stats insight title"),
                    value: formatCurrency(averageIncomePerHourInsight),
                    tint: AppColors.positive
                )
            )
        }
        
        if tipsShareInsight > 0 {
            result.append(
                InsightItem(
                    icon: "sparkles",
                    title: NSLocalizedString("Доля чаевых", comment: "stats insight title"),
                    value: String(format: "%.1f%%", tipsShareInsight),
                    tint: .orange
                )
            )
        }
        
        if let bestExpenseWeekdayInsight {
            result.append(
                InsightItem(
                    icon: "cart.fill.badge.minus",
                    title: NSLocalizedString("Пик расходов", comment: "stats insight title"),
                    value: bestExpenseWeekdayInsight,
                    tint: expenseColor
                )
            )
        }
        
        if monthlyForecastExpenses > 0 {
            result.append(
                InsightItem(
                    icon: "calendar.badge.clock",
                    title: NSLocalizedString("Прогноз расходов в месяц", comment: "stats insight title"),
                    value: formatCurrency(smartMonthlyExpensesForecast),
                    tint: expenseColor
                )
            )
        }

        if let holidayImpactInsightItem {
            result.append(holidayImpactInsightItem)
        }
        
        if smartMonthlyNetForecast != 0 {
            result.append(
                InsightItem(
                    icon: "waveform.path.ecg",
                    title: NSLocalizedString("Умный прогноз чистой прибыли", comment: "stats insight title"),
                    value: formatCurrency(smartMonthlyNetForecast),
                    tint: smartMonthlyNetForecast >= 0 ? incomeColor : expenseColor
                )
            )
        }
        
        if let expenseAnomalyInsight {
            result.append(
                InsightItem(
                    icon: "exclamationmark.triangle.fill",
                    title: NSLocalizedString("Аномалия расходов", comment: "stats insight title"),
                    value: expenseAnomalyInsight,
                    tint: Color(hex: "#A16B44") ?? .orange
                )
            )
        }

        result.append(contentsOf: budgetInsightItems)
        return Array(result.prefix(8))
    }

    private var holidayImpactInsightItem: InsightItem? {
        guard let upcoming = HolidayManager.shared.nextSignificantImpact(
            from: Date(),
            withinDays: 21,
            regionCode: settings.proHolidayRegionCode,
            minimumAbsPercent: 0.08
        ) else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let eventDay = calendar.startOfDay(for: upcoming.date)
        let daysUntil = max(0, calendar.dateComponents([.day], from: today, to: eventDay).day ?? 0)
        let daysText: String = {
            switch daysUntil {
            case 0:
                return NSLocalizedString("сегодня", comment: "stats holiday insight: today")
            case 1:
                return NSLocalizedString("завтра", comment: "stats holiday insight: tomorrow")
            default:
                return String(
                    format: NSLocalizedString("через %d дн.", comment: "stats holiday insight: in days"),
                    daysUntil
                )
            }
        }()

        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale()
        formatter.dateFormat = "d MMM"
        let dateText = formatter.string(from: upcoming.date)
        let impactPercent = Int(abs(upcoming.info.percent * 100).rounded())

        if upcoming.info.percent > 0 {
            return InsightItem(
                icon: "sparkles",
                title: NSLocalizedString("Праздничный потенциал", comment: "stats insight title: holiday potential"),
                value: String(
                    format: NSLocalizedString("%@ (%@): +%d%% к доходу", comment: "stats holiday insight value: positive impact"),
                    dateText,
                    daysText,
                    impactPercent
                ),
                tint: AppColors.accent
            )
        }

        return InsightItem(
            icon: "exclamationmark.triangle.fill",
            title: NSLocalizedString("Ожидается снижение спроса", comment: "stats insight title: expected demand drop"),
            value: String(
                format: NSLocalizedString("%@ (%@): -%d%% к доходу", comment: "stats holiday insight value: negative impact"),
                dateText,
                daysText,
                impactPercent
            ),
            tint: Color(hex: "#A16B44") ?? .orange
        )
    }

    private var budgetProgressItems: [(category: String, spent: Double, limit: Double, ratio: Double)] {
        expensesByCategory.compactMap { category, spent in
            guard let limit = settings.budgetLimit(for: category), limit > 0 else { return nil }
            return (category, spent, limit, spent / limit)
        }
        .sorted { $0.ratio > $1.ratio }
    }

    private var budgetInsightItems: [InsightItem] {
        guard settings.proBudgetWarningsEnabled,
              !settings.proBudgetLimits.isEmpty
        else { return [] }

        var alerts: [InsightItem] = []
        for (category, spent) in expensesByCategory {
            guard let limit = settings.budgetLimit(for: category), limit > 0 else { continue }
            let ratio = spent / limit
            if ratio >= 1 {
                let overPercent = Int((ratio - 1) * 100)
                alerts.append(
                    InsightItem(
                        icon: "xmark.octagon.fill",
                        title: String(
                            format: NSLocalizedString("Бюджет превышен: %@", comment: "stats budget exceeded title"),
                            category
                        ),
                        value: String(
                            format: NSLocalizedString("%@ из %@ (+%d%%)", comment: "stats budget exceeded value"),
                            formatCurrency(spent),
                            formatCurrency(limit),
                            max(overPercent, 1)
                        ),
                        tint: AppColors.negative
                    )
                )
            } else if ratio >= 0.85 {
                alerts.append(
                    InsightItem(
                        icon: "exclamationmark.circle.fill",
                        title: String(
                            format: NSLocalizedString("Бюджет на грани: %@", comment: "stats budget near limit title"),
                            category
                        ),
                        value: String(
                            format: NSLocalizedString("%@ из %@", comment: "stats budget near limit value"),
                            formatCurrency(spent),
                            formatCurrency(limit)
                        ),
                        tint: Color(hex: "#A16B44") ?? .orange
                    )
                )
            }
        }

        return alerts.sorted { lhs, rhs in
            let lhsSeverity = lhs.icon == "xmark.octagon.fill" ? 0 : 1
            let rhsSeverity = rhs.icon == "xmark.octagon.fill" ? 0 : 1
            if lhsSeverity != rhsSeverity { return lhsSeverity < rhsSeverity }
            return lhs.title < rhs.title
        }
    }
    
    private func weekdayName(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale()
        let symbols = formatter.standaloneWeekdaySymbols ?? formatter.weekdaySymbols ?? []
        guard weekday >= 1, weekday <= symbols.count else { return "—" }
        return symbols[weekday - 1].capitalized(with: AppLanguage.currentLocale())
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Период
                    VStack(spacing: 8) {
                        Picker(NSLocalizedString("Период", comment: "stats period picker title"), selection: $selectedPeriodIndex) {
                            ForEach(Array(periods.indices), id: \.self) { index in
                                Text(periods[index]).tag(index)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        // STYLE: Внутренние отступы вокруг сегмент-контрола периода.
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        // STYLE: Стеклянная карточка фильтра периода.
                        .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
                        .padding(.horizontal)
                        
                        if selectedPeriodIndex == 3 {
                            VStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(NSLocalizedString("С", comment: "stats custom period start"))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                    DatePicker(NSLocalizedString("С", comment: "stats custom period start"), selection: $customStartDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        // STYLE: Минимальная высота тач-зоны выбора даты.
                                        .frame(minHeight: 44)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                // STYLE: Отдельная стеклянная плашка даты начала.
                                .visionGlassCard(cornerRadius: 14, opacity: 0.82)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(NSLocalizedString("По", comment: "stats custom period end"))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                    DatePicker(NSLocalizedString("По", comment: "stats custom period end"), selection: $customEndDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(minHeight: 44)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                // STYLE: Отдельная стеклянная плашка даты окончания.
                                .visionGlassCard(cornerRadius: 14, opacity: 0.82)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 4)
                    
                    // Основные показатели
                    HStack(spacing: 7) {
                        StatCard(
                            title: NSLocalizedString("Доход", comment: "stats card: income"),
                            amount: totalIncome,
                            formattedAmount: formatCurrency(totalIncome),
                            color: incomeColor,
                            icon: "rublesign.circle.fill"
                        )
                        
                        StatCard(
                            title: NSLocalizedString("Расход", comment: "stats card: expense"),
                            amount: totalExpenses,
                            formattedAmount: formatCurrency(totalExpenses),
                            color: expenseColor,
                            icon: "creditcard.fill"
                        )
                        
                        StatCard(
                            title: NSLocalizedString("Чистый", comment: "stats card: net"),
                            amount: netProfit,
                            formattedAmount: formatCurrency(netProfit),
                            color: netProfit >= 0 ? AppColors.accent : expenseColor,
                            icon: "chart.line.uptrend.xyaxis"
                        )
                    }
                    // STYLE: Отступы ряда KPI-карточек от краев экрана.
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "brain.head.profile")
                                .font(.subheadline)
                                .foregroundColor(AppColors.accent)
                            Text(NSLocalizedString("Инсайты", comment: "stats insights title"))
                                .font(.headline)
                                .foregroundColor(AppColors.text)
                            Spacer()
                            if insightItems.count > 3 {
                                Button(showAllInsights
                                       ? NSLocalizedString("Свернуть", comment: "stats action collapse")
                                       : NSLocalizedString("Показать все", comment: "stats action show all")) {
                                    performUIUpdate(.easeInOut(duration: 0.2)) {
                                        showAllInsights.toggle()
                                    }
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.accent)
                                .frame(minHeight: 44)
                                .buttonStyle(.plain)
                            }
                        }
                        
                        if insightItems.isEmpty {
                            Text(NSLocalizedString("Добавьте больше данных, и здесь появятся подсказки по доходам.", comment: "stats insights empty state"))
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(AppColors.secondaryText)
                        } else {
                            ForEach(showAllInsights ? insightItems : Array(insightItems.prefix(3))) { insight in
                                HStack(spacing: 10) {
                                    Image(systemName: insight.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(insight.tint)
                                        // STYLE: Размер иконки инсайта и цветовой маркер категории.
                                        .frame(width: 26, height: 26)
                                        .visionGlassCard(cornerRadius: 8, opacity: 0.78)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(insight.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(AppColors.secondaryText)
                                        Text(insight.value)
                                            .font(.system(size: 15, weight: .semibold))
                                            .fontWeight(.semibold)
                                            .foregroundColor(AppColors.text)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                // STYLE: Полупрозрачный фон строки инсайта.
                                .visionGlassCard(cornerRadius: 10, opacity: 0.82, showRing: true)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        // STYLE: Нейтральная обводка без цветного оттенка.
                                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    // STYLE: Общий визуальный контейнер секции инсайтов.
                    .visionGlassCard(cornerRadius: 18, opacity: 0.84, showRing: true)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(
                                NSLocalizedString("Бюджеты", comment: "stats budgets section title"),
                                systemImage: "gauge.medium"
                            )
                            .font(.headline)
                            .foregroundColor(AppColors.text)

                            Spacer()

                            Button(NSLocalizedString("Настроить", comment: "stats budgets configure action")) {
                                showBudgetSettings = true
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.accent)
                            .frame(minHeight: 44)
                        }

                        if budgetProgressItems.isEmpty {
                            Text(NSLocalizedString("Лимиты не заданы. Добавьте бюджеты по категориям, чтобы видеть контроль расходов.", comment: "stats budgets empty state"))
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(AppColors.secondaryText)
                        } else {
                            if budgetProgressItems.count > 3 {
                                Button(showAllBudgetItems
                                       ? NSLocalizedString("Свернуть категории", comment: "stats budgets action collapse categories")
                                       : NSLocalizedString("Показать все категории", comment: "stats budgets action show all categories")) {
                                    performUIUpdate(.easeInOut(duration: 0.2)) {
                                        showAllBudgetItems.toggle()
                                    }
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.accent)
                                .buttonStyle(.plain)
                            }

                            ForEach(Array((showAllBudgetItems ? budgetProgressItems : Array(budgetProgressItems.prefix(3)))), id: \.category) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(item.category)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(AppColors.text)
                                        Spacer()
                                        Text(String(
                                            format: NSLocalizedString("%@ из %@", comment: "stats budget row spent of limit"),
                                            formatCurrency(item.spent),
                                            formatCurrency(item.limit)
                                        ))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppColors.secondaryText)
                                    }

                                    ProgressView(value: min(max(item.ratio, 0), 1))
                                        // STYLE: Цвет прогресса: красный (превышен), янтарный (на грани), зеленый (норма).
                                        .tint(item.ratio >= 1 ? AppColors.negative : (item.ratio >= 0.85 ? (Color(hex: "#A16B44") ?? .orange) : AppColors.positive))
                                        // STYLE: Чуть толще полоса прогресса для читаемости.
                                        .scaleEffect(x: 1, y: 1.25, anchor: .center)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .visionGlassCard(cornerRadius: 10, opacity: 0.82, showRing: true)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    // STYLE: Общий визуальный контейнер секции бюджетов.
                    .visionGlassCard(cornerRadius: 18, opacity: 0.84, showRing: true)
                    .padding(.horizontal)
                    
                    // Переключатель типа данных
                    Picker(NSLocalizedString("Тип данных", comment: "stats data type picker title"), selection: $selectedDataType) {
                        ForEach(Array(dataTypes.indices), id: \.self) { index in
                            Text(dataTypes[index]).tag(index)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    // STYLE: Стеклянный фильтр типа данных (всё/доходы/расходы).
                    .visionGlassCard(cornerRadius: 16, opacity: 0.84)
                    .padding(.horizontal)
                    
                    // Детализация по категориям
                    if selectedDataType == 2 {
                        // Расходы
                        if !sortedExpenses.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(NSLocalizedString("Расходы по категориям", comment: "stats section title: expenses by category"))
                                    .font(.headline)
                                    .foregroundColor(AppColors.text)
                                    .padding(.horizontal)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(sortedExpenses, id: \.name) { item in
                                            CategoryCard(
                                                category: item.name,
                                                amount: item.amount,
                                                currency: settings.defaultCurrency,
                                                color: item.color,
                                                icon: item.icon
                                            )
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.top, 8)
                        }
                    } else if selectedDataType == 1 {
                        // Доходы
                        if !sortedIncomes.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(NSLocalizedString("Доходы по видам работ", comment: "stats section title: income by work type"))
                                    .font(.headline)
                                    .foregroundColor(AppColors.text)
                                    .padding(.horizontal)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(sortedIncomes, id: \.name) { item in
                                            TypeCard(
                                                type: item.name,
                                                amount: item.amount,
                                                currency: settings.defaultCurrency,
                                                icon: getIconForWorkType(item.name),
                                                color: item.color
                                            )
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.top, 8)
                        }
                    } else {
                        // Всё - сначала сводка за период, затем прогресс целей
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("Сводка за период", comment: "stats section title: period summary"))
                                .font(.headline)
                                .foregroundColor(AppColors.text)
                                .padding(.horizontal)
                            
                            VStack(spacing: 6) {
                                HStack {
                                    Text(NSLocalizedString("Доходы", comment: "stats summary label: incomes"))
                                        .font(.subheadline)
                                        .foregroundColor(AppColors.secondaryText)
                                    Spacer()
                                    Text(formatCurrency(totalIncome))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(incomeColor)
                                }
                                
                                HStack {
                                    Text(NSLocalizedString("Расходы", comment: "stats summary label: expenses"))
                                        .font(.subheadline)
                                        .foregroundColor(AppColors.secondaryText)
                                    Spacer()
                                    Text(formatCurrency(totalExpenses))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(expenseColor)
                                }
                                
                                Divider()
                                    .background(AppColors.border)
                                    .padding(.vertical, 2)
                                
                                HStack {
                                    Text(NSLocalizedString("Прогноз расходов (мес)", comment: "stats summary label: expense forecast month"))
                                        .font(.subheadline)
                                        .foregroundColor(AppColors.secondaryText)
                                    Spacer()
                                    Text(formatCurrency(smartMonthlyExpensesForecast))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(expenseColor)
                                }
                                
                                if netProfit != 0 {
                                    Divider()
                                        .background(AppColors.border)
                                        .padding(.vertical, 2)
                                    
                                    HStack {
                                        Text(NSLocalizedString("Чистая прибыль", comment: "stats summary label: net profit"))
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(AppColors.text)
                                        Spacer()
                                        Text(formatCurrency(netProfit))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(netProfit >= 0 ? incomeColor : expenseColor)
                                    }
                                }
                                
                                HStack {
                                    Text(NSLocalizedString("Прогноз чистой прибыли", comment: "stats summary label: net profit forecast"))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(AppColors.text)
                                    Spacer()
                                    Text(formatCurrency(smartMonthlyNetForecast))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(smartMonthlyNetForecast >= 0 ? incomeColor : expenseColor)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top, 8)

                        if !activeGoals.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(NSLocalizedString("Прогресс целей", comment: "stats section title: goals progress"))
                                    .font(.headline)
                                    .foregroundColor(AppColors.text)
                                    .padding(.horizontal)
                                
                                if activeGoals.count == 1, let goal = activeGoals.first {
                                    SingleGoalProgressView(
                                        goal: goal,
                                        currency: settings.defaultCurrency,
                                        totalNetProfit: totalNetProfitAllTime
                                    )
                                    .padding(.horizontal)
                                } else {
                                    MultipleGoalsProgressView(
                                        goals: activeGoals,
                                        currency: settings.defaultCurrency,
                                        totalTarget: totalGoalTarget,
                                        totalCurrent: totalGoalCurrent,
                                        totalNetProfit: totalNetProfitAllTime
                                    )
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    
                    // Графики
                    if #available(iOS 16.0, *) {
                        Picker(NSLocalizedString("Тип графика", comment: "stats chart type picker title"), selection: $selectedChart) {
                            ForEach(Array(charts.indices), id: \.self) { index in
                                Text(charts[index]).tag(index)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .visionGlassCard(cornerRadius: 16, opacity: 0.84)
                        .padding(.horizontal)
                        
                        if selectedChart == 0 {
                            // Линейный график
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("Динамика", comment: "stats chart section title: dynamics"))
                                    .font(.headline)
                                    .foregroundColor(AppColors.text)
                                    .padding(.horizontal)
                                
                                CombinedChartView(
                                    incomes: filteredIncomes,
                                    expenses: filteredExpenses,
                                    currency: settings.defaultCurrency,
                                    incomeColor: incomeColor,
                                    expenseColor: expenseColor
                                )
                                .frame(height: 200)
                                .padding()
                                .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                                .padding(.horizontal)
                            }
                        } else {
                            // Круговая диаграмма
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("Структура", comment: "stats chart section title: structure"))
                                    .font(.headline)
                                    .foregroundColor(AppColors.text)
                                    .padding(.horizontal)
                                
                                if selectedDataType == 2 {
                                    ExpensesPieChartView(
                                        expensesByCategory: expensesByCategory,
                                        colorForCategory: colorForExpenseCategory
                                    )
                                    .frame(height: 200)
                                    .padding()
                                    .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                                    .padding(.horizontal)
                                } else if selectedDataType == 1 {
                                    IncomePieChartView(
                                        incomesByType: incomesByType,
                                        tipsTotal: tipsTotal,
                                        colorForWorkType: colorForWorkType,
                                        tipsColor: tipsColor
                                    )
                                    .frame(height: 200)
                                    .padding()
                                    .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                                    .padding(.horizontal)
                                } else {
                                    SimplePieChartView(
                                        income: totalIncome,
                                        expense: totalExpenses,
                                        incomeColor: incomeColor,
                                        expenseColor: expenseColor
                                    )
                                    .frame(height: 200)
                                    .padding()
                                    .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(VisionBackdropView())
            .navigationTitle(NSLocalizedString("Статистика", comment: "statistics screen title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .accentColor(AppColors.accent)
        .sheet(isPresented: $showBudgetSettings) {
            BudgetSettingsSheet(settings: settings)
        }
    }
    
    private func getIconForWorkType(_ type: String) -> String {
        if let workType = settings.workTypes.first(where: { $0.name == type }) {
            return workType.icon
        }
        return "briefcase"
    }
}

// MARK: - StatCard
struct StatCard: View {
    let title: String
    let amount: Double
    let formattedAmount: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                    // STYLE: Фиксированный размер плашки иконки.
                    .frame(width: 30, height: 30)
                    .visionGlassCard(cornerRadius: 11, opacity: 0.78)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(formattedAmount)
                // STYLE: Крупная сумма в карточке KPI.
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        // STYLE: Единая высота всех KPI-карточек для ровной сетки.
        .frame(minHeight: 100, maxHeight: 100)
        .padding(12)
        .visionGlassCard(cornerRadius: 18, opacity: 0.84, showRing: true)
    }
}

// MARK: - TypeCard
struct TypeCard: View {
    let type: String
    let amount: Double
    let currency: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .visionGlassCard(cornerRadius: 10, opacity: 0.78)
                Text(type)
                    .font(.headline)
                    .foregroundColor(AppColors.text)
                    .lineLimit(1)
            }
            
            Text(String(format: "+%.0f %@", amount, currency))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding()
        // STYLE: Фиксированная ширина карточки для горизонтального скролла.
        .frame(width: 160, alignment: .leading)
        .visionGlassCard(cornerRadius: 16, opacity: 0.85, showRing: true)
    }
}

// MARK: - CategoryCard
struct CategoryCard: View {
    let category: String
    let amount: Double
    let currency: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(category)
                    .font(.headline)
                    .foregroundColor(AppColors.text)
                    .lineLimit(1)
            }
            
            Text(String(format: "-%.0f %@", amount, currency))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding()
        // STYLE: Фиксированная ширина карточки категории расхода.
        .frame(width: 160, alignment: .leading)
        .visionGlassCard(cornerRadius: 16, opacity: 0.85, showRing: true)
    }
}

// MARK: - SingleGoalProgressView
struct SingleGoalProgressView: View {
    let goal: FinancialGoal
    let currency: String
    let totalNetProfit: Double
    
    var currentWithProfit: Double {
        goal.currentAmount + (totalNetProfit > 0 ? totalNetProfit : 0)
    }
    
    var progress: Double {
        (min(currentWithProfit, goal.targetAmount) / goal.targetAmount) * 100
    }
    
    var remaining: Double {
        max(goal.targetAmount - currentWithProfit, 0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(goal.name ?? NSLocalizedString("Цель", comment: "goal fallback title"))
                    .font(.headline)
                    .foregroundColor(AppColors.text)
                Spacer()
                if let deadline = goal.deadline {
                    Text(deadline, style: .date)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        // STYLE: Фон прогресс-бара цели.
                        .frame(width: geometry.size.width, height: 8)
                        .foregroundColor(AppColors.border)
                        .cornerRadius(4)
                    
                    Rectangle()
                        // STYLE: Заполнение прогресса цели (зеленый).
                        .frame(width: geometry.size.width * CGFloat(min(progress / 100, 1.0)), height: 8)
                        .foregroundColor(AppColors.positive)
                        .cornerRadius(4)
                        .lightweightAnimation(.spring(), value: progress)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text(NSLocalizedString("Накоплено:", comment: "stats goal card label: saved"))
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                Text("\(Int(currentWithProfit)) \(currency)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.positive)
                
                Spacer()
                
                Text(NSLocalizedString("Цель:", comment: "goal target label"))
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                Text("\(Int(goal.targetAmount)) \(currency)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.accent)
            }
            
            HStack {
                Text(NSLocalizedString("Выполнено:", comment: "goal completed label"))
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                Text(String(format: "%.1f%%", progress))
                    .font(.title3)
                    .fontWeight(.semibold)
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
                            currency
                        )
                    )
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            if totalNetProfit > 0 && progress < 100 {
                HStack {
                    Text(NSLocalizedString("+ Чистая прибыль:", comment: "goal extra net profit label"))
                        .font(.caption2)
                        .foregroundColor(AppColors.secondaryText)
                    Text("\(Int(totalNetProfit)) \(currency)")
                        .font(.caption2)
                        .foregroundColor(AppColors.positive)
                        .fontWeight(.semibold)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        // STYLE: Карточка цели в общем стиле экрана.
        .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
    }
}

// MARK: - MultipleGoalsProgressView
struct MultipleGoalsProgressView: View {
    let goals: [FinancialGoal]
    let currency: String
    let totalTarget: Double
    let totalCurrent: Double
    let totalNetProfit: Double
    
    var totalCurrentWithProfit: Double {
        totalCurrent + (totalNetProfit > 0 ? totalNetProfit : 0)
    }
    
    var progress: Double {
        guard totalTarget > 0 else { return 0 }
        return (min(totalCurrentWithProfit, totalTarget) / totalTarget) * 100
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(
                    String(
                        format: NSLocalizedString("Всего целей: %d", comment: "goals total count"),
                        goals.count
                    )
                )
                    .font(.headline)
                    .foregroundColor(AppColors.text)
                
                Spacer()
                
                Text("\(Int(progress))%")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.accent)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(AppColors.border)
                        .frame(width: geometry.size.width, height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        // STYLE: Заполнение агрегированного прогресса всех целей.
                        .fill(AppColors.accent)
                        .frame(width: geometry.size.width * CGFloat(min(progress / 100, 1.0)), height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text(NSLocalizedString("Накоплено:", comment: "stats goals aggregate label: saved"))
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                Text("\(Int(totalCurrentWithProfit)) \(currency)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.accent)
            }
            
            HStack {
                Text(NSLocalizedString("Требуется:", comment: "stats goals aggregate label: required"))
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                Text("\(Int(totalTarget)) \(currency)")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
            }
            
            if !goals.isEmpty {
                Text(NSLocalizedString("Ближайшие:", comment: "goals nearest section title"))
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.top, 4)
                
                ForEach(goals.prefix(2)) { goal in
                    HStack {
                        Text(goal.name ?? NSLocalizedString("Цель", comment: "goal fallback title"))
                            .font(.caption2)
                            .foregroundColor(AppColors.text)
                        Spacer()
                        if let deadline = goal.deadline {
                            Text(deadline, style: .date)
                                .font(.caption2)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
            }
        }
        .padding()
        // STYLE: Карточка агрегированного прогресса.
        .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
    }
}

// MARK: - CombinedChartView
@available(iOS 16.0, *)
struct CombinedChartView: View {
    let incomes: [Income]
    let expenses: [Expense]
    let currency: String
    let incomeColor: Color
    let expenseColor: Color
    
    private var groupedByDay: [(key: Date, income: Double, expense: Double)] {
        let calendar = Calendar.current
        
        let incomeGrouped = Dictionary(grouping: incomes) { income in
            calendar.startOfDay(for: income.date ?? Date())
        }.mapValues { items in
            items.reduce(0) { $0 + ($1.hoursWorked * $1.hourlyRate) + $1.tips + $1.floatingAmount }
        }
        
        let expenseGrouped = Dictionary(grouping: expenses) { expense in
            calendar.startOfDay(for: expense.date ?? Date())
        }.mapValues { items in
            items.reduce(0) { $0 + $1.amount }
        }
        
        let allDates = Set(incomeGrouped.keys).union(expenseGrouped.keys).sorted()
        
        return allDates.map { date in
            (
                key: date,
                income: incomeGrouped[date] ?? 0,
                expense: expenseGrouped[date] ?? 0
            )
        }
    }
    
    var body: some View {
        let incomeLegend = NSLocalizedString("Доход", comment: "statistics chart legend: income")
        let expenseLegend = NSLocalizedString("Расход", comment: "statistics chart legend: expense")
        Chart {
            ForEach(groupedByDay, id: \.key) { day in
                BarMark(
                    x: .value("День", day.key, unit: .day),
                    y: .value("Сумма", day.income)
                )
                // STYLE: Цвет столбцов доходов.
                .foregroundStyle(incomeColor.gradient)
                .position(by: .value("Тип", incomeLegend))
                
                BarMark(
                    x: .value("День", day.key, unit: .day),
                    y: .value("Сумма", day.expense)
                )
                // STYLE: Цвет столбцов расходов.
                .foregroundStyle(expenseColor.gradient)
                .position(by: .value("Тип", expenseLegend))
            }
        }
        // STYLE: Явная привязка легенды к цветам серий.
        .chartForegroundStyleScale([
            incomeLegend: incomeColor,
            expenseLegend: expenseColor
        ])
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel()
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel()
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
    }
}

// MARK: - IncomePieChartView
@available(iOS 16.0, *)
struct IncomePieChartView: View {
    let incomesByType: [String: Double]
    let tipsTotal: Double
    let colorForWorkType: (String) -> Color
    let tipsColor: Color
    
    var body: some View {
        Chart {
            ForEach(Array(incomesByType.keys.sorted()), id: \.self) { type in
                if let amount = incomesByType[type] {
                    SectorMark(
                        angle: .value("Сумма", amount),
                        // STYLE: Толщина кольца диаграммы.
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(colorForWorkType(type))
                    .annotation(position: .overlay) {
                        if amount > 0 && amount > tipsTotal * 0.1 {
                            Text("\(Int(amount))")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            if tipsTotal > 0 {
                SectorMark(
                    angle: .value("Чаевые", tipsTotal),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                // STYLE: Отдельный цвет сектора чаевых.
                .foregroundStyle(tipsColor)
                .annotation(position: .overlay) {
                    if tipsTotal > 0 {
                        Text("\(Int(tipsTotal))")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        // STYLE: Легенда вынесена вниз для компактности графика.
        .chartLegend(position: .bottom)
    }
}

// MARK: - ExpensesPieChartView
@available(iOS 16.0, *)
struct ExpensesPieChartView: View {
    let expensesByCategory: [String: Double]
    let colorForCategory: (String) -> Color
    
    var body: some View {
        Chart {
            ForEach(Array(expensesByCategory.keys.sorted()), id: \.self) { category in
                if let amount = expensesByCategory[category] {
                    SectorMark(
                        angle: .value("Сумма", amount),
                        // STYLE: Кольцевая форма и зазор между секторами.
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(colorForCategory(category))
                    .annotation(position: .overlay) {
                        if amount > 0 {
                            Text("\(Int(amount))")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .chartLegend(position: .bottom)
    }
}

// MARK: - SimplePieChartView
@available(iOS 16.0, *)
struct SimplePieChartView: View {
    let income: Double
    let expense: Double
    let incomeColor: Color
    let expenseColor: Color
    
    var body: some View {
        Chart {
            if income > 0 {
                SectorMark(
                    angle: .value("Доход", income),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                // STYLE: Цвет сектора доходов.
                .foregroundStyle(incomeColor)
                .annotation(position: .overlay) {
                    Text("\(Int(income))")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
            }
            if expense > 0 {
                SectorMark(
                    angle: .value("Расход", expense),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                // STYLE: Цвет сектора расходов.
                .foregroundStyle(expenseColor)
                .annotation(position: .overlay) {
                    Text("\(Int(expense))")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
            }
        }
        .chartLegend(position: .bottom)
    }
}
