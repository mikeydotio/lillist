---
module: Packages/LillistCore/Sources/LillistCore/Notifications
summary: "Notification scheduling: spec persistence, desired-vs-pending diff reconciliation, snooze registry, and authorization."
read_when: "Touching notification scheduling or snooze"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/DeviceFingerprint.swift
    blob: bef576ad1fef41b6e8919ea51dddb1ef5c26d338
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/MorningSummaryRequestID.swift
    blob: 593257d83f2e1a2a2452edcca76ee6974bbe230a
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/NotificationCategoryFactory.swift
    blob: 0ed484910145ec08b21f6f3efe00e8960d0f5163
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/NotificationPermissions.swift
    blob: 3715fdd24935b9584645329f17c14ccce1462c18
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/NotificationReconciling.swift
    blob: 8ea9d70de48667e45bb44efa7aa5b881509d3cdd
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift
    blob: 70fc2b44f809c53e192844ffdf3ee9826e76c516
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift
    blob: 4c06302b9716636d5da60addd3d9d189ac65306c
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeAction.swift
    blob: 8b12e554a99d47e88381ed4614718c2c9f8576db
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeRegistry.swift
    blob: 1449db3718e98237232b036e757b5ef2d9587144
  - path: Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift
    blob: 36c1281750042203b07725b7278ef6680ce99a1e
references_modules: [Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/Notifications

## Purpose

This module owns the full notification lifecycle for Lillist: persisting reminder specs in Core Data (`NotificationSpecStore`), reconciling those specs against the OS pending queue (`NotificationScheduler`), managing snooze choices (`SnoozeRegistry`/`SnoozeAction`), and gating on user authorization (`NotificationPermissions`). The unifying mechanism is an idempotent desired-vs-pending diff: every store mutation that affects scheduling calls `reconcile(taskID:)`, which converges the OS queue to match the live spec set without duplicates or stale entries. Without this module tasks fire no notifications, snooze actions cannot be dispatched, and the daily morning summary cannot be installed or removed.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AuthorizationStatus` | enum | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationPermissions.swift:8` | App-layer enum; `.authorized` covers `.provisional` and `.ephemeral`; `Sendable` and `Equatable` for safe actor-boundary crossing. |
| `DeviceFingerprint` | enum | `Packages/LillistCore/Sources/LillistCore/Notifications/DeviceFingerprint.swift:9` | Namespace enum; callers rely only on `current(defaults:)` to obtain or lazily create the stable per-device fingerprint string. |
| `MorningSummary` | enum | `Packages/LillistCore/Sources/LillistCore/Notifications/MorningSummaryRequestID.swift:5` | Namespace holding `requestID` and `categoryID` string constants for the daily morning summary notification; never mutated at runtime. |
| `NotificationCategoryFactory` | enum | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationCategoryFactory.swift:7` | Namespace; callers use only `makeCategories(registry:)` to build the full `UNNotificationCategory` set; async because it reads actor-isolated registry. |
| `NotificationCategoryID` | enum | `Packages/LillistCore/Sources/LillistCore/Notifications/MorningSummaryRequestID.swift:12` | Namespace with `categoryID(for:)` mapping each `NotificationKind` to its stable, well-known category identifier string. |
| `NotificationPermissions` | actor | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationPermissions.swift:7` | Actor wrapping notification authorization; inject a `UNUserNotificationCenterProtocol` fake in tests; default init uses the real center. |
| `NotificationReconciling` | protocol | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationReconciling.swift:13` | Seam that lets stores trigger reconciliation without importing UserNotifications; conformers must be `Sendable` and must not throw. |
| `NotificationScheduler` | actor | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:14` | Central actor owning the desired-vs-pending diff loop; every mutation that affects scheduling must call `reconcile(taskID:)` after saving. |
| `NotificationSpecStore` | class | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:7` | Pure Core Data store for `NotificationSpec` rows; no scheduling side effects; all writes use `viewContext.perform` for thread safety. |
| `SnoozeAction` | struct | `Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeAction.swift:7` | Sendable value type holding a snooze option's id, display name, and `@Sendable Compute` closure; value semantics keep the registry actor-safe. |
| `SnoozeAction` | extension | `Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeAction.swift:21` | Provides `.tenMinutes`, `.oneHour`, and `.tomorrowMorning(hour:minute:timeZone:)` presets; callers may add or replace via `SnoozeRegistry`. |
| `SnoozeRegistry` | actor | `Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeRegistry.swift:7` | Actor holding the ordered snooze action list; default init registers ten-minute, one-hour, and tomorrow-morning presets. |
| `SpecDraft` | struct | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:46` | Mutable value for patching a spec via the `update` block-mutation API; covers kind, offsetMinutes, fireDate, and snoozedUntil. |
| `SpecRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:15` | Immutable `Sendable` DTO for a `NotificationSpec`; the only form in which spec data escapes `NotificationSpecStore` to callers. |
| `SystemUserNotificationCenter` | class | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:25` | Production `UNUserNotificationCenterProtocol` adapter wrapping `UNUserNotificationCenter.current()`; swap for a fake in tests. |
| `TaskSnapshot` | struct | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:119` | Internal snapshot capturing only the task fields needed by `computeDesiredRequests`; never escapes the actor. |
| `UNUserNotificationCenterProtocol` | protocol | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:11` | Test seam for `UNUserNotificationCenter`; `currentAuthorizationStatus` exists so fakes avoid constructing a real `UNNotificationSettings`. |
| `action` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeRegistry.swift:29` | Returns the `SnoozeAction` matching the given identifier string, or nil; safe to call from any actor. |
| `add` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:54` | Creates a spec; deduplicates `.defaultStart`/`.defaultDeadline` as singletons per task and self-heals CloudKit-delivered duplicates. |
| `add` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:12` | Schedules a `UNNotificationRequest`; may throw if the system rejects the request. |
| `add` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:32` | Delegates to `center.add(_:)` on the real `UNUserNotificationCenter`; protocol requirement satisfied. |
| `addNudge` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:451` | Creates a `.nudge` spec with an absolute fireDate, reconciles immediately, and returns the new spec UUID. |
| `addOffset` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:372` | Creates an `.offsetStart` or `.offsetDeadline` spec by anchor and minute-offset, reconciles immediately, and returns the spec UUID. |
| `bootstrap` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:289` | Must be called once on app launch; registers notification categories so the OS can dispatch snooze action taps to the app. |
| `cancelAllPending` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:307` | Cancels all per-task pending OS notifications while preserving `MorningSummary.requestID`; intended for pre-migration use. |
| `categoryID` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/MorningSummaryRequestID.swift:13` | Returns a deterministic category identifier string for the given `NotificationKind`; exhaustive over all cases. |
| `computeDesiredRequests` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:169` | Pure: returns the `UNNotificationRequest` set that should be pending; returns empty for closed or soft-deleted tasks. |
| `computeFireDate` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:212` | Pure: resolves the fire date for a spec, honouring snooze, kind, offset, and anchor; returns nil when the required anchor date is absent. |
| `current` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/DeviceFingerprint.swift:13` | Returns a stable, lazily-created fingerprint stored in UserDefaults; idempotent on repeat calls; deliberately not synced via CloudKit. |
| `currentAuthorizationStatus` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:21` | Returns only the authorization status; avoids forcing test fakes to construct a real `UNNotificationSettings` instance. |
| `currentAuthorizationStatus` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:56` | Returns `center.notificationSettings().authorizationStatus` from the real center. |
| `currentStatus` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationPermissions.swift:37` | Snapshot of current authorization state without prompting; `.provisional` and `.ephemeral` both collapse to `.authorized`. |
| `delete` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:143` | Removes the spec by ID; throws `LillistError.notFound` if absent. |
| `fetch` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:105` | Returns the `SpecRecord` for a spec ID; throws `LillistError.notFound` if absent. |
| `handleSnoozeAction` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:466` | Applies a named snooze action to a spec (writes `snoozedUntil`) and reconciles; throws `LillistError.validationFailed` on unknown action. |
| `identifier` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:270` | Returns the device-scoped request identifier `"<specID>#<deviceFingerprint>"`; callers must use this to match pending requests. |
| `installMorningSummary` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:397` | Replaces the daily repeating morning summary request at the given hour:minute; removes any previous request first (idempotent). |
| `makeCalendarTrigger` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:257` | Returns a DST-safe `UNCalendarNotificationTrigger` that stores `DateComponents`, not an absolute interval. |
| `makeCategories` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationCategoryFactory.swift:8` | Builds one `UNNotificationCategory` per `NotificationKind` plus the morning summary category, each carrying current snooze actions from the registry. |
| `notificationSettings` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:17` | Returns the full `UNNotificationSettings` snapshot for callers that need more than the authorization status. |
| `notificationSettings` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:52` | Delegates to `center.notificationSettings()`. |
| `pendingNotificationRequests` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:13` | Returns the current pending OS notification queue as an array of `UNNotificationRequest`. |
| `pendingNotificationRequests` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:36` | Delegates to `center.pendingNotificationRequests()`. |
| `reconcile` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationReconciling.swift:14` | Callers may rely on fire-and-forget semantics; the implementation must reconcile idempotently and never propagate errors outward. |
| `reconcile` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:46` | Idempotent diff: adds missing and removes stale or trigger-changed pending OS requests for the task; silences all internal errors. |
| `record` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:177` | Static mapper from a `NotificationSpec` managed object to `SpecRecord`; called at every fetch boundary to prevent managed-object escapes. |
| `recordFired` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:490` | Writes `lastFiredAt` for cross-device de-dup then reconciles; call from `UNUserNotificationCenterDelegate.willPresent`. |
| `recordLastFired` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:151` | Writes `lastFiredAt` on the spec row for the cross-device de-dup mechanism; no scheduling side effect. |
| `register` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeRegistry.swift:21` | Inserts a new snooze action or replaces an existing one with the same `id`; used to update `tomorrowMorning` when preferences change. |
| `removePendingNotificationRequests` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:14` | Cancels pending OS notification requests by identifier array. |
| `removePendingNotificationRequests` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:40` | Delegates to `center.removePendingNotificationRequests(withIdentifiers:)`. |
| `requestAuthorization` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationPermissions.swift:24` | Requests `.alert/.sound/.badge` authorization; system errors are mapped to `.denied` so callers need no try/catch. |
| `requestAuthorization` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:16` | Requests OS notification authorization with the given options; returns a Bool indicating whether authorization was granted. |
| `requestAuthorization` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:48` | Delegates to `center.requestAuthorization(options:)`. |
| `resolvedAnchorDate` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:242` | Time-bearing dates pass through unchanged; all-day dates receive the actor's `defaultAllDayHour:Minute` applied via Calendar in the configured time zone. |
| `restoreSteadyState` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:433` | Post-migration: reconciles every task with surviving specs and installs or removes the morning summary; idempotent. |
| `setNotificationCategories` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:15` | Registers the full category set with the OS; must be called on launch before snooze action taps can be dispatched. |
| `setNotificationCategories` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift:44` | Delegates to `center.setNotificationCategories(_:)`. |
| `specs` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:112` | Returns all `SpecRecord`s for a task ordered by `createdAt`; returns an empty array when none exist. |
| `tomorrowMorning` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeAction.swift:40` | Builds a snooze firing at the user's default all-day hour on the next calendar day, computed via `Calendar.date(byAdding:)`. |
| `uninstallMorningSummary` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:419` | Cancels the daily morning summary request by its well-known `MorningSummary.requestID`. |
| `update` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:121` | Applies a block mutation to a spec via `SpecDraft` and saves atomically within a single `viewContext.perform`. |
| `updateDefaultAllDayTime` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift:325` | Updates the in-actor all-day time preference and re-reconciles every task with an all-day anchor so their pending triggers reflect the new time. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `fetchManagedObject` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:161` | Choke-point for every `NotificationSpec` fetch within `NotificationSpecStore`: `fetch`, `update`, `delete`, and `recordLastFired` all route through it (`NotificationSpecStore.swift:107,123,145,153`). Its `fetchLimit = 1` + guard throw enforce at-most-one semantics and are the single place to adjust for future schema changes. |
| `fetchTask` | func | `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift:169` | Guards the `task` relationship at spec creation (`NotificationSpecStore.swift:61`); if the task UUID is not found it throws `LillistError.notFound` before any `NotificationSpec` is inserted, preventing orphaned spec rows. |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Notifications.addOffset -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.tasks (calls)`
- `Packages-LillistCore-Sources-LillistCore-Notifications.current -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Notifications.reconcile -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.closure (calls)`

## Type notes

`NotificationScheduler` is a Swift `actor` (`NotificationScheduler.swift:14`); all mutable state (default all-day time, device fingerprint, snooze registry reference) is actor-isolated and must be awaited by callers. It is the only type in this module that enqueues or cancels OS notifications.

`NotificationSpecStore` is `final class @unchecked Sendable` (`NotificationSpecStore.swift:7`), not an actor. Thread safety comes entirely from `viewContext.perform(_:)` — it always uses `viewContext`, meaning Core Data operations run on the main-queue serial context. Adding a background context would break that invariant.

`NotificationPermissions` and `SnoozeRegistry` are actors (`NotificationPermissions.swift:7`, `SnoozeRegistry.swift:7`). `SnoozeRegistry.actions` is mutable only through the actor-isolated `register`.

`SnoozeAction.Compute` is typed `@Sendable` (`SnoozeAction.swift:8`), ensuring closures carried across actor boundaries are data-race-free.

`DeviceFingerprint.current` reads/writes `UserDefaults.standard`, which is thread-safe. `NotificationScheduler` captures the fingerprint as an immutable `String` at `init` time (`NotificationScheduler.swift:19,29`), so there is no shared mutable state between the actor and `UserDefaults` after bootstrap.

`UNUserNotificationCenterProtocol` is declared with `@preconcurrency import UserNotifications` (`UNUserNotificationCenterProtocol.swift:2`) to suppress Sendable warnings on `UNNotificationRequest` crossing actor boundaries under Swift 6.

## External deps

- CoreData — imported
- Foundation — imported
- UserNotifications — imported

## Gotchas

- `reconcile` catches and discards all errors rather than throwing (`NotificationScheduler.swift:93-97`); a comment explains failures are transient — the next reconcile will retry. Callers get no signal on failure.
- `reconcile` builds stale/changed sets with for-loops instead of `compactMap` to avoid capturing the actor-isolated `desiredByID` dictionary into a closure, which triggers a Swift 6 `SendingRisksDataRace` (`NotificationScheduler.swift:72-82`).
- Default-spec (`.defaultStart`/`.defaultDeadline`) dedup in `add` uses a `task == %@` predicate rather than a Core Data model-level unique constraint because CloudKit doesn't honor uniqueness constraints; the guard also self-heals CloudKit-delivered duplicates by deleting all but the earliest (`NotificationSpecStore.swift:62-87`).
- `cancelAllPending` explicitly filters out `MorningSummary.requestID` before calling `removePendingNotificationRequests` (`NotificationScheduler.swift:311`); the morning summary is device-local, content-extension-filled, and must survive migration wipes.
