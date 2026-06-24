import Foundation
import CoreData

/// Keeps the on-disk backup package (`TaskBackupStore`) in step with the live
/// Core Data store (issue #7).
///
/// It installs two observers — one chokepoint each for local and remote writes:
///
/// 1. `NSManagedObjectContextDidSave` on the `viewContext` catches **every**
///    local commit in one place — all of `TaskStore`'s mutation methods,
///    recurrence/follow-up spawns, journal/attachment writes, and merged
///    background imports — so a future 13th mutation path can't silently skip
///    backup.
/// 2. `NSPersistentStoreRemoteChange` catches **remote** CloudKit imports from
///    other devices (cloned from `RemoteChangeReconciler`'s persistent-history
///    diff) so per-task files reflect cross-device state.
///
/// Concurrency discipline (the load-bearing part): change *identifiers*
/// (`UUID`s) are projected out of the non-`Sendable` managed objects
/// **synchronously on the posting context queue**, then all heavier work —
/// re-fetching, DTO projection (including attachment-byte reads), and disk
/// writes — happens off that queue. Re-fetching uses a background context, and
/// every disk write is serialized on the `TaskBackupStore` actor. Only value
/// types ever cross an `await`.
///
/// `@unchecked Sendable`: the only mutable state is the two observer tokens,
/// touched on the main actor in `start()`/`stop()` (same justification as
/// `RemoteChangeReconciler`).
public final class LocalBackupCoordinator: @unchecked Sendable {
    private let persistence: PersistenceController
    private let preferences: PreferencesStore
    private let store: TaskBackupStore
    private let tokenStore: PersistentHistoryTokenStore
    private let snapshotManager: BackupSnapshotManager?
    private let localAuthor: String

    private var didSaveObserver: NSObjectProtocol?
    private var remoteObserver: NSObjectProtocol?

    public init(
        persistence: PersistenceController,
        preferences: PreferencesStore,
        store: TaskBackupStore,
        tokenStore: PersistentHistoryTokenStore,
        snapshotManager: BackupSnapshotManager? = nil,
        localAuthor: String = PersistenceController.localTransactionAuthor
    ) {
        self.persistence = persistence
        self.preferences = preferences
        self.store = store
        self.tokenStore = tokenStore
        self.snapshotManager = snapshotManager
        self.localAuthor = localAuthor
    }

    /// One-call launch entry point: start observing, seed the package if it has
    /// never been written, and roll a daily snapshot if one is due. All
    /// best-effort and non-fatal — backup must never block app launch.
    public func bootstrapAtLaunch() async {
        start()
        await seedPackageIfEmpty()
        await runSnapshotIfDue()
    }

    /// Create a daily snapshot if one is due. Runs the zip off the caller's
    /// executor so it never stutters launch/foreground. No-op without a
    /// configured snapshot manager.
    public func runSnapshotIfDue() async {
        guard let snapshotManager else { return }
        _ = try? await Task.detached { try snapshotManager.createSnapshotIfDue() }.value
    }

    // MARK: - Lifecycle

    /// Begin observing local saves and remote CloudKit changes. Idempotent.
    public func start() {
        guard didSaveObserver == nil else { return }
        let center = NotificationCenter.default
        didSaveObserver = center.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: persistence.container.viewContext,
            queue: nil
        ) { [weak self] note in
            guard let self else { return }
            // Extract Sendable change identifiers synchronously on the posting
            // (view-context) queue — the managed objects in userInfo are only
            // valid here. Reading `id`/`objectID` does not fault attributes.
            let change = Self.extractChange(from: note)
            guard change.hasWork else { return }
            Task { await self.applyLocalChange(change) }
        }
        remoteObserver = center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.processRemoteChange() }
        }
    }

    /// Stop observing. `[weak self]` makes a stale token a no-op in production;
    /// explicit for deterministic test teardown.
    public func stop() {
        let center = NotificationCenter.default
        if let didSaveObserver { center.removeObserver(didSaveObserver) }
        if let remoteObserver { center.removeObserver(remoteObserver) }
        didSaveObserver = nil
        remoteObserver = nil
    }

    deinit { stop() }

    // MARK: - Local save path

    /// A Sendable summary of one local save's task-relevant changes.
    struct LocalChange: Sendable {
        var upsertTaskIDs: [UUID]
        var deleteTaskIDs: [UUID]
        var sidecarsDirty: Bool
        var hasWork: Bool { !upsertTaskIDs.isEmpty || !deleteTaskIDs.isEmpty || sidecarsDirty }
    }

    /// Project change identifiers out of a did-save notification. Runs
    /// synchronously on the context queue; touches managed objects only to read
    /// `id` (a UUID attribute) and entity names — never bytes.
    static func extractChange(from note: Notification) -> LocalChange {
        let info = note.userInfo ?? [:]
        let inserted = (info[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? []
        let updated = (info[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? []
        let deleted = (info[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? []

        var upserts: [UUID] = []
        var deletes: [UUID] = []
        var sidecarsDirty = false

        for object in inserted.union(updated) {
            switch object.entity.name {
            case "LillistTask":
                if let id = (object as? LillistTask)?.id { upserts.append(id) }
            case "Tag", "AppPreferences":
                sidecarsDirty = true
            case "JournalEntry", "Attachment":
                if let owner = ownerTaskID(of: object) { upserts.append(owner) }
            default:
                break
            }
        }
        for object in deleted {
            switch object.entity.name {
            case "LillistTask":
                if let id = (object as? LillistTask)?.id { deletes.append(id) }
            case "Tag", "AppPreferences":
                sidecarsDirty = true
            case "JournalEntry", "Attachment":
                // A child removed without its task → the surviving task's record
                // must drop it. If the owner was also deleted, its own delete in
                // `deletes` wins (removal beats upsert in `applyLocalChange`).
                if let owner = ownerTaskID(of: object) { upserts.append(owner) }
            default:
                break
            }
        }

        return LocalChange(
            upsertTaskIDs: dedupe(upserts),
            deleteTaskIDs: dedupe(deletes),
            sidecarsDirty: sidecarsDirty
        )
    }

    private static func ownerTaskID(of object: NSManagedObject) -> UUID? {
        if let entry = object as? JournalEntry { return entry.task?.id }
        if let attachment = object as? Attachment {
            return attachment.task?.id ?? attachment.journalEntry?.task?.id
        }
        return nil
    }

    private static func dedupe(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        var ordered: [UUID] = []
        for id in ids where seen.insert(id).inserted { ordered.append(id) }
        return ordered
    }

    /// Apply a local change off the context queue: re-fetch + project upserts on
    /// a background context, then write/remove on the `TaskBackupStore` actor.
    private func applyLocalChange(_ change: LocalChange) async {
        let deleteSet = Set(change.deleteTaskIDs)
        // A task can appear in both sets if a child changed while the task was
        // deleted — removal wins.
        let toUpsert = change.upsertTaskIDs.filter { !deleteSet.contains($0) }

        let projected = await projectRecords(forTaskIDs: toUpsert)
        do {
            if !projected.records.isEmpty {
                try await store.upsert(projected.records, assets: projected.assets)
            }
            if !change.deleteTaskIDs.isEmpty {
                try await store.remove(taskIDs: change.deleteTaskIDs)
            }
            if change.sidecarsDirty {
                try await refreshSidecars()
            }
            try await updateManifest()
        } catch {
            // Backup is best-effort: a transient disk error must never surface
            // into a user mutation. The next save (or daily snapshot) reconciles.
        }
    }

    // MARK: - Remote (CloudKit) path

    /// React to a remote CloudKit change: diff persistent history for
    /// foreign-author task/tag/preference changes, upsert the changed tasks, and
    /// prune package files for tasks deleted on another device (set-difference,
    /// since history carries no UUID for deletes without tombstones).
    public func processRemoteChange() async {
        let ctx = persistence.container.viewContext
        let diff: HistoryDiff
        do {
            diff = try await ctx.perform { [self] in
                let after = tokenStore.lastToken
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: after)
                guard let result = try ctx.execute(request) as? NSPersistentHistoryResult,
                      let transactions = result.result as? [NSPersistentHistoryTransaction]
                else { return HistoryDiff(taskObjectIDs: [], sidecarsDirty: false, newToken: nil) }

                var taskObjectIDs: [NSManagedObjectID] = []
                var sidecarsDirty = false
                for txn in transactions where txn.author != localAuthor {
                    for change in txn.changes ?? [] {
                        switch change.changedObjectID.entity.name {
                        case "LillistTask":
                            if change.changeType != .delete { taskObjectIDs.append(change.changedObjectID) }
                        case "Tag", "AppPreferences":
                            sidecarsDirty = true
                        default:
                            break
                        }
                    }
                }
                return HistoryDiff(
                    taskObjectIDs: taskObjectIDs,
                    sidecarsDirty: sidecarsDirty,
                    newToken: transactions.last?.token
                )
            }
        } catch {
            return  // transient store error; the next remote change retries
        }

        // Resolve changed objectIDs → live task UUIDs (off the history fetch).
        let upsertIDs = await resolveTaskIDs(diff.taskObjectIDs)
        let projected = await projectRecords(forTaskIDs: upsertIDs)
        do {
            if !projected.records.isEmpty {
                try await store.upsert(projected.records, assets: projected.assets)
            }
            // Prune files for tasks no longer present in the live store.
            let live = await liveTaskIDs()
            let onDisk = (try? await store.taskFileIDs()) ?? []
            let stale = Array(onDisk.subtracting(live))
            if !stale.isEmpty { try await store.remove(taskIDs: stale) }
            if diff.sidecarsDirty { try await refreshSidecars() }
            try await updateManifest()
        } catch {
            return
        }

        // Advance the watermark only after a successful apply. The token store
        // is thread-safe (UserDefaults-backed), so this needs no `perform` — and
        // wrapping it in one would illegally capture the non-Sendable token in a
        // `@Sendable` closure (mirrors `RemoteChangeReconciler`).
        if let newToken = diff.newToken {
            tokenStore.lastToken = newToken
        }
    }

    private struct HistoryDiff {
        let taskObjectIDs: [NSManagedObjectID]
        let sidecarsDirty: Bool
        let newToken: NSPersistentHistoryToken?
    }

    private func resolveTaskIDs(_ objectIDs: [NSManagedObjectID]) async -> [UUID] {
        guard !objectIDs.isEmpty else { return [] }
        let ctx = persistence.makeBackgroundContext()
        return await ctx.perform {
            var ids: [UUID] = []
            for oid in objectIDs {
                if let task = try? ctx.existingObject(with: oid) as? LillistTask, let id = task.id {
                    ids.append(id)
                }
            }
            return Self.dedupe(ids)
        }
    }

    private func liveTaskIDs() async -> Set<UUID> {
        let ctx = persistence.makeBackgroundContext()
        return await ctx.perform {
            let req = NSFetchRequest<NSDictionary>(entityName: "LillistTask")
            req.resultType = .dictionaryResultType
            req.propertiesToFetch = ["id"]
            let rows = (try? ctx.fetch(req)) ?? []
            return Set(rows.compactMap { $0["id"] as? UUID })
        }
    }

    // MARK: - Seed / full reconcile

    /// Seed the package from a full store snapshot when it has no task files yet
    /// (first run, or after the package directory was cleared). Idempotent.
    public func seedPackageIfEmpty() async {
        guard await store.isEmpty() else { return }
        await reconcileFull()
    }

    /// Rebuild the entire package from the live store. Reclaims orphans.
    public func reconcileFull() async {
        let prefs = try? await preferences.read()
        let prefsDTO = prefs.map(BackupRecordProjector.preferencesDTO(from:)) ?? Self.fallbackPreferences

        let ctx = persistence.makeBackgroundContext()
        let payload: FullPayload = await ctx.perform {
            let taskReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            taskReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let taskMOs = (try? ctx.fetch(taskReq)) ?? []
            var records: [BackupPackageSchema.TaskBackupRecord] = []
            var assets: [TaskBackupStore.PendingAsset] = []
            for m in taskMOs {
                let projected = Self.project(m)
                records.append(projected.record)
                assets.append(contentsOf: projected.assets)
            }
            let tagReq = NSFetchRequest<Tag>(entityName: "Tag")
            let tags = ((try? ctx.fetch(tagReq)) ?? []).map(BackupRecordProjector.tagDTO(from:))
            return FullPayload(records: records, assets: assets, tags: tags)
        }

        try? await store.replaceAll(
            records: payload.records,
            assets: payload.assets,
            tags: payload.tags,
            preferences: prefsDTO,
            cloudKitSchemaVersion: CloudKitSchema.currentVersion,
            updatedAt: Date()
        )
    }

    private struct FullPayload: Sendable {
        let records: [BackupPackageSchema.TaskBackupRecord]
        let assets: [TaskBackupStore.PendingAsset]
        let tags: [ExportSchema.TagDTO]
    }

    // MARK: - Projection (shared by all paths)

    private struct ProjectedBatch: Sendable {
        var records: [BackupPackageSchema.TaskBackupRecord]
        var assets: [TaskBackupStore.PendingAsset]
    }

    /// Re-fetch each task UUID on a background context and project it (including
    /// its owned journal entries and attachment bytes) into Sendable records.
    /// Tasks that vanished between the save and this fetch are skipped.
    private func projectRecords(forTaskIDs ids: [UUID]) async -> ProjectedBatch {
        guard !ids.isEmpty else { return ProjectedBatch(records: [], assets: []) }
        let ctx = persistence.makeBackgroundContext()
        return await ctx.perform {
            var records: [BackupPackageSchema.TaskBackupRecord] = []
            var assets: [TaskBackupStore.PendingAsset] = []
            for id in ids {
                let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
                req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                req.fetchLimit = 1
                guard let m = try? ctx.fetch(req).first else { continue }
                let projected = Self.project(m)
                records.append(projected.record)
                assets.append(contentsOf: projected.assets)
            }
            return ProjectedBatch(records: records, assets: assets)
        }
    }

    /// Project one task into a `TaskBackupRecord` plus its attachment blobs.
    /// Must be called inside the owning context's `perform`. Attachments include
    /// both those owned directly by the task and those owned by its journal
    /// entries. Ordering is stabilized for deterministic files.
    private static func project(_ m: LillistTask) -> (record: BackupPackageSchema.TaskBackupRecord, assets: [TaskBackupStore.PendingAsset]) {
        let task = BackupRecordProjector.taskDTO(from: m)

        let journalMOs = ((m.journalEntries as? Set<JournalEntry>) ?? [])
            .sorted { ($0.createdAt ?? .distantPast, $0.id?.uuidString ?? "") < ($1.createdAt ?? .distantPast, $1.id?.uuidString ?? "") }
        let journals = journalMOs.map(BackupRecordProjector.journalEntryDTO(from:))

        var attachmentMOs = Array((m.attachments as? Set<Attachment>) ?? [])
        for entry in journalMOs {
            attachmentMOs.append(contentsOf: (entry.attachments as? Set<Attachment>) ?? [])
        }
        attachmentMOs.sort { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }

        var attachments: [ExportSchema.AttachmentDTO] = []
        var assets: [TaskBackupStore.PendingAsset] = []
        for a in attachmentMOs {
            let projected = BackupRecordProjector.attachmentDTO(from: a)
            attachments.append(projected.dto)
            if let asset = projected.asset {
                assets.append(.init(filename: asset.filename, bytes: asset.bytes))
            }
        }

        let record = BackupPackageSchema.TaskBackupRecord(
            backupSchemaVersion: BackupPackageSchema.version,
            cloudKitSchemaVersion: Int(m.schemaVersion),
            task: task,
            journalEntries: journals,
            attachments: attachments
        )
        return (record, assets)
    }

    // MARK: - Sidecars + manifest

    private func refreshSidecars() async throws {
        let prefs = try? await preferences.read()
        let prefsDTO = prefs.map(BackupRecordProjector.preferencesDTO(from:)) ?? Self.fallbackPreferences
        let ctx = persistence.makeBackgroundContext()
        let tags: [ExportSchema.TagDTO] = await ctx.perform {
            let req = NSFetchRequest<Tag>(entityName: "Tag")
            return ((try? ctx.fetch(req)) ?? []).map(BackupRecordProjector.tagDTO(from:))
        }
        try await store.writeSidecars(tags: tags, preferences: prefsDTO)
    }

    private func updateManifest() async throws {
        let count = (try? await store.taskFileCount()) ?? 0
        try await store.writeManifest(BackupPackageSchema.Manifest(
            backupSchemaVersion: BackupPackageSchema.version,
            cloudKitSchemaVersion: CloudKitSchema.currentVersion,
            updatedAt: Date(),
            taskCount: count
        ))
    }

    private static let fallbackPreferences = ExportSchema.PreferencesDTO(
        defaultAllDayHour: 9, defaultAllDayMinute: 0,
        morningSummaryEnabled: true, morningSummaryHour: 9, morningSummaryMinute: 0,
        trashRetentionDays: 30, defaultTaskListSort: "manualPosition"
    )
}
