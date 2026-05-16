# Lillist Plan 12 — Plan 11 Follow-up Cleanup

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close two cleanup items deferred by Plan 11: (1) `TaskRecord.seriesID` is now populated by the canonical `TaskStore.record(from:)` mapper, but two parallel mappers — `SmartFilterStore.record(from:)` and `CLIBridge.LsHandler.record(from:)` — still skip it, leaving smart-filter results and `lillist ls` output without series membership info; (2) the macOS hotkey stack has two duplicated keyCode↔keyName tables (one inside `HotkeyRecorder` for encoding, one inside `GlobalHotkeyMonitor` for parsing). Add either key to one without the other and the round-trip silently breaks. Consolidate into a shared `HotkeyKeyTable` type with a round-trip regression test.

**Architecture:** Item 1 is a 2-line edit to each parallel mapper plus two small Swift Testing additions. Item 2 introduces `Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift` as the single canonical source of `keyCode ↔ keyName`; both `HotkeyRecorder.encode` and `GlobalHotkeyMonitor.parse` delegate to it. A round-trip test asserts `parse(encode(x)) == x` for representative combos.

**Tech Stack:** Swift 6, Swift Testing.

**Depends on:** Plan 11 (`TaskRecord.seriesID`, `HotkeyRecorder.swift`, `GlobalHotkeyMonitor.swift`).

---

## Task 1: Populate `seriesID` in `SmartFilterStore.record(from:)`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:310-328`
- Modify: `Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift` (or add a new test file if cleaner)

- [ ] **Step 1: Write the failing test**

Append to `SmartFilterStoreTests.swift` (or whichever existing smart-filter test file is closest to the evaluate path):

```swift
    @Test("SmartFilter evaluate result surfaces seriesID for recurring tasks")
    func evaluateSurfacesSeriesID() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let series = SeriesStore(persistence: persistence)
        let smart = SmartFilterStore(persistence: persistence)

        let taskID = try await tasks.create(title: "recurring")
        let seriesID = try await series.create(
            fromSeedTask: taskID,
            rule: .calendar(.init(freq: .daily, interval: 1))
        )

        // Match-everything filter.
        let group = PredicateGroup(combinator: .and, leaves: [], groups: [])
        let filterID = try await smart.create(name: "All", group: group)
        let results = try await smart.evaluate(filterID: filterID, sort: .createdAt, ascending: true)

        let recurring = results.first { $0.id == taskID }
        #expect(recurring?.seriesID == seriesID)
    }
```

- [ ] **Step 2: Run filter, verify fail**

```bash
swift test --package-path Packages/LillistCore --filter 'SmartFilter evaluate result surfaces seriesID' 2>&1 | tail -10
```

Expect: fails with "expected seriesID to be `<uuid>`, got nil" (or similar).

- [ ] **Step 3: Fix the mapper**

Open `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift`. Find the static `record(from m: LillistTask) -> TaskStore.TaskRecord` around line 310. Add `seriesID: m.series?.id` as the last field:

```swift
    static func record(from m: LillistTask) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: m.id ?? UUID(),
            title: m.title ?? "",
            notes: m.notes ?? "",
            status: m.status,
            start: m.start,
            startHasTime: m.startHasTime,
            deadline: m.deadline,
            deadlineHasTime: m.deadlineHasTime,
            position: m.position,
            isPinned: m.isPinned,
            parentID: m.parent?.id,
            createdAt: m.createdAt,
            modifiedAt: m.modifiedAt,
            closedAt: m.closedAt,
            deletedAt: m.deletedAt,
            seriesID: m.series?.id
        )
    }
```

- [ ] **Step 4: Run filter, verify pass**

```bash
swift test --package-path Packages/LillistCore --filter 'SmartFilter evaluate result surfaces seriesID' 2>&1 | tail -5
```

- [ ] **Step 5: Run full suite**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
```

Expect clean PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift
git commit -m "fix(core): SmartFilterStore.record propagates seriesID"
```

---

## Task 2: Populate `seriesID` in `CLIBridge.LsHandler.record(from:)`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift:52-70`
- Modify or create: `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/LsHandlerTests.swift` (or co-locate inside an existing handler test file)

- [ ] **Step 1: Write the failing test**

If `LsHandlerTests.swift` doesn't exist, create it. Otherwise append the test:

```swift
    @Test("Ls result surfaces seriesID for recurring tasks")
    func lsSurfacesSeriesID() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let series = SeriesStore(persistence: persistence)
        let taskID = try await tasks.create(title: "recurring")
        let seriesID = try await series.create(
            fromSeedTask: taskID,
            rule: .calendar(.init(freq: .daily, interval: 1))
        )

        let rendered = try await CLIBridge.LsHandler.run(
            filter: .init(),
            sort: .createdAt,
            ascending: true,
            persistence: persistence
        )
        let recurring = rendered.first { $0.id == taskID }
        #expect(recurring?.seriesID == seriesID)
    }
```

(Adapt to `LsHandler.run`'s actual signature — read the file first. If it takes a different argument shape, adjust the test to match while preserving the assertion's intent: "the LsHandler-produced TaskRecord has seriesID populated for a task in a series.")

- [ ] **Step 2: Run filter, verify fail**

```bash
swift test --package-path Packages/LillistCore --filter 'Ls result surfaces seriesID' 2>&1 | tail -10
```

- [ ] **Step 3: Fix the mapper**

In `LsHandler.swift` (around line 52-70), add `seriesID: m.series?.id` as the last field to the `TaskRecord(...)` construction:

```swift
        static func record(from m: LillistTask) -> TaskStore.TaskRecord {
            TaskStore.TaskRecord(
                id: m.id ?? UUID(),
                title: m.title ?? "",
                notes: m.notes ?? "",
                status: m.status,
                start: m.start,
                startHasTime: m.startHasTime,
                deadline: m.deadline,
                deadlineHasTime: m.deadlineHasTime,
                position: m.position,
                isPinned: m.isPinned,
                parentID: m.parent?.id,
                createdAt: m.createdAt,
                modifiedAt: m.modifiedAt,
                closedAt: m.closedAt,
                deletedAt: m.deletedAt,
                seriesID: m.series?.id
            )
        }
```

- [ ] **Step 4: Run filter, verify pass**

```bash
swift test --package-path Packages/LillistCore --filter 'Ls result surfaces seriesID' 2>&1 | tail -5
```

- [ ] **Step 5: Full suite**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
```

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/LsHandlerTests.swift
git commit -m "fix(cli): LsHandler.record propagates seriesID"
```

---

## Task 3: Consolidate `keyCode ↔ keyName` into `HotkeyKeyTable`

**Files:**
- Create: `Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift`
- Modify: `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift` (delete the `keyName(for:)` private method, delegate to `HotkeyKeyTable.name(forKeyCode:)`)
- Modify: `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift` (delete the `keyCode(for:)` private method, delegate to `HotkeyKeyTable.keyCode(forName:)`)
- Modify: `Apps/project.yml` if a new file in `Sources/Hotkey/` needs to be picked up by Xcode (it should be auto-discovered by directory glob — verify after regenerating)

- [ ] **Step 1: Create `HotkeyKeyTable.swift`**

```swift
import Foundation

/// Canonical mapping between macOS virtual key codes and the
/// lowercase string tokens used in user-facing hotkey combos
/// (`ctrl+opt+space`, `cmd+shift+l`).
///
/// Single source of truth: both ``HotkeyRecorder.encode`` (keyCode →
/// name, for writing user combos to preferences) and
/// ``GlobalHotkeyMonitor.parse`` (name → keyCode, for arming the
/// matcher) call through this enum. Plan 12 collapsed the two
/// previously-duplicated tables — adding a key in one place without
/// the other used to cause silent round-trip failures.
enum HotkeyKeyTable {
    /// Lookup keyed by macOS virtual key code; returns the canonical
    /// lowercase token, or `nil` for keys that aren't user-bindable.
    static func name(forKeyCode keyCode: Int) -> String? {
        codeToName[keyCode]
    }

    /// Lookup keyed by lowercase token; returns the macOS virtual key
    /// code, or `nil` for unknown names.
    static func keyCode(forName name: String) -> Int? {
        nameToCode[name]
    }

    /// Master table. Edits here automatically update both lookup
    /// directions and stay in sync.
    private static let entries: [(keyCode: Int, name: String)] = [
        // Letters
        (0, "a"), (1, "s"), (2, "d"), (3, "f"),
        (4, "h"), (5, "g"), (6, "z"), (7, "x"),
        (8, "c"), (9, "v"), (11, "b"), (12, "q"),
        (13, "w"), (14, "e"), (15, "r"), (16, "y"),
        (17, "t"), (31, "o"), (32, "u"), (34, "i"),
        (35, "p"), (37, "l"), (38, "j"), (40, "k"),
        (45, "n"), (46, "m"),
        // Whitespace & navigation
        (49, "space"), (36, "return"), (51, "delete"), (53, "escape"),
        // Digits
        (18, "1"), (19, "2"), (20, "3"), (21, "4"),
        (23, "5"), (22, "6"), (26, "7"), (28, "8"),
        (25, "9"), (29, "0"),
        // Function keys
        (122, "f1"), (120, "f2"), (99, "f3"), (118, "f4"),
        (96, "f5"), (97, "f6"), (98, "f7"), (100, "f8"),
        (101, "f9"), (109, "f10"), (103, "f11"), (111, "f12")
    ]

    private static let codeToName: [Int: String] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.keyCode, $0.name) }
    )
    private static let nameToCode: [String: Int] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.name, $0.keyCode) }
    )
}
```

- [ ] **Step 2: Update `HotkeyRecorder.swift` to delegate**

Find the `keyName(for keyCode: Int) -> String?` private static method (around line 95-115). Delete the body and the entire `switch` table; replace with a one-liner:

```swift
    private static func keyName(for keyCode: Int) -> String? {
        HotkeyKeyTable.name(forKeyCode: keyCode)
    }
```

Keep the method (it preserves the existing API surface inside the file), but the table is now in one place.

- [ ] **Step 3: Update `GlobalHotkeyMonitor.swift` to delegate**

Find the `keyCode(for name: String) -> Int?` private static method (lines 122-140). Same surgery:

```swift
    private static func keyCode(for name: String) -> Int? {
        HotkeyKeyTable.keyCode(forName: name)
    }
```

- [ ] **Step 4: Regenerate xcodegen if needed**

```bash
cd Apps && xcodegen generate --spec project.yml --project . && cd ..
git status --short Apps/Lillist-macOS.xcodeproj/project.pbxproj
```

If `project.pbxproj` shows changes, the new file got picked up — keep it staged.

- [ ] **Step 5: Build macOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 6: Re-run the existing `HotkeyRecorder` tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/HotkeyRecorderTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expect: 3 PASS (same tests as Plan 11 Task 17).

- [ ] **Step 7: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift \
        Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift \
        Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift \
        Apps/Lillist-macOS.xcodeproj/project.pbxproj
git commit -m "refactor(macOS): consolidate hotkey keyCode/keyName into HotkeyKeyTable"
```

---

## Task 4: Add a round-trip regression test for hotkey encode/decode

**File:**
- Modify: `Apps/Lillist-macOS/Tests/HotkeyRecorderTests.swift` (append a new test)

The test exercises `HotkeyRecorder.encode` (Plan 11 Task 17) and `GlobalHotkeyMonitor.parse` (Plan 11 Task 18) as a pair: every output of `encode` should round-trip cleanly through `parse`. Specifically: pick representative combos, encode them, parse the result, assert the parsed (modifiers, keyCode) match the original inputs.

- [ ] **Step 1: Append the test**

```swift
import AppKit
// (existing imports stay)

extension HotkeyRecorderTests {
    @Test("Encode then parse round-trips for representative combos")
    func encodeParseRoundTrip() {
        let cases: [(modifiers: NSEvent.ModifierFlags, keyCode: Int)] = [
            ([.control, .option], 49),     // ctrl+opt+space (default)
            ([.command, .shift], 37),      // cmd+shift+l
            ([.command], 18),              // cmd+1
            ([.command, .option, .shift], 99), // cmd+opt+shift+f3
            ([.shift], 122)                // shift+f1
        ]
        for c in cases {
            guard let encoded = HotkeyRecorder.encode(modifiers: c.modifiers, keyCode: c.keyCode) else {
                Issue.record("encode returned nil for \(c)")
                continue
            }
            guard let parsed = GlobalHotkeyMonitor.parse(combo: encoded) else {
                Issue.record("parse returned nil for '\(encoded)'")
                continue
            }
            #expect(parsed.modifiers == c.modifiers, "modifiers diverged for '\(encoded)'")
            #expect(parsed.keyCode == c.keyCode, "keyCode diverged for '\(encoded)'")
        }
    }
}
```

Note: `GlobalHotkeyMonitor.parse` is currently `static`. If it's not visible to the test target, expose it as `internal` (drop any `private` modifier) since it's already documented as a deliberate public-ish helper. If the test target uses `@testable import Lillist_macOS`, that's enough. If it co-compiles (per Plan 7/11 macOS test pattern), add `GlobalHotkeyMonitor.swift` to the co-compile sources in `Apps/project.yml`.

- [ ] **Step 2: Run the new test**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/HotkeyRecorderTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15
```

Expect: 4 tests pass (3 existing + the new one).

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Tests/HotkeyRecorderTests.swift \
        Apps/project.yml \
        Apps/Lillist-macOS.xcodeproj/project.pbxproj
git commit -m "test(macOS): hotkey encode/parse round-trip across HotkeyKeyTable"
```

(Include `project.yml` and `.pbxproj` only if regeneration was needed for Step 1's visibility note.)

---

## Task 5: Final sweep + engineering note

**Files:**
- Modify: `docs/engineering-notes.md`

- [ ] **Step 1: Full test sweeps**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
swift test --package-path Packages/LillistUI 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

All green.

- [ ] **Step 2: Append engineering note**

Add at the top of `docs/engineering-notes.md` (above the Plan 11 entry):

```markdown
## 2026-05-15 — Plan 12 Plan 11 follow-ups: parallel `record(from:)` mappers, shared key-code table

**Context.** Plan 11 added `TaskRecord.seriesID` and populated it in the canonical `TaskStore.record(from:)` mapper. Two parallel mappers — `SmartFilterStore.record(from:)` and `CLIBridge.LsHandler.record(from:)` — were not updated at the time, leaving smart-filter results and `lillist ls` output without series info. Plan 12 backfilled both with regression tests. Separately, Plan 11's macOS hotkey stack had two duplicated keyCode↔keyName tables (in `HotkeyRecorder` and `GlobalHotkeyMonitor`); Plan 12 consolidated them into `HotkeyKeyTable` with a round-trip test.

**Rule.**

- **When you add a field to a public DTO, grep the entire codebase for parallel mappers that construct that DTO.** `TaskStore.record(from:)` was not the only place that produced `TaskRecord`; `SmartFilterStore` and `LsHandler` each had their own static mapper. Adding the field with a default value in the `init` keeps callers compiling, but the parallel mappers silently omit it. `grep -rn 'TaskRecord(' --include='*.swift'` surfaces every site.
- **Don't duplicate inversion tables.** When two pieces of code map A→B and B→A, the inversion is one source of truth: a `[(A, B)]` master list plus two `Dictionary(uniqueKeysWithValues:)` lookups. Adding a row in one place propagates to both directions. Duplicated tables drift silently and produce confusing round-trip failures.

**Evidence.** Plan 12 commits on `plan-12-followups` (or merged into `main` as such): SmartFilterStore + test, LsHandler + test, `HotkeyKeyTable.swift`, both Hotkey delegates, round-trip test.
```

- [ ] **Step 3: Commit and tag**

```bash
git add docs/engineering-notes.md
git commit -m "docs: record Plan 12 follow-up lessons (parallel mappers; inversion-table consolidation)"
git tag plan-12-followups
```

- [ ] **Step 4: Branch summary**

```bash
git log --oneline plan-11-pre-uat-cleanup..plan-12-followups
```

---

## Plan 12 Scope

**In:** `seriesID` propagation in two parallel mappers + tests; `HotkeyKeyTable` consolidation + round-trip test; engineering note; tag.

**Out:** anything else.
