import Foundation
import CoreData

/// Reacts to `NSPersistentStoreRemoteChange` notifications by diffing the
/// persistent-history stream and enqueuing notification reconciliation for the
/// tasks whose `NotificationSpec.lastFiredAt` a *CloudKit import* changed.
///
/// Why this exists (review notif-2, persist-2 §92): when device A delivers a
/// notification it writes `lastFiredAt`. Device B only learns of that fire via
/// CloudKit; without a remote-change-driven reconcile, B keeps its now-stale
/// pending request and the user gets a duplicate. This reconciler closes that
/// loop. It deliberately ignores self-authored transactions (matched against
/// `PersistenceController.localTransactionAuthor`) so an app's own writes don't
/// trigger a redundant reconcile cycle.
///
/// `@unchecked Sendable`: the only mutable state (the observer token and the
/// token watermark) is touched on the main actor in `start()`/`stop()` and the
/// token store is itself thread-safe.
public final class RemoteChangeReconciler: @unchecked Sendable {
    /// A flattened, Sendable view of one persistent-history change — either
    /// extracted from a real `NSPersistentHistoryChange` or constructed by a
    /// test. Keeps the diffing core pure and container-free.
    public struct SyntheticChange: Sendable {
        public let changedObjectID: NSManagedObjectID
        public let entityName: String
        public let changedProperties: Set<String>
        public let author: String?

        public init(
            changedObjectID: NSManagedObjectID,
            entityName: String,
            changedProperties: Set<String>,
            author: String?
        ) {
            self.changedObjectID = changedObjectID
            self.entityName = entityName
            self.changedProperties = changedProperties
            self.author = author
        }
    }

    private let persistence: PersistenceController
    private let tokenStore: PersistentHistoryTokenStore
    private let onAffectedTasks: @Sendable ([UUID]) async -> Void
    private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - persistence: the live controller (its `viewContext` is used to fetch
    ///     history and resolve `NotificationSpec` → `taskID`).
    ///   - tokenStore: watermark persistence so diffing resumes across launches.
    ///   - onAffectedTasks: callback invoked with the unique affected task ids.
    ///     The app wires this to `scheduler.reconcile(taskID:)` per id.
    public init(
        persistence: PersistenceController,
        tokenStore: PersistentHistoryTokenStore,
        onAffectedTasks: @escaping @Sendable ([UUID]) async -> Void
    ) {
        self.persistence = persistence
        self.tokenStore = tokenStore
        self.onAffectedTasks = onAffectedTasks
    }

    /// Begin observing `NSPersistentStoreRemoteChange`. Call once at bootstrap.
    public func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.processPendingHistory() }
        }
    }

    /// Stop observing. Optional in production (`[weak self]` makes a stale token
    /// a no-op), but lets tests/teardown be deterministic.
    public func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    deinit { stop() }

    /// Walk history since the last watermark, compute affected task ids, advance
    /// the watermark, and fire the callback. Public so the app can also call it
    /// once at launch (catch-up for changes that arrived while not running).
    public func processPendingHistory() async {
        let ctx = persistence.container.viewContext
        let (changes, newToken): ([SyntheticChange], NSPersistentHistoryToken?)
        do {
            (changes, newToken) = try await ctx.perform { [weak self] in
                guard let self else { return ([], nil) }
                // Read the watermark inside the perform block so the non-Sendable
                // NSPersistentHistoryToken is never captured across the @Sendable
                // boundary (Swift 6 strict concurrency).
                let after = self.tokenStore.lastToken
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: after)
                guard let result = try ctx.execute(request) as? NSPersistentHistoryResult,
                      let transactions = result.result as? [NSPersistentHistoryTransaction]
                else { return ([], nil) }
                var flattened: [SyntheticChange] = []
                for txn in transactions {
                    for change in txn.changes ?? [] {
                        let name = change.changedObjectID.entity.name ?? ""
                        flattened.append(
                            SyntheticChange(
                                changedObjectID: change.changedObjectID,
                                entityName: name,
                                changedProperties: change.updatedProperties.map { Set($0.map(\.name)) } ?? [],
                                author: txn.author
                            )
                        )
                    }
                }
                return (flattened, transactions.last?.token)
            }
        } catch {
            return   // transient store error; next remote change retries
        }

        let affected = (try? await Self.affectedTaskIDs(
            from: changes,
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )) ?? []

        if let newToken {
            tokenStore.lastToken = newToken
        }
        if affected.isEmpty == false {
            await onAffectedTasks(affected)
        }
    }

    /// Pure-ish diffing core (no NotificationCenter, no live CloudKit): given a
    /// flat change list, return the de-duplicated, order-stable list of task ids
    /// whose `NotificationSpec.lastFiredAt` a foreign-author change touched.
    ///
    /// `nonisolated static` so XCTest / background callers can use it without
    /// crossing an actor boundary (CLAUDE.md UI-layer note generalizes here).
    public nonisolated static func affectedTaskIDs(
        from changes: [SyntheticChange],
        localAuthor: String,
        in ctx: NSManagedObjectContext
    ) async throws -> [UUID] {
        await ctx.perform {
            var ordered: [UUID] = []
            var seen: Set<UUID> = []
            for change in changes {
                guard change.entityName == "NotificationSpec" else { continue }
                guard change.author != localAuthor else { continue }
                guard change.changedProperties.contains("lastFiredAt") else { continue }
                guard let spec = try? ctx.existingObject(with: change.changedObjectID) as? NotificationSpec
                else { continue }
                guard let taskID = spec.task?.id else { continue }
                if seen.insert(taskID).inserted {
                    ordered.append(taskID)
                }
            }
            return ordered
        }
    }
}
