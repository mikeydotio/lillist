import Foundation
import CoreData

/// Periodic persistent-history sweep for `.localOnly` stores.
///
/// Persistent-history tracking stays ON for `.localOnly` stores so the
/// sync-mode swap is a pure description mutation (see
/// `PersistenceController.makeStoreDescription`). With nothing consuming
/// the history, transactions accumulate unbounded. This pruner reads the
/// current token, deletes everything before it, and persists the token as
/// `Data` so a re-run is idempotent.
///
/// When `syncMode == .iCloudSync`, `NSPersistentCloudKitContainer` owns
/// history pruning (it trims behind its own export cursor), so the sweep
/// is a deliberate no-op.
///
/// `NSPersistentHistoryToken` is not `Sendable`: it is read, used, and
/// archived to `Data` entirely inside a single `perform`; only the `Data`
/// crosses the closure boundary.
public final class HistoryPruner: @unchecked Sendable {
    /// `UserDefaults` key under which the last pruned token is stored as
    /// `Data`. Using a reverse-DNS prefix ensures the key is collision-free
    /// across all suites used by the app and its extensions.
    public static let tokenDefaultsKey = "io.mikeydotio.lillist.history.prunedToken"

    private let persistence: PersistenceController
    private let syncMode: SyncMode
    private let defaults: UserDefaults

    /// Designated initialiser. Inject any `UserDefaults` suite — the app
    /// uses the App Group suite; tests pass ephemeral suites.
    public init(persistence: PersistenceController, syncMode: SyncMode, defaults: UserDefaults) {
        self.persistence = persistence
        self.syncMode = syncMode
        self.defaults = defaults
    }

    /// Convenience initialiser using App Group `UserDefaults`. Returns `nil`
    /// when the group container is unreachable (e.g. missing entitlement).
    public convenience init?(persistence: PersistenceController, syncMode: SyncMode, appGroupID: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        self.init(persistence: persistence, syncMode: syncMode, defaults: defaults)
    }

    /// Sweeps persistent history for `.localOnly` stores.
    ///
    /// - Returns: `true` if a prune was executed (regardless of how many
    ///   transactions were deleted), `false` if skipped because the store
    ///   is in `.iCloudSync` mode.
    /// - Throws: Core Data errors from `NSPersistentHistoryChangeRequest`
    ///   execution or `NSKeyedArchiver` encoding failures.
    @discardableResult
    public func sweep() async throws -> Bool {
        guard syncMode == .localOnly else { return false }
        let ctx = persistence.makeBackgroundContext()
        let coordinator = persistence.container.persistentStoreCoordinator
        let key = Self.tokenDefaultsKey
        let archived: Data? = try await ctx.perform {
            guard let token = coordinator.currentPersistentHistoryToken(fromStores: nil) else {
                // No token means the store has no history yet (empty or
                // tracking was just enabled). Return nil so we skip the
                // defaults write; the sweep still counts as having run.
                return nil
            }
            let request = NSPersistentHistoryChangeRequest.deleteHistory(before: token)
            _ = try ctx.execute(request)
            return try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
        }
        if let archived {
            defaults.set(archived, forKey: key)
        }
        return true
    }
}
