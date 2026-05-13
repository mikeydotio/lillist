import Foundation
import CoreData

@objc(Series)
public final class Series: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var ruleJSON: String?
    @NSManaged public var nextOccurrenceAfter: Date?

    @NSManaged public var seedTask: LillistTask?
    @NSManaged public var instances: NSSet?
}

extension Series {
    @objc(addInstancesObject:)
    @NSManaged public func addToInstances(_ value: LillistTask)

    @objc(removeInstancesObject:)
    @NSManaged public func removeFromInstances(_ value: LillistTask)

    @objc(addInstances:)
    @NSManaged public func addToInstances(_ values: NSSet)

    @objc(removeInstances:)
    @NSManaged public func removeFromInstances(_ values: NSSet)
}

extension Series {
    /// Typed accessor over `ruleJSON`. Returns `nil` if the JSON is missing
    /// or malformed (caller should treat that as a data-corruption signal).
    public var rule: RecurrenceRule? {
        get {
            guard let json = ruleJSON, let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(RecurrenceRule.self, from: data)
        }
        set {
            if let newValue,
               let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                ruleJSON = str
            } else {
                ruleJSON = nil
            }
        }
    }
}
