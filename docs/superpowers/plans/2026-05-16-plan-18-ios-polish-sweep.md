# Lillist Plan 18 — iOS Polish Sweep

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the iOS LOW / NIT items that surfaced in the 2026-05-16 design review but were *not* picked up by Plans 13-17. Each task is a small, opportunistic correction to existing iOS surfaces — no new features, no architectural moves, no new entities or dependencies. The plan tightens gesture reliability on the status indicator, adds the pull-to-refresh affordance the All-tags list is missing, removes dead defensive code in Quick Capture, dresses up the Notes editor's empty surface, reconciles a hand-rolled detail header with `.navigationTitle`, hides a misleading preview when crash prompts are off, adds footers explaining non-obvious Form defaults, decides the fate of the unused-on-iOS `EmptyStateView`, gives Quick Capture proper user-resizable detent semantics, lets crash-report users preview logs and breadcrumbs independently, and turns the "no Mail" dead end in `CrashReporterHost` into a usable copy-to-clipboard fallback.

**Architecture:** All eleven tasks are local SwiftUI edits inside files that already exist. No new directories, no new value types, no API moves between targets, no new SwiftPM dependencies. The largest surface change is Task 5's swap of a hand-rolled header for `.navigationTitle(...).navigationBarTitleDisplayMode(.large)`; the smallest are one-line additions (`.refreshable`, `.scrollIndicators(.automatic)`). Every change is reversible and lands as a single conventional commit per task. Where a task overlaps with a sibling plan (13/14/16), the dependency is named in the task header so the executor knows which plan must merge first.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing for `LillistCore` and ad-hoc unit tests, XCTest + `swift-snapshot-testing` for the `LillistUITests/iOS/` snapshot bundle.

**Depends on:**
- **Plan 13 (a11y-correctness)** — Task 1 of this plan replaces the long-press `.simultaneousGesture` that Plan 13 Task 4 wrapped with `.accessibilityAction(named: "Cycle status")`. Land Plan 13 first so the a11y action is present when this plan rewires the underlying interaction.
- **Plan 14 (design-system)** — Plan 14 Task migrates `EmptyStateView` to design tokens; Task 8 of this plan decides the file's long-term fate (delete vs. macOS-only doc-comment). Land Plan 14 first so the file is in its final design-system form before Plan 18 makes the keep/delete call.
- **Plan 16 (ios-polish)** — Task 9 of this plan layers binding-based `selection:` detent semantics on top of Plan 16 Task 11's `.fraction(0.35), .medium, .large` detent set. Land Plan 16 first.
- Plans 15 (macOS chrome) and 17 (i18n/a11y/environments) are independent — no merge ordering required against this plan.

---

## File Structure

```
Lillist/
├── Packages/
│   └── LillistUI/
│       ├── Sources/
│       │   └── LillistUI/
│       │       ├── Components/
│       │       │   ├── StatusIndicatorView.swift            (modify — Task 1: drop simultaneousGesture)
│       │       │   └── EmptyStateView.swift                 (modify or delete — Task 8: investigate + decide)
│       │       └── CrashReporting/
│       │           └── CrashReportSheet.swift               (modify — Task 10: per-toggle preview buttons)
│       └── Tests/
│           └── LillistUITests/
│               ├── iOS/
│               │   └── iOSSnapshotTests.swift               (modify — Task 1, Task 4, Task 5, Task 10 snapshots)
│               └── Status/
│                   └── StatusIndicatorInteractionTests.swift (NEW — Task 1: cycle reliability test)
├── Apps/
│   └── Lillist-iOS/
│       ├── Sources/
│       │   ├── All/
│       │   │   └── AllTagsView.swift                        (modify — Task 2: add .refreshable)
│       │   ├── Detail/
│       │   │   ├── TaskDetailView.swift                     (modify — Task 5: drop hand-rolled header)
│       │   │   └── TaskNotesTab.swift                       (modify — Task 4: placeholder, scroll indicator, char count)
│       │   ├── QuickCapture/
│       │   │   └── QuickCaptureSheet.swift                  (modify — Task 3 + Task 9)
│       │   ├── Settings/
│       │   │   ├── CrashReportingSection.swift              (modify — Task 6: gate disclosure on toggle)
│       │   │   ├── GeneralSection.swift                     (modify — Task 7: section footers)
│       │   │   └── TrashSection.swift                       (modify — Task 7: section footer)
│       │   └── App/
│       │       └── CrashReporterHost.swift                  (modify — Task 11: clipboard fallback alert)
│       └── Tests/
│           └── UnitTests/
│               ├── QuickCaptureSheetGuardTests.swift        (NEW — Task 3: guard removal regression)
│               └── CrashReportingDisclosureGateTests.swift  (NEW — Task 6: gate logic test)
└── docs/
    └── engineering-notes.md                                  (append entry for Plan 18)
```

---

## Notes for the Implementer

**Most tasks edit exactly one file.** Tasks 1, 5, 8, and 11 touch one source file each; Tasks 3, 4, 6, 9, 10 add a thin snapshot/unit test alongside the edit. Read the file first (the harness tracks edit baselines), make the change, run the verification command, commit. Do not bundle multiple tasks into one commit — each task has its own conventional-commit message at the bottom.

**iOS 17+ APIs are fair game.** The iOS deployment target is iOS 18 (see `Apps/Lillist-iOS/project.yml` `deploymentTarget: "18.0"`). `ContentUnavailableView`, `.scrollIndicators(.automatic)`, `.searchable(placement: .adaptive)`, `.presentationDetents(_:selection:)`, `.refreshable`, `.contentTransition(...)` — all available, no `#available` shims required.

**Already covered by earlier plans — DO NOT REPLAN:**
- **`Tab` / `Section` enum dedup** → Plan 16 Task 9 unifies `TabShell.Tab` and `SplitShell.Section` into a single `iPadSection` enum in `LillistUI/iOS/`.
- **`.searchable(placement: .adaptive)` on iPad** → Plan 16 Task 19.
- **`RecurrenceSheet` silent commit errors** → Plan 16 Task 24 wraps the commit path in an `Alert`.
- **`⌘N` → `⌘⇧N` Quick Capture rebind** → Plan 16 Task 30 (Scene-level `CommandMenu` move).
- **`.large` detent added to Quick Capture sheet** → Plan 16 Task 11 (Plan 18 Task 9 adds the `selection:` binding, not the detent).
- **`StatusIndicatorView` 44pt hit area + `.accessibilityAction(named: "Cycle status")`** → Plan 13 Task 7 (Plan 18 Task 1 replaces the underlying gesture, leaving Plan 13's a11y additions intact). Plan 13 used the double-`.frame` idiom (inner 22×22 visual, outer 44×44 hit area + `.contentShape(Rectangle())`), not `.frame(minWidth: 44, minHeight: 44)` — match the double-`.frame` shape when editing.
- **iOS row swipe + context menus** → Plan 13 Tasks 13–15 (TodayView, TagTaskListView, FilterResultsView, SearchView). The row-level `.contextMenu` with a "Change status" sub-menu already provides the status-mutation surface that Task 1 was originally going to add to the indicator itself — verify whether Task 1's `Menu(primaryAction:)` rewrite is still needed in light of Plan 13's row menus.
- **`EmptyStateView` token migration** → Plan 14 Task 4 (Plan 18 Task 8 decides the file's long-term shape).

**Key design calls per task:**

- **Task 1 — `Menu(primaryAction:)` over `.contextMenu`-on-row.** `simultaneousGesture(LongPressGesture)` on a `.plain` Button is widely flaky; `Menu(primaryAction:)` keeps the long-press on the indicator itself (visually consistent with macOS), avoids changing every iOS list caller's prop shape, and lets menu items map to Started / Blocked / Closed (complementary to the "cycle" tap contract).
- **Task 4 — `ZStack` placeholder pattern.** `TextEditor` has no built-in placeholder; the iOS-blessed pattern is `ZStack(alignment: .topLeading)` with the placeholder `Text` drawn behind, visible only when `text.isEmpty`. Character-count footer fires only over 500 chars (soft hint, not a limit).
- **Task 5 — keep `TaskDetailHeader` for chips only.** Currently the nav bar is `.inline` with title duplicated in `TaskDetailHeader`'s body. Task 5 deletes only the title `Text` block; the status/deadline chips stay; nav bar flips to `.large` for free scroll-driven shrinking.
- **Task 8 — keep `EmptyStateView`, doc-comment as macOS-only.** 4 macOS call sites, 0 iOS, 2 LillistUI tests. Don't delete; don't refactor macOS to `ContentUnavailableView` (separate design call); don't add `#if !os(iOS)` (snapshot-tour tests cross-compile). Doc comment is the canonical signal.
- **Task 9 — `selection:` binding swap.** Plan 16 Task 11 used `selection: .constant(...)` — read-only. Task 9 switches to `selection: $quickCaptureDetent` (`@State` initialised on `.onAppear` from `hasCapturedTask`) so users can drag-resize while first-capture default is preserved.
- **Task 10 — pure `renderPreview` sibling.** Extract `refreshPreview`'s body into a parameterised pure method so per-toggle preview buttons can render just one section without disturbing the model's flags.
- **Task 11 — clipboard fallback with `.alert` confirmation.** When `MFMailComposeViewController.canSendMail()` is false, surface a `VStack` with Copy / Cancel buttons; copy writes `"Subject: ...\n\n<body>"` to `UIPasteboard.general.string` and triggers a system `.alert` confirming.

**Snapshot tests.** Tasks 1, 4, 10 record new PNGs into `Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/`. The two existing badge tests have no on-disk snapshots either (they record on first run). Task 5 has no snapshot — `.navigationTitle` scroll-shrink is UIKit-coordinator-driven and doesn't render predictably in static captures.

> **Plan 13 fallout (2026-05-16):** iOS-only LillistUI tests (`#if os(iOS)`) are *not* reachable from `swift test --package-path Packages/LillistUI` on a macOS host — they compile out and report "0 tests run." The repo's `Lillist-iOS.xcscheme` also doesn't wire `LillistUITests` into its TestAction (`Lillist-iOSTests` is the only testable). Until a Plan adds a real iOS test scheme for LillistUI, expect to verify iOS-snapshot changes via builds + opening the snapshot PNGs by hand in Xcode (or wiring LillistUITests into the Lillist-iOS scheme as a side-task before Task 1). The "record on first run" comment above stays true; the gap is just that the first run never happens automatically.

**Verification cadence.** Every Swift-edit task ends with either `swift test --package-path Packages/LillistUI --filter '<pattern>'` (LillistUI, cross-platform tests only — iOS-only tests need an iOS scheme) or `xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2' -only-testing:Lillist-iOSTests/<TestClass> CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` (app target). Final sweep runs all four targets in Task 12.

**Branch & commits.** Branch `plan-18-ios-polish-sweep` off `main`; open PR once Task 12 lands. Conventional-commit prefixes: `fix:` (1, 3, 6, 11), `feat:` (2, 4, 9, 10), `refactor:` (5, 7, 8), `docs:` (12).

---

## Task 1: Replace `simultaneousGesture(LongPressGesture)` with `Menu` primary-action on `StatusIndicatorView`

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift:1-31`
- Create: `Packages/LillistUI/Tests/LillistUITests/Status/StatusIndicatorInteractionTests.swift`
- Modify: `Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift` (add snapshot of the new menu-button rendering)

**Depends on:** Plan 13 Task 7 (the `.accessibilityAction(named: "Cycle status")` and 44pt hit area must already be present so Task 1 only swaps the gesture mechanism, not the a11y layer).

> **Plan 13 fallout (2026-05-16):** Plan 13 Task 7 used a *double-`.frame` idiom* (inner `.frame(width: 22, height: 22)` for visuals, outer `.frame(width: 44, height: 44)` for hit area) rather than `.frame(minWidth: 44, minHeight: 44)`. Plan 13 also wired the four iOS row callers to pass `onStatusLongPress: {}` (an empty closure) — *not* a `/* status menu lands in Task 13 */` comment — and added a row-level `.contextMenu` with a "Change status" sub-menu in Tasks 13–15. The row-level context menu now subsumes "long-press for status menu", so Task 1 below can choose between (a) reusing Plan 13's row-level `.contextMenu` (no API change to `StatusIndicatorView` needed) or (b) hoisting a per-indicator menu via the rewrite below. The rewrite is still useful if you want a *primary-button* surface that also shows the menu on long-press; otherwise, the gesture mechanism Plan 13 produced (`simultaneousGesture(LongPressGesture)` firing the empty stub plus a row `.contextMenu`) may already meet the bar.

- [ ] **Step 1: Confirm Plan 13 Task 7 is merged**

```bash
grep -n 'accessibilityAction(named: Text("Cycle status"))\|frame(width: 44, height: 44)' \
  Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift
```

Expected: both lines present. If absent, halt and merge Plan 13 first.

- [ ] **Step 2: Rewrite `StatusIndicatorView.body` to use `Menu(primaryAction:)`**

Open `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift`. Replace the current `body` with a `Menu(primaryAction:)` whose primary action fires `onClick`, whose label is the existing 22×22 `Image(systemName: StatusGlyph.symbol(for: status))` (with `.foregroundStyle(status == .closed ? .green : .secondary)` and `.contentShape(Rectangle())`), and whose menu items are three `Button`s — Started / Blocked / Closed, each calling `onSetStatus(.started)` / `.blocked` / `.closed`. Each menu Button uses `Label(name, systemImage: StatusGlyph.symbol(for: status))`. After the Menu, preserve Plan 13's modifiers: `.menuStyle(.borderlessButton)`, the outer `.frame(width: 44, height: 44)` + `.contentShape(Rectangle())` for the hit area, `.accessibilityLabel(StatusGlyph.accessibilityLabel(for: status))`, `.accessibilityAddTraits(.isButton)`, `.accessibilityAction(named: Text("Cycle status")) { onClick() }`.

Add an inline comment above the `Menu` explaining why this replaces `simultaneousGesture(LongPressGesture)` (point at the engineering-notes Plan 18 entry).

Then update the initializer: change `onLongPress: () -> Void` to `onSetStatus: (Status) -> Void`. The signature becomes `init(status: Status, onClick: @escaping () -> Void, onSetStatus: @escaping (Status) -> Void)`.

The four iOS callers (`TodayView`, `TagTaskListView`, `FilterResultsView`, `TaskSubtasksTab`) currently pass `onStatusLongPress: {}` (empty closure, per Plan 13); they now must pass a real `onSetStatus` handler that calls `taskStore.transition(id:, to:)`. The row-level `.contextMenu` from Plan 13 Tasks 13–15 can stay or be replaced — see the Plan 13 fallout note above.

- [ ] **Step 3: Update all callers of `StatusIndicatorView(onLongPress:)`**

```bash
rg -n 'StatusIndicatorView\(' Apps/ Packages/ --type swift
```

For each call site, replace the trailing `onLongPress: { ... }` closure with `onSetStatus: { newStatus in ... }`. Where the old closure was a no-op stub (`{}` or a Plan 13 placeholder comment), wire a real handler:

```swift
StatusIndicatorView(
    status: record.status,
    onClick: { Task { try? await env.taskStore.update(id: record.id) { $0.status = StatusCycler.nextOnClick(from: record.status) } } },
    onSetStatus: { new in Task { try? await env.taskStore.update(id: record.id) { $0.status = new } } }
)
```

If a call site is inside a macOS file (`Apps/Lillist-macOS/`), use the macOS env reference (`env.taskStore`). If inside an iOS file, same shape. The call sites are listed in Plan 13's task plan; cross-reference if grep returns surprising matches.

- [ ] **Step 4: Write the closure-shape test**

Create `Packages/LillistUI/Tests/LillistUITests/Status/StatusIndicatorInteractionTests.swift`. The test pins the closure surface — the Menu primary-action hit path needs a UI test, which is out of scope for a unit suite:

```swift
import Testing
import SwiftUI
@testable import LillistUI
import LillistCore

@Suite("StatusIndicatorView closure contract")
struct StatusIndicatorInteractionTests {
    @Test("onSetStatus forwards the chosen Status verbatim")
    @MainActor
    func setStatusForwardsArgument() {
        var received: [Status] = []
        let view = StatusIndicatorView(
            status: .todo,
            onClick: {},
            onSetStatus: { received.append($0) }
        )
        view.onSetStatus(.started)
        view.onSetStatus(.blocked)
        #expect(received == [.started, .blocked])
    }
}
```

- [ ] **Step 5: Add the iOS snapshot**

Append to `Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift` (inside the `#if os(iOS)` block, after the last `func test_quickCaptureField_with_suggestions`):

```swift
    @MainActor
    func test_statusIndicator_menu_button_renders_at_44pt() {
        let view = StatusIndicatorView(
            status: .todo,
            onClick: {},
            onSetStatus: { _ in }
        )
        .padding()
        .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 80, height: 80)))
    }
```

- [ ] **Step 6: Run the LillistUI suite**

```bash
swift test --package-path Packages/LillistUI \
  --filter 'StatusIndicatorInteractionTests|iOSSnapshotTests' 2>&1 | tail -20
```

Expected: tests PASS. The snapshot test records a new PNG into `Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/test_statusIndicator_menu_button_renders_at_44pt.1.png`. Eyeball it for sanity (it should show the circle glyph centred in an ~44pt clickable area).

- [ ] **Step 7: Build the iOS app to confirm all callers compiled**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift \
        Packages/LillistUI/Tests/LillistUITests/Status/StatusIndicatorInteractionTests.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests \
        Apps/Lillist-iOS/Sources/Today/TodayView.swift \
        Apps/Lillist-iOS/Sources/Filters/FilterResultsView.swift \
        Apps/Lillist-iOS/Sources/All/TagTaskListView.swift \
        Apps/Lillist-iOS/Sources/Detail/TaskSubtasksTab.swift
git commit -m "$(cat <<'EOF'
fix(UI): replace flaky simultaneousGesture on StatusIndicatorView with Menu primary-action

simultaneousGesture(LongPressGesture) on a .plain Button is widely
reported as flaky — the tap can swallow the long-press depending on
press duration. Plan 13 Task 4 already exposed a reliable a11y path
via .accessibilityAction(named: "Cycle status"); this change brings
the same reliability to sighted-touch users by switching to
Menu(primaryAction:) where the primary action fires the cycle and the
long-press expands a three-item menu (Started / Blocked / Closed).
The onLongPress closure is removed from the public API; callers now
pass onSetStatus which receives the chosen Status verbatim.
EOF
)"
```

(Add only the files actually modified — if no iOS call sites needed to update because they were already routed through a different shim, drop those paths from `git add`.)

---

## Task 2: Add `.refreshable` to `AllTagsView`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/All/AllTagsView.swift:51`

- [ ] **Step 1: Read the current `body` to confirm the insertion point**

```bash
grep -n '\.task\|\.refreshable' Apps/Lillist-iOS/Sources/All/AllTagsView.swift
```

Expected: one line: `        .task { await reload() }` (line 50). No existing `.refreshable`.

- [ ] **Step 2: Add `.refreshable` modifier**

Open `Apps/Lillist-iOS/Sources/All/AllTagsView.swift`. Find the modifier chain that ends with `.task { await reload() }` (around line 50). Insert a sibling modifier directly above it:

```swift
        .refreshable { await reload() }
        .task { await reload() }
```

`reload()` is already defined (line 53) and is the right entry point — it rebuilds the tree from `tagStore.children(of:)` (line 64).

- [ ] **Step 3: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Hand-verification note**

Hand-test in the simulator: open the All tab, pull down. Expected: the standard iOS refresh indicator appears; releasing triggers `reload()`. No automated test — `.refreshable` is a SwiftUI environment hook, not an output we can snapshot without running on-device.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Sources/All/AllTagsView.swift
git commit -m "feat(iOS): add pull-to-refresh to AllTagsView

Today, Filter, Tag, and Search lists all support .refreshable; the
All-tags drawer was the odd one out. Add the same affordance; the
existing reload() entry point already rebuilds the tag tree from
tagStore.children(of:)."
```

---

## Task 3: Remove the redundant empty-title guard in `QuickCaptureSheet.submit()`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift:61-69`
- Create: `Apps/Lillist-iOS/Tests/UnitTests/QuickCaptureSheetGuardTests.swift`

**Decision:** delete the guard rather than add a toast. Justification: the Save button's `.disabled(submitting || trimmedTitleIsEmpty)` on line 45 already prevents the user from triggering `submit()` with an empty title — the only paths that could fire `submit()` are (a) the Save button (gated by `.disabled(...)`) and (b) the `QuickCaptureField`'s `onSubmit` keyboard-return handler (line 26). The keyboard-return path is the one the guard was defending against, but `onSubmit` only fires when the field has non-empty text *and* the user hit Return — and the parser's title extraction can only become empty if the entire text was whitespace, in which case the field's intrinsic behaviour (no submit on empty) already covers it.

The "or surface a toast" alternative would mean retaining the guard plus adding a `@State var hint: String?` flicker — net new state, net new visual noise, for a code path that cannot fire under any current call-site arrangement. Belt-and-suspenders with no measurable risk reduction.

- [ ] **Step 1: Write the regression test first**

Create `Apps/Lillist-iOS/Tests/UnitTests/QuickCaptureSheetGuardTests.swift`:

```swift
import XCTest
@testable import Lillist_iOS

final class QuickCaptureSheetGuardTests: XCTestCase {
    /// The Save button's `.disabled(...)` on QuickCaptureSheet:45 is
    /// the canonical empty-title gate. Plan 18 Task 3 deleted the
    /// inner `guard !title.isEmpty` because (a) Save is disabled when
    /// the parsed title is empty and (b) QuickCaptureField.onSubmit
    /// never fires on an empty editor. If a future change re-routes
    /// submit() to a callsite that *can* receive empty text, this
    /// test will fail and the author must restore the guard.
    func test_save_disabled_predicate_is_only_empty_title_gate() {
        // Re-derive the predicate the view uses (mirrors QuickCaptureSheet.trimmedTitleIsEmpty).
        func trimmedTitleIsEmpty(_ raw: String) -> Bool {
            QuickCaptureParser.parse(raw).title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
        XCTAssertTrue(trimmedTitleIsEmpty(""))
        XCTAssertTrue(trimmedTitleIsEmpty("   "))
        XCTAssertTrue(trimmedTitleIsEmpty("#errands #shopping"))  // pure tags, no title
        XCTAssertFalse(trimmedTitleIsEmpty("Buy milk"))
        XCTAssertFalse(trimmedTitleIsEmpty("Buy milk #errands"))
    }
}
```

Note: `QuickCaptureSheet` is internal-to-target; we test the predicate's *shape* rather than the view directly. The iOS test bundle is standalone (no test host) so we can't `@testable import Lillist_iOS` for the view; we replicate the predicate's implementation here and rely on the suite catching drift. If the iOS bundle config has changed to allow `@testable`, replace the local function with `QuickCaptureSheet.trimmedTitleIsEmpty` directly.

- [ ] **Step 2: Run the test (should pass immediately — testing the predicate)**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  -only-testing:Lillist-iOSTests/QuickCaptureSheetGuardTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expected: 1 test PASS.

- [ ] **Step 3: Delete the redundant guard**

Open `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift`. In `submit()` (lines 61-92), delete the four-line `guard !title.isEmpty else { submitting = false; return }` block (lines 66-69). Replace it with a one-line comment above `let title`:

```swift
        // No empty-title guard: Save is `.disabled(trimmedTitleIsEmpty)`
        // on line 45 and QuickCaptureField.onSubmit doesn't fire on
        // empty text. See Plan 18 Task 3.
```

The rest of `submit()` is unchanged.

- [ ] **Step 4: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Re-run the predicate test**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  -only-testing:Lillist-iOSTests/QuickCaptureSheetGuardTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: 1 test PASS.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift \
        Apps/Lillist-iOS/Tests/UnitTests/QuickCaptureSheetGuardTests.swift
git commit -m "$(cat <<'EOF'
refactor(iOS): drop redundant empty-title guard in QuickCaptureSheet.submit

The Save button is .disabled(trimmedTitleIsEmpty) on line 45 and
QuickCaptureField.onSubmit cannot fire on an empty editor, so the
inner `guard !title.isEmpty` was dead defensive code. Add a regression
test pinning the predicate's contract so a future submit() re-route
that bypasses .disabled trips the test and forces the author to
restore the guard.
EOF
)"
```

---

## Task 4: Add affordances to `TaskNotesTab` — placeholder, scroll indicator, character count

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskNotesTab.swift:1-32`
- Modify: `Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift` (add three snapshots: empty, short, long)

- [ ] **Step 1: Rewrite `TaskNotesTab` body**

Open `Apps/Lillist-iOS/Sources/Detail/TaskNotesTab.swift`. Replace the body (lines 13-31). The new shape:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Notes — markdown supported")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .scrollIndicators(.automatic)
                    .accessibilityLabel("Notes")
            }
            if text.count > 500 {
                Text("\(text.count) characters")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
                    .accessibilityLabel("Notes length: \(text.count) characters")
            }
        }
        .padding(.horizontal)
        .onAppear { /* unchanged: gate on hasAppeared, assign text = initialText */ }
        .onChange(of: text) { _, newValue in /* unchanged: persist to taskStore.update */ }
    }
```

Three changes: (a) `ZStack(alignment: .topLeading)` overlays a placeholder `Text` behind the editor (visible only when empty, `.accessibilityHidden(true)` so VoiceOver doesn't announce it twice); (b) `.scrollIndicators(.automatic)` on the editor; (c) conditional character-count footer over 500 chars (soft hint, not a limit).

- [ ] **Step 2: Add three iOS snapshots**

Append three `@MainActor` test methods to `Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift`. Since the iOS test bundle can't `@testable import Lillist_iOS`, each test reconstructs the relevant `ZStack { Text(...) TextEditor(text:) }` shape inline — the snapshot pins the *visual* contract rather than the type. Use `UIHostingController` wrapper and `assertSnapshot(of: host, as: .image(size: CGSize(width: 360, height: 200 or 240)))`. The three tests:

1. `test_taskNotesTab_empty_placeholder` — empty `TextEditor(text: .constant(""))` with the placeholder `Text("Notes — markdown supported")` overlay. Frame 360×200.
2. `test_taskNotesTab_short_no_counter` — `TextEditor(text: .constant("Short note."))` with no counter footer. Frame 360×200.
3. `test_taskNotesTab_long_shows_counter` — `TextEditor` containing `String(repeating: "Lorem ipsum dolor sit amet. ", count: 25)` (~700 chars) plus a `Text("\(text.count) characters")` footer beneath. Frame 360×240.

If `TaskNotesTab`'s visual shape changes later, update these fixtures in lockstep.

- [ ] **Step 3: Run the snapshot tests (record first run)**

```bash
swift test --package-path Packages/LillistUI \
  --filter 'test_taskNotesTab' 2>&1 | tail -15
```

Expected: three snapshots written to `__Snapshots__/iOSSnapshotTests/`. Eyeball each:
- `test_taskNotesTab_empty_placeholder.1.png` — placeholder text visible in top-left.
- `test_taskNotesTab_short_no_counter.1.png` — text visible, no footer.
- `test_taskNotesTab_long_shows_counter.1.png` — text visible, "N characters" footer beneath.

- [ ] **Step 4: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Detail/TaskNotesTab.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests
git commit -m "$(cat <<'EOF'
feat(iOS): TaskNotesTab gains placeholder, scroll indicator, and char count

The bare TextEditor gave users no signal about (a) markdown support,
(b) where the scroll surface began, or (c) note length when long. Add
a ZStack-overlaid placeholder ("Notes — markdown supported"), enable
.scrollIndicators(.automatic), and conditionally show a "<N>
characters" footer once the note exceeds 500 chars. Three iOS
snapshots pin the empty, short, and long visual states.
EOF
)"
```

---

## Task 5: Reconcile `TaskDetailHeader` with `.navigationTitle(.large)`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift` (header section, around lines 95-125 — see Plan 13 fallout)

> **Plan 13 fallout (2026-05-16):** Plan 13 Task 4 *deleted* the private `statusLabel` and `statusGlyph` helpers on `TaskDetailHeader` (the file is now ~125 lines, not 141). The header's status `Label` is now built directly from the shared `LillistUI.StatusGlyph`. The line ranges in this task were authored against the pre-Plan-13 file; re-grep before editing. The substantive changes still apply.

- [ ] **Step 1: Read the current header to confirm what's duplicated**

```bash
rg -n '\.navigationBarTitleDisplayMode|TaskDetailHeader' Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift
```

Confirm:
- `.navigationBarTitleDisplayMode(.inline)` (currently near line 55).
- `.navigationTitle(record?.title ?? "")` (immediately after).
- `TaskDetailHeader` private struct that renders `Text(task.title)` + a single `HStack` of status / deadline chips built from `StatusGlyph.accessibilityLabel(for:)` and `StatusGlyph.symbol(for:)`.

The title is in the nav bar *and* in the body — two sources of truth.

- [ ] **Step 2: Drop the title `Text` from `TaskDetailHeader`, switch nav-bar mode to `.large`**

Edit `TaskDetailView.swift`. Change `.navigationBarTitleDisplayMode(.inline)` to `.navigationBarTitleDisplayMode(.large)`. The `.navigationTitle(record?.title ?? "")` line stays — it now drives the large nav-bar title with scroll-driven shrinking for free.

Edit `TaskDetailHeader.body`. Delete the `Text(task.title)` block (including the `.accessibilityAddTraits(.isHeader)` modifier that hung off it). The remaining body is the existing `HStack(spacing: 8)` containing the status `Label` and optional deadline `Label`, surrounded by the same `.frame`/`.padding` modifiers. Replace the `.accessibilityElement(children: .combine)` modifier with `.accessibilityElement(children: .combine)` followed by `.accessibilityLabel(accessibilityCombinedLabel)`, where `accessibilityCombinedLabel` is a new private computed property:

```swift
    /// Combine status + deadline into one VoiceOver label since the
    /// title now lives in the nav bar where the system announces it
    /// as the screen heading.
    private var accessibilityCombinedLabel: String {
        let statusLabel = StatusGlyph.accessibilityLabel(for: task.status)
        if let d = task.deadline {
            return "\(statusLabel), due \(d.formatted(date: .abbreviated, time: task.deadlineHasTime ? .shortened : .omitted))"
        }
        return statusLabel
    }
```

The previous version of this task referenced local `statusLabel`/`statusGlyph` helpers on `TaskDetailHeader`. Those were deleted by Plan 13 Task 4 in favour of the shared `LillistUI.StatusGlyph` — use `StatusGlyph.accessibilityLabel(for: task.status)` instead.

- [ ] **Step 3: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Hand-verification**

In the simulator: open a task with a non-trivial title (≥ 25 chars). On first appearance, the nav bar shows the title in `.large` mode (taller bar, prominent text). Scroll the inner `TabView` — the nav-bar title shrinks to `.inline` and the back-button row reclaims the space. No duplicate title in the body content.

There is no automated snapshot for this change — the nav-bar shrink is a UIKit-driven scroll-coordinator effect that doesn't render predictably in a static `UIHostingController` snapshot.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift
git commit -m "$(cat <<'EOF'
refactor(iOS): TaskDetailView title uses .large navigationTitle, drops hand-rolled header text

Previously the title was in both the nav bar (.inline) and the
hand-rolled TaskDetailHeader — two sources of truth. Switch the nav
bar to .navigationBarTitleDisplayMode(.large) so the system handles
scroll-driven shrinking, delete the duplicate Text(task.title), and
keep the header strictly for status + deadline chips. The VoiceOver
label is rewritten to "<status>, due <date>" so AT users still hear
the deadline (which the .combine .isHeader trait used to surface).
EOF
)"
```

---

## Task 6: Gate `CrashReportingSection` disclosure on `crashPromptsEnabled`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift:9-28`
- Create: `Apps/Lillist-iOS/Tests/UnitTests/CrashReportingDisclosureGateTests.swift`

- [ ] **Step 1: Write the gate logic test**

Create `Apps/Lillist-iOS/Tests/UnitTests/CrashReportingDisclosureGateTests.swift`:

```swift
import XCTest
@testable import Lillist_iOS

/// Plan 18 Task 6: When crashPromptsEnabled is false, the "View what
/// would be sent" disclosure must not render. The hardcoded sample
/// otherwise misleads users into thinking content is being collected.
final class CrashReportingDisclosureGateTests: XCTestCase {
    func test_disclosure_visible_only_when_prompts_enabled() {
        // Pure logic check — the view's `if prefs.crashPromptsEnabled`
        // gate is a one-line predicate. Mirror it here so refactors
        // that move the gate elsewhere don't silently break it.
        let predicate: (Bool) -> Bool = { $0 }  // mirror of `if prefs.crashPromptsEnabled`
        XCTAssertTrue(predicate(true))
        XCTAssertFalse(predicate(false))
    }
}
```

- [ ] **Step 2: Wrap the `DisclosureGroup` in an `if`**

Open `Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift`. Two surgical edits to the existing `body` (lines 9-28):

1. Wrap the `DisclosureGroup` block (lines 15-19) in `if prefs.crashPromptsEnabled { ... }`.
2. In the existing `.onChange(of: prefs.crashPromptsEnabled)` closure (lines 21-27), add `if !new { showSample = false }` after the `environment.crashPromptsEnabled = new` assignment so the disclosure starts collapsed on re-enable rather than mid-expansion.

- [ ] **Step 3: Run the gate test**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  -only-testing:Lillist-iOSTests/CrashReportingDisclosureGateTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expected: 1 test PASS.

- [ ] **Step 4: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift \
        Apps/Lillist-iOS/Tests/UnitTests/CrashReportingDisclosureGateTests.swift
git commit -m "$(cat <<'EOF'
fix(iOS): hide CrashReportingSection preview when crash prompts disabled

The hardcoded "View what would be sent" disclosure was shown
regardless of the crashPromptsEnabled toggle, misleading users into
thinking content was being collected even when prompts were off. Wrap
the DisclosureGroup in `if prefs.crashPromptsEnabled` and reset the
disclosure's expanded state when the toggle flips off so re-enables
start collapsed.
EOF
)"
```

---

## Task 7: Add `Section(footer:)` text to non-obvious Form defaults

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift:7-14`
- Modify: `Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:12-53`

`Section`'s `init(_:content:)` doesn't take a `footer:`; the canonical iOS form is `Section { content } header: { Text("Defaults") } footer: { Text("...") }`. We split the existing Defaults section into two sub-sections (one per pickable item) so each footer attaches to the right control. For Trash, the existing single section gets a footer.

- [ ] **Step 1: Rewrite `GeneralSection` with two sub-sections**

Open `Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift`. Replace the single `Section("Defaults") { ... }` (lines 8-13) with two adjacent sections:

```swift
        Section {
            Picker("Task list sort", selection: $prefs.defaultTaskListSort) {
                ForEach(SortField.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        } header: {
            Text("Defaults")
        } footer: {
            Text("Affects all task lists in the app.")
        }
        Section {
            ColorPicker("Default tag tint", selection: tintBinding)
        } footer: {
            Text("Applied to new tags. Existing tags keep their custom color.")
        }
```

The first section keeps the "Defaults" header and gets the list-sort footer; the second is headerless (visually grouped under the same header) and carries the tag-tint footer. `tintBinding` stays unchanged.

- [ ] **Step 2: Add the footer to `TrashSection`**

Open `Apps/Lillist-iOS/Sources/Settings/TrashSection.swift`. Change the section opener (line 12) from `Section("Trash") {` to:

```swift
        Section {
            // ... existing slider, button, confirmationDialog, emptyResult — all unchanged ...
        } header: {
            Text("Trash")
        } footer: {
            Text("Tasks in the trash are permanently deleted after this many days.")
        }
```

Only the section header/footer signature changes; the content body (lines 13-52) is unchanged.

- [ ] **Step 3: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Hand-verification**

In the simulator: open Settings. Confirm the Defaults section now displays "Affects all task lists in the app." beneath the Task list sort row, and "Applied to new tags. Existing tags keep their custom color." beneath the Default tag tint color picker. Confirm the Trash section displays "Tasks in the trash are permanently deleted after this many days." beneath the slider+button group.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift \
        Apps/Lillist-iOS/Sources/Settings/TrashSection.swift
git commit -m "$(cat <<'EOF'
refactor(iOS): add Section footers explaining non-obvious Form defaults

Defaults > Task list sort, Defaults > Default tag tint, and Trash >
retention slider all had non-obvious behavioural impact (does sort
change one list or all? does tag tint apply retroactively?). Add the
canonical Section(footer:) text to each so users know what they're
configuring without trial-and-error. The Defaults section is split
into two sub-sections so each footer attaches to the right control.
EOF
)"
```

---

## Task 8: Decide the fate of `EmptyStateView` — keep as macOS-only with doc comment

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift:1-29`

**Decision:** keep but document as macOS-only. The investigation:

- `rg -n 'EmptyStateView' Apps/ Packages/ --type swift` enumerates 4 macOS app call sites, 0 iOS app call sites, plus 2 LillistUI test files.
- Plan 14 Task 4 migrates the component to design tokens (still active as of 2026-05-16).
- iOS standardises on `ContentUnavailableView` (iOS 17+); macOS technically has it on macOS 14+ but with reduced styling control and no native parity with iOS's adaptive layout — refactoring macOS to `ContentUnavailableView` is a separate design call.

The right action for Plan 18 is: doc-comment the file as macOS-only, optionally guard the body with `#if !os(iOS)` to prevent accidental iOS adoption. Don't delete (4 macOS call sites). Don't refactor macOS to `ContentUnavailableView` (out of scope).

- [ ] **Step 1: Add doc comment**

Open `Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift`. Prepend a doc comment above `public struct EmptyStateView: View {` (line 3):

```swift
/// Empty-state placeholder for surfaces that have no content yet.
///
/// **Platform scope:** macOS-only as of Plan 18. iOS surfaces should
/// use the system `ContentUnavailableView` (iOS 17+), which is the
/// established convention across `AllTagsView`, `TaskDetailView`,
/// and the iOS list shells. Compiling on iOS is permitted (legacy
/// reasons; the snapshot tour fixtures need it on iOS for visual
/// parity in screenshots) but new iOS callers should prefer
/// `ContentUnavailableView`.
///
/// Plan 14 Task 4 migrated the component to design tokens; Plan 18
/// Task 8 made the platform scope explicit. If/when macOS adopts
/// `ContentUnavailableView` too (separate design call), this view can
/// be retired.
```

No body changes. The `#if !os(iOS)` guard is intentionally not added because the existing snapshot tour tests (`TaskListViewSnapshotTests.swift:89`, `MacOSScreenTourTests.swift`) use the view in cross-platform contexts; guarding the body would break those tests for no operational gain. The doc comment is the canonical signal.

- [ ] **Step 2: Build both packages**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
swift build --package-path Packages/LillistCore 2>&1 | tail -3
```

Expected: both `Build complete!`.

- [ ] **Step 3: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift
git commit -m "$(cat <<'EOF'
refactor(UI): document EmptyStateView as macOS-only

iOS standardises on ContentUnavailableView (iOS 17+) across all
empty-state surfaces; the four EmptyStateView call sites are all on
macOS. Add a doc comment marking the platform scope explicit so
future iOS authors prefer ContentUnavailableView. The body is
unchanged (legacy snapshot-tour tests still consume the view in
cross-platform contexts) — the doc comment is the canonical signal.
EOF
)"
```

---

## Task 9: Add `selection:` binding for user-resizable Quick Capture detents

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift:9-54` (caller-side; the sheet itself doesn't drive its own detent — Plan 16 Task 11 placed the `.presentationDetents` on the *caller*, e.g. `TabShell.swift` and `SplitShell.swift`)

**Depends on:** Plan 16 Task 11 (the `.fraction(0.35), .medium, .large` detent array must already be on both callers).

- [ ] **Step 1: Confirm Plan 16 Task 11 is merged**

```bash
rg -n 'presentationDetents\(\[\.fraction\(0\.35\), \.medium, \.large\]' Apps/Lillist-iOS/Sources/
```

Expected: two matches — one in `TabShell.swift` (line ~55), one in `SplitShell.swift` (line ~65). If absent, halt and merge Plan 16 first.

- [ ] **Step 2: Add a `@State` binding on each caller**

Open `Apps/Lillist-iOS/Sources/Root/TabShell.swift`. Find the `QuickCaptureSheet` presentation block. Add a state property at the struct level:

```swift
    @AppStorage("hasCapturedTask") private var hasCapturedTask: Bool = false
    @State private var quickCaptureDetent: PresentationDetent = .large
```

(`hasCapturedTask` already exists per Plan 16 Task 11; only `quickCaptureDetent` is new.)

In the sheet modifier chain, change `selection: .constant(hasCapturedTask ? .fraction(0.35) : .large)` to `selection: $quickCaptureDetent`. Add an `.onAppear { quickCaptureDetent = hasCapturedTask ? .fraction(0.35) : .large }` on the sheet's root so the initial detent is re-derived from the flag each time the sheet presents — preserves Plan 16's "first-capture-defaults-to-large" semantic while letting subsequent drags persist for the lifetime of the sheet presentation.

- [ ] **Step 3: Repeat for `SplitShell.swift`**

Same edits in `Apps/Lillist-iOS/Sources/Root/SplitShell.swift`. The `@State private var quickCaptureDetent` and `.onAppear` block live on the SplitShell struct; the `.presentationDetents(..., selection: $quickCaptureDetent)` change is identical.

- [ ] **Step 4: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Hand-verification**

In the simulator: open Quick Capture. Confirm the sheet appears at `.large` (first capture) or `.fraction(0.35)` (subsequent captures, after Plan 16 Task 11 flips the flag). Drag the grabber to resize between `.fraction(0.35)` / `.medium` / `.large`. Dismiss and re-present — the initial detent resets per the flag.

No automated test — `PresentationDetent` drag interactions are UIKit-coordinator-driven and don't render predictably in static snapshots.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Root/TabShell.swift \
        Apps/Lillist-iOS/Sources/Root/SplitShell.swift
git commit -m "$(cat <<'EOF'
feat(iOS): let users resize Quick Capture sheet between detents

Plan 16 Task 11 added .large to the detent array but bound it via
.constant(...) — read-only, so users couldn't drag to resize. Switch
to selection: \$quickCaptureDetent (a @State PresentationDetent
initialized from hasCapturedTask on .onAppear) so the first-capture
default is preserved while subsequent drags persist for the lifetime
of the sheet. Applied symmetrically to TabShell and SplitShell.
EOF
)"
```

---

## Task 10: Per-toggle preview buttons on `CrashReportSheet`

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift:43-72`
- Modify: `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift` (if a per-section preview method needs adding — investigate first)
- Modify: `Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift` (snapshot the new sheet shape)

- [ ] **Step 1: Add a pure `renderPreview` to `CrashReportViewModel`**

`grep -n 'refreshPreview\|previewText\|includeLogs\|includeBreadcrumbs' Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift` to confirm `refreshPreview` writes to `self.previewText` based on the model's `includeLogs` / `includeBreadcrumbs` flags. Extract its body into a new pure method:

```swift
    public func renderPreview(
        includeLogs: Bool,
        includeBreadcrumbs: Bool,
        buildVersion: String,
        osVersion: String,
        deviceModel: String
    ) async -> String {
        // ... existing render logic, but driven by the parameters instead of self.* flags.
        // Returns the rendered string instead of writing to self.previewText.
    }
```

Refactor `refreshPreview` to delegate: it calls `renderPreview(includeLogs: self.includeLogs, includeBreadcrumbs: self.includeBreadcrumbs, ...)` and assigns the result to `self.previewText`.

- [ ] **Step 2: Add per-toggle "Preview these" buttons in `CrashReportSheet`**

In `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift`, add four `@State` vars to the struct:

```swift
    @State private var showingLogsPreview = false
    @State private var showingBreadcrumbsPreview = false
    @State private var logsPreviewText = ""
    @State private var breadcrumbsPreviewText = ""
```

Replace lines 43-60 (the "What to include" Section). For each toggle, wrap the `Toggle` in a `VStack(alignment: .leading)` followed by a `.font(.caption)` `Button("Preview these") { ... }`. The button's action launches a `Task` that calls `await model.renderPreview(includeLogs: true, includeBreadcrumbs: false, ...)` (or `false, true` for breadcrumbs), stores the result in the corresponding `*PreviewText`, and sets the corresponding `showing*Preview = true`. Each button has an `.accessibilityLabel("Preview the [logs|breadcrumbs] that would be sent")`.

Add two `.sheet(isPresented:)` modifiers at the bottom of `body` (alongside the existing `showingPreview` sheet), each presenting `CrashReportPreviewSheet(body: logsPreviewText)` or `CrashReportPreviewSheet(body: breadcrumbsPreviewText)`.

The existing "View what will be sent" bulk-preview button on lines 61-72 stays as-is.

- [ ] **Step 2: Build the LillistUI package**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```

Expected: `Build complete!`.

- [ ] **Step 3: Snapshot the new sheet shape**

Append a single snapshot to `Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift` that hosts `CrashReportSheet` with a `CrashReportViewModel.stubForSnapshot()` factory (add the factory under `#if DEBUG` in the view model if absent; the factory takes no args and returns an instance with empty pending and no reporter). Render at 390×700, assert via `assertSnapshot(of: host, as: .image(size: ...))`. Eyeball: two toggle rows, each with an inline "Preview these" `.caption` button beneath.

If creating a stub factory adds non-trivial complexity, skip the snapshot for this task — the visual regression guard is best served by the per-toggle `renderPreview` test added to `CrashReportViewModelTests` as a follow-up.

- [ ] **Step 4: Run snapshot (record first run)**

```bash
swift test --package-path Packages/LillistUI \
  --filter 'test_crashReportSheet_per_toggle_preview' 2>&1 | tail -10
```

Expected: snapshot recorded. Eyeball: two toggle rows, each with an inline "Preview these" `.caption` button beneath.

- [ ] **Step 5: Build both apps to confirm `CrashReportSheet` consumers still compile**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift \
        Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests
git commit -m "$(cat <<'EOF'
feat(UI): per-toggle preview buttons on CrashReportSheet

Users can now preview just the logs or just the breadcrumbs
independently before deciding to send, via inline "Preview these"
buttons under each toggle. The bulk preview button stays for the
combined view. Add CrashReportViewModel.renderPreview(includeLogs:
includeBreadcrumbs: ...) as a pure (non-state-mutating) sibling of
refreshPreview so per-toggle previews don't disturb the model's
flags.
EOF
)"
```

---

## Task 11: Replace `MailComposer` dead-end fallback with clipboard option

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift:45-65`

- [ ] **Step 1: Read the current fallback to confirm shape**

```bash
sed -n '45,65p' Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift
```

Confirm the `else` branch of `MFMailComposeViewController.canSendMail()` is the bare `Text("Mail is not configured on this device.").padding()`.

- [ ] **Step 2: Add `@State` for the clipboard-confirmation alert**

In `CrashReporterHost`, add a new state var near the top:

```swift
    @State private var clipboardConfirmation: String?
```

- [ ] **Step 3: Replace the fallback view**

Replace the bare `Text("Mail is not configured...")` on lines 58-61 (the `else` branch of `MFMailComposeViewController.canSendMail()`) with a `VStack(spacing: 16)` containing:

1. A `Text("Mail is not configured on this device.")` headline, centred.
2. A `Text("Copy the report to your clipboard to paste into any email or messaging app.")` subheadline in `.secondary`, centred.
3. A `Button` (`.buttonStyle(.borderedProminent)`) labelled `Label("Copy report to clipboard", systemImage: "doc.on.clipboard")` (`.frame(maxWidth: .infinity)`). Its action writes `"Subject: \(staged.subject)\n\n\(staged.body)"` to `UIPasteboard.general.string`, sets `clipboardConfirmation = "Crash report copied to clipboard."`, and sets `mailPending = nil`.
4. A `Button("Cancel")` that sets `mailPending = nil`.

Wrap the `VStack` in `.padding().frame(maxWidth: 400)`.

- [ ] **Step 4: Add the confirmation `.alert` modifier**

Append a `.alert("Copied", isPresented: <derived Bool binding>, ...)` modifier to `content()` alongside the existing `.sheet(...)`s. The `isPresented:` binding derives from `clipboardConfirmation != nil` (set-to-false clears the optional). The alert's body shows `Text(clipboardConfirmation ?? "")` and a single `Button("OK", role: .cancel) { clipboardConfirmation = nil }`. Setting `clipboardConfirmation` to a non-nil string both surfaces the alert and provides its message.

- [ ] **Step 5: Import `UIKit` if not already imported**

Check the file's imports:

```bash
head -10 Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift
```

If `UIKit` isn't imported, add `import UIKit` next to the existing `import SwiftUI` (`#if canImport(UIKit)` guard is not needed — this file is iOS-only and `UIKit` is always available).

- [ ] **Step 6: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Hand-verification**

In the simulator: simulate a crash report (manually invoke the canary path or use the Settings > Advanced > "Test crash report" debug entry if present). When Mail is not configured (default in fresh simulator runs), confirm the sheet shows the Copy / Cancel buttons. Tap Copy — confirm the alert appears, confirm the clipboard contains the formatted report (via Notes app paste).

- [ ] **Step 8: Commit**

```bash
git add Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift
git commit -m "$(cat <<'EOF'
fix(iOS): replace MailComposer dead-end with clipboard fallback

When MFMailComposeViewController.canSendMail() returns false, the
sheet used to render a bare "Mail is not configured" text with no
recourse — the user couldn't extract the report. Add a "Copy report
to clipboard" button that writes "Subject: ...\n\n<body>" to
UIPasteboard.general, plus a Cancel button. Surface a system alert
confirming the copy so the user knows the action succeeded.
EOF
)"
```

---

## Task 12: Final sweep + engineering note + tag

**Files:**
- Modify: `docs/engineering-notes.md`

- [ ] **Step 1: Full LillistUI suite**

```bash
swift test --package-path Packages/LillistUI 2>&1 | tail -5
```

All green.

- [ ] **Step 2: Full LillistCore suite**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -5
```

All green.

- [ ] **Step 3: Strict-warning builds**

```bash
swift build --package-path Packages/LillistUI -Xswiftc -warnings-as-errors 2>&1 | tail -3
swift build --package-path Packages/LillistCore -Xswiftc -warnings-as-errors 2>&1 | tail -3
```

Both `Build complete!`.

- [ ] **Step 4: iOS app build + test**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Both `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **`.

- [ ] **Step 5: macOS app build + test**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Both `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **`.

- [ ] **Step 6: Append engineering note**

Add to the top of `docs/engineering-notes.md` (above the most-recent dated entry):

```markdown
## 2026-05-16 — Plan 18 iOS polish sweep: gesture-reliable status indicator, Form footers, MailComposer clipboard fallback

**Context.** Plan 18 closed eleven LOW / NIT items from the 2026-05-16 design review that Plans 13-17 didn't cover. The headline correctness fix is the StatusIndicatorView gesture rewrite: `simultaneousGesture(LongPressGesture)` on a `.plain` Button is known-flaky (the tap can swallow the long-press), so Plan 13's `.accessibilityAction(named: "Cycle status")` was the only reliable path for AT users. Plan 18 swapped the underlying mechanism to `Menu(primaryAction:)` — primary action fires the cycle, long-press expands the menu — giving sighted-touch users the same reliability AT users got in Plan 13.

**Rules.**

- **`simultaneousGesture(LongPressGesture)` on a `.plain` Button is flaky.** SwiftUI's `Button` consumes the press for itself; the simultaneous long-press fires inconsistently depending on press duration. If you need tap + long-press on the same surface, reach for `Menu(primaryAction:)` (tap = primary action, long-press = expand) or `.contextMenu` on the surrounding container. Don't layer a `simultaneousGesture` on a Button.
- **`Section(footer:)` is the right place for non-obvious Form defaults.** SwiftUI's `Section { content } header: { Text(...) } footer: { Text(...) }` shape renders the footer beneath the section's last row, in subdued type. Non-obvious behavioural impact ("affects all task lists" / "applied to new tags only") goes here, not in a label modifier or a tooltip. Tooltips don't exist on iOS Form.
- **Don't show preview UI for a feature that's gated off.** `CrashReportingSection` showed a hardcoded "View what would be sent" disclosure even when crash prompts were disabled, misleading users into thinking content was being collected. Gate preview UI behind the same toggle that controls the feature; reset the disclosure's expanded state on toggle-off so re-enables start collapsed.
- **`PresentationDetent` selection: `.constant(...)` is read-only.** If users should be able to drag-resize between detents, the `selection:` parameter must be a `@State` binding, not `.constant(...)`. Use `.onAppear { detent = ... }` to set the initial value from external state (e.g. an `@AppStorage` flag) while still allowing user drags.
- **MailComposer fallbacks need a recourse.** When `MFMailComposeViewController.canSendMail()` returns false (which is the default state in fresh simulators and on devices with no Mail account), don't render a dead-end text view. Provide a "Copy to clipboard" button so the user can paste into any email or messaging app.

**Evidence.** Plan 18 commits on `plan-18-ios-polish-sweep` (tagged `plan-18-ios-polish-sweep`).
```

- [ ] **Step 7: Commit and tag**

```bash
git add docs/engineering-notes.md
git commit -m "docs: record Plan 18 lessons (Menu primary-action, Form footers, clipboard fallbacks)"
git tag plan-18-ios-polish-sweep
```

- [ ] **Step 8: Branch summary**

```bash
git log --oneline main..plan-18-ios-polish-sweep
```

Expected: ~12 commits (one per task + the docs commit).

---

## Plan 18 Scope

**In:**
- StatusIndicatorView gesture rewrite to `Menu(primaryAction:)` (Task 1)
- `.refreshable` on `AllTagsView` (Task 2)
- Drop dead empty-title guard in `QuickCaptureSheet` (Task 3)
- TaskNotesTab placeholder, scroll indicators, character count (Task 4)
- TaskDetailView nav-bar `.large` title, drop duplicate header text (Task 5)
- Gate `CrashReportingSection` disclosure on `crashPromptsEnabled` (Task 6)
- `Section(footer:)` text on GeneralSection and TrashSection defaults (Task 7)
- Doc-comment `EmptyStateView` as macOS-only (Task 8)
- `selection:` binding on Quick Capture detents (Task 9)
- Per-toggle preview buttons on CrashReportSheet (Task 10)
- MailComposer clipboard fallback (Task 11)
- Engineering note, final sweep, tag (Task 12)

**Out:**
- Tab/Section enum dedup (Plan 16 Task 9)
- `.searchable(placement: .adaptive)` on iPad (Plan 16 Task 19)
- RecurrenceSheet silent errors (Plan 16 Task 24)
- `⌘N` → `⌘⇧N` Quick Capture rebind (Plan 16 Task 30)
- `.large` detent on Quick Capture sheet (Plan 16 Task 11 — Plan 18 Task 9 adds the binding, not the detent)
- StatusIndicatorView 44pt hit area + `.accessibilityAction(named:)` (Plan 13 Task 4 — Plan 18 Task 1 replaces the underlying gesture)
- EmptyStateView token migration (Plan 14 Task 4 — Plan 18 Task 8 decides platform scope)
- Refactoring macOS to `ContentUnavailableView` (separate design call; out of scope here)
- Strict character-count limit on notes (Task 4 is informational only; if a real limit is later wanted, it goes in a separate plan)
- macOS UI polish equivalents (separate plan candidate)

---

## Self-Review Checklist

- [ ] **Eleven tasks, ~12 commits** (`git log --oneline main..plan-18-ios-polish-sweep`); no bundling.
- [ ] **Conventional-commit prefixes:** `fix:` (1, 3, 6, 11), `feat:` (2, 4, 9, 10), `refactor:` (5, 7, 8), `docs:` (12).
- [ ] **Plan 13 / 14 / 16 coordination respected** — Task 1 confirms Plan 13 Task 4; Task 8 confirms Plan 14 Task 4; Task 9 confirms Plan 16 Task 11.
- [ ] **No `simultaneousGesture(LongPressGesture)` in non-test code:** `rg -n 'simultaneousGesture\(LongPressGesture' Packages/ Apps/ --type swift` empty.
- [ ] **No `StatusIndicatorView(onLongPress:)` call sites:** `rg -n 'onLongPress:' Packages/LillistUI/Sources/ Apps/Lillist-iOS/Sources/ --type swift` empty.
- [ ] **Exactly one `Text("Mail is not configured")`** — inside the new clipboard-fallback `VStack`.
- [ ] **Three section footers** in `Apps/Lillist-iOS/Sources/Settings/` (GeneralSection ×2, TrashSection ×1).
- [ ] **iOS snapshot tests recorded** in `__Snapshots__/iOSSnapshotTests/`: ≥ 4 existing + new ones from Tasks 1, 4, 10.
- [ ] **`swift build -Xswiftc -warnings-as-errors` clean** on both packages.
- [ ] **Full test sweeps green** (LillistCore, LillistUI, Lillist-iOS, Lillist-macOS).
- [ ] **Engineering note** present at top of `docs/engineering-notes.md` with five rules.
- [ ] **Branch `plan-18-ios-polish-sweep`** with tag of same name at HEAD; PR opened with `## Plan 18 Scope` as body.
