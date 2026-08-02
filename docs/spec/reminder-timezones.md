# Reminder time zones — sync the intent, keep the machinery local

**Stories:** LIL-83 (all-day cross-timezone duplicate notifications) and LIL-90
(remote in-place `NotificationSpec` edits invisible to the reconciler).
**Status:** specified 2026-08-01. Supersedes the council decision at
`.council/x10-all-day-timezone-dedup-posture/DECISION.md`.
**Blocked on one manual step:** a CloudKit Development→Production schema deploy
only Mikey can run (see *Deployment* at the end).

## Why these two stories are one change

LIL-83's fix **activates** LIL-90. That is the governing fact of this spec.

The time-zone-change prompt updates every reminder at once. That is an in-place
edit of existing, synced `NotificationSpec` rows on one device. Today
`RemoteChangeReconciler.affectedTaskIDs` handles a `NotificationSpec` UPDATE
only when `changedProperties.contains("lastFiredAt")` — every other in-place
property edit is ignored. So without LIL-90's fix, a user who accepts "reschedule
to PST" on the iPhone would find the Mac still firing on EST: a choice made and
silently disobeyed by half their devices.

LIL-90's own recorded redesign trigger is *"any new caller of
`NotificationSpecStore.update` reachable from a different device."* The prompt is
exactly that caller. LIL-90 therefore cannot be closed as unreachable; it must be
fixed here.

## The model

> **Sync the user's intent. Keep the machinery on the device.**

| Synced (CloudKit) | Device-local (App Group `UserDefaults`) |
|---|---|
| *what* the user asked for — anchor date, offset, and **the zone they were in when they asked** | *how this device is currently honouring it* — snooze state, last-known zone |
| `fireDate`, `offsetMinutes`, `kindRaw`, `scheduledTimeZoneID` | `snoozedUntil`, `lastKnownTimeZoneID` |
| `lastFiredAt` — genuinely cross-device (the dedup guard) | |

This is the same partition `DevicePreferencesStore` already draws for
preferences, and the same migration shape `AppPreferencesPartitionMigrator`
already performed once. It is a paved road, not a new idea.

### Why this fixes LIL-83 at the origin

The X10 fault is that each device resolves an all-day reminder through its own
`TimeZone.current`, so two devices compute two different absolute instants and
the `lastFiredAt` dedup guard — which compares instants — cannot suppress the
second. Storing the zone **with the reminder** means every device computes the
**same** instant from the same two inputs. The guard then works as designed,
untouched.

Note what this removes: the need for a "home time zone" concept at all. There is
no global setting to keep correct, and no question of what happens when a device
disagrees with it. Each reminder simply carries the answer.

### Why snooze must be local

Snooze is a statement about *this device's current notification*, not about the
user's intent. Syncing it is what makes an in-place spec edit reachable from
another device at all.

Behaviour after the change: `lastFiredAt` already means only one device shows a
given reminder. The user snoozes on that device; the snooze re-fires on that
device; the others were already suppressed and stay quiet. **No user-visible
regression** — the reminder still appears once and re-appears once.

## Type-system proposal

```
                       ┌────────────────────────────────────┐
   SYNCED              │ NotificationSpec        (Core Data)│
   (CloudKit mirror)   ├────────────────────────────────────┤
                       │  id, kindRaw, offsetMinutes        │
                       │  fireDate, createdAt               │
                       │  lastFiredAt      ← cross-device   │
                       │  scheduledTimeZoneID : String?  NEW│
                       │  snoozedUntil     ← DEPRECATED,    │
                       │                     read once by   │
                       │                     the migrator,  │
                       │                     never written  │
                       └───────────────┬────────────────────┘
                                       │ projected into
                       ┌───────────────▼────────────────────┐
                       │ NotificationSpecStore.SpecRecord   │
                       ├────────────────────────────────────┤
                       │  scheduledTimeZoneID : String?  NEW│
                       │  snoozedUntil : Date?              │
                       │    ← now hydrated from the LOCAL   │
                       │      store, not from Core Data     │
                       └───────────────┬────────────────────┘
                                       │ consumed by
   ┌───────────────────────────────────▼──────────────────────────────┐
   │ NotificationScheduler                                            │
   ├──────────────────────────────────────────────────────────────────┤
   │  timeZone: TimeZone     ← now the CAPTURE + FALLBACK zone only,  │
   │                           no longer the resolution zone          │
   │  resolvedAnchorDate(date:hasTime:zone:)      ← zone parameterised │
   │  makeCalendarTrigger(for:zone:)              ← zone parameterised │
   │  zone(for spec:) -> TimeZone   NEW  (spec's zone ?? fallback)    │
   └──────────────────────────────────────────────────────────────────┘

   DEVICE-LOCAL                     ┌──────────────────────────────────┐
   (App Group UserDefaults)         │ SnoozeStateStore          NEW    │
                                    ├──────────────────────────────────┤
                                    │  snoozedUntil(specID:) -> Date?  │
                                    │  setSnoozedUntil(_:specID:)      │
                                    │  clear(specID:) / prune(live:)   │
                                    └──────────────────────────────────┘
                                    ┌──────────────────────────────────┐
                                    │ DevicePreferencesStore  EXTENDED │
                                    │  lastKnownTimeZoneID             │
                                    │  snoozeMigrationCompleted        │
                                    └──────────────────────────────────┘
                                    ┌──────────────────────────────────┐
                                    │ TimeZoneChangeDetector    NEW    │
                                    ├──────────────────────────────────┤
                                    │  check() -> Change?              │
                                    │  Change { from, to, affected }   │
                                    │  accept() / decline()            │
                                    └──────────────────────────────────┘
```

**Invariant made structural:** `snoozedUntil` is never written to Core Data
again, so a remote in-place snooze edit cannot exist. LIL-90's snooze half
becomes *unrepresentable* rather than merely unreachable. Its `offsetMinutes`
half is closed by the reconciler widening below.

### Reconciler change (LIL-90)

`RemoteChangeReconciler.affectedTaskIDs` widens its `NotificationSpec` UPDATE
gate from `lastFiredAt` alone to any **schedule-affecting** property:

```
lastFiredAt | scheduledTimeZoneID | offsetMinutes | fireDate | kindRaw
```

Deliberately a named allow-list, not "any property": the set is the properties
that can change *when a notification should fire*, which is exactly what makes a
reconcile necessary. A future non-scheduling attribute must not silently start
triggering reconciles.

## Decisions taken

These were the open questions; defaults chosen and recorded rather than left
implicit.

1. **Snooze stops crossing devices.** Accepted — see *Why snooze must be local*.
2. **Pre-upgrade reminders have no stored zone.** `scheduledTimeZoneID` is
   optional and `nil` means *legacy*. Legacy specs resolve through the device's
   current zone, exactly as today, so **behaviour is unchanged until the user
   interacts**. No blind backfill: writing a zone the user never chose would be
   inventing intent, and would silently convert every existing reminder into a
   cross-device disagreement if the backfill ran on two devices in two zones.
   A legacy spec acquires a zone the first time it is rewritten (an edit, or an
   accepted reschedule prompt).
3. **When the prompt appears.** On app foreground, never mid-flight from a bare
   `NSSystemTimeZoneDidChange`. Additionally gated on the zone being *stably*
   different — the detector records the new zone and only offers once the app
   foregrounds in it, so a layover that ends before the next launch never
   prompts.
4. **Which reminders move.** Future, unfired reminders only. A spec whose
   computed fire date is in the past, or that has a `lastFiredAt`, is left
   alone — rescheduling a reminder that already did its job would re-fire it.

## Deployment — the one manual step

`scheduledTimeZoneID` is a new CloudKit field. `NSPersistentCloudKitContainer`
auto-creates schema **only** in the Development environment.

1. Run a **Development-signed** build (a local Xcode run — see CLAUDE.md,
   *CloudKit / iCloud sync environment*) and create/edit one reminder, so the
   field is exercised and the Development schema gains it.
2. In the CloudKit Console, deploy the schema **Development → Production**.
3. Only then ship a distribution build (`/deployit`, which signs for Production).

Shipping a Production build before step 2 means the field silently fails to sync
— the local value is kept, peers never see it, and reminders diverge exactly as
they do today. The change is additive and permanent; CloudKit cannot remove a
field.

`snoozedUntil` stays in the deployed schema forever as a vestigial column. That
is fine and costs nothing: it is simply never written again.
