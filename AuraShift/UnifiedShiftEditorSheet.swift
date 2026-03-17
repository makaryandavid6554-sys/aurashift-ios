import SwiftUI

struct UnifiedShiftEditorSheet: View {
    @Environment(\.presentationMode) private var presentationMode

    let item: DisplayItem
    @ObservedObject var settings: UserSettings
    @ObservedObject var sessionManager: SessionManager
    let onSave: () -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColorHex: String
    @State private var paymentMode: WorkTypePaymentMode
    @State private var rateValue: Double
    @State private var hasTipsEnabled: Bool
    @State private var startHour: Int
    @State private var startMinute: Int
    @State private var endHour: Int
    @State private var endMinute: Int
    @State private var floatingAmount: Double
    @State private var tipsAmount: Double
    @State private var noteText: String

    @State private var validationAlert: ValidationAlertContext?
    @State private var showStatsImpactConfirmation = false

    private let sourceWorkTypeId: UUID
    private let sourceWorkTypeName: String

    private let iconOptions: [String] = [
        "wineglass", "bicycle", "car", "bus", "fork.knife", "house", "briefcase",
        "cart", "wrench.and.screwdriver", "hammer", "bag", "figure.walk"
    ]

    private enum ValidationAlertKind {
        case invalidDuration
        case invalidRate
        case invalidName
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

        let fallbackColor = settings.lightColors.first ?? "#5E5CE6"
        let sourceId: UUID
        let sourceName: String
        let start: Int
        let startMin: Int
        let end: Int
        let endMin: Int
        let floating: Double
        let tips: Double
        let note: String
        let hourlyRateFromItem: Double
        let fixedRateFromItem: Double
        let hasHourlyFromItem: Bool
        let hasFixedFromItem: Bool
        let hasFloatingFromItem: Bool
        let hasTipsFromItem: Bool
        let iconFromItem: String

        switch item {
        case .session(let session):
            sourceId = session.workTypeId
            sourceName = session.workTypeName
            start = session.startHour
            startMin = session.startMinute
            end = session.endHour
            endMin = session.endMinute
            floating = session.floatingAmount
            tips = session.tips
            note = session.note ?? ""
            hourlyRateFromItem = session.hourlyRate
            fixedRateFromItem = session.fixedAmount
            hasHourlyFromItem = session.hasHourlyRate
            hasFixedFromItem = session.hasFixedRate
            hasFloatingFromItem = session.hasFloatingRate
            hasTipsFromItem = session.hasTips
            iconFromItem = session.icon
        case .planned(let planned):
            let calendar = Calendar.current
            sourceId = planned.workTypeId
            sourceName = planned.workTypeName
            start = calendar.component(.hour, from: planned.startTime)
            startMin = calendar.component(.minute, from: planned.startTime)
            end = calendar.component(.hour, from: planned.endTime)
            endMin = calendar.component(.minute, from: planned.endTime)
            floating = 0
            tips = 0
            note = planned.note ?? ""
            hourlyRateFromItem = planned.hourlyRate
            fixedRateFromItem = 0
            hasHourlyFromItem = planned.hourlyRate > 0
            hasFixedFromItem = false
            hasFloatingFromItem = planned.hourlyRate == 0
            hasTipsFromItem = planned.hasTips
            iconFromItem = planned.icon
        }

        self.sourceWorkTypeId = sourceId
        self.sourceWorkTypeName = sourceName

        let resolvedType = settings.workTypes.first { $0.id == sourceId || $0.name == sourceName }
        let initialName = resolvedType?.name ?? sourceName
        let initialIcon = resolvedType?.icon ?? iconFromItem
        let initialColor = resolvedType?.colorHex ?? fallbackColor
        let initialHasTips = resolvedType?.hasTips ?? hasTipsFromItem

        let initialMode: WorkTypePaymentMode
        let initialRate: Double
        if let resolvedType {
            if resolvedType.hasHourlyRate {
                initialMode = .hourly
                initialRate = resolvedType.hourlyRate
            } else if resolvedType.hasFixedRate {
                initialMode = .fixed
                initialRate = resolvedType.fixedRate
            } else {
                initialMode = .floating
                initialRate = 0
            }
        } else if hasHourlyFromItem {
            initialMode = .hourly
            initialRate = hourlyRateFromItem
        } else if hasFixedFromItem {
            initialMode = .fixed
            initialRate = fixedRateFromItem
        } else if hasFloatingFromItem {
            initialMode = .floating
            initialRate = 0
        } else {
            initialMode = .hourly
            initialRate = max(hourlyRateFromItem, 0)
        }

        _name = State(initialValue: initialName)
        _selectedIcon = State(initialValue: initialIcon)
        _selectedColorHex = State(initialValue: initialColor)
        _paymentMode = State(initialValue: initialMode)
        _rateValue = State(initialValue: initialRate)
        _hasTipsEnabled = State(initialValue: initialHasTips)
        _startHour = State(initialValue: start)
        _startMinute = State(initialValue: startMin)
        _endHour = State(initialValue: end)
        _endMinute = State(initialValue: endMin)
        _floatingAmount = State(initialValue: max(floating, 0))
        _tipsAmount = State(initialValue: max(tips, 0))
        _noteText = State(initialValue: note)
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedNote: String? {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var requiresRate: Bool {
        paymentMode != .floating
    }

    private var editedStartMinuteOfDay: Int {
        startHour * 60 + startMinute
    }

    private var editedEndMinuteOfDay: Int {
        endHour * 60 + endMinute
    }

    private var editedHours: Double {
        let startTotal = editedStartMinuteOfDay
        let endTotal = editedEndMinuteOfDay
        var diff = endTotal - startTotal
        if diff < 0 { diff += 24 * 60 }
        return Double(diff) / 60.0
    }

    private var editedItemDate: Date {
        switch item {
        case .session(let session):
            return session.date
        case .planned(let planned):
            return planned.date
        }
    }

    private var affectsStatistics: Bool {
        guard case .session = item else { return false }
        return editedItemDate <= Date()
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

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
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
                        NumberField(
                            title: NSLocalizedString("Ставка", comment: "work type editor rate title"),
                            value: $rateValue,
                            currency: settings.defaultCurrency
                        )
                    } else if paymentMode == .fixed {
                        NumberField(
                            title: NSLocalizedString("За смену", comment: "work type editor fixed amount title"),
                            value: $rateValue,
                            currency: settings.defaultCurrency
                        )
                    }

                    Toggle(NSLocalizedString("Есть чаевые", comment: "work type editor toggle: tips enabled"), isOn: $hasTipsEnabled)
                        .tint(AppColors.accent)
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
                    if paymentMode == .hourly {
                        Section(header: Text(NSLocalizedString("Почасовая оплата", comment: "edit item section header: hourly payment"))) {
                            HStack {
                                Text(NSLocalizedString("Часы", comment: "edit item sheet label: hours"))
                                Spacer()
                                Text(String(format: "%.1f", editedHours))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if paymentMode == .floating {
                        Section(header: Text(NSLocalizedString("Плавающий заработок", comment: "edit item section header: flexible earnings"))) {
                            NumberField(
                                title: NSLocalizedString("Заработок", comment: "edit item number field title: earnings"),
                                value: $floatingAmount,
                                currency: settings.defaultCurrency
                            )
                        }
                    }

                    if hasTipsEnabled {
                        Section(header: Text(NSLocalizedString("Чаевые", comment: "edit item section header: tips"))) {
                            NumberField(
                                title: NSLocalizedString("Чаевые", comment: "edit item number field title: tips"),
                                value: $tipsAmount,
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

                if affectsStatistics {
                    Section {
                        Text(NSLocalizedString("Изменение этой смены повлияет на статистику.", comment: "edit shift stats impact inline warning"))
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
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
            .navigationTitle(NSLocalizedString("Редактирование смены", comment: "unified shift editor title"))
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
        .alert(item: $validationAlert) { context in
            switch context.kind {
            case .overlapWarning:
                return Alert(
                    title: Text(context.title),
                    message: Text(context.message),
                    primaryButton: .destructive(Text(NSLocalizedString("Сохранить", comment: "common save action"))) {
                        proceedSave()
                    },
                    secondaryButton: .cancel(Text(NSLocalizedString("Отмена", comment: "common cancel action")))
                )
            default:
                return Alert(
                    title: Text(context.title),
                    message: Text(context.message),
                    dismissButton: .default(Text(NSLocalizedString("Ок", comment: "common ok action")))
                )
            }
        }
        .alert(
            NSLocalizedString("Влияние на статистику", comment: "edit shift stats impact alert title"),
            isPresented: $showStatsImpactConfirmation
        ) {
            Button(NSLocalizedString("Отмена", comment: "common cancel action"), role: .cancel) {}
            Button(NSLocalizedString("Продолжить", comment: "common continue action"), role: .destructive) {
                proceedSave()
            }
        } message: {
            Text(NSLocalizedString("Изменение этой смены повлияет на статистику. Продолжить?", comment: "edit shift stats impact alert message"))
        }
    }

    private func validateAndSave() {
        guard !normalizedName.isEmpty else {
            validationAlert = ValidationAlertContext(
                kind: .invalidName,
                title: NSLocalizedString("Проверьте данные", comment: "work type editor validation alert title"),
                message: NSLocalizedString("Введите название смены.", comment: "work type validation: empty name")
            )
            return
        }

        if requiresRate && rateValue <= 0 {
            validationAlert = ValidationAlertContext(
                kind: .invalidRate,
                title: NSLocalizedString("Проверьте данные", comment: "work type editor validation alert title"),
                message: NSLocalizedString("Укажите ставку больше нуля.", comment: "work type validation: invalid rate")
            )
            return
        }

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

        if affectsStatistics {
            showStatsImpactConfirmation = true
            return
        }

        proceedSave()
    }

    private func proceedSave() {
        applyChanges()
        HapticManager.shared.success()
        SoundManager.shared.play(.success)
        onSave()
        presentationMode.wrappedValue.dismiss()
    }

    private func upsertWorkType() -> WorkType {
        if let index = settings.workTypes.firstIndex(where: { $0.id == sourceWorkTypeId || $0.name == sourceWorkTypeName }) {
            settings.workTypes[index].name = normalizedName
            settings.workTypes[index].icon = selectedIcon
            settings.workTypes[index].colorHex = selectedColorHex
            settings.workTypes[index].hasHourlyRate = paymentMode == .hourly
            settings.workTypes[index].hasFixedRate = paymentMode == .fixed
            settings.workTypes[index].hasFloatingRate = paymentMode == .floating
            settings.workTypes[index].hasTips = hasTipsEnabled
            settings.workTypes[index].isActive = true
            settings.workTypes[index].hourlyRate = paymentMode == .hourly ? rateValue : 0
            settings.workTypes[index].fixedRate = paymentMode == .fixed ? rateValue : 0
            settings.workTypes[index].startHour = startHour
            settings.workTypes[index].startMinute = startMinute
            settings.workTypes[index].endHour = endHour
            settings.workTypes[index].endMinute = endMinute
            return settings.workTypes[index]
        }

        let newType = WorkType(
            name: normalizedName,
            icon: selectedIcon,
            colorHex: selectedColorHex,
            hasHourlyRate: paymentMode == .hourly,
            hasFixedRate: paymentMode == .fixed,
            hasFloatingRate: paymentMode == .floating,
            hasTips: hasTipsEnabled,
            isActive: true,
            hourlyRate: paymentMode == .hourly ? rateValue : 0,
            fixedRate: paymentMode == .fixed ? rateValue : 0,
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute
        )
        settings.workTypes.append(newType)
        return newType
    }

    private func applyChanges() {
        let updatedType = upsertWorkType()
        settings.saveSettings()

        sessionManager.applyWorkTypeChanges(
            fromName: sourceWorkTypeName,
            fromId: sourceWorkTypeId,
            to: updatedType
        )

        switch item {
        case .session(let session):
            guard let index = sessionManager.workSessions.firstIndex(where: { $0.id == session.id }) else { break }
            var updated = sessionManager.workSessions[index]
            updated.workTypeId = updatedType.id
            updated.workTypeName = normalizedName
            updated.icon = selectedIcon
            updated.hasHourlyRate = paymentMode == .hourly
            updated.hasFixedRate = paymentMode == .fixed
            updated.hasFloatingRate = paymentMode == .floating
            updated.hasTips = hasTipsEnabled
            updated.startHour = startHour
            updated.startMinute = startMinute
            updated.endHour = endHour
            updated.endMinute = endMinute
            updated.note = normalizedNote

            if paymentMode == .hourly {
                updated.hourlyRate = rateValue
                updated.fixedAmount = 0
                updated.floatingAmount = 0
            } else if paymentMode == .fixed {
                updated.hourlyRate = 0
                updated.fixedAmount = rateValue
                updated.floatingAmount = 0
            } else {
                updated.hourlyRate = 0
                updated.fixedAmount = 0
                updated.floatingAmount = max(floatingAmount, 0)
            }

            updated.tips = hasTipsEnabled ? max(tipsAmount, 0) : 0
            sessionManager.updateWorkSession(at: index, with: updated)

        case .planned(let planned):
            let calendar = Calendar.current
            var comps = calendar.dateComponents([.year, .month, .day], from: planned.date)
            comps.hour = startHour
            comps.minute = startMinute
            let newStart = calendar.date(from: comps) ?? planned.startTime

            comps.hour = endHour
            comps.minute = endMinute
            let newEnd = calendar.date(from: comps) ?? planned.endTime

            let updatedPlan = PlannedShift(
                id: planned.id,
                date: planned.date,
                workTypeId: updatedType.id,
                workTypeName: normalizedName,
                icon: selectedIcon,
                startTime: newStart,
                endTime: newEnd,
                hourlyRate: paymentMode == .hourly ? rateValue : 0,
                hasTips: hasTipsEnabled,
                note: normalizedNote
            )
            sessionManager.replacePlannedShift(id: planned.id, with: updatedPlan)
        }

        sessionManager.persistWorkSessionsToCoreData()
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

    @ViewBuilder
    // STYLE: `timePicker(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
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
}
