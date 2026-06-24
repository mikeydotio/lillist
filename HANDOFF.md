# HANDOFF — macOS main window adopts the shared iOS UI

Full spec: the approved plan at
`~/.claude/plans/let-s-nuke-the-mac-specific-twinkly-phoenix.md`
(Context + locked decisions + 6 waves + verification). Cross-cutting
lessons are in `docs/engineering-notes.md` (2026-06-24 entry). This file
tracks live state only.

## Done ✅ (macOS app + LillistUI + LillistCore green; iOS unaffected)

The macOS main window is now the shared iOS single-column surface —
"the iOS app running on a Mac." The bespoke `NavigationSplitView`
(sidebar + list) is gone; navigation is the iOS `FilterHeader` (search +
quick-filter chips + saved-filter chips), task detail is the in-window
overlay editor, and the window is narrow + freely resizable.

- **Un-gated shared LillistUI components** (Wave 1) — `TasksScreen`,
  `iOS/Tasks/*`, toasts, `SyncStatusBadge`, `FloatingAddButton`,
  `TaskEditorOverlay`, `QuickCaptureActionEnvironment`. Three iOS-only
  modifiers platform-branched in `TasksScreen` + `FilterHeader`. Genuinely
  iOS-only files stay gated. (`swift build`/`swift test` LillistUI green.)
- **macOS container** (Wave 2) — new `Apps/Lillist-macOS/Sources/`:
  `Tasks/MacTasksView.swift` (mirrors iOS `TasksView`; Settings opens via
  `openSettings`; Dock-menu + panel notifications observed),
  `Editor/MacTaskEditorHost.swift` (in-window overlay; `NSOpenPanel`
  attachments), `Common/SceneBindings.swift`.
- **App wiring + window** (Wave 3) — `LillistApp` renders `MacTasksView`;
  narrow window (`minWidth 360 / ideal 420`, `.contentMinSize`);
  `lillist.macos.sort` AppStorage; `uiTestResetState` updated.
- **Command menu + deletions** (Wave 4) — `LillistCommands` trimmed (⌘N →
  quick-capture binding; selection/sidebar commands retired);
  `CommandNotifications` trimmed; deleted `Views/` (RootSplitView,
  Sidebar/*, TaskList/*), `UIStatePersistence`, `FocusedListColumn`,
  `OpenTaskEditorAction` + 6 dependent unit tests; `Apps/project.yml`
  co-compile lines pruned; project regenerated. macOS app builds signed;
  `Lillist-macOSTests` 23/23 green; UITest tour rewritten for the new UI.

The global-hotkey `QuickCapturePanelController` NSPanel is intentionally
kept (only path that works with the window closed/unfocused).

## Remaining — tracked follow-up (shared, both platforms)

**Tag + saved-filter management has no UI on either platform.** Rename /
recolor / delete (tags) and rename / delete (saved filters) lived *only*
in the removed macOS sidebar; iOS never had them. Per the parity
principle, add this to the **shared** iOS-style UI (a Settings
sub-screen so both platforms gain it together) — **not** a macOS-only
Preferences pane. The store ops + their guards already exist and are
green (`SidebarContextMenuTests`, `PinnedSidebarIntegrationTests` —
pure LillistCore), so this is UI-only work.

## Verify
```bash
swift build  --package-path Packages/LillistUI                 # macOS host: un-gated files compile
swift test   --package-path Packages/LillistUI --skip Snapshot --skip Tour
swift test   --package-path Packages/LillistCore --parallel --num-workers 2
(cd Apps && xcodegen generate)                                  # pbxproj drift
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' build
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' -only-testing:Lillist-macOSTests
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build
```
macOS UITests (`ScreenshotTests`) are not in CI — verify on a signed Mac
with iCloud (the screenshot tour was rewritten for the single-column UI).
Manual macOS smoke: single-column list, filter-header expand, quick +
saved-filter chips, row tap → in-window overlay editor, ⌃⌥Space still
opens the NSPanel when unfocused, ⌘N + FAB open in-window capture, drag-
reorder + swipe-to-delete, narrow window resizes to ~360, Dock "Show
Today" lands the Today chip, Preferences → Trash works.
