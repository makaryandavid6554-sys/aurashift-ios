import Foundation

struct AppNumberFormatter {
    static func number(
        _ value: Double,
        settings: UserSettings,
        minFractionDigits: Int = 0,
        maxFractionDigits: Int = 0
    ) -> String {
        let formatter = configuredFormatter(
            settings: settings,
            minFractionDigits: minFractionDigits,
            maxFractionDigits: maxFractionDigits
        )

        let number = NSNumber(value: value)
        return formatter.string(from: number) ?? "0"
    }

    static func currency(
        _ value: Double,
        settings: UserSettings,
        minFractionDigits: Int = 0,
        maxFractionDigits: Int = 0
    ) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        let base = number(
            absValue,
            settings: settings,
            minFractionDigits: minFractionDigits,
            maxFractionDigits: maxFractionDigits
        )
        let spacer = settings.currencySpacingEnabled ? " " : ""

        switch settings.currencySymbolPosition {
        case .suffix:
            return "\(sign)\(base)\(spacer)\(settings.defaultCurrency)"
        case .prefix:
            return "\(sign)\(settings.defaultCurrency)\(spacer)\(base)"
        }
    }

    private static func configuredFormatter(
        settings: UserSettings,
        minFractionDigits: Int,
        maxFractionDigits: Int
    ) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = settings.appLanguage.locale
        formatter.minimumFractionDigits = minFractionDigits
        formatter.maximumFractionDigits = max(minFractionDigits, maxFractionDigits)

        switch settings.numberGroupingStyle {
        case .space:
            formatter.usesGroupingSeparator = true
            formatter.groupingSeparator = " "
        case .comma:
            formatter.usesGroupingSeparator = true
            formatter.groupingSeparator = ","
        case .dot:
            formatter.usesGroupingSeparator = true
            formatter.groupingSeparator = "."
        case .none:
            formatter.usesGroupingSeparator = false
        }

        switch settings.decimalSeparatorStyle {
        case .comma:
            formatter.decimalSeparator = ","
        case .dot:
            formatter.decimalSeparator = "."
        }

        return formatter
    }
}
