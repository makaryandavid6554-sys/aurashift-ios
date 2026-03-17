import SwiftUI
import Combine
import CoreData

// MARK: - ExpenseItem
struct ExpenseItem: Identifiable, Codable {
    var id: UUID
    var amount: Double
    var category: String
    var note: String
    
    init(id: UUID = UUID(), amount: Double, category: String, note: String) {
        self.id = id
        self.amount = amount
        self.category = category
        self.note = note
    }
}

// MARK: - PlannedShift
struct PlannedShift: Identifiable, Codable {
    let id: UUID
    let date: Date
    let workTypeId: UUID
    let workTypeName: String
    let icon: String
    let startTime: Date
    let endTime: Date
    let hourlyRate: Double
    let hasTips: Bool
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case workTypeId
        case workTypeName
        case icon
        case startTime
        case endTime
        case hourlyRate
        case hasTips
        case note
    }

    init(
        id: UUID = UUID(),
        date: Date,
        workTypeId: UUID,
        workTypeName: String,
        icon: String,
        startTime: Date,
        endTime: Date,
        hourlyRate: Double,
        hasTips: Bool,
        note: String?
    ) {
        self.id = id
        self.date = date
        self.workTypeId = workTypeId
        self.workTypeName = workTypeName
        self.icon = icon
        self.startTime = startTime
        self.endTime = endTime
        self.hourlyRate = hourlyRate
        self.hasTips = hasTips
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        workTypeId = try container.decode(UUID.self, forKey: .workTypeId)
        workTypeName = try container.decode(String.self, forKey: .workTypeName)
        icon = try container.decode(String.self, forKey: .icon)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        hourlyRate = try container.decode(Double.self, forKey: .hourlyRate)
        hasTips = try container.decode(Bool.self, forKey: .hasTips)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

// MARK: - WorkSession
struct WorkSession: Identifiable {
    let id: UUID
    var workTypeId: UUID
    var workTypeName: String
    var icon: String
    var hasHourlyRate: Bool
    var hasFixedRate: Bool
    var hasFloatingRate: Bool
    var hasTips: Bool
    var floatingAmount: Double = 0
    var tips: Double = 0
    let date: Date
    var note: String?

    var hoursWorked: Double = 0
    var hourlyRate: Double = 0
    var fixedAmount: Double = 0

    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    var calculatedHours: Double {
        let startInMinutes = startHour * 60 + startMinute
        let endInMinutes = endHour * 60 + endMinute
        var diff = endInMinutes - startInMinutes
        if diff < 0 { diff += 24 * 60 }
        return Double(diff) / 60.0
    }

    var totalEarning: Double {
        var total = 0.0
        if hasHourlyRate {
            total += calculatedHours * hourlyRate
        }
        if hasFixedRate {
            total += fixedAmount
        }
        if hasFloatingRate {
            total += floatingAmount
        }
        if hasTips {
            total += tips
        }
        return total
    }

    var startTimeFormatted: String {
        String(format: "%02d:%02d", startHour, startMinute)
    }

    var endTimeFormatted: String {
        String(format: "%02d:%02d", endHour, endMinute)
    }

    var timeRange: String {
        "\(startTimeFormatted)-\(endTimeFormatted)"
    }

    // Инициализатор для новой сессии (из WorkType)
    init(workType: WorkType, date: Date) {
        self.id = UUID()
        self.workTypeId = workType.id
        self.workTypeName = workType.name
        self.icon = workType.icon
        self.hasHourlyRate = workType.hasHourlyRate
        self.hasFixedRate = workType.hasFixedRate
        self.hasFloatingRate = workType.hasFloatingRate
        self.hasTips = workType.hasTips
        self.date = date
        self.startHour = workType.startHour
        self.startMinute = workType.startMinute
        self.endHour = workType.endHour
        self.endMinute = workType.endMinute

        self.hourlyRate = workType.hourlyRate
        self.fixedAmount = workType.fixedRate

        self.note = nil
        self.floatingAmount = 0
        self.tips = 0
        self.hoursWorked = 0
    }

    // Полный инициализатор для загрузки из Core Data
    init(workTypeId: UUID, workTypeName: String, icon: String,
         hasHourlyRate: Bool, hasFixedRate: Bool, hasFloatingRate: Bool,
         hasTips: Bool,
         date: Date, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int,
         hourlyRate: Double = 0, fixedAmount: Double = 0,
         floatingAmount: Double = 0, tips: Double = 0, hoursWorked: Double = 0,
         note: String? = nil) {
        self.id = UUID()
        self.workTypeId = workTypeId
        self.workTypeName = workTypeName
        self.icon = icon
        self.hasHourlyRate = hasHourlyRate
        self.hasFixedRate = hasFixedRate
        self.hasFloatingRate = hasFloatingRate
        self.hasTips = hasTips
        self.date = date
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.hourlyRate = hourlyRate
        self.fixedAmount = fixedAmount
        self.floatingAmount = floatingAmount
        self.tips = tips
        self.hoursWorked = hoursWorked
        self.note = note
    }
}

// MARK: - SessionManager
class SessionManager: ObservableObject {
    @Published var workSessions: [WorkSession] = []
    @Published var plannedShifts: [PlannedShift] = []

    private let plannedShiftsKey = "plannedShifts"
    private var resetObserver: NSObjectProtocol?

    init(context _: NSManagedObjectContext) {
        loadPlannedShifts()
        loadSessionsFromCoreData()
        observeDataReset()
    }

    deinit {
        if let observer = resetObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Core Data Integration
    func loadSessionsFromCoreData() {
        let workTypesByName = Self.loadWorkTypesByNameFromDefaults()
        let container = PersistenceController.shared.container

        container.performBackgroundTask { [weak self] backgroundContext in
            let fetchRequest: NSFetchRequest<Income> = Income.fetchRequest()
            fetchRequest.returnsObjectsAsFaults = false
            fetchRequest.fetchBatchSize = 256
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Income.date, ascending: true)]

            do {
                let incomes = try backgroundContext.fetch(fetchRequest)
                let loadedSessions = incomes.compactMap { income -> WorkSession? in
                    guard let workTypeName = income.type else { return nil }
                    let workType = workTypesByName[workTypeName]
                    let icon = workType?.icon ?? "briefcase"

                    let hasHourlyRate = income.hoursWorked > 0 && income.hourlyRate > 0
                    let hasFloatingRate = !hasHourlyRate && income.floatingAmount > 0
                    let hasTips = income.tips > 0
                    let hasFixedRate = false

                    return WorkSession(
                        workTypeId: workType?.id ?? UUID(),
                        workTypeName: workTypeName,
                        icon: icon,
                        hasHourlyRate: hasHourlyRate,
                        hasFixedRate: hasFixedRate,
                        hasFloatingRate: hasFloatingRate,
                        hasTips: hasTips,
                        date: income.date ?? Date(),
                        startHour: workType?.startHour ?? 9,
                        startMinute: workType?.startMinute ?? 0,
                        endHour: workType?.endHour ?? 17,
                        endMinute: workType?.endMinute ?? 0,
                        hourlyRate: income.hourlyRate,
                        fixedAmount: 0,
                        floatingAmount: income.floatingAmount,
                        tips: income.tips,
                        hoursWorked: income.hoursWorked,
                        note: income.note
                    )
                }

                DispatchQueue.main.async {
                    self?.workSessions = loadedSessions
                    print("📅 Загружено сессий из Core Data: \(loadedSessions.count)")
                }
            } catch {
                DispatchQueue.main.async {
                    print("❌ Ошибка загрузки из Core Data: \(error)")
                }
            }
        }
    }

    private static func loadWorkTypesByNameFromDefaults() -> [String: WorkType] {
        guard let data = UserDefaults.standard.data(forKey: "workTypes"),
              let decoded = try? JSONDecoder().decode([WorkType].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.name, $0) })
    }

    // MARK: - Work Sessions Management
    func addWorkSession(_ session: WorkSession) {
        workSessions.append(session)
        print("✅ Добавлена сессия: \(session.workTypeName), hourlyRate=\(session.hourlyRate)")
    }

    func updateWorkSession(at index: Int, with session: WorkSession) {
        guard index >= 0 && index < workSessions.count else { return }
        workSessions[index] = session
        print("✅ Обновлена сессия: \(session.workTypeName), hourlyRate=\(session.hourlyRate)")
    }

    func removeWorkSession(at index: Int) {
        guard index >= 0 && index < workSessions.count else { return }
        let removed = workSessions.remove(at: index)
        print("✅ Удалена сессия: \(removed.workTypeName)")
    }

    // MARK: - Planned Shifts Management
    private func loadPlannedShifts() {
        if let data = UserDefaults.standard.data(forKey: plannedShiftsKey),
           let decoded = try? JSONDecoder().decode([PlannedShift].self, from: data) {
            self.plannedShifts = decoded
            print("✅ Загружено планов: \(self.plannedShifts.count)")
        }
    }

    func addPlannedShift(_ shift: PlannedShift) {
        plannedShifts.append(shift)
        savePlannedShifts()
        print("✅ Добавлен план: \(shift.workTypeName)")
    }

    func removePlannedShift(at index: Int) {
        guard index >= 0 && index < plannedShifts.count else { return }
        plannedShifts.remove(at: index)
        savePlannedShifts()
    }

    func removePlannedShift(_ shift: PlannedShift) {
        plannedShifts.removeAll { $0.id == shift.id }
        savePlannedShifts()
    }

    func replacePlannedShift(id: UUID, with shift: PlannedShift) {
        guard let index = plannedShifts.firstIndex(where: { $0.id == id }) else { return }
        plannedShifts[index] = shift
        savePlannedShifts()
    }

    func setPlannedShifts(_ shifts: [PlannedShift]) {
        plannedShifts = shifts
        savePlannedShifts()
    }

    func applyWorkTypeChanges(fromName oldName: String, fromId oldId: UUID, to updatedType: WorkType) {
        for index in workSessions.indices {
            let matches = workSessions[index].workTypeId == oldId || workSessions[index].workTypeName == oldName
            guard matches else { continue }

            workSessions[index].workTypeId = updatedType.id
            workSessions[index].workTypeName = updatedType.name
            workSessions[index].icon = updatedType.icon
            workSessions[index].hasHourlyRate = updatedType.hasHourlyRate
            workSessions[index].hasFixedRate = updatedType.hasFixedRate
            workSessions[index].hasFloatingRate = updatedType.hasFloatingRate
            workSessions[index].hasTips = updatedType.hasTips
            workSessions[index].hourlyRate = updatedType.hasHourlyRate ? updatedType.hourlyRate : 0
            workSessions[index].fixedAmount = updatedType.hasFixedRate ? updatedType.fixedRate : 0

            if updatedType.hasHourlyRate {
                workSessions[index].floatingAmount = 0
            } else if updatedType.hasFixedRate {
                workSessions[index].floatingAmount = 0
            }
            if !updatedType.hasTips {
                workSessions[index].tips = 0
            }
        }

        plannedShifts = plannedShifts.map { shift in
            let matches = shift.workTypeId == oldId || shift.workTypeName == oldName
            guard matches else { return shift }
            return PlannedShift(
                id: shift.id,
                date: shift.date,
                workTypeId: updatedType.id,
                workTypeName: updatedType.name,
                icon: updatedType.icon,
                startTime: shift.startTime,
                endTime: shift.endTime,
                hourlyRate: updatedType.hasHourlyRate ? updatedType.hourlyRate : 0,
                hasTips: updatedType.hasTips,
                note: shift.note
            )
        }
        savePlannedShifts()
    }

    func persistWorkSessionsToCoreData() {
        let context = PersistenceController.shared.container.viewContext
        context.performAndWait {
            let fetch: NSFetchRequest<Income> = Income.fetchRequest()
            fetch.returnsObjectsAsFaults = false
            if let existing = try? context.fetch(fetch) {
                existing.forEach { context.delete($0) }
            }

            for session in workSessions where session.totalEarning > 0 {
                let income = Income(context: context)
                income.id = UUID()
                income.date = session.date
                income.type = session.workTypeName
                income.tips = session.hasTips ? session.tips : 0
                income.note = session.note

                if session.hasHourlyRate {
                    income.hoursWorked = session.calculatedHours
                    income.hourlyRate = session.hourlyRate
                    income.floatingAmount = 0
                } else if session.hasFixedRate {
                    income.hoursWorked = 0
                    income.hourlyRate = 0
                    income.floatingAmount = session.fixedAmount
                } else if session.hasFloatingRate {
                    income.hoursWorked = 0
                    income.hourlyRate = 0
                    income.floatingAmount = session.floatingAmount
                } else {
                    income.hoursWorked = 0
                    income.hourlyRate = 0
                    income.floatingAmount = 0
                }
            }

            do {
                try context.save()
            } catch {
                print("❌ Ошибка массового сохранения смен: \(error)")
            }
        }
    }

    private func savePlannedShifts() {
        if let encoded = try? JSONEncoder().encode(plannedShifts) {
            UserDefaults.standard.set(encoded, forKey: plannedShiftsKey)
            print("💾 Планы сохранены: \(plannedShifts.count)")
        }
    }

    private func observeDataReset() {
        resetObserver = NotificationCenter.default.addObserver(
            forName: .aurashiftDataDidReset,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.workSessions.removeAll()
            self.plannedShifts.removeAll()
            UserDefaults.standard.removeObject(forKey: self.plannedShiftsKey)
        }
    }

    // MARK: - Helper Methods
    func getSessionsForDate(_ date: Date) -> [WorkSession] {
        let calendar = Calendar.current
        return workSessions.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func getPlannedShiftsForDate(_ date: Date) -> [PlannedShift] {
        let calendar = Calendar.current
        return plannedShifts.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
}
