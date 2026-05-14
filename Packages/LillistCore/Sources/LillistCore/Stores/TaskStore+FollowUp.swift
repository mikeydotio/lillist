import Foundation
import CoreData

extension TaskStore {
    /// Create a sibling follow-up task and append a `createdFollowUp`
    /// journal entry on the parent. Per design Section 4: "Sibling rather
    /// than child so collapsing the blocked task doesn't hide the follow-up."
    ///
    /// - Parameters:
    ///   - parentTaskID: the blocked task to attach the journal entry to.
    ///     The new task becomes its sibling (same `parent`).
    ///   - title: title of the new task.
    ///   - deadline: deadline for the new task (time-bearing is preserved).
    /// - Returns: the new task's UUID.
    @discardableResult
    public func scheduleFollowUp(
        parentTaskID: UUID,
        title: String,
        deadline: Date
    ) async throws -> UUID {
        try validateTitle(title)
        let ctx = persistence.container.viewContext
        let newID: UUID = try await ctx.perform { [self] in
            let blocked = try fetchManagedObject(id: parentTaskID, in: ctx)
            let siblingParent: LillistTask? = blocked.parent

            let followUp = LillistTask(context: ctx)
            let id = UUID()
            followUp.id = id
            followUp.title = title
            followUp.notes = ""
            followUp.status = .todo
            followUp.startHasTime = false
            followUp.deadlineHasTime = true
            followUp.deadline = deadline
            followUp.isPinned = false
            followUp.createdAt = Date()
            followUp.modifiedAt = followUp.createdAt
            followUp.parent = siblingParent
            followUp.position = try nextPosition(forParent: siblingParent)

            // Journal entry on the blocked task.
            let entry = JournalEntry(context: ctx)
            entry.id = UUID()
            entry.task = blocked
            entry.kind = .createdFollowUp
            entry.body = "Created follow-up: \(title)"
            entry.createdAt = Date()
            let payload: [String: String] = ["followUpTaskID": id.uuidString]
            entry.payload = try JSONSerialization.data(withJSONObject: payload)

            try ctx.save()
            return id
        }
        // Reconcile notifications for the newly-created task — it has a
        // deadline and needs its defaultDeadline spec scheduled.
        if let scheduler = notificationScheduler {
            await scheduler.reconcile(taskID: newID)
        }
        return newID
    }
}
