---
module: "Packages/LillistCore/Sources/LillistCore/Sync (chunk 2)"
summary: "Observable CloudKit sync-state value types and the actor that aggregates events into them"
read_when: CloudKit sync-status surface
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Sync/SyncStatus.swift
    blob: 223dfb9083d24d793ee63be7e908eb838f1951c2
  - path: Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift
    blob: f9bcc5757ae01fcbe270c0fb554473dab5d63c75
  - path: Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift
    blob: bb8cbfb1b0244af352900f7d1d3a575ae5b3f842
references_modules: [Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-misc, Apps-Lillist-iOS-Sources-App, Apps-Lillist-iOS-Sources-Settings]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistCore/Sources/LillistCore/Sync (chunk 2)

## Purpose

The read-side of the CloudKit sync stack: the Sendable value types that describe
"how is sync doing" and "is iCloud usable," plus the actor that folds a raw
event stream into the former. The design idea is that UI and CLI never touch
CloudKit directly — they observe these snapshots. If this vanished, status
indicators and account-state banners would lose their single source of truth.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `iCloudAccountState` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift:8` | Four-case account verdict; `.accountChanged` signals the store must be quarantined |
| `iCloudAccountState.from(ckAccountStatus:)` | static func | `Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift:24` | Maps a `CKAccountStatus` to a verdict; the sole translation point for CloudKit |
| `SyncStatus` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatus.swift:6` | Sendable snapshot of last-sync time, in-progress flag, and error; `.idle` is the zero value |
| `SyncStatusMonitor` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:5` | Owns the current `SyncStatus`; vends a multicast `statusStream` |
| `SyncStatusMonitor.start()` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:25` | Idempotently begins consuming the bridge's event stream |
| `SyncStatusMonitor.stop()` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:18` | Cancels the consumer task; lets tests halt deterministically |
| `SyncStatusMonitor.statusStream` | computed var | `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:35` | `AsyncStream<SyncStatus>`; immediately yields the current value on subscribe |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `apply(_:)` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:58` | The state machine — folds each `CloudKitSyncEvent` into the next `SyncStatus` and fans it out to subscribers |
| `registerStatus(id:continuation:)` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:49` | Synchronous same-actor subscription that replays `currentStatus` so late subscribers aren't blank |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.SyncStatusMonitor -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.SyncStatus (owns)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.SyncStatusMonitor -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.CloudKitEventBridge (reads)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.SyncStatusMonitor -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.CloudKitSyncEvent (reads)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.SyncStatus -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (owns)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.AccountStateMonitor -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.iCloudAccountState (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.iCloudAccountState (owns)`
- `Apps-Lillist-iOS-Sources-Settings.ICloudSyncSection -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.iCloudAccountState (reads)`

## Type notes

`SyncStatusMonitor` is an `actor`; `currentStatus` is `private(set)` so reads are
actor-isolated (`Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:6`).
`statusStream` registers its continuation synchronously on the same actor and the
`onTermination` closure hops back via `Task` to unregister
(`Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:42`). The
consumer `Task` captures `[weak self]` so `stop()` can deterministically tear it
down (`Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:28`).
`SyncStatus` and `iCloudAccountState` are immutable `Sendable` value types crossing
the actor boundary freely. The `iCloudAccountState` casing intentionally matches
Apple's `iCloud` brand spelling
(`Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift:7`).

## External deps

- CloudKit — `CKAccountStatus` is the input to `iCloudAccountState.from(ckAccountStatus:)`

## Gotchas

- `from(ckAccountStatus:)` maps `.couldNotDetermine` to `.noAccount` to avoid writing CloudKit data without account evidence (`Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift:32`)
- `.temporarilyUnavailable` maps to `.restricted` so the UI shows a banner without quarantining the store (`Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift:34`)
- `start()` is idempotent — a second call leaves the existing consumer running (`Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:26`)
