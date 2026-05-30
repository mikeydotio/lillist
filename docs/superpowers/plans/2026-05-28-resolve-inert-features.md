# Resolve Inert Features Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 3.**
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> ⚠️ **Wave 1 (`store-swap-safety`) is merged to `main`.** It changed several shared files (`MigrationCoordinator`, `PersistenceHost`, `QuarantineManager`, `MigrationJournal`, both `AppEnvironment`s, `PersistenceController`). **Re-Read every file before editing and anchor by code structure — the line numbers in this plan may have drifted.**

> **⚠️ Wave-1 reconciliation:**
> store-swap-safety merged (bfd8635..6f008f7) and added the `sync-7` `localStoreRowCount` closure block to BOTH `AppEnvironment.swift` inits, shifting every bootstrap-region line number in Task 8 and Task 10 down by ~11 lines.
> Re-Read both files and anchor by TEXT, not the plan's line numbers. Verified current anchors: iOS — `await notificationScheduler.bootstrap()` is line 274 (plan says 263); `self.accountState = await accountStateMonitor.currentState` is 286 (plan says 275); `startObservingAccountState()` 287; `installCanaryLifecycleObservers()` 289; `startObservingSyncMode()` 350. macOS — `notificationScheduler.bootstrap()` 246 (plan says 235); `self.accountState = …` 260 (plan says 249); `startObservingSyncMode()` 262 (plan says 251). The named-text insertion points are all still unique and present, so the edits remain valid once re-anchored.
> No work is duplicated: this plan's findings (persist-6, ios-1, ios-4, macos-2, logs-2, crumbs-3, cli-1) are disjoint from store-swap-safety's closed set, and it does NOT touch MigrationCoordinator, restoreFromBackup, PersistenceReconfiguring, copyStore, or the localStoreRowCount wiring (already done). Do not re-wire localStoreRowCount — it is present in both inits already.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every shipped-but-inert feature honest — wire `AutoPurgeJob` into launch and a real iOS background task, drive (or honestly delete) the iOS pause-reason mirror, remove the four dead macOS menu commands and the dead iOS `CommandMenu("Task")` block behind a guard test, strip misleading crash-report logs/breadcrumb copy, and centralize the CLI `time_zone` knob so it actually affects date parsing.

**Architecture:** All testable seams live in `LillistCore` (host-runnable under `swift test`); app-target wiring stays thin and is guarded by tests that live where they can actually run (LillistCore Swift Testing suites + the macOS XCTest bundle), because the standalone iOS test bundle cannot `@testable import Lillist_iOS`. `AutoPurgeJob` is invoked from both `AppEnvironment.bootstrap()` methods and from a new iOS `BGProcessingTaskRequest` handler keyed on a `LillistCore` constant. The CLI gets a single `Config.resolvedCalendar()` that validates the configured identifier and threads through every date command, replacing the eight hardcoded `Calendar.current` call sites.

**Tech Stack:** Swift 6.2, SwiftUI, Core Data (`NSPersistentCloudKitContainer`), `BackgroundTasks` (iOS), Swift Testing (`import Testing`) for LillistCore, XCTest for the macOS app bundle, `swift-argument-parser` for the CLI.

**Source findings:** persist-6, ios-1, ios-4, macos-2, logs-2, crumbs-3, cli-1

---

## File Structure

### Create

- `Packages/LillistCore/Sources/LillistCore/Persistence/BackgroundPurgeSchedule.swift` — host-testable constant struct holding the iOS background-task identifier and the earliest-begin interval; single source of truth shared by the iOS registration, the Info.plist permitted-identifier, and a pin test.
- `Packages/LillistCore/Tests/LillistCoreTests/Persistence/BackgroundPurgeScheduleTests.swift` — pins the identifier string + interval so iOS registration and Info.plist can't silently drift.
- `Packages/LillistCore/Tests/LillistCoreTests/Persistence/AutoPurgeLaunchTests.swift` — proves the exact `AutoPurgeJob.run()` call the launch/background paths make actually purges an aged soft-deleted task end-to-end.
- `Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift` — dependency-free (Foundation-only) home for the command `Notification.Name` extension plus the `CommandNotifications.postedByCommands` registry, so the standalone macOS test bundle can co-compile it without an app test host.
- `Apps/Lillist-macOS/Tests/CommandNotificationObserverGuardTests.swift` — guard test asserting every notification name the `LillistCommands` menu posts is in the curated observed-allowlist (catches re-introduced dead menu commands).

### Modify

- `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift` — add `autoPurgeJob` property; call `autoPurgeJob.run()` in `bootstrap()`; add `startObservingPauseReason()` driving the `pauseReason` mirror (ios-1); add `runBackgroundPurge()` entry point used by the BGTask handler.
- `Apps/Lillist-macOS/Sources/AppEnvironment.swift` — add `autoPurgeJob` property; call `autoPurgeJob.run()` in `bootstrap()`; add `startObservingPauseReason()` driving the `pauseReason` mirror (parity with iOS so the macOS dead mirror stops being dead).
- `Apps/Lillist-iOS/Sources/App/LillistApp.swift` — register the `BGProcessingTaskRequest` handler in `App.init()` and submit the request after a successful launch (persist-6).
- `Apps/Lillist-iOS/Info.plist` — add `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes` (`processing`) so the OS will dispatch the task.
- `Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift` — delete the entire dead `CommandMenu("Task")` block and the four orphaned `Notification.Name`s it owned (ios-4).
- `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift` — delete the unobserved Indent/Outdent buttons, the unobserved `Find in View…`/`Find Everywhere…` `CommandGroup`, and the inline `Notification.Name` extension (moved to `CommandNotifications.swift`) (macos-2).
- `Apps/project.yml` — co-compile `CommandNotifications.swift` into the `Lillist-macOSTests` bundle, then regenerate the pbxproj (macos-2).
- `Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift` — remove the two preview lines that claim breadcrumbs and crashed-run logs are captured (they are not, post-crash) (logs-2, crumbs-3).
- `Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift` — replace the stale "placeholder strings for breadcrumbs and logs" TODO comment with an accurate one referencing the observability-logging plan (logs-2, crumbs-3).
- `Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift` — replace `cfg.timeZone = TimeZone(identifier: value)` silent-nil with validation that throws on an unknown identifier; add `resolvedCalendar()` (cli-1).
- `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/ConfigTests.swift` — add tests for `resolvedCalendar()` and the invalid-identifier validation (cli-1).
- `Packages/LillistCore/Sources/lillist-cli/Commands/{Ls,Add,Edit,Eval,Nudge,Watch,Count,Filters}Command.swift` — read `Config` and pass `cfg.resolvedCalendar()` instead of `Calendar.current` (cli-1).

---

### Task 1: Centralize the CLI `time_zone` knob into `Config.resolvedCalendar()` (cli-1)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift` (lines 47-48 parse site; add method after line 16)
- Test `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/ConfigTests.swift`

- [ ] **Step 1: Write the failing test** — append these two tests to `ConfigTests.swift`, inside the `struct ConfigTests` body (after the `defaultLocation` test, before the closing brace). They match the existing Swift Testing style.

```swift
    @Test("resolvedCalendar uses the configured time zone")
    func resolvedCalendarUsesConfiguredZone() throws {
        let url = try writeToml("time_zone = \"America/Los_Angeles\"")
        let cfg = try CLIBridge.Config.read(from: url)
        let cal = cfg.resolvedCalendar()
        #expect(cal.timeZone.identifier == "America/Los_Angeles")
    }

    @Test("resolvedCalendar falls back to current when no time zone is set")
    func resolvedCalendarDefaultsToCurrent() throws {
        let cfg = CLIBridge.Config()
        let cal = cfg.resolvedCalendar()
        #expect(cal.timeZone == Calendar.current.timeZone)
    }

    @Test("Invalid time_zone throws validationFailed")
    func invalidTimeZone() throws {
        let url = try writeToml("time_zone = \"Mars/Olympus_Mons\"")
        #expect(throws: LillistError.self) {
            _ = try CLIBridge.Config.read(from: url)
        }
    }
```

- [ ] **Step 2: Run the test, expect failure** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ConfigTests
  ```
  Expect a compile failure: `value of type 'CLIBridge.Config' has no member 'resolvedCalendar'`, and once that's stubbed, `invalidTimeZone` fails because the current parser silently sets `nil` instead of throwing.

- [ ] **Step 3: Implement the minimal change** — in `Config.swift`, add the `resolvedCalendar()` method directly after the `init` (after line 16, before `read(from:)`):

```swift
        /// The calendar date commands should use, honoring the configured
        /// `time_zone`. Falls back to `Calendar.current` (which carries the
        /// host's zone) when no `time_zone` key is set. Centralizes what
        /// every CLI date command previously hardcoded as `Calendar.current`,
        /// so the parsed `time_zone` actually affects relative-date math.
        public func resolvedCalendar() -> Calendar {
            guard let timeZone else { return Calendar.current }
            var calendar = Calendar.current
            calendar.timeZone = timeZone
            return calendar
        }
```

  Then replace the silent-nil `time_zone` parse arm (lines 47-48) with a validating one:

```swift
                case "time_zone":
                    guard let zone = TimeZone(identifier: value) else {
                        throw LillistError.validationFailed([
                            .init(field: "time_zone", message: "unknown time zone identifier '\(value)'")
                        ])
                    }
                    cfg.timeZone = zone
```

- [ ] **Step 4: Run the test, expect pass** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ConfigTests
  ```
  Expect: all `ConfigTests` cases pass (the original six plus the three new ones).

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/ConfigTests.swift
  git commit -m "feat(cli): validate time_zone and add Config.resolvedCalendar()

The time_zone key parsed into Config.timeZone but no command consumed it;
every date command hardcoded Calendar.current. Add resolvedCalendar() as the
single source of truth and make an unknown identifier a validation error
instead of a silent nil. (cli-1)"
  ```

---

### Task 2: Thread `Config.resolvedCalendar()` through every CLI date command (cli-1)

**Files (Modify):**
- `Packages/LillistCore/Sources/lillist-cli/Commands/LsCommand.swift` (line 91)
- `Packages/LillistCore/Sources/lillist-cli/Commands/AddCommand.swift` (line 48)
- `Packages/LillistCore/Sources/lillist-cli/Commands/EditCommand.swift` (line 36)
- `Packages/LillistCore/Sources/lillist-cli/Commands/EvalCommand.swift` (line 19)
- `Packages/LillistCore/Sources/lillist-cli/Commands/NudgeCommand.swift` (line 12)
- `Packages/LillistCore/Sources/lillist-cli/Commands/WatchCommand.swift` (line 34)
- `Packages/LillistCore/Sources/lillist-cli/Commands/CountCommand.swift` (line 24)
- `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift` (lines 65, 93)

This task has no new unit test of its own — Task 1 proved `resolvedCalendar()` is correct; this wiring is verified by `swift build` plus the existing handler tests (which inject their own calendar and are unaffected). The change is a mechanical substitution per file.

- [ ] **Step 1: `LsCommand.swift`** — `LsCommand` already reads `cfg` at line 59. Change the `LsHandler.run` call (lines 89-92) from `calendar: Calendar.current` to `calendar: cfg.resolvedCalendar()`:

```swift
        let records = try await CLIBridge.LsHandler.run(
            flags: flags, savedFilterName: saved, sort: sortField,
            persistence: p, now: Date(), calendar: cfg.resolvedCalendar()
        )
```

- [ ] **Step 2: `AddCommand.swift`** — read the file. If it does not already read `cfg`, add `let cfg = try CLIBridge.Config.read(from: CLIBridge.Config.defaultLocation())` immediately after the `StoreLocator.openAppGroup()` line, then change line 48 `calendar: Calendar.current` to `calendar: cfg.resolvedCalendar()`. Verify the surrounding `AddHandler.run(...)` argument label is unchanged.

- [ ] **Step 3: `EditCommand.swift`, `EvalCommand.swift`, `NudgeCommand.swift`, `WatchCommand.swift`, `CountCommand.swift`** — for each: read the file; ensure a `let cfg = try CLIBridge.Config.read(from: CLIBridge.Config.defaultLocation())` exists right after the persistence open (add it if absent); replace each `calendar: Calendar.current` with `calendar: cfg.resolvedCalendar()`. In `WatchCommand.swift` there are two calendar uses (lines 34 and a `calendarCopy` at the handler's second call); pass `cfg.resolvedCalendar()` at line 34 — the handler derives its own internal copy, so only the entry-point argument changes.

- [ ] **Step 4: `FiltersCommand.swift`** — it already reads `cfg` at line 54. Replace both `calendar: Calendar.current` occurrences (lines 65 and 93) with `calendar: cfg.resolvedCalendar()`.

- [ ] **Step 5: Build and verify no `Calendar.current` remains in the CLI commands** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | tail -5
  grep -rn "Calendar.current" Packages/LillistCore/Sources/lillist-cli/Commands/ || echo "CLEAN: no Calendar.current left"
  swift test --package-path Packages/LillistCore --filter CLIBridge 2>&1 | tail -5
  ```
  Expect: clean build (no warnings — warnings are errors), `CLEAN: no Calendar.current left`, and all `CLIBridge` handler tests still passing.

- [ ] **Step 6: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/lillist-cli/Commands/
  git commit -m "feat(cli): thread Config.resolvedCalendar() through date commands

Replace the eight hardcoded Calendar.current call sites so a configured
time_zone actually affects relative-date parsing in ls/add/edit/eval/nudge/
watch/count/filters. (cli-1)"
  ```

---

### Task 3: Strip the misleading crash-report breadcrumbs/logs preview copy (logs-2, crumbs-3)

**Files (Modify):**
- `Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift` (lines 38-41)
- `Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift` (lines 27-34 comment)

The crash report's `OSLogFetcher` reads `OSLogStore(scope: .currentProcessIdentifier)` — after a crash the crashed process is gone, so on the next launch there are no "logs from the crashed run." `BreadcrumbBuffer` is in-memory only, so post-crash breadcrumbs are also empty. The toggles and `CrashReporter.submit` plumbing are real and stay; only the **preview copy** overpromises. The on-disk-buffer decision is owned by the observability-logging plan (see Self-review / crossPlanCoordination). Until that lands, the preview must not claim data it cannot deliver.

- [ ] **Step 1: Write the failing test** — the cross-platform user-visible string is guarded by snapshot tests. First confirm which snapshot suite renders `CrashReportSample.preview`:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -rln "CrashReportSample\|samplePreview\|View what would be sent" Packages/LillistUI/Tests Apps/*/Tests | grep -v .build
  ```
  There is no LillistUI snapshot of this static string today (it is rendered only inside the app-target panes). Add a focused assertion to LillistUI pinning the corrected copy. Append to the existing crash-reporting view-model test file — which is **XCTest** (`final class CrashReportViewModelTests: XCTestCase`, not Swift Testing). Open `Packages/LillistUI/Tests/LillistUITests/CrashReporting/CrashReportViewModelTests.swift`, read it, and add this XCTest method inside the class:

```swift
    func test_samplePreview_omitsUnavailablePostCrashSections() {
        let text = CrashReportSample.preview(.init(
            buildVersion: "1.0 (1)",
            osVersion: "iOS 26.2",
            deviceModel: "iPhone",
            recipient: "x@y.z",
            methodSuffix: "Mail."
        ))
        XCTAssertFalse(text.contains("last ~50 mutations"),
                       "Preview must not promise breadcrumbs that don't survive a crash")
        XCTAssertFalse(text.contains("last ~30 seconds of the crashed run"),
                       "Preview must not promise crashed-run logs OSLogFetcher can't fetch")
        XCTAssertTrue(text.contains("Build:"))
        XCTAssertTrue(text.contains("Sent to:"))
    }
```

- [ ] **Step 2: Run the test, expect failure** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI --filter CrashReportViewModelTests
  ```
  Expect failure: the two `!text.contains(...)` assertions fail because the current preview still includes the breadcrumbs and logs placeholder lines.

- [ ] **Step 3: Implement the minimal change** — edit `CrashReportSample.preview` to drop the two overpromising sections. Replace the whole returned string literal (lines 34-44) with:

```swift
        """
        Build: \(env.buildVersion)
        OS: \(env.osVersion)
        Device: \(env.deviceModel)
        Sent to: \(env.recipient)
        Method: \(env.methodSuffix)
        """
```

  Then fix the stale comment in `CrashReportingPane.swift` (the `TODO(Plan 19 / Plan 14 follow-up)` block, lines 27-34). Replace that comment with:

```swift
                        // The preview shows the build/OS/device/recipient
                        // header only. Breadcrumbs and crashed-run logs are
                        // not captured post-crash today (BreadcrumbBuffer is
                        // in-memory; OSLogFetcher scopes to the current
                        // process), so the preview must not advertise them.
                        // A real on-disk buffer is owned by the
                        // observability-logging plan; when it lands, restore
                        // the breadcrumbs/logs preview sections together with
                        // the live render.
```

- [ ] **Step 4: Run the test, expect pass** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI --filter CrashReportViewModelTests 2>&1 | tail -5
  ```
  Expect: the new test passes and the existing `CrashReportViewModelTests` still pass.

- [ ] **Step 5: Re-record the crash-report sheet snapshot if it shifted** — the sheet snapshot renders `samplePreview` inside it. Run the snapshot suite; if it fails on the dropped lines, that is the expected, intended diff — re-record:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI --filter CrashReportSheetSnapshotTests 2>&1 | tail -15
  ```
  If it reports a recorded-snapshot mismatch, delete the stale reference snapshots under `Packages/LillistUI/Tests/LillistUITests/CrashReporting/__Snapshots__/CrashReportSheetSnapshotTests/` that show the removed lines, then re-run the suite once to regenerate, then run a final time to confirm green. (If the snapshot does not include the sample preview, this step is a no-op confirming green.)

- [ ] **Step 6: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift Packages/LillistUI/Tests/LillistUITests/CrashReporting/
  git commit -m "fix(crash-report): stop preview promising unavailable breadcrumbs/logs

OSLogFetcher scopes to the current process and BreadcrumbBuffer is in-memory,
so neither survives a crash; the preview claimed both. Drop the overpromising
lines and point the pane comment at the observability-logging plan, which owns
the real on-disk buffer decision. (logs-2, crumbs-3)"
  ```

---

### Task 4: Delete the dead iOS `CommandMenu("Task")` block and orphaned names (ios-4)

**Files (Modify):**
- `Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift` (the `CommandMenu("Task")` block lines 26-50; the `Notification.Name` extension lines 54-62)

On iOS there is **no** observer for `lillistMarkClosed`, `lillistMarkBlocked`, `lillistIndent`, or `lillistOutdent` — verified by `grep` across `Apps/Lillist-iOS/Sources/` (the only `addObserver` calls are the canary lifecycle in `AppEnvironment`). The entire `CommandMenu("Task")` block posts notifications nobody listens to. `lillistFocusSidebar/List/Detail` are also defined but unused on iOS; this task removes only what the dead block owns, keeping `lillistMarkClosed`/`lillistMarkBlocked` names **only if** still referenced. They are not referenced elsewhere on iOS, so all four go.

- [ ] **Step 1: Re-confirm no observers exist before deleting** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -rn "lillistMarkClosed\|lillistMarkBlocked\|lillistIndent\|lillistOutdent\|lillistFocusSidebar\|lillistFocusList\|lillistFocusDetail" Apps/Lillist-iOS/Sources/ | grep -v "Commands/LillistCommands.swift"
  ```
  Expect: **no output** (no observers). If anything prints, stop and re-scope — do not delete an observed name.

- [ ] **Step 2: Delete the dead block** — in `Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift`, remove the entire `CommandMenu("Task")` block (the second `CommandMenu`, currently lines 26-50, including its leading blank line). After the edit, `body` contains only the `CommandMenu("Lillist")` New Task entry. Then remove the orphaned `Notification.Name` extension members so no dead names linger. Replace the whole `extension Notification.Name { ... }` (lines 54-62) with the trimmed set actually used by the surviving iOS command surface:

```swift
extension Notification.Name {
    static let lillistMarkClosed   = Notification.Name("lillist.markClosed")
    static let lillistMarkBlocked  = Notification.Name("lillist.markBlocked")
    static let lillistFocusSidebar = Notification.Name("lillist.focusSidebar")
    static let lillistFocusList    = Notification.Name("lillist.focusList")
    static let lillistFocusDetail  = Notification.Name("lillist.focusDetail")
}
```

  Then re-run the grep from Step 1 across the **whole** iOS app target including the commands file:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -rn "lillistMarkClosed\|lillistMarkBlocked\|lillistFocusSidebar\|lillistFocusList\|lillistFocusDetail\|lillistIndent\|lillistOutdent" Apps/Lillist-iOS/Sources/
  ```
  If any of these five remaining names are now **also** unreferenced (defined but never posted/observed anywhere in `Apps/Lillist-iOS/Sources/`), delete that member too — the goal is zero dead names. (`lillistIndent`/`lillistOutdent` must be fully gone.)

- [ ] **Step 3: Update the file's doc comment to match reality** — the header comment (lines 8-14) still describes "status-mutation and indent/outdent shortcuts." Replace that paragraph so it reads:

```swift
/// The 3-tab restructure collapsed the previous section/search command
/// surface into a single primary `TasksView`. iOS exposes only Quick
/// Capture as a hardware-keyboard shortcut (`⌘⇧N`, avoiding the
/// iPadOS-reserved `⌘N`); the status-mutation and indent/outdent
/// commands were removed because no iOS surface observed their
/// notifications.
```

- [ ] **Step 4: Build the iOS target without signing** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -15
  ```
  Expect: `** BUILD SUCCEEDED **` with no warnings (warnings are errors). The build proves no surviving code referenced the deleted names.

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift
  git commit -m "fix(ios): remove dead CommandMenu(Task) block and orphaned names

No iOS surface observed lillistMarkClosed/Blocked/Indent/Outdent; the entire
Task command menu posted into the void. Delete it and the now-orphaned
Notification.Name members. (ios-4)"
  ```

---

### Task 5: Remove the four dead macOS menu commands behind a guard test (macos-2)

**Files:**
- Create `Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift` (standalone, dependency-free: the `Notification.Name` extension + the `postedByCommands` registry)
- Modify `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift` (Indent/Outdent buttons lines 52-60; Find `CommandGroup` lines 63-76; delete the inline `Notification.Name` extension lines 125-146)
- Modify `Apps/project.yml` (co-compile `CommandNotifications.swift` into `Lillist-macOSTests`)
- Create `Apps/Lillist-macOS/Tests/CommandNotificationObserverGuardTests.swift`

`lillistIndent`, `lillistOutdent`, `lillistFindInView`, `lillistFindEverywhere` are posted by macOS menu commands (with ⌘F shortcuts) but have **no** `onReceive`/`addObserver` anywhere — verified by `grep`. ⌘F does nothing today.

**Constraint:** the standalone `Lillist-macOSTests` bundle has no app test host and therefore cannot `@testable import Lillist_macOS` (it co-compiles dependency-free source files instead — see `FocusedListColumn.swift`, `HotkeyRecorder.swift` in `Apps/project.yml`). So the registry and the `Notification.Name` extension must live in a **dependency-free** source file (`Foundation` only, no `AppEnvironment`/SwiftUI-state types) that both the app and the test bundle compile. The guard test then references those symbols directly without `@testable import`.

- [ ] **Step 1: Create the dependency-free notifications source** — create `Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift`. This becomes the single source of truth for command notification names and which the command menu posts; it imports only `Foundation` so the standalone test bundle can co-compile it (mirrors the `FocusedListColumn.swift` extraction pattern).

```swift
import Foundation

/// Command-menu notification names, promoted out of `LillistCommands`
/// into a dependency-free file so the standalone `Lillist-macOSTests`
/// bundle can co-compile it without `@testable import Lillist_macOS`
/// (it has no app test host). Mirrors the `FocusedListColumn.swift`
/// extraction pattern.
extension Notification.Name {
    static let lillistNewTask           = Notification.Name("lillist.newTask")
    static let lillistNewSibling        = Notification.Name("lillist.newSibling")
    static let lillistToggleStarted     = Notification.Name("lillist.toggleStarted")
    static let lillistMarkClosed        = Notification.Name("lillist.markClosed")
    static let lillistMarkBlocked       = Notification.Name("lillist.markBlocked")
    static let lillistFocusSidebar      = Notification.Name("lillist.focusSidebar")
    static let lillistFocusList         = Notification.Name("lillist.focusList")
    static let lillistFocusDetail       = Notification.Name("lillist.focusDetail")
    // Plan 15 Task 20: dock menu navigation.
    static let lillistSelectTodayFilter = Notification.Name("lillist.selectTodayFilter")
    static let lillistSelectFilter      = Notification.Name("lillist.selectFilter")
    // Plan 15 Task 29: ⌃⌘S menu command for sidebar visibility.
    static let lillistToggleSidebar     = Notification.Name("lillist.toggleSidebar")
    // Plan 19 Task 12: re-spawn the main window after ⌘W closed it (or
    // the menu-bar popover's "Show Main Window" button was clicked).
    static let lillistReopenMainWindow  = Notification.Name("lillist.reopenMainWindow")
}

/// Registry of every notification the `LillistCommands` menu surface
/// posts. `CommandNotificationObserverGuardTests` asserts each one has a
/// live observer, so a re-introduced dead command fails the build. Keep
/// this in sync when adding/removing a posting button.
enum CommandNotifications {
    static let postedByCommands: [Notification.Name] = [
        .lillistNewTask,
        .lillistNewSibling,
        .lillistToggleStarted,
        .lillistMarkClosed,
        .lillistMarkBlocked,
        .lillistFocusSidebar,
        .lillistFocusList,
        .lillistFocusDetail,
        .lillistToggleSidebar
    ]
}
```

  Note: `.lillistSelectTodayFilter`, `.lillistSelectFilter`, and `.lillistReopenMainWindow` are posted by `AppDelegate`/`MenuBarExtraScene`, not by `LillistCommands`, so they are declared above (the app still needs them) but are **not** in `postedByCommands`. The four dead names (`lillistIndent`/`lillistOutdent`/`lillistFindInView`/`lillistFindEverywhere`) are intentionally absent.

- [ ] **Step 2: Strip the dead commands and the inline extension from `LillistCommands.swift`** — in `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`:

  (a) Delete the two dead Indent/Outdent buttons inside `CommandMenu("Task")` (the `Divider()` + Indent + Outdent, lines 50-60) so the Task menu ends after "Mark Blocked & Schedule Follow-up":

```swift
        CommandMenu("Task") {
            Button("Toggle Started") {
                NotificationCenter.default.post(name: .lillistToggleStarted, object: nil)
            }.keyboardShortcut(.space, modifiers: [])
              .disabled(listColumn == nil)

            Button("Mark Closed") {
                NotificationCenter.default.post(name: .lillistMarkClosed, object: nil)
            }.keyboardShortcut(.return, modifiers: [.command])
              .disabled(listColumn == nil)

            Button("Mark Blocked & Schedule Follow-up") {
                NotificationCenter.default.post(name: .lillistMarkBlocked, object: nil)
            }.keyboardShortcut(".", modifiers: [.command])
              .disabled(listColumn == nil)
        }
```

  (b) Delete the entire dead Find `CommandGroup(after: .textEditing)` block (lines 63-76, including its leading comment). The standard system Find submenu survives once we stop appending to it.

  (c) Delete the inline `extension Notification.Name { ... }` at the bottom of the file (lines 125-146 in full) — it now lives in `CommandNotifications.swift`. Removing it avoids a duplicate-declaration error.

- [ ] **Step 3: Co-compile the new source into the macOS test bundle** — in `Apps/project.yml`, under `Lillist-macOSTests:` `sources:`, add (after the existing `FocusedListColumn.swift` co-compile entry) :

```yaml
      # macos-2: CommandNotifications declares the dependency-free
      # Notification.Name extension + the postedByCommands registry, so
      # CommandNotificationObserverGuardTests can read them without a
      # signed app test host.
      - path: Lillist-macOS/Sources/Commands/CommandNotifications.swift
```

  Then regenerate the pbxproj (CLAUDE.md ritual after adding source files):

```bash
cd /Volumes/Code/mikeyward/Lillist && (cd Apps && xcodegen generate --spec project.yml --project .)
git diff --stat Apps/Lillist.xcodeproj/project.pbxproj
```

- [ ] **Step 4: Write the failing test** — create `Apps/Lillist-macOS/Tests/CommandNotificationObserverGuardTests.swift`. It uses XCTest (matching every file in `Apps/Lillist-macOS/Tests/`) and references the co-compiled `CommandNotifications`/`Notification.Name` symbols directly — no `@testable import`.

```swift
import XCTest
import Foundation

/// Guard against re-introducing dead menu commands: every notification
/// name the `LillistCommands` menu posts must have a live observer (be in
/// the curated `observed` set below). `macos-2` shipped four commands
/// (Indent / Outdent / Find in View / Find Everywhere) that posted into
/// the void; this fails if any such name reappears unobserved.
///
/// `observed` is maintained by hand from the real `.onReceive` /
/// `addObserver` sites: RootSplitView, TaskListView, AppDelegate,
/// LillistApp, MenuBarExtraScene. When you add a command, add its
/// observer AND list it here — or the build fails.
final class CommandNotificationObserverGuardTests: XCTestCase {
    private let observed: Set<Notification.Name> = [
        .lillistNewTask,
        .lillistNewSibling,
        .lillistToggleStarted,
        .lillistMarkClosed,
        .lillistMarkBlocked,
        .lillistFocusSidebar,
        .lillistFocusList,
        .lillistFocusDetail,
        .lillistToggleSidebar,
        .lillistSelectTodayFilter,
        .lillistSelectFilter,
        .lillistReopenMainWindow
    ]

    func test_everyPostedCommandNotificationHasAnObserver() {
        let posted = Set(CommandNotifications.postedByCommands)
        let unobserved = posted.subtracting(observed)
        XCTAssertTrue(
            unobserved.isEmpty,
            "These command notifications are posted but unobserved (dead menu commands): \(unobserved.map(\.rawValue).sorted())"
        )
    }

    func test_theFourKnownDeadNamesAreGone() {
        let posted = Set(CommandNotifications.postedByCommands)
        for raw in ["lillist.indent", "lillist.outdent", "lillist.findInView", "lillist.findEverywhere"] {
            XCTAssertFalse(
                posted.contains(Notification.Name(raw)),
                "\(raw) was a dead command removed in macos-2; do not reintroduce it without an observer"
            )
        }
    }
}
```

- [ ] **Step 5: Run the test, expect pass; confirm no dead names remain** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' -only-testing:Lillist-macOSTests/CommandNotificationObserverGuardTests CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
  ```
  Expect: `Test Suite 'CommandNotificationObserverGuardTests' passed`. Then confirm the source is clean and the full macOS app still builds:
  ```bash
  grep -rn "lillistIndent\|lillistOutdent\|lillistFindInView\|lillistFindEverywhere" Apps/Lillist-macOS/Sources/ || echo "CLEAN"
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -6
  ```
  Expect `CLEAN` and `** BUILD SUCCEEDED **` (the build proves no surviving app code referenced the deleted names or the moved extension).

- [ ] **Step 6: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift Apps/Lillist-macOS/Tests/CommandNotificationObserverGuardTests.swift Apps/project.yml Apps/Lillist.xcodeproj
  git commit -m "fix(macos): remove four unobserved menu commands; add observer guard test

Indent/Outdent and Find in View/Everywhere posted notifications with no
observer (CmdF did nothing). Delete them, move the Notification.Name extension
into a dependency-free CommandNotifications source, and add an observer guard
test (co-compiled, no app test host) that fails the build if any posted
command notification lacks an observer. (macos-2)"
  ```

---

### Task 6: Add the shared background-purge schedule constant + pin test (persist-6)

**Files:**
- Create `Packages/LillistCore/Sources/LillistCore/Persistence/BackgroundPurgeSchedule.swift`
- Create `Packages/LillistCore/Tests/LillistCoreTests/Persistence/BackgroundPurgeScheduleTests.swift`

The iOS `BGProcessingTaskRequest`, the `Info.plist` `BGTaskSchedulerPermittedIdentifiers` entry, and the registration handler must all agree on one identifier string. Putting it in `LillistCore` makes it host-testable under `swift test` and impossible to drift silently.

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Persistence/BackgroundPurgeScheduleTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("BackgroundPurgeSchedule")
struct BackgroundPurgeScheduleTests {
    @Test("Task identifier is the stable, bundle-prefixed string")
    func identifierIsStable() {
        // The iOS Info.plist BGTaskSchedulerPermittedIdentifiers entry and
        // the BGProcessingTaskRequest must use exactly this string.
        #expect(BackgroundPurgeSchedule.taskIdentifier == "io.mikeydotio.Lillist.autopurge")
    }

    @Test("Earliest-begin interval is one day")
    func earliestBeginIsOneDay() {
        #expect(BackgroundPurgeSchedule.earliestBeginInterval == 24 * 60 * 60)
    }
}
```

- [ ] **Step 2: Run the test, expect failure** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter BackgroundPurgeSchedule
  ```
  Expect compile failure: `cannot find 'BackgroundPurgeSchedule' in scope`.

- [ ] **Step 3: Implement the minimal change** — create `Packages/LillistCore/Sources/LillistCore/Persistence/BackgroundPurgeSchedule.swift`:

```swift
import Foundation

/// Single source of truth for the iOS background trash-purge task.
///
/// The identifier must match the `Info.plist`
/// `BGTaskSchedulerPermittedIdentifiers` entry and the
/// `BGProcessingTaskRequest` the iOS app submits; the interval bounds how
/// soon after the last run the OS may re-dispatch the task. Lives in
/// `LillistCore` so it is host-testable under `swift test` (the
/// `BackgroundTasks` API itself is iOS-only and stays in the app target).
public enum BackgroundPurgeSchedule {
    /// Reverse-DNS task identifier registered with `BGTaskScheduler`.
    public static let taskIdentifier = "io.mikeydotio.Lillist.autopurge"

    /// Soonest the OS may launch the task after submission (one day).
    public static let earliestBeginInterval: TimeInterval = 24 * 60 * 60
}
```

- [ ] **Step 4: Run the test, expect pass** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter BackgroundPurgeSchedule
  ```
  Expect: both tests pass.

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Persistence/BackgroundPurgeSchedule.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/BackgroundPurgeScheduleTests.swift
  git commit -m "feat(core): add BackgroundPurgeSchedule constant for the iOS purge task

Single source of truth for the BGTask identifier + earliest-begin interval,
shared by the iOS registration, Info.plist, and a pin test so the three can't
drift. (persist-6)"
  ```

---

### Task 7: Prove `AutoPurgeJob` purges on the launch path (persist-6)

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/Persistence/AutoPurgeLaunchTests.swift`

`bootstrap()` will call `autoPurgeJob.run()` (Task 8). Because the standalone iOS test bundle cannot `@testable import Lillist_iOS`, the executable proof lives in `LillistCore`: it constructs the exact `AutoPurgeJob` the env builds, seeds an aged soft-deleted task, runs `.run()`, and asserts the purge. This pins the behavior the launch path invokes. (Task 8 wires the call; this test guarantees the call does the right thing.)

> **Verify before writing (so the test compiles):** the test below pokes the
> `LillistTask` managed object's `deletedAt` attribute directly and seeds the
> `trashRetentionDays` pref. Confirm both names are current against the real
> sources before pasting: `deletedAt` is declared at
> `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:20`
> (`@NSManaged public var deletedAt: Date?`) and `trashRetentionDays` is the
> pref field used by `AutoPurgeJob` / `PreferencesStore.Prefs` (see
> `AutoPurgeJob.swift:18` and the sibling `AutoPurgeJobTests.swift`, which use
> the identical `m.deletedAt = …` poke and `$0.trashRetentionDays = 30` seed).
> If either name has drifted, fix the test to match before running, or it won't
> compile.

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Persistence/AutoPurgeLaunchTests.swift`. It uses the `TestStore.make()` helper and Swift Testing, matching `AutoPurgeJobTests.swift` in the same directory:

```swift
import Testing
import Foundation
import CoreData
@testable import LillistCore

/// Proves the exact `AutoPurgeJob.run()` invocation that
/// `AppEnvironment.bootstrap()` and the iOS BGProcessingTask handler make
/// actually hard-deletes an aged soft-deleted task. The app-target
/// bootstrap call cannot be unit-tested directly (the standalone iOS test
/// bundle has no app host), so this LillistCore test stands in as the
/// behavioral contract the launch path relies on.
@Suite("AutoPurge launch contract")
struct AutoPurgeLaunchTests {
    @Test("run() at launch purges a task aged past retention")
    func launchPurgePurgesAgedTask() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 30 }

        let id = try await tasks.create(title: "stale-trash")
        try await tasks.softDelete(id: id)
        try await p.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try p.container.viewContext.fetch(req).first!
            m.deletedAt = Date().addingTimeInterval(-31 * 86400)
            try p.container.viewContext.save()
        }

        // Exactly what AppEnvironment.bootstrap() / the BGTask handler do.
        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run()

        #expect(purged == 1)
        await #expect(throws: LillistError.notFound) {
            _ = try await tasks.fetch(id: id)
        }
    }

    @Test("run() at launch is a no-op when the trash is fresh")
    func launchPurgeSparesFreshTrash() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 30 }

        let id = try await tasks.create(title: "recent-trash")
        try await tasks.softDelete(id: id)

        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run()
        #expect(purged == 0)
        _ = try await tasks.fetch(id: id)
    }
}
```

- [ ] **Step 2: Run the test, expect pass-on-real-behavior** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "AutoPurge launch contract"
  ```
  These pass immediately because `AutoPurgeJob` already works. That is intentional: the test is the **behavioral contract** the Task 8 wiring relies on; the wiring's own correctness is verified by the iOS build in Task 8. (TDD note: there is no failing-first state to manufacture here without duplicating `AutoPurgeJobTests`; the value is the named launch-contract guard, not a new behavior.)

- [ ] **Step 3: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Tests/LillistCoreTests/Persistence/AutoPurgeLaunchTests.swift
  git commit -m "test(core): pin AutoPurgeJob launch-path contract

Names the exact run() invocation bootstrap() and the BGTask handler make, so
a behavior regression in the purge the launch path depends on fails under
swift test even though the app-target wiring itself isn't unit-testable.
(persist-6)"
  ```

---

### Task 8: Wire `AutoPurgeJob` into both `bootstrap()` paths (persist-6)

**Files (Modify):**
- `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift` (property block ~line 59; init ~line 103; `bootstrap()` ~line 257)
- `Apps/Lillist-macOS/Sources/AppEnvironment.swift` (property block ~line 59; init ~line 89; `bootstrap()` ~line 230)

- [ ] **Step 1: iOS — add the property and build it in `init`** — in `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift`, add the stored property next to the other stores (after `let defaultsInstaller: DefaultsInstaller` on line 59):

```swift
    /// Persist-6: hard-deletes trash older than the retention window.
    /// Run opportunistically at launch (`bootstrap()`) and from the iOS
    /// background-processing task (`runBackgroundPurge()`).
    let autoPurgeJob: AutoPurgeJob
```

  Then assign it in `init` immediately after `self.defaultsInstaller = DefaultsInstaller(filters: smartFilterStore)` (line 103) — `preferencesStore` is already a local at that point:

```swift
        self.autoPurgeJob = AutoPurgeJob(persistence: persistence, preferences: preferencesStore)
```

- [ ] **Step 2: iOS — call it from `bootstrap()`** — in `bootstrap()`, after `await notificationScheduler.bootstrap()` (line 263), add:

```swift
        // Persist-6: opportunistically clear expired trash at launch.
        // Errors are non-fatal — a failed purge must never block launch.
        _ = try? await autoPurgeJob.run()
```

- [ ] **Step 3: macOS — mirror the property, init, and bootstrap call** — in `Apps/Lillist-macOS/Sources/AppEnvironment.swift`, add the same `let autoPurgeJob: AutoPurgeJob` property (after `let defaultsInstaller: DefaultsInstaller`, line 40), assign it after `self.defaultsInstaller = DefaultsInstaller(filters: smartFilterStore)` (line 89):

```swift
        self.autoPurgeJob = AutoPurgeJob(persistence: persistence, preferences: preferencesStore)
```

  and add to `bootstrap()` after `await notificationScheduler.bootstrap()` (line 235):

```swift
        // Persist-6: opportunistically clear expired trash at launch.
        _ = try? await autoPurgeJob.run()
```

- [ ] **Step 4: Build both app targets without signing** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -8
  xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -8
  ```
  Expect: `** BUILD SUCCEEDED **` for both, no warnings.

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Apps/Lillist-iOS/Sources/App/AppEnvironment.swift Apps/Lillist-macOS/Sources/AppEnvironment.swift
  git commit -m "feat(app): run AutoPurgeJob at launch on iOS and macOS

The job shipped fully tested but nothing invoked it; expired trash never got
hard-deleted. Build it on AppEnvironment and run it (non-fatally) from both
bootstrap() paths. (persist-6)"
  ```

---

### Task 9: Register the iOS `BGProcessingTask` and submit the request (persist-6)

**Files (Modify):**
- `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift` (add `runBackgroundPurge()`)
- `Apps/Lillist-iOS/Sources/App/LillistApp.swift` (`App.init()` registration + post-launch submit)
- `Apps/Lillist-iOS/Info.plist` (background mode + permitted identifier)

- [ ] **Step 1: Add the background entry point on the iOS env** — in `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift`, add a method after `bootstrap()` (it reuses the same job):

```swift
    /// Persist-6: entry point for the iOS background-processing task.
    /// Runs the trash purge off the foreground; returns whether it
    /// completed without throwing so the `BGTask` can report success.
    func runBackgroundPurge() async -> Bool {
        do {
            _ = try await autoPurgeJob.run()
            return true
        } catch {
            return false
        }
    }
```

- [ ] **Step 2: Register the task and submit the request in `LillistApp`** — in `Apps/Lillist-iOS/Sources/App/LillistApp.swift`, add `import BackgroundTasks` at the top (after `import LillistUI`). Add an explicit `init()` to `LillistApp` that registers the handler (registration must happen before the app finishes launching), and submit a request after a successful environment load.

  Add the `import`:

```swift
import BackgroundTasks
```

  Add the `init()` immediately after the stored properties (after the `sortBinding` computed property, before `var body`).

  > **⚠️ Execution gotcha — strict-concurrency isolation of the BGTask handler.**
  > `LillistApp` is a SwiftUI `App`, so it is **implicitly `@MainActor`**, and
  > `AppEnvironment` is `@MainActor` too (`Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:17`).
  > But the closure passed to `BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)`
  > is **non-isolated and `@Sendable`** — it does NOT inherit `LillistApp`'s MainActor
  > isolation. So the `@MainActor` work (`AppEnvironment.make()` →
  > `env.runBackgroundPurge()`) must be hopped onto the MainActor **explicitly** with
  > `Task { @MainActor in … }`; a bare `Task { … }` started inside that non-isolated
  > closure runs on the generic executor and will not satisfy the MainActor isolation
  > the helper requires. Two more constraints the compiler will enforce:
  > (1) `BGTask` is **not `Sendable`**, so do not capture `task` across the actor hop
  > — call `task.setTaskCompleted(success:)` and set `task.expirationHandler` on the
  > non-isolated closure's own thread, and pass only the `Bool` result across the hop;
  > (2) set `task.expirationHandler` **before** kicking off the work `Task` so an early
  > expiration can always cancel it. The block below is written to compile under Swift 6
  > strict concurrency as-is — do not "simplify" it back to a bare `Task {}` or it will
  > fail to build (warnings are errors here).

```swift
    init() {
        // Persist-6: register the background trash-purge handler before
        // launch completes (BGTaskScheduler requires registration during
        // app init). The handler builds a short-lived AppEnvironment so it
        // can run without the foreground SwiftUI environment being alive.
        //
        // The launch-handler closure is @Sendable / non-isolated (it does
        // NOT inherit LillistApp's implicit @MainActor), and BGTask is not
        // Sendable. So we: wire expirationHandler first; run the MainActor
        // work on an explicit `Task { @MainActor in … }`; and complete the
        // task back on the closure's own (non-isolated) thread using only
        // the Bool that crosses the actor hop — never the BGTask itself.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundPurgeSchedule.taskIdentifier,
            using: nil
        ) { task in
            // `expirationHandler` and `setTaskCompleted` are on the BGTask
            // base class, so no BGProcessingTask cast is needed here.
            let work = Task { @MainActor in
                // Hop to the MainActor explicitly: both AppEnvironment.make()
                // and env.runBackgroundPurge() are @MainActor-isolated.
                let ok = await Self.runBackgroundPurge()
                Self.scheduleBackgroundPurge()
                return ok
            }
            // Set expiration before awaiting `work` so an early expiration
            // can cancel the in-flight purge. `task` stays on this
            // non-isolated thread; only the Bool result crosses the hop.
            task.expirationHandler = { work.cancel() }
            Task {
                let ok = (try? await work.value) ?? false
                task.setTaskCompleted(success: ok)
            }
        }
    }
```

  Notes on the shape above (all load-bearing for the build):
  - `Self.scheduleBackgroundPurge()` is called **inside** the `@MainActor`
    work `Task` (it is non-isolated and safe to call from MainActor) so the
    next request is queued whether or not the purge throws.
  - The outer `Task { … }` that calls `task.setTaskCompleted(success:)`
    `await`s `work.value`; `work` never throws (it returns `Bool`), so the
    `try?` is belt-and-suspenders against cancellation surfacing as an error.
  - Do not annotate the `init()` itself or add `@MainActor` to the register
    closure — `register` requires a plain `@Sendable` closure and an
    isolation annotation there is rejected.

  Add the two `static` helpers to `LillistApp` (after `uiTestResetState()`):

```swift
    /// Build a fresh environment, run the purge, tear it down. Used only by
    /// the background task — the foreground env is owned by `@State`.
    private static func runBackgroundPurge() async -> Bool {
        guard let env = try? await AppEnvironment.make() else { return false }
        return await env.runBackgroundPurge()
    }

    /// Submit the next background-processing request. Safe to call after
    /// every run; the scheduler coalesces duplicate identifiers.
    static func scheduleBackgroundPurge() {
        let request = BGProcessingTaskRequest(identifier: BackgroundPurgeSchedule.taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: BackgroundPurgeSchedule.earliestBeginInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
```

  Finally, submit the first request after a successful launch. In `loadEnvironmentIfNeeded()`, after `environment = env` (line 77), add:

```swift
            Self.scheduleBackgroundPurge()
```

- [ ] **Step 3: Add the Info.plist keys** — in `Apps/Lillist-iOS/Info.plist`, add the background mode and permitted-identifier keys inside the top-level `<dict>` (e.g. immediately before `<key>NSUserActivityTypes</key>` on line 50):

```xml
    <key>UIBackgroundModes</key>
    <array>
        <string>processing</string>
    </array>
    <key>BGTaskSchedulerPermittedIdentifiers</key>
    <array>
        <string>io.mikeydotio.Lillist.autopurge</string>
    </array>
```

  The identifier string must equal `BackgroundPurgeSchedule.taskIdentifier` — Task 6's test pins that value.

- [ ] **Step 4: Build the iOS target and confirm the registration compiles** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -10
  ```
  Expect: `** BUILD SUCCEEDED **`, no warnings. Then sanity-check the Info.plist parses:
  ```bash
  plutil -lint Apps/Lillist-iOS/Info.plist
  ```
  Expect: `Apps/Lillist-iOS/Info.plist: OK`.

- [ ] **Step 5: Run the LillistCore suite to confirm the identifier pin still holds** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "BackgroundPurgeSchedule"
  ```
  Expect: both pin tests pass (guards that the Info.plist string and the registration agree).

- [ ] **Step 6: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Apps/Lillist-iOS/Sources/App/AppEnvironment.swift Apps/Lillist-iOS/Sources/App/LillistApp.swift Apps/Lillist-iOS/Info.plist
  git commit -m "feat(ios): run trash purge from a BGProcessingTask

Register the autopurge background task during app init and submit a daily
request after launch so trash gets purged even when the app rarely runs
foreground. Identifier is pinned by BackgroundPurgeSchedule + its test.
(persist-6)"
  ```

---

### Task 10: Drive the iOS pause-reason classifier into the `pauseReason` mirror (ios-1)

**Files (Modify):**
- `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift` (`bootstrap()` ~line 277; add `startObservingPauseReason()`)
- `Apps/Lillist-macOS/Sources/AppEnvironment.swift` (`bootstrap()` ~line 251; add `startObservingPauseReason()`) — parity so the macOS dead mirror is also driven

`environment.pauseReason` is consumed by `ICloudSyncSection` (the paused-status badge and `PauseExplainerDialog`) but is never assigned — the classifier (`PauseReasonClassifier`) is built and never called. `PauseReasonClassifier.currentReason()` returns the current reason (or `nil`); the account-state stream is the natural trigger. We classify once at bootstrap and re-classify on every account-state change (the classifier reads the same `AccountStateMonitor`), keeping the mirror in step with the stream that already drives `accountState`.

- [ ] **Step 1: iOS — classify at bootstrap and on account-state changes** — in `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift`, in `bootstrap()`, after `self.accountState = await accountStateMonitor.currentState` (line 275) add a first classification, then start the observer. Insert before `startObservingAccountState()` (line 276):

```swift
        // ios-1: prime the pause-reason mirror so the sync-status badge and
        // PauseExplainerDialog read a real classification, not a stale nil.
        self.pauseReason = await pauseReasonClassifier.currentReason()
```

  and after `installCanaryLifecycleObservers()` (line 278) add:

```swift
        startObservingPauseReason()
```

  Then add the observer method after `startObservingSyncMode()` (after line 348):

```swift
    /// ios-1: re-classify the sync pause reason whenever the iCloud
    /// account state changes. The classifier reads the same
    /// `AccountStateMonitor`, so reacting to its stream keeps
    /// `pauseReason` consistent with `accountState`. `nil` means sync is
    /// active (or LocalOnly); the settings surface renders accordingly.
    private func startObservingPauseReason() {
        let monitor = self.accountStateMonitor
        let classifier = self.pauseReasonClassifier
        Task { [weak self] in
            for await _ in await monitor.stateStream {
                let reason = await classifier.currentReason()
                await MainActor.run {
                    self?.pauseReason = reason
                }
            }
        }
    }
```

- [ ] **Step 2: macOS — mirror the same wiring** — in `Apps/Lillist-macOS/Sources/AppEnvironment.swift`, in `bootstrap()`, after `self.accountState = await accountStateMonitor.currentState` (line 249) add:

```swift
        // ios-1 parity: prime the pause-reason mirror the Preferences sync
        // pane reads, so the macOS classifier stops being dead too.
        self.pauseReason = await pauseReasonClassifier.currentReason()
```

  and after `startObservingSyncMode()` (line 251) add `startObservingPauseReason()`, then add the method after `startObservingSyncMode()` (after line 279):

```swift
    /// ios-1 parity: re-classify the sync pause reason on every iCloud
    /// account-state change so the macOS sync surface mirrors the live
    /// reason rather than a stale nil.
    private func startObservingPauseReason() {
        let monitor = self.accountStateMonitor
        let classifier = self.pauseReasonClassifier
        Task { [weak self] in
            for await _ in await monitor.stateStream {
                let reason = await classifier.currentReason()
                await MainActor.run {
                    self?.pauseReason = reason
                }
            }
        }
    }
```

- [ ] **Step 3: Build both app targets** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -8
  xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -8
  ```
  Expect: `** BUILD SUCCEEDED **` for both, no warnings (confirms the `for await _ in` stream consumption and weak-self capture satisfy strict concurrency).

- [ ] **Step 4: Run the LillistCore classifier tests to confirm no regression in the seam we now depend on** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter PauseReason 2>&1 | tail -8
  ```
  Expect: the existing `PauseReasonClassifier` tests pass (we did not change `LillistCore`; this confirms the contract we wired against still holds).

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Apps/Lillist-iOS/Sources/App/AppEnvironment.swift Apps/Lillist-macOS/Sources/AppEnvironment.swift
  git commit -m "feat(app): drive PauseReasonClassifier into the pauseReason mirror

The classifier was built but never called, so environment.pauseReason stayed
nil and the sync-status badge / PauseExplainerDialog never reflected a real
reason. Classify at bootstrap and on every account-state change, on both
platforms. (ios-1)"
  ```

---

## Self-review checklist

- [ ] **persist-6** — `AutoPurgeJob` wired into both `bootstrap()` paths (Task 8) and into an iOS `BGProcessingTask` keyed on the shared `BackgroundPurgeSchedule` constant (Task 6 + Task 9). The launch-path purge behavior is proven by `AutoPurgeLaunchTests` (Task 7) under `swift test`, and the identifier/interval are pinned by `BackgroundPurgeScheduleTests` (Task 6) so the Info.plist and registration cannot drift.
- [ ] **ios-1** — `AppEnvironment.startObservingPauseReason()` (iOS) classifies via `PauseReasonClassifier` at bootstrap and on every account-state change, assigning `self.pauseReason` (Task 10). The dead mirror that `ICloudSyncSection` reads is now live.
- [ ] **ios-4** — the dead iOS `CommandMenu("Task")` block and its four orphaned `Notification.Name`s are deleted, and the file's doc comment corrected (Task 4); the iOS target still builds.
- [ ] **macos-2** — the unobserved Indent/Outdent buttons and the unobserved Find `CommandGroup` plus their four orphaned names are deleted, and `CommandNotificationObserverGuardTests` (Task 5) fails the build if any posted command notification lacks an observer.
- [ ] **logs-2** — the crash-report preview no longer claims "logs from the last ~30 seconds of the crashed run" (Task 3), because `OSLogFetcher`'s current-process scope returns nothing after a crash; the macOS pane comment now points at the observability-logging plan.
- [ ] **crumbs-3** — the crash-report preview no longer claims "anonymized verbs from your last ~50 mutations" (Task 3), because `BreadcrumbBuffer` is in-memory and empty post-crash; the toggle/plumbing stay intact for when a real on-disk buffer lands.
- [ ] **cli-1** — `Config.resolvedCalendar()` is the single source of truth, `time_zone` is validated (throws on unknown identifier), and all eight CLI date commands thread it through instead of hardcoding `Calendar.current` (Tasks 1-2), proven by `ConfigTests` and a `grep` showing zero remaining `Calendar.current` in the CLI commands.

### Cross-plan coordination notes

- **observability-logging (blind-spot)** owns the real on-disk breadcrumb/log buffer decision and the `OSLogFetcher` rework. Task 3 only removes the overpromising preview copy and adds a comment deferring to that plan — it deliberately does **not** touch `CrashReporter.submit`, the include-toggles, or `OSLogFetcher`. When observability-logging lands a durable buffer, restore the two preview sections in `CrashReportSample.preview` together with a live render.
- **breadcrumb-truthfulness (P1)** edits `Stores/TaskStore.swift`, `TagStore.swift`, `JournalStore.swift` (the `defer { recordCrumb(success: true) }` fix). This plan does not touch those stores; no file collision. (Task 8/Task 10 touch only the two app-target `AppEnvironment.swift` files and `LillistApp.swift`, which no other listed plan modifies.)
- No file in this plan's scope (`AppEnvironment.swift` ×2, both `LillistCommands.swift`, `CrashReportSample.swift`, `CrashReportingPane.swift`, `CLIBridge/Config.swift`, the eight CLI command files, `Info.plist`, and the new test files) is listed as a primary file of any other parallel plan, so there are no shared-edit collisions to sequence.
