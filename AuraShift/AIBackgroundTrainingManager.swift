import Foundation
import BackgroundTasks
import CoreData
import os

/// Night background retraining scheduler for AI forecasts.
/// Uses BGProcessingTask and runs only on-device.
final class AIBackgroundTrainingManager {
    static let shared = AIBackgroundTrainingManager()
    static let taskIdentifier = "com.aurashift.ai.retrain"

    private let logger = Logger(subsystem: "D-D.AuraShift", category: "AIBackgroundTraining")
    private let lastTrainingAtKey = "aurashift.ai.backgroundTraining.lastAt"
    private let lastTrainingModeKey = "aurashift.ai.backgroundTraining.lastMode"
    private let lastTrainingShiftsKey = "aurashift.ai.backgroundTraining.lastShiftCount"

    private var isRegistered = false

    private init() {}

    func registerIfNeeded() {
        guard !isRegistered else { return }
        let didRegister = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(task: processingTask)
        }
        guard didRegister else {
            logger.error("BGTask registration failed. Ensure Info.plist has permitted identifiers.")
            return
        }
        isRegistered = true
        logger.info("BGTask registration succeeded for '\(Self.taskIdentifier, privacy: .public)'")
    }

    /// Schedules retraining for the next night window.
    /// `forceSoon` is useful for debug/testing.
    func scheduleNightTraining(forceSoon: Bool = false) {
        if !isRegistered { registerIfNeeded() }
        guard isRegistered else {
            logger.error("Attempted to schedule BG task before registration")
            return
        }
        guard ProManager.shared.canUse(.advancedML) else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)

        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        // Training is fully on-device. Do NOT require network. If Low Power Mode is enabled, prefer external power to be nice to the user.
        let needsNetwork = false
        let needsExternalPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        request.requiresExternalPower = needsExternalPower
        request.requiresNetworkConnectivity = needsNetwork
        request.earliestBeginDate = forceSoon
            ? Date().addingTimeInterval(120)
            : nextNightTrainingDate()

        logger.info("Scheduling BGProcessing '\(Self.taskIdentifier, privacy: .public)' at ~\(request.earliestBeginDate?.description ?? "nil") | requiresPower=\(needsExternalPower, privacy: .public) | requiresNetwork=\(needsNetwork, privacy: .public) | forceSoon=\(forceSoon, privacy: .public)")

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("BG retraining task submitted successfully")
        } catch {
            logger.error("Failed to submit BG retraining task: \(error.localizedDescription, privacy: .public)")
        }
    }

    var lastTrainingAt: Date? {
        UserDefaults.standard.object(forKey: lastTrainingAtKey) as? Date
    }

    private func handle(task: BGProcessingTask) {
        logger.info("BGProcessing task received: starting background AI retraining")
        // Re-schedule first to keep the chain alive even if the current run fails.
        scheduleNightTraining()

        let start = Date()
        let worker = Task.detached(priority: .background) { [weak self] in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            let success = await self.runBackgroundTraining()
            let elapsed = Date().timeIntervalSince(start)
            self.logger.info("BGProcessing task finished with success=\(success, privacy: .public) in \(elapsed, privacy: .public)s")
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            self.logger.error("BGProcessing task expired by the system — cancelling work")
            worker.cancel()
        }
    }

    private func nextNightTrainingDate(from now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent

        let todayAtTwo = calendar.date(
            bySettingHour: 2,
            minute: 15,
            second: 0,
            of: now
        ) ?? now.addingTimeInterval(6 * 3600)

        if todayAtTwo > now {
            return todayAtTwo
        }

        return calendar.date(byAdding: .day, value: 1, to: todayAtTwo) ?? now.addingTimeInterval(24 * 3600)
    }

    private func runBackgroundTraining() async -> Bool {
        logger.info("runBackgroundTraining: invoked")
        guard ProManager.shared.canUse(.advancedML) else {
            logger.info("runBackgroundTraining: skipped — Pro feature not available")
            return true
        }
        if Task.isCancelled { return false }

        let outcome = await performTrainingOnMainActor()
        if Task.isCancelled {
            logger.error("runBackgroundTraining: cancelled after training")
            return false
        }

        UserDefaults.standard.set(Date(), forKey: lastTrainingAtKey)
        UserDefaults.standard.set(modeString(outcome.mode), forKey: lastTrainingModeKey)
        UserDefaults.standard.set(outcome.shiftCount, forKey: lastTrainingShiftsKey)

        AnalyticsManager.shared.track(
            "ai_background_retrain",
            metadata: [
                "success": outcome.success ? "1" : "0",
                "mode": modeString(outcome.mode),
                "shifts": "\(outcome.shiftCount)"
            ]
        )

        logger.info("runBackgroundTraining: success=\(outcome.success, privacy: .public) mode=\(self.modeString(outcome.mode), privacy: .public) shifts=\(outcome.shiftCount, privacy: .public)")

        return outcome.success
    }

    @MainActor
    private func performTrainingOnMainActor() async -> (success: Bool, mode: AIEngine.ForecastModelMode, shiftCount: Int) {
        let context = PersistenceController.shared.container.viewContext

        let incomes: [Income]
        let expenses: [Expense]
        let goals: [FinancialGoal]

        do {
            let incomeRequest: NSFetchRequest<Income> = Income.fetchRequest()
            let expenseRequest: NSFetchRequest<Expense> = Expense.fetchRequest()
            let goalRequest: NSFetchRequest<FinancialGoal> = FinancialGoal.fetchRequest()

            incomeRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Income.date, ascending: true)]
            expenseRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Expense.date, ascending: true)]
            goalRequest.sortDescriptors = [NSSortDescriptor(keyPath: \FinancialGoal.deadline, ascending: true)]

            incomes = try context.fetch(incomeRequest)
            expenses = try context.fetch(expenseRequest)
            goals = try context.fetch(goalRequest)
        } catch {
            logger.error("Background retraining fetch failed: \(error.localizedDescription, privacy: .public)")
            return (false, .standard, 0)
        }

        guard !incomes.isEmpty else {
            logger.info("performTrainingOnMainActor: no incomes — nothing to train")
            return (true, .standard, 0)
        }

        let settings = UserSettings()
        let engine = AIEngine()
        logger.info("performTrainingOnMainActor: starting analysis on main actor")
        engine.analyze(incomes: incomes, expenses: expenses, settings: settings, goals: goals, plannedShifts: [])

        let timeout = Date().addingTimeInterval(22)
        while engine.isAnalyzing && Date() < timeout {
            if Task.isCancelled { return (false, .standard, 0) }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        let completed = !engine.isAnalyzing
        logger.info("performTrainingOnMainActor: completed=\(completed, privacy: .public) mode=\(engine.forecastModelMode == .standard ? "standard" : (engine.forecastModelMode == .blended ? "blended" : "enhanced"), privacy: .public) shifts=\(engine.forecast.basedOnShifts, privacy: .public)")
        return (
            completed,
            engine.forecastModelMode,
            engine.forecast.basedOnShifts
        )
    }

    private func modeString(_ mode: AIEngine.ForecastModelMode) -> String {
        switch mode {
        case .standard: return "standard"
        case .blended: return "blended"
        case .enhanced: return "enhanced"
        }
    }
}
