---
module: Packages/LillistUI/Sources/LillistUI/Status
summary: "Sync-status bridge (CloudKit→SyncIndicator) and task-status tap-cycle rule for LillistUI"
read_when: "Touching sync-status or task-status cycling"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Status/CloudKitSyncStatusAdapter.swift
    blob: ecb7d581bcd778e282f5579e5dc903bb0ba6f375
  - path: Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift
    blob: edd504c3d1dad3a1f59af94b1300fcaf1c6bfc23
  - path: Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift
    blob: 7ee15900e5fcb564d7c0b961ce0ca8c444be236e
references_modules: [Packages-LillistUI-Sources-LillistUI-DragReorder]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/Status

## Purpose

This module is the architectural seam between LillistCore's CloudKit event stream and the UI's sync-badge surface: it defines the `SyncIndicatorMonitor` protocol and `SyncIndicator` enum that every sync-status view consumes, and provides `CloudKitSyncStatusAdapter` as the production bridge that converts raw `SyncStatus` snapshots into those enum cases via an `AsyncStream` consumer on the main actor (`CloudKitSyncStatusAdapter.swift:38-47`). Without it, the UI would have no stable, actor-safe contract for reflecting genuine CloudKit activity — `IdleSyncIndicatorMonitor` exists only as the preview/test stub that preceded the real bridge. `StatusCycler` cohabits here as the pure encoding of the forward-only task-status tap rule (todo→started→closed), keeping that interaction policy in one testable function (`StatusCycler.swift:14-23`).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CloudKitSyncStatusAdapter` | class | `Packages/LillistUI/Sources/LillistUI/Status/CloudKitSyncStatusAdapter.swift:19` | Callers inject a `SyncStatusMonitor` and call `start()`; the published `indicator` then reflects live CloudKit status for the adapter's lifetime. |
| `IdleSyncIndicatorMonitor` | class | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:43` | Preview/test stub that always publishes `.idle(lastSync: Date())`; `retry()` is a no-op. Not suitable for production sync reporting. |
| `StatusCycler` | enum | `Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift:14` | Namespace for the forward-only tap-advance rule; callers receive the next `Status` for a given current status, per design Section 7. |
| `SyncIndicator` | enum | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:7` | UI-facing sync state: `.idle(lastSync:)`, `.inProgress`, `.error(message:lastSuccess:)`, `.paused(reason:)`; `Sendable` and `Equatable` so it crosses actor boundaries and drives animation keys. |
| `SyncIndicatorMonitor` | protocol | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:26` | `@MainActor AnyObject` that publishes `indicator: SyncIndicator` and responds to `retry()` and `start()`; `start()` has a no-op default for static/stub conformers. |
| `SyncIndicatorMonitor` | extension | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:35` | Provides the default no-op `start()` for conformers that need no lifecycle setup; live conformers override it. |
| `apply` | func | `Packages/LillistUI/Sources/LillistUI/Status/CloudKitSyncStatusAdapter.swift:66` | Translates a `SyncStatus` snapshot to a `SyncIndicator` and publishes it; internal entry point that lets tests drive the observable path without the async stream. |
| `nextOnClick` | func | `Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift:15` | Returns the next `Status` for a tap: `todo→started`, `started→closed`, `blocked→started`; `closed` is terminal and returns `closed` unchanged. |
| `retry` | func | `Packages/LillistUI/Sources/LillistUI/Status/CloudKitSyncStatusAdapter.swift:60` | Re-asserts `monitor.start()` to ensure the stream is connected; never fakes a success timestamp and does not force a CloudKit sync. |
| `retry` | func | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:28` | Protocol requirement: trigger a best-effort re-connection to the sync source; implementations must not fake a success timestamp. |
| `retry` | func | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:46` | No-op `retry()` on the idle stub; the stub has no active connection to re-assert. |
| `start` | func | `Packages/LillistUI/Sources/LillistUI/Status/CloudKitSyncStatusAdapter.swift:38` | Idempotent: connects to `monitor.statusStream` and begins forwarding updates to `indicator`; subsequent calls while already consuming are silent no-ops. |
| `start` | func | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:32` | Protocol requirement: connect to the underlying status source; the app calls this once during `bootstrap()`. Static/stub monitors get the default no-op from the extension. |
| `start` | func | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:36` | Default no-op `start()` for static/stub conformers; conformers with live data sources override this. |
| `stop` | func | `Packages/LillistUI/Sources/LillistUI/Status/CloudKitSyncStatusAdapter.swift:51` | Cancels the background consume task; the adapter publishes no further updates after this call. Safe to call multiple times. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Status.CloudKitSyncStatusAdapter -> Packages-LillistUI-Sources-LillistUI-DragReorder.indicator (calls)`
- `Packages-LillistUI-Sources-LillistUI-Status.apply -> Packages-LillistUI-Sources-LillistUI-DragReorder.indicator (calls)`

## Type notes

`SyncIndicatorMonitor` is `@MainActor`; every conforming type must also be main-actor-isolated (`SyncStatusMonitor.swift:25-26`). `CloudKitSyncStatusAdapter` is `@Observable`, so SwiftUI views observe `indicator` changes without explicit `objectWillChange` (`CloudKitSyncStatusAdapter.swift:17-20`). The adapter holds a `[weak self]` capture inside its consume task to avoid a retain cycle during async stream iteration (`CloudKitSyncStatusAdapter.swift:42`). `CloudKitSyncStatusAdapter` is designed for app-lifetime ownership — `stop()` exists for test determinism, and in production the adapter is never stopped (`CloudKitSyncStatusAdapter.swift:49-54`). `SyncIndicator` is `Sendable` and `Equatable`, allowing it to cross actor boundaries and drive SwiftUI `.animation(_:value:)` keys safely (`SyncStatusMonitor.swift:7`).

## External deps

- Foundation — imported
- LillistCore — imported
- Observation — imported

## Gotchas

`.paused` is intentionally never produced by `CloudKitSyncStatusAdapter.indicator(for:)` — the app layer overlays `pauseReason` before reading `indicator`, so an account-level pause always wins over the event stream (`CloudKitSyncStatusAdapter.swift:72-76`). `apply` is documented as `internal` despite appearing in the public symbol index — the doc comment at line 64 states "Internal so tests can drive the observable path without the async stream" (`CloudKitSyncStatusAdapter.swift:64-66`). `IdleSyncIndicatorMonitor.indicator` captures `Date()` at init time, so each preview or tour-test instance will report a distinct, immediately-stale last-sync timestamp (`SyncStatusMonitor.swift:44`).
