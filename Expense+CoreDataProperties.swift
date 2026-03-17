//
//  Expense+CoreDataProperties.swift
//  AuraShift
//
//  Created by David Makarian on 25.02.2026.
//
//

public import Foundation
public import CoreData


public typealias ExpenseCoreDataPropertiesSet = NSSet

extension Expense {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Expense> {
        return NSFetchRequest<Expense>(entityName: "Expense")
    }

    @NSManaged public var amount: Double
    @NSManaged public var category: String?
    @NSManaged public var date: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var notes: String?

}

extension Expense : Identifiable {

}
