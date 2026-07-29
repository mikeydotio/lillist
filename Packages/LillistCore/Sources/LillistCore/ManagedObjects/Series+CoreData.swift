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
    /// Typed read accessor over `ruleJSON`. Returns `nil` if the JSON is
    /// missing or malformed (caller should treat that as a data-corruption
    /// signal). Read-only — see `setRule(_:)` for why the write side is a
    /// throwing method rather than this property's setter (L6).
    public var rule: RecurrenceRule? {
        guard let json = ruleJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RecurrenceRule.self, from: data)
    }

    /// Encodes `newValue` into `ruleJSON`, throwing on failure instead of
    /// silently clearing the rule (L6). The former `rule` setter used
    /// `try?` and fell back to `ruleJSON = nil` on any encode error —
    /// symptom-masking that would permanently drop a series' recurrence
    /// data with no signal, unlike this codebase's sibling JSON-column
    /// pattern (`SmartFilterStore.encode(_:)`/`.decode(_:)`), which already
    /// throws. `ruleJSON` is left untouched until the encode succeeds, so a
    /// failure can never overwrite a previously-valid rule with `nil`.
    public func setRule(_ newValue: RecurrenceRule) throws {
        let data = try JSONEncoder().encode(newValue)
        guard let str = String(data: data, encoding: .utf8) else {
            throw LillistError.validationFailed([
                .init(field: "rule", message: "encoded JSON was not valid UTF-8")
            ])
        }
        ruleJSON = str
    }
}
