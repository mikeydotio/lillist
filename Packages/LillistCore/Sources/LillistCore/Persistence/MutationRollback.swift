import Foundation
import CoreData

/// Runs `body` on `context`'s queue as one atomic mutate-then-save scope,
/// saving only if `body` actually dirtied the context, and rolling back on
/// any throw (from `body` or from the save itself) — but only if the
/// context has uncommitted changes at that moment.
///
/// This is the shared shape every mutating store method in `LillistCore`
/// funnels through (`5a` / `H5`), generalizing the rollback-on-catch pattern
/// `TaskStore` already had. Two invariants make the guards below safe rather
/// than merely convenient:
///
/// - **Rollback is gated on `hasChanges`.** A throw that happens *before*
///   `body` has touched the context (an early validation failure) must not
///   discard whatever another, legitimately in-flight
///   `withMutationRollback` call had already staged on the shared
///   `viewContext` — `NSManagedObjectContext.rollback()` is context-wide,
///   not scoped to the objects one caller touched. `NSManagedObjectContext
///   .perform` blocks are serialized by Core Data (one call's block runs to
///   completion before the next queued block starts), so as long as *every*
///   mutator of a shared context routes through this helper (or an equally
///   atomic mutate-then-save-or-rollback scope with no `await` gap in
///   between — the invariant `MutationRollbackConformanceTests` enforces
///   mechanically across every store), `context.hasChanges` at the moment
///   this catch runs can only be true because of *this* call's own `body`.
///   `hasChanges` itself is context-wide, not scoped to a caller — this
///   guard provides no protection if the invariant is ever violated (see
///   `MutationRollbackTests.preExistingDirtyContextIsNotProtectedFromAn
///   UnrelatedThrow` and plan-5a §8's "Deliberate tech debt" for the
///   documented limitation and its redesign trigger).
/// - **Save is gated on `hasChanges` too.** A `body` that makes no change
///   (an early-return guard, an idempotent no-op) never calls
///   `context.save()`, so it can never commit unrelated staged work as an
///   accidental side effect of doing nothing (`X19`).
///
/// See `docs/superpowers/plans/2026-07-28-plan-5a-mutation-scope-discipline.md`
/// §3 for the full design rationale and the rejected full-`MutationContext`
/// re-architecture alternative.
func withMutationRollback<T: Sendable>(
    context: NSManagedObjectContext,
    _ body: @escaping @Sendable () throws -> T
) async throws -> T {
    do {
        return try await context.perform {
            let value = try body()
            if context.hasChanges {
                try context.save()
            }
            return value
        }
    } catch {
        await context.perform {
            if context.hasChanges {
                context.rollback()
            }
        }
        throw error
    }
}
