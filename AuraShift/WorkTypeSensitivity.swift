import Foundation

struct WorkTypeSensitivity {
    let weatherWeight: Double   // 0...1
    let holidayWeight: Double   // 0...1
    let outdoorBias: Double     // -1...1 (negative = indoor)
}

enum WorkTypeSensitivityEstimator {
    static func estimate(workType: WorkType, features: [ShiftFeature]) -> WorkTypeSensitivity {
        let typeFeatures = features.filter { $0.workTypeName == workType.name }

        let hasTipsBoost = workType.hasTips ? 0.22 : 0.08
        let sampleBoost = min(Double(typeFeatures.count) / 40.0, 0.25)

        // Outdoor-oriented icons are usually more weather-sensitive.
        let outdoorBias: Double = {
            switch workType.icon {
            case "bicycle", "car", "bus":
                return 0.75
            case "wineglass", "fork.knife", "house":
                return -0.35
            default:
                return 0.2
            }
        }()

        let variability: Double = {
            let incomes = typeFeatures.map { $0.actualIncome }
            guard incomes.count >= 3 else { return 0.15 }
            let mean = incomes.reduce(0, +) / Double(incomes.count)
            guard mean > 0 else { return 0.1 }
            let variance = incomes.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(incomes.count)
            return min(max(sqrt(variance) / mean, 0), 0.5)
        }()

        let weatherWeight = min(max(0.18 + hasTipsBoost + sampleBoost + variability * 0.6, 0.1), 1.0)
        let holidayWeight = min(max(0.14 + (workType.hasTips ? 0.18 : 0.07) + sampleBoost * 0.5, 0.1), 1.0)
        return WorkTypeSensitivity(weatherWeight: weatherWeight, holidayWeight: holidayWeight, outdoorBias: outdoorBias)
    }
}
