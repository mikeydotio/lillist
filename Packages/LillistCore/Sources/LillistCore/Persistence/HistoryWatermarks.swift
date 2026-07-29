import Foundation

/// Bundles every `UserDefaults`-backed persistent-history watermark this
/// process's consumers maintain, so a destructive store reset/rebuild
/// (data-sync-hardening `X11`) can clear them all in one call instead of
/// each reset/migration path reaching into three-plus separate keys by
/// hand.
///
/// After a store is destroyed and rebuilt, every one of these watermarks
/// points at a transaction log that no longer exists — silently deaf
/// (nothing left to consume) or a full unbounded replay, with no error
/// surfaced either way. Only the ops that actually destroy/rebuild the
/// store need this: `DataStoreResetService`'s reset flavors (always) and
/// `MigrationCoordinator`'s `.replaceLocalWithICloud` (the one migration
/// op that calls `rebuildEmptyStore()` — the other three tear down and
/// reattach the *same* on-disk file, so their watermarks stay valid and
/// must NOT be cleared).
///
/// **Not exhaustive by construction** — a future consumer that adds its
/// own `PersistentHistoryTokenStore` must be added here by hand. `5c`
/// (`watermark-registry-pruning`) formalizes a real `WatermarkRegistry`
/// consumers register themselves into; this type is the deliberately
/// narrow seam until then.
///
/// `@unchecked Sendable`: `UserDefaults` is documented thread-safe (like
/// every other type in this codebase that holds one — see
/// `AppliedEventStore`/`ResetEventDeadLetterStore`) but isn't marked
/// `Sendable` by Apple; `PersistentHistoryTokenStore` is itself
/// `@unchecked Sendable` for the identical reason.
public struct HistoryWatermarks: @unchecked Sendable {
    private let reconciler: PersistentHistoryTokenStore
    private let diagnostics: PersistentHistoryTokenStore
    private let backup: PersistentHistoryTokenStore
    private let prunerDefaults: UserDefaults

    /// - Parameters:
    ///   - reconciler: keyed with `PersistentHistoryTokenStore.defaultKey` —
    ///     `RemoteChangeReconciler`'s watermark.
    ///   - diagnostics: keyed with `PersistentHistoryTokenStore.diagnosticsKey`
    ///     — `DiagnosticHistoryObserver`'s watermark.
    ///   - backup: keyed with `PersistentHistoryTokenStore.backupKey` —
    ///     `LocalBackupCoordinator`'s watermark.
    ///   - prunerDefaults: the same `UserDefaults` suite `HistoryPruner` was
    ///     constructed with. Its `tokenDefaultsKey` is write-only bookkeeping
    ///     today (`HistoryPruner.sweep()` never reads it back to resume —
    ///     verified against source), not a live replay/deaf-consumer bug
    ///     like the other three — cleared anyway for hygiene, so a future
    ///     change to `sweep()` that started reading it back doesn't
    ///     silently inherit this defect.
    public init(
        reconciler: PersistentHistoryTokenStore,
        diagnostics: PersistentHistoryTokenStore,
        backup: PersistentHistoryTokenStore,
        prunerDefaults: UserDefaults
    ) {
        self.reconciler = reconciler
        self.diagnostics = diagnostics
        self.backup = backup
        self.prunerDefaults = prunerDefaults
    }

    /// Clear every watermark. Call once a store destroy/rebuild has
    /// completed successfully.
    public func clearAll() {
        reconciler.lastToken = nil
        diagnostics.lastToken = nil
        backup.lastToken = nil
        prunerDefaults.removeObject(forKey: HistoryPruner.tokenDefaultsKey)
    }
}
