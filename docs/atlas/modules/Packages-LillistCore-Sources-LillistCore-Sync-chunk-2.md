---
module: "Packages/LillistCore/Sources/LillistCore/Sync (chunk 2)"
summary: "CloudKit sync observability: SyncStatusMonitor actor, quiesce heuristic for migration gating, iCloudAccountState."
read_when: "Touching sync-status display or quiesce gate"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift
    blob: ad9399267df89701c33893a29e31d3be9950bcce
  - path: Packages/LillistCore/Sources/LillistCore/Sync/SyncStatus.swift
    blob: 223dfb9083d24d793ee63be7e908eb838f1951c2
  - path: Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift
    blob: 0a7e76e258e7ff0c10c776393bfe460ad2bc1a98
  - path: Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift
    blob: bb8cbfb1b0244af352900f7d1d3a575ae5b3f842
generator: cartographer/4
baseline: 99321d774840d17affd02fe2ac63b01b3d8cbec3
---

# Module: Packages/LillistCore/Sources/LillistCore/Sync (chunk 2)

## Purpose

This module is the sync-status observability layer for LillistCore. It converts raw `CloudKitSyncEvent` streams (from `CloudKitEventBridge`) into three typed, consumer-ready surfaces: a live `SyncStatus` aggregate via `SyncStatusMonitor`, a quiesce heuristic for migration gating via `SyncQuiesceMonitor`, and a CKAccountStatus mapping via `iCloudAccountState`. Without this layer the UI cannot surface sync progress or errors, and migration coordinators have no signal for when the post-mode-change CloudKit flood has settled enough to flip the mode flag.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `QuiesceResult` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:4` | Two-case exhaustive result: `.quiesced` means quiet window observed; `.timedOut` means caller should proceed and surface "still syncing" copy. |
| `SyncQuiesceMonitor` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:28` | Actor wrapping a quiesce heuristic; callers get a `QuiesceResult` from `waitForQuiesce` and may rely on it completing within `hardTimeout` seconds. |
| `SyncStatus` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatus.swift:6` | Sendable, Equatable value snapshot of CloudKit sync state; `idle` is the zero state; `inProgress`, `error`, and `lastSyncedAt` are independently nullable. |
| `SyncStatusMonitor` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:5` | Actor; callers subscribe via `statusStream` (immediate current-status yield on subscribe), drive lifecycle with `start()`/`stop()`, and read `currentStatus` for a synchronous snapshot. |
| `from` | func | `Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift:24` | Total function: maps any `CKAccountStatus` including `@unknown default` to one of four cases; never throws, never returns nil, always degrades to `.noAccount` on uncertainty. |
| `iCloudAccountState` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift:8` | Four-case Sendable/Equatable/Hashable enum; `.accountChanged` signals store quarantine (not a UI-only warning); `.restricted` covers both parental controls and temporary unavailability. |
| `start` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:25` | Idempotent: safe to call multiple times; a second call while the consumer is running does nothing. Must be awaited before the monitor will emit status updates. |
| `stop` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:18` | Cancels the consumer task synchronously; existing `statusStream` subscribers receive no further yields. Safe to call at any point including before `start()`. |
| `waitForQuiesce` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:36` | Suspends until no import/export events arrive for `minQuietWindow` seconds (returns `.quiesced`) or `hardTimeout` elapses (returns `.timedOut`); always returns, never throws. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `apply` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:58` | Central event reducer for `SyncStatusMonitor`: every CloudKit event flows through here; it is the exclusive writer of `currentStatus` and the sole fanout point to all registered `statusContinuations`, making it the invariant guard for status consistency across all active subscribers (Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:58-76). |
| `recordEvent` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:67` | Sole write path to `lastEventAt` inside `SyncQuiesceMonitor`; `waitForQuiesce`'s polling loop reads this timestamp to determine quiescence, making `recordEvent` the only mechanism by which real CloudKit activity resets the quiet-window clock (Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:67-69). |

## Relationships

## Type notes

- `SyncStatusMonitor` (actor): all state mutations are actor-isolated. `statusStream` is a computed property returning a new `AsyncStream<SyncStatus>` per call; each new subscriber receives the current status immediately via `registerStatus` → `continuation.yield(currentStatus)` (Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:49-52). The consumer `Task` uses `[weak self]` to avoid anchoring the actor's lifetime.
- `start()` is idempotent via `guard consumeTask == nil` (Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:26), so multiple `bootstrap()` call sites across app layers cannot spawn competing consumers.
- `SyncQuiesceMonitor` (actor): `lastEventAt` is exclusively mutated through the private `recordEvent()` method, which is awaited from the watcher `Task` inside `waitForQuiesce` (Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:49). The watcher `Task` uses `[weak self]` to avoid extending the actor's lifetime (Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:45).
- `SyncStatus` (struct): value type, no identity; `idle` static constant is the zero/unknown state (Packages/LillistCore/Sources/LillistCore/Sync/SyncStatus.swift:18). `error` and `lastSyncedAt` are independently nullable and carry no ordering invariant between them.
- `iCloudAccountState` (enum): `@unknown default` in `from(ckAccountStatus:)` maps to `.noAccount` so future CKAccountStatus cases degrade safely (Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift:36-38).

## External deps

- CloudKit — imported
- Foundation — imported

## Gotchas

- `SyncQuiesceMonitor.waitForQuiesce` uses `Date().addingTimeInterval` for its deadline — the one deliberate exception to the Calendar-only rule, because quiesce windows are defined in absolute seconds (Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:55).
- `NSPersistentCloudKitContainer.eventChangedNotification` never fires a terminal "all done" event (doc comment: "skeptic A4"); the quiesce heuristic is not a guarantee (Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:18-25).
- `CKAccountStatus.couldNotDetermine` maps to `.noAccount` (not a retry state) as a safety-first policy; callers that need retry logic must handle this case explicitly (Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift:27-29).
- `iCloudAccountState` uses lowercase-i casing to match Apple brand spelling, intentionally violating Swift type-naming conventions (Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift:6-7).
