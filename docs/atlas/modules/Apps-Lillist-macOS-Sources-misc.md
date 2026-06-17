---
module: "Apps/Lillist-macOS/Sources (misc)"
summary: "macOS app shell — @main scene graph, root @Observable environment, AppKit bridges, crash/Spotlight/Services hosts"
read_when: "macOS app shell wiring or launch sequence"
sources:
  - path: Apps/Lillist-macOS/Sources/AppDelegate.swift
    blob: 62ce4ca17340759272beab7879d10fce70f392bb
  - path: Apps/Lillist-macOS/Sources/AppEnvironment.swift
    blob: 811902651b2e50baf715b11b479a1680895bc210
  - path: Apps/Lillist-macOS/Sources/CrashReporterHost.swift
    blob: b3a56574761886ab64c2efdb80bab618ec92c82e
  - path: Apps/Lillist-macOS/Sources/Editor/EditorOpenDecision.swift
    blob: 886dc8df7fdd02054ac98860626e6748af72fda2
  - path: Apps/Lillist-macOS/Sources/Editor/OpenTaskEditorAction.swift
    blob: c8160a65773bdd5635392b0308a2a16dd16c17ba
  - path: Apps/Lillist-macOS/Sources/Indexing/IndexingMappers.swift
    blob: 8ec987eef9c37edd3c6abde3093dac44962e0044
  - path: Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift
    blob: add637f94bf65575631a2b81dc0f1cba26977bb0
  - path: Apps/Lillist-macOS/Sources/LillistApp.swift
    blob: 129004c268f7d30a958bea8e39249381c5fdd209
  - path: Apps/Lillist-macOS/Sources/MailtoTransport.swift
    blob: 62d6df19a2ee52c3dfa72c411577dd2e4dd94d22
  - path: Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift
    blob: 02305835ca157cd328fca49ebd3ce7147f10c615
  - path: Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift
    blob: e252864f910909a073621b494fddf7d062eade3f
  - path: Apps/Lillist-macOS/Sources/Persistence/UIStatePersistence.swift
    blob: 324a7b17096296dc7dafb6eb869e19312bc3ead7
  - path: Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift
    blob: 7fbe83aa6c8cda947dd2df8601c8b2166e107e4a
  - path: Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift
    blob: 90274bef31060bca2bee37d3cd550a68dc1fca93
references_modules: [Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-Sync-chunk-2, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistUI-Sources-LillistUI-misc, Packages-LillistUI-Sources-LillistUI-Onboarding, Packages-LillistUI-Sources-LillistUI-CrashReporting, Packages-LillistUI-Sources-LillistUI-Sync, Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Apps-Lillist-macOS-Sources-Views, Apps-Lillist-macOS-Sources-Commands, Apps-Lillist-macOS-Sources-Preferences, Apps-Lillist-macOS-Sources-Hotkey]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Apps/Lillist-macOS/Sources (misc)

## Purpose

The macOS application shell: the `@main` SwiftUI scene graph, the single
`@Observable` dependency container every view reads, and the AppKit bridges
SwiftUI cannot express (dock badge/menu, Spotlight index, Services provider,
global-hotkey wiring). `AppEnvironment` is the spine — it constructs every
LillistCore store/scheduler once and hands them down; `LillistApp` orchestrates
its async load, then bootstraps crash detection, onboarding, and the menu-bar
scene around it. Remove this module and there is no macOS app.

## Public API

This is an app target; symbols are internal-to-target by default. The cross-app
public surface is the `MailtoTransport` crash transport.

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `EditorOpenDecision` | enum | `Apps/Lillist-macOS/Sources/Editor/EditorOpenDecision.swift:16` | Pure value-math: `decide(isOpen:request:)` returns present/retarget/noop for panel routing |
| `EditorOpenRequest` | enum | `Apps/Lillist-macOS/Sources/Editor/EditorOpenDecision.swift:11` | Input to `EditorOpenDecision.decide`; `.quickCapture` or `.existing(UUID)` |
| `MailtoTransport` | struct | `Apps/Lillist-macOS/Sources/MailtoTransport.swift:10` | `CrashReportTransport` impl; writes a `.lillistcrash` temp file and opens a `mailto:` URL |
| `OpenTaskEditorActionKey` | struct | `Apps/Lillist-macOS/Sources/Editor/OpenTaskEditorAction.swift:12` | `EnvironmentKey` + `EnvironmentValues` extension; closure injected by `LillistApp`, consumed by task rows |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `AppEnvironment` | class | `Apps/Lillist-macOS/Sources/AppEnvironment.swift:14` | Root `@Observable` container; owns every store, scheduler, crash/diagnostic/migration object |
| `AppEnvironment.make` | func | `Apps/Lillist-macOS/Sources/AppEnvironment.swift:235` | Async constructor — loads the Core Data store and reads sync mode before any view exists |
| `AppEnvironment.bootstrap` | func | `Apps/Lillist-macOS/Sources/AppEnvironment.swift:277` | One-shot post-load wiring: diagnostics, scheduler, auto-purge, account/sync observers |
| `LillistApp` | struct | `Apps/Lillist-macOS/Sources/LillistApp.swift:6` | `@main` App; WindowGroup + Settings + MenuBarExtra scenes, `loadEnvironmentIfNeeded()` |
| `AppDelegate` | class | `Apps/Lillist-macOS/Sources/AppDelegate.swift:14` | Owns AppKit bridge objects (quick-capture panel, dock badge/menu, Sparkle updater) |
| `AppDelegate.bootstrap` | func | `Apps/Lillist-macOS/Sources/AppDelegate.swift:54` | Wires hotkey callback, dock badge, Services provider, Spotlight indexer post-load |
| `CrashReporterHost` | struct | `Apps/Lillist-macOS/Sources/CrashReporterHost.swift:7` | Root view that surfaces the crash sheet via `.sheet(item:)` on a stale canary |
| `OnboardingPresentationModifier` | struct | `Apps/Lillist-macOS/Sources/LillistApp.swift:140` | Drives onboarding / iCloud-unavailable / migration-recovery sheets over main content |
| `IndexingService` | class | `Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift:17` | Pushes tasks into Spotlight; re-indexes on every Core Data save (idempotent `start()`) |
| `IndexingMappers` | enum | `Apps/Lillist-macOS/Sources/Indexing/IndexingMappers.swift:10` | Pure `CSSearchableItem` mappers, co-compiled for tests without `AppEnvironment` |
| `UIStatePersistence` | class | `Apps/Lillist-macOS/Sources/Persistence/UIStatePersistence.swift:6` | Per-machine UI state (sidebar selection, sort, task selection) in UserDefaults; not synced |
| `LillistServicesProvider` | class | `Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift:14` | "Add to Lillist as task" Services handler; creates a task from selected text |
| `MenuBarExtraScene` | struct | `Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift:22` | MenuBarExtra scene with `isInserted:` runtime toggle; hosts `TodayPopoverView` |
| `OnboardingSheet` | struct | `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift:22` | First-launch sheet; takes explicit LillistCore deps via init, not `@Environment` |
| `TodayPopoverView` | struct | `Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift:6` | Menu-bar popover listing the "Today" smart-filter evaluate output |

## Relationships

- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (owns)` — `Apps/Lillist-macOS/Sources/AppEnvironment.swift:17`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (owns)` — `Apps/Lillist-macOS/Sources/AppEnvironment.swift:87`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore (owns)` — `Apps/Lillist-macOS/Sources/AppEnvironment.swift:99`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator (owns)` — `Apps/Lillist-macOS/Sources/AppEnvironment.swift:215`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.AccountStateMonitor (owns)` — `Apps/Lillist-macOS/Sources/AppEnvironment.swift:110`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler (owns)` — `Apps/Lillist-macOS/Sources/AppEnvironment.swift:134`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (owns)` — `Apps/Lillist-macOS/Sources/AppEnvironment.swift:163`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticLog (owns)` — `Apps/Lillist-macOS/Sources/AppEnvironment.swift:181`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Apps-Lillist-macOS-Sources-Hotkey.GlobalHotkeyMonitor (owns)` — `Apps/Lillist-macOS/Sources/AppEnvironment.swift:108`
- `Apps-Lillist-macOS-Sources-misc.MailtoTransport -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReportTransport (conforms-to)` — `Apps/Lillist-macOS/Sources/MailtoTransport.swift:10`
- `Apps-Lillist-macOS-Sources-misc.MailtoTransport -> Packages-LillistCore-Sources-LillistCore-misc.FileSaveTransport (calls)` — `Apps/Lillist-macOS/Sources/MailtoTransport.swift:18`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-misc.AppDelegate (owns)` — `Apps/Lillist-macOS/Sources/LillistApp.swift:7`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-Views.RootSplitView (calls)` — `Apps/Lillist-macOS/Sources/LillistApp.swift:89`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-Commands.LillistCommands (calls)` — `Apps/Lillist-macOS/Sources/LillistApp.swift:38`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-Preferences.PreferencesWindow (calls)` — `Apps/Lillist-macOS/Sources/LillistApp.swift:45`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-misc.CrashReporterHost (calls)` — `Apps/Lillist-macOS/Sources/LillistApp.swift:82`
- `Apps-Lillist-macOS-Sources-misc.AppDelegate -> Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePanelController (owns)` — `Apps/Lillist-macOS/Sources/AppDelegate.swift:15`
- `Apps-Lillist-macOS-Sources-misc.AppDelegate -> Apps-Lillist-macOS-Sources-misc.LillistServicesProvider (owns)` — `Apps/Lillist-macOS/Sources/AppDelegate.swift:87`
- `Apps-Lillist-macOS-Sources-misc.AppDelegate -> Apps-Lillist-macOS-Sources-misc.IndexingService (owns)` — `Apps/Lillist-macOS/Sources/AppDelegate.swift:93`
- `Apps-Lillist-macOS-Sources-misc.IndexingService -> Apps-Lillist-macOS-Sources-misc.IndexingMappers (calls)` — `Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift:64`
- `Apps-Lillist-macOS-Sources-misc.OnboardingSheet -> Packages-LillistUI-Sources-LillistUI-Onboarding.OnboardingContent (calls)` — `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift:40`
- `Apps-Lillist-macOS-Sources-misc.CrashReporterHost -> Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportSheet (calls)` — `Apps/Lillist-macOS/Sources/CrashReporterHost.swift:31`
- `Apps-Lillist-macOS-Sources-misc.OnboardingPresentationModifier -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationRecoverySheet (calls)` — `Apps/Lillist-macOS/Sources/LillistApp.swift:177`
- `Apps-Lillist-macOS-Sources-misc.OnboardingPresentationModifier -> Packages-LillistUI-Sources-LillistUI-Onboarding.ICloudUnavailableScreen (calls)` — `Apps/Lillist-macOS/Sources/LillistApp.swift:156`
- `Apps-Lillist-macOS-Sources-misc.TodayPopoverView -> Packages-LillistUI-Sources-LillistUI-Components.TaskRowView (calls)` — `Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift:24`
- `Apps-Lillist-macOS-Sources-misc.TodayPopoverView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.LillistColor (reads)` — `Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift:15`
- `Apps-Lillist-macOS-Sources-misc.LillistServicesProvider -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)` — `Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift:49`

## Type notes

`AppEnvironment` is `@MainActor @Observable`; `make()` is the only constructor
(private `init`), called from `LillistApp.loadEnvironmentIfNeeded()`
(`Apps/Lillist-macOS/Sources/LillistApp.swift:107`). It mirrors actor-isolated
state (`accountState`, `currentSyncMode`, `pauseReason`) onto `@Observable`
properties via `for await` streams so SwiftUI reacts without polling
(`Apps/Lillist-macOS/Sources/AppEnvironment.swift:323`).

`AppDelegate` holds the only strong references to `LillistServicesProvider` and
`IndexingService` (`NSApp.servicesProvider` is unowned), so their lifetime is
the app session (`Apps/Lillist-macOS/Sources/AppDelegate.swift:87`). It keeps a
`weak` link to `AppEnvironment` and a `pinnedFilterCache` snapshot refreshed on
every Core Data save for the synchronous dock-menu callback
(`Apps/Lillist-macOS/Sources/AppDelegate.swift:21`).

`CrashReporterHost` binds the sheet to model presence via `.sheet(item:)` so an
empty modal is structurally impossible
(`Apps/Lillist-macOS/Sources/CrashReporterHost.swift:12`). The canary is armed
lazily by this host's `.task`, not by `AppEnvironment.bootstrap()`, to avoid a
self-triggered report on every launch
(`Apps/Lillist-macOS/Sources/AppEnvironment.swift:302`).

`EditorOpenDecision` is pure value-math with no AppKit dependency —
`decide(isOpen:request:)` is the testable seam for panel routing. A
`.quickCapture` request while the panel is open resolves to `.noop`; an
`.existing(UUID)` request resolves to `.retarget` so no second panel spawns
(`Apps/Lillist-macOS/Sources/Editor/EditorOpenDecision.swift:24`).

`OpenTaskEditorActionKey` is injected at `LillistApp.content` via
`.environment(\.openTaskEditorAction)` and calls
`appDelegate.quickCapturePanel?.open(taskID:)`, keeping the panel reference
out of child views (`Apps/Lillist-macOS/Sources/LillistApp.swift:91`).

`UIStatePersistence` is per-machine and deliberately unsynced;
`persistenceKey(for:)` mirrors `TaskListView.sourceKey` so sort and
task-selection dictionaries share one source identity
(`Apps/Lillist-macOS/Sources/Persistence/UIStatePersistence.swift:85`).

## External deps

- SwiftUI / AppKit — scene graph plus the AppKit bridges (`NSApp`, dock, Services)
- CoreSpotlight — `CSSearchableItem` / `CSSearchableIndex` for the task index
- CloudKit — `CKContainer` for the account-status provider
- Sparkle — `SPUStandardUpdaterController` for the "Check for Updates…" menu item

## Gotchas

- Dock menu reads `pinnedFilterCache`, not the store, because `applicationDockMenu(_:)` fires synchronously on right-click (`Apps/Lillist-macOS/Sources/AppDelegate.swift:18`).
- Indexing errors log the error TYPE only as `.public` — a full `localizedDescription` can leak store paths / attribute values (`Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift:71`).
- `MenuBarExtraScene` is declared unconditionally with an optional `AppEnvironment?` because SceneBuilder type-checks optional Scenes poorly (`Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift:16`).
- `OnboardingSheet` takes deps via init, never `@Environment` — sheet presentation forks a fresh environment chain that would crash on first paint (`Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift:17`).
