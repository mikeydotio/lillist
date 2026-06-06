import Foundation
import CoreData

/// Derives data-layer diagnostic events from the persistent-history stream and
/// forwards them to a `DiagnosticSink`. Structurally a clone of
/// `RemoteChangeReconciler`'s consumption pattern (observe
/// `NSPersistentStoreRemoteChange`, read the watermark *inside* `ctx.perform`,
/// fetch history, advance the watermark) but with three differences:
///
/// 1. **Own watermark.** It uses `PersistentHistoryTokenStore.diagnosticsKey`,
///    never the reconciler's key, so the two consumers don't clobber each other.
/// 2. **No author filter.** The reconciler skips self-authored transactions; the
///    observer records *every* writer (the attribution is the whole point) and
///    stamps each event's `author` payload with the transaction author.
/// 3. **Net-new on macOS**, where no `RemoteChangeReconciler` exists.
///
/// `@unchecked Sendable`: the observer token is touched on the main actor in
/// `start()`/`stop()`, the token store is thread-safe, and the `seq` counter is
/// lock-guarded.
public final class DiagnosticHistoryObserver: @unchecked Sendable {
    /// A flattened, `Sendable` view of one history change — resolved against the
    /// live context *inside* `perform`, then handed to the pure event builder.
    public struct HistoryChange: Sendable {
        public let entityName: String
        public let op: String              // "insert" | "update" | "delete"
        public let objectUUID: UUID?
        public let changedProps: [String]
        public let position: Double?
        public let author: String?
        public let at: Date

        public init(entityName: String, op: String, objectUUID: UUID?, changedProps: [String], position: Double?, author: String?, at: Date) {
            self.entityName = entityName
            self.op = op
            self.objectUUID = objectUUID
            self.changedProps = changedProps
            self.position = position
            self.author = author
            self.at = at
        }
    }

    private let persistence: PersistenceController
    private let tokenStore: PersistentHistoryTokenStore
    private let sink: DiagnosticSink
    private let process: DiagProcess
    private var observer: NSObjectProtocol?

    private let seqLock = NSLock()
    private var nextSeq: UInt64 = 0

    /// Serializes drains. A burst of `NSPersistentStoreRemoteChange`
    /// notifications spawns several `Task { await processPendingHistory() }`
    /// calls on arbitrary threads; without this they would race the split token
    /// read-modify-write (read inside `perform`, advance after the emit loop —
    /// two suspension points apart) and double-emit the same history into the
    /// append-only log. The gate lets exactly one drain run at a time and
    /// coalesces overlapping requests into a single follow-up pass, so no change
    /// is ever emitted twice or missed.
    private let drainGate = DrainGate()

    /// Actor gate guarding the single-drain invariant. An actor (not a lock)
    /// because the call sites are `async`, where `NSLock.lock()` is unavailable.
    private actor DrainGate {
        private var isDraining = false
        private var rerunRequested = false
        /// `true` if the caller becomes the owning drainer; `false` if a drain is
        /// already in flight (a coalesced rerun is requested instead).
        func tryAcquire() -> Bool {
            if isDraining { rerunRequested = true; return false }
            isDraining = true
            return true
        }
        /// `true` if the owner should sweep again (a request arrived mid-drain).
        func finishOrRerun() -> Bool {
            if rerunRequested { rerunRequested = false; return true }
            isDraining = false
            return false
        }
    }

    /// - Parameters:
    ///   - persistence: the live controller; its `viewContext` fetches history.
    ///   - tokenStore: watermark persistence — pass one keyed with
    ///     `PersistentHistoryTokenStore.diagnosticsKey`.
    ///   - sink: where derived events go (the process `DiagnosticLog` in prod).
    ///   - process: the *observing* process; stamped on each event's `process`
    ///     field (the writing process is captured separately in `author`).
    public init(
        persistence: PersistenceController,
        tokenStore: PersistentHistoryTokenStore,
        sink: DiagnosticSink,
        process: DiagProcess
    ) {
        self.persistence = persistence
        self.tokenStore = tokenStore
        self.sink = sink
        self.process = process
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

    public func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    deinit { stop() }

    /// Walk history since the last watermark, emit one event per change, advance
    /// the watermark. Public so the host can run a catch-up pass at launch.
    ///
    /// Reentrancy-safe: only one drain runs at a time. If a call arrives while a
    /// drain is in flight it requests a single coalesced follow-up pass and
    /// returns, so overlapping notifications never double-emit and a change that
    /// lands mid-drain is still picked up. The lock is only ever held across
    /// synchronous flag checks — never across an `await`.
    public func processPendingHistory() async {
        guard await drainGate.tryAcquire() else { return }
        while true {
            await drainOnce()
            if await drainGate.finishOrRerun() { continue }   // change landed mid-drain; sweep again
            return
        }
    }

    /// One serialized read-fetch-emit-advance pass. Only ever called by the
    /// single owning `processPendingHistory` loop, so the token read (inside
    /// `perform`) and advance (after the emit loop) are atomic w.r.t. other
    /// drains despite the intervening suspension points.
    private func drainOnce() async {
        let ctx = persistence.container.viewContext
        let (changes, newToken): ([HistoryChange], NSPersistentHistoryToken?)
        do {
            (changes, newToken) = try await ctx.perform { [weak self] in
                guard let self else { return ([], nil) }
                // Read the watermark inside `perform` so the non-Sendable token
                // never crosses the @Sendable boundary (Swift 6 strict concurrency).
                let after = self.tokenStore.lastToken
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: after)
                guard let result = try ctx.execute(request) as? NSPersistentHistoryResult,
                      let transactions = result.result as? [NSPersistentHistoryTransaction]
                else { return ([], nil) }
                return (Self.flatten(transactions, in: ctx), transactions.last?.token)
            }
        } catch {
            return   // transient store error; the next remote change retries
        }

        guard changes.isEmpty == false else {
            if let newToken { tokenStore.lastToken = newToken }
            return
        }
        let base = reserveSeqs(changes.count)
        let events = Self.makeEvents(from: changes, process: process, startingSeq: base)
        for event in events { await sink.log(event) }
        if let newToken { tokenStore.lastToken = newToken }
    }

    private func reserveSeqs(_ count: Int) -> UInt64 {
        seqLock.lock(); defer { seqLock.unlock() }
        let base = nextSeq
        nextSeq += UInt64(count)
        return base
    }

    /// Resolve each `NSPersistentHistoryChange` against the live context. Must be
    /// called inside `ctx.perform`. Reads `id`/`position` defensively via
    /// `attributesByName` — `value(forKey:)` on an undeclared key raises an
    /// uncatchable Obj-C exception, so it is guarded, never assumed.
    private static func flatten(_ transactions: [NSPersistentHistoryTransaction], in ctx: NSManagedObjectContext) -> [HistoryChange] {
        var out: [HistoryChange] = []
        for txn in transactions {
            for change in txn.changes ?? [] {
                let entity = change.changedObjectID.entity
                let entityName = entity.name ?? ""
                let op = opName(change.changeType)
                let props = change.updatedProperties.map { $0.map(\.name) } ?? []
                var uuid: UUID?
                var position: Double?
                if change.changeType == .delete {
                    // Tombstones only carry attributes flagged
                    // `preserveValueInHistoryOnDeletion` in the model; `id` is not
                    // (yet) flagged, so delete events currently resolve a nil
                    // objectUUID and are attributed by entity + author only.
                    // Enabling preservation is a model change (+ CloudKit-store
                    // migration risk) deferred as a follow-up; not RCA-critical,
                    // since the reorder tie is a *create*-time signal.
                    uuid = change.tombstone?["id"] as? UUID
                } else if let obj = try? ctx.existingObject(with: change.changedObjectID) {
                    if entity.attributesByName["id"] != nil { uuid = obj.value(forKey: "id") as? UUID }
                    // Capture position for every LillistTask insert/update, not just
                    // when "position" is in changedProps: the RCA tie is a *create-time*
                    // position, so insert events (whose updatedProperties are nil) must
                    // still record where the row landed.
                    if entityName == "LillistTask", entity.attributesByName["position"] != nil {
                        position = obj.value(forKey: "position") as? Double
                    }
                }
                out.append(HistoryChange(
                    entityName: entityName,
                    op: op,
                    objectUUID: uuid,
                    changedProps: props,
                    position: position,
                    author: txn.author,
                    at: txn.timestamp
                ))
            }
        }
        return out
    }

    private static func opName(_ type: NSPersistentHistoryChangeType) -> String {
        switch type {
        case .insert: return "insert"
        case .update: return "update"
        case .delete: return "delete"
        @unknown default: return "unknown"
        }
    }

    /// Pure event builder: no context, no I/O. `nonisolated static` so tests can
    /// exercise it directly. Names events `<entity>.<op>` and attaches author,
    /// object UUID, changed-property list, and (for `position` writes) the value.
    public nonisolated static func makeEvents(from changes: [HistoryChange], process: DiagProcess, startingSeq: UInt64) -> [DiagnosticEvent] {
        var seq = startingSeq
        return changes.map { change in
            var payload: [String: DiagValue] = [
                "author": change.author.map(DiagValue.string) ?? .null,
                "objectUUID": change.objectUUID.map { DiagValue.string($0.uuidString) } ?? .null,
                "changedProps": .string(change.changedProps.sorted().joined(separator: ",")),
            ]
            if let position = change.position { payload["position"] = .double(position) }
            let event = DiagnosticEvent(
                at: change.at,
                seq: seq,
                process: process,
                category: .data,
                name: "\(change.entityName).\(change.op)",
                payload: payload
            )
            seq += 1
            return event
        }
    }
}
