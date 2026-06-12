# Symptom Report

## Observed Behavior
On iOS, tapping the status circle (completion control) on a task row does
nothing: no status change, no error, **and no navigation** (so the touch is
claimed by the control, not falling through to the row's NavigationLink).

## Expected Behavior
Tap cycles status per design §7 (todo → started → closed → todo); long-press
opens the explicit Started/Blocked/Closed menu.

## Classification
Regression — shipped in deploy build 26 (2026-05-26).

## Timeline
- First noticed: ~2026-06-11 (build 40 era); user could not pin last-known-good
  build ("worked fine a few builds ago").
- Builds: 26 (05-26), 36/37 (05-27), 38 (05-28), 39 (06-06), 40 (06-11).
- Device iOS updated in the window, but the break predates the update.

## Reproduction
100% reproducible on device and on the iPhone 17 / iOS 26.2 simulator
(fresh install, one task, tap the glyph at ~x=64pt of the row).

## Scope
iOS only. macOS clicks work (rows are not NavigationLink-wrapped there and the
macOS drag gesture differs).

## Key Observations (user-confirmed)
- Long-press on the same circle opens the menu AND selecting a status works
  end-to-end → the downstream chain (closure → TaskStore.transition → reload)
  is healthy.
- Row-title taps navigate to detail on device.
- Other mutations (capture, delete, reorder) unaffected.

## Relevant Code Areas
- `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift`
  (`Menu(primaryAction:)`)
- `Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift`
  (row composition: NavigationLink wrap + `.dragReorderable`)
- `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift`
- `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift` (`cycle`/`setStatus`)
