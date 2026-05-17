# Lillist Plan 15 — macOS Chrome & System Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Branch:** `plan-15-macos-chrome` (off `main`).

**Goal:** Transform the macOS app from "SwiftUI app with no chrome" into a polished macOS 26 (Tahoe) citizen. The single highest-leverage change is wiring a real `.toolbar` on `RootSplitView` so the window finally has a sidebar toggle, a source title in the principal slot, and primary actions for `+ New Task` / Sort / sync status. Layered on top are a Form-style detail pane, a SwiftUI `MenuBarExtra` (replacing the AppKit `NSStatusBar` controller), Quick Capture panel polish (cursor-screen placement, resign-key dismissal, modifier-symbol hotkey UI), and the system integrations that a tasks-and-notes app of this caliber is expected to ship — dock badge / menu, About box, Help menu, Services provider, Spotlight indexing, NSUserActivity for Handoff, and an animated Preferences window. The plan also fixes a misleading `NSAppleEventsUsageDescription` and reclaims `⌘F` from `replacing: .textEditing` so the standard Find Next / Previous menu survives.

**Architecture:** The toolbar replaces hand-rolled column headers (`TaskListHeaderView`'s right-side sort menu and the sidebar's `safeAreaInset` sync dot collapse into `ToolbarItem` slots). Detail becomes a real `Form` with named sections instead of an ad-hoc `VStack` inside a `ScrollView`. `MenuBarExtra(.window)` replaces `NSStatusBar`-based `StatusBarController` and inherits Tahoe's anchored popover semantics for free. `QuickCapturePanelController` keeps its `NSPanel` but gains cursor-screen placement, a resign-key observer, and loses the `NSApp.activate(ignoringOtherApps:)` call that defeats `.nonactivatingPanel`. System integrations (dock badge, dock menu, About / Help command groups, Services provider, Spotlight `IndexingService`, `NSUserActivity`) are independent additions that don't touch existing call sites — each lives in its own file. Preferences sizing flips from a hard-coded outer frame to per-pane intrinsic sizing via `.fixedSize()`, matching System Settings.

**Tech Stack:** Swift 6, SwiftUI, AppKit (for `NSPanel`, `NSScreen`, `NSApp.dockTile`, `NSServicesProvider`), CoreSpotlight (`CSSearchableIndex`, `CSSearchableItem`, `CSSearchableItemAttributeSet`), `MenuBarExtra` (macOS 13+), `@SceneStorage` (SwiftUI 4+), `NavigationSplitView` toolbar APIs. No new SPM dependencies. Tests use `XCTest` plus `swift-snapshot-testing` for the `MacOSScreenTourTests` re-record.

**Depends on:**
- All prior plans (1–12) merged on `main`.
- **Plans 13 (accessibility / correctness) and 14 (design tokens — `LillistSpacing`, `LillistRadius`, `SyncPalette`, `StatusPalette`) are referenced in several tasks** (specifically: Task 5 borders via `LillistRadius.s`, Task 6 status pill colors via `StatusPalette.color(for:)`). At the time of writing, those plans do not yet exist on `main`. **If Plans 13 / 14 are not yet merged when this plan executes, inline literal values (e.g. `cornerRadius: 6`, hard-coded `Color`) and leave a `// TODO(Plan 14): swap for design token` comment so the work isn't blocked.** A follow-up sweep after Plan 14 lands will replace the literals.

---

## File Structure

```
Lillist/
├── Apps/
│   ├── Lillist-macOS/
│   │   ├── Info.plist                                       (modify — fix NSAppleEventsUsageDescription)
│   │   ├── project.yml                                      (modify — pick up new directories)
│   │   ├── Sources/
│   │   │   ├── AppDelegate.swift                            (modify — dock badge/menu, Services provider)
│   │   │   ├── LillistApp.swift                             (modify — MenuBarExtra scene, remove Settings fixed frame)
│   │   │   ├── Commands/
│   │   │   │   └── LillistCommands.swift                    (modify — About/Help/Find/Sidebar shortcuts)
│   │   │   ├── Hotkey/
│   │   │   │   ├── HotkeyRecorder.swift                     (modify — SF Symbol modifier glyphs, conflict guard)
│   │   │   │   └── QuickCapturePanelController.swift        (modify — cursor screen, resign-key, hasShadow)
│   │   │   ├── Indexing/                                    (NEW directory)
│   │   │   │   └── IndexingService.swift                    (NEW — Spotlight CSSearchableItem pipeline)
│   │   │   ├── MenuBar/                                     (NEW directory)
│   │   │   │   └── MenuBarExtraScene.swift                  (NEW — MenuBarExtra(.window) host)
│   │   │   ├── Persistence/
│   │   │   │   └── UIStatePersistence.swift                 (modify — sidebar visibility, per-source taskSelection)
│   │   │   ├── Preferences/
│   │   │   │   └── PreferencesWindow.swift                  (modify — remove fixed frame, intrinsic sizing)
│   │   │   ├── Services/                                    (NEW directory)
│   │   │   │   └── LillistServicesProvider.swift            (NEW — NSServicesProvider host)
│   │   │   ├── StatusBar/                                   (delete after MenuBarExtra migration)
│   │   │   │   ├── StatusBarController.swift                (delete in Task 9)
│   │   │   │   └── TodayPopoverView.swift                   (modify — onAppear refresh; reused by MenuBarExtra)
│   │   │   └── Views/
│   │   │       ├── RootSplitView.swift                      (modify — .toolbar, persisted visibility/selection)
│   │   │       ├── Detail/
│   │   │       │   ├── DetailHeaderView.swift               (modify — StatusPalette pill colors)
│   │   │       │   ├── JournalComposerView.swift            (modify — ⌘⏎ keyboard shortcut)
│   │   │       │   ├── JournalStreamView.swift              (modify — segmented picker)
│   │   │       │   ├── NotesEditorView.swift                (modify — bordered editor)
│   │   │       │   └── TaskDetailView.swift                 (modify — Form sections, userActivity)
│   │   │       ├── Sidebar/
│   │   │       │   └── SidebarView.swift                    (modify — drop safeAreaInset sync dot)
│   │   │       └── TaskList/
│   │   │           ├── TaskListHeaderView.swift             (modify — drop right-side sort menu)
│   │   │           └── TaskListSortControl.swift            (modify — used from toolbar)
│   │   ├── Resources/
│   │   │   └── Assets.xcassets/
│   │   │       └── StatusBarIcon.imageset/                  (delete — empty PNGs, SF Symbol fallback)
│   │   └── Tests/
│   │       ├── ToolbarPersistenceTests.swift                (NEW — sidebar visibility round-trip)
│   │       ├── HotkeyRecorderConflictTests.swift            (NEW — bare-Cmd guard)
│   │       ├── QuickCapturePlacementTests.swift             (NEW — cursor-screen math)
│   │       └── IndexingServiceTests.swift                   (NEW — CSSearchableItem mapping)
└── Packages/
    └── LillistUI/
        ├── Sources/
        │   └── LillistUI/
        │       ├── QuickCapture/
        │       │   └── QuickCaptureView.swift               (audit — `.thickMaterial` → `.regularMaterial`)
        │       └── Theme/
        │           └── StatusPalette.swift                  (NEW — depends on Plan 14; defer if missing)
        └── Tests/
            └── LillistUITests/
                ├── Snapshots/
                │   └── TaskDetailViewSnapshotTests.swift    (modify — re-record Form layout)
                └── Tour/
                    └── MacOSScreenTourTests.swift           (modify — add toolbar + Form screens)
└── docs/
    └── engineering-notes.md                                  (append entry for Plan 15)
```

---

## Notes for the Implementer

**macOS 26 Liquid Glass material APIs.** Tahoe introduces `.glassBackgroundEffect()` / Liquid Glass materials. The current `QuickCaptureView.swift:46` uses `.thickMaterial` — fine but heavier than the Tahoe-native look. Audit during Task 16: prefer `.regularMaterial` with an optional `.glassBackgroundEffect()` call when available (the modifier is non-throwing and degrades gracefully on older OSes via `if #available(macOS 26.0, *)`). Don't churn it if you're unsure; the existing material is acceptable.

**`@FocusedValue` is the way to gate menu commands.** Several commands (Task 28's reclaimed `⌘F`, Task 29's `⌃⌘S` sidebar toggle) need to know what's currently focused. The Tahoe-native pattern is to publish a `@FocusedValue` from `RootSplitView` (or the focused view), then read it in `LillistCommands` via `@FocusedBinding` / `@FocusedValue`. Avoid `NotificationCenter` for menu state — it works but creates implicit coupling.

> **Plan 13 fallout (2026-05-16):** This infrastructure is already on `main`. Plan 13 Task 5 published `\.listColumn` (a `ListColumn?` value, where `ListColumn` is a top-level enum in `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift`) from `RootSplitView` via `.focusedValue(\.listColumn, focusedColumn)`, and `LillistCommands` already declares `@FocusedValue(\.listColumn) private var listColumn: ListColumn?`. Plan 15's new commands (⌘F, ⌃⌘S, etc.) should reuse the existing key rather than declaring a new one. Plan 13 also rebound `⌘D` → `⌘⏎` (Mark Closed) and `⌘⇧N` → `⌘⇧⏎` (New Sibling Task) and gated Space/⌘⏎/⌘./Tab/Shift-Tab with `.disabled(listColumn == nil)` — Plan 15's command-block edits should preserve those modifiers and rebinds.

**`AppDelegate` already exists** at `Apps/Lillist-macOS/Sources/AppDelegate.swift:11` with a `bootstrap()` method called from `LillistApp.task` once `AppEnvironment.make()` resolves. Add the dock badge subscription, dock menu, and Services provider registration in `bootstrap()` so they have access to `environment`. Do not move them into `applicationDidFinishLaunching` — the environment isn't yet available there (see the existing comment in `AppDelegate.swift:17-20`).

**xcodegen step when adding new directories.** Apps' xcodegen spec is at `Apps/project.yml`. The `sources:` rules use directory globs, so most new files (under `Sources/`) are auto-discovered. Tasks that add a **new top-level directory** (`Indexing/`, `MenuBar/`, `Services/`) still need `xcodegen` to be re-run so the `.pbxproj` picks them up, even though `project.yml` itself doesn't need editing:

```bash
cd Apps && xcodegen generate --spec project.yml --project . && cd ..
```

Verify with `git status --short Apps/Lillist-macOS.xcodeproj/project.pbxproj` — if it shows changes, the new file got picked up; stage it. Tasks that add new files to **existing** directories should still re-run `xcodegen` to be safe; xcodegen is idempotent and cheap.

**`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`** is on for the macOS targets (`project.yml:15`). Every task ends with a build verification — treat any new warning as a failure and fix it before commit.

**Snapshot test re-records.** Tasks that change visible UI (4, 5, 6, 7, 26) re-record `MacOSScreenTourTests.swift` and `TaskDetailViewSnapshotTests.swift`. Use the `RECORD_SNAPSHOTS=YES` environment toggle if the suite supports it; otherwise delete the affected `__Snapshots__/*.png` files and re-run to let `swift-snapshot-testing` regenerate them.

**Verification cadence.** Every task ends with at least one of:

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

For tasks that include new tests:

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/<SuiteName> \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

**Commits.** Conventional-commit prefixes throughout: `feat:`, `refactor:`, `fix:`, `test:`, `chore:`, `docs:`. One commit per task unless explicitly noted.

**Push protocol.** This repo lives in `mikeydotio` on GitHub; SSH agent requires interactive auth so push over HTTPS:

```bash
git -c url."https://github.com/".insteadOf="git@github.com:" push origin plan-15-macos-chrome
```

---

## Task 1: Wire a real `.toolbar` on `RootSplitView`

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:19-39`
- Modify: `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListHeaderView.swift` (drop the right-side sort menu — toolbar owns it now)
- Modify: `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:48-57` (drop the `safeAreaInset` sync dot — toolbar owns it now)

The toolbar adds four placements:

1. **`.navigation`** — a sidebar-toggle button that flips an `@State var columnVisibility: NavigationSplitViewVisibility`.
2. **`.principal`** — the source title (currently in `TaskListHeaderView`'s left side), so the window has a real chrome breadcrumb instead of one buried in the list pane.
3. **`.primaryAction`** — `+ New Task` (posts `.lillistNewTask`) and the Sort menu (reuses `TaskListSortControl`).
4. **`.status`** — the `SyncStatusDotView`, currently in the sidebar's bottom inset.

The toolbar also needs to know the *current* sort field/order so it can render the right chevron. We hoist `sortField` / `sortAscending` from `TaskListView` to `RootSplitView` and pass bindings down (the task list already drives its refresh off these).

- [ ] **Step 1: Read the affected files and confirm starting state**

```bash
grep -n "NavigationSplitView\|safeAreaInset\|TaskListHeaderView\|TaskListSortControl" \
    Apps/Lillist-macOS/Sources/Views/RootSplitView.swift \
    Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift \
    Apps/Lillist-macOS/Sources/Views/TaskList/TaskListHeaderView.swift
```

Expected: `RootSplitView.swift:20` opens `NavigationSplitView { … }`; `SidebarView.swift:48` has the `.safeAreaInset(edge: .bottom)` with `SyncStatusDotView`; `TaskListHeaderView.swift:18` renders `TaskListSortControl` to the right of the title.

- [ ] **Step 2: Hoist sort state and add column visibility to `RootSplitView`**

In `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift`, replace the top of the struct (lines 5-18) with:

```swift
struct RootSplitView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var uiState = UIStatePersistence()
    @State private var sidebarSelection: SidebarSelection?
    @State private var taskSelection: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var sortField: SortField = .deadline
    @State private var sortAscending: Bool = true
    @FocusState private var focusedColumn: Column?

    enum Column: Hashable { case sidebar, list, detail }

    init() {
        let persisted = UIStatePersistence().sidebarSelection
        _sidebarSelection = State(initialValue: persisted)
    }
```

Then change `NavigationSplitView { … }` (line 20) to bind to `columnVisibility`:

```swift
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $sidebarSelection)
                .focused($focusedColumn, equals: .sidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            if let sel = sidebarSelection {
                TaskListView(
                    selection: sel,
                    taskSelection: $taskSelection,
                    sortField: $sortField,
                    sortAscending: $sortAscending
                )
                .focused($focusedColumn, equals: .list)
                .navigationSplitViewColumnWidth(min: 320, ideal: 460)
            } else {
                EmptyStateView(title: "Select a source", message: "Pick a pinned item, tag, or filter from the sidebar.")
            }
        } detail: {
            if let id = taskSelection {
                TaskDetailView(taskID: id)
                    .focused($focusedColumn, equals: .detail)
                    .navigationSplitViewColumnWidth(min: 360, ideal: 520)
            } else {
                NoSelectionDetailView()
                    .navigationSplitViewColumnWidth(min: 360, ideal: 520)
            }
        }
        .toolbar { toolbarContent }
```

- [ ] **Step 3: Add the `toolbarContent` builder**

Append to the body of `RootSplitView` (above the closing brace):

```swift
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Sidebar toggle. NavigationSplitView ships its own affordance
        // on Tahoe, but binding a button to columnVisibility lets us
        // persist the user's choice and expose a stable target for the
        // ⌃⌘S menu command (Task 29).
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    columnVisibility = (columnVisibility == .all)
                        ? .doubleColumn
                        : .all
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle sidebar")
            .accessibilityLabel("Toggle sidebar")
        }

        // Principal: the source title. TaskListHeaderView used to own
        // this; the toolbar is the right home so it survives column
        // collapse and matches Mac Mail / Notes / Reminders.
        ToolbarItem(placement: .principal) {
            Text(sidebarSelection.map(principalTitle(for:)) ?? "Lillist")
                .font(.headline)
        }

        // Primary actions: + New Task and the sort menu. The Sort
        // menu used to live inside TaskListHeaderView's right side;
        // hoisting it here gives it standard chrome placement.
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                NotificationCenter.default.post(name: .lillistNewTask, object: nil)
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .help("New Task (⌘N)")
            .keyboardShortcut("n", modifiers: [.command])

            TaskListSortControl(field: $sortField, ascending: $sortAscending)
        }

        // Status: the sync dot. SidebarView's safeAreaInset placement
        // is replaced by this — Task 1 deletes the inset block in
        // SidebarView.swift in the same commit.
        ToolbarItem(placement: .status) {
            SyncStatusDotView(indicator: env.syncMonitor.indicator) {
                Task { await env.syncMonitor.retry() }
            }
        }
    }

    private func principalTitle(for selection: SidebarSelection) -> String {
        switch selection {
        case .pinnedTask:    return "Pinned task"
        case .pinnedFilter:  return "Pinned filter"
        case .tag:           return "Tag"
        case .filter:        return "Filter"
        case .trash:         return "Trash"
        }
    }
```

- [ ] **Step 4: Update `TaskListView` to accept sort bindings instead of owning them**

In `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift`, replace the existing `sortField` / `sortAscending` `@State` declarations (lines 14-15) with `@Binding` and pass through. Drop the `TaskListHeaderView` from the body (the toolbar shows the title now). The list keeps its breadcrumb pane and the inline-create field. Detailed edits:

Change lines 13-16 from:
```swift
    @State private var sortField: SortField = .deadline
    @State private var sortAscending = true
    @State private var inlineCreateText = ""
    @State private var showInlineCreate = false
```
to:
```swift
    @Binding var sortField: SortField
    @Binding var sortAscending: Bool
    @State private var inlineCreateText = ""
    @State private var showInlineCreate = false
```

Delete the `TaskListHeaderView` invocation (currently lines 49-55). The list now starts straight with the (conditional) flat results or outline.

- [ ] **Step 5: Drop the `safeAreaInset` sync dot from `SidebarView`**

In `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift`, delete lines 48-57 (the `.safeAreaInset(edge: .bottom) { HStack { SyncStatusDotView … } }`). Leave the `.task { await refresh() }` on its own.

- [ ] **Step 6: Drop the right-side sort menu from `TaskListHeaderView`**

`TaskListHeaderView` is now used only by snapshot tests (the toolbar owns the live header). Keep the file (snapshots reference it) but simplify the body to title + count only:

```swift
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.bold())
            Text("\(count)")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(count) tasks")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
```

The `sortField` / `sortAscending` bindings can be removed from the initializer signature; if any caller passes them (snapshot tests do), update the call sites to drop the args. If the snapshot test build breaks, update the call site in `MacOSScreenTourTests.swift` to omit the deprecated bindings.

- [ ] **Step 7: Build and confirm**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`, zero warnings.

- [ ] **Step 8: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/RootSplitView.swift \
        Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift \
        Apps/Lillist-macOS/Sources/Views/TaskList/TaskListHeaderView.swift \
        Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift
git commit -m "feat(macOS): wire .toolbar on RootSplitView for sidebar, title, sort, sync"
```

---

## Task 2: Persist sidebar visibility and per-source task selection

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Persistence/UIStatePersistence.swift`
- Modify: `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift`
- Create: `Apps/Lillist-macOS/Tests/ToolbarPersistenceTests.swift`

`UIStatePersistence` currently persists `sidebarSelection`, `expandedTagIDs`, and per-source sort. We extend it with:

1. `columnVisibility` (the toolbar-toggle's persisted state).
2. `taskSelection(for: SidebarSelection)` — a per-source task ID so switching back to a previously-visited filter restores the user's row.

We also wire `@SceneStorage` where appropriate (the column-visibility binding is a window-level concept). `@SceneStorage` is preferred for visibility because SwiftUI restores it automatically on window restoration; `UserDefaults` is the right home for per-source selection because it should persist across launches.

- [ ] **Step 1: Write the failing test**

Create `Apps/Lillist-macOS/Tests/ToolbarPersistenceTests.swift`:

```swift
import XCTest
@testable import LillistCore

@MainActor
final class ToolbarPersistenceTests: XCTestCase {
    private let suiteName = "ToolbarPersistenceTests"

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    func test_taskSelection_persistsPerSidebarSource() throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UIStatePersistence(defaults: defaults)

        let filterA = SidebarSelection.filter(UUID())
        let filterB = SidebarSelection.filter(UUID())
        let taskA = UUID()
        let taskB = UUID()

        store.setTaskSelection(taskA, for: filterA)
        store.setTaskSelection(taskB, for: filterB)

        XCTAssertEqual(store.taskSelection(for: filterA), taskA)
        XCTAssertEqual(store.taskSelection(for: filterB), taskB)
    }

    func test_taskSelection_nilClears() throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UIStatePersistence(defaults: defaults)

        let filter = SidebarSelection.filter(UUID())
        let task = UUID()
        store.setTaskSelection(task, for: filter)
        XCTAssertEqual(store.taskSelection(for: filter), task)
        store.setTaskSelection(nil, for: filter)
        XCTAssertNil(store.taskSelection(for: filter))
    }
}
```

This test references `UIStatePersistence`, which lives in the macOS app target. Add it to the test bundle's co-compile list (xcodegen step in Step 5).

- [ ] **Step 2: Extend `UIStatePersistence`**

In `Apps/Lillist-macOS/Sources/Persistence/UIStatePersistence.swift`, append a new section:

```swift
    private enum Key {
        static let sidebarSelection  = "lillist.ui.sidebarSelection"
        static let expandedTagIDs    = "lillist.ui.expandedTagIDs"
        static let sortPerSource     = "lillist.ui.sortPerSource"
        // Plan 15: per-source task selection. Key is a `SidebarSelection`
        // string representation (matching `TaskListView.sourceKey`), value
        // is a UUID string. Lookups return `nil` if the selection
        // hasn't been seen yet or was explicitly cleared.
        static let taskSelection     = "lillist.ui.taskSelection"
    }

    /// Last task ID the user selected while viewing `source`. Returns
    /// `nil` if the user hasn't yet selected anything in this source or
    /// explicitly cleared the selection (see `setTaskSelection(_:for:)`).
    func taskSelection(for source: SidebarSelection) -> UUID? {
        let key = Self.persistenceKey(for: source)
        guard let dict = defaults.dictionary(forKey: Key.taskSelection) as? [String: String],
              let raw = dict[key] else { return nil }
        return UUID(uuidString: raw)
    }

    /// Sets the remembered task selection for `source`. Pass `nil` to
    /// clear (e.g. when the selected task is deleted).
    func setTaskSelection(_ id: UUID?, for source: SidebarSelection) {
        let key = Self.persistenceKey(for: source)
        var dict = (defaults.dictionary(forKey: Key.taskSelection) as? [String: String]) ?? [:]
        if let id {
            dict[key] = id.uuidString
        } else {
            dict.removeValue(forKey: key)
        }
        defaults.set(dict, forKey: Key.taskSelection)
    }

    /// Canonical string key for a `SidebarSelection`. Mirrors
    /// `TaskListView.sourceKey` so the sort and task-selection
    /// dictionaries can share the same notion of "source identity."
    private static func persistenceKey(for source: SidebarSelection) -> String {
        switch source {
        case .pinnedTask(let id):   return "pinnedTask.\(id.uuidString)"
        case .pinnedFilter(let id): return "pinnedFilter.\(id.uuidString)"
        case .tag(let id):          return "tag.\(id.uuidString)"
        case .filter(let id):       return "filter.\(id.uuidString)"
        case .trash:                return "trash"
        }
    }
```

(Replace the existing `private enum Key { … }` declaration in full — the new one adds the `taskSelection` case alongside the existing keys.)

- [ ] **Step 3: Wire `columnVisibility` to `@SceneStorage` in `RootSplitView`**

In `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift`, change the `columnVisibility` declaration from `@State` to `@SceneStorage` so SwiftUI restores it on window restoration without an explicit save call:

```swift
    @SceneStorage("lillist.ui.columnVisibility") private var columnVisibilityRaw: String = "all"
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { Self.parseVisibility(columnVisibilityRaw) },
            set: { columnVisibilityRaw = Self.encodeVisibility($0) }
        )
    }

    private static func parseVisibility(_ raw: String) -> NavigationSplitViewVisibility {
        switch raw {
        case "doubleColumn": return .doubleColumn
        case "detailOnly":   return .detailOnly
        default:             return .all
        }
    }

    private static func encodeVisibility(_ v: NavigationSplitViewVisibility) -> String {
        switch v {
        case .doubleColumn: return "doubleColumn"
        case .detailOnly:   return "detailOnly"
        default:            return "all"
        }
    }
```

Then update the `NavigationSplitView(columnVisibility: $columnVisibility)` call from Task 1 to pass `columnVisibility` (the computed binding).

- [ ] **Step 4: Wire per-source taskSelection**

Below the `.onChange(of: sidebarSelection) { _, new in uiState.sidebarSelection = new }` line in `RootSplitView`, add two more modifiers:

```swift
        .onChange(of: sidebarSelection) { _, new in
            uiState.sidebarSelection = new
            // Restore the remembered task selection for the new source
            // (or clear if none).
            taskSelection = new.flatMap { uiState.taskSelection(for: $0) }
        }
        .onChange(of: taskSelection) { _, new in
            if let sel = sidebarSelection {
                uiState.setTaskSelection(new, for: sel)
            }
        }
```

(Replace the existing single `.onChange(of: sidebarSelection)` with this expanded pair — the `uiState.sidebarSelection = new` line moves into the new body.)

- [ ] **Step 5: Regenerate xcodegen and add test bundle co-compile entries**

The test references `UIStatePersistence` and `SidebarSelection`, both of which live in the app target. Add to `Apps/project.yml` under the test target's `sources:`:

```yaml
      - path: Lillist-macOS/Sources/Persistence/UIStatePersistence.swift
      - path: Lillist-macOS/Sources/Views/Sidebar/SidebarSelection.swift
```

Then regenerate:

```bash
cd Apps && xcodegen generate --spec project.yml --project . && cd ..
git status --short Apps/Lillist-macOS.xcodeproj/project.pbxproj
```

- [ ] **Step 6: Run the new tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/ToolbarPersistenceTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

Expected: 2 PASS.

- [ ] **Step 7: Build the whole app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Persistence/UIStatePersistence.swift \
        Apps/Lillist-macOS/Sources/Views/RootSplitView.swift \
        Apps/Lillist-macOS/Tests/ToolbarPersistenceTests.swift \
        Apps/project.yml \
        Apps/Lillist-macOS.xcodeproj/project.pbxproj
git commit -m "feat(macOS): persist sidebar visibility and per-source task selection"
```

---

## Task 3: Bound the detail column width

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift` (Task 1 introduced this; we're verifying)

Task 1's Step 2 already added `.navigationSplitViewColumnWidth(min: 360, ideal: 520)` to both the `TaskDetailView` and `NoSelectionDetailView` branches of the `detail:` closure. This task exists as a separate sanity-check and gives us a small standalone commit that's easy to revert if Tahoe disagrees with the values.

- [ ] **Step 1: Verify the modifier exists on both branches**

```bash
grep -n "navigationSplitViewColumnWidth" Apps/Lillist-macOS/Sources/Views/RootSplitView.swift
```

Expected: exactly three results — one on `SidebarView`, one on `TaskListView`, two on the detail column (one for `TaskDetailView`, one for `NoSelectionDetailView`). If only one branch has the modifier, add it to the other.

- [ ] **Step 2: Eyeball-test by building and launching**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Launch manually if desired — the detail column should not collapse to 0 width when the window is narrow.

- [ ] **Step 3: Commit only if the modifier was missing from one branch**

If Step 1 found both branches already had the modifier (because Task 1 covered it), skip this commit and move on. Otherwise:

```bash
git add Apps/Lillist-macOS/Sources/Views/RootSplitView.swift
git commit -m "fix(macOS): bound detail column min/ideal width so it can't collapse"
```

---

## Task 4: Convert `TaskDetailView` to a sectioned `Form`

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift:18-47`
- Modify: `Packages/LillistUI/Tests/LillistUITests/Snapshots/TaskDetailViewSnapshotTests.swift`
- Modify: `Packages/LillistUI/Tests/LillistUITests/Tour/MacOSScreenTourTests.swift` (the `taskDetailPane()` mock — re-record affected screens)

The current `ScrollView { VStack { … } }` layout (`TaskDetailView.swift:19-47`) is functional but visually flat. Tahoe-native detail panes use `Form { Section { … } }.formStyle(.grouped)` so each logical chunk (title, dates, recurrence, notes, subtasks, journal) gets a labeled card with system padding. The conversion is straightforward — the existing subviews drop in unchanged, the layout container changes.

- [ ] **Step 1: Rewrite the body**

In `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift`, replace the entire `body` (lines 18-64) with:

```swift
    var body: some View {
        Form {
            if let r = record {
                Section {
                    TitleRow(title: $title, status: r.status, onStatusMenu: { s in
                        Task { await transition(to: s) }
                    })
                }

                Section("Dates") {
                    DatePicker("Start", selection: Binding(
                        get: { start ?? Date() }, set: { start = $0 }
                    ), displayedComponents: [.date])
                    DatePicker("Deadline", selection: Binding(
                        get: { deadline ?? Date() }, set: { deadline = $0 }
                    ), displayedComponents: [.date])
                }

                Section("Recurrence") {
                    recurrenceRow
                }

                if showFollowUpForm {
                    Section("Follow-up") {
                        FollowUpFormView(
                            blockedTaskID: r.id,
                            parentTitle: title,
                            onCommit: { showFollowUpForm = false },
                            onDismiss: { showFollowUpForm = false }
                        )
                    }
                }

                Section("Notes") {
                    NotesEditorView(markdown: $notes)
                }

                Section("Subtasks") {
                    SubtaskOutlineView(parentID: r.id)
                }

                Section("Journal") {
                    JournalStreamView(taskID: r.id)
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .task(id: taskID) { await load() }
        .onChange(of: title) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.title = new } } }
        .onChange(of: notes) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.notes = new } } }
        .onChange(of: start) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.start = new } } }
        .onChange(of: deadline) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.deadline = new } } }
        .sheet(isPresented: $showingRecurrenceEditor) {
            RecurrenceEditorView(
                viewModel: $recurrenceViewModel,
                onCommit: { rule in
                    Task { await commitRecurrence(rule) }
                    showingRecurrenceEditor = false
                },
                onCancel: { showingRecurrenceEditor = false }
            )
            .frame(minWidth: 420, minHeight: 480)
        }
    }
```

- [ ] **Step 2: Extract a `TitleRow` private subview**

Append to the bottom of `TaskDetailView.swift` (above the closing brace):

```swift
    private struct TitleRow: View {
        @Binding var title: String
        let status: Status
        var onStatusMenu: (Status) -> Void

        var body: some View {
            HStack {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title3.bold())
                Menu {
                    ForEach(Status.allCases, id: \.self) { s in
                        Button { onStatusMenu(s) } label: {
                            Label(StatusGlyph.accessibilityLabel(for: s),
                                  systemImage: StatusGlyph.symbol(for: s))
                        }
                    }
                } label: {
                    Label(StatusGlyph.accessibilityLabel(for: status),
                          systemImage: StatusGlyph.symbol(for: status))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.quaternary))
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Status: \(StatusGlyph.accessibilityLabel(for: status))")
                .fixedSize()
            }
        }
    }
```

Note `DetailHeaderView` is no longer referenced from `TaskDetailView` directly — its start/deadline pickers moved into the "Dates" section and the status pill moved into `TitleRow`. The file `DetailHeaderView.swift` stays in the tree because Task 6 will edit its `StatusPalette` color usage, but `TaskDetailView` no longer imports it. Confirm with `grep -n DetailHeaderView Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift` — expected: no results.

- [ ] **Step 3: Re-record the affected snapshot tests**

Delete the existing `TaskDetailViewSnapshotTests` PNGs so swift-snapshot-testing regenerates them on next run:

```bash
rm -rf Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/TaskDetailComponentsSnapshotTests*
```

Then run the affected tests in record mode:

```bash
swift test --package-path Packages/LillistUI \
    --filter 'TaskDetailComponentsSnapshotTests' \
    -Xswiftc -DRECORD_SNAPSHOTS 2>&1 | tail -10
```

Re-run without the flag to confirm the new baselines match:

```bash
swift test --package-path Packages/LillistUI \
    --filter 'TaskDetailComponentsSnapshotTests' 2>&1 | tail -10
```

Expected: PASS. (The existing snapshot file in this repo only covers `TagChipView` — the real detail view isn't snapshotted there because it lives in the app target. The `MacOSScreenTourTests` `taskDetailPane()` mock is what we re-record in the next step.)

- [ ] **Step 4: Update `MacOSScreenTourTests`'s `taskDetailPane()` mock to use a Form layout**

In `Packages/LillistUI/Tests/LillistUITests/Tour/MacOSScreenTourTests.swift:341-411`, change the existing `taskDetailPane()` body from `ScrollView { VStack … }` to `Form { Section { … } }.formStyle(.grouped)`. Keep the same content (title, tags, notes, subtasks, journal) but reorganized into sections that match the new live view. Delete the affected PNGs:

```bash
rm -f Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__/MacOSScreenTourTests/test_01_mainWindow_today_light.1.png \
       Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__/MacOSScreenTourTests/test_02_mainWindow_today_dark.1.png
```

Then re-run those tests to regenerate the baselines:

```bash
swift test --package-path Packages/LillistUI \
    --filter 'MacOSScreenTourTests/test_01' 2>&1 | tail -5
swift test --package-path Packages/LillistUI \
    --filter 'MacOSScreenTourTests/test_02' 2>&1 | tail -5
```

Inspect the regenerated PNGs visually to confirm the Form layout looks right.

- [ ] **Step 5: Build the macOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`, zero warnings.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift \
        Packages/LillistUI/Tests/LillistUITests/Tour/MacOSScreenTourTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__/MacOSScreenTourTests/
git commit -m "refactor(macOS): convert TaskDetailView to grouped Form sections"
```

---

## Task 5: Border the `NotesEditorView` `TextEditor`

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/NotesEditorView.swift:24-27`

The bare `TextEditor` floats with no visible edge inside the Form section, which is jarring next to the bordered inputs. Wrap it in a rounded-rectangle stroke. Plan 14 (design tokens) introduces `LillistRadius.s`; until it merges, inline the literal `6`.

- [ ] **Step 1: Edit the `TextEditor` block**

Replace lines 23-27 of `NotesEditorView.swift` with:

```swift
            } else {
                TextEditor(text: $markdown)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .padding(6) // TODO(Plan 14): replace with LillistSpacing.s
                    .overlay(
                        RoundedRectangle(cornerRadius: 6) // TODO(Plan 14): LillistRadius.s
                            .stroke(.quaternary)
                    )
                    .accessibilityLabel("Notes editor, Markdown")
            }
```

- [ ] **Step 2: Build and re-record snapshots if a detail tour exists**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Detail/NotesEditorView.swift
git commit -m "feat(macOS): border the notes TextEditor so it doesn't float"
```

---

## Task 6: Color the status pill via `StatusPalette`

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/DetailHeaderView.swift` (status pill `Menu` label, currently around lines 25-32 — see Plan 13 fallout)
- (Conditionally create) `Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift`

`DetailHeaderView`'s status pill currently uses `.quaternary` as a fill — visually neutral, so the user has to read the icon to know the status. Plan 14 will introduce `StatusPalette.color(for: Status)`; this task either consumes it (if Plan 14 has merged) or stubs it inline with a `TODO(Plan 14)` marker.

> **Plan 13 fallout (2026-05-16):** Plan 13 Task 12 added `.accessibilityElement(children: .ignore)` immediately after `.menuStyle(.borderlessButton)` (above the existing `.accessibilityLabel("Status: …")`). Preserve that line when replacing the pill — without it, VoiceOver re-introduces the "Status: To do To do" stutter Plan 13 fixed. Line range may have shifted by one; re-grep before editing.

- [ ] **Step 1: Check whether `StatusPalette` exists**

```bash
find Packages/LillistUI -name "StatusPalette.swift" 2>&1
```

If found: skip Step 2 and proceed to Step 3.

- [ ] **Step 2: (Conditional) Stub `StatusPalette` if Plan 14 hasn't merged**

If Step 1 found nothing, create `Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift`:

```swift
import SwiftUI
import LillistCore

/// Color tokens for task statuses. Plan 14 will own the canonical
/// palette and dark-mode handling; this stub provides reasonable
/// defaults so the macOS detail header (Plan 15 Task 6) doesn't
/// block on Plan 14 landing.
///
/// When Plan 14 ships its real palette, replace this file with the
/// design-token version and confirm callers still compile.
public enum StatusPalette {
    public static func color(for status: Status) -> Color {
        switch status {
        case .todo:    return Color.secondary
        case .started: return Color.accentColor
        case .blocked: return Color.orange
        case .closed:  return Color.green
        }
    }

    /// A muted fill suitable for backgrounds (capsules, badges). Keeps
    /// the same hue as `color(for:)` but at lower opacity so foreground
    /// text/icons retain contrast.
    public static func fill(for status: Status) -> some ShapeStyle {
        color(for: status).opacity(0.18)
    }
}
```

- [ ] **Step 3: Update the status pill in `DetailHeaderView`**

In `Apps/Lillist-macOS/Sources/Views/Detail/DetailHeaderView.swift`, replace lines 25-30 with:

```swift
                } label: {
                    Label(StatusGlyph.accessibilityLabel(for: status), systemImage: StatusGlyph.symbol(for: status))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(StatusPalette.fill(for: status)))
                        .foregroundStyle(StatusPalette.color(for: status))
                }
```

The same change applies to `TaskDetailView.TitleRow` (Task 4 introduced this private subview). Update its `.background(Capsule().fill(.quaternary))` line in the same commit to use `StatusPalette.fill(for: status)` / `StatusPalette.color(for: status)` so the chrome agrees with itself.

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Detail/DetailHeaderView.swift \
        Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift \
        Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift
git commit -m "feat(macOS): color status pill via StatusPalette per status"
```

(Omit `StatusPalette.swift` from the `git add` if Plan 14 had already created it.)

---

## Task 7: Replace JournalStreamView "Attachments only" toggle with a segmented picker

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift:7,15-16,34-36`

The `Toggle("Attachments only", isOn:)` is fine but visually noisy in the Form's Journal section. A segmented picker reads faster and matches how Mail / Notes filter inline.

- [ ] **Step 1: Convert the filter state and UI**

In `Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift`, replace the `@State private var filterAttachmentsOnly = false` line (line 7) with:

```swift
    enum Filter: Hashable { case all, attachments }
    @State private var filter: Filter = .all
```

Replace the toggle (lines 15-16) with a segmented picker:

```swift
                Picker("Filter", selection: $filter) {
                    Text("All").tag(Filter.all)
                    Text("Attachments").tag(Filter.attachments)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
```

Update the `filtered` computed property (line 34) to switch on the enum:

```swift
    private var filtered: [JournalStore.JournalRecord] {
        switch filter {
        case .all:         return entries
        case .attachments: return entries.filter { $0.kind == .attachment }
        }
    }
```

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift
git commit -m "refactor(macOS): JournalStreamView uses a segmented Filter picker"
```

---

## Task 8: ⌘⏎ submits in `JournalComposerView`

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/JournalComposerView.swift:17`

The "Add entry" button currently has no keyboard shortcut, so the user has to mouse to submit. `⌘⏎` is the Mac convention for "submit" inside a multi-line editor (Mail's send, Messages' send, GitHub's comment).

- [ ] **Step 1: Add the shortcut**

In `Apps/Lillist-macOS/Sources/Views/Detail/JournalComposerView.swift`, change line 17:

```swift
                Button("Add entry") { Task { await submit() } }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
```

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Detail/JournalComposerView.swift
git commit -m "feat(macOS): ⌘⏎ submits a Journal entry"
```

---

## Task 9: Migrate to `MenuBarExtra` and delete `StatusBarController`

**Files:**
- Create: `Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift`
- Modify: `Apps/Lillist-macOS/Sources/LillistApp.swift`
- Modify: `Apps/Lillist-macOS/Sources/AppDelegate.swift`
- Delete: `Apps/Lillist-macOS/Sources/StatusBar/StatusBarController.swift`

`NSStatusBar`-based status items pre-date `MenuBarExtra` (introduced in macOS 13). The SwiftUI scene gives us anchored popovers for free, honors light/dark and accent-color preferences automatically, and removes the AppKit bridge code. The existing `TodayPopoverView` is reused as the body of `MenuBarExtra(.window)`; Task 11 fixes its stale-on-reopen behavior.

The preference toggle `statusBarItemVisible` (`PreferencesStore.Prefs`, referenced at `QuickCapturePane.swift:22`) gates whether the `MenuBarExtra` scene is included at all. `MenuBarExtra`'s `isInserted:` initializer accepts a `Bool` binding that SwiftUI uses to add/remove the scene at runtime, so the toggle works without a relaunch.

- [ ] **Step 1: Create `MenuBarExtraScene`**

Create `Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift`:

```swift
import SwiftUI
import LillistCore
import LillistUI

/// Plan 15 Task 9: SwiftUI `MenuBarExtra` scene that replaces the
/// AppKit-bridge `StatusBarController`. The popover content is the
/// existing `TodayPopoverView` plus a Quick Capture primary action and
/// a "Open Lillist" affordance. The `isInserted:` binding lets the
/// scene be removed at runtime when the user disables the
/// status-bar icon in Preferences (no relaunch needed).
///
/// `.menuBarExtraStyle(.window)` opens an anchored panel below the
/// status item (instead of the default `.menu` style which renders an
/// NSMenu). The panel auto-anchors above-or-below based on screen
/// position — no manual `preferredEdge:` calculation.
struct MenuBarExtraScene: Scene {
    @Binding var isInserted: Bool
    let environment: AppEnvironment
    let onQuickCapture: () -> Void

    var body: some Scene {
        MenuBarExtra(
            "Lillist",
            systemImage: "checklist",
            isInserted: $isInserted
        ) {
            MenuBarPopover(onQuickCapture: onQuickCapture)
                .environment(environment)
                .frame(width: 320, height: 400)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarPopover: View {
    @Environment(\.openWindow) private var openWindow
    let onQuickCapture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Lillist").font(.headline)
                Spacer()
                Button("Quick Capture", systemImage: "plus.circle.fill") {
                    onQuickCapture()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Quick Capture (⌃⌥Space)")
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
            Divider()
            TodayPopoverView()
            Divider()
            HStack {
                Button("Open Lillist") {
                    NSApp.activate(ignoringOtherApps: true)
                    for w in NSApp.windows where w.title == "Lillist" {
                        w.makeKeyAndOrderFront(nil); return
                    }
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }
}
```

- [ ] **Step 2: Add the scene to `LillistApp`**

In `Apps/Lillist-macOS/Sources/LillistApp.swift`, add `@State` for the preferences value and a `MenuBarExtraScene` after the existing `Settings { … }` scene:

After the `@State private var loadError: String?` line, add:

```swift
    @State private var statusBarItemVisible = true
```

Update `loadEnvironmentIfNeeded()` to hydrate this from `PreferencesStore`:

```swift
    private func loadEnvironmentIfNeeded() async {
        guard environment == nil, loadError == nil else { return }
        do {
            let env = try await AppEnvironment.make()
            environment = env
            appDelegate.environment = env
            appDelegate.bootstrap()
            await env.bootstrap()
            try? await env.defaultsInstaller.installIfNeeded()
            // Plan 15 Task 9: prime the menu-bar visibility binding from
            // user prefs so the MenuBarExtra scene inserts (or not) on
            // first launch matching the saved setting.
            if let prefs = try? await env.preferencesStore.read() {
                statusBarItemVisible = prefs.statusBarItemVisible
            }
        } catch {
            loadError = "\(error)"
        }
    }
```

Then add the scene after the `Settings { … }` block:

```swift
        if let environment {
            MenuBarExtraScene(
                isInserted: $statusBarItemVisible,
                environment: environment,
                onQuickCapture: { appDelegate.quickCapturePanel?.toggle() }
            )
        }
```

- [ ] **Step 3: Remove the AppKit controller from `AppDelegate`**

In `Apps/Lillist-macOS/Sources/AppDelegate.swift`, delete the `statusBarController` property (line 12) and its usages in `bootstrap()` (lines 28-31) and `applicationWillTerminate(_:)` (line 36 — `statusBarController?.uninstall()`). The `MenuBarExtraScene` owns the lifecycle now.

- [ ] **Step 4: Delete `StatusBarController.swift`**

```bash
rm Apps/Lillist-macOS/Sources/StatusBar/StatusBarController.swift
```

(Keep `Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift` — Task 11 updates its refresh behavior.)

- [ ] **Step 5: Regenerate xcodegen for the new `MenuBar/` directory**

```bash
cd Apps && xcodegen generate --spec project.yml --project . && cd ..
git status --short Apps/Lillist-macOS.xcodeproj/project.pbxproj
```

- [ ] **Step 6: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift \
        Apps/Lillist-macOS/Sources/LillistApp.swift \
        Apps/Lillist-macOS/Sources/AppDelegate.swift \
        Apps/Lillist-macOS/Sources/StatusBar/StatusBarController.swift \
        Apps/Lillist-macOS.xcodeproj/project.pbxproj
git commit -m "refactor(macOS): migrate status bar to MenuBarExtra(.window) scene"
```

---

## Task 10: Verify `MenuBarExtra(.window)` popover anchors correctly

**Files:** (verification only — no code change unless the anchor is wrong)

The old `StatusBarController.showToday()` passed `preferredEdge: .minY`, which anchored the popover *upward* into the menu bar — wrong. `MenuBarExtra(.window)` auto-anchors below the status item (or above when the item is near the bottom of a vertically rotated screen). This task is a sanity check that the migration didn't regress.

- [ ] **Step 1: Manual smoke test**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Launch the built app (`open ./build/Debug/Lillist.app`). Click the checklist status item — the popover should appear directly below it, anchored to the bottom of the menu bar, *not* sliding up into the menu bar.

- [ ] **Step 2: No commit needed**

This task exists for traceability. If the popover *does* anchor wrong, the fix is to add `.menuBarExtraStyle(.window)` (already present in Task 9) — if it's somehow missing, restore it and create a fix-up commit; otherwise move on.

---

## Task 11: Fix `TodayPopoverView` stale-on-reopen

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift:26`

`.task { … }` fires once when the view first appears in a scene. With `MenuBarExtra(.window)`, the popover content view persists across open/close cycles (SwiftUI keeps the scene tree alive), so `.task` only runs the first time. Subsequent reopens show whatever was on screen when the user last closed. Fix by switching to `.onAppear { Task { await load() } }` (fires on every appearance) plus a `NotificationCenter` subscription so external changes (a new task being added in the main window) refresh the popover.

- [ ] **Step 1: Edit the modifiers**

In `Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift`, replace lines 24-27 (the `.padding`, `.frame`, `.task` block at the end of `body`) with:

```swift
        .padding()
        .frame(width: 320, height: 360)
        .onAppear { Task { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            Task { await load() }
        }
```

The `NSManagedObjectContextDidSave` subscription catches every store-side mutation (TaskStore.create, transition, update, etc.) and refreshes the popover. It fires on the actor's queue so the `Task { await load() }` hop is the right shape.

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. (`CoreData` is already imported transitively via `LillistCore`; if the build complains it isn't found, add `import CoreData` at the top of `TodayPopoverView.swift`.)

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift
git commit -m "fix(macOS): TodayPopoverView refreshes on every reopen and on save"
```

---

## Task 12: Delete the empty `StatusBarIcon` asset

**Files:**
- Delete: `Apps/Lillist-macOS/Resources/Assets.xcassets/StatusBarIcon.imageset/` (entire directory)

The asset folder has `Contents.json` declaring two image slots but ships zero PNGs. The `MenuBarExtra` scene uses `systemImage: "checklist"` (SF Symbol), so the empty asset is unreachable. Delete it to remove the build-time warning about missing image data.

- [ ] **Step 1: Remove the directory**

```bash
rm -rf Apps/Lillist-macOS/Resources/Assets.xcassets/StatusBarIcon.imageset/
```

- [ ] **Step 2: Regenerate xcodegen (resources catalog re-scanned)**

```bash
cd Apps && xcodegen generate --spec project.yml --project . && cd ..
```

- [ ] **Step 3: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | grep -E "warning|error" | head -5
```

Expected: no warnings about `StatusBarIcon`.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Resources/Assets.xcassets/StatusBarIcon.imageset \
        Apps/Lillist-macOS.xcodeproj/project.pbxproj
git commit -m "chore(macOS): remove empty StatusBarIcon asset (SF Symbol fallback)"
```

---

## Task 13: Open Quick Capture on the cursor's screen

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:42`
- Create: `Apps/Lillist-macOS/Tests/QuickCapturePlacementTests.swift`

`panel.center()` always picks the primary screen. Users on multi-monitor setups expect the panel on the screen where their cursor lives. Replace `center()` with `NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? .main` and place the panel ~1/3 from the top of that screen's `visibleFrame`.

We factor the placement math into a pure static helper so it's testable without `NSPanel`.

- [ ] **Step 1: Write the failing test**

Create `Apps/Lillist-macOS/Tests/QuickCapturePlacementTests.swift`:

```swift
import XCTest
import AppKit
@testable import Lillist_macOS // co-compiled via Apps/project.yml below

final class QuickCapturePlacementTests: XCTestCase {
    func test_origin_centersHorizontally_thirdFromTop() {
        // 1920×1080 screen with 25pt menu bar at the top:
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = NSRect(x: 0, y: 0, width: 1920, height: 1055)
        let panel  = NSSize(width: 560, height: 140)

        let origin = QuickCapturePanelController.placementOrigin(
            screenFrame: screen,
            visibleFrame: visible,
            panelSize: panel
        )

        // Horizontal: centered → (1920 - 560) / 2 = 680
        XCTAssertEqual(origin.x, 680, accuracy: 0.5)
        // Vertical: ~1/3 from the top of the visible frame; AppKit's
        // coordinate space has origin at bottom-left, so the panel's
        // origin.y = visible.maxY - (visible.height / 3) - panel.height.
        let expectedY = visible.maxY - (visible.height / 3) - panel.height
        XCTAssertEqual(origin.y, expectedY, accuracy: 0.5)
    }

    func test_origin_offsetSecondaryScreen() {
        // 1440×900 secondary screen positioned to the right of a 2560
        // primary, with a 25pt menu bar.
        let screen = NSRect(x: 2560, y: 0, width: 1440, height: 900)
        let visible = NSRect(x: 2560, y: 0, width: 1440, height: 875)
        let panel  = NSSize(width: 560, height: 140)

        let origin = QuickCapturePanelController.placementOrigin(
            screenFrame: screen,
            visibleFrame: visible,
            panelSize: panel
        )

        XCTAssertEqual(origin.x, 2560 + (1440 - 560) / 2, accuracy: 0.5)
    }
}
```

- [ ] **Step 2: Add `placementOrigin` and rewrite `present()`**

In `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift`, replace lines 20-46 (the `present()` method) with:

```swift
    func present() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = true // Plan 15 Task 16: drop shadow under borderless panel

        let host = NSHostingController(
            rootView: QuickCaptureView(
                text: Binding(get: { self.text }, set: { self.text = $0 }),
                onSubmit: { [weak self] r in self?.submit(r) },
                onCancel: { [weak self] in self?.close() }
            )
            .environment(environment)
        )
        panel.contentView = host.view

        // Plan 15 Task 13: place on the screen under the cursor (or
        // primary if the cursor isn't over any screen — e.g. a
        // disconnected display) at ~1/3 from the top of that screen's
        // visible frame. `placementOrigin` is a pure helper for tests.
        let target = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? .main
        let screenFrame = target?.frame ?? .zero
        let visibleFrame = target?.visibleFrame ?? .zero
        let origin = Self.placementOrigin(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            panelSize: panel.frame.size
        )
        panel.setFrameOrigin(origin)

        panel.makeKeyAndOrderFront(nil)
        // Plan 15 Task 15: do NOT call NSApp.activate(ignoringOtherApps:)
        // — that defeats `.nonactivatingPanel` and steals menu bar focus
        // from whatever app the user was in. The panel can be key
        // without bringing the app forward.

        // Plan 15 Task 14: dismiss when the panel resigns key (e.g. the
        // user clicked away or hit ⌘Tab to switch apps).
        installResignKeyObserver(on: panel)

        self.panel = panel
    }

    /// Pure-math helper: given a screen frame, that screen's visible
    /// frame (excluding the menu bar and Dock), and the panel's size,
    /// return the bottom-left origin that centers the panel
    /// horizontally and places its top edge ~1/3 down from the top of
    /// the visible frame.
    ///
    /// AppKit uses bottom-left-origin coordinates, so the panel's
    /// `origin.y` equals `visibleFrame.maxY - (visibleFrame.height / 3)
    /// - panelSize.height`.
    static func placementOrigin(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        panelSize: NSSize
    ) -> NSPoint {
        let x = screenFrame.origin.x + (screenFrame.width - panelSize.width) / 2
        let y = visibleFrame.maxY - (visibleFrame.height / 3) - panelSize.height
        return NSPoint(x: x, y: y)
    }

    private func installResignKeyObserver(on panel: NSPanel) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.close()
        }
    }
```

(`close()` already removes the panel; it's idempotent. We don't bother removing the NotificationCenter observer because closing the panel removes its target and the observer becomes a no-op; the panel is also released in `close()` so the observer drops out with it.)

- [ ] **Step 3: Add the test source to the test bundle's co-compile list**

Add to `Apps/project.yml` under the test target's `sources:`:

```yaml
      - path: Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift
```

Then regenerate xcodegen:

```bash
cd Apps && xcodegen generate --spec project.yml --project . && cd ..
```

- [ ] **Step 4: Run the new tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/QuickCapturePlacementTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift \
        Apps/Lillist-macOS/Tests/QuickCapturePlacementTests.swift \
        Apps/project.yml \
        Apps/Lillist-macOS.xcodeproj/project.pbxproj
git commit -m "feat(macOS): Quick Capture panel opens on cursor's screen, 1/3 from top"
```

---

## Task 14: Dismiss Quick Capture panel on resign-key

**Files:** (already handled in Task 13 — verification only)

Task 13's `installResignKeyObserver(on:)` already subscribes to `NSWindow.didResignKeyNotification` and calls `close()` when the panel loses key. The previous behavior (`hidesOnDeactivate = false`, no resign handler) meant the panel stuck around even after the user clicked away. This task exists for traceability and to confirm the observer fires correctly.

- [ ] **Step 1: Manual smoke test**

Launch the app, press the global hotkey (⌃⌥Space), confirm the Quick Capture panel appears. Click outside the panel (or hit ⌘Tab). Expect the panel to close.

- [ ] **Step 2: No commit needed** (covered by Task 13).

---

## Task 15: Remove `NSApp.activate(ignoringOtherApps:)` from Quick Capture

**Files:** (already handled in Task 13 — verification only)

The deleted line was `NSApp.activate(ignoringOtherApps: true)` (was line 44). Calling this contradicts `.nonactivatingPanel`'s entire purpose: the panel is meant to float over whatever app the user was in *without* stealing focus from the menu bar / app switcher. Keeping `activate(ignoringOtherApps:)` made Lillist briefly become the frontmost app on every Quick Capture, which broke ⌘Tab muscle memory.

- [ ] **Step 1: Verify the line is gone**

```bash
grep -n "NSApp.activate" Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift
```

Expected: no results (or only results in comments).

- [ ] **Step 2: No commit needed** (covered by Task 13).

---

## Task 16: Render hotkey modifiers as SF Symbols

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift:21-37`

The recorder currently displays the raw encoded combo string (`"ctrl+opt+space"`). macOS users expect modifier glyphs: ⌃ ⌥ ⌘ ⇧. SF Symbols `command`, `option`, `control`, `shift` render the canonical glyphs at any size; the key glyph (the letter / function key) renders inside a `KeyCapView`-style rounded rect to match the system Settings → Keyboard pane.

We don't change the *encoding* (the underlying `value` Binding is still `"ctrl+opt+space"`); only the *display*.

- [ ] **Step 1: Add a `displayView` that parses `value` for rendering**

In `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift`, replace the entire `body` property (lines 19-38) with:

```swift
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    recording ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: 1
                )
            HStack {
                if recording {
                    Text("Press a key combination…")
                        .foregroundStyle(.secondary)
                } else {
                    glyphRow
                }
                Spacer()
                Button(recording ? "Stop" : "Record") {
                    toggleRecording()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
    }

    /// SF-Symbol-based render of the current `value`. Falls back to the
    /// raw string ("—" for empty) if the value can't be parsed by
    /// `GlobalHotkeyMonitor.parse`. The display agrees with the system
    /// Settings → Keyboard Shortcuts pane (⌃⌥⇧⌘ + key cap).
    @ViewBuilder
    private var glyphRow: some View {
        if value.isEmpty {
            Text("—").foregroundStyle(.secondary)
        } else {
            let tokens = value.split(separator: "+").map { String($0).lowercased() }
            HStack(spacing: 2) {
                ForEach(tokens.dropLast(), id: \.self) { mod in
                    Image(systemName: Self.symbolName(forModifier: mod))
                        .accessibilityHidden(true)
                }
                if let key = tokens.last {
                    KeyCap(label: Self.keyCapLabel(for: key))
                }
            }
            .accessibilityLabel(Self.accessibilityDescription(for: tokens))
        }
    }

    /// SF Symbol name for a modifier token. Mirrors the canonical
    /// tokens emitted by `encode(modifiers:keyCode:)`.
    nonisolated private static func symbolName(forModifier token: String) -> String {
        switch token {
        case "ctrl":  return "control"
        case "opt":   return "option"
        case "cmd":   return "command"
        case "shift": return "shift"
        default:      return "questionmark"
        }
    }

    /// Friendly label for the key glyph inside a `KeyCap`. Most letters
    /// render uppercase; whitespace and navigation keys spell out
    /// (`space`, `return`, `delete`, `escape`); function keys keep
    /// their `F1` form.
    nonisolated private static func keyCapLabel(for token: String) -> String {
        switch token {
        case "space":  return "space"
        case "return": return "↩"
        case "delete": return "⌫"
        case "escape": return "esc"
        default:       return token.uppercased()
        }
    }

    nonisolated private static func accessibilityDescription(for tokens: [String]) -> String {
        let mods = tokens.dropLast().map { friendlyModifier($0) }
        let key = tokens.last.map { friendlyKey($0) } ?? "no key"
        return (mods + [key]).joined(separator: " ")
    }

    nonisolated private static func friendlyModifier(_ token: String) -> String {
        switch token {
        case "ctrl":  return "Control"
        case "opt":   return "Option"
        case "cmd":   return "Command"
        case "shift": return "Shift"
        default:      return token
        }
    }

    nonisolated private static func friendlyKey(_ token: String) -> String {
        switch token {
        case "space":  return "Space"
        case "return": return "Return"
        case "delete": return "Delete"
        case "escape": return "Escape"
        default:       return token.uppercased()
        }
    }
```

- [ ] **Step 2: Add a `KeyCap` private view at the bottom of the file**

Append to the bottom of `HotkeyRecorder.swift` (above the closing `}` of the struct if you put it inline, or after the struct as a fileprivate type):

```swift
private struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
                    )
            )
    }
}
```

- [ ] **Step 3: Drop the now-unused `displayString` computed property**

In `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift`, delete the `private var displayString: String` block (was lines 40-42).

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Open Preferences → Quick Capture to eyeball-test that the displayed combo shows SF Symbol glyphs.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift
git commit -m "feat(macOS): render hotkey combo with SF Symbol modifier glyphs and KeyCap"
```

---

## Task 17: Audit `QuickCaptureView` material for Tahoe

**Files:**
- Audit (potentially modify): `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift:46`

The current `.background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))` is heavier than the Tahoe-native Liquid Glass look. Switch to `.regularMaterial` and conditionally apply `.glassBackgroundEffect()` if the deployment target allows.

- [ ] **Step 1: Read the file and decide**

```bash
sed -n '40,52p' Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift
```

If the macOS deployment target is `15.0` (which it is — see `Apps/project.yml:5`), `.glassBackgroundEffect()` (added in macOS 26) requires an `if #available` guard.

- [ ] **Step 2: Edit the material**

In `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift`, replace line 46 with:

```swift
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        #if os(macOS)
        .modifier(QuickCaptureGlassBackgroundIfAvailable())
        #endif
```

Add at the bottom of the file:

```swift
#if os(macOS)
/// Applies the Tahoe Liquid Glass material on macOS 26+; no-op on
/// earlier OSes. Wrapped in a `ViewModifier` so the call site stays
/// flat and the availability check is local.
private struct QuickCaptureGlassBackgroundIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassBackgroundEffect()
        } else {
            content
        }
    }
}
#endif
```

- [ ] **Step 3: Re-record the Quick Capture snapshots**

```bash
rm -f Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__/MacOSScreenTourTests/test_04_quickCapture_empty_light.1.png \
      Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__/MacOSScreenTourTests/test_05_quickCapture_typed_dark.1.png
swift test --package-path Packages/LillistUI --filter 'MacOSScreenTourTests/test_04' 2>&1 | tail -3
swift test --package-path Packages/LillistUI --filter 'MacOSScreenTourTests/test_05' 2>&1 | tail -3
```

(Both should regenerate; subsequent runs match the new baselines.)

- [ ] **Step 4: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift \
        Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__/MacOSScreenTourTests/
git commit -m "refactor(ui): Quick Capture uses .regularMaterial with optional glassBackgroundEffect"
```

(If the new material doesn't visually improve things, revert this commit — the Plan 15 scope explicitly allows skipping this task.)

---

## Task 18: Reject bare-modifier-less hotkey combos in `HotkeyRecorder`

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift` (the `encode(modifiers:keyCode:)` static)
- Create: `Apps/Lillist-macOS/Tests/HotkeyRecorderConflictTests.swift`

A user could currently record `⌘Q` as the Quick Capture combo, which would shadow Quit. The recorder should refuse to encode any combo whose modifier set lacks at least one of `⌃` / `⌥` / `⇧`. Plain `⌘` + letter is reserved for application-level shortcuts.

Practical examples of what we reject:
- `cmd+q` (Quit)
- `cmd+w` (Close)
- `cmd+space` (Spotlight)
- `cmd+tab` (App switcher)
- `cmd+letter` in general

We *accept*: `ctrl+opt+space` (default), `cmd+shift+l`, `cmd+option+x`, plain function keys (`f5`), etc.

- [ ] **Step 1: Write the failing test**

Create `Apps/Lillist-macOS/Tests/HotkeyRecorderConflictTests.swift`:

```swift
import XCTest
import AppKit
@testable import Lillist_macOS

final class HotkeyRecorderConflictTests: XCTestCase {

    func test_rejects_bareCommand() {
        XCTAssertNil(HotkeyRecorder.encode(modifiers: [.command], keyCode: 12 /* q */))
        XCTAssertNil(HotkeyRecorder.encode(modifiers: [.command], keyCode: 13 /* w */))
        XCTAssertNil(HotkeyRecorder.encode(modifiers: [.command], keyCode: 49 /* space */))
    }

    func test_rejects_noModifier() {
        XCTAssertNil(HotkeyRecorder.encode(modifiers: [], keyCode: 49))
        XCTAssertNil(HotkeyRecorder.encode(modifiers: [], keyCode: 12))
    }

    func test_accepts_commandWithSecondModifier() {
        XCTAssertNotNil(HotkeyRecorder.encode(modifiers: [.command, .shift], keyCode: 37 /* l */))
        XCTAssertNotNil(HotkeyRecorder.encode(modifiers: [.command, .option], keyCode: 35 /* p */))
    }

    func test_accepts_controlOption() {
        XCTAssertNotNil(HotkeyRecorder.encode(modifiers: [.control, .option], keyCode: 49))
    }

    func test_accepts_functionKey_withModifier() {
        XCTAssertNotNil(HotkeyRecorder.encode(modifiers: [.shift], keyCode: 122 /* f1 */))
    }
}
```

- [ ] **Step 2: Add the guard inside `encode`**

In `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift`, modify `encode(modifiers:keyCode:)` (currently around lines 82-97). Insert the guard at the top of the method body, before the `parts` array is built:

```swift
    nonisolated static func encode(modifiers: NSEvent.ModifierFlags, keyCode: Int) -> String? {
        // Plan 15 Task 18: require at least one of ⌃ / ⌥ / ⇧ in the
        // modifier set. Bare ⌘+letter combos would shadow standard
        // application shortcuts (⌘Q quit, ⌘W close, ⌘Space Spotlight,
        // …). A combo with no modifiers at all is also rejected — a
        // global hotkey without modifiers would intercept every
        // bare keystroke on the system.
        let hasNonCommandModifier = modifiers.contains(.control)
            || modifiers.contains(.option)
            || modifiers.contains(.shift)
        guard hasNonCommandModifier else { return nil }

        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.shift) { parts.append("shift") }
        guard let keyName = keyName(for: keyCode) else { return nil }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }
```

(`cmd+shift+l` still encodes — `shift` satisfies the guard. `cmd+q` does not — only `.command` is present.)

- [ ] **Step 3: Run the new tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/HotkeyRecorderConflictTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

Expected: 5 PASS.

- [ ] **Step 4: Run the existing `HotkeyRecorderTests` to confirm no regression**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/HotkeyRecorderTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

Expected: 4 PASS (3 existing + Plan 12 Task 4's round-trip). The default `ctrl+opt+space` still encodes; both `cmd+shift+l` examples in the round-trip test still pass.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift \
        Apps/Lillist-macOS/Tests/HotkeyRecorderConflictTests.swift \
        Apps/project.yml \
        Apps/Lillist-macOS.xcodeproj/project.pbxproj
git commit -m "feat(macOS): reject hotkey combos lacking control/option/shift"
```

(`Apps/project.yml` and `.pbxproj` are only included if you needed to add the new test file to the test target — xcodegen usually picks up new test files automatically via the directory glob on `Apps/Lillist-macOS/Tests`.)

---

## Task 19: Dock badge for today / overdue counts

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/AppDelegate.swift`

`NSApp.dockTile.badgeLabel` accepts a `String?` and renders as a red dot on the app's dock icon. Subscribe to `NSManagedObjectContextDidSave` (every store-side mutation refreshes the count) and to `AccountStateMonitor`'s stream (sync events also imply data changes). Use `SmartFilterStore.fetch(byName: "Today")` + `evaluate(id:)` to get the count.

- [ ] **Step 1: Add the dock badge subscription**

In `Apps/Lillist-macOS/Sources/AppDelegate.swift`, add an `@MainActor` method `installDockBadge()` and call it from `bootstrap()`:

```swift
    func bootstrap() {
        guard let env = environment, quickCapturePanel == nil else { return }
        let panel = QuickCapturePanelController(environment: env)
        env.hotkeyMonitor.onHotkey = { panel.toggle() }
        env.hotkeyMonitor.install()
        self.quickCapturePanel = panel

        // Plan 15 Task 19: dock badge.
        installDockBadge()
        // Plan 15 Task 20: dock menu (overridden via
        // `applicationDockMenu(_:)` below).
        // Plan 15 Task 23: services provider.
        NSApp.servicesProvider = LillistServicesProvider(environment: env)
        NSUpdateDynamicServices()
    }

    /// Refreshes `NSApp.dockTile.badgeLabel` whenever Core Data saves
    /// (i.e. any task mutation, sync apply, etc.). The count is the
    /// size of the "Today" smart filter's evaluate output; if that
    /// filter is missing for any reason, the badge is cleared.
    private func installDockBadge() {
        guard let env = environment else { return }
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshDockBadge() }
        }
        Task { @MainActor in await self.refreshDockBadge() }
        _ = env // suppress unused-warning when refactoring
    }

    @MainActor
    private func refreshDockBadge() async {
        guard let env = environment else { return }
        do {
            let today = try await env.smartFilterStore.fetch(byName: "Today")
            let count = try await env.smartFilterStore.evaluate(id: today.id).count
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        } catch {
            NSApp.dockTile.badgeLabel = nil
        }
    }
```

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. (`CoreData` is imported transitively via `LillistCore`; if the compiler complains, add `import CoreData` at the top of `AppDelegate.swift`.)

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Sources/AppDelegate.swift
git commit -m "feat(macOS): dock badge shows Today count, refreshes on Core Data save"
```

---

## Task 20: Dock menu with Quick Capture, Today, and pinned filters

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/AppDelegate.swift`

`applicationDockMenu(_:)` lets AppKit ask for a menu when the user right-clicks the dock icon. Standard items: Quick Capture, Today's tasks, then dynamically-built items for each pinned smart filter. Tapping a filter sends a notification the main window listens for to select that filter.

- [ ] **Step 1: Implement `applicationDockMenu(_:)`**

In `Apps/Lillist-macOS/Sources/AppDelegate.swift`, add:

```swift
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let quick = NSMenuItem(
            title: "Quick Capture…",
            action: #selector(quickCaptureAction),
            keyEquivalent: ""
        )
        quick.target = self
        menu.addItem(quick)

        let today = NSMenuItem(
            title: "Today's Tasks…",
            action: #selector(showTodayAction),
            keyEquivalent: ""
        )
        today.target = self
        menu.addItem(today)

        // Dynamically-built pinned filters. Read synchronously from
        // a cached list maintained on every refresh; if the cache
        // hasn't populated yet, omit the section. The cache itself
        // is refreshed by the existing Core Data save subscription
        // installed in `installDockBadge()`.
        if !pinnedFilterCache.isEmpty {
            menu.addItem(.separator())
            for filter in pinnedFilterCache {
                let item = NSMenuItem(
                    title: filter.name,
                    action: #selector(selectPinnedFilter(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = filter.id
                menu.addItem(item)
            }
        }

        return menu
    }

    @objc private func quickCaptureAction() {
        quickCapturePanel?.toggle()
    }

    @objc private func showTodayAction() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.title == "Lillist" {
            w.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .lillistSelectTodayFilter, object: nil)
    }

    @objc private func selectPinnedFilter(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.title == "Lillist" {
            w.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(
            name: .lillistSelectFilter, object: nil, userInfo: ["id": id]
        )
    }

    // MARK: - Pinned filter cache

    /// Cached snapshot of the user's pinned smart filters. Read by the
    /// dock menu (which fires synchronously). Refreshed on every Core
    /// Data save by `installDockBadge()`'s observer — extend that path
    /// to also call `refreshPinnedFilterCache()`.
    private var pinnedFilterCache: [SmartFilterStore.SmartFilterRecord] = []

    @MainActor
    private func refreshPinnedFilterCache() async {
        guard let env = environment else { return }
        let all = (try? await env.smartFilterStore.list()) ?? []
        pinnedFilterCache = all.filter(\.isPinned)
    }
```

Then update `installDockBadge()` from Task 19 to also refresh the pinned filter cache:

```swift
    private func installDockBadge() {
        guard let env = environment else { return }
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshDockBadge()
                await self?.refreshPinnedFilterCache()
            }
        }
        Task { @MainActor in
            await self.refreshDockBadge()
            await self.refreshPinnedFilterCache()
        }
        _ = env
    }
```

- [ ] **Step 2: Add the new notification names**

In `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`, append to the `extension Notification.Name`:

```swift
    static let lillistSelectTodayFilter = Notification.Name("lillist.selectTodayFilter")
    static let lillistSelectFilter      = Notification.Name("lillist.selectFilter")
```

- [ ] **Step 3: Have `RootSplitView` respond to the new notifications**

In `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift`, append to the chain of `.onReceive` modifiers (before the `.onChange(of: sidebarSelection)`):

```swift
        .onReceive(NotificationCenter.default.publisher(for: .lillistSelectTodayFilter)) { _ in
            Task {
                if let today = try? await env.smartFilterStore.fetch(byName: "Today") {
                    sidebarSelection = .pinnedFilter(today.id)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lillistSelectFilter)) { note in
            if let id = note.userInfo?["id"] as? UUID {
                sidebarSelection = .pinnedFilter(id)
            }
        }
```

- [ ] **Step 4: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/AppDelegate.swift \
        Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift \
        Apps/Lillist-macOS/Sources/Views/RootSplitView.swift
git commit -m "feat(macOS): dock menu with Quick Capture, Today, and pinned filters"
```

---

## Task 21: Custom About box

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`

Standard SwiftUI gives us a free About panel, but adding a `credits:` attributed string lets us claim a byline. Replace `.appInfo` with a custom `CommandGroup`.

- [ ] **Step 1: Add the command group**

In `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`, add inside `var body: some Commands { … }` (after the existing groups):

```swift
        CommandGroup(replacing: .appInfo) {
            Button("About Lillist") {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .credits: NSAttributedString(
                        string: "Built by Mikey Ward",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                            .foregroundColor: NSColor.secondaryLabelColor
                        ]
                    )
                ])
            }
        }
```

`AppKit` is already in scope via `LillistApp`'s transitive imports; if not, add `import AppKit` at the top of `LillistCommands.swift`.

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift
git commit -m "feat(macOS): custom About panel with byline credit"
```

---

## Task 22: Help menu link

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`

The default Help menu has only a search field bound to the app's `.help` documentation, which Lillist doesn't ship. Replace it with a single `Link("Lillist Help", destination: …)` until we have real online docs.

**Note for the implementer:** the URL is a placeholder. Confirm the target URL with the user (mikeyward) before merging this commit — `https://github.com/mikeydotio/Lillist` is a reasonable default, but the user may prefer a custom landing page. If unsure, use the GitHub repo URL and leave a TODO so the link is easy to swap later.

- [ ] **Step 1: Add the command group**

In `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`, add inside `var body: some Commands { … }`:

```swift
        CommandGroup(replacing: .help) {
            // TODO: Confirm URL with mikey before launch. Currently
            // points at the public repo; replace with a docs page
            // when one exists.
            Link("Lillist Help", destination: URL(string: "https://github.com/mikeydotio/Lillist")!)
        }
```

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift
git commit -m "feat(macOS): Help menu opens repo URL (placeholder pending docs site)"
```

---

## Task 23: Services menu — "Add to Lillist as task"

**Files:**
- Create: `Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift`
- Modify: `Apps/Lillist-macOS/Sources/AppDelegate.swift` (already wires `NSApp.servicesProvider` in Task 19's `bootstrap()` — verify)
- Modify: `Apps/Lillist-macOS/Info.plist` (declare the service)

`NSServicesProvider` is the AppKit API behind the Services submenu. To expose a "Add to Lillist as task" service that takes selected text from any app, we:

1. Implement a class with `@objc func addToLillistAsTask(_ pasteboard:userData:error:)` matching the AppKit selector shape.
2. Register it via `NSApp.servicesProvider = …` (done in Task 19's `bootstrap()`).
3. Declare it in `Info.plist`'s `NSServices` array so the system shows it in the Services menu.

- [ ] **Step 1: Create the provider**

Create `Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift`:

```swift
import AppKit
import LillistCore

/// Plan 15 Task 23: AppKit Services provider. Exposes
/// "Add to Lillist as task" in the system Services submenu — selecting
/// text in any app and choosing this item creates a new task whose
/// title is the selected text.
///
/// Registered via `NSApp.servicesProvider = self` in
/// `AppDelegate.bootstrap()`. The corresponding `NSServices` entry in
/// `Info.plist` declares the service to the system so it appears in
/// the menu.
@MainActor
final class LillistServicesProvider: NSObject {
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    /// Matches the selector pattern AppKit calls when the user picks
    /// the service from the Services submenu. The selector name is
    /// declared in `Info.plist` under `NSServices > NSMessage`.
    ///
    /// - Parameters:
    ///   - pasteboard: contains the selection (any of the types
    ///     declared in `NSServices > NSSendTypes`).
    ///   - userData: unused; AppKit threads it through unchanged.
    ///   - error: writable autorelease pointer — populate with a
    ///     localized message if the service fails.
    @objc func addToLillistAsTask(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let raw = pasteboard.string(forType: .string),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "Lillist could not read the selected text." as NSString
            return
        }
        // Title is the first line; everything else becomes notes.
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        let title = String(lines.first ?? "").trimmingCharacters(in: .whitespaces)
        let notes = lines.dropFirst().joined(separator: "\n")

        Task { @MainActor in
            do {
                let id = try await environment.taskStore.create(title: title)
                if !notes.isEmpty {
                    try await environment.taskStore.update(id: id) { $0.notes = notes }
                }
            } catch {
                // The Services API has no inline UI to report failure;
                // log and move on. The user can confirm by opening
                // Lillist's main window.
                NSLog("LillistServicesProvider failed: \(error)")
            }
        }
    }
}
```

- [ ] **Step 2: Declare the service in `Info.plist`**

In `Apps/Lillist-macOS/Info.plist`, add a new `NSServices` array entry before the closing `</dict>`:

```xml
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Add to Lillist as task</string>
            </dict>
            <key>NSMessage</key>
            <string>addToLillistAsTask</string>
            <key>NSPortName</key>
            <string>Lillist</string>
            <key>NSSendTypes</key>
            <array>
                <string>NSStringPboardType</string>
                <string>public.utf8-plain-text</string>
            </array>
            <key>NSReturnTypes</key>
            <array/>
        </dict>
    </array>
```

(`NSPortName` should match the app's CFBundleName, which is `Lillist`. AppKit uses the port name to route the service callback to the right process.)

- [ ] **Step 3: Verify `AppDelegate.bootstrap()` registers the provider**

```bash
grep -n "servicesProvider\|NSUpdateDynamicServices" Apps/Lillist-macOS/Sources/AppDelegate.swift
```

Expected: matches from Task 19 — `NSApp.servicesProvider = LillistServicesProvider(environment: env)` and `NSUpdateDynamicServices()`. If those are missing (e.g. Task 19 was skipped), add them now.

- [ ] **Step 4: Regenerate xcodegen for the new `Services/` directory**

```bash
cd Apps && xcodegen generate --spec project.yml --project . && cd ..
```

- [ ] **Step 5: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Manual smoke test: launch the app, select text in any other app (e.g. Safari), pick Services → "Add to Lillist as task" — a task should appear in Lillist with the selected text as its title.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift \
        Apps/Lillist-macOS/Sources/AppDelegate.swift \
        Apps/Lillist-macOS/Info.plist \
        Apps/Lillist-macOS.xcodeproj/project.pbxproj
git commit -m "feat(macOS): Services menu item 'Add to Lillist as task'"
```

---

## Task 24: Spotlight indexing

**Files:**
- Create: `Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift`
- Create: `Apps/Lillist-macOS/Tests/IndexingServiceTests.swift`
- Modify: `Apps/Lillist-macOS/Sources/AppDelegate.swift` (call `start()` from `bootstrap()`)

Spotlight integration goes through `CoreSpotlight`: each `CSSearchableItem` has a `uniqueIdentifier`, a `domainIdentifier` (we use `com.mikeydotio.lillist.task`), and a `contentAttributeSet` (`CSSearchableItemAttributeSet`) holding title / contentDescription / keywords. We push items into `CSSearchableIndex.default()` on every TaskStore change, and re-index from scratch on launch if a signature key in UserDefaults is stale (e.g. major version change).

- [ ] **Step 1: Write the failing test**

Create `Apps/Lillist-macOS/Tests/IndexingServiceTests.swift`:

```swift
import XCTest
import CoreSpotlight
import LillistCore
@testable import Lillist_macOS

@MainActor
final class IndexingServiceTests: XCTestCase {

    func test_attributeSet_populatesTitleNotesKeywords() {
        let task = TaskStore.TaskRecord(
            id: UUID(),
            title: "Draft launch email",
            notes: "Mention CloudKit sync and the new recurrence engine.",
            status: .started,
            start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false,
            position: 0, isPinned: false, parentID: nil,
            createdAt: Date(), modifiedAt: Date(),
            closedAt: nil, deletedAt: nil
        )
        let attrs = IndexingService.attributeSet(for: task, tagNames: ["work", "urgent"])
        XCTAssertEqual(attrs.title, "Draft launch email")
        XCTAssertEqual(attrs.contentDescription, "Mention CloudKit sync and the new recurrence engine.")
        let keywords = (attrs.keywords ?? [])
        XCTAssertTrue(keywords.contains("work"))
        XCTAssertTrue(keywords.contains("urgent"))
    }

    func test_searchableItem_usesCanonicalDomainIdentifier() {
        let task = TaskStore.TaskRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "x", notes: "", status: .todo,
            start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false,
            position: 0, isPinned: false, parentID: nil,
            createdAt: Date(), modifiedAt: Date(),
            closedAt: nil, deletedAt: nil
        )
        let item = IndexingService.searchableItem(for: task, tagNames: [])
        XCTAssertEqual(item.domainIdentifier, "com.mikeydotio.lillist.task")
        XCTAssertEqual(item.uniqueIdentifier, task.id.uuidString)
    }
}
```

- [ ] **Step 2: Create `IndexingService`**

Create `Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift`:

```swift
import CoreSpotlight
import Foundation
import LillistCore

/// Plan 15 Task 24: pushes Lillist tasks into the system Spotlight
/// index. Each task becomes a `CSSearchableItem` under the
/// `com.mikeydotio.lillist.task` domain identifier, so the user can
/// find their tasks from any Spotlight search and the system can
/// optionally surface them in `Show More From Lillist…`.
///
/// `start()` is idempotent: it subscribes once to Core Data save
/// notifications and re-indexes any modified tasks; on first invocation
/// it also performs a full reindex if the signature key in
/// UserDefaults is stale.
@MainActor
final class IndexingService {
    /// Canonical domain identifier — used by both `CSSearchableItem`
    /// (for grouping) and `CSSearchableIndex.delete(domainIdentifier:)`
    /// (for purging on uninstall / app reset).
    static let domainIdentifier = "com.mikeydotio.lillist.task"

    /// UserDefaults key marking the index format version. Bump when
    /// the attribute-set shape changes to trigger a full reindex.
    private static let indexSignatureKey = "lillist.spotlight.indexSignature"
    private static let currentIndexSignature = "v1"

    private let environment: AppEnvironment
    private var saveObserver: NSObjectProtocol?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func start() async {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: Self.indexSignatureKey)
        if stored != Self.currentIndexSignature {
            await reindexAll()
            defaults.set(Self.currentIndexSignature, forKey: Self.indexSignatureKey)
        }
        installSaveObserver()
    }

    func stop() {
        if let observer = saveObserver {
            NotificationCenter.default.removeObserver(observer)
            saveObserver = nil
        }
    }

    private func installSaveObserver() {
        saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.indexChangedTasks() }
        }
    }

    /// Re-indexes every non-trashed task. Called on first launch (or
    /// after a signature bump). Tasks in the trash are removed from
    /// the index via `deleteSearchableItems(withIdentifiers:)`.
    func reindexAll() async {
        do {
            let live = try await environment.taskStore.children(of: nil)
            let trashed = try await environment.taskStore.trashed()
            let items = live.map { Self.searchableItem(for: $0, tagNames: []) }
            try await CSSearchableIndex.default().indexSearchableItems(items)
            let trashedIDs = trashed.map(\.id.uuidString)
            if !trashedIDs.isEmpty {
                try await CSSearchableIndex.default()
                    .deleteSearchableItems(withIdentifiers: trashedIDs)
            }
        } catch {
            NSLog("IndexingService.reindexAll failed: \(error)")
        }
    }

    /// Refreshes the index for whatever the last Core Data save
    /// touched. We don't have per-save deltas, so the cheap-and-correct
    /// option is to re-push the same items — `indexSearchableItems`
    /// is upsert-shaped and Spotlight de-duplicates by
    /// `uniqueIdentifier`. A future optimization is to subscribe to
    /// the `NSManagedObjectContextObjectsDidChange` notification and
    /// push only the inserted/updated objects.
    private func indexChangedTasks() async {
        await reindexAll()
    }

    // MARK: - Pure mappers (testable)

    /// Constructs the `CSSearchableItemAttributeSet` for a task. Pure
    /// function — no Core Data access, no Spotlight side effects —
    /// so tests can assert on the attribute set without standing up
    /// a real index.
    nonisolated static func attributeSet(
        for record: TaskStore.TaskRecord,
        tagNames: [String]
    ) -> CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = record.title
        attrs.contentDescription = record.notes.isEmpty ? nil : record.notes
        attrs.keywords = tagNames
        return attrs
    }

    /// Constructs the full `CSSearchableItem` (attribute set + IDs)
    /// for a task. Pairs with `attributeSet(for:tagNames:)`.
    nonisolated static func searchableItem(
        for record: TaskStore.TaskRecord,
        tagNames: [String]
    ) -> CSSearchableItem {
        CSSearchableItem(
            uniqueIdentifier: record.id.uuidString,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributeSet(for: record, tagNames: tagNames)
        )
    }
}
```

- [ ] **Step 3: Start `IndexingService` from `AppDelegate.bootstrap()`**

In `Apps/Lillist-macOS/Sources/AppDelegate.swift`, add a property and start it:

```swift
    var indexingService: IndexingService?

    func bootstrap() {
        guard let env = environment, quickCapturePanel == nil else { return }
        // … existing setup …

        // Plan 15 Task 24: kick off Spotlight indexing.
        let indexer = IndexingService(environment: env)
        Task { await indexer.start() }
        self.indexingService = indexer
    }
```

- [ ] **Step 4: Add the test source and the live source to the test bundle**

Add to `Apps/project.yml` under the test target's `sources:`:

```yaml
      - path: Lillist-macOS/Sources/Indexing/IndexingService.swift
```

Then regenerate xcodegen:

```bash
cd Apps && xcodegen generate --spec project.yml --project . && cd ..
```

- [ ] **Step 5: Run the new tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/IndexingServiceTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

Expected: 2 PASS.

- [ ] **Step 6: Build the app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift \
        Apps/Lillist-macOS/Sources/AppDelegate.swift \
        Apps/Lillist-macOS/Tests/IndexingServiceTests.swift \
        Apps/project.yml \
        Apps/Lillist-macOS.xcodeproj/project.pbxproj
git commit -m "feat(macOS): Spotlight indexing via IndexingService and CSSearchableIndex"
```

---

## Task 25: `NSUserActivity` for Handoff and Continuity

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift`

When the user is viewing a task, broadcast an `NSUserActivity` so the iPhone / iPad can pick up where the Mac left off (and vice versa once the iOS app implements the reciprocal continuation handler). SwiftUI's `.userActivity(_:isActive:_:)` modifier handles registration; we just populate `userInfo`, `title`, and the eligibility flags.

- [ ] **Step 1: Add the modifier**

In `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift`, append a `.userActivity(...)` modifier to the `Form` (after the `.sheet(isPresented: $showingRecurrenceEditor)`):

```swift
        .userActivity(
            "com.mikeydotio.lillist.viewing-task",
            isActive: record != nil
        ) { activity in
            guard let r = record else { return }
            activity.userInfo = ["taskID": r.id.uuidString]
            activity.title = r.title
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.requiredUserInfoKeys = ["taskID"]
        }
```

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift
git commit -m "feat(macOS): broadcast NSUserActivity for the focused task (Handoff)"
```

---

## Task 26: Preferences window — intrinsic per-pane sizing

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Preferences/PreferencesWindow.swift:24`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/{GeneralPane,NotificationsPane,TrashPane,QuickCapturePane,CrashReportingPane,AdvancedPane}.swift` (each gets `.fixedSize()`)

System Settings panes intrinsically size themselves, and the window animates between heights when the user switches tabs. The current `PreferencesWindow` hard-codes `.frame(width: 520, height: 420)`, which is the wrong shape for narrow panes (e.g. Trash, which has two toggles) and the wrong shape for tall panes (e.g. Notifications, which has six rows).

Remove the outer frame. Add `.fixedSize()` to each pane's outer container so SwiftUI knows the pane is sized by its content, not by available space — then the `TabView`'s window animates as the user clicks between tabs.

- [ ] **Step 1: Drop the outer frame from `PreferencesWindow`**

In `Apps/Lillist-macOS/Sources/Preferences/PreferencesWindow.swift`, delete the `.frame(width: 520, height: 420)` line (line 24). The struct becomes:

```swift
struct PreferencesWindow: View {
    var body: some View {
        TabView {
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationsPane()
                .tabItem { Label("Notifications", systemImage: "bell") }
            TrashPane()
                .tabItem { Label("Trash", systemImage: "trash") }
            QuickCapturePane()
                .tabItem { Label("Quick Capture", systemImage: "keyboard") }
            CrashReportingPane()
                .tabItem { Label("Crash Reporting", systemImage: "ant") }
            AdvancedPane()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
    }
}
```

- [ ] **Step 2: Add `.fixedSize()` to each pane's root view**

For each of the six panes, append `.fixedSize()` to the outer `Form { … }` (or top-level container). Example for `QuickCapturePane.swift`:

```swift
        Form {
            // … existing body …
        }
        .formStyle(.grouped)
        .padding()
        .fixedSize() // Plan 15 Task 26: pane self-sizes; Preferences window animates
```

Apply the same edit to each of:
- `GeneralPane.swift`
- `NotificationsPane.swift`
- `TrashPane.swift`
- `CrashReportingPane.swift`
- `AdvancedPane.swift`

If a pane has very long content that should scroll instead of size unbounded, wrap the content in `ScrollView { … }.frame(maxHeight: 600)` and append `.fixedSize(horizontal: true, vertical: false)`.

Also remove the `ProgressView("Loading…").frame(width: 520, height: 420)` fallback in `LillistApp.swift` (lines 30-32) — let the placeholder size itself instead:

```swift
            } else {
                ProgressView("Loading…")
                    .padding()
            }
```

- [ ] **Step 3: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Manual smoke test: launch the app, open ⌘,, click between tabs — the window should animate to each pane's intrinsic size.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Preferences/PreferencesWindow.swift \
        Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift \
        Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift \
        Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift \
        Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift \
        Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift \
        Apps/Lillist-macOS/Sources/Preferences/AdvancedPane.swift \
        Apps/Lillist-macOS/Sources/LillistApp.swift
git commit -m "refactor(macOS): Preferences panes self-size; window animates between tabs"
```

---

## Task 27: Fix misleading `NSAppleEventsUsageDescription`

**Files:**
- Modify: `Apps/Lillist-macOS/Info.plist`

`Info.plist` currently declares `NSAppleEventsUsageDescription = "Lillist uses Apple Events for global keyboard shortcuts."` This is false: the global hotkey implementation in `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift` uses `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` (Quartz Event Services under the hood), *not* Apple Events. The misleading key triggers a permission prompt the app doesn't need.

We verify by grepping for any `NSAppleScript` or `NSAppleEventDescriptor` usage — if there are none, the key can be removed outright. If something does use Apple Events (now or anticipated), rewrite the justification to match.

- [ ] **Step 1: Confirm no Apple Events usage**

```bash
grep -rn "NSAppleScript\|NSAppleEventDescriptor\|kAEPerformService\|AEDesc" \
    Apps/Lillist-macOS/ Packages/LillistCore/ Packages/LillistUI/ 2>/dev/null | head -10
```

Expected: zero results. (If anything appears — e.g. someone adds AppleScript scripting later — keep the key but with a correct description.)

- [ ] **Step 2: Remove the key**

In `Apps/Lillist-macOS/Info.plist`, delete:

```xml
    <key>NSAppleEventsUsageDescription</key>
    <string>Lillist uses Apple Events for global keyboard shortcuts.</string>
```

- [ ] **Step 3: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Launch the app — there should be no spurious Apple Events permission prompt on first run.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Info.plist
git commit -m "fix(macOS): remove misleading NSAppleEventsUsageDescription (app uses NSEvent, not AppleEvents)"
```

---

## Task 28: Reclaim `⌘F` from `replacing: .textEditing`

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift` (the `CommandGroup(replacing: .textEditing)` block — line numbers shifted after Plan 13)

> **Plan 13 fallout (2026-05-16):** Plan 13 Task 5 added an `@FocusedValue(\.listColumn)` declaration on `LillistCommands`, rebound `⌘D` → `⌘⏎` and `⌘⇧N` → `⌘⇧⏎`, and appended `.disabled(listColumn == nil)` to the Space, Mark Closed, Mark Blocked, Indent, and Outdent buttons. Line numbers in the `CommandMenu("Task")` block shifted by ~6 lines. Use `rg -n 'CommandGroup\(replacing: \.textEditing\)'` to locate the Find block before editing.

`CommandGroup(replacing: .textEditing)` overwrites the entire standard Find submenu, killing Find Next (`⌘G`), Find Previous (`⇧⌘G`), and Use Selection for Find — basic Mac text-editing affordances. The Find command should live in its own menu (`CommandMenu("Find")` or `CommandGroup(after: .textEditing)`) and `⌘F` should be reserved for an in-view `.searchable`-driven find when the focus is in the task list.

For Plan 15 we move the Find commands to their own `CommandGroup(after: .textEditing)` so the standard Find submenu survives. Wiring `.searchable` into the task list is out of scope here (it deserves its own plan); the `.lillistFindInView` notification still posts so the future view-side handler can implement it.

- [ ] **Step 1: Edit the command group**

In `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`, replace the existing `CommandGroup(replacing: .textEditing) { … }` block (lines 46-54) with:

```swift
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find in View…") {
                NotificationCenter.default.post(name: .lillistFindInView, object: nil)
            }.keyboardShortcut("f", modifiers: [.command])
            Button("Find Everywhere…") {
                NotificationCenter.default.post(name: .lillistFindEverywhere, object: nil)
            }.keyboardShortcut("f", modifiers: [.command, .shift])
        }
```

(`after:` appends to the standard Find submenu instead of replacing it. The `Divider()` keeps the new entries visually separate from `Find…` / `Find Next` / `Find Previous`.)

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Manual smoke test: launch the app and open the Edit menu — Find should show `Find…`, `Find Next`, `Find Previous`, `Use Selection for Find`, then a divider, then `Find in View…` and `Find Everywhere…`.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift
git commit -m "fix(macOS): preserve standard Find submenu; append Lillist find commands"
```

---

## Task 29: `⌃⌘S` Show Sidebar menu command

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`
- Modify: `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift`

`⌃⌘S` is the macOS standard for "Toggle Sidebar" (Mail, Notes, Reminders, Music). The toolbar button from Task 1 already handles the click affordance; this task wires the menu shortcut so it works without aiming at the toolbar.

- [ ] **Step 1: Add the menu command**

In `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`, add inside `var body: some Commands { … }`:

```swift
        CommandGroup(after: .sidebar) {
            Button("Show Sidebar") {
                NotificationCenter.default.post(name: .lillistToggleSidebar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }
```

In the same file's `extension Notification.Name`, add:

```swift
    static let lillistToggleSidebar = Notification.Name("lillist.toggleSidebar")
```

- [ ] **Step 2: Wire the notification in `RootSplitView`**

In `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift`, append to the chain of `.onReceive` modifiers:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .lillistToggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                let current = Self.parseVisibility(columnVisibilityRaw)
                columnVisibilityRaw = Self.encodeVisibility(
                    current == .all ? .doubleColumn : .all
                )
            }
        }
```

(The `columnVisibilityRaw` `@SceneStorage` and the `parseVisibility` / `encodeVisibility` helpers were added in Task 2.)

- [ ] **Step 3: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Manual smoke test: View menu should have `Show Sidebar` with `⌃⌘S`; pressing it toggles the sidebar.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift \
        Apps/Lillist-macOS/Sources/Views/RootSplitView.swift
git commit -m "feat(macOS): ⌃⌘S toggles sidebar visibility (Mac convention)"
```

---

## Task 30: Final sweep + engineering note

**Files:**
- Modify: `docs/engineering-notes.md`

- [ ] **Step 1: Full test sweeps**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
swift test --package-path Packages/LillistUI 2>&1 | tail -3
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
xcodebuild build -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

All four must be green. iOS-build inclusion catches accidental cross-platform breakage in `LillistUI` (the `QuickCaptureView` material change in Task 17 is the main risk).

- [ ] **Step 2: Append the engineering note**

Add at the top of `docs/engineering-notes.md` (above the most recent existing entry):

```markdown
## 2026-05-16 — Plan 15 macOS chrome: toolbar over header views, MenuBarExtra over NSStatusBar, `.nonactivatingPanel` quirks, dock + Spotlight + Services integration

**Context.** Plan 15 swapped the macOS app's ad-hoc column headers for a real `.toolbar`, migrated the status item to a SwiftUI `MenuBarExtra(.window)` scene, polished the Quick Capture panel, and added system-citizen integrations (dock badge / menu, About / Help command groups, Services provider, Spotlight indexing, NSUserActivity, animated Preferences). Several non-obvious gotchas surfaced.

**Rules.**

- **`NavigationSplitView`'s `columnVisibility:` binding is the only stable handle on sidebar state.** Toolbar buttons need to flip it imperatively (and persist the result via `@SceneStorage`) — there's no "sidebar is visible" environment value to query. The Tahoe-native auto-toggle still works without the binding, but a custom toolbar button that flips it gives you a stable target for the `⌃⌘S` menu command and persistence across launches.
- **`MenuBarExtra(.window)` reanchors automatically; `.menu` style does not.** The pre-`MenuBarExtra` `NSPopover.show(relativeTo:of:preferredEdge:)` call needed manual edge selection (often wrong — anchoring `.minY` opens *into* the menu bar). `MenuBarExtra(.window)` reads the screen geometry itself and picks above-or-below correctly.
- **`@SceneStorage` is the right home for window-level UI state.** `UserDefaults` works but is the wrong shape for state that varies per window/scene. `@SceneStorage` survives window restoration, scopes per scene, and doesn't pollute `UserDefaults`. Use `UserDefaults` for state that *must* persist across launches in a per-machine way (per-source task selection, per-source sort).
- **`.nonactivatingPanel` is undone by `NSApp.activate(ignoringOtherApps:)`.** The whole point of the non-activating panel style is that the panel can be key without bringing the app forward — calling `activate(ignoringOtherApps:)` immediately after `makeKeyAndOrderFront(nil)` steals focus from the user's previous app and breaks ⌘Tab muscle memory.
- **`NSPanel.center()` always picks the primary screen.** Multi-monitor users expect floating panels to appear under the cursor. `NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? .main` is the conventional pattern; place the panel ~1/3 from the top of that screen's `visibleFrame`.
- **`.task { ... }` on a `MenuBarExtra` popover view fires once and never again.** The popover content view stays alive across open/close cycles, so `.task` doesn't re-trigger. Use `.onAppear { Task { await load() } }` (which fires every appearance) plus a `NotificationCenter` subscription on `NSManagedObjectContextDidSave` so external changes refresh the popover too.
- **`CommandGroup(replacing: .textEditing)` destroys the standard Find submenu.** Always use `CommandGroup(after: .textEditing)` if you want to *add* to a built-in menu, not replace it. The same caveat applies to `.appInfo` (replacing it is fine for About — you're meant to override that), `.help` (replacing is fine; Help has no built-in items worth keeping), and `.sidebar` (use `after:` so the OS-provided "Show Sidebar" item survives).
- **`CSSearchableIndex` is upsert-shaped.** `indexSearchableItems(_:)` overwrites existing items by `uniqueIdentifier`, so re-pushing the same item on every save is correct (just inefficient). The optimization path is `NSManagedObjectContextObjectsDidChange` for per-save deltas; skip until measurement says it matters.
- **`NSAppleEventsUsageDescription` triggers a permission prompt every launch.** Don't declare it unless the app actually uses Apple Events (`NSAppleScript`, `NSAppleEventDescriptor`, `AESendMessage`, …). `NSEvent.addGlobalMonitorForEvents` uses Quartz Event Services, which doesn't need the declaration.

**Evidence.** Plan 15 commits on `plan-15-macos-chrome` (or merged into `main` as such): `feat(macOS): wire .toolbar on RootSplitView`, `feat(macOS): persist sidebar visibility`, `refactor(macOS): convert TaskDetailView to grouped Form sections`, `refactor(macOS): migrate status bar to MenuBarExtra(.window) scene`, `feat(macOS): Quick Capture panel opens on cursor's screen`, `feat(macOS): dock badge`, `feat(macOS): Spotlight indexing`, `feat(macOS): Services menu item`, `fix(macOS): preserve standard Find submenu`.
```

- [ ] **Step 3: Commit and tag**

```bash
git add docs/engineering-notes.md
git commit -m "docs: record Plan 15 macOS-chrome lessons (toolbar, MenuBarExtra, panel semantics)"
git tag plan-15-macos-chrome
```

- [ ] **Step 4: Branch summary**

```bash
git log --oneline main..plan-15-macos-chrome
```

- [ ] **Step 5: Push**

```bash
git -c url."https://github.com/".insteadOf="git@github.com:" push origin plan-15-macos-chrome
git -c url."https://github.com/".insteadOf="git@github.com:" push origin plan-15-macos-chrome --tags
```

Open a PR via `gh`:

```bash
gh pr create \
    --title "Plan 15: macOS chrome and system integration" \
    --body "Implements Plan 15 from \`docs/superpowers/plans/2026-05-16-plan-15-macos-chrome.md\`. See plan for task-by-task scope." \
    --base main
```

---

## Plan 15 Scope

**In:**

- Toolbar on `RootSplitView` (sidebar toggle, principal title, primary actions for + New Task / Sort, sync status).
- `@SceneStorage` for column visibility; `UIStatePersistence` extension for per-source task selection.
- Bounded detail-column width.
- `TaskDetailView` as a grouped `Form` with named sections.
- Bordered `NotesEditorView` `TextEditor`.
- `StatusPalette`-colored status pill in `DetailHeaderView` / `TaskDetailView.TitleRow`.
- Segmented Filter picker in `JournalStreamView`.
- `⌘⏎` submit in `JournalComposerView`.
- `MenuBarExtra(.window)` scene replacing `StatusBarController`, with `isInserted:` toggle binding driven by `PreferencesStore.statusBarItemVisible`.
- `TodayPopoverView` refresh on appearance + `NSManagedObjectContextDidSave`.
- Deletion of the empty `StatusBarIcon.imageset`.
- Quick Capture panel: cursor-screen placement, resign-key dismissal, `.hasShadow`, removal of `NSApp.activate(ignoringOtherApps:)`.
- SF-Symbol-glyph hotkey display in `HotkeyRecorder`; bare-`⌘` combo rejection.
- `QuickCaptureView` material audit for Tahoe.
- Dock badge (Today count) + dock menu (Quick Capture, Today, pinned filters).
- Custom About box with byline.
- Help menu link (placeholder URL, confirmed before merge).
- Services provider exposing "Add to Lillist as task".
- Spotlight indexing via `IndexingService` + `CSSearchableIndex`.
- `NSUserActivity` for Handoff/Continuity on `TaskDetailView`.
- Preferences window: drop fixed frame, per-pane intrinsic sizing with `.fixedSize()`.
- Removal of misleading `NSAppleEventsUsageDescription` from `Info.plist`.
- Reclaiming `⌘F` from `replacing: .textEditing`; `⌃⌘S` Show Sidebar menu command.

**Out:**

- Wiring `.searchable` into the task list (deserves its own plan; Plan 15 just preserves the menu structure so a future plan has a clean target).
- Real Help documentation site (Plan 15 ships a placeholder Help URL pointing at the GitHub repo).
- iOS reciprocal `NSUserActivity` continuation handler — that lives in the iOS app target, out of scope here.
- Design tokens themselves (Plan 14's job) — Plan 15 consumes `StatusPalette` / `LillistSpacing` if available, stubs them inline with `TODO(Plan 14)` markers if not.
- App Intents / Shortcuts integration (`AppShortcutsProvider` etc.) — `AppIntents.framework` is already linked but no intents are defined; that's a separate plan.

---

## Self-Review Checklist

- [ ] Every task ends with a `git add … && git commit -m "<conventional prefix>: <message>"`.
- [ ] Every task that changes visible UI updates the snapshot baselines (Task 4, Task 17) — re-recorded PNGs are committed alongside the source change.
- [ ] No task introduces a `Task { ... }` inside an actor-isolated context without auditing whether the `await` is redundant (Plan 2 lesson).
- [ ] No task adds a parallel mapper for a public DTO without considering the other call sites (Plan 12 lesson). The IndexingService mapper produces `CSSearchableItem`, a system type — no Lillist DTO duplication.
- [ ] No task introduces a hand-rolled `keyCode ↔ keyName` table — both `HotkeyRecorder` and `GlobalHotkeyMonitor` delegate to `HotkeyKeyTable` (Plan 12 lesson).
- [ ] No task references `NSAppleScript` / `NSAppleEventDescriptor` (Task 27 verified the codebase is clean).
- [ ] `xcodebuild build` and `xcodebuild test` both green on `Lillist-macOS`.
- [ ] `xcodebuild build` green on `Lillist-iOS` (catches accidental cross-platform breakage from the `LillistUI` material change in Task 17).
- [ ] `swift test --package-path Packages/LillistCore` and `swift test --package-path Packages/LillistUI` both green.
- [ ] `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` still enforced (`Apps/project.yml:15`) — every task should produce zero new warnings, not just compile.
- [ ] Engineering note appended at the top of `docs/engineering-notes.md`.
- [ ] Tag `plan-15-macos-chrome` exists on the merge commit.
- [ ] PR opened, URL captured.
- [ ] No use of force-push; no `--no-verify`; no `git rebase -i` / `git add -i`.
- [ ] Push went over HTTPS per `~/.claude/CLAUDE.md` (gitconfig `insteadOf` override).
- [ ] Plans 13 / 14 dependency stubs (`StatusPalette`) carry a `TODO(Plan 14)` marker so the design-token sweep can find and replace them later.
