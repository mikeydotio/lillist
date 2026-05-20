import Foundation
import CloudKit

/// Production `CloudKitZoneEraser` that talks to a real CKContainer.
///
/// Mode-switch flows that wipe iCloud (`.replaceICloudWithLocal`)
/// call this. The implementation:
///
/// 1. Resolves the container's private database
///    (`CKContainer(identifier:).privateCloudDatabase`).
/// 2. Fetches all custom record zones via `recordZones(matching:)`
///    with a predicate that excludes the default-zone (`_defaultZone`).
/// 3. Filters to the `com.apple.coredata.cloudkit.zone` zone(s) that
///    Core Data mirroring creates.
/// 4. Deletes each zone via `deleteRecordZone(withID:)` — subscriptions
///    and CKAssets are reclaimed automatically.
///
/// Progress is reported as the fraction of zones deleted so far.
/// Errors propagate; the caller (`MigrationCoordinator`) treats any
/// thrown error as a hard failure and marks the journal `.failed`.
public struct LiveCloudKitZoneEraser: CloudKitZoneEraser {
    public init() {}

    public func eraseManagedZones(
        in containerIdentifier: String,
        progress: @Sendable (Double) async -> Void
    ) async throws -> CloudKitEraseSummary {
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase

        // Step 1: enumerate every custom zone in the private DB.
        let allZones = try await Self.fetchAllCustomZones(in: database)
        // Step 2: keep only zones that Core Data's CloudKit mirror
        // owns. The mirror's zone name is documented to start with
        // `com.apple.coredata.cloudkit.zone`.
        let managed = allZones.filter { $0.zoneName.hasPrefix("com.apple.coredata.cloudkit.zone") }

        guard !managed.isEmpty else {
            await progress(1.0)
            return CloudKitEraseSummary(zoneIDs: [])
        }

        await progress(0.0)
        var deleted: [CKRecordZone.ID] = []
        for (index, zoneID) in managed.enumerated() {
            try await database.deleteRecordZone(withID: zoneID)
            deleted.append(zoneID)
            let fraction = Double(index + 1) / Double(managed.count)
            await progress(fraction)
        }
        return CloudKitEraseSummary(zoneIDs: deleted)
    }

    private static func fetchAllCustomZones(in database: CKDatabase) async throws -> [CKRecordZone.ID] {
        // `recordZones(matching:)` arrived in iOS 15 / macOS 12 — but
        // the `(matching: NSPredicate, inZoneWith: nil)` variant uses
        // the older `CKFetchRecordZonesOperation` API that returned a
        // dictionary. The simpler and well-supported call is
        // `allRecordZones()`, which returns every custom zone in the
        // database. We filter `_defaultZone` out by id.
        let zones = try await database.allRecordZones()
        return zones
            .map(\.zoneID)
            .filter { $0.zoneName != CKRecordZone.ID.defaultZoneName }
    }
}
