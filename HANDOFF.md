# HANDOFF — issue #12 fix (list scroll blocked by row gestures)

**State:** fix complete and verified on branch `fix/12-list-scroll-blocked`; PR open
(link on issue #12). This session ran in a linked worktree, so per policy it stops
after the PR — merge, versioning, and deploy happen from `main`.

## What landed

- **Root cause (RCA `ios-list-scroll-blocked-when`, HIGH confidence, toggle-proven):**
  BOTH row gestures — the reorder `LongPress.sequenced(DragGesture(min 0))` via
  `.gesture()` on the label and `SwipeableRow`'s `.simultaneousGesture(DragGesture(min 10))`
  on the card — each independently starved the List's scroll pan (OR-shape). SwiftUI
  drag-family gestures on List row content claim touches at touch-down and never
  release them, regardless of attachment mode / minimumDistance / handler yields.
- **Fix (council-decided C1):** both gestures bridged to UIKit recognizers via
  `UIGestureRecognizerRepresentable` — `ReorderLongPressGesture` (long-press loses to
  the pan on early movement, owns the touch once matured) and
  `HorizontalSwipePanGesture` (`shouldBegin` declines non-horizontal touches) +
  `SwipePanProjection` (unit-tested deceleration prediction). `DragController`,
  `SwipeSettleArbiter`, and all macOS branches frozen.
- **Five-interaction real-touch matrix** now guards the module: `ListScrollUITests`
  (the #12 witness), `LongPressReorderUITests` (first-ever real-touch reorder tests),
  `TaskTapOpenUITests`, plus existing `SwipeDeleteUITests` / `StatusCycleUITests`.
- Engineering-notes entry appended (2026-07-14, gesture-vs-scroll arbitration lesson).

## Remaining steps (for Mikey, from `main`)

1. **Merge the PR** (merge commit; verify merge; delete branch).
2. **Gate 4 — on-device acceptance pass** after the next `/deployit deploy` from
   `main`: scroll from row body (flick + slow), long-press reorder incl. horizontal
   depth targeting, swipe reveal both edges (reveal-only Delete), tap-to-open,
   status tap/menu, chevron, no scroll during an active reorder.
3. Optionally run `/atlas update` (mapped LillistUI sources changed).

## Known issues filed, not fixed here

- **#15** — pre-existing `StatusCycleUITests.test_statusTap_cycles_and_persists`
  failure (Closed-state indicator 9.7×9.3pt AX frame never hittable for the terminal
  no-op tap; proven present without this fix).
- **#16** — tag + saved-filter management UI (carried forward from the prior
  macOS-single-column handoff; was tracked only in this file until now).
- Tech-debt (logged in `.rca/ios-list-scroll-blocked-when/REMEDIATION.md`): macOS
  keeps the falsified SwiftUI arbitration assumptions (untested there; wheel/trackpad
  input differs); the bridged reorder's window-space anchor assumes no mid-drag list
  movement — revisit if edge auto-scroll is ever built.

## Artifacts

RCA: `.rca/ios-list-scroll-blocked-when/` (GRID → REPRO → ORIGIN → EVIDENCE →
HYPOTHESES/experiments → CHALLENGE → DIAGNOSIS → REPORT/REMEDIATION → FIX →
POSTMORTEM). Council: `.council/fix-strategy-issue-12-list-scroll/DECISION.md`
(3/3 IRV for C1 + QA rider). Storyhook: LIL-5. Both are gitignored plugin dirs;
the durable record is the issue-#12 comment thread + the PR.
