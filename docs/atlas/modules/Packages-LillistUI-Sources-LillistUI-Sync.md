---
module: Packages/LillistUI/Sources/LillistUI/Sync
summary: "Pure-presenter modal sheets and dialogs for all iCloud sync management flows."
read_when: "Touching iCloud sync mode UI"
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
    blob: 700e0f1f0739980cf8ee8c6c295b8f65f0f65539
  - path: Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationRecoverySheet.swift
    blob: 94595d3885ceeeba0cb2be0b21c30a828e862b8d
references_modules: [Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/Sync

## Purpose

Provides the complete set of modal UI surfaces that gate or describe every iCloud sync mode transition: a pause explainer dialog, a disable-sync confirmation sheet, the three-step enable-sync migration sequence (choice → confirmation → progress), and a crash-recovery sheet for interrupted migrations. All views are pure presenters — no @State, no .task, no env coupling — so the host owns the state machine and these views just render phases and surface closures. Without this module, the app would have no user-facing story for sync failures, destructive migrations, or mid-migration crashes.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Direction` | enum | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationConfirmationDialog.swift:8` | `Sendable` enum with two cases tagging the destructive sync direction; drives `title`/`message` copy on the parent confirmation dialog. |
| `PauseExplainerDialog` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/PauseExplainerDialog.swift:17` | Renders per-PauseReason sync-pause explanation; "Disable Sync" option appears only for `.accountChanged`; `onDisableSync` defaults to `{}`. |
| `RainbowProgressBar` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationProgressSheet.swift:109` | Inset spectrum progress bar; clamps `value` to [0,1]; uses `.accessibilityRepresentation` to expose a native ProgressView for VoiceOver. |
| `SyncDisableConfirmationSheet` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncDisableConfirmationSheet.swift:6` | Confirmation sheet for disabling iCloud Sync; presents sync-first vs disable-now paths; callers wire three closures, no state owned. |
| `SyncMigrationChoiceSheet` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationChoiceSheet.swift:9` | Full-screen choice sheet for enabling sync from LocalOnly; surfaces two destructive options plus Cancel; no state owned. |
| `SyncMigrationConfirmationDialog` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationConfirmationDialog.swift:7` | Second-tap confirmation dialog; `title` and `message` are `public var String` so hosts can extract them for `.confirmationDialog` without rendering the view. |
| `SyncMigrationProgressSheet` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationProgressSheet.swift:11` | Full-screen migration progress renderer; driven by `MigrationPhase`; Done button visible only on `.completed`; progress bar shown only for phases carrying a Double. |
| `SyncMigrationRecoverySheet` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationRecoverySheet.swift:8` | Launch-time recovery sheet for interrupted migrations; `detailText(for:)` is `public nonisolated static` for testability; adds disk-space hint when `failureReason` contains "insufficientDiskSpace". |

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
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationProgressSheet -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationRecoverySheet -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationRecoverySheet -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.body -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync.destructiveOption -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.rainbowCard (calls)`

## Type notes

All six views are pure presenters: no @State, no .task, no environment reads. Callers supply all data and closures at init time, enabling IOSScreenTourTests to render them with frozen mock data. Views are implicitly @MainActor as SwiftUI Views; SyncMigrationRecoverySheet.detailText(for:) is explicitly `nonisolated static` to remain callable from test and background contexts without a main-actor hop (Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationRecoverySheet.swift:67). SyncMigrationProgressSheet binds to `MigrationPhase` from LillistCore and `MigrationJournal`/`ModeTransitionOp` are consumed by SyncMigrationRecoverySheet — both are value types, so the views hold no managed-object references. RainbowProgressBar is internal (no `public` modifier despite the assignment listing it as public) and is only instantiated from SyncMigrationProgressSheet.body (Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationProgressSheet.swift:54).

## External deps

- LillistCore — imported
- SwiftUI — imported

## Gotchas

SyncMigrationConfirmationDialog exposes `title` and `message` as `public var String` (not inside body) so hosts can pass them directly to `.confirmationDialog` title/message params without embedding the view — Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationConfirmationDialog.swift:23-37. SyncMigrationRecoverySheet.detailText(for:) is `public nonisolated static` so tests and non-main-actor callers can invoke it without a main-actor dispatch hop — Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationRecoverySheet.swift:67. PauseExplainerDialog's "Disable Sync" button only renders for `.accountChanged`; the `onDisableSync` closure defaults to `{}` so hosts that never encounter that reason can omit it safely — Packages/LillistUI/Sources/LillistUI/Sync/PauseExplainerDialog.swift:26,57.
