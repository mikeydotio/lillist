# Remediation Plan

> Designed via a 3-architect panel (minimalist / invariant / question-the-scheme),
> adversarial critique of each, and a synthesis judge — then code-verified and
> corrected by the orchestrator. See `VERIFICATION.md` for the root cause.

## Root Cause (summary)

An **unenforced strictly-increasing-siblings invariant**: non-atomic
`nextPosition = max(position) + 1.0` raced across uncoordinated writers
(Share/App-Intents XPC extensions + CloudKit imports) mints two equal-position
("tied") siblings at the tail. A drag into that gap calls
`reorder(after, before)` with `after.position == before.position`; the
`anchorsAreOutOfOrder` guard throws **before** the `recompactSiblings` self-heal
can run, and the throw is rendered as a full-screen "Could not load tasks".

## Guiding philosophy

**Ties are expected input, not corruption.** Make every presenter agree on one
canonical sibling order, heal a degenerate anchor pair in that exact order
before re-checking the guard, and demote reorder write-failures to a transient
surface. Do **not** try to prevent ties at write time (impossible under CloudKit).

## Decisions on the six questions

### Q1 — Origin allocator: KEEP & TOLERATE (do not touch `nextPosition`)
A `(parent, position)` uniqueness constraint is the only true write-time
prevention and CloudKit cannot mirror constraints. The race is cross-context /
cross-device (proven by `TagStoreFindOrCreateRaceTests`); no single-context
write change closes it. "Hardening" the max-fetch tie-break is a **verified
no-op** (`fetchLimit = 1`, returns `max + 1.0` regardless of secondary sort).
**YAGNI — leave it; enforce at the consumer.**

### Q2 — Reorder heal (R1): heal-then-recheck via the SINGLE `anchorsAreOutOfOrder` predicate
Restructure both `reorder` methods inside the existing `perform` block:
mixed-parent/cycle guards (unchanged) → **soft-deleted-anchor guard** (throw
`notFound`) → if `anchorsAreOutOfOrder(after, before)`: `recompactSiblings`
(now in canonical order) → `context.refresh` both anchors → **re-check**
`anchorsAreOutOfOrder`; if still true, throw; else fall through to the existing
`needsCompaction`/midpoint/save path (recomputed against refreshed positions).

**Why this is correct (orchestrator's proof, correcting the synthesis):**
recompaction assigns each sibling its *rank* under `SiblingOrder`
(`position`-primary). So `after.newpos < before.newpos` **iff**
`SiblingOrder.precedes(after, before)` **iff** `after.position ≤ before.position`.
Therefore:
- **Tie (`a == b`)** → recompaction breaks it by `id`; since the resolver picks
  `after` = the visually-above row (smaller `id` for a tie), `after` gets the
  lower rank → re-check passes → midpoint lands in the user's slot. **Heals.**
- **Inversion (`a > b`)** → `after` still ranks higher post-recompaction →
  re-check throws. This is correct: an `a > b` at reorder time is **only** a
  swapped programmatic request *or* a position changed by a CloudKit merge
  between the `flatRows` snapshot and execution — neither should be silently
  "healed" against a stale intent. R2 makes the throw graceful.

> Correction vs. synthesis: there is **no** "adjacent inversion that heals" —
> the heal handles ties; all inversions throw. The control flow is unchanged
> (it already does this); only the rationale and test T6's expectation change.

### Q3 — Tie-break unification: ONE canonical comparator in LillistCore, sorted in Swift, applied to BOTH presenters
New `Packages/LillistCore/Sources/LillistCore/Ordering/SiblingOrder.swift`:
```swift
public enum SiblingOrder {
    /// Canonical personalized sibling order: position ascending, then
    /// id.uuidString ascending. The single source of truth shared by every
    /// presenter (iOS TaskTree, macOS buildTree) and every recompaction.
    public static func precedes(positionA: Double, idA: UUID,
                                positionB: Double, idB: UUID) -> Bool {
        positionA != positionB ? positionA < positionB
                               : idA.uuidString < idB.uuidString
    }
}
```
Consumers, all sorting **in Swift in-memory** (never `NSSortDescriptor` on the
UUID attribute — Core Data orders UUID as raw bytes, which is NOT guaranteed to
equal Swift's `uuidString` lexical order):
- `TaskTree.applySort(.personalized)` (iOS) — delegate, delete inline closure.
- **macOS `TaskListView.buildTree`** — re-sort each level via `SiblingOrder.precedes`.
- `TaskStore.recompactSiblings` & `SmartFilterStore.recompactSiblings` — fetch,
  then sort the array via `SiblingOrder.precedes` before `PositionCompactor`.
- `SmartFilterStore.list()` — sort via `SiblingOrder.precedes` after fetch.

### Q4 — Load-time normalization (R3): INCLUDE, conditional + idempotent, explicit method
`TaskStore.normalizeSiblingsIfDegenerate(ofParent:)` and
`SmartFilterStore.normalizeIfDegenerate()`: in one `perform`, fetch, sort via
`SiblingOrder.precedes`, scan adjacent pairs; **only if** any
`position[i] >= position[i+1]`, `recompactSiblings` + `save`; else zero writes.
Pure, explicit, idempotent — called at the load seam (iOS `reload`, macOS
`refresh`, filters list). Detect-before-write bounds amplification; `SiblingOrder`
is device-independent (no `createdAt`/locale) so devices converge to identical
`1..n` and CloudKit does not ping-pong. **Scope note: R3 is belt-and-suspenders
— R1 alone un-bricks the reported bug. See the open scope question below.**

### Q5 — Error surfacing (R2): transient toast on BOTH platforms; never `loadError` from a write
- iOS `TasksView.applyDrop` catch: stop setting `loadError = "\(error)"`; set a
  new `@State reorderFailureMessage` (fixed localized copy) and `await reload()`.
- New transient surface in LillistUI (reuse the `ArchiveToast` pattern), distinct
  from the `loadError` `ContentUnavailableView` (reserved for real load failures).
- macOS `TaskListView.applyDrop` (currently silent) — add the same transient banner.
- **Copy (verbatim on both platforms):** `"Couldn't move that item. Please try again."`
  Raw `validationFailed([...])` flows only into `emitReorderDiag`, never to the UI.
- Three `Localizable.xcstrings` kept aligned.

### Q6 — SmartFilter parity (+ latent bug fix)
Identical guard→heal→re-read→re-check→compute restructure in
`SmartFilterStore.reorder`; `recompactSiblings`/`list()` via `SiblingOrder`;
same transient surface. **Also fix `sortDescriptors` line ~421:** `.manualPosition`
must use `primaryKey = "position"`, not `"deadline"` (verify no caller depends on
the broken mapping). Tests mirror the TaskStore suite case-for-case.

## Anti-Pattern Check
| Check | Pass | Notes |
|-------|------|-------|
| Not symptom masking | ✅ | Fixes the unenforced invariant at the consumer + unifies the comparator; not a try/catch over the throw |
| Not a band-aid | ✅ | No special-case flag; the guard is *re-evaluated* after a real repair |
| Not whack-a-mole | ✅ | One comparator + one heal pattern applied to every presenter & both stores |
| Removes flawed assumption | ✅ | Drops "single-context atomicity ⇒ no ties" and "store order == UI order" |
| Strengthens invariants | ✅ | Degenerate data self-heals deterministically, device-independently |
| Simplifies | ✅ | Deletes duplicated sort closures; single `anchorsAreOutOfOrder` discriminator reused |

## Confirmed correctness holes closed
- **H1 macOS slot-mirror** — macOS `buildTree` re-sorts via `SiblingOrder`.
- **H2 filter `.manualPosition → deadline`** — fixed to `"position"`.
- **H3 filtered/hidden sibling between anchors** — discriminator reads only the
  two anchors' positions, filter-agnostic.
- **H4 N≥3 ties** — pair-position check is tie-count-agnostic.
- **H5 stale/`a>b` inversion** — correctly throws → R2 toast + reload (graceful).
- **H6 soft-deleted anchor** — throw `notFound` before heal; `context.refresh` after recompact.
- **H7 write-error-as-load-error / macOS silent swallow** — transient toast both platforms.
- **H8 toast on `.noop`** — `.noop` never throws, so the catch never fires for it.

## TDD test plan (red first; reuse `TagStoreFindOrCreateRaceTests` two-context pattern)
1. **T1 `SiblingOrderTests`** — distinct→by position; equal→by `id.uuidString`;
   **parity**: sorting `TaskRecord`s by `SiblingOrder` == `TaskTree.applySort(.personalized)`.
2. **T2 `healsEqualTailPair`** — two siblings written at identical tail position;
   reorder a third into the gap → no throw, strictly increasing, intended slot.
3. **T3 brick repro (two-context tie)** — independent ctxA/ctxB both write `max+1` →
   equal pair; reorder into the gap → throws today, heals after fix, intended slot.
4. **T4 regression** — `TaskStoreOrderingTests.outOfOrderAnchors` (distinct 1,2,3;
   `after=B before=A`) **still throws** after the restructure.
5. **T5** — existing `reorderBetween/Head/Tail/mixedParents/repeatedSameGapInsertsCompact` stay green.
6. **T6 stale inversion → throws gracefully** *(corrected)* — anchors mutated to
   `a>b` between snapshot and reorder → **throws** (not heals); paired with the
   UI test that this surfaces as a toast + reload, not a brick.
7. **T7 filtered/hidden sibling between anchors** → heals, no brick.
8. **T8 N≥3 ties** → heals, lands between the user's chosen neighbors.
9. **T9 tie-break disagreement** — tied pair whose `createdAt` order is opposite
   its `id.uuidString` order → post-heal order matches `id` (UI), not `createdAt`.
10. **T10 soft-deleted anchor** → throws `notFound`.
11. **T11** — `SmartFilterStore.sortDescriptors(.manualPosition)` primary key is `"position"`.
12. **T12 iOS surfacing** — forced throw sets `reorderFailureMessage`, leaves
    `loadError` nil; `TasksScreen` renders the list; message has no `"validationFailed"`.
13. **T13 macOS surfacing** — failure shows the transient banner; list intact.
14. **T14** — `.noop` resolution produces no toast on either platform.
15. **T15 single-element & nil anchors** — head/tail/only-sibling → no heal, no throw.
16. **T16 CloudKit merge mid-session** — merge a remote tie into the viewContext
    between load and drop, then drop into the gap → heals on refreshed anchors.
17. **T17 normalize idempotency** — healthy→0 writes; degenerate→one repair; second call→no-op.
18. **T18 SmartFilter parity** — mirror T2/T3/T4/T6/T9/T17 against `SmartFilterStore`.
19. **T9-macOS** — `buildTree` level order == `SiblingOrder`; tied-pair drop lands in intended slot.
20. **T19 stress** — bounded-parallel repetition of T3 to shake out refresh-after-recompact.

## Implementation steps (small, focused commits, TDD per step)
1. `test(ordering): SiblingOrder comparator + parity (red)` — T1.
2. `feat(ordering): canonical SiblingOrder comparator` — new file; T1 green.
3. `refactor(ui): TaskTree uses SiblingOrder` — delete inline closure.
4. `fix(macos): buildTree sorts via SiblingOrder` — + T9-macOS.
5. `fix(smartfilter): manualPosition sorts by position` — sortDescriptors line ~421; + T11.
6. `test(taskstore): reorder heal repro (red)` — T2,T3,T4,T6,T7,T8,T9,T10,T15,T16.
7. `fix(taskstore): heal-then-recheck reorder + canonical recompaction` — restructure
   `reorder` (soft-delete guard, heal branch, `context.refresh`, re-check, recompute);
   `recompactSiblings` via `SiblingOrder`. Step-6 green; T5 stays green.
8. `fix(smartfilter): heal-then-recheck reorder parity` — same restructure; `recompactSiblings`/`list()`; + T18.
9. `feat(taskstore): conditional idempotent load-time normalize (R3)` — `normalizeSiblingsIfDegenerate`; wire at load seams; + T17. *(gated on scope decision)*
10. `fix(ui): transient reorder-failure surface, drop loadError from writes` — iOS + LillistUI toast + macOS banner; + T12,T13,T14.
11. `chore(loc): reorder-failure string in three xcstrings`.
12. `test(stress): bounded-parallel reorder-heal repetition` — T19.
13. `docs(engineering-notes): SiblingOrder is the sole sibling comparator`.

## Explicitly rejected
- Hardening `nextPosition` tie-break (verified no-op). Write-time tie *prevention*
  (counter row / LexoRank / integer-dense reindex — unsafe under XPC+CloudKit;
  LexoRank needs a full migration + new CloudKit-backed attribute). The
  `anchorRelation {ok,tied,inverted}` enum (assumes-away the re-check). A global
  canonical-index adjacency test (breaks under filtered/hidden siblings + N≥3
  ties). Per-surface "already normalized" `Set`s (murky invalidation). A general
  `LillistError→copy` mapper (one message needed). Recovery migration (data is
  disposable). `NSSortDescriptor` on the UUID `id` attribute (byte-order ≠ uuidString).

## Impact / blast radius
- **LillistCore:** `SiblingOrder` (new), `TaskStore.reorder`/`recompactSiblings`/`+normalize`,
  `SmartFilterStore.reorder`/`recompactSiblings`/`list`/`sortDescriptors`/`+normalize`.
- **LillistUI:** `TaskTree`, transient toast, `TasksScreen` flatRows/loadError boundary.
- **Apps:** iOS `TasksView` (applyDrop, reload, new @State), macOS `TaskListView`
  (buildTree, applyDrop banner). Three `Localizable.xcstrings`.
- **Risk: LOW–MEDIUM.** Healthy lists are behavior-unchanged (heal inert on `.ok`).
  The visible change is tie display order (createdAt→id) on first heal — acceptable
  (a tie was already a latent defect; test data disposable).

## Lessons
Single-context atomicity ≠ cross-process/cross-device atomicity. An ordering
invariant CloudKit can't express as a constraint must be enforced by
*self-healing consumers* against *one canonical comparator*, not assumed at the
allocator. Store fetch order and UI presentation order must share that comparator
or any recompaction silently mirror-slots.
