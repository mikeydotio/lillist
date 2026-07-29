import Testing
import Foundation
import CoreData
@testable import LillistCore

private struct ProbeError: Error {}

@Suite("withMutationRollback")
struct MutationRollbackTests {
    @Test("A body that mutates and succeeds saves the change and returns its value")
    func mutatingBodySavesAndReturnsValue() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        let id = UUID()

        let returned: UUID = try await withMutationRollback(context: ctx) {
            let tag = LillistCore.Tag(context: ctx)
            tag.id = id
            tag.name = "Home"
            return id
        }

        #expect(returned == id)
        let hasChanges: Bool = await ctx.perform { ctx.hasChanges }
        #expect(hasChanges == false, "a successful mutation must be saved, not left dirty")
        let saved: String? = try await ctx.perform {
            let req = NSFetchRequest<LillistCore.Tag>(entityName: "Tag")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            return try ctx.fetch(req).first?.name
        }
        #expect(saved == "Home")
    }

    /// The realistic (invariant-respecting) shape of H5's TaskStore wart fix:
    /// under full adoption, nothing else can be transiently dirty on the
    /// context when a `withMutationRollback` call begins (every other
    /// mutator is itself atomic — mutate-then-save-or-rollback within one
    /// `perform` scope, never split across an `await`). So a throw that
    /// never touches the context leaves nothing to roll back, and the
    /// context — correctly — never becomes dirty in the first place.
    @Test("A body that throws before touching the context never dirties it")
    func throwingBeforeMutationNeverDirtiesContext() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext

        var threw = false
        do {
            _ = try await withMutationRollback(context: ctx) { () throws -> Void in
                throw ProbeError()
            }
        } catch is ProbeError {
            threw = true
        }
        #expect(threw == true)

        let hasChanges: Bool = await ctx.perform { ctx.hasChanges }
        #expect(hasChanges == false)
    }

    /// Documents a known, load-bearing limitation (plan-5a §8 "Deliberate
    /// tech debt"): `context.hasChanges` is context-wide, not scoped to a
    /// specific caller's own work, so the rollback guard cannot by itself
    /// distinguish "my own dirt" from "someone else's already-staged dirt."
    /// Safety against cross-caller contamination comes entirely from the
    /// structural invariant that EVERY mutator is atomic (enforced by
    /// `MutationRollbackConformanceTests`, not by this guard in isolation).
    /// If that invariant is ever violated — some future caller mutates the
    /// context and leaves it dirty across an `await` gap — this test proves
    /// the fallout: an unrelated throw rolls that stray work back too. This
    /// is intentional, not a bug this helper is meant to prevent; it's the
    /// documented trigger for the full `MutationContext` re-architecture the
    /// plan doc rejected for now.
    @Test("A pre-existing dirty context is rolled back by an unrelated throw (documented limitation)")
    func preExistingDirtyContextIsNotProtectedFromAnUnrelatedThrow() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext

        // Simulate a hypothetical invariant violation: some other party left
        // the context dirty without saving-or-rolling-back atomically.
        await ctx.perform {
            let tag = LillistCore.Tag(context: ctx)
            tag.id = UUID()
            tag.name = "PreStaged"
        }
        let preHasChanges: Bool = await ctx.perform { ctx.hasChanges }
        #expect(preHasChanges == true)

        var threw = false
        do {
            _ = try await withMutationRollback(context: ctx) { () throws -> Void in
                throw ProbeError()
            }
        } catch is ProbeError {
            threw = true
        }
        #expect(threw == true)

        let postHasChanges: Bool = await ctx.perform { ctx.hasChanges }
        #expect(postHasChanges == false, "documented limitation: hasChanges can't tell whose dirt it is")
    }

    @Test("A body that mutates then throws rolls back its own change")
    func mutatingThenThrowingRollsBackOwnChange() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        let id = UUID()

        var threw = false
        do {
            _ = try await withMutationRollback(context: ctx) { () throws -> Void in
                let tag = LillistCore.Tag(context: ctx)
                tag.id = id
                tag.name = "Doomed"
                throw ProbeError()
            }
        } catch is ProbeError {
            threw = true
        }
        #expect(threw == true)

        let hasChanges: Bool = await ctx.perform { ctx.hasChanges }
        #expect(hasChanges == false, "the body's own partial mutation must be rolled back")
        let count: Int = try await ctx.perform {
            let req = NSFetchRequest<LillistCore.Tag>(entityName: "Tag")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            return try ctx.count(for: req)
        }
        #expect(count == 0)
    }

    /// X19: a no-op body must never call `context.save()` at all — on a
    /// clean context (the realistic, invariant-respecting case — see the
    /// pre-existing-dirty-context test above for the documented exception),
    /// this is directly observable: no `NSManagedObjectContextDidSave`
    /// notification fires. Avoiding a gratuitous save also avoids the
    /// notification churn and (on a real CloudKit-mirrored store) a
    /// meaningless export attempt for a body that changed nothing.
    @Test("A no-op body on a clean context never fires a did-save notification")
    func noOpBodyOnCleanContextNeverSaves() async throws {
        let p = try await TestStore.make()
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

        let result: Int = try await withMutationRollback(context: ctx) {
            42   // no context mutation at all
        }
        #expect(result == 42)

        let hasChanges: Bool = await ctx.perform { ctx.hasChanges }
        #expect(hasChanges == false)
        #expect(observed.fired == false, "a no-op body must never call context.save()")
    }
}
