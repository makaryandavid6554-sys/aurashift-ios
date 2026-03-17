//
//  HistoryView.swift
//  AuraShift
//
//  Created by David Makarian on 24.02.2026.
//

import SwiftUI
import CoreData
import UIKit

struct HistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var settings: UserSettings
    
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
    
    // MARK: - Фильтр по дате (период или один день)
    @State private var filterStartDate: Date? = nil
    @State private var filterEndDate: Date? = nil
    @State private var showCalendar = false
    
    @State private var selectedFilter = 0
    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    @State private var exportError: String?
    @State private var isGeneratingPDF = false // индикатор загрузки
    
    private var filters: [String] {
        [
            NSLocalizedString("Все", comment: "history filter: all"),
            NSLocalizedString("Доходы", comment: "history filter: incomes"),
            NSLocalizedString("Расходы", comment: "history filter: expenses")
        ]
    }
    private let calendar = Calendar.current
    
    // MARK: - Body
    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            VStack {
                Picker(NSLocalizedString("Тип", comment: "history filter picker title"), selection: $selectedFilter) {
                    ForEach(Array(filters.indices), id: \.self) { index in
                        Text(filters[index]).tag(index)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                if groupedByDate.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(AppColors.text)
                            .frame(width: 72, height: 72)
                            .visionGlassCard(cornerRadius: 22, opacity: 0.84, showRing: true)
                        Text(NSLocalizedString("История пока пустая", comment: "history empty state title"))
                            .font(.title3.weight(.semibold))
                            .foregroundColor(AppColors.text)
                        Text(NSLocalizedString("Добавьте доходы или расходы, чтобы видеть хронологию.", comment: "history empty state subtitle"))
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                } else {
                    List {
                        ForEach(groupedByDate) { group in
                            Section(header: sectionHeader(for: group)) {
                                ForEach(group.items) { item in
                                    historyRow(for: item)
                                }
                                .onDelete { offsets in
                                    deleteItems(items: group.items, offsets: offsets)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .visionListBackground()
                }
            }
            .background(VisionBackdropView())
            .navigationTitle(NSLocalizedString("История", comment: "history screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Кнопка экспорта в CSV
                    Button(action: exportHistoryCSV) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(AppColors.accent)
                    }
                    .disabled(historyEntries.isEmpty || isGeneratingPDF)

                    // Кнопка экспорта в Excel (Pro)
                    if ProManager.shared.canUse(.xlsxExport) {
                        Button(action: exportHistoryXLSX) {
                            Image(systemName: "tablecells")
                                .foregroundColor(AppColors.accent)
                        }
                        .disabled(historyEntries.isEmpty || isGeneratingPDF)
                    }
                    
                    // Кнопка экспорта в PDF (с индикатором загрузки)
                    if isGeneratingPDF {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.accent))
                    } else {
                        Button(action: exportHistoryPDF) {
                            Image(systemName: "doc.richtext")
                                .foregroundColor(AppColors.accent)
                        }
                        .disabled(historyEntries.isEmpty)
                    }
                    
                    // Кнопка выбора периода (календарь)
                    Button(action: { showCalendar.toggle() }) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
            .accentColor(AppColors.accent)
            .sheet(isPresented: $showCalendar) {
                CustomCalendarSheet(
                    startDate: $filterStartDate,
                    endDate: $filterEndDate,
                    isPresented: $showCalendar
                )
                .presentationDetents([.height(440)])
            }
            .sheet(isPresented: $showingShareSheet, onDismiss: clearExportFile) {
                if let exportURL {
                    ActivityViewController(activityItems: [exportURL])
                }
            }
            .alert(NSLocalizedString("Экспорт недоступен", comment: "history export unavailable alert title"), isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button(NSLocalizedString("OK", comment: "common ok action"), role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
        }
    }
    
    // MARK: - History Entry Enum
    private enum HistoryEntry: Identifiable {
        case income(Income)
        case expense(Expense)
        
        var id: NSManagedObjectID {
            switch self {
            case .income(let income): return income.objectID
            case .expense(let expense): return expense.objectID
            }
        }
        
        var date: Date {
            switch self {
            case .income(let income): return income.date ?? Date()
            case .expense(let expense): return expense.date ?? Date()
            }
        }
        
        var signedAmount: Double {
            switch self {
            case .income(let income):
                return income.hoursWorked * income.hourlyRate + income.tips + income.floatingAmount
            case .expense(let expense):
                return -expense.amount
            }
        }
    }
    
    // MARK: - History Day Group
    private struct HistoryDayGroup: Identifiable {
        let date: Date
        var items: [HistoryEntry]
        var dayTotal: Double
        
        var id: Date { date }
    }
    
    // MARK: - Computed Properties
    private var historyEntries: [HistoryEntry] {
        var entries: [HistoryEntry] = []
        
        if selectedFilter == 0 || selectedFilter == 1 {
            for income in incomes {
                let date = income.date ?? Date()
                guard shouldIncludeDate(date) else { continue }
                entries.append(.income(income))
            }
        }
        
        if selectedFilter == 0 || selectedFilter == 2 {
            for expense in expenses {
                let date = expense.date ?? Date()
                guard shouldIncludeDate(date) else { continue }
                entries.append(.expense(expense))
            }
        }
        
        return entries.sorted { $0.date > $1.date }
    }
    
    private var groupedByDate: [HistoryDayGroup] {
        var grouped: [Date: HistoryDayGroup] = [:]
        
        for entry in historyEntries {
            let day = calendar.startOfDay(for: entry.date)
            var group = grouped[day] ?? HistoryDayGroup(date: day, items: [], dayTotal: 0)
            group.items.append(entry)
            group.dayTotal += entry.signedAmount
            grouped[day] = group
        }
        
        return grouped.values
            .map { group in
                var updated = group
                updated.items.sort { $0.date > $1.date }
                return updated
            }
            .sorted { $0.date > $1.date }
    }
    
    private func shouldIncludeDate(_ date: Date) -> Bool {
        guard let start = filterStartDate else { return true } // нет фильтра
        let day = calendar.startOfDay(for: date)
        let startDay = calendar.startOfDay(for: start)
        
        if let end = filterEndDate {
            // диапазон
            let endDay = calendar.startOfDay(for: end)
            return day >= startDay && day <= endDay
        } else {
            // один день
            return day == startDay
        }
    }
    
    // STYLE: `sectionHeader(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private func sectionHeader(for group: HistoryDayGroup) -> some View {
        HStack {
            Text(formattedSectionDate(group.date))
                .font(.headline)
                .foregroundColor(AppColors.text)
            Spacer()
            let dayTotal = group.dayTotal
            if dayTotal != 0 {
                Text(
                    String(
                        format: NSLocalizedString("Итого: %.0f %@", comment: "history day total"),
                        dayTotal,
                        settings.defaultCurrency
                    )
                )
                    .font(.subheadline)
                    .foregroundColor(dayTotal >= 0 ? AppColors.positive : AppColors.negative)
            }
        }
    }

    private func formattedSectionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = settings.appLanguage.locale
        return formatter.string(from: date)
    }
    
    @ViewBuilder
    // STYLE: `historyRow(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private func historyRow(for item: HistoryEntry) -> some View {
        switch item {
        case .income(let income):
            IncomeHistoryRow(income: income, settings: settings)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        case .expense(let expense):
            ExpenseHistoryRow(expense: expense, settings: settings)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }
    
    // MARK: - Delete
    private func deleteItems(items: [HistoryEntry], offsets: IndexSet) {
        for index in offsets {
            let item = items[index]
            switch item {
            case .income(let income):
                viewContext.delete(income)
            case .expense(let expense):
                viewContext.delete(expense)
            }
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Ошибка удаления: \(error)")
        }
    }
    
    // MARK: - CSV Export
    private func exportHistoryCSV() {
        guard !historyEntries.isEmpty else {
            exportError = NSLocalizedString("Нет данных для выгрузки.", comment: "history export: no data")
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        var lines: [String] = []
        lines.append("date,type,name_or_category,amount,currency,hours,rate,tips,note")
        
        for entry in historyEntries {
            switch entry {
            case .income(let income):
                let incomeAmount = income.hoursWorked * income.hourlyRate + income.tips + income.floatingAmount
                let row = [
                    formatter.string(from: income.date ?? Date()),
                    "income",
                    income.type ?? NSLocalizedString("Источник", comment: "history csv fallback source"),
                    String(format: "%.2f", incomeAmount),
                    settings.defaultCurrency,
                    String(format: "%.2f", income.hoursWorked),
                    String(format: "%.2f", income.hourlyRate),
                    String(format: "%.2f", income.tips),
                    income.note ?? ""
                ]
                lines.append(row.map(escapeCSV).joined(separator: ","))
            case .expense(let expense):
                let row = [
                    formatter.string(from: expense.date ?? Date()),
                    "expense",
                    expense.category ?? NSLocalizedString("Расход", comment: "history csv fallback expense"),
                    String(format: "%.2f", expense.amount),
                    settings.defaultCurrency,
                    "",
                    "",
                    "",
                    expense.notes ?? ""
                ]
                lines.append(row.map(escapeCSV).joined(separator: ","))
            }
        }
        
        let fileName = "AuraShift-History-\(Int(Date().timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showingShareSheet = true
        } catch {
            exportError = NSLocalizedString("Не удалось сформировать CSV-файл.", comment: "history csv export failure")
        }
    }

    // MARK: - XLSX Export (Pro)
    private func exportHistoryXLSX() {
        guard !historyEntries.isEmpty else {
            exportError = NSLocalizedString("Нет данных для выгрузки.", comment: "history export: no data")
            return
        }

        let incomes = historyEntries.compactMap { entry -> Income? in
            if case .income(let income) = entry { return income }
            return nil
        }
        let expenses = historyEntries.compactMap { entry -> Expense? in
            if case .expense(let expense) = entry { return expense }
            return nil
        }

        let sortedDates = historyEntries.map(\.date).sorted()
        let startDate = sortedDates.first ?? Date()
        let endDate = sortedDates.last ?? Date()

        guard let url = ExportManager.shared.generateXLSX(
            incomes: incomes,
            expenses: expenses,
            currency: settings.defaultCurrency,
            from: startDate,
            to: endDate
        ) else {
            exportError = NSLocalizedString("Не удалось сформировать XLSX-файл.", comment: "history xlsx export failure")
            return
        }

        exportURL = url
        showingShareSheet = true
    }
    
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
    
    // MARK: - PDF Export (с фоном и индикатором)
    private func exportHistoryPDF() {
        guard !historyEntries.isEmpty else {
            exportError = NSLocalizedString("Нет данных для выгрузки.", comment: "history export: no data")
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = settings.appLanguage.locale
        
        isGeneratingPDF = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let pdfData = self.generatePDFReport(entries: self.historyEntries, formatter: formatter)
            let fileName = "AuraShift-Report-\(Int(Date().timeIntervalSince1970)).pdf"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
            do {
                try pdfData.write(to: url)
                DispatchQueue.main.async {
                    self.exportURL = url
                    self.showingShareSheet = true
                    self.isGeneratingPDF = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.exportError = NSLocalizedString("Не удалось сформировать PDF-файл.", comment: "history pdf export failure")
                    self.isGeneratingPDF = false
                }
            }
        }
    }
    
    // MARK: - Генерация PDF (современный дизайн)
    private func generatePDFReport(entries: [HistoryEntry], formatter: DateFormatter) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let margin: CGFloat = 32
        let usableWidth = pageRect.width - margin * 2
        
        // Цветовая схема
        let backgroundColor = UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0)
        let surfaceColor = UIColor.white
        let textColor = UIColor(red: 0.13, green: 0.13, blue: 0.18, alpha: 1.0)
        let secondaryTextColor = UIColor(red: 0.45, green: 0.47, blue: 0.55, alpha: 1.0)
        let accentColor = UIColor(red: 0.29, green: 0.39, blue: 0.54, alpha: 1.0)
        let positiveColor = UIColor(red: 0.22, green: 0.60, blue: 0.44, alpha: 1.0)
        let negativeColor = UIColor(red: 0.85, green: 0.30, blue: 0.30, alpha: 1.0)
        let separatorColor = UIColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1.0)
        
        // Цвета доходов — берём из настроек смен пользователя (workType.colorHex)
        let workTypeColorMap: [String: UIColor] = Dictionary(
            uniqueKeysWithValues: settings.workTypes.compactMap { wt -> (String, UIColor)? in
                guard let swiftColor = Color(hex: wt.colorHex) else { return nil }
                return (wt.name, UIColor(swiftColor))
            }
        )
        // Запасная палитра для неизвестных типов дохода
        let incomeFallbackPalette: [UIColor] = settings.lightColors.compactMap { hex in
            guard let c = Color(hex: hex) else { return nil }
            return UIColor(c)
        }
        
        // Палитра расходов — тёплые смысловые цвета
        let expensePalette: [UIColor] = [
            UIColor(red: 0.88, green: 0.32, blue: 0.25, alpha: 1.0), // Красный — жильё/обязательные
            UIColor(red: 0.93, green: 0.53, blue: 0.18, alpha: 1.0), // Оранжевый — еда/продукты
            UIColor(red: 0.95, green: 0.73, blue: 0.15, alpha: 1.0), // Жёлтый — транспорт
            UIColor(red: 0.87, green: 0.60, blue: 0.20, alpha: 1.0), // Янтарный — развлечения
            UIColor(red: 0.76, green: 0.35, blue: 0.28, alpha: 1.0), // Терракота — здоровье
            UIColor(red: 0.92, green: 0.45, blue: 0.30, alpha: 1.0), // Коралловый — одежда
            UIColor(red: 0.83, green: 0.28, blue: 0.40, alpha: 1.0), // Малиновый — подарки
            UIColor(red: 0.97, green: 0.83, blue: 0.30, alpha: 1.0), // Золотой — прочее
            UIColor(red: 0.72, green: 0.42, blue: 0.22, alpha: 1.0), // Коричневый — комиссии
            UIColor(red: 0.90, green: 0.65, blue: 0.35, alpha: 1.0), // Персиковый — кафе
        ]
        
        // Шрифты
        let titleFont    = UIFont.systemFont(ofSize: 22, weight: .bold)
        let subtitleFont = UIFont.systemFont(ofSize: 11, weight: .regular)
        let headerFont   = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let textFont     = UIFont.systemFont(ofSize: 9.5, weight: .regular)
        let metricLabelFont = UIFont.systemFont(ofSize: 8.5, weight: .regular)
        let metricValueFont = UIFont.systemFont(ofSize: 14, weight: .bold)
        let sectionFont  = UIFont.systemFont(ofSize: 11, weight: .semibold)
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.locale = settings.appLanguage.locale
        
        func fmt(_ v: Double) -> String {
            (numberFormatter.string(from: NSNumber(value: v)) ?? "0") + " " + settings.defaultCurrency
        }
        
        // Агрегаты
        let income  = entries.reduce(0) { $0 + max(0, $1.signedAmount) }
        let expense = entries.reduce(0) { $0 + max(0, -$1.signedAmount) }
        let balance = income - expense
        
        let sortedEntries = entries.sorted { $0.date < $1.date }
        
        // Источники для диаграмм
        let incomeBySource = Dictionary(grouping: entries.filter { $0.signedAmount > 0 }) { entryCategory($0) }
            .mapValues { $0.reduce(0) { $0 + $1.signedAmount } }
        let expenseByCategory = Dictionary(grouping: entries.filter { $0.signedAmount < 0 }) { entryCategory($0) }
            .mapValues { abs($0.reduce(0) { $0 + $1.signedAmount }) }
        
        // Вспомогательные функции рисования
        func drawRoundedRect(context: UIGraphicsPDFRendererContext, rect: CGRect, radius: CGFloat, fill: UIColor, strokeColor: UIColor? = nil, lineWidth: CGFloat = 1) {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
            fill.setFill()
            path.fill()
            if let sc = strokeColor {
                sc.setStroke()
                path.lineWidth = lineWidth
                path.stroke()
            }
        }
        
        func drawText(_ text: String, at point: CGPoint, font: UIFont, color: UIColor, maxWidth: CGFloat? = nil, alignment: NSTextAlignment = .left) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if let w = maxWidth {
                let para = NSMutableParagraphStyle()
                para.alignment = alignment
                para.lineBreakMode = .byTruncatingTail
                attrs[.paragraphStyle] = para
                text.draw(in: CGRect(x: point.x, y: point.y, width: w, height: 20), withAttributes: attrs)
            } else {
                text.draw(at: point, withAttributes: attrs)
            }
        }
        
        return renderer.pdfData { context in
            var page = 0
            var rowIndex = 0
            let rowH_const: CGFloat = 19
            let tableHeaderH_const: CGFloat = 24
            // Страница 1 содержит карточки (56+20) + диаграммы (18+150+20) + шапку таблицы
            // y после всего контента на стр. 1 ≈ 376, остаток 842-376 = 466 → 24 строки
            // Страница 2+ — y ≈ 88+32+14+24 = 158, остаток 684 → 36 строк
            let maxRowsPage1 = 24
            let maxRowsOther = 36
            
            while rowIndex < sortedEntries.count {
                context.beginPage()
                page += 1
                var y: CGFloat = 0
                
                // ── Фон страницы ──────────────────────────────────────────
                backgroundColor.setFill()
                context.cgContext.fill(pageRect)
                
                // ── ШАПКА с градиентом ────────────────────────────────────
                let headerHeight: CGFloat = 72
                let headerRect = CGRect(x: 0, y: 0, width: pageRect.width, height: headerHeight)
                
                // Градиент шапки
                let gradStart = UIColor(red: 0.29, green: 0.39, blue: 0.54, alpha: 1.0).cgColor
                let gradEnd   = UIColor(red: 0.18, green: 0.27, blue: 0.42, alpha: 1.0).cgColor
                context.cgContext.saveGState()
                context.cgContext.clip(to: headerRect)
                let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [gradStart, gradEnd] as CFArray,
                                      locations: [0, 1])!
                context.cgContext.drawLinearGradient(grad,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: pageRect.width, y: headerHeight),
                    options: [])
                context.cgContext.restoreGState()
                
                // Текст шапки
                drawText("AuraShift", at: CGPoint(x: margin, y: 18), font: titleFont, color: .white)
                
                let generatedStr = String(
                    format: NSLocalizedString("Финансовый отчёт · %@", comment: "history pdf generated date title"),
                    formatter.string(from: Date())
                )
                drawText(generatedStr, at: CGPoint(x: margin, y: 46), font: subtitleFont, color: UIColor.white.withAlphaComponent(0.75))
                
                // Номер страницы справа в шапке
                let pageStr = String(
                    format: NSLocalizedString("стр. %d", comment: "history pdf page label"),
                    page
                )
                let pageSize = pageStr.size(withAttributes: [.font: subtitleFont])
                drawText(pageStr, at: CGPoint(x: pageRect.width - margin - pageSize.width, y: 46),
                         font: subtitleFont, color: UIColor.white.withAlphaComponent(0.6))
                
                y = headerHeight + 16
                
                // ── КАРТОЧКИ МЕТРИК (на первой странице большие, на остальных — компактная полоска) ──
                if page == 1 {
                    // Три карточки: Доходы / Расходы / Баланс
                    let cardSpacing: CGFloat = 10
                    let cardW = (usableWidth - cardSpacing * 2) / 3
                    let cardH: CGFloat = 56
                    
                    let metrics: [(label: String, value: Double, color: UIColor)] = [
                        (NSLocalizedString("Доходы", comment: "history pdf metric: incomes"), income, positiveColor),
                        (NSLocalizedString("Расходы", comment: "history pdf metric: expenses"), expense, negativeColor),
                        (NSLocalizedString("Баланс", comment: "history pdf metric: balance"), balance, balance >= 0 ? positiveColor : negativeColor)
                    ]
                    
                    for (i, m) in metrics.enumerated() {
                        let cardX = margin + CGFloat(i) * (cardW + cardSpacing)
                        let cardRect = CGRect(x: cardX, y: y, width: cardW, height: cardH)
                        drawRoundedRect(context: context, rect: cardRect, radius: 10, fill: surfaceColor, strokeColor: separatorColor, lineWidth: 0.8)
                        
                        // Цветная полоса сверху карточки
                        let accentBar = CGRect(x: cardX, y: y, width: cardW, height: 3)
                        let barPath = UIBezierPath(roundedRect: accentBar, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 10, height: 10))
                        m.color.setFill()
                        barPath.fill()
                        
                        drawText(m.label, at: CGPoint(x: cardX + 12, y: y + 11),
                                 font: metricLabelFont, color: secondaryTextColor)
                        drawText(fmt(m.value), at: CGPoint(x: cardX + 12, y: y + 28),
                                 font: metricValueFont, color: m.color, maxWidth: cardW - 16)
                    }
                    y += cardH + 20
                    
                    // ── КОЛЬЦЕВЫЕ ДИАГРАММЫ ────────────────────────────────
                    if income > 0 || expense > 0 {
                        let sectionLabel = NSLocalizedString("Структура доходов и расходов", comment: "history pdf section title: income and expense structure")
                        drawText(sectionLabel, at: CGPoint(x: margin, y: y), font: sectionFont, color: textColor)
                        y += 18
                        
                        let chartAreaW = (usableWidth - 20) / 2
                        let chartCardH: CGFloat = 150
                        
                        // Карточка доходов
                        drawRoundedRect(context: context,
                            rect: CGRect(x: margin, y: y, width: chartAreaW, height: chartCardH),
                            radius: 12, fill: surfaceColor, strokeColor: separatorColor, lineWidth: 0.8)
                        
                        // Карточка расходов
                        drawRoundedRect(context: context,
                            rect: CGRect(x: margin + chartAreaW + 20, y: y, width: chartAreaW, height: chartCardH),
                            radius: 12, fill: surfaceColor, strokeColor: separatorColor, lineWidth: 0.8)
                        
                        let donutRadius: CGFloat = 43
                        let donutRingWidth: CGFloat = 15
                        let donutX_income = margin + donutRadius + 16
                        let donutX_expense = margin + chartAreaW + 20 + donutRadius + 16
                        let donutCenterY = y + 20 + donutRadius
                        
                        // Диаграмма доходов — цвета из настроек смен пользователя
                        drawModernDonutChart(
                            context: context,
                            center: CGPoint(x: donutX_income, y: donutCenterY),
                            radius: donutRadius, ringWidth: donutRingWidth,
                            data: incomeBySource, total: income,
                            colorMap: workTypeColorMap,
                            fallbackColors: incomeFallbackPalette,
                            title: NSLocalizedString("Доходы", comment: "history pdf donut title: incomes"),
                            currency: settings.defaultCurrency,
                            numberFormatter: numberFormatter,
                            legendStartX: margin + donutRadius * 2 + 26,
                            legendY: y + 14,
                            legendWidth: chartAreaW - donutRadius * 2 - 30,
                            cardY: y, cardH: chartCardH,
                            textColor: textColor, secondaryColor: secondaryTextColor
                        )
                        
                        // Диаграмма расходов — тёплая смысловая палитра
                        drawModernDonutChart(
                            context: context,
                            center: CGPoint(x: donutX_expense, y: donutCenterY),
                            radius: donutRadius, ringWidth: donutRingWidth,
                            data: expenseByCategory, total: expense,
                            colorMap: [:],
                            fallbackColors: expensePalette,
                            title: NSLocalizedString("Расходы", comment: "history pdf donut title: expenses"),
                            currency: settings.defaultCurrency,
                            numberFormatter: numberFormatter,
                            legendStartX: margin + chartAreaW + 20 + donutRadius * 2 + 26,
                            legendY: y + 14,
                            legendWidth: chartAreaW - donutRadius * 2 - 30,
                            cardY: y, cardH: chartCardH,
                            textColor: textColor, secondaryColor: secondaryTextColor
                        )
                        
                        y += chartCardH + 20
                    }
                } else {
                    // Компактная полоска с метриками на последующих страницах
                    let stripH: CGFloat = 32
                    let stripRect = CGRect(x: margin, y: y, width: usableWidth, height: stripH)
                    drawRoundedRect(context: context, rect: stripRect, radius: 8, fill: surfaceColor, strokeColor: separatorColor, lineWidth: 0.8)
                    
                    let colW = usableWidth / 3
                    let mData: [(String, Double, UIColor)] = [
                        (String(format: NSLocalizedString("Доходы: %@", comment: "history pdf compact metric: incomes"), fmt(income)), income, positiveColor),
                        (String(format: NSLocalizedString("Расходы: %@", comment: "history pdf compact metric: expenses"), fmt(expense)), expense, negativeColor),
                        (String(format: NSLocalizedString("Баланс: %@", comment: "history pdf compact metric: balance"), fmt(balance)), balance, balance >= 0 ? positiveColor : negativeColor)
                    ]
                    for (i, m) in mData.enumerated() {
                        drawText(m.0, at: CGPoint(x: margin + CGFloat(i) * colW + 12, y: y + 9),
                                 font: textFont, color: m.2)
                    }
                    y += stripH + 14
                }
                
                // ── ЗАГОЛОВОК ТАБЛИЦЫ ──────────────────────────────────────
                let tableHeaderH: CGFloat = 24
                let tableHeaderRect = CGRect(x: margin, y: y, width: usableWidth, height: tableHeaderH)
                drawRoundedRect(context: context, rect: tableHeaderRect, radius: 6, fill: accentColor)
                
                let colDefs: [(String, CGFloat)] = [
                    (NSLocalizedString("Дата", comment: "history pdf table column: date"),      95),
                    (NSLocalizedString("Тип", comment: "history pdf table column: type"),       55),
                    (NSLocalizedString("Категория", comment: "history pdf table column: category"), 185),
                    (NSLocalizedString("Сумма", comment: "history pdf table column: amount"),     usableWidth - 335)
                ]
                
                var xh = margin
                for col in colDefs {
                    drawText(col.0, at: CGPoint(x: xh + 8, y: y + 5), font: headerFont, color: .white)
                    xh += col.1
                }
                y += tableHeaderH
                
                // ── СТРОКИ ТАБЛИЦЫ ─────────────────────────────────────────
                let rowH: CGFloat = rowH_const
                let maxRowsThisPage = page == 1 ? maxRowsPage1 : maxRowsOther
                // Дополнительно: динамически считаем сколько строк реально влезет
                let remainingPageSpace = pageRect.height - y - tableHeaderH_const - 20  // 20 нижнее поле
                let dynamicMax = max(1, Int(remainingPageSpace / rowH))
                let rowsThisPage = min(min(maxRowsThisPage, dynamicMax), sortedEntries.count - rowIndex)
                
                for ri in 0..<rowsThisPage {
                    let entry = sortedEntries[rowIndex]
                    let isEven = ri % 2 == 0
                    
                    let rowRect = CGRect(x: margin, y: y, width: usableWidth, height: rowH)
                    let rowFill = isEven ? surfaceColor : UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0)
                    rowFill.setFill()
                    context.cgContext.fill(rowRect)
                    
                    // Тонкая разделительная линия
                    separatorColor.setStroke()
                    context.cgContext.setLineWidth(0.4)
                    context.cgContext.move(to: CGPoint(x: margin, y: y + rowH))
                    context.cgContext.addLine(to: CGPoint(x: margin + usableWidth, y: y + rowH))
                    context.cgContext.strokePath()
                    
                    let amount = abs(entry.signedAmount)
                    let amountStr = fmt(amount)
                    let amountColor: UIColor = entry.signedAmount >= 0 ? positiveColor : negativeColor
                    let typeStr = entry.signedAmount >= 0
                        ? NSLocalizedString("Доход", comment: "history pdf table type: income")
                        : NSLocalizedString("Расход", comment: "history pdf table type: expense")
                    
                    let values: [(String, UIColor)] = [
                        (formatter.string(from: entry.date), textColor),
                        (typeStr, entry.signedAmount >= 0 ? positiveColor : negativeColor),
                        (entryCategory(entry), textColor),
                        (amountStr, amountColor)
                    ]
                    
                    var xr = margin
                    for (i, (val, color)) in values.enumerated() {
                        let cellFont = i == 1 ? UIFont.systemFont(ofSize: 9.5, weight: .medium) : textFont
                        drawText(val, at: CGPoint(x: xr + 8, y: y + 4),
                                 font: cellFont, color: color, maxWidth: colDefs[i].1 - 10)
                        xr += colDefs[i].1
                    }
                    
                    y += rowH
                    rowIndex += 1
                }
                
                // Граница вокруг таблицы
                let tableRect = CGRect(x: margin, y: y - rowH * CGFloat(rowsThisPage) - tableHeaderH,
                                       width: usableWidth,
                                       height: tableHeaderH + rowH * CGFloat(rowsThisPage))
                let tableBorder = UIBezierPath(roundedRect: tableRect, cornerRadius: 6)
                separatorColor.setStroke()
                tableBorder.lineWidth = 0.8
                tableBorder.stroke()
                
                // ── ФУТЕР ─────────────────────────────────────────────────
                let footerY = pageRect.height - 22
                separatorColor.setStroke()
                context.cgContext.setLineWidth(0.5)
                context.cgContext.move(to: CGPoint(x: margin, y: footerY - 5))
                context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: footerY - 5))
                context.cgContext.strokePath()
                
                drawText(
                    "AuraShift · \(NSLocalizedString("Финансовый отчёт", comment: "history pdf report title"))",
                         at: CGPoint(x: margin, y: footerY),
                         font: UIFont.systemFont(ofSize: 7.5), color: secondaryTextColor)
                
                let totalPagesEst = 1 + max(0, Int(ceil(Double(max(0, sortedEntries.count - maxRowsPage1)) / Double(maxRowsOther))))
                let pageFooter = String(
                    format: NSLocalizedString("стр. %d / %d", comment: "history pdf footer page index and total"),
                    page, totalPagesEst
                )
                let pfSize = pageFooter.size(withAttributes: [.font: UIFont.systemFont(ofSize: 7.5)])
                drawText(pageFooter,
                         at: CGPoint(x: pageRect.width - margin - pfSize.width, y: footerY),
                         font: UIFont.systemFont(ofSize: 7.5), color: secondaryTextColor)
            }
        }
    }
    
    // MARK: - Современная кольцевая диаграмма с легендой
    // colorMap: для каждой категории — конкретный цвет (используется для доходов, цвета берутся из настроек смен)
    // fallbackColors: запасная палитра по индексу (для расходов — тёплые смысловые цвета)
    private func drawModernDonutChart(
        context: UIGraphicsPDFRendererContext,
        center: CGPoint,
        radius: CGFloat,
        ringWidth: CGFloat,
        data: [String: Double],
        total: Double,
        colorMap: [String: UIColor],
        fallbackColors: [UIColor],
        title: String,
        currency: String,
        numberFormatter: NumberFormatter,
        legendStartX: CGFloat,
        legendY: CGFloat,
        legendWidth: CGFloat,
        cardY: CGFloat,
        cardH: CGFloat,
        textColor: UIColor,
        secondaryColor: UIColor
    ) {
        guard total > 0, !data.isEmpty else {
            let emptyAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: secondaryColor
            ]
            NSLocalizedString("Нет данных", comment: "history donut empty state")
                .draw(at: CGPoint(x: center.x - 20, y: center.y), withAttributes: emptyAttr)
            return
        }
        
        let sortedData = data.sorted { $0.value > $1.value }
        var startAngle: CGFloat = -.pi / 2
        let ringRadius = radius - ringWidth / 2
        let clampedRingWidth = max(8, min(ringWidth, radius - 6))
        let segmentGap: CGFloat = min(0.06, 1.1 / max(ringRadius, 1))
        
        // Назначаем цвета: из colorMap если есть, иначе из fallbackColors по индексу
        var fallbackIndex = 0
        var colorAssignment: [(key: String, color: UIColor)] = sortedData.map { item in
            if let mapped = colorMap[item.key] {
                return (item.key, mapped)
            } else {
                let c = fallbackColors[fallbackIndex % fallbackColors.count]
                fallbackIndex += 1
                return (item.key, c)
            }
        }
        
        // Фоновая дорожка кольца
        let trackPath = UIBezierPath(
            arcCenter: center,
            radius: ringRadius,
            startAngle: 0,
            endAngle: 2 * .pi,
            clockwise: true
        )
        trackPath.lineWidth = clampedRingWidth
        trackPath.lineCapStyle = .round
        UIColor(red: 0.90, green: 0.92, blue: 0.96, alpha: 1.0).setStroke()
        trackPath.stroke()
        
        // Сегменты кольца (чётко donut-стиль)
        context.cgContext.saveGState()
        for (i, item) in sortedData.enumerated() {
            let sweepAngle = CGFloat(item.value / total) * 2 * .pi
            let rawEnd = startAngle + sweepAngle
            let segmentStart = startAngle + segmentGap / 2
            let segmentEnd = rawEnd - segmentGap / 2
            
            if segmentEnd > segmentStart {
                let arcPath = UIBezierPath(
                    arcCenter: center,
                    radius: ringRadius,
                    startAngle: segmentStart,
                    endAngle: segmentEnd,
                    clockwise: true
                )
                arcPath.lineWidth = clampedRingWidth
                arcPath.lineCapStyle = .round
                colorAssignment[i].color.setStroke()
                arcPath.stroke()
            }
            
            startAngle = rawEnd
        }
        context.cgContext.restoreGState()
        
        // Центр для лучшего контраста подписи
        let centerRadius = max(ringRadius - clampedRingWidth / 2 - 1, 12)
        let centerPath = UIBezierPath(
            arcCenter: center,
            radius: centerRadius,
            startAngle: 0,
            endAngle: 2 * .pi,
            clockwise: true
        )
        UIColor(red: 0.99, green: 0.995, blue: 1.0, alpha: 1).setFill()
        centerPath.fill()
        UIColor(red: 0.89, green: 0.91, blue: 0.95, alpha: 1.0).setStroke()
        centerPath.lineWidth = 0.8
        centerPath.stroke()
        
        // Заголовок и сумма в центре кольца
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7.5, weight: .medium),
            .foregroundColor: secondaryColor
        ]
        let sumAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9.5, weight: .bold),
            .foregroundColor: textColor
        ]
        let titleSize = title.size(withAttributes: titleAttr)
        let sumValue = numberFormatter.string(from: NSNumber(value: total)) ?? "0"
        let sumStr = "\(sumValue) \(currency)"
        let sumSize = sumStr.size(withAttributes: sumAttr)
        
        title.draw(at: CGPoint(x: center.x - titleSize.width / 2, y: center.y - titleSize.height - 1),
                   withAttributes: titleAttr)
        sumStr.draw(at: CGPoint(x: center.x - sumSize.width / 2, y: center.y + 2),
                    withAttributes: sumAttr)
        
        // Легенда справа от диаграммы
        let legendDotSize: CGFloat = 7
        let legendRowH: CGFloat = 14
        let maxLegendItems = min(colorAssignment.count, 6)
        let totalLegendH = CGFloat(maxLegendItems) * legendRowH
        var lY = max(legendY, cardY + (cardH - totalLegendH) / 2 - 2)
        
        for i in 0..<maxLegendItems {
            let item = sortedData[i]
            let color = colorAssignment[i].color
            
            // Цветной кружок
            let dotRect = CGRect(x: legendStartX, y: lY + (legendRowH - legendDotSize) / 2,
                                 width: legendDotSize, height: legendDotSize)
            let dotPath = UIBezierPath(ovalIn: dotRect)
            color.setFill()
            dotPath.fill()
            
            // Подпись: название · процент · сумма
            let pct = String(format: "%.0f%%", (item.value / total) * 100)
            let amountText = numberFormatter.string(from: NSNumber(value: item.value)) ?? "0"
            let legendLabel = item.key.count > 11 ? String(item.key.prefix(10)) + "…" : item.key
            let fullLabel = "\(legendLabel) · \(pct) · \(amountText)"
            
            let labelAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8, weight: .regular),
                .foregroundColor: textColor
            ]
            fullLabel.draw(in: CGRect(x: legendStartX + legendDotSize + 5, y: lY + 2,
                                      width: legendWidth - legendDotSize - 6, height: 12),
                           withAttributes: labelAttr)
            lY += legendRowH
        }
        
        if colorAssignment.count > maxLegendItems {
            let moreAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 7.5),
                .foregroundColor: secondaryColor
            ]
            String(
                format: NSLocalizedString("+ ещё %d", comment: "history donut legend more categories"),
                colorAssignment.count - maxLegendItems
            ).draw(
                at: CGPoint(x: legendStartX, y: lY + 2),
                withAttributes: moreAttr)
        }
    }
    
    private func clearExportFile() {
        if let exportURL {
            try? FileManager.default.removeItem(at: exportURL)
        }
        exportURL = nil
    }
    
    private func entryCategory(_ entry: HistoryEntry) -> String {
        switch entry {
        case .income(let income):
            return income.type ?? NSLocalizedString("Доход", comment: "history entry fallback income")
        case .expense(let expense):
            return expense.category ?? NSLocalizedString("Расход", comment: "history entry fallback expense")
        }
    }
}

// MARK: - Кастомный календарь (исправлен: уникальные ID)
struct CustomCalendarSheet: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @Binding var isPresented: Bool
    
    @State private var currentMonth = Date()
    @State private var selectedStart: Date? = nil
    @State private var selectedEnd: Date? = nil
    @State private var selectionState: SelectionState = .none
    
    enum SelectionState {
        case none
        case oneSelected
        case rangeSelected
    }
    
    private let calendar = Calendar.current
    private var daysOfWeek: [String] {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale()
        var symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        if symbols.count == 7 {
            let sunday = symbols.removeFirst()
            symbols.append(sunday)
        }
        return symbols
    }
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    
    // Структура для дня с уникальным ID
    struct CalendarDay: Identifiable {
        let id = UUID()
        let date: Date?
    }
    
    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Заголовок с месяцем и стрелками
                HStack {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .foregroundColor(AppColors.accent)
                    }
                    Spacer()
                    Text(monthYearString(from: currentMonth))
                        .font(.headline)
                        .foregroundColor(AppColors.text)
                    Spacer()
                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundColor(AppColors.accent)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                
                // Дни недели
                HStack {
                    ForEach(daysOfWeek, id: \.self) { day in
                        Text(day)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                .padding(.top, 8)
                
                // Сетка дней
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(daysInMonth()) { day in
                        if let date = day.date {
                            DayCell(
                                date: date,
                                isSelected: isDateSelected(date),
                                isInRange: isDateInRange(date),
                                isStart: isStart(date),
                                isEnd: isEnd(date)
                            )
                            .onTapGesture {
                                handleDateTap(date)
                            }
                        } else {
                            Text("")
                                .frame(height: 36)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                
                Spacer(minLength: 12)
                
                // Кнопки управления
                HStack {
                    Button(NSLocalizedString("Сбросить", comment: "history custom calendar reset")) {
                        selectedStart = nil
                        selectedEnd = nil
                        selectionState = .none
                        startDate = nil
                        endDate = nil
                        isPresented = false
                    }
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    Button(NSLocalizedString("Готово", comment: "history custom calendar done")) {
                        applySelection()
                        isPresented = false
                    }
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .background(VisionBackdropView())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(NSLocalizedString("Выберите даты", comment: "history custom calendar title"))
            .onAppear {
                selectedStart = startDate
                selectedEnd = endDate
                if selectedStart != nil && selectedEnd != nil {
                    selectionState = .rangeSelected
                } else if selectedStart != nil {
                    selectionState = .oneSelected
                }
            }
        }
        .accentColor(AppColors.accent)
    }
    
    // MARK: - Логика выбора
    private func handleDateTap(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        
        switch selectionState {
        case .none:
            selectedStart = day
            selectedEnd = nil
            selectionState = .oneSelected
            
        case .oneSelected:
            guard let start = selectedStart else { return }
            if day == start {
                selectedEnd = nil
                selectionState = .oneSelected
            } else if day > start {
                selectedEnd = day
                selectionState = .rangeSelected
            } else {
                selectedStart = day
                selectedEnd = nil
                selectionState = .oneSelected
            }
            
        case .rangeSelected:
            selectedStart = day
            selectedEnd = nil
            selectionState = .oneSelected
        }
    }
    
    private func applySelection() {
        startDate = selectedStart
        endDate = selectedEnd
    }
    
    private func isDateSelected(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day == selectedStart || day == selectedEnd
    }
    
    private func isDateInRange(_ date: Date) -> Bool {
        guard let start = selectedStart, let end = selectedEnd else { return false }
        let day = calendar.startOfDay(for: date)
        return day >= start && day <= end
    }
    
    private func isStart(_ date: Date) -> Bool {
        guard let start = selectedStart else { return false }
        return calendar.startOfDay(for: date) == start
    }
    
    private func isEnd(_ date: Date) -> Bool {
        guard let end = selectedEnd else { return false }
        return calendar.startOfDay(for: date) == end
    }
    
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        formatter.locale = AppLanguage.currentLocale()
        return formatter.string(from: date).capitalized
    }
    
    private func previousMonth() {
        currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }
    
    private func nextMonth() {
        currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
    }
    
    private func daysInMonth() -> [CalendarDay] {
        guard let range = calendar.range(of: .day, in: .month, for: currentMonth) else { return [] }
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        
        var days: [CalendarDay] = []
        let firstWeekday = calendar.component(.weekday, from: start)
        let offset = firstWeekday == 1 ? 6 : firstWeekday - 2
        
        // Пустые ячейки в начале
        for _ in 0..<offset {
            days.append(CalendarDay(date: nil))
        }
        
        // Дни месяца
        for day in 0..<range.count {
            if let date = calendar.date(byAdding: .day, value: day, to: start) {
                days.append(CalendarDay(date: date))
            }
        }
        
        // Можно добавить пустые ячейки в конце для ровной сетки (необязательно)
        let totalCells = ((days.count + 6) / 7) * 7
        while days.count < totalCells {
            days.append(CalendarDay(date: nil))
        }
        
        return days
    }
}

// MARK: - Ячейка дня
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isInRange: Bool
    let isStart: Bool
    let isEnd: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private let calendar = Calendar.current
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()
    
    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.surface.opacity(0.9))

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isInRange ? 0.30 : 0.22))

            if isInRange {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.10))
            }

            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.13))
            }

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isStart || isEnd ? Color.white.opacity(0.40) : Color.white.opacity(0.30),
                    lineWidth: isStart || isEnd ? 1.8 : 0.8
                )

            Text(dayFormatter.string(from: date))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isSelected ? .white : AppColors.text)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
                .shadow(color: Color.black.opacity(isSelected ? 0.20 : 0.10), radius: 1, x: 0, y: 1)
        }
        .frame(height: 42)
        .shadow(color: .black.opacity(isSelected ? 0.14 : 0.06), radius: isSelected ? 4 : 2, x: 0, y: 1)
    }
}

// MARK: - Вспомогательные представления (без изменений)
struct IncomeHistoryRow: View {
    let income: Income
    let settings: UserSettings
    
    private var icon: String {
        if let workType = settings.workTypes.first(where: { $0.name == income.type }) {
            return workType.icon
        }
        return "briefcase"
    }
    
    private var totalAmount: Double {
        income.hoursWorked * income.hourlyRate + income.tips + income.floatingAmount
    }
    
    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        ZStack {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(AppColors.accent)
                    .frame(width: 30, height: 30)
                    .visionGlassCard(cornerRadius: 9, opacity: 0.78)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(income.type ?? NSLocalizedString("Смена", comment: "history income row fallback title"))
                        .font(.headline)
                        .foregroundColor(AppColors.text)
                    
                    if income.hoursWorked > 0 {
                        Text(
                            String(
                                format: NSLocalizedString("%.1f ч × %.0f %@/ч", comment: "history income row hourly breakdown"),
                                income.hoursWorked,
                                income.hourlyRate,
                                settings.defaultCurrency
                            )
                        )
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "+%.0f %@", totalAmount, settings.defaultCurrency))
                        .font(.headline)
                        .foregroundColor(AppColors.positive)
                    
                    if income.tips > 0 {
                        Text(
                            String(
                                format: NSLocalizedString("Чаевые: %.0f %@", comment: "history income row tips"),
                                income.tips,
                                settings.defaultCurrency
                            )
                        )
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    if income.floatingAmount > 0 && income.hoursWorked == 0 {
                        Text(
                            String(
                                format: NSLocalizedString("Заработок: %.0f %@", comment: "history income row earnings"),
                                income.floatingAmount,
                                settings.defaultCurrency
                            )
                        )
                            .font(.caption)
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .visionGlassCard(cornerRadius: 12, opacity: 0.84, showRing: true)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
        .padding(.vertical, 2)
    }
}

struct ExpenseHistoryRow: View {
    let expense: Expense
    let settings: UserSettings
    
    private func expenseCategoryIcon(_ category: String) -> String {
        settings.iconForExpenseCategory(category)
    }
    
    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        ZStack {
            HStack {
                Image(systemName: expenseCategoryIcon(expense.category ?? ""))
                    .foregroundColor(AppColors.negative)
                    .frame(width: 30, height: 30)
                    .visionGlassCard(cornerRadius: 9, opacity: 0.78)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(expense.category ?? NSLocalizedString("Расход", comment: "history expense row fallback title"))
                        .font(.headline)
                        .foregroundColor(AppColors.text)
                    
                    if let notes = expense.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "-%.0f %@", expense.amount, settings.defaultCurrency))
                        .font(.headline)
                        .foregroundColor(AppColors.negative)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .visionGlassCard(cornerRadius: 12, opacity: 0.84, showRing: true)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
        .padding(.vertical, 2)
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
