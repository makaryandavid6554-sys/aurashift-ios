import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case russian
    case english
    case armenian
    case ukrainian
    case kazakh
    case uzbek

    static let userDefaultsKey = "appLanguage"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Системный"
        case .russian: return "Русский"
        case .english: return "English"
        case .armenian: return "Հայերեն"
        case .ukrainian: return "Українська"
        case .kazakh: return "Қазақша"
        case .uzbek: return "O'zbekcha"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .system: return Locale.autoupdatingCurrent.identifier
        case .russian: return "ru_RU"
        case .english: return "en_US"
        case .armenian: return "hy_AM"
        case .ukrainian: return "uk_UA"
        case .kazakh: return "kk_KZ"
        case .uzbek: return "uz_UZ"
        }
    }

    var localizationCode: String? {
        switch self {
        case .system: return nil
        case .russian: return "ru"
        case .english: return "en"
        case .armenian: return "hy"
        case .ukrainian: return "uk"
        case .kazakh: return "kk"
        case .uzbek: return "uz"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    static func current() -> AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
              let lang = AppLanguage(rawValue: raw) else {
            return .system
        }
        return lang
    }

    static func currentLocale() -> Locale {
        current().locale
    }
}
