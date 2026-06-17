---
module: Packages/LillistUI/Sources/LillistUI/Sync
summary: "Pure-presentation SwiftUI sheets and dialogs for the iCloud sync-mode change and pause-explainer flows"
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
references_modules: [Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-Sync-chunk-2, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-Theme-chunk-2]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Packages/LillistUI/Sources/LillistUI/Sync

## Purpose

The cross-platform SwiftUI surface for the iCloud sync-mode change lifecycle (Plan 21): explaining why sync paused, choosing a destructive migration direction, confirming it, watching it run, and recovering from a crashed migration. Every view here is *pure presentation* — data comes in via `init`, actions go out via closures; no `@State`, `.task`, or environment coupling. That split lets the iOS Settings section and macOS Preferences pane own all lifecycle/`AppEnvironment` wiring while these views stay snapshot-testable with frozen inputs.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `PauseExplainerDialog` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/PauseExplainerDialog.swift:17` | Dialog for a `PauseReason`; `onDisableSync` surfaced only for `.accountChanged` |
| `SyncDisableConfirmationSheet` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncDisableConfirmationSheet.swift:6` | Sync-off confirmation: sync-one-more-time vs disconnect-now vs cancel |
| `SyncMigrationChoiceSheet` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationChoiceSheet.swift:9` | Enable-from-LocalOnly chooser: replace-iCloud vs replace-local vs cancel |
| `SyncMigrationConfirmationDialog` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationConfirmationDialog.swift:7` | Second-tap destructive confirm; copy keyed off `Direction`; also exposes `title`/`message` for native `.confirmationDialog` |
| `SyncMigrationConfirmationDialog.Direction` | enum | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationConfirmationDialog.swift:8` | `.replaceICloud` / `.replaceLocal`; `Sendable`, carried by hosts as pending state |
| `SyncMigrationProgressSheet` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationProgressSheet.swift:11` | Renders a single `MigrationPhase`; `onDismissAfterCompletion` only wired on `.completed` |
| `SyncMigrationRecoverySheet` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationRecoverySheet.swift:8` | Crash-recovery sheet from a non-idle `MigrationJournal`: restore-backup vs retry |
| `SyncMigrationRecoverySheet.detailText(for:)` | static func | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationRecoverySheet.swift:67` | `public nonisolated` pure narrative; adds a low-disk-space hint when the journal reason names `insufficientDiskSpace` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `RainbowProgressBar` | struct | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationProgressSheet.swift:109` | The only sync-specific component; sunken track + spectrum fill, clamps value to 0...1, wraps a hidden `ProgressView` for accessibility |
| `destructiveOption(action:title:detail:)` | func | `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationChoiceSheet.swift:68` | Renders each erase-choice as an action-orange Rainbow card; gravity reads from color, not a red wash |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Sync.PauseExplainerDialog -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.PauseReason (reads)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationProgressSheet -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationPhase (reads)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationRecoverySheet -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationJournal (reads)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationRecoverySheet -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.ModeTransitionOp (reads)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationChoiceSheet -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowPalette (reads)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationProgressSheet -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowGradient (reads)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationChoiceSheet -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistTypography (reads)`
- `Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationConfirmationDialog -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistTypography (reads)`

## Type notes

All six views are value-type SwiftUI `View`s with no stored state beyond their `init` inputs; hosts own presentation (`.sheet` / `.fullScreenCover`) and lifecycle. The `MigrationPhase` consumed by `SyncMigrationProgressSheet` is sourced from `MigrationCoordinator.progressStream` (an `AsyncStream`) by the host, not subscribed to here — this view re-renders per emitted phase. `SyncMigrationRecoverySheet.detailText(for:)` and `operationDescription(_:)` are `nonisolated static` so XCTest can exercise the copy logic off the `MainActor`. User-visible copy is localized via `String(localized:bundle:.module)` and must stay verbatim-aligned across iOS/macOS (snapshot-guarded).

`SyncMigrationConfirmationDialog` exposes `title` and `message` as `public var String` computed properties so a host can bind them into SwiftUI's native `.confirmationDialog` modifier; the `body` is an alternate full-panel rendering path — both are valid presentation routes for the same `Direction` value.

## External deps

- SwiftUI — every view; `GeometryReader`, `Capsule`, `ProgressView`, `accessibilityRepresentation`
- LillistCore — `PauseReason`, `MigrationPhase`, `MigrationJournal`, `ModeTransitionOp` value types (imported by the phase/journal/pause views)

## Gotchas

- `PauseExplainerDialog` only shows the "Disable Sync" button when `reason == .accountChanged`; all other reasons omit it (`Packages/LillistUI/Sources/LillistUI/Sync/PauseExplainerDialog.swift:57`).
- `SyncMigrationProgressSheet` shows `RainbowProgressBar` only for `.erasingICloud`, `.uploading`, and `.downloading` — the only phases carrying an associated `Double` progress value (`Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationProgressSheet.swift:95`).
- The `.completed` phase is a sanctioned rainbow moment (full-gradient checkmark + `.rainbow(.green)` Done button); no other phase in this module uses the full gradient (`Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationProgressSheet.swift:26`).
