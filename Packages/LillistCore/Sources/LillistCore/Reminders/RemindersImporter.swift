import Foundation

/// Drains a chosen Reminders.app list into top-level Lillist tasks.
///
/// Invoked when the app becomes active (cold launch via `bootstrap()`, warm
/// returns via the platform `didBecomeActive` observer). Each *incomplete*
/// reminder becomes a top-level task — title + notes + due date (→ deadline)
/// — and is then removed from the list, so the list behaves as an input
/// queue. Completed reminders are left untouched: neither imported nor
/// removed, so the list's incomplete count is exactly what a drain will do.
///
/// An `actor` so overlapping activations serialize; an `isDraining` flag
/// coalesces a queued second pass into a no-op. The create→delete crash window
/// is guarded by an in-flight id set in device preferences: an id recorded but
/// not yet confirmed-deleted is, on the next pass, deleted *without*
/// re-creating a duplicate task.
public actor RemindersImporter {
    private let gateway: RemindersGateway
    private let taskStore: TaskStore
    private let devicePreferences: DevicePreferencesStore
    private var isDraining = false

    /// Fallback title for a reminder with a blank title — `TaskStore.create`
    /// rejects empty titles, and we must still drain the item.
    private static let fallbackTitle = "Untitled"

    public init(
        gateway: RemindersGateway,
        taskStore: TaskStore,
        devicePreferences: DevicePreferencesStore
    ) {
        self.gateway = gateway
        self.taskStore = taskStore
        self.devicePreferences = devicePreferences
    }

    /// Drain the configured list when the feature is enabled, a list is
    /// chosen, and Reminders access is granted. Best-effort and silent: a
    /// failure to import or delete one item never blocks the rest or the
    /// caller. Returns the number of newly-created tasks (useful for tests).
    @discardableResult
    public func drainIfNeeded() async -> Int {
        // Set the guard flag *synchronously* after the check — before any
        // `await`. The first `await` releases actor isolation, so if the flag
        // were set later, concurrent activations would all pass the check and
        // drain in parallel (creating duplicates). Caught by the stress test.
        guard !isDraining else { return 0 }
        isDraining = true
        defer { isDraining = false }

        guard await devicePreferences.remindersImportEnabled(),
              let listID = await devicePreferences.remindersImportListID()
        else { return 0 }
        guard await gateway.authorization() == .authorized else { return 0 }

        let items: [ReminderItem]
        do {
            items = try await gateway.items(inListID: listID)
        } catch {
            return 0
        }
        guard !items.isEmpty else { return 0 }

        var inFlight = await devicePreferences.remindersInFlightIDs()
        // Prune markers for ids no longer in the list so the set stays bounded
        // (an item still mid-flight is, by definition, still present).
        let liveIDs = Set(items.map(\.id))
        if !inFlight.isSubset(of: liveIDs) {
            inFlight.formIntersection(liveIDs)
            await devicePreferences.setRemindersInFlightIDs(inFlight)
        }

        var imported = 0
        for item in items {
            let wasInFlight = inFlight.contains(item.id)
            if !wasInFlight {
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
                    try await createTask(from: item)
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
            } catch {
                // Keep the marker; the next pass deletes without re-creating.
            }
        }
        return imported
    }

    private func createTask(from item: ReminderItem) async throws {
        let title = TaskStore.isCommittableTitle(item.title) ? item.title : Self.fallbackTitle
        let id = try await taskStore.create(
            title: title,
            notes: item.notes ?? "",
            parent: nil,
            placement: .top
        )
        guard let due = item.dueDate else { return }
        try await taskStore.update(id: id) { draft in
            draft.deadline = due
            draft.deadlineHasTime = item.dueHasTime
        }
    }
}
