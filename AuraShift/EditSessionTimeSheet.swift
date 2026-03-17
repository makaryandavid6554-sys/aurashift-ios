//
//  EditSessionTimeSheet.swift
//  AuraShift
//
//  Created by David Makarian on 26.02.2026.
//

import SwiftUI

struct EditSessionTimeSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var session: WorkSession
    let settings: UserSettings
    let onDelete: () -> Void

    @State private var startHour: Int
    @State private var startMinute: Int
    @State private var endHour: Int
    @State private var endMinute: Int
    @State private var floatingAmount: Double
    @State private var tips: Double

    init(session: Binding<WorkSession>, settings: UserSettings, onDelete: @escaping () -> Void) {
        self._session = session
        self.settings = settings
        self.onDelete = onDelete

        _startHour = State(initialValue: session.wrappedValue.startHour)
        _startMinute = State(initialValue: session.wrappedValue.startMinute)
        _endHour = State(initialValue: session.wrappedValue.endHour)
        _endMinute = State(initialValue: session.wrappedValue.endMinute)
        _floatingAmount = State(initialValue: session.wrappedValue.floatingAmount)
        _tips = State(initialValue: session.wrappedValue.tips)
    }

    var body: some View {
        NavigationView {
            Form {
                // Информация о смене
                Section {
                    HStack {
                        Image(systemName: session.icon)
                            // STYLE: Акцентный цвет иконки типа смены.
                            .foregroundColor(AppColors.accent)
                        Text(session.workTypeName)
                            .font(.headline)
                            .foregroundColor(AppColors.text)
                    }
                }

                // Время смены (wheel-пикеры в iOS-стиле)
                Section(header: Text(NSLocalizedString("Время", comment: "edit session section header: time")).font(.caption).foregroundColor(.secondary)) {
                    timeWheelRow(
                        title: NSLocalizedString("Начало", comment: "edit session time picker title: start"),
                        hourSelection: $startHour,
                        minuteSelection: $startMinute
                    )
                    timeWheelRow(
                        title: NSLocalizedString("Конец", comment: "edit session time picker title: end"),
                        hourSelection: $endHour,
                        minuteSelection: $endMinute
                    )
                }

                // Заработок и чаевые
                if session.hasFloatingRate || session.hasTips {
                    Section(header: Text(NSLocalizedString("Заработок", comment: "edit session section header: earnings")).font(.caption).foregroundColor(.secondary)) {
                        if session.hasFloatingRate {
                            HStack {
                                Text(NSLocalizedString("Заработок", comment: "edit session label: earnings"))
                                    .font(.subheadline)
                                Spacer()
                                TextField(NSLocalizedString("0", comment: "edit session amount placeholder"), value: $floatingAmount, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 100)
                                Text(settings.defaultCurrency)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if session.hasTips {
                            HStack {
                                Text(NSLocalizedString("Чаевые", comment: "edit session label: tips"))
                                    .font(.subheadline)
                                Spacer()
                                TextField(NSLocalizedString("0", comment: "edit session tips placeholder"), value: $tips, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 100)
                                Text(settings.defaultCurrency)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Кнопка удаления
                Section {
                    Button(role: .destructive) {
                        onDelete()
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text(NSLocalizedString("Удалить смену", comment: "edit session destructive action: delete shift"))
                                .foregroundColor(AppColors.negative)
                            Spacer()
                        }
                    }
                }
            }
            // STYLE: Единый стеклянный фон формы редактирования смены.
            .visionFormBackground()
            .navigationTitle(NSLocalizedString("Редактировать смену", comment: "edit session title"))
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
                        session.startHour = startHour
                        session.startMinute = startMinute
                        session.endHour = endHour
                        session.endMinute = endMinute
                        session.floatingAmount = floatingAmount
                        session.tips = tips
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(AppColors.accent)
                }
            }
        }
        .accentColor(AppColors.accent)
    }

    @ViewBuilder
    private func timeWheelRow(title: String,
                              hourSelection: Binding<Int>,
                              minuteSelection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            DatePicker(
                "",
                selection: timeBinding(hour: hourSelection, minute: minuteSelection),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            // STYLE: Высота колеса времени внутри строки.
            .frame(height: 120)
            .clipped()
            // STYLE: Стеклянная карточка для wheel DatePicker.
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
}
