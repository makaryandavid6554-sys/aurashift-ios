import SwiftUI
import CoreData
import Combine
import CoreLocation
import UIKit
import os

struct ContentView: View {
    private static let appLockLastBackgroundKey = "appLock.lastBackgroundAt"
    private static let appLockGraceInterval: TimeInterval = 5 * 60

    @State private var selectedTab = 0
    @State private var loadedTabs: Set<Int> = [0]
    @StateObject private var settings = UserSettings()
    @StateObject private var ai = AIEngine()
    @StateObject private var locationManager = DeviceLocationManager.shared
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) var scenePhase
    @State private var showingOnboarding = false
    @State private var isAppUnlocked = true
    @State private var isAuthenticating = false
    @State private var appLockError: String?
    @State private var languageRefreshID = UUID()
    @State private var lastBackgroundAt: Date? = UserDefaults.standard.object(forKey: appLockLastBackgroundKey) as? Date
    @State private var pendingAIAnalysisWorkItem: DispatchWorkItem?
    @State private var didHandleInitialActivePhase = false
    @State private var lastActiveMaintenanceAt: Date?
    
    @State private var debouncedEventCancellable: AnyCancellable?
    @State private var eventTrigger = PassthroughSubject<Void, Never>()
    // Temporary switch: keep onboarding implementation in code, but do not present it for now.
    private let isOnboardingEnabled = false

    // FetchRequests для AIEngine на уровне ContentView
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Income.date, ascending: true)])
    private var incomes: FetchedResults<Income>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Expense.date, ascending: true)])
    private var expenses: FetchedResults<Expense>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \FinancialGoal.deadline, ascending: true)])
    private var goals: FetchedResults<FinancialGoal>

    init() {
        Self.configureGlobalAppearance()
    }

    private static func configureGlobalAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0)
                : UIColor.white
        }

        // STYLE: Цвет и размер неактивных иконок/подписей табов.
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(AppColors.secondaryText)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(AppColors.secondaryText),
            .font: UIFont.systemFont(ofSize: 11, weight: .medium)
        ]

        // STYLE: Цвет и вес шрифта активного таба.
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(AppColors.accent)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(AppColors.accent),
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
        ]

        appearance.shadowColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.14)
                : UIColor.black.withAlphaComponent(0.12)
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = UIColor(AppColors.secondaryText)

        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(AppColors.accent).withAlphaComponent(0.20)
        segmented.backgroundColor = UIColor(AppColors.surface)
        segmented.setTitleTextAttributes(
            [
                .foregroundColor: UIColor(AppColors.secondaryText).withAlphaComponent(0.95),
                .font: UIFont.systemFont(ofSize: 14, weight: .medium)
            ],
            for: .normal
        )
        segmented.setTitleTextAttributes(
            [
                .foregroundColor: UIColor(AppColors.text),
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
            ],
            for: .selected
        )

        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.backgroundEffect = nil
        nav.backgroundColor = UIColor(AppColors.background)
        nav.titleTextAttributes = [
            .foregroundColor: UIColor(AppColors.text),
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor(AppColors.text),
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(AppColors.accent)

        let table = UITableView.appearance()
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.sectionHeaderTopPadding = 0

        let cell = UITableViewCell.appearance()
        cell.backgroundColor = .clear
        cell.selectionStyle = .none

        let headerFooter = UITableViewHeaderFooterView.appearance()
        headerFooter.tintColor = .clear

        UICollectionView.appearance().backgroundColor = .clear
        UITextView.appearance().backgroundColor = .clear
    }

    private var shouldShowAppLock: Bool {
        settings.appLockEnabled &&
        settings.hasCompletedOnboarding &&
        !showingOnboarding &&
        !isAppUnlocked
    }

    private var preferredScheme: ColorScheme? {
        switch settings.colorTheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    var body: some View {
        ZStack {
            // STYLE: Глобальный фон приложения виден сквозь все glass-слои.
            VisionBackdropView()

            TabView(selection: $selectedTab) {
                // 0 - Сегодня
                tabHost(index: 0) {
                    DailyView(settings: settings)
                }
                    .tabItem {
                        Label(NSLocalizedString("Сегодня", comment: "tab title: today"), systemImage: "square.and.pencil")
                    }
                    .tag(0)

                // 1 - Статистика
                tabHost(index: 1) {
                    StatisticsView(settings: settings)
                }
                    .tabItem {
                        Label(NSLocalizedString("Статистика", comment: "tab title: statistics"), systemImage: "chart.bar.fill")
                    }
                    .tag(1)

                // 2 - Аврора
                tabHost(index: 2) {
                    AuroraView(settings: settings)
                }
                    .tabItem {
                        Label(NSLocalizedString("Аврора", comment: "tab title: aurora"), systemImage: "sparkles")
                    }
                    .tag(2)

                // 3 - Цели
                tabHost(index: 3) {
                    GoalsView(settings: settings)
                }
                    .tabItem {
                        Label(NSLocalizedString("Цели", comment: "tab title: goals"), systemImage: "target")
                    }
                    .tag(3)

                // 4 - Еще
                tabHost(index: 4) {
                    MoreHubView(settings: settings)
                }
                    .tabItem {
                        Label(NSLocalizedString("Еще", comment: "tab title: more"), systemImage: "ellipsis")
                    }
                    .tag(4)
            }

            if shouldShowAppLock {
                AppLockView(
                    authTypeTitle: BiometricManager.shared.authType().localizedTitle,
                    isAuthenticating: isAuthenticating,
                    errorText: appLockError,
                    onUnlock: authenticateApp
                )
                .zIndex(10)
                .transition(.opacity)
            }
        }
        .id(languageRefreshID)
        .environmentObject(ai)
        .onAppear {
            // Boot log for AI background training channel visibility
            do {
                let bootLogger = Logger(subsystem: "D-D.AuraShift", category: "AIBackgroundTraining")
                bootLogger.info("App boot — AIBackgroundTraining channel is alive")
            }
            UIApplication.shared.isIdleTimerDisabled = false
            if isOnboardingEnabled && !settings.hasCompletedOnboarding {
                showingOnboarding = true
            }
            AnalyticsManager.shared.setEnabled(settings.anonymousAnalyticsEnabled)
            AnalyticsManager.shared.track("app_open")
            // One-time data migration: copy Income.notes -> Income.note if needed
            DataMigration.migrateIncomeNotesIfNeeded(context: viewContext)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                runActiveMaintenance(force: true)
            }
            AIBackgroundTrainingManager.shared.scheduleNightTraining()
            refreshDeviceLocationIfNeeded(promptIfNeeded: true)
            // Proactively refresh weather on launch if possible
            refreshWeatherIfPossible(promptIfNeeded: false)
            scheduleAIAnalysis(delay: 1.2)
            if settings.appLockEnabled && settings.hasCompletedOnboarding {
                enforceLockAndRequestAuth(force: true)
            }
            
            debouncedEventCancellable = eventTrigger
                .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
                .sink { [weak ai = ai, weak settings = settings] _ in
                    // Re-run AI analysis and optionally refresh weather if needed
                    triggerAIAnalysis()
                }
        }
        .onChange(of: selectedTab) { _, tab in
            loadedTabs.insert(tab)
        }
        .onChange(of: scenePhase) { _, newPhase in
            UIApplication.shared.isIdleTimerDisabled = false
            if newPhase == .active {
                runActiveMaintenance()
                if didHandleInitialActivePhase {
                    eventTrigger.send()
                } else {
                    didHandleInitialActivePhase = true
                }
                if settings.appLockEnabled {
                    // Ensure weather refresh on app becoming active
                    refreshWeatherIfPossible(promptIfNeeded: false)
                    enforceLockAndRequestAuth()
                }
            }
            if newPhase == .background {
                pendingAIAnalysisWorkItem?.cancel()
                AIBackgroundTrainingManager.shared.scheduleNightTraining()
                if settings.appLockEnabled {
                    let now = Date()
                    lastBackgroundAt = now
                    UserDefaults.standard.set(now, forKey: Self.appLockLastBackgroundKey)
                }
                PersistenceController.shared.save()
                settings.saveSettings()
                print("💾 Приложение сворачивается - сохранено")
            }
        }
        .onReceive(sessionManager.$plannedShifts.dropFirst()) { _ in
            eventTrigger.send()
        }
        .onReceive(settings.$workTypes.dropFirst()) { _ in
            eventTrigger.send()
        }
        .onReceive(settings.$proUseLiveWeather.dropFirst()) { enabled in
            if enabled {
                refreshDeviceLocationIfNeeded(promptIfNeeded: true)
            }
            eventTrigger.send()
        }
        .onReceive(settings.$proWeatherCity.dropFirst()) { _ in
            let manualCity = settings.proWeatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
            if ProManager.shared.canUse(.externalFactors), !manualCity.isEmpty {
                WeatherManager.shared.refreshForecast(for: manualCity)
            }
            eventTrigger.send()
        }
        .onReceive(settings.$proHolidayRegionCode.dropFirst()) { _ in
            eventTrigger.send()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)) { notification in
            guard shouldRefreshAI(for: notification) else { return }
            eventTrigger.send()
        }
        .onReceive(NotificationCenter.default.publisher(for: .weatherManagerDidUpdateForecast)) { _ in
            guard ProManager.shared.canUse(.externalFactors) else { return }
            eventTrigger.send()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceLocationManagerDidUpdate)) { _ in
            let city = locationManager.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !city.isEmpty, city != settings.proWeatherCity {
                settings.proWeatherCity = city
                settings.saveSettings()
                // Trigger weather refresh when city updated from location
                if ProManager.shared.canUse(.externalFactors) {
                    WeatherManager.shared.refreshForecast(for: city)
                }
            }
            if let coord = locationManager.coordinate, ProManager.shared.canUse(.externalFactors) {
                WeatherManager.shared.refreshForecast(latitude: coord.latitude, longitude: coord.longitude)
            }
            guard ProManager.shared.canUse(.externalFactors) else { return }
            eventTrigger.send()
        }
        .onChange(of: settings.appLockEnabled) { _, enabled in
            if enabled {
                enforceLockAndRequestAuth(force: true)
            } else {
                isAppUnlocked = true
                isAuthenticating = false
                appLockError = nil
                lastBackgroundAt = nil
                UserDefaults.standard.removeObject(forKey: Self.appLockLastBackgroundKey)
            }
        }
        .onChange(of: settings.iCloudSyncEnabled) { _, enabled in
            ICloudSyncManager.shared.refresh(isEnabled: enabled)
        }
        .onChange(of: settings.appLanguage) { _, language in
            LocalizationManager.shared.apply(language: language)
            languageRefreshID = UUID()
        }
        .onChange(of: settings.anonymousAnalyticsEnabled) { _, enabled in
            AnalyticsManager.shared.setEnabled(enabled)
        }
        .preferredColorScheme(preferredScheme)
        .environment(\.locale, settings.appLanguage.locale)
        .fontDesign(.rounded)
        .transaction { transaction in
            if UIRuntimeConfig.reduceAnimations {
                transaction.animation = nil
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView { targetTab in
                settings.completeOnboarding()
                showingOnboarding = false
                selectedTab = targetTab ?? 0
                if settings.appLockEnabled {
                    enforceLockAndRequestAuth(force: true)
                }
            }
        }
    }

    private func triggerAIAnalysis() {
        ai.analyze(
            incomes: Array(incomes),
            expenses: Array(expenses),
            settings: settings,
            goals: Array(goals),
            plannedShifts: sessionManager.plannedShifts
        )
    }

    private func scheduleAIAnalysis(delay: TimeInterval = 0.2) {
        pendingAIAnalysisWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            triggerAIAnalysis()
        }
        pendingAIAnalysisWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func refreshDeviceLocationIfNeeded(promptIfNeeded: Bool) {
        guard settings.proUseLiveWeather else { return }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            if promptIfNeeded {
                locationManager.requestWhenInUseAuthorization()
            }
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.refreshLocation()
            print("🌤️ Requested location refresh for live weather")
        case .restricted, .denied:
            // Fall back to manual city if available
            let manualCity = settings.proWeatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
            if ProManager.shared.canUse(.externalFactors), !manualCity.isEmpty {
                WeatherManager.shared.refreshForecast(for: manualCity)
            }
        @unknown default:
            break
        }
    }
    
    private func refreshWeatherIfPossible(promptIfNeeded: Bool) {
        guard ProManager.shared.canUse(.externalFactors) else { return }
        if settings.proUseLiveWeather {
            if let coord = locationManager.coordinate {
                WeatherManager.shared.refreshForecast(latitude: coord.latitude, longitude: coord.longitude)
            } else {
                let city = locationManager.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !city.isEmpty {
                    WeatherManager.shared.refreshForecast(for: city)
                } else {
                    refreshDeviceLocationIfNeeded(promptIfNeeded: promptIfNeeded)
                }
            }
        } else {
            let manualCity = settings.proWeatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
            if !manualCity.isEmpty {
                WeatherManager.shared.refreshForecast(for: manualCity)
            }
        }
    }

    @ViewBuilder
    private func tabHost<Content: View>(index: Int, @ViewBuilder content: () -> Content) -> some View {
        if loadedTabs.contains(index) {
            content()
        } else {
            Color.clear
        }
    }

    private func runActiveMaintenance(force: Bool = false) {
        let now = Date()
        if !force,
           let last = lastActiveMaintenanceAt,
           now.timeIntervalSince(last) < 15 {
            return
        }
        lastActiveMaintenanceAt = now
        if force || settings.dailyReminderEnabled {
            NotificationManager.shared.syncReminder(with: settings)
        }
        if force || settings.iCloudSyncEnabled {
            ICloudSyncManager.shared.refresh(isEnabled: settings.iCloudSyncEnabled)
        }
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

    private func enforceLockAndRequestAuth(force: Bool = false) {
        guard settings.appLockEnabled,
              settings.hasCompletedOnboarding,
              !showingOnboarding else {
            isAppUnlocked = true
            return
        }
        guard force || shouldRequireReauthentication else {
            isAppUnlocked = true
            return
        }
        isAppUnlocked = false
        authenticateApp()
    }

    private var shouldRequireReauthentication: Bool {
        guard let lastBackgroundAt else { return true }
        let elapsed = Date().timeIntervalSince(lastBackgroundAt)
        return elapsed >= Self.appLockGraceInterval
    }

    private func authenticateApp() {
        guard settings.appLockEnabled else {
            isAppUnlocked = true
            return
        }
        guard !isAuthenticating else { return }

        isAuthenticating = true
        appLockError = nil
        BiometricManager.shared.authenticate { success, errorText in
            isAuthenticating = false
            if success {
                isAppUnlocked = true
                appLockError = nil
                let now = Date()
                lastBackgroundAt = now
                UserDefaults.standard.set(now, forKey: Self.appLockLastBackgroundKey)
            } else {
                isAppUnlocked = false
                appLockError = errorText ?? NSLocalizedString("Не удалось пройти проверку", comment: "app lock fallback error")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .environmentObject(SessionManager(context: PersistenceController.shared.container.viewContext))
    }
}
