# Lillist macOS — Visual Design Pass (2026-06-23)

A full visual review of the macOS app, driven by **live XCUITest screenshots**
of real rendered surfaces (the only way to capture macOS Liquid Glass —
offscreen `NSHostingView`→image capture blanks glass). Both light and dark
appearance, across 13 distinct surfaces.

## Method & artifacts

- **Harness (new, committed):** `Lillist-macOSUITests`
  (`Apps/Lillist-macOS/Tests/UITests/`), driven by DEBUG launch-arg seams in
  `LillistApp.swift` / `AppDelegate.swift`: `--ui-test-reset-store`,
  `--ui-test-seed-demo`, `--ui-test-bypass-gates`, `--ui-test-force-onboarding`,
  `--ui-test-show-quick-capture`, `--ui-test-appearance-light|dark`. Runs on a
  signed Mac (login keychain), **not** in CI (no window server). Re-run:
  `xcodebuild test -scheme Lillist-macOS -destination 'platform=macOS' -only-testing:Lillist-macOSUITests`
  then `xcrun xcresulttool export attachments`.
- **Screenshots:** `~/Enderchest/Lillist/macos-design-pass/before/` (32 PNGs).
- **Captured cleanly:** select-source empty state, tag list, two filter lists,
  empty trash, inline-create, onboarding, and Preferences panes 1–5 (iCloud,
  General, Notifications, Trash, Quick Capture) — all light+dark.
- **Capture limits (documented from source):** the floating quick-capture
  `NSPanel` and task-editor panel aren't surfaced by XCUITest (nonactivating
  panels); and the 3 overflow Preferences panes (Crash Reporting, Diagnostics,
  Advanced) sit behind the toolbar `>>` and resisted automated navigation —
  both facts reinforce findings below.

## Findings

| ID | Surface | Issue | Severity | Fix scope | Status |
| --- | --- | --- | --- | --- | --- |
| F1 | Task list (content pane) | Build-version label floats at bottom-center, looks like dev cruft (worse on short/empty lists); version already in About | Medium | macOS-only | **Fixed** |
| F2 | Sidebar | Selection highlight inconsistent: tag rows (DisclosureGroup) render **gray**, filter/trash rows render **bold purple** | Medium | macOS (shared row risk) | Recommend |
| F3 | Preferences | 8 tabs overflow the toolbar → `>>` chevron hides Diagnostics + Advanced | Medium | macOS, IA decision | Recommend |
| F4 | Preferences | Window width changes per pane (only `ICloudSyncPane` pins width; others self-size) → toolbar reflows when switching tabs | Medium | macOS-only | **Fixed** |
| F5 | Preferences › iCloud | Redundant "iCloud Sync" — section header *and* row label | Low | shared (iOS too) | Recommend |
| F6 | Help menu | "Lillist Help" opens the GitHub **repo** (TODO to swap to docs); a menu labeled "Help" landing on source | Low | macOS-only | **Fixed** |
| F7 | Quick Capture prefs | `HotkeyRecorder` hardcodes `Color.secondary.opacity(...)` instead of `LillistColor` tokens | Low | macOS-only | **Fixed** |
| F8 | Preferences | Stale comment: "Six tabs match design Section 7" — there are 8 | Trivial | macOS-only | **Fixed** |
| F9 | Sidebar | First-launch: sidebar refreshes once via `.task` and never re-queries, so default filters/tags can be absent until relaunch | Medium | macOS-only | **Fixed** |

### F1 — Build-version label floats in the content pane *(fixed)*
`Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:238` renders the
shared `BuildVersionLabel` at the bottom of the content column. On iOS that
component sits naturally at the end of a scrolling list; on macOS it floats
mid-air at the bottom-center, reading as leftover debug text — and the version
is already shown by the standard **About Lillist** panel
(`orderFrontStandardAboutPanel`). **Fix:** removed it from the macOS content
pane and relocated it as a subtle, muted footer pinned to the bottom of the
**sidebar** (a Mac-native spot; still useful during alpha for "which build am
I on?"). iOS usage of `BuildVersionLabel` is untouched.

### F2 — Sidebar selection inconsistency *(recommend)*
Tags render through `TagDisclosureView` (a `DisclosureGroup`); filters/trash
render as plain `SidebarRowView` rows. A selected **tag** shows a muted gray
highlight while a selected **filter** shows the bold script-purple accent
(confirmed in both light and dark). The selected tag reads as "inactive."
This is a SwiftUI `List(selection:)` + `DisclosureGroup` rendering quirk; a
clean fix likely means giving `SidebarRowView` its own consistent selection
treatment (it already receives `isSelected`) and neutralizing the List's
default — but that row view is **shared with iOS**, so the change must be
validated against the iOS sidebar/snapshots before landing. Flagged for a
focused follow-up rather than risk an iOS regression in this pass.

### F3 — Preferences tab overflow *(recommend — IA decision)*
Eight top-level panes don't fit the Settings toolbar; macOS collapses
Diagnostics + Advanced behind a `>>` overflow chevron. Recommendation:
consolidate to ~6 panes — e.g. fold **Diagnostics** and **Crash Reporting**
into one "Diagnostics & Privacy" pane (both are troubleshooting/telemetry),
and consider merging **Trash** retention into **General** or **Advanced**.
Which panes merge is an information-architecture call worth your sign-off, so
not auto-applied. (Pinning width — F4 — at least makes the overflow *stable*
rather than shifting per pane.)

### F4 — Preferences window reflows per pane *(fixed)*
Only `ICloudSyncPane` pins `.frame(width: 520)`; the other panes end in
`.fixedSize()` and self-size to their content, so the window width (and the
toolbar tab layout) changes every time you switch panes. **Fix:** pinned a
shared, consistent content width across all panes so the window stays put and
the toolbar stops reflowing. Height still varies per pane (acceptable, matches
System Settings).

### F5 — Redundant "iCloud Sync" label *(recommend)*
The iCloud pane shows a Section header "iCloud Sync" immediately above a row
also labeled "iCloud Sync". The labels live in the **shared**
`ICloudSyncSettingsSection` (LillistUI), so a change touches iOS and the
snapshot baselines — deferred to a shared-UI change with the iOS surface and
all three `Localizable.xcstrings` updated together.

### F6 — Help menu points at the repo *(fixed)*
`LillistCommands.swift:104` mapped "Lillist Help" → the GitHub repo with a
`TODO`. **Fix:** relabeled to "Lillist on GitHub" so the menu item is honest
about its destination until a real docs site exists (the repo README is the
de-facto docs during alpha).

### F7 — HotkeyRecorder hardcoded colors *(fixed)*
`HotkeyRecorder.swift` used `Color.accentColor` / `Color.secondary.opacity(...)`
for its border and key-cap chrome instead of the design tokens. **Fix:** routed
through `LillistColor` (focus accent + `borderHair`/`sunken`) for token
consistency with the rest of Rainbow Glass.

### F8 — Stale tab-count comment *(fixed)*
`PreferencesWindow.swift` header said "Six tabs"; there are eight. **Fix:**
corrected the comment.

### F9 — First-launch empty sidebar *(fixed)*
`SidebarView` only refreshes via `.task { refresh() }` (one shot) and has no
Core Data save observer, while `DefaultsInstaller.installIfNeeded()` runs
*after* the first render. On a fresh install the default filters/tags can be
missing until the next launch. **Fix:** `SidebarView` now also refreshes on
`NSManagedObjectContextDidSave` (the same signal `AppDelegate` already uses for
the dock badge), so defaults appear as soon as they're installed and the
sidebar stays live when filters/tags change via the CLI or CloudKit sync.

## What looked good (no change)

- Dark mode: clean contrast; cards (`#1F2128`) on workspace (`#14151A`), legible
  status cubes, coherent onboarding.
- Task rows: accent stripes, status cubes (todo/started/blocked/closed), closed
  rows faded + strikethrough — all reading correctly.
- Empty states (Trash "No matching tasks", select-source) use the dot-grid +
  spectrum-masked icon as designed.
- Preferences toggles **are** the `RainbowToggleStyle` (flat `focusBlue` track +
  white thumb); they merely resemble the system switch at this size.
- Onboarding sheet: hero status-cube, tagline, three bullets, clear CTAs.
