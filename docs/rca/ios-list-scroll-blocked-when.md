# iOS task list scroll blocked when the touch starts on row content

- **Date**: 2026-07-14
- **Severity/Impact**: High — vertical touch scrolling of the iOS tasks `List`, a core
  interaction, was dead for every drag starting on row content (all rows, deterministic,
  0.0 pt movement). Only the thin gesture-free margins scrolled. No crash or data loss;
  macOS (wheel/trackpad input) unaffected. Latent in shipped test builds from 2026-06-17
  until reported 2026-07-14 (issue #12).
- **Status**: Fixed in fix commit on branch `fix/12-list-scroll-blocked` (PR pending merge; see issue #12)

## Summary

Touches beginning on task-row content were silently claimed by the row's bespoke SwiftUI
gestures, so the List's UIScrollView pan never began and the list moved 0.0 pt. Toggle
experiments proved an OR-shaped root cause: the reorder long-press+drag and the swipe-reveal
drag were *each independently sufficient* to kill scrolling, because the code's arbitration
model wrongly assumed failed or yielding SwiftUI recognizers release the touch stream. The
fix (council-decided, 3/3) moves both gestures onto UIKit recognizers — the only layer with
a documented arbitration contract — and lands a five-interaction real-touch test matrix so
no single row gesture can again be validated in isolation. Lesson in one line: on this OS,
a SwiftUI drag-family gesture on List row content owns the touch from touch-down, and only
UIKit lets you decline it.

## Timeline

- **`94eb682b` / `de5769a7` 2026-05-26** — Custom reorder composition authored
  (`LongPress(0.3 s/4 pt).sequenced(before: DragGesture(minimumDistance: 0))` via
  `.gesture()`) and wired live, replacing native `List.onMove`. The scroll-blocking
  property is present but **latent**.
- **`9fbfe46a` 2026-06-17 06:14** — Label becomes a `Button`; its intrinsic recognizer
  starves the sequenced composition. Scroll works, reorder is dead.
- **`4c36bcf9` 2026-06-17 12:20** — The `Button` is removed to restore reorder
  (label = `contentShape` + `onTapGesture` + `dragReorderGesture`). **Regression onset,
  boundary-proven**: parent `3c9e5b19` passes the repro 3/3; this commit fails identically
  to HEAD (0.0 pt).
- **`7468db0a` 2026-06-17 16:35** — `SwipeableRow` replaces `.swipeActions` with a
  card-wide `.simultaneousGesture(DragGesture(minimumDistance: 10))` — the **second,
  independent blocker** is born.
- **2026-07-14** — Reported as issue #12 → RCA: deterministic automated repro
  (`ListScrollUITests`, failure rate 1.0), boundary check, toggle-lattice diagnosis →
  `/council-vote` on fix strategy → UIKit-bridge fix implemented on
  `fix/12-list-scroll-blocked`.

## Root cause & trigger

**Chain (verified per link):**

- **Defect** — two SwiftUI drag-family gestures on row content, plus the arbitration
  assumptions written around them: the reorder composition
  (`DragReorderable.swift:70-125`, attached via `.gesture()` at `TasksScreen.swift:353`)
  and the swipe drag (`SwipeableRow.swift:131`,
  `.simultaneousGesture(DragGesture(minimumDistance: 10))`).
- **Infection** — for touches starting on row content, the List's scroll pan never begins;
  the claimed touches are silently discarded (no diagnostic path exists for a
  claimed-but-never-begun touch).
- **Failure** — row-content vertical drags move the list 0.0 pt; margin drags scroll fine
  (the repro's passing control arm).

**Evidence:** the boundary check proved the reorder gesture sufficient alone
(`4c36bcf9` fails with `SwipeableRow` not yet existing); exp-1 Leg B proved the swipe
gesture sufficient alone (reorder removed → still red); exp-2's lattice closed the shape
(swipe-only removed → red; both removed with tap/contentShape/a11y intact → green; both
restored → red). **OR-shape: fixing either gesture alone could not fix the symptom.**

The diagnosis falsified three arbitration assumptions the code and notes had recorded as
law: (1) "the long-press gate disambiguates from scroll" — a *failed* long-press does not
hand the touch back; (2) "a `simultaneousGesture` never starves the scroll" — it does;
(3) "returning early for vertical drags yields them" — an `onChanged` handler cannot
un-claim a touch; arbitration settles before it runs.

**ODC classification:** Interface / Incorrect — a wrong interaction contract at the
SwiftUI↔UIKit scroll-arbitration boundary. **Trigger:** workload / basic interaction
(plain scrolling).

## Contributing factors

- **`4c36bcf9` was an exposer, not the authoring of new defective logic** — it removed the
  `Button` whose recognizer had starved the latent 2026-05-26 composition; its
  `DragReorderable.swift` diff was comment-only.
- **No test at any layer exercised real gesture arbitration.** State-machine, pure-math,
  and snapshot suites all existed; none drove recognition. No real-touch test drove
  long-press reorder at all.
- **Every documented arbitration lesson was gesture-vs-gesture** (2026-06-12, 06-17 ×2,
  06-18); gesture-vs-scroll-pan rested on a single unverified code comment.
- **Silent-by-design touch discard** — the gesture pipeline emits no diagnostic for a
  claimed touch that never reaches `beginDrag`, so the failure produced zero signal even
  with diagnostics logging on.
- **Three-regression ping-pong** (status-tap 06-12, dead reorder 06-17, scroll now): each
  gesture change was validated only against the interaction being fixed, so restoring one
  interaction could silently break another.

## The fix

Council decision (3/3 IRV, `.council/fix-strategy-issue-12-list-scroll/DECISION.md`):
**C1 — bridge both gestures to UIKit recognizers** via `UIGestureRecognizerRepresentable`,
the only layer with a documented arbitration contract with the scroll pan:

- NEW `ReorderLongPressGesture` (wraps `UILongPressGestureRecognizer`, 0.3 s/4 pt tokens):
  early movement fails the press and the scroll pan takes the touch; a matured press owns
  it exclusively.
- NEW `HorizontalSwipePanGesture` (wraps `UIPanGestureRecognizer`):
  `gestureRecognizerShouldBegin` *declines* non-horizontal touches (|dx| > |dy|, ties →
  scroll), so vertical drags are never claimed at all.
- NEW `SwipePanProjection`: pure, unit-tested deceleration projection replacing
  `predictedEndTranslation` (UIKit pans expose velocity, not a prediction).
- FROZEN: `DragController`, `SwipeSettleArbiter`, all consumers, and the macOS SwiftUI
  branches (byte-identical).

The diagnosis verdict was **REDESIGN of the gesture-arbitration seam, scope-bounded**: the
module was a 3× repeat offender, and no narrower patch existed — the OR-shape means both
gestures must change, the empirically refuted families (`.simultaneousGesture`
re-attachment, raising `minimumDistance`, in-handler axis yield — SwipeableRow embodied
all three and blocked anyway) are dead on arrival, and removal is a feature regression.

**Tech debt logged with the fix:** macOS retains the falsified SwiftUI arbitration
assumptions (known-untested, revisit on any macOS gesture/scroll defect — issue #18); the
bridged recognizers anchor translation in window space, which breaks if edge auto-scroll is
ever built (issue #19).

**Post-review hardening (same PR):** the merge review surfaced and the branch fixed four
further correctness gaps in the bridges — system-cancelled touches (`.cancelled`) now abort
instead of committing (reorder → `cancelDrag()`, swipe → close, never a full-swipe commit);
`beginDrag` retries per event again so a press maturing during the previous drop's settle
window isn't a dead touch; onChanged/onEnded carry session-ownership guards so a second
finger can't steer another row's drag; and reorder translation tracks the first touch, not
the multi-touch centroid.

## Preventative action — killing the class

The defect class is "a row-gesture change validated only against its own interaction."
Its guard is the **five-interaction real-touch matrix**, landed in the same change as the
fix: `ListScrollUITests` (the red→green witness), `LongPressReorderUITests` (**first-ever
real-touch reorder coverage** — positive reorder + persistence, sub-gate drag does not
reorder, Due-sort drag does not corrupt personalized order), `TaskTapOpenUITests`,
`SwipeDeleteUITests`, and `StatusCycleUITests`. **Rule: any change to row gestures keeps
the whole matrix green, not just its own test.** The falsified arbitration assumptions are
recorded in `docs/engineering-notes.md` (2026-07-14, issue #12 entry) so they cannot be
re-adopted from the old comments.

## Lessons

- A SwiftUI drag-family gesture attached to `List` row content claims the touch stream at
  touch-down and never releases it to the scroll pan — regardless of attachment mode
  (`.gesture` vs `.simultaneousGesture`), `minimumDistance`, or handler-level yields.
- UIKit is the only layer with a documented gesture-arbitration contract; declining a
  touch (`gestureRecognizerShouldBegin`) is only possible there.
- In the iOS 26.2 SDK, `UIGestureRecognizerRepresentable` does **not** refine `Gesture` —
  it attaches through a dedicated `View.gesture(_:)` overload, so it cannot flow through a
  shared `some Gesture` property (hence the `#if os(iOS)` fork in the modifier body).
- The simulator reproduced this defect exactly as reported on device — the blanket
  sim-fidelity caveat in the engineering notes does not apply to this class.
