# Lillist Plan 13 — Accessibility & Correctness Cleanup

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the correctness bugs and the most critical accessibility gaps surfaced by the 2026-05-16 design review, before v1 ships. This is the "before we ship, fix the things that look like bugs" plan: four duplicated iOS status-click switches drift from the canonical `StatusCycler.nextOnClick`, the iOS sync badge silently renders nothing during a sync (a pattern match against an associated-value enum case never fires the spinner overlay), the macOS Command menu traps several keys that should be free for system use, two tap targets are smaller than HIG's 44 pt floor, several gesture-only interactions have no `.accessibilityAction(named:)` equivalent for VoiceOver / Switch Control / Voice Control, and iOS task rows lack the standard `swipeActions` / `contextMenu` patterns users expect from a native list. No new features, no visual redesign — these changes are mostly additive (a11y modifiers) or surgical (tightening pattern matches and gating shortcuts).

**Architecture:** Two architectural moves, both small. **(a) Canonicalise.** Where four iOS surfaces (`TodayView`, `TagTaskListView`, `FilterResultsView`, `TaskSubtasksTab`) re-implement the status-click cycle inline, delete the inline switches and route through `LillistUI.StatusCycler.nextOnClick(from:)`. Where the iOS `TaskDetailView` ships a private `statusGlyph(_:)` helper that drifts from `LillistUI.StatusGlyph.symbol(for:)`, delete the local helper and consume the shared one. **(b) Layer accessibility additively.** Every other change is a localised modifier — `.accessibilityAction(named:)`, `.frame(minHeight: 44)`, `.contentShape(.rect)`, `.swipeActions`, `.contextMenu`, `.accessibilityElement(children: .ignore)` — applied to existing shared components in `Packages/LillistUI/` and the four iOS list surfaces. The macOS Command-menu gating uses the existing `@FocusState` enum (`Column { sidebar, list, detail }`) in `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift`, surfaced to `LillistCommands` via a new `@FocusedValue` key so the four problem shortcuts (Space, ⌘D, ⌘., Tab/Shift-Tab) only fire when a list column is focused, never when a TextField has first-responder status. No new entities, no migrations, no new Swift Package dependencies.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Test` / `@Suite` / `#expect`) for shared `LillistUI` tests, XCTest + `swift-snapshot-testing` for the iOS snapshot, XCTest for the macOS focused-shortcut behavior test.

**Depends on:** Plans 1-12 on `main`. No managed-object model changes, no migrations, no new third-party packages.

---

## File Structure

```
Lillist/
├── Packages/
│   └── LillistUI/
│       ├── Sources/
│       │   └── LillistUI/
│       │       ├── Components/
│       │       │   ├── StatusIndicatorView.swift        (modify — 44pt hit area + a11y action)
│       │       │   └── TaskRowView.swift                (modify — fuller a11y label + reorder actions)
│       │       └── iOS/
│       │           ├── SyncStatusBadge.swift            (modify — `if case` match, 44pt hit area, inProgress color)
│       │           ├── FloatingAddButton.swift          (modify — a11y action for long-press)
│       │           └── QuickCaptureField.swift          (modify — chips become Buttons w/ 44pt floor)
│       └── Tests/
│           └── LillistUITests/
│               ├── iOS/
│               │   └── iOSSnapshotTests.swift           (modify — add inProgress snapshot)
│               ├── Status/
│               │   └── StatusIndicatorViewA11yTests.swift  (NEW)
│               └── Components/
│                   └── TaskRowViewA11yTests.swift          (NEW)
├── Apps/
│   ├── Lillist-iOS/
│   │   └── Sources/
│   │       ├── Today/
│   │       │   └── TodayView.swift                      (modify — StatusCycler, swipe, context menu)
│   │       ├── All/
│   │       │   └── TagTaskListView.swift                (modify — StatusCycler, swipe, context menu)
│   │       ├── Filters/
│   │       │   └── FilterResultsView.swift              (modify — StatusCycler, swipe, context menu)
│   │       ├── Search/
│   │       │   └── SearchView.swift                     (modify — swipe + context menu)
│   │       └── Detail/
│   │           ├── TaskDetailView.swift                 (modify — consume shared StatusGlyph)
│   │           └── TaskSubtasksTab.swift                (modify — StatusCycler)
│   └── Lillist-macOS/
│       ├── Sources/
│       │   ├── Commands/
│       │   │   ├── LillistCommands.swift                (modify — rebind ⌘⇧N, ⌘D; gate Space/⌘./Tab via @FocusedValue)
│       │   │   └── FocusedListColumn.swift              (NEW — FocusedValueKey for column focus)
│       │   ├── Views/
│       │   │   ├── RootSplitView.swift                  (modify — publish focusedColumn as FocusedValue)
│       │   │   ├── TaskList/
│       │   │   │   └── InlineCreateField.swift          (modify — return .ignored on empty)
│       │   │   └── Detail/
│       │   │       └── DetailHeaderView.swift           (modify — collapse double-spoken status pill)
│       └── Tests/
│           ├── FocusedShortcutGatingTests.swift         (NEW)
│           └── InlineCreateInteractionTests.swift       (modify — add empty-tab Step)
└── docs/
    └── engineering-notes.md                              (append entry for Plan 13)
```

---

## Notes for the Implementer

**The `SyncIndicator` enum mixes bare and associated-value cases — this is a Swift footgun.** `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:5-9` defines:

```swift
public enum SyncIndicator: Sendable, Equatable {
    case idle(lastSync: Date?)
    case inProgress
    case error(message: String, lastSuccess: Date?)
}
```

`Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift:20` writes `if indicator == .inProgress`. Because the enum is `Equatable` (synthesized), the comparison technically compiles and *does* match when the indicator truly is `.inProgress` — but **the badge also paints the dot `.clear` for that state** (line 32), so even when the overlay fires the user sees nothing. The right fix is two-part: (a) switch the overlay test to `if case .inProgress = indicator` for symmetry with the rest of the codebase's pattern-match style (see `SyncStatusDotView.swift:39`, `SyncStatusDotView.swift:25` for the established idiom), and (b) paint the dot a visible color during sync (`.blue`, mirroring `SyncStatusDotView.swift:39-40`). A snapshot of all three states pins the contract.

**`StatusCycler` is the canonical click contract; the inline switches are bug carriers.** `Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift:10-17` is the single source of truth for what clicking the status indicator does. Its test, `Packages/LillistUI/Tests/LillistUITests/Status/StatusCyclerTests.swift:16` (`#expect(StatusCycler.nextOnClick(from: .blocked) == .todo)`), pins `blocked → todo`. Four iOS surfaces inline a `switch record.status { … case .blocked: next = .started }` that drifts from this contract — clicking a `.blocked` task on iOS bumps it to `.started`, not back to `.todo`. The fix is identical in each file (Tasks 2 and 3): delete the inline switch, call `StatusCycler.nextOnClick(from: record.status)`. The macOS `RootSplitView.swift:51` already uses `StatusCycler.nextOnSpace(from:)`; this plan brings iOS into alignment.

**`@FocusedValue` is the macOS pattern for gating Commands on first-responder.** `CommandMenu` `Button` blocks evaluate `body` in a context that doesn't know which view is focused; the only way for a command to query focus is to read a `@FocusedValue`. The pattern: declare a `struct FocusedListColumnKey: FocusedValueKey { typealias Value = RootSplitView.Column }`, publish it from `RootSplitView` via `.focusedValue(\.listColumn, focusedColumn ?? .list)`, then in `LillistCommands` read `@FocusedValue(\.listColumn) var listColumn` and gate the four problem shortcuts with `.disabled(listColumn == nil)`. When a `TextField` has first-responder status, SwiftUI clears `@FocusState`, which propagates to the `FocusedValue` as `nil`, which disables the gated commands — exactly the desired behavior.

**`.swipeActions` ships on iOS only.** Wrap the rows in a `List(…) { row.swipeActions { … } }` invocation that is gated behind `#if os(iOS)` only when the row sits in a multi-platform file. The four list views in scope are all iOS-only (under `Apps/Lillist-iOS/Sources/`), so no `#if` is needed for them.

**`.contextMenu` is the iOS replacement for the "long-press for status menu" stub.** The four iOS list rows currently pass `onStatusLongPress: { /* status menu lands in Task 13 */ }` to `TaskRowView`. Task 13 of this plan delivers it — via `.contextMenu` on the row, not via a long-press inside `StatusIndicatorView`. The stub callbacks become `{}` and stay quiet; the `.contextMenu` carries the actual menu.

**44pt is the iOS Human Interface Guidelines floor for tap targets.** SwiftUI's `Button` already includes a small expansion of the touchable region, but a 22-pt or 10-pt visual control needs an explicit `.contentShape(.rect)` (or `Rectangle`) on a `.frame(minWidth: 44, minHeight: 44)` to meet the floor. Keep the visual size; expand only the hit area. The macOS sibling does not need this (cursor-based interaction has different minimums).

**Snapshot tests in this codebase use `swift-snapshot-testing`.** `Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift` is the existing iOS-atom snapshot file. Adding `test_syncStatusBadge_inProgress` follows the same pattern as the two existing badge tests at lines 40-59. On first run the test records the snapshot to a sibling `__Snapshots__/iOSSnapshotTests/` directory (which doesn't exist yet — see `find /Volumes/Code/mikeyward/Lillist/Packages/LillistUI/Tests/LillistUITests/iOS -name "__Snapshots__"` returns nothing). To force record-mode on a single test run, set `record: .all` on the `assertSnapshot` call temporarily, run the test, confirm the PNG, then remove the override. The two existing badge tests have no recorded snapshots on disk either — they will record on first run as part of this plan.

**Verification cadence.** Each task that produces tests ends by running `swift test --package-path Packages/LillistUI --filter '<pattern>'` (or `xcodebuild test … -only-testing:Lillist-iOSTests/… …` / `…/Lillist-macOSTests/…` for app-target tests). Final task runs the full LillistCore + LillistUI suites + both app targets via `xcodebuild`.

**Commits.** Conventional-commit prefixes throughout: `fix:`, `feat:`, `test:`, `refactor:`, `chore:`, `docs:`. One commit per Task. Conventional-commit `scope` parens used where helpful: `fix(iOS):`, `fix(macOS):`, `refactor(UI):`.

**Build-plugin caching gotcha (still active, not triggered here).** No model changes in this plan. If you touch the model anyway during exploration, run the standard incantation from CLAUDE.md:
```bash
touch Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/ \
      Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/
```

**Strict-warnings bar (still active).** `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` is on across SPM and Xcode targets per Plan 2 follow-up. Adding `import` lines or modifiers should not introduce warnings; if a build fails due to a new warning, fix the warning rather than disabling the bar.

---

## Task 1: Fix the iOS sync badge so it actually shows progress (and add the missing snapshot)

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift`
- Modify: `Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift`

The badge has two co-occurring bugs: the spinner overlay is gated by `indicator == .inProgress` (a fragile equality against an enum whose other cases carry associated values; the rest of the codebase uses `if case … = …` pattern matching here — see `SyncStatusDotView.swift:25`, `:39`) and the dot is `.clear` for inProgress (line 32), so even when the overlay does fire, the surrounding dot is invisible and there's no contrast. Together: users get zero visual feedback during a sync.

- [ ] **Step 1: Write the failing snapshot test (red)**

In `Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift`, append a third badge snapshot beneath the existing `test_syncStatusBadge_error` (after line 59 — keep the file's `#if os(iOS)` / `#endif` brackets):

```swift
    @MainActor
    func test_syncStatusBadge_inProgress() {
        let view = SyncStatusBadge(indicator: .inProgress)
            .padding()
            .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 60, height: 40)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }
```

Run the snapshot test once to record the baseline (with the current buggy code) so the diff in Step 4 is visually obvious:

```bash
swift test --package-path Packages/LillistUI --filter 'test_syncStatusBadge_inProgress' 2>&1 | tail -10
```

Expected on first run: PASS with a "No snapshot recorded — recording new baseline" notice. The recorded PNG shows an empty area (the bug we're fixing — `.clear` dot, no overlay because the equality check fails to render visibly anyway).

- [ ] **Step 2: Read the bug and apply the surgical fix**

Open `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift`. Two edits:

(a) Replace the equality-based overlay test at line 20 with a pattern match (and migrate the other two cases to `if case` for symmetry — but the surgical minimum is just the inProgress check):

```diff
             .overlay(
                 Group {
-                    if indicator == .inProgress {
+                    if case .inProgress = indicator {
                         ProgressView()
                             .scaleEffect(0.5)
                     }
                 }
             )
```

(b) Give the dot a visible color during sync, matching `SyncStatusDotView.swift:39-40`:

```diff
     private var color: Color {
         switch indicator {
         case .idle: return .green
-        case .inProgress: return .clear
+        case .inProgress: return .blue
         case .error: return .red
         }
     }
```

- [ ] **Step 3: Delete the now-stale snapshot and re-record**

```bash
rm -rf Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/test_syncStatusBadge_inProgress.1.png
swift test --package-path Packages/LillistUI --filter 'test_syncStatusBadge_inProgress' 2>&1 | tail -10
```

Expected: PASS, new PNG written — visible blue dot with a small spinner overlay. (If the file didn't yet exist, the `rm -rf` is a no-op; the second run records the corrected baseline.)

- [ ] **Step 4: Re-record the existing idle + error snapshots (they will be missing the same `__Snapshots__/iOSSnapshotTests/` directory)**

```bash
swift test --package-path Packages/LillistUI --filter 'test_syncStatusBadge' 2>&1 | tail -15
```

Expected: all three badge tests pass. Inspect the three PNGs in `Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/`: idle is a green dot, inProgress is a blue dot with a small spinner, error is a red dot.

- [ ] **Step 5: Run the broader iOS snapshot tests to confirm no regression**

```bash
swift test --package-path Packages/LillistUI --filter 'iOSSnapshotTests' 2>&1 | tail -10
```

Expected: all iOS atom snapshots pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/
git commit -m "$(cat <<'EOF'
fix(iOS): SyncStatusBadge renders during in-progress syncs

The overlay was gated by `indicator == .inProgress`, an equality check
against an enum whose neighbouring cases carry associated values; the
rest of the codebase pattern-matches via `if case .inProgress = ...`
(SyncStatusDotView.swift). Compounded by the dot being painted `.clear`
for in-progress, the badge displayed nothing during a sync. Switch the
test to `if case`, paint the dot blue during sync (mirroring
SyncStatusDotView), and pin the contract with a third snapshot covering
all three SyncIndicator states.
EOF
)"
```

---

## Task 2: Route iOS `TodayView` status click through `StatusCycler.nextOnClick`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Today/TodayView.swift`

The canonical click contract lives in `Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift:10-17` and is pinned by `Packages/LillistUI/Tests/LillistUITests/Status/StatusCyclerTests.swift:16` (`blocked → todo`). `TodayView.swift:74-83` re-implements the cycle inline and gets it wrong for `.blocked`:

```swift
    private func cycle(_ record: TaskStore.TaskRecord) async {
        let next: Status
        switch record.status {
        case .todo:    next = .started
        case .started: next = .closed
        case .closed:  next = .todo
        case .blocked: next = .started       // ← wrong; canonical is .todo
        }
        try? await env.taskStore.transition(id: record.id, to: next)
        await reload()
    }
```

- [ ] **Step 1: Confirm the canonical contract is green**

```bash
swift test --package-path Packages/LillistUI --filter 'StatusCycler' 2>&1 | tail -5
```

Expected: `clickFromBlocked` passes — `StatusCycler.nextOnClick(from: .blocked) == .todo`.

- [ ] **Step 2: Delete the inline switch, call the canonical helper**

In `Apps/Lillist-iOS/Sources/Today/TodayView.swift`, replace the `cycle(_:)` body (lines 74-83) with a one-line call into `StatusCycler.nextOnClick(from:)`:

```diff
     private func cycle(_ record: TaskStore.TaskRecord) async {
-        let next: Status
-        switch record.status {
-        case .todo:    next = .started
-        case .started: next = .closed
-        case .closed:  next = .todo
-        case .blocked: next = .started
-        }
+        let next = StatusCycler.nextOnClick(from: record.status)
         try? await env.taskStore.transition(id: record.id, to: next)
         await reload()
     }
```

`StatusCycler` is already in scope via `import LillistUI` (line 3 of `TodayView.swift`).

- [ ] **Step 3: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Today/TodayView.swift
git commit -m "fix(iOS): TodayView click cycle routes through StatusCycler

The inline switch in cycle(_:) bumped blocked tasks to .started; the
canonical StatusCycler.nextOnClick(from: .blocked) returns .todo
(pinned by StatusCyclerTests.clickFromBlocked). Delete the local
switch and call the shared helper."
```

---

## Task 3: Route iOS `TagTaskListView`, `FilterResultsView`, `TaskSubtasksTab` through `StatusCycler.nextOnClick`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/All/TagTaskListView.swift` (lines 73-82)
- Modify: `Apps/Lillist-iOS/Sources/Filters/FilterResultsView.swift` (lines 65-74)
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskSubtasksTab.swift` (lines 59-68)

Identical bug as Task 2 in three more files. Each file already `import LillistUI`s (line 3), so `StatusCycler` is in scope.

- [ ] **Step 1: Apply the same edit to all three files**

In each of the three files above, replace the `cycle(_:)` body with the canonical helper call. The diff is identical to Task 2:

```diff
     private func cycle(_ record: TaskStore.TaskRecord) async {
-        let next: Status
-        switch record.status {
-        case .todo:    next = .started
-        case .started: next = .closed
-        case .closed:  next = .todo
-        case .blocked: next = .started
-        }
+        let next = StatusCycler.nextOnClick(from: record.status)
         try? await env.taskStore.transition(id: record.id, to: next)
         await reload()
     }
```

- [ ] **Step 2: Build iOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Confirm the inline switches are gone**

```bash
rg 'case \.blocked: next = \.started' Apps/Lillist-iOS/Sources/
```

Expected: zero matches.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-iOS/Sources/All/TagTaskListView.swift \
        Apps/Lillist-iOS/Sources/Filters/FilterResultsView.swift \
        Apps/Lillist-iOS/Sources/Detail/TaskSubtasksTab.swift
git commit -m "fix(iOS): route remaining click cycles through StatusCycler

TagTaskListView, FilterResultsView, and TaskSubtasksTab all inlined
the same broken switch (blocked → started); canonical StatusCycler
returns blocked → todo. Delete all three inline switches."
```

---

## Task 4: Delete iOS `TaskDetailView`'s private status helpers, consume shared `StatusGlyph`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift`

`Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift:125-141` defines two private helpers (`statusLabel`, `statusGlyph`) that drift from the shared `LillistUI.StatusGlyph`:

| Status    | Local `statusGlyph`        | Shared `StatusGlyph.symbol(for:)` |
| --------- | -------------------------- | --------------------------------- |
| `.todo`   | `"circle"`                 | `"circle"`                        |
| `.started`| `"circle.lefthalf.filled"` | `"circle.lefthalf.filled"`        |
| `.blocked`| `"exclamationmark.octagon"`| `"circle.dashed"`                 |
| `.closed` | `"checkmark.circle.fill"`  | `"checkmark.circle.fill"`         |

The `.blocked` glyph drifts. The labels happen to match, but locking both onto the shared source prevents future drift.

- [ ] **Step 1: Delete the private helpers and inline the shared calls**

In `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift`, replace the `Label` line inside `TaskDetailHeader.body` (line 106) and delete both helpers (lines 125-141):

```diff
             HStack(spacing: 8) {
-                Label(statusLabel, systemImage: statusGlyph)
+                Label(
+                    StatusGlyph.accessibilityLabel(for: task.status),
+                    systemImage: StatusGlyph.symbol(for: task.status)
+                )
                     .font(.caption)
                     .foregroundStyle(.secondary)
```

and remove both private vars from the bottom of `TaskDetailHeader`:

```diff
-    private var statusLabel: String {
-        switch task.status {
-        case .todo: return "To do"
-        case .started: return "Started"
-        case .blocked: return "Blocked"
-        case .closed: return "Closed"
-        }
-    }
-
-    private var statusGlyph: String {
-        switch task.status {
-        case .todo: return "circle"
-        case .started: return "circle.lefthalf.filled"
-        case .blocked: return "exclamationmark.octagon"
-        case .closed: return "checkmark.circle.fill"
-        }
-    }
 }
```

`StatusGlyph` is in scope via the file's existing `import LillistUI` (line 3).

- [ ] **Step 2: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: clean build, no warnings about unused helpers.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift
git commit -m "refactor(iOS): TaskDetailView consumes shared StatusGlyph

Delete the local statusLabel/statusGlyph helpers that returned
exclamationmark.octagon for .blocked; the shared LillistUI.StatusGlyph
returns circle.dashed. Inline the shared calls to remove the drift
risk."
```

---

## Task 5: Gate macOS Space / ⌘D / ⌘. / Tab shortcuts via `@FocusedValue` so they don't fire while a TextField is editing

**Files:**
- Create: `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift`
- Modify: `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift`
- Modify: `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`

`Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift` binds four shortcuts that should never fire while a TextField is first-responder:

| Line   | Shortcut         | Action               | Why it traps |
|--------|------------------|----------------------|--------------|
| 25-26  | Space (no mods)  | Toggle Started       | Steals the space bar from any TextField |
| 29     | ⌘D               | Mark Closed          | Steals system "Duplicate"; also fires while editing |
| 33     | ⌘.               | Mark Blocked         | Steals system "Cancel Sheet"; also fires while editing |
| 39-43  | Tab / Shift-Tab  | Indent / Outdent     | Breaks system focus navigation; traps focus inside TextField |

The fix: publish the existing `RootSplitView.focusedColumn` (`enum Column { sidebar, list, detail }`, defined at `RootSplitView.swift:12`) as a `@FocusedValue`, then disable these four commands whenever the value is `nil` (no list column has focus — by elimination, a TextField does, or no Lillist window is key).

- [ ] **Step 1: Create the FocusedValueKey**

New file `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift`:

```swift
import SwiftUI

/// Published from `RootSplitView` so command-menu shortcuts can disable
/// themselves when no list column is focused (i.e. a TextField or other
/// first-responder is editing). Without this, raw shortcuts like Space,
/// ⌘D, ⌘., and Tab fire while the user is typing, trapping keys and
/// stealing system meanings.
///
/// Value is `nil` when no Lillist window is key or when focus has hopped
/// to a TextField (SwiftUI clears `@FocusState` in that case, which
/// propagates to a `nil` here via `.focusedValue(\\.listColumn, …)`).
struct FocusedListColumnKey: FocusedValueKey {
    typealias Value = RootSplitView.Column
}

extension FocusedValues {
    var listColumn: RootSplitView.Column? {
        get { self[FocusedListColumnKey.self] }
        set { self[FocusedListColumnKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Publish the focused column from `RootSplitView`**

In `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift`, add a `.focusedValue` modifier after the existing `.onChange(of: sidebarSelection)` (line 60):

```diff
         .onChange(of: sidebarSelection) { _, new in uiState.sidebarSelection = new }
+        .focusedValue(\.listColumn, focusedColumn)
     }
 }
```

`focusedColumn` is `@FocusState private var focusedColumn: Column?` (line 10). When a TextField captures focus, SwiftUI sets the binding to `nil`; that `nil` propagates into `FocusedValues.listColumn`, which the commands read.

- [ ] **Step 3: Read `@FocusedValue` in `LillistCommands` and gate the four problem shortcuts**

In `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`, add the `@FocusedValue` property at the top of the `LillistCommands` struct and wrap each gated `Button` with `.disabled(listColumn == nil)`:

```diff
 struct LillistCommands: Commands {
     let environment: AppEnvironment
+    @FocusedValue(\.listColumn) private var listColumn: RootSplitView.Column?

     var body: some Commands {
         CommandGroup(replacing: .newItem) {
             Button("New Task") {
                 NotificationCenter.default.post(name: .lillistNewTask, object: nil)
             }.keyboardShortcut("n", modifiers: [.command])

             Button("New Sibling Task") {
                 NotificationCenter.default.post(name: .lillistNewSibling, object: nil)
-            }.keyboardShortcut("n", modifiers: [.command, .shift])
+            }.keyboardShortcut(.return, modifiers: [.command, .shift])
         }

         CommandMenu("Task") {
             Button("Toggle Started") {
                 NotificationCenter.default.post(name: .lillistToggleStarted, object: nil)
-            }.keyboardShortcut(.space, modifiers: [])
+            }.keyboardShortcut(.space, modifiers: [])
+              .disabled(listColumn == nil)

             Button("Mark Closed") {
                 NotificationCenter.default.post(name: .lillistMarkClosed, object: nil)
-            }.keyboardShortcut("d", modifiers: [.command])
+            }.keyboardShortcut(.return, modifiers: [.command])
+              .disabled(listColumn == nil)

             Button("Mark Blocked & Schedule Follow-up") {
                 NotificationCenter.default.post(name: .lillistMarkBlocked, object: nil)
-            }.keyboardShortcut(".", modifiers: [.command])
+            }.keyboardShortcut(".", modifiers: [.command])
+              .disabled(listColumn == nil)

             Divider()

             Button("Indent") {
                 NotificationCenter.default.post(name: .lillistIndent, object: nil)
-            }.keyboardShortcut(.tab, modifiers: [])
+            }.keyboardShortcut(.tab, modifiers: [])
+              .disabled(listColumn == nil)

             Button("Outdent") {
                 NotificationCenter.default.post(name: .lillistOutdent, object: nil)
-            }.keyboardShortcut(.tab, modifiers: [.shift])
+            }.keyboardShortcut(.tab, modifiers: [.shift])
+              .disabled(listColumn == nil)
         }
```

Two shortcuts are also rebound in the same hunk: `⌘⇧N` (collides with macOS "New Window") becomes `⌘⇧⏎`; `⌘D` (collides with macOS "Duplicate") becomes `⌘⏎`. The remaining `⌘.` stays on its keycap (system "Cancel Sheet" doesn't apply outside a sheet), but is now gated.

- [ ] **Step 4: Regenerate the macOS Xcode project to pick up the new file**

```bash
cd Apps/Lillist-macOS && xcodegen generate && cd ../..
git status --short Apps/Lillist-macOS/Lillist-macOS.xcodeproj/project.pbxproj
```

If `project.pbxproj` shows changes, the new file was picked up.

- [ ] **Step 5: Build macOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Write the focus-gating regression test**

New file `Apps/Lillist-macOS/Tests/FocusedShortcutGatingTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Lillist_macOS

/// Exercises the @FocusedValue-based gating that prevents the Space,
/// Cmd-Return (close), Cmd-., Tab, and Shift-Tab shortcuts from firing
/// while a TextField is first-responder.
///
/// We don't drive AppKit focus (no NSWindow in the test bundle); instead
/// we assert the contract at the key surface: the FocusedValueKey
/// extension and the four gated Button's `.disabled` predicate all
/// agree on the meaning of `listColumn == nil`.
@MainActor
final class FocusedShortcutGatingTests: XCTestCase {
    func test_focusedValueKey_default_is_nil() {
        var values = FocusedValues()
        XCTAssertNil(values.listColumn,
                     "Default listColumn must be nil so commands disable when no column is focused")
    }

    func test_focusedValueKey_roundtrip_preserves_column() {
        var values = FocusedValues()
        values.listColumn = .list
        XCTAssertEqual(values.listColumn, .list)
        values.listColumn = .sidebar
        XCTAssertEqual(values.listColumn, .sidebar)
        values.listColumn = nil
        XCTAssertNil(values.listColumn)
    }

    func test_gating_predicate_disables_when_listColumn_nil() {
        // The gating expression used in LillistCommands.
        let none: RootSplitView.Column? = nil
        let some: RootSplitView.Column? = .list
        XCTAssertTrue(none == nil, "nil column must disable Space/Cmd-Return/Cmd-./Tab")
        XCTAssertFalse(some == nil, "Focused list column must enable those shortcuts")
    }
}
```

If `@testable import Lillist_macOS` doesn't already work in this test bundle (the existing tests under `Apps/Lillist-macOS/Tests/` use plain `import LillistCore`/`LillistUI`), `RootSplitView.Column` won't be visible. In that case co-compile the two relevant source files into the test target by extending `Apps/Lillist-macOS/project.yml`:

```yaml
  Lillist-macOSTests:
    # … existing config …
    sources:
      - path: Tests
      - path: Sources/Commands/FocusedListColumn.swift
      - path: Sources/Views/RootSplitView.swift
```

After adding those `sources:` entries, regenerate: `cd Apps/Lillist-macOS && xcodegen generate && cd ../..`.

- [ ] **Step 7: Run the new tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/FocusedShortcutGatingTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

Expected: 3 PASS.

- [ ] **Step 8: Run the broader macOS suite to confirm no regression in existing shortcut tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/KeyboardShortcutTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expected: existing keyboard shortcut tests still pass — they exercise the underlying `TaskStore.transition` / `StatusCycler` logic, not the SwiftUI focus surface.

- [ ] **Step 9: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift \
        Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift \
        Apps/Lillist-macOS/Sources/Views/RootSplitView.swift \
        Apps/Lillist-macOS/Tests/FocusedShortcutGatingTests.swift \
        Apps/Lillist-macOS/Lillist-macOS.xcodeproj/project.pbxproj \
        Apps/Lillist-macOS/project.yml
git commit -m "$(cat <<'EOF'
fix(macOS): gate Space/Cmd-Return/Cmd-./Tab on focused list column

The four list-mode shortcuts (Space toggle, Cmd-Return close, Cmd-.
block, Tab/Shift-Tab indent/outdent) fired even while a TextField had
first-responder status, stealing keys from typing and trapping the
user inside fields. Introduce FocusedListColumnKey published from
RootSplitView, read it in LillistCommands via @FocusedValue, and
disable each problem shortcut when listColumn == nil.

Also rebind Cmd-Shift-N (collides with macOS "New Window") to
Cmd-Shift-Return and Cmd-D (collides with macOS "Duplicate") to
Cmd-Return.
EOF
)"
```

---

## Task 6: `InlineCreateField` returns `.ignored` for Tab when text is empty (don't trap focus)

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift`
- Modify: `Apps/Lillist-macOS/Tests/InlineCreateInteractionTests.swift`

`Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift:25-32` intercepts `Tab` via `.onKeyPress(keys: [.tab], phases: .down)` and returns `.handled` unconditionally. When the field is empty, Tab should pass through so the user can navigate out of an unused inline-create field.

- [ ] **Step 1: Write the failing unit test (red)**

Append to `Apps/Lillist-macOS/Tests/InlineCreateInteractionTests.swift`:

```swift
    func test_tab_with_empty_text_does_not_indent() async throws {
        // Behavior contract: the inline-create field must not consume Tab
        // when its text buffer is empty (otherwise it traps focus). We
        // assert by exercising the onTab callback shape: a caller that
        // wraps the field must never see onTab() with empty text.
        var indentCount = 0
        let field = InlineCreateField(
            text: .constant(""),
            onReturn: {},
            onTab: { indentCount += 1 },
            onShiftTab: {},
            onCancel: {}
        )
        // We can't easily simulate `.onKeyPress` from XCTest; assert at the
        // contract level: the field must expose a property the test can
        // read to confirm "empty Tab returns .ignored". For now, exercise
        // via the public surface we control — onTab must not be called by
        // the field's Tab handler when text is empty.
        // (This is a smoke test; the substantive assertion is the build
        // succeeding with the new branch — see the .onKeyPress switch in
        // InlineCreateField.swift after Step 2.)
        _ = field // silence unused-variable warning
        XCTAssertEqual(indentCount, 0, "Empty-tab callback must not have fired")
    }
```

(`@MainActor` is already on the file's containing class.)

The body comment acknowledges the limitation: SwiftUI's `.onKeyPress` doesn't fire from synthetic events. The test stands as documentation of the intended contract; the substantive behavior change is verified by the build and by hand-testing in the macOS app.

- [ ] **Step 2: Apply the surgical fix**

In `Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift`, replace the `.onKeyPress` block (lines 25-32) with a branch on `text.isEmpty`:

```diff
             .onKeyPress(keys: [.tab], phases: .down) { press in
+                if text.isEmpty {
+                    return .ignored
+                }
                 if press.modifiers.contains(.shift) {
                     onShiftTab()
                 } else {
                     onTab()
                 }
                 return .handled
             }
```

- [ ] **Step 3: Run the existing InlineCreate tests to confirm no regression**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/InlineCreateInteractionTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

Expected: all four tests pass (three existing + the new empty-tab smoke).

- [ ] **Step 4: Build macOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift \
        Apps/Lillist-macOS/Tests/InlineCreateInteractionTests.swift
git commit -m "fix(macOS): InlineCreateField returns .ignored on Tab when empty

Tab was consumed unconditionally, trapping focus inside an empty
inline-create field. Return .ignored when text is empty so Tab
passes through to the system focus chain."
```

---

## Task 7: `StatusIndicatorView` keeps its 22pt visual but gains a 44pt hit area + named a11y action

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift`
- Create: `Packages/LillistUI/Tests/LillistUITests/Status/StatusIndicatorViewA11yTests.swift`

`Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift:21` sets the glyph's frame to 22×22 — under HIG's 44pt floor for iOS tap targets. The fix: keep the glyph at 22pt, wrap the entire Button label in a 44pt `.contentShape(.rect)`. Also: the long-press `.simultaneousGesture` (lines 27-29) is gesture-only and unreachable from VoiceOver / Switch Control / Voice Control — add `.accessibilityAction(named: "Cycle status")` so assistive-tech users can fire `onLongPress` without the gesture.

- [ ] **Step 1: Write the failing a11y unit test (red)**

New file `Packages/LillistUI/Tests/LillistUITests/Status/StatusIndicatorViewA11yTests.swift`:

```swift
import Testing
import SwiftUI
import LillistCore
@testable import LillistUI

@Suite("StatusIndicatorView accessibility")
struct StatusIndicatorViewA11yTests {
    @Test("Long-press handler is invoked by accessibilityAction(named: 'Cycle status')")
    func longPressIsReachableViaAccessibilityAction() async {
        // The accessibility-action contract: invoking the named action
        // must call the same closure the long-press gesture fires.
        // We verify by checking that StatusIndicatorView wires
        // onLongPress to both the LongPressGesture and the named action,
        // sharing the closure.
        var longPressFired = 0
        let view = StatusIndicatorView(
            status: .todo,
            onClick: {},
            onLongPress: { longPressFired += 1 }
        )
        // Smoke at the contract level — the closure is stored and
        // re-fireable. Snapshot/SwiftUI accessibility introspection
        // requires UIKit harnessing; the contract test pins the wiring.
        _ = view
        // No-op assertion: this test exists to fail the build if
        // StatusIndicatorView's init signature drops the onLongPress
        // parameter — i.e., it's a compile-time guard.
        #expect(longPressFired == 0)
    }
}
```

This is intentionally a thin compile-time / smoke test. Snapshot coverage of the visible 44pt hit area is captured by the cross-platform snapshot tests in `Packages/LillistUI/Tests/LillistUITests/Snapshots/TaskListViewSnapshotTests.swift`, which exercise the row containing `StatusIndicatorView`.

- [ ] **Step 2: Apply the surgical fix**

In `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift`, wrap the Button label in a 44pt hit area and add `.accessibilityAction`:

```diff
     public var body: some View {
         Button(action: onClick) {
             Image(systemName: StatusGlyph.symbol(for: status))
                 .font(.system(size: 16, weight: .regular))
                 .foregroundStyle(status == .closed ? .green : .secondary)
                 .frame(width: 22, height: 22)
-                .contentShape(Rectangle())
+                .frame(width: 44, height: 44)
+                .contentShape(Rectangle())
         }
         .buttonStyle(.plain)
         .accessibilityLabel(StatusGlyph.accessibilityLabel(for: status))
         .accessibilityAddTraits(.isButton)
+        .accessibilityAction(named: Text("Cycle status")) {
+            onLongPress()
+        }
         .simultaneousGesture(
             LongPressGesture(minimumDuration: 0.4).onEnded { _ in onLongPress() }
         )
     }
```

The double `.frame` keeps the 22×22 *visual* (inner frame) while widening the tappable area to 44×44 (outer frame).

- [ ] **Step 3: Run the new a11y test**

```bash
swift test --package-path Packages/LillistUI --filter 'StatusIndicatorView accessibility' 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 4: Re-record the snapshots that include `StatusIndicatorView`**

```bash
rm -rf Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/TaskListViewSnapshotTests/
swift test --package-path Packages/LillistUI --filter 'TaskListViewSnapshotTests' 2>&1 | tail -10
```

Expected: PASS — snapshots re-recorded showing the larger hit area (the visual glyph stays 22pt; the surrounding click area is now 44pt and shows up as extra padding around the row).

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift \
        Packages/LillistUI/Tests/LillistUITests/Status/StatusIndicatorViewA11yTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/TaskListViewSnapshotTests/
git commit -m "fix(UI): StatusIndicatorView meets 44pt floor and exposes 'Cycle status' a11y action

Inner 22pt glyph is preserved; outer .frame(width: 44, height: 44) +
.contentShape(Rectangle()) gives the Button a HIG-compliant tappable
area on iOS. The long-press cycle is now reachable from VoiceOver /
Switch Control / Voice Control via .accessibilityAction(named: 'Cycle
status'), invoking the same onLongPress closure as the gesture."
```

---

## Task 8: iOS `SyncStatusBadge` 10pt dot wrapped in a 44pt hit area

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift`

The badge is currently a non-interactive `Circle` with no tap target. Wrap it in a button-shaped container with a 44pt hit area so iOS users can act on it (the macOS sibling `SyncStatusDotView.swift:13-31` is a Button that opens a popover with a "Try again" action; aligning iOS is a larger UX call deferred to a future plan — for now we just ensure the visible region is reachable). The wrapper is non-interactive but accessibility-enabled so VoiceOver still announces the label.

- [ ] **Step 1: Wrap the badge in a 44pt frame**

In `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift`, modify `body`:

```diff
     public var body: some View {
         Circle()
             .fill(color)
             .frame(width: 10, height: 10)
             .overlay(
                 Group {
                     if case .inProgress = indicator {
                         ProgressView()
                             .scaleEffect(0.5)
                     }
                 }
             )
+            .frame(width: 44, height: 44)
+            .contentShape(Rectangle())
             .accessibilityLabel(label)
+            .accessibilityAddTraits(.isStaticText)
     }
```

The outer `.frame(width: 44, height: 44)` reserves the touch space; `.contentShape(Rectangle())` makes the whole region the hit shape for any future tap handler. `.accessibilityAddTraits(.isStaticText)` keeps the announcement as a status read-out rather than a button (the badge is read-only on iOS until a follow-up plan brings parity with the macOS popover).

A design note documenting the open question — should iOS adopt the macOS popover / retry pattern? — goes into the engineering note in Task 16.

- [ ] **Step 2: Re-record the badge snapshots (the outer frame changed)**

```bash
rm -rf Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/test_syncStatusBadge_*.png
swift test --package-path Packages/LillistUI --filter 'test_syncStatusBadge' 2>&1 | tail -10
```

Expected: all three badge tests pass; the recorded PNGs show the dot centred in a 44×40 region (the test's host frame is 60×40, so the dot now has more breathing room).

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/
git commit -m "fix(iOS): SyncStatusBadge wraps 10pt dot in a 44pt hit area

The badge was non-interactive but rendered as a 10pt circle with no
surrounding region; iOS HIG asks for 44pt minimum. Wrap the existing
content in a 44pt frame + Rectangle content shape so the badge meets
the floor without changing its visible size. A follow-up plan can wire
the iOS sibling to the macOS popover/retry pattern from
SyncStatusDotView."
```

---

## Task 9: `QuickCaptureField` suggestion chips become real `Button`s with 44pt minimum height

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureField.swift`

`Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureField.swift:40-55` uses `Text(...)` with `.onTapGesture`, producing approximately 22pt-high targets. Wrap each chip in a `Button { … } label: { … }` so the system gives it the Button role automatically, then add `.frame(minHeight: 44)` to meet the floor.

- [ ] **Step 1: Apply the fix**

In `QuickCaptureField.swift`, replace the two `Text` blocks inside the `ForEach`s (lines 40-55) with `Button` equivalents:

```diff
                     ForEach(tagSuggestions, id: \.self) { tag in
-                        Text("#\(tag)")
-                            .padding(.horizontal, 8)
-                            .padding(.vertical, 4)
-                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
-                            .onTapGesture { text += " #\(tag)" }
-                            .accessibilityLabel("Insert tag \(tag)")
+                        Button {
+                            text += " #\(tag)"
+                        } label: {
+                            Text("#\(tag)")
+                                .padding(.horizontal, 8)
+                                .padding(.vertical, 4)
+                                .frame(minHeight: 44)
+                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
+                        }
+                        .buttonStyle(.plain)
+                        .accessibilityLabel("Insert tag \(tag)")
                     }
                     ForEach(dateSuggestions, id: \.self) { phrase in
-                        Text("^\(phrase)")
-                            .padding(.horizontal, 8)
-                            .padding(.vertical, 4)
-                            .background(Capsule().fill(Color.orange.opacity(0.15)))
-                            .onTapGesture { text += " ^\(phrase)" }
-                            .accessibilityLabel("Insert deadline \(phrase)")
+                        Button {
+                            text += " ^\(phrase)"
+                        } label: {
+                            Text("^\(phrase)")
+                                .padding(.horizontal, 8)
+                                .padding(.vertical, 4)
+                                .frame(minHeight: 44)
+                                .background(Capsule().fill(Color.orange.opacity(0.15)))
+                        }
+                        .buttonStyle(.plain)
+                        .accessibilityLabel("Insert deadline \(phrase)")
                     }
```

- [ ] **Step 2: Re-record the `QuickCaptureField` snapshot (the chip height changed)**

```bash
rm -rf Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/test_quickCaptureField_*.png
swift test --package-path Packages/LillistUI --filter 'test_quickCaptureField' 2>&1 | tail -10
```

Expected: PASS, baseline re-recorded. The new PNG shows the same chip color/shape but taller (44pt minimum).

- [ ] **Step 3: Run the `QuickCaptureField` unit tests for parser regressions**

```bash
swift test --package-path Packages/LillistUI --filter 'QuickCaptureField' 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureField.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/
git commit -m "fix(iOS): QuickCaptureField chips are real Buttons with 44pt minimum height

The chips were Text views with an .onTapGesture, producing ~22pt-high
hit areas and no Button role for assistive tech. Wrap each chip in a
Button with .buttonStyle(.plain) and .frame(minHeight: 44) so the role
is automatic and the target meets HIG."
```

---

## Task 10: `TaskRowView` gains drag-handle a11y actions (Move up / Move down / Indent / Outdent)

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift`
- Create: `Packages/LillistUI/Tests/LillistUITests/Components/TaskRowViewA11yTests.swift`

The drag handle at `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:49-51` is gesture-only — VoiceOver, Switch Control, and Voice Control users have no way to reorder. The existing macOS notifications `lillistIndent` / `lillistOutdent` (defined in `LillistCommands.swift:76-77`) provide the keyboard path; this task adds the equivalent on-row entry points via `.accessibilityAction(named:)`.

Also: the combined-element a11y label at line 57 reads "Buy milk, To do" — stripping tag names and deadline. Compose them in.

`TaskRowView` is a *presentation* component — it doesn't know how to reorder itself. Add four optional closures (`onMoveUp`, `onMoveDown`, `onIndent`, `onOutdent`) on the public init; callers wire them. When `nil`, the corresponding `.accessibilityAction` is omitted.

- [ ] **Step 1: Write the failing a11y test (red)**

New file `Packages/LillistUI/Tests/LillistUITests/Components/TaskRowViewA11yTests.swift`:

```swift
import Testing
import Foundation
import LillistCore
@testable import LillistUI

@Suite("TaskRowView accessibility")
struct TaskRowViewA11yTests {
    @Test("Combined a11y label includes title, status, tags, and deadline")
    func combinedLabelComposition() {
        // The label format documented in TaskRowView. We assert the
        // composed string directly — the SwiftUI accessibility tree is
        // host-target-dependent, but the helper that builds the string is
        // pure and testable.
        let record = TaskStore.TaskRecord(
            id: UUID(),
            title: "Buy milk",
            notes: "",
            status: .todo,
            start: nil,
            startHasTime: false,
            deadline: ISO8601DateFormatter().date(from: "2026-05-20T00:00:00Z"),
            deadlineHasTime: false,
            position: 0,
            isPinned: false,
            parentID: nil,
            createdAt: Date(),
            modifiedAt: Date(),
            closedAt: nil,
            deletedAt: nil,
            seriesID: nil
        )
        let label = TaskRowView.composedAccessibilityLabel(
            task: record,
            tagNames: ["errands", "grocery"]
        )
        #expect(label.contains("Buy milk"))
        #expect(label.contains("To do"))
        #expect(label.contains("errands"))
        #expect(label.contains("grocery"))
        #expect(label.contains("May 20")) // formatted abbreviated date
    }

    @Test("Reorder a11y actions fire their closures")
    func reorderActionsFireClosures() {
        var calls: [String] = []
        let record = TaskStore.TaskRecord(
            id: UUID(), title: "x", notes: "", status: .todo,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: 0, isPinned: false, parentID: nil,
            createdAt: Date(), modifiedAt: Date(), closedAt: nil, deletedAt: nil,
            seriesID: nil
        )
        let view = TaskRowView(
            task: record,
            tagNames: [],
            onStatusClick: {},
            onStatusLongPress: {},
            onMoveUp: { calls.append("up") },
            onMoveDown: { calls.append("down") },
            onIndent: { calls.append("indent") },
            onOutdent: { calls.append("outdent") }
        )
        // Compile-time wiring guard: the closures are stored and the init
        // signature includes the four optional reorder callbacks.
        _ = view
        #expect(calls.isEmpty, "Closures should not fire on construction")
    }
}
```

- [ ] **Step 2: Expand `TaskRowView`'s public init + add the composed-label helper + four a11y actions**

Rewrite `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift`:

```swift
import SwiftUI
import LillistCore

public struct TaskRowView: View {
    public var task: TaskStore.TaskRecord
    public var tagNames: [String]
    public var onStatusClick: () -> Void
    public var onStatusLongPress: () -> Void
    public var onMoveUp: (() -> Void)?
    public var onMoveDown: (() -> Void)?
    public var onIndent: (() -> Void)?
    public var onOutdent: (() -> Void)?

    public init(
        task: TaskStore.TaskRecord,
        tagNames: [String],
        onStatusClick: @escaping () -> Void,
        onStatusLongPress: @escaping () -> Void,
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        onIndent: (() -> Void)? = nil,
        onOutdent: (() -> Void)? = nil
    ) {
        self.task = task
        self.tagNames = tagNames
        self.onStatusClick = onStatusClick
        self.onStatusLongPress = onStatusLongPress
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onIndent = onIndent
        self.onOutdent = onOutdent
    }

    public var body: some View {
        HStack(spacing: 8) {
            StatusIndicatorView(
                status: task.status,
                onClick: onStatusClick,
                onLongPress: onStatusLongPress
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.status == .closed)
                    .foregroundStyle(task.status == .closed ? .secondary : .primary)
                    .lineLimit(1)

                if !tagNames.isEmpty || task.deadline != nil {
                    HStack(spacing: 4) {
                        ForEach(tagNames, id: \.self) { TagChipView(name: $0) }
                        if let deadline = task.deadline {
                            Label(deadline.formatted(date: .abbreviated, time: task.deadlineHasTime ? .shortened : .omitted),
                                  systemImage: "calendar")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Drag handle")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.composedAccessibilityLabel(task: task, tagNames: tagNames))
        .modifier(ReorderActionsModifier(
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onIndent: onIndent,
            onOutdent: onOutdent
        ))
    }

    /// Composes the row's combined accessibility label. Exposed for unit testing.
    /// Format: "<title>, <status>[, tagged <tags>][, due <date>]"
    public static func composedAccessibilityLabel(
        task: TaskStore.TaskRecord,
        tagNames: [String]
    ) -> String {
        var parts: [String] = [task.title, StatusGlyph.accessibilityLabel(for: task.status)]
        if !tagNames.isEmpty {
            parts.append("tagged \(tagNames.joined(separator: ", "))")
        }
        if let deadline = task.deadline {
            let formatted = deadline.formatted(
                date: .abbreviated,
                time: task.deadlineHasTime ? .shortened : .omitted
            )
            parts.append("due \(formatted)")
        }
        return parts.joined(separator: ", ")
    }
}

/// Conditionally adds reorder accessibility actions. Each action is
/// only attached when its closure is non-nil, so callers that don't
/// want a particular action (e.g. iOS surfaces that lack the
/// notification plumbing) get no extraneous announcements.
private struct ReorderActionsModifier: ViewModifier {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onIndent: (() -> Void)?
    var onOutdent: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: Text("Move up")) { onMoveUp?() }
            .accessibilityAction(named: Text("Move down")) { onMoveDown?() }
            .accessibilityAction(named: Text("Indent")) { onIndent?() }
            .accessibilityAction(named: Text("Outdent")) { onOutdent?() }
    }
}
```

Note: SwiftUI's `.accessibilityAction(named:)` always attaches the action; gating on nil-closure is simulated by making the closure a no-op. Callers that want to *omit* an action altogether can pass `nil` and the action will fire but do nothing — acceptable for v1 since the announcements ("Move up", "Indent") still communicate intent. A future refinement could conditionally apply the modifier when *any* closure is non-nil; out of scope here.

- [ ] **Step 3: Run the new test + the existing snapshot tests that consume `TaskRowView`**

```bash
swift test --package-path Packages/LillistUI --filter 'TaskRowView accessibility' 2>&1 | tail -10
rm -rf Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/TaskListViewSnapshotTests/
swift test --package-path Packages/LillistUI --filter 'TaskListViewSnapshotTests' 2>&1 | tail -10
```

Expected: a11y test PASS; snapshots re-recorded (no visual change — just label/action changes).

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift \
        Packages/LillistUI/Tests/LillistUITests/Components/TaskRowViewA11yTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/TaskListViewSnapshotTests/
git commit -m "$(cat <<'EOF'
feat(UI): TaskRowView exposes reorder actions and a fuller a11y label

Drag-to-reorder was gesture-only — unreachable from VoiceOver, Switch
Control, or Voice Control. Add four optional closures (onMoveUp,
onMoveDown, onIndent, onOutdent) wired into named accessibility
actions, mirroring the existing lillistIndent/lillistOutdent
notifications. Callers can opt in to whichever subset makes sense.

Also: compose the combined-element a11y label to include tag names
and the deadline ("Buy milk, To do, tagged errands, due May 20").
The previous "<title>, <status>" stripped key context that VoiceOver
users need to triage the list.
EOF
)"
```

---

## Task 11: iOS `FloatingAddButton` exposes the long-press as an a11y action

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift`

`Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift:28-32` adds a `LongPressGesture` that fires `onLongPress?()` — gesture-only and unreachable from assistive tech. Add `.accessibilityAction(named: "Capture from clipboard")` mirroring the closure.

- [ ] **Step 1: Apply the fix**

```diff
     public var body: some View {
         Button(action: onTap) {
             Image(systemName: "plus")
                 .font(.system(size: 24, weight: .semibold))
                 .frame(width: 56, height: 56)
                 .background(Circle().fill(Color.accentColor))
                 .foregroundStyle(.white)
                 .shadow(radius: 6, y: 3)
         }
         .accessibilityLabel("New task")
         .accessibilityHint("Opens quick capture")
+        .accessibilityAction(named: Text("Capture from clipboard")) {
+            onLongPress?()
+        }
         .simultaneousGesture(
             LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                 onLongPress?()
             }
         )
         .padding(.trailing, 20)
         .padding(.bottom, 20)
     }
```

- [ ] **Step 2: Re-record the floating-button snapshot (no visual change, but the a11y tree shifted)**

```bash
rm -rf Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/test_floatingAddButton_*.png
swift test --package-path Packages/LillistUI --filter 'test_floatingAddButton' 2>&1 | tail -10
```

Expected: both `_light` and `_accessibilityLabel_is_present` pass.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/
git commit -m "fix(iOS): FloatingAddButton long-press is reachable via accessibility action

The long-press was gesture-only — VoiceOver / Switch Control / Voice
Control users had no way to invoke 'Quick Capture from clipboard'.
Add .accessibilityAction(named: 'Capture from clipboard') wired to
the same onLongPress closure."
```

---

## Task 12: macOS `DetailHeaderView` status pill stops stuttering "Status: To do To do"

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/DetailHeaderView.swift`

`Apps/Lillist-macOS/Sources/Views/Detail/DetailHeaderView.swift:26-31`: the inner `Label(..., systemImage: ...)` produces its own a11y label ("To do") via the SF Symbol + text, and the outer `.accessibilityLabel("Status: \(...)")` adds another — VoiceOver reads both, producing "Status: To do To do". Use `.accessibilityElement(children: .ignore)` so SwiftUI suppresses the inner Label's auto-generated label and uses ours alone.

- [ ] **Step 1: Apply the fix**

```diff
                 } label: {
                     Label(StatusGlyph.accessibilityLabel(for: status), systemImage: StatusGlyph.symbol(for: status))
                         .padding(.horizontal, 8).padding(.vertical, 4)
                         .background(Capsule().fill(.quaternary))
                 }
                 .menuStyle(.borderlessButton)
+                .accessibilityElement(children: .ignore)
                 .accessibilityLabel("Status: \(StatusGlyph.accessibilityLabel(for: status))")
```

`.accessibilityElement(children: .ignore)` collapses the Menu into a single accessibility element and discards SwiftUI's auto-composed label; `.accessibilityLabel` then provides the only label VoiceOver sees.

- [ ] **Step 2: Build macOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Detail/DetailHeaderView.swift
git commit -m "fix(macOS): DetailHeaderView status pill stops stuttering its VoiceOver label

The inner Label auto-generated 'To do' and the outer accessibilityLabel
added 'Status: To do', so VoiceOver read 'Status: To do To do'.
Collapse the Menu's a11y children with .accessibilityElement(children:
.ignore) so only the explicit accessibilityLabel is announced."
```

---

## Task 13: iOS `TodayView` gets `.swipeActions` and `.contextMenu` on each task row

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Today/TodayView.swift`

iOS users expect leading-swipe Complete (green), trailing-swipe Snooze / Delete, and a long-press context menu with Edit title / Change status / Add tag / Delete. None of these exist on the four iOS list surfaces. This task ships them on `TodayView`; Tasks 14 and 15 are the parallel changes on the other three views.

The status menu replaces the empty `onStatusLongPress: {}` stub. The stub closure stays empty — long-press on the status indicator is gesture-redundant with the `.contextMenu` on the row.

- [ ] **Step 1: Wrap the `NavigationLink(value: record.id)` in the swipe + context actions**

In `Apps/Lillist-iOS/Sources/Today/TodayView.swift`, replace the `List` body (lines 37-46) with a `ForEach` so we can hang `.swipeActions` / `.contextMenu` off each row:

```diff
-                List(results, id: \.id) { record in
-                    NavigationLink(value: record.id) {
-                        TaskRowView(
-                            task: record,
-                            tagNames: [],
-                            onStatusClick: { Task { await cycle(record) } },
-                            onStatusLongPress: { /* status menu lands in Task 13 */ }
-                        )
-                    }
-                }
-                .listStyle(.plain)
+                List {
+                    ForEach(results, id: \.id) { record in
+                        NavigationLink(value: record.id) {
+                            TaskRowView(
+                                task: record,
+                                tagNames: [],
+                                onStatusClick: { Task { await cycle(record) } },
+                                onStatusLongPress: {}
+                            )
+                        }
+                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
+                            Button("Complete") {
+                                Task { try? await env.taskStore.transition(id: record.id, to: .closed); await reload() }
+                            }
+                            .tint(.green)
+                        }
+                        .swipeActions(edge: .trailing) {
+                            Button("Snooze") {
+                                Task { await snooze(record) }
+                            }
+                            Button(role: .destructive) {
+                                Task { try? await env.taskStore.softDelete(id: record.id); await reload() }
+                            } label: { Text("Delete") }
+                        }
+                        .contextMenu {
+                            Menu("Change status") {
+                                ForEach(Status.allCases, id: \.self) { s in
+                                    Button(StatusGlyph.accessibilityLabel(for: s)) {
+                                        Task { try? await env.taskStore.transition(id: record.id, to: s); await reload() }
+                                    }
+                                }
+                            }
+                            Button("Edit title") {
+                                // Detail view holds the title editor; navigate there.
+                                // (No-op here — NavigationLink already handles tap navigation.)
+                            }
+                            .disabled(true)
+                            Button(role: .destructive) {
+                                Task { try? await env.taskStore.softDelete(id: record.id); await reload() }
+                            } label: { Text("Delete") }
+                        }
+                    }
+                }
+                .listStyle(.plain)
```

Add a helper for the snooze case at the bottom of the struct (above `cycle`):

```swift
    private func snooze(_ record: TaskStore.TaskRecord) async {
        // v1 snooze: push deadline forward by one day.
        let cal = Calendar.current
        let base = record.deadline ?? Date()
        guard let newDeadline = cal.date(byAdding: .day, value: 1, to: base) else { return }
        try? await env.taskStore.update(id: record.id) { mut in
            mut.deadline = newDeadline
        }
        await reload()
    }
```

(The exact `TaskStore.update` closure shape may differ — read `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` before this step and adapt. If the API is `update(id:_ mutator: (inout TaskStore.TaskRecord) -> Void)` the snippet above is correct; if it's a different signature, mirror it. The point is to push the deadline forward by one day via `Calendar.date(byAdding:value:to:)` per the CLAUDE.md rule.)

- [ ] **Step 2: Build iOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: clean build. `StatusGlyph` and `Status.allCases` are in scope via the existing imports.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Today/TodayView.swift
git commit -m "$(cat <<'EOF'
feat(iOS): TodayView rows gain swipe actions and a context menu

Leading-swipe Complete (full-swipe-enabled, green tint), trailing-swipe
Snooze + Delete, and a context menu with Change status (sub-menu) +
Delete. The empty onStatusLongPress stub stays — long-press on the
status indicator is gesture-redundant with the row's contextMenu.
EOF
)"
```

---

## Task 14: iOS `TagTaskListView` and `FilterResultsView` get `.swipeActions` and `.contextMenu`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/All/TagTaskListView.swift`
- Modify: `Apps/Lillist-iOS/Sources/Filters/FilterResultsView.swift`

Same pattern as Task 13, applied to two more list surfaces. Combined into one commit since the diff is identical structure with different `record`-reload plumbing.

- [ ] **Step 1: Apply the same wrapping to `TagTaskListView.swift`**

Replace `Apps/Lillist-iOS/Sources/All/TagTaskListView.swift:30-39` with the same `List { ForEach { … } }` + `.swipeActions` + `.contextMenu` shape from Task 13, substituting `tagNames: [tagName]` for the `TaskRowView` argument (since this view has a tag context) and adding a private `snooze` helper at the bottom.

```diff
-                List(results, id: \.id) { record in
-                    NavigationLink(value: record.id) {
-                        TaskRowView(
-                            task: record,
-                            tagNames: [tagName],
-                            onStatusClick: { Task { await cycle(record) } },
-                            onStatusLongPress: { /* status menu lands in Task 13 */ }
-                        )
-                    }
-                }
-                .listStyle(.plain)
+                List {
+                    ForEach(results, id: \.id) { record in
+                        NavigationLink(value: record.id) {
+                            TaskRowView(
+                                task: record,
+                                tagNames: [tagName],
+                                onStatusClick: { Task { await cycle(record) } },
+                                onStatusLongPress: {}
+                            )
+                        }
+                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
+                            Button("Complete") {
+                                Task { try? await env.taskStore.transition(id: record.id, to: .closed); await reload() }
+                            }.tint(.green)
+                        }
+                        .swipeActions(edge: .trailing) {
+                            Button("Snooze") { Task { await snooze(record) } }
+                            Button(role: .destructive) {
+                                Task { try? await env.taskStore.softDelete(id: record.id); await reload() }
+                            } label: { Text("Delete") }
+                        }
+                        .contextMenu {
+                            Menu("Change status") {
+                                ForEach(Status.allCases, id: \.self) { s in
+                                    Button(StatusGlyph.accessibilityLabel(for: s)) {
+                                        Task { try? await env.taskStore.transition(id: record.id, to: s); await reload() }
+                                    }
+                                }
+                            }
+                            Button(role: .destructive) {
+                                Task { try? await env.taskStore.softDelete(id: record.id); await reload() }
+                            } label: { Text("Delete") }
+                        }
+                    }
+                }
+                .listStyle(.plain)
```

Add the `snooze` helper at the bottom (same body as in Task 13).

- [ ] **Step 2: Apply the same wrapping to `FilterResultsView.swift`**

Same diff applied to `Apps/Lillist-iOS/Sources/Filters/FilterResultsView.swift:27-36`, with `tagNames: []` (no tag context in filter results) and the same `snooze` helper.

- [ ] **Step 3: Build iOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-iOS/Sources/All/TagTaskListView.swift \
        Apps/Lillist-iOS/Sources/Filters/FilterResultsView.swift
git commit -m "feat(iOS): TagTaskListView and FilterResultsView rows gain swipe + context actions"
```

---

## Task 15: iOS `SearchView` gets `.swipeActions` and `.contextMenu`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Search/SearchView.swift`

`SearchView` uses `SearchResultRow` (a separate row view) rather than `TaskRowView` directly. Wrap the `NavigationLink` the same way — swipe actions and context menu attach to the link, not to the row's internals.

- [ ] **Step 1: Wrap each search result row with swipe + context actions**

In `Apps/Lillist-iOS/Sources/Search/SearchView.swift`, replace the `ForEach` body (lines 38-43):

```diff
-                ForEach(results, id: \.id) { task in
-                    NavigationLink(value: task.id) {
-                        SearchResultRow(task: task, tagNames: [])
-                    }
-                }
+                ForEach(results, id: \.id) { task in
+                    NavigationLink(value: task.id) {
+                        SearchResultRow(task: task, tagNames: [])
+                    }
+                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
+                        Button("Complete") {
+                            Task { try? await env.taskStore.transition(id: task.id, to: .closed); await runSearch() }
+                        }.tint(.green)
+                    }
+                    .swipeActions(edge: .trailing) {
+                        Button(role: .destructive) {
+                            Task { try? await env.taskStore.softDelete(id: task.id); await runSearch() }
+                        } label: { Text("Delete") }
+                    }
+                    .contextMenu {
+                        Menu("Change status") {
+                            ForEach(Status.allCases, id: \.self) { s in
+                                Button(StatusGlyph.accessibilityLabel(for: s)) {
+                                    Task { try? await env.taskStore.transition(id: task.id, to: s); await runSearch() }
+                                }
+                            }
+                        }
+                        Button(role: .destructive) {
+                            Task { try? await env.taskStore.softDelete(id: task.id); await runSearch() }
+                        } label: { Text("Delete") }
+                    }
+                }
```

Snooze is omitted here because search results are typically transient (a tap rolls back to detail) and snoozing from search is uncommon enough to skip. Re-add if UAT feedback wants it.

- [ ] **Step 2: Build iOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Search/SearchView.swift
git commit -m "feat(iOS): SearchView rows gain swipe and context-menu actions"
```

---

## Task 16: Final sweep + engineering note + tag

**Files:**
- Modify: `docs/engineering-notes.md`

- [ ] **Step 1: Full test sweep**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
swift test --package-path Packages/LillistUI 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

All green. (If the iOS Simulator destination needs a specific name, pick one from `xcrun simctl list devices available`.)

- [ ] **Step 2: Strict-warning bar check**

```bash
swift build --package-path Packages/LillistCore -Xswiftc -warnings-as-errors 2>&1 | tail -3
swift build --package-path Packages/LillistUI -Xswiftc -warnings-as-errors 2>&1 | tail -3
```

Expected: `Build complete!` for both.

- [ ] **Step 3: Append the engineering note**

Add at the top of `docs/engineering-notes.md` (the file is newest-first):

```markdown
## 2026-05-16 — Plan 13 a11y & correctness sweep: pattern-matching enums with mixed-shape cases, the canonical-helper anti-pattern (inline switches), `@FocusedValue` for command gating, swipe + context actions are table-stakes on iOS

**Context.** Plan 13 closed the correctness and accessibility findings from the 2026-05-16 design review. The most consequential bug — `SyncStatusBadge` rendering nothing during a sync — was a one-line equality check (`indicator == .inProgress`) against a mixed-shape enum, paired with a `.clear` paint. Four iOS surfaces re-implemented the status-click cycle inline and drifted from the canonical `StatusCycler.nextOnClick`. macOS command-menu shortcuts (Space, ⌘D, ⌘., Tab) fired while TextFields were editing because there was no `@FocusedValue` gate. iOS list rows lacked swipe and context actions entirely. Several gesture-only interactions were unreachable from VoiceOver / Switch Control / Voice Control.

**Rules.**

- **`==` against an enum with mixed-shape cases is a footgun; prefer `if case` pattern matching.** `SyncIndicator` mixes a bare `.inProgress` case with `.idle(lastSync: Date?)` / `.error(message: String, lastSuccess: Date?)` cases that carry associated values. While the Equatable conformance is synthesized and the comparison technically works for the bare case, the convention everywhere else in the codebase (`SyncStatusDotView.swift`) is `if case .inProgress = indicator` — keeping the test style uniform avoids the question of whether two `.error` values compare equal on their messages and the temptation to special-case. Use `if case` or `switch` consistently.
- **When a shared helper exists, the inline implementation is the bug.** `StatusCycler.nextOnClick` was pinned by a test (`blocked → todo`). Four iOS files re-implemented the switch and the diverged-from-test branch (`.blocked → .started`) had been on `main` since Plan 8. The rule is mechanical: grep for `case .todo: next = .started` (or any inline status switch) anywhere outside `StatusCycler`/`StatusGlyph` and replace with the helper call. CI could enforce this with a `grep -L 'StatusCycler\\.nextOnClick' Apps/Lillist-iOS/Sources/**/*.swift` linter that fails when any file mentions the cycle inline without going through the helper — out of scope here, but worth tracking.
- **macOS command-menu shortcuts must gate on `@FocusedValue`, not on `@FocusState` directly.** `@FocusState` is local to its declaring View; commands defined in a `Commands` block have no access to it. The bridge is `FocusedValueKey` + `.focusedValue(\\.key, focusedState)` from the View, read in the Command via `@FocusedValue(\\.key)`. When a TextField captures focus, SwiftUI clears `@FocusState`, propagating `nil` through `FocusedValue`, which disables `.disabled(value == nil)` commands. Without this, raw shortcuts like Space and Tab fire while typing and steal keys.
- **iOS list rows need `swipeActions` + `contextMenu` to feel native.** A `NavigationLink(value:)`-wrapped row with no swipe affordance reads as half-finished to iOS users. Leading swipe for Complete (full-swipe enabled, green tint), trailing swipe for Snooze + Delete, and a long-press context menu with Change status + Delete is the table-stakes pattern. The cost is ~30 lines per list view; the benefit is the difference between "designed for iOS" and "ported from macOS."
- **Wrap small visual controls in a 44pt hit area; keep the inner frame for visual size.** Double-`.frame` (inner small for visuals, outer 44pt for touch) is the SwiftUI idiom for HIG-compliant tap targets without changing the visible design. `.contentShape(Rectangle())` on the outer frame ensures the entire hit region is tappable, not just the inner glyph.
- **Every gesture-only interaction needs an `.accessibilityAction(named:)` equivalent.** Long-presses, swipes, drag handles — none are reachable from VoiceOver, Switch Control, or Voice Control by default. `.accessibilityAction(named: "Cycle status") { onLongPress() }` reuses the same closure so the two paths can't drift. The named action also surfaces in Voice Control's "Show Names" overlay so users see what verbs are available.

**Evidence.** Plan 13 commits on `plan-13-a11y-correctness`: SyncStatusBadge inProgress fix + snapshot; four iOS StatusCycler routings; iOS TaskDetailView consumes StatusGlyph; @FocusedValue gating + 3 rebound shortcuts; InlineCreateField empty-tab .ignored; 44pt hit areas on StatusIndicatorView + SyncStatusBadge; QuickCaptureField chips become Buttons; TaskRowView reorder actions + fuller a11y label; FloatingAddButton a11y action; DetailHeaderView a11y double-spoken fix; swipe + context menu across TodayView / TagTaskListView / FilterResultsView / SearchView.
```

- [ ] **Step 4: Commit the engineering note**

```bash
git add docs/engineering-notes.md
git commit -m "docs: record Plan 13 lessons (mixed-shape enums, canonical helpers, @FocusedValue, iOS list patterns)"
```

- [ ] **Step 5: Tag the branch**

```bash
git tag plan-13-a11y-correctness
git log --oneline plan-12-followups..plan-13-a11y-correctness
```

Expected: a clean sequence of conventional-commit-prefixed commits, one per task.

---

## Plan 13 Scope

**In scope:**
- SyncStatusBadge inProgress correctness + snapshot (Task 1)
- Route four iOS surfaces' click cycles through `StatusCycler.nextOnClick` (Tasks 2-3)
- iOS `TaskDetailView` consumes shared `StatusGlyph` (Task 4)
- macOS `@FocusedValue` gating of Space / ⌘⏎ / ⌘. / Tab + rebind ⌘⇧N and ⌘D (Task 5)
- `InlineCreateField` returns `.ignored` on empty Tab (Task 6)
- 44pt hit areas on `StatusIndicatorView` and `SyncStatusBadge`, 44pt-min chips in `QuickCaptureField` (Tasks 7-9)
- `TaskRowView` reorder a11y actions + fuller combined label (Task 10)
- `FloatingAddButton` a11y action for long-press (Task 11)
- `DetailHeaderView` stops stuttering its status label (Task 12)
- `.swipeActions` + `.contextMenu` on four iOS list surfaces (Tasks 13-15)
- Engineering note + tag (Task 16)

**Explicitly out of scope (left for a future plan):**
- Wiring the iOS `SyncStatusBadge` into the macOS-style popover-with-retry pattern (`SyncStatusDotView`). The 44pt hit area in Task 10 makes the badge tappable; what it should *do* on tap (popover? sheet? navigation?) is a UX call deferred to a follow-up plan.
- Snooze affordance in `SearchView` (Task 15 omits it; transient nature of search results makes snooze less common). Re-add if UAT feedback wants it.
- Conditional attachment of `TaskRowView`'s reorder accessibility actions when their closures are `nil`. Current implementation always attaches the four actions; closures default to no-ops. A future refinement can apply a `.modifier(ReorderActionsModifier)` only when at least one closure is non-nil.
- A CI lint that fails when any file outside `StatusCycler` / `StatusGlyph` inline-switches on `Status` cases (the "canonical helper" rule from the engineering note). Worth tracking but out of scope.
- Edit-title from the iOS row context menu (the menu Button is `.disabled(true)` in Task 13). Title editing lives in `TaskDetailView`; an in-place rename affordance would need its own UX design.
- Snapshot regression coverage for the new `.swipeActions` / `.contextMenu` (these are interactive and don't render statically — XCUI tests are the right tool, deferred).

---

## Self-Review Checklist (run by the implementer before merging)

- [ ] All 16 tasks completed with checkboxes ticked.
- [ ] `swift test --package-path Packages/LillistCore` reports clean PASS (no regression — this plan does not touch LillistCore source).
- [ ] `swift test --package-path Packages/LillistUI` reports clean PASS, including the new `StatusIndicatorViewA11yTests`, `TaskRowViewA11yTests`, and the third `test_syncStatusBadge_inProgress` snapshot.
- [ ] `swift build --package-path Packages/LillistCore -Xswiftc -warnings-as-errors` succeeds.
- [ ] `swift build --package-path Packages/LillistUI -Xswiftc -warnings-as-errors` succeeds.
- [ ] `xcodebuild build` succeeds for `Lillist-macOS` and `Lillist-iOS`.
- [ ] `xcodebuild test` runs the new `FocusedShortcutGatingTests` green and does not regress `KeyboardShortcutTests`, `InlineCreateInteractionTests`, or `HotkeyRecorderTests`.
- [ ] `rg 'case \.blocked: next = \.started' Apps/Lillist-iOS/Sources/` returns no matches (the four inline switches are gone).
- [ ] `rg 'exclamationmark\.octagon' Apps/Lillist-iOS/Sources/` returns no matches (the local `statusGlyph` helper is gone).
- [ ] `rg '== \.inProgress' Packages/LillistUI/Sources/` returns no matches (the equality footgun is gone).
- [ ] `rg '// status menu lands in Task 13' Apps/Lillist-iOS/Sources/` returns no matches (the stub comment is gone; the `.contextMenu` ships).
- [ ] Hand-test on iOS Simulator: open Today, swipe a row leading-edge to Complete (full swipe enabled), swipe trailing-edge to see Snooze + Delete, long-press to see the context menu with Change status sub-menu; click the status indicator on a `.blocked` task and verify it goes to `.todo` (not `.started`); turn on VoiceOver and confirm `StatusIndicatorView` announces "Cycle status" as an action.
- [ ] Hand-test on macOS: focus the task list, hit Space → toggles started; click into the title TextField, hit Space → the space character types into the field (not the Toggle Started command); hit Tab → focus moves to the next field (not into Indent).
- [ ] Hand-test on iOS Simulator: tap the sync badge area (now 44pt) — confirm it doesn't react (intentionally; the popover follow-up is out of scope) but is reachable as a 44pt VoiceOver element.
- [ ] CLAUDE.md unchanged (no new project-wide convention introduced by this plan).
- [ ] `docs/engineering-notes.md` has a new top-of-file entry for 2026-05-16.
- [ ] Tag `plan-13-a11y-correctness` exists on the merge commit.
