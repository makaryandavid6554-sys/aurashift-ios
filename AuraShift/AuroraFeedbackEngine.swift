import Foundation
import SwiftUI
import Combine

enum AuroraMood: String, Codable, CaseIterable, Identifiable {
    case positive
    case neutral
    case negative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .positive:
            return NSLocalizedString("Позитивное", comment: "aurora mood title positive")
        case .neutral:
            return NSLocalizedString("Нейтральное", comment: "aurora mood title neutral")
        case .negative:
            return NSLocalizedString("Негативное", comment: "aurora mood title negative")
        }
    }

    var icon: String {
        switch self {
        case .positive:
            return "sun.max.fill"
        case .neutral:
            return "circle.lefthalf.filled"
        case .negative:
            return "cloud.rain.fill"
        }
    }

    var color: Color {
        switch self {
        case .positive:
            return AppColors.positive
        case .neutral:
            return AppColors.accent
        case .negative:
            return AppColors.negative
        }
    }
}

struct AuroraDayContext: Codable {
    let isWeekend: Bool
    let hasShiftToday: Bool
    let shiftCountToday: Int
    let dayDate: Date?
}

struct AuroraFeedbackRecommendation: Codable, Identifiable {
    let id: UUID
    let title: String
    let body: String
    let details: [String]
    let mood: AuroraMood

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        details: [String],
        mood: AuroraMood
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.details = details
        self.mood = mood
    }
}

struct AuroraFeedbackEntry: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let text: String
    let manualMood: AuroraMood?
    let detectedMood: AuroraMood
    let keyMoments: [String]
    let dayContext: AuroraDayContext
    let recommendations: [AuroraFeedbackRecommendation]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        text: String,
        manualMood: AuroraMood?,
        detectedMood: AuroraMood,
        keyMoments: [String],
        dayContext: AuroraDayContext,
        recommendations: [AuroraFeedbackRecommendation]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.manualMood = manualMood
        self.detectedMood = detectedMood
        self.keyMoments = keyMoments
        self.dayContext = dayContext
        self.recommendations = recommendations
    }
}

struct AuroraAIContext {
    let forecast: AIForecast
    let profile: BehavioralProfile
    let bestWeekday: WeekdayHeatmapRow?
    let bestHour: HourlyHeatmapRow?
    let topInsight: AIInsight?
    let currency: String
    let recentIncomeDeltaPercent: Double
    let recentTipsShare: Double
    let externalFactors: AuroraExternalFactorsContext
}

struct AuroraExternalFactorsContext {
    let weatherCondition: WeatherCondition
    let precipitationChance: Double
    let holidayTitle: String?
    let holidayImpactPercent: Double
    let isPublicHoliday: Bool
    let seasonLabel: String
    let anomalyDetected: Bool
}

enum AuroraStreakStage: Int, CaseIterable {
    case zero
    case oneToThree
    case fourToSeven
    case eightToFourteen
    case fifteenToThirty
    case legend

    init(streakDays: Int) {
        switch streakDays {
        case ...0:
            self = .zero
        case 1...3:
            self = .oneToThree
        case 4...7:
            self = .fourToSeven
        case 8...14:
            self = .eightToFourteen
        case 15...30:
            self = .fifteenToThirty
        default:
            self = .legend
        }
    }

    var title: String {
        switch self {
        case .zero:
            return NSLocalizedString("Старт", comment: "aurora streak stage title: start")
        case .oneToThree:
            return NSLocalizedString("Разгон", comment: "aurora streak stage title: warmup")
        case .fourToSeven:
            return NSLocalizedString("Ритм", comment: "aurora streak stage title: rhythm")
        case .eightToFourteen:
            return NSLocalizedString("Подъём", comment: "aurora streak stage title: rise")
        case .fifteenToThirty:
            return NSLocalizedString("Фокус", comment: "aurora streak stage title: focus")
        case .legend:
            return NSLocalizedString("Легенда", comment: "aurora streak stage title: legend")
        }
    }

    var greetingPrefix: String {
        switch self {
        case .zero:
            return NSLocalizedString("Я рядом и помогу начать в мягком темпе.", comment: "aurora streak greeting prefix: zero")
        case .oneToThree:
            return NSLocalizedString("Отличное начало серии, держим темп.", comment: "aurora streak greeting prefix: one to three")
        case .fourToSeven:
            return NSLocalizedString("Ты вошёл в рабочий ритм, усилим сильные слоты.", comment: "aurora streak greeting prefix: four to seven")
        case .eightToFourteen:
            return NSLocalizedString("Классная серия, продуктивность растёт день за днём.", comment: "aurora streak greeting prefix: eight to fourteen")
        case .fifteenToThirty:
            return NSLocalizedString("Стабильность высокого уровня, давай укрепим результат.", comment: "aurora streak greeting prefix: fifteen to thirty")
        case .legend:
            return NSLocalizedString("Режим Легенда активен, можно играть в долгую и точнее планировать цели.", comment: "aurora streak greeting prefix: legend")
        }
    }

    var assetCandidates: [String] {
        switch self {
        case .zero:
            return ["AuroraMuted", "AuroraMaster"]
        case .oneToThree:
            return ["AuroraWarm", "AuroraWaving"]
        case .fourToSeven:
            return ["AuroraBright", "AuroraListening"]
        case .eightToFourteen:
            return ["AuroraJoy", "AuroraCelebration"]
        case .fifteenToThirty:
            return ["AuroraRadiant", "AuroraCelebration"]
        case .legend:
            return ["AuroraLegend", "AuroraCelebration"]
        }
    }

    var particleOpacity: Double {
        switch self {
        case .zero, .oneToThree:
            return 0
        case .fourToSeven:
            return 0.12
        case .eightToFourteen:
            return 0.18
        case .fifteenToThirty:
            return 0.24
        case .legend:
            return 0.30
        }
    }
}

final class AuroraEngagementTracker: ObservableObject {
    @Published private(set) var streakDays: Int = 0
    @Published private(set) var lastOpenDate: Date?

    private let defaults = UserDefaults.standard
    private let streakKey = "aurashift.aurora.engagement.streak.v1"
    private let lastOpenKey = "aurashift.aurora.engagement.lastOpen.v1"
    private let calendar = Calendar.current

    init() {
        streakDays = defaults.integer(forKey: streakKey)
        lastOpenDate = defaults.object(forKey: lastOpenKey) as? Date
    }

    var stage: AuroraStreakStage {
        AuroraStreakStage(streakDays: streakDays)
    }

    func registerOpen(on date: Date = Date()) {
        let currentDay = calendar.startOfDay(for: date)

        guard let lastOpenDate else {
            streakDays = 1
            self.lastOpenDate = currentDay
            persist()
            return
        }

        let lastDay = calendar.startOfDay(for: lastOpenDate)
        if calendar.isDate(currentDay, inSameDayAs: lastDay) {
            return
        }

        if let expectedNext = calendar.date(byAdding: .day, value: 1, to: lastDay),
           calendar.isDate(currentDay, inSameDayAs: expectedNext) {
            streakDays += 1
        } else {
            streakDays = 1
        }

        self.lastOpenDate = currentDay
        persist()
    }

    private func persist() {
        defaults.set(streakDays, forKey: streakKey)
        defaults.set(lastOpenDate, forKey: lastOpenKey)
    }
}

struct AuroraFeedbackAnalysis {
    let mood: AuroraMood
    let keyMoments: [String]
    let recommendations: [AuroraFeedbackRecommendation]
}

final class AuroraFeedbackStore: ObservableObject {
    @Published private(set) var entries: [AuroraFeedbackEntry] = []

    private let storageKey = "aurashift.aurora.feedback.entries.v1"
    private let maxEntries = 120

    init() {
        load()
    }

    var latestEntry: AuroraFeedbackEntry? {
        entries.first
    }

    func add(_ entry: AuroraFeedbackEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            entries = []
            return
        }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([AuroraFeedbackEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

struct AuroraFeedbackAnalyzer {
    private let positiveWords: Set<String> = [
        "хорошо", "класс", "отлично", "рад", "спокойно", "получилось", "продуктивно", "успел", "доволен",
        "great", "good", "nice", "happy", "productive", "win", "progress"
    ]

    private let negativeWords: Set<String> = [
        "плохо", "устал", "тяжело", "стресс", "проблема", "ошибка", "неудача", "грустно", "перегруз",
        "bad", "tired", "stress", "hard", "fail", "sad", "burnout", "problem"
    ]

    private let keyMomentWords: Set<String> = [
        "чаевые", "клиент", "гость", "смен", "заказ", "доход", "выходной", "семья", "спорт", "цель",
        "tips", "client", "shift", "income", "goal", "weekend", "rest"
    ]

    func analyze(
        text: String,
        manualMood: AuroraMood?,
        dayContext: AuroraDayContext,
        ai: AuroraAIContext,
        recentEntries: [AuroraFeedbackEntry]
    ) -> AuroraFeedbackAnalysis {
        let normalized = text.lowercased()
        let autoMood = detectMood(from: normalized)
        let mood = manualMood ?? autoMood
        let keyMoments = extractKeyMoments(from: text)
        let recommendations = generateRecommendations(
            mood: mood,
            dayContext: dayContext,
            keyMoments: keyMoments,
            ai: ai,
            recentEntries: recentEntries
        )
        return AuroraFeedbackAnalysis(
            mood: mood,
            keyMoments: keyMoments,
            recommendations: recommendations
        )
    }

    private func detectMood(from text: String) -> AuroraMood {
        let tokens = tokenize(text)
        let positiveScore = tokens.filter { positiveWords.contains($0) }.count
        let negativeScore = tokens.filter { negativeWords.contains($0) }.count

        if positiveScore > negativeScore + 1 {
            return .positive
        }
        if negativeScore > positiveScore + 1 {
            return .negative
        }

        // Additional signal from punctuation
        if text.contains("!") && negativeScore == 0 {
            return .positive
        }
        if text.contains("...") || text.contains("(") {
            return .neutral
        }
        return .neutral
    }

    private func extractKeyMoments(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let sentences = trimmed
            .replacingOccurrences(of: "\n", with: ". ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var selected: [String] = []

        for sentence in sentences {
            let lowered = sentence.lowercased()
            let tokens = tokenize(lowered)
            let hasKeyword = tokens.contains(where: { keyMomentWords.contains($0) })
            let hasSignalLength = sentence.count >= 18
            if hasKeyword || hasSignalLength {
                selected.append(sentence)
            }
            if selected.count >= 3 {
                break
            }
        }

        if selected.isEmpty {
            selected = Array(sentences.prefix(2))
        }
        return selected
    }

    private func generateRecommendations(
        mood: AuroraMood,
        dayContext: AuroraDayContext,
        keyMoments: [String],
        ai: AuroraAIContext,
        recentEntries: [AuroraFeedbackEntry]
    ) -> [AuroraFeedbackRecommendation] {
        var cards: [AuroraFeedbackRecommendation] = []
        let pattern = buildPatternSummary(recentEntries: recentEntries)

        cards.append(
            emotionalCard(mood: mood, dayContext: dayContext)
        )

        if let weatherCard = weatherAndSeasonCard(ai: ai) {
            cards.append(weatherCard)
        }

        if let day = ai.bestWeekday,
           let hour = ai.bestHour,
           day.shiftsCount > 0,
           hour.shiftsCount > 0 {
            cards.append(
                AuroraFeedbackRecommendation(
                    title: NSLocalizedString("Опора на сильный слот", comment: "aurora recommendation: best slot title"),
                    body: String(
                        format: NSLocalizedString("Попробуйте сделать следующую смену в %@ около %d:00 — там у вас стабильно сильный результат.", comment: "aurora recommendation: best slot body"),
                        day.weekdayName,
                        hour.hour
                    ),
                    details: [
                        String(
                            format: NSLocalizedString("Средний доход в этот день: %.0f %@", comment: "aurora recommendation: best day avg"),
                            day.avgIncome,
                            ai.currency
                        ),
                        String(
                            format: NSLocalizedString("Средний доход при старте в %d:00: %.0f %@", comment: "aurora recommendation: best hour avg"),
                            hour.hour,
                            hour.avgIncome,
                            ai.currency
                        )
                    ],
                    mood: .positive
                )
            )
        }

        if ai.profile.tipsContribution >= 0.08 || ai.recentTipsShare >= 0.08 {
            let tipsShare = max(ai.profile.tipsContribution, ai.recentTipsShare)
            cards.append(
                AuroraFeedbackRecommendation(
                    title: NSLocalizedString("Фокус на чаевые", comment: "aurora recommendation: tips title"),
                    body: String(
                        format: NSLocalizedString("Чаевые дают около %d%% вашего дохода — выбирайте смены с большим потоком гостей.", comment: "aurora recommendation: tips body"),
                        Int(tipsShare * 100)
                    ),
                    details: [
                        NSLocalizedString("Перед сменой заранее продумайте приветствие и быстрые upsell-скрипты.", comment: "aurora recommendation: tips detail one"),
                        ai.externalFactors.precipitationChance >= 0.6
                        ? NSLocalizedString("В дождливые дни делайте акцент на ранние часы: чаевые обычно ниже нормы.", comment: "aurora recommendation: tips detail rainy day")
                        : NSLocalizedString("Отмечайте дни с лучшими чаевыми — Аврора усилит прогноз точнее.", comment: "aurora recommendation: tips detail two")
                    ],
                    mood: .neutral
                )
            )
        }

        cards.append(
            goalCard(probability: ai.forecast.goalProbability)
        )

        if let patternCard = patternDrivenCard(pattern: pattern, ai: ai) {
            cards.append(patternCard)
        }

        if pattern.consecutiveNegative >= 2 || mood == .negative {
            cards.append(
                AuroraFeedbackRecommendation(
                    title: NSLocalizedString("Восстановление темпа", comment: "aurora recommendation: recovery title"),
                    body: NSLocalizedString("Добавьте один лёгкий день восстановления и одну короткую прибыльную смену — это снизит усталость без потери темпа.", comment: "aurora recommendation: recovery body"),
                    details: [
                        NSLocalizedString("Короткая смена 4–6 часов часто даёт хороший баланс энергии и дохода.", comment: "aurora recommendation: recovery detail one"),
                        NSLocalizedString("Зафиксируйте 1 главный результат дня, чтобы вернуть ощущение контроля.", comment: "aurora recommendation: recovery detail two")
                    ],
                    mood: .negative
                )
            )
        }

        if ai.externalFactors.anomalyDetected {
            cards.append(
                AuroraFeedbackRecommendation(
                    title: NSLocalizedString("Обнаружена аномалия дня", comment: "aurora recommendation: anomaly title"),
                    body: NSLocalizedString("Сегодняшние условия заметно отклоняются от обычных. Планируйте смену короче и с запасом по энергии.", comment: "aurora recommendation: anomaly body"),
                    details: [
                        NSLocalizedString("Если нагрузка нестабильная, фиксируйте 1-2 ключевых события смены для корректировки прогноза.", comment: "aurora recommendation: anomaly detail one"),
                        NSLocalizedString("Аврора учтёт аномалию в следующих рекомендациях и сгладит прогноз.", comment: "aurora recommendation: anomaly detail two")
                    ],
                    mood: .neutral
                )
            )
        }

        if let topInsight = ai.topInsight {
            cards.append(
                AuroraFeedbackRecommendation(
                    title: NSLocalizedString("Что Аврора видит сейчас", comment: "aurora recommendation: top insight title"),
                    body: topInsight.title,
                    details: [topInsight.body] + keyMoments,
                    mood: .neutral
                )
            )
        }

        return Array(cards.prefix(7))
    }

    private func emotionalCard(mood: AuroraMood, dayContext: AuroraDayContext) -> AuroraFeedbackRecommendation {
        switch mood {
        case .positive:
            return AuroraFeedbackRecommendation(
                title: NSLocalizedString("Отличный тон дня", comment: "aurora recommendation: emotional positive title"),
                body: NSLocalizedString("Классный настрой. Зафиксируйте, что именно сработало сегодня, и повторите это в следующей смене.", comment: "aurora recommendation: emotional positive body"),
                details: [
                    dayContext.hasShiftToday
                    ? NSLocalizedString("Сохраните короткую заметку о сильном моменте смены.", comment: "aurora recommendation: emotional positive detail shift")
                    : NSLocalizedString("Сохраните, что помогло хорошо восстановиться в выходной.", comment: "aurora recommendation: emotional positive detail day off")
                ],
                mood: .positive
            )
        case .neutral:
            return AuroraFeedbackRecommendation(
                title: NSLocalizedString("Ровный день", comment: "aurora recommendation: emotional neutral title"),
                body: NSLocalizedString("Нейтральный ритм — хорошая база для улучшения. Добавим один точечный шаг к доходу и один шаг к восстановлению.", comment: "aurora recommendation: emotional neutral body"),
                details: [
                    NSLocalizedString("Выберите одну метрику для фокуса: чаевые, длительность смены или стартовый час.", comment: "aurora recommendation: emotional neutral detail")
                ],
                mood: .neutral
            )
        case .negative:
            return AuroraFeedbackRecommendation(
                title: NSLocalizedString("Поддержка от Авроры", comment: "aurora recommendation: emotional negative title"),
                body: NSLocalizedString("День мог быть непростым. Давайте снизим нагрузку и вернём контроль через короткий понятный план.", comment: "aurora recommendation: emotional negative body"),
                details: [
                    NSLocalizedString("Сделайте одну простую цель на завтра и отметьте её выполнение.", comment: "aurora recommendation: emotional negative detail")
                ],
                mood: .negative
            )
        }
    }

    private func goalCard(probability: Double) -> AuroraFeedbackRecommendation {
        let pct = Int(probability * 100)
        if probability >= 0.75 {
            return AuroraFeedbackRecommendation(
                title: NSLocalizedString("Цель в хорошем темпе", comment: "aurora recommendation: goal high title"),
                body: String(
                    format: NSLocalizedString("Вероятность достижения цели: %d%%. Держите текущий ритм и не перегружайте график.", comment: "aurora recommendation: goal high body"),
                    pct
                ),
                details: [
                    NSLocalizedString("Поддерживайте регулярность и не пропускайте фиксацию смен.", comment: "aurora recommendation: goal high detail")
                ],
                mood: .positive
            )
        }
        if probability >= 0.5 {
            return AuroraFeedbackRecommendation(
                title: NSLocalizedString("Цель достижима", comment: "aurora recommendation: goal medium title"),
                body: String(
                    format: NSLocalizedString("Вероятность достижения цели: %d%%. Добавьте 1 сильную смену в неделю для запаса.", comment: "aurora recommendation: goal medium body"),
                    pct
                ),
                details: [
                    NSLocalizedString("Смещайте фокус на лучшие дни и часы, которые Аврора уже определила.", comment: "aurora recommendation: goal medium detail")
                ],
                mood: .neutral
            )
        }
        return AuroraFeedbackRecommendation(
            title: NSLocalizedString("Цель требует корректировки", comment: "aurora recommendation: goal low title"),
            body: String(
                format: NSLocalizedString("Вероятность достижения цели: %d%%. Пересоберите график: меньше случайных смен, больше смен в сильные слоты.", comment: "aurora recommendation: goal low body"),
                pct
            ),
            details: [
                NSLocalizedString("Нужна серия из 2–3 стабильных недель с контролем смен и расходов.", comment: "aurora recommendation: goal low detail")
            ],
            mood: .negative
        )
    }

    private struct PatternSummary {
        let positiveShare7d: Double
        let negativeShare7d: Double
        let consecutivePositive: Int
        let consecutiveNegative: Int
    }

    private func buildPatternSummary(recentEntries: [AuroraFeedbackEntry]) -> PatternSummary {
        let calendar = Calendar.current
        let now = Date()
        let entries7d = recentEntries.filter { entry in
            guard let start = calendar.date(byAdding: .day, value: -6, to: now) else { return false }
            return entry.createdAt >= start
        }

        let total7d = max(entries7d.count, 1)
        let positiveCount7d = entries7d.filter { $0.detectedMood == .positive }.count
        let negativeCount7d = entries7d.filter { $0.detectedMood == .negative }.count

        var consecutivePositive = 0
        var consecutiveNegative = 0
        for entry in recentEntries {
            if entry.detectedMood == .positive {
                consecutivePositive += 1
            } else {
                break
            }
        }
        for entry in recentEntries {
            if entry.detectedMood == .negative {
                consecutiveNegative += 1
            } else {
                break
            }
        }

        return PatternSummary(
            positiveShare7d: Double(positiveCount7d) / Double(total7d),
            negativeShare7d: Double(negativeCount7d) / Double(total7d),
            consecutivePositive: consecutivePositive,
            consecutiveNegative: consecutiveNegative
        )
    }

    private func weatherAndSeasonCard(ai: AuroraAIContext) -> AuroraFeedbackRecommendation? {
        let weather = ai.externalFactors.weatherCondition
        let precipitationPercent = Int((ai.externalFactors.precipitationChance * 100).rounded())
        let holidayPercent = Int((ai.externalFactors.holidayImpactPercent * 100).rounded())

        if ai.externalFactors.isPublicHoliday || abs(ai.externalFactors.holidayImpactPercent) >= 0.08 {
            let holidayTitle = ai.externalFactors.holidayTitle
                ?? NSLocalizedString("Календарное событие", comment: "aurora recommendation: holiday fallback title")
            let impactPhrase: String
            if holidayPercent > 0 {
                impactPhrase = String(
                    format: NSLocalizedString("ожидается до +%d%% к спросу", comment: "aurora recommendation: holiday positive impact"),
                    holidayPercent
                )
            } else if holidayPercent < 0 {
                impactPhrase = String(
                    format: NSLocalizedString("возможна просадка до %d%%", comment: "aurora recommendation: holiday negative impact"),
                    abs(holidayPercent)
                )
            } else {
                impactPhrase = NSLocalizedString("сильные колебания спроса вероятны", comment: "aurora recommendation: holiday neutral impact")
            }
            return AuroraFeedbackRecommendation(
                title: NSLocalizedString("Праздники и сезонность", comment: "aurora recommendation: seasonality title"),
                body: "\(holidayTitle): \(impactPhrase).",
                details: [
                    String(
                        format: NSLocalizedString("Сезон: %@.", comment: "aurora recommendation: season detail"),
                        ai.externalFactors.seasonLabel
                    ),
                    NSLocalizedString("Если ожидается перегруз, лучше брать смену утром или днём и фиксировать итог.", comment: "aurora recommendation: holiday planning detail")
                ],
                mood: holidayPercent >= 0 ? .positive : .neutral
            )
        }

        if weather == .rain || weather == .snow || ai.externalFactors.precipitationChance >= 0.55 {
            let title = NSLocalizedString("Погодный фактор на чаевые", comment: "aurora recommendation: weather tips title")
            let body: String
            if weather == .rain || weather == .snow {
                body = String(
                    format: NSLocalizedString("Сегодня ожидаются осадки (%d%%). Лучше выбрать более ранний старт смены.", comment: "aurora recommendation: weather tips body rainy"),
                    precipitationPercent
                )
            } else {
                body = String(
                    format: NSLocalizedString("Вероятность осадков около %d%%. Планируйте смену в часы с максимальным потоком.", comment: "aurora recommendation: weather tips body uncertain"),
                    precipitationPercent
                )
            }
            return AuroraFeedbackRecommendation(
                title: title,
                body: body,
                details: [
                    NSLocalizedString("В дни с плохой погодой чаевые чаще смещаются в утренние/дневные слоты.", comment: "aurora recommendation: weather tips detail one"),
                    NSLocalizedString("Добавьте факт по итоговым чаевым в заметке — Аврора уточнит модель быстрее.", comment: "aurora recommendation: weather tips detail two")
                ],
                mood: .neutral
            )
        }

        return nil
    }

    private func patternDrivenCard(
        pattern: PatternSummary,
        ai: AuroraAIContext
    ) -> AuroraFeedbackRecommendation? {
        if pattern.consecutivePositive >= 3 {
            return AuroraFeedbackRecommendation(
                title: NSLocalizedString("Рост продуктивности по серии", comment: "aurora recommendation: productivity streak title"),
                body: NSLocalizedString("По последним заметкам продуктивность усиливается после 3 дней подряд. Сохраните серию ещё на 2 дня в сильных слотах.", comment: "aurora recommendation: productivity streak body"),
                details: [
                    String(
                        format: NSLocalizedString("Изменение дохода за последние периоды: %.0f%%.", comment: "aurora recommendation: productivity streak income change detail"),
                        ai.recentIncomeDeltaPercent
                    ),
                    NSLocalizedString("Держите стабильный режим сна и одинаковое время старта — это усилит прогнозируемость.", comment: "aurora recommendation: productivity streak detail two")
                ],
                mood: .positive
            )
        }

        if pattern.negativeShare7d >= 0.45 {
            return AuroraFeedbackRecommendation(
                title: NSLocalizedString("Нагрузка растёт", comment: "aurora recommendation: overload title"),
                body: NSLocalizedString("В заметках за 7 дней много признаков усталости. Лучше сделать один облегчённый день и сократить риск выгорания.", comment: "aurora recommendation: overload body"),
                details: [
                    NSLocalizedString("Оптимальный шаг: короткая смена + фиксированный перерыв перед следующим рабочим днём.", comment: "aurora recommendation: overload detail one"),
                    NSLocalizedString("После стабилизации настроения вернитесь к сильным дням/часам из подсказок Авроры.", comment: "aurora recommendation: overload detail two")
                ],
                mood: .negative
            )
        }

        if pattern.positiveShare7d >= 0.60 {
            return AuroraFeedbackRecommendation(
                title: NSLocalizedString("Стабильный прогресс", comment: "aurora recommendation: stable progress title"),
                body: NSLocalizedString("Большая часть заметок за неделю позитивные. Хороший момент усилить цели и закрепить рабочий ритм.", comment: "aurora recommendation: stable progress body"),
                details: [
                    NSLocalizedString("Добавьте одну целевую смену в лучший день недели для ускорения роста.", comment: "aurora recommendation: stable progress detail one")
                ],
                mood: .positive
            )
        }

        return nil
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
