---
module: "Apps/Lillist-macOS/Sources (misc)"
summary: "macOS app shell — @main scene graph, root @Observable environment, AppKit bridges, crash/Spotlight/Services hosts"
read_when: macOS app shell wiring
sources:
  - path: Apps/Lillist-macOS/Sources/AppDelegate.swift
    blob: 62ce4ca17340759272beab7879d10fce70f392bb
  - path: Apps/Lillist-macOS/Sources/AppEnvironment.swift
    blob: 22f0a3d452bda96525896b47d9c461ea385e73dd
  - path: Apps/Lillist-macOS/Sources/CrashReporterHost.swift
    blob: b3a56574761886ab64c2efdb80bab618ec92c82e
  - path: Apps/Lillist-macOS/Sources/Indexing/IndexingMappers.swift
    blob: 8ec987eef9c37edd3c6abde3093dac44962e0044
  - path: Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift
    blob: add637f94bf65575631a2b81dc0f1cba26977bb0
  - path: Apps/Lillist-macOS/Sources/LillistApp.swift
    blob: dc3f2c22592a35f5b813d658ad3346d6e45d9135
  - path: Apps/Lillist-macOS/Sources/MailtoTransport.swift
    blob: 62d6df19a2ee52c3dfa72c411577dd2e4dd94d22
  - path: Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift
    blob: 02305835ca157cd328fca49ebd3ce7147f10c615
  - path: Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift
    blob: e252864f910909a073621b494fddf7d062eade3f
  - path: Apps/Lillist-macOS/Sources/Persistence/UIStatePersistence.swift
    blob: 324a7b17096296dc7dafb6eb869e19312bc3ead7
  - path: Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift
    blob: bc0fa7c4100a95e20333e55990bb8aa9262f532b
  - path: Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift
    blob: 90274bef31060bca2bee37d3cd550a68dc1fca93
references_modules: [Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistUI-Sources-LillistUI-misc, Apps-Lillist-macOS-Sources-Views-misc, Apps-Lillist-macOS-Sources-Commands, Apps-Lillist-macOS-Sources-Preferences, Apps-Lillist-macOS-Sources-Hotkey]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
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
| `MailtoTransport` | struct | `Apps/Lillist-macOS/Sources/MailtoTransport.swift:10` | `CrashReportTransport` impl; writes a `.lillistcrash` temp file and opens a `mailto:` URL |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `AppEnvironment` | class | `Apps/Lillist-macOS/Sources/AppEnvironment.swift:14` | Root `@Observable` container; owns every store, scheduler, crash/diagnostic/migration object |
| `AppEnvironment.make()` | func | `Apps/Lillist-macOS/Sources/AppEnvironment.swift:229` | Async constructor — loads the Core Data store before any view exists |
| `AppEnvironment.bootstrap()` | func | `Apps/Lillist-macOS/Sources/AppEnvironment.swift:271` | One-shot post-load wiring: diagnostics, scheduler, auto-purge, account/sync observers |
| `LillistApp` | struct | `Apps/Lillist-macOS/Sources/LillistApp.swift:6` | `@main` App; WindowGroup + Settings + MenuBarExtra scenes, `loadEnvironmentIfNeeded()` |
| `AppDelegate` | class | `Apps/Lillist-macOS/Sources/AppDelegate.swift:14` | Owns AppKit bridge objects (quick-capture panel, dock badge/menu, Sparkle updater) |
| `AppDelegate.bootstrap()` | func | `Apps/Lillist-macOS/Sources/AppDelegate.swift:54` | Wires hotkey callback, dock badge, Services provider, Spotlight indexer post-load |
| `CrashReporterHost` | struct | `Apps/Lillist-macOS/Sources/CrashReporterHost.swift:7` | Root view that surfaces the crash sheet via `.sheet(item:)` on a stale canary |
| `OnboardingPresentationModifier` | struct | `Apps/Lillist-macOS/Sources/LillistApp.swift:137` | Drives onboarding / iCloud-unavailable / migration-recovery sheets over main content |
| `IndexingService` | class | `Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift:17` | Pushes tasks into Spotlight; re-indexes on every Core Data save (idempotent `start()`) |
| `IndexingMappers` | enum | `Apps/Lillist-macOS/Sources/Indexing/IndexingMappers.swift:10` | Pure `CSSearchableItem` mappers, co-compiled for tests without `AppEnvironment` |
| `UIStatePersistence` | class | `Apps/Lillist-macOS/Sources/Persistence/UIStatePersistence.swift:6` | Per-machine UI state (sidebar selection, sort, task selection) in UserDefaults; not synced |
| `LillistServicesProvider` | class | `Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift:14` | "Add to Lillist as task" Services handler; creates a task from selected text |
| `MenuBarExtraScene` | struct | `Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift:22` | MenuBarExtra scene with `isInserted:` runtime toggle; hosts `TodayPopoverView` |
| `OnboardingSheet` | struct | `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift:22` | First-launch sheet; takes explicit LillistCore deps via init, not `@Environment` |
| `TodayPopoverView` | struct | `Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift:6` | Menu-bar popover listing the "Today" smart-filter evaluate output |

## Relationships

- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-misc.PersistenceController (owns)`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-misc.TaskStore (owns)`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-misc.MigrationCoordinator (owns)`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-misc.CrashReporter (owns)`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-misc.NotificationScheduler (owns)`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Apps-Lillist-macOS-Sources-Hotkey.GlobalHotkeyMonitor (owns)`
- `Apps-Lillist-macOS-Sources-misc.MailtoTransport -> Packages-LillistCore-Sources-LillistCore-misc.CrashReportTransport (conforms-to)`
- `Apps-Lillist-macOS-Sources-misc.MailtoTransport -> Packages-LillistCore-Sources-LillistCore-misc.FileSaveTransport (calls)`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-misc.AppDelegate (owns)`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-Views-misc.RootSplitView (calls)`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-Commands.LillistCommands (calls)`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-Preferences.PreferencesWindow (calls)`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-misc.CrashReporterHost (calls)`
- `Apps-Lillist-macOS-Sources-misc.AppDelegate -> Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePanelController (owns)`
- `Apps-Lillist-macOS-Sources-misc.AppDelegate -> Apps-Lillist-macOS-Sources-misc.LillistServicesProvider (owns)`
- `Apps-Lillist-macOS-Sources-misc.AppDelegate -> Apps-Lillist-macOS-Sources-misc.IndexingService (owns)`
- `Apps-Lillist-macOS-Sources-misc.IndexingService -> Apps-Lillist-macOS-Sources-misc.IndexingMappers (calls)`
- `Apps-Lillist-macOS-Sources-misc.OnboardingSheet -> Packages-LillistUI-Sources-LillistUI-misc.OnboardingContent (calls)`
- `Apps-Lillist-macOS-Sources-misc.CrashReporterHost -> Packages-LillistUI-Sources-LillistUI-misc.CrashReportSheet (calls)`
- `Apps-Lillist-macOS-Sources-misc.TodayPopoverView -> Packages-LillistUI-Sources-LillistUI-misc.TaskRowView (calls)`
- `Apps-Lillist-macOS-Sources-misc.LillistServicesProvider -> Packages-LillistCore-Sources-LillistCore-misc.TaskStore (calls)`

## Type notes

`AppEnvironment` is `@MainActor @Observable`; `make()` is the only constructor
(private `init`), called from `LillistApp.loadEnvironmentIfNeeded()`
(`Apps/Lillist-macOS/Sources/LillistApp.swift:104`). It mirrors actor-isolated
state (`accountState`, `currentSyncMode`, `pauseReason`) onto `@Observable`
properties via `for await` streams so SwiftUI reacts without polling
(`Apps/Lillist-macOS/Sources/AppEnvironment.swift:319`).

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
(`Apps/Lillist-macOS/Sources/AppEnvironment.swift:295`).

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
