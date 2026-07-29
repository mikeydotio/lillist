# Plan 5b — widget-snapshot-correctness

Closes findings `X5 X6` from the 2026-07-28 data & sync hardening review
(`docs/reviews/2026-07-28-data-sync-review.md`). Not on the `TaskStore.swift`
serial chain (that chain closed for good with `5a`); this plan's own hotspot
files are `Packages/LillistCore/Sources/LillistCore/Widgets/*.swift` and the
two apps' widget-refresh wiring in `AppEnvironment.swift`.

Story IDs (moved to `in-progress` before this doc was committed):
`X5`→`LIL-18`, `X6`→`LIL-37`.

## 1. Why this plan exists

`WidgetSnapshotBuilder.regenerate(filterIDs:)` is called from **six**
call sites across three trust tiers that the current API doesn't
distinguish at all:

| Caller | Process | Scope | Read freshness relative to the write it's reacting to |
|---|---|---|---|
| `WidgetRefreshCoordinator` (both apps) | main app | full (`nil`) | same-process, same save — always current |
| `Extensions/ShortcutsActions/WidgetRefresh.swift` | App Intents extension | full (`nil`) | separate process; may lag the app's most recent write |
| `Extensions/ShareExtension-iOS/ShareRootView.swift` | Share extension | full (`nil`) | separate process; may lag |
| `Extensions/LillistWidget/AdvanceTaskStatusFromWidget.swift` | widget extension | full (`nil`) | separate process; may lag |
| `Extensions/LillistWidget/FilterTimelineProvider.swift` (cache-miss) | widget extension | one filter | separate process; frequently lags — this is the cold-cache path, triggered precisely when nothing has synced yet |

Every one of these ends its call with the same unconditional step:

```swift
snapshotStore.pruneFilters(keeping: Set(filters.map(\.id)).union([WidgetSnapshot.unfilteredID]))
```

`filters` is whatever `smartFilterStore.list()` happened to return **on this
call, in this process, from this context**. Two independent processes
sharing one on-disk store via an App Group do not see each other's writes
synchronously — `NSPersistentCloudKitContainer`'s cross-process propagation
(WAL checkpoint + `NSPersistentHistory` + `.NSPersistentStoreRemoteChange`)
is asynchronous by design. So when the widget extension's cold-cache-miss
rebuild reads the filter list one instant after the app created a new
filter, `list()` can legitimately return a set that doesn't yet include it
— and the existing code reads that as "this filter no longer exists" and
deletes its snapshot. `X5`'s failure scenario is exactly this: combined with
the (now-fixed, `1c`) `X1` wrong-store bug it could blank every desktop
widget; on iOS it manifests as this narrower but still real stale-read race.

Separately, `X6`: both apps register exactly one trigger for "the store
changed" — `.NSPersistentStoreRemoteChange` — and both apps' source comments
assert this "fires for local writes and CloudKit imports alike." That's
false for this codebase (confirmed against Apple's documented behavior and
the existing, working precedent in `LocalBackupCoordinator`, which needed a
*second*, separate observer for exactly this reason): `.NSPersistentStoreRemoteChange`
reflects changes this process's own `viewContext` didn't just make itself.
Completing a task in the app saves on `viewContext` directly (`TaskStore
.context` = `persistence.container.viewContext`) and never trips that
notification — the widget only ever catches up via the next CloudKit import
from another device (never, in `.localOnly` mode) or the 30-minute timeline
backstop, which just re-reads the same stale JSON rather than rebuilding it.

## 2. Empty-vs-failed read semantics

`WidgetSnapshotBuilder`'s existing guard,
`guard let filters = try? await smartFilterStore.list() else { return }`,
already handles the one case Swift's type system can express: `list()`
**throwing** (store unavailable, fetch error) short-circuits before any
write happens — no index write, no per-filter write, no prune. That part is
correct and unchanged.

The defect is a case Swift's type system *can't* express, because Core Data
doesn't surface it as an error: `list()` **succeeding** with a result that
is accurate for the reader's own context but stale relative to another
process's very recent write. From the calling code's point of view these are
indistinguishable — both are "a successful call that returned fewer filters
than actually exist." No exception type, retry, or timeout closes this gap;
the read is not wrong, it's just *not yet caught up*, and nothing signals
when it will be.

| Case | `list()` behavior | Safe to treat as "these are ALL the filters, delete anything else"? |
|---|---|---|
| Store unavailable / fetch throws | `try?` → `nil` → early return | N/A — already skips every write, including prune |
| Genuinely zero filters exist | Returns `[]`, no error | Yes, but **only from the one process guaranteed not to be lagging its own writes** — see §3 |
| Filters exist but this reader's context hasn't merged a very recent cross-process write yet | Returns a set missing that filter (possibly `[]`), no error | **Never** — indistinguishable from the row above at the call site; must not be able to delete anything regardless of which case it actually is |

Since the last two rows are indistinguishable by the callee, the fix cannot
be "detect staleness and skip pruning" — there is nothing to detect. It has
to be "make pruning available only where staleness relative to *this
process's own writes* cannot occur at all," which is an authority question,
not a freshness question. That's §3.

## 3. Prune-authority rules

**Split `regenerate(filterIDs:)` into two entry points on `WidgetSnapshotBuilder`:**

- **`regenerate(filterIDs:)`** (existing signature, unchanged call sites) —
  additive-only. Writes/refreshes the snapshot for each requested filter id
  (or every saved filter when `nil`) plus the "No Filter" sentinel when in
  scope. **Never writes the index. Never prunes.** Every extension/widget
  call site keeps calling this, unchanged syntax, corrected behavior.
- **`regenerateAuthoritatively()`** (new) — always a full read (no
  `filterIDs` parameter — partial-scope pruning was never coherent, since a
  prune decision needs the complete filter set to judge against). Does
  everything `regenerate(filterIDs:)` does, **plus** writes the picker index
  and prunes snapshots for filters the read didn't return. Callable **only**
  from `WidgetRefreshController` (new LillistCore type, §4) — which itself
  is driven only by the app's own bootstrap/debounced-refresh/reset paths.

**Who may call `regenerateAuthoritatively()`, and why that boundary is
correct, not arbitrary:** the app process is the one place a read of
`smartFilterStore.list()` is guaranteed current relative to *the app's own*
writes — Core Data serializes `context.perform` blocks on one queue, so a
fetch issued after a save on the same context (or a sibling context with
`automaticallyMergesChangesFromParent`) always observes that save. It is
**not** guaranteed current relative to a write CloudKit merged in from
another device microseconds ago — but under-pruning (a just-arrived remote
filter not yet reflected) is safe; the failure mode this program cares about
is over-pruning (deleting a snapshot for a filter that still exists), and
that can only happen when the reader's *own* recent writes are the ones it's
failing to see, which is categorically true only for same-process reads. No
extension, the Share extension, the Shortcuts action, or the widget's own
intent has that guarantee about the app's writes (or each other's) — they
are always looking at a different process's state.

**Corollary — the widget's cache-miss rebuild (`FilterTimelineProvider`)
never needed prune authority in the first place:** its entire job is "I have
no cached snapshot for filter X, and I have live Core Data access, so build
one." That is definitionally a **single-filter, additive** operation; it was
only ever calling the shared `regenerate(filterIDs:)` method because that
method didn't yet distinguish scope from authority. No behavior change is
needed at that call site beyond the method it calls becoming safe.

## 4. Local-save observation design (`X6`)

**Notification choice:** `.NSManagedObjectContextDidSave`, scoped to
`persistence.container.viewContext` (`object:` parameter, not `object: nil`)
— the identical mechanism `LocalBackupCoordinator` already uses to track the
same two entities (`LillistTask`, `SmartFilter`) these snapshots are built
from. Every `LillistCore` store's mutating methods save through
`context = persistence.container.viewContext` (verified: `TaskStore.context`,
and by extension every store built the same way), so this one observer
catches every local mutation that could change what a widget should show,
with no per-store enumeration to keep in sync as new mutation methods are
added. Registered **alongside**, not instead of, the existing
`.NSPersistentStoreRemoteChange` observer — CloudKit imports still need their
own trigger, since they don't touch `viewContext` via a local `save()` call
this process initiated.

**Debounce:** unchanged shape from the existing `WidgetRefreshCoordinator` —
cancel-and-restart a `Task.sleep` window (default 1500ms) so a burst of
either signal (local saves, remote changes, or both) coalesces into one
rebuild + one timeline reload.

**Seam (WidgetKit stays out of `LillistCore`):** a new
`public protocol WidgetTimelineReloading: Sendable { func reloadAllTimelines() }`
lives in `LillistCore`. The app/extension target's own conformance
(`WidgetCenter.shared.reloadAllTimelines()`) is the only place that imports
WidgetKit. This mirrors the existing house rule (`docs/engineering-notes.md`,
2026-07-01: "never `import WidgetKit` in LillistCore — CLI link") and is what
makes the debounce+rebuild logic testable at the `LillistCore` level: a test
double conforming to `WidgetTimelineReloading` proves the reload step fired,
without ever linking WidgetKit into the test target.

**New type:** `Packages/LillistCore/Sources/LillistCore/Widgets/WidgetRefreshController.swift`
— an `actor` (not a class) because, unlike the app-level type it replaces,
this one self-registers its `NotificationCenter` observers rather than
relying on a caller to hop onto `@MainActor` before invoking it; the two
notifications can post from different queues, so the mutable debounce
`Task` needs real serialization, not a documented calling convention. Owns:
`start()`/`stop()` (idempotent, mirrors `LocalBackupCoordinator`),
`scheduleRefresh()` (debounced), `refreshNow()` (immediate, bootstrap warm),
`resetAfterDestructiveOp()` (immediate + cache clear, awaited synchronously
by destructive-op callers — `X11`'s existing contract, preserved exactly).
All four regenerate-triggering paths call `regenerateAuthoritatively()` —
this type **is** "the app side" that §3 grants prune authority to; there is
no other caller.

**Retires:** `Apps/Lillist-iOS/Sources/App/WidgetRefreshCoordinator.swift` and
`Apps/Lillist-macOS/Sources/WidgetRefreshCoordinator.swift` (byte-identical
files — confirmed via `diff`) and the duplicated `.NSPersistentStoreRemoteChange`
observer block + its incorrect "fires for local writes and CloudKit imports
alike" comment in both `AppEnvironment.swift`s. Each app keeps a
few-line `WidgetTimelineReloading` conformance (the only WidgetKit-importing
surface left in this call chain) and constructs `WidgetRefreshController`
in its place.

## 5. Test plan

- `WidgetSnapshotBuilderTests` (existing, `regenerateWritesSnapshotAndIndex`):
  split — the additive `regenerate()` case drops its index assertion (moved
  to a new `regenerateAuthoritatively` test), since additive calls no longer
  touch the index. Two-hats: this is the finding's own behavior change, not
  an unrelated refactor riding along.
- New `WidgetSnapshotBuilderX5Tests.swift`: additive `regenerate(filterIDs:)`
  never prunes a snapshot for a filter its own read didn't include (deletes
  the filter out from under a builder instance mid-test, then calls the
  additive path and asserts the stale snapshot survives); `regenerateAuthoritatively()`
  still correctly prunes a genuinely deleted filter's snapshot (same setup,
  authoritative path, snapshot gone); `regenerateAuthoritatively()` writes the
  index, additive does not.
- New `WidgetSnapshotBuilderX5CrossProcessTests.swift`, built on the `1c`
  Keystone harness (`MultiProcessStoreHarnessTests`'s two-`PersistenceController`,
  one-file pattern): controller A (simulating the app) creates a filter and
  writes its snapshot via `regenerateAuthoritatively()`; controller B
  (simulating the widget extension, **never `refreshAllObjects()`'d** — the
  harness's documented mechanism for withholding a merge, i.e. genuine
  cross-instance staleness, not a simulated/mocked gap) calls the additive
  `regenerate(filterIDs:)` for that same filter id. Asserts the filter's
  snapshot (written by A) still exists after B's call — the literal
  "app writes filter + snapshot, widget-side rebuild with an older read must
  not delete it" scenario from the wave brief.
- New `WidgetRefreshControllerTests.swift` (LillistCore-level, no WidgetKit):
  a spy conforming to `WidgetTimelineReloading` records call count/timestamps;
  a real `TaskStore` mutation (e.g. `create` or `transition`) on the
  controller's `viewContext` is performed after `start()`; after waiting
  longer than the debounce window, asserts (a) the snapshot on disk reflects
  the mutation (proving `regenerateAuthoritatively()` actually ran as a
  *consequence* of the local save, not from some earlier warm call) and (b)
  the spy recorded a reload. A second case proves a burst of several rapid
  saves debounces into exactly one reload, matching the existing coordinator's
  documented coalescing behavior.

## 6. Deviations tracker

None anticipated. Any discovered during implementation get written in place
here (matching `5a`'s precedent) rather than as a separate addendum, since
nothing will have built on the superseded text yet.

## 7. What `5c` needs to know (filled in at close)

TBD — completed in the ledger's Wave 5b closing report and this section,
per the standard handoff shape.
