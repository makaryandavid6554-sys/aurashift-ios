// SettingsView.swift
// AuraShift — полный экран настроек (Free + Pro-заглушки)

import SwiftUI
import StoreKit
import CoreData
import CoreLocation
import UIKit
import UserNotifications

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var settings: UserSettings
    @StateObject private var proManager = ProManager.shared
    @StateObject private var iCloudSyncManager = ICloudSyncManager.shared
    @StateObject private var locationManager = DeviceLocationManager.shared
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Income.date, ascending: true)])
    private var incomes: FetchedResults<Income>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Expense.date, ascending: true)])
    private var expenses: FetchedResults<Expense>

    @State private var showAppearanceStudio = false
    @State private var showLanguagePicker  = false
    @State private var showNumberFormat    = false
    @State private var showGoalReminders   = false
    @State private var showAbout           = false
    @State private var showResetAlert      = false
    @State private var showProUpgrade      = false
    @State private var showExportSheet     = false
    @State private var showExportPeriodPicker = false
    @State private var showCustomExportRange = false
    @State private var selectedExportFormat: ExportFileFormat = .csv
    @State private var customExportStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customExportEndDate = Date()
    @State private var showNoDataExportAlert = false
    @State private var showBiometryUnavailableAlert = false
    @State private var exportURL: URL?     = nil
    @State private var weatherLiveStatus: WeatherLiveStatus = .fallback
    @State private var weatherLiveStatusError: String?

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            ZStack {
                VisionBackdropView()
                ScrollView {
                    VStack(spacing: 0) {
                        // Pro-баннер (только для Free пользователей)
                        if !proManager.isProUser {
                            proBanner
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                        }

                        settingsGroup(title: NSLocalizedString("Внешний вид", comment: "settings section title: appearance")) {
                            themeRow
                            appearanceStudioRow
                        }

                        settingsGroup(title: NSLocalizedString("Система", comment: "settings section title: system")) {
                            languageRow
                            numberFormatRow
                            iCloudSyncRow
                            analyticsRow
                        }

                        settingsGroup(title: NSLocalizedString("Уведомления", comment: "settings section title: notifications")) {
                            dailyReminderRow
                            goalReminderRow
                            soundsRow
                            hapticsRow
                        }

                        settingsGroup(title: NSLocalizedString("Данные", comment: "settings section title: data")) {
                            csvExportRow
                            if proManager.isProUser {
                                xlsxExportRow
                            }
                            resetDataRow
                        }

                        settingsGroup(title: NSLocalizedString("Безопасность", comment: "settings section title: security")) {
                            appLockRow
                        }

                        if proManager.isProUser {
                            settingsGroup(title: NSLocalizedString("Pro — AI и аналитика", comment: "settings section title: pro ai and analytics")) {
                                proManagementRow
                                proAIRow
                                proExternalFactorsConfigRow
                                proScheduleRow
                            }
                        }

                        settingsGroup(title: NSLocalizedString("О приложении", comment: "settings section title: about app")) {
                            appVersionRow
                            feedbackRow
                            rateAppRow
                            privacyRow
                            termsRow
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Настройки", comment: "settings screen title"))
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            iCloudSyncManager.refresh(isEnabled: settings.iCloudSyncEnabled)
        }
        .sheet(isPresented: $showAppearanceStudio) { AppearanceStudioSheet(settings: settings) }
        .sheet(isPresented: $showLanguagePicker) { AppLanguagePickerSheet(settings: settings) }
        .sheet(isPresented: $showNumberFormat)   { NumberFormatSettingsSheet(settings: settings) }
        .sheet(isPresented: $showGoalReminders)  { GoalReminderSettingsSheet(settings: settings) }
        .sheet(isPresented: $showAbout)          { AboutSheet() }
        .sheet(isPresented: $showProUpgrade)     { ProUpgradeSheet() }
        .sheet(isPresented: $showCustomExportRange) { customExportRangeSheet }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .confirmationDialog(selectedExportFormat.dialogTitle, isPresented: $showExportPeriodPicker, titleVisibility: .visible) {
            ForEach(ExportPeriod.allCases.filter { $0 != .custom }) { period in
                Button(period.localizedTitle) { exportPeriod(period) }
            }
            Button(NSLocalizedString("Выбрать период...", comment: "settings csv export dialog action: custom period")) { showCustomExportRange = true }
            Button(NSLocalizedString("Отмена", comment: "common cancel action"), role: .cancel) {}
        }
        .alert(NSLocalizedString("Нет данных для экспорта", comment: "settings export no data alert title"), isPresented: $showNoDataExportAlert) {
            Button(NSLocalizedString("Ок", comment: "common ok action"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("За выбранный период нет доходов и расходов.", comment: "settings export no data alert message"))
        }
        .alert(NSLocalizedString("Биометрия недоступна", comment: "settings biometric unavailable alert title"), isPresented: $showBiometryUnavailableAlert) {
            Button(NSLocalizedString("Ок", comment: "common ok action"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("На этом устройстве не настроены Face ID/Touch ID или код устройства.", comment: "settings biometric unavailable alert message"))
        }
        .alert(NSLocalizedString("Сбросить все данные?", comment: "settings reset all data alert title"), isPresented: $showResetAlert) {
            Button(NSLocalizedString("Удалить", comment: "common delete action"), role: .destructive) { resetAllData() }
            Button(NSLocalizedString("Отмена", comment: "common cancel action"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Это действие удалит все смены, расходы и цели. Отменить невозможно.", comment: "settings reset all data alert message"))
        }
    }

    // MARK: - Pro-баннер

    // STYLE: `proBanner` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var proBanner: some View {
        Button(action: { showProUpgrade = true }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.accentGradient)
                        .frame(width: 40, height: 40)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("AuraShift Pro", comment: "settings pro banner title"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppColors.text)
                    Text(NSLocalizedString("Умный AI, AI-ориентиры бюджета, планировщик графика", comment: "settings pro banner subtitle"))
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.secondaryText)
                }
                Spacer()
                Text(NSLocalizedString("Открыть", comment: "common open action"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .visionGlassCard(cornerRadius: 8, opacity: 0.84, showRing: true)
            }
            .padding(14)
            .visionGlassCard(cornerRadius: 16, opacity: 0.84, showRing: true)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Секции

    // Тема
    // STYLE: `themeRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var themeRow: some View {
        HStack {
            settingsIcon("moon.fill", color: .indigo)
            Text(NSLocalizedString("Тема", comment: "settings row: theme"))
            Spacer()
            Picker("", selection: $settings.colorTheme) {
                Text(NSLocalizedString("Авто", comment: "theme option: auto")).tag(UserSettings.ColorTheme.system)
                Text(NSLocalizedString("Светлая", comment: "theme option: light")).tag(UserSettings.ColorTheme.light)
                Text(NSLocalizedString("Тёмная", comment: "theme option: dark")).tag(UserSettings.ColorTheme.dark)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }

    // STYLE: `appearanceStudioRow` — единая вкладка для акцента и обоев.
    private var appearanceStudioRow: some View {
        Button(action: { showAppearanceStudio = true }) {
            HStack {
                settingsIcon("photo.on.rectangle.angled", color: .blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("Оформление", comment: "settings row: appearance studio"))
                        .foregroundColor(AppColors.text)
                }
                Spacer()
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(AppColors.border, lineWidth: 1))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText.opacity(0.5))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Язык интерфейса
    // STYLE: `languageRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var languageRow: some View {
        Button(action: { showLanguagePicker = true }) {
            HStack {
                settingsIcon("globe", color: .blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("Язык интерфейса", comment: "settings row: app language")).foregroundColor(AppColors.text)
                    Text(settings.appLanguage.displayName)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText.opacity(0.5))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Формат чисел и валюты
    // STYLE: `numberFormatRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var numberFormatRow: some View {
        Button(action: { showNumberFormat = true }) {
            HStack {
                settingsIcon("number.circle.fill", color: .mint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("Формат чисел и валюты", comment: "settings row: numbers and currency format"))
                        .foregroundColor(AppColors.text)
                    Text(settings.numberFormatPreview)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText.opacity(0.5))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // NOTE(iCloud): This row controls the user-facing toggle only. CloudKit is currently disabled in Persistence.swift.
    // See FULL_RESTORE_AFTER_DEV_ACCOUNT.md, section "1) iCloud / CloudKit (Core Data sync)" for re-enable steps.
    // iCloud sync (подготовка)
    // STYLE: `iCloudSyncRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var iCloudSyncRow: some View {
            HStack {
                settingsIcon("icloud.fill", color: .cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("iCloud синхронизация", comment: "settings row: iCloud sync"))
                    Text(iCloudSyncManager.statusDescription)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            Spacer()
            Toggle("", isOn: $settings.iCloudSyncEnabled)
                .tint(AppColors.accent)
                .onChange(of: settings.iCloudSyncEnabled) { enabled in
                    settings.saveSettings()
                    iCloudSyncManager.refresh(isEnabled: enabled)
                    if enabled {
                        HapticManager.shared.success()
                    } else {
                        HapticManager.shared.selection()
                    }
                }
        }
    }

    // Ежедневное напоминание
    // STYLE: `dailyReminderRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var dailyReminderRow: some View {
        HStack {
            settingsIcon("bell.fill", color: .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("Ежедневное напоминание", comment: "settings row: daily reminder"))
                if settings.reminderEnabled {
                    Text(
                        String(
                            format: NSLocalizedString("Каждый день в %@", comment: "settings daily reminder subtitle"),
                            timeFormatter.string(from: settings.reminderTime)
                        )
                    )
                        .font(.caption).foregroundColor(AppColors.secondaryText)
                }
            }
            Spacer()
            Toggle("", isOn: $settings.reminderEnabled)
                .tint(AppColors.accent)
                .onChange(of: settings.reminderEnabled) { enabled in
                    settings.saveSettings()
                    if enabled {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                            DispatchQueue.main.async {
                                if granted {
                                    NotificationManager.shared.syncReminder(with: settings)
                                } else {
                                    settings.reminderEnabled = false
                                }
                            }
                        }
                    } else {
                        NotificationManager.shared.syncReminder(with: settings)
                    }
                }
        }
    }

    // Напоминания о целях
    // STYLE: `goalReminderRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var goalReminderRow: some View {
        Button(action: { showGoalReminders = true }) {
            HStack {
                settingsIcon("target", color: AppColors.positive)
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("Напоминания о целях", comment: "settings row: goal reminders")).foregroundColor(AppColors.text)
                    Text(
                        settings.goalReminderEnabled
                        ? String(
                            format: NSLocalizedString("За %d дн. до дедлайна", comment: "settings goal reminder subtitle"),
                            settings.goalReminderDaysBefore
                        )
                        : NSLocalizedString("Выключено", comment: "common off state")
                    )
                        .font(.caption).foregroundColor(AppColors.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText.opacity(0.5))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Звук
    // STYLE: `soundsRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var soundsRow: some View {
        HStack {
            settingsIcon("speaker.wave.2.fill", color: .purple)
            Text(NSLocalizedString("Звуки интерфейса", comment: "settings row: interface sounds"))
            Spacer()
            Toggle("", isOn: $settings.soundsEnabled)
                .tint(AppColors.accent)
                .onChange(of: settings.soundsEnabled) { _ in
                    settings.saveSettings()
                    if settings.soundsEnabled {
                        SoundManager.shared.play(.tap)
                    }
                }
        }
    }

    // Вибрация
    // STYLE: `hapticsRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var hapticsRow: some View {
        HStack {
            settingsIcon("iphone.radiowaves.left.and.right", color: .teal)
            Text(NSLocalizedString("Тактильная отдача", comment: "settings row: haptics"))
            Spacer()
            Toggle("", isOn: $settings.hapticsEnabled)
                .tint(AppColors.accent)
                .onChange(of: settings.hapticsEnabled) { _ in
                    if settings.hapticsEnabled { HapticManager.shared.impact(.medium) }
                }
        }
    }

    // STYLE: `analyticsRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var analyticsRow: some View {
        HStack {
            settingsIcon("chart.line.uptrend.xyaxis", color: .indigo)
            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("Анонимная аналитика", comment: "settings row: anonymous analytics"))
                Text(settings.anonymousAnalyticsEnabled
                     ? NSLocalizedString("Включено", comment: "common switch state enabled")
                     : NSLocalizedString("Выключено", comment: "common switch state disabled"))
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            Spacer()
            Toggle("", isOn: $settings.anonymousAnalyticsEnabled)
                .tint(AppColors.accent)
                .onChange(of: settings.anonymousAnalyticsEnabled) { enabled in
                    settings.saveSettings()
                    AnalyticsManager.shared.setEnabled(enabled)
                    HapticManager.shared.selection()
                }
        }
    }

    // CSV экспорт
    // STYLE: `csvExportRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var csvExportRow: some View {
        Button(action: {
            selectedExportFormat = .csv
            showExportPeriodPicker = true
        }) {
            HStack {
                settingsIcon("doc.text", color: .green)
                Text(NSLocalizedString("Экспорт в CSV", comment: "settings row: export csv")).foregroundColor(AppColors.text)
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.accent)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // XLSX (Pro)
    // STYLE: `xlsxExportRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var xlsxExportRow: some View {
        Button(action: {
            selectedExportFormat = .xlsx
            showExportPeriodPicker = true
        }) {
            HStack {
                settingsIcon("tablecells", color: .green)
                Text(NSLocalizedString("Экспорт в Excel (Pro)", comment: "settings row: export xlsx pro"))
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.accent)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Сброс данных
    // STYLE: `resetDataRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var resetDataRow: some View {
        Button(action: { showResetAlert = true }) {
            HStack {
                settingsIcon("trash.fill", color: .red)
                Text(NSLocalizedString("Сбросить все данные", comment: "settings row: reset all data"))
                    .foregroundColor(AppColors.negative)
                Spacer()
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Блокировка
    // STYLE: `appLockRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var appLockRow: some View {
        HStack {
            settingsIcon("faceid", color: .blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("Блокировка (Face ID / Touch ID)", comment: "settings row: app lock"))
                Text(settings.appLockEnabled
                     ? String(format: NSLocalizedString("Включено: %@", comment: "settings app lock enabled with auth type"), BiometricManager.shared.authType().localizedTitle)
                     : NSLocalizedString("Выключено", comment: "common switch state disabled"))
                    .font(.caption).foregroundColor(AppColors.secondaryText)
            }
            Spacer()
            Toggle("", isOn: $settings.appLockEnabled)
                .tint(AppColors.accent)
                .onChange(of: settings.appLockEnabled) { enabled in
                    settings.saveSettings()
                    guard enabled else {
                        HapticManager.shared.selection()
                        return
                    }
                    if !BiometricManager.shared.canAuthenticate() {
                        settings.appLockEnabled = false
                        showBiometryUnavailableAlert = true
                        HapticManager.shared.error()
                        return
                    }
                    HapticManager.shared.success()
                }
        }
    }

    // Pro AI
    // STYLE: `proManagementRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var proManagementRow: some View {
        Button(action: { showProUpgrade = true }) {
            HStack {
                settingsIcon("crown.fill", color: Color(hex:"#6C5CE7") ?? .purple)
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("Управление Pro", comment: "settings row: manage pro"))
                    Text(NSLocalizedString("Тариф, восстановление и debug-переключатели", comment: "settings row subtitle: manage pro"))
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }

    // STYLE: `proAIRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var proAIRow: some View {
        HStack {
            settingsIcon("brain", color: Color(hex:"#6C5CE7") ?? .purple)
            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("Улучшенный AI", comment: "settings row: advanced ai"))
                Text(NSLocalizedString("Активен в Pro автоматически", comment: "settings advanced ai status"))
                    .font(.caption).foregroundColor(AppColors.secondaryText)
            }
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(AppColors.positive)
        }
    }

    // STYLE: `proExternalFactorsConfigRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var proExternalFactorsConfigRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.leading, 40)

            HStack(spacing: 10) {
                settingsIcon("cloud.sun.fill", color: .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Live-погода", comment: "settings row: live weather"))
                    Text(NSLocalizedString("Open-Meteo с локальным кэшом", comment: "settings row subtitle: weather provider and cache"))
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                Spacer()
                Toggle("", isOn: $settings.proUseLiveWeather)
                    .tint(AppColors.accent)
            }

            HStack(spacing: 10) {
                settingsIcon("location.fill", color: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Геопозиция устройства", comment: "settings row: device geolocation"))
                    Text(locationManager.authorizationDescription)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                    if !locationManager.cityName.isEmpty {
                        Text(locationManager.cityName)
                            .font(.caption)
                            .foregroundColor(AppColors.text)
                    }
                    if !locationManager.countryCode.isEmpty {
                        Text(String(
                            format: NSLocalizedString("ISO: %@", comment: "settings weather location ISO code"),
                            locationManager.countryCode
                        ))
                            .font(.caption2)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    if let coordinate = locationManager.coordinate {
                        Text(formattedCoordinates(coordinate))
                            .font(.caption2)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    if let error = locationManager.lastErrorText, !error.isEmpty {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(AppColors.negative)
                    }
                    if weatherLiveStatus == .error, let weatherLiveStatusError, !weatherLiveStatusError.isEmpty {
                        Text(weatherLiveStatusError)
                            .font(.caption2)
                            .foregroundColor(AppColors.negative)
                    }
                }
                Spacer()
                Circle()
                    .fill(weatherStatusDotColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                    )
            }
            .opacity(settings.proUseLiveWeather ? 1 : 0.6)

            HStack(spacing: 8) {
                switch locationManager.authorizationStatus {
                case .notDetermined:
                    Button(NSLocalizedString("Разрешить при использовании", comment: "settings location action: allow when in use")) {
                        locationManager.requestWhenInUseAuthorization()
                    }
                case .authorizedWhenInUse:
                    Button(NSLocalizedString("Обновить GPS", comment: "settings location action: refresh gps")) {
                        locationManager.refreshLocation()
                    }
                    // Removed "Разрешить всегда" button as per instructions
                case .authorizedAlways:
                    Button(NSLocalizedString("Обновить GPS", comment: "settings location action: refresh gps")) {
                        locationManager.refreshLocation()
                    }
                case .denied, .restricted:
                    Button(NSLocalizedString("Открыть настройки", comment: "settings location action: open system settings")) {
                        locationManager.openSystemLocationSettings()
                    }
                @unknown default:
                    Button(NSLocalizedString("Обновить GPS", comment: "settings location action: refresh gps")) {
                        locationManager.refreshLocation()
                    }
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .buttonStyle(.bordered)
            .disabled(!settings.proUseLiveWeather)
            .opacity(settings.proUseLiveWeather ? 1 : 0.6)

            HStack(spacing: 10) {
                settingsIcon("flag.2.crossed.fill", color: .mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Регион праздников", comment: "settings row: holiday region"))
                    Picker("", selection: $settings.proHolidayRegionCode) {
                        ForEach(HolidayRegion.allCases) { region in
                            Text(region.displayName).tag(region.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Spacer()
            }
        }
        .onChange(of: settings.proUseLiveWeather) { _ in
            settings.saveSettings()
            refreshLocationForWeather(promptIfNeeded: true)
            refreshWeatherStatusIndicator()
        }
        .onChange(of: settings.proHolidayRegionCode) { newValue in
            if HolidayRegion(rawValue: newValue) == nil {
                settings.proHolidayRegionCode = HolidayRegion.auto.rawValue
            }
            settings.saveSettings()
        }
        .onChange(of: locationManager.authorizationStatus) { newStatus in
            if newStatus == .authorizedAlways || newStatus == .authorizedWhenInUse {
                refreshLocationForWeather(promptIfNeeded: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceLocationManagerDidUpdate)) { _ in
            let city = locationManager.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !city.isEmpty, city != settings.proWeatherCity {
                settings.proWeatherCity = city
                settings.saveSettings()
            }
        }
        .onAppear {
            refreshLocationForWeather(promptIfNeeded: false)
            refreshWeatherStatusIndicator()
        }
        .onReceive(NotificationCenter.default.publisher(for: .weatherManagerStatusDidChange)) { _ in
            refreshWeatherStatusIndicator()
        }
    }

    private func refreshLocationForWeather(promptIfNeeded: Bool) {
        guard settings.proUseLiveWeather else { return }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            if promptIfNeeded {
                locationManager.requestWhenInUseAuthorization()
            }
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.refreshLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func formattedCoordinates(_ coordinate: (latitude: Double, longitude: Double)) -> String {
        String(format: "Lat %.4f, Lon %.4f", coordinate.latitude, coordinate.longitude)
    }

    private var weatherStatusDotColor: Color {
        guard settings.proUseLiveWeather else { return .orange }
        switch weatherLiveStatus {
        case .active:
            return AppColors.positive
        case .error:
            return AppColors.negative
        case .fallback:
            return .orange
        }
    }

    private func refreshWeatherStatusIndicator() {
        weatherLiveStatus = WeatherManager.shared.currentLiveStatus
        weatherLiveStatusError = WeatherManager.shared.currentLiveStatusErrorMessage
    }

    // STYLE: `proScheduleRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var proScheduleRow: some View {
        HStack {
            settingsIcon("calendar.badge.plus", color: Color(hex:"#6C5CE7") ?? .purple)
            Text(NSLocalizedString("Планировщик графика", comment: "settings row: schedule planner"))
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.positive)
        }
    }

    // Версия
    // STYLE: `appVersionRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var appVersionRow: some View {
        HStack {
            settingsIcon("info.circle.fill", color: .gray)
            Text(NSLocalizedString("Версия приложения", comment: "settings row: app version"))
            Spacer()
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                .foregroundColor(AppColors.secondaryText)
                .font(.subheadline)
        }
    }

    // Обратная связь
    // STYLE: `feedbackRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var feedbackRow: some View {
        Button(action: sendFeedback) {
            HStack {
                settingsIcon("envelope.fill", color: .blue)
                Text(NSLocalizedString("Написать разработчику", comment: "settings row: contact developer")).foregroundColor(AppColors.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText.opacity(0.5))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Оценить
    // STYLE: `rateAppRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var rateAppRow: some View {
        Button(action: rateApp) {
            HStack {
                settingsIcon("star.fill", color: .yellow)
                Text(NSLocalizedString("Оценить AuraShift", comment: "settings row: rate app")).foregroundColor(AppColors.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText.opacity(0.5))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Политика
    // STYLE: `privacyRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var privacyRow: some View {
        Button(action: { openURL("https://aurashift.app/privacy") }) {
            HStack {
                settingsIcon("lock.shield.fill", color: .gray)
                Text(NSLocalizedString("Политика конфиденциальности", comment: "settings row: privacy policy")).foregroundColor(AppColors.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText.opacity(0.5))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Условия
    // STYLE: `termsRow` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var termsRow: some View {
        Button(action: { openURL("https://aurashift.app/terms") }) {
            HStack {
                settingsIcon("doc.plaintext.fill", color: .gray)
                Text(NSLocalizedString("Условия использования", comment: "settings row: terms of use")).foregroundColor(AppColors.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText.opacity(0.5))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Вспомогательные view

    @ViewBuilder
    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 6)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                content()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.clear)
                    // divider между строками — автоматически через overlay
            }
            .visionGlassCard(cornerRadius: 14, opacity: 0.82, showRing: true)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 0.5))
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    // STYLE: `settingsIcon(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private func settingsIcon(_ name: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(AppColors.accent.opacity(0.88))
                .frame(width: 30, height: 30)
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Actions

    private func exportPeriod(_ period: ExportPeriod) {
        let range = period.dateRange()
        exportData(from: range.start, to: range.end, format: selectedExportFormat)
    }

    private func exportData(from startDate: Date, to endDate: Date, format: ExportFileFormat) {
        HapticManager.shared.impact(.light)
        let start = min(startDate, endDate)
        let end = max(startDate, endDate)

        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let endExclusive = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end)) ?? end

        let filteredIncomes = incomes.filter {
            guard let date = $0.date else { return false }
            return date >= startDay && date < endExclusive
        }
        let filteredExpenses = expenses.filter {
            guard let date = $0.date else { return false }
            return date >= startDay && date < endExclusive
        }

        guard !filteredIncomes.isEmpty || !filteredExpenses.isEmpty else {
            showNoDataExportAlert = true
            HapticManager.shared.error()
            return
        }

        let url: URL?
        switch format {
        case .csv:
            url = ExportManager.shared.generateCSV(
                incomes: filteredIncomes,
                expenses: filteredExpenses,
                currency: settings.defaultCurrency,
                from: startDay,
                to: end
            )
        case .xlsx:
            url = ExportManager.shared.generateXLSX(
                incomes: filteredIncomes,
                expenses: filteredExpenses,
                currency: settings.defaultCurrency,
                from: startDay,
                to: end
            )
        }

        if let url {
            exportURL = url
            showExportSheet = true
            HapticManager.shared.success()
        } else {
            HapticManager.shared.error()
        }
    }

    private func sendFeedback() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let subject = "AuraShift \(version) — Обратная связь"
        let body    = "Версия: \(version)\nУстройство: \(UIDevice.current.model)\niOS: \(UIDevice.current.systemVersion)\n\n"
        let encoded = "mailto:support@aurashift.com?subject=\(subject)&body=\(body)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: encoded) {
            UIApplication.shared.open(url)
        }
    }

    private func rateApp() {
        // SKStoreReviewController для in-app запроса
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func resetAllData() {
        do {
            try PersistenceController.shared.deleteAllData()
            NotificationManager.shared.removeAllGoalReminders()
            HapticManager.shared.success()
        } catch {
            HapticManager.shared.error()
            print("❌ Ошибка сброса данных: \(error)")
        }
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }

    // STYLE: `customExportRangeSheet` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private var customExportRangeSheet: some View {
        NavigationView {
            Form {
                Section(header: Text(NSLocalizedString("Период экспорта", comment: "settings export custom period section header"))) {
                    DatePicker(NSLocalizedString("С", comment: "export custom period start"), selection: $customExportStartDate, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .frame(height: 140)
                        .clipped()
                        .visionGlassCard(cornerRadius: 12, opacity: 0.82)
                    DatePicker(NSLocalizedString("По", comment: "export custom period end"), selection: $customExportEndDate, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .frame(height: 140)
                        .clipped()
                        .visionGlassCard(cornerRadius: 12, opacity: 0.82)
                }
            }
            .visionFormBackground()
            .navigationTitle(selectedExportFormat.dialogTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button(NSLocalizedString("Отмена", comment: "common cancel action")) { showCustomExportRange = false }
                    .foregroundColor(AppColors.accent),
                trailing: Button(NSLocalizedString("Экспорт", comment: "common export action")) {
                    exportData(from: customExportStartDate, to: customExportEndDate, format: selectedExportFormat)
                    showCustomExportRange = false
                }
                .foregroundColor(AppColors.accent)
            )
        }
    }
}

private enum ExportFileFormat {
    case csv
    case xlsx

    var dialogTitle: String {
        switch self {
        case .csv:
            return NSLocalizedString("Экспорт CSV", comment: "settings csv export dialog title")
        case .xlsx:
            return NSLocalizedString("Экспорт Excel", comment: "settings xlsx export dialog title")
        }
    }
}

struct BudgetSettingsSheet: View {
    @ObservedObject var settings: UserSettings
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var proManager = ProManager.shared
    private let minAIBudgetHintDays = 7

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Expense.date, ascending: false)])
    private var expenses: FetchedResults<Expense>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Income.date, ascending: false)])
    private var incomes: FetchedResults<Income>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \FinancialGoal.deadline, ascending: true)])
    private var goals: FetchedResults<FinancialGoal>

    @State private var draftLimits: [String: Double] = [:]
    @State private var draftWarningsEnabled = true

    private struct AIBudgetHintContext {
        let goalName: String
        let deadline: Date
        let totalMonthlyLimit: Double
        let perCategoryLimit: [String: Double]
    }

    private var activeGoal: FinancialGoal? {
        goals
            .filter { $0.isActive }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            .first
    }

    private var currentMonthSpent: [String: Double] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date()

        var totals: [String: Double] = [:]
        for expense in expenses {
            guard let date = expense.date, date >= monthStart, date < monthEnd else { continue }
            let category = settings.normalizedExpenseCategoryName(expense.category ?? NSLocalizedString("Другое", comment: "budget default category"))
            totals[category, default: 0] += expense.amount
        }
        return totals
    }

    private var aiBudgetHintContext: AIBudgetHintContext? {
        guard proManager.canUse(.budgets) else { return nil }
        guard let goal = activeGoal,
              let deadline = goal.deadline else {
            return nil
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let deadlineDay = calendar.startOfDay(for: deadline)
        guard deadlineDay >= today else { return nil }

        let remainingGoalAmount = max(goal.targetAmount - goal.currentAmount, 0)
        guard remainingGoalAmount > 0 else { return nil }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let windowStart = calendar.date(byAdding: .day, value: -89, to: today) ?? today

        var incomeTotalWindow = 0.0
        var expenseTotalWindow = 0.0
        var expenseByCategoryWindow: [String: Double] = [:]
        var firstDataDate: Date?

        for income in incomes {
            guard let date = income.date, date >= windowStart, date < tomorrow else { continue }
            let amount = (income.hoursWorked * income.hourlyRate) + income.tips + income.floatingAmount
            incomeTotalWindow += amount
            firstDataDate = min(firstDataDate ?? date, date)
        }

        for expense in expenses {
            guard let date = expense.date, date >= windowStart, date < tomorrow else { continue }
            let amount = max(expense.amount, 0)
            let category = settings.normalizedExpenseCategoryName(
                expense.category ?? NSLocalizedString("Другое", comment: "budget default category")
            )
            expenseTotalWindow += amount
            expenseByCategoryWindow[category, default: 0] += amount
            firstDataDate = min(firstDataDate ?? date, date)
        }

        guard let firstDate = firstDataDate else { return nil }
        let dataDays = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: firstDate), to: tomorrow).day ?? 1)
        guard dataDays >= minAIBudgetHintDays else { return nil }

        let monthlyScale = 30.0 / Double(dataDays)
        let estimatedMonthlyIncome = incomeTotalWindow * monthlyScale

        let daysToDeadline = max(1, calendar.dateComponents([.day], from: today, to: deadlineDay).day ?? 1)
        let monthsToDeadline = max(Double(daysToDeadline) / 30.0, 0.25)
        let requiredNetPerMonth = remainingGoalAmount / monthsToDeadline
        let recommendedMonthlyExpenseLimit = max(0, estimatedMonthlyIncome - requiredNetPerMonth)

        let normalizedCategories = settings.expenseCategories.map { settings.normalizedExpenseCategoryName($0) }
        guard !normalizedCategories.isEmpty else { return nil }

        let baseShare = 1.0 / Double(normalizedCategories.count)
        var blendedShares: [String: Double] = [:]
        for category in normalizedCategories {
            let historical = expenseByCategoryWindow[category, default: 0]
            let empirical = expenseTotalWindow > 0 ? (historical / expenseTotalWindow) : 0
            // Лёгкое сглаживание: у новых категорий всегда есть ненулевой ориентир.
            blendedShares[category] = empirical * 0.85 + baseShare * 0.15
        }

        let shareSum = max(blendedShares.values.reduce(0, +), 0.0001)
        var perCategory: [String: Double] = [:]
        for category in normalizedCategories {
            let normalizedShare = (blendedShares[category] ?? baseShare) / shareSum
            let rawValue = max(0, recommendedMonthlyExpenseLimit * normalizedShare)
            perCategory[category] = (rawValue / 10.0).rounded() * 10.0
        }

        return AIBudgetHintContext(
            goalName: (goal.name?.isEmpty == false ? goal.name! : NSLocalizedString("Активная цель", comment: "budget ai fallback goal name")),
            deadline: deadlineDay,
            totalMonthlyLimit: (recommendedMonthlyExpenseLimit / 10.0).rounded() * 10.0,
            perCategoryLimit: perCategory
        )
    }

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(NSLocalizedString("Показывать предупреждения о перерасходе", comment: "budget warnings toggle"), isOn: $draftWarningsEnabled)
                        .tint(AppColors.accent)
                } header: {
                    Text(NSLocalizedString("Уведомления", comment: "budget section header: notifications"))
                } footer: {
                    Text(NSLocalizedString("Предупреждения появляются в аналитике, когда расход по категории превышает лимит.", comment: "budget warnings footer"))
                }

                Section(header: Text(NSLocalizedString("Лимиты по категориям", comment: "budget section header: category limits"))) {
                    if settings.expenseCategories.isEmpty {
                        Text(NSLocalizedString("Добавьте категории расходов в настройках.", comment: "budget empty state categories"))
                            .foregroundColor(AppColors.secondaryText)
                    } else {
                        ForEach(settings.expenseCategories, id: \.self) { category in
                            budgetRow(category: category)
                        }
                        if !proManager.canUse(.budgets) {
                            Text(NSLocalizedString("AI-ориентиры бюджета доступны в Pro.", comment: "budget ai hints paywall hint"))
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                        } else if aiBudgetHintContext == nil {
                            Text(
                                String(
                                    format: NSLocalizedString("AI-подсказки появятся после включения активной цели и минимум %d дней данных.", comment: "budget ai hints empty state with dynamic minimum days"),
                                    minAIBudgetHintDays
                                )
                            )
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
            }
            .visionFormBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(NSLocalizedString("Бюджеты", comment: "budget sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button(NSLocalizedString("Отмена", comment: "common cancel action")) {
                    presentationMode.wrappedValue.dismiss()
                }.foregroundColor(AppColors.accent),
                trailing: Button(NSLocalizedString("Сохранить", comment: "common save action")) {
                    applyChanges()
                    presentationMode.wrappedValue.dismiss()
                }.foregroundColor(AppColors.accent)
            )
            .onAppear {
                draftLimits = settings.proBudgetLimits
                draftWarningsEnabled = settings.proBudgetWarningsEnabled
            }
        }
    }

    @ViewBuilder
    // STYLE: `budgetRow(...)` — визуальный блок; здесь меняются цвета, фон, отступы и размеры.
    private func budgetRow(category: String) -> some View {
        let normalizedCategory = settings.normalizedExpenseCategoryName(category)
        let key = normalizedCategory.lowercased()
        let spent = currentMonthSpent[normalizedCategory, default: 0]
        let limit = draftLimits[key] ?? 0
        let ratio = limit > 0 ? spent / limit : 0
        let progressColor: Color = ratio >= 1 ? AppColors.negative : (ratio >= 0.8 ? (Color(hex: "#A16B44") ?? .orange) : AppColors.positive)
        let aiHintLimit = aiBudgetHintContext?.perCategoryLimit[normalizedCategory]

        VStack(alignment: .leading, spacing: 8) {
            NumberField(
                title: normalizedCategory,
                value: Binding(
                    get: { draftLimits[key] ?? 0 },
                    set: { newValue in
                        if newValue > 0 {
                            draftLimits[key] = newValue
                        } else {
                            draftLimits.removeValue(forKey: key)
                        }
                    }
                ),
                currency: settings.defaultCurrency,
                showsKeyboardToolbar: false
            )

            if aiBudgetHintContext != nil, let aiHintLimit, aiHintLimit > 0 {
                Text(
                    String(
                        format: NSLocalizedString("Рекомендованный бюджет: до %@ / месяц", comment: "budget ai compact per-category recommendation"),
                        settings.formattedCurrency(aiHintLimit)
                    )
                )
                .font(.caption2)
                .foregroundColor(AppColors.accent)
            }

            if limit > 0 {
                let spentText = settings.formattedCurrency(spent)
                let limitText = settings.formattedCurrency(limit)
                Text(String(
                    format: NSLocalizedString("Текущий месяц: %@ из %@", comment: "budget row monthly spent and limit"),
                    spentText,
                    limitText
                ))
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)

                ProgressView(value: min(max(ratio, 0), 1))
                    .tint(progressColor)
                    .scaleEffect(x: 1, y: 1.3, anchor: .center)
            }
        }
        .padding(.vertical, 4)
    }

    private func applyChanges() {
        var normalized: [String: Double] = [:]
        for category in settings.expenseCategories {
            let key = settings.normalizedExpenseCategoryName(category).lowercased()
            guard !key.isEmpty else { continue }
            let limit = max(0, draftLimits[key] ?? 0)
            if limit > 0 {
                normalized[key] = limit
            }
        }
        settings.proBudgetLimits = normalized
        settings.proBudgetWarningsEnabled = draftWarningsEnabled
        settings.saveSettings()
    }

    private func budgetDeadlineString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

}

// MARK: - AppearanceStudioSheet

struct AppearanceStudioSheet: View {
    @ObservedObject var settings: UserSettings
    @Environment(\.presentationMode) var presentationMode

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            ZStack {
                VisionBackdropView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(NSLocalizedString("Цветовая схема", comment: "appearance studio unified color section"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.secondaryText)
                                .textCase(.uppercase)
                                .padding(.horizontal, 16)

                            HStack(spacing: 10) {
                                Circle()
                                    .fill(AppColors.accent)
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(AppColors.border, lineWidth: 1))
                                Text(NSLocalizedString("Используется единый акцентный цвет для лучшей читаемости в светлой и тёмной теме.", comment: "appearance studio unified color description"))
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(AppColors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 16)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(NSLocalizedString("Обои", comment: "appearance studio wallpapers section"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.secondaryText)
                                .textCase(.uppercase)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(GradientManager.shared.selectableStyles) { style in
                                        Button(action: { selectWallpaper(style) }) {
                                            ZStack {
                                                wallpaperCirclePreview(style)
                                                    .frame(width: 42, height: 42)
                                                    .clipShape(Circle())
                                                Circle()
                                                    .stroke(settings.wallpaperStyle == style ? AppColors.accent.opacity(0.92) : Color.white.opacity(0.30), lineWidth: settings.wallpaperStyle == style ? 2 : 1)
                                                if settings.wallpaperStyle == style {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundColor(.white)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(NSLocalizedString("Оформление", comment: "settings appearance studio title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(NSLocalizedString("Готово", comment: "common done action")) {
                presentationMode.wrappedValue.dismiss()
            }.foregroundColor(AppColors.accent))
        }
    }

    private func selectWallpaper(_ style: UserSettings.WallpaperStyle) {
        settings.wallpaperStyle = style
        settings.saveSettings()
        HapticManager.shared.selection()
    }

    @ViewBuilder
    private func wallpaperCirclePreview(_ style: UserSettings.WallpaperStyle) -> some View {
        let descriptor = GradientManager.shared.descriptor(for: style)
        if let uiImage = UIImage(named: descriptor.assetName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: descriptor.fallbackColors,
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - AccentColorPickerSheet

struct AccentColorPickerSheet: View {
    @ObservedObject var settings: UserSettings
    @Environment(\.presentationMode) var presentationMode

    private let presets: [(name: String, hex: String)] = [
        ("Индиго",    "#5E5CE6"),
        ("Синий",     "#0A84FF"),
        ("Бирюзовый", "#32D74B"),
        ("Зелёный",   "#30D158"),
        ("Оранжевый", "#FF9F0A"),
        ("Красный",   "#FF453A"),
        ("Розовый",   "#FF375F"),
        ("Фиолетовый","#BF5AF2"),
        ("Жёлтый",    "#FFD60A"),
        ("Серый",     "#8E8E93"),
    ]

    @State private var customColor: Color = AppColors.accent
    @State private var showCustomPicker = false

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            ZStack {
                VisionBackdropView()
                VStack(spacing: 24) {
                    // Превью
                    VStack(spacing: 8) {
                        Text(NSLocalizedString("Превью", comment: "accent color picker preview title"))
                            .font(.caption).foregroundColor(AppColors.secondaryText)
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppColors.accent)
                                .frame(width: 48, height: 48)
                                .overlay(Image(systemName: "sparkles")
                                    .foregroundColor(.white).font(.title3))
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("Акцентный цвет", comment: "settings row: accent color"))
                                    .font(.headline).foregroundColor(AppColors.accent)
                                Text(NSLocalizedString("Так выглядят кнопки и выделения", comment: "accent color picker preview subtitle"))
                                    .font(.caption).foregroundColor(AppColors.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .visionGlassCard(cornerRadius: 14, opacity: 0.84, showRing: true)
                    }
                    .padding(.horizontal, 16)

                    // Сетка пресетов
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("Готовые цвета", comment: "accent color picker preset section title"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .textCase(.uppercase)
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 5), spacing: 14) {
                            ForEach(presets, id: \.hex) { preset in
                                Button(action: { selectPreset(preset.hex) }) {
                                    VStack(spacing: 5) {
                                        ZStack {
                                            Circle()
                                                .fill(Color(hex: preset.hex) ?? .blue)
                                                .frame(width: 48, height: 48)
                                            if settings.accentColorHex == preset.hex {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        Text(preset.name)
                                            .font(.system(size: 10))
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Кастомный цвет
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("Свой цвет", comment: "accent color picker custom color section title"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .textCase(.uppercase)
                            .padding(.horizontal, 16)

                        HStack {
                            ColorPicker(NSLocalizedString("Выбрать цвет", comment: "accent color picker choose color"), selection: $customColor)
                                .onChange(of: customColor) { newColor in
                                    if let hex = newColor.toHex() {
                                        settings.accentColorHex = hex
                                        AppColors.updateAccent(hex: hex)
                                    }
                                }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .visionGlassCard(cornerRadius: 12, opacity: 0.84, showRing: true)
                        .padding(.horizontal, 16)
                    }

                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle(NSLocalizedString("Акцентный цвет", comment: "settings row: accent color"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(NSLocalizedString("Готово", comment: "common done action")) {
                presentationMode.wrappedValue.dismiss()
            }.foregroundColor(AppColors.accent))
        }
    }

    private func selectPreset(_ hex: String) {
        HapticManager.shared.selection()
        settings.accentColorHex = hex
        AppColors.updateAccent(hex: hex)
    }
}
// MARK: - AppLanguagePickerSheet

struct AppLanguagePickerSheet: View {
    @ObservedObject var settings: UserSettings
    @Environment(\.presentationMode) var presentationMode

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            List {
                ForEach(AppLanguage.allCases) { language in
                    Button(action: { select(language) }) {
                        HStack {
                            Text(language.displayName)
                                .foregroundColor(AppColors.text)
                            Spacer()
                            if settings.appLanguage == language {
                                Image(systemName: "checkmark")
                                    .foregroundColor(AppColors.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .visionListBackground()
            .navigationTitle(NSLocalizedString("Язык интерфейса", comment: "settings row: app language"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(NSLocalizedString("Готово", comment: "common done action")) {
                presentationMode.wrappedValue.dismiss()
            }.foregroundColor(AppColors.accent))
        }
    }

    private func select(_ language: AppLanguage) {
        settings.appLanguage = language
        settings.saveSettings()
        LocalizationManager.shared.apply(language: language)
        HapticManager.shared.selection()
    }
}
// MARK: - NumberFormatSettingsSheet

struct NumberFormatSettingsSheet: View {
    @ObservedObject var settings: UserSettings
    @Environment(\.presentationMode) var presentationMode

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(NSLocalizedString("Разделитель тысяч", comment: "number format section header: grouping separator"))) {
                    Picker(NSLocalizedString("Стиль", comment: "number format picker label: style"), selection: $settings.numberGroupingStyle) {
                        ForEach(UserSettings.NumberGroupingStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                }

                Section(header: Text(NSLocalizedString("Десятичный разделитель", comment: "number format section header: decimal separator"))) {
                    Picker(NSLocalizedString("Стиль", comment: "number format picker label: style"), selection: $settings.decimalSeparatorStyle) {
                        ForEach(UserSettings.DecimalSeparatorStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                }

                Section(header: Text(NSLocalizedString("Символ валюты", comment: "number format section header: currency symbol"))) {
                    Picker(NSLocalizedString("Позиция", comment: "number format picker label: position"), selection: $settings.currencySymbolPosition) {
                        ForEach(UserSettings.CurrencySymbolPosition.allCases, id: \.self) { position in
                            Text(position.displayName).tag(position)
                        }
                    }

                    Toggle(NSLocalizedString("Пробел между суммой и валютой", comment: "number format toggle: spacing between amount and currency"), isOn: $settings.currencySpacingEnabled)
                        .tint(AppColors.accent)
                }

                Section(header: Text(NSLocalizedString("Пример", comment: "number format section header: preview"))) {
                    Text(settings.numberFormatPreview)
                        .foregroundColor(AppColors.text)
                        .font(.body.monospacedDigit())
                }
            }
            .visionFormBackground()
            .navigationTitle(NSLocalizedString("Формат чисел", comment: "number format sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button(NSLocalizedString("Сохранить", comment: "common save action")) {
                    settings.saveSettings()
                    HapticManager.shared.success()
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(AppColors.accent)
            )
        }
    }
}
// MARK: - GoalReminderSettingsSheet

struct GoalReminderSettingsSheet: View {
    @ObservedObject var settings: UserSettings
    @Environment(\.presentationMode) var presentationMode

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(NSLocalizedString("Напоминания о дедлайне цели", comment: "goal reminder section header"))) {
                    Toggle(NSLocalizedString("Включить", comment: "common enable toggle"), isOn: $settings.goalReminderEnabled)
                        .tint(AppColors.accent)
                    if settings.goalReminderEnabled {
                        Picker(NSLocalizedString("За сколько дней", comment: "goal reminder picker label: days before"), selection: $settings.goalReminderDaysBefore) {
                            Text(NSLocalizedString("За 1 день", comment: "goal reminder option: 1 day")).tag(1)
                            Text(NSLocalizedString("За 3 дня", comment: "goal reminder option: 3 days")).tag(3)
                            Text(NSLocalizedString("За 7 дней", comment: "goal reminder option: 7 days")).tag(7)
                            Text(NSLocalizedString("За 14 дней", comment: "goal reminder option: 14 days")).tag(14)
                            Text(NSLocalizedString("За 30 дней", comment: "goal reminder option: 30 days")).tag(30)
                        }
                    }
                }
                Section(header: Text(NSLocalizedString("Как работает", comment: "goal reminder section header: how it works"))) {
                    Text(NSLocalizedString("AuraShift отправит уведомление, когда до дедлайна выбранной цели останется указанное количество дней. Уведомление придёт один раз.", comment: "goal reminder explanation"))
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .visionFormBackground()
            .navigationTitle(NSLocalizedString("Напоминания о целях", comment: "settings row: goal reminders"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(NSLocalizedString("Сохранить", comment: "common save action")) {
                NotificationManager.shared.rescheduleGoalReminders(settings: settings)
                HapticManager.shared.success()
                presentationMode.wrappedValue.dismiss()
            }.foregroundColor(AppColors.accent))
        }
    }
}
// MARK: - AboutSheet

struct AboutSheet: View {
    @Environment(\.presentationMode) var presentationMode

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            ZStack {
                VisionBackdropView()
                VStack(spacing: 28) {
                    // Лого
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22)
                                .fill(LinearGradient(
                                    colors: [Color(hex:"#6C5CE7") ?? .purple,
                                             Color(hex:"#4834d4") ?? .purple],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 88, height: 88)
                            Image(systemName: "sparkles")
                                .font(.system(size: 38, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        Text(NSLocalizedString("AuraShift", comment: "about app brand title"))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(AppColors.text)
                        Text(String(
                            format: NSLocalizedString("Версия %@ (Build %@)", comment: "about app version and build"),
                            version,
                            build
                        ))
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(.top, 32)

                    Divider().background(AppColors.border)

                    VStack(spacing: 0) {
                        aboutRow(icon: "envelope.fill", color: .blue, title: NSLocalizedString("Написать разработчику", comment: "settings row: contact developer")) {
                            let url = "mailto:support@aurashift.com?subject=AuraShift \(version) — Обратная связь"
                            if let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                               let u = URL(string: encoded) {
                                UIApplication.shared.open(u)
                            }
                        }
                        aboutRow(icon: "star.fill", color: .yellow, title: NSLocalizedString("Оценить в App Store", comment: "about app row: rate in app store")) {
                            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                                SKStoreReviewController.requestReview(in: scene)
                            }
                        }
                        aboutRow(icon: "lock.shield.fill", color: .gray, title: NSLocalizedString("Политика конфиденциальности", comment: "settings row: privacy policy")) {
                            UIApplication.shared.open(URL(string: "https://aurashift.app/privacy")!)
                        }
                        aboutRow(icon: "doc.plaintext.fill", color: .gray, title: NSLocalizedString("Условия использования", comment: "settings row: terms of use")) {
                            UIApplication.shared.open(URL(string: "https://aurashift.app/terms")!)
                        }
                    }
                    .visionGlassCard(cornerRadius: 14, opacity: 0.84, showRing: true)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 0.5))
                    .padding(.horizontal, 16)

                    Spacer()

                    Text(NSLocalizedString("Сделано с ❤️ командой AuraShift", comment: "about app footer"))
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle(NSLocalizedString("О приложении", comment: "settings section title: about app"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(NSLocalizedString("Закрыть", comment: "common close action")) {
                presentationMode.wrappedValue.dismiss()
            }.foregroundColor(AppColors.accent))
        }
    }

    @ViewBuilder
    private func aboutRow(icon: String, color: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(color)
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(title).foregroundColor(AppColors.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
// MARK: - ProUpgradeSheet

struct ProUpgradeSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var proManager = ProManager.shared
    @State private var selectedProductID: String?

    private let features: [(icon: String, color: Color, title: String, desc: String)] = [
        ("brain", Color(hex:"#6C5CE7") ?? .purple,
         NSLocalizedString("Умный AI", comment: "pro upgrade feature title"),
         NSLocalizedString("Random Forest и градиентный бустинг — прогнозы точнее на 25%", comment: "pro upgrade feature description")),
        ("cloud.sun.fill", .blue,
         NSLocalizedString("Погода и праздники", comment: "pro upgrade feature title"),
         NSLocalizedString("Прогнозы с учётом внешних факторов и их влияния на ваш доход", comment: "pro upgrade feature description")),
        ("gauge.medium", .orange,
         NSLocalizedString("AI-ориентиры бюджета", comment: "pro upgrade feature title"),
         NSLocalizedString("ИИ подсказывает лимит по каждой категории для достижения цели в срок", comment: "pro upgrade feature description")),
        ("calendar.badge.plus", .green,
         NSLocalizedString("Планировщик графика", comment: "pro upgrade feature title"),
         NSLocalizedString("Персональный план работы на неделю с максимальным доходом", comment: "pro upgrade feature description")),
        ("tablecells", .teal,
         NSLocalizedString("Экспорт в Excel", comment: "pro upgrade feature title"),
         NSLocalizedString("Красивые отчёты в XLSX с графиками и форматированием", comment: "pro upgrade feature description")),
        ("chart.bar.xaxis", Color(hex:"#6C5CE7") ?? .purple,
         NSLocalizedString("Анализ факторов", comment: "pro upgrade feature title"),
         NSLocalizedString("Что именно влияет на ваш доход и насколько — в виде диаграммы", comment: "pro upgrade feature description")),
    ]

    // STYLE: Основная компоновка экрана: фон, отступы, размеры и визуальная иерархия.
    var body: some View {
        NavigationView {
            ZStack {
                VisionBackdropView()
                ScrollView {
                    VStack(spacing: 24) {
                        // Hero
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [Color(hex:"#6C5CE7") ?? .purple,
                                                 Color(hex:"#a29bfe") ?? .purple],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 80, height: 80)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 34, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            Text(NSLocalizedString("AuraShift Pro", comment: "pro upgrade title"))
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(AppColors.text)
                            Text(NSLocalizedString("Все инструменты для максимального дохода", comment: "pro upgrade subtitle"))
                                .font(.subheadline)
                                .foregroundColor(AppColors.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 24)

                        // Фичи
                        VStack(spacing: 10) {
                            ForEach(features, id: \.title) { f in
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(f.color.opacity(0.15))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: f.icon)
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(f.color)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(AppColors.text)
                                        Text(f.desc)
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(f.color)
                                        .font(.system(size: 18))
                                }
                                .padding(14)
                                .visionGlassCard(cornerRadius: 14, opacity: 0.84, showRing: true)
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(f.color.opacity(0.2), lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(NSLocalizedString("Планы подписки", comment: "pro upgrade plans title"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.secondaryText)
                                .textCase(.uppercase)

                            if proManager.isLoadingProducts {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text(NSLocalizedString("Загружаем предложения App Store…", comment: "pro upgrade loading products"))
                                        .font(.subheadline)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else if proManager.availableProducts.isEmpty {
                                Text(NSLocalizedString("Пока не удалось загрузить тарифы. Можно продолжить и протестировать в Debug режиме.", comment: "pro upgrade products unavailable message"))
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(proManager.availableProducts, id: \.id) { product in
                                    Button {
                                        selectedProductID = product.id
                                        HapticManager.shared.selection()
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(product.displayName)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(AppColors.text)
                                                if !product.description.isEmpty {
                                                    Text(product.description)
                                                        .font(.caption)
                                                        .foregroundColor(AppColors.secondaryText)
                                                        .lineLimit(2)
                                                }
                                            }
                                            Spacer()
                                            Text(product.displayPrice)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(AppColors.accent)
                                            Image(systemName: selectedProductID == product.id ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(selectedProductID == product.id ? AppColors.accent : AppColors.secondaryText.opacity(0.5))
                                        }
                                        .padding(12)
                                        .visionGlassCard(cornerRadius: 12, opacity: 0.84, showRing: true)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    selectedProductID == product.id ? AppColors.accent.opacity(0.45) : AppColors.border,
                                                    lineWidth: 1
                                                )
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        // CTA
                        VStack(spacing: 10) {
                            Button(action: {
                                Task { await activatePro() }
                            }) {
                                Text(ctaTitle)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(LinearGradient(
                                        colors: [Color(hex:"#6C5CE7") ?? .purple,
                                                 Color(hex:"#4834d4") ?? .purple],
                                        startPoint: .leading, endPoint: .trailing))
                                    .cornerRadius(14)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(proManager.isProUser || proManager.isPurchaseInProgress)
                            .opacity((proManager.isProUser || proManager.isPurchaseInProgress) ? 0.6 : 1.0)

                            Button {
                                Task { await restorePurchase() }
                            } label: {
                                Text(NSLocalizedString("Восстановить покупку", comment: "pro upgrade restore purchase"))
                                    .font(.system(size: 13))
                                    .foregroundColor(AppColors.accent)
                            }
                            .buttonStyle(.plain)
                            .disabled(proManager.isPurchaseInProgress)

                            if let message = proManager.storeMessage, !message.isEmpty {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .onAppear {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                            proManager.clearStoreMessage()
                                        }
                                    }
                            }

                            if proManager.isPurchaseInProgress {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.accent))
                                    .frame(maxWidth: .infinity)
                            }

                            #if DEBUG
                            Button {
                                let isCurrentlyProMode = proManager.canUse(.advancedML)
                                if isCurrentlyProMode {
                                    proManager.enableDebugForcedFree()
                                } else {
                                    proManager.unlockProForTesting()
                                }
                                HapticManager.shared.success()
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                Text(
                                    proManager.canUse(.advancedML)
                                    ? NSLocalizedString("Debug: включить Free-режим", comment: "pro debug enable free mode action")
                                    : NSLocalizedString("Debug: активировать Pro", comment: "pro debug unlock action")
                                )
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .buttonStyle(.plain)
                            #endif

                            Text(NSLocalizedString("Оплата через App Store · Отмена в любое время", comment: "pro upgrade billing note"))
                                .font(.caption2)
                                .foregroundColor(AppColors.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Pro-версия", comment: "pro upgrade screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(NSLocalizedString("Закрыть", comment: "common close action")) {
                presentationMode.wrappedValue.dismiss()
            }.foregroundColor(AppColors.accent))
        }
        .onAppear {
            Task {
                await proManager.loadProducts()
                if selectedProductID == nil {
                    selectedProductID = proManager.selectedProduct?.id
                }
            }
        }
    }

    private var selectedProduct: Product? {
        if let id = selectedProductID {
            return proManager.availableProducts.first(where: { $0.id == id })
        }
        return proManager.selectedProduct
    }

    private var ctaTitle: String {
        if proManager.isProUser {
            return NSLocalizedString("Pro уже активирован", comment: "pro upgrade cta active")
        }
        if let product = selectedProduct {
            return String(
                format: NSLocalizedString("Оформить Pro · %@", comment: "pro upgrade cta buy with price"),
                product.displayPrice
            )
        }
        return NSLocalizedString("Активировать Pro", comment: "pro upgrade cta activate")
    }

    private func activatePro() async {
        if proManager.isProUser {
            presentationMode.wrappedValue.dismiss()
            return
        }
        guard let product = selectedProduct else {
            proManager.storeMessage = NSLocalizedString("Тарифы Pro недоступны. Попробуйте позже.", comment: "pro upgrade no products")
            return
        }
        let success = await proManager.purchase(product)
        if success {
            HapticManager.shared.success()
            presentationMode.wrappedValue.dismiss()
        }
    }

    private func restorePurchase() async {
        let restored = await proManager.restorePurchases()
        if restored {
            HapticManager.shared.success()
            presentationMode.wrappedValue.dismiss()
        }
    }
}
// MARK: - Color extension для hex конвертации

extension Color {
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
