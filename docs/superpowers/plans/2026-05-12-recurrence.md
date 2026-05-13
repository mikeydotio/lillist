# Lillist Plan 4 — Recurrence Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `LillistCore` with the Apple Calendar / Reminders-style recurrence model — `Series` + instances with edit-this-one and edit-all-future. Tasks belong to a `Series` via a new `series` relationship. Completing an instance spawns the next one. Editing a non-seed instance creates a forked `Series`. The model supports both calendar-driven rules (an RRULE subset with DST-correct math and proper `byMonthDay = 31` skip-month handling) and after-completion rules (interval from the moment the previous instance closed).

**Architecture:** A new entity (`Series`) is added to `LillistModel.xcdatamodeld`. A new relationship `series` is added to `LillistTask`. Recurrence rules live as a Codable `RecurrenceRule` value type, JSON-encoded into `Series.ruleJSON`. A pure-Swift `RecurrenceExpander` produces occurrence dates from a rule + a seed date — DST-correct via `Calendar.current` + `DateComponents`, never absolute seconds. A `SeriesStore` provides CRUD over series and `forkFutureFromInstance`. A `RecurrenceSpawner` is invoked from `TaskStore.transition(to: .closed)` to spawn the next instance, copy the seed's children, and update `Series.nextOccurrenceAfter`. Re-opening a closed instance does **not** undo the spawn — that's a one-way operation per design Section 8.

**Tech Stack:** Swift 6, Swift Package Manager, Core Data, Swift Testing. No new dependencies. Uses `JSONEncoder`/`JSONDecoder` for the rule blob and `Calendar.current` for all date math (test code sets a fixed `Calendar` + `TimeZone` to keep expectations stable).

This plan depends on Plan 1 (Foundation). It assumes `LillistTask`, `TaskStore`, `JournalStore`, `Validators`, `LillistError`, `PersistenceController`, and `TestStore` from Plan 1 already exist with the public surface described there.

---

## File Structure

```
Packages/LillistCore/
├── Sources/
│   └── LillistCore/
│       ├── Model/
│       │   └── LillistModel.xcdatamodeld/
│       │       └── LillistModel.xcdatamodel/
│       │           └── contents                                  (modified — adds Series entity + LillistTask.series + LillistTask.seriesAsSeed)
│       ├── ManagedObjects/
│       │   └── Series+CoreData.swift                             (new — typed rule accessor over ruleJSON)
│       ├── Recurrence/                                           (new directory)
│       │   ├── Weekday.swift                                     (Mon..Sun enum)
│       │   ├── RecurrenceRule.swift                              (Codable value type — calendar + afterCompletion)
│       │   ├── RecurrenceExpander.swift                          (pure-Swift occurrence generator)
│       │   └── RecurrenceSpawner.swift                           (closure-on-completion hook)
│       └── Stores/
│           ├── SeriesStore.swift                                 (new — CRUD + forkFutureFromInstance)
│           └── TaskStore.swift                                   (modified — call RecurrenceSpawner from transition)
└── Tests/
    └── LillistCoreTests/
        ├── Recurrence/                                           (new directory)
        │   ├── WeekdayTests.swift
        │   ├── RecurrenceRuleCodingTests.swift
        │   ├── RecurrenceExpanderDailyTests.swift
        │   ├── RecurrenceExpanderWeeklyTests.swift
        │   ├── RecurrenceExpanderMonthlyTests.swift
        │   ├── RecurrenceExpanderYearlyTests.swift
        │   ├── RecurrenceExpanderBySetPosTests.swift
        │   ├── RecurrenceExpanderDSTTests.swift
        │   ├── RecurrenceExpanderByMonthDay31Tests.swift
        │   ├── RecurrenceExpanderAfterCompletionTests.swift
        │   └── RecurrenceExpanderLimitTests.swift
        ├── Stores/
        │   ├── SeriesStoreCRUDTests.swift
        │   ├── SeriesStoreForkTests.swift
        │   └── TaskStoreRecurrenceSpawnTests.swift
        └── Helpers/
            └── RecurrenceTestCalendar.swift                      (fixed-calendar helper for deterministic tests)
```

---

## Notes for the Implementer

**Read Design Section 2 (Series) and Section 8 (Recurrence edge cases) before starting.** Section 2 defines the data shape (`seedTask`, `nextOccurrenceAfter`, the calendar/after-completion split). Section 8 nails down the edge cases: DST preserves wall-clock time, `byMonthDay = 31` skips short months (does *not* coerce to the 30th), re-opening a closed instance does **not** undo the spawn, and `until` mid-flight leaves existing instances alone.

**Calendar safety.** Every date computation in `RecurrenceExpander` uses `Calendar.dateComponents` / `Calendar.date(from:)` / `Calendar.date(byAdding:to:)` against `Calendar.current` — never `Date.addingTimeInterval` for calendar-aware adjustments. The only exception is `.afterCompletion`, where the design explicitly specifies an absolute `TimeInterval`. Tests that depend on DST or timezone behavior construct an explicit `Calendar(identifier: .gregorian)` with a specific `timeZone` and pass it through — see Task 4 for the helper.

**CloudKit compatibility (still applies here).** Every new attribute and relationship is optional at the schema level. No `Deny` deletion rules. Every relationship has an inverse. Plan 2 already swapped to `NSPersistentCloudKitContainer`; we keep that invariant.

**Re-using `Validators`.** No new validation helpers should be needed; cycle prevention for tasks is unchanged.

**Spawner hook placement.** `TaskStore.transition` from Plan 1 already writes a `statusChange` journal entry. We add a hook *after* the save: if the transition is to `.closed`, we invoke `RecurrenceSpawner.spawnIfNeeded(forClosedTask:in:)`. The spawner runs inside the same `viewContext` perform block as the transition so the spawn is atomic with the close. Re-opening (a transition *out of* `.closed`) does not invoke the spawner — this matches design Section 8's "spawn already happened; not undone" rule.

**Series limit semantics.** A `Series` with `count` reached has `nextOccurrenceAfter = nil` and the spawner refuses. A `Series` with `until` set whose next computed occurrence falls strictly after `until` also has `nextOccurrenceAfter = nil` and the spawner refuses. Reaching the limit does not delete the series — instances remain queryable.

**Concurrency.** All new stores follow Plan 1's pattern: `@unchecked Sendable` final classes, viewContext `perform`, value-type DTOs (`SeriesRecord`) crossing the boundary.

**Commits.** Conventional-commit prefixes: `feat:`, `test:`, `chore:`, `fix:`, `refactor:`.

**Verification command:** `cd Packages/LillistCore && swift test`.

---

## Task 1: Extend the Core Data model with `Series` entity and `LillistTask.series` relationship

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`

Plan 1 produced a five-entity model (`LillistTask`, `Tag`, `JournalEntry`, `Attachment`, `AppPreferences`). We add a sixth — `Series` — and two new relationships on `LillistTask`. **All attributes optional, no `Deny` rules, every relationship has an inverse** (per Plan 1 invariants and design Section 3).

The relationships:

- `Series.seedTask: LillistTask?` (to-one, `Nullify`) — inverse `LillistTask.seriesAsSeed: Series?`.
- `Series.instances: Set<LillistTask>` (to-many, `Nullify`) — inverse `LillistTask.series: Series?`.

The second relationship is the membership pointer for every instance (including the seed, which is *both* `Series.seedTask` and a member of `Series.instances`).

- [ ] **Step 1: Read the current model `contents` file**

Run: `cat Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`

Confirm Plan 1's five entities are present.

- [ ] **Step 2: Apply the XML diff**

Diff (additions in `+`, modifications in `~`):

```diff
     <entity name="LillistTask" representedClassName="LillistTask" syncable="YES">
         <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
         ...existing attributes unchanged...
         <relationship name="parent" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="LillistTask" inverseName="children" inverseEntity="LillistTask"/>
         <relationship name="children" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="LillistTask" inverseName="parent" inverseEntity="LillistTask"/>
         <relationship name="tags" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="Tag" inverseName="tasks" inverseEntity="Tag"/>
         <relationship name="journalEntries" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="JournalEntry" inverseName="task" inverseEntity="JournalEntry"/>
         <relationship name="attachments" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="Attachment" inverseName="task" inverseEntity="Attachment"/>
+        <relationship name="series" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Series" inverseName="instances" inverseEntity="Series"/>
+        <relationship name="seriesAsSeed" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Series" inverseName="seedTask" inverseEntity="Series"/>
     </entity>
     ...other existing entities unchanged...
+    <entity name="Series" representedClassName="Series" syncable="YES">
+        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
+        <attribute name="ruleJSON" optional="YES" attributeType="String"/>
+        <attribute name="nextOccurrenceAfter" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
+        <relationship name="seedTask" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="LillistTask" inverseName="seriesAsSeed" inverseEntity="LillistTask"/>
+        <relationship name="instances" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="LillistTask" inverseName="series" inverseEntity="LillistTask"/>
+    </entity>
 </model>
```

Apply this diff to `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`. The two new relationships on `LillistTask` go after the existing `attachments` relationship; the new `Series` entity goes before the closing `</model>` tag.

- [ ] **Step 3: Build to confirm Core Data picks up the new entity**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds. Core Data auto-generates a `Series` NSManagedObject subclass with `id`, `ruleJSON`, `nextOccurrenceAfter`, `seedTask`, and `instances` accessors.

- [ ] **Step 4: Run the existing test suite to confirm no regressions**

Run: `cd Packages/LillistCore && swift test`
Expected: every Plan 1 (and Plans 2/3) test still passes. The schema addition is purely additive.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/
git commit -m "feat(model): add Series entity and LillistTask.series/seriesAsSeed relationships"
```

---

## Task 2: Define `Weekday` enum

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Recurrence/Weekday.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/WeekdayTests.swift`

`Weekday` mirrors RRULE's `BYDAY` codes. We use Monday-first ordering (matches ISO 8601 and most non-US task managers) but expose a converter to Core Foundation's Sunday-first integers for `Calendar` interop.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/WeekdayTests.swift`:

```swift
import Testing
@testable import LillistCore

@Suite("Weekday")
struct WeekdayTests {
    @Test("Raw values are RRULE-stable codes")
    func rawValues() {
        #expect(Weekday.monday.rawValue == "MO")
        #expect(Weekday.tuesday.rawValue == "TU")
        #expect(Weekday.wednesday.rawValue == "WE")
        #expect(Weekday.thursday.rawValue == "TH")
        #expect(Weekday.friday.rawValue == "FR")
        #expect(Weekday.saturday.rawValue == "SA")
        #expect(Weekday.sunday.rawValue == "SU")
    }

    @Test("All cases enumerable")
    func allCases() {
        #expect(Weekday.allCases.count == 7)
    }

    @Test("calendarComponent maps to Calendar's Sunday-first 1...7")
    func calendarComponentMapping() {
        #expect(Weekday.sunday.calendarComponent == 1)
        #expect(Weekday.monday.calendarComponent == 2)
        #expect(Weekday.tuesday.calendarComponent == 3)
        #expect(Weekday.wednesday.calendarComponent == 4)
        #expect(Weekday.thursday.calendarComponent == 5)
        #expect(Weekday.friday.calendarComponent == 6)
        #expect(Weekday.saturday.calendarComponent == 7)
    }

    @Test("Round-trip from calendarComponent")
    func fromCalendarComponent() {
        for d in Weekday.allCases {
            #expect(Weekday(calendarComponent: d.calendarComponent) == d)
        }
    }

    @Test("Invalid calendarComponent returns nil")
    func invalidCalendarComponent() {
        #expect(Weekday(calendarComponent: 0) == nil)
        #expect(Weekday(calendarComponent: 8) == nil)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter WeekdayTests`
Expected: FAIL — `Weekday` undefined.

- [ ] **Step 3: Write implementation**

Write `Packages/LillistCore/Sources/LillistCore/Recurrence/Weekday.swift`:

```swift
import Foundation

/// A day of the week, encoded as the two-letter RRULE code (`MO`..`SU`).
///
/// Raw values are persisted in `RecurrenceRule` JSON; never renumber.
public enum Weekday: String, CaseIterable, Codable, Sendable {
    case monday = "MO"
    case tuesday = "TU"
    case wednesday = "WE"
    case thursday = "TH"
    case friday = "FR"
    case saturday = "SA"
    case sunday = "SU"

    /// Apple `Calendar` uses Sunday=1...Saturday=7 regardless of `firstWeekday`.
    /// This property bridges Lillist's Monday-first ordering to that scheme
    /// for use with `DateComponents.weekday`.
    public var calendarComponent: Int {
        switch self {
        case .sunday:    return 1
        case .monday:    return 2
        case .tuesday:   return 3
        case .wednesday: return 4
        case .thursday:  return 5
        case .friday:    return 6
        case .saturday:  return 7
        }
    }

    /// Inverse of `calendarComponent`. Returns `nil` for out-of-range input.
    public init?(calendarComponent value: Int) {
        switch value {
        case 1: self = .sunday
        case 2: self = .monday
        case 3: self = .tuesday
        case 4: self = .wednesday
        case 5: self = .thursday
        case 6: self = .friday
        case 7: self = .saturday
        default: return nil
        }
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter WeekdayTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Recurrence/Weekday.swift Packages/LillistCore/Tests/LillistCoreTests/Recurrence/WeekdayTests.swift
git commit -m "feat(recurrence): add Weekday enum with Calendar-component bridge"
```

---

## Task 3: Define `RecurrenceRule` Codable value type

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceRuleCodingTests.swift`

The rule is a sum type with two variants:

1. `.calendar(CalendarRule)` — RRULE subset: `freq`, `interval`, optional `byDay`, `byMonthDay`, `bySetPos`, `count`, `until`.
2. `.afterCompletion(AfterCompletionRule)` — fixed `TimeInterval` from the moment the previous instance closed.

JSON encoding uses a `type` discriminator so we can evolve safely.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceRuleCodingTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceRule coding")
struct RecurrenceRuleCodingTests {
    @Test("Round-trip daily calendar rule")
    func dailyRoundTrip() throws {
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == rule)
    }

    @Test("Round-trip weekly with byDay")
    func weeklyByDay() throws {
        let rule = RecurrenceRule.calendar(.init(
            freq: .weekly,
            interval: 2,
            byDay: [.monday, .wednesday, .friday]
        ))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == rule)
    }

    @Test("Round-trip monthly with byMonthDay + bySetPos + count")
    func monthlyComplex() throws {
        let rule = RecurrenceRule.calendar(.init(
            freq: .monthly,
            interval: 1,
            byMonthDay: [15],
            bySetPos: [1],
            count: 12
        ))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == rule)
    }

    @Test("Round-trip yearly with until")
    func yearlyUntil() throws {
        let until = Date(timeIntervalSince1970: 1_800_000_000)
        let rule = RecurrenceRule.calendar(.init(freq: .yearly, interval: 1, until: until))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == rule)
    }

    @Test("Round-trip after-completion rule")
    func afterCompletionRoundTrip() throws {
        let rule = RecurrenceRule.afterCompletion(.init(interval: 86_400 * 3))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == rule)
    }

    @Test("Type discriminator is stable across encodes")
    func discriminatorStable() throws {
        let cal = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let after = RecurrenceRule.afterCompletion(.init(interval: 60))
        let calJSON = String(data: try JSONEncoder().encode(cal), encoding: .utf8)!
        let afterJSON = String(data: try JSONEncoder().encode(after), encoding: .utf8)!
        #expect(calJSON.contains("\"type\":\"calendar\""))
        #expect(afterJSON.contains("\"type\":\"afterCompletion\""))
    }

    @Test("Unknown type discriminator rejects with decoding error")
    func unknownTypeRejected() {
        let bogus = "{\"type\":\"never-heard-of-it\"}"
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                RecurrenceRule.self,
                from: Data(bogus.utf8)
            )
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceRuleCodingTests`
Expected: FAIL — type undefined.

- [ ] **Step 3: Write implementation**

Write `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift`:

```swift
import Foundation

/// A recurrence specification for a `Series`.
///
/// Two variants per design Section 2:
///   - `.calendar` — RRULE-subset (`freq`, `interval`, `byDay`, `byMonthDay`,
///     `bySetPos`, optional `count` and `until`).
///   - `.afterCompletion` — fixed `TimeInterval` from the moment the previous
///     instance was closed.
///
/// JSON-encoded into `Series.ruleJSON`. A `type` discriminator distinguishes the
/// two variants; never rename or remove discriminator values.
public enum RecurrenceRule: Codable, Sendable, Equatable {
    case calendar(CalendarRule)
    case afterCompletion(AfterCompletionRule)

    public enum Frequency: String, Codable, Sendable {
        case daily, weekly, monthly, yearly
    }

    public struct CalendarRule: Codable, Sendable, Equatable {
        public var freq: Frequency
        public var interval: Int
        public var byDay: [Weekday]?
        public var byMonthDay: [Int]?
        public var bySetPos: [Int]?
        public var count: Int?
        public var until: Date?

        public init(
            freq: Frequency,
            interval: Int,
            byDay: [Weekday]? = nil,
            byMonthDay: [Int]? = nil,
            bySetPos: [Int]? = nil,
            count: Int? = nil,
            until: Date? = nil
        ) {
            self.freq = freq
            self.interval = interval
            self.byDay = byDay
            self.byMonthDay = byMonthDay
            self.bySetPos = bySetPos
            self.count = count
            self.until = until
        }
    }

    public struct AfterCompletionRule: Codable, Sendable, Equatable {
        public var interval: TimeInterval
        public init(interval: TimeInterval) {
            self.interval = interval
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case rule
    }

    private enum RuleType: String, Codable {
        case calendar
        case afterCompletion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(RuleType.self, forKey: .type)
        switch type {
        case .calendar:
            self = .calendar(try c.decode(CalendarRule.self, forKey: .rule))
        case .afterCompletion:
            self = .afterCompletion(try c.decode(AfterCompletionRule.self, forKey: .rule))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .calendar(let r):
            try c.encode(RuleType.calendar, forKey: .type)
            try c.encode(r, forKey: .rule)
        case .afterCompletion(let r):
            try c.encode(RuleType.afterCompletion, forKey: .type)
            try c.encode(r, forKey: .rule)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceRuleCodingTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceRuleCodingTests.swift
git commit -m "feat(recurrence): add RecurrenceRule Codable value type"
```

---

## Task 4: Test helper — fixed-calendar utility

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Helpers/RecurrenceTestCalendar.swift`

All recurrence tests need a deterministic `Calendar` + `TimeZone` so that "next Monday after 2026-01-01" is the same regardless of where CI runs. We expose a helper with one specific timezone (`America/Los_Angeles`) used by most tests, with a method to construct dates from `(year, month, day, hour, minute)` tuples.

- [ ] **Step 1: Write the helper (test code, no production tests needed)**

Write `Packages/LillistCore/Tests/LillistCoreTests/Helpers/RecurrenceTestCalendar.swift`:

```swift
import Foundation

/// Deterministic `Calendar` + helpers for recurrence tests.
///
/// All recurrence math is calendar-aware (DST-correct, month-length-aware).
/// Tests pin to a specific timezone to keep expectations stable across CI machines.
enum RecurrenceTestCalendar {
    /// Pacific Time — chosen because it has clean DST transitions to assert against.
    static let pacific: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.firstWeekday = 2 // Monday — but most math is weekday-explicit so this is harmless.
        return c
    }()

    /// UTC — used when the test doesn't care about wall-clock semantics
    /// but does care about deterministic Date arithmetic.
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    /// Builds a `Date` in `calendar`'s timezone from explicit components.
    static func date(
        in calendar: Calendar = Self.pacific,
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        c.second = 0
        return calendar.date(from: c)!
    }
}
```

- [ ] **Step 2: Build to confirm the helper compiles into the test target**

Run: `cd Packages/LillistCore && swift build --target LillistCoreTests`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Helpers/RecurrenceTestCalendar.swift
git commit -m "test(recurrence): add fixed-calendar helper for deterministic date math"
```

---

## Task 5: `RecurrenceExpander` — daily frequency

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderDailyTests.swift`

We build `RecurrenceExpander` frequency-by-frequency. Daily is the simplest: add `interval` days to the previous occurrence. Wall-clock time-of-day preserved.

- [ ] **Step 1: Write failing tests for daily**

Write `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderDailyTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander daily")
struct RecurrenceExpanderDailyTests {
    @Test("Daily interval=1 produces consecutive days")
    func dailyEveryDay() throws {
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1)
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1, hour: 9)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        #expect(dates == [
            RecurrenceTestCalendar.date(year: 2026, month: 1, day: 2, hour: 9),
            RecurrenceTestCalendar.date(year: 2026, month: 1, day: 3, hour: 9),
            RecurrenceTestCalendar.date(year: 2026, month: 1, day: 4, hour: 9)
        ])
    }

    @Test("Daily interval=3 skips two days each step")
    func dailyEveryThirdDay() throws {
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 3)
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 6, day: 1, hour: 14)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 4
        )
        #expect(dates.map { RecurrenceTestCalendar.pacific.component(.day, from: $0) } == [4, 7, 10, 13])
    }

    @Test("Daily count=2 yields exactly 2 occurrences even when callers ask for more")
    func dailyCountCap() throws {
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, count: 2)
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 10
        )
        #expect(dates.count == 2)
    }

    @Test("Daily until cuts off the stream")
    func dailyUntilCutoff() throws {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let until = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 3, hour: 23, minute: 59)
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, until: until)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 10
        )
        #expect(dates.count == 2) // Jan 2 and Jan 3.
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderDailyTests`
Expected: FAIL — `RecurrenceExpander` undefined.

- [ ] **Step 3: Write the expander skeleton + daily implementation**

Write `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift`:

```swift
import Foundation

/// Pure-Swift expansion of a `RecurrenceRule` into a stream of occurrence dates.
///
/// Calendar-aware throughout: uses `Calendar.date(byAdding:)` rather than
/// `Date.addingTimeInterval`, so DST transitions preserve wall-clock time
/// (design Section 8). `byMonthDay = 31` skips short months rather than
/// coercing to the 30th (design Section 8).
public enum RecurrenceExpander {

    /// Returns up to `count` occurrences strictly after `seed`, respecting
    /// the rule's `count` and `until` caps.
    ///
    /// - Parameters:
    ///   - seed: The previous occurrence. Output dates are strictly after it.
    ///   - rule: The calendar rule. (`.afterCompletion` is handled separately
    ///     via `nextAfterCompletion(completedAt:rule:)`.)
    ///   - calendar: Calendar to use for all date math. Tests pin to a fixed
    ///     calendar; production passes `Calendar.current`.
    ///   - count: Soft cap on returned occurrences. Rule's own `count`/`until`
    ///     may produce fewer.
    public static func nextOccurrences(
        after seed: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar,
        count: Int
    ) -> [Date] {
        guard count > 0 else { return [] }
        var out: [Date] = []
        var cursor = seed
        let hardCap = rule.count.map { min($0, count) } ?? count

        while out.count < hardCap {
            guard let next = step(from: cursor, rule: rule, calendar: calendar) else {
                break
            }
            if let until = rule.until, next > until { break }
            out.append(next)
            cursor = next
        }
        return out
    }

    /// Computes the next occurrence after `completedAt` for an
    /// `.afterCompletion` rule.
    public static func nextAfterCompletion(
        completedAt: Date,
        rule: RecurrenceRule.AfterCompletionRule
    ) -> Date {
        completedAt.addingTimeInterval(rule.interval)
    }

    // MARK: - Frequency dispatch

    private static func step(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        switch rule.freq {
        case .daily:
            return calendar.date(byAdding: .day, value: rule.interval, to: previous)
        case .weekly:
            return nil  // implemented in Task 6
        case .monthly:
            return nil  // implemented in Task 7
        case .yearly:
            return nil  // implemented in Task 8
        }
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderDailyTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderDailyTests.swift
git commit -m "feat(recurrence): add RecurrenceExpander with daily frequency"
```

---

## Task 6: `RecurrenceExpander` — weekly frequency with `byDay`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderWeeklyTests.swift`

Weekly semantics:
- No `byDay`: same weekday as seed, every `interval` weeks.
- With `byDay`: within each `interval`-week window, fire on the listed weekdays in order. So `weekly interval=1 byDay=[MO,WE,FR]` fires Mon, Wed, Fri, Mon, Wed, Fri…

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderWeeklyTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander weekly")
struct RecurrenceExpanderWeeklyTests {
    @Test("Weekly with no byDay repeats the seed's weekday")
    func plainWeekly() {
        // 2026-01-05 is a Monday.
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 5, hour: 9)
        let rule = RecurrenceRule.CalendarRule(freq: .weekly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let weekdays = dates.map { RecurrenceTestCalendar.pacific.component(.weekday, from: $0) }
        #expect(weekdays == [Weekday.monday.calendarComponent,
                              Weekday.monday.calendarComponent,
                              Weekday.monday.calendarComponent])
        let days = dates.map { RecurrenceTestCalendar.pacific.component(.day, from: $0) }
        #expect(days == [12, 19, 26])
    }

    @Test("Weekly interval=2 jumps two weeks")
    func biweekly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 5)
        let rule = RecurrenceRule.CalendarRule(freq: .weekly, interval: 2)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 2
        )
        let days = dates.map { RecurrenceTestCalendar.pacific.component(.day, from: $0) }
        #expect(days == [19, 2])  // Jan 19, then Feb 2.
    }

    @Test("Weekly byDay=[MO,WE,FR] fires on each day in order")
    func mwfPattern() {
        // Seed = Mon 2026-01-05.
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 5, hour: 9)
        let rule = RecurrenceRule.CalendarRule(
            freq: .weekly,
            interval: 1,
            byDay: [.monday, .wednesday, .friday]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 5
        )
        let days = dates.map { RecurrenceTestCalendar.pacific.component(.day, from: $0) }
        #expect(days == [7, 9, 12, 14, 16])  // Wed, Fri, Mon, Wed, Fri.
    }

    @Test("Weekly byDay=[TU,TH] interval=2 only fires Tue/Thu in alternating weeks")
    func tthBiweekly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 6)  // Tue.
        let rule = RecurrenceRule.CalendarRule(
            freq: .weekly,
            interval: 2,
            byDay: [.tuesday, .thursday]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 4
        )
        let formatter = DateFormatter()
        formatter.calendar = RecurrenceTestCalendar.pacific
        formatter.timeZone = RecurrenceTestCalendar.pacific.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let days = dates.map(formatter.string(from:))
        #expect(days == ["2026-01-08", "2026-01-20", "2026-01-22", "2026-02-03"])
    }

    @Test("Weekly preserves seed's wall-clock hour")
    func preservesTime() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 5, hour: 14, minute: 30)
        let rule = RecurrenceRule.CalendarRule(freq: .weekly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 2
        )
        for d in dates {
            #expect(RecurrenceTestCalendar.pacific.component(.hour, from: d) == 14)
            #expect(RecurrenceTestCalendar.pacific.component(.minute, from: d) == 30)
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderWeeklyTests`
Expected: FAIL — weekly returns nil.

- [ ] **Step 3: Implement weekly in `RecurrenceExpander`**

Replace the `step(from:rule:calendar:)` function in `RecurrenceExpander.swift` with one that handles weekly, plus add a `weeklyStep` helper. Final `step` function:

```swift
    private static func step(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        switch rule.freq {
        case .daily:
            return calendar.date(byAdding: .day, value: rule.interval, to: previous)
        case .weekly:
            return weeklyStep(from: previous, rule: rule, calendar: calendar)
        case .monthly:
            return nil  // Task 7
        case .yearly:
            return nil  // Task 8
        }
    }

    private static func weeklyStep(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        guard let byDay = rule.byDay, byDay.isEmpty == false else {
            return calendar.date(byAdding: .weekOfYear, value: rule.interval, to: previous)
        }
        let sortedDays = byDay.sorted { $0.calendarComponent < $1.calendarComponent }
        let previousWeekday = calendar.component(.weekday, from: previous)
        // Find the next byDay weekday within the current week.
        if let next = sortedDays.first(where: { $0.calendarComponent > previousWeekday }) {
            let delta = next.calendarComponent - previousWeekday
            return calendar.date(byAdding: .day, value: delta, to: previous)
        }
        // Otherwise wrap to the first byDay weekday in the next `interval`-th week.
        let firstNext = sortedDays.first!
        let daysToEndOfWeek = 7 - previousWeekday + firstNext.calendarComponent
        // Add (interval - 1) full weeks + the wrap-around days.
        let totalDays = daysToEndOfWeek + 7 * (rule.interval - 1)
        return calendar.date(byAdding: .day, value: totalDays, to: previous)
    }
```

- [ ] **Step 4: Run weekly tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderWeeklyTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Run the full RecurrenceExpander suite to confirm no regression**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpander`
Expected: every previously-passing recurrence test still passes.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderWeeklyTests.swift
git commit -m "feat(recurrence): add weekly frequency with byDay support"
```

---

## Task 7: `RecurrenceExpander` — monthly frequency with `byMonthDay`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderMonthlyTests.swift`

Monthly semantics:
- No `byMonthDay`, no `byDay`: fire on the seed's day-of-month every `interval` months. If the target month doesn't have that day (e.g. seed = Jan 31, target = Feb), **skip the month entirely** per design Section 8.
- With `byMonthDay = [n1, n2, …]`: fire on each listed day-of-month within each `interval`-month window, skipping non-existent days.
- `bySetPos` is handled in Task 9 (it's most useful in combination with `byDay`).

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderMonthlyTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander monthly")
struct RecurrenceExpanderMonthlyTests {
    @Test("Monthly interval=1 with no byMonthDay repeats seed day-of-month")
    func plainMonthly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 15, hour: 9)
        let rule = RecurrenceRule.CalendarRule(freq: .monthly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let formatter = DateFormatter()
        formatter.calendar = RecurrenceTestCalendar.pacific
        formatter.timeZone = RecurrenceTestCalendar.pacific.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        #expect(dates.map(formatter.string(from:)) == ["2026-02-15", "2026-03-15", "2026-04-15"])
    }

    @Test("Monthly interval=3 fires every quarter")
    func quarterly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let rule = RecurrenceRule.CalendarRule(freq: .monthly, interval: 3)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let months = dates.map { RecurrenceTestCalendar.pacific.component(.month, from: $0) }
        let years = dates.map { RecurrenceTestCalendar.pacific.component(.year, from: $0) }
        #expect(months == [4, 7, 10])
        #expect(years == [2026, 2026, 2026])
    }

    @Test("Monthly with byMonthDay=[1,15] fires twice each month")
    func multipleMonthDays() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 1,
            byMonthDay: [1, 15]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 4
        )
        let formatter = DateFormatter()
        formatter.calendar = RecurrenceTestCalendar.pacific
        formatter.timeZone = RecurrenceTestCalendar.pacific.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        #expect(dates.map(formatter.string(from:)) == [
            "2026-01-15", "2026-02-01", "2026-02-15", "2026-03-01"
        ])
    }

    @Test("Monthly byMonthDay=[15] interval=2 fires every other month on the 15th")
    func bimonthly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 15)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 2,
            byMonthDay: [15]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let months = dates.map { RecurrenceTestCalendar.pacific.component(.month, from: $0) }
        #expect(months == [3, 5, 7])
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderMonthlyTests`
Expected: FAIL.

- [ ] **Step 3: Implement monthly in `RecurrenceExpander`**

Update `step` to dispatch to a new `monthlyStep` and add the helper. New code in `RecurrenceExpander.swift`:

```swift
        case .monthly:
            return monthlyStep(from: previous, rule: rule, calendar: calendar)
```

```swift
    private static func monthlyStep(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        let targetDays = rule.byMonthDay ?? [calendar.component(.day, from: previous)]
        // Build candidate dates in (previous month, current month, next month, …)
        // until we find one strictly after `previous`. We hard-cap the look-ahead at
        // 12 months to avoid infinite loops if every candidate is invalid.
        var monthOffset = 0
        while monthOffset <= 12 * max(rule.interval, 1) + 1 {
            guard let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: previous) else {
                return nil
            }
            // Only consider months that are an integer multiple of `interval` ahead of
            // the seed month. monthOffset=0 (same month) is allowed for byMonthDay lists
            // with multiple entries within the seed's month.
            if monthOffset > 0 && monthOffset % rule.interval != 0 {
                monthOffset += 1
                continue
            }
            let candidates = targetDays.compactMap { day -> Date? in
                composeDate(in: monthStart, day: day, time: previous, calendar: calendar)
            }.sorted()
            if let next = candidates.first(where: { $0 > previous }) {
                return next
            }
            monthOffset += 1
        }
        return nil
    }

    /// Builds a date in `monthAnchor`'s year+month, using `day` for day-of-month
    /// and `time`'s hour/minute/second. Returns `nil` if `day` doesn't exist in
    /// that month (e.g. Feb 31), implementing the skip-month rule from design
    /// Section 8.
    private static func composeDate(
        in monthAnchor: Date,
        day: Int,
        time: Date,
        calendar: Calendar
    ) -> Date? {
        var comps = calendar.dateComponents([.year, .month], from: monthAnchor)
        let timeComps = calendar.dateComponents([.hour, .minute, .second], from: time)
        comps.day = day
        comps.hour = timeComps.hour
        comps.minute = timeComps.minute
        comps.second = timeComps.second
        guard
            let year = comps.year,
            let month = comps.month,
            let range = calendar.range(of: .day, in: .month, for: monthAnchor),
            range.contains(day)
        else {
            return nil
        }
        _ = year
        _ = month
        return calendar.date(from: comps)
    }
```

- [ ] **Step 4: Run monthly tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderMonthlyTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Confirm no regressions in daily/weekly**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpander`
Expected: all recurrence tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderMonthlyTests.swift
git commit -m "feat(recurrence): add monthly frequency with byMonthDay"
```

---

## Task 8: `RecurrenceExpander` — yearly frequency

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderYearlyTests.swift`

Yearly: fire on the same month/day as seed every `interval` years. Feb 29 on a non-leap year: skip the year per the same skip-month logic.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderYearlyTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander yearly")
struct RecurrenceExpanderYearlyTests {
    @Test("Yearly interval=1 repeats month-day across years")
    func plainYearly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 3, day: 15)
        let rule = RecurrenceRule.CalendarRule(freq: .yearly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let years = dates.map { RecurrenceTestCalendar.pacific.component(.year, from: $0) }
        #expect(years == [2027, 2028, 2029])
    }

    @Test("Yearly Feb 29 seed skips non-leap years")
    func feb29SkipsNonLeapYears() {
        let seed = RecurrenceTestCalendar.date(year: 2024, month: 2, day: 29)  // 2024 is a leap year.
        let rule = RecurrenceRule.CalendarRule(freq: .yearly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 2
        )
        let years = dates.map { RecurrenceTestCalendar.pacific.component(.year, from: $0) }
        let months = dates.map { RecurrenceTestCalendar.pacific.component(.month, from: $0) }
        let days = dates.map { RecurrenceTestCalendar.pacific.component(.day, from: $0) }
        #expect(years == [2028, 2032])   // Next two leap years.
        #expect(months == [2, 2])
        #expect(days == [29, 29])
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderYearlyTests`
Expected: FAIL.

- [ ] **Step 3: Implement yearly**

Update the `step` switch:

```swift
        case .yearly:
            return yearlyStep(from: previous, rule: rule, calendar: calendar)
```

Add `yearlyStep`:

```swift
    private static func yearlyStep(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        let month = calendar.component(.month, from: previous)
        let day = calendar.component(.day, from: previous)
        let hour = calendar.component(.hour, from: previous)
        let minute = calendar.component(.minute, from: previous)
        let second = calendar.component(.second, from: previous)
        var year = calendar.component(.year, from: previous) + rule.interval

        // Skip years where (month, day) doesn't exist (Feb 29 in non-leap years).
        for _ in 0..<40 {
            var c = DateComponents()
            c.year = year
            c.month = month
            c.day = day
            c.hour = hour
            c.minute = minute
            c.second = second
            if let date = calendar.date(from: c),
               calendar.component(.day, from: date) == day,
               calendar.component(.month, from: date) == month {
                return date
            }
            year += rule.interval
        }
        return nil
    }
```

- [ ] **Step 4: Run yearly tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderYearlyTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Run all recurrence tests**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpander`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderYearlyTests.swift
git commit -m "feat(recurrence): add yearly frequency with Feb 29 skip-year handling"
```

---

## Task 9: `RecurrenceExpander` — `bySetPos` filter

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderBySetPosTests.swift`

`bySetPos` picks specific positions within a single period. In the task-manager-meaningful cases:
- Monthly `byDay=[MO]`, `bySetPos=[1]` → first Monday of every month.
- Monthly `byDay=[MO]`, `bySetPos=[-1]` → last Monday of every month.
- Monthly `byDay=[MO,TU,WE,TH,FR]`, `bySetPos=[1]` → first weekday of every month.
- Yearly `byDay=[TH]`, `bySetPos=[4]` (in `byMonth=[11]`) → Thanksgiving; but we don't support `byMonth` in v1, so we focus on monthly.

For v1 we only honor `bySetPos` with `freq = .monthly` and a non-empty `byDay`. Other combinations are ignored (the rule expander returns the un-filtered occurrences).

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderBySetPosTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander bySetPos")
struct RecurrenceExpanderBySetPosTests {
    @Test("Monthly first Monday")
    func firstMondayOfMonth() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 1,
            byDay: [.monday],
            bySetPos: [1]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let formatter = DateFormatter()
        formatter.calendar = RecurrenceTestCalendar.pacific
        formatter.timeZone = RecurrenceTestCalendar.pacific.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        #expect(dates.map(formatter.string(from:)) == ["2026-01-05", "2026-02-02", "2026-03-02"])
    }

    @Test("Monthly last Friday")
    func lastFridayOfMonth() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 1,
            byDay: [.friday],
            bySetPos: [-1]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let formatter = DateFormatter()
        formatter.calendar = RecurrenceTestCalendar.pacific
        formatter.timeZone = RecurrenceTestCalendar.pacific.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        #expect(dates.map(formatter.string(from:)) == ["2026-01-30", "2026-02-27", "2026-03-27"])
    }

    @Test("Monthly first weekday")
    func firstWeekdayOfMonth() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 1,
            byDay: [.monday, .tuesday, .wednesday, .thursday, .friday],
            bySetPos: [1]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let formatter = DateFormatter()
        formatter.calendar = RecurrenceTestCalendar.pacific
        formatter.timeZone = RecurrenceTestCalendar.pacific.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        // Jan 1 2026 is Thursday, so first weekday is Jan 1.
        // But we ask for occurrences *after* seed = Jan 1; so first one is Feb 2, etc.
        #expect(dates.map(formatter.string(from:)) == ["2026-02-02", "2026-03-02", "2026-04-01"])
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderBySetPosTests`
Expected: FAIL.

- [ ] **Step 3: Update monthly step to honor `bySetPos` + `byDay`**

In `monthlyStep`, before the `targetDays` line, branch on whether `byDay` + `bySetPos` are both present and the freq is monthly. Replace `monthlyStep` with:

```swift
    private static func monthlyStep(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        if let byDay = rule.byDay, byDay.isEmpty == false,
           let bySetPos = rule.bySetPos, bySetPos.isEmpty == false {
            return monthlyStepBySetPos(
                from: previous,
                byDay: byDay,
                bySetPos: bySetPos,
                interval: rule.interval,
                calendar: calendar
            )
        }
        let targetDays = rule.byMonthDay ?? [calendar.component(.day, from: previous)]
        var monthOffset = 0
        while monthOffset <= 12 * max(rule.interval, 1) + 1 {
            guard let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: previous) else {
                return nil
            }
            if monthOffset > 0 && monthOffset % rule.interval != 0 {
                monthOffset += 1
                continue
            }
            let candidates = targetDays.compactMap { day -> Date? in
                composeDate(in: monthStart, day: day, time: previous, calendar: calendar)
            }.sorted()
            if let next = candidates.first(where: { $0 > previous }) {
                return next
            }
            monthOffset += 1
        }
        return nil
    }

    private static func monthlyStepBySetPos(
        from previous: Date,
        byDay: [Weekday],
        bySetPos: [Int],
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        // Walk forward month by month. For each month-multiple-of-interval, compute
        // all candidate (weekday-in-byDay) dates, then filter by bySetPos.
        var monthOffset = 0
        while monthOffset <= 12 * max(interval, 1) + 1 {
            guard let monthAnchor = calendar.date(byAdding: .month, value: monthOffset, to: previous) else {
                return nil
            }
            if monthOffset > 0 && monthOffset % interval != 0 {
                monthOffset += 1
                continue
            }
            let candidates = candidateDates(
                inMonthOf: monthAnchor,
                weekdays: byDay,
                timeOf: previous,
                calendar: calendar
            ).sorted()
            // Apply bySetPos: 1 = first, 2 = second, -1 = last, -2 = second-to-last, ...
            let selected = bySetPos.compactMap { pos -> Date? in
                let idx = pos > 0 ? pos - 1 : candidates.count + pos
                return candidates.indices.contains(idx) ? candidates[idx] : nil
            }.sorted()
            if let next = selected.first(where: { $0 > previous }) {
                return next
            }
            monthOffset += 1
        }
        return nil
    }

    private static func candidateDates(
        inMonthOf monthAnchor: Date,
        weekdays: [Weekday],
        timeOf timeSource: Date,
        calendar: Calendar
    ) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: monthAnchor) else { return [] }
        let weekdayValues = Set(weekdays.map(\.calendarComponent))
        let timeComps = calendar.dateComponents([.hour, .minute, .second], from: timeSource)
        var monthStartComps = calendar.dateComponents([.year, .month], from: monthAnchor)
        var out: [Date] = []
        for day in range {
            monthStartComps.day = day
            monthStartComps.hour = timeComps.hour
            monthStartComps.minute = timeComps.minute
            monthStartComps.second = timeComps.second
            guard let d = calendar.date(from: monthStartComps) else { continue }
            if weekdayValues.contains(calendar.component(.weekday, from: d)) {
                out.append(d)
            }
        }
        return out
    }
```

- [ ] **Step 4: Run bySetPos tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderBySetPosTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Run all recurrence tests for regression**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpander`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderBySetPosTests.swift
git commit -m "feat(recurrence): add monthly bySetPos+byDay support"
```

---

## Task 10: `RecurrenceExpander` — DST-correct wall-clock preservation

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderDSTTests.swift`

No production code changes — `Calendar.date(byAdding:)` is already DST-correct. This task adds tests that lock in design Section 8: wall-clock time preserved across DST transitions.

In `America/Los_Angeles`, in 2026:
- Spring forward: March 8 02:00 → 03:00 (skip).
- Fall back: November 1 02:00 → 01:00 (repeat).

- [ ] **Step 1: Write DST tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderDSTTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander DST")
struct RecurrenceExpanderDSTTests {
    @Test("Daily across spring-forward preserves 09:00 wall clock")
    func dailyAcrossSpringForward() {
        // Seed Friday March 6 2026 at 09:00. Spring forward is Sunday March 8.
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 3, day: 6, hour: 9)
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 4
        )
        for d in dates {
            #expect(RecurrenceTestCalendar.pacific.component(.hour, from: d) == 9)
            #expect(RecurrenceTestCalendar.pacific.component(.minute, from: d) == 0)
        }
    }

    @Test("Daily across fall-back preserves 09:00 wall clock")
    func dailyAcrossFallBack() {
        // Seed Friday October 30 2026 at 09:00. Fall back is Sunday November 1.
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 10, day: 30, hour: 9)
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 4
        )
        for d in dates {
            #expect(RecurrenceTestCalendar.pacific.component(.hour, from: d) == 9)
            #expect(RecurrenceTestCalendar.pacific.component(.minute, from: d) == 0)
        }
    }

    @Test("Weekly across spring-forward preserves wall clock")
    func weeklyAcrossSpringForward() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 3, day: 1, hour: 14, minute: 30)
        let rule = RecurrenceRule.CalendarRule(freq: .weekly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        for d in dates {
            #expect(RecurrenceTestCalendar.pacific.component(.hour, from: d) == 14)
            #expect(RecurrenceTestCalendar.pacific.component(.minute, from: d) == 30)
        }
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderDSTTests`
Expected: PASS, 3 tests. (No implementation changes needed — `Calendar.date(byAdding:)` is already DST-aware.)

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderDSTTests.swift
git commit -m "test(recurrence): lock in DST-correct wall-clock preservation"
```

---

## Task 11: `RecurrenceExpander` — `byMonthDay = 31` skip-month behavior

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderByMonthDay31Tests.swift`

Design Section 8 mandates: `byMonthDay = 31` in shorter months **skips the month entirely**, not coerces to the 30th. Task 7's monthly implementation already does this; this task adds explicit regression tests.

- [ ] **Step 1: Write tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderByMonthDay31Tests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander byMonthDay=31")
struct RecurrenceExpanderByMonthDay31Tests {
    @Test("byMonthDay=31 skips months that don't have 31")
    func skipsShortMonths() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 31)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 1,
            byMonthDay: [31]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 5
        )
        let formatter = DateFormatter()
        formatter.calendar = RecurrenceTestCalendar.pacific
        formatter.timeZone = RecurrenceTestCalendar.pacific.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        // 2026: Jan, Mar, May, Jul, Aug, Oct, Dec have 31.
        // Starting after Jan 31 → Mar 31, May 31, Jul 31, Aug 31, Oct 31.
        #expect(dates.map(formatter.string(from:)) == [
            "2026-03-31", "2026-05-31", "2026-07-31", "2026-08-31", "2026-10-31"
        ])
    }

    @Test("byMonthDay=31 does NOT coerce to the 30th")
    func doesNotCoerceTo30() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 31)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 1,
            byMonthDay: [31]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 5
        )
        for d in dates {
            #expect(RecurrenceTestCalendar.pacific.component(.day, from: d) == 31)
        }
    }

    @Test("Plain monthly with seed on the 31st also skips short months")
    func plainMonthlySkipsShortMonths() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 31)
        let rule = RecurrenceRule.CalendarRule(freq: .monthly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let days = dates.map { RecurrenceTestCalendar.pacific.component(.day, from: $0) }
        #expect(days == [31, 31, 31])
        let months = dates.map { RecurrenceTestCalendar.pacific.component(.month, from: $0) }
        #expect(months == [3, 5, 7])
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderByMonthDay31Tests`
Expected: PASS, 3 tests.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderByMonthDay31Tests.swift
git commit -m "test(recurrence): lock in byMonthDay=31 skip-month behavior"
```

---

## Task 12: `RecurrenceExpander` — after-completion timing

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderAfterCompletionTests.swift`

The `.afterCompletion` variant is a fixed `TimeInterval` from the moment the previous instance closed. Production code already exists in `nextAfterCompletion(completedAt:rule:)`; this task pins the behavior.

- [ ] **Step 1: Write tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderAfterCompletionTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander after-completion")
struct RecurrenceExpanderAfterCompletionTests {
    @Test("Returns completedAt + interval")
    func basic() {
        let completed = Date(timeIntervalSince1970: 1_800_000_000)
        let rule = RecurrenceRule.AfterCompletionRule(interval: 86_400 * 3)
        let next = RecurrenceExpander.nextAfterCompletion(completedAt: completed, rule: rule)
        #expect(next == completed.addingTimeInterval(86_400 * 3))
    }

    @Test("Zero interval returns the same instant")
    func zeroInterval() {
        let completed = Date()
        let rule = RecurrenceRule.AfterCompletionRule(interval: 0)
        let next = RecurrenceExpander.nextAfterCompletion(completedAt: completed, rule: rule)
        #expect(next == completed)
    }

    @Test("Negative interval is permitted (returns earlier date) — caller's responsibility")
    func negativeIntervalAllowed() {
        let completed = Date(timeIntervalSince1970: 1_000_000)
        let rule = RecurrenceRule.AfterCompletionRule(interval: -60)
        let next = RecurrenceExpander.nextAfterCompletion(completedAt: completed, rule: rule)
        #expect(next < completed)
    }
}
```

- [ ] **Step 2: Run**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderAfterCompletionTests`
Expected: PASS, 3 tests.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderAfterCompletionTests.swift
git commit -m "test(recurrence): lock in afterCompletion timing"
```

---

## Task 13: `RecurrenceExpander` — `count` and `until` limit semantics

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderLimitTests.swift`

Task 5 already implemented `count`/`until` caps inside `nextOccurrences`. This task expands the regression bed to cover edge cases: `count = 0`, `until` before the first computed occurrence, `count` smaller than the requested batch, etc.

- [ ] **Step 1: Write tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderLimitTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander limits")
struct RecurrenceExpanderLimitTests {
    @Test("count=0 yields no occurrences")
    func countZero() {
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, count: 0)
        let dates = RecurrenceExpander.nextOccurrences(
            after: Date(),
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 10
        )
        #expect(dates.isEmpty)
    }

    @Test("until before first computed occurrence yields no occurrences")
    func untilBeforeFirst() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let until = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, until: until)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 10
        )
        #expect(dates.isEmpty)
    }

    @Test("count smaller than requested batch caps results")
    func countCaps() {
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, count: 3)
        let dates = RecurrenceExpander.nextOccurrences(
            after: Date(),
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 100
        )
        #expect(dates.count == 3)
    }

    @Test("until on the same instant as a computed occurrence includes it")
    func untilInclusiveOfMatchingInstant() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1, hour: 9)
        let until = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 3, hour: 9)
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, until: until)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 10
        )
        // Jan 2, Jan 3 — both before-or-equal to until.
        #expect(dates.count == 2)
    }

    @Test("count interacts with until — whichever is tighter wins")
    func countAndUntil() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let until = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 4)
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, count: 10, until: until)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 100
        )
        // until trims to Jan 2, 3, 4 = 3 occurrences (less than count=10).
        #expect(dates.count == 3)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cd Packages/LillistCore && swift test --filter RecurrenceExpanderLimitTests`
Expected: PASS, 5 tests.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderLimitTests.swift
git commit -m "test(recurrence): lock in count and until limit semantics"
```

---

## Task 14: `Series+CoreData.swift` — typed rule accessor

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift`

A typed `rule: RecurrenceRule?` accessor over the underlying `ruleJSON: String?` attribute. Parallels Plan 1's `LillistTask.status` typed accessor.

- [ ] **Step 1: Write the extension**

Write `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift`:

```swift
import Foundation
import CoreData

extension Series {
    /// Typed accessor over `ruleJSON`. Returns `nil` if the JSON is missing
    /// or malformed (caller should treat that as a data-corruption signal).
    public var rule: RecurrenceRule? {
        get {
            guard let json = ruleJSON, let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(RecurrenceRule.self, from: data)
        }
        set {
            if let newValue,
               let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                ruleJSON = str
            } else {
                ruleJSON = nil
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift
git commit -m "feat(model): add typed RecurrenceRule accessor over Series.ruleJSON"
```

---

## Task 15: `SeriesStore` — create / fetch / list / update / delete

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/SeriesStoreCRUDTests.swift`

`SeriesStore.create(fromSeedTask:rule:)` is atomic: it creates the series, encodes the rule, links the seed task (via both `seedTask` and `instances`), and computes the initial `nextOccurrenceAfter`.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/SeriesStoreCRUDTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("SeriesStore CRUD")
struct SeriesStoreCRUDTests {
    @Test("Create from seed task wires the relationship and persists the rule")
    func createFromSeed() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let taskID = try await tasks.create(title: "Water plants")
        try await tasks.update(id: taskID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await series.create(fromSeedTask: taskID, rule: rule)

        let record = try await series.fetch(id: seriesID)
        #expect(record.seedTaskID == taskID)
        #expect(record.rule == rule)
        #expect(record.nextOccurrenceAfter != nil)

        // Seed task is also linked as an instance.
        let instances = try await series.instances(of: seriesID)
        #expect(instances.contains(taskID))
    }

    @Test("Creating a series sets nextOccurrenceAfter from the seed's start")
    func nextOccurrenceComputed() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        let seedStart = Date(timeIntervalSince1970: 1_800_000_000)
        try await tasks.update(id: id) { $0.start = seedStart }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await series.create(fromSeedTask: id, rule: rule)
        let next = try await series.fetch(id: seriesID).nextOccurrenceAfter
        #expect(next != nil)
        #expect(next! > seedStart)
    }

    @Test("Create from seed without a start uses createdAt as the anchor")
    func anchorsOnCreatedAtWhenNoStart() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await series.create(fromSeedTask: id, rule: rule)
        #expect(try await series.fetch(id: seriesID).nextOccurrenceAfter != nil)
    }

    @Test("Update rewrites the rule JSON")
    func updateRule() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        let original = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await series.create(fromSeedTask: id, rule: original)
        let updated = RecurrenceRule.calendar(.init(freq: .weekly, interval: 1))
        try await series.update(id: seriesID, rule: updated)
        #expect(try await series.fetch(id: seriesID).rule == updated)
    }

    @Test("Delete clears series from instances but doesn't delete the tasks")
    func deletePreservesInstances() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await series.create(fromSeedTask: id, rule: rule)
        try await series.delete(id: seriesID)
        await #expect(throws: LillistError.notFound) {
            _ = try await series.fetch(id: seriesID)
        }
        _ = try await tasks.fetch(id: id)  // task still exists.
    }

    @Test("List returns all series ordered by next-occurrence")
    func list() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let a = try await tasks.create(title: "A")
        let b = try await tasks.create(title: "B")
        _ = try await series.create(fromSeedTask: a, rule: .calendar(.init(freq: .daily, interval: 1)))
        _ = try await series.create(fromSeedTask: b, rule: .calendar(.init(freq: .weekly, interval: 1)))
        let all = try await series.list()
        #expect(all.count == 2)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter SeriesStoreCRUDTests`
Expected: FAIL — `SeriesStore` undefined.

- [ ] **Step 3: Write `SeriesStore`**

Write `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift`:

```swift
import Foundation
import CoreData

public final class SeriesStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    /// Value-type DTO for `Series`.
    public struct SeriesRecord: Sendable, Equatable {
        public var id: UUID
        public var seedTaskID: UUID?
        public var rule: RecurrenceRule?
        public var nextOccurrenceAfter: Date?
    }

    // MARK: - Create

    @discardableResult
    public func create(fromSeedTask seedTaskID: UUID, rule: RecurrenceRule) async throws -> UUID {
        try await context.perform { [self] in
            let task = try TaskStore(persistence: persistence).fetchManagedObject(id: seedTaskID, in: context)
            let series = Series(context: context)
            series.id = UUID()
            series.rule = rule
            series.seedTask = task
            // Membership: the seed is also part of `instances`.
            task.series = series

            let anchor = task.start ?? task.createdAt ?? Date()
            series.nextOccurrenceAfter = computeNextOccurrence(rule: rule, after: anchor)

            try context.save()
            return series.id!
        }
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> SeriesRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return record(from: m)
        }
    }

    public func instances(of seriesID: UUID) async throws -> [UUID] {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: seriesID, in: context)
            guard let set = m.instances as? Set<LillistTask> else { return [] }
            return set.compactMap { $0.id }
        }
    }

    public func list() async throws -> [SeriesRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<Series>(entityName: "Series")
            req.sortDescriptors = [NSSortDescriptor(key: "nextOccurrenceAfter", ascending: true)]
            return try context.fetch(req).map(record(from:))
        }
    }

    // MARK: - Update

    public func update(id: UUID, rule: RecurrenceRule) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            m.rule = rule
            let anchor = m.seedTask?.start ?? m.seedTask?.createdAt ?? Date()
            m.nextOccurrenceAfter = computeNextOccurrence(rule: rule, after: anchor)
            try context.save()
        }
    }

    // MARK: - Delete

    public func delete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            context.delete(m)
            try context.save()
        }
    }

    // MARK: - Internal helpers (used by RecurrenceSpawner)

    func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> Series {
        let req = NSFetchRequest<Series>(entityName: "Series")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else {
            throw LillistError.notFound
        }
        return m
    }

    static func computeNextOccurrence(rule: RecurrenceRule, after anchor: Date) -> Date? {
        switch rule {
        case .calendar(let cal):
            return RecurrenceExpander.nextOccurrences(
                after: anchor,
                rule: cal,
                calendar: Calendar.current,
                count: 1
            ).first
        case .afterCompletion(let after):
            return RecurrenceExpander.nextAfterCompletion(completedAt: anchor, rule: after)
        }
    }

    func computeNextOccurrence(rule: RecurrenceRule, after anchor: Date) -> Date? {
        Self.computeNextOccurrence(rule: rule, after: anchor)
    }

    func record(from m: Series) -> SeriesRecord {
        SeriesRecord(
            id: m.id ?? UUID(),
            seedTaskID: m.seedTask?.id,
            rule: m.rule,
            nextOccurrenceAfter: m.nextOccurrenceAfter
        )
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter SeriesStoreCRUDTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/SeriesStoreCRUDTests.swift
git commit -m "feat(recurrence): add SeriesStore with create/fetch/list/update/delete"
```

---

## Task 16: `RecurrenceSpawner` — spawn-on-completion (calendar rules)

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift`

`RecurrenceSpawner` is the hook `TaskStore.transition(to: .closed)` calls. It runs inside the same `viewContext` perform block as the transition (so the spawn is atomic with the close). It:

1. Returns early if the closed task has no `series`.
2. Returns early if the series has `nextOccurrenceAfter == nil` (count/until reached).
3. Creates a new `LillistTask` instance using the seed's editable fields (title, notes, tags), with `start`/`deadline` shifted to the new occurrence date, `status = .todo`, `series` pointing to the same `Series`.
4. Deep-copies the seed's children per instance.
5. Updates `Series.nextOccurrenceAfter` to the *next-next* occurrence (after the just-spawned one).
6. If the just-spawned date is beyond `until`, or count has now been reached, sets `nextOccurrenceAfter = nil`.

The spawner is not its own store — it operates on the managed objects directly, called from within `TaskStore.transition`.

- [ ] **Step 1: Write `RecurrenceSpawner`**

Write `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift`:

```swift
import Foundation
import CoreData

/// Spawns the next instance of a `Series` when an existing instance closes.
///
/// Invoked from inside `TaskStore.transition` while the `viewContext` is
/// already locked — so this code runs synchronously on the context queue
/// and shares the same save. Calling this with a non-series task is a no-op.
///
/// Re-opening a closed task does NOT call this — that's a one-way operation
/// per design Section 8.
enum RecurrenceSpawner {
    /// If `closed` is an instance of a still-spawning series, create the
    /// next instance and update the series' `nextOccurrenceAfter`. No-op
    /// when there's no series or the series has reached its limit.
    ///
    /// Pre: called inside `context.perform { … }`. Caller is responsible
    /// for `context.save()` afterward.
    static func spawnIfNeeded(
        forClosedTask closed: LillistTask,
        in context: NSManagedObjectContext
    ) {
        guard let series = closed.series else { return }
        guard let rule = series.rule else { return }
        // Limit reached?
        guard let nextDate = series.nextOccurrenceAfter else { return }

        // 1. Spawn the new instance, copying the seed.
        let seed = series.seedTask ?? closed
        let spawn = LillistTask(context: context)
        spawn.id = UUID()
        spawn.title = seed.title
        spawn.notes = seed.notes
        spawn.statusRaw = Int16(Status.todo.rawValue)
        spawn.startHasTime = seed.startHasTime
        spawn.deadlineHasTime = seed.deadlineHasTime
        spawn.isPinned = false
        spawn.createdAt = Date()
        spawn.modifiedAt = spawn.createdAt
        spawn.parent = seed.parent
        spawn.position = (seed.position) + 0.5  // Placed near the seed; PositionCompactor will tidy.
        spawn.series = series
        spawn.tags = seed.tags

        // Shift dates so seed.start → nextDate, and seed.deadline keeps its delta.
        if let seedStart = seed.start {
            let delta = nextDate.timeIntervalSince(seedStart)
            spawn.start = nextDate
            spawn.deadline = seed.deadline.map { $0.addingTimeInterval(delta) }
        } else {
            spawn.start = nextDate
            spawn.deadline = seed.deadline
        }

        // 2. Deep-copy children (one level — design Section 2 specifies child copies per instance).
        if let kids = seed.children as? Set<LillistTask> {
            for kid in kids where kid.deletedAt == nil {
                deepCopy(kid, into: spawn, in: context)
            }
        }

        // 3. Advance `nextOccurrenceAfter`.
        let advanced = advance(rule: rule, lastOccurrence: nextDate, completedAt: closed.closedAt ?? Date())
        // 4. Enforce `count` limit.
        let countLimited = countReached(series: series, rule: rule, justSpawnedDate: nextDate)
        series.nextOccurrenceAfter = countLimited ? nil : advanced
    }

    private static func deepCopy(
        _ source: LillistTask,
        into newParent: LillistTask,
        in context: NSManagedObjectContext
    ) {
        let copy = LillistTask(context: context)
        copy.id = UUID()
        copy.title = source.title
        copy.notes = source.notes
        copy.statusRaw = Int16(Status.todo.rawValue)
        copy.start = source.start
        copy.startHasTime = source.startHasTime
        copy.deadline = source.deadline
        copy.deadlineHasTime = source.deadlineHasTime
        copy.isPinned = source.isPinned
        copy.createdAt = Date()
        copy.modifiedAt = copy.createdAt
        copy.position = source.position
        copy.parent = newParent
        copy.tags = source.tags

        if let kids = source.children as? Set<LillistTask> {
            for kid in kids where kid.deletedAt == nil {
                deepCopy(kid, into: copy, in: context)
            }
        }
    }

    private static func advance(
        rule: RecurrenceRule,
        lastOccurrence: Date,
        completedAt: Date
    ) -> Date? {
        switch rule {
        case .calendar(let cal):
            // Compute the occurrence AFTER `lastOccurrence`.
            return RecurrenceExpander.nextOccurrences(
                after: lastOccurrence,
                rule: cal,
                calendar: Calendar.current,
                count: 1
            ).first
        case .afterCompletion(let after):
            return RecurrenceExpander.nextAfterCompletion(completedAt: completedAt, rule: after)
        }
    }

    /// True if spawning `justSpawnedDate` consumed the rule's `count` budget.
    private static func countReached(
        series: Series,
        rule: RecurrenceRule,
        justSpawnedDate: Date
    ) -> Bool {
        guard case .calendar(let cal) = rule, let count = cal.count else { return false }
        // The seed is instance #1; every spawned instance after it counts.
        // After this spawn, total instances = current + 1.
        let existing = (series.instances as? Set<LillistTask>)?.count ?? 0
        return existing >= count
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds. (Tests come in Task 17.)

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift
git commit -m "feat(recurrence): add RecurrenceSpawner — spawn next instance on close"
```

---

## Task 17: Hook `RecurrenceSpawner` into `TaskStore.transition`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreRecurrenceSpawnTests.swift`

We modify `TaskStore.transition` to call `RecurrenceSpawner.spawnIfNeeded` after applying the status change but before `context.save()`. This makes the spawn atomic with the close. Re-opening (transition out of `.closed`) explicitly does **not** invoke the spawner.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreRecurrenceSpawnTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore recurrence spawn")
struct TaskStoreRecurrenceSpawnTests {
    @Test("Closing a recurring instance spawns the next one")
    func spawnsOnClose() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily standup")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: seedID, rule: rule)

        try await tasks.transition(id: seedID, to: .closed)

        // Now there should be a second task with the same title.
        let allRoots = try await tasks.children(of: nil)
        let standups = allRoots.filter { $0.title == "Daily standup" }
        #expect(standups.count == 2)
        let openCount = standups.filter { $0.status == .todo }.count
        #expect(openCount == 1)
    }

    @Test("Closing a non-recurring task does NOT spawn")
    func noSpawnForNonRecurring() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "One-shot")
        try await tasks.transition(id: id, to: .closed)
        let all = try await tasks.children(of: nil)
        #expect(all.count == 1)
    }

    @Test("Re-opening a closed instance does NOT undo the spawn")
    func reopenDoesNotUndoSpawn() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: seedID, rule: rule)

        try await tasks.transition(id: seedID, to: .closed)
        try await tasks.transition(id: seedID, to: .todo)

        let allRoots = try await tasks.children(of: nil)
        #expect(allRoots.filter { $0.title == "Daily" }.count == 2)
    }

    @Test("Spawning copies the seed's children")
    func deepCopiesChildren() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Weekly review")
        _ = try await tasks.create(title: "Subtask A", parent: seedID)
        _ = try await tasks.create(title: "Subtask B", parent: seedID)
        let rule = RecurrenceRule.calendar(.init(freq: .weekly, interval: 1))
        _ = try await series.create(fromSeedTask: seedID, rule: rule)

        try await tasks.transition(id: seedID, to: .closed)

        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.title == "Weekly review" && $0.id != seedID }
        #expect(spawn != nil)
        let spawnedKids = try await tasks.children(of: spawn!.id)
        #expect(Set(spawnedKids.map(\.title)) == ["Subtask A", "Subtask B"])
    }

    @Test("Spawned instance is open (todo) regardless of seed status")
    func spawnedIsTodo() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: id, rule: rule)
        try await tasks.transition(id: id, to: .closed)
        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.title == "T" && $0.id != id }
        #expect(spawn!.status == .todo)
    }

    @Test("Series with count=1 spawns once and then stops")
    func countLimit() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "Twice")
        // count=2 means seed + 1 spawn.
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1, count: 2))
        let seriesID = try await series.create(fromSeedTask: id, rule: rule)

        try await tasks.transition(id: id, to: .closed)  // First spawn.
        let afterFirst = try await tasks.children(of: nil).filter { $0.title == "Twice" }
        #expect(afterFirst.count == 2)

        let openID = afterFirst.first { $0.status == .todo }!.id
        try await tasks.transition(id: openID, to: .closed)  // Should NOT spawn.
        let afterSecond = try await tasks.children(of: nil).filter { $0.title == "Twice" }
        #expect(afterSecond.count == 2)
        #expect(try await series.fetch(id: seriesID).nextOccurrenceAfter == nil)
    }

    @Test("Series with until that has passed spawns no more")
    func untilLimit() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "Bounded")
        let seedStart = Date(timeIntervalSince1970: 1_800_000_000)
        try await tasks.update(id: id) { $0.start = seedStart }
        // Until is right after seedStart — the very first computed occurrence is past it.
        let until = seedStart.addingTimeInterval(60)
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1, until: until))
        let seriesID = try await series.create(fromSeedTask: id, rule: rule)

        // Since the very first occurrence > until, nextOccurrenceAfter is nil.
        #expect(try await series.fetch(id: seriesID).nextOccurrenceAfter == nil)

        // Closing the seed therefore spawns nothing.
        try await tasks.transition(id: id, to: .closed)
        let roots = try await tasks.children(of: nil).filter { $0.title == "Bounded" }
        #expect(roots.count == 1)
    }

    @Test("After-completion series spawns at completedAt + interval")
    func afterCompletionSpawn() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "Three days after")
        let rule = RecurrenceRule.afterCompletion(.init(interval: 86_400 * 3))
        _ = try await series.create(fromSeedTask: id, rule: rule)

        let beforeClose = Date()
        try await tasks.transition(id: id, to: .closed)

        let roots = try await tasks.children(of: nil).filter { $0.title == "Three days after" }
        #expect(roots.count == 2)
        let spawn = roots.first { $0.status == .todo }!
        // Allow 2s slack for transition timing.
        let expected = beforeClose.addingTimeInterval(86_400 * 3)
        #expect(abs(spawn.start!.timeIntervalSince(expected)) < 2.0)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreRecurrenceSpawnTests`
Expected: FAIL — `TaskStore.transition` does not yet call the spawner.

- [ ] **Step 3: Modify `TaskStore.transition` to call the spawner**

In `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`, find the existing `transition` method (from Plan 1 Task 14). Modify the body so that on a transition *to* `.closed`, after writing the journal entry but before `context.save()`, the spawner runs:

```swift
    public func transition(id: UUID, to newStatus: Status) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let oldStatus = m.status
            guard oldStatus != newStatus else { return }
            m.status = newStatus
            m.modifiedAt = Date()
            if newStatus == .closed {
                m.closedAt = m.modifiedAt
            } else if oldStatus == .closed {
                m.closedAt = nil
            }

            // System journal entry for the transition.
            let entry = JournalEntry(context: context)
            entry.id = UUID()
            entry.task = m
            entry.kind = .statusChange
            entry.createdAt = m.modifiedAt
            entry.body = "\(oldStatus) → \(newStatus)"
            let payload: [String: Int] = ["from": oldStatus.rawValue, "to": newStatus.rawValue]
            entry.payload = try JSONSerialization.data(withJSONObject: payload)

            // Recurrence: spawn next instance ONLY on transition-to-closed.
            // Re-opening (oldStatus == .closed) does NOT undo the spawn,
            // per design Section 8.
            if newStatus == .closed {
                RecurrenceSpawner.spawnIfNeeded(forClosedTask: m, in: context)
            }

            try context.save()
        }
    }
```

- [ ] **Step 4: Run spawn tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreRecurrenceSpawnTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Run the full test suite to confirm no regressions**

Run: `cd Packages/LillistCore && swift test`
Expected: every existing test still passes.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreRecurrenceSpawnTests.swift
git commit -m "feat(recurrence): hook RecurrenceSpawner into TaskStore.transition"
```

---

## Task 18: `SeriesStore.forkFutureFromInstance` — edit-all-future

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/SeriesStoreForkTests.swift`

When a user edits a non-seed instance and chooses "edit all future," we:

1. Create a new `Series` with the same rule as the old one.
2. Set the new series's `seedTask` to *this instance*.
3. Move this instance's `series` pointer to the new series.
4. Old series keeps its existing instances and continues to point at its original seed.
5. Future spawns on the *old* series remain bound to its remaining `nextOccurrenceAfter`.
6. Future spawns on the *new* series start fresh from this instance's start date.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/SeriesStoreForkTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("SeriesStore fork")
struct SeriesStoreForkTests {
    @Test("Forking from a non-seed instance creates a new series")
    func forkCreatesNewSeries() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let originalSeriesID = try await series.create(fromSeedTask: seedID, rule: rule)
        try await tasks.transition(id: seedID, to: .closed)  // spawns instance #2.

        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.title == "Daily" && $0.id != seedID }!

        let newSeriesID = try await series.forkFutureFromInstance(instanceID: spawn.id)

        #expect(newSeriesID != originalSeriesID)
        let newRec = try await series.fetch(id: newSeriesID)
        #expect(newRec.seedTaskID == spawn.id)
        #expect(newRec.rule == rule)
    }

    @Test("Forking preserves the old series and its existing instances")
    func forkPreservesOldSeries() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let originalID = try await series.create(fromSeedTask: seedID, rule: rule)
        try await tasks.transition(id: seedID, to: .closed)

        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.title == "Daily" && $0.id != seedID }!
        _ = try await series.forkFutureFromInstance(instanceID: spawn.id)

        // Old series still exists.
        let oldRec = try await series.fetch(id: originalID)
        #expect(oldRec.seedTaskID == seedID)
        // Old series's instance set still contains the seed (the closed one).
        let oldInstances = try await series.instances(of: originalID)
        #expect(oldInstances.contains(seedID))
    }

    @Test("Forking moves the forked instance to the new series")
    func forkMovesInstance() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let originalID = try await series.create(fromSeedTask: seedID, rule: rule)
        try await tasks.transition(id: seedID, to: .closed)
        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.title == "Daily" && $0.id != seedID }!

        let newID = try await series.forkFutureFromInstance(instanceID: spawn.id)

        let oldInstances = try await series.instances(of: originalID)
        let newInstances = try await series.instances(of: newID)
        #expect(oldInstances.contains(spawn.id) == false)
        #expect(newInstances.contains(spawn.id))
    }

    @Test("Forking from the seed itself throws validationFailed")
    func cannotForkFromSeed() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: id, rule: rule)
        await #expect(throws: LillistError.self) {
            _ = try await series.forkFutureFromInstance(instanceID: id)
        }
    }

    @Test("Forking from a task with no series throws validationFailed")
    func cannotForkNonInstance() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "T")
        await #expect(throws: LillistError.self) {
            _ = try await series.forkFutureFromInstance(instanceID: id)
        }
    }

    @Test("Future spawns from the new series use the forked instance's start")
    func newSeriesSpawnsFromFork() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: seedID, rule: rule)
        try await tasks.transition(id: seedID, to: .closed)

        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.title == "Daily" && $0.id != seedID }!
        let newSeriesID = try await series.forkFutureFromInstance(instanceID: spawn.id)

        // Edit the forked instance's start to something distinctive.
        let newStart = Date(timeIntervalSince1970: 2_000_000_000)
        try await tasks.update(id: spawn.id) { $0.start = newStart }
        // Refresh nextOccurrenceAfter by re-saving the rule.
        try await series.update(id: newSeriesID, rule: rule)

        let next = try await series.fetch(id: newSeriesID).nextOccurrenceAfter
        #expect(next != nil)
        #expect(next! > newStart)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter SeriesStoreForkTests`
Expected: FAIL — `forkFutureFromInstance` undefined.

- [ ] **Step 3: Add `forkFutureFromInstance` to `SeriesStore`**

Append the following to `SeriesStore.swift` (inside the class):

```swift
    // MARK: - Fork (edit-all-future)

    /// Create a new `Series` rooted at `instanceID`, leaving the old series
    /// and its existing instances unchanged. Subsequent spawns of the
    /// **forked** instance will come from the new series.
    @discardableResult
    public func forkFutureFromInstance(instanceID: UUID) async throws -> UUID {
        try await context.perform { [self] in
            let task = try TaskStore(persistence: persistence).fetchManagedObject(id: instanceID, in: context)
            guard let oldSeries = task.series else {
                throw LillistError.validationFailed([
                    .init(field: "instance", message: "task is not part of a series")
                ])
            }
            if let seed = oldSeries.seedTask, seed.objectID == task.objectID {
                throw LillistError.validationFailed([
                    .init(field: "instance", message: "cannot fork from the seed task")
                ])
            }
            guard let rule = oldSeries.rule else {
                throw LillistError.validationFailed([
                    .init(field: "series", message: "missing rule")
                ])
            }

            // Build the new series.
            let newSeries = Series(context: context)
            newSeries.id = UUID()
            newSeries.rule = rule
            newSeries.seedTask = task
            // Move the forked instance into the new series.
            task.series = newSeries
            // Anchor the new series's next-occurrence on this instance.
            let anchor = task.start ?? task.createdAt ?? Date()
            newSeries.nextOccurrenceAfter = Self.computeNextOccurrence(rule: rule, after: anchor)

            try context.save()
            return newSeries.id!
        }
    }
```

- [ ] **Step 4: Run fork tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter SeriesStoreForkTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Run the full test suite**

Run: `cd Packages/LillistCore && swift test`
Expected: green across the board.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/SeriesStoreForkTests.swift
git commit -m "feat(recurrence): add SeriesStore.forkFutureFromInstance for edit-all-future"
```

---

## Task 19: Integration sweep — full suite, strict concurrency, tag

**Files:**
- (no new files)

- [ ] **Step 1: Run the entire test suite**

Run: `cd Packages/LillistCore && swift test 2>&1 | tee /tmp/lillist-recurrence-test.log`
Expected: all tests pass. The Plan 4 additions alone should number around 50+ tests across recurrence-math, series CRUD, fork, and spawn behavior.

- [ ] **Step 2: Run with strict concurrency surfaced**

Run: `cd Packages/LillistCore && swift build -Xswiftc -warnings-as-errors`
Expected: build succeeds with no escalated warnings. If a concurrency warning appears (likely on a new `@unchecked Sendable` boundary), fix at source per Plan 1's playbook: annotate, mark `nonisolated`, or move state inside the `perform` block.

- [ ] **Step 3: Confirm `RecurrenceSpawner` is internal-only (not public)**

Run: `grep -n "public " Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift`
Expected: no output. The spawner is an implementation detail — only `TaskStore.transition` invokes it, and there's no reason for external callers to spawn manually.

- [ ] **Step 4: Tag the plan completion**

```bash
git tag -a plan-4-recurrence -m "Lillist Plan 4: Recurrence engine complete"
```

- [ ] **Step 5: Final verification**

Run: `cd Packages/LillistCore && swift test`
Expected: full suite green.

Plan 4 is complete. The recurrence engine — Series, instances, calendar + after-completion rules, spawn-on-close, edit-all-future fork — is ready for use by the GUI (Plan 6+) and CLI (Plan 5).

---

## Self-Review Checklist (run by the implementer before merging)

- [ ] **Design alignment.** Design Section 2 (Series mechanics) and Section 8 (Recurrence edge cases) drove the test list; every edge case listed there has a corresponding test.
- [ ] **DST correctness.** Wall-clock time is preserved across both spring-forward and fall-back; tests cover both, using `Calendar`-aware math throughout, never `Date.addingTimeInterval` on calendar fields.
- [ ] **`byMonthDay = 31` skip-month.** Tests verify *skip*, not coerce-to-30. Plain monthly (seed on the 31st) also skips short months.
- [ ] **`byDay` × `bySetPos` combinations.** First/last weekday of month, first weekday of month (any weekday), and bi-weekly Tue/Thu all covered.
- [ ] **`count` and `until` limits.** Both produce `nextOccurrenceAfter = nil` when reached; spawner refuses to spawn; existing instances unaffected (design Section 8).
- [ ] **After-completion.** Returns `completedAt + interval`; integrates with spawn-on-close.
- [ ] **Re-open is one-way.** Test confirms re-opening a closed instance does not undo the spawn.
- [ ] **Fork preserves old series.** New series has the forked instance as its seed; old series keeps its existing instances and remains spawnable.
- [ ] **Fork from seed rejected.** Forking from the seed task or from a non-instance task throws `LillistError.validationFailed`.
- [ ] **Atomicity.** Spawn runs inside the same `viewContext` perform block as the close transition; if the save fails, no half-spawn is left behind.
- [ ] **No `NSManagedObject` escapes.** All public APIs return `SeriesRecord` value-types, matching Plan 1 conventions.
- [ ] **CloudKit compatibility maintained.** All new attributes optional; no `Deny` deletion rules; every new relationship has an inverse.
- [ ] **Test Engineer subagent review** per design Section 9 — coverage of behaviors, edge case taxonomy completeness, mutation-test-style rigor.
