//
//  FinancialGoal+CoreDataProperties.swift
//  AuraShift
//
//  Created by David Makarian on 24.02.2026.
//
//
import Foundation
import CoreData

public import Foundation
public import CoreData


public typealias FinancialGoalCoreDataPropertiesSet = NSSet

extension FinancialGoal {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FinancialGoal> {
        return NSFetchRequest<FinancialGoal>(entityName: "FinancialGoal")
    }

    @NSManaged public var currentAmount: Double
    @NSManaged public var deadline: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var isActive: Bool
    @NSManaged public var name: String?
    @NSManaged public var targetAmount: Double

}

extension FinancialGoal : Identifiable {

}
