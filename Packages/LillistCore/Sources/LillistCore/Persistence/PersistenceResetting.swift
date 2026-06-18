import Foundation

/// The persistence surface a destructive *data-store reset* needs:
/// tear the live store off the coordinator (capturing a recovery
/// backup first), destroy it and rebuild an empty one, or re-attach
/// the original if a surrounding step fails.
///
/// This is deliberately **separate** from `PersistenceReconfiguring`
/// (interface-segregation): `MigrationCoordinator` only ever swaps
/// sync modes and must not gain a destroy/rebuild surface, while
/// `DataStoreResetService` only ever wipes and must not gain a
/// mode-swap surface. `PersistenceHost` conforms to both;
/// `DataStoreResetService` consumes only this one.
///
/// All members are `async` because the production conformer
/// (`PersistenceHost`) is an `actor`; conformers are `Sendable` so the
/// `@MainActor` reset service can hold one across the boundary.
public protocol PersistenceResetting: Sendable {
    /// The canonical sync mode the underlying store is currently
    /// attached as. The reset service reads it to decide whether the
    /// CloudKit zone must also be erased (only in `.iCloudSync`).
    var currentMode: SyncMode { get async }

    /// Flush pending writes, remove the live store from the
    /// coordinator (closing the SQLite connection), and — when a
    /// `QuarantineManager` is supplied — copy the now-closed files into
    /// quarantine as a recovery anchor. The copy runs the quarantine
    /// disk-space pre-flight, so this **throws before** any irreversible
    /// CloudKit erase the caller might perform next. The on-disk files
    /// are left in place (only detached) so a later failure can
    /// `reattachStore()`. Returns the backup descriptor, or `nil` when
    /// no quarantine was requested or the store file was absent.
    func tearDownStore(backupVia quarantine: QuarantineManager?) async throws -> QuarantineManager.QuarantinedBackup?

    /// Destroy the (already torn-down) store's files via
    /// `destroyPersistentStore`, add a fresh empty store for
    /// `currentMode`, and reset the view context so no stale objects
    /// survive. Must be called only after `tearDownStore`.
    func rebuildEmptyStore() async throws

    /// Re-add the original store (its files are still on disk after
    /// `tearDownStore`) for `currentMode`. Rollback path when a step
    /// between teardown and rebuild fails, so the coordinator is never
    /// left store-less.
    func reattachStore() async throws
}
