# Plan 1b — Purge/CloudKit Retirement

**Program:** [Data & Sync Hardening](2026-07-28-data-sync-hardening-index.md), Wave 1, plan `1b`.
**Findings:** `C4`/`X4` (merged), `H3`, `X14` (stories `LIL-10`, `LIL-21`, `LIL-63`).
**Source review:** [`docs/reviews/2026-07-28-data-sync-review.md`](../../reviews/2026-07-28-data-sync-review.md).

**Story-ID correction:** the wave-1b brief cited `H3`→`LIL-23` and `X14`→`LIL-48`. Both are
wrong — `LIL-23` is `H5` ("Five stores never roll back failed mutations…", `plan-5a`) and
`LIL-48` is `M4` ("`PreferencesStore.read()` performs writes", `plan-5a`). The ledger's own
*Story-ID cross-reference table* and `story show` agree on `H3`→`LIL-21` and `X14`→`LIL-63`;
those are the IDs this plan's commits close. Flagged to `team-lead`.

## Why one plan for three findings

All three sit in the exact two purge call sites (`TaskStore.batchPurge`, `AutoPurgeJob.run`)
plus one directly-adjacent one (`TaskStore.hardDelete`). `C4`/`X4`'s fix — replacing
`NSBatchDeleteRequest` with chunked managed-object-context deletes — reshapes those call sites
enough that `H3` (notification cancellation) and `X14` (delete-time revalidation) are best
designed against the *new* shape, not bolted onto the old one and then redone. Same
shared-file-chain discipline as 1a: read the current code first, fix once, land as separate
commits per finding (two-hats).

## C4/X4 — batch deletes bypass CloudKit mirroring

### The defect

`TaskStore.batchPurge` and `AutoPurgeJob.run` fetch trashed victims, expand the cascade
closure via `CascadeReaper.planPurge(ofTrashedRoots:)` (1a's C1 fix — bounds the cascade at
any live descendant, promoting it to root first), then delete the closure with
`CascadeReaper.batchDelete(objectIDs:in:)` — a wrapper around `NSBatchDeleteRequest`, grouped
per-entity because that initializer is single-entity-only. Apple documents
`NSBatchDeleteRequest` as bypassing the managed-object graph entirely: it executes as a direct
SQL delete against the store, never touching `NSPersistentCloudKitContainer`'s per-object
export bookkeeping. A context-level `save()` with real `context.delete(_:)` calls is what NSPCC
observes to know a row must be tombstoned and exported as a CloudKit delete; a batch request
gives it nothing to observe. Corroborated by two independent review sweeps (`C4` stores, `X4`
cross-process): a purged task's `CKRecord` is never explicitly retired, so it can resurrect
from the zone on the next import — and since resurrection recreates a row with the *same*
`id`, `TaskDuplicateReconciler` has no signal to heal it (there's no local duplicate to merge;
the row is simply back). Suspected live in Production since the 2026-06-24 cutover — see the
ledger's manual-verification checklist; this fix does not wait on that audit.

### Fix: chunked managed-object-context deletes

Both purge call sites already run on a dedicated background context
(`persistence.makeBackgroundContext()`) so a large purge never blocks `viewContext`.
`hardDelete(id:)` already deletes correctly (`context.delete(m); try context.save()` — a normal
context-level delete, never batch) and has never been part of this defect; it's the existence
proof that context deletes plus the model's `Cascade` delete rules produce exactly the same
end state `CascadeReaper`'s manual traversal computes (see `LillistModel.xcdatamodeld`'s
relationship definitions: `children`/`journalEntries`/`attachments`/`notificationSpecs` are all
`deletionRule="Cascade"`, matching `CascadeReaper.collect(task:into:)` node-for-node). The fix
makes the two purge paths do what `hardDelete` already does, at scale:

1. **Fetch candidate roots** (unchanged filtering: matched victims whose parent doesn't also
   match the predicate, so a nested victim isn't independently processed — it's reached via its
   ancestor's cascade instead).
2. **Chunk the roots** into groups of `TrashPurger.defaultChunkSize` (**200**) and process one
   chunk per saved transaction. 200 doubles `TaskStore.listFetchBatchSize` (100, the existing
   paging precedent in this file) — few enough that one chunk's `CascadeReaper.planPurge` call
   plus its save stays well within interactive latency even on contended hardware, large enough
   that a 10k-row "Empty Trash" is tens of round trips, not thousands. No other numeric
   precedent exists in this codebase for a delete-chunk size, so this is a reasoned pick, not a
   measured one — revisit if a real-world purge shows chunk-boundary overhead.
3. **Per chunk:** re-fetch each candidate root via `ctx.existingObject(with:)`, re-evaluate the
   *original victim predicate* against it (not just "still has `deletedAt`" — see `X14`
   below), run `CascadeReaper.planPurge` fresh against the surviving roots (promoting any live
   descendant to root — 1a's C1 barrier, now re-derived every chunk instead of once globally),
   save the promotion, then `ctx.delete(root)` for each validated root and `save()` again. Core
   Data's own Cascade delete rule removes the rest of that root's subtree (journal entries,
   attachments, notification specs, cascade-trashed descendants) automatically — no manual
   per-entity batch grouping needed, because this is no longer a batch request.
4. **Merge into `viewContext`:** unchanged mechanism — `NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: plan.deletable], into: [viewContext])`, awaited on `viewContext`'s own queue. `plan.deletable` (all four entity types, not just the
   roots) is still required here: only explicitly deleting the *root* objects and relying on
   Core Data's in-memory cascade to remove the rest means `viewContext` would otherwise be left
   holding dangling faults for the cascaded descendants exactly as `CascadeReaper`'s original
   doc comment warns against for the old batch-delete path. This is a **deliberate non-change**:
   the bug is the *deletion* mechanism (`NSBatchDeleteRequest`), not the `viewContext`-sync
   mechanism, which already works correctly and is proven by every existing purge test. Relying
   instead on `viewContext.automaticallyMergesChangesFromParent` (already `true`) was considered
   and rejected: that merge is dispatched asynchronously onto `viewContext`'s queue in response
   to the background context's real `NSManagedObjectContextDidSave` notification, and while nothing
   in Core Data's contract guarantees it has *run* by the time `purgeAll()`/`AutoPurgeJob.run()`
   returns, the explicit awaited merge does guarantee it — keeping every existing test
   (`TaskStorePurgeAllTests`, `AutoPurgeJobTests`) reading `viewContext` immediately after a
   purge call returns deterministic rather than newly flaky.

### Shared extraction: `TrashPurger`

`TaskStore.batchPurge` and `AutoPurgeJob.run` were already near-duplicates before this fix;
rewriting both by hand would make them near-duplicates again. New internal (not public — both
call sites are in-module) type `Persistence/TrashPurger.swift` holds the chunked-purge
algorithm once:

```
enum TrashPurger {
    static let defaultChunkSize = 200

    static func fetchCandidateRootObjectIDs(
        predicateFormat: String, arguments: [any Sendable], context: NSManagedObjectContext
    ) async throws -> [NSManagedObjectID]

    static func purgeChunk(
        _ chunk: [NSManagedObjectID],
        predicateFormat: String, arguments: [any Sendable],
        context: NSManagedObjectContext, viewContext: NSManagedObjectContext,
        notificationScheduler: (any NotificationReconciling)?
    ) async throws -> Int   // tasks purged in this chunk

    static func purge(
        predicateFormat: String, arguments: [any Sendable],
        context: NSManagedObjectContext, viewContext: NSManagedObjectContext,
        notificationScheduler: (any NotificationReconciling)?,
        chunkSize: Int = defaultChunkSize
    ) async throws -> Int   // composes the two above
}
```

`fetchCandidateRootObjectIDs`/`purgeChunk` are exposed separately (not folded into `purge`) so
`X14`'s regression test can drive them independently — see below. `predicateFormat`/`arguments`
(not a prebuilt `NSPredicate`) preserve the existing hoist-and-rebuild pattern
(`TaskStore.batchPurge`'s current doc comment): `NSPredicate` is not `Sendable` and must never
be captured across the `ctx.perform` actor boundary — each `perform` block rebuilds it locally
from the `Sendable` format string + argument array, exactly as today. `TaskStore.batchPurge`
and `AutoPurgeJob.run` become thin callers that supply their own predicate + arguments and
their own `notificationScheduler`.

This is a small internal plumbing type, not a new architectural concept (no public API, no new
concurrency model, no cross-cutting pattern) — it doesn't rise to the house rule's
type-system-proposal-plus-UML bar (reserved for public/architectural additions; see 1a's
`TreeIntegrityChecker`/`TaskTreeRepair` for the contrast). Documented here instead.

### `CascadeReaper`'s fate (explicit verdict, no council needed)

The wave brief asked this be decided explicitly, with council-vote if genuinely 2-sided. It
isn't, once the H3 design (below) is factored in:

- **`CascadeReaper.planPurge(ofTrashedRoots:)` — kept, unchanged.** Still the only correct way
  to compute 1a's C1 live-descendant barrier, and now also doubles as the source of the
  doomed-task-ID list `H3`'s notification cancellation needs (`plan.deletable`, filtered to
  `LillistTask` entities).
- **`CascadeReaper.objectIDs(forDeleting:)` — kept, repurposed.** Before this plan its only
  caller was its own unit tests (`CascadeReaperTests`) — genuinely closer to dead code. `H3`
  gives it a real, permanent caller: `TaskStore.hardDelete` needs the *unconditional* cascade
  closure (every descendant regardless of `deletedAt`, since `hardDelete` has no live/trashed
  barrier concept — it permanently removes a specific task and everything under it, full stop)
  to collect the task-ID closure for notification cancellation before deleting. That's a
  different traversal contract than `planPurge`'s trash-bounded one, and `objectIDs(forDeleting:)`
  already implements it correctly and is already tested against the model's actual Cascade
  graph. Keeping two near-identical private traversals (`collect` vs. `collectForPurge`) inside
  one type is acceptable — they encode two genuinely different semantics (unconditional reap vs.
  barrier-bounded reap), not accidental duplication.
- **`CascadeReaper.batchDelete(objectIDs:in:)` — deleted.** Zero callers once both purge paths
  stop using it; it is *literally the mechanism this plan retires* (the direct
  `NSBatchDeleteRequest` wrapper). Keeping it around unused would leave the exact attractive
  nuisance a future contributor could reach for again, defeating the fix. No test exercises it
  directly (`CascadeReaperTests` only tests `objectIDs(forDeleting:)`), so nothing needs
  updating beyond removing the function and its now-stale doc comment references.

The type's top-level doc comment is rewritten to describe both surviving traversals and why
each exists, rather than framing the whole type around "so `NSBatchDeleteRequest` can reproduce
[Cascade] rules" (no longer true for either remaining function).

## X14 — revalidate the victim predicate at delete time

### The defect

Both purge paths originally fetched victims once, then did all subsequent work (barrier
promotion, batch delete) inside a single `ctx.perform` block with no intervening suspension
point — but chunking `X14`'s fix *introduces* suspension points between chunks (each chunk is
its own `await ctx.perform`), and even before chunking, `AutoPurgeJob`'s `preferences.read()` /
the time between `now` being captured and the fetch running is real elapsed wall-clock time in
production. A task restored (`deletedAt` cleared) or re-trashed with a fresher timestamp after
being fetched as a candidate but before its chunk's delete runs must not be purged — `X14`
calls this out explicitly, and it directly protects `C4`/`X4`'s fix from resurrecting a task
that was never actually supposed to be deleted in the first place (a restore-then-immediate-purge
race would otherwise still delete the row, and *then* `C4`/`X4`'s own fix would faithfully
mirror that incorrect deletion to CloudKit — correctly-exported wrong behavior is still wrong).

### Fix

`TrashPurger.purgeChunk` re-fetches each candidate objectID via `ctx.existingObject(with:)` and
re-evaluates the **original predicate** (`NSPredicate.evaluate(with:)`, rebuilt from
`predicateFormat`/`arguments` inside the same `perform` block) against the live object,
skipping (not purging) anything that no longer matches. This is a full predicate re-check, not
a narrower "is `deletedAt` still non-nil" check — `AutoPurgeJob`'s predicate is
`deletedAt != nil AND deletedAt < cutoff`, and `softDelete(id:)` has no guard against
re-trashing an already-trashed task (it unconditionally stamps `deletedAt = now`), so a task
can move from "past the retention cutoff" back to "within it" without `deletedAt` ever becoming
nil. Only the full predicate catches that case; a bare non-nil check would not.

### Regression test design

The interesting race is: task fetched as a Step-0 candidate (so it's already registered/fired
in the purge's background context, with `deletedAt != nil` cached) → restored via `viewContext`
(a *different*, real, saved context transaction) → the chunk's delete-time re-check must see
the restore, not the stale cached value. This is deterministic, not timing-based, for the same
reason `TagStoreFindOrCreateRaceTests.secondContextCanRace` is: `ctx.automaticallyMergesChangesFromParent
= true`, and `NSManagedObjectContext.save()` posts its `NSManagedObjectContextDidSave`
notification *synchronously* before returning, which (because the observing context has
auto-merge enabled) enqueues a merge block onto the purge context's own serial queue
synchronously as part of that same call — i.e., by the time the test's `await viewContext.perform
{ ...restore...; try viewContext.save() }` call returns, the merge block is already ahead of
anything the test subsequently enqueues via `ctx.perform` on the purge context, giving FIFO
ordering without a sleep. Test drives `TrashPurger.fetchCandidateRootObjectIDs` then
`purgeChunk` directly (both `internal`, reachable via `@testable import`) rather than the full
`purge()`, so the restore can be inserted at the exact right point without needing an
artificial test-only hook in production code (matching the existing
`TagStoreFindOrCreateRaceTests` precedent of driving real contexts by hand instead of adding
seams).

## H3 — cancel pending OS notifications before purged rows vanish

### The defect

`hardDelete`, `purgeAll`/`batchPurge`, and `AutoPurgeJob.run` all permanently remove
`LillistTask` rows with no notification-scheduler awareness at all — `AutoPurgeJob` doesn't
even have a `notificationScheduler` property. A purged task's OS-level reminder still fires
later, and its deep link (`lillist://task/<id>`) now dangles. Critically, the *existing*
mutation pattern used elsewhere in `TaskStore` — call `notificationScheduler?.reconcile(taskID:)`
*after* the save — does not work here: `reconcile(taskID:)` starts by fetching the task from
`viewContext` (`loadTaskSnapshot`), and for every other mutation path (`update`, `transition`,
`softDelete`, `restore`) the row still exists at that point (soft-delete only sets `deletedAt`;
`computeDesiredRequests` reads it and returns `[]`, achieving cancellation *through* the normal
diff). After a **hard** delete the row is entirely gone — `loadTaskSnapshot` throws
`.notFound`, and `reconcile`'s own top-level `catch` silently swallows it, so calling `reconcile`
post-hard-delete is a guaranteed silent no-op. This is exactly why the finding names a new
mechanism rather than "just call reconcile like everywhere else."

### Fix: a new protocol method that doesn't require the row to exist

`NotificationReconciling` gains a second requirement:

```swift
public protocol NotificationReconciling: Sendable {
    func reconcile(taskID: UUID) async
    /// Cancels every pending OS notification for each id in `taskIDs`,
    /// without requiring the corresponding task row to still exist. Used
    /// after a hard delete / purge, where `reconcile(taskID:)` would
    /// silently no-op (see the type's doc comment).
    func cancelPending(forTaskIDs taskIDs: [UUID]) async
}
```

`NotificationScheduler`'s implementation reuses its existing `isPendingForTask` matching logic
(which already keys off `request.content.userInfo["taskID"]`, not a DB lookup — it has to,
since it also has to match specs that were *just* deleted in the same reconcile pass), widened
to accept a `Set<String>` of task-id strings instead of one, fetches
`pendingNotificationRequests()` **once**, filters, and issues **one**
`removePendingNotificationRequests(withIdentifiers:)` call for the whole batch — deliberately
not "call `cancelPending` once per task ID," which would mean N full OS-level pending-request
fetches for an N-task purge (thousands, for "Empty Trash" on an old device). `NotificationReconciling`
has exactly one production conformer (`NotificationScheduler` — confirmed by grep; tests either
inject the real scheduler against a fake `UNUserNotificationCenterProtocol` or leave the
property `nil`), so this is not a source-breaking protocol change for any test double.

### Ordering (binding, per the wave brief)

Collect ids first, cancel only after a successful save — never before, and never for ids whose
save didn't happen:

- **`hardDelete`:** collect `CascadeReaper.objectIDs(forDeleting: [m])` (filtered to
  `LillistTask`, mapped to `.id`) **before** `context.delete(m)`, inside the same
  `context.perform` block as the delete + save. `cancelPending` is called *after* `context.perform`
  returns without throwing — a failed save propagates to `hardDelete`'s existing `catch`
  (rollback), and the collected ids are never used.
- **`TrashPurger.purgeChunk`:** collects `plan.deletable`'s `LillistTask`-entity ids **before**
  the chunk's `ctx.delete(root)` calls, inside the same `perform` block as the delete + save,
  and calls `cancelPending` **per chunk**, immediately after that chunk's `viewContext` merge —
  not once at the very end of the whole purge. This matters for partial-failure correctness: if
  chunk 5 of 10 throws, chunks 1–4 are already durably saved and merged, and their
  notifications must already be cancelled by that point (they are — `cancelPending` already ran
  for them) rather than depending on the *entire* purge succeeding before any cancellation
  happens.

This is a separate commit from the `C4`/`X4` rewrite (two hats — `H3` is new behavior, `C4`/`X4`
is a mechanism swap with no behavior change to the deleted/kept row set).

### App-target wiring

`AutoPurgeJob` gains a `public var notificationScheduler: (any NotificationReconciling)?`,
property-injected exactly like `TaskStore`'s (same doc-comment shape: optional, set by the
composition root, `nil` in tests that don't care, no-op when unset). Both `AppEnvironment.swift`
(iOS and macOS — distinct regions per the ledger's serial-chain note) get one line added right
after the existing `self.taskStore.notificationScheduler = scheduler`:
`self.autoPurgeJob.notificationScheduler = scheduler`. This is the one app-target touch this
plan makes; verified via unsigned `xcodebuild` builds for both apps per the ledger's
verification gate (no signed build needed for a property-assignment change).

## Test plan (TDD, red→green per finding)

- `Packages/LillistCore/Tests/LillistCoreTests/Persistence/C4X4PurgeMirroringTests.swift` —
  asserts the *mechanism*: register an `NSManagedObjectContextDidSave` observer before calling
  `purgeAll()`/`AutoPurgeJob.run()`, assert the purged task's objectID appears in some captured
  notification's `NSDeletedObjectsKey`. This is the discriminating signal `NSBatchDeleteRequest`
  never produces (it calls `context.execute(_:)`, never `context.save()`, so no such
  notification fires for the affected rows — which is exactly why the *old* code needed a
  synthetic `mergeChanges(fromRemoteContextSave:)` call instead of relying on one). Existing
  `TaskStorePurgeAllTests`/`AutoPurgeJobTests`/`C1LiveDescendantPurgeTests` assert only end
  state (row counts, survivor promotion) and must keep passing unmodified — they don't
  discriminate the mechanism, which is why this plan adds a dedicated mechanism-level suite
  rather than relying on them.
- `Packages/LillistCore/Tests/LillistCoreTests/Persistence/X14PurgeRevalidationTests.swift` —
  the deterministic restore-mid-flight race described above, plus a fresher-`deletedAt`
  re-trash variant (predicate-level, not just nil-check).
- `Packages/LillistCore/Tests/LillistCoreTests/Notifications/H3PurgeNotificationCancellationTests.swift`
  — `hardDelete` cancels its own + every descendant's pending notifications;
  `purgeAll`/`AutoPurgeJob.run` do the same for a purged subtree; a task with **no** pending
  notifications purges cleanly with `notificationScheduler` nil (existing tests' composition
  pattern) and with it set (no crash, no-op removal call).
- `CascadeReaperTests.swift` — unchanged (still exercises `objectIDs(forDeleting:)`, now proven
  live by `hardDelete`'s real usage rather than only by these tests).
- Existing `TaskStorePurgeAllTests`, `AutoPurgeJobTests`, `C1LiveDescendantPurgeTests` — must
  pass **unmodified**; they encode the behavioral contract (`purgedCount`, barrier promotion)
  this plan must not change, only reimplement.

## Verification gate

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test --package-path Packages/LillistCore --parallel --num-workers 2
```

Baseline to not regress: 1a closed at 1134 tests / 216 suites. Plus unsigned `xcodebuild`
builds for both apps (AppEnvironment.swift touch).

## Closeout notes for 1c/1d

- `TrashPurger.swift` is a new shared-file dependency for anything that purges tasks. `1d`
  (export-schema-completeness) doesn't touch it. If a future plan needs to purge by a different
  predicate, extend via `TrashPurger.purge(predicateFormat:arguments:...)` rather than adding a
  third hand-rolled copy of this loop.
- `CascadeReaper.batchDelete(objectIDs:in:)` no longer exists — if any later plan's review of
  `docs/engineering-notes.md`'s "Batch delete skips delete rules" entry assumes it's still
  called, that entry is superseded by a new dated entry this plan adds (append-only convention;
  the old entry is left in place as historical record of the *problem*, not the current fix).
- `NotificationReconciling` now has two methods. Any *new* conformer (none exist today besides
  `NotificationScheduler`) must implement `cancelPending(forTaskIDs:)`.
