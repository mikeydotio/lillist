import Foundation
import CloudKit

/// Summary of the CloudKit zones that an eraser deleted in a single
/// `eraseManagedZones` call.
public struct CloudKitEraseSummary: Sendable, Equatable {
    public let zoneIDs: [CKRecordZone.ID]

    public init(zoneIDs: [CKRecordZone.ID]) {
        self.zoneIDs = zoneIDs
    }

    public var count: Int { zoneIDs.count }
}

/// Erases the CloudKit zones that `NSPersistentCloudKitContainer`
/// uses to mirror Core Data. The protocol exists so `MigrationCoordinator`
/// can be tested without hitting a real CloudKit container.
///
/// Per the Plan 21 architecture (skeptic A2): callers must **not**
/// loop `CKModifyRecordsOperation` per entity. Zone deletion reclaims
/// every record + asset under the zone in one round-trip; that's the
/// only correct way to wipe the mirror cheaply.
public protocol CloudKitZoneEraser: Sendable {
    func eraseManagedZones(
        in containerIdentifier: String,
        progress: @Sendable (Double) async -> Void
    ) async throws -> CloudKitEraseSummary
}
