import SwiftUI
import Combine

class UserSettings: ObservableObject {
    @Published var workTypes: [WorkType] = []
    @Published var expenseCategories: [String] = []
    @Published var defaultCurrency = "₽"
    @Published var colorTheme: ColorTheme = .system
    @Published var wallpaperStyle: WallpaperStyle = .gradientZipDefault
    @Published var appLanguage: AppLanguage = .system
    @Published var accentColorHex = AppColors.unifiedAccentHex
    @Published var soundsEnabled = true
    @Published var hapticsEnabled = true
    @Published var anonymousAnalyticsEnabled = false
    @Published var numberGroupingStyle: NumberGroupingStyle = .space
    @Published var decimalSeparatorStyle: DecimalSeparatorStyle = .comma
    @Published var currencySymbolPosition: CurrencySymbolPosition = .suffix
    @Published var currencySpacingEnabled = true
    @Published var goalReminderEnabled = false
    @Published var goalReminderDaysBefore = 7
    @Published var appLockEnabled = false
    @Published var iCloudSyncEnabled = false
    @Published var proExternalFactorsEnabled = false
    @Published var proUseLiveWeather = true
    @Published var proWeatherCity = ""
    @Published var proHolidayRegionCode = HolidayRegion.auto.rawValue
    @Published var proBudgetLimits: [String: Double] = [:]
    @Published var proBudgetWarningsEnabled = true
    @Published var hasCompletedOnboarding = false
    @Published var dailyReminderEnabled = false
    @Published var dailyReminderHour = 22
    @Published var dailyReminderMinute = 0

    enum ColorTheme: String, CaseIterable, Codable {
        case light, dark, system
    }

    enum WallpaperStyle: String, CaseIterable, Codable, Identifiable {
        case gradientZipDefault
        case gradientZipBlue
        case gradientZipBerry
        case gradientZipGraphite
        case gradientZipPastel
        case universal
        case valleyPair
        case alpinePair

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .gradientZipDefault:
                return NSLocalizedString("Градиент Default", comment: "wallpaper name: zip default")
            case .gradientZipBlue:
                return NSLocalizedString("Градиент Blue", comment: "wallpaper name: zip blue")
            case .gradientZipBerry:
                return NSLocalizedString("Градиент Berry", comment: "wallpaper name: zip berry")
            case .gradientZipGraphite:
                return NSLocalizedString("Градиент Graphite", comment: "wallpaper name: zip graphite")
            case .gradientZipPastel:
                return NSLocalizedString("Градиент Pastel", comment: "wallpaper name: zip pastel")
            case .universal:
                return NSLocalizedString("Универсальный", comment: "wallpaper name: universal")
            case .valleyPair:
                return NSLocalizedString("Долина (Light/Dark)", comment: "wallpaper name: valley pair")
            case .alpinePair:
                return NSLocalizedString("Горы (Light/Dark)", comment: "wallpaper name: alpine pair")
            }
        }
    }

    static let wallpaperStyleKey = "wallpaperStyle"

    enum NumberGroupingStyle: String, CaseIterable, Codable {
        case space
        case comma
        case dot
        case none

        var displayName: String {
            switch self {
            case .space: return NSLocalizedString("Пробел (1 234 567)", comment: "number grouping style: space")
            case .comma: return NSLocalizedString("Запятая (1,234,567)", comment: "number grouping style: comma")
            case .dot: return NSLocalizedString("Точка (1.234.567)", comment: "number grouping style: dot")
            case .none: return NSLocalizedString("Без разделителя", comment: "number grouping style: none")
            }
        }
    }

    enum DecimalSeparatorStyle: String, CaseIterable, Codable {
        case comma
        case dot

        var displayName: String {
            switch self {
            case .comma: return NSLocalizedString("Запятая (12,5)", comment: "decimal separator: comma")
            case .dot: return NSLocalizedString("Точка (12.5)", comment: "decimal separator: dot")
            }
        }
    }

    enum CurrencySymbolPosition: String, CaseIterable, Codable {
        case suffix
        case prefix

        var displayName: String {
            switch self {
            case .suffix: return NSLocalizedString("После суммы (1 250 ₽)", comment: "currency position suffix")
            case .prefix: return NSLocalizedString("Перед суммой (₽ 1 250)", comment: "currency position prefix")
            }
        }
    }

    let lightColors: [String] = [
        "#3E6BAA", "#B16E3D", "#2F7D68", "#7454A6", "#1F6B8E",
        "#B04B63", "#5A7C37", "#8B5F8F", "#4E708F", "#9A7A2E"
    ]

    let darkColors: [String] = [
        "#2C4D7D", "#855130", "#245E4E", "#573C7D", "#1E506B",
        "#7D3649", "#455D2D", "#654669", "#3C5771", "#715B24"
    ]
    
    private let legacyLightColors: [String] = [
        "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFE194",
        "#E6B89C", "#B8A9C9", "#FE938C", "#A7C5EB", "#9C89B8"
    ]
    
    private let legacyDarkColors: [String] = [
        "#8B0000", "#00695C", "#0D47A1", "#1B5E20", "#BF360C",
        "#4A148C", "#3E2723", "#B71C1C", "#004D40", "#311B92"
    ]
    
    private let previousPremiumLightColors: [String] = [
        "#5F7597", "#8A7A67", "#5D857A", "#7E6E9A", "#4F6C79",
        "#9A7D68", "#6A7F99", "#6D8A67", "#8D6F75", "#5D6B7D"
    ]
    
    private let previousPremiumDarkColors: [String] = [
        "#3E4D67", "#5A4D3F", "#3D6259", "#4E4267", "#324B56",
        "#664F42", "#465B72", "#4F6248", "#664D54", "#3E4A5C"
    ]
    
    private let previousPremiumV2LightColors: [String] = [
        "#4F6FA8", "#A16B44", "#3F7D72", "#7B5EA5", "#2F6E8A",
        "#B25E70", "#5A7D4F", "#8D6A9E", "#6E7B95", "#9B7D4A"
    ]
    
    private let previousPremiumV2DarkColors: [String] = [
        "#3A527B", "#7A4F33", "#2F5E56", "#5C477D", "#25546A",
        "#834657", "#46633E", "#6A4F78", "#4F5B73", "#7A6138"
    ]
    
    private let defaultExpenseCategories: [String] = [
        "Еда", "Транспорт", "Развлечения", "Жилье", "Другое"
    ]

    init() {
        loadSettings()
    }

    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "workTypes"),
           let decoded = try? JSONDecoder().decode([WorkType].self, from: data) {
            workTypes = decoded
            print("📂 Загружено работ: \(workTypes.count)")
        } else {
            // Настройки по умолчанию – светлые цвета
            workTypes = [
                WorkType(
                    name: "Бар",
                    icon: "wineglass",
                    colorHex: lightColors[0],
                    hasHourlyRate: true,
                    hasTips: true,
                    hourlyRate: 400,
                    startHour: 9, startMinute: 0, endHour: 22, endMinute: 0
                ),
                WorkType(
                    name: "Курьер",
                    icon: "bicycle",
                    colorHex: lightColors[1],
                    hasFloatingRate: true,
                    hasTips: true,
                    startHour: 9, startMinute: 0, endHour: 17, endMinute: 0
                ),
                WorkType(
                    name: "Водитель Автобуса",
                    icon: "bus",
                    colorHex: lightColors[2],
                    hasFixedRate: true,
                    fixedRate: 2000,
                    startHour: 9, startMinute: 0, endHour: 20, endMinute: 0
                )
            ]
        }

        if let themeRaw = UserDefaults.standard.string(forKey: "colorTheme"),
           let theme = ColorTheme(rawValue: themeRaw) {
            colorTheme = theme
        }
        if let wallpaperRaw = UserDefaults.standard.string(forKey: Self.wallpaperStyleKey),
           let style = WallpaperStyle(rawValue: wallpaperRaw) {
            wallpaperStyle = style
        } else {
            wallpaperStyle = .gradientZipDefault
        }
        if let languageRaw = UserDefaults.standard.string(forKey: AppLanguage.userDefaultsKey),
           let language = AppLanguage(rawValue: languageRaw) {
            appLanguage = language
        } else {
            appLanguage = .system
        }
        accentColorHex = AppColors.unifiedAccentHex
        if UserDefaults.standard.object(forKey: "soundsEnabled") != nil {
            soundsEnabled = UserDefaults.standard.bool(forKey: "soundsEnabled")
        }
        if UserDefaults.standard.object(forKey: "hapticsEnabled") != nil {
            hapticsEnabled = UserDefaults.standard.bool(forKey: "hapticsEnabled")
        }
        if UserDefaults.standard.object(forKey: "anonymousAnalyticsEnabled") != nil {
            anonymousAnalyticsEnabled = UserDefaults.standard.bool(forKey: "anonymousAnalyticsEnabled")
        }
        if let rawGrouping = UserDefaults.standard.string(forKey: "numberGroupingStyle"),
           let grouping = NumberGroupingStyle(rawValue: rawGrouping) {
            numberGroupingStyle = grouping
        }
        if let rawDecimal = UserDefaults.standard.string(forKey: "decimalSeparatorStyle"),
           let decimal = DecimalSeparatorStyle(rawValue: rawDecimal) {
            decimalSeparatorStyle = decimal
        }
        if let rawCurrencyPosition = UserDefaults.standard.string(forKey: "currencySymbolPosition"),
           let currencyPosition = CurrencySymbolPosition(rawValue: rawCurrencyPosition) {
            currencySymbolPosition = currencyPosition
        }
        if UserDefaults.standard.object(forKey: "currencySpacingEnabled") != nil {
            currencySpacingEnabled = UserDefaults.standard.bool(forKey: "currencySpacingEnabled")
        }
        if UserDefaults.standard.object(forKey: "goalReminderEnabled") != nil {
            goalReminderEnabled = UserDefaults.standard.bool(forKey: "goalReminderEnabled")
        }
        if UserDefaults.standard.object(forKey: "goalReminderDaysBefore") != nil {
            goalReminderDaysBefore = max(1, UserDefaults.standard.integer(forKey: "goalReminderDaysBefore"))
        }
        if UserDefaults.standard.object(forKey: "appLockEnabled") != nil {
            appLockEnabled = UserDefaults.standard.bool(forKey: "appLockEnabled")
        }
        if UserDefaults.standard.object(forKey: "iCloudSyncEnabled") != nil {
            iCloudSyncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        }
        if UserDefaults.standard.object(forKey: "proExternalFactorsEnabled") != nil {
            proExternalFactorsEnabled = UserDefaults.standard.bool(forKey: "proExternalFactorsEnabled")
        }
        if UserDefaults.standard.object(forKey: "proUseLiveWeather") != nil {
            proUseLiveWeather = UserDefaults.standard.bool(forKey: "proUseLiveWeather")
        }
        if let city = UserDefaults.standard.string(forKey: "proWeatherCity") {
            proWeatherCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let regionCode = UserDefaults.standard.string(forKey: "proHolidayRegionCode"),
           HolidayRegion(rawValue: regionCode) != nil {
            proHolidayRegionCode = regionCode
        } else {
            proHolidayRegionCode = HolidayRegion.auto.rawValue
        }
        if let budgetData = UserDefaults.standard.data(forKey: "proBudgetLimits"),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: budgetData) {
            proBudgetLimits = sanitizeBudgetLimits(decoded)
        } else {
            proBudgetLimits = [:]
        }
        if UserDefaults.standard.object(forKey: "proBudgetWarningsEnabled") != nil {
            proBudgetWarningsEnabled = UserDefaults.standard.bool(forKey: "proBudgetWarningsEnabled")
        }
        
        if UserDefaults.standard.object(forKey: "hasCompletedOnboarding") != nil {
            hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        } else {
            // Не показываем онбординг старым пользователям после обновления.
            let hasStoredWorkTypes = UserDefaults.standard.data(forKey: "workTypes") != nil
            let hasStoredCategories = UserDefaults.standard.data(forKey: "expenseCategories") != nil
            hasCompletedOnboarding = hasStoredWorkTypes || hasStoredCategories
        }
        
        dailyReminderEnabled = UserDefaults.standard.bool(forKey: "dailyReminderEnabled")
        if UserDefaults.standard.object(forKey: "dailyReminderHour") != nil {
            dailyReminderHour = UserDefaults.standard.integer(forKey: "dailyReminderHour")
        }
        if UserDefaults.standard.object(forKey: "dailyReminderMinute") != nil {
            dailyReminderMinute = UserDefaults.standard.integer(forKey: "dailyReminderMinute")
        }
        
        if let categoriesData = UserDefaults.standard.data(forKey: "expenseCategories"),
           let decodedCategories = try? JSONDecoder().decode([String].self, from: categoriesData) {
            expenseCategories = sanitizeExpenseCategories(decodedCategories)
        } else {
            expenseCategories = defaultExpenseCategories
        }
        
        migrateLegacyPaletteIfNeeded()
    }

    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(workTypes) {
            UserDefaults.standard.set(encoded, forKey: "workTypes")
        }
        if let encodedCategories = try? JSONEncoder().encode(expenseCategories) {
            UserDefaults.standard.set(encodedCategories, forKey: "expenseCategories")
        }
        UserDefaults.standard.set(dailyReminderEnabled, forKey: "dailyReminderEnabled")
        UserDefaults.standard.set(dailyReminderHour, forKey: "dailyReminderHour")
        UserDefaults.standard.set(dailyReminderMinute, forKey: "dailyReminderMinute")
        UserDefaults.standard.set(appLanguage.rawValue, forKey: AppLanguage.userDefaultsKey)
        accentColorHex = AppColors.unifiedAccentHex
        UserDefaults.standard.set(accentColorHex, forKey: "accentColorHex")
        UserDefaults.standard.set(soundsEnabled, forKey: "soundsEnabled")
        UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled")
        UserDefaults.standard.set(anonymousAnalyticsEnabled, forKey: "anonymousAnalyticsEnabled")
        UserDefaults.standard.set(numberGroupingStyle.rawValue, forKey: "numberGroupingStyle")
        UserDefaults.standard.set(decimalSeparatorStyle.rawValue, forKey: "decimalSeparatorStyle")
        UserDefaults.standard.set(currencySymbolPosition.rawValue, forKey: "currencySymbolPosition")
        UserDefaults.standard.set(currencySpacingEnabled, forKey: "currencySpacingEnabled")
        UserDefaults.standard.set(goalReminderEnabled, forKey: "goalReminderEnabled")
        UserDefaults.standard.set(goalReminderDaysBefore, forKey: "goalReminderDaysBefore")
        UserDefaults.standard.set(appLockEnabled, forKey: "appLockEnabled")
        UserDefaults.standard.set(iCloudSyncEnabled, forKey: "iCloudSyncEnabled")
        UserDefaults.standard.set(proExternalFactorsEnabled, forKey: "proExternalFactorsEnabled")
        UserDefaults.standard.set(proUseLiveWeather, forKey: "proUseLiveWeather")
        UserDefaults.standard.set(proWeatherCity.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "proWeatherCity")
        UserDefaults.standard.set(proHolidayRegionCode, forKey: "proHolidayRegionCode")
        if let budgetData = try? JSONEncoder().encode(sanitizeBudgetLimits(proBudgetLimits)) {
            UserDefaults.standard.set(budgetData, forKey: "proBudgetLimits")
        }
        UserDefaults.standard.set(proBudgetWarningsEnabled, forKey: "proBudgetWarningsEnabled")
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(colorTheme.rawValue, forKey: "colorTheme")
        UserDefaults.standard.set(wallpaperStyle.rawValue, forKey: Self.wallpaperStyleKey)
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        saveSettings()
    }
    
    var reminderEnabled: Bool {
        get { dailyReminderEnabled }
        set {
            dailyReminderEnabled = newValue
            saveSettings()
        }
    }
    
    var reminderTime: Date {
        get {
            var components = DateComponents()
            components.hour = dailyReminderHour
            components.minute = dailyReminderMinute
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            dailyReminderHour = components.hour ?? 22
            dailyReminderMinute = components.minute ?? 0
            saveSettings()
        }
    }

    func applyTheme(_ theme: ColorTheme) {
        let palette: [String]
        switch theme {
        case .light:
            palette = lightColors
        case .dark:
            palette = darkColors
        case .system:
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            palette = isDark ? darkColors : lightColors
        }
        
        for i in workTypes.indices {
            let colorIndex = i % palette.count
            workTypes[i].colorHex = palette[colorIndex]
        }
        colorTheme = theme
        saveSettings()
    }
    
    private func migrateLegacyPaletteIfNeeded() {
        let pairs =
            Array(zip(legacyLightColors, lightColors)) +
            Array(zip(legacyDarkColors, darkColors)) +
            Array(zip(previousPremiumLightColors, lightColors)) +
            Array(zip(previousPremiumDarkColors, darkColors)) +
            Array(zip(previousPremiumV2LightColors, lightColors)) +
            Array(zip(previousPremiumV2DarkColors, darkColors))
        
        var migrationMap: [String: String] = [:]
        for (oldHex, newHex) in pairs {
            migrationMap[oldHex] = newHex
        }
        
        var didMigrate = false
        for index in workTypes.indices {
            let currentHex = workTypes[index].colorHex
            if let newHex = migrationMap[currentHex], newHex != currentHex {
                workTypes[index].colorHex = newHex
                didMigrate = true
            }
        }
        
        if didMigrate {
            saveSettings()
        }
    }
    
    func normalizedExpenseCategoryName(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return compact
    }
    
    func addExpenseCategory(_ rawValue: String) -> Bool {
        let name = normalizedExpenseCategoryName(rawValue)
        guard !name.isEmpty else { return false }
        guard !expenseCategories.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        expenseCategories.append(name)
        saveSettings()
        return true
    }
    
    func renameExpenseCategory(at index: Int, to rawValue: String) -> Bool {
        guard expenseCategories.indices.contains(index) else { return false }
        let name = normalizedExpenseCategoryName(rawValue)
        guard !name.isEmpty else { return false }
        
        let oldName = expenseCategories[index]
        if oldName.caseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        
        guard !expenseCategories.enumerated().contains(where: { pair in
            pair.offset != index && pair.element.caseInsensitiveCompare(name) == .orderedSame
        }) else { return false }
        
        let oldBudgetKey = budgetCategoryKey(oldName)
        let newBudgetKey = budgetCategoryKey(name)
        if let oldLimit = proBudgetLimits[oldBudgetKey], oldBudgetKey != newBudgetKey {
            proBudgetLimits.removeValue(forKey: oldBudgetKey)
            proBudgetLimits[newBudgetKey] = oldLimit
        }
        expenseCategories[index] = name
        saveSettings()
        return true
    }
    
    func removeExpenseCategories(at offsets: IndexSet) {
        for index in offsets {
            guard expenseCategories.indices.contains(index) else { continue }
            let key = budgetCategoryKey(expenseCategories[index])
            proBudgetLimits.removeValue(forKey: key)
        }
        expenseCategories.remove(atOffsets: offsets)
        expenseCategories = sanitizeExpenseCategories(expenseCategories)
        saveSettings()
    }
    
    func iconForExpenseCategory(_ category: String) -> String {
        let normalized = category.lowercased()
        if normalized.contains("ед") || normalized.contains("food") {
            return "fork.knife"
        }
        if normalized.contains("транспорт") || normalized.contains("метро") ||
            normalized.contains("такси") || normalized.contains("бенз") || normalized.contains("дорог") {
            return "car"
        }
        if normalized.contains("развлеч") || normalized.contains("кино") || normalized.contains("игр") {
            return "tv"
        }
        if normalized.contains("жиль") || normalized.contains("аренд") || normalized.contains("дом") {
            return "house"
        }
        if normalized.contains("здоров") || normalized.contains("апт") || normalized.contains("мед") {
            return "cross.case.fill"
        }
        if normalized.contains("одеж") {
            return "tshirt"
        }
        if normalized.contains("подар") {
            return "gift"
        }
        return "creditcard"
    }
    
    func colorForExpenseCategory(_ category: String) -> Color {
        Color(hex: colorHexForExpenseCategory(category)) ?? (Color(hex: "#6E7B95") ?? .gray)
    }
    
    func colorHexForExpenseCategory(_ category: String) -> String {
        let normalized = category.lowercased()
        if normalized.contains("ед") || normalized.contains("food") { return "#A16B44" }
        if normalized.contains("транспорт") || normalized.contains("метро") ||
            normalized.contains("такси") || normalized.contains("бенз") || normalized.contains("дорог") { return "#4F6FA8" }
        if normalized.contains("развлеч") || normalized.contains("кино") || normalized.contains("игр") { return "#7B5EA5" }
        if normalized.contains("жиль") || normalized.contains("аренд") || normalized.contains("дом") { return "#3F7D72" }
        if normalized.contains("здоров") || normalized.contains("апт") || normalized.contains("мед") { return "#5A7D4F" }
        
        let palette = colorTheme == .dark ? darkColors : lightColors
        guard !palette.isEmpty else { return "#6E7B95" }
        
        var hash = 5381
        for scalar in normalized.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
        }
        let index = (hash & Int.max) % palette.count
        return palette[index]
    }
    
    private func sanitizeExpenseCategories(_ categories: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        
        for category in categories {
            let cleaned = normalizedExpenseCategoryName(category)
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            normalized.append(cleaned)
        }
        
        if normalized.isEmpty {
            return defaultExpenseCategories
        }
        return normalized
    }

    private func sanitizeBudgetLimits(_ limits: [String: Double]) -> [String: Double] {
        var cleaned: [String: Double] = [:]
        for (key, value) in limits {
            let normalizedKey = budgetCategoryKey(key)
            let clamped = max(0, value)
            guard !normalizedKey.isEmpty, clamped > 0 else { continue }
            cleaned[normalizedKey] = clamped
        }
        return cleaned
    }

    private func budgetCategoryKey(_ category: String) -> String {
        normalizedExpenseCategoryName(category).lowercased()
    }

    func budgetLimit(for category: String) -> Double? {
        let key = budgetCategoryKey(category)
        return proBudgetLimits[key]
    }

    func setBudgetLimit(_ value: Double?, for category: String) {
        let key = budgetCategoryKey(category)
        guard !key.isEmpty else { return }
        if let value, value > 0 {
            proBudgetLimits[key] = value
        } else {
            proBudgetLimits.removeValue(forKey: key)
        }
        saveSettings()
    }

    func budgetProgress(spent: Double, category: String) -> Double? {
        guard let limit = budgetLimit(for: category), limit > 0 else { return nil }
        return spent / limit
    }

    func formattedNumber(_ value: Double, minFractionDigits: Int = 0, maxFractionDigits: Int = 0) -> String {
        AppNumberFormatter.number(
            value,
            settings: self,
            minFractionDigits: minFractionDigits,
            maxFractionDigits: maxFractionDigits
        )
    }

    func formattedCurrency(_ value: Double, minFractionDigits: Int = 0, maxFractionDigits: Int = 0) -> String {
        AppNumberFormatter.currency(
            value,
            settings: self,
            minFractionDigits: minFractionDigits,
            maxFractionDigits: maxFractionDigits
        )
    }

    var numberFormatPreview: String {
        let sampleNumber = AppNumberFormatter.number(1234567.89, settings: self, minFractionDigits: 2, maxFractionDigits: 2)
        let sampleCurrency = AppNumberFormatter.currency(1250, settings: self, minFractionDigits: 0, maxFractionDigits: 0)
        return "\(sampleNumber) · \(sampleCurrency)"
    }
}

struct WorkType: Identifiable, Codable {
    let id = UUID()
    var name: String
    var icon: String
    var colorHex: String

    var hasHourlyRate: Bool = false
    var hasFixedRate: Bool = false
    var hasFloatingRate: Bool = false
    var hasTips: Bool = false

    var isActive: Bool = true

    var hourlyRate: Double = 0
    var fixedRate: Double = 0

    var startHour: Int = 9
    var startMinute: Int = 0
    var endHour: Int = 17
    var endMinute: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, name, icon, colorHex, hasHourlyRate, hasFixedRate, hasFloatingRate, hasTips, isActive, hourlyRate, fixedRate, startHour, startMinute, endHour, endMinute
    }

    // Инициализатор с параметрами по умолчанию
    init(name: String, icon: String, colorHex: String,
         hasHourlyRate: Bool = false, hasFixedRate: Bool = false,
         hasFloatingRate: Bool = false, hasTips: Bool = false,
         isActive: Bool = true,
         hourlyRate: Double = 0, fixedRate: Double = 0,
         startHour: Int = 9, startMinute: Int = 0,
         endHour: Int = 17, endMinute: Int = 0) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.hasHourlyRate = hasHourlyRate
        self.hasFixedRate = hasFixedRate
        self.hasFloatingRate = hasFloatingRate
        self.hasTips = hasTips
        self.isActive = isActive
        self.hourlyRate = hourlyRate
        self.fixedRate = fixedRate
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
