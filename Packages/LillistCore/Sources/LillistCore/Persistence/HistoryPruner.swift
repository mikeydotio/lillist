import Foundation
import CoreData

/// Periodic persistent-history sweep for `.localOnly` stores.
///
/// Persistent-history tracking stays ON for `.localOnly` stores so the
/// sync-mode swap is a pure description mutation (see
/// `PersistenceController.makeStoreDescription`). With nothing consuming
/// the history, transactions accumulate unbounded.
///
/// **Prunes to `WatermarkRegistry.pruneBoundary(in:)`, never to "now"**
/// (data-sync-hardening `X12`/`L7`). The pruner used to delete everything
/// before the coordinator's current token, correct only because both apps'
/// `bootstrap()` happens to run every history consumer's catch-up before
/// the sweep call — a property no compiler or test enforced, and one a
/// Share Extension write landing while the main app was closed could
/// silently violate. Consulting the registry instead means a consumer that
/// hasn't caught up yet (or has no watermark at all) provably blocks the
/// sweep, rather than merely happening to have run first. See the plan
/// doc's semantics table for every case:
/// `docs/superpowers/plans/2026-07-28-plan-5c-watermark-registry-pruning.md`.
///
/// When `syncMode == .iCloudSync`, `NSPersistentCloudKitContainer` owns
/// history pruning (it trims behind its own export cursor), so the sweep
/// is a deliberate no-op.
///
/// `NSPersistentHistoryToken` is not `Sendable`: it is read, used, and
/// consumed entirely inside a single `perform`; only `SweepOutcome` (a
/// plain enum) crosses the closure boundary.
public final class HistoryPruner: @unchecked Sendable {
    /// Retired bookkeeping key from before `5c` — `sweep()` never read it
    /// back even then (confirmed by source read; `L7`'s "dead write" half).
    /// Kept only so `WatermarkRegistry.clearAll()` can purge it from any
    /// install that wrote it before this plan; nothing writes it again.
    static let legacyBookkeepingKey = "app.lillist.history.prunedToken"

    /// The outcome of one `sweep()` call.
    public enum SweepOutcome: Sendable, Equatable {
        /// Deleted every history transaction strictly before the registry's
        /// computed boundary.
        case pruned
        /// Skipped: `syncMode == .iCloudSync` — CloudKit owns pruning.
        case skippedICloudSync
        /// Skipped: the store currently retains no history at all
        /// (fresh/empty, or already fully pruned to the frontier).
        case skippedNoHistory
        /// Skipped: no safe boundary could be established this cycle — at
        /// least one registered consumer has no watermark yet, or a
        /// watermark could not be located in currently retained history.
        /// Never a data-loss risk; see the plan doc's semantics table.
        case skippedNoSafeBoundary
    }

    private let persistence: PersistenceController
    private let syncMode: SyncMode
    private let registry: WatermarkRegistry

    /// Designated initialiser. Inject any `WatermarkRegistry` — the app uses
    /// one backed by the App Group suite; tests pass one backed by an
    /// ephemeral suite.
    public init(persistence: PersistenceController, syncMode: SyncMode, registry: WatermarkRegistry) {
        self.persistence = persistence
        self.syncMode = syncMode
        self.registry = registry
    }

    /// Convenience initialiser using an App-Group-backed `WatermarkRegistry`.
    /// Returns `nil` when the group container is unreachable (e.g. missing
    /// entitlement) — matches the prior initializer's failure shape exactly.
    public convenience init?(persistence: PersistenceController, syncMode: SyncMode, appGroupID: String) {
        guard UserDefaults(suiteName: appGroupID) != nil else { return nil }
        self.init(persistence: persistence, syncMode: syncMode, registry: WatermarkRegistry(appGroupID: appGroupID))
    }

    /// Sweeps persistent history for `.localOnly` stores.
    ///
    /// - Returns: what happened — see `SweepOutcome`.
    /// - Throws: Core Data errors from `NSPersistentHistoryChangeRequest`
    ///   execution.
    @discardableResult
    public func sweep() async throws -> SweepOutcome {
        guard syncMode == .localOnly else { return .skippedICloudSync }
        let ctx = persistence.makeBackgroundContext()
        let registry = registry
        let boundary = try await ctx.perform { try registry.pruneBoundary(in: ctx) }
        switch boundary {
        case .noHistory:
            return .skippedNoHistory
        case .unresolved:
            return .skippedNoSafeBoundary
        case .boundary(let token):
            try await ctx.perform {
                let request = NSPersistentHistoryChangeRequest.deleteHistory(before: token)
                _ = try ctx.execute(request)
            }
            return .pruned
        }
    }
}
