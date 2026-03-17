import WidgetKit
import SwiftUI

// MARK: - Модель PlannedShift (только нужные поля)
struct PlannedShift: Identifiable, Codable {
    let id: UUID
    let date: Date
    let workTypeName: String
    let icon: String
    let startTime: Date
    // Остальные поля (endTime, hourlyRate и т.д.) не используются в виджете
}

// MARK: - Данные для виджета
// ВАЖНО: Без App Groups виджет изолирован от данных приложения. Здесь используется UserDefaults.standard
// только как временный вариант для отладки. Для реального обмена данными включите App Groups
// и используйте одинаковый suiteName в приложении и расширении.
struct WidgetData {
    let todayIncome: Double
    let monthIncome: Double
    let remainingGoals: Double
    let goalProgress: Double
    let currency: String
    let plannedShifts: [PlannedShift]
}

// MARK: - Provider
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), data: placeholderData)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), data: loadData())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [SimpleEntry] = []
        let currentDate = Date()
        // Обновляем каждые 2 часа
        for hourOffset in 0 ..< 12 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset * 2, to: currentDate)!
            let entry = SimpleEntry(date: entryDate, data: loadData())
            entries.append(entry)
        }
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

    private func loadData() -> WidgetData {
        // NOTE: App Groups are not enabled on the free account, so the widget cannot access a shared suite.
        // Using standard UserDefaults here avoids assuming shared storage. This will NOT share data with the app.
        // For real data sharing between app and widget, enable App Groups and switch back to suiteName.
        let sharedDefaults = UserDefaults.standard
        
        let todayIncome = sharedDefaults.double(forKey: "todayIncome")
        let monthIncome = sharedDefaults.double(forKey: "monthIncome")
        let remainingGoals = sharedDefaults.double(forKey: "remainingGoals")
        let goalProgress = sharedDefaults.double(forKey: "goalProgress")
        let currency = sharedDefaults.string(forKey: "currency") ?? "₽"
        
        var plannedShifts: [PlannedShift] = []
        if let data = sharedDefaults.data(forKey: "plannedShifts") {
            plannedShifts = (try? JSONDecoder().decode([PlannedShift].self, from: data)) ?? []
        }
        
        return WidgetData(
            todayIncome: todayIncome,
            monthIncome: monthIncome,
            remainingGoals: remainingGoals,
            goalProgress: goalProgress,
            currency: currency,
            plannedShifts: plannedShifts
        )
    }
    
    private var placeholderData: WidgetData {
        WidgetData(
            todayIncome: 2500,
            monthIncome: 45000,
            remainingGoals: 15000,
            goalProgress: 65,
            currency: "₽",
            plannedShifts: []
        )
    }
}

// MARK: - Entry
struct SimpleEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - View
struct AuraShiftWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            smallView
        }
    }
    
    var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Сегодня")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(Int(entry.data.todayIncome)) \(entry.data.currency)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.green)
            Spacer()
            ProgressView(value: entry.data.goalProgress / 100, total: 1)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            Text("Осталось: \(Int(entry.data.remainingGoals)) \(entry.data.currency)")
                .font(.caption2)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    var mediumView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Сегодня: \(Int(entry.data.todayIncome)) \(entry.data.currency)")
                    .font(.subheadline)
                Text("Месяц: \(Int(entry.data.monthIncome)) \(entry.data.currency)")
                    .font(.subheadline)
                ProgressView("Цель", value: entry.data.goalProgress, total: 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .padding(.top, 4)
            }
            .padding()
            
            Divider()
            
            if !entry.data.plannedShifts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Планы").font(.caption).bold()
                    ForEach(entry.data.plannedShifts.prefix(2)) { shift in
                        HStack {
                            Image(systemName: shift.icon)
                                .font(.caption)
                            Text(shift.workTypeName)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text(shift.startTime, style: .time)
                                .font(.caption2)
                        }
                    }
                }
                .padding()
            } else {
                Text("Нет планов")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Сводка")
                .font(.headline)
            Divider()
            HStack {
                Label("Доход сегодня", systemImage: "rublesign.circle")
                Spacer()
                Text("\(Int(entry.data.todayIncome)) \(entry.data.currency)")
            }
            HStack {
                Label("Доход за месяц", systemImage: "calendar")
                Spacer()
                Text("\(Int(entry.data.monthIncome)) \(entry.data.currency)")
            }
            ProgressView("Цель (\(Int(entry.data.goalProgress))%)", value: entry.data.goalProgress, total: 100)
                .padding(.vertical, 4)
            
            if !entry.data.plannedShifts.isEmpty {
                Text("Ближайшие смены")
                    .font(.subheadline)
                    .padding(.top, 4)
                ForEach(entry.data.plannedShifts.prefix(3)) { shift in
                    HStack {
                        Image(systemName: shift.icon)
                        Text(shift.workTypeName)
                        Spacer()
                        Text(shift.startTime, style: .time)
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget
struct AuraShiftWidget: Widget {
    let kind: String = "AuraShiftWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AuraShiftWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AuraShift")
        .description("Быстрый доступ к финансам и планам")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

