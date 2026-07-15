# HANDOFF — issue #18 (macOS row gestures: unverified SwiftUI arbitration model)

**State:** harness authored and **compiling** (`xcodebuild build-for-testing` green);
DRY consolidation done and unit-verified; PR open (link on issue #18). This session ran
in a linked worktree, so per policy it stops after the PR — the behavioral verdict run,
merge, versioning, and deploy happen from `main` / on Mikey's Mac.

## The reframe

#18 is tech debt, **not a live defect** and never reopened. PR #17 bridged the *iOS* row
gestures to UIKit recognizers but froze the macOS `#else` branches on the SwiftUI
arbitration model iOS's #12 RCA falsified. Key finding: macOS's event model makes the iOS
root cause **structurally impossible** — scrolling is scroll-wheel/trackpad input routed to
`NSScrollView`, while a `DragGesture` fires only on mouse-button-down + move (different
event streams that never compete). So the debt was *unverified + unguarded*, not broken.
Resolution chosen (with Mikey): **verify-first**, not a speculative AppKit bridge.

## What landed (this branch)

- **macOS real-input gesture harness** in `Lillist-macOSUITests` — the regression guard the
  macOS branch never had: `MacListScrollUITests` (scroll-wheel from row body scrolls the
  list — the macOS #12 analogue), `MacReorderUITests` (vertical click-drag reorders +
  persists; horizontal doesn't), `MacSwipeUITests` (horizontal reveals Delete + deletes +
  persists; vertical doesn't reveal), `MacRowTapOpenUITests` (click opens the right task).
- **`MacUITestHelpers`** extended with gesture-harness launches, element-agnostic row
  location, stable-order reads, and a macOS drag/scroll driver.
- **`--ui-test-seed-many` + `--ui-test-seed-count <N>`** launch seam in the macOS `LillistApp`.
- **DRY consolidation:** `SwipeableRow`'s macOS branch now derives its axis from the shared
  `DragAxisArbiter` at a new `macSwipeAxisCommitDistance` (10) token — proven
  behavior-preserving by an exhaustive grid test in `DragAxisArbiterTests` (host-runnable).
- Docs: `DragReorderable`/`SwipeableRow` headers, the RCA `#18 update` note, an
  engineering-notes entry, this handoff.

## Verified here (agent-runnable)

- macOS `build-for-testing` **SUCCEEDED** (app + `Lillist-macOSUITests` + LillistUI compile,
  warnings-as-errors); iOS `build` **SUCCEEDED** (shared change is macOS-only).
- `swift test` LillistUI (skip Snapshot/Tour) green incl. the new `DragAxisArbiterTests`
  equivalence grid; LillistCore untouched (full run for hygiene).

## Remaining steps (Mikey, on-device / from `main`)

1. **Gate 4 — run the harness on a signed Mac with a live window server** (physical console,
   not headless SSH): the XCUITest runner cannot initialize over SSH
   (`LAError -4 "System authentication is running"`), so it did not execute here.
   ```
   xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
     -destination 'platform=macOS' -only-testing:Lillist-macOSUITests
   ```
   - **Green (expected):** the debt is discharged by verification — the harness is the
     standing guard. Merge the PR (closes #18). Consider tightening the header wording from
     "guarded by" to "verified by".
   - **Red:** a genuine macOS gesture defect — the trigger has fired for real. *Then* bridge
     the affected macOS branch to `NSGestureRecognizerRepresentable` (macOS 15+) mirroring
     the iOS bridge, red→green. (Design only if needed.)
2. **Merge the PR** (merge commit; verify; delete branch).
3. Optionally `/atlas update` (mapped LillistUI sources changed: SwipeableRow, Tokens).

## Related issues still open

- **#19** — bridged reorder's window-space translation anchor assumes no mid-drag list
  movement; redesign before edge auto-scroll is built. (Untouched here.)
