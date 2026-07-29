# Plan 4c — Recurrence Correctness

Closes `H1` (`LIL-19`), `X7` (`LIL-38`), `X16` (`LIL-65`), `X17` (`LIL-66`)
from `docs/reviews/2026-07-28-data-sync-review.md`. Wave 4's third and final
plan; see `docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`
for the program-level ledger, the *Wave 4b closing report* (what this plan
inherits), and the *Resume protocol*.

## Context all four findings share

All four live in `Packages/LillistCore/Sources/LillistCore/Recurrence/` (plus
`Stores/TaskStore.swift`'s spawn call site and `Ordering/FractionalPosition.swift`
for `H1`). None touches the Core Data model — no CloudKit schema
implications. Two are genuine defects reachable today on a single device
(`H1`, `X16`); two are cross-process/cross-device races or locale gaps
(`X7`, `X17`) the review's *Structural test gaps* note flags as invisible
under the pre-1c test architecture (no multi-process harness, no
locale-parameterized recurrence tests).

---

## H1 — every spawn collides at `seed.position + 0.5`

### Root cause

`RecurrenceSpawner.spawnIfNeeded` (`RecurrenceSpawner.swift:32,46`):

```swift
let seed = series.seedTask ?? closed
...
spawn.position = seed.position + 0.5
```

`seed` is **`series.seedTask`** — the *original* instance the series was
created from — not `closed` (the instance that just transitioned, i.e. the
most recent spawn). `series.seedTask` never changes across a series'
lifetime. So every spawn after the first computes the identical
`seed.position + 0.5`: spawn #2 and spawn #3 land on the exact same
fractional position, a permanent sibling tie that only grows every cycle a
recurring task closes. (`series.seedTask ?? closed` only degrades to `closed`
when `seedTask` itself is nil — a corrupted-row case, not the common path.)

This is not fixable by "advance the anchor" (e.g. use `closed.position`
instead) without also solving a second problem: `closed`'s position is
already occupied by a *closed* task sharing a parent with potentially many
live siblings inserted since the series started — there's no guarantee
`closed.position + 0.5` doesn't collide with something a user dragged into
that exact gap in the meantime. The fix needs a live, collision-free
placement computed against the *current* sibling set, not an offset from any
single stored value (stale or otherwise) — which is exactly what `1a`
already built for `TaskStore.create`.

### Placement decision — bottom, decided directly (no council)

Three candidate placements, per the wave brief's instruction to decide
deliberately:

1. **Bottom** — `nextPositionDetail(forParent:placement:.bottom)`'s existing
   live-edge-fetch machinery, verbatim. A spawn is treated as "a new task,"
   same as every other creation path's default (`NewTaskPlacement.bottom` is
   already the default for `create`).
2. **Top** — visible immediately, but every recurring task's next instance
   would jump to the head of its sibling list on every close. For a daily
   standup or similar high-frequency recurrence this reorders a manually
   curated list (Lillist's whole ordering model is user-drag fractional
   positioning) once a day, every day, indefinitely — a much larger, more
   frequent disruption than a one-time capture landing at the top.
3. **Adjacent to the closed instance** (replace its visual slot) — requires
   new "insert between two arbitrary siblings" machinery
   (`FractionalPosition.position(after: closed.position, before:
   nextLiveSiblingAfterClosed.position)`) that doesn't exist yet anywhere in
   the codebase, for a benefit that doesn't clearly land: closed tasks are
   filtered out of the primary list surfaces today (`children(of:)` and the
   UI's active views), so "keeping the same visual slot" isn't visible to the
   user in the place it would matter.

**Decision: bottom.** It's the only option that (a) reuses already-tested,
already-`H4`-hardened machinery with zero new surface area, (b) can never
collide by construction (computed against the live sibling set at spawn
time, not a stale offset), and (c) doesn't silently reshuffle a manually
ordered list on a cadence the user didn't initiate. This isn't a close call
once "reuse tested machinery, never surprise-reorder the user's list" is
weighed against "requires new insert-between machinery for a benefit users
won't see" — no council needed.

### Fix — extract the position machinery, use it from `RecurrenceSpawner`

`TaskStore.nextPositionDetail(forParent:placement:)` is an *instance* method
reading `self.context`; `RecurrenceSpawner.spawnIfNeeded` is a `static` func
over a raw `NSManagedObjectContext` with no `TaskStore` instance available.
Rather than duplicate the fetch+`FractionalPosition` logic (DRY), extract the
core into a new file, `Ordering/SiblingPositioning.swift`:

```swift
enum SiblingPositioning {
    static func nextPositionDetail(
        forParent parent: LillistTask?,
        placement: NewTaskPlacement = .bottom,
        in context: NSManagedObjectContext
    ) throws -> (assigned: Double, observedMax: Double?)
}
```

`TaskStore.nextPositionDetail` becomes a one-line wrapper delegating to it
(`self.context` supplied); `RecurrenceSpawner.spawnIfNeeded` calls it
directly with the raw `context` it already has, `forParent: seed.parent,
placement: .bottom`. `spawnIfNeeded` becomes `throws` (the fetch can throw);
its one call site in `TaskStore.transition` already runs inside a `try
await context.perform { ... }` closure, so this is a one-`try` change at the
call site, not a new error-handling path.

### Tests

`H1PositionCollisionTests.swift` (new):
- Two consecutive closes of the same daily series produce three live/closed
  instances with three **distinct** positions (the direct collision
  reproduction — red under the current code, since spawn #2 and #3 both land
  at `seed.position + 0.5`).
- A spawn lands at the bottom of the parent's *current* live sibling set even
  when a manually created sibling was inserted between series closes (proves
  "live fetch," not "stale offset").
- A spawn under a series whose seed has since been reparented still resolves
  siblings against `seed.parent` correctly (parent can change independently
  of the series).
- Existing `TaskStoreRecurrenceSpawnTests` continue to pass unmodified
  (no assertions on exact numeric positions there today, so no update
  needed — verified by reading the file, not assumed).

---

## X7 — recurrence spawn has no idempotency key

### The mechanism this fix relies on

`TaskDuplicateReconciler` (`Persistence/TaskDuplicateReconciler.swift`,
delivered in `1a`) already detects and merges `LillistTask` rows sharing one
app-level `id`, re-pointing children/journal/attachments/notification specs
from the "loser" onto the "survivor" before deleting the loser — the exact
subtree-preserving merge the wave brief points at. It runs automatically on
every `NSPersistentStoreRemoteChange` plus once at bootstrap.

**Why two devices produce two managed-object rows today even for the "same"
conceptual occurrence:** `NSPersistentCloudKitContainer` mints a CKRecord
identity per local Core Data row (keyed off its own store metadata), not off
any app-level attribute. Two independently-created `LillistTask` rows — one
per device — become two independent CKRecords regardless of what values their
attributes hold. So even a fully deterministic app-level `id` doesn't prevent
two rows from existing after a concurrent double-spawn — it turns what would
otherwise be two *permanently un-reconcilable* rows (today: two random UUIDs,
no signal that they're "the same occurrence") into two rows the
already-shipped duplicate reconciler can *find and merge*, because it merges
on `id` equality. This is the whole fix: give the spawn (and its deep-copied
children) a deterministic `id`, then let `1a`'s existing machinery do the
rest.

### Design — deterministic UUIDv5 identity

New file `Recurrence/DeterministicUUID.swift`:

```swift
enum DeterministicUUID {
    /// RFC 4122 §4.3 version-5 UUID: SHA-1 over `namespace`'s 16 raw bytes
    /// followed by `name`'s UTF-8 bytes, variant/version bits set per spec.
    /// Same (namespace, name) always yields the same UUID.
    static func v5(namespace: UUID, name: String) -> UUID
}
```

Pure `Foundation` + `CryptoKit` (`Insecure.SHA1` — the RFC's mandated hash,
already an Apple-native framework, no new SPM dependency; `Insecure.` is
CryptoKit's own naming for algorithms that are cryptographically weak for
*security* purposes but remain the literal, non-negotiable spec for a
name-based UUID). Not a general-purpose crypto primitive — scoped to this one
identity derivation.

**Spawn identity:** `spawn.id = DeterministicUUID.v5(namespace: series.id,
name: <nextDate, precise>)`.

- `nextDate` (== `series.nextOccurrenceAfter`, read at the top of
  `spawnIfNeeded` *before* either racing process advances it) is the value
  both a concurrent widget-process close and a concurrent second-device close
  read as the *same already-stored* field — the race is over "who spawns
  first," not "what date is being spawned," so both sides compute the
  identical name input. (The value `nextOccurrenceAfter` gets advanced *to*
  for the *next* future spawn can differ by device timezone for `.calendar`
  rules — that's `X10`'s already-deferred `LIL-83` concern, not this one:
  it affects a *future* spawn's anchor, never this spawn's own identity.)
- Name encoding: `nextDate.timeIntervalSince1970.bitPattern` formatted as a
  fixed-width hex string — exact, unambiguous bit-for-bit identity between
  processes reading the same stored `Date`, no locale/format-string
  round-trip risk (Foundation's `Double` decimal `description` is
  round-trip-safe but this sidesteps the question entirely).
- `series.id` may be `nil` on a corrupted row (the model has no non-optional
  constraint anywhere — same trust posture as every other entity in this
  program). Falls back to `UUID()` (random) with a `RecurrenceLog` warning:
  idempotency for that one corrupted-series spawn is unrecoverable, but the
  spawn must not be blocked by it.

**Child-copy identity (`deepCopy`):** `copy.id = DeterministicUUID.v5(
namespace: <the copy's own newParent.id — either spawnID at the top level, or
the parent copy's own already-v5-derived id one level down>, name:
source.id.uuidString)`. `source.id` is the seed-subtree child's own stable,
pre-existing id — unaffected by any of this — so composing the (now
deterministic) parent copy's id as namespace with the stable source id as
name makes **the entire spawned subtree** deterministic, recursively, to
arbitrary depth: two devices independently deep-copying the same seed
subtree produce a copy tree with identical ids at every level, node-for-node.
A `source.id == nil` child (corrupted row) falls back to `UUID()`, same
resilience posture as the top-level fallback — no worse than today's
behavior for that one node.

```
Series (id: S)                    Device A spawn            Device B spawn
  seedTask ──┐                    v5(S, date) = T           v5(S, date) = T  ← same id
             │  children: [C1,C2]  ├─ copy(C1) = v5(T, C1)=X  ├─ copy(C1)=v5(T,C1)=X  ← same
             ▼                     └─ copy(C2) = v5(T, C2)=Y  └─ copy(C2)=v5(T,C2)=Y  ← same
```

Both devices' local rows for the spawn (`T`) and each child (`X`, `Y`) share
an `id` once both sync. `TaskDuplicateReconciler` finds each `id`-group,
picks the CloudKit-backed survivor, re-points relationships, deletes the
loser — exactly the mechanism `1a` shipped and `M3` (`4a`) hardened against
bursty-notification thrash.

### `nextOccurrenceAfter` advancement — no dedicated fix needed, verified

The *series row's* `nextOccurrenceAfter` field (the anchor for the
**following**, not-yet-spawned occurrence) is written by both racing
processes to the *same* computed value whenever they're deriving it from the
same rule + the same pre-race `nextOccurrenceAfter` (deterministic
`RecurrenceExpander` math, no randomness). `Series` saves go through the
store-wide `mergeByPropertyObjectTrump` policy (`PersistenceController`), so
whichever write actually lands last on that property simply overwrites with
an **identical** value — convergence by construction, not by a new
mechanism. (Cross-device *timezone* divergence in what `Calendar.current`
computes as "the next occurrence" is the already-filed, already-deferred
`LIL-83` — out of scope here, and irrelevant to *this* spawn's identity per
the point above.)

### Tests

`X7IdempotentSpawnTests.swift` (new):
- Same `(seriesID, occurrenceDate)` pair → `DeterministicUUID.v5` produces
  the same `UUID` every call (pure function contract).
- Different occurrence dates for the same series → different ids; same date,
  different series → different ids (no accidental collision across the two
  axes).
- Two independent `spawnIfNeeded` calls simulating a concurrent double-spawn
  from the same pre-race `series.nextOccurrenceAfter` (two separate contexts
  over the shared `MultiProcessStoreHarnessTests`-style two-controller,
  one-file setup, or two in-context calls against two freshly fetched `Series`
  faults — whichever reproduces the race deterministically without a live
  CloudKit round trip) produce spawns sharing the same `id`.
- A spawned subtree's children carry deterministic, colliding-on-purpose ids
  across two simulated concurrent spawns (deep-copy identity, 2+ levels deep).
- After both racing rows exist, `TaskDuplicateReconciler.reconcileDuplicates`
  (driven directly per its own test seam) collapses the pair to one survivor
  — the actual end-to-end proof the review asked for ("which the existing
  duplicate-reconciler machinery already heals"), not just an id-equality
  assertion in isolation.
- A close that does **not** race (single spawn, normal path) is unaffected —
  `TaskStoreRecurrenceSpawnTests` continue to pass unmodified except any spot
  that literally asserted "spawn ids are random" (none currently do — checked
  by reading the file).

---

## X16 — `AfterCompletionRule.interval` is unvalidated

### Fix — mirror `CalendarRule`'s two-sided clamp, at both trust boundaries

`AfterCompletionRule.interval: TimeInterval` gets the identical shape
`CalendarRule.interval: Int` already has:

```swift
public struct AfterCompletionRule: Codable, Sendable, Equatable {
    public var interval: TimeInterval
    public init(interval: TimeInterval) { self.interval = Self.normalizedInterval(interval) }
    public init(from decoder: Decoder) throws { ... self.interval = Self.normalizedInterval(...) }

    static let minInterval: TimeInterval = 1          // must be strictly positive
    static let maxInterval: TimeInterval = 86_400 * 365 * 10   // 10 years
    static func clampedInterval(_ raw: TimeInterval) -> TimeInterval {
        min(maxInterval, max(minInterval, raw))
    }
    private static func normalizedInterval(_ raw: TimeInterval) -> TimeInterval { /* clamp + RecurrenceLog.normalization.warning, same shape */ }
}
```

**Bound values, decided directly:**
- **Low (1 second):** the finding is specifically "0/negative interval
  spawns permanently-overdue tasks" — a 0 or negative interval sets the
  spawned due date at-or-before the completion instant. `1` second is the
  minimal floor that fully eliminates that class without inventing a new UX
  floor the review never asked for (the first-party editor's own minimum,
  1 day, is a UI choice, not a validity boundary — the clamp is a
  trust-boundary backstop for CloudKit/Importer/CLI input, same posture as
  `CalendarRule`'s).
- **High (10 years):** unlike `CalendarRule.interval`, this field has no
  looping/month-scan consumer — `nextAfterCompletion` is one
  `addingTimeInterval` call, so there's no algorithmic hang/overflow hazard
  the way an unbounded `CalendarRule.interval` has. The upper bound exists
  purely so the clamp *shape* matches `CalendarRule`'s two-sided design (per
  the wave brief) and so `Date` arithmetic never approaches
  `Date.distantFuture`/overflow territory from an absurd `TimeInterval`.

**Defense-in-depth at the point of use**, mirroring `CalendarRule`'s
`effectiveInterval` (which re-clamps at every `step()` call in case a rule's
mutable `var interval` was forced out of range after construction —
`RecurrenceExpanderIntervalGuardTests` already covers this pattern for
`CalendarRule`): `RecurrenceExpander.nextAfterCompletion` re-clamps via
`AfterCompletionRule.clampedInterval(rule.interval)` before adding, not just
trusting the value the initializer normalized.

### Two pre-existing tests contradict the fix — update in the same commit

`RecurrenceExpanderAfterCompletionTests.swift` has two tests whose names and
assertions **document the pre-fix bug as intended behavior**:
- `zeroInterval` — "Zero interval returns the same instant" (will become
  `completed + 1s` post-clamp).
- `negativeIntervalAllowed` — "Negative interval is permitted... caller's
  responsibility" (will become `completed + 1s`, no longer earlier than
  `completed`).

Per two-hats discipline this is the fix's own behavior change, not a
separate refactor — both tests are rewritten in the same commit as the fix
(red: old assertions fail against clamped output; green: rewritten
assertions match the new, correct behavior), not left in place contradicting
shipped code.

### Tests

`X16AfterCompletionIntervalClampTests.swift` (new):
- `interval: 0` and `interval: -60` both normalize to `minInterval` (1s) at
  construction.
- Decoding a v1-shaped JSON payload with `"interval": -100` produces a
  clamped `AfterCompletionRule` (decode-boundary coverage, same shape as
  `RecurrenceRuleCodingTests`' existing `CalendarRule` decode tests).
- A rule whose `interval` is mutated to `0`/negative *after* construction
  (defeating the init-time clamp, same "defeat the boundary" technique
  `RecurrenceExpanderIntervalGuardTests` uses for `CalendarRule`) still
  produces `nextAfterCompletion(completedAt:) > completedAt` — the
  point-of-use defense-in-depth.
- `interval: .greatestFiniteMagnitude` clamps to `maxInterval`, and
  `nextAfterCompletion` returns a finite, valid `Date` (no overflow/trap).
- End-to-end: `RecurrenceSpawner.spawnIfNeeded` against an
  `.afterCompletion` series whose rule was constructed with an invalid raw
  interval (bypassing the clamp the same way, or fed through a hand-built
  JSON decode) spawns a task whose `start` is strictly after `closedAt` —
  the actual "permanently-overdue" symptom, closed at the integration level.

---

## X17 — weekly `byDay` hardcodes a Sunday week boundary

### Root cause

`RecurrenceExpander.weeklyStep` (`RecurrenceExpander.swift:74-93`) computes
same-week-vs-next-week using `Weekday.calendarComponent` values directly
(`Sun=1...Sat=7`, per `Weekday`'s own doc comment: "Apple `Calendar` uses
Sunday=1...Saturday=7 **regardless of `firstWeekday`**"). That numbering is
Apple's fixed *day-of-week* encoding, not a week-grouping — but
`weeklyStep`'s arithmetic (`sortedDays.first(where: { $0.calendarComponent >
previousWeekday })`, and the wraparound's `daysToEndOfWeek = 7 -
previousWeekday + firstNext.calendarComponent`) treats "day 1 (Sunday) starts
a new week" as baked-in truth, ignoring whatever `calendar.firstWeekday`
actually is. `RecurrenceSpawner`/`SeriesStore` both call this with
`Calendar.current` — a real device's locale-derived calendar, whose
`firstWeekday` varies (1=Sunday in en_US, 2=Monday in most of Europe, other
values elsewhere).

**Concretely** (worked in the plan's research, not just asserted): a
biweekly SA/SU rule under a Monday-first calendar (`firstWeekday = 2`),
stepping from a Sunday seed, should land the next SA/SU pair one full
Monday-first week later than the immediate next day — but the hardcoded
Sunday-boundary arithmetic instead treats the immediate-next Saturday (6 days
away, still "this Sunday-first week") as the answer, producing an occurrence
one week too early and silently drifting the whole subsequent sequence. The
mid-week ("later this week") branch is unaffected for day pairs that don't
straddle the *actual* week boundary (verified by hand against the existing
`tthBiweekly`/`mwfPattern` tests below) — only pairs adjacent to the true
`firstWeekday` seam diverge.

### Fix — offset from `calendar.firstWeekday`, not from raw `calendarComponent`

```swift
private static func weeklyStep(
    from previous: Date,
    rule: RecurrenceRule.CalendarRule,
    calendar: Calendar
) -> Date? {
    let n = effectiveInterval(rule.interval)
    guard let byDay = rule.byDay, byDay.isEmpty == false else {
        return calendar.date(byAdding: .weekOfYear, value: n, to: previous)
    }
    // X17: `Weekday.calendarComponent` is always Sunday=1...Saturday=7
    // (Apple's fixed day numbering); `weekOffset` re-bases that onto "days
    // since THIS calendar's week start" (RFC 5545 WKST == `firstWeekday`)
    // so same-week-vs-next-week decisions below match the calendar's own
    // week grouping instead of assuming Sunday starts every week.
    func weekOffset(_ component: Int) -> Int { (component - calendar.firstWeekday + 7) % 7 }

    let previousOffset = weekOffset(calendar.component(.weekday, from: previous))
    let sortedDays = byDay.sorted { weekOffset($0.calendarComponent) < weekOffset($1.calendarComponent) }
    if let next = sortedDays.first(where: { weekOffset($0.calendarComponent) > previousOffset }) {
        let delta = weekOffset(next.calendarComponent) - previousOffset
        return calendar.date(byAdding: .day, value: delta, to: previous)
    }
    let firstNext = sortedDays.first!
    let daysToEndOfWeek = 7 - previousOffset + weekOffset(firstNext.calendarComponent)
    let totalDays = daysToEndOfWeek + 7 * (n - 1)
    return calendar.date(byAdding: .day, value: totalDays, to: previous)
}
```

Single-day `byDay` rules are unaffected (hand-verified: with one element the
"later this week" branch never matches — `weekOffset` of the sole day can
never exceed itself — so every step falls through to the wraparound formula,
which reduces to `7 * n` regardless of `firstWeekday` when `firstNext ==
previousDay`). Multi-day rules that don't straddle the true week boundary are
also unaffected — deltas between two offsets computed against the *same*
reference point are invariant to what that reference point is, as long as
neither day wraps around it (hand-verified against `tthBiweekly` below).

### Week-boundary semantics table (firstWeekday values tested)

| `firstWeekday` | Locale example | Week model | SA/SU relationship |
|---|---|---|---|
| `1` (Sunday) | en_US | Sun...Sat | SU starts the week, SA ends it — adjacent but in *different* week-groups |
| `2` (Monday) | most of Europe, Lillist's own `Weekday` UI ordering | Mon...Sun | SA and SU are adjacent days in the *same* week-group (day 6, day 7) |
| `7` (Saturday) | e.g. `AR` locale variants | Sat...Fri | SA starts the week, SU is day 2 — adjacent, *same* week-group, but SA no longer trails SU |

### Tests

`X17WeekBoundaryLocaleTests.swift` (new), parameterized across the three
`firstWeekday` values above via a new `RecurrenceTestCalendar.calendar(firstWeekday:)`
factory (reuses `pacific`'s timezone, varies only `firstWeekday` — the "locale
seam" the wave brief points at):
- Biweekly SA/SU stepping from a Sunday seed produces the correct
  week-grouped pair under each of the three `firstWeekday` values (three
  `@Test` cases or one parameterized `@Test(arguments:)`), asserting the
  **specific dates**, not just "some date" — this is the direct regression
  proof, red under the current hardcoded-Sunday arithmetic for `firstWeekday
  != 1`.
- Existing `RecurrenceExpanderWeeklyTests` (`plainWeekly`, `biweekly`,
  `mwfPattern`, `tthBiweekly`, `preservesTime`) continue to pass unmodified —
  hand-verified in this plan's research that TU/TH and MO/WE/FR pairs don't
  straddle any `firstWeekday` boundary, so their fixed `pacific`
  (`firstWeekday = 2`) expectations are unaffected by the fix; the full suite
  run confirms this empirically, not just by hand-derivation.
- `RecurrenceExpanderIntervalGuardTests`' weekly cases (`weeklyZeroWithByDay`,
  `weeklyNegativeWithByDay`) continue to pass unmodified — they assert
  "treated as interval 1," a property of `effectiveInterval`, orthogonal to
  the `weekOffset` change.

---

## Verification plan

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test --package-path Packages/LillistCore --parallel --num-workers 2 > /tmp/suite.log 2>&1; echo EXIT:$?
grep -E "Test Suite .* failed|Note: Some test targets reported failures" /tmp/suite.log
```

Per the binding *Verification protocol*: unmasked exit code, clean grep, run
**twice**. No app-target files are touched by this plan (pure `LillistCore`
engine change) — if that changes during implementation, add unsigned
`xcodebuild` builds for both apps before closing.

## Commit plan (two hats, one red→green cycle per commit)

1. `docs(plan): commit plan 4c` — this document.
2. `fix(core): H1 — recurrence spawn uses live sibling positioning, not a
   stale seed offset` — `SiblingPositioning.swift` (new), `TaskStore.swift`
   (delegate), `RecurrenceSpawner.swift` (`throws` + call), `H1PositionCollisionTests.swift`.
3. `feat(core): X16 — clamp AfterCompletionRule.interval at both trust
   boundaries` — `RecurrenceRule.swift`, `RecurrenceExpander.swift`
   (point-of-use clamp), `RecurrenceExpanderAfterCompletionTests.swift`
   (two pre-existing tests rewritten — behavior change, same commit as the
   fix per two-hats), `X16AfterCompletionIntervalClampTests.swift`.
4. `fix(core): X17 — weekly byDay respects calendar.firstWeekday, not a
   hardcoded Sunday boundary` — `RecurrenceExpander.swift`,
   `RecurrenceTestCalendar.swift` (`calendar(firstWeekday:)` factory),
   `X17WeekBoundaryLocaleTests.swift`.
5. `feat(core): X7 — deterministic UUIDv5 identity for recurrence spawns and
   their deep-copied children` — `DeterministicUUID.swift` (new),
   `RecurrenceSpawner.swift`, `X7IdempotentSpawnTests.swift`.
6. `chore(stories): close LIL-19, LIL-38, LIL-65, LIL-66` — story moves +
   ledger update.

Each commit's own red→green cycle runs the verification gate above before
moving to the next commit.
