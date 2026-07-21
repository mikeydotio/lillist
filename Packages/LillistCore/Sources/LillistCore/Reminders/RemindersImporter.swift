import Foundation

/// Drains a chosen Reminders.app list into top-level Lillist tasks.
///
/// Invoked when the app becomes active (cold launch via `bootstrap()`, warm
/// returns via the platform `didBecomeActive` observer) via ``drainIfNeeded()``,
/// and explicitly from the Settings "Drain now" action via ``drain(listID:)``.
/// Each *incomplete* reminder becomes a top-level task — title + notes + due
/// date (→ deadline) — and is then removed from the list, so the list
/// behaves as an input queue. Completed reminders are left untouched: neither
/// imported nor removed, so the list's incomplete count is exactly what a
/// drain will do.
///
/// An `actor` so overlapping activations serialize; an `isDraining` flag
/// coalesces a queued second pass into ``RemindersDrainOutcome/busy``. The
/// create→delete crash window is guarded by an in-flight id set in device
/// preferences: an id recorded but not yet confirmed-deleted is, on the next
/// pass, deleted *without* re-creating a duplicate task.
///
/// Every pass returns a ``RemindersDrainOutcome`` rather than a bare count —
/// see its doc comment for why that distinction is the point of this type
/// (issue #50). When `diagnosticLog` is non-nil, each pass also emits one
/// `reminders.drain` event, so the automatic (silent, UI-less) activation
/// drains become inspectable after the fact.
public actor RemindersImporter {
    private let gateway: RemindersGateway
    private let taskStore: TaskStore
    private let devicePreferences: DevicePreferencesStore
    private let diagnosticLog: DiagnosticSink?
    private let autoImportLimit: Int
    private var isDraining = false

    /// Fallback title for a reminder with a blank title — `TaskStore.create`
    /// rejects empty titles, and we must still drain the item.
    private static let fallbackTitle = "Untitled"

    /// Issue #66: ceiling on how many incomplete reminders an **automatic**
    /// (activation-triggered, no UI to confirm through) pass will import
    /// before treating the list as too big to drain silently. Large enough
    /// that an ordinary automatic drain (a handful of items added since the
    /// last launch) is never affected; small enough that the incident this
    /// guards against (~1,900 reminders imported in one silent pass, with no
    /// preview and no way to undo — the drained reminder is also deleted
    /// from Reminders.app, so a full local restore was the only recourse) is
    /// caught by a wide margin. The **manual** "Drain now" path is never
    /// subject to this limit — the Settings UI gates it behind
    /// ``preview(listID:)`` and an explicit confirmation instead.
    public static let defaultAutoImportLimit = 25

    public init(
        gateway: RemindersGateway,
        taskStore: TaskStore,
        devicePreferences: DevicePreferencesStore,
        diagnosticLog: DiagnosticSink? = nil,
        autoImportLimit: Int = defaultAutoImportLimit
    ) {
        self.gateway = gateway
        self.taskStore = taskStore
        self.devicePreferences = devicePreferences
        self.diagnosticLog = diagnosticLog
        self.autoImportLimit = autoImportLimit
    }

    /// Issue #66: a non-mutating count of what draining `listID` would do
    /// right now — the manual "Drain now" UI's preview, shown in a
    /// confirmation dialog before anything is imported or removed from
    /// Reminders. `nil` when access isn't granted or the list can't be read
    /// (the caller falls back to its existing authorization/list-unavailable
    /// messaging in that case; this is purely the "how many" signal for the
    /// happy path).
    public func preview(listID: String) async -> RemindersDrainPreview? {
        guard await gateway.authorization() == .authorized else { return nil }
        guard let items = try? await gateway.items(inListID: listID) else { return nil }
        let candidateCount = items.filter { !$0.isCompleted }.count
        return RemindersDrainPreview(listID: listID, candidateCount: candidateCount)
    }

    /// Issue #66: undo the most recent drain pass that imported at least one
    /// task — soft-deletes (moves to Trash) exactly those tasks. This can
    /// only undo the **Lillist** side: the drained reminders were already
    /// removed from Reminders.app during the import (existing, unchanged
    /// behavior) and cannot be restored there. Guarded by the same
    /// `isDraining` flag as a drain pass, so an undo can't race an in-flight
    /// import clobbering the batch it's about to read.
    @discardableResult
    public func undoLastImport() async -> RemindersUndoOutcome {
        guard !isDraining else { return .busy }
        isDraining = true
        defer { isDraining = false }

        let ids = await devicePreferences.remindersLastImportedTaskIDs()
        guard !ids.isEmpty else { return .nothingToUndo }

        var undone = 0
        for id in ids {
            do {
                try await taskStore.softDelete(id: id)
                undone += 1
            } catch {
                // Already gone (hard-deleted since, or a prior partial
                // undo) — still counts toward clearing the batch below.
            }
        }
        await devicePreferences.setRemindersLastImportedTaskIDs([])
        return .undone(count: undone)
    }

    /// Drain the configured list when the feature is enabled, a list is
    /// chosen, and Reminders access is granted. Reads `enabled` and the
    /// selected list id from persisted device preferences — the path used by
    /// the automatic activation drains. Best-effort: a failure to import or
    /// delete one item never blocks the rest or the caller.
    @discardableResult
    public func drainIfNeeded() async -> RemindersDrainOutcome {
        // Set the guard flag *synchronously* after the check — before any
        // `await`. The first `await` releases actor isolation, so if the flag
        // were set later, concurrent activations would all pass the check and
        // drain in parallel (creating duplicates). Caught by the stress test.
        guard !isDraining else { return await finish(.busy, listID: nil, trigger: "auto") }
        isDraining = true
        defer { isDraining = false }

        guard await devicePreferences.remindersImportEnabled() else {
            return await finish(.featureDisabled, listID: nil, trigger: "auto")
        }
        guard let listID = await devicePreferences.remindersImportListID() else {
            return await finish(.noListSelected, listID: nil, trigger: "auto")
        }
        return await performDrain(listID: listID, trigger: "auto")
    }

    /// Drain the given list directly, bypassing the persisted selection.
    ///
    /// The Settings "Drain now" action calls this with its own in-memory
    /// selected-list state rather than going through ``drainIfNeeded()``'s
    /// persisted read. That persisted read is written by an unordered
    /// fire-and-forget `Task` from the picker binding — a quick pick-then-drain
    /// could otherwise read a stale or not-yet-written list id (issue #50's
    /// race). Still subject to the same authorization check and `isDraining`
    /// guard as the automatic path.
    @discardableResult
    public func drain(listID: String) async -> RemindersDrainOutcome {
        guard !isDraining else { return await finish(.busy, listID: listID, trigger: "manual") }
        isDraining = true
        defer { isDraining = false }
        return await performDrain(listID: listID, trigger: "manual")
    }

    /// Shared core once a list id is known: check authorization, fetch,
    /// import, delete. `trigger` ("auto"/"manual") only affects the emitted
    /// diagnostic event, not behavior.
    private func performDrain(listID: String, trigger: String) async -> RemindersDrainOutcome {
        guard await gateway.authorization() == .authorized else {
            return await finish(.notAuthorized, listID: listID, trigger: trigger)
        }

        let items: [ReminderItem]
        do {
            items = try await gateway.items(inListID: listID)
        } catch let error as RemindersGatewayError {
            switch error {
            case .listUnavailable(let id):
                return await finish(.listUnavailable(listID: id), listID: listID, trigger: trigger)
            case .fetchFailed(let id):
                return await finish(.fetchFailed(listID: id), listID: listID, trigger: trigger)
            }
        } catch {
            // A conforming gateway threw something other than
            // RemindersGatewayError — still a legible outcome, never a silent 0.
            return await finish(.fetchFailed(listID: listID), listID: listID, trigger: trigger)
        }
        guard !items.isEmpty else {
            return await finish(.completed(imported: 0, deletedWithoutImport: 0), listID: listID, trigger: trigger)
        }

        // Issue #66: an automatic pass never silently imports more than
        // autoImportLimit — it imports nothing and reports
        // .tooManyToAutoImport, so a large batch is reviewed and confirmed
        // through the manual path instead. The manual path itself is never
        // gated here — its UI already gated the user through preview(_:)
        // before calling drain(listID:).
        if trigger == "auto" {
            let candidateCount = items.filter { !$0.isCompleted }.count
            guard candidateCount <= autoImportLimit else {
                return await finish(
                    .tooManyToAutoImport(listID: listID, count: candidateCount),
                    listID: listID, trigger: trigger
                )
            }
        }

        var inFlight = await devicePreferences.remindersInFlightIDs()
        // Prune markers for ids no longer in the list so the set stays bounded
        // (an item still mid-flight is, by definition, still present).
        let liveIDs = Set(items.map(\.id))
        if !inFlight.isSubset(of: liveIDs) {
            inFlight.formIntersection(liveIDs)
            await devicePreferences.setRemindersInFlightIDs(inFlight)
        }

        var imported = 0
        var deletedWithoutImport = 0
        var importedTaskIDs: [UUID] = []
        for item in items {
            let wasAlreadyInFlight = inFlight.contains(item.id)
            if !wasAlreadyInFlight {
                // Completed reminders are never drained — the list's
                // incomplete count is the promise of what a drain will do. An
                // item already mid-flight (task created, delete pending from
                // a prior crash) is *not* skipped here even if it has since
                // been completed: the create already happened, so the delete
                // below must still run to clear its in-flight marker.
                guard !item.isCompleted else { continue }
                // Create first, then record the id, so a crash before delete
                // can't re-create the task on the next pass.
                do {
                    let taskID = try await createTask(from: item)
                    importedTaskIDs.append(taskID)
                    imported += 1
                } catch {
                    // Couldn't create — leave the reminder so a later pass retries.
                    continue
                }
                inFlight.insert(item.id)
                await devicePreferences.setRemindersInFlightIDs(inFlight)
            }
            // Remove from Reminders; clear the in-flight marker only on success.
            do {
                try await gateway.remove(itemID: item.id)
                inFlight.remove(item.id)
                await devicePreferences.setRemindersInFlightIDs(inFlight)
                // Counted only when the item was already in-flight from a prior,
                // interrupted pass — a fresh create+delete in the same pass is
                // "imported", not crash-window cleanup.
                if wasAlreadyInFlight { deletedWithoutImport += 1 }
            } catch {
                // Keep the marker; the next pass deletes without re-creating.
            }
        }
        // Issue #66: record this pass's imports as the undoable batch — but
        // only when it actually imported something. A later empty/no-op
        // pass must not clear a still-undoable prior batch.
        if !importedTaskIDs.isEmpty {
            await devicePreferences.setRemindersLastImportedTaskIDs(importedTaskIDs)
        }
        return await finish(
            .completed(imported: imported, deletedWithoutImport: deletedWithoutImport),
            listID: listID,
            trigger: trigger
        )
    }

    /// Emits the diagnostic event for this pass (if a sink is wired) and
    /// returns the outcome unchanged — every return path in this actor routes
    /// through here so no outcome ships without a matching diagnostic record.
    private func finish(_ outcome: RemindersDrainOutcome, listID: String?, trigger: String) async -> RemindersDrainOutcome {
        if let diagnosticLog {
            await diagnosticLog.log(DiagnosticEvent(
                at: Date(),
                seq: 0,
                process: .app,
                category: .data,
                name: "reminders.drain",
                payload: payload(for: outcome, listID: listID, trigger: trigger)
            ))
        }
        return outcome
    }

    private func payload(for outcome: RemindersDrainOutcome, listID: String?, trigger: String) -> [String: DiagValue] {
        var payload: [String: DiagValue] = [
            "trigger": .string(trigger),
            "outcome": .string(outcomeName(outcome))
        ]
        if let listID { payload["listID"] = .string(listID) }
        if case .completed(let imported, let deletedWithoutImport) = outcome {
            payload["imported"] = .int(imported)
            payload["deletedWithoutImport"] = .int(deletedWithoutImport)
        }
        if case .tooManyToAutoImport(_, let count) = outcome {
            payload["candidateCount"] = .int(count)
        }
        return payload
    }

    private func outcomeName(_ outcome: RemindersDrainOutcome) -> String {
        switch outcome {
        case .featureDisabled: return "featureDisabled"
        case .noListSelected: return "noListSelected"
        case .notAuthorized: return "notAuthorized"
        case .busy: return "busy"
        case .listUnavailable: return "listUnavailable"
        case .fetchFailed: return "fetchFailed"
        case .tooManyToAutoImport: return "tooManyToAutoImport"
        case .completed: return "completed"
        }
    }

    @discardableResult
    private func createTask(from item: ReminderItem) async throws -> UUID {
        let title = TaskStore.isCommittableTitle(item.title) ? item.title : Self.fallbackTitle
        let id = try await taskStore.create(
            title: title,
            notes: item.notes ?? "",
            parent: nil,
            placement: .top
        )
        guard let due = item.dueDate else { return id }
        try await taskStore.update(id: id) { draft in
            draft.deadline = due
            draft.deadlineHasTime = item.dueHasTime
        }
        return id
    }
}
