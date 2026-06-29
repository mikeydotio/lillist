---
module: Packages/LillistUI/Sources/LillistUI/Sync
summary: "Pure-presentation sync-modal surfaces (pause, disable, migration, recovery) unified under SyncSheetRoute."
read_when: "Touching iCloud sync UI or sync-modal routing"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Sync/PauseExplainerDialog.swift
    blob: dae02594c447a8a058e4dfecf8145a405554b0fa
  - path: Packages/LillistUI/Sources/LillistUI/Sync/SyncDisableConfirmationSheet.swift
    blob: 256921bb870b9d40bc20af70f93ea73be940e790
  - path: Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationChoiceSheet.swift
    blob: 3119ede020bb8360759bc671375e9c4c1a1c0b4c
  - path: Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationConfirmationDialog.swift
    blob: cec35a30c637384550600a236608f9c5da0c3ae9
  - path: Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationProgressSheet.swift
    blob: 59d38deeade5e33c4b42e180280ef591e92bbe90
  - path: Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationRecoverySheet.swift
    blob: 94595d3885ceeeba0cb2be0b21c30a828e862b8d
  - path: Packages/LillistUI/Sources/LillistUI/Sync/SyncSheetRoute.swift
    blob: 1cadc05f00c4d440a2b7ff204152a0b3ca0ac2fd
references_modules: [Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 99321d774840d17affd02fe2ac63b01b3d8cbec3
---

# Module: Packages/LillistUI/Sources/LillistUI/Sync

## Purpose

Provides the complete set of pure-presentation SwiftUI surfaces for the iCloud sync mode lifecycle: pause-state explanation, disable confirmation, migration choice, second-tap destructive confirmation, live migration progress, and crash-recovery. All six modal views are stateless presenters — hosts pass data and action closures, this module renders. The `SyncSheetRoute` router enum is the module's architectural keystone: it funnels every sync modal through a single `.sheet(item:)` binding, eliminating a SwiftUI multiple-presentation-modifier conflict that previously caused the Settings pane to collapse. Without this module, both platform layers would scatter sync modal logic across their own presentation stacks, re-introducing the clobbering bug and duplicating destructive-operation copy.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Direction` | enum | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationConfirmationDialog.swift:8` | `Sendable` enum with two cases tagging the destructive sync direction; drives `title`/`message` copy on the parent confirmation dialog. |
| `PauseExplainerDialog` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/PauseExplainerDialog.swift:17` | Renders per-PauseReason sync-pause explanation; "Disable Sync" option appears only for `.accountChanged`; `onDisableSync` defaults to `{}`. |
| `RainbowProgressBar` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationProgressSheet.swift:103` | Inset spectrum progress bar; clamps `value` to [0,1]; uses `.accessibilityRepresentation` to expose a native ProgressView for VoiceOver. |
| `SyncDisableConfirmationSheet` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncDisableConfirmationSheet.swift:6` | Confirmation sheet for disabling iCloud Sync; presents sync-first vs disable-now paths; callers wire three closures, no state owned. |
| `SyncMigrationChoiceSheet` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationChoiceSheet.swift:9` | Full-screen choice sheet for enabling sync from LocalOnly; surfaces two destructive options plus Cancel; no state owned. |
| `SyncMigrationConfirmationDialog` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationConfirmationDialog.swift:7` | Second-tap confirmation dialog; `title` and `message` are `public var String` so hosts can extract them for `.confirmationDialog` without rendering the view. |
| `SyncMigrationProgressSheet` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationProgressSheet.swift:13` | Full-screen migration progress renderer; driven by `MigrationPhase`; Done button visible only on `.completed`; progress bar shown only for phases carrying a Double. |
| `SyncMigrationRecoverySheet` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationRecoverySheet.swift:8` | Launch-time recovery sheet for interrupted migrations; `detailText(for:)` is `public nonisolated static` for testability; adds disk-space hint when `failureReason` contains "insufficientDiskSpace". |
| `SyncSheetRoute` | enum | `Packages/LillistUI/Sources/LillistUI/Sync/SyncSheetRoute.swift:14` | Callers may bind any case to `.sheet(item:)`; at most one sheet is ever presented, and `.progress`'s `id` stays constant across phase changes so the sheet updates in place. `Packages/LillistUI/Sources/LillistUI/Sync/SyncSheetRoute.swift:14-40` |
| `afterToggle` | func | `Packages/LillistUI/Sources/LillistUI/Sync/SyncSheetRoute.swift:37` | Returns `.choice` when `on` is true, `.disable` when false; callers need not know which route maps to which toggle state. `Packages/LillistUI/Sources/LillistUI/Sync/SyncSheetRoute.swift:37-39` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Sync.Direction -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.Direction -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.PauseExplainerDialog -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.RainbowProgressBar -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationChoiceSheet -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationProgressSheet -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationRecoverySheet -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationRecoverySheet -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.body -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.destructiveOption -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.rainbowCard (calls)`

## Type notes

All six sheet/dialog views are pure-presentation `struct`s with no `@State` and no `.task`; all data and action closures arrive via `init` so hosts fully control lifecycle (`Packages/LillistUI/Sources/LillistUI/Sync/PauseExplainerDialog.swift:17-33`, `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationProgressSheet.swift:11-18`).

`SyncSheetRoute` is `public enum` conforming to both `Equatable` and `Identifiable`, allowing it to drive `.sheet(item:)` directly (`Packages/LillistUI/Sources/LillistUI/Sync/SyncSheetRoute.swift:14`). The `.progress(MigrationPhase)` case's `id` returns the constant string `"progress"` regardless of the associated phase value — a deliberate invariant that keeps the sheet alive across phase updates instead of dismissing and re-presenting (`Packages/LillistUI/Sources/LillistUI/Sync/SyncSheetRoute.swift:30-31`).

`SyncMigrationRecoverySheet.detailText(for:)` is `public nonisolated static`, enabling test code to call it without crossing the `@MainActor` boundary (`Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationRecoverySheet.swift:67`).

`SyncMigrationConfirmationDialog.Direction` is `Sendable` for safe cross-actor propagation (`Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationConfirmationDialog.swift:8`).

`RainbowProgressBar` is module-internal (`struct`, no `public`), used only by `SyncMigrationProgressSheet` (`Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationProgressSheet.swift:109-127`).

## External deps

- LillistCore — imported
- SwiftUI — imported

## Gotchas

SwiftUI multiple-modifier conflict: before `SyncSheetRoute` existed, both platform wrappers stacked several `.sheet`/`.fullScreenCover` modifiers on the same view; SwiftUI silently honors only the last one per style, so presenting an earlier modal was clobbered — and, nested inside the Settings sheet, the failed presentation cascaded up and tore down all of Settings (the 'Disable iCloud sheet flashes then dismisses, taking Settings with it' bug). `Packages/LillistUI/Sources/LillistUI/Sync/SyncSheetRoute.swift:6-13`.

`.progress` case uses a constant `id` string ("progress") regardless of the inner `MigrationPhase` value; this is intentional so that streaming a new phase into the binding updates the presented sheet in place rather than triggering a dismiss/re-present cycle on every progress tick. `Packages/LillistUI/Sources/LillistUI/Sync/SyncSheetRoute.swift:22-33`.
