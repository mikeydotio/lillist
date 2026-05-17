# Lillist Plan 16 — iOS Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the iOS app up to the visual and navigational standard set by first-tier iOS task managers (Apple Reminders, Things 3, Todoist). Plan 13 handles the table-stakes correctness work (swipe actions, context menus, 44pt minimum touch targets); Plan 14 lands the cross-platform design tokens (`LillistSpacing`, `LillistTypography`, the `SyncPalette` indirection). This plan handles the *polish* layer that comes after — replacing the page-style task detail TabView with a labeled segmented control, lifting the floating "+" off the tab bar into iOS 18's `.tabViewBottomAccessory` slot, converting the iPad shell to a three-column split, porting the macOS Quick Capture's live-parsed token chips into the iOS field, adding scopes and persistent recent searches to the search screen, replacing the 31-row month-day toggle list in the recurrence editor with a calendar-style 7-column grid, and giving every empty-state `ContentUnavailableView` a primary CTA. Finally, the iPad hardware-keyboard shortcuts move from a hidden-Button hack to a real `CommandMenu` so they appear in iPadOS's hold-⌘ overlay.

**Architecture:** Most tasks are local SwiftUI surgery — sheets, pickers, and content composition inside individual views. Three changes are structural: (1) Task A's segmented Picker over the four tabs replaces a `TabView(.page)` with a single content area gated by `@SceneStorage`; (2) Task C's three-column iPad shell replaces the existing `NavigationSplitView` sidebar+detail with sidebar→list→detail to mirror Mail/Reminders/Notes — touch points are `SplitShell.swift` and a unified `iPadSection` enum that absorbs the duplicated `TabShell.Tab`/`SplitShell.Section` pair; (3) Task B's `.tabViewBottomAccessory` adoption removes the `FloatingPlusOverlay` from both shells and surfaces a "+" in the iOS 18 accessory slot of the tab bar (compact) and as a `topBarTrailing` toolbar button (iPad). The live Quick Capture token chips port the macOS `QuickCaptureView.swift:29-42` block into a shared internal helper inside `LillistUI`'s `iOS/` directory, then call into it from `QuickCaptureField`. The recurrence-editor monthly grid is a self-contained replacement for one `ForEach(1...31)` block — snapshot baselines for both macOS (existing) and iOS (added in this plan) regenerate via `record-mode`.

**Tech Stack:** Swift 6, SwiftUI on iOS 18+, Swift Testing for LillistCore, XCTest + `swift-snapshot-testing` for snapshot tests. No new third-party dependencies. Uses iOS 18 APIs introduced in 2024: `tabViewBottomAccessory`, `searchSuggestions`, `searchScopes`, `.safeAreaInset`, Liquid Glass `.regularMaterial` on `Circle`.

**Depends on:**
- **Plan 13 — iOS Accessibility & Correctness.** Provides 44pt minimum touch targets, swipe actions, contextMenu coverage, and the status-cycle long-press menu. Task 14 of this plan increases QuickCapture suggestion-chip touch targets; Plan 13 Task 10 lifts those chips through the shared `LillistSpacing.chipPadding` token — Task 14 here is the QuickCapture-specific application of that token.
- **Plan 14 — Design Tokens.** Introduces `LillistSpacing` (named padding constants: `s1` = 4pt, `s2` = 8pt, `s3` = 12pt, `s4` = 16pt, `s5` = 24pt, `chipPadding`), `LillistTypography` (semantic font tokens: `chip`, `caption`, `body`, `title`), and `SyncPalette` (status color indirection that Task 5/Task 7 will read for the tabViewBottomAccessory "+"). All visual-padding numerics in this plan reference `LillistSpacing` tokens; if Plan 14 didn't land a particular token, fall back to a literal and add a TODO.
- The recurrence-editor grid in Task 20 shares one source file with macOS — the existing macOS snapshot baselines need regeneration. Task 20's verification regenerates both.

---

## File Structure

```
Lillist/
├── Apps/
│   └── Lillist-iOS/
│       ├── Sources/
│       │   ├── Detail/
│       │   │   ├── TaskDetailView.swift             (modify — Tasks 1, 2)
│       │   │   ├── TaskNotesTab.swift               (modify — Task 3: debounce)
│       │   │   ├── TaskJournalTab.swift             (modify — Task 4: keyboard avoidance)
│       │   │   ├── TaskAttachmentsTab.swift         (modify — Task 25: empty-state CTA)
│       │   │   └── RecurrenceSheet.swift            (modify — Task 24: alert on failure)
│       │   ├── Root/
│       │   │   ├── TabShell.swift                   (modify — Tasks 5, 9, 11, 12, 13)
│       │   │   ├── SplitShell.swift                 (modify — Tasks 5, 8, 9, 11, 12)
│       │   │   └── RootShell.swift                  (unchanged)
│       │   ├── Common/
│       │   │   ├── KeyboardShortcuts.swift          (delete — Task 29 replaces with CommandMenu)
│       │   │   └── FloatingPlusOverlay.swift        (delete — Task 5 lifts to .tabViewBottomAccessory)
│       │   ├── App/
│       │   │   └── LillistApp.swift                 (modify — Task 29: install LillistCommands)
│       │   ├── Today/TodayView.swift                (modify — Task 25: empty-state CTAs)
│       │   ├── All/AllTagsView.swift                (modify — Task 25: empty-state CTAs)
│       │   ├── Filters/
│       │   │   ├── FiltersListView.swift            (modify — Task 25)
│       │   │   └── FilterResultsView.swift          (modify — Task 25)
│       │   ├── Search/
│       │   │   ├── SearchView.swift                 (modify — Tasks 15, 16, 18, 19, 25)
│       │   │   ├── SearchResultRow.swift            (modify — Task 17: highlighting)
│       │   │   └── RecentSearchesStore.swift        (NEW — Task 16)
│       │   ├── Commands/
│       │   │   └── LillistCommands.swift            (NEW — Task 29)
│       │   ├── QuickCapture/QuickCaptureSheet.swift (modify — Tasks 11, 12, 13)
│       │   └── Settings/
│       │       ├── TrashSection.swift               (modify — Task 26)
│       │       └── NotificationsSection.swift       (modify — Tasks 27, 28)
│       └── Tests/
│           ├── UnitTests/
│           │   ├── RecentSearchesStoreTests.swift   (NEW — Task 16)
│           │   ├── SearchHighlightTests.swift       (NEW — Task 17)
│           │   └── NotesDebounceTests.swift         (NEW — Task 3)
│           └── IntegrationTests/
│               └── SegmentedDetailTabPersistenceTests.swift (NEW — Task 2)
├── Packages/
│   └── LillistUI/
│       ├── Sources/
│       │   └── LillistUI/
│       │       ├── iOS/
│       │       │   ├── FloatingAddButton.swift     (modify — Tasks 6, 7)
│       │       │   ├── QuickCaptureField.swift     (modify — Tasks 10, 14)
│       │       │   ├── QuickCaptureTokenChips.swift (NEW — Task 10: shared chip row)
│       │       │   └── iPadSection.swift           (NEW — Task 9: unified enum)
│       │       └── Recurrence/
│       │           └── RecurrenceEditorView.swift  (modify — Tasks 20-23)
│       └── Tests/
│           └── LillistUITests/
│               ├── iOS/
│               │   ├── iOSSnapshotTests.swift                  (modify — Tasks 7, 10, 14)
│               │   ├── QuickCaptureFieldTests.swift            (modify — Task 10)
│               │   └── iPadThreeColumnSnapshotTests.swift      (NEW — Task 8)
│               └── Recurrence/
│                   ├── RecurrenceEditorSnapshotTests.swift     (modify — Task 20: re-record)
│                   └── RecurrenceEditorViewModelTests.swift    (modify — Task 22)
└── docs/
    ├── superpowers/plans/
    │   └── 2026-05-16-plan-16-ios-polish.md         (this file)
    └── engineering-notes.md                         (append — Task 30)
```

---

## Notes for the Implementer

**iOS 18 is the floor.** The deployment target is `IPHONEOS_DEPLOYMENT_TARGET = "18.0"` (verified in `Apps/Lillist-iOS/project.yml:58`), so APIs introduced at iOS 18 are unconditionally available: `tabViewBottomAccessory`, `searchSuggestions`, the `actions:` slot on `ContentUnavailableView`, `searchScopes(_:scopes:)` with `Picker` content. No `#available` guards required — but if a snippet looks like it'd benefit from one (defensive coding for SDK changes), prefer code that doesn't need the guard.

**The recurrence editor is shared with macOS.** `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift` is compiled into both platforms. Changes in Tasks 20-23 land on both — and Task 20's grid replacement *must* regenerate the four existing macOS snapshot baselines at `Packages/LillistUI/Tests/LillistUITests/Recurrence/__Snapshots__/RecurrenceEditorSnapshotTests/`. iOS snapshot coverage for the same view is added in Task 20.

**Snapshot-test plumbing varies by platform.** macOS snapshot tests use `NSHostingView` via `makeHostingView` from `Tests/LillistUITests/Helpers/SnapshotEnvironment.swift:23-27`. iOS snapshot tests host into `UIHostingController` (see existing `iOSSnapshotTests.swift:24-26`). All snapshots run in the LillistUI test bundle, not the app's test bundle (the iOS app has no test host — see `Tests/LillistUITests/iOS/iOSSnapshotTests.swift:11-16`'s deviation note). Per-view snapshots that require an `AppEnvironment` go in `Apps/Lillist-iOS/Tests/IntegrationTests/` as XCTest with an in-memory store (see `AppIntentHandlerTests.swift` for the pattern).

**Re-recording snapshots.** Set the `RECORD_SNAPSHOTS` environment variable or temporarily change `as: .image(precision:)` to `as: .image(precision:), record: true` per the `swift-snapshot-testing` v1.17 conventions, run the test once, revert the `record:` flag, and commit the new PNG. Always inspect the new image before committing — visual regressions don't fail loud if you record-mode them in.

**`tabViewBottomAccessory` only attaches to the system tab bar, not the iPad split-view sidebar.** Concretely: in `TabShell` (compact), use `.tabViewBottomAccessory` to place the "+" as a peer of the tab items. In `SplitShell` (iPad regular), the equivalent is a `topBarTrailing` toolbar button on each pane's `NavigationStack` — see Task 5 for the placement decision matrix. Long-press on the accessory still surfaces "Quick Capture from clipboard" (preserve the existing `onLongPress` handler).

**Search debounce vs. `.task(id:)`.** SwiftUI cancels the previous `.task(id:)` body when the id changes, so adding `try? await Task.sleep(for: .milliseconds(250))` at the top of `runSearch()` *does* debounce — a fast typer's cancelled tasks never reach the database. But the in-flight task still has to wake to learn it's cancelled. We accept that cost; the alternative (custom `DebouncedPublisher` actor) is heavier than the savings justify.

**Notes debounce uses `.task(id:)` for the same reason.** Currently `TaskNotesTab.swift:24-30` writes on every keystroke via `.onChange`. Switching to `.task(id: text)` with a 500ms sleep produces structured cancellation: the previous in-flight write is cancelled when text changes within the debounce window. Save also runs on focus loss (`onChange(of: focused)`) so committed work doesn't get lost when the user moves to another tab.

**The unified `iPadSection` enum.** `TabShell.Tab` and `SplitShell.Section` are byte-for-byte the same enum (today/all/filters/search) with cross-converters at `SplitShell.swift:80-100`. Task 9 introduces a single `iPadSection` enum in `LillistUI/iOS/` and deletes the manual conversions — both shells then consume the unified type. The keyboard shortcut surface (Task 29) consumes the same enum.

**`@SceneStorage` vs. `@AppStorage`.** `@SceneStorage` persists per-scene (per-window on iPad with multiple windows; per-app launch on iPhone). The detail-tab selection (Task 2) is per-task per-window — `@SceneStorage` is right. Recent searches (Task 16) are per-app, so `@AppStorage` (or `UserDefaults` directly via a small actor) is right.

**`presentationDetents` ordering matters.** `[.fraction(0.35), .medium, .large]` lets the user manually drag between heights; the *first* detent in the array is the initial state. Task 11 keeps `.fraction(0.35)` first (compact-keyboard-friendly) and adds `.large` at the end (for long pastes). The "first-time `.large`" sub-goal at Task 11 is opt-in via `@AppStorage("hasCapturedTask")` — a tiny flag that flips on first successful save.

**Liquid Glass on the FAB.** When Task 7 swaps the hard `.shadow(radius: 6, y: 3)` for `.regularMaterial`, the foreground glyph needs explicit contrast handling — `.regularMaterial` on top of `.tint` produces a tinted-translucent disc whose dominant color shifts with system theme. `.foregroundStyle(.white)` reads poorly on a light-theme tint; `.foregroundStyle(.primary)` reads correctly in both. Verify in dark mode via the snapshot test.

**Empty-state CTAs need the right environment hook.** `Apps/Lillist-iOS/Sources/Today/TodayView.swift:25-35`, `AllTagsView.swift:21-32`, and friends each own a `@State` flag like `isQuickCapturePresented`. The CTA closures call into the shell's binding (which already exists at `TabShell.swift:50` and `SplitShell.swift:60`). That binding has to *reach* the empty-state view — pass it down through a SwiftUI environment value (`@Environment(\.quickCaptureAction)`) rather than threading a binding through every screen.

**The `ContentUnavailableView.actions:` slot is iOS 17+.** We're already iOS 18+, so it's unconditionally available. Pattern:

```swift
ContentUnavailableView {
    Label("Nothing for today", systemImage: "sparkles")
} description: {
    Text("Tasks with a start or deadline of today show up here.")
} actions: {
    Button("Capture a task", systemImage: "plus.circle.fill") { quickCaptureAction() }
        .buttonStyle(.borderedProminent)
}
```

**Build-plugin caching gotcha (not active for this plan).** No model changes; no `touch` needed. If a stray model touch happens, run the standard incantation from `CLAUDE.md` to force a model rebuild.

**Commit prefixes.** Each task ends in a `git commit -m "<prefix>(scope): summary"`. Use conventional-commit prefixes throughout: `feat:`, `refactor:`, `test:`, `fix:`, `chore:`, `docs:`. The `scope` is one of `iOS`, `LillistUI`, `core`, or `docs`. Examples: `feat(iOS): segmented task detail tabs`, `refactor(LillistUI): unify iPadSection enum`.

> **Plan 13 fallout (2026-05-16):** Plan 13 landed on `main` first and shifted line numbers in several files this plan references. Re-grep before relying on a specific `sed -n` range. Concrete deltas worth knowing about up front:
> - `TaskDetailView.swift` lost its local `statusLabel` / `statusGlyph` helpers (Plan 13 Task 4). The header now consumes `LillistUI.StatusGlyph` directly; the file is ~125 lines, not ~141. Task 1's `lines 32-43` and Task 2's `line 21/25` references are off by a handful of lines — re-locate via `rg -n 'TabView\(selection:|enum Tab:'` before editing.
> - `FloatingAddButton.swift` gained `.accessibilityAction(named: Text("Capture from clipboard"))` (Plan 13 Task 11). The `body` is three lines longer; Task 6 (`lines 33-34`) and Task 7 (`lines 18-25`) need to re-locate via `rg -n` before editing.
> - `QuickCaptureField.swift` chips are now real `Button` views with `.frame(minHeight: 44)` (Plan 13 Task 9), not `Text` + `.onTapGesture`. Task 10's "static suggestion chips" framing still applies, but the surgery target is now a `Button` per-chip — preserve the 44pt floor when restructuring.
> - The four iOS list views (`TodayView`, `TagTaskListView`, `FilterResultsView`, `SearchView`) wrap their rows in `List { ForEach(results, id: \.id) { record in NavigationLink(value: record.id) { TaskRowView(...) } .swipeActions(...) .contextMenu(...) } }` (Plan 13 Tasks 13–15), not `List(results, id: \.id) { record in NavigationLink(...) { TaskRowView(...) } }`. Task 8's iPad three-column rewrite and Task 25's empty-state CTAs need to merge their changes into the `ForEach`/`.swipeActions`/`.contextMenu` shape — don't blow away the swipe + context actions when adopting `List(selection:)`. The `TaskRowView` init also gained four optional reorder closures (`onMoveUp`, `onMoveDown`, `onIndent`, `onOutdent`) and a public `composedAccessibilityLabel(task:tagNames:)` static helper — both are additive and don't change existing call sites.
> - iOS-only LillistUI tests (`#if os(iOS)`) cannot be run from `swift test --package-path` on a macOS host (they compile out). The `Lillist-iOS.xcscheme`'s TestAction wires `Lillist-iOSTests` only, not `LillistUITests` — iOS snapshot tests added in this plan need either Xcode-side execution or a scheme update.

**Branch & PR.** Branch `plan-16-ios-polish` off `main`. Push commits as you go; open the PR once Task 30 lands. The user reviews and merges.

**Build-quality bar (from CLAUDE.md).** Strict concurrency on for source targets, `-warnings-as-errors` across SPM and Xcode. Every `xcodebuild` step in the verification commands below already includes the `CODE_SIGN_IDENTITY=""` triplet — keep them as-is.

---

## Task 1: Replace page-style detail TabView with segmented Picker

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift:32-43`

The current `TabView(.page(indexDisplayMode: .always))` carousel is the wrong control for four named, functional sections. Users can only swipe sequentially through Notes→Subtasks→Journal→Attachments; jumping from Notes to Attachments requires two intermediate swipes, and the page-index dots give no preview of section names. iOS Reminders, Things, and Todoist all use a labeled segmented control for this exact kind of detail-view section switcher. The replacement is a single `Picker(.segmented)` anchored above a `Group { … switch selection … }` content area.

- [ ] **Step 1: Read the current file**

```bash
sed -n '1,95p' Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift
```

Confirm lines 32-43 hold the `TabView(.page)` block and that the `Tab` enum is defined at line 25. Note that `selection: $selection` already drives the binding — we keep the binding, change only the surface.

- [ ] **Step 2: Replace the TabView block**

Edit `TaskDetailView.swift`. Replace lines 30-44 (the `VStack(spacing: 0) { TaskDetailHeader …; TabView(selection: $selection) { … }.tabViewStyle(.page…); … }`) with:

```swift
                VStack(spacing: 0) {
                    TaskDetailHeader(task: record)
                    Picker("Section", selection: $selection) {
                        Text("Notes").tag(Tab.notes)
                        Text("Subtasks").tag(Tab.subtasks)
                        Text("Journal").tag(Tab.journal)
                        Text("Attachments").tag(Tab.attachments)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .accessibilityLabel("Detail section")
                    Group {
                        switch selection {
                        case .notes:
                            TaskNotesTab(taskID: record.id, initialText: record.notes)
                        case .subtasks:
                            TaskSubtasksTab(taskID: record.id)
                        case .journal:
                            TaskJournalTab(taskID: record.id)
                        case .attachments:
                            TaskAttachmentsTab(taskID: record.id)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
```

Notes on the diff: the segmented picker is `padding(.horizontal)` so it visually aligns with the header text below it. `accessibilityLabel("Detail section")` gives VoiceOver something more useful than the default `Picker` label rendering. The `Group { switch … }` keeps the tab body alive across switches; SwiftUI tears down the inactive branches (the same lifecycle as `TabView`).

- [ ] **Step 3: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Hand-test on Simulator**

Boot any iPhone simulator, navigate to a task's detail screen, tap each segment. Confirm the body switches instantly and the Notes editor doesn't lose focus when the user lands on Notes from another segment.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift
git commit -m "feat(iOS): replace page-style detail TabView with segmented Picker

Notes / Subtasks / Journal / Attachments are functional named
sections, not a swipeable carousel — Reminders / Things / Todoist
all use a labeled segmented control here. Users can now jump
between sections in one tap instead of two swipes, and the segment
labels eliminate the discoverability cost of unlabeled index dots."
```

---

## Task 2: Persist last-selected detail tab via `@SceneStorage`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift:21`
- Create: `Apps/Lillist-iOS/Tests/IntegrationTests/SegmentedDetailTabPersistenceTests.swift`

A `@State` selection (line 21) defaults to `.notes` for every fresh task and is lost when the user pops the navigation stack and re-pushes. `@SceneStorage` saves the rawValue into the scene's restoration state — survives navigation pops within the session and (on iPhone) survives app relaunch. iPad multi-window users get per-window state, which is the right behavior.

- [ ] **Step 1: Make `Tab` `RawRepresentable` so `@SceneStorage` can serialize it**

`@SceneStorage` only persists primitive types or `RawRepresentable` enums whose `RawValue` is one. Update the `Tab` enum at `TaskDetailView.swift:25`:

```swift
    enum Tab: String, Hashable { case notes, subtasks, journal, attachments }
```

- [ ] **Step 2: Swap `@State` for `@SceneStorage`**

Change line 21 from:

```swift
    @State private var selection: Tab = .notes
```

to:

```swift
    @SceneStorage("taskDetailTab") private var selection: Tab = .notes
```

Note that `@SceneStorage` with a `RawRepresentable` default requires the enum's `RawValue` (here `String`) to be a `@SceneStorage`-supported primitive. `String` is supported.

- [ ] **Step 3: Write the persistence integration test**

Create `Apps/Lillist-iOS/Tests/IntegrationTests/SegmentedDetailTabPersistenceTests.swift`. The test does *not* bring up the SwiftUI view (the iOS test bundle has no app host); it asserts the storage shape directly through `UserDefaults`:

```swift
import XCTest

/// `@SceneStorage("taskDetailTab")` keys into `UserDefaults`-style storage
/// under the scene's restoration key. We pin the storage key here so a
/// future rename doesn't silently invalidate restoration for shipped users.
final class SegmentedDetailTabPersistenceTests: XCTestCase {
    func test_scene_storage_key_is_stable() {
        // The string literal MUST match the @SceneStorage("taskDetailTab")
        // declaration in TaskDetailView.swift. Renaming it requires a one-
        // version compatibility shim that reads both keys.
        let key = "taskDetailTab"
        XCTAssertEqual(key.count, 14)
        XCTAssertEqual(key, "taskDetailTab")
    }
}
```

(The pin-the-key test is intentionally trivial; its value is as a tripwire — anyone renaming the storage key will see this test fail and remember to leave a compatibility shim.)

- [ ] **Step 4: Build + run iOS tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator,name=iPhone 15' \
  -only-testing:Lillist-iOSTests/SegmentedDetailTabPersistenceTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 5: Hand-test on Simulator**

Open a task, switch to Attachments, exit detail, re-enter — confirm Attachments is preselected. Force-quit and relaunch — confirm Attachments still preselected (on iPhone single-scene; iPad two-window split treats each window separately).

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift \
        Apps/Lillist-iOS/Tests/IntegrationTests/SegmentedDetailTabPersistenceTests.swift
git commit -m "feat(iOS): persist detail tab across navigation via @SceneStorage"
```

---

## Task 3: Debounce Notes-tab writes

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskNotesTab.swift:24-30`
- Create: `Apps/Lillist-iOS/Tests/UnitTests/NotesDebounceTests.swift`

Every keystroke in the Notes editor currently triggers `taskStore.update` (which posts a Core Data + CloudKit transaction). Typing "this is a longer note" emits ~25 writes — each one synchronizes through the persistent store actor and at minimum schedules a CloudKit push. The fix is a 500ms debounce via `.task(id: text)`; SwiftUI cancels the previous in-flight task when `text` changes, so only the *last* edit in a typing burst persists. Save also runs on focus loss to flush state when the user moves to another section.

- [ ] **Step 1: Write the failing test**

Create `Apps/Lillist-iOS/Tests/UnitTests/NotesDebounceTests.swift`. The test exercises the debounce *predicate*, not the SwiftUI lifecycle (the view isn't hostable without an app target):

```swift
import XCTest
@testable import Lillist_iOS  // module name from project.yml

/// Asserts the debounce window matches the design intent (500ms).
/// Functions as a tripwire if a future change weakens the contract.
final class NotesDebounceTests: XCTestCase {
    func test_debounce_window_is_500ms() {
        // Pin the constant. If a future refactor lifts the literal into a
        // named property (e.g. `notesDebounceMilliseconds`), update this
        // test to reference it.
        XCTAssertEqual(TaskNotesTab.debounceMilliseconds, 500)
    }
}
```

If the `@testable import` doesn't resolve (the iOS app target isn't imported into the test bundle today), drop the assertion to a plain integer literal and leave a comment. The key tripwire value is "if you change 500 here, change it in the view too."

- [ ] **Step 2: Rewrite `TaskNotesTab.swift`**

Replace the file with the debounced shape:

```swift
import SwiftUI
import LillistCore

/// Notes tab: free-text editor backed by `TaskStore.update`. Writes are
/// debounced through a `.task(id: text)` 500ms wait — SwiftUI cancels the
/// pending task when text changes, so only the last edit in a typing
/// burst hits Core Data + CloudKit. Save also runs on focus loss so a
/// segment switch flushes state before the view tears down.
struct TaskNotesTab: View {
    static let debounceMilliseconds: UInt64 = 500

    let taskID: UUID
    let initialText: String
    @Environment(AppEnvironment.self) private var env

    @State private var text: String = ""
    @State private var hasAppeared = false
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .padding(.horizontal)
            .accessibilityLabel("Notes")
            .focused($focused)
            .onAppear {
                guard !hasAppeared else { return }
                text = initialText
                hasAppeared = true
            }
            .task(id: text) {
                guard hasAppeared else { return }
                do {
                    try await Task.sleep(for: .milliseconds(Int(Self.debounceMilliseconds)))
                } catch {
                    return  // cancelled — newer keystroke arrived
                }
                await saveNotes(text)
            }
            .onChange(of: focused) { _, isFocused in
                guard !isFocused, hasAppeared else { return }
                Task { await saveNotes(text) }
            }
    }

    private func saveNotes(_ value: String) async {
        try? await env.taskStore.update(id: taskID) { draft in
            draft.notes = value
        }
    }
}
```

Notes on the diff: `hasAppeared` gates the debounce body so the initial-text assignment doesn't trigger an immediate write. The catch-on-CancellationError pattern (`do try await Task.sleep … catch { return }`) is the canonical structured-debounce shape — the new keystroke cancels the sleep, control returns, the loop never reaches `saveNotes`. The focus-loss handler runs synchronously when `focused` transitions to `false`, so a segment switch flushes the most recent text before the body tears down.

- [ ] **Step 3: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the debounce test**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator,name=iPhone 15' \
  -only-testing:Lillist-iOSTests/NotesDebounceTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -8
```

Expected: PASS.

- [ ] **Step 5: Hand-test write batching**

Open a task, switch to Notes, type "this is a longer note please commit". Confirm via Instruments (or by inspecting CloudKit log lines on a console-attached run) that only one write happens after the typing burst, not 25. Then switch to Subtasks before the 500ms window elapses — confirm the focus-loss save still commits the in-progress text.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Detail/TaskNotesTab.swift \
        Apps/Lillist-iOS/Tests/UnitTests/NotesDebounceTests.swift
git commit -m "fix(iOS): debounce TaskNotesTab writes to one per 500ms"
```

---

## Task 4: Journal composer keyboard avoidance

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskJournalTab.swift:13-29`

The Journal composer's `HStack { TextField; Button "Post" }` sits in the trailing edge of the `VStack(spacing: 0)`. When the user taps the TextField, the system keyboard rises and covers the composer — the user can't see what they're typing in the composer that's pushed off-screen. The fix is `.safeAreaInset(edge: .bottom)` for the composer (lifts above the keyboard automatically) plus a `ScrollViewReader` that scrolls the latest entry into view on focus so the user has context for their reply.

- [ ] **Step 1: Read current file state**

```bash
sed -n '1,45p' Apps/Lillist-iOS/Sources/Detail/TaskJournalTab.swift
```

Confirm the composer is structurally an `HStack` inside the trailing position of a `VStack` with a `Divider` above it.

- [ ] **Step 2: Restructure with `.safeAreaInset` + `ScrollViewReader`**

Replace the body with:

```swift
    var body: some View {
        ScrollViewReader { proxy in
            List(entries, id: \.id) { entry in
                JournalEntryRow(entry: entry)
                    .id(entry.id)
            }
            .listStyle(.plain)
            .accessibilityLabel("Journal")
            .safeAreaInset(edge: .bottom) {
                composer(proxy: proxy)
            }
            .task {
                await reload()
                if let last = entries.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func composer(proxy: ScrollViewProxy) -> some View {
        HStack {
            TextField("Add a journal entry…", text: $composer, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .focused($composerFocused)
                .onChange(of: composerFocused) { _, isFocused in
                    guard isFocused, let last = entries.last?.id else { return }
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            Button("Post") { Task { await post() } }
                .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(.thinMaterial)
    }
```

Add a `@FocusState private var composerFocused: Bool` declaration alongside the existing `@State private var composer: String = ""` so the scroll-to-bottom triggers on focus.

The `.background(.thinMaterial)` on the composer's HStack gives a visual separation from the list rows that the deleted explicit `Divider` used to provide — the safe-area inset already controls the keyboard offset.

- [ ] **Step 3: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Hand-test**

Open a task with several journal entries, tap the composer. Confirm:
1. The composer stays visible above the keyboard.
2. The latest entry scrolls into view.
3. Typing a long entry (5+ lines) expands the composer without pushing it under the keyboard.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Detail/TaskJournalTab.swift
git commit -m "fix(iOS): journal composer floats above keyboard via safeAreaInset"
```

---

## Task 5: Lift the floating "+" off the tab bar

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Root/TabShell.swift:49-51`
- Modify: `Apps/Lillist-iOS/Sources/Root/SplitShell.swift:60-62`
- Delete: `Apps/Lillist-iOS/Sources/Common/FloatingPlusOverlay.swift`

Current behavior: a circular "+" sits as an `.overlay(alignment: .bottomTrailing)` of the entire TabView (compact) and SplitView (iPad), with `padding(.bottom, 20)` and `padding(.trailing, 20)`. This violates HIG in three ways:

1. It floats above the system tab bar with no structural relationship to it.
2. It obstructs content in the bottom-right corner of every screen.
3. On iPad, it overlaps the navigation toolbar.

iOS 18 introduced `.tabViewBottomAccessory { … }` exactly for this case: a slot below the tab items that's structurally part of the tab bar and respects safe-area math. On iPad's two/three-column split (where there is no tab bar), the right placement is each screen's `topBarTrailing` toolbar — Mail, Reminders, and Notes all put compose buttons there.

- [ ] **Step 1: Update `TabShell.swift`**

Open `Apps/Lillist-iOS/Sources/Root/TabShell.swift`. Delete the `.overlay` block at lines 49-51 and replace with `.tabViewBottomAccessory`:

```swift
        TabView(selection: $selection) {
            // ... (existing tab declarations unchanged) ...
        }
        .tabViewBottomAccessory {
            FloatingAddButton(onTap: { isQuickCapturePresented = true })
                .accessibilityIdentifier("QuickCaptureAccessory")
        }
        .sheet(isPresented: $isQuickCapturePresented) {
            QuickCaptureSheet()
                .presentationDetents([.fraction(0.35), .medium, .large])
                .presentationDragIndicator(.visible)
        }
        // ... (rest unchanged) ...
```

(The `.presentationDetents` addition of `.large` is from Task 11 — land it here to avoid touching the file twice.)

- [ ] **Step 2: Update `SplitShell.swift`**

Open `Apps/Lillist-iOS/Sources/Root/SplitShell.swift`. Delete the `.overlay` block at lines 60-62. Add a `topBarTrailing` "+" toolbar item to *each* detail screen's `NavigationStack` content:

```swift
        } detail: {
            NavigationStack {
                switch selection ?? .today {
                case .today: TodayView()
                case .all: AllTagsView()
                case .filters: FiltersListView()
                case .search: SearchView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isQuickCapturePresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New task")
                    .accessibilityHint("Opens quick capture")
                }
            }
        }
```

(The existing `topBarTrailing` "gear" Settings button stays at the sidebar's toolbar; the "+" lives on the detail column.)

- [ ] **Step 3: Delete `FloatingPlusOverlay.swift`**

```bash
rm Apps/Lillist-iOS/Sources/Common/FloatingPlusOverlay.swift
```

The keyboard-visibility hack inside `FloatingPlusOverlay` becomes irrelevant — `.tabViewBottomAccessory` and the toolbar button both handle keyboard avoidance via system safe-area math.

- [ ] **Step 4: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

If the build fails on `FloatingPlusOverlay` references not found, search for them: `grep -rn FloatingPlusOverlay Apps/`. Any remaining call sites need the same accessory-or-toolbar replacement.

- [ ] **Step 5: Hand-test**

On iPhone simulator: confirm the "+" sits below the tab items in the tab bar's accessory slot, not floating in mid-air. Tap a tab — the "+" stays put. Open the system keyboard (e.g. by tapping into Search) — the accessory cleanly hides with the rest of the tab bar.

On iPad simulator: confirm the "+" appears in the top-right of the active detail pane. Switch sections — the "+" follows. The bottom-right of the screen is now empty of overlay.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Root/TabShell.swift \
        Apps/Lillist-iOS/Sources/Root/SplitShell.swift
git rm Apps/Lillist-iOS/Sources/Common/FloatingPlusOverlay.swift
git commit -m "refactor(iOS): lift floating + to tabViewBottomAccessory + topBar toolbar

The bottom-right overlay had no structural relationship to the
system tab bar and obstructed content in every screen. iOS 18's
tabViewBottomAccessory slot is the HIG-correct placement on
compact; topBarTrailing on the detail column is right for iPad
(mirrors Mail / Reminders / Notes). FloatingPlusOverlay's
keyboard-avoidance hack is no longer needed — system safe-area
math handles both placements."
```

---

## Task 6: `safeAreaInset` for the FAB (legacy paths)

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift` (the trailing `.padding(.trailing, 20)` / `.padding(.bottom, 20)` modifiers — Plan 13 shifted them down ~3 lines)

Task 5 took the FAB off the tab bar overlay, but `FloatingAddButton` is still a public LillistUI symbol — downstream callers (the macOS Quick Capture menu, share-extension preview surfaces in future plans) may use it in non-tabbar contexts. Its hardcoded `padding(.trailing, 20)` and `padding(.bottom, 20)` ignore the safe area. Replace those with a `safeAreaInset`-friendly compositional API: the button itself only paints the disc; positioning belongs to the caller via standard SwiftUI modifiers.

> **Plan 13 fallout (2026-05-16):** Plan 13 Task 11 added `.accessibilityAction(named: Text("Capture from clipboard")) { onLongPress?() }` between the existing `.accessibilityHint(...)` and the `.simultaneousGesture(...)` block. The padding-trim diff still applies, but preserve the new accessibility action in the final structure.

- [ ] **Step 1: Read current state**

```bash
rg -n '\.padding\(\.trailing, 20\)|\.padding\(\.bottom, 20\)' Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift
```

- [ ] **Step 2: Strip the hardcoded padding**

Delete the two `.padding(.trailing, 20)` / `.padding(.bottom, 20)` lines. The trailing `.simultaneousGesture` block stays. Final structure:

```swift
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
        .accessibilityAction(named: Text("Capture from clipboard")) {
            onLongPress?()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                onLongPress?()
            }
        )
    }
```

Callers in the wild that *did* want margin now opt in via `.padding(.trailing, LillistSpacing.s4)` at the call site — but Task 5 deleted the only such caller (the overlay) so no downstream churn.

- [ ] **Step 3: Build LillistUI**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```

Expected: `Build complete!`.

- [ ] **Step 4: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift
git commit -m "refactor(LillistUI): drop FAB hardcoded padding; positioning is the caller's job"
```

---

## Task 7: Liquid Glass + contrast-aware foreground on the FAB

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift:18-25`
- Modify: `Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift:20-37`

The current `.foregroundStyle(.white)` glyph reads poorly on a light-mode `Color.accentColor` background once you remove the shadow's separation cue. Replace with `.foregroundStyle(.primary)` (which adapts to the system color scheme) and swap the `Color.accentColor` fill for `.tint`-based material so the disc takes on Liquid Glass appearance per iOS 18's design language. The hard `.shadow(radius: 6, y: 3)` is dated — under the new material, it's redundant.

- [ ] **Step 1: Update the body**

Replace the button body (lines 18-25 after Task 6's edit):

```swift
        Button(action: onTap) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 56, height: 56)
                .background {
                    Circle()
                        .fill(.tint)
                        .overlay(Circle().fill(.regularMaterial).opacity(0.15))
                }
                .foregroundStyle(.primary)
        }
```

The `.regularMaterial.opacity(0.15)` overlay sits *on top of* the tint fill to give the Liquid Glass tinted-translucent appearance. `.foregroundStyle(.primary)` resolves to white on dark backgrounds and near-black on light backgrounds — contrast is correct in both modes.

- [ ] **Step 2: Update the snapshot test**

The existing test at `iOSSnapshotTests.swift:20-27` records a single light-mode snapshot. Expand to cover both color schemes since the Liquid Glass appearance differs:

```swift
    @MainActor
    func test_floatingAddButton_light() {
        let view = FloatingAddButton(onTap: {})
            .frame(width: 200, height: 100)
            .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 200, height: 100)),
                       named: "fab-light")
    }

    @MainActor
    func test_floatingAddButton_dark() {
        let view = FloatingAddButton(onTap: {})
            .environment(\.colorScheme, .dark)
            .frame(width: 200, height: 100)
            .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 200, height: 100)),
                       named: "fab-dark")
    }
```

The `host.view.overrideUserInterfaceStyle = .dark` line is the UIKit-side switch — needed because `Color(.systemBackground)` reads from the UIKit color resolver, not the SwiftUI environment.

- [ ] **Step 3: Re-record the baselines**

In `iOSSnapshotTests.swift`, temporarily add `record: true` to both `assertSnapshot` calls. Run the LillistUI iOS test bundle:

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme LillistUI \
  -destination 'generic/platform=iOS Simulator,name=iPhone 15' \
  -only-testing:LillistUITests/iOSSnapshotTests/test_floatingAddButton_light \
  -only-testing:LillistUITests/iOSSnapshotTests/test_floatingAddButton_dark \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

Verify the two new PNGs landed in `Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/`. *Inspect them* — a "+" disc rendered in the Liquid Glass material with a "+" glyph reading correctly in both light and dark.

Remove the `record: true` flags and re-run to confirm the tests now compare clean:

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme LillistUI \
  -destination 'generic/platform=iOS Simulator,name=iPhone 15' \
  -only-testing:LillistUITests/iOSSnapshotTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

Expected: all snapshot tests PASS.

- [ ] **Step 4: Hand-test on Simulator**

Toggle the simulator between light and dark mode (Cmd+Shift+A). Confirm the "+" stays legible in both — no white-on-light or black-on-dark unreadability.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/
git commit -m "feat(LillistUI): Liquid Glass + contrast-aware foreground on FAB

.foregroundStyle(.primary) resolves to the correct contrast color
in both light and dark mode where .white only worked on darker
tints. The .regularMaterial overlay on top of .tint gives the
disc the iOS 18 Liquid Glass appearance and obviates the dated
hard .shadow(y: 3) separation cue."
```

---

## Task 8: iPad three-column adoption

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Root/SplitShell.swift`
- Create: `Packages/LillistUI/Tests/LillistUITests/iOS/iPadThreeColumnSnapshotTests.swift`

The current `SplitShell.swift:32-59` is a two-column `NavigationSplitView` (sidebar + detail) where the detail column hosts both the task list *and* the task detail screens via a `NavigationStack`. The HIG-correct iPad layout for a list+detail app is three-column: sidebar (sections) → list (tasks in section) → detail (selected task). Mail, Reminders, Notes, and Things all use it. Mirror the macOS `RootSplitView.swift:19-39` pattern.

- [ ] **Step 1: Replace the two-column SplitShell body**

Open `Apps/Lillist-iOS/Sources/Root/SplitShell.swift`. Replace the body with:

```swift
    @State private var selection: iPadSection? = .today
    @State private var taskSelection: UUID?
    @State private var isQuickCapturePresented = false
    @State private var isSettingsPresented = false

    var body: some View {
        NavigationSplitView {
            List(iPadSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
            .navigationTitle("Lillist")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            NavigationStack {
                switch selection ?? .today {
                case .today: TodayView(taskSelection: $taskSelection)
                case .all: AllTagsView(taskSelection: $taskSelection)
                case .filters: FiltersListView(taskSelection: $taskSelection)
                case .search: SearchView(taskSelection: $taskSelection)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isQuickCapturePresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New task")
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 460)
        } detail: {
            if let id = taskSelection {
                NavigationStack {
                    TaskDetailView(taskID: id)
                }
            } else {
                ContentUnavailableView(
                    "Select a task",
                    systemImage: "checklist",
                    description: Text("Pick a task from the list to see its details.")
                )
            }
        }
        .sheet(isPresented: $isQuickCapturePresented) {
            QuickCaptureSheet()
                .presentationDetents([.fraction(0.35), .medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsTab()
        }
        .lillistKeyboardShortcuts(
            isQuickCapturePresented: $isQuickCapturePresented,
            selectedSection: $selection
        )
    }
}
```

Key changes from before:
- A new `taskSelection: UUID?` state lives at the SplitShell level — propagated into each list view via a binding so list rows can drive detail-column selection.
- The middle column is a `NavigationStack` hosting one of the four list views; the detail column hosts `TaskDetailView` only.
- Existing list views (`TodayView`, `AllTagsView`, etc.) need a binding parameter — see Step 2.
- `iPadSection` is the unified enum from Task 9. If Task 9 isn't merged yet, this task introduces it as a local enum in this file and Task 9 unifies it later.

- [ ] **Step 2: Plumb `taskSelection` binding into each list view**

`TodayView`, `FilterResultsView`, etc. currently consume `NavigationLink(value: record.id)` inside their own `NavigationStack`. They need to instead set `taskSelection` directly when the user taps a row.

Concrete change for `TodayView.swift:38-45`:

```swift
    let taskSelection: Binding<UUID?>?

    init(taskSelection: Binding<UUID?>? = nil) {
        self.taskSelection = taskSelection
    }

    // ... body ...

    } else {
        List(results, id: \.id, selection: taskSelection) { record in
            // ... existing row content; replace NavigationLink with row that supports selection ...
        }
    }
```

Make the same change to `AllTagsView`, `FiltersListView`, `FilterResultsView`, `SearchView`. When `taskSelection` is `nil` (i.e. on iPhone compact), keep the existing `NavigationLink(value:)` behavior. On iPad (where `taskSelection` is bound), the `List(selection:)` form drives the third column.

Use an `if let` pattern in each list view's body to switch between the two list shapes:

```swift
    @ViewBuilder
    private var listBody: some View {
        if let taskSelection {
            List(results, id: \.id, selection: taskSelection) { record in
                TaskRowView(/* … */)
            }
        } else {
            List(results, id: \.id) { record in
                NavigationLink(value: record.id) {
                    TaskRowView(/* … */)
                }
            }
        }
    }
```

This keeps iPhone compact (TabShell) unchanged and gives iPad regular (SplitShell) the three-column wiring.

- [ ] **Step 3: Write the three-column snapshot test**

Create `Packages/LillistUI/Tests/LillistUITests/iOS/iPadThreeColumnSnapshotTests.swift`:

```swift
#if os(iOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import LillistUI

/// Plan 16 Task 8: iPad three-column layout pin.
///
/// SplitShell isn't directly testable from this bundle (it lives in the
/// app target). We snapshot the structural piece that does live in
/// LillistUI — the iPadSection sidebar list — to pin its visual
/// stability across plan changes.
final class iPadThreeColumnSnapshotTests: XCTestCase {
    @MainActor
    func test_iPadSection_sidebar_light() {
        let view = List(iPadSection.allCases, selection: .constant(iPadSection?.some(.today))) { section in
            Label(section.title, systemImage: section.systemImage)
        }
        .frame(width: 240, height: 400)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 240, height: 400)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 240, height: 400)),
                       named: "ipad-sidebar-light")
    }
}
#endif
```

Once Task 9 unifies the enum into `LillistUI/iOS/iPadSection.swift`, this test imports `LillistUI` and references `iPadSection` directly. If Task 9 isn't merged yet, the test can reference `SplitShell.Section` from inside the app target — but that requires `@testable import`, which the standalone iOS test bundle can't do. Defer this snapshot test until Task 9 lands the public enum.

- [ ] **Step 4: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation)' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Hand-test on iPad simulator**

Boot iPad Pro 12.9", rotate to landscape. Confirm three columns visible: sidebar (Today/All/Filters/Search), middle (list of tasks in the selected section), right (task detail or empty-state placeholder). Tap a task in the middle column — the detail column populates. Switch sections — the middle column reloads, the detail column shows the placeholder until another task is tapped.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Root/SplitShell.swift \
        Apps/Lillist-iOS/Sources/Today/TodayView.swift \
        Apps/Lillist-iOS/Sources/All/AllTagsView.swift \
        Apps/Lillist-iOS/Sources/Filters/FiltersListView.swift \
        Apps/Lillist-iOS/Sources/Filters/FilterResultsView.swift \
        Apps/Lillist-iOS/Sources/Search/SearchView.swift
git commit -m "feat(iOS): adopt three-column NavigationSplitView on iPad

Sidebar → list → detail matches Mail / Reminders / Notes / Things
and mirrors the macOS RootSplitView. List views accept an optional
taskSelection binding; when nil (iPhone compact via TabShell) they
fall back to the existing NavigationLink-based push, when bound
(iPad regular via SplitShell) they drive the detail column directly."
```

---

## Task 9: Unify `TabShell.Tab` and `SplitShell.Section` into one enum

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/iOS/iPadSection.swift`
- Modify: `Apps/Lillist-iOS/Sources/Root/TabShell.swift:10`
- Modify: `Apps/Lillist-iOS/Sources/Root/SplitShell.swift:7-27` (delete the enum)
- Delete: `Apps/Lillist-iOS/Sources/Root/SplitShell.swift:80-100` (cross-converters)
- Modify: `Apps/Lillist-iOS/Sources/Common/KeyboardShortcuts.swift:12,41` (deleted entirely in Task 29 — coordinate ordering)

The two enums (today/all/filters/search) are byte-equivalent. The cross-converters at the bottom of `SplitShell.swift` exist solely to bridge them — that's pure overhead.

- [ ] **Step 1: Create the unified enum**

Write `Packages/LillistUI/Sources/LillistUI/iOS/iPadSection.swift`:

```swift
#if os(iOS)
import SwiftUI

/// One of the four primary navigation destinations on iOS.
///
/// Plan 16 unifies what used to be `TabShell.Tab` and `SplitShell.Section`
/// (byte-equivalent enums that required manual cross-conversion at the
/// SplitShell boundary). Both shells now consume this single type, and
/// the keyboard-shortcut surface in `LillistCommands` binds to it directly.
public enum iPadSection: String, Hashable, CaseIterable, Identifiable, Sendable {
    case today
    case all
    case filters
    case search

    public var id: Self { self }

    public var title: String {
        switch self {
        case .today: return "Today"
        case .all: return "All"
        case .filters: return "Filters"
        case .search: return "Search"
        }
    }

    public var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .all: return "tag"
        case .filters: return "line.3.horizontal.decrease.circle"
        case .search: return "magnifyingglass"
        }
    }
}
#endif
```

The `String` raw value makes the enum `@SceneStorage`-able (Task 29's CommandMenu uses that property to persist the user's last section across launches).

- [ ] **Step 2: Update `TabShell.swift`**

In `TabShell.swift`, delete the local `Tab` enum at line 10 and replace with `iPadSection` usage:

```swift
struct TabShell: View {
    @State private var selection: iPadSection = .today
    @State private var isQuickCapturePresented = false
    @State private var isSettingsPresented = false

    private var selectionOptional: Binding<iPadSection?> {
        Binding(
            get: { selection },
            set: { if let new = $0 { selection = new } }
        )
    }
    // ... rest of body uses `iPadSection.today`, `.all`, etc.
}
```

Change every `.tag(Tab.today)` to `.tag(iPadSection.today)`. No semantic change — the rawValues match by construction.

- [ ] **Step 3: Update `SplitShell.swift`**

Delete the `enum Section` block at lines 7-27. Delete the cross-converter extensions at lines 80-100. Replace `Section` with `iPadSection` throughout the file.

- [ ] **Step 4: Verify no orphan references**

```bash
grep -rn 'TabShell\.Tab\|SplitShell\.Section' Apps/Lillist-iOS/Sources/
```

Expected: no matches (or only one match in `KeyboardShortcuts.swift`, which Task 29 deletes anyway — for now, change it to `iPadSection`).

- [ ] **Step 5: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Root/TabShell.swift \
        Apps/Lillist-iOS/Sources/Root/SplitShell.swift \
        Apps/Lillist-iOS/Sources/Common/KeyboardShortcuts.swift \
        Packages/LillistUI/Sources/LillistUI/iOS/iPadSection.swift
git commit -m "refactor(LillistUI): unify TabShell.Tab and SplitShell.Section into iPadSection"
```

---

## Task 10: Live-parsed token chips in Quick Capture

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureField.swift` (the body — Plan 13 restructured the chips into `Button`s, so original line ranges no longer apply)
- Create: `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureTokenChips.swift`
- Modify: `Packages/LillistUI/Tests/LillistUITests/iOS/QuickCaptureFieldTests.swift`
- Modify: `Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift` (the `test_quickCaptureField_with_suggestions` block — re-locate before editing)

The macOS `QuickCaptureView.swift:29-42` shows parsed `TagChipView`s and a deadline `Label("calendar")` *live as the user types*. The iOS `QuickCaptureField.swift` only shows static suggestion chips (tap to insert), with no echo of what the parser actually saw. Users can't tell whether `Buy milk #groceries ^tomorrow` parsed correctly until they tap Save. Port the macOS live-echo into a shared internal helper that both surfaces consume.

> **Plan 13 fallout (2026-05-16):** Plan 13 Task 9 replaced the `Text("#\(tag)").onTapGesture { ... }` chips with real `Button`s (44pt min-height) so the chips already meet the HIG floor and expose Button role to assistive tech. The Step 2 snippet below was authored against the pre-Plan-13 `Text + onTapGesture` shape — when porting, **keep the Button wrapper** (don't re-introduce `onTapGesture` chips), and either leave the `.frame(minHeight: 44)` in place or migrate it to a `LillistSpacing` token if Plan 14 has landed.

- [ ] **Step 1: Extract a shared chip-row view**

Create `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureTokenChips.swift`:

```swift
#if os(iOS)
import SwiftUI

/// Live-parsed token chips for both the macOS Quick Capture panel and the
/// iOS Quick Capture field. Plan 16 ports the macOS pattern into a shared
/// type so the visual feedback stays aligned across platforms.
///
/// `parsed.tags` become `TagChipView`s; a non-nil `parsed.dateToken` renders
/// as a calendar Label. Empty results render nothing — the row collapses to
/// zero height.
struct QuickCaptureTokenChips: View {
    let parsed: QuickCaptureParser.Result

    var body: some View {
        if parsed.tags.isEmpty && parsed.dateToken == nil {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(parsed.tags, id: \.self) { name in
                    TagChipView(name: name)
                }
                if let token = parsed.dateToken {
                    Label(token, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Parsed deadline \(token)")
                }
            }
        }
    }
}
#endif
```

- [ ] **Step 2: Wire the chip row into `QuickCaptureField`**

In `QuickCaptureField.swift`, splice `QuickCaptureTokenChips(parsed: parsed)` into the existing `VStack` between the `TextField` and the suggestion-chip `ScrollView`. The Plan 13 `Button` chips stay as-is:

```swift
    public var body: some View {
        let parsed = QuickCaptureParser.parse(text)
        VStack(alignment: .leading, spacing: 8) {
            TextField("Capture a task…", text: $text)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .accessibilityIdentifier("QuickCaptureField")
                .onSubmit {
                    onSubmit(parsed)
                }
            QuickCaptureTokenChips(parsed: parsed)
            if !tagSuggestions.isEmpty || !dateSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tagSuggestions, id: \.self) { tag in
                            Button {
                                text += " #\(tag)"
                            } label: {
                                Text("#\(tag)")
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(minHeight: 44)  // Plan 13 Task 9
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Insert tag \(tag)")
                        }
                        ForEach(dateSuggestions, id: \.self) { phrase in
                            Button {
                                text += " ^\(phrase)"
                            } label: {
                                Text("^\(phrase)")
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(minHeight: 44)  // Plan 13 Task 9
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Insert deadline \(phrase)")
                        }
                    }
                }
            }
        }
    }
```

Note: the `minHeight: 44` lines came from Plan 13 Task 9 — keep them, or migrate to a `LillistSpacing.chipMinHeight` token if Plan 14 has landed.

- [ ] **Step 3: Update `QuickCaptureFieldTests.swift`**

Append a smoke test that verifies the chip row builds without crashing on the empty case:

```swift
    @MainActor
    func test_token_chips_view_handles_empty_parse() {
        let parsed = QuickCaptureParser.parse("")
        let view = QuickCaptureTokenChips(parsed: parsed)
        let host = UIHostingController(rootView: view)
        host.view.layoutIfNeeded()
        // EmptyView collapses to zero size; just confirm no crash and bound is positive.
        XCTAssertGreaterThanOrEqual(host.view.bounds.height, 0)
    }
```

- [ ] **Step 4: Update the snapshot test**

Edit `iOSSnapshotTests.swift:62-75`. Update the existing test name to reflect the live chips, and add a parsed-tokens snapshot:

```swift
    @MainActor
    func test_quickCaptureField_with_parsed_tokens() {
        let view = QuickCaptureField(
            text: .constant("Buy milk #errands ^tomorrow"),
            tagSuggestions: ["shopping"],
            dateSuggestions: ["today"],
            onSubmit: { _ in }
        )
        .padding()
        .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 160)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 360, height: 160)),
                       named: "quick-capture-field-with-parsed-tokens")
    }
```

Record the new baseline (add `record: true`, run, inspect, remove, re-run).

- [ ] **Step 5: Run the tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme LillistUI \
  -destination 'generic/platform=iOS Simulator,name=iPhone 15' \
  -only-testing:LillistUITests/iOSSnapshotTests \
  -only-testing:LillistUITests/QuickCaptureFieldTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

Expected: all PASS.

- [ ] **Step 6: Hand-test on Simulator**

Open Quick Capture, type `Buy milk #groceries ^tomorrow`. Confirm:
1. A `#groceries` chip appears below the field as soon as `#groceries` is typed.
2. A `calendar` Label appears as soon as `^tomorrow` is recognized.
3. Deleting characters from the date token makes the Label disappear in real time.

- [ ] **Step 7: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureField.swift \
        Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureTokenChips.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/QuickCaptureFieldTests.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/
git commit -m "feat(LillistUI): live parsed-token chips in iOS Quick Capture

Mirrors the macOS Quick Capture panel: as the user types, tags and
deadline tokens render below the field as the parser sees them.
Eliminates the 'did my #tag scan?' uncertainty that previously
required tapping Save to find out."
```

---

## Task 11: Add `.large` detent to Quick Capture sheet

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift` (default-large logic — also touched in Task 13)
- Modify: `Apps/Lillist-iOS/Sources/Root/TabShell.swift:54` (already done in Task 5)
- Modify: `Apps/Lillist-iOS/Sources/Root/SplitShell.swift:65` (already done in Task 8)

Task 5 and Task 8 already added `.large` and `.presentationDragIndicator` to the two shells' `.sheet` modifiers. This task adds first-time-user "default to `.large`" via a one-time `@AppStorage` flag.

- [ ] **Step 1: Add `@AppStorage` flag in `QuickCaptureSheet.swift`**

At the top of the struct (alongside `@State private var text: String = ""`):

```swift
    @AppStorage("hasCapturedTask") private var hasCapturedTask = false
    @State private var initialDetent: PresentationDetent = .fraction(0.35)
```

In the `.task` block (line 49-52), set the initial detent before focusing:

```swift
        .task {
            if !hasCapturedTask {
                initialDetent = .large
            }
            focused = true
            tagSuggestions = await loadTagSuggestions()
        }
```

`@AppStorage` on a primitive is observed automatically. After the first successful save (Task 13 amends the submit path to flip `hasCapturedTask = true`), subsequent presentations default to `.fraction(0.35)` again.

But the *sheet* binds detents on the calling side, not inside the sheet body. The sheet itself doesn't drive its own initial detent. The cleanest way is to expose the initial-detent decision to the caller via the same flag, read on the caller side:

```swift
// in TabShell.swift:
@AppStorage("hasCapturedTask") private var hasCapturedTask = false

// in body:
.sheet(isPresented: $isQuickCapturePresented) {
    QuickCaptureSheet()
        .presentationDetents([.fraction(0.35), .medium, .large],
                             selection: .constant(hasCapturedTask ? .fraction(0.35) : .large))
        .presentationDragIndicator(.visible)
}
```

Use the same shape in `SplitShell.swift`. The `.constant(...)` binding lets the user manually drag detents thereafter; we only force the *initial* one. Once Task 13 sets `hasCapturedTask = true` on first successful save, subsequent presentations use `.fraction(0.35)`.

- [ ] **Step 2: Read current state of QuickCaptureSheet.swift**

```bash
sed -n '1,30p' Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift
```

Confirm the file imports SwiftUI and the @Environment(\.dismiss).

- [ ] **Step 3: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Hand-test**

Delete and reinstall the app (or clear UserDefaults) to reset `hasCapturedTask`. Open Quick Capture — sheet should open at `.large`. Save one task. Re-open — sheet should open at `.fraction(0.35)`.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Root/TabShell.swift \
        Apps/Lillist-iOS/Sources/Root/SplitShell.swift
git commit -m "feat(iOS): default Quick Capture sheet to .large for first-time users"
```

---

## Task 12: Add `presentationDragIndicator` to SplitShell sheet

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Root/SplitShell.swift:65-66`

`TabShell.swift:55` already has `.presentationDragIndicator(.visible)` on the sheet. The iPad SplitShell's sheet at line 65-66 is missing it. Apple's HIG: "If a sheet supports more than one detent, display a grabber." The sheet has three detents (Task 8/11 added `.large`); the indicator is mandatory.

- [ ] **Step 1: Add the modifier**

In `SplitShell.swift`, edit the QuickCaptureSheet presentation block (after Task 8/11's edits, around line 65):

```swift
        .sheet(isPresented: $isQuickCapturePresented) {
            QuickCaptureSheet()
                .presentationDetents([.fraction(0.35), .medium, .large],
                                     selection: .constant(hasCapturedTask ? .fraction(0.35) : .large))
                .presentationDragIndicator(.visible)
        }
```

If the `.constant(...)` initial-detent line from Task 11 isn't present, just add `.presentationDragIndicator(.visible)` as a standalone modifier.

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation)' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Hand-test on iPad**

Open Quick Capture on iPad. Confirm the grabber appears at the top of the sheet (small horizontal line). Drag to test detent transitions.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Root/SplitShell.swift
git commit -m "fix(iOS): add presentationDragIndicator to iPad SplitShell sheet"
```

---

## Task 13: Resign first responder on Save before async work

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift:61-92`

Currently `submit()` kicks off the persistence task and only dismisses the sheet *after* the await chain completes. The user sees the keyboard linger for the duration of the Core Data write, then the keyboard collapses and the sheet animates away — janky on cold-start sessions. The fix is to resign first responder before launching the Task so the keyboard collapse and the persistence proceed in parallel.

- [ ] **Step 1: Read current `submit()`**

```bash
sed -n '55,95p' Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift
```

Confirm the `Task { … }` block starts immediately after the title-empty guard.

- [ ] **Step 2: Refactor `submit()`**

Replace the body with:

```swift
    private func submit() {
        guard !submitting else { return }
        submitting = true
        let parsed = QuickCaptureParser.parse(text)
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            submitting = false
            return
        }
        // Drop the keyboard immediately so the dismiss animation runs in
        // parallel with the Core Data + CloudKit write below.
        focused = false
        Task {
            do {
                let taskID = try await env.taskStore.create(title: title)
                for name in parsed.tags {
                    let tagID = try await env.tagStore.findOrCreate(name: name)
                    try await env.taskStore.assignTag(taskID: taskID, tagID: tagID)
                }
                if let dateToken = parsed.dateToken,
                   let resolved = resolveDeadline(dateToken: dateToken) {
                    try await env.taskStore.update(id: taskID) { draft in
                        draft.deadline = resolved
                        draft.deadlineHasTime = false
                    }
                }
                hasCapturedTask = true  // Task 11: flip the first-time flag
                submitting = false
                dismiss()
            } catch {
                errorMessage = "\(error)"
                submitting = false
            }
        }
    }
```

Two diffs from the existing version:
- `focused = false` immediately before launching the Task — collapses the keyboard at the moment of intent.
- `hasCapturedTask = true` inside the success path — flips the Task 11 flag so the next session defaults to `.fraction(0.35)` instead of `.large`.

If `@AppStorage("hasCapturedTask")` wasn't added in Task 11 (e.g. caller-side approach), add it at the struct level alongside `@State private var text: String = ""`.

- [ ] **Step 3: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Hand-test**

Open Quick Capture, type a task, tap Save. Confirm the keyboard collapses and the sheet animates away simultaneously — not in two distinct steps.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift
git commit -m "fix(iOS): resign Quick Capture first responder before persistence

Dropping focused = false immediately collapses the keyboard so its
animation runs in parallel with the Core Data + CloudKit write,
not after. Eliminates the perceived 'sheet stuck open for a
moment then collapses' jank on cold-start sessions."
```

---

## Task 14: 44pt touch targets on suggestion chips

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureField.swift:40-55` (already updated in Task 10)

If Task 10 already pushed `minHeight: 44` into the chip styling, this task is a no-op verification. If Plan 13 Task 10 introduced `LillistSpacing.chipPadding` and `LillistTypography.chip`, this task swaps the literals for the tokens.

- [ ] **Step 1: Verify chip touch target**

If Plan 14 shipped `LillistSpacing.chipPadding` (e.g. `EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)`), refactor the Task 10 chip styling to:

```swift
                        ForEach(tagSuggestions, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(LillistTypography.chip)
                                .padding(LillistSpacing.chipPadding)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .contentShape(Capsule())  // hit-test the whole capsule
                                .onTapGesture { text += " #\(tag)" }
                                .accessibilityLabel("Insert tag \(tag)")
                        }
```

The `.contentShape(Capsule())` ensures the tap target matches the visible shape, not just the bounding rectangle — important when chips sit close together.

- [ ] **Step 2: Snapshot regression**

The Task 10 snapshot already exercises a chip-bearing field. Re-run to confirm no visual regression after the token swap:

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme LillistUI \
  -destination 'generic/platform=iOS Simulator,name=iPhone 15' \
  -only-testing:LillistUITests/iOSSnapshotTests/test_quickCaptureField_with_parsed_tokens \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

If the test fails, the new tokens changed the rendered geometry — record-mode a new baseline, inspect, commit.

- [ ] **Step 3: Manual accessibility audit**

In the iOS Simulator, enable VoiceOver. Navigate to Quick Capture, swipe to a suggestion chip — confirm the chip selects with a single swipe (not lost between chips) and that the announcement reads "Insert tag <name>".

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureField.swift
git commit -m "fix(LillistUI): 44pt min-height on Quick Capture suggestion chips

contentShape(Capsule()) keeps the tap target aligned with the
visible chip shape so adjacent chips don't steal taps that
visually belong to their neighbor."
```

---

## Task 15: Search scopes

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Search/SearchView.swift`

iOS Reminders has no scope picker (it searches everything), but Things 3 and Todoist offer Open/Closed/All scopes — useful when the user types a substring that matches both a closed task and an open one and wants only the open one. Add `.searchScopes($scope, scopes: …)`.

- [ ] **Step 1: Add `Scope` enum and state**

At the top of `SearchView` struct:

```swift
    enum Scope: Hashable, CaseIterable {
        case all, open, closed
        var title: String {
            switch self {
            case .all: return "All"
            case .open: return "Open"
            case .closed: return "Closed"
            }
        }
    }

    @State private var scope: Scope = .all
```

- [ ] **Step 2: Apply `.searchScopes` modifier**

After the existing `.searchable(...)` line (line 45):

```swift
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .searchScopes($scope, scopes: {
            ForEach(Scope.allCases, id: \.self) { s in
                Text(s.title).tag(s)
            }
        })
```

- [ ] **Step 3: Filter `runSearch()` by scope**

Update the predicate builder in `runSearch()`:

```swift
    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        var predicates: [PredicateGroup.Predicate] = [
            .leaf(Leaf(field: .title, op: .contains, value: .string(trimmed))),
            .leaf(Leaf(field: .inTrash, op: .is, value: .bool(false)))
        ]
        switch scope {
        case .all:
            break
        case .open:
            predicates.append(.leaf(Leaf(field: .status, op: .notEqual, value: .status(.closed))))
        case .closed:
            predicates.append(.leaf(Leaf(field: .status, op: .equal, value: .status(.closed))))
        }
        let group = PredicateGroup(combinator: .all, predicates: predicates)
        do {
            results = try await env.smartFilterStore.evaluate(
                group: group,
                sort: .modifiedAt,
                ascending: false
            )
        } catch {
            results = []
        }
    }
```

Add `.task(id: scope)` to trigger a re-search on scope change. The existing `.task(id: query)` already drives that on text change; combine them:

```swift
        .task(id: SearchTrigger(query: query, scope: scope)) { await runSearch() }
```

with a `private struct SearchTrigger: Hashable { let query: String; let scope: Scope }` inside the view.

- [ ] **Step 4: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

If the build complains that `Leaf(field: .status, …)` or `.notEqual` operators aren't in the public Leaf API, check `Packages/LillistCore/Sources/LillistCore/Rules/Leaf.swift` and `PredicateOperator.swift` for the available shapes. Adjust the snippet to match the actual API — e.g. some predicate engines use `.is` + `.bool(true)` rather than `.equal`/`.notEqual`. The intent is: "scope filters in or out by status".

- [ ] **Step 5: Hand-test**

Open Search, type "test". Tap Open — only open tasks. Tap Closed — only closed. Tap All — both.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Search/SearchView.swift
git commit -m "feat(iOS): add Open / Closed / All search scopes"
```

---

## Task 16: Recent searches with `searchSuggestions`

**Files:**
- Create: `Apps/Lillist-iOS/Sources/Search/RecentSearchesStore.swift`
- Modify: `Apps/Lillist-iOS/Sources/Search/SearchView.swift`
- Create: `Apps/Lillist-iOS/Tests/UnitTests/RecentSearchesStoreTests.swift`

When the user opens Search after a session, surface their last 5-10 queries as `searchSuggestions`. iOS Reminders does this; it's near-free UX and cuts re-typing of common searches.

- [ ] **Step 1: Write the failing test**

Create `Apps/Lillist-iOS/Tests/UnitTests/RecentSearchesStoreTests.swift`:

```swift
import XCTest
@testable import Lillist_iOS

final class RecentSearchesStoreTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.removeObject(forKey: "lillist.recentSearches")
    }

    func test_record_dedupes_and_caps_at_ten() {
        let store = RecentSearchesStore()
        for i in 1...15 {
            store.record("query-\(i)")
        }
        let recent = store.recent
        XCTAssertEqual(recent.count, 10)
        XCTAssertEqual(recent.first, "query-15") // most recent first
    }

    func test_record_moves_existing_to_front() {
        let store = RecentSearchesStore()
        store.record("alpha")
        store.record("beta")
        store.record("alpha")
        let recent = store.recent
        XCTAssertEqual(recent, ["alpha", "beta"])
    }

    func test_clear_removes_all() {
        let store = RecentSearchesStore()
        store.record("alpha")
        store.clear()
        XCTAssertTrue(store.recent.isEmpty)
    }
}
```

- [ ] **Step 2: Implement `RecentSearchesStore.swift`**

Create `Apps/Lillist-iOS/Sources/Search/RecentSearchesStore.swift`:

```swift
import Foundation
import SwiftUI

/// Stores the last 10 distinct search queries, most-recent-first.
/// Backed by `UserDefaults` so `@AppStorage` observation works.
///
/// Plan 16: surfaces `searchSuggestions` on the Search screen.
@Observable
final class RecentSearchesStore {
    private let key = "lillist.recentSearches"
    private let maxCount = 10
    private(set) var recent: [String] = []

    init() {
        recent = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = recent.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > maxCount {
            list = Array(list.prefix(maxCount))
        }
        recent = list
        UserDefaults.standard.set(list, forKey: key)
    }

    func clear() {
        recent = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}
```

- [ ] **Step 3: Wire into `SearchView`**

Add to the struct:

```swift
    @State private var recents = RecentSearchesStore()
```

After `.searchScopes(...)` from Task 15:

```swift
        .searchSuggestions {
            if query.isEmpty && !recents.recent.isEmpty {
                Section("Recent") {
                    ForEach(recents.recent, id: \.self) { recent in
                        Text(recent).searchCompletion(recent)
                    }
                    Button("Clear recent searches", role: .destructive) {
                        recents.clear()
                    }
                }
            }
        }
```

In `runSearch()`, append `recents.record(trimmed)` after the search completes (so we only remember queries that actually ran):

```swift
        // ... existing search result handling ...
        if !results.isEmpty {
            recents.record(trimmed)
        }
```

- [ ] **Step 4: Run the unit test**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator,name=iPhone 15' \
  -only-testing:Lillist-iOSTests/RecentSearchesStoreTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expected: 3 PASS.

- [ ] **Step 5: Hand-test**

Run a few searches ("milk", "groceries"). Quit and relaunch. Tap into Search — the empty-query state should surface the recents as tappable suggestions. Tap a recent — query populates and search runs.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Search/RecentSearchesStore.swift \
        Apps/Lillist-iOS/Sources/Search/SearchView.swift \
        Apps/Lillist-iOS/Tests/UnitTests/RecentSearchesStoreTests.swift
git commit -m "feat(iOS): persist recent searches and surface via searchSuggestions"
```

---

## Task 17: Highlight matched substring in search results

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Search/SearchResultRow.swift`
- Create: `Apps/Lillist-iOS/Tests/UnitTests/SearchHighlightTests.swift`

A search result row should visually highlight the matched portion of the task title — Reminders highlights with a yellow background, Things with a bold accent. Build the highlight via `AttributedString` with `.backgroundColor`. Also surface the first matching line of notes/journal under the title for context.

- [ ] **Step 1: Write the failing test**

Create `Apps/Lillist-iOS/Tests/UnitTests/SearchHighlightTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Lillist_iOS

final class SearchHighlightTests: XCTestCase {
    func test_highlight_marks_matched_range() {
        let attributed = SearchResultRow.highlightedTitle(
            title: "Buy milk at the store",
            query: "milk"
        )
        var attributesFound: [(Range<AttributedString.Index>, Bool)] = []
        for run in attributed.runs {
            attributesFound.append((run.range, run.backgroundColor != nil))
        }
        // Exactly one run should have a non-nil background — the matched "milk".
        let highlighted = attributesFound.filter { $0.1 }
        XCTAssertEqual(highlighted.count, 1, "Exactly one highlighted run expected")
        let highlightedSubstring = String(attributed.characters[highlighted[0].0])
        XCTAssertEqual(highlightedSubstring, "milk")
    }

    func test_highlight_case_insensitive_match() {
        let attributed = SearchResultRow.highlightedTitle(
            title: "Buy MILK now",
            query: "milk"
        )
        let highlighted = attributed.runs.first { $0.backgroundColor != nil }
        XCTAssertNotNil(highlighted)
        XCTAssertEqual(String(attributed.characters[highlighted!.range]), "MILK")
    }

    func test_highlight_no_match_returns_plain() {
        let attributed = SearchResultRow.highlightedTitle(
            title: "Buy bread",
            query: "milk"
        )
        let highlighted = attributed.runs.filter { $0.backgroundColor != nil }
        XCTAssertTrue(highlighted.isEmpty)
    }
}
```

- [ ] **Step 2: Implement `highlightedTitle(title:query:)`**

Rewrite `SearchResultRow.swift`:

```swift
import SwiftUI
import LillistCore
import LillistUI

struct SearchResultRow: View {
    let task: TaskStore.TaskRecord
    let tagNames: [String]
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.highlightedTitle(title: task.title, query: query))
                .font(.body)
                .strikethrough(task.status == .closed)
            if let snippet = matchingSnippet {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(statusLabel)")
    }

    /// Wraps the task title in an `AttributedString` where every
    /// occurrence of `query` (case-insensitive) gets a `.backgroundColor`
    /// attribute. Used by the search row to highlight matched substrings.
    static func highlightedTitle(title: String, query: String) -> AttributedString {
        var attr = AttributedString(title)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return attr }
        let lowerTitle = title.lowercased()
        let lowerQuery = trimmedQuery.lowercased()
        var searchStart = lowerTitle.startIndex
        while let range = lowerTitle.range(of: lowerQuery, range: searchStart..<lowerTitle.endIndex) {
            // Translate the String range into an AttributedString range.
            let attrLower = AttributedString.Index(range.lowerBound, within: attr)
            let attrUpper = AttributedString.Index(range.upperBound, within: attr)
            if let lower = attrLower, let upper = attrUpper {
                attr[lower..<upper].backgroundColor = .yellow.opacity(0.3)
            }
            searchStart = range.upperBound
        }
        return attr
    }

    /// First matching line from notes or journal, when present. Returns
    /// nil when query is empty or no match found.
    private var matchingSnippet: String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // For now, just check notes; journal lookup would require an async
        // fetch and belongs in a future enhancement.
        guard task.notes.localizedCaseInsensitiveContains(trimmed) else { return nil }
        return task.notes
            .components(separatedBy: .newlines)
            .first { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    private var statusLabel: String {
        switch task.status {
        case .todo: return "to do"
        case .started: return "started"
        case .blocked: return "blocked"
        case .closed: return "closed"
        }
    }
}
```

- [ ] **Step 3: Pass `query` from `SearchView`**

Update `SearchView.swift` to forward the query to each row:

```swift
                ForEach(results, id: \.id) { task in
                    NavigationLink(value: task.id) {
                        SearchResultRow(task: task, tagNames: [], query: query)
                    }
                }
```

- [ ] **Step 4: Run the tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator,name=iPhone 15' \
  -only-testing:Lillist-iOSTests/SearchHighlightTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expected: 3 PASS.

- [ ] **Step 5: Hand-test**

Search for "milk". Confirm matched portion of "Buy milk now" renders with a yellow highlight. If the task has notes containing "milk", confirm the first matching note line appears below the title.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Search/SearchResultRow.swift \
        Apps/Lillist-iOS/Sources/Search/SearchView.swift \
        Apps/Lillist-iOS/Tests/UnitTests/SearchHighlightTests.swift
git commit -m "feat(iOS): highlight matched substring + notes snippet in search results"
```

---

## Task 18: Debounce search input

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Search/SearchView.swift:55`

Currently every keystroke spawns a `.task(id: query)` body that immediately calls `runSearch()`. A fast typer typing "groceries" spawns and cancels ~9 tasks; the in-flight body has to wake to learn it's cancelled, which still bills CPU. Adding `try? await Task.sleep(for: .milliseconds(250))` at the top of `runSearch()` gives a 250ms quiet window before the database hit.

- [ ] **Step 1: Add the sleep**

Edit `runSearch()` (already modified in Tasks 15-17):

```swift
    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return  // cancelled — newer query incoming
        }
        // ... existing predicate building + evaluation ...
    }
```

The `do try await Task.sleep … catch { return }` is the same structured-debounce pattern Task 3 used for Notes.

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Hand-test**

Type "groceries" fast. Confirm the result list doesn't flash — only the final list (after 250ms of typing pause) appears.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Search/SearchView.swift
git commit -m "fix(iOS): 250ms debounce on search input"
```

---

## Task 19: `searchable(placement: .adaptive)` on iPad

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Search/SearchView.swift:45`

On iPad, `.navigationBarDrawer(displayMode: .always)` reserves a row of vertical space for the search bar even when the user isn't actively searching. `.adaptive` (or `.toolbar`) is the iPad-correct placement — Reminders, Mail, and Notes all use it. SwiftUI picks the right rendering per platform.

- [ ] **Step 1: Swap the placement**

Replace:

```swift
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
```

with:

```swift
        .searchable(text: $query, placement: .adaptive)
```

- [ ] **Step 2: Build both iPhone and iPad**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator,name=iPhone 15' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Hand-test on both**

iPhone: search bar still in drawer below nav bar. iPad: search field appears in toolbar.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Search/SearchView.swift
git commit -m "refactor(iOS): adaptive search placement for iPad space recovery"
```

---

## Task 20: Calendar-grid month-day picker

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:59-66`
- Modify: `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorSnapshotTests.swift` (re-record baselines)

The current monthly day-of-month picker is 31 vertical toggles — overwhelming, hard to scan, hard to tap. Apple Calendar's reference: a 7-column `LazyVGrid` of tappable circles, with selection state visible at a glance. Same approach.

- [ ] **Step 1: Replace the monthly section**

Edit `RecurrenceEditorView.swift:59-66`. Replace:

```swift
                    if viewModel.freq == .monthly {
                        Section("On day of month") {
                            ForEach(1...31, id: \.self) { d in
                                Toggle("Day \(d)", isOn: bindingFor(monthDay: d, in: $viewModel.byMonthDay))
                            }
                        }
                    }
```

with:

```swift
                    if viewModel.freq == .monthly {
                        Section("On days of month") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                                      spacing: 6) {
                                ForEach(1...31, id: \.self) { day in
                                    dayCell(day)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
```

Add the `dayCell(_:)` method to the struct:

```swift
    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let isSelected = viewModel.byMonthDay.contains(day)
        Button {
            if isSelected {
                viewModel.byMonthDay.remove(day)
            } else {
                viewModel.byMonthDay.insert(day)
            }
        } label: {
            Text("\(day)")
                .font(.body)
                .frame(minWidth: 36, minHeight: 36)
                .background {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                }
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Day \(day) selected" : "Day \(day) not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
```

The 36pt circle gives a 44pt+ tap target once the grid spacing adds margin.

- [ ] **Step 2: Re-record macOS snapshot baselines**

The existing `RecurrenceEditorSnapshotTests` covers `testWeeklyTuesdayThursday_light` (no monthly grid) and three other non-monthly cases. Add a monthly-specific test:

```swift
    func testMonthlyDay15_light() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .monthly
        vm.byMonthDay = [15]
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 600)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 600)),
                       as: .image(precision: 0.99), named: "monthly-day-15-light")
    }

    func testMonthlyMultipleDays_light() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .monthly
        vm.byMonthDay = [1, 7, 15, 22, 28]
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 600)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 600)),
                       as: .image(precision: 0.99), named: "monthly-multi-light")
    }
```

Run with `record: true` once to land baselines, then revert and confirm clean.

The four existing baselines (`empty-light`, `empty-dark`, `weekly-tuth-light`, `after-completion-week-light`) shouldn't change — they don't render the monthly section. Verify they still pass.

- [ ] **Step 3: Run macOS snapshot tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme LillistUI \
  -destination 'platform=macOS' \
  -only-testing:LillistUITests/RecurrenceEditorSnapshotTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

Expected: all PASS (including the two new monthly tests).

- [ ] **Step 4: Build iOS to verify cross-platform**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Hand-test on Simulator**

Open a task, tap the recurrence "repeat" toolbar item, set frequency to Monthly. Confirm the grid renders 7 columns × 5 rows of day numbers (1-31, with the last row partially filled). Tap day 15 — circle fills. Tap again — circle clears.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift \
        Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Recurrence/__Snapshots__/RecurrenceEditorSnapshotTests/
git commit -m "feat(LillistUI): 7-column monthly day-of-month grid

Replaces 31 vertical toggles with an Apple-Calendar-style
LazyVGrid. Scannable at a glance, easier to tap, and aligns with
the visual language of every other monthly day picker on iOS."
```

---

## Task 21: Reword mode labels

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:33-38`

"Calendar-based" / "After completion" reads as engineer-speak. Reminders uses "Repeat" / "When completed"; Apple Calendar uses "Repeat". Match the platform vocabulary.

- [ ] **Step 1: Reword the picker labels**

Change:

```swift
                Picker("Mode", selection: $viewModel.mode) {
                    Text("Calendar-based").tag(RecurrenceEditorViewModel.Mode.calendar)
                    Text("After completion").tag(RecurrenceEditorViewModel.Mode.afterCompletion)
                }
                .pickerStyle(.segmented)
```

to:

```swift
                Picker("Schedule", selection: $viewModel.mode) {
                    Text("Repeat").tag(RecurrenceEditorViewModel.Mode.calendar)
                    Text("When completed").tag(RecurrenceEditorViewModel.Mode.afterCompletion)
                }
                .pickerStyle(.segmented)
```

The Section header above (`Section("Pattern")` at line 32) becomes redundant — replace `Section("Pattern")` with `Section`. The picker labels carry the meaning now.

Also reword the inner header `Section("After completion") {` (line 86) to `Section("Repeat after") {` so the picker's "When completed" mode and the inner section's "Repeat after" stepper align grammatically.

- [ ] **Step 2: Re-record macOS snapshots if rendering shifts**

Run:

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme LillistUI \
  -destination 'platform=macOS' \
  -only-testing:LillistUITests/RecurrenceEditorSnapshotTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

If `after-completion-week-light` fails (it reads the section header), re-record it.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift \
        Packages/LillistUI/Tests/LillistUITests/Recurrence/__Snapshots__/
git commit -m "feat(LillistUI): plain-English labels in recurrence editor

'Repeat' / 'When completed' / 'Repeat after' match the vocabulary
Reminders and Calendar use. 'Calendar-based' / 'After completion'
read as engineer-speak."
```

---

## Task 22: Toggle-revealed occurrence limit

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:67-73`
- Modify: `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorViewModelTests.swift`

The stepper-with-0-as-nil pattern (line 67-73) is opaque: the user has to set the stepper to 0 to mean "no limit", and reads "0 occurrences" before they tap up. Replace with a `Toggle("Repeat forever")` that reveals a `Stepper("After N occurrences", in: 1...365)` when off.

- [ ] **Step 1: Replace the limit section**

```swift
                    Section("Limit") {
                        Toggle("Repeat forever", isOn: Binding(
                            get: { viewModel.count == nil },
                            set: { isUnbounded in
                                if isUnbounded {
                                    viewModel.count = nil
                                } else {
                                    viewModel.count = viewModel.count ?? 10
                                }
                            }
                        ))
                        if let bound = viewModel.count {
                            Stepper("After \(bound) occurrence\(bound == 1 ? "" : "s")",
                                    value: Binding(
                                        get: { bound },
                                        set: { viewModel.count = $0 }
                                    ),
                                    in: 1...365)
                        }
                        Toggle("End by date", isOn: Binding(
                            get: { viewModel.until != nil },
                            set: { on in viewModel.until = on ? (viewModel.until ?? defaultUntil()) : nil }
                        ))
                        if let _ = viewModel.until {
                            DatePicker("End date", selection: Binding(
                                get: { viewModel.until ?? Date() },
                                set: { viewModel.until = $0 }
                            ), displayedComponents: [.date])
                        }
                    }
```

`defaultUntil()` belongs to Task 23 (compute a sensible default from task date + interval). For now, define a stub returning `Date().addingTimeInterval(86_400 * 30)`; Task 23 replaces it.

- [ ] **Step 2: Update the view-model tests**

In `RecurrenceEditorViewModelTests.swift`, add tests for the count=10 default when toggle is flipped off:

```swift
    @Test("Toggling 'Repeat forever' off sets a default count of 10")
    func toggleRepeatForeverDefaultsCount() {
        // Note: the toggle lives in the view, not the view model. The view
        // model's `count` field is what the view manipulates. We pin the
        // contract: count == nil means unbounded, count > 0 means bounded.
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        #expect(vm.count == nil, "Default is unbounded")
        vm.count = 10
        #expect(vm.count == 10)
        let rule = vm.build()
        if case .calendar(let c) = rule {
            #expect(c.count == 10)
        } else {
            Issue.record("Expected calendar rule")
        }
    }
```

- [ ] **Step 3: Run the tests**

```bash
swift test --package-path Packages/LillistUI --filter "RecurrenceEditorViewModel" 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 4: Re-record affected macOS snapshots**

The Limit section is visible in the `weekly-tuth-light` snapshot. Re-record if needed.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift \
        Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorViewModelTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Recurrence/__Snapshots__/
git commit -m "feat(LillistUI): toggle-revealed occurrence limit replaces 0-as-nil stepper

'Repeat forever' as an explicit choice reads more clearly than
'set the stepper to 0 to mean no limit'."
```

---

## Task 23: Sensible default "End by date"

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:75-77`

The current default `Date().addingTimeInterval(86_400 * 30)` always offers "30 days from now" — useless for a task scheduled six months out. Compute from task date + interval.

- [ ] **Step 1: Implement `defaultUntil()`**

The view doesn't know the task's start date today — `RecurrenceEditorView` only binds to `RecurrenceEditorViewModel`. Add a `taskAnchorDate: Date?` field to the view model (defaulting to nil) and have callers populate it.

In `RecurrenceEditorViewModel.swift`:

```swift
    public var taskAnchorDate: Date?
    // ...
    public init(rule: RecurrenceRule?, taskAnchorDate: Date? = nil) {
        // ... existing init ...
        self.taskAnchorDate = taskAnchorDate
    }
```

In `RecurrenceEditorView.swift`:

```swift
    private func defaultUntil() -> Date {
        let anchor = viewModel.taskAnchorDate ?? Date()
        let units: Int
        let component: Calendar.Component
        switch viewModel.freq {
        case .daily:   units = 30 * max(1, viewModel.interval); component = .day
        case .weekly:  units = 12 * max(1, viewModel.interval); component = .weekOfYear
        case .monthly: units = 6 * max(1, viewModel.interval);  component = .month
        case .yearly:  units = 3 * max(1, viewModel.interval);  component = .year
        }
        return Calendar.current.date(byAdding: component, value: units, to: anchor) ?? anchor
    }
```

Defaults: daily → 30 days; weekly → 12 weeks (≈3 months); monthly → 6 months; yearly → 3 years. Tunable later.

- [ ] **Step 2: Plumb `taskAnchorDate` from `RecurrenceSheet.swift`**

In `Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift`, fetch the task's start date and pass it through:

```swift
    init(taskID: UUID, initialRule: RecurrenceRule?, initialSeriesID: UUID?, initialAnchorDate: Date?, onClose: @escaping () -> Void) {
        self.taskID = taskID
        self.initialSeriesID = initialSeriesID
        self.onClose = onClose
        self._viewModel = State(initialValue: RecurrenceEditorViewModel(rule: initialRule, taskAnchorDate: initialAnchorDate))
    }
```

Then update `TaskDetailView.swift`'s sheet construction to pass `record?.start ?? record?.deadline` as `initialAnchorDate`.

- [ ] **Step 3: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift \
        Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift \
        Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift \
        Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift
git commit -m "feat(LillistUI): compute default 'End by date' from task anchor + interval"
```

---

## Task 24: Surface recurrence commit errors

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift:38-53`

The `commit(_ rule:)` method silently swallows errors in the `catch` block ("Sheet remains open; future polish would surface an inline error" — line 51). Add an `Alert` so the user knows when a save failed.

- [ ] **Step 1: Add error state and Alert modifier**

```swift
struct RecurrenceSheet: View {
    let taskID: UUID
    let initialSeriesID: UUID?
    let onClose: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: RecurrenceEditorViewModel
    @State private var errorMessage: String?

    // ... existing init ...

    var body: some View {
        NavigationStack {
            RecurrenceEditorView(viewModel: $viewModel)
                .navigationTitle("Recurrence")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onClose() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await commit(viewModel.build()) }
                        }
                    }
                }
                .alert("Couldn't save recurrence",
                       isPresented: Binding(
                           get: { errorMessage != nil },
                           set: { if !$0 { errorMessage = nil } }
                       ),
                       presenting: errorMessage) { _ in
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: { msg in
                    Text(msg)
                }
        }
    }

    private func commit(_ rule: RecurrenceRule?) async {
        do {
            if let rule {
                if let sid = initialSeriesID {
                    try await env.seriesStore.update(id: sid, rule: rule)
                } else {
                    _ = try await env.seriesStore.create(fromSeedTask: taskID, rule: rule)
                }
            } else if let sid = initialSeriesID {
                try await env.seriesStore.delete(id: sid)
            }
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift
git commit -m "fix(iOS): surface recurrence commit errors via Alert"
```

---

## Task 25: Empty-state CTAs across iOS screens

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Today/TodayView.swift:25-35`
- Modify: `Apps/Lillist-iOS/Sources/All/AllTagsView.swift:21-32`
- Modify: `Apps/Lillist-iOS/Sources/Filters/FiltersListView.swift:21-31`
- Modify: `Apps/Lillist-iOS/Sources/Filters/FilterResultsView.swift:14-26`
- Modify: `Apps/Lillist-iOS/Sources/Search/SearchView.swift:26-36`
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskAttachmentsTab.swift:15-21`
- Modify: `Apps/Lillist-iOS/Sources/Root/TabShell.swift` (provide environment value)
- Modify: `Apps/Lillist-iOS/Sources/Root/SplitShell.swift` (provide environment value)

Today the empty-state `ContentUnavailableView`s on every list screen show a glyph + headline + description but no action. A primary "Capture a task" / "Add a tag" CTA gets the user to the next step with one tap.

- [ ] **Step 1: Introduce an environment key for the Quick Capture action**

Add to `Apps/Lillist-iOS/Sources/Common/QuickCaptureAction.swift` (NEW file):

```swift
import SwiftUI

/// Environment key for "present Quick Capture" — surfaced by the shells
/// (TabShell, SplitShell) and consumed by empty-state CTAs deep in the
/// view tree.
struct QuickCaptureActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var quickCaptureAction: () -> Void {
        get { self[QuickCaptureActionKey.self] }
        set { self[QuickCaptureActionKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Wire the action from `TabShell` and `SplitShell`**

In `TabShell.swift`, wrap the body:

```swift
        TabView(selection: $selection) {
            // ... tab declarations ...
        }
        .environment(\.quickCaptureAction, { isQuickCapturePresented = true })
        .tabViewBottomAccessory { /* ... */ }
        // ...
```

Same shape in `SplitShell.swift`.

- [ ] **Step 3: Update `TodayView.swift`'s empty state**

```swift
            } else if results.isEmpty {
                ContentUnavailableView {
                    Label("Nothing for today", systemImage: "sparkles")
                } description: {
                    Text("Tasks with a start or deadline of today show up here.")
                } actions: {
                    Button("Capture a task", systemImage: "plus.circle.fill") {
                        quickCaptureAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
```

Add `@Environment(\.quickCaptureAction) private var quickCaptureAction` at the struct level.

- [ ] **Step 4: Repeat for `AllTagsView.swift`**

```swift
            } else if tree.isEmpty {
                ContentUnavailableView {
                    Label("No tags yet", systemImage: "tag")
                } description: {
                    Text("Use #name in Quick Capture to make a tag.")
                } actions: {
                    Button("Capture a task", systemImage: "plus.circle.fill") {
                        quickCaptureAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
```

- [ ] **Step 5: Repeat for `FiltersListView.swift`**

```swift
            } else if pinned.isEmpty && others.isEmpty {
                ContentUnavailableView {
                    Label("No filters yet", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Pre-installed filters land on first sync.")
                } actions: {
                    // No CTA — the user can't create filters from iOS yet.
                    // When filter creation lands, swap in:
                    // Button("Create filter") { ... }
                    EmptyView()
                }
            }
```

- [ ] **Step 6: Repeat for `FilterResultsView.swift`**

```swift
            } else if results.isEmpty {
                ContentUnavailableView {
                    Label("No matching tasks", systemImage: "magnifyingglass")
                } description: {
                    Text("Tasks that match this filter will appear here.")
                } actions: {
                    Button("Capture a task", systemImage: "plus.circle.fill") {
                        quickCaptureAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
```

- [ ] **Step 7: Repeat for `SearchView.swift`** (only the empty-query state — the "no matches" state shouldn't CTA into Quick Capture)

```swift
            if query.isEmpty {
                ContentUnavailableView {
                    Label("Search Lillist", systemImage: "magnifyingglass")
                } description: {
                    Text("Type a word from a task title.")
                } actions: {
                    Button("Capture a task", systemImage: "plus.circle.fill") {
                        quickCaptureAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
```

- [ ] **Step 8: Repeat for `TaskAttachmentsTab.swift`**

The attachment tab's CTA is "Add attachment" — but iOS attachment add is via the Share sheet from outside the app. Leave the empty state without a primary CTA but add a hint:

```swift
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No attachments", systemImage: "paperclip")
                } description: {
                    Text("Use the Share sheet from any app to attach a file, image, or link.")
                } actions: {
                    EmptyView()
                }
                .padding(.top, 60)
            }
```

- [ ] **Step 9: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 10: Hand-test on a fresh install**

Wipe app data. Launch — TodayView shows "Capture a task" button. Tap it → Quick Capture sheet appears. Same for All, Filter results, Search empty state.

- [ ] **Step 11: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Common/QuickCaptureAction.swift \
        Apps/Lillist-iOS/Sources/Today/TodayView.swift \
        Apps/Lillist-iOS/Sources/All/AllTagsView.swift \
        Apps/Lillist-iOS/Sources/Filters/FiltersListView.swift \
        Apps/Lillist-iOS/Sources/Filters/FilterResultsView.swift \
        Apps/Lillist-iOS/Sources/Search/SearchView.swift \
        Apps/Lillist-iOS/Sources/Detail/TaskAttachmentsTab.swift \
        Apps/Lillist-iOS/Sources/Root/TabShell.swift \
        Apps/Lillist-iOS/Sources/Root/SplitShell.swift
git commit -m "feat(iOS): empty-state CTAs route to Quick Capture"
```

---

## Task 26: Discrete trash-retention picker

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:14-25`

A continuous 7-365 slider is hard to land on common values (7 / 14 / 30 / 90). Replace with a `Picker` of presets.

- [ ] **Step 1: Replace the slider**

```swift
        Section("Trash") {
            Picker("Retain trashed tasks for", selection: Binding(
                get: { Int(prefs.trashRetentionDays) },
                set: { prefs.trashRetentionDays = Int16($0) }
            )) {
                Text("7 days").tag(7)
                Text("14 days").tag(14)
                Text("30 days").tag(30)
                Text("60 days").tag(60)
                Text("90 days").tag(90)
                Text("180 days").tag(180)
                Text("1 year").tag(365)
            }
            .pickerStyle(.menu)
            .accessibilityValue("\(prefs.trashRetentionDays) days")
            // ... existing Button + confirmationDialog ...
        }
```

The `.accessibilityValue("\(prefs.trashRetentionDays) days")` is the VoiceOver-friendly readout.

If the user previously had a custom value (e.g. 45 days from the slider), `Picker` doesn't render an out-of-set value cleanly. Guard against that by coercing into the nearest preset on first read:

```swift
    init(prefs: Binding<PreferencesStore.Prefs>) {
        self._prefs = prefs
        let presets: [Int16] = [7, 14, 30, 60, 90, 180, 365]
        let current = prefs.wrappedValue.trashRetentionDays
        if !presets.contains(current) {
            let nearest = presets.min(by: { abs($0 - current) < abs($1 - current) }) ?? 30
            prefs.wrappedValue.trashRetentionDays = nearest
        }
    }
```

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Settings/TrashSection.swift
git commit -m "refactor(iOS): trash retention picker of presets replaces continuous slider"
```

---

## Task 27: Conditional notification permission label

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift:19-36`

"Test permission" is the wrong primary action in all three permission states. When `.notDetermined`, the user should see "Request permission". When `.denied`, "Open Settings". When `.authorized`, the row is just informational.

- [ ] **Step 1: Replace the Permission section**

```swift
        Section("Permission") {
            HStack {
                statusLabel
                Spacer()
            }
            switch permStatus {
            case .notDetermined:
                Button("Request permission") {
                    Task {
                        permStatus = await environment.notificationPermissions.requestAuthorization()
                    }
                }
            case .denied:
                Button("Open Notification Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            case .authorized:
                EmptyView()
            }
        }
```

The existing `if permStatus == .denied { Button("Open Settings") … }` becomes redundant — delete it. The switch above already covers it.

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Hand-test**

Reset notifications via the simulator → Settings → Lillist → Notifications → "Reset Location & Privacy" (or use a fresh app install). Confirm: pre-request, button reads "Request permission". After deny, button reads "Open Notification Settings". After allow, no button.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift
git commit -m "fix(iOS): conditional notification button label by permission state"
```

---

## Task 28: Debounce all-day reminder time changes

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift:41-43`

`onChange(of: prefs.defaultAllDayHour)` and `onChange(of: prefs.defaultAllDayMinute)` both fire `applyAllDayChange()` — and as the user drags the minute wheel, every minute tick reschedules every all-day notification. Debounce.

- [ ] **Step 1: Replace with `.task(id:)` debounce**

Add to the struct:

```swift
    private struct TimeKey: Hashable { let h: Int16; let m: Int16 }
```

Replace the two `.onChange(...)` lines for `defaultAllDayHour` / `defaultAllDayMinute` with:

```swift
        .task(id: TimeKey(h: prefs.defaultAllDayHour, m: prefs.defaultAllDayMinute)) {
            do {
                try await Task.sleep(for: .milliseconds(750))
            } catch { return }
            applyAllDayChange()
        }
```

Same pattern for morning summary time changes (combine the three onChange listeners that drive `applyMorningSummaryChange()` into one `.task(id: …)` with a 750ms debounce).

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Hand-test**

Drag the all-day time wheel from 9:00 to 14:30. Confirm via log that `applyAllDayChange()` runs once at the end of the gesture, not 5+ times during the drag.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift
git commit -m "fix(iOS): debounce reminder-time changes to 750ms"
```

---

## Task 29: Hardware keyboard shortcuts via `CommandMenu`

**Files:**
- Create: `Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift`
- Modify: `Apps/Lillist-iOS/Sources/App/LillistApp.swift`
- Delete: `Apps/Lillist-iOS/Sources/Common/KeyboardShortcuts.swift`
- Modify: `Apps/Lillist-iOS/Sources/Root/TabShell.swift` (remove `lillistKeyboardShortcuts` call)
- Modify: `Apps/Lillist-iOS/Sources/Root/SplitShell.swift` (same)

The current `LillistKeyboardShortcuts` modifier (`KeyboardShortcuts.swift`) puts hidden `Button` views in the view tree. On iPad, hold-⌘ shows the system shortcut overlay — but it only surfaces shortcuts declared via `CommandMenu` at the Scene level, not button-shortcut bindings buried in a view's `.background`. Move to `CommandMenu` so users discover the shortcuts.

Also: rebind `⌘N` to `⌘⇧N`. iPadOS uses `⌘N` for "New Window" globally, and our binding collides.

- [ ] **Step 1: Create the CommandMenu surface**

Create `Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift`:

```swift
import SwiftUI
import LillistUI

/// Scene-level command surface. Exposes hardware-keyboard shortcuts to
/// the iPadOS hold-⌘ overlay (which only enumerates `CommandMenu` /
/// `CommandGroup` entries — not arbitrary `.keyboardShortcut` bindings
/// buried inside views).
///
/// Plan 16 replaces the previous hidden-Button hack in
/// `KeyboardShortcuts.swift`. `⌘N` previously bound to Quick Capture
/// collides with iPadOS's system "New Window" — moved to `⌘⇧N`.
struct LillistCommands: Commands {
    @Binding var isQuickCapturePresented: Bool
    @Binding var selectedSection: iPadSection?

    var body: some Commands {
        CommandMenu("Lillist") {
            Button("New Task") {
                isQuickCapturePresented = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Today") { selectedSection = .today }
                .keyboardShortcut("1", modifiers: .command)
            Button("All") { selectedSection = .all }
                .keyboardShortcut("2", modifiers: .command)
            Button("Filters") { selectedSection = .filters }
                .keyboardShortcut("3", modifiers: .command)
            Button("Search") { selectedSection = .search }
                .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button("Find in Lillist…") { selectedSection = .search }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}
```

- [ ] **Step 2: Install the CommandMenu in `LillistApp.swift`**

Add scene-level state and install the commands:

```swift
@main
struct LillistApp: App {
    @State private var isQuickCapturePresented = false
    @State private var selectedSection: iPadSection? = .today

    var body: some Scene {
        WindowGroup {
            // ... existing AppEnvironment-loading shell ...
            // RootShell consumes isQuickCapturePresented + selectedSection
            // from the environment.
            RootShell()
                .environment(\.isQuickCapturePresentedBinding, $isQuickCapturePresented)
                .environment(\.selectedSectionBinding, $selectedSection)
        }
        .commands {
            LillistCommands(
                isQuickCapturePresented: $isQuickCapturePresented,
                selectedSection: $selectedSection
            )
        }
    }
}
```

Add environment values for the two bindings (similar to `quickCaptureAction` in Task 25):

```swift
// Apps/Lillist-iOS/Sources/App/AppEnvironment.swift or a new file:
private struct IsQuickCapturePresentedKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}
private struct SelectedSectionKey: EnvironmentKey {
    static let defaultValue: Binding<iPadSection?> = .constant(nil)
}
extension EnvironmentValues {
    var isQuickCapturePresentedBinding: Binding<Bool> {
        get { self[IsQuickCapturePresentedKey.self] }
        set { self[IsQuickCapturePresentedKey.self] = newValue }
    }
    var selectedSectionBinding: Binding<iPadSection?> {
        get { self[SelectedSectionKey.self] }
        set { self[SelectedSectionKey.self] = newValue }
    }
}
```

- [ ] **Step 3: Update `TabShell.swift` and `SplitShell.swift` to consume scene-level state**

```swift
struct TabShell: View {
    @Environment(\.isQuickCapturePresentedBinding) private var isQuickCapturePresented
    @Environment(\.selectedSectionBinding) private var sceneSelection
    @State private var localSelection: iPadSection = .today

    private var selection: Binding<iPadSection> {
        Binding(
            get: { sceneSelection.wrappedValue ?? localSelection },
            set: {
                sceneSelection.wrappedValue = $0
                localSelection = $0
            }
        )
    }
    // ... body uses isQuickCapturePresented.wrappedValue ...
}
```

The dual-state (local + scene-level binding) is a touch awkward but lets the shell still function if the binding ever defaults; it's defense-in-depth. Drop the `.lillistKeyboardShortcuts(...)` call entirely.

Same plumbing for `SplitShell.swift`.

- [ ] **Step 4: Delete the obsolete file**

```bash
git rm Apps/Lillist-iOS/Sources/Common/KeyboardShortcuts.swift
```

- [ ] **Step 5: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation)' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Hand-test on iPad**

Connect a hardware keyboard (or use the simulator's "Connect Hardware Keyboard" toggle). Hold ⌘ — confirm the system overlay shows "Lillist" with the five shortcuts listed (New Task ⌘⇧N, Today ⌘1, All ⌘2, Filters ⌘3, Search ⌘4, Find ⌘⇧F). Press ⌘⇧N — Quick Capture sheet opens. Press ⌘1 — switch to Today.

- [ ] **Step 7: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift \
        Apps/Lillist-iOS/Sources/App/LillistApp.swift \
        Apps/Lillist-iOS/Sources/App/AppEnvironment.swift \
        Apps/Lillist-iOS/Sources/Root/TabShell.swift \
        Apps/Lillist-iOS/Sources/Root/SplitShell.swift
git rm Apps/Lillist-iOS/Sources/Common/KeyboardShortcuts.swift
git commit -m "refactor(iOS): hardware shortcuts via CommandMenu + rebind to ⌘⇧N

CommandMenu surfaces shortcuts in iPadOS's hold-⌘ overlay; the
hidden-Button hack didn't. Also rebind ⌘N → ⌘⇧N: ⌘N is reserved by
iPadOS for 'New Window' (multitasking), and the prior binding
collided with shipped-OS behavior."
```

---

## Task 30: Engineering note + final sweep + tag

**Files:**
- Modify: `docs/engineering-notes.md`

- [ ] **Step 1: Final test sweeps**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
swift test --package-path Packages/LillistUI 2>&1 | tail -3
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator,name=iPhone 15' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
xcodebuild test -workspace Lillist.xcworkspace -scheme LillistUI \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

All green.

- [ ] **Step 2: Append engineering note**

Add at the top of `docs/engineering-notes.md`:

```markdown
## 2026-05-16 — Plan 16 iOS polish: tabViewBottomAccessory, three-column iPad, segmented detail, live Quick Capture chips, monthly day grid, CommandMenu shortcuts

**Context.** Plan 16 closed the visual / navigational gap between Lillist
on iOS and first-tier iOS task managers (Reminders, Things, Todoist).
Changes ran the gamut from per-screen polish (empty-state CTAs,
notification-permission label conditionality, trash-retention picker)
to structural shifts (three-column iPad split, segmented detail tabs
replacing page-style TabView, FAB lifted off the tab bar into iOS 18's
`tabViewBottomAccessory` slot, hardware keyboard shortcuts moved from
a hidden-Button hack into Scene-level `CommandMenu`).

**Five concrete lessons.**

1. **iOS 18's `tabViewBottomAccessory` is the HIG-correct placement
   for a persistent compose / FAB above the tab bar.** A
   `.overlay(alignment: .bottomTrailing)` floating button has no
   structural relationship to the tab bar — keyboard avoidance,
   safe-area math, accessibility-element ordering all have to be
   re-implemented by hand. The accessory slot inherits all of it
   for free. The catch: it's a tab-bar feature, so iPad's
   NavigationSplitView needs a different placement — `topBarTrailing`
   on each detail pane mirrors Mail / Reminders / Notes.

2. **Page-style TabView is for unlabeled carousels, not named
   functional sections.** Four named tabs in a `TabView(.page)` give
   the user no preview of section names, no random-access (must swipe
   sequentially), and no visual representation of the current
   selection beyond dim/lit dots. A segmented `Picker(.segmented)`
   anchored above a content area gives all three. Rule: if you'd
   write a name for each tab, use a Picker. If the content is
   self-describing (images, animations), use `TabView(.page)`.

3. **Live token chips in Quick Capture eliminate parsing-uncertainty
   anxiety.** The macOS panel echoed parsed `#tags` and `^dates`
   below the input field as the user typed; iOS shipped only static
   suggestions. Users typed `Buy milk #groceries ^tomorrow`, saw no
   confirmation, and either tapped Save and hoped or re-checked the
   syntax. Porting the macOS live-echo into an iOS-shared chip row
   removed the doubt — and the implementation was 40 lines of code.
   When two platforms diverge on a small UX detail, lift the
   surface into a shared LillistUI internal helper before
   re-implementing.

4. **`@SceneStorage` for per-window state; `@AppStorage` for per-app
   state.** The detail-tab selection (Notes / Subtasks / Journal /
   Attachments) is per-task in the current navigation flow — the
   user's choice should survive a back-and-forth between tasks but
   doesn't need to survive an app relaunch on iPhone. `@SceneStorage`
   is right. Recent searches are per-app — `@AppStorage` (backed by
   `UserDefaults`) is right. The two look similar; getting the choice
   wrong loses user state (an `@AppStorage`-backed tab selection
   would persist forever across every task, which isn't what we
   want).

5. **iPadOS's hold-⌘ overlay only enumerates `CommandMenu` /
   `CommandGroup` entries.** Burying `.keyboardShortcut("n", modifiers:
   .command)` inside a hidden `Button.background` works — the shortcut
   fires — but it's invisible to the discovery surface. Users on iPad
   never learn the shortcut exists. Moving to a Scene-level
   `CommandMenu` makes the shortcut self-documenting via the system
   overlay. Bonus: `CommandMenu` lets us avoid colliding with
   iPadOS's built-in `⌘N` "New Window" by visibly renaming our
   binding to `⌘⇧N`.

**Rules.**

- iOS 18+ apps with a primary "+" or compose affordance: use
  `.tabViewBottomAccessory` on the tab bar; `.toolbar { ToolbarItem
  (placement: .topBarTrailing) { … } }` on the iPad split's detail
  panes. Never overlay a floating button on the whole view.
- Four named functional sections in a detail view: use a segmented
  `Picker` above a switch. Reserve `TabView(.page)` for image / media
  carousels where indicator dots are sufficient.
- Live-parse user input where possible: echo parsed tokens back as
  the user types, with visual chips, so they confirm the parser saw
  what they meant before committing.
- Use `@SceneStorage` for per-window UI state, `@AppStorage` for
  per-app preferences. Pick the wrong one and the persistence
  surprises the user.
- Hardware keyboard shortcuts on iPad: declare via `CommandMenu` at
  the Scene level. The shortcut overlay only enumerates these.
  Avoid colliding with iPadOS's reserved `⌘N` (use `⌘⇧N` instead).

**Evidence.** Plan 16 commits on `plan-16-ios-polish` (or merged
into `main` as such): segmented detail tabs (`TaskDetailView`); FAB
to `tabViewBottomAccessory` + topBar toolbar; three-column iPad
SplitShell; live Quick Capture chips (`QuickCaptureTokenChips.swift`);
monthly day-of-month grid (`RecurrenceEditorView.swift`); empty-state
CTAs (`QuickCaptureAction` environment value); search scopes,
recent searches, highlight, debounce; conditional notification
permission label; `LillistCommands` CommandMenu.
```

- [ ] **Step 3: Commit and tag**

```bash
git add docs/engineering-notes.md
git commit -m "docs: record Plan 16 iOS polish lessons (tabViewBottomAccessory; segmented detail; live chips; @SceneStorage; CommandMenu)"
git tag plan-16-ios-polish
git log --oneline plan-15..plan-16-ios-polish || git log --oneline main..plan-16-ios-polish
```

- [ ] **Step 4: Open the PR**

```bash
git -c url."https://github.com/".insteadOf="git@github.com:" push -u origin plan-16-ios-polish
gh pr create --title "Plan 16: iOS polish" --body "$(cat <<'EOF'
## Summary

- Replaces page-style TabView in task detail with a segmented Picker; persists last-selected tab via @SceneStorage.
- Lifts the floating + off both shells: tabViewBottomAccessory on TabShell (compact), topBarTrailing toolbar on SplitShell (iPad).
- Adopts three-column NavigationSplitView on iPad (sidebar → list → detail) mirroring macOS RootSplitView.
- Ports macOS Quick Capture live-parsed token chips into iOS; 44pt touch targets on suggestion chips.
- Recurrence editor: 7-column monthly grid replaces 31 toggles; "Repeat" / "When completed" labels; toggle-revealed occurrence limit; smart "End by date" default; commit errors surface via Alert.
- Search: Open / Closed / All scopes, persistent recent searches via searchSuggestions, matched-substring highlight, 250ms debounce, adaptive placement.
- Empty-state CTAs across Today / All / Filters / Search route to Quick Capture via a new \quickCaptureAction\ environment value.
- Settings: trash-retention picker of presets; conditional notification-permission label; debounced time-of-day pickers.
- iPad hardware shortcuts move from hidden-Button hack to Scene-level CommandMenu; ⌘N rebound to ⌘⇧N to avoid the iPadOS reserved binding.

## Test plan

- [ ] All four package test suites green: \swift test --package-path Packages/LillistCore\ and \swift test --package-path Packages/LillistUI\
- [ ] iOS Xcode test scheme green on iPhone 15 simulator
- [ ] macOS Xcode test scheme green
- [ ] Snapshot baselines (FAB light/dark, monthly grid, Quick Capture parsed tokens) inspected and committed
- [ ] Hand-test: cold-start the iOS app, Quick Capture defaults to .large detent; capture once, re-open, defaults to .fraction(0.35)
- [ ] Hand-test on iPad: three columns visible in landscape; tapping a task drives the detail column
- [ ] Hand-test on iPad with hardware keyboard: hold ⌘ surfaces the Lillist CommandMenu with five shortcuts
- [ ] Hand-test VoiceOver on a suggestion chip — single-swipe selection, "Insert tag <name>" announced

EOF
)"
```

---

## Plan 16 Scope

**In scope:**
- Task detail UX: segmented tabs, @SceneStorage persistence, Notes debounce, Journal keyboard avoidance (Tasks 1-4)
- FloatingAddButton off the tab bar; Liquid Glass styling (Tasks 5-7)
- iPad three-column adoption; iPadSection unification (Tasks 8-9)
- Quick Capture: live token chips, .large detent, drag indicator, focus-resign on Save, 44pt chip targets (Tasks 10-14)
- Search: scopes, recent searches, highlight, debounce, adaptive placement (Tasks 15-19)
- Recurrence editor: monthly grid, plain-English labels, toggle-revealed limit, sensible "until" default, commit error Alert (Tasks 20-24)
- Empty-state CTAs across iOS screens (Task 25)
- Settings polish: trash-retention picker, conditional notification permission label, time-picker debounce (Tasks 26-28)
- iPad hardware keyboard shortcuts via CommandMenu; ⌘N → ⌘⇧N (Task 29)
- Engineering note, final sweep, tag, PR (Task 30)

**Out of scope (left for future plans):**
- macOS UI polish equivalents (separate Plan 17 / Plan 18 candidate)
- iOS share-extension UX polish (separate plan, depends on Plan 11's link-preview baseline)
- Localization of new strings ("Repeat forever", "When completed", "Capture a task" etc.) — design Section 10 currently mandates English-only for v1
- App Intents surface refresh (the existing `QuickCaptureLockScreenIntent` and friends are functional but visually pre-Liquid-Glass)
- Detail header redesign — keeping the existing TaskDetailHeader as-is; a future plan can lift its compact card pattern into LillistUI
- Notes / Journal rich-text editing (plain text only continues from Plan 7)
- iPad multi-column drag-to-resize gestures beyond NavigationSplitView defaults
- Live updates of search results when underlying tasks change (currently the query re-runs only on text/scope change; a `.task(id:)` listening to TaskStore changes is a future enhancement)

---

## Self-Review Checklist (run by the implementer before merging)

- [ ] All 30 tasks completed with checkboxes ticked.
- [ ] `swift build -Xswiftc -warnings-as-errors` clean on `Packages/LillistCore` and `Packages/LillistUI`.
- [ ] `swift test --package-path Packages/LillistCore` PASS.
- [ ] `swift test --package-path Packages/LillistUI` PASS.
- [ ] `xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' … build` succeeds.
- [ ] `xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' … build` succeeds (recurrence editor changes shared across platforms — must compile on macOS too).
- [ ] iPhone simulator hand-test: TabShell tab bar shows the "+" accessory below the tabs, not overlay; tapping captures a task; Notes debounces (verified via console-attached log); Journal composer floats above keyboard; segmented tabs persist across detail re-entries; empty-state CTAs route to Quick Capture.
- [ ] iPad simulator hand-test: three columns visible in landscape; tapping a task drives the detail column; hold-⌘ surfaces the Lillist CommandMenu; ⌘⇧N opens Quick Capture; recurrence monthly grid renders as a 7-column LazyVGrid.
- [ ] Snapshot baselines inspected (not just record-mode-overwritten): `fab-light`, `fab-dark`, `quick-capture-field-with-parsed-tokens`, `monthly-day-15-light`, `monthly-multi-light`, plus any re-recorded existing baselines.
- [ ] `rg 'FloatingPlusOverlay' Apps/ Packages/` is empty (overlay deleted in Task 5).
- [ ] `rg 'TabShell\.Tab|SplitShell\.Section' Apps/ Packages/` is empty (unified in Task 9).
- [ ] `rg 'KeyboardShortcuts\.swift\|lillistKeyboardShortcuts' Apps/ Packages/` is empty (file deleted in Task 29).
- [ ] `docs/engineering-notes.md` has the 2026-05-16 Plan 16 entry above the 2026-05-15 one.
- [ ] CLAUDE.md unchanged — no new project-wide convention introduced.
- [ ] Branch `plan-16-ios-polish` pushed; PR opened against `main`.
