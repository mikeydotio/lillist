# Lillist Plan 19 — macOS Polish Sweep

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every LOW / NIT-severity macOS finding from the 2026-05-16 design review that is **not** already handled by the structural Plans 13–17 — small UX corrections, missing system integrations, and a single shared-constant extraction. Each task is sized to land in one sitting; none of them require new architecture. The aggregate impact is a markedly more polished macOS app: a title bar that reflects the current source, a sensible first-launch window size, a working "New Window" command, a live crash-report preview, Preferences panes that react to live CloudKit-pushed setting changes, right-click affordances on sidebar rows, a list-column header that names the actual selected source, explicit arrow-key navigation, friendlier onboarding copy, a collapsed defaults-install path, a release-appropriate bundle version, a recovery path for `⌘W`-closing-the-only-window, and a single shared constant for the crash-report email recipient.

**Architecture:** All work is local SwiftUI/AppKit surgery inside `Apps/Lillist-macOS/Sources/`, plus one new shared-constant file in `LillistCore`. No new directory trees, no new entities, no migrations. The single new file (`Packages/LillistCore/Sources/LillistCore/Support/LillistCoreContact.swift`) introduces a `LillistCoreContact` namespace with one `static let crashReportRecipient: String` so the three sites that currently hardcode the same email address (`MailtoTransport`, `CLIMailtoTransport`, `CrashReportingPane`, `CrashReportSheet`) consume one source of truth. One new view-model affordance (`CrashReportViewModel.samplePreview(environment:)` — if Plan 14 lands first; otherwise inline-and-TODO) makes the Preferences disclosure preview live. One new Preferences-side observation pattern (subscribing the form bindings to a `PreferencesStore.Prefs` `AsyncStream` change feed) replaces the load-once-then-stale `.task` pattern in every Preferences pane; the change stream itself is a small additive change to `PreferencesStore`. The remaining items are one-to-three-line surgical edits.

**Tech Stack:** Swift 6, SwiftUI for the macOS scene/window APIs, AppKit for `NSApp.windows` reopen handling and the dock/menubar bits, Swift Testing (LillistCore) + XCTest with `swift-snapshot-testing` (LillistUI tour + macOS app target snapshot/UI tests).

**Depends on:**

- **Plan 13** (a11y/correctness) — Task 5 of Plan 13 gates `Space` / `⌘D` / `⌘.` / `Tab` shortcuts via `@FocusedValue`; do not re-touch those shortcuts here. Plan 13 must merge before this plan starts so the gating exists when Task 3 (this plan) verifies that `⌘N`+`⌥⌘N` round-trip cleanly under the new focused-value contract.
- **Plan 14** (design system) — Task 10 of Plan 14 promotes `CrashReportSample` into `LillistUI/Components/`. This plan's Task 4 (live preview) consumes that shared helper if available; if Plan 14 has not merged, Task 4 falls back to a local `samplePreview` computed property plus a TODO referencing Plan 14 Task 10.
- **Plan 15** (macOS chrome) — **merged on `main`** as of 2026-05-16. Plan 15 Task 1 wires the real `.toolbar` on `RootSplitView` and renders the source title in the principal slot via the local `principalTitle(for:)` helper (no `.navigationTitle(...)` modifier). This plan's Task 1 (WindowGroup title binding) reinforces the same behavior at the scene level so the window-chrome title (not just the toolbar) is correct. Plan 15 Task 9 introduced `MenuBarExtra` as a SwiftUI scene (`Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift`) whose popover content is `MenuBarPopover` (`fileprivate` in the same file) — this plan's Task 12 (recovery from `⌘W` closing the only window) adds a "Show Main Window" button to that popover. Plan 15 Tasks 19–25 added the Dock menu, About box, Help menu, Services provider, and Spotlight indexing — none of those are duplicated here.
- **Plan 16** (iOS polish) — Independent; only the version-bump task (Task 11 here) touches iOS, and only to keep `CFBundleShortVersionString` in lock-step with macOS.
- **Plan 17** (i18n/a11y environments) — **merged on `main`** as of 2026-05-16. The recurrence editor's Cancel button already carries `.keyboardShortcut(.cancelAction)`; do not duplicate. Both app targets have a `Localizable.xcstrings` and the `String(localized:)` extraction pattern is already established — Task 1 here (WindowGroup title) routes its `sourceTitle` accordingly.

**Already covered by earlier plans — DO NOT REPLAN here:**

- HotkeyRecorder conflict detection → **Plan 15 Task 18**
- TodayPopoverView stale-on-reopen → **Plan 15 Task 11**
- RecurrenceEditorView Cancel `.keyboardShortcut(.cancelAction)` → **Plan 17 Task 25**
- macOS keyboard traps (Space/`⌘D`/`⌘.`/Tab focus gating) → **Plan 13 Task 5**
- `⌘D` rebind (system Duplicate collision) → **Plan 13 Task 5/7**
- `⌘.` (system Cancel collision) → covered in **Plan 13 Task 5** focus gating
- Window `.toolbar` and "Detail as Form" → **Plan 15 Tasks 1, 4**
- `MenuBarExtra` migration → **Plan 15 Task 9**
- Dock badge/menu, About/Help/Services/Spotlight → **Plan 15 Tasks 19–25**
- Recurrence editor month-day grid, segmented detail picker, FAB lift → **Plan 16 Tasks 1, 5, 20**
- All-text-localization scaffolding, RTL, reduce-motion / reduce-transparency / increase-contrast environments → **Plan 17 Tasks 1–17**

If a reviewer says "but that's already on the list above" while reading this plan, **stop and re-check the corresponding plan first** — duplicating it here causes merge conflicts and a deleted-then-recreated commit history.

---

## File Structure

```
Lillist/
├── Packages/
│   └── LillistCore/
│       └── Sources/
│           └── LillistCore/
│               ├── Stores/
│               │   └── PreferencesStore.swift            (modify — add prefsStream)
│               └── Support/                              (NEW directory)
│                   └── LillistCoreContact.swift          (NEW — shared recipient)
├── Apps/
│   ├── Lillist-macOS/
│   │   ├── Sources/
│   │   │   ├── LillistApp.swift                          (modify — title binding, defaultSize,
│   │   │   │                                                       windowResizability,
│   │   │   │                                                       drop dual install path)
│   │   │   ├── AppDelegate.swift                         (modify — applicationShouldHandleReopen)
│   │   │   ├── Commands/
│   │   │   │   └── LillistCommands.swift                 (modify — add New Window)
│   │   │   ├── Onboarding/
│   │   │   │   └── OnboardingSheet.swift                 (modify — copy rewrite,
│   │   │   │                                                       drop installer call)
│   │   │   ├── Preferences/
│   │   │   │   ├── CrashReportingPane.swift              (modify — live preview)
│   │   │   │   ├── GeneralPane.swift                     (modify — subscribe prefsStream)
│   │   │   │   ├── QuickCapturePane.swift                (modify — subscribe prefsStream)
│   │   │   │   ├── NotificationsPane.swift               (modify — subscribe prefsStream)
│   │   │   │   ├── TrashPane.swift                       (modify — subscribe prefsStream)
│   │   │   │   └── AdvancedPane.swift                    (modify — subscribe prefsStream)
│   │   │   ├── MailtoTransport.swift                     (modify — consume shared constant)
│   │   │   ├── Views/
│   │   │   │   ├── Sidebar/
│   │   │   │   │   └── SidebarView.swift                 (modify — contextMenu)
│   │   │   │   └── TaskList/
│   │   │   │       └── TaskListView.swift                (modify — real sourceTitle,
│   │   │   │                                                       arrow-key onKeyPress)
│   │   │   └── MenuBar/
│   │   │       └── MenuBarExtraScene.swift              (modify — add "Show Main Window" to MenuBarPopover; Plan 15 Task 9 shipped this file)
│   │   ├── Info.plist                                    (modify — version bump)
│   │   └── Tests/
│   │       ├── KeyboardShortcutTests.swift               (modify — arrow-key UI test)
│   │       ├── SidebarContextMenuTests.swift             (NEW)
│   │       └── TaskListSourceTitleTests.swift            (NEW)
│   └── Lillist-iOS/
│       ├── Sources/
│       │   └── App/
│       │       └── CrashReporterHost.swift               (modify — consume shared constant)
│       └── Info.plist                                    (modify — version bump)
├── Packages/
│   └── LillistCore/
│       └── Sources/
│           └── lillist-cli/
│               └── Support/
│                   └── CLIMailtoTransport.swift          (modify — consume shared constant)
├── Packages/
│   └── LillistUI/
│       └── Sources/
│           └── LillistUI/
│               └── CrashReporting/
│                   └── CrashReportSheet.swift            (modify — consume shared constant)
└── docs/
    └── engineering-notes.md                              (append entry)
```

---

## Notes for the Implementer

**Read the "already covered" list at the top.** Each macOS LOW/NIT item that is *not* on that list became a task in this plan. If something feels familiar from another plan, it's probably already on the "already covered" list — re-check before writing code.

**SwiftUI `List(selection:)` arrow-key behavior.** Task 8 (explicit arrow-key bindings) is **contingent on empirical verification**. SwiftUI's `List(selection:)` on macOS 15+ *should* support up/down arrow navigation out of the box when the list has focus; the focused-column wiring from `RootSplitView` (`Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:10`, where `@FocusState private var focusedColumn: ListColumn?` lives — note: Plan 13 hoisted the previously-nested `Column` enum to the standalone `ListColumn` in `FocusedListColumn.swift`) should give the list keyboard focus. **Before writing code for Task 8, build the app and confirm by hand that arrow keys advance selection within the task list.** If they do, Task 8 is reduced to "write a UI test asserting the behavior" and the `.onKeyPress` path is skipped. If they do not, the explicit `.onKeyPress` fallback lands. Either outcome is acceptable — the goal is "arrow keys reliably navigate the list", not "we used `.onKeyPress`."

**`PreferencesStore` does not currently expose a change stream.** Task 5 introduces one. Pattern: an `AsyncStream<Prefs>` produced by `prefsStream`, fed by a per-call continuation table keyed by `UUID`, with `onTermination` unregistering. Same shape as `AccountStateMonitor.stateStream` (`Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:46-55`), `CloudKitEventBridge.eventStream`, and `SyncStatusMonitor.statusStream` — copy that pattern, do not reinvent it. The store posts a snapshot every time `update(_:)` succeeds; CloudKit pushes do not currently flow through `PreferencesStore.update`, but Core Data's `NSPersistentCloudKitContainer` posts `NSPersistentStoreRemoteChange` notifications when a remote write lands. Bridge those notifications to a refresh in the same step that adds `prefsStream` so external pushes also propagate to the Preferences UI.

**Strict-concurrency / warnings-as-errors quality bar.** Per `CLAUDE.md`: zero warnings. Every task ends with the build commands inline. Run them. If a warning appears, fix it inside the same task — do not punt to "next plan."

**Build-plugin caching gotcha.** No model edits in this plan, so no `touch` needed. If exploration accidentally bumps the model, run:
```bash
touch Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/ \
      Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/
```

**xcodegen step.** Two new files land here: `Apps/Lillist-macOS/Tests/SidebarContextMenuTests.swift` (Task 6) and `Apps/Lillist-macOS/Tests/TaskListSourceTitleTests.swift` (Task 7). The macOS app `project.yml` discovers sources by directory glob, so neither file *should* need a project regeneration — but verify with `git status Apps/Lillist-macOS.xcodeproj/project.pbxproj` after each `xcodebuild test` run. If the `.pbxproj` is changed by the test command, stage it. The single new file in `LillistCore` (Task 13) lands under `Packages/LillistCore/Sources/LillistCore/Support/` — SwiftPM auto-discovers `Sources/<target>/**` so no `Package.swift` edit is needed.

**Verification commands.** Each task ends with `swift test --package-path Packages/LillistCore --filter '<pattern>'` for LillistCore changes and `xcodebuild test … -only-testing:Lillist-macOSTests/<TestName>` for app-target tests. The verification commands always use:
```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```
for builds and the `xcodebuild test` analogue for tests. iOS only gets touched by Task 11 (version bump) and Task 13 (shared constant); both end with an `xcodebuild build` for the iOS scheme as a smoke check.

**Commit cadence.** One commit per task using conventional-commit prefixes: `fix:`, `feat:`, `refactor:`, `chore:`, `docs:`. The final task tags `plan-19-macos-polish-sweep`.

---

## Task 1: Bind WindowGroup title to the current sidebar source

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/LillistApp.swift:12` (WindowGroup title)
- Coordinate-with-Plan-15: `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift` (Plan 15 Task 1 may have already added a `.navigationTitle(...)` on the content column that this task simply verifies inherits to the window chrome)

The window-chrome title bar currently reads "Lillist" forever, regardless of what the user selected in the sidebar. macOS apps of this caliber set the title to the current source — Apple's Reminders shows "Today" / "Scheduled" / list name, Things shows the area or project. Use SwiftUI's `.navigationTitle(...)` inside the content column: the SwiftUI runtime promotes the most-specific `navigationTitle` to the `WindowGroup`'s title bar automatically.

- [ ] **Step 1: Read the current state**

```bash
grep -n "WindowGroup\|navigationTitle" Apps/Lillist-macOS/Sources/LillistApp.swift Apps/Lillist-macOS/Sources/Views/RootSplitView.swift Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift Apps/Lillist-macOS/Sources/Views/TaskList/TaskListHeaderView.swift
```

If Plan 15 Task 1 has already added `.navigationTitle(...)` on `TaskListView` or `TaskListHeaderView`, the WindowGroup title binding is already in place — jump to Step 3 (verification only). Otherwise continue with Step 2.

- [ ] **Step 2: Add `.navigationTitle(...)` on the list column**

Edit `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift`. After the existing `.task(id: anchorIdentity) { ... }` modifier (around line 122), add:

```swift
        .navigationTitle(sourceTitle)
```

`sourceTitle` is the computed property defined at line 37-45 — note that Task 7 (this plan) rewrites it to return the actual filter/tag/task name rather than the generic kind string. Once Task 7 lands, the WindowGroup title automatically becomes "Today", "#groceries", "Pinned: Buy milk", etc.

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`, zero warnings.

Manual verification (do this before committing): launch the app, click a tag in the sidebar, confirm the title bar updates from "Lillist" to the tag name.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift
git commit -m "feat(macOS): window title reflects sidebar source via .navigationTitle"
```

---

## Task 2: Add `.defaultSize` and `.windowResizability` to the main WindowGroup

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/LillistApp.swift:12-16`

The current scene declaration only specifies `.frame(minWidth: 900, minHeight: 560)` on the content view; SwiftUI lacks a default size hint, so first launch produces the system's default window size (variable, often too small for the three-column layout). `.defaultSize(width:height:)` provides a first-launch hint; `.windowResizability(.contentSize)` lets the content view's `minWidth`/`minHeight` floor flow up to the window manager.

- [ ] **Step 1: Read current state**

```bash
sed -n '11,17p' Apps/Lillist-macOS/Sources/LillistApp.swift
```

Confirm lines 12-14 are:
```swift
        WindowGroup("Lillist") {
            content
                .frame(minWidth: 900, minHeight: 560)
```

- [ ] **Step 2: Edit the scene**

Edit `Apps/Lillist-macOS/Sources/LillistApp.swift`. After the closing `}` of the `WindowGroup`'s content (line 16, right before `.commands { ... }` at line 17), add the two new modifiers:

```swift
        WindowGroup("Lillist") {
            content
                .frame(minWidth: 900, minHeight: 560)
                .task { await loadEnvironmentIfNeeded() }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentSize)
```

(`.task { await loadEnvironmentIfNeeded() }` stays on the content view; the two new modifiers go on the `WindowGroup` itself, after its closing `}`.)

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

Manual verification (before committing): delete any persisted window frame state via `defaults delete io.mikeydotio.Lillist NSWindow Frame WindowGroup-Lillist 2>/dev/null || true`, then launch the app — the window should open at roughly 1180×760, comfortably larger than the 900×560 minimum.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Sources/LillistApp.swift
git commit -m "feat(macOS): first-launch window size 1180×760, content-sized resizability"
```

---

## Task 3: Restore "New Window" entry to the File menu (or document why it was dropped)

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift` (the `CommandGroup(replacing: .newItem)` block — Plan 13 shifted line numbers)
- Possibly modify: `Apps/Lillist-macOS/Sources/AppDelegate.swift` if multi-window state needs custodianship

`LillistCommands` uses `CommandGroup(replacing: .newItem)` for "New Task" / "New Sibling Task", which removed SwiftUI's implicit `⌘N` "New Window" entry that comes free from `WindowGroup`. macOS users expect `⌥⌘N` (or `⌘N`) to open another instance of the main window. Restore that affordance — but first verify multi-window actually works for this app.

> **Plan 13 fallout (2026-05-16):** Plan 13 Task 5 rebound `⌘⇧N` ("New Sibling Task") to `⌘⇧⏎`, added `@FocusedValue(\.listColumn)` plumbing, and gated four other shortcuts on `listColumn != nil`. The `CommandGroup(replacing: .newItem)` block is still in roughly the same location but `⌥⌘N` is now genuinely free (previously it would have collided with `⌘⇧N`'s neighbour). Re-grep `'CommandGroup\(replacing: \.newItem\)'` before editing.

- [ ] **Step 1: Manually verify multi-window viability**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Launch the app. From the macOS terminal:
```bash
osascript -e 'tell application "Lillist" to make new window'
```

If a second window opens and renders the same sidebar+list+detail correctly with independent state, multi-window is viable — continue with Step 2. If the second window crashes, deadlocks, or renders garbage (most commonly because two `AppEnvironment.make()` calls race over the same Core Data store), **stop and document the finding**: replace this task's commit with a `docs:` commit that adds a `// Multi-window deferred — single AppEnvironment owns the Core Data stack; see Plan 19 Task 3.` comment above `CommandGroup(replacing: .newItem)` and skip the rest of this task. The "New Window" item lands once `AppEnvironment` is made multi-window-safe (out of scope here).

- [ ] **Step 2: Add the "New Window" command (only if Step 1 verified viability)**

Edit `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`. After the existing `CommandGroup(replacing: .newItem)` block (re-grep — Plan 13 shifted the block's bottom by ~1 line when it rebound `⌘⇧N` to `⌘⇧⏎`), add:

```swift
        CommandGroup(after: .newItem) {
            Button("New Window") {
                NotificationCenter.default.post(name: .lillistNewWindow, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }
```

Add the notification name to the extension at the bottom:
```swift
    static let lillistNewWindow = Notification.Name("lillist.newWindow")
```

Same pattern as Task 12 (this plan) — observe the notification in a small `ViewModifier` that calls `@Environment(\.openWindow)`. Task 12's `MainWindowReopener` infrastructure can be reused (give the WindowGroup an `id: "main"` and call `openWindow(id: "main")`).

- [ ] **Step 3: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification**

Launch the app, press `⌥⌘N`. A second window opens with independent sidebar selection. Confirm both windows can edit independently without crashing.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift \
        Apps/Lillist-macOS/Sources/AppDelegate.swift
git commit -m "feat(macOS): restore New Window command (⌥⌘N) lost when File>New was customized"
```

If Step 1 ruled out multi-window, the commit instead is:

```bash
git add Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift
git commit -m "docs(macOS): note multi-window deferred; New Window awaits AppEnvironment multi-instance support"
```

---

## Task 4: Live crash-report preview in `CrashReportingPane`

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift:25-30, 54-66`
- Conditionally modify: `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift` (add `samplePreview(environment:)` if Plan 14 Task 10 has not landed)

The "View what would be sent" disclosure currently shows a static template string assembled from the live build/OS/device values plus hardcoded placeholder text for breadcrumbs/logs. A user inspecting this expects to see a *real* preview — the actual redacted breadcrumbs and the actual last-30-seconds of system log that *would* be sent. This task replaces the static template with a real `CrashReporter.preview(...)` call.

- [ ] **Step 1: Check whether Plan 14 Task 10 has landed**

```bash
grep -n "samplePreview\|CrashReportSample" Packages/LillistUI/Sources/LillistUI/ -r
```

If `CrashReportSample` is a public LillistUI module, use it directly (continue with Step 2a). If not (most likely Plan 14 has not landed yet), add a `CrashReporter.preview(...)` shim and a TODO (Step 2b).

- [ ] **Step 2a (Plan 14 landed): Wire the shared sample**

Edit `Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift`. Add `@State private var livePreview: String?` near the existing `@State` block. Replace lines 24-30 (the `Section { DisclosureGroup ... }` body) with a version that renders `livePreview` if available (else a small `ProgressView`) and invokes `CrashReportSample.render(reporter:buildVersion:osVersion:deviceModel:recipient:)` via `.task(id: sampleVisible)` when the disclosure is expanded. Delete the now-unused `private var samplePreview: String { ... }` block (lines 54-66).

- [ ] **Step 2b (Plan 14 has not landed): TODO + keep static template**

Edit `Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift`. Above the `Text(samplePreview)` (line 26), add:

```swift
                        // TODO(Plan 19 / Plan 14 Task 10 follow-up): swap to a
                        // live CrashReporter.preview() once CrashReportSample
                        // lands in LillistUI.
```

Change the hardcoded `Sent to: mikeyward@gmail.com` on line 63 to consume the shared constant (Task 13):
```swift
        Sent to: \(LillistCoreContact.crashReportRecipient)
```

(Step 2b is the conservative path — it ships the user-visible recipient via the new constant even if Plan 14 has not yet landed.)

- [ ] **Step 3: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`, zero warnings. (If Plan 14 Task 10's `CrashReportSample` accidentally captures a non-Sendable closure, fix it here — do not punt.)

- [ ] **Step 4: Snapshot the preview**

If Plan 14 Task 10 has landed (Step 2a path), add a snapshot test in `Apps/Lillist-macOS/Tests/`. If not (Step 2b path), skip this step — the static template is already covered by existing tour snapshots.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift
git commit -m "feat(macOS): live crash-report preview in CrashReportingPane"
```

(If Step 2b path was taken, use `chore` not `feat`:)
```bash
git commit -m "chore(macOS): CrashReportingPane consumes shared crash-recipient constant; preview live-swap deferred"
```

---

## Task 5: Subscribe Preferences panes to a live `PreferencesStore` change stream

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift` (add `prefsStream`)
- Modify: `Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/AdvancedPane.swift`
- New: `Packages/LillistCore/Tests/LillistCoreTests/Stores/PreferencesStoreStreamTests.swift`

Each Preferences pane currently loads `prefs` exactly once via `.task { prefs = try? await environment.preferencesStore.read() }` and never re-syncs. If CloudKit pushes a settings change from another device — or another window of the same app calls `update(...)` — the open Settings tab is stale until the user closes and reopens. Add a real change stream, subscribe each pane to it, and let the bindings stay current.

- [ ] **Step 1: Write the failing test**

Create `Packages/LillistCore/Tests/LillistCoreTests/Stores/PreferencesStoreStreamTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("PreferencesStore.prefsStream")
struct PreferencesStoreStreamTests {
    @Test("Stream emits a snapshot after every update")
    func emitsSnapshotPerUpdate() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = PreferencesStore(persistence: persistence)
        _ = try await store.read() // prime the singleton row

        var received: [PreferencesStore.Prefs] = []
        let listener = Task<Void, Never> {
            var seen = 0
            for await snapshot in store.prefsStream {
                received.append(snapshot)
                seen += 1
                if seen >= 3 { return }
            }
        }
        try await store.update { $0.morningSummaryEnabled = false }
        try await store.update { $0.trashRetentionDays = 7 }
        try await store.update { $0.defaultTagTintHex = "#FF0000" }
        _ = await listener.value

        #expect(received.count == 3)
        #expect(received[0].morningSummaryEnabled == false)
        #expect(received[1].trashRetentionDays == 7)
        #expect(received[2].defaultTagTintHex == "#FF0000")
    }
}
```

Run:
```bash
swift test --package-path Packages/LillistCore --filter 'PreferencesStore.prefsStream' 2>&1 | tail -10
```

Expected: fails with "use of unresolved identifier 'prefsStream'".

- [ ] **Step 2: Add `prefsStream` to `PreferencesStore`**

Edit `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift`. Pattern is identical to `AccountStateMonitor.stateStream` (`Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:46-55`) — copy that shape. Three additions:

1. Private continuation registry guarded by `NSLock` (the store is `@unchecked Sendable`, not an actor):
```swift
    private var continuations: [UUID: AsyncStream<Prefs>.Continuation] = [:]
    private let continuationsLock = NSLock()
```

2. Public `prefsStream` + `register`/`unregister`/`broadcast` helpers (modeled on `AccountStateMonitor`):
```swift
    public var prefsStream: AsyncStream<Prefs> {
        AsyncStream { continuation in
            let id = UUID()
            self.register(id: id, continuation: continuation)
            continuation.onTermination = { [weak self] _ in self?.unregister(id: id) }
        }
    }
```

3. In `update(_:)` (line 56-90), capture the post-save snapshot and call `broadcast(updated)` *outside* the `context.perform` block.

4. In `init(persistence:)`, register a `NSPersistentStoreRemoteChange` observer on `persistence.container.persistentStoreCoordinator` that calls `read()` and `broadcast(...)` so external CloudKit pushes also flow through the stream.

- [ ] **Step 3: Run the test, verify pass**

```bash
swift test --package-path Packages/LillistCore --filter 'PreferencesStore.prefsStream' 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 4: Subscribe each Preferences pane**

For each of the six panes (`GeneralPane`, `QuickCapturePane`, `NotificationsPane`, `TrashPane`, `CrashReportingPane`, `AdvancedPane`), replace the existing one-shot `.task { prefs = try? await environment.preferencesStore.read() }` with a stream consumer that updates `prefs` on every snapshot. Pattern, applied to `GeneralPane.swift` (line 34):

```swift
        .task {
            // Initial load + live stream — the stream emits once on the
            // first subscription via the same broadcast path used for
            // local updates, so we cover both first-load and subsequent
            // remote pushes with one iterator.
            if prefs == nil {
                prefs = try? await environment.preferencesStore.read()
            }
            for await snapshot in environment.preferencesStore.prefsStream {
                // Only adopt remote/external changes — skip echoes from
                // our own writes (the form's onChange already mutates
                // `prefs` locally before kicking the store update, so
                // the round-tripped snapshot matches `prefs` already).
                if snapshot != prefs {
                    prefs = snapshot
                }
            }
        }
```

Apply the same shape to each of the other five panes. The "skip echoes" guard is crucial — without it, every local toggle would round-trip through the stream and stomp the form's mid-edit state.

- [ ] **Step 5: Build**

```bash
swift build --package-path Packages/LillistCore -Xswiftc -warnings-as-errors 2>&1 | tail -5
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Both clean.

- [ ] **Step 6: Run the broader Core suite to catch regressions**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -5
```

Expect green.

- [ ] **Step 7: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/PreferencesStoreStreamTests.swift \
        Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift \
        Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift \
        Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift \
        Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift \
        Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift \
        Apps/Lillist-macOS/Sources/Preferences/AdvancedPane.swift
git commit -m "feat(prefs): PreferencesStore exposes prefsStream; panes adopt live snapshots"
```

---

## Task 6: Add `.contextMenu` to sidebar rows (tags, pinned tasks, filters)

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift`
- New: `Apps/Lillist-macOS/Tests/SidebarContextMenuTests.swift`

Design Section 7 calls for "right-click for color/rename/delete" on sidebar rows. Today there is no right-click menu — tag rows, pinned-task rows, and filter rows are pure selection targets. Wire `.contextMenu { ... }` on each row variant: tags get rename / change color / delete; pinned tasks get rename / unpin; filters get rename / delete. The work is mostly a wiring exercise — the underlying mutations exist on the respective stores.

- [ ] **Step 1: Write the failing UI test**

Create `Apps/Lillist-macOS/Tests/SidebarContextMenuTests.swift`:

```swift
import Testing
import LillistCore
import Foundation

@Suite("Sidebar context-menu wiring contract")
struct SidebarContextMenuTests {
    @Test("Tag rename mutation flows through TagStore")
    func tagRenameThroughStore() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let tags = TagStore(persistence: persistence)
        let id = try await tags.create(name: "old")
        try await tags.rename(id: id, to: "new")
        let fetched = try await tags.fetch(id: id)
        #expect(fetched.name == "new")
    }

    @Test("Tag delete removes it from children(of: nil)")
    func tagDelete() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let tags = TagStore(persistence: persistence)
        let id = try await tags.create(name: "delete-me")
        try await tags.delete(id: id)
        let roots = try await tags.children(of: nil)
        #expect(!roots.map(\.id).contains(id))
    }

    @Test("Pinned task unpin mutation persists")
    func pinnedTaskUnpin() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let tasks = TaskStore(persistence: persistence)
        let id = try await tasks.create(title: "pinned")
        try await tasks.update(id: id) { $0.isPinned = true }
        try await tasks.update(id: id) { $0.isPinned = false }
        let pinned = try await tasks.pinned()
        #expect(!pinned.map(\.id).contains(id))
    }
}
```

(These are LillistCore-level "the mutations the context menu will invoke do what we expect" tests; the actual SwiftUI `.contextMenu` rendering is exercised by the existing tour snapshots once the menu is wired.)

Run:
```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/SidebarContextMenuTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expected: PASS (the underlying store methods already exist).

- [ ] **Step 2: Wire `.contextMenu` on each row variant**

Edit `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift`. Add `@State` ids for the three rename/color editor sheets at the top of the view (after line 14):
```swift
    @State private var renamingPinnedTask: UUID?
    @State private var renamingFilter: UUID?
    @State private var renamingTag: UUID?
    @State private var changingTagColor: UUID?
```

Wrap each `SidebarRowView` with `.contextMenu { ... }`:

- **Pinned tasks** (lines 19-22): `Rename…` (opens sheet) + `Unpin` (calls `env.taskStore.update(id:) { $0.isPinned = false }`).
- **Pinned filters & non-pinned filters** (lines 23-26 and 36-39): `Rename…` + `Delete` (destructive, calls `env.smartFilterStore.delete(id:)`).
- **Tag rows** in `TagDisclosureView` (lines 94-102): `Rename…` + `Change Color…` + Divider + `Delete` (destructive, calls `env.tagStore.delete(id:)`).

Add `.sheet(item:)` presentations at the bottom of the body for the three editors. Rename editor is a `TextField` + Save/Cancel pair (pattern after `RecurrenceEditorView`); color editor wraps `ColorPicker`. Each editor calls the matching store mutation on Save and `await refresh()` to repopulate the sidebar.

- [ ] **Step 3: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Clean.

- [ ] **Step 4: Delete the stale stub comment**

Remove any `/* menu in Task 19 */` / `// TODO menu` stubs around the sidebar rows — this task is the landing those stubs anticipated.

- [ ] **Step 5: Manual smoke test**

Launch the app, right-click a tag row → confirm Rename / Change Color / Delete appear and work. Same for pinned task and filter rows.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift \
        Apps/Lillist-macOS/Tests/SidebarContextMenuTests.swift
git commit -m "feat(macOS): sidebar rows gain rename/color/delete context menus"
```

---

## Task 7: `TaskListView.sourceTitle` shows the actual selected source name

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:37-45`
- New: `Apps/Lillist-macOS/Tests/TaskListSourceTitleTests.swift`

`sourceTitle` (lines 37-45) returns generic strings — "Pinned task", "Pinned filter", "Tag", "Filter", "Trash". The user just clicked a sidebar row labeled "Today" — the list column should say "Today", not "Filter". Resolve the selection's referent ID against the appropriate store and use its name.

- [ ] **Step 1: Write the failing test**

Create `Apps/Lillist-macOS/Tests/TaskListSourceTitleTests.swift`. Test the resolver as a `static func` on `TaskListView` so the SwiftUI rendering layer is not pulled in:

```swift
import Testing
import LillistCore
import Foundation

@Suite("TaskListView.sourceTitle resolves actual names")
struct TaskListSourceTitleTests {
    private func make() async throws -> (TaskStore, TagStore, SmartFilterStore) {
        let p = try await PersistenceController(configuration: .inMemory)
        return (TaskStore(persistence: p), TagStore(persistence: p), SmartFilterStore(persistence: p))
    }

    @Test("Pinned task selection resolves to the task's title")
    func pinnedTaskTitle() async throws {
        let (tasks, tags, filters) = try await make()
        let id = try await tasks.create(title: "Buy milk")
        try await tasks.update(id: id) { $0.isPinned = true }
        let title = await TaskListView.resolveSourceTitle(
            for: .pinnedTask(id), taskStore: tasks, tagStore: tags, smartFilterStore: filters)
        #expect(title == "Buy milk")
    }

    @Test("Tag selection resolves to the tag name")
    func tagName() async throws {
        let (tasks, tags, filters) = try await make()
        let id = try await tags.create(name: "groceries")
        let title = await TaskListView.resolveSourceTitle(
            for: .tag(id), taskStore: tasks, tagStore: tags, smartFilterStore: filters)
        #expect(title == "groceries")
    }

    @Test("Filter selection resolves to the filter name")
    func filterName() async throws {
        let (tasks, tags, filters) = try await make()
        let group = PredicateGroup(combinator: .and, leaves: [], groups: [])
        let id = try await filters.create(name: "Today", group: group)
        let title = await TaskListView.resolveSourceTitle(
            for: .filter(id), taskStore: tasks, tagStore: tags, smartFilterStore: filters)
        #expect(title == "Today")
    }

    @Test("Trash returns 'Trash'")
    func trash() async throws {
        let (tasks, tags, filters) = try await make()
        let title = await TaskListView.resolveSourceTitle(
            for: .trash, taskStore: tasks, tagStore: tags, smartFilterStore: filters)
        #expect(title == "Trash")
    }
}
```

Run:
```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/TaskListSourceTitleTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expected: fails with "use of unresolved identifier 'resolveSourceTitle'".

- [ ] **Step 2: Add the resolver and route the computed property through it**

Edit `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift`. Add the resolver as a `static func` on `TaskListView`:

```swift
    static func resolveSourceTitle(
        for selection: SidebarSelection,
        taskStore: TaskStore,
        tagStore: TagStore,
        smartFilterStore: SmartFilterStore
    ) async -> String {
        switch selection {
        case .pinnedTask(let id):
            return (try? await taskStore.fetch(id: id))?.title ?? "Pinned task"
        case .pinnedFilter(let id), .filter(let id):
            return (try? await smartFilterStore.list().first(where: { $0.id == id }))?.name ?? "Filter"
        case .tag(let id):
            return (try? await tagStore.fetch(id: id))?.name ?? "Tag"
        case .trash:
            return "Trash"
        }
    }
```

Replace the existing synchronous computed property `sourceTitle` (lines 37-45) with a `@State` cache plus an async refresh:

```swift
    @State private var resolvedSourceTitle: String = ""

    private var sourceTitle: String {
        resolvedSourceTitle.isEmpty ? defaultTitleFallback : resolvedSourceTitle
    }

    private var defaultTitleFallback: String {
        switch selection {
        case .pinnedTask:    return "Pinned task"
        case .pinnedFilter:  return "Pinned filter"
        case .tag:           return "Tag"
        case .filter:        return "Filter"
        case .trash:         return "Trash"
        }
    }
```

Inside `.task(id: anchorIdentity) { ... }` (after the existing call to `refresh()`), append:

```swift
            resolvedSourceTitle = await Self.resolveSourceTitle(
                for: selection,
                taskStore: env.taskStore,
                tagStore: env.tagStore,
                smartFilterStore: env.smartFilterStore
            )
```

- [ ] **Step 3: Verify the test passes**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/TaskListSourceTitleTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expected: 4 PASS.

- [ ] **Step 4: Build the macOS app for a warning check**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Clean.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift \
        Apps/Lillist-macOS/Tests/TaskListSourceTitleTests.swift
git commit -m "feat(macOS): list-column header shows actual source name (tag/filter/task title)"
```

---

## Task 8: Verify and (if needed) explicitly bind arrow-key navigation in the task list

**Files:**
- Possibly modify: `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift` (only if Step 1 finds default behavior insufficient)
- Modify: `Apps/Lillist-macOS/Tests/KeyboardShortcutTests.swift` (always — add the assertion)

SwiftUI's `List(selection:)` on macOS 15+ should support up/down arrow navigation out of the box. Verify empirically; if it works, this task is a pure test addition; if it doesn't, add `.onKeyPress(...)` as a fallback.

- [ ] **Step 1: Manually verify default behavior**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Launch the app, click into the task list to focus it, press the down arrow. Selection should advance to the next task. Press up — selection should go back. If both work, **proceed to Step 3** (test-only path). If they do not, **proceed to Step 2** (add `.onKeyPress`).

- [ ] **Step 2 (only if Step 1 failed): Add explicit `.onKeyPress` bindings**

Edit `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift`. On the `List(selection: $taskSelection)` (line 65 *and* line 88, both branches), add:

```swift
                    .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
                        advanceSelection(direction: press.key == .upArrow ? -1 : 1)
                        return .handled
                    }
```

Add helper methods on `TaskListView`:
- `private func advanceSelection(direction: Int)` — picks the ordered ID list (`flatResults` when `isFlat`, otherwise `flattenedTree(rootNodes)`), finds the current index, advances by `direction`, clamps at the ends.
- `private func flattenedTree(_ nodes: [TaskOutlineNode]) -> [TaskOutlineNode]` — `nodes.flatMap { [$0] + flattenedTree($0.children ?? []) }`.

Extract the index math (`advanceSelectionAlgo(current:ordered:direction:)`) as a `static` so the Step 3 unit test can drive it without the SwiftUI view.

- [ ] **Step 3: Add the UI test**

Edit `Apps/Lillist-macOS/Tests/KeyboardShortcutTests.swift`. Append a test asserting that down-arrow advances `taskSelection` when the list has focus. The test models the selection-cursor behavior directly against the helper (the SwiftUI view itself can't easily be driven from a test bundle without a host app):

```swift
import Testing
import LillistCore
import Foundation
@testable import struct Lillist_macOS.TaskListView

@Suite("Task-list arrow-key navigation")
struct ArrowKeyNavigationTests {
    @Test("Default behavior moves selection within flat results")
    func flatNavigation() async throws {
        // The test exercises the selection-advance algorithm directly.
        // If Step 1 confirmed SwiftUI's default works without our help,
        // this test still passes — the helper is just defensive plumbing.
        let ids = (0..<5).map { _ in UUID() }
        var selection: UUID? = ids[2]

        // Down arrow
        selection = TaskListView.advanceSelectionAlgo(
            current: selection,
            ordered: ids,
            direction: 1
        )
        #expect(selection == ids[3])

        // Up arrow
        selection = TaskListView.advanceSelectionAlgo(
            current: selection,
            ordered: ids,
            direction: -1
        )
        #expect(selection == ids[2])
    }
}
```

(Note: this requires the helper to be visible — either by being `internal` and using `@testable import`, or by being lifted to a top-level free function. Pick whichever fits cleaner; the goal is a deterministic test of the next-index math.)

If Step 1 confirmed default SwiftUI behavior works (no `.onKeyPress` added), still add the helper extracted as a pure function and assert it in this test — it's load-bearing documentation that "we know what we expect" even if SwiftUI is doing the work today.

- [ ] **Step 4: Run the test**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/ArrowKeyNavigationTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

PASS.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift \
        Apps/Lillist-macOS/Tests/KeyboardShortcutTests.swift
git commit -m "feat(macOS): explicit arrow-key navigation contract in task list"
```

(If Step 1 confirmed default behavior and Step 2 was skipped, the commit is `test:` not `feat:`:)

```bash
git commit -m "test(macOS): assert arrow-key navigation algorithm for task-list selection"
```

---

## Task 9: Rewrite the onboarding tagline

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift:58`

The current copy is "A pure-nesting task manager. Everything is a task." — opaque jargon. Replace with something a user will recognize.

- [ ] **Step 1: Apply the rewrite**

Edit `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift` line 58. Replace:

```swift
            Text("A pure-nesting task manager. Everything is a task.")
```

with:

```swift
            Text("Lists, tags, and reminders — synced to your iCloud.")
```

(Per the scope note, this is one reasonable rewrite. The user has full latitude to substitute a different tagline during execution — flag in the commit message that the wording is settled.)

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Clean.

- [ ] **Step 3: Update the snapshot if one exists**

```bash
grep -rn "OnboardingSheet\|pure-nesting" Packages/LillistUI/Tests/ Apps/Lillist-macOS/Tests/ 2>/dev/null
```

If a snapshot references the old string, regenerate it: run the relevant test in record mode (set `withSnapshotTesting(record: .all)` around the suite or use `record = true` on the assertion temporarily), commit the new image, then revert the record flag. The macOS tour snapshot is the likely site (`Packages/LillistUI/Tests/LillistUITests/Tour/MacOSScreenTourTests.swift`).

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift \
        Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__/
git commit -m "docs(macOS): rewrite onboarding tagline in plain English"
```

---

## Task 10: Collapse the default-tour smart-filter dual-install path

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift:152-153`

`DefaultsInstaller.installIfNeeded()` is invoked from two sites — `OnboardingSheet.complete()` at line 153 *and* `LillistApp.loadEnvironmentIfNeeded()` at line 73. If a user quits mid-onboarding, the next launch's `loadEnvironmentIfNeeded` path covers them, so the onboarding call is structurally redundant. Keep the `loadEnvironmentIfNeeded` path (the more guaranteed one — every launch runs it) and remove the onboarding-side call.

- [ ] **Step 1: Read the current state**

```bash
sed -n '148,162p' Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift
sed -n '60,78p' Apps/Lillist-macOS/Sources/LillistApp.swift
```

Confirm:
- `OnboardingSheet.complete()` at line 149-161 calls `try await installer.installIfNeeded()` at line 153
- `LillistApp.loadEnvironmentIfNeeded()` at line 73 calls `try? await env.defaultsInstaller.installIfNeeded()`

- [ ] **Step 2: Remove the onboarding-side call**

Edit `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift`. In `complete()` (lines 149-161), delete line 153:

```diff
     private func complete() async {
         isCompleting = true
         defer { isCompleting = false }
         do {
-            try await installer.installIfNeeded()
             try await onboardingState.markCompleted()
             onCompleted()
         } catch {
             // Surface to the user — non-fatal; they can retry.
             let alert = NSAlert(error: error)
             alert.runModal()
         }
     }
```

The `installer` parameter is still threaded through the view because the iOS app's `OnboardingScreen` also takes one; for type-consistency we keep it (the parameter becomes dead-weight on macOS but stays for shape parity). Alternatively, drop the parameter entirely and update the `OnboardingSheet(...)` construction in `LillistApp.swift:103` — but that's a wider edit. The conservative read: keep the parameter, drop the call.

If keeping the unused parameter trips `-warnings-as-errors` (unused property), suppress with `_ = installer` in `body` once, or delete the property and update the init.

- [ ] **Step 3: Update the comment in `LillistApp.loadEnvironmentIfNeeded`**

Edit `Apps/Lillist-macOS/Sources/LillistApp.swift` lines 69-73. The current comment claims the onboarding path "is also invoked" — update it now that this is the sole call site:

```swift
            // Sole install path: runs on every launch (idempotent by name).
            // OnboardingSheet used to call this too but that was redundant —
            // a user who quits mid-onboarding still gets defaults the next
            // launch through this code path.
            try? await env.defaultsInstaller.installIfNeeded()
```

- [ ] **Step 4: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Clean.

- [ ] **Step 5: Sanity-check the onboarding flow still installs defaults**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/NotificationPermissionFlowTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Any existing onboarding-flow tests should still pass — the `LillistApp` startup path runs the same installer.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift \
        Apps/Lillist-macOS/Sources/LillistApp.swift
git commit -m "refactor(macOS): single defaults-install path in LillistApp.loadEnvironmentIfNeeded"
```

---

## Task 11: Bump `CFBundleShortVersionString` / `CFBundleVersion` to release-appropriate values

**Files:**
- Modify: `Apps/Lillist-macOS/Info.plist:19-22`
- Modify: `Apps/Lillist-iOS/Info.plist:19-22`

Both targets currently advertise `0.1.0` / `1`. For a v1-ready build, set `1.0.0` and a meaningful build number. Use the date-derived `YYYYMMDD` form for builds — easy to read and monotonic — until a CI system takes over.

- [ ] **Step 1: Compute today's build number**

Use today's date (today is 2026-05-16 per the project's current-date context):
- `CFBundleShortVersionString` → `1.0.0`
- `CFBundleVersion` → `20260516`

- [ ] **Step 2: Edit `Apps/Lillist-macOS/Info.plist`**

Replace lines 19-22:
```xml
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>20260516</string>
```

- [ ] **Step 3: Edit `Apps/Lillist-iOS/Info.plist`**

Same change, lines 19-22:
```xml
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>20260516</string>
```

- [ ] **Step 4: Build both targets**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Both clean.

- [ ] **Step 5: Verify the embedded version (manual)**

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Apps/Lillist-macOS/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Apps/Lillist-macOS/Info.plist
```

Expected: `1.0.0` and `20260516`.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-macOS/Info.plist Apps/Lillist-iOS/Info.plist
git commit -m "chore(release): bump bundle version to 1.0.0 (build 20260516)"
```

---

## Task 12: Recovery path for `⌘W` closing the only window

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/AppDelegate.swift`
- Modify: `Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift` (Plan 15 Task 9 shipped this; add "Show Main Window" to its `MenuBarPopover`)

Today, after `⌘W` the user has no in-app way to reopen the main window — they must click the Dock icon or use the menu-bar item. Two complementary fixes:
1. Override `applicationShouldHandleReopen(_:hasVisibleWindows:)` so clicking the Dock icon when no windows are visible reopens the main window. This is the AppKit-native path.
2. Add a "Show Main Window" item to the `MenuBarExtra` popover so users with the menubar item visible have an explicit affordance.

- [ ] **Step 1: Add the AppDelegate reopen handler**

Edit `Apps/Lillist-macOS/Sources/AppDelegate.swift`. Add after `applicationDidFinishLaunching(_:)`:

```swift
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .lillistReopenMainWindow, object: nil)
        }
        return true
    }
```

Add the notification name to `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift` (extension at line 70):
```swift
    static let lillistReopenMainWindow = Notification.Name("lillist.reopenMainWindow")
```

In `Apps/Lillist-macOS/Sources/LillistApp.swift`, add `id: "main"` to the `WindowGroup` (line 12) and attach a small `ViewModifier` that grabs `@Environment(\.openWindow)` and calls `openWindow(id: "main")` on the notification:

```swift
private struct MainWindowReopener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .lillistReopenMainWindow)) { _ in
            openWindow(id: "main")
        }
    }
}
```

Apply it to `content` inside the `WindowGroup`.

- [ ] **Step 2: Add a "Show Main Window" item to the `MenuBarExtra` popover**

Plan 15 Task 9 shipped `MenuBarExtraScene` with a fileprivate `MenuBarPopover` view in `Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift`. Its bottom `HStack` currently has "Open Lillist" and "Quit" buttons; insert a "Show Main Window" button alongside "Open Lillist" that posts the new notification:

```swift
            HStack {
                Button("Open Lillist") { … }
                Button("Show Main Window") {
                    NotificationCenter.default.post(name: .lillistReopenMainWindow, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command])
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
```

(The keyboard shortcut works while the popover is key. The notification flows to `MainWindowReopener` regardless of whether the popover is visible, so `openWindow(id: "main")` fires the same way as the Dock-icon path.)

- [ ] **Step 3: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Clean.

- [ ] **Step 4: Manual verification**

Launch the app, press `⌘W` to close the window, click the Dock icon — a new window opens.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/AppDelegate.swift \
        Apps/Lillist-macOS/Sources/LillistApp.swift \
        Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift \
        Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift
git commit -m "feat(macOS): Dock-icon reopens main window after ⌘W; recover lost main window"
```

---

## Task 13: Extract `mikeyward@gmail.com` into a single `LillistCoreContact.crashReportRecipient` constant

**Files:**
- New: `Packages/LillistCore/Sources/LillistCore/Support/LillistCoreContact.swift`
- Modify: `Apps/Lillist-macOS/Sources/MailtoTransport.swift:12`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift:63` (already touched in Task 4, but reconfirm)
- Modify: `Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift:52`
- Modify: `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift:74`
- Modify: `Packages/LillistCore/Sources/lillist-cli/Support/CLIMailtoTransport.swift:9`

Five sites hardcode the same email address. Lift to one constant in `LillistCore` (the only module all five sites can import).

- [ ] **Step 1: Create the constant**

Create `Packages/LillistCore/Sources/LillistCore/Support/LillistCoreContact.swift`:

```swift
import Foundation

/// Lillist's single source of truth for user-visible contact info.
///
/// Currently scoped to the crash-report recipient — the email address
/// that the macOS `MailtoTransport`, iOS `MailComposeTransport`, CLI
/// `CLIMailtoTransport`, and both UI surfaces (the macOS Preferences
/// pane and the cross-platform CrashReportSheet) all consume.
///
/// Adding a second piece of contact info (a support URL, a forum link)
/// goes here too. Keep the surface minimal — this is `static let`
/// constants, not configuration.
public enum LillistCoreContact {
    /// Recipient for user-mediated crash reports. Plumbed through
    /// `MailtoTransport.init(recipient:)`, `CLIMailtoTransport.init(recipient:)`,
    /// and the iOS `MailComposeTransport`. Two prior copies of this
    /// string lived in app-target Preferences UI strings; Plan 19
    /// collapsed those into this single declaration.
    public static let crashReportRecipient: String = "mikeyward@gmail.com"
}
```

- [ ] **Step 2: Migrate each call site**

Edit each of the five sites to read `LillistCoreContact.crashReportRecipient` instead of the literal:

`Apps/Lillist-macOS/Sources/MailtoTransport.swift:12`:
```swift
    public init(recipient: String = LillistCoreContact.crashReportRecipient) {
```

`Packages/LillistCore/Sources/lillist-cli/Support/CLIMailtoTransport.swift:9`:
```swift
    public init(recipient: String = LillistCoreContact.crashReportRecipient) { self.recipient = recipient }
```

`Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift:52`:
```swift
                        recipient: LillistCoreContact.crashReportRecipient,
```

`Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift:63` (the multi-line string):
```swift
        Sent to: \(LillistCoreContact.crashReportRecipient)
```

`Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift:74`:
```swift
                    Text("Reports go directly to Mikey (\(LillistCoreContact.crashReportRecipient)). No third-party telemetry.")
```

(LillistUI imports LillistCore — confirm with `grep -n "import LillistCore" Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift`; if not, add the import.)

- [ ] **Step 3: Build all targets**

```bash
swift build --package-path Packages/LillistCore -Xswiftc -warnings-as-errors 2>&1 | tail -5
swift build --package-path Packages/LillistUI -Xswiftc -warnings-as-errors 2>&1 | tail -5
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

All four clean.

- [ ] **Step 4: Grep to confirm no straggler literals remain**

```bash
grep -rn "mikeyward@gmail.com" Apps/ Packages/LillistCore/Sources/ Packages/LillistUI/Sources/ 2>/dev/null
```

Expected: the only match is the literal inside `LillistCoreContact.swift`. The two test-fixture occurrences (`BreadcrumbBufferTests.swift`, `raw-logs-with-emails.txt`) are intentional fixtures and stay as-is.

- [ ] **Step 5: Run the broader test suites to catch any regressions**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -5
swift test --package-path Packages/LillistUI 2>&1 | tail -5
```

Both green.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Support/LillistCoreContact.swift \
        Apps/Lillist-macOS/Sources/MailtoTransport.swift \
        Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift \
        Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift \
        Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift \
        Packages/LillistCore/Sources/lillist-cli/Support/CLIMailtoTransport.swift
git commit -m "refactor(core): single LillistCoreContact.crashReportRecipient; remove four duplicates"
```

---

## Task 14: Final sweep, engineering note, tag

**Files:**
- Modify: `docs/engineering-notes.md`

- [ ] **Step 1: Full test sweeps**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
swift test --package-path Packages/LillistUI 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

All five green.

- [ ] **Step 2: Append the engineering-notes entry**

Add at the top of `docs/engineering-notes.md` (above the most-recent entry):

```markdown
## 2026-05-16 — Plan 19 macOS polish sweep: WindowGroup chrome, live preference streams, sidebar context menus, list-column source-name resolution, single contact-info constant

**Context.** Plan 19 closed the LOW/NIT-severity macOS findings from the 2026-05-16 design review that weren't addressed by Plans 13–17. Most tasks were 1–5-file surgical edits; the load-bearing structural change was a hot `AsyncStream<Prefs>` on `PreferencesStore` so the six Preferences panes stay current under CloudKit-pushed setting changes.

**Rules.**

- **`WindowGroup` title flows from the deepest `.navigationTitle`.** Set the title on the column whose content the user is editing, not on the `WindowGroup` itself — the system promotes it. Same computation feeds the toolbar (Plan 15 Task 1) and the window chrome (Plan 19 Task 1).
- **`@unchecked Sendable` final classes expose `AsyncStream` with `NSLock` + a continuation dictionary.** Copy the shape from `AccountStateMonitor.stateStream` / `CloudKitEventBridge.eventStream` / `SyncStatusMonitor.statusStream`. Pair every `update`-then-`save` with `broadcast(snapshot)`. Bridge `NSPersistentStoreRemoteChange` through the same path so subscribers don't care about provenance.
- **Subscribers that round-trip their own writes must echo-suppress.** When a Preferences pane writes `prefs` and the store broadcasts the snapshot back, compare to local state and skip if equal. Otherwise the form fights itself mid-edit.
- **`applicationShouldHandleReopen(_:hasVisibleWindows:)` is the AppKit-native recovery for `⌘W`-closes-only-window.** SwiftUI's `WindowGroup` does not auto-reopen. The system asks AppDelegate via the reopen callback; combine with `NotificationCenter` → `@Environment(\.openWindow)` to spawn a fresh window if the group is empty.
- **One constant beats five copies.** Five files held `"mikeyward@gmail.com"`. The right shape is `LillistCoreContact.crashReportRecipient`. Cost of the one-file abstraction: zero; cost of copies diverging on the next email change: a bug-report round.

**Evidence.** Plan 19 commits on `plan-19-macos-polish-sweep` (or merged into `main`): one commit per task, tagged `plan-19-macos-polish-sweep`.
```

- [ ] **Step 3: Commit and tag**

```bash
git add docs/engineering-notes.md
git commit -m "docs: record Plan 19 macOS polish lessons"
git tag plan-19-macos-polish-sweep
```

- [ ] **Step 4: Branch summary**

```bash
git log --oneline main..plan-19-macos-polish-sweep
```

Inspect — there should be ~13 task commits + this final `docs:` commit.

---

## Plan 19 Scope

**In:**

1. WindowGroup title binding via `.navigationTitle(sourceTitle)`.
2. `.defaultSize` + `.windowResizability` on the main `WindowGroup`.
3. "New Window" command (or documented deferral if multi-window is not viable today).
4. Live crash-report preview in `CrashReportingPane` (or shared-recipient + TODO if Plan 14 Task 10 has not merged).
5. `PreferencesStore.prefsStream` + every Preferences pane subscribing to live snapshots.
6. Sidebar `.contextMenu` on tag rows, pinned-task rows, and filter rows (rename / change color / delete / unpin as appropriate).
7. `TaskListView.sourceTitle` resolves to actual filter/tag/task names.
8. Verified-or-explicit arrow-key navigation in the task list, with a regression test.
9. Onboarding tagline rewritten in plain English.
10. Single defaults-install path in `LillistApp.loadEnvironmentIfNeeded`.
11. `CFBundleShortVersionString` / `CFBundleVersion` bumped to `1.0.0` / `20260516` for both macOS and iOS.
12. `applicationShouldHandleReopen(_:hasVisibleWindows:)` recovery path for `⌘W`-closes-only-window, plus a "Show Main Window" item added to Plan 15's `MenuBarPopover` (Plan 15 is merged on `main`; the conditional is gone).
13. `LillistCoreContact.crashReportRecipient` shared constant; all five hardcoded sites consume it.
14. Engineering note + branch tag.

**Out (deferred or owned by other plans):**

- HotkeyRecorder conflict detection → **Plan 15 Task 18**
- TodayPopoverView stale-on-reopen → **Plan 15 Task 11**
- RecurrenceEditorView Cancel `.keyboardShortcut(.cancelAction)` → **Plan 17 Task 25**
- macOS keyboard traps focus-gating (Space/`⌘D`/`⌘.`/Tab) → **Plan 13 Task 5**
- `⌘D` and `⌘.` rebinds → **Plan 13 Tasks 5/7**
- Toolbar, Detail-as-Form, sectioned detail layout → **Plan 15 Tasks 1, 4**
- `MenuBarExtra` migration → **Plan 15 Task 9**
- Dock badge/menu, About box, Help menu, Services provider, Spotlight, Handoff → **Plan 15 Tasks 19–25**
- Multi-window correctness (Core Data race-safety across multiple `AppEnvironment`s) → out-of-scope; Task 3 documents the deferral path if discovered during execution.
- Anything iOS-side beyond the version bump and the shared-recipient migration → **Plan 16**.
- Anything localization or accessibility-environment-related (RTL, reduce-motion, increase-contrast) → **Plan 17**.

---

## Self-Review Checklist (run by the implementer before merging)

- [ ] All 14 tasks merged as separate commits with conventional-commit prefixes (`feat:` / `fix:` / `refactor:` / `chore:` / `docs:` / `test:`).
- [ ] `swift build --package-path Packages/LillistCore -Xswiftc -warnings-as-errors` clean.
- [ ] `swift build --package-path Packages/LillistUI -Xswiftc -warnings-as-errors` clean.
- [ ] `swift test --package-path Packages/LillistCore` green.
- [ ] `swift test --package-path Packages/LillistUI` green.
- [ ] `xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' build` clean.
- [ ] `xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' build` clean.
- [ ] `xcodebuild test … Lillist-macOS …` green for all macOS test targets, including the three new test files (`SidebarContextMenuTests`, `TaskListSourceTitleTests`, `ArrowKeyNavigationTests`-extending-`KeyboardShortcutTests`).
- [ ] Manual verification: title bar reflects sidebar source; window opens at ~1180×760 on first launch; `⌥⌘N` opens a second window (or "New Window" is documented as deferred); `⌘W` then Dock-click reopens; right-click on a sidebar tag shows rename/color/delete; "View what would be sent" shows a live preview (or a TODO comment is present if Plan 14 hasn't merged); CloudKit-pushed preference change in another window propagates to the open Settings pane.
- [ ] `grep -rn "mikeyward@gmail.com" Apps/ Packages/LillistCore/Sources/ Packages/LillistUI/Sources/` returns only the one declaration inside `LillistCoreContact.swift`.
- [ ] `Info.plist` files show `CFBundleShortVersionString=1.0.0`, `CFBundleVersion=20260516` for both platforms.
- [ ] No stale `// TODO: menu in Task N` / `/* menu in Task N */` comments referencing this plan's context menu work.
- [ ] `docs/engineering-notes.md` has the Plan 19 entry at the top.
- [ ] `git tag plan-19-macos-polish-sweep` lands on the final commit.
- [ ] None of the "already covered by other plans" items were re-implemented.
