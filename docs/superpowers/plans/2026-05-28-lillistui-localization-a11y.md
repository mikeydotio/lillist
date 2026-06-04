# LillistUI Localization-Readiness & Accessibility Correctness Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 7.**
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> **Pre-flight (run before any edit):** Confirm Waves 1–6 are on `main` (`git log --oneline main | head -20`). Read `docs/superpowers/handoffs/wave-6.md`. Re-Read every file you touch and anchor by code **structure**, not line number — each wave shifts the shared hotspot files. On completion, write `docs/superpowers/handoffs/wave-7.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `LillistUI` structurally ready for localization (declared default language, `.module`-pinned strings, a populated catalog, and a CI extraction-drift lint) and fix two accessibility-correctness defects (phantom no-op reorder actions hidden behind a false doc comment, and a tautological reorder-action test).

**Architecture:** Convert every bare `Text("…")` accessibility action in LillistUI to the project's established `Text(String(localized:bundle: .module))` form so strings resolve against LillistUI's own bundle once the catalog is populated. Replace `RecurrenceEditorViewModel.humanSummary: String` (which hand-builds English plurals in the data layer) with a structured `RecurrenceSummary` value the VM returns, and a single View-layer `RecurrenceSummaryFormatter` that renders it via `.module`-pinned localized strings with real `.stringsdict`-style plural rules in the catalog — keeping localization out of the value type (SoC) and DRY across the iOS + macOS detail views. Gate each reorder `accessibilityAction` on its non-nil closure via a small pure dispatch helper (`ReorderActionDispatch`) so surfaces passing `nil` expose no phantom action; unit-test that helper directly to retire the tautological construct-and-assert-empty test. Finally, add a `defaultLocalization: en` to `Package.swift` and a CI lint that builds with `-emit-localized-strings`, collects extracted keys from the `.stringsdata`, and fails when any extracted key is absent from the catalog.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`import Testing`, `@Test`/`#expect`), SwiftPM resource catalogs (`Localizable.xcstrings`), `xcrun xcstringstool` + `swiftc -emit-localized-strings`, GitHub Actions, `jq`.

**Source findings:** `ui-loc-1`, `ui-loc-2`, `ui-a11y-1`, `ui-test-1` (Roadmap item #19).

**Out of scope:** Residual #6 — populating the iOS-app and macOS-app target string catalogs (`Apps/Lillist-iOS/.../Localizable.xcstrings`, `Apps/Lillist-macOS/.../Localizable.xcstrings`). This plan covers the **LillistUI** catalog only (`Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings`) plus its `defaultLocalization` and extraction-drift lint. The app-target catalogs are a separate effort.

---

## File Structure

### Create
- `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummary.swift` — the structured, `Sendable`, non-localized recurrence-summary value (`enum RecurrenceSummary`) returned by the view model. One responsibility: describe *what* the recurrence is, not how it reads in English.
- `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift` — the single View-layer formatter that turns a `RecurrenceSummary` into a `.module`-localized, correctly-pluralized `String`. One responsibility: presentation/localization of the summary.
- `Packages/LillistUI/Sources/LillistUI/Components/ReorderActionDispatch.swift` — pure, testable enum + dispatcher mapping a reorder action name to its optional closure, used by `TaskRowView`'s modifier so only non-nil actions are attached. One responsibility: action-name→closure routing.
- `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceSummaryFormatterTests.swift` — Swift Testing suite covering every frequency, interval-1 vs interval-N pluralization, and after-completion singular/plural.
- `Packages/LillistUI/Tests/LillistUITests/Components/ReorderActionDispatchTests.swift` — Swift Testing suite proving each closure fires, that `nil` closures are inert, and that the set of *available* actions equals only the non-nil ones (the real replacement for the tautological test).
- `Tools/CI/check-lillistui-localization.sh` — CI lint script: builds LillistUI with `-emit-localized-strings`, collects extracted keys, and fails on any key missing from the catalog.
- `.github/workflows/lillistui-localization.yml` — GitHub Actions workflow invoking the lint on macOS. Create it standalone here; `ci-and-build-posture` (the last Wave-7 plan) must later fold this `localization-lint` job into its consolidated `ci.yml` and **delete** this standalone file. *(See cross-plan coordination in Task 5.)*

### Modify
- `Packages/LillistUI/Package.swift` (lines 4–9) — add `defaultLocalization: "en"`. *(Shared file with `ci-and-build-posture`; see cross-plan coordination.)*
- `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift` (lines 96–113) — rewrite `ReorderActionsModifier` to attach only non-nil actions via `ReorderActionDispatch`, and `.module`-pin the action names; fix the doc comment to describe the *actual* behavior.
- `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift` (line 66) — `.module`-pin the `Cycle status` action name.
- `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift` (line 32) — `.module`-pin the `Capture from clipboard` action name.
- `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift` (lines 99–121) — replace `humanSummary: String` with `summary: RecurrenceSummary` (structured, non-localized).
- `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift` (lines 115–117) — call `RecurrenceSummaryFormatter` on the VM's `.summary`.
- `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift` (lines 115–117) — call `RecurrenceSummaryFormatter` on the VM's `.summary`.
- `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorViewModelTests.swift` (lines 73–114) — replace the `humanSummary` string-equality tests with `summary`-equality tests against the structured value.
- `Packages/LillistUI/Tests/LillistUITests/Components/TaskRowViewA11yTests.swift` (lines 47–71) — delete the tautological `reorderActionsFireClosures` test (its replacement lives in `ReorderActionDispatchTests`).
- `Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings` — populate with the extracted keys (including the plural-variation entries for the recurrence summary).

---

## Task 1: Gate reorder accessibility actions on their non-nil closure (ui-a11y-1)

**Files:**
- Create `Packages/LillistUI/Sources/LillistUI/Components/ReorderActionDispatch.swift`
- Create `Packages/LillistUI/Tests/LillistUITests/Components/ReorderActionDispatchTests.swift`
- Modify `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift` (lines 96–113)
- Modify `Packages/LillistUI/Tests/LillistUITests/Components/TaskRowViewA11yTests.swift` (lines 47–71)

Today `ReorderActionsModifier.body` attaches **all four** `accessibilityAction(named:)` calls unconditionally (`onMoveUp?()`, etc.), so a surface passing `nil` still advertises a phantom action that does nothing when invoked — and the doc comment on lines 96–99 falsely claims actions "are only attached when its closure is non-nil." We extract the name→closure routing into a pure helper, attach only the available actions, and fix the comment.

- [ ] **Step 1: Write the failing test** — create `Packages/LillistUI/Tests/LillistUITests/Components/ReorderActionDispatchTests.swift` with the complete code below. It references `ReorderActionDispatch`, which does not exist yet, so it must fail to compile.

```swift
import Testing
@testable import LillistUI

@Suite("ReorderActionDispatch")
struct ReorderActionDispatchTests {
    @Test("Only actions with a non-nil closure are available")
    func availableActionsExcludeNilClosures() {
        let dispatch = ReorderActionDispatch(
            onMoveUp: {},
            onMoveDown: nil,
            onIndent: {},
            onOutdent: nil
        )
        #expect(dispatch.availableActions == [.moveUp, .indent])
    }

    @Test("Empty when all closures are nil")
    func availableActionsEmptyWhenAllNil() {
        let dispatch = ReorderActionDispatch(
            onMoveUp: nil,
            onMoveDown: nil,
            onIndent: nil,
            onOutdent: nil
        )
        #expect(dispatch.availableActions.isEmpty)
    }

    @Test("Invoking an available action fires exactly its closure")
    func invokeFiresExactClosure() {
        var calls: [ReorderAction] = []
        let dispatch = ReorderActionDispatch(
            onMoveUp: { calls.append(.moveUp) },
            onMoveDown: { calls.append(.moveDown) },
            onIndent: { calls.append(.indent) },
            onOutdent: { calls.append(.outdent) }
        )
        dispatch.invoke(.moveUp)
        dispatch.invoke(.outdent)
        #expect(calls == [.moveUp, .outdent])
    }

    @Test("Invoking an unavailable (nil-closure) action is a no-op")
    func invokeNilClosureIsNoOp() {
        var fired = false
        let dispatch = ReorderActionDispatch(
            onMoveUp: { fired = true },
            onMoveDown: nil,
            onIndent: nil,
            onOutdent: nil
        )
        dispatch.invoke(.moveDown) // no closure registered
        dispatch.invoke(.indent)   // no closure registered
        #expect(fired == false)
    }

    @Test("Every action carries a stable accessibility key")
    func actionKeysAreStable() {
        #expect(ReorderAction.moveUp.accessibilityKey == "Move up")
        #expect(ReorderAction.moveDown.accessibilityKey == "Move down")
        #expect(ReorderAction.indent.accessibilityKey == "Indent")
        #expect(ReorderAction.outdent.accessibilityKey == "Outdent")
    }
}
```

- [ ] **Step 2: Run the test, expect failure** — `swift test --package-path Packages/LillistUI --filter ReorderActionDispatch`. Expected: a build error such as `cannot find 'ReorderActionDispatch' in scope` / `cannot find 'ReorderAction' in scope` (compilation fails because the type does not exist yet).

- [ ] **Step 3: Implement the minimal change** — create `Packages/LillistUI/Sources/LillistUI/Components/ReorderActionDispatch.swift` with the complete code below.

```swift
/// The four reorder operations a task row can expose to VoiceOver.
///
/// Order matches `allCases` so callers iterate actions in their visual
/// (up → down → indent → outdent) order.
enum ReorderAction: CaseIterable, Equatable {
    case moveUp
    case moveDown
    case indent
    case outdent

    /// Stable source key used as the `accessibilityAction(named:)` string
    /// and as the catalog key. Localized at the call site via `.module`.
    var accessibilityKey: String {
        switch self {
        case .moveUp:   return "Move up"
        case .moveDown: return "Move down"
        case .indent:   return "Indent"
        case .outdent:  return "Outdent"
        }
    }
}

/// Pure router mapping each `ReorderAction` to its optional closure.
///
/// `availableActions` is exactly the set of actions whose closure is
/// non-nil, so a surface that doesn't wire (e.g.) indent/outdent never
/// advertises a phantom no-op action to assistive technology.
struct ReorderActionDispatch {
    private let onMoveUp: (() -> Void)?
    private let onMoveDown: (() -> Void)?
    private let onIndent: (() -> Void)?
    private let onOutdent: (() -> Void)?

    init(
        onMoveUp: (() -> Void)?,
        onMoveDown: (() -> Void)?,
        onIndent: (() -> Void)?,
        onOutdent: (() -> Void)?
    ) {
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onIndent = onIndent
        self.onOutdent = onOutdent
    }

    /// The actions that have a wired closure, in visual order.
    var availableActions: [ReorderAction] {
        ReorderAction.allCases.filter { closure(for: $0) != nil }
    }

    /// Invokes the closure for `action` if one is registered; otherwise
    /// does nothing.
    func invoke(_ action: ReorderAction) {
        closure(for: action)?()
    }

    private func closure(for action: ReorderAction) -> (() -> Void)? {
        switch action {
        case .moveUp:   return onMoveUp
        case .moveDown: return onMoveDown
        case .indent:   return onIndent
        case .outdent:  return onOutdent
        }
    }
}
```

- [ ] **Step 4: Run the test, expect pass** — `swift test --package-path Packages/LillistUI --filter ReorderActionDispatch`. Expected: `Suite "ReorderActionDispatch" passed` with 5 tests passing, run summary `Test run with 5 tests ... passed`.

- [ ] **Step 5: Rewire `ReorderActionsModifier` and fix the false doc comment** — in `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift`, replace the entire block on lines 96–113 (the doc comment + `ReorderActionsModifier`) with the code below. Note: the `Text(String(localized:bundle: .module))` form satisfies ui-loc-2 for these four strings; `dispatch.availableActions` drives a `reduce(AnyView(content))` fold over the value type, attaching one `.accessibilityAction` per wired action and wrapping each step in `AnyView` to satisfy the opaque-return requirement.

```swift
/// Adds a VoiceOver reorder action for each *wired* closure. An action is
/// attached only when its closure is non-nil, so surfaces that don't
/// support a given operation (e.g. iOS lists without indent/outdent
/// plumbing) advertise no phantom no-op action.
private struct ReorderActionsModifier: ViewModifier {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onIndent: (() -> Void)?
    var onOutdent: (() -> Void)?

    func body(content: Content) -> some View {
        let dispatch = ReorderActionDispatch(
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onIndent: onIndent,
            onOutdent: onOutdent
        )
        return dispatch.availableActions.reduce(AnyView(content)) { view, action in
            AnyView(
                view.accessibilityAction(
                    named: Text(String(localized: .init(action.accessibilityKey), bundle: .module))
                ) {
                    dispatch.invoke(action)
                }
            )
        }
    }
}
```

- [ ] **Step 6: Replace the tautological reorder test** — in `Packages/LillistUI/Tests/LillistUITests/Components/TaskRowViewA11yTests.swift`, delete the entire `reorderActionsFireClosures` test (lines 47–71, from `@Test("Reorder a11y actions fire their closures")` through its closing `}`). The real coverage now lives in `ReorderActionDispatchTests`. After deletion the suite retains only `combinedLabelComposition`. The exact text to remove:

```swift

    @Test("Reorder a11y actions fire their closures")
    func reorderActionsFireClosures() {
        var calls: [String] = []
        let record = TaskStore.TaskRecord(
            id: UUID(), title: "x", notes: "", status: .todo,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: 0, isPinned: false, parentID: nil,
            createdAt: Date(), modifiedAt: Date(), closedAt: nil, deletedAt: nil,
            seriesID: nil
        )
        let view = TaskRowView(
            task: record,
            tagNames: [],
            onStatusClick: {},
            onStatusSet: { _ in },
            onMoveUp: { calls.append("up") },
            onMoveDown: { calls.append("down") },
            onIndent: { calls.append("indent") },
            onOutdent: { calls.append("outdent") }
        )
        // Compile-time wiring guard: the closures are stored and the init
        // signature includes the four optional reorder callbacks.
        _ = view
        #expect(calls.isEmpty, "Closures should not fire on construction")
    }
```

- [ ] **Step 7: Run the full LillistUI suite, expect pass** — `swift test --package-path Packages/LillistUI`. Expected: all suites pass; the run summary shows **32 tests** (28 baseline − 1 deleted tautological test + 5 new `ReorderActionDispatch` tests = 32) and the line `Test run with 32 tests ... passed`. Treat any warning as an error: the build must be warning-clean.

- [ ] **Step 8: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistUI/Sources/LillistUI/Components/ReorderActionDispatch.swift \
        Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift \
        Packages/LillistUI/Tests/LillistUITests/Components/ReorderActionDispatchTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Components/TaskRowViewA11yTests.swift
git commit -m "fix(a11y): gate reorder accessibility actions on non-nil closures

ReorderActionsModifier attached all four accessibilityAction(named:)
calls unconditionally, advertising phantom no-op Move/Indent/Outdent
actions on surfaces that pass nil — contradicting its own doc comment.
Route name->closure through a pure ReorderActionDispatch so only wired
actions are exposed, .module-pin the action names, and replace the
tautological construct-and-assert-empty test with direct dispatch
coverage (each closure fires; nil is a no-op).

Closes ui-a11y-1, ui-test-1."
```

---

## Task 2: Replace `humanSummary` with structured data + a localized View-layer formatter (ui-loc-1)

**Files:**
- Create `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummary.swift`
- Create `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift`
- Create `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceSummaryFormatterTests.swift`
- Modify `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift` (lines 99–121)
- Modify `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorViewModelTests.swift` (lines 73–114)
- Modify `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift` (lines 115–117)
- Modify `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift` (lines 115–117)

Today `RecurrenceEditorViewModel.humanSummary` (lines 99–121) builds English text with hand-rolled pluralization (`"Every \(interval) \(unit)s"`, `"day\(days == 1 ? "" : "s")"`) in the value type — not localizable and wrong for languages with non-`s` plurals. We move the *structure* into a `RecurrenceSummary` value (data) and the *rendering* into `RecurrenceSummaryFormatter` (presentation), which uses `.module`-pinned keys whose plural variants live in the catalog (Task 4).

- [ ] **Step 1: Write the failing tests** — create `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceSummaryFormatterTests.swift` with the complete code below. It references `RecurrenceSummary` and `RecurrenceSummaryFormatter`, which don't exist yet, so it must fail to compile. We force the `en` locale so the English source strings render deterministically regardless of test-runner region.

```swift
import Testing
import Foundation
import LillistCore
@testable import LillistUI

@Suite("RecurrenceSummaryFormatter")
struct RecurrenceSummaryFormatterTests {
    private let en = Locale(identifier: "en")

    @Test("Never repeats")
    func never() {
        let text = RecurrenceSummaryFormatter.string(for: .never, locale: en)
        #expect(text == "Doesn't repeat")
    }

    @Test("Calendar, interval 1, every frequency reads singular")
    func everyUnitSingular() {
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.daily, interval: 1), locale: en) == "Every day")
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.weekly, interval: 1), locale: en) == "Every week")
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.monthly, interval: 1), locale: en) == "Every month")
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.yearly, interval: 1), locale: en) == "Every year")
    }

    @Test("Calendar, interval N reads plural")
    func everyNUnits() {
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.daily, interval: 2), locale: en) == "Every 2 days")
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.monthly, interval: 3), locale: en) == "Every 3 months")
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.weekly, interval: 4), locale: en) == "Every 4 weeks")
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.yearly, interval: 5), locale: en) == "Every 5 years")
    }

    @Test("After completion, 1 day reads singular")
    func afterCompletionSingular() {
        #expect(RecurrenceSummaryFormatter.string(
            for: .afterCompletion(days: 1), locale: en) == "Repeats 1 day after completion")
    }

    @Test("After completion, N days reads plural")
    func afterCompletionPlural() {
        #expect(RecurrenceSummaryFormatter.string(
            for: .afterCompletion(days: 7), locale: en) == "Repeats 7 days after completion")
    }
}
```

- [ ] **Step 2: Run the tests, expect failure** — `swift test --package-path Packages/LillistUI --filter RecurrenceSummaryFormatter`. Expected: build error `cannot find 'RecurrenceSummaryFormatter' in scope` and `cannot find 'RecurrenceSummary' / type 'RecurrenceSummary' has no member` (compilation fails).

- [ ] **Step 3a: Create the structured value** — create `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummary.swift` with the complete code below. It is `Sendable` and carries no localization.

```swift
import LillistCore

/// Structured, non-localized description of a recurrence configuration.
///
/// Produced by `RecurrenceEditorViewModel.summary` (the data layer) and
/// rendered to a localized, correctly-pluralized string by
/// `RecurrenceSummaryFormatter` (the View layer). Keeping the shape here
/// and the wording there preserves separation of concerns: the value
/// type never embeds English or pluralization rules.
public enum RecurrenceSummary: Equatable, Sendable {
    /// The task does not repeat.
    case never
    /// A calendar rule firing every `interval` units of `frequency`.
    case calendar(_ frequency: RecurrenceRule.Frequency, interval: Int)
    /// An after-completion rule firing `days` after each completion.
    case afterCompletion(days: Int)
}
```

- [ ] **Step 3b: Create the formatter** — create `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift` with the complete code below. The interval-N strings carry a positional `%lld` so the catalog can define `plural` variations keyed on it; the unit word is itself a localized noun, and `String.localizedStringWithFormat` resolves the `%lld`-driven plural from the catalog.

```swift
import Foundation
import LillistCore

/// Renders a `RecurrenceSummary` into a localized, correctly-pluralized
/// string using LillistUI's own string catalog (`bundle: .module`).
///
/// All wording and plural rules live in `Resources/Localizable.xcstrings`;
/// this type only selects the right key and feeds the numeric argument so
/// the catalog's plural variations resolve.
public enum RecurrenceSummaryFormatter {
    /// Renders `summary` for `locale` (defaults to `.current`).
    public static func string(
        for summary: RecurrenceSummary,
        locale: Locale = .current
    ) -> String {
        switch summary {
        case .never:
            return String(localized: "Doesn't repeat", bundle: .module, locale: locale)

        case let .calendar(frequency, interval):
            // Two catalog keys per outcome path keep the plural rule on the
            // count, not on a hand-appended "s". interval == 1 is its own
            // key so "Every day" never reads "Every 1 day".
            switch frequency {
            case .daily:
                return interval == 1
                    ? String(localized: "Every day", bundle: .module, locale: locale)
                    : countString("Every %lld days", interval, locale)
            case .weekly:
                return interval == 1
                    ? String(localized: "Every week", bundle: .module, locale: locale)
                    : countString("Every %lld weeks", interval, locale)
            case .monthly:
                return interval == 1
                    ? String(localized: "Every month", bundle: .module, locale: locale)
                    : countString("Every %lld months", interval, locale)
            case .yearly:
                return interval == 1
                    ? String(localized: "Every year", bundle: .module, locale: locale)
                    : countString("Every %lld years", interval, locale)
            }

        case let .afterCompletion(days):
            return countString("Repeats %lld days after completion", days, locale)
        }
    }

    /// Looks up a `%lld`-bearing catalog key and substitutes `count`,
    /// letting the catalog's plural variations choose the right wording.
    private static func countString(
        _ key: String.LocalizationValue,
        _ count: Int,
        _ locale: Locale
    ) -> String {
        let format = String(localized: key, bundle: .module, locale: locale)
        return String(format: format, locale: locale, count)
    }
}
```

- [ ] **Step 4: Run the tests, expect pass** — `swift test --package-path Packages/LillistUI --filter RecurrenceSummaryFormatter`. The English source format string in `countString` substitutes the `%lld` positionally even before the catalog is populated, so all 5 tests pass at this step: `never` and `interval == 1` keys resolve to their literal source form; the `%lld` keys (`"Every %lld days"` → `"Every 2 days"`, `"Repeats %lld days after completion"` → `"Repeats 7 days after completion"`) resolve correctly via `String(format:locale:)`. Confirm the run summary reads `Test run with 5 tests ... passed`. (The catalog plural *variations* authored in Task 4 Step 5 make non-English locales correct; English correctness already holds via the source format string. If any case fails, the source format string in `countString`'s key is wrong — fix it, do not paper over.)

- [ ] **Step 5: Swap the view model from `humanSummary` to `summary`** — in `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift`, replace the entire `humanSummary` computed property (lines 99–121, from the `/// Human-readable summary…` doc comment through its closing `}`) with the structured `summary` property below.

```swift
    /// Structured summary of the current recurrence configuration.
    /// Returns non-localized data; render it with
    /// `RecurrenceSummaryFormatter.string(for:)` at the View layer so the
    /// value type stays free of wording and pluralization rules.
    public var summary: RecurrenceSummary {
        guard repeats else { return .never }
        switch mode {
        case .calendar:
            return .calendar(freq, interval: max(1, interval))
        case .afterCompletion:
            let days = Int(afterCompletionSeconds / 86_400)
            return .afterCompletion(days: days)
        }
    }
```

- [ ] **Step 6: Update the view model tests** — in `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorViewModelTests.swift`, replace the whole `// MARK: - humanSummary (Plan 14)` block (lines 73–114, from the `// MARK:` comment through the closing `}` of `humanSummary_afterCompletion_pluralDays`) with the structured-value tests below. These assert the VM's *data*, not its English text.

```swift
    // MARK: - summary (structured; rendering lives in RecurrenceSummaryFormatter)

    @Test("summary: empty state is .never")
    func summary_never() {
        let vm = RecurrenceEditorViewModel(rule: nil)
        #expect(vm.summary == .never)
    }

    @Test("summary: daily/interval 1 is .calendar(.daily, 1)")
    func summary_everyDay() {
        let rule: RecurrenceRule = .calendar(.init(freq: .daily, interval: 1))
        let vm = RecurrenceEditorViewModel(rule: rule)
        #expect(vm.summary == .calendar(.daily, interval: 1))
    }

    @Test("summary: weekly/interval 1 is .calendar(.weekly, 1)")
    func summary_everyWeek() {
        let rule: RecurrenceRule = .calendar(.init(freq: .weekly, interval: 1))
        let vm = RecurrenceEditorViewModel(rule: rule)
        #expect(vm.summary == .calendar(.weekly, interval: 1))
    }

    @Test("summary: monthly/interval 3 is .calendar(.monthly, 3)")
    func summary_everyNMonths() {
        let rule: RecurrenceRule = .calendar(.init(freq: .monthly, interval: 3))
        let vm = RecurrenceEditorViewModel(rule: rule)
        #expect(vm.summary == .calendar(.monthly, interval: 3))
    }

    @Test("summary: interval is clamped to >= 1 (defends against corrupt input)")
    func summary_clampsInterval() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .daily
        vm.interval = 0
        #expect(vm.summary == .calendar(.daily, interval: 1))
    }

    @Test("summary: afterCompletion at 1 day is .afterCompletion(days: 1)")
    func summary_afterCompletion_singularDay() {
        let rule: RecurrenceRule = .afterCompletion(.init(interval: 86_400))
        let vm = RecurrenceEditorViewModel(rule: rule)
        #expect(vm.summary == .afterCompletion(days: 1))
    }

    @Test("summary: afterCompletion at 7 days is .afterCompletion(days: 7)")
    func summary_afterCompletion_pluralDays() {
        let rule: RecurrenceRule = .afterCompletion(.init(interval: 86_400 * 7))
        let vm = RecurrenceEditorViewModel(rule: rule)
        #expect(vm.summary == .afterCompletion(days: 7))
    }
```

- [ ] **Step 7: Update the iOS caller** — in `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift`, replace the `seriesRuleSummary` body (lines 115–117) so it renders via the formatter. The current text is:
```swift
    private var seriesRuleSummary: String {
        RecurrenceEditorViewModel(rule: seriesRule).humanSummary
    }
```
Replace it with:
```swift
    private var seriesRuleSummary: String {
        RecurrenceSummaryFormatter.string(for: RecurrenceEditorViewModel(rule: seriesRule).summary)
    }
```

- [ ] **Step 8: Update the macOS caller** — in `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift`, replace the `currentRecurrenceSummary` body (lines 115–117). The current text is:
```swift
    private var currentRecurrenceSummary: String {
        recurrenceViewModel.humanSummary
    }
```
Replace it with:
```swift
    private var currentRecurrenceSummary: String {
        RecurrenceSummaryFormatter.string(for: recurrenceViewModel.summary)
    }
```

- [ ] **Step 9: Run LillistUI tests, expect pass** — `swift test --package-path Packages/LillistUI`. Expected: all suites pass; the run summary shows **33 tests** (32 from Task 1 − 6 old `humanSummary` tests + 7 new `summary` tests = 33). Warning-clean.

- [ ] **Step 10: Verify both app targets still build (the `humanSummary` callers were rewired)** —
```bash
cd /Volumes/Code/mikeyward/Lillist
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```
Expected: both end with `** BUILD SUCCEEDED **` and no references to a missing `humanSummary` member.

- [ ] **Step 11: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummary.swift \
        Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift \
        Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift \
        Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceSummaryFormatterTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorViewModelTests.swift \
        Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift \
        Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift
git commit -m "refactor(recurrence): structured summary + localized View formatter

RecurrenceEditorViewModel.humanSummary hand-built English plurals
(\"Every \(n) \(unit)s\", \"day\(s)\") inside the value type — not
localizable. Return a structured RecurrenceSummary from the VM (data)
and render it via a new .module-localized RecurrenceSummaryFormatter
(presentation), keeping wording and plural rules out of the model.
Both app detail views now format through the formatter.

Closes ui-loc-1."
```

---

## Task 3: `.module`-pin the remaining bare-Text accessibility actions (ui-loc-2)

**Files:**
- Modify `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift` (line 66)
- Modify `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift` (line 32)

Task 1 already `.module`-pinned the four `TaskRowView` reorder actions. Two bare `Text("…")` accessibility actions remain in LillistUI (`Cycle status`, `Capture from clipboard`); a bare `Text` literal resolves against the *main app* bundle at runtime, not LillistUI's `.module`, so once the LillistUI catalog is populated these strings would silently fail to localize. This is a small, non-TDD mechanical fix (the accessibility tree isn't host-testably assertable from `swift test`; the extraction lint in Task 5 is the regression guard).

- [ ] **Step 1: Pin the `Cycle status` action** — in `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift`, replace line 66:
```swift
        .accessibilityAction(named: Text("Cycle status")) {
```
with:
```swift
        .accessibilityAction(named: Text(String(localized: "Cycle status", bundle: .module))) {
```

- [ ] **Step 2: Pin the `Capture from clipboard` action** — in `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift`, replace line 32:
```swift
        .accessibilityAction(named: Text("Capture from clipboard")) {
```
with:
```swift
        .accessibilityAction(named: Text(String(localized: "Capture from clipboard", bundle: .module))) {
```

- [ ] **Step 3: Verify no bare-Text accessibility strings remain in LillistUI** —
```bash
cd /Volumes/Code/mikeyward/Lillist
grep -rn 'accessibilityAction(named: Text("' Packages/LillistUI/Sources/ || echo "CLEAN: no bare-Text accessibility actions remain"
```
Expected: `CLEAN: no bare-Text accessibility actions remain`.

- [ ] **Step 4: Run LillistUI tests, expect pass** — `swift test --package-path Packages/LillistUI`. Expected: still **33 tests**, `Test run with 33 tests ... passed`, warning-clean.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift \
        Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift
git commit -m "fix(loc): pin remaining accessibility-action strings to .module

Bare Text(\"Cycle status\") / Text(\"Capture from clipboard\") resolved
against the main app bundle, not LillistUI's catalog. Wrap both in
String(localized:bundle: .module) so they localize from LillistUI's
own catalog once populated.

Part of ui-loc-2."
```

---

## Task 4: Declare `defaultLocalization` and populate the catalog (ui-loc-2)

**Files:**
- Modify `Packages/LillistUI/Package.swift` (lines 4–9)
- Modify `Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings`

The package has no `defaultLocalization`, so SwiftPM treats the resource catalog as un-localized and `String(localized:bundle: .module)` cannot resolve regional variants. We declare `en`, then populate the empty catalog from the compiler's extraction output and hand-author the plural variations for the recurrence-count keys.

> **Cross-plan coordination:** `Packages/LillistUI/Package.swift` is also edited by **`ci-and-build-posture`** (which bumps `swift-tools-version` to 6.2 and adds `.treatAllWarnings(as: .error)` to `swiftSettings`). Both edits are additive and non-overlapping: this plan adds the `defaultLocalization: "en"` argument to the `Package(` initializer; `ci-and-build-posture` touches the tools-version pragma and `swiftSettings`. This plan runs first, so leave `swift-tools-version` (`6.0`) and `swiftSettings` untouched here. `ci-and-build-posture` lands after and **must preserve the `defaultLocalization: "en"` argument** — its edits do not overlap it. Whoever edits second should re-read the file first.

- [ ] **Step 1: Add `defaultLocalization: "en"`** — in `Packages/LillistUI/Package.swift`, change the `Package(` initializer header. Replace:
```swift
let package = Package(
    name: "LillistUI",
    platforms: [
```
with:
```swift
let package = Package(
    name: "LillistUI",
    defaultLocalization: "en",
    platforms: [
```

- [ ] **Step 2: Verify the package still resolves and builds** —
```bash
cd /Volumes/Code/mikeyward/Lillist
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```
Expected: `Build complete!` with no manifest-parse error. (Adding `defaultLocalization` is the documented enabler for localized resources; it does not change behavior of existing source strings.)

- [ ] **Step 3: Extract the catalog keys from the compiler** — run the extraction into a scratch dir (the script in Task 5 automates this; here we do it once to author the file):
```bash
cd /Volumes/Code/mikeyward/Lillist
rm -rf /tmp/lillistui-loc && mkdir -p /tmp/lillistui-loc
swift build --package-path Packages/LillistUI \
  -Xswiftc -emit-localized-strings \
  -Xswiftc -emit-localized-strings-path -Xswiftc /tmp/lillistui-loc 2>&1 | tail -2
jq -r '.tables.Localizable[]?.key' /tmp/lillistui-loc/*.stringsdata 2>/dev/null | sort -u > /tmp/lillistui-keys.txt
wc -l /tmp/lillistui-keys.txt
grep -c 'Every\|Repeats\|Doesn' /tmp/lillistui-keys.txt
```
Expected: ~150+ unique keys; the recurrence keys (`Doesn't repeat`, `Every day`, `Every %lld days`, `Repeats %lld days after completion`, etc.) appear in the list. Confirm `Move up`, `Move down`, `Indent`, `Outdent`, `Cycle status`, `Capture from clipboard` are present (they prove Tasks 1 & 3 are extractable).

- [ ] **Step 4: Generate the populated catalog body** — `xcstringstool sync` is unreliable for SPM `.stringsdata` (it silently merges nothing in this toolchain), so build the catalog deterministically from the extracted key list with `jq`. Write the populated catalog:
```bash
cd /Volumes/Code/mikeyward/Lillist
jq -R -s '
  {
    sourceLanguage: "en",
    strings: (split("\n") | map(select(length > 0)) | sort | unique
              | map({ (.): {} }) | add // {}),
    version: "1.0"
  }
' /tmp/lillistui-keys.txt > Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings
jq '.strings | length' Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings
```
Expected: prints the same key count as Step 3. Every extracted key now exists in the catalog as an empty (source-language-derived) entry — which is what an *un-translated but extraction-complete* catalog should look like before any translator opens it.

- [ ] **Step 5: Author the English plural variations for the recurrence-count keys** — the four `Every %lld <units>` keys and the `Repeats %lld days after completion` key carry a `%lld` and need explicit `en` plural variations so the source language is itself plural-correct and translators see the variation slots. Edit `Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings`: for each of the five keys below, replace its empty `{}` value with the corresponding object. (The non-`%lld` recurrence keys — `Doesn't repeat`, `Every day`, `Every week`, `Every month`, `Every year` — stay as empty `{}` entries; their source form is correct.)

For `"Every %lld days"`:
```json
    "Every %lld days" : {
      "localizations" : {
        "en" : {
          "variations" : {
            "plural" : {
              "one" : { "stringUnit" : { "state" : "translated", "value" : "Every %lld day" } },
              "other" : { "stringUnit" : { "state" : "translated", "value" : "Every %lld days" } }
            }
          }
        }
      }
    }
```

For `"Every %lld weeks"`:
```json
    "Every %lld weeks" : {
      "localizations" : {
        "en" : {
          "variations" : {
            "plural" : {
              "one" : { "stringUnit" : { "state" : "translated", "value" : "Every %lld week" } },
              "other" : { "stringUnit" : { "state" : "translated", "value" : "Every %lld weeks" } }
            }
          }
        }
      }
    }
```

For `"Every %lld months"`:
```json
    "Every %lld months" : {
      "localizations" : {
        "en" : {
          "variations" : {
            "plural" : {
              "one" : { "stringUnit" : { "state" : "translated", "value" : "Every %lld month" } },
              "other" : { "stringUnit" : { "state" : "translated", "value" : "Every %lld months" } }
            }
          }
        }
      }
    }
```

For `"Every %lld years"`:
```json
    "Every %lld years" : {
      "localizations" : {
        "en" : {
          "variations" : {
            "plural" : {
              "one" : { "stringUnit" : { "state" : "translated", "value" : "Every %lld year" } },
              "other" : { "stringUnit" : { "state" : "translated", "value" : "Every %lld years" } }
            }
          }
        }
      }
    }
```

For `"Repeats %lld days after completion"`:
```json
    "Repeats %lld days after completion" : {
      "localizations" : {
        "en" : {
          "variations" : {
            "plural" : {
              "one" : { "stringUnit" : { "state" : "translated", "value" : "Repeats %lld day after completion" } },
              "other" : { "stringUnit" : { "state" : "translated", "value" : "Repeats %lld days after completion" } }
            }
          }
        }
      }
    }
```

- [ ] **Step 6: Validate the catalog is well-formed JSON and parses with xcstringstool** —
```bash
cd /Volumes/Code/mikeyward/Lillist
jq empty Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings && echo "VALID JSON"
xcrun xcstringstool print Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings >/dev/null && echo "xcstringstool OK"
```
Expected: `VALID JSON` and `xcstringstool OK` (non-zero exit if the file is malformed).

- [ ] **Step 7: Rebuild and run tests so plural resolution is exercised against the populated catalog** —
```bash
cd /Volumes/Code/mikeyward/Lillist
swift test --package-path Packages/LillistUI --filter RecurrenceSummaryFormatter 2>&1 | tail -5
```
Expected: `Test run with 5 tests ... passed` — now the formatter's `%lld` plural cases resolve through the catalog's `en` `one`/`other` variations (verifying singular like `Every 1 …` would read correctly were it ever requested, and `Every 2 days` reads plural).

- [ ] **Step 8: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistUI/Package.swift \
        Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings
git commit -m "feat(loc): declare defaultLocalization en and populate the catalog

Add defaultLocalization: en so LillistUI's .module catalog resolves,
then populate the previously-empty Localizable.xcstrings from the
compiler's extracted keys and author en plural variations for the
recurrence-count keys (Every %lld <unit>, Repeats %lld days after
completion).

Part of ui-loc-2."
```

---

## Task 5: Add the CI localization extraction-drift lint (ui-loc-2)

**Files:**
- Create `Tools/CI/check-lillistui-localization.sh`
- Create `.github/workflows/lillistui-localization.yml`

A populated catalog rots silently: the next contributor adds a `String(localized:…)` and forgets the catalog. The lint re-runs the compiler extraction and fails when any extracted key is missing from the committed catalog. We deliberately *don't* rely on `xcstringstool sync` (it merges nothing for SPM `.stringsdata` in this toolchain — verified during planning); instead we diff extracted keys against catalog keys with `jq`.

> **Cross-plan coordination:** `ci-and-build-posture` is the **last** Wave-7 plan, so it has not created `.github/workflows/` yet when this plan runs — create the standalone `lillistui-localization.yml` here as written. When `ci-and-build-posture` lands, it must fold this `localization-lint` job into its consolidated `ci.yml` and **delete** the standalone `lillistui-localization.yml`. The shell script in `Tools/CI/` is the durable, plan-owned artifact and stays put either way.

- [ ] **Step 1: Create the lint script** — create `Tools/CI/check-lillistui-localization.sh` with the complete content below, then make it executable.

```bash
#!/usr/bin/env bash
#
# check-lillistui-localization.sh
#
# Fails if any localizable string used in LillistUI source is missing
# from Resources/Localizable.xcstrings. Re-runs the compiler's string
# extraction (-emit-localized-strings) and diffs the extracted keys
# against the committed catalog.
#
# We diff keys directly with jq rather than `xcstringstool sync` because
# `sync` does not merge SwiftPM-emitted .stringsdata in the current
# toolchain (it exits 0 and changes nothing).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_PATH="${REPO_ROOT}/Packages/LillistUI"
CATALOG="${PACKAGE_PATH}/Sources/LillistUI/Resources/Localizable.xcstrings"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "${SCRATCH}"' EXIT

echo "==> Building LillistUI with string extraction"
swift build --package-path "${PACKAGE_PATH}" \
  -Xswiftc -emit-localized-strings \
  -Xswiftc -emit-localized-strings-path -Xswiftc "${SCRATCH}" >/dev/null

echo "==> Collecting extracted keys"
jq -r '.tables.Localizable[]?.key' "${SCRATCH}"/*.stringsdata 2>/dev/null \
  | sort -u > "${SCRATCH}/extracted.txt"

echo "==> Collecting catalog keys"
jq -r '.strings | keys[]' "${CATALOG}" | sort -u > "${SCRATCH}/catalog.txt"

# Keys present in source extraction but absent from the catalog.
MISSING="$(comm -23 "${SCRATCH}/extracted.txt" "${SCRATCH}/catalog.txt" || true)"

if [[ -n "${MISSING}" ]]; then
  echo "ERROR: localizable strings missing from ${CATALOG#${REPO_ROOT}/}:" >&2
  echo "${MISSING}" | sed 's/^/  - /' >&2
  echo >&2
  echo "Run Tools/CI/check-lillistui-localization.sh locally, then add the" >&2
  echo "missing keys to Localizable.xcstrings (empty {} entries are fine for" >&2
  echo "source-language-only strings)." >&2
  exit 1
fi

echo "==> OK: all $(wc -l < "${SCRATCH}/extracted.txt" | tr -d ' ') extracted keys are present in the catalog"
```

```bash
cd /Volumes/Code/mikeyward/Lillist
chmod +x Tools/CI/check-lillistui-localization.sh
```

- [ ] **Step 2: Run the lint locally, expect pass** —
```bash
cd /Volumes/Code/mikeyward/Lillist
./Tools/CI/check-lillistui-localization.sh
```
Expected: ends with `==> OK: all <N> extracted keys are present in the catalog` and exit code 0 (the catalog was populated in Task 4).

- [ ] **Step 3: Prove the lint actually fails on drift (negative check)** — temporarily add an unregistered string, confirm the lint catches it, then revert. The revert uses `git checkout -- StatusGlyph.swift`, which discards the *whole file* back to HEAD — so first **abort if that file already has uncommitted edits** (no Task in this plan touches it, so a clean tree is the expected state; if it's dirty, stop and resolve those edits before running the canary):
```bash
cd /Volumes/Code/mikeyward/Lillist
GLYPH=Packages/LillistUI/Sources/LillistUI/Theme/StatusGlyph.swift
# Guard: refuse to run if StatusGlyph.swift is already dirty — the revert
# below would otherwise clobber unrelated uncommitted work.
if ! git diff --quiet -- "$GLYPH" || ! git diff --cached --quiet -- "$GLYPH"; then
  echo "ABORT: $GLYPH has uncommitted changes; the canary revert would discard them. Resolve first." >&2
  exit 1
fi
# Inject a deliberately-unregistered string into a source file.
printf '\n// loc-lint canary\nlet _locLintCanary = String(localized: "ZZ lint canary string", bundle: .module)\n' \
  >> "$GLYPH"
set +e; ./Tools/CI/check-lillistui-localization.sh; RC=$?; set -e
git checkout -- "$GLYPH"
test "${RC}" -ne 0 && echo "GOOD: lint failed on drift as expected" || (echo "BAD: lint did not catch drift" && exit 1)
```
Expected: the lint prints `- ZZ lint canary string` under the missing-keys list, exits non-zero, and the final line is `GOOD: lint failed on drift as expected`. (The `git checkout` reverts the canary before the assertion; the guard above ensures it only discards the canary, never real work.)

- [ ] **Step 4: Create the GitHub Actions workflow** — create `.github/workflows/lillistui-localization.yml` with the complete content below. This plan runs before `ci-and-build-posture`, so `.github/workflows/` does not exist yet — create it. *(`ci-and-build-posture` later folds this job into `ci.yml` and deletes this standalone file; see cross-plan note above.)*

```yaml
name: LillistUI Localization Lint

on:
  push:
    paths:
      - "Packages/LillistUI/**"
      - "Tools/CI/check-lillistui-localization.sh"
      - ".github/workflows/lillistui-localization.yml"
  pull_request:
    paths:
      - "Packages/LillistUI/**"
      - "Tools/CI/check-lillistui-localization.sh"

jobs:
  localization-lint:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -switch /Applications/Xcode_26.3.app
      - name: Verify jq is available
        run: jq --version
      - name: Run LillistUI localization extraction-drift lint
        run: ./Tools/CI/check-lillistui-localization.sh
```

- [ ] **Step 5: Validate the workflow YAML is well-formed** —
```bash
cd /Volumes/Code/mikeyward/Lillist
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/lillistui-localization.yml')); print('VALID YAML')"
```
Expected: `VALID YAML`.

- [ ] **Step 6: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Tools/CI/check-lillistui-localization.sh \
        .github/workflows/lillistui-localization.yml
git commit -m "ci(loc): add LillistUI localization extraction-drift lint

New Tools/CI/check-lillistui-localization.sh re-runs the compiler's
-emit-localized-strings extraction and fails when any source string is
missing from Localizable.xcstrings, plus a GitHub Actions workflow that
runs it on macOS. Guards against the catalog silently rotting as new
String(localized:) call sites land.

Closes ui-loc-2."
```

---

## Task 6: Final full verification

**Files:** none (verification only).

- [ ] **Step 1: Full LillistUI host suite** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI 2>&1 | tail -8`. Expected: `Test run with 33 tests ... passed`, warning-clean.

- [ ] **Step 2: iOS snapshot/tour tests still pass** (TaskRowView/recurrence rendering changed):
```bash
cd /Volumes/Code/mikeyward/Lillist
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' 2>&1 | tail -6
```
Expected: `** TEST SUCCEEDED **`. If `IOSScreenTourTests` snapshots diff because the recurrence summary or row a11y changed *visible* text, re-record only if the diff is the intended wording — otherwise it's a bug.

- [ ] **Step 3: Lint passes against the final tree** — `cd /Volumes/Code/mikeyward/Lillist && ./Tools/CI/check-lillistui-localization.sh`. Expected: `==> OK: all <N> extracted keys are present in the catalog`.

- [ ] **Step 4: Confirm the working tree is clean** — `cd /Volumes/Code/mikeyward/Lillist && git status --short`. Expected: empty output (all five task commits landed; nothing uncommitted, no stray `/tmp` artifacts tracked).

---

## Self-review checklist

- **`ui-loc-1`** — `RecurrenceEditorViewModel.humanSummary` (hand-rolled English plurals in the value type) replaced by a structured `RecurrenceSummary` returned from the VM and a `.module`-localized, plural-rule-correct `RecurrenceSummaryFormatter` at the View layer; both app detail views rewired. Covered by **Task 2** (+ plural catalog entries authored in **Task 4** Step 5).
- **`ui-loc-2`** — `defaultLocalization: "en"` added (**Task 4** Step 1); all bare `Text("…")` accessibility actions converted to `Text(String(localized:bundle: .module))` (`TaskRowView` reorder actions in **Task 1**; `StatusIndicatorView` + `FloatingAddButton` in **Task 3**); catalog populated from compiler extraction (**Task 4**); CI extraction-drift lint added and proven to fail on drift (**Task 5**). Covered by **Tasks 1, 3, 4, 5**.
- **`ui-a11y-1`** — reorder `accessibilityAction`s now gated on their non-nil closure via the pure `ReorderActionDispatch`, so surfaces passing `nil` expose no phantom no-op action; the false doc comment is rewritten to describe actual behavior. Covered by **Task 1** (Steps 3–5).
- **`ui-test-1`** — the tautological `reorderActionsFireClosures` test (construct view, assert `calls.isEmpty`) deleted; replaced by `ReorderActionDispatchTests` asserting each closure fires, `nil` is a no-op, and `availableActions` excludes nil-closure actions. Covered by **Task 1** (Steps 1–2, 6).

**Strengths preserved (not refactored away):** the container/presenter split is untouched (the new formatter is a stateless `enum`, the VM stays a pure value type); the established `String(localized:bundle: .module)` pattern is reused verbatim (DRY); no `NSManagedObject` or Core Data type is introduced; `Calendar`-based date math is not modified; the recurrence VM's `max(1, interval)` clamp (a `rec-1`-adjacent guard owned by `recurrence-input-hardening`) is carried over into `summary` so this change doesn't regress it.
