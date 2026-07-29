import Foundation
import CoreData

/// Every persistent-history consumer this app registers, keyed by a closed
/// enum so a `PersistentHistoryTokenStore` can only ever be constructed with
/// a case declared here — never an arbitrary `String`. Adding a fourth
/// history consumer means adding a case to this enum; there is no other way
/// to build a watermark store, so an off-registry key can no longer be
/// typo'd into production (data-sync-hardening `X12`/`L7`).
public enum HistoryConsumerID: String, CaseIterable, Sendable {
    /// `RemoteChangeReconciler`'s watermark — the historical default key.
    case remoteChangeReconciler = "app.lillist.persistentHistoryToken"
    /// `DiagnosticHistoryObserver`'s watermark.
    case diagnostics = "app.lillist.diagnostics.historyToken"
    /// `LocalBackupCoordinator`'s watermark.
    case backup = "app.lillist.backup.historyToken"

    /// The `UserDefaults` key this consumer's watermark is stored under.
    public var tokenDefaultsKey: String { rawValue }
}

/// The formal registry of every `PersistentHistoryTokenStore`-backed history
/// consumer sharing this app's App Group `UserDefaults` suite — the
/// successor to the deliberately narrow, hand-maintained `HistoryWatermarks`
/// seam `3b` landed ahead of this plan (see that type's own now-removed doc
/// comment, and the ledger's Wave 3b closing report).
///
/// Two jobs:
/// 1. **Reset hygiene** (`X11`, unchanged from `HistoryWatermarks`) —
///    `clearAll()` nils every registered consumer's watermark after a
///    destructive store rebuild.
/// 2. **Safe pruning** (`X12`/`L7`, new) — `pruneBoundary(in:)` gives
///    `HistoryPruner` the one boundary it needs: the earliest transaction
///    any *registered* consumer has recorded as its own watermark, read
///    fresh from `UserDefaults` every call. `HistoryPruner` used to delete
///    everything before "now," correct only because both apps' `bootstrap()`
///    happens to run every consumer's catch-up before the sweep — a
///    property no compiler or test enforced. Consulting this registry
///    instead makes that safety property true by construction, independent
///    of bootstrap ordering.
///
/// See `docs/superpowers/plans/2026-07-28-plan-5c-watermark-registry-pruning.md`
/// for the full design, including the fresh-consumer fail-safe semantics
/// table and why `NSPersistentHistoryToken`'s lack of a public ordering API
/// makes `pruneBoundary(in:)`'s full-history scan the correct approach
/// rather than a direct token comparison.
///
/// `@unchecked Sendable`: `UserDefaults` is documented thread-safe (like
/// every other type in this codebase that holds one) but isn't marked
/// `Sendable` by Apple; `PersistentHistoryTokenStore` is itself
/// `@unchecked Sendable` for the identical reason.
public struct WatermarkRegistry: @unchecked Sendable {
    /// One registered consumer's current watermark.
    public struct ConsumerWatermark: Sendable {
        public let id: HistoryConsumerID
        public let token: NSPersistentHistoryToken?

        public init(id: HistoryConsumerID, token: NSPersistentHistoryToken?) {
            self.id = id
            self.token = token
        }
    }

    /// The result of asking the registry for a safe history-prune boundary.
    public enum PruneBoundary: Sendable {
        /// Safe to prune: delete every history transaction strictly before
        /// this token. Always the earliest transaction any registered
        /// consumer has recorded as its own watermark.
        case boundary(NSPersistentHistoryToken)
        /// Nothing to prune — the store currently retains no history at all
        /// (fresh/empty, or already fully pruned to the frontier).
        case noHistory
        /// Fail-safe: at least one registered consumer has no recorded
        /// watermark yet, or a recorded watermark could not be located in
        /// the currently retained history. Never prune in either case — see
        /// the plan doc's semantics table for the full rationale.
        case unresolved
    }

    private let tokenStores: [HistoryConsumerID: PersistentHistoryTokenStore]
    private let prunerDefaults: UserDefaults

    /// Backed by the App Group's shared defaults — the production shape,
    /// matching the exact suite every real consumer already uses.
    public init(appGroupID: String) {
        self.init(
            tokenStores: Dictionary(
                uniqueKeysWithValues: HistoryConsumerID.allCases.map {
                    ($0, PersistentHistoryTokenStore(appGroupID: appGroupID, consumer: $0))
                }
            ),
            prunerDefaults: UserDefaults(suiteName: appGroupID) ?? .standard
        )
    }

    /// Backed by an explicit suite — the test shape.
    public init(suiteName: String) {
        self.init(
            tokenStores: Dictionary(
                uniqueKeysWithValues: HistoryConsumerID.allCases.map {
                    ($0, PersistentHistoryTokenStore(suiteName: suiteName, consumer: $0))
                }
            ),
            prunerDefaults: UserDefaults(suiteName: suiteName) ?? .standard
        )
    }

    private init(tokenStores: [HistoryConsumerID: PersistentHistoryTokenStore], prunerDefaults: UserDefaults) {
        self.tokenStores = tokenStores
        self.prunerDefaults = prunerDefaults
    }

    /// Every registered consumer's current watermark, read fresh — reflects
    /// writes any process sharing this App Group suite has made, not a
    /// cached snapshot from when the registry was constructed.
    public var watermarks: [ConsumerWatermark] {
        HistoryConsumerID.allCases.map { id in
            ConsumerWatermark(id: id, token: tokenStores[id]?.lastToken)
        }
    }

    /// Computes the safe prune boundary. Must run on `context`'s own queue
    /// (call from inside `context.perform`) — `NSPersistentHistoryToken` is
    /// not `Sendable`, matching every other history-token access in this
    /// codebase.
    ///
    /// Fetches the store's full currently-retained history (`fetchHistory
    /// (after: nil)`, chronologically ordered — the documented contract
    /// every consumer in this codebase already relies on) and locates the
    /// earliest-appearing registered watermark within it. Token identity is
    /// compared via `NSKeyedArchiver`-archived `Data` equality, the same
    /// technique `PersistentHistoryTokenStore` uses to persist tokens —
    /// `NSPersistentHistoryToken` has no public ordering/comparison API, so
    /// this scan (not a direct token comparison) is how "the minimum of N
    /// opaque tokens" is determined.
    public func pruneBoundary(in context: NSManagedObjectContext) throws -> PruneBoundary {
        let marks = watermarks
        guard marks.allSatisfy({ $0.token != nil }) else { return .unresolved }

        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
        guard let result = try context.execute(request) as? NSPersistentHistoryResult,
              let transactions = result.result as? [NSPersistentHistoryTransaction],
              transactions.isEmpty == false
        else { return .noHistory }

        let targets = Set(marks.compactMap { $0.token }.compactMap(Self.archive))
        for txn in transactions {
            if let data = Self.archive(txn.token), targets.contains(data) {
                return .boundary(txn.token)
            }
        }
        return .unresolved
    }

    /// Clear every registered consumer's watermark, plus `HistoryPruner`'s
    /// now-retired bookkeeping key. That key is never written again by this
    /// plan forward — this removal is one-time hygiene for any install that
    /// wrote it before `5c` (see `HistoryPruner.legacyBookkeepingKey`'s own
    /// doc comment), not a live migration path.
    public func clearAll() {
        for store in tokenStores.values { store.lastToken = nil }
        prunerDefaults.removeObject(forKey: HistoryPruner.legacyBookkeepingKey)
    }

    private static func archive(_ token: NSPersistentHistoryToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }
}

extension WatermarkRegistry.PruneBoundary: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.noHistory, .noHistory), (.unresolved, .unresolved):
            return true
        case let (.boundary(a), .boundary(b)):
            // Same-file access to `WatermarkRegistry`'s `private static
            // func archive` — Swift's `private` extends to extensions of
            // the same type within the same file.
            return WatermarkRegistry.archive(a) == WatermarkRegistry.archive(b)
        default:
            return false
        }
    }
}
