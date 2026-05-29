import Foundation

/// The minimal surface `MigrationCoordinator` needs from the
/// persistence layer: read the canonical sync mode and run the
/// structural store swap.
///
/// Plan 21 hardening: extracting this seam lets `runMigration` and
/// `restoreFromBackup` run end-to-end under `swift test` against a
/// `FakePersistenceReconfigurer`, instead of requiring a live
/// `NSPersistentCloudKitContainer` (whose `NSCloudKitMirroringDelegate`
/// teardown crashes the swift-test binary — see `StoreLevelModeSwapSpike`
/// for the long version). `PersistenceHost` is the production conformer;
/// the live container swap stays covered by the host-gated tests.
///
/// Both members are `async` because the production conformer is an
/// `actor`; conformers are `Sendable` so the coordinator can hold one
/// across the `@MainActor` boundary.
public protocol PersistenceReconfiguring: Sendable {
    /// The canonical sync mode the underlying store is currently
    /// attached as.
    var currentMode: SyncMode { get async }

    /// Switch the underlying store to `newMode`. Implementations must
    /// be transactional: on any failure the store stays attached in
    /// its pre-call mode (no store-less coordinator).
    func reconfigure(to newMode: SyncMode) async throws
}
