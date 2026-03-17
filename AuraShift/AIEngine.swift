// AIEngine.swift
// AuraShift — Интеллектуальный аналитический движок
// Локальная ML-аналитика без CoreML: регрессия, EMA, тренды, аномалии, рекомендации

import Foundation
import CoreData
import SwiftUI
import Combine

// MARK: - Data Models

struct ShiftFeature {
    let workTypeName: String
    let weekday: Int          // 1=Пн..7=Вс
    let month: Int
    let startHour: Int
    let durationHours: Double
    let hasTips: Bool
    let actualIncome: Double
    let tipsAmount: Double
    let date: Date
}

struct AIInsight: Identifiable {
    let id = UUID()
    let type: InsightType
    let title: String
    let body: String
    let impact: Double
    let confidence: Double
    let icon: String
    let accentColor: Color
    let priority: Int

    enum InsightType: String {
        case recommendation, anomaly, trend, achievement, warning, forecast
    }
}

struct WeekdayHeatmapRow: Identifiable {
    let id = UUID()
    let weekday: Int
    let weekdayName: String
    let avgIncome: Double
    let shiftsCount: Int
    let intensity: Double
}

struct HourlyHeatmapRow: Identifiable {
    let id = UUID()
    let hour: Int
    let avgIncome: Double
    let shiftsCount: Int
    let intensity: Double
}

struct AIFeatureImportance: Identifiable {
    let id = UUID()
    let name: String
    let weight: Double    // 0...1
    let detail: String
}

struct ShiftRecommendation: Identifiable {
    let id = UUID()
    let date: Date
    let workTypeName: String
    let workTypeIcon: String
    let expectedIncome: Double
    let confidence: Double
    let holidayPriorityPercent: Double
    let reasons: [String]
}

struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let movingAverage: Double
    let isPredicted: Bool
}

struct AIForecast {
    var shiftPrediction: Double       = 0
    var monthForecast: Double         = 0
    var goalProbability: Double       = 0
    var highIncomeProbability: Double = 0
    var confidence: Double            = 0
    var basedOnShifts: Int            = 0
    /// Фактический темп: первые N дней текущего месяца vs первые N дней прошлого месяца.
    var currentProgressChange: Double = 0
    /// Прогноз к концу месяца vs полный прошлый месяц.
    var forecastEndMonthChange: Double = 0
    var hasCurrentProgressComparison: Bool = false
    var hasForecastEndComparison: Bool = false
    var currentProgressDays: Int = 0
    var forecastEndComparisonWindow: Int = 0
    var forecastEndComparisonMessage: String? = nil
    var forecastEndComparisonExplanation: String? = nil
    var monthOverMonthChange: Double  = 0
    var anomalyScore: Double          = 0
    var anomalyDirection: Int         = 0
}

struct AIForecastQuality {
    var mae: Double = 0
    var rmse: Double = 0
    var mape: Double = 0        // 0...1
    var monthlyMAE: Double = 0
    var sampleCount: Int = 0
    var monthlySampleCount: Int = 0

    var hasShiftMetrics: Bool { sampleCount > 0 }
    var hasMonthlyMetrics: Bool { monthlySampleCount > 0 }
}

struct BehavioralProfile {
    var optimalShiftDuration: Double = 8
    var bestWeekdays: [Int]          = []
    var bestStartHours: [Int]        = []
    var tipsContribution: Double     = 0
    var consistencyScore: Double     = 0
    var growthRate: Double           = 0
}

// MARK: - AIEngine

final class AIEngine: ObservableObject {

    enum ForecastModelMode: Equatable {
        case standard
        case blended
        case enhanced
    }

    @Published var insights: [AIInsight]               = []
    @Published var forecast: AIForecast                = AIForecast()
    @Published var forecastModelMode: ForecastModelMode = .standard
    @Published var weekdayHeatmap: [WeekdayHeatmapRow] = []
    @Published var hourlyHeatmap: [HourlyHeatmapRow]   = []
    @Published var trendPoints: [TrendPoint]           = []
    @Published var profile: BehavioralProfile          = BehavioralProfile()
    @Published var isAnalyzing: Bool                   = false
    @Published var hasEnoughData: Bool                 = false
    @Published var lastUpdated: Date?                  = nil
    @Published var featureImportance: [AIFeatureImportance] = []
    @Published var shiftRecommendations: [ShiftRecommendation] = []
    @Published var forecastQuality: AIForecastQuality        = AIForecastQuality()
    /// Прогноз дохода по типу работы: [workTypeName: (predicted, confidence, basedOn)]
    @Published var perWorkTypeForecast: [String: (predicted: Double, confidence: Double, basedOn: Int)] = [:]
    /// Поправка по дням недели для каждого типа работы: [workTypeName: [weekday: multiplier]]
    @Published var perWorkTypeWeekdayMultipliers: [String: [Int: Double]] = [:]

    private let minShifts = 5
    private let fullDayHoursThreshold = 9.0

    // Серийная очередь для фоновых вычислений
    // Utility QoS keeps UI responsive during cold start while analysis runs in background.
    private let queue = DispatchQueue(label: "com.aurashift.aiengine", qos: .utility)
    private typealias IncomeSnap = (date: Date, amount: Double, tips: Double,
                                    hours: Double, rate: Double, type: String, floating: Double)
    private typealias ExpSnap = (date: Date, amount: Double, category: String)
    private typealias GoalSnap = (target: Double, current: Double, active: Bool)
    private struct PlannedSnap {
        let date: Date
        let workTypeId: UUID
        let workTypeName: String
        let startTime: Date
        let endTime: Date
        let hourlyRate: Double
        let hasTips: Bool
    }

    private struct AnalyzeRequest {
        let incomes: [IncomeSnap]
        let expenses: [ExpSnap]
        let goals: [GoalSnap]
        let plannedShifts: [PlannedSnap]
        let wtMap: [String:(startHour:Int,hasTips:Bool)]
        let activeWorkTypes: [WorkType]
        let currency: String
        let externalFactorsEnabled: Bool
        let weatherCity: String
        let weatherCoordinates: (latitude: Double, longitude: Double)?
        let liveWeatherEnabled: Bool
        let holidayRegionCode: String
    }

    private struct AdvancedMLSample {
        let vector: [Double]
        let target: Double
        let date: Date
    }

    private indirect enum RegressionTreeNode {
        case leaf(Double)
        case split(feature: Int, threshold: Double, left: RegressionTreeNode, right: RegressionTreeNode)
    }

    private struct DeterministicRNG {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        }

        mutating func nextUInt64() -> UInt64 {
            state = 6364136223846793005 &* state &+ 1442695040888963407
            return state
        }

        mutating func nextInt(upperBound: Int) -> Int {
            guard upperBound > 0 else { return 0 }
            return Int(nextUInt64() % UInt64(upperBound))
        }
    }

    private typealias RandomForestModel = [RegressionTreeNode]

    private struct GradientBoostingModel {
        let bias: Double
        let trees: [RegressionTreeNode]
        let stepSizes: [Double]
    }

    private var pendingRequest: AnalyzeRequest?

    func analyze(incomes: [Income], expenses: [Expense],
                 settings: UserSettings, goals: [FinancialGoal],
                 plannedShifts: [PlannedShift] = []) {
        let iSnaps: [IncomeSnap] = incomes.compactMap { i in
            guard let d = i.date else { return nil }
            return (d, (i.hoursWorked*i.hourlyRate)+i.tips+i.floatingAmount,
                    i.tips, i.hoursWorked, i.hourlyRate, i.type ?? NSLocalizedString("Работа", comment: "AI default work type"), i.floatingAmount)
        }
        let eSnaps: [ExpSnap] = expenses.compactMap { e in
            guard let d = e.date else { return nil }
            return (d, e.amount, e.category ?? NSLocalizedString("Другое", comment: "AI default expense category"))
        }
        let gSnaps: [GoalSnap] = goals.map { ($0.targetAmount, $0.currentAmount, $0.isActive) }
        let pSnaps: [PlannedSnap] = plannedShifts.map { shift in
            PlannedSnap(
                date: shift.date,
                workTypeId: shift.workTypeId,
                workTypeName: shift.workTypeName,
                startTime: shift.startTime,
                endTime: shift.endTime,
                hourlyRate: shift.hourlyRate,
                hasTips: shift.hasTips
            )
        }
        let wtMap: [String:(startHour:Int,hasTips:Bool)] = Dictionary(uniqueKeysWithValues:
            settings.workTypes.map { ($0.name, ($0.startHour, $0.hasTips)) })
        let locationManager = DeviceLocationManager.shared
        let locationCity = locationManager.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCity = locationCity.isEmpty
            ? settings.proWeatherCity
            : locationCity
        let request = AnalyzeRequest(
            incomes: iSnaps,
            expenses: eSnaps,
            goals: gSnaps,
            plannedShifts: pSnaps,
            wtMap: wtMap,
            activeWorkTypes: settings.workTypes.filter { $0.isActive },
            currency: settings.defaultCurrency,
            externalFactorsEnabled: ProManager.shared.canUse(.externalFactors),
            weatherCity: resolvedCity,
            weatherCoordinates: locationManager.coordinate,
            liveWeatherEnabled: settings.proUseLiveWeather,
            holidayRegionCode: settings.proHolidayRegionCode
        )
        enqueueAnalyze(request)
    }

    private func enqueueAnalyze(_ request: AnalyzeRequest) {
        if isAnalyzing {
            pendingRequest = request
            return
        }
        isAnalyzing = true
        runAnalyze(request)
    }

    private func runAnalyze(_ request: AnalyzeRequest) {
        queue.async { [weak self] in
            guard let self else { return }
            let features = self.buildFeatures(snaps: request.incomes, wtMap: request.wtMap)
            let wdH  = self.buildWeekdayHeatmap(features: features)
            let hrH  = self.buildHourlyHeatmap(features: features)
            let tp   = self.buildTrend(iSnaps: request.incomes, eSnaps: request.expenses)
            let bp   = self.buildProfile(features: features)
            let forecastBuild = self.buildForecast(
                features: features,
                iSnaps: request.incomes,
                eSnaps: request.expenses,
                goals: request.goals,
                plannedShifts: request.plannedShifts,
                activeWorkTypes: request.activeWorkTypes,
                externalFactorsEnabled: request.externalFactorsEnabled,
                weatherCity: request.weatherCity,
                weatherCoordinates: request.weatherCoordinates,
                allowLiveWeather: request.liveWeatherEnabled,
                holidayRegionCode: request.holidayRegionCode
            )
            let fc   = forecastBuild.forecast
            let quality = self.buildForecastQuality(features: features, iSnaps: request.incomes, eSnaps: request.expenses)
            // Прогноз индивидуально по каждому типу работы
            let wtNames = Array(Set(request.activeWorkTypes.map { $0.name } + features.map { $0.workTypeName }))
            var perWT: [String:(predicted:Double,confidence:Double,basedOn:Int)] = [:]
            var perWTWeekday: [String:[Int:Double]] = [:]
            for name in wtNames {
                let typeFeatures = features.filter { $0.workTypeName == name }
                perWT[name] = self.buildPerWorkTypeForecast(features: typeFeatures, allFeatures: features)
                perWTWeekday[name] = self.buildPerWorkTypeWeekdayMultipliers(
                    features: typeFeatures,
                    allFeatures: features)
            }
            // Даты, уже занятые сменами (учитываем и фактические, и запланированные)
            let cal = Calendar.current
            let occupiedFromActual = features.reduce(into: ([Date: Int](), [Date: Double]())) { result, feature in
                let day = cal.startOfDay(for: feature.date)
                result.0[day, default: 0] += 1
                result.1[day, default: 0] += max(feature.durationHours, 1)
            }
            var occupiedDateCounts = occupiedFromActual.0
            var occupiedDayHours = occupiedFromActual.1
            for snap in request.plannedShifts {
                let day = cal.startOfDay(for: snap.date)
                occupiedDateCounts[day, default: 0] += 1
                occupiedDayHours[day, default: 0] += max(plannedShiftDurationHours(start: snap.startTime, end: snap.endTime), 1)
            }
            let ins  = self.buildInsights(features: features, fc: fc, wdH: wdH, bp: bp,
                                          currency: request.currency, goals: request.goals,
                                          externalFactorsEnabled: request.externalFactorsEnabled,
                                          weatherCity: request.weatherCity,
                                          weatherCoordinates: request.weatherCoordinates,
                                          allowLiveWeather: request.liveWeatherEnabled,
                                          holidayRegionCode: request.holidayRegionCode,
                                          occupiedDateCounts: occupiedDateCounts,
                                          occupiedDayHours: occupiedDayHours,
                                          maxShiftsPerDay: 1,
                                          fullDayHoursThreshold: self.fullDayHoursThreshold)

            let factorImportance = self.buildFeatureImportance(features: features)
            let recommendations = self.buildShiftRecommendations(
                workTypes: request.activeWorkTypes,
                features: features,
                currency: request.currency,
                externalFactorsEnabled: request.externalFactorsEnabled,
                weatherCity: request.weatherCity,
                weatherCoordinates: request.weatherCoordinates,
                allowLiveWeather: request.liveWeatherEnabled,
                holidayRegionCode: request.holidayRegionCode,
                perWorkTypeForecast: perWT,
                perWorkTypeWeekdayMultipliers: perWTWeekday,
                occupiedDateCounts: occupiedDateCounts,
                occupiedDayHours: occupiedDayHours,
                upcomingDays: 30,
                maxShiftsPerDay: 1,
                fullDayHoursThreshold: self.fullDayHoursThreshold
            )
            #if DEBUG
            self.validateAnalysisConsistency(
                recommendations: recommendations,
                perWorkTypeForecast: perWT,
                occupiedDateCounts: occupiedDateCounts,
                occupiedDayHours: occupiedDayHours,
                maxShiftsPerDay: 1,
                fullDayHoursThreshold: self.fullDayHoursThreshold
            )
            #endif
            DispatchQueue.main.async {
                self.weekdayHeatmap = wdH
                self.hourlyHeatmap  = hrH
                self.trendPoints    = tp
                self.profile        = bp
                self.forecast       = fc
                self.forecastModelMode = forecastBuild.modelMode
                self.forecastQuality = quality
                self.insights       = ins
                self.featureImportance = factorImportance
                self.shiftRecommendations = recommendations
                self.perWorkTypeForecast = perWT
                self.perWorkTypeWeekdayMultipliers = perWTWeekday
                self.hasEnoughData  = features.count >= self.minShifts
                self.lastUpdated    = Date()
                self.isAnalyzing    = false

                if let pending = self.pendingRequest {
                    self.pendingRequest = nil
                    self.enqueueAnalyze(pending)
                }
            }
        }
    }

    #if DEBUG
    private func validateAnalysisConsistency(
        recommendations: [ShiftRecommendation],
        perWorkTypeForecast: [String:(predicted:Double,confidence:Double,basedOn:Int)],
        occupiedDateCounts: [Date: Int],
        occupiedDayHours: [Date: Double],
        maxShiftsPerDay: Int,
        fullDayHoursThreshold: Double
    ) {
        let calendar = Calendar.current
        for rec in recommendations {
            let day = calendar.startOfDay(for: rec.date)
            let count = occupiedDateCounts[day, default: 0]
            let hours = occupiedDayHours[day, default: 0]
            if count >= maxShiftsPerDay || hours >= fullDayHoursThreshold {
                assertionFailure("AI inconsistency: recommendation generated for occupied/full day \(day)")
                break
            }
        }

        let confidentPredictions = perWorkTypeForecast.values.filter { $0.basedOn >= 2 }.map { $0.predicted }
        if confidentPredictions.count >= 2,
           let minValue = confidentPredictions.min(),
           let maxValue = confidentPredictions.max(),
           abs(maxValue - minValue) < 0.01 {
            assertionFailure("AI inconsistency: per-work-type predictions are unexpectedly identical")
        }
    }
    #endif

    // MARK: Features

    private func buildFeatures(snaps: [(date:Date,amount:Double,tips:Double,hours:Double,rate:Double,type:String,floating:Double)],
                                wtMap: [String:(startHour:Int,hasTips:Bool)]) -> [ShiftFeature] {
        let cal = Calendar.current
        return snaps.compactMap { s in
            guard s.amount > 0 else { return nil }
            let raw = cal.component(.weekday, from: s.date)
            let wd  = raw == 1 ? 7 : raw - 1
            let wt  = wtMap[s.type]
            return ShiftFeature(workTypeName: s.type, weekday: wd,
                                month: cal.component(.month, from: s.date),
                                startHour: wt?.startHour ?? cal.component(.hour, from: s.date),
                                durationHours: s.hours > 0 ? s.hours : 8.0,
                                hasTips: s.tips > 0, actualIncome: s.amount,
                                tipsAmount: s.tips, date: s.date)
        }
    }

    // MARK: Weekday Heatmap

    private func buildWeekdayHeatmap(features: [ShiftFeature]) -> [WeekdayHeatmapRow] {
        let names = localizedWeekdaySymbols()
        var grouped: [Int:[Double]] = [:]
        for f in features { grouped[f.weekday, default:[]].append(f.actualIncome) }
        let maxAvg = grouped.values.map { $0.reduce(0,+)/Double($0.count) }.max() ?? 1.0
        return (1...7).map { wd in
            let arr = grouped[wd] ?? []
            let avg = arr.isEmpty ? 0 : arr.reduce(0,+)/Double(arr.count)
            return WeekdayHeatmapRow(weekday: wd, weekdayName: names[wd-1].capitalized(with: AppLanguage.currentLocale()),
                                     avgIncome: avg, shiftsCount: arr.count,
                                     intensity: maxAvg > 0 ? avg/maxAvg : 0)
        }
    }

    // MARK: Hourly Heatmap

    private func buildHourlyHeatmap(features: [ShiftFeature]) -> [HourlyHeatmapRow] {
        var grouped: [Int:[Double]] = [:]
        for f in features { grouped[f.startHour, default:[]].append(f.actualIncome) }
        let maxAvg = grouped.values.map { $0.reduce(0,+)/Double($0.count) }.max() ?? 1.0
        return grouped.keys.sorted().map { h in
            let arr = grouped[h]!
            let avg = arr.reduce(0,+)/Double(arr.count)
            return HourlyHeatmapRow(hour: h, avgIncome: avg, shiftsCount: arr.count,
                                    intensity: maxAvg > 0 ? avg/maxAvg : 0)
        }
    }

    // MARK: Per-WorkType Forecast (индивидуальный прогноз по типу работы)

    private func buildPerWorkTypeForecast(
        features: [ShiftFeature],
        allFeatures: [ShiftFeature]
    ) -> (predicted: Double, confidence: Double, basedOn: Int) {
        let minForType = 3
        guard !features.isEmpty else {
            return (0, 0, 0)
        }
        // Если для данного типа мало данных — используем только его историю, без общего одинакового фоллбэка
        guard features.count >= minForType else {
            let typeAvg = features.map { $0.actualIncome }.reduce(0, +) / Double(features.count)
            let allAvg = allFeatures.isEmpty ? typeAvg :
                allFeatures.map { $0.actualIncome }.reduce(0,+) / Double(allFeatures.count)
            let blended = typeAvg * 0.7 + allAvg * 0.3
            let conf = min(0.55, Double(features.count) / Double(minForType) * 0.5)
            return (blended, conf, features.count)
        }
        let incs = features.map { $0.actualIncome }
        let avg  = incs.reduce(0,+) / Double(incs.count)
        // EMA с весом 0.3 — сглаженный прогноз
        let ema  = computeEMA(Array(incs.suffix(10)), alpha: 0.3)
        // Линейный тренд — учитываем рост/падение
        let slope = linearSlope(incs)
        let trendAdj = min(max(slope, -avg * 0.15), avg * 0.15) // ограничиваем ±15%
        let predicted = max(0, avg * 0.35 + ema * 0.55 + trendAdj * 0.10)
        let confidence = min(1.0, Double(features.count) / 20.0)
        return (predicted, confidence, features.count)
    }

    private func buildPerWorkTypeWeekdayMultipliers(
        features: [ShiftFeature],
        allFeatures: [ShiftFeature]
    ) -> [Int: Double] {
        guard !allFeatures.isEmpty else { return [:] }
        let globalAvg = allFeatures.map { $0.actualIncome }.reduce(0,+) / Double(allFeatures.count)
        guard globalAvg > 0 else { return [:] }

        var grouped: [Int:[Double]] = [:]
        for f in features {
            grouped[f.weekday, default: []].append(f.actualIncome)
        }
        var multipliers: [Int: Double] = [:]
        for wd in 1...7 {
            if let arr = grouped[wd], !arr.isEmpty {
                let wdAvg = arr.reduce(0,+) / Double(arr.count)
                multipliers[wd] = min(max(wdAvg / globalAvg, 0.55), 1.75)
            }
        }
        return multipliers
    }

    // MARK: Trend (7-day MA + 14-day projection)

    private func buildTrend(iSnaps: [(date:Date,amount:Double,tips:Double,hours:Double,rate:Double,type:String,floating:Double)],
                             eSnaps: [(date:Date,amount:Double,category:String)]) -> [TrendPoint] {
        let cal = Calendar.current
        let today = Date()
        guard let cutoff = cal.date(byAdding: .month, value: -6, to: today) else { return [] }
        var daily: [Date:Double] = [:]
        for s in iSnaps where s.date >= cutoff { daily[cal.startOfDay(for: s.date), default:0] += s.amount }
        for e in eSnaps where e.date >= cutoff  { daily[cal.startOfDay(for: e.date), default:0] -= e.amount }
        let days = daily.keys.sorted()
        guard days.count >= 3 else { return [] }
        let vals = days.map { daily[$0]! }
        var result: [TrendPoint] = []
        for (i, day) in days.enumerated() {
            let ws = max(0, i-6)
            let ma = Array(vals[ws...i]).reduce(0,+) / Double(i - ws + 1)
            result.append(TrendPoint(date: day, value: vals[i], movingAverage: ma, isPredicted: false))
        }
        let slope = linearSlope(Array(vals.suffix(min(30,vals.count))))
        let lastMA = result.last?.movingAverage ?? 0
        for i in 1...14 {
            guard let fd = cal.date(byAdding: .day, value: i, to: days.last ?? today) else { continue }
            let pred = max(0, lastMA + slope * Double(i))
            result.append(TrendPoint(date: fd, value: pred, movingAverage: pred, isPredicted: true))
        }
        return result
    }

    // MARK: Behavioral Profile

    private func buildProfile(features: [ShiftFeature]) -> BehavioralProfile {
        guard !features.isEmpty else { return BehavioralProfile() }
        let incs = features.map { $0.actualIncome }
        let avg  = incs.reduce(0,+)/Double(incs.count)
        let abv  = features.filter { $0.actualIncome >= avg }
        let optDur = abv.isEmpty ? 8.0 : abv.reduce(0){$0+$1.durationHours}/Double(abv.count)
        var wdM:[Int:[Double]]=[:]; for f in features { wdM[f.weekday,default:[]].append(f.actualIncome) }
        let bestWD = wdM.map{(wd:$0.key,avg:$0.value.reduce(0,+)/Double($0.value.count))}.sorted{$0.avg>$1.avg}.prefix(3).map{$0.wd}.sorted()
        var hrM:[Int:[Double]]=[:]; for f in features { hrM[f.startHour,default:[]].append(f.actualIncome) }
        let bestHr = hrM.map{(h:$0.key,avg:$0.value.reduce(0,+)/Double($0.value.count))}.sorted{$0.avg>$1.avg}.prefix(3).map{$0.h}.sorted()
        let tips   = features.reduce(0){$0+$1.tipsAmount}
        let total  = features.reduce(0){$0+$1.actualIncome}
        let tipShare = total>0 ? tips/total : 0
        let std    = standardDev(incs)
        let cv     = avg>0 ? std/avg : 1.0
        let cons   = max(0,min(1.0,1.0-cv))
        let growth = computeGrowth(features: features)
        return BehavioralProfile(optimalShiftDuration: optDur, bestWeekdays: bestWD,
                                  bestStartHours: bestHr, tipsContribution: tipShare,
                                  consistencyScore: cons, growthRate: growth)
    }

    // MARK: Forecast

    private func buildForecast(features: [ShiftFeature],
                                iSnaps:[(date:Date,amount:Double,tips:Double,hours:Double,rate:Double,type:String,floating:Double)],
                                eSnaps:[(date:Date,amount:Double,category:String)],
                                goals:[(target:Double,current:Double,active:Bool)],
                                plannedShifts: [PlannedSnap],
                                activeWorkTypes: [WorkType],
                                externalFactorsEnabled: Bool,
                                weatherCity: String,
                                weatherCoordinates: (latitude: Double, longitude: Double)?,
                                allowLiveWeather: Bool,
                                holidayRegionCode: String) -> (forecast: AIForecast, modelMode: ForecastModelMode) {
        guard features.count >= minShifts else {
            return (
                forecast: AIForecast(confidence: Double(features.count)/Double(minShifts), basedOnShifts: features.count),
                modelMode: .standard
            )
        }
        let cal = Calendar.current; let today = Date()
        let incs = features.map{$0.actualIncome}
        let avg  = incs.reduce(0,+)/Double(incs.count)
        let ema  = computeEMA(Array(incs.suffix(12)), alpha: 0.3)
        var shiftPred = avg*0.4 + ema*0.6
        var modelMode: ForecastModelMode = .standard

        let curM  = monthInc(snaps: iSnaps, cal: cal, date: today)
        let progressSnapshot = currentProgressSnapshot(snaps: iSnaps, calendar: cal, today: today)
        var monthFC = forecastCurrentMonthIncome(iSnaps: iSnaps, features: features, calendar: cal, today: today)

        if ProManager.shared.canUse(.advancedML), features.count >= 12 {
            if let advancedShift = advancedShiftPrediction(features: features, calendar: cal, referenceDate: today) {
                shiftPred = max(0, shiftPred * 0.38 + advancedShift.value * 0.62)
                modelMode = advancedShift.mode
            }
            let remainingShifts = estimatedRemainingShiftsInMonth(features: features, calendar: cal, from: today)
            let monthlyFromShift = curM + shiftPred * remainingShifts
            monthFC = max(monthFC, monthFC * 0.58 + monthlyFromShift * 0.42)
        }
        let hasCurrentProgressComparison =
            progressSnapshot.elapsedDays >= 3 &&
            progressSnapshot.currentShiftCount >= 2 &&
            progressSnapshot.previousShiftCount >= 2 &&
            progressSnapshot.previousIncome > 0
        let currentProgressChange = hasCurrentProgressComparison
            ? ((progressSnapshot.currentIncome / progressSnapshot.previousIncome) - 1.0) * 100.0
            : 0.0

        let comparison = plannedShiftWindowComparison(
            iSnaps: iSnaps,
            plannedShifts: plannedShifts,
            activeWorkTypes: activeWorkTypes,
            calendar: cal,
            today: today,
            externalFactorsEnabled: externalFactorsEnabled,
            weatherCity: weatherCity,
            weatherCoordinates: weatherCoordinates,
            allowLiveWeather: allowLiveWeather,
            holidayRegionCode: holidayRegionCode
        )
        let hasForecastEndComparison = comparison.hasComparison
        let forecastEndMonthChange = comparison.changePercent
        let med   = sortedMedian(incs)
        let hiP   = Double(incs.filter{$0>=med*1.2}.count)/Double(incs.count)

        let active = goals.filter{$0.active}
        var goalP = 0.0
        if !active.isEmpty {
            let tgt = active.reduce(0){$0+$1.target}
            let cur = active.reduce(0){$0+$1.current}
            let net = iSnaps.reduce(0){$0+$1.amount} - eSnaps.reduce(0){$0+$1.amount}
            let eff = cur + max(net,0)
            let r   = max(tgt-eff,0)
            goalP   = r<=0 ? 1.0 : min(1.0,max(0,1.0/(1.0+(r/max(monthFC,1))*0.25)))
        }

        var anomScore = 0.0; var anomDir = 0
        if let last = features.last, features.count >= 3 {
            let std = standardDev(incs)
            let z   = std>0 ? (last.actualIncome - avg)/std : 0
            anomScore = min(1.0,abs(z)/3.0); anomDir = z>0 ? 1 : -1
        }
        return (
            forecast: AIForecast(
                shiftPrediction: shiftPred,
                monthForecast: monthFC,
                goalProbability: goalP,
                highIncomeProbability: hiP,
                confidence: min(1.0,Double(features.count)/30.0),
                basedOnShifts: features.count,
                currentProgressChange: currentProgressChange,
                forecastEndMonthChange: forecastEndMonthChange,
                hasCurrentProgressComparison: hasCurrentProgressComparison,
                hasForecastEndComparison: hasForecastEndComparison,
                currentProgressDays: progressSnapshot.elapsedDays,
                forecastEndComparisonWindow: comparison.windowSize,
                forecastEndComparisonMessage: comparison.message,
                forecastEndComparisonExplanation: comparison.explanation,
                monthOverMonthChange: currentProgressChange,
                anomalyScore: anomScore,
                anomalyDirection: anomDir
            ),
            modelMode: modelMode
        )
    }

    // MARK: Forecast Quality (walk-forward backtest)

    private func buildForecastQuality(
        features: [ShiftFeature],
        iSnaps:[(date:Date,amount:Double,tips:Double,hours:Double,rate:Double,type:String,floating:Double)],
        eSnaps:[(date:Date,amount:Double,category:String)]
    ) -> AIForecastQuality {
        let sorted = features.sorted { $0.date < $1.date }
        guard sorted.count >= 10 else { return AIForecastQuality() }

        let minTrainCount = max(minShifts, 8)
        var absErrors: [Double] = []
        var sqErrors: [Double] = []
        var pctErrors: [Double] = []

        for idx in minTrainCount..<sorted.count {
            let train = Array(sorted.prefix(idx))
            let target = sorted[idx]
            let predicted = walkForwardShiftPrediction(target: target, train: train)
            guard predicted.isFinite else { continue }

            let actual = max(target.actualIncome, 0)
            let absErr = abs(predicted - actual)
            absErrors.append(absErr)
            sqErrors.append(absErr * absErr)
            if actual > 0.001 {
                pctErrors.append(absErr / actual)
            }
        }

        var result = AIForecastQuality()
        if !absErrors.isEmpty {
            let n = Double(absErrors.count)
            result.mae = absErrors.reduce(0, +) / n
            result.rmse = sqrt(sqErrors.reduce(0, +) / n)
            result.mape = pctErrors.isEmpty ? 0 : pctErrors.reduce(0, +) / Double(pctErrors.count)
            result.sampleCount = absErrors.count
        }

        let monthlyErrors = monthlyNetBacktestErrors(iSnaps: iSnaps, eSnaps: eSnaps)
        if !monthlyErrors.isEmpty {
            result.monthlyMAE = monthlyErrors.reduce(0, +) / Double(monthlyErrors.count)
            result.monthlySampleCount = monthlyErrors.count
        }
        return result
    }

    private func walkForwardShiftPrediction(target: ShiftFeature, train: [ShiftFeature]) -> Double {
        guard !train.isEmpty else { return 0 }

        let typeTrain = train.filter { $0.workTypeName == target.workTypeName }
        if typeTrain.count >= 2 {
            let base = buildPerWorkTypeForecast(features: typeTrain, allFeatures: train)
            if base.basedOn >= 2 {
                let multipliers = buildPerWorkTypeWeekdayMultipliers(features: typeTrain, allFeatures: train)
                let weekdayMultiplier = multipliers[target.weekday] ?? 1.0
                let normalizedDuration = min(max(target.durationHours, 3.0), 14.0)
                let durationMultiplier = 0.88 + (normalizedDuration / 14.0) * 0.24
                return max(0, base.predicted * weekdayMultiplier * durationMultiplier)
            }
        }

        // Fallback: EMA + профиль дня недели без разделения по типам.
        let incomes = train.map(\.actualIncome)
        let ema = computeEMA(Array(incomes.suffix(12)), alpha: 0.33)
        let weekdayValues = train.filter { $0.weekday == target.weekday }.map(\.actualIncome)
        let weekdayAvg = weekdayValues.isEmpty
            ? (incomes.reduce(0, +) / Double(max(incomes.count, 1)))
            : (weekdayValues.reduce(0, +) / Double(weekdayValues.count))
        let blended = weekdayAvg * 0.56 + ema * 0.44
        return max(0, blended)
    }

    private func monthlyNetBacktestErrors(
        iSnaps:[(date:Date,amount:Double,tips:Double,hours:Double,rate:Double,type:String,floating:Double)],
        eSnaps:[(date:Date,amount:Double,category:String)]
    ) -> [Double] {
        let calendar = Calendar.current

        func monthStart(_ date: Date) -> Date {
            calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        }

        var incomeByMonth: [Date: Double] = [:]
        for snap in iSnaps {
            incomeByMonth[monthStart(snap.date), default: 0] += snap.amount
        }

        var expenseByMonth: [Date: Double] = [:]
        for snap in eSnaps {
            expenseByMonth[monthStart(snap.date), default: 0] += snap.amount
        }

        let monthKeys = Array(Set(incomeByMonth.keys).union(expenseByMonth.keys)).sorted()
        guard monthKeys.count >= 4 else { return [] }

        let netSeries: [Double] = monthKeys.map { key in
            incomeByMonth[key, default: 0] - expenseByMonth[key, default: 0]
        }

        var errors: [Double] = []
        for index in 3..<netSeries.count {
            let history = Array(netSeries[..<index])
            guard !history.isEmpty else { continue }
            let ema = computeEMA(history, alpha: 0.5)
            let slope = linearSlope(Array(history.suffix(min(history.count, 6))))
            let predicted = ema + slope
            let actual = netSeries[index]
            errors.append(abs(predicted - actual))
        }
        return errors
    }

    private func advancedShiftPrediction(features: [ShiftFeature],
                                         calendar: Calendar,
                                         referenceDate: Date) -> (value: Double, mode: ForecastModelMode)? {
        guard features.count >= 12 else { return nil }

        let ridgeBaseline = ridgeShiftPrediction(features: features, calendar: calendar, referenceDate: referenceDate)
        guard features.count >= 18 else {
            if let ridgeBaseline {
                return (max(0, ridgeBaseline), .standard)
            }
            return nil
        }

        let sorted = features.sorted { $0.date < $1.date }
        guard let latestDate = sorted.last?.date else {
            if let ridgeBaseline {
                return (max(0, ridgeBaseline), .standard)
            }
            return nil
        }

        let workTypeList = Array(Set(sorted.map(\.workTypeName))).sorted()
        let workTypeDenominator = Double(max(workTypeList.count - 1, 1))
        let workTypeEncoding = Dictionary(uniqueKeysWithValues: workTypeList.enumerated().map { pair in
            (pair.element, Double(pair.offset) / workTypeDenominator)
        })

        let samples: [AdvancedMLSample] = sorted.map { feature in
            let recencyDays = max(0, calendar.dateComponents([.day], from: feature.date, to: latestDate).day ?? 0)
            let tipsShare = clampUnit(feature.tipsAmount / max(feature.actualIncome, 1))
            return AdvancedMLSample(
                vector: advancedModelVector(
                    weekday: feature.weekday,
                    month: feature.month,
                    startHour: feature.startHour,
                    duration: feature.durationHours,
                    hasTips: feature.hasTips,
                    tipsShare: tipsShare,
                    recencyDays: recencyDays,
                    workTypeName: feature.workTypeName,
                    workTypeEncoding: workTypeEncoding
                ),
                target: max(0, feature.actualIncome),
                date: feature.date
            )
        }

        guard let featureCount = samples.first?.vector.count, featureCount > 0 else {
            if let ridgeBaseline {
                return (max(0, ridgeBaseline), .standard)
            }
            return nil
        }
        let validationCount = max(3, min(10, samples.count / 5))
        guard samples.count - validationCount >= 12 else {
            if let ridgeBaseline {
                return (max(0, ridgeBaseline), .standard)
            }
            return nil
        }

        let train = Array(samples.dropLast(validationCount))
        let validation = Array(samples.suffix(validationCount))
        let trainX = train.map(\.vector)
        let trainY = train.map(\.target)
        let validationX = validation.map(\.vector)
        let validationY = validation.map(\.target)

        let rfFeatureSubset = max(2, Int(sqrt(Double(featureCount)).rounded(.up)))
        let rfTreeCount = min(24, max(12, train.count / 2))
        let gbmEstimators = min(28, max(10, train.count / 3))

        let rfModel = trainRandomForest(
            samples: trainX,
            targets: trainY,
            treeCount: rfTreeCount,
            maxDepth: 5,
            minSamplesLeaf: 3,
            featureSubsample: rfFeatureSubset
        )
        let gbmModel = trainGradientBoosting(
            samples: trainX,
            targets: trainY,
            estimatorCount: gbmEstimators,
            learningRate: 0.08,
            maxDepth: 2,
            minSamplesLeaf: 4
        )

        guard rfModel != nil || gbmModel != nil else {
            if let ridgeBaseline {
                return (max(0, ridgeBaseline), .standard)
            }
            return nil
        }

        let recentWindow = Array(sorted.suffix(18))
        let avgStart = recentWindow.map { Double($0.startHour) }.reduce(0, +) / Double(max(recentWindow.count, 1))
        let avgDuration = recentWindow.map { $0.durationHours }.reduce(0, +) / Double(max(recentWindow.count, 1))
        let avgTipsShare = recentWindow.map { clampUnit($0.tipsAmount / max($0.actualIncome, 1)) }.reduce(0, +) / Double(max(recentWindow.count, 1))
        let tipsPresence = Double(recentWindow.filter(\.hasTips).count) / Double(max(recentWindow.count, 1))
        let targetWorkType = dominantWorkType(in: recentWindow)
        let targetVector = advancedModelVector(
            weekday: weekdayMon(from: referenceDate, calendar: calendar),
            month: calendar.component(.month, from: referenceDate),
            startHour: Int(round(avgStart)),
            duration: max(avgDuration, 1),
            hasTips: tipsPresence >= 0.5,
            tipsShare: avgTipsShare,
            recencyDays: 0,
            workTypeName: targetWorkType,
            workTypeEncoding: workTypeEncoding
        )

        var modelPredictions: [(target: Double, validation: [Double], mae: Double)] = []

        if let model = rfModel {
            let validationPred = validationX.map { predictRandomForest(model, vector: $0) }
            let mae = meanAbsoluteError(predicted: validationPred, actual: validationY)
            let pred = predictRandomForest(model, vector: targetVector)
            if pred.isFinite, mae.isFinite {
                modelPredictions.append((max(0, pred), validationPred.map { max(0, $0) }, max(mae, 1e-6)))
            }
        }

        if let model = gbmModel {
            let validationPred = validationX.map { predictGradientBoosting(model, vector: $0) }
            let mae = meanAbsoluteError(predicted: validationPred, actual: validationY)
            let pred = predictGradientBoosting(model, vector: targetVector)
            if pred.isFinite, mae.isFinite {
                modelPredictions.append((max(0, pred), validationPred.map { max(0, $0) }, max(mae, 1e-6)))
            }
        }

        guard !modelPredictions.isEmpty else {
            if let ridgeBaseline {
                return (max(0, ridgeBaseline), .standard)
            }
            return nil
        }

        let inverseErrors = modelPredictions.map { 1.0 / $0.mae }
        let inverseSum = inverseErrors.reduce(0, +)
        let normalizedWeights: [Double] = {
            guard inverseSum > 0 else {
                return Array(repeating: 1.0 / Double(modelPredictions.count), count: modelPredictions.count)
            }
            return inverseErrors.map { $0 / inverseSum }
        }()

        let ensemble = zip(modelPredictions, normalizedWeights).reduce(0.0) { partial, tuple in
            partial + tuple.0.target * tuple.1
        }
        let ensembleValidation = validationX.indices.map { index in
            zip(modelPredictions, normalizedWeights).reduce(0.0) { partial, tuple in
                partial + tuple.0.validation[index] * tuple.1
            }
        }
        let ensembleMAE = meanAbsoluteError(predicted: ensembleValidation, actual: validationY)

        var ridgeValidationMAE = Double.infinity
        if let ridgeBaseline {
            let ridgeCoefficients = ridgeRegressionCoefficients(
                samples: trainX,
                targets: trainY,
                lambda: 0.2,
                learningRate: 0.07,
                iterations: 260
            )
            if !ridgeCoefficients.isEmpty {
                let ridgeValidation = validationX.map { max(0, dot(ridgeCoefficients, $0)) }
                ridgeValidationMAE = meanAbsoluteError(predicted: ridgeValidation, actual: validationY)
            } else {
                ridgeValidationMAE = meanAbsoluteError(
                    predicted: Array(repeating: max(0, ridgeBaseline), count: validationY.count),
                    actual: validationY
                )
            }
        }

        if let ridgeBaseline,
           ridgeValidationMAE.isFinite,
           ensembleMAE.isFinite,
           ensembleMAE > ridgeValidationMAE * 1.08 {
            return (max(0, ridgeBaseline), .standard)
        }

        if let ridgeBaseline {
            let baseWeight = min(0.85, max(0.50, 0.50 + Double(features.count - 18) / 80.0))
            let qualityPenalty: Double = {
                guard ridgeValidationMAE.isFinite, ensembleMAE.isFinite else { return 1.0 }
                let ratio = ensembleMAE / max(ridgeValidationMAE, 1e-6)
                // If ensemble quality is close to ridge, reduce its influence.
                return min(1.0, max(0.35, 1.15 - ratio))
            }()
            let mlWeight = min(0.88, max(0.35, baseWeight * qualityPenalty))
            return (max(0, ensemble * mlWeight + ridgeBaseline * (1 - mlWeight)), .blended)
        }
        return (max(0, ensemble), .enhanced)
    }

    private func ridgeShiftPrediction(features: [ShiftFeature],
                                      calendar: Calendar,
                                      referenceDate: Date) -> Double? {
        guard features.count >= 12 else { return nil }

        let latestDate = features.map(\.date).max() ?? referenceDate
        let recent = features.sorted { $0.date < $1.date }
        let lastWindow = Array(recent.suffix(14))
        let avgStart = lastWindow.map { Double($0.startHour) }.reduce(0, +) / Double(max(lastWindow.count, 1))
        let avgDuration = lastWindow.map { $0.durationHours }.reduce(0, +) / Double(max(lastWindow.count, 1))
        let tipsRatio = Double(lastWindow.filter(\.hasTips).count) / Double(max(lastWindow.count, 1))
        let avgTips = lastWindow.map { $0.tipsAmount }.reduce(0, +) / Double(max(lastWindow.count, 1))

        func makeVector(_ feature: ShiftFeature) -> [Double] {
            let weekday = Double(feature.weekday) / 7.0
            let month = Double(feature.month) / 12.0
            let start = Double(feature.startHour) / 24.0
            let duration = min(max(feature.durationHours, 0), 16) / 16.0
            let hasTips = feature.hasTips ? 1.0 : 0.0
            let tips = min(max(feature.tipsAmount / max(feature.actualIncome, 1), 0), 1)
            let recencyDays = max(0, calendar.dateComponents([.day], from: feature.date, to: latestDate).day ?? 0)
            let recency = exp(-Double(recencyDays) / 120.0)
            return [
                1,
                weekday, weekday * weekday,
                month,
                start, start * start,
                duration, duration * duration,
                hasTips,
                tips,
                weekday * duration,
                start * duration,
                recency
            ]
        }

        let x = features.map(makeVector)
        let y = features.map(\.actualIncome)
        let coefficients = ridgeRegressionCoefficients(
            samples: x,
            targets: y,
            lambda: 0.18,
            learningRate: 0.08,
            iterations: 420
        )
        guard !coefficients.isEmpty else { return nil }

        let targetFeature = ShiftFeature(
            workTypeName: lastWindow.last?.workTypeName ?? "",
            weekday: weekdayMon(from: referenceDate, calendar: calendar),
            month: calendar.component(.month, from: referenceDate),
            startHour: Int(round(avgStart)),
            durationHours: max(avgDuration, 1),
            hasTips: tipsRatio >= 0.5,
            actualIncome: 0,
            tipsAmount: avgTips,
            date: referenceDate
        )
        let prediction = dot(coefficients, makeVector(targetFeature))
        return max(0, prediction)
    }

    private func advancedModelVector(
        weekday: Int,
        month: Int,
        startHour: Int,
        duration: Double,
        hasTips: Bool,
        tipsShare: Double,
        recencyDays: Int,
        workTypeName: String,
        workTypeEncoding: [String: Double]
    ) -> [Double] {
        let weekdayNorm = clampUnit(Double(weekday) / 7.0)
        let monthNorm = clampUnit(Double(month) / 12.0)
        let monthAngle = monthNorm * 2 * .pi
        let startNorm = clampUnit(Double(startHour) / 24.0)
        let durationNorm = clampUnit(min(max(duration, 1), 16) / 16.0)
        let tipsNorm = clampUnit(tipsShare)
        let recency = exp(-Double(max(recencyDays, 0)) / 90.0)
        let workTypeNorm = clampUnit(workTypeEncoding[workTypeName] ?? 0)

        return [
            1.0,
            weekdayNorm,
            monthNorm,
            sin(monthAngle),
            cos(monthAngle),
            startNorm,
            durationNorm,
            hasTips ? 1.0 : 0.0,
            tipsNorm,
            weekdayNorm * durationNorm,
            startNorm * durationNorm,
            recency,
            workTypeNorm,
            workTypeNorm * weekdayNorm
        ]
    }

    private func dominantWorkType(in features: [ShiftFeature]) -> String {
        guard !features.isEmpty else { return "" }
        var stats: [String: (count: Int, income: Double)] = [:]
        for feature in features {
            var value = stats[feature.workTypeName] ?? (0, 0)
            value.count += 1
            value.income += feature.actualIncome
            stats[feature.workTypeName] = value
        }
        return stats.max { lhs, rhs in
            if lhs.value.count == rhs.value.count {
                return lhs.value.income < rhs.value.income
            }
            return lhs.value.count < rhs.value.count
        }?.key ?? (features.last?.workTypeName ?? "")
    }

    private func clampUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func meanAbsoluteError(predicted: [Double], actual: [Double]) -> Double {
        guard predicted.count == actual.count, !predicted.isEmpty else { return .infinity }
        let sum = zip(predicted, actual).reduce(0.0) { partial, pair in
            partial + abs(pair.0 - pair.1)
        }
        return sum / Double(predicted.count)
    }

    private func trainRandomForest(
        samples: [[Double]],
        targets: [Double],
        treeCount: Int,
        maxDepth: Int,
        minSamplesLeaf: Int,
        featureSubsample: Int
    ) -> RandomForestModel? {
        guard !samples.isEmpty,
              samples.count == targets.count,
              let featureCount = samples.first?.count,
              featureCount > 0
        else { return nil }

        var forest: RandomForestModel = []
        forest.reserveCapacity(max(treeCount, 1))
        var masterRNG = DeterministicRNG(seed: UInt64(samples.count * 4099 + treeCount * 97 + featureSubsample * 13))

        for _ in 0..<max(treeCount, 1) {
            var bootSamples: [[Double]] = []
            var bootTargets: [Double] = []
            bootSamples.reserveCapacity(samples.count)
            bootTargets.reserveCapacity(samples.count)
            for _ in 0..<samples.count {
                let index = masterRNG.nextInt(upperBound: samples.count)
                bootSamples.append(samples[index])
                bootTargets.append(targets[index])
            }
            var treeRNG = DeterministicRNG(seed: masterRNG.nextUInt64())
            if let tree = trainRegressionTree(
                samples: bootSamples,
                targets: bootTargets,
                maxDepth: maxDepth,
                minSamplesLeaf: minSamplesLeaf,
                featureSubsample: featureSubsample,
                rng: &treeRNG
            ) {
                forest.append(tree)
            }
        }
        return forest.isEmpty ? nil : forest
    }

    private func trainGradientBoosting(
        samples: [[Double]],
        targets: [Double],
        estimatorCount: Int,
        learningRate: Double,
        maxDepth: Int,
        minSamplesLeaf: Int
    ) -> GradientBoostingModel? {
        guard !samples.isEmpty,
              samples.count == targets.count,
              samples.first?.isEmpty == false
        else { return nil }

        let bias = targets.reduce(0, +) / Double(targets.count)
        var predictions = Array(repeating: bias, count: targets.count)
        var trees: [RegressionTreeNode] = []
        var steps: [Double] = []

        var seedRNG = DeterministicRNG(seed: UInt64(samples.count * 2089 + estimatorCount * 31 + maxDepth * 11))
        for _ in 0..<max(estimatorCount, 1) {
            let residuals = zip(targets, predictions).map { $0 - $1 }
            var treeRNG = DeterministicRNG(seed: seedRNG.nextUInt64())
            guard let tree = trainRegressionTree(
                samples: samples,
                targets: residuals,
                maxDepth: maxDepth,
                minSamplesLeaf: minSamplesLeaf,
                featureSubsample: nil,
                rng: &treeRNG
            ) else { continue }

            let treeOutputs = samples.map { predictTree(tree, vector: $0) }
            let numerator = zip(residuals, treeOutputs).reduce(0.0) { partial, pair in
                partial + pair.0 * pair.1
            }
            let denominator = treeOutputs.reduce(0.0) { $0 + $1 * $1 }
            guard denominator > 1e-9 else { continue }

            let step = learningRate * (numerator / denominator)
            guard step.isFinite, abs(step) >= 1e-5 else { continue }

            for index in predictions.indices {
                predictions[index] += step * treeOutputs[index]
            }
            trees.append(tree)
            steps.append(step)
        }

        guard !trees.isEmpty else { return nil }
        return GradientBoostingModel(bias: bias, trees: trees, stepSizes: steps)
    }

    private func trainRegressionTree(
        samples: [[Double]],
        targets: [Double],
        maxDepth: Int,
        minSamplesLeaf: Int,
        featureSubsample: Int?,
        rng: inout DeterministicRNG
    ) -> RegressionTreeNode? {
        guard !samples.isEmpty,
              samples.count == targets.count,
              let featureCount = samples.first?.count,
              featureCount > 0
        else { return nil }

        return buildRegressionTreeNode(
            sampleIndices: Array(samples.indices),
            samples: samples,
            targets: targets,
            depth: 0,
            maxDepth: maxDepth,
            minSamplesLeaf: max(minSamplesLeaf, 1),
            featureCount: featureCount,
            featureSubsample: featureSubsample,
            rng: &rng
        )
    }

    private func buildRegressionTreeNode(
        sampleIndices: [Int],
        samples: [[Double]],
        targets: [Double],
        depth: Int,
        maxDepth: Int,
        minSamplesLeaf: Int,
        featureCount: Int,
        featureSubsample: Int?,
        rng: inout DeterministicRNG
    ) -> RegressionTreeNode {
        guard !sampleIndices.isEmpty else { return .leaf(0) }

        let mean = sampleIndices.reduce(0.0) { $0 + targets[$1] } / Double(sampleIndices.count)
        let variance = sampleIndices.reduce(0.0) { partial, index in
            let diff = targets[index] - mean
            return partial + diff * diff
        } / Double(sampleIndices.count)

        let shouldStop = depth >= maxDepth
            || sampleIndices.count <= minSamplesLeaf * 2
            || variance < 1e-6
        if shouldStop {
            return .leaf(mean)
        }

        let selectedFeatures: [Int]
        if let subset = featureSubsample {
            selectedFeatures = randomFeatureSubset(
                featureCount: featureCount,
                subsetSize: subset,
                rng: &rng
            )
        } else {
            selectedFeatures = Array(0..<featureCount)
        }

        guard let split = bestRegressionSplit(
            sampleIndices: sampleIndices,
            samples: samples,
            targets: targets,
            featureIndices: selectedFeatures,
            minSamplesLeaf: minSamplesLeaf
        ) else {
            return .leaf(mean)
        }

        let left = buildRegressionTreeNode(
            sampleIndices: split.leftIndices,
            samples: samples,
            targets: targets,
            depth: depth + 1,
            maxDepth: maxDepth,
            minSamplesLeaf: minSamplesLeaf,
            featureCount: featureCount,
            featureSubsample: featureSubsample,
            rng: &rng
        )
        let right = buildRegressionTreeNode(
            sampleIndices: split.rightIndices,
            samples: samples,
            targets: targets,
            depth: depth + 1,
            maxDepth: maxDepth,
            minSamplesLeaf: minSamplesLeaf,
            featureCount: featureCount,
            featureSubsample: featureSubsample,
            rng: &rng
        )

        return .split(feature: split.feature, threshold: split.threshold, left: left, right: right)
    }

    private func bestRegressionSplit(
        sampleIndices: [Int],
        samples: [[Double]],
        targets: [Double],
        featureIndices: [Int],
        minSamplesLeaf: Int
    ) -> (feature: Int, threshold: Double, leftIndices: [Int], rightIndices: [Int])? {
        guard sampleIndices.count >= minSamplesLeaf * 2 else { return nil }

        var bestFeature = -1
        var bestThreshold = 0.0
        var bestScore = Double.infinity

        for feature in featureIndices {
            let ordered = sampleIndices.sorted { samples[$0][feature] < samples[$1][feature] }
            guard ordered.count >= minSamplesLeaf * 2 else { continue }

            let orderedValues = ordered.map { samples[$0][feature] }
            let orderedTargets = ordered.map { targets[$0] }
            let totalCount = ordered.count

            var prefixSum = Array(repeating: 0.0, count: totalCount)
            var prefixSq = Array(repeating: 0.0, count: totalCount)
            for index in 0..<totalCount {
                let value = orderedTargets[index]
                prefixSum[index] = value + (index > 0 ? prefixSum[index - 1] : 0)
                prefixSq[index] = value * value + (index > 0 ? prefixSq[index - 1] : 0)
            }

            let totalSum = prefixSum[totalCount - 1]
            let totalSq = prefixSq[totalCount - 1]

            for splitIndex in (minSamplesLeaf - 1)..<(totalCount - minSamplesLeaf) {
                let leftValue = orderedValues[splitIndex]
                let rightValue = orderedValues[splitIndex + 1]
                if leftValue == rightValue { continue }

                let leftCount = splitIndex + 1
                let rightCount = totalCount - leftCount

                let leftSum = prefixSum[splitIndex]
                let leftSq = prefixSq[splitIndex]
                let rightSum = totalSum - leftSum
                let rightSq = totalSq - leftSq

                let leftSSE = max(0, leftSq - (leftSum * leftSum / Double(leftCount)))
                let rightSSE = max(0, rightSq - (rightSum * rightSum / Double(rightCount)))
                let score = leftSSE + rightSSE

                if score < bestScore {
                    bestScore = score
                    bestFeature = feature
                    bestThreshold = (leftValue + rightValue) / 2.0
                }
            }
        }

        guard bestFeature >= 0 else { return nil }
        let leftIndices = sampleIndices.filter { samples[$0][bestFeature] <= bestThreshold }
        let rightIndices = sampleIndices.filter { samples[$0][bestFeature] > bestThreshold }
        guard leftIndices.count >= minSamplesLeaf, rightIndices.count >= minSamplesLeaf else { return nil }

        return (bestFeature, bestThreshold, leftIndices, rightIndices)
    }

    private func randomFeatureSubset(
        featureCount: Int,
        subsetSize: Int,
        rng: inout DeterministicRNG
    ) -> [Int] {
        guard featureCount > 0 else { return [] }
        let required = max(1, min(subsetSize, featureCount))
        if required >= featureCount {
            return Array(0..<featureCount)
        }

        var indices = Array(0..<featureCount)
        for i in 0..<required {
            let j = i + rng.nextInt(upperBound: featureCount - i)
            if i != j {
                indices.swapAt(i, j)
            }
        }
        return Array(indices.prefix(required))
    }

    private func predictTree(_ node: RegressionTreeNode, vector: [Double]) -> Double {
        switch node {
        case .leaf(let value):
            return value
        case .split(let feature, let threshold, let left, let right):
            guard feature < vector.count else { return 0 }
            if vector[feature] <= threshold {
                return predictTree(left, vector: vector)
            } else {
                return predictTree(right, vector: vector)
            }
        }
    }

    private func predictRandomForest(_ model: RandomForestModel, vector: [Double]) -> Double {
        guard !model.isEmpty else { return 0 }
        let total = model.reduce(0.0) { partial, tree in
            partial + predictTree(tree, vector: vector)
        }
        return total / Double(model.count)
    }

    private func predictGradientBoosting(_ model: GradientBoostingModel, vector: [Double]) -> Double {
        var prediction = model.bias
        for (index, tree) in model.trees.enumerated() {
            let step = index < model.stepSizes.count ? model.stepSizes[index] : 0
            prediction += step * predictTree(tree, vector: vector)
        }
        return prediction
    }

    private func estimatedRemainingShiftsInMonth(features: [ShiftFeature],
                                                 calendar: Calendar,
                                                 from referenceDate: Date) -> Double {
        guard let monthRange = calendar.range(of: .day, in: .month, for: referenceDate) else { return 0 }
        let currentDay = calendar.component(.day, from: referenceDate)
        let daysLeft = max(0, monthRange.count - currentDay)
        guard daysLeft > 0 else { return 0 }

        let uniqueDays = Set(features.map { calendar.startOfDay(for: $0.date) })
        let weeklyStats = weeklyActivityStats(days: Array(uniqueDays), calendar: calendar)
        let weeklyAverage = weeklyStats.bucketCount > 0 ? weeklyStats.average : 4.5
        let projected = weeklyAverage / 7.0 * Double(daysLeft)
        return max(0, projected)
    }

    private func ridgeRegressionCoefficients(
        samples: [[Double]],
        targets: [Double],
        lambda: Double,
        learningRate: Double,
        iterations: Int
    ) -> [Double] {
        guard let featureCount = samples.first?.count,
              !samples.isEmpty,
              samples.count == targets.count
        else { return [] }

        var weights = Array(repeating: 0.0, count: featureCount)
        let n = Double(samples.count)
        let lr = max(learningRate, 0.001)
        let reg = max(lambda, 0)

        for _ in 0..<max(iterations, 60) {
            var gradient = Array(repeating: 0.0, count: featureCount)
            for i in 0..<samples.count {
                let prediction = dot(weights, samples[i])
                let error = prediction - targets[i]
                for j in 0..<featureCount {
                    gradient[j] += (2.0 / n) * error * samples[i][j]
                }
            }
            for j in 1..<featureCount {
                gradient[j] += 2 * reg * weights[j]
            }
            for j in 0..<featureCount {
                weights[j] -= lr * gradient[j]
            }
        }
        return weights
    }

    private func dot(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count else { return 0 }
        return zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
    }

    // MARK: Insights

    private func buildInsights(features: [ShiftFeature], fc: AIForecast,
                                wdH: [WeekdayHeatmapRow], bp: BehavioralProfile,
                                currency: String,
                                goals: [(target:Double,current:Double,active:Bool)],
                                externalFactorsEnabled: Bool,
                                weatherCity: String,
                                weatherCoordinates: (latitude: Double, longitude: Double)?,
                                allowLiveWeather: Bool,
                                holidayRegionCode: String,
                                occupiedDateCounts: [Date: Int] = [:],
                                occupiedDayHours: [Date: Double] = [:],
                                maxShiftsPerDay: Int = 1,
                                fullDayHoursThreshold: Double = 9.0) -> [AIInsight] {
        var list: [AIInsight] = []
        guard features.count >= minShifts else {
            list.append(AIInsight(type:.warning,
                                   title: NSLocalizedString("Нужно больше данных", comment: "AI insight title: not enough data"),
                                   body: String(format: NSLocalizedString("Добавьте ещё %d смен для запуска полного AI-анализа.", comment: "AI insight body: need more shifts"), minShifts - features.count),
                                   impact:0, confidence:1, icon:"brain.head.profile",
                                   accentColor:AppColors.accent, priority:0))
            return list
        }
        let incs = features.map{$0.actualIncome}
        let avg  = incs.reduce(0,+)/Double(incs.count)
        let useExternalFactors = ProManager.shared.canUse(.externalFactors) && externalFactorsEnabled

        if abs(bp.growthRate) >= 2.5 {
            let up = bp.growthRate > 0
            let title = up
                ? NSLocalizedString("Доход растёт", comment: "AI insight title: income grows")
                : NSLocalizedString("Доход снижается", comment: "AI insight title: income declines")
            let body = up
                ? String(format: NSLocalizedString("Рост %.1f%% в месяц. Отличный темп!", comment: "AI insight body: growth trend"), bp.growthRate)
                : String(format: NSLocalizedString("Снижение %.1f%% в месяц. Добавьте смены.", comment: "AI insight body: decline trend"), abs(bp.growthRate))
            list.append(AIInsight(type:.trend, title: title,
                                   body: body,
                                   impact:bp.growthRate, confidence:min(1,Double(features.count)/20.0),
                                   icon: up ? "chart.line.uptrend.xyaxis":"chart.line.downtrend.xyaxis",
                                   accentColor: up ? AppColors.positive:AppColors.negative, priority:1))
        }
        if let best = wdH.filter({$0.shiftsCount>=2}).max(by:{$0.avgIncome<$1.avgIncome}) {
            let second = wdH.filter{$0.shiftsCount>=2 && $0.weekday != best.weekday}.sorted{$0.avgIncome>$1.avgIncome}.first
            let uplift = max(0, best.avgIncome - (second?.avgIncome ?? 0))
            if uplift > 200 {
                let title = String(format: NSLocalizedString("%@ — лучший день", comment: "AI insight title: best weekday"), best.weekdayName)
                let body = String(
                    format: NSLocalizedString("В %@ вы зарабатываете %d %@ — на %d больше, чем в другие дни.", comment: "AI insight body: best weekday details"),
                    weekdayAccusative(best.weekday),
                    Int(best.avgIncome),
                    currency,
                    Int(uplift)
                )
                list.append(AIInsight(type:.recommendation, title:title,
                                       body:body,
                                       impact:uplift, confidence:min(1,Double(best.shiftsCount)/5.0),
                                       icon:"calendar.badge.checkmark", accentColor:AppColors.accent, priority:2))
            }
        }
        if let upcoming = HolidayManager.shared.nextSignificantImpact(
            from: Date(),
            withinDays: 21,
            regionCode: holidayRegionCode,
            minimumAbsPercent: 0.08
        ) {
            let cal = Calendar.current
            let startToday = cal.startOfDay(for: Date())
            let startEvent = cal.startOfDay(for: upcoming.date)
            let daysUntil = max(0, cal.dateComponents([.day], from: startToday, to: startEvent).day ?? 0)
            let dateFormatter = DateFormatter()
            dateFormatter.locale = AppLanguage.currentLocale()
            dateFormatter.dateFormat = "d MMM"
            let dateText = dateFormatter.string(from: upcoming.date)
            let percent = Int(abs(upcoming.info.percent * 100).rounded())
            let dayText: String = {
                switch daysUntil {
                case 0:
                    return NSLocalizedString("сегодня", comment: "AI holiday insight: today")
                case 1:
                    return NSLocalizedString("завтра", comment: "AI holiday insight: tomorrow")
                default:
                    return String(
                        format: NSLocalizedString("через %d дн.", comment: "AI holiday insight: in days"),
                        daysUntil
                    )
                }
            }()

            if upcoming.info.percent > 0 {
                let title = String(
                    format: NSLocalizedString("Праздничный потенциал: +%d%% к доходу", comment: "AI insight title: upcoming positive holiday impact"),
                    percent
                )
                let body = String(
                    format: NSLocalizedString("%@ (%@): %@. Ожидается повышенный спрос.", comment: "AI insight body: upcoming positive holiday impact"),
                    dateText,
                    dayText,
                    upcoming.info.title
                )
                list.append(AIInsight(type: .forecast,
                                      title: title,
                                      body: body,
                                      impact: upcoming.info.percent * 100,
                                      confidence: 0.86,
                                      icon: "sparkles",
                                      accentColor: AppColors.accent,
                                      priority: 3))
            } else {
                let title = String(
                    format: NSLocalizedString("Риск снижения спроса: -%d%% к доходу", comment: "AI insight title: upcoming negative impact"),
                    percent
                )
                let body = String(
                    format: NSLocalizedString("%@ (%@): %@. Лучше выбирать проверенные смены.", comment: "AI insight body: upcoming negative holiday impact"),
                    dateText,
                    dayText,
                    upcoming.info.title
                )
                list.append(AIInsight(type: .warning,
                                      title: title,
                                      body: body,
                                      impact: -Double(percent),
                                      confidence: 0.84,
                                      icon: "exclamationmark.triangle.fill",
                                      accentColor: .orange,
                                      priority: 3))
            }
        }
        if useExternalFactors,
           let anomaly = nearestAdverseWeatherAnomaly(
            from: Date(),
            withinDays: 21,
            weatherCity: weatherCity,
            weatherCoordinates: weatherCoordinates,
            allowLiveWeather: allowLiveWeather
           ) {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = AppLanguage.currentLocale()
            dateFormatter.dateFormat = "d MMM"
            let dateText = dateFormatter.string(from: anomaly.date)
            let title = NSLocalizedString("Погодная аномалия: лучше пропустить смену", comment: "AI weather anomaly title")
            let body = String(
                format: NSLocalizedString("%@: %@. Это сильное отклонение от нормы (повторяется %d дн. подряд), лучше не планировать смену в этот день.", comment: "AI weather anomaly body"),
                dateText,
                weatherAnomalySummary(anomaly),
                anomaly.severeStreakLength
            )
            list.append(AIInsight(
                type: .warning,
                title: title,
                body: body,
                impact: -max(abs(anomaly.precipitationDelta) * 100, abs(anomaly.temperatureDeltaC) * 3),
                confidence: anomaly.confidence,
                icon: "cloud.rain.fill",
                accentColor: .orange,
                priority: 3
            ))
        }
        // Рекомендуем только реально свободные ближайшие даты
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let horizonDays = 28
        let bestByWeekday = Dictionary(uniqueKeysWithValues: wdH.map { ($0.weekday, $0.avgIncome) })
        var bestDate: (date: Date, weekday: Int, expectedIncome: Double)?
        for offset in 1...horizonDays {
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let day = cal.startOfDay(for: date)
            let occupied = occupiedDateCounts[day, default: 0]
            let occupiedHours = occupiedDayHours[day, default: 0]
            guard occupied < maxShiftsPerDay, occupiedHours < fullDayHoursThreshold else { continue }
            if useExternalFactors,
               let anomaly = weatherAnomalyAssessment(
                for: day,
                weatherCity: weatherCity,
                weatherCoordinates: weatherCoordinates,
                allowLiveWeather: allowLiveWeather
               ),
               anomaly.isAdverse {
                continue
            }
            let wd = weekdayMon(from: day, calendar: cal)
            let expected = bestByWeekday[wd] ?? avg
            if bestDate == nil || expected > (bestDate?.expectedIncome ?? 0) {
                bestDate = (date: day, weekday: wd, expectedIncome: expected)
            }
        }

        if bestDate == nil {
            // Все дни заняты — предлагаем оптимизацию вместо добавления
            list.append(AIInsight(type:.recommendation,
                                   title: NSLocalizedString("График заполнен", comment: "AI insight title: schedule is full"),
                                   body: NSLocalizedString("Все рабочие дни заняты. Попробуйте заменить низкодоходные смены на более прибыльные.", comment: "AI insight body: schedule full suggestion"),
                                   impact:0, confidence:0.9, icon:"calendar.badge.exclamationmark",
                                   accentColor:.orange, priority:3))
        } else if let best = bestDate {
            let formatter = DateFormatter()
            formatter.locale = AppLanguage.currentLocale()
            formatter.dateFormat = "d MMM"
            let dateText = formatter.string(from: best.date)
            let title = String(format: NSLocalizedString("Добавь смену — %@", comment: "AI insight title: add shift"), weekdayName(best.weekday))
            let body = String(
                format: NSLocalizedString("Ближайшая свободная дата: %@. Одна дополнительная смена может добавить ~%d %@.", comment: "AI insight body: add shift details"),
                dateText,
                Int(best.expectedIncome),
                currency
            )
            list.append(AIInsight(type:.recommendation, title:title,
                                   body:body,
                                   impact:best.expectedIncome, confidence:0.72, icon:"plus.circle.fill",
                                   accentColor:AppColors.accent, priority:3))
        }
        if bp.tipsContribution >= 0.05 {
            let tipInc = Int(avg * bp.tipsContribution)
            let tipsPercent = Int(bp.tipsContribution * 100)
            let title = String(format: NSLocalizedString("Чаевые: +%d%% дохода", comment: "AI insight title: tips contribution"), tipsPercent)
            let body = String(
                format: NSLocalizedString("Чаевые приносят вам ~%d %@ за смену — это %d%% заработка. Выбирай смены, где гости чаще оставляют чаевые.", comment: "AI insight body: tips contribution details"),
                tipInc,
                currency,
                tipsPercent
            )
            list.append(AIInsight(type:.recommendation, title:title,
                                   body:body,
                                   impact:Double(tipInc), confidence:0.88, icon:"banknote",
                                   accentColor:.orange, priority:4))
        }
        if fc.anomalyScore > 0.6, let last = features.last {
            let isLow = fc.anomalyDirection < 0
            let diff  = Int(abs(last.actualIncome - avg)/max(avg,1)*100)
            let title = isLow
                ? NSLocalizedString("Слабая смена", comment: "AI insight title: weak shift")
                : NSLocalizedString("Рекордная смена", comment: "AI insight title: record shift")
            let body = isLow
                ? String(format: NSLocalizedString("Последняя смена на %d%% ниже нормы (%d vs %d %@).", comment: "AI insight body: weak shift details"), diff, Int(last.actualIncome), Int(avg), currency)
                : String(format: NSLocalizedString("Последняя смена на %d%% выше нормы — %d %@!", comment: "AI insight body: record shift details"), diff, Int(last.actualIncome), currency)
            list.append(AIInsight(type:.anomaly,
                                   title: title,
                                   body: body,
                                   impact:last.actualIncome-avg, confidence:fc.anomalyScore,
                                   icon: isLow ? "exclamationmark.triangle.fill":"star.fill",
                                   accentColor: isLow ? AppColors.negative:.yellow, priority:5))
        }
        if !goals.filter({$0.active}).isEmpty {
            let pct = Int(fc.goalProbability * 100)
            let title = String(format: NSLocalizedString("Вероятность достижения цели в срок: %d%%", comment: "AI insight title: goal probability"), pct)
            let body = pct >= 70
                ? NSLocalizedString("Отличный темп! Сохраняй его — цель близко.", comment: "AI insight body: good goal pace")
                : String(
                    format: NSLocalizedString("Добавь %@ смену в неделю для ускорения.", comment: "AI insight body: speed up goal pace"),
                    pct < 50 ? "2–3" : "1"
                )
            list.append(AIInsight(type:.forecast, title:title,
                                   body: body,
                                   impact:0, confidence:fc.confidence, icon:"target",
                                   accentColor: pct>=70 ? AppColors.positive:AppColors.accent, priority:6))
        }
        if bp.optimalShiftDuration > 0 {
            let title = String(format: NSLocalizedString("Оптимально: %.0f ч", comment: "AI insight title: optimal shift duration"), bp.optimalShiftDuration)
            let body = String(format: NSLocalizedString("Смены по %.0f часов приносят вам максимум дохода.", comment: "AI insight body: optimal shift duration"), bp.optimalShiftDuration)
            list.append(AIInsight(type:.recommendation,
                                   title: title,
                                   body: body,
                                   impact:0, confidence:min(1,Double(features.count)/15.0),
                                   icon:"clock.badge.checkmark", accentColor:AppColors.accent, priority:7))
        }
        if fc.hasCurrentProgressComparison, abs(fc.currentProgressChange) >= 5 {
            let ch = fc.currentProgressChange
            let pct = abs(Int(ch))
            let title = ch > 0
                ? String(format: NSLocalizedString("+%d%% к прошлому месяцу", comment: "AI insight title: month over month up"), pct)
                : String(format: NSLocalizedString("-%d%% к прошлому месяцу", comment: "AI insight title: month over month down"), pct)
            let body = ch > 0
                ? String(format: NSLocalizedString("Текущий месяц опережает прошлый на %d%% (по сопоставимым дням).", comment: "AI insight body: month over month up comparable days"), pct)
                : String(format: NSLocalizedString("Текущий месяц отстаёт от прошлого на %d%% (по сопоставимым дням).", comment: "AI insight body: month over month down comparable days"), pct)
            list.append(AIInsight(type:.trend,
                                   title: title,
                                   body: body,
                                   impact:ch, confidence:0.8,
                                   icon: ch>0 ? "arrow.up.right.circle.fill":"arrow.down.right.circle.fill",
                                   accentColor: ch>0 ? AppColors.positive:AppColors.negative, priority:8))
        }
        if bp.consistencyScore > 0.7 {
            let body = String(format: NSLocalizedString("Стабильность %d%%. Вы работаете очень регулярно.", comment: "AI insight body: consistency"), Int(bp.consistencyScore * 100))
            list.append(AIInsight(type:.achievement,
                                   title: NSLocalizedString("Стабильный доход", comment: "AI insight title: stable income"),
                                   body: body,
                                   impact:0, confidence:bp.consistencyScore,
                                   icon:"checkmark.seal.fill", accentColor:AppColors.positive, priority:9))
        }
        return list.sorted { $0.priority < $1.priority }
    }

    // MARK: Feature Importance (Pro-ready)

    private func buildFeatureImportance(features: [ShiftFeature]) -> [AIFeatureImportance] {
        guard features.count >= minShifts else { return [] }

        let income = features.map { $0.actualIncome }
        let weekdayScore = betweenGroupVarianceRatio(values: income, groups: features.map { $0.weekday })
        let monthScore = betweenGroupVarianceRatio(values: income, groups: features.map { $0.month })
        let startHourScore = abs(pearsonCorrelation(x: features.map { Double($0.startHour) }, y: income))
        let durationScore = abs(pearsonCorrelation(x: features.map { $0.durationHours }, y: income))

        let tipsOn = features.filter { $0.hasTips }.map { $0.actualIncome }
        let tipsOff = features.filter { !$0.hasTips }.map { $0.actualIncome }
        let tipsScore: Double = {
            guard !tipsOn.isEmpty, !tipsOff.isEmpty else { return 0.05 }
            let onAvg = tipsOn.reduce(0, +) / Double(tipsOn.count)
            let offAvg = tipsOff.reduce(0, +) / Double(tipsOff.count)
            let base = max((onAvg + offAvg) / 2, 1)
            return min(max(abs(onAvg - offAvg) / base, 0), 1)
        }()

        var raw: [(name: String, value: Double, detail: String)] = [
            (
                NSLocalizedString("День недели", comment: "AI factor name: weekday"),
                weekdayScore,
                NSLocalizedString("Стабильные различия дохода по дням", comment: "AI factor detail: weekday")
            ),
            (
                NSLocalizedString("Время старта", comment: "AI factor name: start time"),
                startHourScore,
                NSLocalizedString("Доход меняется в зависимости от времени начала", comment: "AI factor detail: start time")
            ),
            (
                NSLocalizedString("Длительность смены", comment: "AI factor name: shift duration"),
                durationScore,
                NSLocalizedString("Более длинные/короткие смены дают разный результат", comment: "AI factor detail: shift duration")
            ),
            (
                NSLocalizedString("Чаевые", comment: "AI factor name: tips"),
                tipsScore,
                NSLocalizedString("Наличие чаевых заметно влияет на итог", comment: "AI factor detail: tips")
            ),
            (
                NSLocalizedString("Сезонность", comment: "AI factor name: seasonality"),
                monthScore,
                NSLocalizedString("Есть разница между месяцами", comment: "AI factor detail: seasonality")
            )
        ]

        raw = raw.filter { $0.value > 0.0001 }
        guard !raw.isEmpty else { return [] }

        let total = raw.reduce(0.0) { $0 + $1.value }
        let normalized = raw.map {
            AIFeatureImportance(
                name: $0.name,
                weight: min(max($0.value / total, 0), 1),
                detail: $0.detail
            )
        }
        return normalized.sorted { $0.weight > $1.weight }
    }

    private func betweenGroupVarianceRatio(values: [Double], groups: [Int]) -> Double {
        guard values.count == groups.count, values.count >= 3 else { return 0 }
        let globalMean = values.reduce(0, +) / Double(values.count)
        guard globalMean > 0 else { return 0 }

        var grouped: [Int: [Double]] = [:]
        for (idx, value) in values.enumerated() {
            grouped[groups[idx], default: []].append(value)
        }
        guard grouped.count > 1 else { return 0 }

        let between = grouped.values.reduce(0.0) { partial, arr in
            let mean = arr.reduce(0, +) / Double(arr.count)
            return partial + Double(arr.count) * pow(mean - globalMean, 2)
        } / Double(values.count)

        let within = grouped.values.reduce(0.0) { partial, arr in
            let mean = arr.reduce(0, +) / Double(arr.count)
            let variance = arr.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(max(arr.count, 1))
            return partial + variance
        } / Double(grouped.count)

        guard within > 0 else { return 1 }
        return min(max(between / within, 0), 1)
    }

    private func pearsonCorrelation(x: [Double], y: [Double]) -> Double {
        guard x.count == y.count, x.count >= 3 else { return 0 }
        let n = Double(x.count)
        let mx = x.reduce(0, +) / n
        let my = y.reduce(0, +) / n
        let numerator = zip(x, y).reduce(0.0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let sx = sqrt(x.reduce(0.0) { $0 + pow($1 - mx, 2) })
        let sy = sqrt(y.reduce(0.0) { $0 + pow($1 - my, 2) })
        guard sx > 0, sy > 0 else { return 0 }
        return numerator / (sx * sy)
    }

    private struct WeatherAnomalyAssessment {
        let date: Date
        let temperatureC: Double
        let precipitationChance: Double
        let normalTemperatureC: Double
        let normalPrecipitationChance: Double
        let temperatureDeltaC: Double
        let precipitationDelta: Double
        let severeStreakLength: Int
        let confidence: Double
        let isAdverse: Bool
    }

    private func nearestAdverseWeatherAnomaly(
        from startDate: Date,
        withinDays: Int,
        weatherCity: String,
        weatherCoordinates: (latitude: Double, longitude: Double)?,
        allowLiveWeather: Bool
    ) -> WeatherAnomalyAssessment? {
        let calendar = Calendar.current
        let fromDay = calendar.startOfDay(for: startDate)
        for offset in 1...max(withinDays, 1) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: fromDay) else { continue }
            guard let anomaly = weatherAnomalyAssessment(
                for: date,
                weatherCity: weatherCity,
                weatherCoordinates: weatherCoordinates,
                allowLiveWeather: allowLiveWeather
            ) else { continue }
            if anomaly.isAdverse {
                return anomaly
            }
        }
        return nil
    }

    private func weatherAnomalyAssessment(
        for date: Date,
        weatherCity: String,
        weatherCoordinates: (latitude: Double, longitude: Double)?,
        allowLiveWeather: Bool
    ) -> WeatherAnomalyAssessment? {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let target = WeatherManager.shared.context(
            for: day,
            cityName: weatherCity,
            coordinates: weatherCoordinates,
            allowLive: allowLiveWeather
        )

        var samples: [(offset: Int, context: DailyWeatherContext)] = []
        samples.reserveCapacity(20)
        for offset in -10...10 where offset != 0 {
            guard let sampleDate = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
            let sample = WeatherManager.shared.context(
                for: sampleDate,
                cityName: weatherCity,
                coordinates: weatherCoordinates,
                allowLive: allowLiveWeather
            )
            samples.append((offset, sample))
        }
        guard samples.count >= 8 else { return nil }

        let medianTemp = sortedMedian(samples.map { $0.context.temperatureC })
        let medianPrecip = min(max(sortedMedian(samples.map { $0.context.precipitationChance }), 0), 1)
        let tempTrendEstimate = linearRegressionPredictionAtZero(
            points: samples.map { (x: Double($0.offset), y: $0.context.temperatureC) }
        ) ?? medianTemp
        let precipTrendEstimate = linearRegressionPredictionAtZero(
            points: samples.map { (x: Double($0.offset), y: $0.context.precipitationChance) }
        ) ?? medianPrecip

        let normalTemp = medianTemp * 0.65 + tempTrendEstimate * 0.35
        let normalPrecip = min(max(medianPrecip * 0.65 + precipTrendEstimate * 0.35, 0), 1)

        let tempDelta = target.temperatureC - normalTemp
        let precipDelta = target.precipitationChance - normalPrecip
        let heavyPrecipSpike = target.precipitationChance >= 0.70 && normalPrecip <= 0.20
        let tempShock = abs(tempDelta) >= 8
        let severeTarget = heavyPrecipSpike || tempShock
        guard severeTarget else { return nil }

        var sampleByOffset: [Int: DailyWeatherContext] = [0: target]
        for sample in samples {
            sampleByOffset[sample.offset] = sample.context
        }

        func isSevere(_ context: DailyWeatherContext) -> Bool {
            let sampleTempDelta = context.temperatureC - normalTemp
            let sampleHeavyPrecip = context.precipitationChance >= 0.70 && normalPrecip <= 0.20
            return sampleHeavyPrecip || abs(sampleTempDelta) >= 8
        }

        var streak = 1
        for step in 1...3 {
            if let prev = sampleByOffset[-step], isSevere(prev) {
                streak += 1
            } else {
                break
            }
        }
        for step in 1...3 {
            if let next = sampleByOffset[step], isSevere(next) {
                streak += 1
            } else {
                break
            }
        }
        guard streak < 3 else { return nil }

        let isAdverse = target.condition == .rain
            || target.condition == .snow
            || target.precipitationChance >= 0.55
            || target.temperatureC <= normalTemp - 8
            || target.temperatureC >= normalTemp + 10

        let severity = weatherDeviationSeverity(
            temperatureDelta: tempDelta,
            precipitationDelta: precipDelta,
            heavyPrecipSpike: heavyPrecipSpike
        )
        let confidence = min(0.95, 0.55 + min(severity, 1.8) * 0.2 + (samples.count >= 12 ? 0.1 : 0))

        return WeatherAnomalyAssessment(
            date: day,
            temperatureC: target.temperatureC,
            precipitationChance: target.precipitationChance,
            normalTemperatureC: normalTemp,
            normalPrecipitationChance: normalPrecip,
            temperatureDeltaC: tempDelta,
            precipitationDelta: precipDelta,
            severeStreakLength: streak,
            confidence: confidence,
            isAdverse: isAdverse
        )
    }

    private func linearRegressionPredictionAtZero(points: [(x: Double, y: Double)]) -> Double? {
        guard points.count >= 4 else { return nil }
        let count = Double(points.count)
        let meanX = points.reduce(0) { $0 + $1.x } / count
        let meanY = points.reduce(0) { $0 + $1.y } / count
        let varianceX = points.reduce(0) { $0 + pow($1.x - meanX, 2) }
        guard varianceX > 0.0001 else { return nil }
        let covarianceXY = points.reduce(0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        let slope = covarianceXY / varianceX
        return meanY - slope * meanX
    }

    private func weatherDeviationSeverity(
        temperatureDelta: Double,
        precipitationDelta: Double,
        heavyPrecipSpike: Bool
    ) -> Double {
        let tempPart = abs(temperatureDelta) / 8.0
        let precipPart = max(0, precipitationDelta) / 0.5
        return max(tempPart, precipPart, heavyPrecipSpike ? 1.0 : 0.0)
    }

    private func weatherAnomalySummary(_ anomaly: WeatherAnomalyAssessment) -> String {
        var fragments: [String] = []
        let precipNow = Int((anomaly.precipitationChance * 100).rounded())
        let precipNorm = Int((anomaly.normalPrecipitationChance * 100).rounded())
        if anomaly.precipitationChance >= 0.70 && anomaly.normalPrecipitationChance <= 0.20 {
            fragments.append(
                String(
                    format: NSLocalizedString("осадки %d%% при норме %d%%", comment: "AI weather anomaly summary: precipitation spike"),
                    precipNow,
                    precipNorm
                )
            )
        }

        if abs(anomaly.temperatureDeltaC) >= 8 {
            let tempNow = Int(anomaly.temperatureC.rounded())
            let tempNorm = Int(anomaly.normalTemperatureC.rounded())
            let tempPrefix = tempNow > 0 ? "+" : ""
            let normPrefix = tempNorm > 0 ? "+" : ""
            fragments.append(
                String(
                    format: NSLocalizedString("температура %@%d°C при норме %@%d°C", comment: "AI weather anomaly summary: temperature shock"),
                    tempPrefix,
                    tempNow,
                    normPrefix,
                    tempNorm
                )
            )
        }

        if fragments.isEmpty {
            fragments.append(
                String(
                    format: NSLocalizedString("резкое отклонение: осадки %d%%, отклонение температуры %.0f°C", comment: "AI weather anomaly summary: generic"),
                    precipNow,
                    anomaly.temperatureDeltaC
                )
            )
        }
        return fragments.joined(separator: ", ")
    }

    // MARK: Shift Recommendations (Pro-ready planner base)

    private func buildShiftRecommendations(
        workTypes: [WorkType],
        features: [ShiftFeature],
        currency: String,
        externalFactorsEnabled: Bool,
        weatherCity: String,
        weatherCoordinates: (latitude: Double, longitude: Double)?,
        allowLiveWeather: Bool,
        holidayRegionCode: String,
        perWorkTypeForecast: [String:(predicted:Double,confidence:Double,basedOn:Int)],
        perWorkTypeWeekdayMultipliers: [String:[Int:Double]],
        occupiedDateCounts: [Date: Int],
        occupiedDayHours: [Date: Double],
        upcomingDays: Int,
        maxShiftsPerDay: Int,
        fullDayHoursThreshold: Double
    ) -> [ShiftRecommendation] {
        guard !workTypes.isEmpty, !perWorkTypeForecast.isEmpty else { return [] }

        let cal = Calendar.current
        let useExternalFactors = ProManager.shared.canUse(.externalFactors) && externalFactorsEnabled
        let today = cal.startOfDay(for: Date())
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = AppLanguage.currentLocale()
            formatter.dateFormat = "d MMM"
            return formatter
        }()
        var all: [ShiftRecommendation] = []

        for offset in 1...max(upcomingDays, 1) {
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let day = cal.startOfDay(for: date)
            let occupiedCount = occupiedDateCounts[day, default: 0]
            let occupiedHours = occupiedDayHours[day, default: 0]
            guard occupiedCount < maxShiftsPerDay, occupiedHours < fullDayHoursThreshold else { continue }
            if useExternalFactors,
               let anomaly = weatherAnomalyAssessment(
                for: day,
                weatherCity: weatherCity,
                weatherCoordinates: weatherCoordinates,
                allowLiveWeather: allowLiveWeather
               ),
               anomaly.isAdverse {
                continue
            }

            let weekday = weekdayMon(from: day, calendar: cal)
            let dayName = weekdayName(weekday)
            for wt in workTypes {
                guard let base = perWorkTypeForecast[wt.name], base.basedOn >= 2 else { continue }
                let weekdayMultiplier = perWorkTypeWeekdayMultipliers[wt.name]?[weekday] ?? 1.0
                let duration = defaultWorkTypeDurationHours(wt)
                let hourMultiplier = 0.88 + (min(max(duration, 3.0), 14.0) / 14.0) * 0.24
                let baseBeforeExternal = max(0, base.predicted * weekdayMultiplier * hourMultiplier)
                var externalMultiplier = 1.0
                var weatherImpact = 0.0
                var weatherReason: String?
                var holidayImpact = 0.0
                var holidayPriorityPercent = 0.0
                let holidayInfo = HolidayManager.shared.impactInfo(for: day, regionCode: holidayRegionCode)
                let rawHolidayPercent = holidayInfo?.percent ?? 0
                holidayPriorityPercent = rawHolidayPercent
                if useExternalFactors {
                    let sensitivity = WorkTypeSensitivityEstimator.estimate(workType: wt, features: features)
                    let weather = WeatherManager.shared.context(
                        for: day,
                        cityName: weatherCity,
                        coordinates: weatherCoordinates,
                        allowLive: allowLiveWeather
                    )

                    let weatherSignal: Double = {
                        switch weather.condition {
                        case .clear:
                            return sensitivity.outdoorBias >= 0 ? 0.11 : 0.03
                        case .cloudy:
                            return 0.01
                        case .rain:
                            return sensitivity.outdoorBias >= 0 ? -0.12 : 0.04
                        case .snow:
                            return sensitivity.outdoorBias >= 0 ? -0.16 : 0.03
                        case .unknown:
                            return 0
                        }
                    }()
                    weatherImpact = weatherSignal * sensitivity.weatherWeight
                    externalMultiplier *= 1 + weatherImpact
                    if abs(weatherImpact) >= 0.02 {
                        let weatherText = weatherReasonText(
                            condition: weather.condition,
                            impactPercent: Int((weatherImpact * 100).rounded())
                        )
                        let weatherAmount = Int((baseBeforeExternal * weatherImpact).rounded())
                        weatherReason = String(
                            format: NSLocalizedString("%@ (≈%+d %@)", comment: "planner reason: weather with amount"),
                            weatherText,
                            weatherAmount,
                            currency
                        )
                    }

                    let normalizedHolidayImpact: Double
                    if abs(rawHolidayPercent) > 0.001 {
                        normalizedHolidayImpact = rawHolidayPercent
                    } else if holidayInfo?.isPublicHoliday == true {
                        normalizedHolidayImpact = 0.08
                    } else {
                        normalizedHolidayImpact = 0
                    }
                    holidayImpact = normalizedHolidayImpact * sensitivity.holidayWeight
                    if abs(holidayImpact) >= 0.01 {
                        externalMultiplier *= 1 + holidayImpact
                    }
                }

                let expectedIncome = max(0, baseBeforeExternal * externalMultiplier)

                var reasonCandidates: [(priority: Int, text: String)] = []

                if abs(rawHolidayPercent) >= 0.02 {
                    let holidayImpactPct = Int(abs(rawHolidayPercent * 100).rounded())
                    let dateText = dateFormatter.string(from: day)
                    let holidayTitle = holidayInfo?.title.isEmpty == false
                        ? (holidayInfo?.title ?? "")
                        : NSLocalizedString("событие календаря", comment: "planner holiday event fallback")
                    if rawHolidayPercent > 0 {
                        reasonCandidates.append(
                            (
                                130,
                                String(
                                    format: NSLocalizedString("%@ — %@: ожидается +%d%% к выручке.", comment: "planner reason: positive holiday impact short"),
                                    dateText,
                                    holidayTitle,
                                    holidayImpactPct
                                )
                            )
                        )
                    } else {
                        reasonCandidates.append(
                            (
                                130,
                                String(
                                    format: NSLocalizedString("%@ — %@: ожидается -%d%% к выручке.", comment: "planner reason: negative holiday impact short"),
                                    dateText,
                                    holidayTitle,
                                    holidayImpactPct
                                )
                            )
                        )
                    }
                }

                let totalGainPct = Int(((weekdayMultiplier * hourMultiplier * externalMultiplier - 1) * 100).rounded())
                if totalGainPct >= 4 {
                    reasonCandidates.append(
                        (
                            70,
                            String(
                                format: NSLocalizedString("Суммарный потенциал этой смены: примерно +%d%% к вашей базовой смене.", comment: "planner reason: total gain vs baseline"),
                                totalGainPct
                            )
                        )
                    )
                }

                let weekdayDeltaPct = Int(((weekdayMultiplier - 1) * 100).rounded())
                if weekdayDeltaPct >= 4 {
                    reasonCandidates.append(
                        (
                            90,
                            String(
                                format: NSLocalizedString("%@ по вашей истории даёт около +%d%% к среднему (%d смен в базе).", comment: "planner reason: weekday stronger with data"),
                                dayName,
                                weekdayDeltaPct,
                                base.basedOn
                            )
                        )
                    )
                } else {
                    reasonCandidates.append(
                        (
                            40,
                            String(
                                format: NSLocalizedString("%@ даёт стабильный результат по вашей истории (%d смен в базе).", comment: "planner reason: weekday stable with data"),
                                dayName,
                                base.basedOn
                            )
                        )
                    )
                }

                let durationImpactPct = Int(max(0, (hourMultiplier - 1) * 100).rounded())
                if durationImpactPct >= 4 {
                    reasonCandidates.append(
                        (
                            65,
                            String(
                                format: NSLocalizedString("Длительность %.0f ч обычно добавляет около +%d%% к выручке.", comment: "planner reason: long shift with impact"),
                                duration,
                                durationImpactPct
                            )
                        )
                    )
                }

                if let weatherReason {
                    reasonCandidates.append((55, weatherReason))
                }

                if base.basedOn <= 3 {
                    reasonCandidates.append(
                        (
                            10,
                            String(
                                format: NSLocalizedString("Пока только %d смен(ы) в базе: прогноз предварительный.", comment: "planner reason: low data"),
                                base.basedOn
                            )
                        )
                    )
                }

                var reasons = reasonCandidates
                    .sorted { $0.priority > $1.priority }
                    .map(\.text)
                    .reduce(into: [String]()) { result, text in
                        if !result.contains(text) { result.append(text) }
                    }

                if reasons.isEmpty {
                    reasons.append(
                        String(
                            format: NSLocalizedString("Прогноз основан на %d предыдущих сменах этого типа.", comment: "planner reason: generic data-based fallback"),
                            base.basedOn
                        )
                    )
                }

                if reasons.count == 1 {
                    reasons.append(
                        String(
                            format: NSLocalizedString("Оценка подтверждена на %d сменах и текущем профиле графика.", comment: "planner reason: confidence fallback"),
                            base.basedOn
                        )
                    )
                }
                reasons = Array(reasons.prefix(2))

                let confidence = min(0.95, max(0.25, base.confidence * (weekdayMultiplier > 1 ? 1.06 : 0.96)))
                all.append(
                    ShiftRecommendation(
                        date: day,
                        workTypeName: wt.name,
                        workTypeIcon: wt.icon,
                        expectedIncome: expectedIncome,
                        confidence: confidence,
                        holidayPriorityPercent: holidayPriorityPercent,
                        reasons: reasons
                    )
                )
            }
        }

        let bestPerDay = Dictionary(grouping: all, by: { Calendar.current.startOfDay(for: $0.date) })
            .compactMap { _, items in
                items.max { lhs, rhs in
                    if lhs.holidayPriorityPercent != rhs.holidayPriorityPercent {
                        return lhs.holidayPriorityPercent < rhs.holidayPriorityPercent
                    }
                    if lhs.expectedIncome != rhs.expectedIncome {
                        return lhs.expectedIncome < rhs.expectedIncome
                    }
                    return lhs.confidence < rhs.confidence
                }
            }
            .sorted { lhs, rhs in
                if lhs.holidayPriorityPercent != rhs.holidayPriorityPercent {
                    return lhs.holidayPriorityPercent > rhs.holidayPriorityPercent
                }
                if lhs.expectedIncome != rhs.expectedIncome {
                    return lhs.expectedIncome > rhs.expectedIncome
                }
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.date < rhs.date
            }
        let targetCount = recommendationTargetCount(features: features, horizonDays: upcomingDays, calendar: cal)
        return Array(bestPerDay.prefix(targetCount))
    }

    private func defaultWorkTypeDurationHours(_ workType: WorkType) -> Double {
        let start = workType.startHour * 60 + workType.startMinute
        let end = workType.endHour * 60 + workType.endMinute
        var diff = end - start
        if diff <= 0 { diff += 24 * 60 }
        return max(Double(diff) / 60.0, 1)
    }

    private func weatherReasonText(condition: WeatherCondition, impactPercent: Int) -> String {
        let absImpact = abs(impactPercent)
        switch condition {
        case .clear:
            return impactPercent >= 0
                ? String(format: NSLocalizedString("Ясная погода: около +%d%% к активности", comment: "planner weather reason: clear positive"), absImpact)
                : String(format: NSLocalizedString("Ясная погода: около -%d%% к активности", comment: "planner weather reason: clear negative"), absImpact)
        case .cloudy:
            return impactPercent >= 0
                ? String(format: NSLocalizedString("Облачно: нейтрально, около +%d%%", comment: "planner weather reason: cloudy positive"), absImpact)
                : String(format: NSLocalizedString("Облачно: нейтрально, около -%d%%", comment: "planner weather reason: cloudy negative"), absImpact)
        case .rain:
            return impactPercent >= 0
                ? String(format: NSLocalizedString("Дождь для этого типа может дать +%d%%", comment: "planner weather reason: rain positive"), absImpact)
                : String(format: NSLocalizedString("Дождь для этого типа может снизить поток на %d%%", comment: "planner weather reason: rain negative"), absImpact)
        case .snow:
            return impactPercent >= 0
                ? String(format: NSLocalizedString("Снег для этого типа может дать +%d%%", comment: "planner weather reason: snow positive"), absImpact)
                : String(format: NSLocalizedString("Снег может снизить спрос/логистику на %d%%", comment: "planner weather reason: snow negative"), absImpact)
        case .unknown:
            return NSLocalizedString("Погодные данные ограничены", comment: "planner weather reason: unknown")
        }
    }

    private func plannedShiftDurationHours(start: Date, end: Date) -> Double {
        var hours = end.timeIntervalSince(start) / 3600
        if hours <= 0 { hours += 24 }
        return max(hours, 1)
    }

    private func plannedShiftDurationHours(_ shift: PlannedShift) -> Double {
        plannedShiftDurationHours(start: shift.startTime, end: shift.endTime)
    }

    private func recommendationTargetCount(features: [ShiftFeature], horizonDays: Int, calendar: Calendar) -> Int {
        let safeHorizon = max(horizonDays, 1)
        let uniqueDays = Set(features.map { calendar.startOfDay(for: $0.date) })
        guard !uniqueDays.isEmpty else {
            return max(1, Int((Double(safeHorizon) * 0.6).rounded()))
        }

        let latestDay = uniqueDays.max() ?? Date()
        let weeklyCutoff = calendar.date(byAdding: .day, value: -84, to: latestDay) ?? latestDay
        let monthlyCutoff = calendar.date(byAdding: .month, value: -12, to: latestDay) ?? latestDay

        let weeklyStats = weeklyActivityStats(days: uniqueDays.filter { $0 >= weeklyCutoff }, calendar: calendar)
        let monthlyStats = monthlyActivityStats(days: uniqueDays.filter { $0 >= monthlyCutoff }, calendar: calendar)
        // Основное правило: средний ритм по неделям (6+4 -> 5), масштабируем под горизонт.
        // Месячную статистику используем только как fallback при отсутствии недельной.
        let blended: Double
        if weeklyStats.bucketCount > 0 {
            blended = weeklyStats.average * Double(safeHorizon) / 7.0
        } else if monthlyStats.bucketCount > 0 {
            blended = monthlyStats.average * Double(safeHorizon) / 30.0
        } else {
            blended = Double(safeHorizon) * 0.6
        }

        let rounded = Int(blended.rounded())
        return min(max(1, rounded), safeHorizon)
    }

    private func weeklyActivityStats(days: [Date], calendar: Calendar) -> (average: Double, bucketCount: Int) {
        guard !days.isEmpty else { return (0, 0) }
        var buckets: [String: Set<Date>] = [:]
        for day in days {
            let normalized = calendar.startOfDay(for: day)
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: normalized)
            let key = "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
            buckets[key, default: []].insert(normalized)
        }
        let counts = buckets.values.map { Double($0.count) }
        guard !counts.isEmpty else { return (0, 0) }
        return (counts.reduce(0, +) / Double(counts.count), buckets.count)
    }

    private func monthlyActivityStats(days: [Date], calendar: Calendar) -> (average: Double, bucketCount: Int) {
        guard !days.isEmpty else { return (0, 0) }
        var buckets: [String: Set<Date>] = [:]
        for day in days {
            let normalized = calendar.startOfDay(for: day)
            let components = calendar.dateComponents([.year, .month], from: normalized)
            let key = "\(components.year ?? 0)-\(components.month ?? 0)"
            buckets[key, default: []].insert(normalized)
        }
        let counts = buckets.values.map { Double($0.count) }
        guard !counts.isEmpty else { return (0, 0) }
        return (counts.reduce(0, +) / Double(counts.count), buckets.count)
    }

    func recommendShifts(for upcomingDays: Int, completion: @escaping ([ShiftRecommendation]) -> Void) {
        let now = Date()
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let maxDate = Calendar.current.date(byAdding: .day, value: max(upcomingDays, 1), to: now) ?? now
            let filtered = self.shiftRecommendations
                .filter { $0.date >= now && $0.date <= maxDate }
                .sorted { lhs, rhs in
                    if lhs.holidayPriorityPercent != rhs.holidayPriorityPercent {
                        return lhs.holidayPriorityPercent > rhs.holidayPriorityPercent
                    }
                    if lhs.expectedIncome != rhs.expectedIncome {
                        return lhs.expectedIncome > rhs.expectedIncome
                    }
                    if lhs.confidence != rhs.confidence {
                        return lhs.confidence > rhs.confidence
                    }
                    return lhs.date < rhs.date
                }
            DispatchQueue.main.async {
                completion(filtered)
            }
        }
    }

    // MARK: Math

    private func computeEMA(_ v:[Double], alpha:Double) -> Double {
        guard let f = v.first else { return 0 }
        return v.dropFirst().reduce(f){ ema,x in alpha*x+(1-alpha)*ema }
    }
    private func standardDev(_ v:[Double]) -> Double {
        guard v.count>1 else { return 0 }
        let m = v.reduce(0,+)/Double(v.count)
        return sqrt(v.reduce(0){$0+pow($1-m,2)}/Double(v.count-1))
    }
    private func sortedMedian(_ v:[Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s=v.sorted(); let mid=s.count/2
        return s.count%2==0 ? (s[mid-1]+s[mid])/2 : s[mid]
    }
    private func linearSlope(_ v:[Double]) -> Double {
        let n=Double(v.count); guard n>1 else { return 0 }
        let xs=(0..<v.count).map{Double($0)}
        let sx=xs.reduce(0,+), sy=v.reduce(0,+)
        let sxy=zip(xs,v).reduce(0){$0+$1.0*$1.1}
        let sxx=xs.reduce(0){$0+$1*$1}
        let d=n*sxx-sx*sx
        return d==0 ? 0 : (n*sxy-sx*sy)/d
    }
    private func computeGrowth(features:[ShiftFeature]) -> Double {
        guard features.count >= 8 else { return 0 }
        let cal = Calendar.current
        let now = Date()
        let currentMonthKey = cal.component(.month, from: now) + cal.component(.year, from: now) * 12

        var monthlyIncome: [Int: Double] = [:]
        var monthlyShiftCount: [Int: Int] = [:]
        for feature in features {
            let monthKey = cal.component(.month, from: feature.date) + cal.component(.year, from: feature.date) * 12
            monthlyIncome[monthKey, default: 0] += feature.actualIncome
            monthlyShiftCount[monthKey, default: 0] += 1
        }

        var monthKeys = monthlyIncome.keys.sorted()
        // Не учитываем текущий (незавершённый) месяц, если есть достаточная история.
        if monthKeys.contains(currentMonthKey), monthKeys.count >= 4 {
            monthKeys.removeAll { $0 == currentMonthKey }
        }

        // Нужны надёжные месяцы: минимум 3 смены, чтобы не ловить шум.
        let reliableMonthKeys = monthKeys.filter { (monthlyShiftCount[$0] ?? 0) >= 3 }
        guard reliableMonthKeys.count >= 3 else { return 0 }

        let totals = reliableMonthKeys.map { monthlyIncome[$0] ?? 0 }
        let slope = linearSlope(totals)
        let mean = totals.reduce(0, +) / Double(totals.count)
        guard mean > 0 else { return 0 }

        let rawGrowth = (slope / mean) * 100.0
        guard rawGrowth.isFinite else { return 0 }
        // Ограничиваем экстремумы, которые почти всегда являются следствием малой выборки.
        return min(max(rawGrowth, -60), 60)
    }

    private struct PlannedShiftWindowComparison {
        let hasComparison: Bool
        let changePercent: Double
        let windowSize: Int
        let message: String?
        let explanation: String?
    }

    private func plannedShiftWindowComparison(
        iSnaps: [(date:Date,amount:Double,tips:Double,hours:Double,rate:Double,type:String,floating:Double)],
        plannedShifts: [PlannedSnap],
        activeWorkTypes: [WorkType],
        calendar: Calendar,
        today: Date,
        externalFactorsEnabled: Bool,
        weatherCity: String,
        weatherCoordinates: (latitude: Double, longitude: Double)?,
        allowLiveWeather: Bool,
        holidayRegionCode: String
    ) -> PlannedShiftWindowComparison {
        guard let currentMonth = calendar.dateInterval(of: .month, for: today),
              let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: today),
              let previousMonth = calendar.dateInterval(of: .month, for: previousMonthDate) else {
            return PlannedShiftWindowComparison(
                hasComparison: false,
                changePercent: 0,
                windowSize: 0,
                message: NSLocalizedString("Недостаточно данных для прогноза", comment: "forecast comparison fallback: not enough data"),
                explanation: nil
            )
        }

        let todayStart = calendar.startOfDay(for: today)
        let plannedCurrentMonth = plannedShifts
            .filter {
                let day = calendar.startOfDay(for: $0.date)
                return day >= todayStart && day >= currentMonth.start && day < currentMonth.end
            }
            .sorted { $0.date < $1.date }

        guard plannedCurrentMonth.count >= 3 else {
            return PlannedShiftWindowComparison(
                hasComparison: false,
                changePercent: 0,
                windowSize: 0,
                message: NSLocalizedString("Точный прогноз появится после ввода минимум 3 смен", comment: "forecast comparison: min planned shifts required"),
                explanation: nil
            )
        }

        let plannedWindow = Array(plannedCurrentMonth.prefix(14))
        let targetWindowSize = max(3, min(14, plannedWindow.count)) // dynamic window: 3...14

        let previousMonthFacts = iSnaps
            .filter { $0.date >= previousMonth.start && $0.date < previousMonth.end }
            .sorted { $0.date > $1.date }

        guard previousMonthFacts.count >= 3 else {
            return PlannedShiftWindowComparison(
                hasComparison: false,
                changePercent: 0,
                windowSize: 0,
                message: NSLocalizedString("Недостаточно данных для прогноза", comment: "forecast comparison: not enough previous month shifts"),
                explanation: nil
            )
        }

        let pastWindowSize = min(targetWindowSize, previousMonthFacts.count)
        guard pastWindowSize >= 3 else {
            return PlannedShiftWindowComparison(
                hasComparison: false,
                changePercent: 0,
                windowSize: 0,
                message: NSLocalizedString("Недостаточно данных для прогноза", comment: "forecast comparison: not enough previous month shifts"),
                explanation: nil
            )
        }

        let finalWindow = min(pastWindowSize, plannedWindow.count)
        guard finalWindow >= 3 else {
            return PlannedShiftWindowComparison(
                hasComparison: false,
                changePercent: 0,
                windowSize: 0,
                message: NSLocalizedString("Недостаточно данных для прогноза", comment: "forecast comparison: insufficient final window"),
                explanation: nil
            )
        }

        let selectedPastRecent = Array(previousMonthFacts.prefix(finalWindow))
        let selectedPlanned = Array(plannedWindow.prefix(finalWindow))

        let pastIncomeTotal = selectedPastRecent.reduce(0.0) { $0 + max($1.amount, 0) }
        let pastTipsTotal = selectedPastRecent.reduce(0.0) { $0 + max($1.tips, 0) }
        let pastBaseTotal = selectedPastRecent.reduce(0.0) { partial, snap in
            let tip = max(snap.tips, 0)
            return partial + max(snap.amount - tip, 0)
        }
        guard pastIncomeTotal > 0 else {
            return PlannedShiftWindowComparison(
                hasComparison: false,
                changePercent: 0,
                windowSize: 0,
                message: NSLocalizedString("Недостаточно данных для прогноза", comment: "forecast comparison: invalid past totals"),
                explanation: nil
            )
        }

        struct WeekdayTipStats {
            var incomeTotal: Double = 0
            var baseTotal: Double = 0
            var tipsTotal: Double = 0
            var tipsDays: Int = 0
            var count: Int = 0
        }
        var weekdayStats: [Int: WeekdayTipStats] = [:]
        for snap in previousMonthFacts {
            let weekday = weekdayMon(from: snap.date, calendar: calendar)
            let income = max(snap.amount, 0)
            let tips = max(snap.tips, 0)
            let base = max(income - tips, 0)
            var item = weekdayStats[weekday] ?? WeekdayTipStats()
            item.incomeTotal += income
            item.baseTotal += base
            item.tipsTotal += tips
            item.count += 1
            if tips > 0.01 {
                item.tipsDays += 1
            }
            weekdayStats[weekday] = item
        }

        let globalTipRatio = pastBaseTotal > 0 ? (pastTipsTotal / pastBaseTotal) : 0
        let globalTipDaysShare = Double(selectedPastRecent.filter { $0.tips > 0.01 }.count) / Double(finalWindow)
        let globalPastIncomeAvg = pastIncomeTotal / Double(finalWindow)

        let pastHistoryForTrend = iSnaps
            .filter { $0.date < currentMonth.start }
            .sorted { $0.date < $1.date }
        let recentTrendHistory = Array(pastHistoryForTrend.suffix(min(120, pastHistoryForTrend.count)))

        let tipRatioHistory = recentTrendHistory.compactMap { snap -> Double? in
            let income = max(snap.amount, 0)
            let tips = max(snap.tips, 0)
            let base = max(income - tips, 0)
            guard base > 0.01 else { return nil }
            return min(max(tips / base, 0), 0.9)
        }
        let tipPresenceHistory = recentTrendHistory.map { max($0.tips, 0) > 0.01 ? 1.0 : 0.0 }

        func trailingAverage(_ values: [Double], limit: Int) -> Double {
            guard !values.isEmpty else { return 0 }
            let window = max(1, min(limit, values.count))
            let slice = values.suffix(window)
            return slice.reduce(0, +) / Double(window)
        }

        let tipRatioMA = tipRatioHistory.isEmpty ? globalTipRatio : trailingAverage(tipRatioHistory, limit: 14)
        let tipPresenceMA = tipPresenceHistory.isEmpty ? globalTipDaysShare : trailingAverage(tipPresenceHistory, limit: 21)
        let tipRatioSlope = linearSlope(Array(tipRatioHistory.suffix(min(28, tipRatioHistory.count))))
        let tipPresenceSlope = linearSlope(Array(tipPresenceHistory.suffix(min(28, tipPresenceHistory.count))))
        let trendHorizon = max(1.0, Double(finalWindow) / 4.0)
        let trendTipRatio = min(max(tipRatioMA + tipRatioSlope * trendHorizon, 0), 0.9)
        let trendTipPresence = clampUnit(tipPresenceMA + tipPresenceSlope * trendHorizon)

        let workTypesById = Dictionary(uniqueKeysWithValues: activeWorkTypes.map { ($0.id, $0) })
        var comparablePastTotal = 0.0
        var futurePredictedTotal = 0.0
        var anomalyDaysCount = 0

        for planned in selectedPlanned {
            let weekday = weekdayMon(from: planned.date, calendar: calendar)
            let base = plannedShiftBaseAmount(planned, workTypesById: workTypesById)

            if let weekdayItem = weekdayStats[weekday], weekdayItem.count > 0 {
                comparablePastTotal += weekdayItem.incomeTotal / Double(weekdayItem.count)
            } else {
                comparablePastTotal += globalPastIncomeAvg
            }

            var weekdayTipRatio = globalTipRatio
            var weekdayTipPresence = globalTipDaysShare
            if let weekdayItem = weekdayStats[weekday], weekdayItem.count > 0 {
                if weekdayItem.baseTotal > 0.01 {
                    weekdayTipRatio = weekdayItem.tipsTotal / weekdayItem.baseTotal
                }
                weekdayTipPresence = Double(weekdayItem.tipsDays) / Double(weekdayItem.count)
            }

            var tipRatioForShift: Double
            var tipPresenceForShift: Double
            if planned.hasTips {
                tipRatioForShift = min(max(weekdayTipRatio * 0.55 + trendTipRatio * 0.35 + globalTipRatio * 0.10, 0), 0.9)
                tipPresenceForShift = clampUnit(weekdayTipPresence * 0.60 + trendTipPresence * 0.30 + globalTipDaysShare * 0.10)
            } else {
                tipRatioForShift = 0
                tipPresenceForShift = 0
            }

            var baseMultiplier = 1.0
            if externalFactorsEnabled && ProManager.shared.canUse(.externalFactors) {
                let weatherAdjustment = weatherTipAdjustment(
                    for: planned.date,
                    weatherCity: weatherCity,
                    weatherCoordinates: weatherCoordinates,
                    allowLiveWeather: allowLiveWeather
                )
                tipRatioForShift = min(max(tipRatioForShift * (1 + weatherAdjustment), 0), 0.9)

                if let anomaly = weatherAnomalyAssessment(
                    for: planned.date,
                    weatherCity: weatherCity,
                    weatherCoordinates: weatherCoordinates,
                    allowLiveWeather: allowLiveWeather
                ), anomaly.isAdverse {
                    anomalyDaysCount += 1
                    baseMultiplier *= 0.95
                    tipRatioForShift *= 0.82
                }

                if let holidayInfo = HolidayManager.shared.impactInfo(for: planned.date, regionCode: holidayRegionCode) {
                    let holidaySignal = min(max(holidayInfo.percent, -0.8), 0.8)
                    baseMultiplier *= (1 + holidaySignal * 0.28)
                    tipRatioForShift *= (1 + holidaySignal * 0.42)
                }
            }

            tipRatioForShift = min(max(tipRatioForShift, 0), 0.9)
            tipPresenceForShift = clampUnit(tipPresenceForShift)

            let predictedTips = base * tipRatioForShift * tipPresenceForShift
            let predictedIncome = max(0, base * max(baseMultiplier, 0.7) + predictedTips)
            futurePredictedTotal += predictedIncome
        }

        guard comparablePastTotal > 0, futurePredictedTotal > 0 else {
            return PlannedShiftWindowComparison(
                hasComparison: false,
                changePercent: 0,
                windowSize: finalWindow,
                message: NSLocalizedString("Недостаточно данных для прогноза", comment: "forecast comparison: no planned base"),
                explanation: nil
            )
        }

        let avgPast = comparablePastTotal / Double(finalWindow)
        let avgFutureAdjusted = futurePredictedTotal / Double(finalWindow)
        let changePercent = ((avgFutureAdjusted - avgPast) / max(avgPast, 0.0001)) * 100

        var messageParts: [String] = []
        if globalTipRatio <= 0.0001 {
            messageParts.append(NSLocalizedString("В прошлом месяце чаевые не зафиксированы — прогноз рассчитан в основном по ставке.", comment: "forecast comparison no tips message"))
        } else if tipRatioHistory.count < 6 {
            messageParts.append(NSLocalizedString("Истории чаевых пока мало — тренд чаевых оценён по ограниченной выборке.", comment: "forecast comparison few tip history message"))
        }
        if anomalyDaysCount > 0 {
            let anomalyMessage = String(
                format: NSLocalizedString("Учтены погодные аномалии на %d дн. — ожидаемая доходность на этих днях снижена.", comment: "forecast comparison weather anomaly days message"),
                anomalyDaysCount
            )
            messageParts.append(anomalyMessage)
        }

        let explanation = String(
            format: NSLocalizedString("Прогноз основан на сравнении %d ближайших запланированных смен с профилем этих же дней недели за прошлый месяц, с учётом тренда чаевых и внешних факторов.", comment: "forecast comparison explanation with weekday profile"),
            finalWindow
        )
        return PlannedShiftWindowComparison(
            hasComparison: true,
            changePercent: changePercent,
            windowSize: finalWindow,
            message: messageParts.isEmpty ? nil : messageParts.joined(separator: " "),
            explanation: explanation
        )
    }

    private func plannedShiftBaseAmount(_ planned: PlannedSnap, workTypesById: [UUID: WorkType]) -> Double {
        let duration = plannedShiftDurationHours(start: planned.startTime, end: planned.endTime)
        if let workType = workTypesById[planned.workTypeId] {
            var base = 0.0
            if workType.hasHourlyRate {
                let rate = planned.hourlyRate > 0 ? planned.hourlyRate: workType.hourlyRate
                base += max(rate, 0) * duration
            }
            if workType.hasFixedRate {
                base += max(workType.fixedRate, 0)
            }
            if !workType.hasHourlyRate && !workType.hasFixedRate && planned.hourlyRate > 0 {
                base += planned.hourlyRate * duration
            }
            return max(base, 0)
        }
        return max(planned.hourlyRate * duration, 0)
    }

    private func weatherTipAdjustment(
        for date: Date,
        weatherCity: String,
        weatherCoordinates: (latitude: Double, longitude: Double)?,
        allowLiveWeather: Bool
    ) -> Double {
        let weather = WeatherManager.shared.context(
            for: date,
            cityName: weatherCity,
            coordinates: weatherCoordinates,
            allowLive: allowLiveWeather
        )
        var adjustment: Double
        switch weather.condition {
        case .clear:
            adjustment = 0.08
        case .cloudy:
            adjustment = 0.0
        case .rain:
            adjustment = -0.06
        case .snow:
            adjustment = -0.1
        case .unknown:
            adjustment = 0.0
        }
        if weather.precipitationChance >= 0.7 {
            adjustment -= 0.05
        } else if weather.precipitationChance <= 0.2 {
            adjustment += 0.03
        }
        return min(max(adjustment, -0.2), 0.2)
    }

    private func monthInc(snaps:[(date:Date,amount:Double,tips:Double,hours:Double,rate:Double,type:String,floating:Double)],
                           cal:Calendar, date:Date) -> Double {
        guard let iv=cal.dateInterval(of:.month,for:date) else { return 0 }
        return snaps.reduce(0){ p,s in s.date>=iv.start && s.date<iv.end ? p+s.amount : p }
    }

    private func monthShiftCount(
        snaps:[(date:Date,amount:Double,tips:Double,hours:Double,rate:Double,type:String,floating:Double)],
        cal:Calendar,
        date:Date
    ) -> Int {
        guard let iv = cal.dateInterval(of: .month, for: date) else { return 0 }
        return snaps.reduce(0) { count, snap in
            (snap.date >= iv.start && snap.date < iv.end) ? (count + 1) : count
        }
    }

    private func currentProgressSnapshot(
        snaps: [(date:Date,amount:Double,tips:Double,hours:Double,rate:Double,type:String,floating:Double)],
        calendar: Calendar,
        today: Date
    ) -> (currentIncome: Double, previousIncome: Double, currentShiftCount: Int, previousShiftCount: Int, elapsedDays: Int) {
        guard let currentMonth = calendar.dateInterval(of: .month, for: today),
              let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: today),
              let previousMonth = calendar.dateInterval(of: .month, for: previousMonthDate)
        else {
            return (0, 0, 0, 0, 0)
        }

        let todayStart = calendar.startOfDay(for: today)
        let dayNumber = max(1, calendar.component(.day, from: todayStart))
        let previousMonthDayCount = calendar.range(of: .day, in: .month, for: previousMonth.start)?.count ?? dayNumber
        let comparableDays = min(dayNumber, previousMonthDayCount)
        guard comparableDays > 0 else { return (0, 0, 0, 0, 0) }

        let previousEndExclusive = calendar.date(byAdding: .day, value: comparableDays, to: previousMonth.start)
            ?? previousMonth.end

        var currentIncome = 0.0
        var previousIncome = 0.0
        var currentShifts = 0
        var previousShifts = 0

        for snap in snaps {
            if snap.date >= currentMonth.start && snap.date <= todayStart {
                currentIncome += snap.amount
                currentShifts += 1
            }
            if snap.date >= previousMonth.start && snap.date < previousEndExclusive {
                previousIncome += snap.amount
                previousShifts += 1
            }
        }

        return (currentIncome, previousIncome, currentShifts, previousShifts, comparableDays)
    }

    private func forecastCurrentMonthIncome(
        iSnaps: [(date:Date,amount:Double,tips:Double,hours:Double,rate:Double,type:String,floating:Double)],
        features: [ShiftFeature],
        calendar: Calendar,
        today: Date
    ) -> Double {
        guard let monthInterval = calendar.dateInterval(of: .month, for: today) else { return 0 }
        let todayStart = calendar.startOfDay(for: today)

        // Факт за прошедшие дни текущего месяца
        let actualToDate = iSnaps.reduce(0.0) { partial, snap in
            let day = calendar.startOfDay(for: snap.date)
            guard day >= monthInterval.start, day <= todayStart else { return partial }
            return partial + snap.amount
        }

        // Профиль по дням недели: средний доход за смену и частота смен
        let historyFeatures = features.filter { $0.date < monthInterval.start || $0.date <= today }
        let weekdayIncomeRows = buildWeekdayHeatmap(features: historyFeatures)
        let weekdayAvgIncome = Dictionary(uniqueKeysWithValues: weekdayIncomeRows.map { ($0.weekday, $0.avgIncome) })

        guard !historyFeatures.isEmpty else { return actualToDate }
        let globalAvgShiftIncome = historyFeatures.map { $0.actualIncome }.reduce(0, +) / Double(historyFeatures.count)

        // Частота смен по дням недели за последние 84 дня
        let historyWindowStart = calendar.date(byAdding: .day, value: -83, to: todayStart) ?? todayStart
        let windowFeatures = historyFeatures.filter { calendar.startOfDay(for: $0.date) >= historyWindowStart }
        let shiftCountsByWeekday = Dictionary(grouping: windowFeatures, by: { $0.weekday }).mapValues(\.count)

        var weekdayOccurrences: [Int: Int] = [:]
        if let dayBeforeToday = calendar.date(byAdding: .day, value: -1, to: todayStart) {
            var cursor = historyWindowStart
            while cursor <= dayBeforeToday {
                let wd = weekdayMon(from: cursor, calendar: calendar)
                weekdayOccurrences[wd, default: 0] += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }
        let weekdayShiftProb = (1...7).reduce(into: [Int: Double]()) { result, wd in
            let occ = max(weekdayOccurrences[wd] ?? 0, 1)
            let shifts = shiftCountsByWeekday[wd] ?? 0
            result[wd] = min(max(Double(shifts) / Double(occ), 0), 1)
        }

        // Прогноз только на оставшиеся дни текущего месяца
        var predictedRemaining = 0.0
        var cursor = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        while cursor < monthInterval.end {
            let wd = weekdayMon(from: cursor, calendar: calendar)
            let avgShiftIncome = max(weekdayAvgIncome[wd] ?? globalAvgShiftIncome, 0)
            let shiftProb = weekdayShiftProb[wd] ?? 0
            predictedRemaining += avgShiftIncome * shiftProb
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return max(actualToDate, actualToDate + predictedRemaining)
    }

    // MARK: - Прогноз конкретной смены (для AddWorkSheet)

    /// Возвращает (predicted, basedOn, probHigh) или nil если данных недостаточно
    private func weekdayMon(from date: Date, calendar: Calendar = .current) -> Int {
        let raw = calendar.component(.weekday, from: date)
        return raw == 1 ? 7 : raw - 1
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = localizedWeekdaySymbols()
        let index = max(0, min(6, weekday - 1))
        guard symbols.indices.contains(index) else {
            return NSLocalizedString("День", comment: "weekday fallback")
        }
        return symbols[index].capitalized(with: AppLanguage.currentLocale())
    }

    // Склонение дня недели для предлога "в"
    private func weekdayAccusative(_ weekday: Int) -> String {
        if isRussianLanguage {
            switch weekday {
            case 1: return "понедельник"
            case 2: return "вторник"
            case 3: return "среду"
            case 4: return "четверг"
            case 5: return "пятницу"
            case 6: return "субботу"
            case 7: return "воскресенье"
            default: return "этот день"
            }
        }
        return weekdayName(weekday).lowercased(with: AppLanguage.currentLocale())
    }

    private func localizedWeekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale()
        var symbols = formatter.standaloneWeekdaySymbols ?? formatter.weekdaySymbols ?? []
        if symbols.count == 7 {
            let sunday = symbols.removeFirst()
            symbols.append(sunday)
        }
        return symbols
    }

    private var isRussianLanguage: Bool {
        switch AppLanguage.current() {
        case .russian:
            return true
        case .system:
            return Locale.autoupdatingCurrent.identifier.lowercased().hasPrefix("ru")
        default:
            return false
        }
    }

    /// Индивидуальный прогноз для конкретного типа работы
    func forecastShift(workTypeName: String,
                       weekday: Int,
                       startHour: Int,
                       durationHours: Double,
                       date: Date? = nil,
                       considerExternalFactors: Bool = false,
                       weatherCity: String = "",
                       weatherCoordinates: (latitude: Double, longitude: Double)? = nil,
                       allowLiveWeather: Bool = false,
                       holidayRegionCode: String = HolidayRegion.auto.rawValue) -> (predicted: Double, basedOn: Int, probHigh: Double)? {
        // Только индивидуальный прогноз; не подставляем одинаковый глобальный прогноз для всех типов.
        guard let perWT = perWorkTypeForecast[workTypeName], perWT.basedOn > 0 else { return nil }
        guard perWT.basedOn >= 2 else { return nil }

        let dayMultiplier = perWorkTypeWeekdayMultipliers[workTypeName]?[weekday] ?? 1.0
        let hourMultiplier: Double = {
            // Лёгкая поправка по длительности, чтобы длинные смены были немного выше
            let normalized = min(max(durationHours, 3.0), 14.0)
            return 0.88 + (normalized / 14.0) * 0.24
        }()
        var adjusted = max(0, perWT.predicted * dayMultiplier * hourMultiplier)
        var probHigh = min(0.95, max(0.1, forecast.highIncomeProbability * (0.7 + perWT.confidence * 0.45)))

        if considerExternalFactors && ProManager.shared.canUse(.externalFactors) {
            let targetDate = date ?? Date()
            let weather = WeatherManager.shared.context(
                for: targetDate,
                cityName: weatherCity,
                coordinates: weatherCoordinates,
                allowLive: allowLiveWeather
            )
            let holidayInfo = HolidayManager.shared.impactInfo(for: targetDate, regionCode: holidayRegionCode)
            let normalizedName = workTypeName.lowercased()
            let outdoorBias: Double = (normalizedName.contains("курьер")
                                       || normalizedName.contains("taxi")
                                       || normalizedName.contains("такси")
                                       || normalizedName.contains("водител")
                                       || normalizedName.contains("driver")) ? 0.7 : -0.2
            let weatherSignal: Double = {
                switch weather.condition {
                case .clear: return outdoorBias >= 0 ? 0.08 : 0.03
                case .cloudy: return 0.01
                case .rain: return outdoorBias >= 0 ? -0.1 : 0.03
                case .snow: return outdoorBias >= 0 ? -0.14 : 0.02
                case .unknown: return 0
                }
            }()
            let holidaySignalRaw: Double = {
                if let holidayInfo, abs(holidayInfo.percent) > 0.001 {
                    return holidayInfo.percent
                }
                if holidayInfo?.isPublicHoliday == true {
                    return 0.06
                }
                return 0
            }()
            let holidaySignal = holidaySignalRaw * 0.8
            let externalMultiplier = max(0.8, 1 + weatherSignal + holidaySignal)
            adjusted = max(0, adjusted * externalMultiplier)
            probHigh = min(0.98, max(0.1, probHigh * externalMultiplier))
        }
        return (adjusted, perWT.basedOn, probHigh)
    }
}
