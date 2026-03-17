import Foundation

enum HolidayRegion: String, CaseIterable, Identifiable {
    case auto
    case ru
    case am
    case us
    case ua
    case kz
    case uz

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return NSLocalizedString("Авто (по региону устройства)", comment: "holiday region: auto")
        case .ru: return NSLocalizedString("Россия", comment: "holiday region: russia")
        case .am: return NSLocalizedString("Армения", comment: "holiday region: armenia")
        case .us: return NSLocalizedString("United States", comment: "holiday region: united states")
        case .ua: return NSLocalizedString("Украина", comment: "holiday region: ukraine")
        case .kz: return NSLocalizedString("Казахстан", comment: "holiday region: kazakhstan")
        case .uz: return NSLocalizedString("Узбекистан", comment: "holiday region: uzbekistan")
        }
    }

    private static func fromCountryCode(_ value: String) -> HolidayRegion? {
        switch value.uppercased() {
        case "RU": return .ru
        case "AM": return .am
        case "US": return .us
        case "UA": return .ua
        case "KZ": return .kz
        case "UZ": return .uz
        default: return nil
        }
    }

    static func resolved(from code: String) -> HolidayRegion {
        if let explicit = HolidayRegion(rawValue: code), explicit != .auto {
            return explicit
        }
        let candidates: [String?] = [
            DeviceLocationManager.shared.countryCode,
            Locale.autoupdatingCurrent.region?.identifier,
            AppLanguage.current().locale.region?.identifier,
            Locale.current.region?.identifier
        ]
        for candidate in candidates {
            guard let normalized = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !normalized.isEmpty else { continue }
            if let mapped = fromCountryCode(normalized) {
                return mapped
            }
        }
        return .ru
    }
}

final class HolidayManager {
    static let shared = HolidayManager()

    struct HolidayImpactInfo {
        let percent: Double
        let title: String
        let isPublicHoliday: Bool
    }

    private struct PendingEvent {
        let keys: Set<String>
        let title: String
        let isPublicHoliday: Bool
    }

    private struct StoredImpact {
        var percent: Double
        var title: String
        var isPublicHoliday: Bool
    }

    private struct ParsedHolidayCalendar {
        var publicDays: [HolidayRegion: [Int: Set<String>]]
        var impacts: [HolidayRegion: [Int: [String: StoredImpact]]]
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private let dateRangeRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})\.(\d{1,2})\s*[–—-]\s*(\d{1,2})\.(\d{1,2})(?!\d)"#
    )
    private let monthWordRangeRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})\s*[–—-]\s*(\d{1,2})\s*(янв(?:аря)?|фев(?:раля)?|мар(?:та)?|апр(?:еля)?|ма[йя]|июн(?:я)?|июл(?:я)?|авг(?:уста)?|сен(?:т(?:ября)?)?|окт(?:ября)?|ноя(?:бря)?|дек(?:абря)?)\b"#,
        options: .caseInsensitive
    )
    private let monthWordSingleRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})\s*(янв(?:аря)?|фев(?:раля)?|мар(?:та)?|апр(?:еля)?|ма[йя]|июн(?:я)?|июл(?:я)?|авг(?:уста)?|сен(?:т(?:ября)?)?|окт(?:ября)?|ноя(?:бря)?|дек(?:абря)?)\b"#,
        options: .caseInsensitive
    )
    private let singleDateRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})\.(\d{1,2})(?!\d)"#
    )
    private let signedPercentRegex = try! NSRegularExpression(
        pattern: #"([+-]?\d{1,3})\s*%"#
    )
    private let stripYearFromTitleRegex = try! NSRegularExpression(
        pattern: #"\(\s*20\d{2}\s*\)"#
    )

    // On-device fallback holiday map (fixed dates only).
    private let fixedPublicHolidaysByRegion: [HolidayRegion: Set<String>] = [
        .ru: [
            "01-01", "01-02", "01-03", "01-04", "01-05", "01-06", "01-07", "01-08",
            "02-23", "03-08", "05-01", "05-09", "06-12", "11-04"
        ],
        .am: [
            "01-01", "01-02", "01-06", "01-28", "03-08", "04-24",
            "05-01", "05-09", "09-21", "12-31"
        ],
        .us: [
            "01-01", "07-04", "11-11", "12-25"
        ],
        .ua: [
            "01-01", "03-08", "05-01", "06-28", "08-24", "12-25"
        ],
        .kz: [
            "01-01", "01-02", "03-08", "03-21", "03-22", "03-23",
            "05-01", "05-07", "05-09", "07-06", "12-16"
        ],
        .uz: [
            "01-01", "03-08", "03-21", "05-09", "09-01", "10-01", "12-08"
        ]
    ]

    private lazy var parsedHolidayCalendar: ParsedHolidayCalendar = {
        loadHolidayMapFromBundle()
    }()

    private init() {}

    func isPublicHoliday(_ date: Date, regionCode: String = HolidayRegion.auto.rawValue) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return false }
        let key = String(format: "%02d-%02d", month, day)
        let region = HolidayRegion.resolved(from: regionCode)

        if let yearMatches = parsedHolidayCalendar.publicDays[region]?[year], yearMatches.contains(key) {
            return true
        }

        // If the exact year is not available (or the region block was empty), reuse nearest known year.
        if let nearest = nearestKnownHolidaySet(for: region, year: year), nearest.contains(key) {
            return true
        }

        let regionHolidays = fixedPublicHolidaysByRegion[region] ?? fixedPublicHolidaysByRegion[.ru] ?? []
        return regionHolidays.contains(key)
    }

    func impactPercent(for date: Date, regionCode: String = HolidayRegion.auto.rawValue) -> Double {
        impactInfo(for: date, regionCode: regionCode)?.percent ?? 0
    }

    func impactInfo(for date: Date, regionCode: String = HolidayRegion.auto.rawValue) -> HolidayImpactInfo? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        let key = String(format: "%02d-%02d", month, day)
        let region = HolidayRegion.resolved(from: regionCode)

        if let byYear = parsedHolidayCalendar.impacts[region]?[year],
           let impact = byYear[key] {
            return HolidayImpactInfo(
                percent: impact.percent,
                title: impact.title,
                isPublicHoliday: impact.isPublicHoliday
            )
        }

        if let nearest = nearestKnownImpactMap(for: region, year: year),
           let impact = nearest[key] {
            return HolidayImpactInfo(
                percent: impact.percent,
                title: impact.title,
                isPublicHoliday: impact.isPublicHoliday
            )
        }

        if isPublicHoliday(date, regionCode: regionCode) {
            return HolidayImpactInfo(
                percent: 0,
                title: NSLocalizedString("Государственный праздник", comment: "holiday impact fallback title"),
                isPublicHoliday: true
            )
        }
        return nil
    }

    func nextSignificantImpact(
        from date: Date = Date(),
        withinDays: Int = 21,
        regionCode: String = HolidayRegion.auto.rawValue,
        minimumAbsPercent: Double = 0.08
    ) -> (date: Date, info: HolidayImpactInfo)? {
        let horizon = max(0, withinDays)
        let start = calendar.startOfDay(for: date)
        for offset in 0...horizon {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let info = impactInfo(for: day, regionCode: regionCode),
                  abs(info.percent) >= minimumAbsPercent else { continue }
            return (day, info)
        }
        return nil
    }

    func isWeekend(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    private func nearestKnownHolidaySet(for region: HolidayRegion, year: Int) -> Set<String>? {
        guard let yearMap = parsedHolidayCalendar.publicDays[region], !yearMap.isEmpty else { return nil }
        let sorted = yearMap.keys.sorted()
        if let exact = yearMap[year], !exact.isEmpty {
            return exact
        }
        if let lower = sorted.last(where: { $0 < year }),
           let set = yearMap[lower], !set.isEmpty {
            return set
        }
        if let upper = sorted.first(where: { $0 > year }),
           let set = yearMap[upper], !set.isEmpty {
            return set
        }
        return nil
    }

    private func nearestKnownImpactMap(for region: HolidayRegion, year: Int) -> [String: StoredImpact]? {
        guard let yearMap = parsedHolidayCalendar.impacts[region], !yearMap.isEmpty else { return nil }
        let sorted = yearMap.keys.sorted()
        if let exact = yearMap[year], !exact.isEmpty {
            return exact
        }
        if let lower = sorted.last(where: { $0 < year }),
           let map = yearMap[lower], !map.isEmpty {
            return map
        }
        if let upper = sorted.first(where: { $0 > year }),
           let map = yearMap[upper], !map.isEmpty {
            return map
        }
        return nil
    }

    private func loadHolidayMapFromBundle() -> ParsedHolidayCalendar {
        guard let url = Bundle.main.url(forResource: "holidays_2026-2028", withExtension: "txt"),
              let rawText = try? String(contentsOf: url, encoding: .utf8) else {
            return ParsedHolidayCalendar(publicDays: [:], impacts: [:])
        }

        var publicDays: [HolidayRegion: [Int: Set<String>]] = [:]
        var impacts: [HolidayRegion: [Int: [String: StoredImpact]]] = [:]
        var currentRegion: HolidayRegion?
        var currentYear: Int?
        var pendingEvents: [PendingEvent] = []

        for rawLine in rawText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                pendingEvents = []
                continue
            }

            if let region = detectRegion(in: line) {
                currentRegion = region
                currentYear = nil
                pendingEvents = []
                continue
            }

            if let year = extractYear(from: line) {
                currentYear = year
                if let region = currentRegion {
                    publicDays[region, default: [:]][year, default: []] = publicDays[region]?[year] ?? []
                    impacts[region, default: [:]][year, default: [:]] = impacts[region]?[year] ?? [:]
                }
                pendingEvents = []
                continue
            }

            guard let region = currentRegion, let year = currentYear else { continue }
            if let percent = extractImpactPercent(from: line), !pendingEvents.isEmpty {
                applyImpact(
                    percent: percent,
                    to: pendingEvents,
                    region: region,
                    year: year,
                    publicDays: &publicDays,
                    impacts: &impacts
                )
                pendingEvents = []
                continue
            }

            let keys = extractDateKeys(from: line, year: year)
            guard !keys.isEmpty else { continue }

            let title = extractEventTitle(from: line)
            let isPublicHoliday = isLikelyPublicHoliday(line: line, title: title)
            pendingEvents = [PendingEvent(keys: keys, title: title, isPublicHoliday: isPublicHoliday)]

            if isPublicHoliday {
                publicDays[region, default: [:]][year, default: []].formUnion(keys)
            }
            // Keep title even when no explicit percentage is provided.
            applyImpact(
                percent: 0,
                to: pendingEvents,
                region: region,
                year: year,
                publicDays: &publicDays,
                impacts: &impacts
            )
        }

        propagateEmptyYears(&publicDays)
        propagateEmptyImpactYears(&impacts)
        return ParsedHolidayCalendar(publicDays: publicDays, impacts: impacts)
    }

    private func applyImpact(
        percent: Double,
        to events: [PendingEvent],
        region: HolidayRegion,
        year: Int,
        publicDays: inout [HolidayRegion: [Int: Set<String>]],
        impacts: inout [HolidayRegion: [Int: [String: StoredImpact]]]
    ) {
        guard !events.isEmpty else { return }
        for event in events {
            if event.isPublicHoliday {
                publicDays[region, default: [:]][year, default: []].formUnion(event.keys)
            }
            for key in event.keys {
                var current = impacts[region, default: [:]][year, default: [:]][key] ?? StoredImpact(
                    percent: 0,
                    title: event.title,
                    isPublicHoliday: event.isPublicHoliday
                )
                let updatedPercent = clampedImpact(current.percent + percent)
                let incomingAbs = abs(percent)
                let currentAbs = abs(current.percent)
                if incomingAbs >= currentAbs || current.title.isEmpty {
                    current.title = event.title
                }
                current.percent = updatedPercent
                current.isPublicHoliday = current.isPublicHoliday || event.isPublicHoliday
                impacts[region, default: [:]][year, default: [:]][key] = current
            }
        }
    }

    private func clampedImpact(_ value: Double) -> Double {
        min(max(value, -0.8), 0.8)
    }

    private func propagateEmptyYears(_ map: inout [HolidayRegion: [Int: Set<String>]]) {
        for region in map.keys {
            guard var regionMap = map[region], !regionMap.isEmpty else { continue }
            let years = regionMap.keys.sorted()
            var previous: Set<String>?

            for year in years {
                let current = regionMap[year] ?? []
                if current.isEmpty, let previous {
                    regionMap[year] = previous
                } else if !current.isEmpty {
                    previous = current
                }
            }

            var next: Set<String>?
            for year in years.reversed() {
                let current = regionMap[year] ?? []
                if current.isEmpty, let next {
                    regionMap[year] = next
                } else if !current.isEmpty {
                    next = current
                }
            }

            map[region] = regionMap
        }
    }

    private func propagateEmptyImpactYears(_ map: inout [HolidayRegion: [Int: [String: StoredImpact]]]) {
        for region in map.keys {
            guard var regionMap = map[region], !regionMap.isEmpty else { continue }
            let years = regionMap.keys.sorted()
            var previous: [String: StoredImpact]?

            for year in years {
                let current = regionMap[year] ?? [:]
                if current.isEmpty, let previous {
                    regionMap[year] = previous
                } else if !current.isEmpty {
                    previous = current
                }
            }

            var next: [String: StoredImpact]?
            for year in years.reversed() {
                let current = regionMap[year] ?? [:]
                if current.isEmpty, let next {
                    regionMap[year] = next
                } else if !current.isEmpty {
                    next = current
                }
            }

            map[region] = regionMap
        }
    }

    private func detectRegion(in line: String) -> HolidayRegion? {
        let upper = line.uppercased()
        if upper.contains("РОССИЯ") { return .ru }
        if upper.contains("АРМЕНИЯ") { return .am }
        if upper.contains("КАЗАХСТАН") { return .kz }
        if upper.contains("УЗБЕКИСТАН") { return .uz }
        if upper.contains("УКРАИНА") { return .ua }
        if upper.contains("UNITED STATES") || upper.contains("США") { return .us }
        return nil
    }

    private func extractYear(from line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let digits = line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard digits.count >= 4 else { return nil }
        return Int(String(digits.prefix(4)))
    }

    private func extractImpactPercent(from line: String) -> Double? {
        let lower = line.lowercased()
        guard lower.contains("%") else { return nil }
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = signedPercentRegex.firstMatch(in: line, options: [], range: fullRange) else {
            return nil
        }
        let rawNumber = nsLine.substring(with: match.range(at: 1))
        guard let value = Int(rawNumber) else { return nil }

        if rawNumber.hasPrefix("+") || rawNumber.hasPrefix("-") {
            return Double(value) / 100.0
        }

        if lower.contains("снижен") || lower.contains("падени") {
            return -abs(Double(value) / 100.0)
        }
        if lower.contains("увелич") || lower.contains("рост") {
            return abs(Double(value) / 100.0)
        }
        return Double(value) / 100.0
    }

    private func extractEventTitle(from line: String) -> String {
        let separators = [" – ", " — "]
        for separator in separators {
            if let range = line.range(of: separator) {
                let title = String(line[range.upperBound...])
                return normalizeTitle(title)
            }
        }

        if let colon = line.range(of: ":") {
            let left = String(line[..<colon.lowerBound])
            return normalizeTitle(left)
        }
        return normalizeTitle(line)
    }

    private func normalizeTitle(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "•", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let nsValue = value as NSString
        let fullRange = NSRange(location: 0, length: nsValue.length)
        value = stripYearFromTitleRegex.stringByReplacingMatches(
            in: value,
            options: [],
            range: fullRange,
            withTemplate: ""
        )
        value = value.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return NSLocalizedString("Событие", comment: "holiday event fallback title")
        }
        return value
    }

    private func isLikelyPublicHoliday(line: String, title: String) -> Bool {
        let lower = "\(line) \(title)".lowercased()
        if lower.contains("пост") || lower.contains("рамадан") || lower.contains("снижение спроса") {
            return false
        }
        return true
    }

    private func extractDateKeys(from line: String, year: Int) -> Set<String> {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        var keys = Set<String>()

        dateRangeRegex.enumerateMatches(in: line, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            let d1 = Int(nsLine.substring(with: match.range(at: 1))) ?? 0
            let m1 = Int(nsLine.substring(with: match.range(at: 2))) ?? 0
            let d2 = Int(nsLine.substring(with: match.range(at: 3))) ?? 0
            let m2 = Int(nsLine.substring(with: match.range(at: 4))) ?? 0
            keys.formUnion(expandRange(year: year, startDay: d1, startMonth: m1, endDay: d2, endMonth: m2))
        }

        monthWordRangeRegex.enumerateMatches(in: line, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            let dayFrom = Int(nsLine.substring(with: match.range(at: 1))) ?? 0
            let dayTo = Int(nsLine.substring(with: match.range(at: 2))) ?? 0
            let monthText = nsLine.substring(with: match.range(at: 3))
            guard let month = monthNumber(from: monthText) else { return }
            keys.formUnion(expandRange(year: year, startDay: dayFrom, startMonth: month, endDay: dayTo, endMonth: month))
        }

        monthWordSingleRegex.enumerateMatches(in: line, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            let day = Int(nsLine.substring(with: match.range(at: 1))) ?? 0
            let monthText = nsLine.substring(with: match.range(at: 2))
            guard let month = monthNumber(from: monthText), isValid(day: day, month: month, year: year) else { return }
            keys.insert(makeKey(month: month, day: day))
        }

        singleDateRegex.enumerateMatches(in: line, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            let day = Int(nsLine.substring(with: match.range(at: 1))) ?? 0
            let month = Int(nsLine.substring(with: match.range(at: 2))) ?? 0
            guard isValid(day: day, month: month, year: year) else { return }
            keys.insert(makeKey(month: month, day: day))
        }

        return keys
    }

    private func expandRange(year: Int, startDay: Int, startMonth: Int, endDay: Int, endMonth: Int) -> Set<String> {
        guard isValid(day: startDay, month: startMonth, year: year),
              isValid(day: endDay, month: endMonth, year: year),
              let startDate = calendar.date(from: DateComponents(year: year, month: startMonth, day: startDay)),
              let rawEndDate = calendar.date(from: DateComponents(year: year, month: endMonth, day: endDay)) else {
            return []
        }

        let endDate: Date
        if rawEndDate >= startDate {
            endDate = rawEndDate
        } else if let shifted = calendar.date(byAdding: .year, value: 1, to: rawEndDate) {
            endDate = shifted
        } else {
            endDate = rawEndDate
        }

        var result = Set<String>()
        var current = startDate
        while current <= endDate {
            let comps = calendar.dateComponents([.month, .day], from: current)
            if let month = comps.month, let day = comps.day {
                result.insert(makeKey(month: month, day: day))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return result
    }

    private func monthNumber(from text: String) -> Int? {
        let value = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("янв") { return 1 }
        if value.hasPrefix("фев") { return 2 }
        if value.hasPrefix("мар") { return 3 }
        if value.hasPrefix("апр") { return 4 }
        if value.hasPrefix("май") || value.hasPrefix("мая") { return 5 }
        if value.hasPrefix("июн") { return 6 }
        if value.hasPrefix("июл") { return 7 }
        if value.hasPrefix("авг") { return 8 }
        if value.hasPrefix("сен") { return 9 }
        if value.hasPrefix("окт") { return 10 }
        if value.hasPrefix("ноя") { return 11 }
        if value.hasPrefix("дек") { return 12 }
        return nil
    }

    private func isValid(day: Int, month: Int, year: Int) -> Bool {
        guard (1...12).contains(month), (1...31).contains(day) else { return false }
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) != nil
    }

    private func makeKey(month: Int, day: Int) -> String {
        String(format: "%02d-%02d", month, day)
    }
}
