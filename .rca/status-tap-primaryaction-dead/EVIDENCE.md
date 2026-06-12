# Evidence Report

## Git History Findings
- Deploy boundaries (`chore(deploy): bump iOS build number`): 26=09689bf
  (05-26 23:11), 36=b4b2541 (05-27 22:46), 37=fad6ef5, 38=8a4b33f (05-28),
  39=b01025f (06-06), 40=5cfbad3 (06-11).
- **Nothing in builds 36→40 touched the tap path**: StatusIndicatorView (one
  a11y-string bundle pin, 1640e6a), TaskRowView (a11y/loc only, ccab595 +
  5895517), TasksScreen rows (only the reorder toast overlay, 0dbafef —
  hit-test inert when hidden), TaskStore.transition (unchanged), StatusCycler
  (untouched since creation 05-14).
- The suspect structures all shipped **inside build 26**:
  - 62c10d1 (05-16): StatusIndicatorView → `Menu(primaryAction:)` (Plan 18,
    replacing the flaky Button+simultaneousGesture).
  - ed6a056 (05-25): single Tasks view; rows wrapped in `NavigationLink(value:)`.
  - d909e75/5d6bdd0 (05-26): DragController; `.dragReorderable` = LongPress
    `.sequenced(before: DragGesture(minimumDistance: 0))` via `.gesture` on the
    ENTIRE row.

## Architecture Findings
- Tap chain: StatusIndicatorView `Menu(primaryAction:)` → onClick →
  TaskOutlineRowView → TasksScreen closures → TasksView.cycle →
  StatusCycler.nextOnClick → TaskStore.transition → reload.
- All errors swallowed: `try?` in cycle/setStatus; `transition` silently
  no-ops on equal status; no `task.transition` diagnostic event (create/
  reorder/reparent had emits; transition did not).
- A11y tree (XCUITest dump): the whole row collapsed to ONE flat Button
  (`NavigationLink` label + `.accessibilityElement(children: .combine)`);
  the status control was not an addressable element.
- macOS TaskListView: TaskRowView directly in List (no NavigationLink);
  drag = `DragGesture(minimumDistance: 4)`.

## Code Evidence
- StatusCycler has no fixed point — every tap requests a real change, so a
  firing onClick would always visibly change status (menu path proves the
  write works). ⇒ onClick was never firing.

## Runtime Evidence (simulator falsification harness)
- V0 baseline: calibration arm (long-press → menu → Blocked) PASSES; tap arm
  FAILS — reproduces the device symptom exactly.
- Incidental find #1: fresh-store launch crash in
  `normalizeSiblingsIfDegenerate` (`for i in 1..<sorted.count` on an empty
  set) — fixed first (1d1f285); see commit message.
- Incidental find #2: the plain task list does not reload after an in-session
  Quick Capture (existing QuickCaptureFlowUITests works around it via
  filter-search). Not pursued; noted for follow-up.
- Incidental find #3 (sim-only): row-title tap does not push detail under
  XCUITest on iOS 26.2 sim even with ALL gestures removed (row highlights,
  no push); works on device. Environmental; documented in StatusCycleUITests.

## Key Facts
1. Menu-set path works; quick-tap path dead ⇒ failure is exactly
   `primaryAction → onClick`.
2. No code in the 36→40 window touched that path ⇒ regression entered with
   build 26's structures.
3. Both candidate structures (NavigationLink wrap, row drag gesture) shipped
   in the same build ⇒ runtime falsification required.
