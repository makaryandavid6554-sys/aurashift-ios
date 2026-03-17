import SwiftUI

struct GlassCalendarView: View {
    @State private var currentMonth = Date()
    @State private var selectedDate: Date? = nil
    private let calendar = Calendar.current
    
    private var daysOfWeek: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        var symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        if symbols.count == 7 {
            let sunday = symbols.removeFirst()
            symbols.append(sunday)
        }
        return symbols
    }
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    
    struct CalendarDay: Identifiable {
        let id = UUID()
        let date: Date?
    }
    
    var body: some View {
        ZStack {
            VisionBackdropView()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(AppColors.accent)
                    }
                    Spacer()
                    Text(monthYearString(from: currentMonth))
                        .font(.title2.weight(.bold))
                        .foregroundColor(AppColors.text)
                        .glassBackground(cornerRadius: 14, opacity: 0.84)
                        .padding(.horizontal, 12)
                    Spacer()
                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .foregroundColor(AppColors.accent)
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal)
                
                HStack {
                    ForEach(daysOfWeek, id: \.self) { day in
                        Text(day)
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .foregroundColor(AppColors.secondaryText)
                            .padding(.vertical, 4)
                    }
                }
                .glassBackground(cornerRadius: 13, opacity: 0.82)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(daysInMonth()) { day in
                        if let date = day.date {
                            GlassDayCell(
                                date: date,
                                isSelected: isDateSelected(date)
                            )
                            .onTapGesture { selectedDate = date }
                        } else {
                            Color.clear.frame(height: 36)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                Spacer(minLength: 18)
            }
        }
    }
    
    private func previousMonth() {
        currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }
    private func nextMonth() {
        currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
    }
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        formatter.locale = Locale.current
        return formatter.string(from: date).capitalized
    }
    private func daysInMonth() -> [CalendarDay] {
        guard let range = calendar.range(of: .day, in: .month, for: currentMonth) else { return [] }
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        var days: [CalendarDay] = []
        let firstWeekday = calendar.component(.weekday, from: start)
        let offset = firstWeekday == 1 ? 6 : firstWeekday - 2
        for _ in 0..<offset { days.append(CalendarDay(date: nil)) }
        for day in 0..<range.count {
            if let date = calendar.date(byAdding: .day, value: day, to: start) {
                days.append(CalendarDay(date: date))
            }
        }
        let totalCells = ((days.count + 6) / 7) * 7
        while days.count < totalCells { days.append(CalendarDay(date: nil)) }
        return days
    }
    private func isDateSelected(_ date: Date) -> Bool {
        guard let selected = selectedDate else { return false }
        return calendar.isDate(date, inSameDayAs: selected)
    }
}

private struct GlassDayCell: View {
    let date: Date
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .glassBackground(cornerRadius: 11, opacity: 0.90, showRing: isSelected)
                .shadow(color: .black.opacity(0.06), radius: isSelected ? 4 : 2, x: 0, y: 1)
            Text(dayFormatter.string(from: date))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isSelected ? AppColors.accent : AppColors.text)
        }
        .frame(height: 42)
        .padding(.vertical, 1)
        .scaleEffect(isSelected ? 1.07 : 1.0)
        .lightweightAnimation(.easeOut(duration: 0.12), value: isSelected)
    }
}

#Preview {
    GlassCalendarView()
        .frame(width: 390, height: 470)
}
