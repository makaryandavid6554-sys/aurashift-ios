//
//  Income+CoreDataProperties.swift
//  AuraShift
//
//  Created by David Makarian on 26.02.2026.
//
//

public import Foundation
public import CoreData


public typealias IncomeCoreDataPropertiesSet = NSSet

extension Income {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Income> {
        return NSFetchRequest<Income>(entityName: "Income")
    }

    @NSManaged public var date: Date?
    @NSManaged public var floatingAmount: Double
    @NSManaged public var hourlyRate: Double
    @NSManaged public var hoursWorked: Double
    @NSManaged public var id: UUID?
    @NSManaged public var notes: String?
    @NSManaged public var tips: Double
    @NSManaged public var type: String?
    @NSManaged public var note: String?

}

extension Income : Identifiable {

}
