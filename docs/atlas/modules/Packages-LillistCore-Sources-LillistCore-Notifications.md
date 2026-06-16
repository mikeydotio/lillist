---
module: Packages/LillistCore/Sources/LillistCore/Notifications
summary: "Reconciles NotificationSpec rows to the system notification center; permissions, snooze, morning summary"
read_when: "Notification scheduling"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/DeviceFingerprint.swift
    blob: 017698e8236497dbf31c324921f892727511f7eb
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/MorningSummaryRequestID.swift
    blob: d6059297c0840d9e4cef84f6a431c21ba0e34264
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/NotificationCategoryFactory.swift
    blob: 0ed484910145ec08b21f6f3efe00e8960d0f5163
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/NotificationPermissions.swift
    blob: 3715fdd24935b9584645329f17c14ccce1462c18
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/NotificationReconciling.swift
    blob: 8ea9d70de48667e45bb44efa7aa5b881509d3cdd
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift
    blob: d85cade15d640aa96c0d298c63151ac4f4e7d312
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift
    blob: de96de04c2529c3fcb6b145b77f94ba4b72752ad
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeAction.swift
    blob: 8b12e554a99d47e88381ed4614718c2c9f8576db
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeRegistry.swift
    blob: 1449db3718e98237232b036e757b5ef2d9587144
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift
    blob: 36c1281750042203b07725b7278ef6680ce99a1e
references_modules: [Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Sync-chunk-2, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-Persistence, Apps-Lillist-iOS-Sources-App, Apps-Lillist-macOS-Sources-Preferences]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistCore/Sources/LillistCore/Notifications

## Purpose

Implements the design's four-layer notification model: persisted `NotificationSpec`
rows are the source of truth, and `NotificationScheduler` continuously reconciles
them against the OS notification center. The whole subsystem hangs off one idea —
a single `reconcile(taskID:)` desired-vs-pending diff that every scheduling-relevant
mutation re-invokes, making the OS pending set a pure function of stored specs plus
task anchors. Cross-device de-dup is achieved without coordination by suffixing
request identifiers with a device fingerprint and skipping fires recorded by peers.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `DeviceFingerprint` | enum | `Packages/LillistCore/Sources/LillistCore/Notifications/DeviceFingerprint.swift:9` | `current(defaults:)` returns a stable per-device id; persisted, never CloudKit-synced |
| `MorningSummary` | enum | `Packages/LillistCore/Sources/LillistCore/Notifications/MorningSummaryRequestID.swift:5` | Well-known `requestID`/`categoryID` for the daily summary request |
| `NotificationCategoryFactory` | enum | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationCategoryFactory.swift:7` | `makeCategories(registry:)` builds the `UNNotificationCategory` set, one per kind |
| `NotificationCategoryID` | enum | `Packages/LillistCore/Sources/LillistCore/Notifications/MorningSummaryRequestID.swift:12` | Maps each `NotificationKind` to a stable category identifier string |
| `NotificationPermissions` | actor | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationPermissions.swift:7` | `requestAuthorization`/`currentStatus`; errors degrade to `.denied` without throwing |
| `NotificationPermissions.AuthorizationStatus` | enum | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationPermissions.swift:8` | `.authorized`/`.denied`/`.notDetermined`; provisional+ephemeral fold to authorized |
| `NotificationReconciling` | protocol | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationReconciling.swift:13` | `reconcile(taskID:)` seam stores depend on instead of the concrete scheduler |
| `NotificationScheduler` | actor | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:14` | Sole owner of OS pending state; `reconcile(taskID:)` is the single entry point |
| `NotificationSpecStore` | class | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:7` | CRUD over `NotificationSpec` returning `SpecRecord` DTOs; pure persistence, no scheduling |
| `NotificationSpecStore.SpecDraft` | struct | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:26` | Mutable patch passed to `update(id:_:)` |
| `NotificationSpecStore.SpecRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:15` | Value-type view of a spec row; no Core Data type escapes |
| `SnoozeAction` | struct | `Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeAction.swift:7` | `{id, displayName, compute}`; presets `tenMinutes`, `oneHour`, `tomorrowMorning` |
| `SnoozeRegistry` | actor | `Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeRegistry.swift:7` | Runtime-mutable set of snooze actions; `register` replaces by id |
| `SystemUserNotificationCenter` | class | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:25` | Production adapter wrapping the real `UNUserNotificationCenter` |
| `UNUserNotificationCenterProtocol` | protocol | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:11` | The center slice the scheduler depends on; lets tests inject a recording fake |

Key scheduler methods: `bootstrap()` (`NotificationScheduler.swift:299`), `cancelAllPending()`
(`:317`), `restoreSteadyState(morningSummaryEnabled:hour:minute:)` (`:441`),
`installMorningSummary(hour:minute:)` (`:405`), `updateDefaultAllDayTime(hour:minute:)`
(`:333`), `addOffset(taskID:anchor:offsetMinutes:)` (`:380`), `addNudge(taskID:fireDate:)`
(`:459`), `handleSnoozeAction(actionID:specID:deliveredAt:)` (`:474`), `recordFired(specID:at:)`
(`:498`).

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `identifier(for:)` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:280` | Encodes the `"<specID>#<deviceFingerprint>"` request-id format the whole de-dup scheme rests on |
| `computeDesiredRequests(task:specs:)` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:179` | Builds the desired pending set; closed/deleted tasks yield none, peer-fired specs are skipped |
| `computeFireDate(for:task:)` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:222` | Per-kind fire-time resolution; snooze wins, offsets add to anchor, nudge uses absolute date |
| `materializeDefaultSpecs(for:)` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:151` | Creates/deletes default specs so rows exist iff the task's anchor field is present |
| `resolvedAnchorDate(date:hasTime:)` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:252` | Applies the default all-day hour/minute to time-less anchors in the configured zone |
| `fetchManagedObject(id:in:)` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:141` | Shared spec lookup behind every spec-store read/mutation; throws `LillistError.notFound` |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationReconciling (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.MigrationCoordinator -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler (calls)`
- `Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationReconciling (conforms-to)`
- `Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler -> Packages-LillistCore-Sources-LillistCore-Notifications.SnoozeRegistry (reads)`
- `Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler -> Packages-LillistCore-Sources-LillistCore-Notifications.UNUserNotificationCenterProtocol (calls)`
- `Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.NotificationSpec (owns)`
- `Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (reads)`
- `Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler -> Packages-LillistCore-Sources-LillistCore-Model.NotificationKind (reads)`
- `Packages-LillistCore-Sources-LillistCore-Notifications.SystemUserNotificationCenter -> Packages-LillistCore-Sources-LillistCore-Notifications.UNUserNotificationCenterProtocol (conforms-to)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.NotificationsPane -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler (calls)`

## Type notes

`NotificationScheduler` is an `actor`; `defaultAllDayHour`/`defaultAllDayMinute` are
its only mutable state (`NotificationScheduler.swift:20`), updated via
`updateDefaultAllDayTime`. The composition root constructs one scheduler and assigns
it to each store's `notificationScheduler` property; a `nil` property makes the
reconcile call a deliberate no-op so notification-unaware store tests need no changes
(`NotificationReconciling.swift:8`). `NotificationSpecStore` is `@unchecked Sendable`
and runs all work inside `context.perform`; default specs are singletons per
(task, kind), enforced by a `task == %@` predicate that self-heals CloudKit-imported
duplicates rather than a model unique constraint (`NotificationSpecStore.swift:52`).
`SnoozeRegistry` is an actor so its `[SnoozeAction]` stays isolated; `SnoozeAction`
is a value type with a `@Sendable` `compute` closure. Snapshots (`TaskSnapshot`,
`SpecRecord`) cross the actor boundary as `Sendable` values, never managed objects.

## External deps

- UserNotifications — `UNUserNotificationCenter`, requests, categories, triggers; imported `@preconcurrency` so framework types cross actor boundaries without `Sendable` shims
- CoreData — `NSFetchRequest`/`NSManagedObjectContext` for spec and task fetches
- Foundation — `Calendar`/`DateComponents` for DST-safe fire-date math, `UserDefaults` for the device fingerprint

## Gotchas

- De-dup is `lastFiredAt >= fireDate - 60s`, relative not absolute, so editing a deadline forward re-fires the spec (`NotificationScheduler.swift:199`).
- `cancelAllPending()` deliberately preserves the morning-summary request because it is device-local and task-independent (`NotificationScheduler.swift:317`).
- All-day anchors get the default hour/minute applied; `UNCalendarNotificationTrigger` stores components (not an interval) to survive DST (`NotificationScheduler.swift:267`).
- `reconcile` swallows errors by design — a failed cycle just retries on the next mutation (`NotificationScheduler.swift:92`).
