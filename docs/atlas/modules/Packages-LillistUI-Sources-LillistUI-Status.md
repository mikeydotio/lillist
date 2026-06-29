---
module: Packages/LillistUI/Sources/LillistUI/Status
summary: "Bridges LillistCore sync status onto UI SyncIndicatorMonitor; encodes tap-driven task status cycling."
read_when: "Touching sync-status display, task-status cycling, or SyncIndicatorMonitor"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Status/CloudKitSyncStatusAdapter.swift
    blob: 7994e3be3abe236542428f678ddf9c28266418f9
  - path: Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift
    blob: edd504c3d1dad3a1f59af94b1300fcaf1c6bfc23
  - path: Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift
    blob: 17f675e51d349aee576301598c28f79719f7d016
references_modules: [Packages-LillistUI-Sources-LillistUI-DragReorder]
generator: cartographer/4
baseline: 99321d774840d17affd02fe2ac63b01b3d8cbec3
---

# Module: Packages/LillistUI/Sources/LillistUI/Status

## Purpose

This module is the translation layer between LillistCore's CloudKit sync machinery and the UI's sync indicator display. CloudKitSyncStatusAdapter bridges the Core actor's async status stream onto the @Observable SyncIndicatorMonitor protocol that all UI surfaces read; without it, the UI would show only the always-idle stub. StatusCycler encodes the tap-to-advance task status progression rule (todo→started→closed), keeping that domain logic out of individual views.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CloudKitSyncStatusAdapter` | class | `Packages/LillistUI/Sources/LillistUI/Status/CloudKitSyncStatusAdapter.swift:19` | Callers inject a `SyncStatusMonitor` and call `start()`; the published `indicator` then reflects live CloudKit status for the adapter's lifetime. |
| `IdleSyncIndicatorMonitor` | class | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:42` | Preview/test stub that always publishes `.idle(lastSync: Date())`; `retry()` is a no-op. Not suitable for production sync reporting. |
| `StatusCycler` | enum | `Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift:14` | Namespace for the forward-only tap-advance rule; callers receive the next `Status` for a given current status, per design Section 7. |
| `SyncIndicator` | enum | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:7` | UI-facing sync state: `.idle(lastSync:)`, `.inProgress`, `.error(message:lastSuccess:)`, `.paused(reason:)`; `Sendable` and `Equatable` so it crosses actor boundaries and drives animation keys. |
| `SyncIndicatorMonitor` | protocol | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:26` | `@MainActor AnyObject` that publishes `indicator: SyncIndicator` and responds to `retry()` and `start()`; `start()` has a no-op default for static/stub conformers. |
| `SyncIndicatorMonitor` | extension | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:34` | Provides the default no-op `start()` for conformers that need no lifecycle setup; live conformers override it. |
| `apply` | func | `Packages/LillistUI/Sources/LillistUI/Status/CloudKitSyncStatusAdapter.swift:58` | Translates a `SyncStatus` snapshot to a `SyncIndicator` and publishes it; internal entry point that lets tests drive the observable path without the async stream. |
| `nextOnClick` | func | `Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift:15` | Returns the next `Status` for a tap: `todo→started`, `started→closed`, `blocked→started`; `closed` is terminal and returns `closed` unchanged. |
| `start` | func | `Packages/LillistUI/Sources/LillistUI/Status/CloudKitSyncStatusAdapter.swift:38` | Idempotent: connects to `monitor.statusStream` and begins forwarding updates to `indicator`; subsequent calls while already consuming are silent no-ops. |
| `start` | func | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:31` | Protocol requirement: connect to the underlying status source; the app calls this once during `bootstrap()`. Static/stub monitors get the default no-op from the extension. |
| `start` | func | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:35` | Default no-op `start()` for static/stub conformers; conformers with live data sources override this. |
| `stop` | func | `Packages/LillistUI/Sources/LillistUI/Status/CloudKitSyncStatusAdapter.swift:51` | Cancels the background consume task; the adapter publishes no further updates after this call. Safe to call multiple times. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Status.CloudKitSyncStatusAdapter -> Packages-LillistUI-Sources-LillistUI-DragReorder.indicator (calls)`
- `Packages-LillistUI-Sources-LillistUI-Status.apply -> Packages-LillistUI-Sources-LillistUI-DragReorder.indicator (calls)`

## Type notes

CloudKitSyncStatusAdapter is @MainActor and @Observable; its `indicator` property is the observable source UI views bind to (Packages/LillistUI/Sources/LillistUI/Status/CloudKitSyncStatusAdapter.swift:17–20). The `indicator(for:)` mapping is `public nonisolated static func` so it can be called from any isolation context including tests (line 69). The `.paused` SyncIndicator case is never emitted by the adapter — the app layer overlays `pauseReason` atop the adapter's output so an account-level pause always wins (lines 64–68). IdleSyncIndicatorMonitor is retained as the stub for previews and screen-tour tests only; production bootstrap replaces it with CloudKitSyncStatusAdapter (SyncStatusMonitor.swift:38–44). StatusCycler is a caseless enum (namespace pattern) exposing a single pure static function; `closed` is a terminal state — tapping it is a no-op because TaskStore short-circuits same-status transitions (StatusCycler.swift:8–10).

## External deps

- Foundation — imported
- LillistCore — imported
- Observation — imported

## Gotchas

The SyncIndicatorMonitor protocol comment (SyncStatusMonitor.swift:22–24) explains a deliberate naming asymmetry: the UI protocol is called `SyncIndicatorMonitor` (not `SyncStatusMonitor`) to avoid a collision with the identically-named concrete actor in LillistCore. Callers that import both modules must be careful — the two types are unrelated despite the similar names.
