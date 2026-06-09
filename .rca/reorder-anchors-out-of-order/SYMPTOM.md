# Symptom Report

## Observed Behavior
Dragging a task row from the **bottom** of the task list **up by one slot** produced a
full-screen error on the iOS Tasks surface:

> **Could not load tasks**
> `validationFailed([LillistCore.LillistError.Issue(field: "neighbors", message: "anchors out of order")])`

Build `0.1.0 (38)`. The list rendered no rows — the error surface replaced the whole list.

## Expected Behavior
Moving the bottom row up one position reorders it without error. At worst, a degenerate
ordering state should self-heal (recompact) rather than hard-fail the entire surface.

## Classification
**Data-dependent** (latent persisted-data corruption surfaced by a specific reorder),
compounded by a **resilience/UX defect** (write failure rendered as a load failure with a
raw Swift error description, and no self-healing).

## Timeline
- First noticed: 2026-06-06, build 0.1.0 (38).
- Suspected trigger: a reorder whose two visual neighbors had **equal or inverted persisted
  `position` anchors** before the drag. The drag itself did not create the bad anchors —
  `reorder` rolls back on throw (TaskStore.swift:352-355), so the bad pair pre-existed.
- Frequency: seen **once** (not yet reproduced deterministically) → points to a rare data
  configuration, not "every reorder fails."

## Reproduction
Not deterministically reproduced. Known steps: drag the last (or near-last) row up one slot
in the personalized (manual-position) sort. The two rows it lands between already have
`position` values that are equal or inverted (`after.position >= before.position`).

## Scope
- Data: **disposable** (test data — a wipe/reset is acceptable to unblock; no recovery
  migration required as a primary goal).
- Surface: the iOS `TasksView`/`TasksScreen`. The same guard exists in
  `SmartFilterStore.reorder` (field `"reorder"`), so saved-filter reordering shares the risk.

## Prior Investigation
None by the user. Inline code scout by orchestrator established the mechanism below.

## Key Observations (from inline scout)
1. **Only emitter of this exact error:** `TaskStore.reorder(id:after:before:)`
   (`Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:316-323`). The
   `anchorsAreOutOfOrder(after:before:)` guard returns true when `after >= before`
   (`Ordering/FractionalPosition.swift:36-39`). It validates the **existing** positions of
   the two neighbor rows — so it detects pre-existing bad data, it does not create it.
2. **Guard precedes self-heal:** the guard throws (line 316) *before* the
   `needsCompaction` → `recompactSiblings` block (line 338-343). Recompaction
   (`PositionCompactor.recompact`, `Ordering/PositionCompactor.swift:9-11`) assigns
   `1,2,3,…` by sorted order and *would* repair equal/inverted anchors — but it never runs
   on this path. **Resilience defect R1.**
3. **Write failure rendered as load failure:** `TasksView.applyDrop` (Apps/Lillist-iOS/
   Sources/Tasks/TasksView.swift:284-286) sets `loadError = "\(error)"` on a failed reorder;
   `loadError` drives the "Could not load tasks" surface in `LillistUI.TasksScreen`. So a
   reorder (write) error is shown as a load error, with the raw `validationFailed(...)`
   description. **UX defect R2.** Load itself (`reload()` → `smartFilterStore.evaluate`)
   does NOT validate anchors, so a relaunch reload clears the error — the user's
   "stuck on every launch" is most likely "fails every time I retry that drag" (the bad
   pair persists), not a literal load-time validation.
4. **Tail-collision lead:** `create` appends via `nextPosition = max(position) + 1.0`
   (TaskStore.swift:138, 685-696) — a **non-atomic tail allocation**. Writers through this
   path: in-app create, Quick Capture, App Intents, the **Share Extension (separate process,
   shared App-Group store)**, and CloudKit-synced creates from other devices. Concurrent /
   merged tail appends can land **two siblings at an equal `position` at the bottom** —
   exactly where "move a bottom row up" drops. Strong fit for the symptom.

## Leading Hypotheses (to be evidenced + adversarially verified)
- **H-A (tail allocation race):** non-atomic `nextPosition` + concurrent writers
  (Share Extension / Quick Capture / App Intents) produce equal tail positions.
- **H-B (CloudKit merge):** `NSPersistentCloudKitContainer` last-writer-wins per-attribute
  merge of `position` across devices yields equal/inverted siblings.
- **H-C (float underflow):** repeated bisection in a region collapses a midpoint onto a
  neighbor; check whether the `after.ulp * 4` `gapIsTooSmall` threshold actually prevents it.
- **H-D (compaction/recompaction defect):** `recompactSiblings`/`PositionCompactor` or its
  trigger ordering leaves ties — *initial read suggests the compactor is correct*; verify.
- **R1/R2/R3 (resilience):** guard-before-heal; write-error-as-load-error; no load-time
  integrity normalization. These hold regardless of which data origin is confirmed.

## Relevant Code Areas
- `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift` — anchor math + guard.
- `Packages/LillistCore/Sources/LillistCore/Ordering/PositionCompactor.swift` — recompaction.
- `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` — `create` (115),
  `reorder` (302), `reparent` (271), `nextPosition` (685), `recompactSiblings` (705).
- `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift` — parallel reorder (260+).
- `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift` — `applyDrop` error surfacing (272-287).
- `Packages/LillistUI/.../iOS/Screens/TasksScreen.swift` — "Could not load tasks" surface.
- `Extensions/ShareExtension-iOS/ShareRootView.swift:103` — cross-process writer.
- Persistence/CloudKit container config (to confirm concurrency model + merge policy).
- Tests: `Tests/LillistCoreTests/Ordering/{FractionalPositionTests,PositionCompactorTests}.swift`,
  `Tests/LillistCoreTests/Stores/TaskStoreOrderingTests.swift`.
