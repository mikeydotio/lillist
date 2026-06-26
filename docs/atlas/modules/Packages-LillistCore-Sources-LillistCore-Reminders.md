---
module: Packages/LillistCore/Sources/LillistCore/Reminders
summary: "EventKit bridge and crash-safe drain importer: converts a Reminders list into Lillist tasks"
read_when: "Touching Reminders import or EventKit auth"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Reminders/EventKitRemindersGateway.swift
    blob: 46d1da8a60968c7b4924379f002d8554bd6c5639
  - path: Packages/LillistCore/Sources/LillistCore/Reminders/ReminderDTOs.swift
    blob: 77a935f3e810245bfa4bd104a311437ba9c594de
  - path: Packages/LillistCore/Sources/LillistCore/Reminders/RemindersGateway.swift
    blob: ca80fca8c3dc8ae22c9aeaa373b64ff34d81e9cb
  - path: Packages/LillistCore/Sources/LillistCore/Reminders/RemindersImporter.swift
    blob: 8a496dc9dd9e308770bc3f4e9b51a8edd0cff41f
references_modules: [Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-misc]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/Reminders

## Purpose

This module is the one-way bridge between Apple Reminders (EventKit) and Lillist's task store. Its core idea is a drain queue: a designated Reminders list acts as an inbox whose items are converted to top-level Lillist tasks and then deleted, so the list empties on each app activation. Without it, there is no path for Reminders-based Quick Capture or Siri-driven task entry to land in Lillist. The module also owns the crash-safety invariant: a device-persisted in-flight ID set ensures a reminder that was task-created but not yet deleted is skipped on re-create and only deleted on the next pass, preventing duplicates after a crash mid-drain.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `EventKitRemindersGateway` | actor | `Packages/LillistCore/Sources/LillistCore/Reminders/EventKitRemindersGateway.swift:10` | Concrete actor conforming to RemindersGateway; confines one EKEventStore; callers receive only Sendable DTOs — no EventKit types escape the isolation boundary. |
| `ReminderItem` | struct | `Packages/LillistCore/Sources/LillistCore/Reminders/ReminderDTOs.swift:19` | Sendable DTO for one EKReminder; id is calendarItemExternalIdentifier (stable, used as dedup key); dueHasTime distinguishes timed from all-day deadlines. |
| `ReminderListInfo` | struct | `Packages/LillistCore/Sources/LillistCore/Reminders/ReminderDTOs.swift:6` | Sendable DTO for one EKCalendar with reminder entity type; id is the calendarIdentifier; carries only the fields Lillist needs for list selection. |
| `RemindersAuthorization` | enum | `Packages/LillistCore/Sources/LillistCore/Reminders/ReminderDTOs.swift:48` | Coarse three-state authorization enum decoupled from EKAuthorizationStatus; denied covers .denied, .restricted, and .writeOnly; callers never import EventKit. |
| `RemindersGateway` | protocol | `Packages/LillistCore/Sources/LillistCore/Reminders/RemindersGateway.swift:7` | Testability seam over EventKit; all methods are async/Sendable; production conformance is EventKitRemindersGateway; tests use an in-memory fake. |
| `RemindersImporter` | actor | `Packages/LillistCore/Sources/LillistCore/Reminders/RemindersImporter.swift:15` | Actor that one-way drains a configured Reminders list into top-level Lillist tasks; serializes overlapping activations via isDraining; uses DevicePreferencesStore to survive mid-drain crashes. |
| `authorization` | func | `Packages/LillistCore/Sources/LillistCore/Reminders/EventKitRemindersGateway.swift:15` | Returns current EKEventStore authorization mapped to RemindersAuthorization; synchronous and non-throwing; .writeOnly and .restricted both map to .denied. |
| `authorization` | func | `Packages/LillistCore/Sources/LillistCore/Reminders/RemindersGateway.swift:9` | Query current authorization state without prompting; callers should check this before deciding whether to call requestAccess. |
| `drainIfNeeded` | func | `Packages/LillistCore/Sources/LillistCore/Reminders/RemindersImporter.swift:40` | Runs a drain pass only when the feature is enabled, a list is configured, and Reminders access is authorized; idempotent via isDraining guard; returns new-task count; never throws. |
| `items` | func | `Packages/LillistCore/Sources/LillistCore/Reminders/EventKitRemindersGateway.swift:41` | Fetches every reminder in the list (any completion state) as Sendable ReminderItem DTOs; returns [] for an unknown listID; throws only if the EK fetch itself errors. |
| `items` | func | `Packages/LillistCore/Sources/LillistCore/Reminders/RemindersGateway.swift:20` | Fetch all reminders in the specified list regardless of completion state; throws if the list is inaccessible or the fetch fails. |
| `lists` | func | `Packages/LillistCore/Sources/LillistCore/Reminders/EventKitRemindersGateway.swift:36` | Returns all EKCalendar reminder calendars mapped to ReminderListInfo DTOs; synchronous and throws if the store query fails. |
| `lists` | func | `Packages/LillistCore/Sources/LillistCore/Reminders/RemindersGateway.swift:17` | Returns all reminder lists visible to the user; throws if Reminders access is unavailable or the store query fails. |
| `remove` | func | `Packages/LillistCore/Sources/LillistCore/Reminders/EventKitRemindersGateway.swift:68` | Deletes every EKReminder matched by externalIdentifier (multiple matches possible for iCloud/recurrence dupes) then commits; throws on commit failure. |
| `remove` | func | `Packages/LillistCore/Sources/LillistCore/Reminders/RemindersGateway.swift:23` | Permanently delete the reminder by external identifier; throws on failure; callers must persist the in-flight marker before calling and clear it only on success. |
| `requestAccess` | func | `Packages/LillistCore/Sources/LillistCore/Reminders/EventKitRemindersGateway.swift:28` | Requests full Reminders access; is a no-op if a decision was already recorded; swallows system errors as false; returns true iff access is now granted. |
| `requestAccess` | func | `Packages/LillistCore/Sources/LillistCore/Reminders/RemindersGateway.swift:14` | Prompt for Reminders access; @discardableResult; no-op after the first user decision; returns true if access is granted after the prompt resolves. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `createTask` | func | `Packages/LillistCore/Sources/LillistCore/Reminders/RemindersImporter.swift:98` | Encapsulates the ReminderItem-to-TaskStore mapping: applies the blank-title fallback via TaskStore.isCommittableTitle, calls taskStore.create, then conditionally patches deadline and deadlineHasTime via taskStore.update. Removing or inlining it would scatter the mapping logic across drainIfNeeded's loop body. |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Reminders.RemindersImporter -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.tasks (calls)`
- `Packages-LillistCore-Sources-LillistCore-Reminders.drainIfNeeded -> Packages-LillistCore-Sources-LillistCore-misc.remindersImportEnabled (reads)`
- `Packages-LillistCore-Sources-LillistCore-Reminders.drainIfNeeded -> Packages-LillistCore-Sources-LillistCore-misc.remindersImportListID (reads)`
- `Packages-LillistCore-Sources-LillistCore-Reminders.drainIfNeeded -> Packages-LillistCore-Sources-LillistCore-misc.remindersInFlightIDs (reads)`
- `Packages-LillistCore-Sources-LillistCore-Reminders.drainIfNeeded -> Packages-LillistCore-Sources-LillistCore-misc.setRemindersInFlightIDs (writes)`

## Type notes

`EventKitRemindersGateway` is an actor that confines a single `EKEventStore` (non-Sendable) inside actor isolation; `@preconcurrency import EventKit` suppresses Swift 6 Sendable warnings for EK types (`Packages/LillistCore/Sources/LillistCore/Reminders/EventKitRemindersGateway.swift:1`). `makeItem(from:)` is `private nonisolated static` so EventKit's non-isolated fetch callback can call it without capturing actor state (`EventKitRemindersGateway.swift:56`). `RemindersImporter` is an actor; its `isDraining: Bool` guard is written before the first `await` to prevent concurrent drain passes both passing the check before either sets the flag (`RemindersImporter.swift:46`). `ReminderItem.id` is `calendarItemExternalIdentifier` — stable across devices and used as the persistent dedup key; do not confuse with the per-device `calendarItemIdentifier` (`ReminderDTOs.swift:17`). `RemindersAuthorization` decouples callers and the UI from `EKAuthorizationStatus`; no consumer of this module needs to import EventKit (`ReminderDTOs.swift:47`).

## External deps

- Foundation — imported

## Gotchas

1. `isDraining` must be set to `true` before the first `await` in `drainIfNeeded` — the actor releases isolation at every suspension point, so setting it after any await lets concurrent activations all pass the guard and drain in parallel, creating duplicates. Documented in-source at `Packages/LillistCore/Sources/LillistCore/Reminders/RemindersImporter.swift:43`. 2. `EventKitRemindersGateway.makeItem` is `private nonisolated static` because EventKit's fetch-completion callback is non-isolated; an actor-isolated closure there would be a Swift 6 error. `Packages/LillistCore/Sources/LillistCore/Reminders/EventKitRemindersGateway.swift:53`. 3. `calendarItems(withExternalIdentifier:)` can return more than one EKReminder for the same external ID (recurrence or iCloud duplicates), so `remove` iterates all matches rather than the first. `Packages/LillistCore/Sources/LillistCore/Reminders/EventKitRemindersGateway.swift:69`.
