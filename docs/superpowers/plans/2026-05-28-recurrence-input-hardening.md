# Recurrence Input Hardening Implementation Plan

> **📍 STATUS — ⬜ PENDING — **the remaining Wave 1 P0; this is the immediate next task** (HIGH: `interval==0` crash on synced/imported data).**
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> ⚠️ **Wave 1 (`store-swap-safety`) is merged to `main`.** It changed several shared files (`MigrationCoordinator`, `PersistenceHost`, `QuarantineManager`, `MigrationJournal`, both `AppEnvironment`s, `PersistenceController`). **Re-Read every file before editing and anchor by code structure — the line numbers in this plan may have drifted.**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the recurrence engine crash-safe against untrusted `interval`/`count` input arriving via CloudKit decode, Importer, or CLI — without dropping recurrence on corrupt data.

**Architecture:** Normalize `interval = max(1, interval)` at the single `CalendarRule` trust boundary (both `init` and `init(from:)`), logging a warning via a new recurrence-scoped `os.Logger` rather than throwing. Add defense-in-depth guarded effective intervals (`let n = max(1, rule.interval)`) at the expander's divide/loop sites so even a hand-constructed rule that bypasses the boundary cannot divide-by-zero or loop-trap. Exclude soft-deleted instances from `RecurrenceSpawner.countReached` so trashing an instance of a `count = N` series doesn't permanently stall the series at the limit.

**Tech Stack:** Swift 6.2, `os.Logger` (subsystem-scoped), Core Data (`NSManagedObject` `Series`/`LillistTask`), Swift Testing (`import Testing`, `@Test`/`#expect`), `RecurrenceTestCalendar` + `TestStore` test helpers.

**Source findings:** rec-1, rec-2, stores-7

---

## File Structure

### Create

| Path | Responsibility |
|------|----------------|
| `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceLog.swift` | One `os.Logger` for the recurrence subsystem, used to warn (not throw) when an out-of-range interval is normalized. Single source of truth so `RecurrenceRule` and the expander don't each define ad-hoc loggers. |
| `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceRuleNormalizationTests.swift` | Boundary tests: `CalendarRule.init` and `RecurrenceRule.init(from:)` (JSON decode) normalize `interval ∈ {0, -1}` to `1` across all four frequencies. |
| `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderIntervalGuardTests.swift` | Defense-in-depth tests: a directly-constructed `CalendarRule` whose `interval` field has been forced to `0`/`-1` (bypassing the boundary) does not crash or loop-trap the expander across all four frequencies. |

### Modify

| Path | Responsibility | Approx. lines today |
|------|----------------|---------------------|
| `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift` | Normalize `interval` in `CalendarRule.init` and `RecurrenceRule.init(from:)`; closes rec-1 at the trust boundary. | `CalendarRule.init` @ 30–46; `RecurrenceRule.init(from:)` @ 66–75 |
| `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift` | Guard effective interval (`let n = max(1, rule.interval)`) at the daily step, weekly fallback/wrap, monthly modulo, by-set-pos modulo, and yearly step; closes rec-1 defense-in-depth. | daily @ 53; weekly @ 69, 79; monthly @ 100, 104; bySetPos @ 127, 131; yearly @ 212, 227 |
| `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift` | Exclude soft-deleted instances from `countReached`; closes stores-7. | `countReached` @ 118–126 |

---

## Task 1: Add the recurrence-scoped logger

**Files:** Create `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceLog.swift`.

This is a non-TDD-able infrastructure step (a `Logger` has no testable behavior of its own — its callers are tested in Tasks 2–3). It exists so the normalization warnings in Task 2 have a single, consistent destination instead of `print()` or ad-hoc loggers, matching the codebase's existing OSLog usage in `CrashReporting`.

- [ ] **Step 1: Create the file** with the complete content below. `os.Logger` is `Sendable`, available on macOS 11+/iOS 14+ (the package targets macOS 15 / iOS 18, per `Packages/LillistCore/Package.swift`), so a module-internal `static let` satisfies strict concurrency.

```swift
import Foundation
import os

/// Logging destination for the recurrence subsystem.
///
/// Recurrence input arriving from CloudKit decode, the Importer, or the CLI is
/// *untrusted*. When such input is out of range (e.g. a non-positive interval),
/// `RecurrenceRule` normalizes it rather than throwing — dropping the rule would
/// lose a user's recurrence on a single corrupt sync record. Each normalization
/// emits a `.warning` here so the event is visible in field diagnostics without
/// crashing or silently swallowing the corruption.
enum RecurrenceLog {
    /// Stable subsystem string, sibling to `CrashReporting.subsystemIdentifier`.
    static let subsystem = "io.mikeydotio.lillist.recurrence"

    /// Logger for input-normalization events at the `CalendarRule` trust boundary.
    static let normalization = Logger(subsystem: subsystem, category: "normalization")
}
```

- [ ] **Step 2: Verify it compiles** within the package.

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore
```

Expected: `Build complete!` with zero warnings (warnings are errors on this target).

- [ ] **Step 3: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceLog.swift
git commit -m "feat(recurrence): add recurrence-scoped os.Logger for input warnings"
```

---

## Task 2: Normalize `interval` at the `CalendarRule` trust boundary (rec-1)

**Files:**
- Test (create): `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceRuleNormalizationTests.swift`
- Modify: `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift` (`CalendarRule.init` @ 30–46; `RecurrenceRule.init(from:)` @ 66–75)

Normalization happens in `CalendarRule.init`. Because `init(from decoder:)` on the enum decodes the nested `CalendarRule` via its synthesized `Codable` conformance (`try c.decode(CalendarRule.self, …)` at line 71), the synthesized `CalendarRule` decoder assigns the raw `interval` field directly and does **not** call our designated `init`. So we must (a) normalize in `CalendarRule.init`, and (b) give `CalendarRule` a hand-written `init(from:)` that routes through the same normalization. This keeps the boundary DRY: both construction paths funnel through one `normalizedInterval(_:)` helper.

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceRuleNormalizationTests.swift` with this complete content. It covers both construction paths (`init` and JSON decode) for `interval ∈ {0, -1}` across all four frequencies, and confirms a valid interval is left untouched.

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceRule interval normalization")
struct RecurrenceRuleNormalizationTests {
    static let allFrequencies: [RecurrenceRule.Frequency] = [.daily, .weekly, .monthly, .yearly]

    // MARK: - Memberwise init boundary

    @Test("init clamps interval 0 to 1 across all frequencies")
    func initClampsZero() throws {
        for freq in Self.allFrequencies {
            let rule = RecurrenceRule.CalendarRule(freq: freq, interval: 0)
            #expect(rule.interval == 1)
        }
    }

    @Test("init clamps negative interval to 1 across all frequencies")
    func initClampsNegative() throws {
        for freq in Self.allFrequencies {
            let rule = RecurrenceRule.CalendarRule(freq: freq, interval: -1)
            #expect(rule.interval == 1)
        }
    }

    @Test("init preserves a valid positive interval")
    func initPreservesValid() throws {
        for freq in Self.allFrequencies {
            let rule = RecurrenceRule.CalendarRule(freq: freq, interval: 3)
            #expect(rule.interval == 3)
        }
    }

    // MARK: - JSON decode boundary (CloudKit / Importer / CLI surface)

    /// Builds raw JSON matching `RecurrenceRule`'s discriminator layout with an
    /// arbitrary (possibly invalid) interval, bypassing the memberwise init.
    private func calendarJSON(freq: RecurrenceRule.Frequency, interval: Int) -> Data {
        let json = """
        {"type":"calendar","rule":{"freq":"\(freq.rawValue)","interval":\(interval)}}
        """
        return Data(json.utf8)
    }

    @Test("decode clamps interval 0 to 1 across all frequencies")
    func decodeClampsZero() throws {
        for freq in Self.allFrequencies {
            let decoded = try JSONDecoder().decode(
                RecurrenceRule.self,
                from: calendarJSON(freq: freq, interval: 0)
            )
            guard case .calendar(let cal) = decoded else {
                Issue.record("expected .calendar for \(freq)")
                continue
            }
            #expect(cal.interval == 1)
            #expect(cal.freq == freq)
        }
    }

    @Test("decode clamps negative interval to 1 across all frequencies")
    func decodeClampsNegative() throws {
        for freq in Self.allFrequencies {
            let decoded = try JSONDecoder().decode(
                RecurrenceRule.self,
                from: calendarJSON(freq: freq, interval: -1)
            )
            guard case .calendar(let cal) = decoded else {
                Issue.record("expected .calendar for \(freq)")
                continue
            }
            #expect(cal.interval == 1)
        }
    }

    @Test("decode preserves a valid positive interval")
    func decodePreservesValid() throws {
        let decoded = try JSONDecoder().decode(
            RecurrenceRule.self,
            from: calendarJSON(freq: .weekly, interval: 2)
        )
        guard case .calendar(let cal) = decoded else {
            Issue.record("expected .calendar")
            return
        }
        #expect(cal.interval == 2)
    }

    @Test("decode preserves byDay/count/until while clamping interval")
    func decodePreservesOtherFieldsWhileClamping() throws {
        // Weekday's Codable raw values are the RFC-5545 codes ("MO", "FR"),
        // not the case names — see Weekday.swift.
        let json = """
        {"type":"calendar","rule":{"freq":"weekly","interval":0,"byDay":["MO","FR"],"count":5}}
        """
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: Data(json.utf8))
        guard case .calendar(let cal) = decoded else {
            Issue.record("expected .calendar")
            return
        }
        #expect(cal.interval == 1)
        #expect(cal.byDay == [.monday, .friday])
        #expect(cal.count == 5)
    }
}
```

- [ ] **Step 2: Run the test, expect failure.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter RecurrenceRuleNormalizationTests
```

Expected: the `init…` tests fail with `Expectation failed: (rule.interval → 0) == 1` (and `→ -1`), and the `decode…` tests fail with `(cal.interval → 0) == 1` — because no normalization exists yet. The `…PreservesValid` tests pass.

- [ ] **Step 3: Implement the minimal change** — edit `RecurrenceRule.swift`. Add a `private static func normalizedInterval(_:)` helper on `CalendarRule`, route the memberwise `init` through it, and add a hand-written `init(from:)` on `CalendarRule` that decodes every field and normalizes the interval (the enum's existing `init(from:)` at line 66 calls `c.decode(CalendarRule.self, …)`, so this new decoder is what runs on the JSON path — no change needed to the enum decoder itself).

Replace the existing `CalendarRule` struct body (lines 21–47) with:

```swift
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
            self.interval = Self.normalizedInterval(interval)
            self.byDay = byDay
            self.byMonthDay = byMonthDay
            self.bySetPos = bySetPos
            self.count = count
            self.until = until
        }

        private enum CodingKeys: String, CodingKey {
            case freq, interval, byDay, byMonthDay, bySetPos, count, until
        }

        /// Hand-written decoder so untrusted JSON (CloudKit / Importer / CLI)
        /// funnels through the same interval normalization as the memberwise
        /// `init`. The synthesized decoder would assign the raw `interval`
        /// directly, leaving a `0`/negative value that crashes the expander.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.freq = try c.decode(Frequency.self, forKey: .freq)
            self.interval = Self.normalizedInterval(try c.decode(Int.self, forKey: .interval))
            self.byDay = try c.decodeIfPresent([Weekday].self, forKey: .byDay)
            self.byMonthDay = try c.decodeIfPresent([Int].self, forKey: .byMonthDay)
            self.bySetPos = try c.decodeIfPresent([Int].self, forKey: .bySetPos)
            self.count = try c.decodeIfPresent(Int.self, forKey: .count)
            self.until = try c.decodeIfPresent(Date.self, forKey: .until)
        }

        /// Clamps an interval to the valid `>= 1` range. An interval of `0`
        /// divide-by-zero-crashes the monthly expander and loop-traps the
        /// daily/weekly steps; a negative interval walks backwards forever.
        /// We normalize rather than throw so a single corrupt sync record
        /// can't strip recurrence off the series entirely (rec-1).
        private static func normalizedInterval(_ raw: Int) -> Int {
            guard raw < 1 else { return raw }
            RecurrenceLog.normalization.warning(
                "CalendarRule interval \(raw, privacy: .public) out of range; clamped to 1"
            )
            return 1
        }
    }
```

Note: the struct still declares `Codable` conformance, and because we now provide a custom `init(from:)`, the compiler keeps the synthesized `encode(to:)` (only the decoder is overridden), so round-trip encoding is unchanged. The `private enum CodingKeys` does not collide with the enum-level `CodingKeys` (line 56) — they're scoped to different types.

- [ ] **Step 4: Run the test, expect pass.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter RecurrenceRuleNormalizationTests
```

Expected: all 8 tests pass. Also re-run the existing coding suite to confirm no regression:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter RecurrenceRuleCodingTests
```

Expected: all 7 existing coding tests still pass (round-trip encode/decode and discriminator stability are preserved).

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceRuleNormalizationTests.swift
git commit -m "fix(recurrence): clamp interval to >=1 at CalendarRule trust boundary

Untrusted recurrence input (CloudKit decode, Importer, CLI) bypassed the
UI clamp and could carry interval 0 or negative, which crashes the
monthly expander (divide-by-zero) and loop-traps daily/weekly. Normalize
in both the memberwise init and a new hand-written init(from:), logging a
warning instead of throwing so a corrupt sync record doesn't drop the
series' recurrence. Closes rec-1 (boundary half)."
```

---

## Task 3: Defense-in-depth interval guards in the expander (rec-1)

**Files:**
- Test (create): `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderIntervalGuardTests.swift`
- Modify: `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift` (daily @ 53; weekly @ 69, 79; monthly @ 100, 104; bySetPos @ 127, 131; yearly @ 212, 227)

Task 2 closes the boundary, but a caller could hand-construct a `CalendarRule` and then mutate its `var interval` to `0`, or a future code path could bypass the init. The expander must not crash or hang regardless. The test forces an invalid interval *after* construction (mutating the `var interval` field) to prove the guards stand alone.

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderIntervalGuardTests.swift` with this complete content. Each case mutates `interval` to `0` then `-1` post-construction (defeating the Task-2 boundary) and asserts the expander returns the same finite result as the canonical `interval = 1` rule — and crucially returns at all (no divide-by-zero trap, no infinite loop). The `count` cap keeps the run bounded; if the daily/weekly/yearly loop trapped, the test process would hang rather than fail, which is the correct signal that the guard is missing.

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander interval guard (defense-in-depth)")
struct RecurrenceExpanderIntervalGuardTests {
    private let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 15, hour: 9)
    private let calendar = RecurrenceTestCalendar.pacific

    /// Forces `interval` to `invalid` after construction (bypassing the
    /// `CalendarRule` boundary) and asserts the expander treats it as `1` —
    /// the same finite, non-empty result as a canonical interval=1 rule.
    private func expectTreatedAsOne(
        freq: RecurrenceRule.Frequency,
        invalid: Int,
        byDay: [Weekday]? = nil,
        bySetPos: [Int]? = nil
    ) {
        var rule = RecurrenceRule.CalendarRule(
            freq: freq,
            interval: 1,
            byDay: byDay,
            bySetPos: bySetPos
        )
        rule.interval = invalid // defeat the boundary

        let canonical = RecurrenceExpander.nextOccurrences(
            after: seed, rule: { var r = rule; r.interval = 1; return r }(),
            calendar: calendar, count: 3
        )
        let guarded = RecurrenceExpander.nextOccurrences(
            after: seed, rule: rule, calendar: calendar, count: 3
        )
        #expect(guarded.isEmpty == false)
        #expect(guarded == canonical)
    }

    @Test("daily interval 0 does not loop-trap and behaves as interval 1")
    func dailyZero() { expectTreatedAsOne(freq: .daily, invalid: 0) }

    @Test("daily interval -1 does not walk backwards forever")
    func dailyNegative() { expectTreatedAsOne(freq: .daily, invalid: -1) }

    @Test("weekly (no byDay) interval 0 does not loop-trap")
    func weeklyZeroNoByDay() { expectTreatedAsOne(freq: .weekly, invalid: 0) }

    @Test("weekly (with byDay wrap) interval 0 does not loop-trap")
    func weeklyZeroWithByDay() {
        expectTreatedAsOne(freq: .weekly, invalid: 0, byDay: [.monday])
    }

    @Test("weekly interval -1 with byDay wrap is finite")
    func weeklyNegativeWithByDay() {
        expectTreatedAsOne(freq: .weekly, invalid: -1, byDay: [.monday])
    }

    @Test("monthly interval 0 does not divide-by-zero crash")
    func monthlyZero() { expectTreatedAsOne(freq: .monthly, invalid: 0) }

    @Test("monthly interval -1 does not crash")
    func monthlyNegative() { expectTreatedAsOne(freq: .monthly, invalid: -1) }

    @Test("monthly by-set-pos interval 0 does not divide-by-zero crash")
    func monthlyBySetPosZero() {
        expectTreatedAsOne(freq: .monthly, invalid: 0, byDay: [.monday], bySetPos: [1])
    }

    @Test("yearly interval 0 does not loop-trap")
    func yearlyZero() { expectTreatedAsOne(freq: .yearly, invalid: 0) }

    @Test("yearly interval -1 is finite")
    func yearlyNegative() { expectTreatedAsOne(freq: .yearly, invalid: -1) }
}
```

- [ ] **Step 2: Run the test, expect failure** — note this run can *hang* (loop-trap) for the daily/weekly/yearly cases before any guard exists, and *crash* (`Fatal error: Division by zero`) for the monthly cases. Run with a timeout so a hang surfaces as a failure rather than blocking the session.

```bash
cd /Volumes/Code/mikeyward/Lillist && timeout 120 swift test --package-path Packages/LillistCore --filter RecurrenceExpanderIntervalGuardTests
```

Expected: process either crashes with `Fatal error: Division by zero` (monthly cases) or is killed by `timeout` after 120s (daily/weekly/yearly loop-trap) — both confirm the guards are missing. If it returns quickly with `#expect` failures instead, that also confirms the unguarded behavior diverges from canonical.

- [ ] **Step 3: Implement the minimal change** — edit `RecurrenceExpander.swift` to clamp the effective interval at every site that uses `rule.interval` (or the passed `interval` param) as a step multiplier, loop bound, or modulus.

Replace the `step(from:rule:calendar:)` method (lines 46–61) — guard the daily step:

```swift
    private static func step(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        switch rule.freq {
        case .daily:
            let n = max(1, rule.interval)
            return calendar.date(byAdding: .day, value: n, to: previous)
        case .weekly:
            return weeklyStep(from: previous, rule: rule, calendar: calendar)
        case .monthly:
            return monthlyStep(from: previous, rule: rule, calendar: calendar)
        case .yearly:
            return yearlyStep(from: previous, rule: rule, calendar: calendar)
        }
    }
```

Replace the `weeklyStep` method (lines 63–81) — guard both the no-byDay fallback and the wrap multiplier:

```swift
    private static func weeklyStep(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        let n = max(1, rule.interval)
        guard let byDay = rule.byDay, byDay.isEmpty == false else {
            return calendar.date(byAdding: .weekOfYear, value: n, to: previous)
        }
        let sortedDays = byDay.sorted { $0.calendarComponent < $1.calendarComponent }
        let previousWeekday = calendar.component(.weekday, from: previous)
        if let next = sortedDays.first(where: { $0.calendarComponent > previousWeekday }) {
            let delta = next.calendarComponent - previousWeekday
            return calendar.date(byAdding: .day, value: delta, to: previous)
        }
        let firstNext = sortedDays.first!
        let daysToEndOfWeek = 7 - previousWeekday + firstNext.calendarComponent
        let totalDays = daysToEndOfWeek + 7 * (n - 1)
        return calendar.date(byAdding: .day, value: totalDays, to: previous)
    }
```

Replace the `monthlyStep` method (lines 83–117) — guard the loop bound and the modulus:

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
        let n = max(1, rule.interval)
        let targetDays = rule.byMonthDay ?? [calendar.component(.day, from: previous)]
        var monthOffset = 0
        while monthOffset <= 12 * n + 1 {
            guard let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: previous) else {
                return nil
            }
            if monthOffset > 0 && monthOffset % n != 0 {
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
```

Replace the `monthlyStepBySetPos` method (lines 119–151) — guard the loop bound and modulus on the passed `interval`:

```swift
    private static func monthlyStepBySetPos(
        from previous: Date,
        byDay: [Weekday],
        bySetPos: [Int],
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        let n = max(1, interval)
        var monthOffset = 0
        while monthOffset <= 12 * n + 1 {
            guard let monthAnchor = calendar.date(byAdding: .month, value: monthOffset, to: previous) else {
                return nil
            }
            if monthOffset > 0 && monthOffset % n != 0 {
                monthOffset += 1
                continue
            }
            let candidates = candidateDates(
                inMonthOf: monthAnchor,
                weekdays: byDay,
                timeOf: previous,
                calendar: calendar
            ).sorted()
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
```

Replace the `yearlyStep` method (lines 202–230) — guard the year-advance step (an `interval = 0` here would never advance `year` and the `for _ in 0..<40` loop would return `nil` instead of a date, silently dropping the rule; clamping to `1` produces the correct next year):

```swift
    private static func yearlyStep(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        let n = max(1, rule.interval)
        let month = calendar.component(.month, from: previous)
        let day = calendar.component(.day, from: previous)
        let hour = calendar.component(.hour, from: previous)
        let minute = calendar.component(.minute, from: previous)
        let second = calendar.component(.second, from: previous)
        var year = calendar.component(.year, from: previous) + n

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
            year += n
        }
        return nil
    }
```

Note: the existing `12 * max(rule.interval, 1) + 1` / `12 * max(interval, 1) + 1` loop-bound expressions (old lines 100, 127) are now expressed via the local `n`, so the `max(…)` is no longer duplicated inline — DRY, single normalization per method.

- [ ] **Step 4: Run the test, expect pass.**

```bash
cd /Volumes/Code/mikeyward/Lillist && timeout 120 swift test --package-path Packages/LillistCore --filter RecurrenceExpanderIntervalGuardTests
```

Expected: all 10 tests pass, process returns in well under the timeout. Then run the full recurrence suite to confirm the guards didn't change valid-interval behavior:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter Recurrence
```

Expected: all recurrence suites pass (Daily, Weekly, Monthly, Yearly, BySetPos, ByMonthDay31, DST, Limit, AfterCompletion, Coding, Normalization, IntervalGuard).

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Recurrence/RecurrenceExpanderIntervalGuardTests.swift
git commit -m "fix(recurrence): guard effective interval at all expander modulo/step sites

Defense-in-depth for rec-1: even if a CalendarRule's interval field is
forced out of range after construction, the expander clamps to max(1, n)
at every daily/weekly/monthly/by-set-pos/yearly site, so it can never
divide-by-zero or loop-trap. Closes rec-1 (expander half)."
```

---

## Task 4: Exclude soft-deleted instances from the count budget (stores-7)

**Files:**
- Test (create): add to `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreRecurrenceSpawnTests.swift` (existing suite; matches framework + `TestStore`)
- Modify: `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift` (`countReached` @ 118–126)

`countReached` counts `series.instances.count`, which includes soft-deleted (trashed) instances. The `LillistTask` entity tracks soft-delete via `deletedAt: Date?` (verified in `LillistTask+CoreData.swift:20`). If a user trashes an instance of a `count = N` series, the trashed row still counts toward the budget, so the series stalls one short. Filter `deletedAt == nil` so only live instances count toward `count`.

The relevant verified APIs (re-confirm with the grep in Step 0 if the file has drifted):
- `TaskStore.softDelete(id: UUID) async throws` — `TaskStore.swift:386`; cascades only to live *children* (`TaskStore.swift:466`).
- `TaskStore.children(of: UUID?) async throws -> [TaskRecord]` — filters `deletedAt == nil` (`TaskStore.swift:208,210`).
- Spawned instances are *siblings* of the seed (`spawn.parent = seed.parent`, `RecurrenceSpawner.swift:44`), so trashing the seed does not cascade to the spawn.
- `Series.instances` is the `NSSet` of all instances incl. trashed (`Series+CoreData.swift:11`); `LillistTask.deletedAt: Date?` is the soft-delete marker (`LillistTask+CoreData.swift:20`).

- [ ] **Step 0: Confirm the soft-delete + children signatures still match** before writing the test.

```bash
cd /Volumes/Code/mikeyward/Lillist && grep -n "func softDelete\|func children" Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift
```

Expected: `func softDelete(id: UUID) async throws` and `func children(of parentID: UUID?) async throws -> [TaskRecord]`. If either differs, substitute the real name verbatim in the test below — do not invent an overload.

- [ ] **Step 1: Write the failing test** — add this `@Test` to the existing `TaskStoreRecurrenceSpawnTests` suite in `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreRecurrenceSpawnTests.swift` (insert after the `countLimit` test, currently ending at line 105, before `untilLimit` at line 107). It builds a `count = 2` daily series, closes the seed to spawn instance #2, trashes the seed, then closes the surviving live instance and asserts a *third* spawn still occurs — proving the trashed instance no longer consumes the budget.

```swift
    @Test("Trashing an instance does not consume the count budget")
    func trashedInstanceDoesNotConsumeCount() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Budgeted")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1, count: 2))
        let seriesID = try await series.create(fromSeedTask: seedID, rule: rule)

        // Close the seed (instance #1) -> spawns instance #2.
        try await tasks.transition(id: seedID, to: .closed)
        let afterFirst = try await tasks.children(of: nil).filter { $0.title == "Budgeted" }
        #expect(afterFirst.count == 2)

        // Trash the original seed instance. With count=2 and two live
        // instances the series would normally be done; after trashing the
        // seed only ONE live instance remains, so the budget is not yet
        // reached and the next close must still spawn.
        try await tasks.softDelete(id: seedID)

        // Close the surviving live instance -> must spawn instance #3.
        let liveOpenID = afterFirst.first { $0.id != seedID && $0.status == .todo }!.id
        try await tasks.transition(id: liveOpenID, to: .closed)

        // Series still has a future occurrence (budget not exhausted by the
        // trashed instance)...
        #expect(try await series.fetch(id: seriesID).nextOccurrenceAfter != nil)
        // ...and exactly two LIVE instances exist (the trashed seed is
        // filtered out of `children(of:)`, which excludes deletedAt != nil).
        let live = try await tasks.children(of: nil).filter { $0.title == "Budgeted" }
        #expect(live.count == 2)
    }
```

- [ ] **Step 2: Run the test, expect failure.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter trashedInstanceDoesNotConsumeCount
```

Expected: fails at `#expect(try await series.fetch(id: seriesID).nextOccurrenceAfter != nil)` — the value is `nil` because `countReached` counted the trashed seed (`existing == 2 >= count == 2`), so the series stopped early and the second close spawned nothing.

- [ ] **Step 3: Implement the minimal change** — edit `RecurrenceSpawner.swift`. Replace the `countReached(series:rule:)` method (lines 116–126) so only live (non-soft-deleted) instances count toward `count`:

```swift
    /// True if the rule's `count` budget would be consumed after this spawn.
    /// The seed is instance #1; each spawned instance counts toward `count`.
    /// Soft-deleted (trashed) instances are excluded so trashing an instance
    /// of a `count = N` series doesn't permanently stall the series one short
    /// of its budget (stores-7).
    private static func countReached(
        series: Series,
        rule: RecurrenceRule
    ) -> Bool {
        guard case .calendar(let cal) = rule, let count = cal.count else { return false }
        let instances = (series.instances as? Set<LillistTask>) ?? []
        let live = instances.filter { $0.deletedAt == nil }.count
        // `live` already includes the new spawn (we set spawn.series = series above).
        return live >= count
    }
```

- [ ] **Step 4: Run the test, expect pass.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter trashedInstanceDoesNotConsumeCount
```

Expected: the test passes. Then re-run the full spawn suite to confirm the existing `count = 2` stop-behavior (no trashing) is unchanged:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter TaskStoreRecurrenceSpawnTests
```

Expected: all 9 spawn tests pass (the 8 originals + the new one) — in particular `countLimit` (no trash) still stops at two instances.

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreRecurrenceSpawnTests.swift
git commit -m "fix(recurrence): exclude soft-deleted instances from count budget

countReached counted trashed instances toward a series' count limit, so
trashing one instance of a count=N series stalled it one short forever.
Filter deletedAt == nil so only live instances consume the budget.
Closes stores-7."
```

---

## Task 5: Final full-suite verification

**Files:** none (verification only).

Confirms the three findings are closed together with no regression and no warnings (warnings are errors on the source target).

- [ ] **Step 1: Run the whole LillistCore test suite.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore
```

Expected: all suites pass, including the new `RecurrenceRule interval normalization`, `RecurrenceExpander interval guard (defense-in-depth)`, and the augmented `TaskStore recurrence spawn`. No pre-existing tests fail.

- [ ] **Step 2: Confirm a clean, warning-free build.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | grep -i "warning:" || echo "no warnings"
```

Expected: `no warnings`. (`.treatAllWarnings(as: .error)` is on the source target, so any warning would already have failed the build.)

- [ ] **Step 3: No commit** — this task only verifies; all code landed in Tasks 1–4.

---

## Self-review checklist

- [ ] **rec-1** (`interval == 0`/negative crashes the recurrence expander on untrusted synced/imported/CLI data) — closed at the trust boundary by **Task 2** (`CalendarRule.init` + hand-written `CalendarRule.init(from:)` normalize `interval = max(1, …)`, logging via `RecurrenceLog` from **Task 1** instead of throwing) and defense-in-depth by **Task 3** (`let n = max(1, …)` at every daily/weekly/monthly/by-set-pos/yearly step + modulo site in `RecurrenceExpander`). Boundary tests across all four frequencies via `init` and JSON decode (Task 2); non-crash/non-trap expander tests across all four frequencies with post-construction-forced invalid intervals (Task 3).
- [ ] **rec-2** (defense-in-depth guarded effective interval at the expander modulo sites; UI clamp at `RecurrenceEditorViewModel` is not the only guard) — closed by **Task 3**: the `monthly`/`monthlyStepBySetPos` modulus sites (`monthOffset % n`) and the daily/weekly/yearly step multipliers all use the clamped `n`, proven by `RecurrenceExpanderIntervalGuardTests` (notably the divide-by-zero monthly cases).
- [ ] **stores-7** (soft-deleted instances counted toward the recurrence `count` budget, stalling the series) — closed by **Task 4**: `RecurrenceSpawner.countReached` now filters `deletedAt == nil`, proven by `trashedInstanceDoesNotConsumeCount` (trashes an instance of a `count = 2` series and asserts a further spawn still occurs), with the existing no-trash `countLimit` test confirming the stop-at-budget behavior is preserved.

**Strengths preserved (not refactored away):**
- Calendar-based date math throughout — Task 3 only inserts `max(1, …)` clamps; no `addingTimeInterval` introduced, the one `afterCompletion` callsite untouched.
- Stable Codable discriminator — Task 2 adds a `CalendarRule.init(from:)` but keeps the synthesized `encode(to:)` and the enum-level `type`/`rule` discriminator; `RecurrenceRuleCodingTests` (round-trip + discriminator stability + unknown-discriminator-throws) is re-run and must stay green.
- No `NSManagedObject` escapes `LillistCore` — Task 4 operates on `Series`/`LillistTask` only inside `RecurrenceSpawner` (already inside the module, called within `context.perform`); the public spawn API still returns a `UUID?`.
- Strict concurrency / warnings-as-errors — `RecurrenceLog` uses a `Sendable` `os.Logger` `static let`; Task 5 asserts a warning-free build.