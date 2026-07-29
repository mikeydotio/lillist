import Testing
import Foundation
import CoreData
@testable import LillistCore

/// X19: `add`'s default-spec dedup branch used to decide whether to save
/// via `if context.hasChanges { save() }` — a store-wide check, not "did
/// this branch make a change." Under `withMutationRollback`'s save-only-if-
/// body-dirtied gate, the found-no-duplicates case (the common one) makes
/// zero changes and triggers zero saves — directly observable as no
/// `NSManagedObjectContextDidSave` notification. (`hasChanges` is
/// context-wide, not scoped to a caller, so this — like every mutator's
/// safety — depends on the invariant that nothing else was already dirty
/// when the call began; see `MutationRollbackTests`'s documented-limitation
/// test for the case where that invariant is violated.)
@Suite("NotificationSpecStore X19 — add's dedup branch doesn't save when nothing changed")
struct NotificationSpecStoreX19Tests {
    @Test("add() with an existing default spec and no duplicates never saves on a clean context")
    func addNoDuplicatesNeverSavesOnCleanContext() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let firstID = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: Date())

        let ctx = p.container.viewContext
        final class SaveObserved: @unchecked Sendable {
            var fired = false
        }
        let observed = SaveObserved()
        let token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: ctx,
            queue: nil
        ) { _ in observed.fired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        // Exactly one existing default spec, no duplicates to collapse —
        // the branch that used to do a store-wide hasChanges-gated save.
        let secondID = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: Date())

        #expect(secondID == firstID, "idempotent: returns the existing survivor's id")
        #expect(observed.fired == false, "the no-op dedup branch must never call context.save()")
    }
}
