import Foundation
import CoreData

/// Reads an `ExportSchema.Document` produced by `Exporter` and writes
/// the contained tasks, tags, and journal entries back into Core Data.
///
/// Plan 21 Wave 7: provides the manual merge escape hatch the
/// destructive sync-mode change deliberately skips. The importer
/// supports three conflict policies:
///
/// - `.skipExisting` — UUIDs already in the store are left alone.
/// - `.replaceExisting` — UUIDs already in the store are overwritten.
/// - `.recencyWins` — uses `modifiedAt` (falling back to `createdAt`)
///   to pick a winner per row.
///
/// When `apply` is given an `assetsDirectory`, attachments are imported too:
/// their metadata is written and their binary blobs are loaded back from the
/// bundle's `assets/` folder (issue #7 full-restore). Without it, attachment
/// rows are skipped (metadata-only bundles, or the legacy folder-import path).
public actor Importer {
    public let persistence: PersistenceController

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public enum ConflictPolicy: Sendable, Equatable {
        case skipExisting
        case replaceExisting
        case recencyWins
    }

    public struct ImportSummary: Sendable, Equatable {
        public let tasksInserted: Int
        public let tasksUpdated: Int
        public let tasksSkipped: Int
        public let tagsInserted: Int
        public let tagsUpdated: Int
        public let tagsSkipped: Int
        public let journalEntriesInserted: Int
        public let journalEntriesUpdated: Int
        public let journalEntriesSkipped: Int
        /// X3: recurrence series, reminders, and smart filters — previously
        /// entirely absent from import (there was nothing to count).
        public let seriesInserted: Int
        public let seriesUpdated: Int
        public let seriesSkipped: Int
        public let notificationSpecsInserted: Int
        public let notificationSpecsUpdated: Int
        public let notificationSpecsSkipped: Int
        public let smartFiltersInserted: Int
        public let smartFiltersUpdated: Int
        public let smartFiltersSkipped: Int
        /// Discovered during the 6a completeness sweep's export/import
        /// round-trip test: `apply` never touched `document.preferences` at
        /// all, so an export -> wipe -> import cycle silently reverted
        /// every account-level preference (trash retention, morning
        /// summary time, default tag tint, ...) to its hardcoded default.
        /// `true` once this document's preferences have been applied to
        /// the destination's singleton `AppPreferences` row (`false` only
        /// when `.skipExisting` left an already-materialized row alone —
        /// see `applyPreferences`'s doc comment).
        public let preferencesApplied: Bool
        public let errors: [String]

        public init(
            tasksInserted: Int = 0,
            tasksUpdated: Int = 0,
            tasksSkipped: Int = 0,
            tagsInserted: Int = 0,
            tagsUpdated: Int = 0,
            tagsSkipped: Int = 0,
            journalEntriesInserted: Int = 0,
            journalEntriesUpdated: Int = 0,
            journalEntriesSkipped: Int = 0,
            seriesInserted: Int = 0,
            seriesUpdated: Int = 0,
            seriesSkipped: Int = 0,
            notificationSpecsInserted: Int = 0,
            notificationSpecsUpdated: Int = 0,
            notificationSpecsSkipped: Int = 0,
            smartFiltersInserted: Int = 0,
            smartFiltersUpdated: Int = 0,
            smartFiltersSkipped: Int = 0,
            preferencesApplied: Bool = false,
            errors: [String] = []
        ) {
            self.tasksInserted = tasksInserted
            self.tasksUpdated = tasksUpdated
            self.tasksSkipped = tasksSkipped
            self.tagsInserted = tagsInserted
            self.tagsUpdated = tagsUpdated
            self.tagsSkipped = tagsSkipped
            self.journalEntriesInserted = journalEntriesInserted
            self.journalEntriesUpdated = journalEntriesUpdated
            self.journalEntriesSkipped = journalEntriesSkipped
            self.seriesInserted = seriesInserted
            self.seriesUpdated = seriesUpdated
            self.seriesSkipped = seriesSkipped
            self.notificationSpecsInserted = notificationSpecsInserted
            self.notificationSpecsUpdated = notificationSpecsUpdated
            self.notificationSpecsSkipped = notificationSpecsSkipped
            self.smartFiltersInserted = smartFiltersInserted
            self.smartFiltersUpdated = smartFiltersUpdated
            self.smartFiltersSkipped = smartFiltersSkipped
            self.preferencesApplied = preferencesApplied
            self.errors = errors
        }
    }

    /// Import a previously-exported bundle at `bundleURL`. The bundle
    /// is expected to be the directory the Exporter writes — with
    /// `lillist.json` at the top level.
    /// - Parameter assetsDirectory: when non-nil, attachments are restored
    ///   from this folder — see `apply(document:policy:assetsDirectory:)`.
    ///   Nil (the default) skips attachment rows entirely. Callers that know
    ///   the bundle was written by `Exporter.export(to:)` (which always
    ///   creates an `assets/` folder alongside `lillist.json`) should pass
    ///   `bundleURL.appendingPathComponent("assets", isDirectory: true)`.
    public func importBundle(
        at bundleURL: URL,
        conflictPolicy: ConflictPolicy,
        assetsDirectory: URL? = nil
    ) async throws -> ImportSummary {
        let docURL = bundleURL.appendingPathComponent("lillist.json")
        let data = try Data(contentsOf: docURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportSchema.Document.self, from: data)
        return try await apply(document: document, policy: conflictPolicy, assetsDirectory: assetsDirectory)
    }

    /// Apply a decoded export `document` to the store.
    ///
    /// ## Transaction contract (import-3)
    ///
    /// This is **all-or-nothing**: every row is staged in a single
    /// background-context `perform` block and committed by one
    /// `ctx.save()` at the end. If that save throws, the context is
    /// rolled back, the error propagates, and *nothing* is persisted
    /// — the returned `ImportSummary` (including its
    /// per-row `errors` array and the `*Skipped` counts) is **discarded
    /// along with the staged objects.** Callers must treat a thrown
    /// error as "the store is unchanged"; the `errors`/`*Skipped` detail
    /// is only meaningful on a successful return. Per-row recovery would
    /// require a per-row save/rollback model, which this manual-merge
    /// escape hatch deliberately does not adopt.
    /// - Parameter assetsDirectory: when non-nil, attachments in `document` are
    ///   imported and their binary blobs are loaded from this folder (each
    ///   `AttachmentDTO.dataPath` resolves to `<assetsDirectory>/<filename>`).
    ///   Nil skips attachment rows entirely.
    public func apply(
        document: ExportSchema.Document,
        policy: ConflictPolicy,
        assetsDirectory: URL? = nil
    ) async throws -> ImportSummary {
        // Forward-incompatible bundles (written by a newer Lillist) are
        // rejected up front. Equal and older versions apply; older
        // bundles are read as-is since every field added since has a
        // safe default at the DTO boundary.
        guard document.version <= ExportSchema.version else {
            throw LillistError.unsupportedExportVersion(
                found: document.version,
                supported: ExportSchema.version
            )
        }
        let ctx = persistence.makeBackgroundContext()  // unchanged Wave-4 seam — do not revert to viewContext
        return try await ctx.perform { [policy, assetsDirectory, self] in
            var tagsInserted = 0
            var tagsUpdated = 0
            var tagsSkipped = 0
            var tasksInserted = 0
            var tasksUpdated = 0
            var tasksSkipped = 0
            var entriesInserted = 0
            var entriesUpdated = 0
            var entriesSkipped = 0
            var seriesInserted = 0
            var seriesUpdated = 0
            var seriesSkipped = 0
            var specsInserted = 0
            var specsUpdated = 0
            var specsSkipped = 0
            var filtersInserted = 0
            var filtersUpdated = 0
            var filtersSkipped = 0
            var errors: [String] = []

            var tagByID: [UUID: Tag] = [:]
            // X13: rows `.skipExisting` explicitly left alone must never be
            // touched by the second pass below — not even their `.parent`.
            var skippedTagIDs: Set<UUID> = []
            for dto in document.tags {
                do {
                    if let existing = try self.fetchTag(id: dto.id, ctx: ctx) {
                        switch policy {
                        case .skipExisting:
                            tagsSkipped += 1
                            skippedTagIDs.insert(dto.id)
                        case .replaceExisting:
                            self.applyTag(dto, into: existing)
                            tagsUpdated += 1
                        case .recencyWins:
                            // Tags don't carry modifiedAt yet; fall back
                            // to "incoming wins" so multi-device imports
                            // converge predictably.
                            self.applyTag(dto, into: existing)
                            tagsUpdated += 1
                        }
                        tagByID[dto.id] = existing
                    } else {
                        let row = Tag(context: ctx)
                        row.id = dto.id
                        self.applyTag(dto, into: row)
                        tagsInserted += 1
                        tagByID[dto.id] = row
                    }
                } catch {
                    errors.append("tag \(dto.id): \(error.localizedDescription)")
                }
            }
            // Second pass to wire tag.parent (now that all rows exist).
            // X13: skip rows this pass didn't write, and fall back to the
            // destination store when the parent isn't part of this bundle —
            // a parent absent from the bundle but present in the store must
            // not be treated as "missing" (which would silently promote an
            // otherwise-valid child to root).
            for dto in document.tags {
                guard !skippedTagIDs.contains(dto.id),
                      let row = tagByID[dto.id],
                      let parentID = dto.parentID
                else { continue }
                row.parent = tagByID[parentID] ?? (try? self.fetchTag(id: parentID, ctx: ctx))
            }

            var taskByID: [UUID: LillistTask] = [:]
            // X13: same discipline as tags above — skipped rows are never
            // touched by the second pass.
            var skippedTaskIDs: Set<UUID> = []
            for dto in document.tasks {
                do {
                    if let existing = try self.fetchTask(id: dto.id, ctx: ctx) {
                        let action = self.decideAction(
                            policy: policy,
                            existingModified: existing.modifiedAt,
                            existingCreated: existing.createdAt,
                            incomingModified: dto.modifiedAt,
                            incomingCreated: dto.createdAt
                        )
                        switch action {
                        case .skip:
                            tasksSkipped += 1
                            skippedTaskIDs.insert(dto.id)
                        case .update:
                            self.applyTask(dto, into: existing, tagByID: tagByID)
                            tasksUpdated += 1
                        }
                        taskByID[dto.id] = existing
                    } else {
                        let row = LillistTask(context: ctx)
                        row.id = dto.id
                        self.applyTask(dto, into: row, tagByID: tagByID)
                        tasksInserted += 1
                        taskByID[dto.id] = row
                    }
                } catch {
                    errors.append("task \(dto.id): \(error.localizedDescription)")
                }
            }
            // X13: skip rows this pass didn't write, and fall back to the
            // destination store when the parent isn't part of this bundle.
            for dto in document.tasks {
                guard !skippedTaskIDs.contains(dto.id),
                      let row = taskByID[dto.id],
                      let parentID = dto.parentID
                else { continue }
                row.parent = taskByID[parentID] ?? (try? self.fetchTask(id: parentID, ctx: ctx))
            }

            // X3: recurrence series (previously entirely absent from import).
            var seriesByID: [UUID: Series] = [:]
            var skippedSeriesIDs: Set<UUID> = []
            for dto in document.series {
                do {
                    if let existing = try self.fetchSeries(id: dto.id, ctx: ctx) {
                        switch policy {
                        case .skipExisting:
                            seriesSkipped += 1
                            skippedSeriesIDs.insert(dto.id)
                        case .replaceExisting, .recencyWins:
                            // Series carries no modifiedAt; fall back to
                            // "incoming wins", matching Tag's precedent.
                            try self.applySeries(dto, into: existing)
                            seriesUpdated += 1
                        }
                        seriesByID[dto.id] = existing
                    } else {
                        let row = Series(context: ctx)
                        row.id = dto.id
                        try self.applySeries(dto, into: row)
                        seriesInserted += 1
                        seriesByID[dto.id] = row
                    }
                } catch {
                    errors.append("series \(dto.id): \(error.localizedDescription)")
                }
            }
            // Wire Series.seedTask — skip-respecting (X13 discipline extended
            // to this new relationship from the start), bundle-then-store
            // fallback. A seedTaskID that resolves nowhere leaves seedTask
            // nil rather than dropping the whole series — see
            // `SeriesDTO.seedTaskID`'s doc comment.
            for dto in document.series {
                guard !skippedSeriesIDs.contains(dto.id), let row = seriesByID[dto.id] else { continue }
                if let seedTaskID = dto.seedTaskID {
                    row.seedTask = taskByID[seedTaskID] ?? (try? self.fetchTask(id: seedTaskID, ctx: ctx))
                }
            }
            // Wire Task.series (X3: applyTask never set this before). Only
            // for tasks this import actually wrote — a skipped task's
            // series membership must not change, matching X13's discipline
            // for `.parent`.
            for dto in document.tasks {
                guard !skippedTaskIDs.contains(dto.id),
                      let row = taskByID[dto.id],
                      let seriesID = dto.seriesID
                else { continue }
                row.series = seriesByID[seriesID] ?? (try? self.fetchSeries(id: seriesID, ctx: ctx))
            }

            var journalByID: [UUID: JournalEntry] = [:]
            for dto in document.journalEntries {
                // A journal entry must belong to a task. Entries with a
                // nil or unresolved taskID are orphans (CloudKit can
                // deliver dangling relationships, and older bundles may
                // predate referential cleanup) — skip them rather than
                // insert a task-less row.
                guard let taskID = dto.taskID, let owner = taskByID[taskID] else {
                    entriesSkipped += 1
                    errors.append("journalEntry \(dto.id): skipped (no resolvable task)")
                    continue
                }
                do {
                    if let existing = try self.fetchJournalEntry(id: dto.id, ctx: ctx) {
                        let action = self.decideAction(
                            policy: policy,
                            existingModified: existing.editedAt,
                            existingCreated: existing.createdAt,
                            incomingModified: dto.editedAt,
                            incomingCreated: dto.createdAt
                        )
                        switch action {
                        case .skip:
                            entriesSkipped += 1
                        case .update:
                            self.applyEntry(dto, into: existing, owner: owner)
                            entriesUpdated += 1
                        }
                        journalByID[dto.id] = existing
                    } else {
                        let row = JournalEntry(context: ctx)
                        row.id = dto.id
                        self.applyEntry(dto, into: row, owner: owner)
                        entriesInserted += 1
                        journalByID[dto.id] = row
                    }
                } catch {
                    errors.append("journalEntry \(dto.id): \(error.localizedDescription)")
                }
            }

            // Attachments — only when an assets directory is supplied (issue #7
            // full restore). Each attachment must resolve to an owning task or
            // journal entry; orphans are skipped. Binary blobs load from disk
            // here, inside the background-context perform (never the main queue).
            if let assetsDirectory {
                for dto in document.attachments {
                    let owningTask = dto.taskID.flatMap { taskByID[$0] }
                    let owningEntry = dto.journalEntryID.flatMap { journalByID[$0] }
                    guard owningTask != nil || owningEntry != nil else {
                        errors.append("attachment \(dto.id): skipped (no resolvable owner)")
                        continue
                    }
                    do {
                        let existing = try self.fetchAttachment(id: dto.id, ctx: ctx)
                        if existing != nil, policy == .skipExisting { continue }
                        let row = existing ?? {
                            let new = Attachment(context: ctx)
                            new.id = dto.id
                            return new
                        }()
                        self.applyAttachment(dto, into: row, task: owningTask, entry: owningEntry, assetsDirectory: assetsDirectory)
                    } catch {
                        errors.append("attachment \(dto.id): \(error.localizedDescription)")
                    }
                }
            }

            // X3: reminders — simple owned-child pattern (like Attachment):
            // the task FK is resolved and set at creation/update time, no
            // second pass needed. A taskID absent from both the bundle and
            // the destination store is an orphan, skipped like JournalEntry/
            // Attachment's existing convention.
            for dto in document.notificationSpecs {
                let owningTask: LillistTask? = dto.taskID.flatMap { id in
                    taskByID[id] ?? (try? self.fetchTask(id: id, ctx: ctx))
                }
                guard let owningTask else {
                    errors.append("notificationSpec \(dto.id): skipped (no resolvable task)")
                    continue
                }
                do {
                    if let existing = try self.fetchNotificationSpec(id: dto.id, ctx: ctx) {
                        if policy == .skipExisting {
                            specsSkipped += 1
                            continue
                        }
                        // No modifiedAt on NotificationSpec either — same
                        // "incoming wins" fallback as Series/Tag.
                        self.applyNotificationSpec(dto, into: existing, task: owningTask)
                        specsUpdated += 1
                    } else {
                        let row = NotificationSpec(context: ctx)
                        row.id = dto.id
                        self.applyNotificationSpec(dto, into: row, task: owningTask)
                        specsInserted += 1
                    }
                } catch {
                    errors.append("notificationSpec \(dto.id): \(error.localizedDescription)")
                }
            }

            // Smart filters — standalone, no relationships to wire.
            // SmartFilter DOES carry modifiedAt, so recencyWins uses the
            // same decideAction comparison as Task/JournalEntry rather than
            // Series/Tag/NotificationSpec's "incoming wins" fallback.
            for dto in document.smartFilters {
                do {
                    if let existing = try self.fetchSmartFilter(id: dto.id, ctx: ctx) {
                        let action = self.decideAction(
                            policy: policy,
                            existingModified: existing.modifiedAt,
                            existingCreated: existing.createdAt,
                            incomingModified: dto.modifiedAt,
                            incomingCreated: dto.createdAt
                        )
                        switch action {
                        case .skip:
                            filtersSkipped += 1
                        case .update:
                            self.applySmartFilter(dto, into: existing)
                            filtersUpdated += 1
                        }
                    } else {
                        let row = SmartFilter(context: ctx)
                        row.id = dto.id
                        self.applySmartFilter(dto, into: row)
                        filtersInserted += 1
                    }
                } catch {
                    errors.append("smartFilter \(dto.id): \(error.localizedDescription)")
                }
            }

            // Preferences — a singleton row, not a collection, so there's
            // no per-row insert/update/skip count to track: only whether
            // this document's preferences were applied at all.
            var preferencesApplied = false
            do {
                preferencesApplied = try self.applyPreferences(document.preferences, policy: policy, ctx: ctx)
            } catch {
                errors.append("preferences: \(error.localizedDescription)")
            }

            do {
                try ctx.save()
            } catch {
                ctx.rollback()
                throw error
            }
            return ImportSummary(
                tasksInserted: tasksInserted,
                tasksUpdated: tasksUpdated,
                tasksSkipped: tasksSkipped,
                tagsInserted: tagsInserted,
                tagsUpdated: tagsUpdated,
                tagsSkipped: tagsSkipped,
                journalEntriesInserted: entriesInserted,
                journalEntriesUpdated: entriesUpdated,
                journalEntriesSkipped: entriesSkipped,
                seriesInserted: seriesInserted,
                seriesUpdated: seriesUpdated,
                seriesSkipped: seriesSkipped,
                notificationSpecsInserted: specsInserted,
                notificationSpecsUpdated: specsUpdated,
                notificationSpecsSkipped: specsSkipped,
                smartFiltersInserted: filtersInserted,
                smartFiltersUpdated: filtersUpdated,
                smartFiltersSkipped: filtersSkipped,
                preferencesApplied: preferencesApplied,
                errors: errors
            )
        }
    }

    private enum Action { case skip, update }
    private nonisolated func decideAction(
        policy: ConflictPolicy,
        existingModified: Date?,
        existingCreated: Date?,
        incomingModified: Date?,
        incomingCreated: Date?
    ) -> Action {
        switch policy {
        case .skipExisting:
            return .skip
        case .replaceExisting:
            return .update
        case .recencyWins:
            let existing = existingModified ?? existingCreated ?? .distantPast
            let incoming = incomingModified ?? incomingCreated ?? .distantPast
            return incoming > existing ? .update : .skip
        }
    }

    // MARK: - Apply helpers (nonisolated; only touch Core Data via ctx)

    private nonisolated func applyTag(_ dto: ExportSchema.TagDTO, into row: Tag) {
        row.name = dto.name
        row.tintColor = dto.tintColor
        row.position = dto.position
    }

    private nonisolated func applyTask(_ dto: ExportSchema.TaskDTO, into row: LillistTask, tagByID: [UUID: Tag]) {
        row.title = dto.title
        row.notes = dto.notes
        row.statusRaw = Int16(dto.status)
        row.start = dto.start
        row.startHasTime = dto.startHasTime
        row.deadline = dto.deadline
        row.deadlineHasTime = dto.deadlineHasTime
        row.position = dto.position
        row.isPinned = dto.isPinned
        row.createdAt = dto.createdAt
        row.modifiedAt = dto.modifiedAt
        row.closedAt = dto.closedAt
        row.deletedAt = dto.deletedAt
        row.archivedAt = dto.archivedAt
        // Imported rows are written with this build's field shape, so they
        // conform to the current CloudKit schema regardless of the bundle's
        // recorded version — stamp current rather than copying `dto.schemaVersion`
        // (issue #7). This keeps restored data self-consistent for a later backup.
        row.stampCurrentSchemaVersion()
        let resolved = dto.tagIDs.compactMap { tagByID[$0] }
        row.tags = NSSet(array: resolved)
    }

    private nonisolated func applyEntry(_ dto: ExportSchema.JournalEntryDTO, into row: JournalEntry, owner: LillistTask) {
        row.task = owner
        row.kindRaw = Int16(dto.kind)
        row.body = dto.body
        row.payload = dto.payload
        row.createdAt = dto.createdAt
        row.editedAt = dto.editedAt
    }

    private nonisolated func applyAttachment(
        _ dto: ExportSchema.AttachmentDTO,
        into row: Attachment,
        task: LillistTask?,
        entry: JournalEntry?,
        assetsDirectory: URL
    ) {
        row.task = task
        row.journalEntry = entry
        row.kindRaw = Int16(dto.kind)
        row.filename = dto.filename
        row.uti = dto.uti
        row.byteSize = dto.byteSize
        row.linkPreviewJSON = dto.linkPreviewJSON
        row.createdAt = dto.createdAt
        // Reload the binary blob from the bundle's assets/ folder. `dataPath` is
        // "assets/<filename>"; resolve its tail against `assetsDirectory`. A
        // missing/unreadable blob leaves `data` nil rather than failing the
        // whole transaction (link previews legitimately carry no blob).
        if let path = dto.dataPath {
            let url = assetsDirectory.appendingPathComponent((path as NSString).lastPathComponent)
            row.data = try? Data(contentsOf: url)
        } else {
            row.data = nil
        }
    }

    /// `Series.rule` is a read-only computed property (L6) — `setRule(_:)`
    /// throws on an encode failure rather than silently clearing the rule,
    /// so this method must too. Its two call sites already run inside a
    /// per-row `do`/`catch` that appends to `errors`, matching every other
    /// entity's import discipline.
    private nonisolated func applySeries(_ dto: ExportSchema.SeriesDTO, into row: Series) throws {
        if let rule = dto.rule {
            try row.setRule(rule)
        } else {
            row.ruleJSON = nil
        }
        row.nextOccurrenceAfter = dto.nextOccurrenceAfter
        // seedTask is wired by the caller's second pass, once every task
        // row (bundle-inserted or destination-store-resident) is resolvable.
    }

    private nonisolated func applyNotificationSpec(
        _ dto: ExportSchema.NotificationSpecDTO,
        into row: NotificationSpec,
        task: LillistTask
    ) {
        row.task = task
        row.kindRaw = Int16(dto.kind)
        if let offset = dto.offsetMinutes {
            row.offsetMinutes = NSNumber(value: offset)
        } else {
            row.offsetMinutes = nil
        }
        row.fireDate = dto.fireDate
        // Round-trips as-is — see `ExportSchema.NotificationSpecDTO`'s doc
        // comment for why resetting this to nil on import would be wrong,
        // not merely unproven.
        row.lastFiredAt = dto.lastFiredAt
        // Written to the vestigial column so an old archive round-trips
        // losslessly; nothing reads it (`LIL-90`).
        row.snoozedUntil = dto.snoozedUntil
        row.scheduledTimeZoneID = dto.scheduledTimeZoneID
        row.createdAt = dto.createdAt
    }

    private nonisolated func applySmartFilter(_ dto: ExportSchema.SmartFilterDTO, into row: SmartFilter) {
        row.name = dto.name
        row.predicateGroupJSON = dto.predicateGroup.flatMap { try? SmartFilterStore.encode($0) }
        row.tintColor = dto.tintColor
        row.sortFieldRaw = dto.sortField
        row.sortAscending = dto.sortAscending
        row.isPinned = dto.isPinned
        row.position = dto.position
        row.createdAt = dto.createdAt
        row.modifiedAt = dto.modifiedAt
    }

    /// Restores `dto` into the destination's singleton `AppPreferences` row
    /// (creating it if absent), returning whether it was applied.
    ///
    /// `AppPreferences` carries no `modifiedAt` (same as `Series`/`Tag`), so
    /// there's no timestamp to arbitrate a `.recencyWins` decision — this
    /// follows their established "incoming wins" fallback for both
    /// `.replaceExisting` and `.recencyWins`. `.skipExisting` only skips
    /// when a row already exists to skip: an absent singleton (a store
    /// that's never been touched) still gets populated, matching every
    /// other entity's "insert always happens, .skipExisting only guards
    /// updates" shape.
    private nonisolated func applyPreferences(
        _ dto: ExportSchema.PreferencesDTO,
        policy: ConflictPolicy,
        ctx: NSManagedObjectContext
    ) throws -> Bool {
        let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
        req.predicate = NSPredicate(format: "id == %@", PreferencesStore.singletonID as CVarArg)
        req.fetchLimit = 1
        let existing = try ctx.fetch(req).first
        if existing != nil, policy == .skipExisting { return false }

        let row = existing ?? {
            let new = AppPreferences(context: ctx)
            new.id = PreferencesStore.singletonID
            return new
        }()
        row.defaultAllDayNotificationHour = dto.defaultAllDayHour
        row.defaultAllDayNotificationMinute = dto.defaultAllDayMinute
        row.morningSummaryEnabled = dto.morningSummaryEnabled
        row.morningSummaryHour = dto.morningSummaryHour
        row.morningSummaryMinute = dto.morningSummaryMinute
        row.trashRetentionDays = dto.trashRetentionDays
        row.defaultTaskListSortRaw = dto.defaultTaskListSort
        row.defaultTagTintHex = dto.defaultTagTintHex
        return true
    }

    private nonisolated func fetchTag(id: UUID, ctx: NSManagedObjectContext) throws -> Tag? {
        let req = NSFetchRequest<Tag>(entityName: "Tag")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try ctx.fetch(req).first
    }

    private nonisolated func fetchTask(id: UUID, ctx: NSManagedObjectContext) throws -> LillistTask? {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try ctx.fetch(req).first
    }

    private nonisolated func fetchJournalEntry(id: UUID, ctx: NSManagedObjectContext) throws -> JournalEntry? {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try ctx.fetch(req).first
    }

    private nonisolated func fetchAttachment(id: UUID, ctx: NSManagedObjectContext) throws -> Attachment? {
        let req = NSFetchRequest<Attachment>(entityName: "Attachment")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try ctx.fetch(req).first
    }

    private nonisolated func fetchSeries(id: UUID, ctx: NSManagedObjectContext) throws -> Series? {
        let req = NSFetchRequest<Series>(entityName: "Series")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try ctx.fetch(req).first
    }

    private nonisolated func fetchNotificationSpec(id: UUID, ctx: NSManagedObjectContext) throws -> NotificationSpec? {
        let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try ctx.fetch(req).first
    }

    private nonisolated func fetchSmartFilter(id: UUID, ctx: NSManagedObjectContext) throws -> SmartFilter? {
        let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try ctx.fetch(req).first
    }
}
