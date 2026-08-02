import Testing
import Foundation
import CoreData
@testable import LillistCore

/// `LIL-90` — a remote **in-place** `NotificationSpec` edit must reach the
/// reconciler when, and only when, it can move a fire time.
///
/// Filed as latent: nothing could edit an existing spec in place from another
/// device, so the narrow `lastFiredAt`-only gate was harmless. `LIL-83`'s
/// time-zone prompt is exactly that caller — it rewrites `scheduledTimeZoneID`
/// on existing rows — so the gate had to widen or the user's "reschedule to the
/// new zone" would apply on one device and be silently dropped on every other.
///
/// `snoozedUntil` is deliberately absent from the allow-list: snooze is
/// device-local now (``SnoozeStateStore``), so a remote snooze edit cannot
/// exist. See ``SnoozeStatePartitionTests``.
@Suite("Remote in-place NotificationSpec edits")
struct RemoteSpecEditReconcileTests {

    private func makeContext() async throws -> (PersistenceController, NSManagedObjectContext) {
        let p = try await TestStore.make()
        return (p, p.container.viewContext)
    }

    private func specObjectID(
        _ ctx: NSManagedObjectContext,
        _ specID: UUID
    ) async throws -> NSManagedObjectID {
        try await ctx.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            return try #require(try ctx.fetch(req).first).objectID
        }
    }

    /// Run one synthetic foreign in-place UPDATE touching `properties`.
    private func affected(
        properties: Set<String>,
        changeType: NSPersistentHistoryChangeType = .update
    ) async throws -> (affected: [UUID], taskID: UUID) {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "Take medication")
        let specID = try await specs.add(
            taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil
        )

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: try await specObjectID(ctx, specID),
            entityName: "NotificationSpec",
            changedProperties: properties,
            author: "OtherDeviceImport",
            changeType: changeType
        )
        let out = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        return (out, taskID)
    }

    // MARK: - The LIL-83 case: this is what would have broken

    @Test("A remote scheduledTimeZoneID edit triggers a reconcile")
    func remoteTimeZoneEditReconciles() async throws {
        let (out, taskID) = try await affected(properties: ["scheduledTimeZoneID"])
        #expect(
            out == [taskID],
            "LIL-83: accepting 'reschedule to the new zone' on one device must move the others too"
        )
    }

    // MARK: - The rest of the schedule-affecting set

    @Test("Every schedule-affecting property triggers a reconcile", arguments: [
        "lastFiredAt", "scheduledTimeZoneID", "offsetMinutes", "fireDate", "kindRaw"
    ])
    func scheduleAffectingPropertiesReconcile(property: String) async throws {
        let (out, taskID) = try await affected(properties: [property])
        #expect(out == [taskID], "\(property) can move a fire time, so it must reconcile")
    }

    @Test("The allow-list is exactly the documented set")
    func allowListIsPinned() {
        // Pinned deliberately: this set is a claim about scheduling semantics.
        // Widening it silently — especially to "any property" — would make
        // unrelated attribute churn trigger notification work.
        #expect(RemoteChangeReconciler.scheduleAffectingSpecProperties == [
            "lastFiredAt", "scheduledTimeZoneID", "offsetMinutes", "fireDate", "kindRaw"
        ])
        #expect(
            RemoteChangeReconciler.scheduleAffectingSpecProperties.contains("snoozedUntil") == false,
            "LIL-90: snooze is device-local, so a remote snooze edit is impossible, not merely ignored"
        )
    }

    // MARK: - Still correctly ignored

    @Test("A remote edit touching only a non-scheduling property does NOT reconcile")
    func nonSchedulingEditIsIgnored() async throws {
        let (out, _) = try await affected(properties: ["createdAt"])
        #expect(out.isEmpty, "reconciling on churn that cannot move a fire time is wasted work")
    }

    @Test("A remote edit touching a scheduling property alongside others still reconciles")
    func mixedEditReconciles() async throws {
        let (out, taskID) = try await affected(properties: ["createdAt", "fireDate"])
        #expect(out == [taskID])
    }

    @Test("A self-authored in-place edit is still ignored")
    func selfAuthoredEditIgnored() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "Take medication")
        let specID = try await specs.add(
            taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil
        )

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: try await specObjectID(ctx, specID),
            entityName: "NotificationSpec",
            changedProperties: ["scheduledTimeZoneID"],
            author: PersistenceController.localTransactionAuthor
        )
        let out = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(out.isEmpty, "this device already did the work that produced the change")
    }
}
