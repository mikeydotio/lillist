# Lillist Plan 20 — Shared Polish & Accessibility Nits

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Branch:** `plan-20-shared-polish` (off `main`).

**Goal:** Close the cross-platform and accessibility LOW/NIT items surfaced by the 2026-05-16 design review that do **not** fit cleanly into any single platform-specific plan. Each task is a small, isolated polish — an asset, a label, an accessibility trait, a per-platform symmetry — applied opportunistically across `LillistUI` and both app targets. Two non-trivial items have user-input or scope considerations called out below (Task 1's brand color, Task 4's screen-extraction refactor).

**Architecture:** Most tasks are local SwiftUI surgery — an `.accessibilityAddTraits(.isHeader)` here, a `@ScaledMetric` wrap there, a hardcoded list centralized into a shared constants file. Task 1 adds an `AccentColor.colorset` to each app target so `LillistUI`'s shared `Color.accentColor` callsites stop falling back to system blue. Task 2 centralizes Quick Capture date tokens into `QuickCaptureDateSuggestions.swift` consumed by both platforms. Task 3 brings the iPad `CommandMenu` surface up to parity with the macOS Command menu for status-mutation and column-focus actions. Task 4 — the largest item, with an explicit split-out decision point — proposes migrating screen composition from inline tour mocks into `Packages/LillistUI/Sources/LillistUI/iOS/Screens/`. Task 5 turns the `LillistUI.swift` stub into a module landing page. Task 6 normalizes title/sentence case per HIG. Tasks 7-12 are individual a11y nits — label ordering, heading traits, Dynamic Type wrapping, future-proofing comments.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing for `LillistCore` tests, XCTest + `swift-snapshot-testing` for `LillistUI` snapshot tests, asset catalog (`.colorset`) for AccentColor. No new third-party dependencies. No managed-object model changes, no migrations.

**Depends on:**

- Plans 1-12 on `main`.
- **Plan 13** (a11y & correctness) — Task 3 inherits any `⌘D` rebinding Plan 13 makes (re-grep `LillistCommands.swift` at Task 3 start).
- **Plan 14** (design tokens) — on `main`. Task 5's module doc references `Theme/Tokens.swift` as the design-system entry point.
- **Plan 16** (iOS polish) — on `main`. Plan 16 Task 29 lifted iPad shortcuts into a Scene-level `CommandMenu` (`Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift`) and deleted `Apps/Lillist-iOS/Sources/Common/KeyboardShortcuts.swift` entirely. Task 3 here extends the `CommandMenu` scaffold. Scene-level state bindings (`isQuickCapturePresented`, `selectedSection`) are owned by `LillistApp` and exposed via env values declared in `Apps/Lillist-iOS/Sources/Common/SceneBindings.swift`.
- **Plan 17** (i18n & a11y environments) — on `main`. Task 5's module doc references `Accessibility/AccessibilityEnvironment.swift` (now real). Task 9 extends the `.isHeader` trait coverage to the recurrence editor (Plan 17 already covered the macOS detail-view sections). Task 2 here covers the macOS-vs-iOS chip-row divergence (Plan 17 documented the parser-token coupling; this task closes the symmetry gap). FollowUpFormView submission announcement is already in place — out of scope here.

---

## Already covered by earlier plans — do not replan

- **Quick Capture date-token localization** → Plan 17 Task 8 (the macOS-vs-iOS *divergence* is still in scope here — Task 2).
- **FollowUpFormView submission announcement** → Plan 17 Task 19.
- **macOS detail-view section `.isHeader` traits** (`SubtaskOutlineView`, `JournalStreamView`, `NotesEditorView`) → Plan 17 Task 27. (The *recurrence editor* section titles are still in scope here — Task 9.)

---

## File Structure

```
Lillist/
├── Apps/
│   ├── Lillist-iOS/
│   │   ├── Resources/
│   │   │   └── Assets.xcassets/
│   │   │       └── AccentColor.colorset/                       (NEW directory — Task 1)
│   │   │           └── Contents.json                            (NEW — placeholder brand tint)
│   │   ├── Sources/
│   │   │   ├── Commands/
│   │   │   │   └── LillistCommands.swift                        (modify — Task 3: extend with parity actions)
│   │   │   ├── QuickCapture/
│   │   │   │   └── QuickCaptureSheet.swift                      (modify — Task 2: consume shared token list)
│   │   │   └── Settings/
│   │   │       └── (audit only — Task 6)
│   │   └── (case-audit only — Task 6)
│   └── Lillist-macOS/
│       ├── Resources/
│       │   └── Assets.xcassets/
│       │       └── AccentColor.colorset/                       (NEW directory — Task 1)
│       │           └── Contents.json                            (NEW — placeholder brand tint)
│       └── Sources/
│           ├── Commands/
│           │   └── LillistCommands.swift                        (modify — Task 6: case audit)
│           └── Views/Detail/
│               └── DetailHeaderView.swift                       (modify — Task 11: a11y labels on DatePickers)
├── Packages/
│   └── LillistUI/
│       ├── Sources/
│       │   └── LillistUI/
│       │       ├── LillistUI.swift                              (modify — Task 5: module doc landing page)
│       │       ├── Components/
│       │       │   ├── BreadcrumbView.swift                     (modify — Task 8: a11y MARK + future contract)
│       │       │   ├── EmptyStateView.swift                     (modify — Task 10: @ScaledMetric)
│       │       │   ├── SidebarRowView.swift                     (modify — Task 7: a11y modifier ordering)
│       │       │   └── TagChipView.swift                        (modify — Task 12: future-proof a11y MARK)
│       │       ├── CrashReporting/
│       │       │   └── CrashReportSheet.swift                   (modify — Task 6: case audit)
│       │       ├── QuickCapture/
│       │       │   ├── QuickCaptureDateSuggestions.swift        (NEW — Task 2: canonical token list)
│       │       │   └── QuickCaptureView.swift                   (modify — Task 2: render shared chip row)
│       │       ├── Recurrence/
│       │       │   └── RecurrenceEditorView.swift               (modify — Task 9: .isHeader on sections)
│       │       └── iOS/
│       │           └── Screens/                                 (NEW directory — Task 4, gated)
│       │               ├── TodayScreen.swift                    (NEW — Task 4a, if not split)
│       │               ├── AllTagsScreen.swift                  (NEW — Task 4b, if not split)
│       │               ├── FiltersListScreen.swift              (NEW — Task 4c, if not split)
│       │               ├── SearchScreen.swift                   (NEW — Task 4d, if not split)
│       │               └── SettingsScreen.swift                 (NEW — Task 4e, if not split)
│       └── Tests/
│           └── LillistUITests/
│               ├── Components/
│               │   ├── SidebarRowViewA11yTests.swift            (NEW — Task 7)
│               │   └── EmptyStateViewDynamicTypeTests.swift     (NEW — Task 10)
│               ├── QuickCapture/
│               │   └── QuickCaptureDateSuggestionsTests.swift   (NEW — Task 2)
│               ├── Recurrence/
│               │   └── RecurrenceEditorHeadingTests.swift       (NEW — Task 9)
│               └── Tour/
│                   ├── IOSScreenTourTests.swift                 (modify — Task 4: swap mocks for real screens)
│                   └── __Snapshots__/                            (modify — Task 4: re-record after migration)
└── docs/
    └── engineering-notes.md                                     (append entry for Plan 20)
```

---

## Notes for the Implementer

**Task 1 (`AccentColor`) needs a brand-tint decision.** Shared `LillistUI` components reference `Color.accentColor` and silently fall back to system blue. This plan uses placeholder warm purple `#7B5BB6` with `TODO(user: pick brand color)`. Swap for any user-supplied hex in Step 1.

**Task 2 (Quick Capture chips) chooses chips on both platforms.** macOS shows none today; iOS hardcodes four. Centralize in `LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift`. `QuickCaptureParser` accepts any `^token` form; `RelativeDate.parse` already resolves the default token set.

**Task 3 (iPad shortcuts) coordinates with Plan 13.** Plan 13 may rebind macOS `⌘D` (Show Bookmarks system conflict) — grep `LillistCommands.swift` for the current "Mark Closed" key before adding the iPad binding. Plan 16 Task 29 already lifted iPad shortcuts into a Scene-level `CommandMenu` (`Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift`); Task 3 extends that file directly.

**Task 4 (IOSScreenTourTests refactor) is significantly larger than every other task.** The iOS tour tests rebuild screens with inline mock chrome because the iOS app bundle isn't `@testable import`-able. The fix migrates screen composition from `Apps/Lillist-iOS/Sources/<Tab>/<Tab>View.swift` into `LillistUI/iOS/Screens/<Tab>Screen.swift` across five screens + a final tour-mock deletion. **Default: flag the user and spin out as `Plan 20a`** so Plan 20 stays a cohesive polish branch.

**Task 5 (module doc) is documentation-only.** Replace the `LillistUI.swift` stub with a doc-comment landing page; the referenced surfaces — `Theme/Tokens.swift` (design tokens) and `Accessibility/AccessibilityEnvironment.swift` (environment-aware modifiers) — both exist on `main`.

**Task 6 (case audit) is one-time normalization.** macOS title case for menus and standalone buttons; iOS title case for toolbar/navbar buttons, sentence case for inline Form-row actions. Known offenders: `CrashReportSheet.swift:82,90` ("Don't send" / "Send report" both sentence) — harmonize to title case for both.

**Tasks 7-12 are individual a11y nits.** Each is a 1-3 line modifier addition (or comment block for Tasks 8, 12). Tasks 7, 9, 10 carry small tests; the rest are documentary or visually verified.

**Build-plugin caching gotcha.** No model edits in this plan. If you touch the model during exploration, run the `touch` from `CLAUDE.md`.

**Verification & commits.** Tests via `swift test --package-path Packages/LillistUI --filter '<pattern>'` or `xcodebuild test … -only-testing:Lillist-{iOS,macOS}Tests/…`. Final task runs full LillistCore + LillistUI suites + both app target builds. One commit per task, conventional-commit prefixes (`feat(iOS):`, `fix(macOS):`, `refactor(UI):` etc.).

---

## Task 1: Define `AccentColor` asset in both app targets

**Files:**
- Create: `Apps/Lillist-iOS/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `Apps/Lillist-macOS/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Modify: `Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__/` (re-record affected screens — see Step 5)

Shared `LillistUI` components reference `Color.accentColor` at multiple sites — verify with `grep -rn 'Color\.accentColor\|accentColor' Packages/LillistUI/Sources/`. Known sites:
- `Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift:24` (`tint?.resolved(in: scheme).color ?? .accentColor`)
- `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift:22` (`Circle().fill(Color.accentColor)`)
- `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureField.swift:44` (`Capsule().fill(Color.accentColor.opacity(0.15))`)

Without an asset-catalog `AccentColor`, both app targets fall back to system blue. Tour snapshots have been recorded with that fallback — they re-record once we pick a tint.

- [ ] **Step 1: Pick the placeholder tint**

Use warm purple `#7B5BB6` as the placeholder. Document the user-input dependency in the file itself so a future search surfaces it:

```bash
echo "Brand tint: #7B5BB6 (placeholder — TODO(user: pick brand color))"
```

If the user has supplied a hex before execution starts, substitute that value in every `Contents.json` written below. Otherwise proceed with `#7B5BB6`.

- [ ] **Step 2: Create both colorsets**

```bash
mkdir -p Apps/Lillist-iOS/Resources/Assets.xcassets/AccentColor.colorset \
         Apps/Lillist-macOS/Resources/Assets.xcassets/AccentColor.colorset
```

Write identical `Contents.json` to both paths. `#7B5BB6` is sRGB `(0.482, 0.357, 0.714)`; lift each channel by `~0.13` for the dark variant so contrast holds against dark backgrounds. Single asset catalog format works for both targets:

```json
{
  "colors" : [
    { "color" : { "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "red" : "0.482", "green" : "0.357", "blue" : "0.714" } },
      "idiom" : "universal" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : { "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "red" : "0.604", "green" : "0.490", "blue" : "0.792" } },
      "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "localizable" : true }
}
```

If the user supplied a brand hex, substitute both variants.

- [ ] **Step 3: Wire the asset name through xcodegen**

Both `Apps/project.yml` (macOS, `Lillist-macOS` target) and `Apps/Lillist-iOS/project.yml` (iOS, `Lillist-iOS` target) already set `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` under `settings.base`. Add `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` next to it in both files. Then regenerate:

```bash
cd Apps && xcodegen generate --spec project.yml --project . && cd ..
cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project . && cd ../..
```

- [ ] **Step 4: Build both app targets**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expect: `** BUILD SUCCEEDED **` on both.

- [ ] **Step 5: Re-record affected tour snapshots**

Tour tests render with `Color.accentColor`, so screens that paint accent (floating "+", tab-bar active state, sidebar icons) will diff. Run, inspect the diff PNGs, then re-record by wrapping the relevant tests in `withSnapshotTesting(record: .all) { … }` (or by threading a record-mode flag into the existing `assertScreen` helper near the bottom of `IOSScreenTourTests.swift`):

```bash
swift test --package-path Packages/LillistUI --filter 'IOSScreenTourTests|MacOSScreenTourTests' 2>&1 | tail -10
```

Expect clean PASS after re-record.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Resources/Assets.xcassets/AccentColor.colorset/Contents.json \
        Apps/Lillist-macOS/Resources/Assets.xcassets/AccentColor.colorset/Contents.json \
        Apps/project.yml \
        Apps/Lillist-iOS/project.yml \
        Apps/Lillist-macOS.xcodeproj/project.pbxproj \
        Apps/Lillist-iOS/Lillist-iOS.xcodeproj/project.pbxproj \
        Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__
git commit -m "feat(theme): define AccentColor in both app targets (placeholder brand tint)

Shared LillistUI components reference Color.accentColor at several
sites (SidebarRowView, FloatingAddButton, QuickCaptureField); without
an asset-catalog AccentColor entry, both apps silently fall back to
system blue. Adds a placeholder warm purple (#7B5BB6) and wires
ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME=AccentColor in both
xcodegen specs. TODO(user: pick brand color) — the placeholder is
clearly marked so it's trivial to swap once a brand decision is made.
Tour snapshots re-recorded against the new tint."
```

---

## Task 2: Unify Quick Capture date-token surface across platforms

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift`
- Modify: `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift` (add chip row)
- Modify: `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift:25` (consume shared list)
- Create: `Packages/LillistUI/Tests/LillistUITests/QuickCapture/QuickCaptureDateSuggestionsTests.swift`

Today: macOS `QuickCaptureView` (`Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift`) renders no chip row; iOS `QuickCaptureSheet.swift:25` hardcodes `["today", "tomorrow", "+3d", "+1w"]`. Unify on "chips on both platforms, single source of truth." `QuickCaptureParser` accepts any `^token` form and `QuickCaptureSheet.swift:95` resolves tokens through `LillistCore.RelativeDate.parse(_:)` — the same path picks up macOS chip taps once the row is in place.

- [ ] **Step 1: Write the failing test**

Create `Packages/LillistUI/Tests/LillistUITests/QuickCapture/QuickCaptureDateSuggestionsTests.swift`:

```swift
import Testing
import LillistCore
@testable import LillistUI

@Suite("Quick Capture date suggestions")
struct QuickCaptureDateSuggestionsTests {
    @Test("Default suggestions are the canonical four")
    func defaultSuggestions() {
        #expect(QuickCaptureDateSuggestions.default == ["today", "tomorrow", "+3d", "+1w"])
    }

    @Test("Every default suggestion resolves through RelativeDate.parse")
    func everyDefaultSuggestionResolves() throws {
        for token in QuickCaptureDateSuggestions.default {
            #expect(throws: Never.self) {
                _ = try RelativeDate.parse(token)
            }
        }
    }
}
```

Run:

```bash
swift test --package-path Packages/LillistUI --filter 'Quick Capture date suggestions' 2>&1 | tail -10
```

Expect: fails to compile (`QuickCaptureDateSuggestions` undefined).

- [ ] **Step 2: Create the shared constants file**

Create `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift`:

```swift
import Foundation

/// Canonical Quick Capture date-token chip list. Both the macOS
/// `QuickCaptureView` and the iOS `QuickCaptureSheet` render chips
/// from this list, so adding a token surfaces on both platforms
/// simultaneously.
///
/// Every token in `default` must round-trip through
/// `LillistCore.RelativeDate.parse(_:)`. Adding a token here without
/// extending the parser produces a chip the user can tap but the
/// parser can't resolve.
///
/// Localization note: Plan 17 Task 8 documents the parser-token
/// coupling. These tokens stay in English at the data layer; the
/// chip rendering can localize the *display* (e.g. show
/// "Today" in any locale) while the underlying parser token stays
/// `"today"`. That decoupling is a future plan — today the chip
/// label and the parser token are the same string.
public enum QuickCaptureDateSuggestions {
    public static let `default`: [String] = [
        "today",
        "tomorrow",
        "+3d",
        "+1w"
    ]
}
```

Run the test again:

```bash
swift test --package-path Packages/LillistUI --filter 'Quick Capture date suggestions' 2>&1 | tail -5
```

Expect: PASS (both cases).

- [ ] **Step 3: Surface chips on macOS `QuickCaptureView`**

Edit `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift`. The `body` shows parsed tags in an `HStack(spacing: 6)` at line 29. Add a new chip row immediately after that `HStack` closes (before the outer `VStack` ends, around line 42):

```swift
            // Date-token chips. Single source of truth shared with the
            // iOS QuickCaptureSheet; tapping appends `^token` to the
            // text field for the inline parser to pick up.
            HStack(spacing: 6) {
                ForEach(QuickCaptureDateSuggestions.default, id: \.self) { token in
                    Button {
                        text += text.isEmpty ? "^\(token)" : " ^\(token)"
                    } label: {
                        Text("^\(token)").font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "Insert deadline \(token)", bundle: .module))
                }
                Spacer()
            }
```

- [ ] **Step 4: Replace the hardcoded iOS list**

Edit `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift`. The current `dateSuggestions:` line carries an `// i18n-exempt:` comment block explaining the parser-token coupling. Replace the literal array with the shared constant; keep the comment block — its rationale still applies to the shared canonical list:

```swift
                    dateSuggestions: QuickCaptureDateSuggestions.default,
```

`QuickCaptureSheet.swift` already imports `LillistUI` (line 3), so the type is visible. Update the comment block above the line to point at `QuickCaptureDateSuggestions.swift` as the canonical home.

- [ ] **Step 5: Snapshot — re-record macOS QuickCapture and verify iOS unchanged**

```bash
swift test --package-path Packages/LillistUI \
  --filter 'QuickCapture' 2>&1 | tail -10
```

macOS snapshots (if any cover QuickCaptureView) will diff because the new chip row is visible. Re-record. iOS snapshots should be unchanged — the chip row content was already present from `QuickCaptureField`.

- [ ] **Step 6: Build both app targets**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expect: `** BUILD SUCCEEDED **` on both.

- [ ] **Step 7: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift \
        Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift \
        Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift \
        Packages/LillistUI/Tests/LillistUITests/QuickCapture/QuickCaptureDateSuggestionsTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__
git commit -m "refactor(quickcapture): unify date-token chip list across platforms

macOS QuickCaptureView previously surfaced no date-suggestion chips;
iOS QuickCaptureSheet hardcoded a four-token list. Both now consume
QuickCaptureDateSuggestions.default — adding a token surfaces on both
platforms simultaneously and stays coupled to the RelativeDate parser
contract (asserted by QuickCaptureDateSuggestionsTests)."
```

---

## Task 3: Unify per-platform keyboard shortcut coverage

**Files:**
- Read first: `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift` (current macOS shortcut bindings — confirm `⌘D` / `⌘.` / `Tab` / `Shift-Tab` / `⌘1/2/3` are still bound where Plan 13 left them)
- Modify: `Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift` (the Scene-level `CommandMenu` Plan 16 Task 29 introduced)

macOS today (per `LillistCommands.swift` — updated after Plan 13 landed):
- `⌘N` new task, `⌘⇧⏎` new sibling (was `⌘⇧N`; rebound by Plan 13 Task 5 to free `⌘⇧N` for macOS's "New Window")
- Space — toggle started *(gated on `@FocusedValue(\.listColumn) != nil`)*
- `⌘⏎` — mark closed (was `⌘D`; rebound by Plan 13 Task 5 to free `⌘D` for macOS's "Duplicate") *(gated)*
- `⌘.` — mark blocked *(gated)*
- `Tab` / `Shift-Tab` — indent/outdent *(gated)*
- `⌘F` — find in view, `⌘⇧F` — find everywhere
- `⌘1/2/3` — focus sidebar / list / detail

iOS today (per `LillistCommands.swift`, Plan 16 Task 29):
- `⌘⇧N` — new task (rebound from `⌘N` to avoid the iPadOS reserved "New Window")
- `⌘1/2/3/4` — Today / All / Filters / Search
- `⌘⇧F` — Find in Lillist…

The iPad surface lacks every status-mutation and indent action available on macOS. Bring the iPad up to parity for the actions that make sense in a touch-first shell:

- `⌘⏎` to mark closed (avoids the `⌘D` conflict with "Show Bookmarks" if Plan 13 rebound)
- `⌘.` to mark blocked
- `⌘⇧J` / `⌘⇧K` to indent / outdent (Tab is reserved by iPadOS for focus navigation)
- `⌘1/2/3` for sidebar/list/detail focus when running in the iPad three-column shell (Plan 16's `SplitShell`)

Tab navigation (`⌘1-4`) for the compact tab shell stays as-is; the new `⌘1-3` for focus only fire when the iPad split shell is active (gate via `@FocusedValue` or only register the shortcuts inside the split-shell view).

- [ ] **Step 1: Confirm current macOS shortcut bindings**

```bash
grep -n 'keyboardShortcut' Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift
```

Plan 13 Task 5 rebound `⌘D` → `⌘⏎` for "Mark Closed" and `⌘⇧N` → `⌘⇧⏎` for "New Sibling Task". Step 3 below assumes those bindings are still in place. If a later plan rebinds again, mirror the chosen alternative here so iPad's "mark closed" matches macOS's.

- [ ] **Step 2: Sanity-check the iOS `LillistCommands` exists on `main`**

```bash
ls Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift
```

Expected: file exists (Plan 16 Task 29). If it's missing, halt — something regressed between Plan 16 and this Plan 20 task.

- [ ] **Step 3: Add the parity shortcuts**

Add to the iOS `LillistCommands` two new `CommandMenu`s that mirror the macOS surface:

```swift
        CommandMenu("Task") {
            Button("Mark Closed") {
                NotificationCenter.default.post(name: .lillistMarkClosed, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [.command])

            Button("Mark Blocked & Schedule Follow-up") {
                NotificationCenter.default.post(name: .lillistMarkBlocked, object: nil)
            }
            .keyboardShortcut(".", modifiers: [.command])

            Divider()

            Button("Indent") {
                NotificationCenter.default.post(name: .lillistIndent, object: nil)
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])

            Button("Outdent") {
                NotificationCenter.default.post(name: .lillistOutdent, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }

        CommandMenu("View") {
            Button("Focus Sidebar") {
                NotificationCenter.default.post(name: .lillistFocusSidebar, object: nil)
            }
            .keyboardShortcut("1", modifiers: [.command])
            Button("Focus List") {
                NotificationCenter.default.post(name: .lillistFocusList, object: nil)
            }
            .keyboardShortcut("2", modifiers: [.command])
            Button("Focus Detail") {
                NotificationCenter.default.post(name: .lillistFocusDetail, object: nil)
            }
            .keyboardShortcut("3", modifiers: [.command])
        }
```

Reuse the macOS `Notification.Name` constants if shared cross-platform; otherwise mirror them so the observer in the shared list/detail view picks up both posts.

- [ ] **Step 4: Build the iOS target**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expect: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual smoke check (iPad simulator, hold ⌘)**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

The user holds `⌘` in the iPad simulator and confirms the new shortcuts appear in the overlay alongside `⌘N` / `⌘1-4` / `⌘⇧F`. (Documentation step — the plan doesn't programmatically assert overlay rendering.)

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift \
        Apps/Lillist-iOS/Lillist-iOS.xcodeproj/project.pbxproj
git commit -m "feat(iOS): expand iPad keyboard shortcut coverage to match macOS

Adds Mark Closed (⌘⏎), Mark Blocked (⌘.), Indent (⌘⇧J), Outdent
(⌘⇧K), Focus Sidebar/List/Detail (⌘1-3) to the iPad surface so every
status-mutation and column-focus action available on macOS is also
reachable from an iPad hardware keyboard. ⌘1-4 tab navigation in the
compact shell stays as-is."
```

---

## Task 4: Refactor `IOSScreenTourTests` to test real views

> **DECISION POINT.** This task is significantly larger than every other task in this plan. **Default action: flag the user, skip in Plan 20, propose `Plan 20a — IOSScreenTourTests Refactor`** as a separate plan that lands after. The sub-task sketch below is laid out so the spin-out is mechanical. Continue with Tasks 5-12.

**Goal:** `Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift` (573 lines) rebuilds each iOS screen with inline mock chrome (`tabScaffold`, `navBar`, `tabBar`, `tagRow`, `filterRow`, etc.) because the iOS app bundle isn't `@testable import`-able. Move screen composition from `Apps/Lillist-iOS/Sources/<Tab>/<Tab>View.swift` into `Packages/LillistUI/Sources/LillistUI/iOS/Screens/<Tab>Screen.swift`; app-target views become thin wrappers that supply `AppEnvironment` to the moved `Screen` struct.

**Files (if not spun out):**
- Create: `Packages/LillistUI/Sources/LillistUI/iOS/Screens/{TodayScreen,AllTagsScreen,FiltersListScreen,SearchScreen,SettingsScreen}.swift`
- Modify: `Apps/Lillist-iOS/Sources/{Today/TodayView,All/AllTagsView,Filters/FiltersListView,Search/SearchView,Settings/SettingsTab}.swift` (each becomes a thin wrapper)
- Modify: `Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift` (consume real screens; delete inline mock helpers)
- Modify: `Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__/IOSScreenTourTests/` (re-record per screen)

- [ ] **Step 1 (4a)** Today screen migration — commit `refactor(iOS): move TodayView composition into LillistUI.TodayScreen`.
- [ ] **Step 2 (4b)** All Tags screen migration — commit `refactor(iOS): move AllTagsView composition into LillistUI.AllTagsScreen`.
- [ ] **Step 3 (4c)** Filters list migration — commit `refactor(iOS): move FiltersListView composition into LillistUI.FiltersListScreen`.
- [ ] **Step 4 (4d)** Search screen migration — commit `refactor(iOS): move SearchView composition into LillistUI.SearchScreen`.
- [ ] **Step 5 (4e)** Settings tab migration — commit `refactor(iOS): move SettingsTab composition into LillistUI.SettingsScreen`.
- [ ] **Step 6 (4f)** Drop tour mock chrome — delete `navBar`/`tabBar`/`tagRow`/`filterRow`/`searchRow`/`settingsGroup`/`settingRow`/`onboardingBullet`/`labelledSection`/`tabScaffold` from `IOSScreenTourTests.swift`; each `test_<NN>_*` constructs the real `<Tab>Screen` with mock-data closures. Commit `refactor(tour): IOSScreenTourTests consume real LillistUI screens`.

**Recommended action for this Plan 20: flag the user and skip.** Continue with Tasks 5-12.

---

## Task 5: Replace `LillistUI.swift` stub with module documentation landing page

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/LillistUI.swift`

Today's stub (lines 1-5):

```swift
import Foundation

public enum LillistUI {
    public static let version = "0.1.0"
}
```

The `version` constant is unused by any test or production callsite (`grep -rn 'LillistUI.version'` returns nothing in the active codebase). Keep the constant for SemVer hygiene but lift the documentation surface to a module landing page.

- [ ] **Step 1: Replace the stub**

Edit `Packages/LillistUI/Sources/LillistUI/LillistUI.swift` to:

```swift
import Foundation

/// # LillistUI
///
/// Cross-platform SwiftUI component library shared by Lillist's
/// macOS and iOS app targets. Owns the design system, the
/// accessibility-environment helpers, and the shared building
/// blocks both shells compose into platform-specific surfaces.
///
/// ## Public surface
///
/// - **`Components/`** — atomic views: `TaskRowView`,
///   `SidebarRowView`, `StatusIndicatorView`, `BreadcrumbView`,
///   `EmptyStateView`, `TagChipView`, `SyncStatusDotView`.
/// - **`Theme/`** — design tokens. `StatusGlyph`, `TagTint`,
///   `StatusPalette`, `SyncPalette`, and `Tokens.swift` (spacing /
///   radius / typography / timing) — the canonical entry point.
/// - **`Accessibility/`** — environment-aware modifiers
///   (`accessibleAnimation`, `accessibleMaterial`,
///   `ContrastTuned.value(in:standard:increased:)`), platform-aware
///   `AccessibilityAnnouncements.post(_:priority:)`, and the WCAG
///   relative-luminance / contrast-ratio helpers in `ContrastMath`.
/// - **`Recurrence/`** — `RecurrenceEditorView` and view-model.
///   Backed by `LillistCore.RecurrenceRule`.
/// - **`QuickCapture/`** — the macOS panel host
///   (`QuickCaptureView`), shared parser (`QuickCaptureParser`),
///   canonical token list (`QuickCaptureDateSuggestions`).
/// - **`Status/`** — `StatusCycler`, `SyncStatusMonitor`,
///   `SyncIndicator`.
/// - **`DragDrop/`** — cross-platform drag/drop helpers.
/// - **`CrashReporting/`** — shared crash-report submission sheet.
/// - **`iOS/`** — iOS-only views/helpers (`FloatingAddButton`,
///   `QuickCaptureField`, `SizeClassRouter`, `SyncStatusBadge`).
///
/// ## Convention
///
/// Public types live under the directory matching their concern.
/// Update this landing page when adding new directories so the
/// surface stays discoverable.
public enum LillistUI {
    /// SemVer for LillistUI. Bump on public-API changes; pre-1.0,
    /// every release may break.
    public static let version = "0.1.0"
}
```

- [ ] **Step 2: Build the package**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```

Expect: `Build complete!` with no warnings.

- [ ] **Step 3: Confirm the doc renders**

The module-level doc-comment is consumed by Xcode's Quick Help. No automated assertion is appropriate; this is a documentation polish.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/LillistUI.swift
git commit -m "docs(ui): replace LillistUI.swift stub with module landing page

Documents the public surface (Components, Theme, Accessibility,
Recurrence, QuickCapture, Status, DragDrop, CrashReporting, iOS) and
calls out the design-system (Theme/Tokens.swift) and a11y
(Accessibility/AccessibilityEnvironment.swift) entry points.
Version constant retained for SemVer hygiene."
```

---

## Task 6: Audit and fix sentence/title case per platform

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift:82,90`
- Modify (per audit): `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift` (verify title case)
- Modify (per audit): `Apps/Lillist-iOS/Sources/Settings/*Section.swift` (verify button labels)
- Document: a checklist of audited callsites in the commit message

**Convention.** macOS: title case for menu items and every standalone button. iOS: title case for buttons in nav bars, toolbars, and primary CTAs; sentence case acceptable for inline / table-cell actions. `CrashReportSheet.swift` is shared via `#if os(…)` hosts — pick title case for its toolbar buttons.

- [ ] **Step 1: Fix the known offender in `CrashReportSheet`**

Edit `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift` lines 82 and 90:
- `Button("Don't send")` → `Button("Don't Send")`
- `Button("Send report")` → `Button("Send Report")`

- [ ] **Step 2: Audit macOS / iOS labels**

```bash
grep -nE 'Button\("[A-Z]' Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift
grep -nE 'Button\("[A-Za-z]' Apps/Lillist-iOS/Sources/Settings/*.swift
grep -nE 'Label\("[A-Z]|Text\("[A-Z]' Apps/Lillist-iOS/Sources/ Apps/Lillist-macOS/Sources/ Packages/LillistUI/Sources/LillistUI/ 2>&1 | head -80
```

Focus only on user-visible chrome (buttons, toolbar items, alert titles, navigation titles). Section headers and inline copy are out of scope (those follow their own conventions: short titles in title case, group headers in all-caps).

macOS `LillistCommands.swift` lines 13-65 already use title case (`New Task`, `Mark Closed`, etc.) — no fix needed. iOS Settings buttons: toolbar `"Done"` at `SettingsTab.swift:30` already title case; inline Form-row actions stay sentence case. Document any divergences uncovered in the commit message.

- [ ] **Step 3: Build all targets**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 4: Re-record snapshots that depend on the changed labels**

```bash
swift test --package-path Packages/LillistUI --filter 'CrashReport' 2>&1 | tail -10
```

Re-record per the standard `withSnapshotTesting(record: .all)` pattern if any snapshot diffs.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots
git commit -m "fix(ui): align button case to HIG (title case on macOS toolbars + sheets)

Audit pass:
- CrashReportSheet: 'Don't send' → 'Don't Send', 'Send report' → 'Send Report'
- macOS LillistCommands menu items: already title case (no change)
- iOS Settings buttons: 'Done' toolbar button already title case
- Inline / row-action buttons in Form sections: kept sentence case (HIG-compliant)

Rule established: title case for macOS menus and every standalone button;
title case for iOS toolbar/navbar buttons; sentence case acceptable for
inline iOS Form-row actions."
```

---

## Task 7: Fix `SidebarRowView` a11y modifier ordering

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift:34-37`
- Modify: `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:19-45` (no code change — verify ordering)
- Create: `Packages/LillistUI/Tests/LillistUITests/Components/SidebarRowViewA11yTests.swift`

Today (lines 23-38 of `SidebarRowView.swift`):

```swift
    public var body: some View {
        HStack(spacing: LillistSpacing.s) {
            …
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(badge.map {
            String(localized: "\(label), \($0) items", bundle: .module)
        } ?? label)
    }
```

`SidebarView.swift:19-45` consumers apply `.tag(SidebarSelection.…)` *after* `SidebarRowView`'s body emits. SwiftUI's `.tag(…)` and `.accessibilityLabel(…)` interact: the modifier that runs last wins. With `.tag()` outside the row's body, the explicit `accessibilityLabel` inside the body should win — but VoiceOver behavior is inconsistent across iOS/macOS when a selection-tagged row composes multiple a11y modifiers. The robust fix is to make the row's accessibility identity the *outermost* contract by running `.accessibilityElement(children: .combine)` and `.accessibilityLabel(…)` at the *end* of the chain, after any selection-relevant modifier the consumer attaches.

The fix: don't change the row internally (the current modifier order is correct for the row's standalone composition); document the convention in a `// MARK: Accessibility` block, and add a regression test that asserts the row's accessibility label survives `.tag()` composition.

- [ ] **Step 1: Write the test**

Create `Packages/LillistUI/Tests/LillistUITests/Components/SidebarRowViewA11yTests.swift`. The test reads the `SidebarRowView.swift` source and asserts modifier ordering (we can't drive VoiceOver from a unit test, but we can pin the source contract so future edits don't move `.tag()` ahead of `.accessibilityLabel`):

```swift
import XCTest
@testable import LillistUI

@MainActor
final class SidebarRowViewA11yTests: XCTestCase {
    func test_rowExposesAccessibilityLabel_whenComposedWithTag() throws {
        let path = "\(#filePath)"
            .replacingOccurrences(
                of: "Tests/LillistUITests/Components/SidebarRowViewA11yTests.swift",
                with: "Sources/LillistUI/Components/SidebarRowView.swift")
        let source = try String(contentsOfFile: path, encoding: .utf8)

        let body = source.components(separatedBy: "public var body: some View {").last ?? ""
        let firstClosingBrace = body.range(of: "    }")!.lowerBound
        let bodyBlock = String(body[..<firstClosingBrace])

        let combinePos = bodyBlock.range(of: ".accessibilityElement(children: .combine)")?.lowerBound
        let labelPos = bodyBlock.range(of: ".accessibilityLabel(")?.lowerBound

        XCTAssertNotNil(combinePos, ".accessibilityElement(children: .combine) must be present.")
        XCTAssertNotNil(labelPos, ".accessibilityLabel(...) must be present.")
        XCTAssertLessThan(combinePos!, labelPos!,
                          ".accessibilityElement must precede .accessibilityLabel so the combined element receives the explicit label.")
    }
}
```

Run:

```bash
swift test --package-path Packages/LillistUI --filter SidebarRowViewA11yTests 2>&1 | tail -10
```

Expect: PASS (current source already satisfies the ordering).

- [ ] **Step 2: Add a `MARK: Accessibility` comment to `SidebarRowView`**

Edit `Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift`. Replace the closing four lines (34-37) with:

```swift
        }
        // MARK: Accessibility
        // The .accessibilityElement(children: .combine) + .accessibilityLabel
        // pair runs *last* in the body chain so the row's selection-tag
        // (applied by SidebarView consumers via .tag(SidebarSelection.…))
        // doesn't mask the explicit label. The
        // SidebarRowViewA11yTests.test_rowExposesAccessibilityLabel_whenComposedWithTag
        // regression test pins the ordering.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(badge.map {
            String(localized: "\(label), \($0) items", bundle: .module)
        } ?? label)
    }
}
```

- [ ] **Step 3: Build + re-run the test**

```bash
swift test --package-path Packages/LillistUI --filter SidebarRowViewA11yTests 2>&1 | tail -5
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```

Expect: PASS + `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift \
        Packages/LillistUI/Tests/LillistUITests/Components/SidebarRowViewA11yTests.swift
git commit -m "test(a11y): pin SidebarRowView accessibility-modifier ordering

SidebarRowView's .accessibilityElement(children: .combine) and
.accessibilityLabel pair must run last in the body chain so the
selection .tag() consumers attach in SidebarView doesn't mask the
explicit label. Adds a regression test that reads SidebarRowView.swift
and asserts the ordering, plus a MARK: Accessibility comment in the
source documenting the contract."
```

---

## Task 8: Document `BreadcrumbView` accessibility contract

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/BreadcrumbView.swift`

Today (lines 1-16) the breadcrumb is pure-text: every segment is a `Text` inside an `HStack`, the whole stack composes a single accessibility element with a "Path: A › B › C" label. No segments are tappable.

When tappability lands (a future plan moves breadcrumbs to navigation), each segment must become a `Button` with `.accessibilityAddTraits(.isButton)`. Today's behavior is correct — the contract just needs to be documented so the next person to edit doesn't forget it.

- [ ] **Step 1: Add a doc-comment a11y contract block**

Edit `Packages/LillistUI/Sources/LillistUI/Components/BreadcrumbView.swift`. Replace lines 1-2 (the `import SwiftUI` and the `public struct` line) with the import + a leading doc-comment block, leaving the struct body untouched:

```swift
import SwiftUI

/// A non-interactive path breadcrumb (`A › B › C`). Today every
/// segment is plain `Text`; the whole stack composes one
/// accessibility element with the path read aloud.
///
/// # MARK: Accessibility
///
/// When segments become tappable (a future plan moves breadcrumbs
/// to navigation), the contract changes:
///
/// 1. Each segment becomes a `Button { … } label: { Text(name) }`
///    with `.accessibilityAddTraits(.isButton)` so VoiceOver
///    announces "Button: A".
/// 2. The outer `.accessibilityElement(children: .combine)` becomes
///    `.contain` (or is removed) so each button keeps its own
///    focus identity.
/// 3. The container `.accessibilityLabel("Path: …")` becomes
///    `.accessibilityLabel("Path")` so the path isn't read twice.
///
/// Until then, the combined-element + composed-label pattern is the
/// correct read-only contract.
public struct BreadcrumbView: View {
```

(The rest of the struct body — `path`, `init`, `body` — stays untouched.)

- [ ] **Step 2: Build**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```

Expect: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/BreadcrumbView.swift
git commit -m "docs(a11y): document BreadcrumbView accessibility contract for future tappability

No behavior change today — the breadcrumb is still pure-text and
composes as a single combined a11y element. Documents the
three-step contract change for when segments become tappable so the
next editor doesn't ship tappable segments with the read-only
accessibility composition."
```

---

## Task 9: Add `.accessibilityAddTraits(.isHeader)` to `RecurrenceEditorView` section labels

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:41,65,73,84,115`
- Create: `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorHeadingTests.swift`

Today's titled sections (confirm with `grep -n 'Section(' Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift`):

- Line 41: `Section("Frequency")`
- Line 65: `Section("On days")`
- Line 73: `Section("On days of month")`
- Line 84: `Section("Limit")`
- Line 115: `Section("Repeat after")`

(The unlabeled `Section { … }` blocks — the Repeats toggle, the Schedule picker, and the Save/Cancel bar — have no title to mark, so they're untouched.)

`SwiftUI.Section` already renders its title with a visual heading style and, on iOS, provides VoiceOver heading semantics automatically via `Form`. **But** on macOS the heading rotor behavior depends on the form style and the explicit trait; adding `.accessibilityAddTraits(.isHeader)` to the title row makes the heading rotor surface them consistently across platforms.

The cleanest hook is to construct the section's header explicitly with a labelled `Text` and add the trait. Replace each `Section("…") { … }` with `Section(header: Text("…").accessibilityAddTraits(.isHeader)) { … }`.

This extends the heading-trait coverage that the macOS detail-view section titles already have (`SubtaskOutlineView`, `JournalStreamView`, `NotesEditorView`).

- [ ] **Step 1: Write the failing test**

Create `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorHeadingTests.swift`:

```swift
import XCTest
@testable import LillistUI

@MainActor
final class RecurrenceEditorHeadingTests: XCTestCase {
    /// Every Section in RecurrenceEditorView must wrap its title in
    /// Text(...).accessibilityAddTraits(.isHeader) so the VoiceOver
    /// heading rotor surfaces them consistently across iOS and macOS.
    func test_everySection_marksHeaderTrait() throws {
        let path = "\(#filePath)"
            .replacingOccurrences(of: "Tests/LillistUITests/Recurrence/RecurrenceEditorHeadingTests.swift",
                                  with: "Sources/LillistUI/Recurrence/RecurrenceEditorView.swift")
        let source = try String(contentsOfFile: path, encoding: .utf8)

        let plainSectionTitles = ["\"Frequency\"", "\"On days\"",
                                   "\"On days of month\"", "\"Limit\"",
                                   "\"Repeat after\""]

        for title in plainSectionTitles {
            XCTAssertFalse(
                source.contains("Section(\(title))"),
                "Section(\(title)) must be Section(header: Text(\(title)).accessibilityAddTraits(.isHeader))"
            )
            XCTAssertTrue(
                source.contains("Text(\(title)).accessibilityAddTraits(.isHeader)"),
                "Section(\(title)) must wrap its title in Text(...).accessibilityAddTraits(.isHeader)"
            )
        }
    }
}
```

Run:

```bash
swift test --package-path Packages/LillistUI --filter RecurrenceEditorHeadingTests 2>&1 | tail -10
```

Expect: fails (current source uses bare `Section("…")`).

- [ ] **Step 2: Update each Section**

Edit `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift`. For each titled `Section`, rewrite the call site so the title is an explicit `Text(...).accessibilityAddTraits(.isHeader)`:

```
Section("Frequency")         → Section(header: Text("Frequency").accessibilityAddTraits(.isHeader))
Section("On days")           → Section(header: Text("On days").accessibilityAddTraits(.isHeader))
Section("On days of month")  → Section(header: Text("On days of month").accessibilityAddTraits(.isHeader))
Section("Limit")             → Section(header: Text("Limit").accessibilityAddTraits(.isHeader))
Section("Repeat after")      → Section(header: Text("Repeat after").accessibilityAddTraits(.isHeader))
```

Leave the unlabeled `Section { … }` blocks (the Repeats toggle, the Schedule picker, the Save/Cancel bar) untouched — they have no title to mark.

- [ ] **Step 3: Re-run the test**

```bash
swift test --package-path Packages/LillistUI --filter RecurrenceEditorHeadingTests 2>&1 | tail -5
```

Expect: PASS.

- [ ] **Step 4: Snapshot — re-record if any RecurrenceEditor visuals shift**

```bash
swift test --package-path Packages/LillistUI --filter Recurrence 2>&1 | tail -10
```

The `Section(header:)` overload renders identically to `Section("…")` on both platforms, so snapshots should be unchanged. If a diff appears, inspect and re-record.

- [ ] **Step 5: Build**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```

Expect: `Build complete!`.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift \
        Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorHeadingTests.swift
git commit -m "fix(a11y): mark RecurrenceEditorView section titles as headings

Every titled Section now wraps its label in
Text(...).accessibilityAddTraits(.isHeader) so the VoiceOver heading
rotor surfaces them consistently across iOS and macOS, matching the
treatment already in place on the macOS detail-view section titles."
```

---

## Task 10: Make `EmptyStateView` icon scale with Dynamic Type

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift:17`
- Create: `Packages/LillistUI/Tests/LillistUITests/Components/EmptyStateViewDynamicTypeTests.swift`

Today (lines 15-18):

```swift
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
```

The hardcoded `36` doesn't scale when the user picks a larger Dynamic Type size. Two equally good fixes:

1. **`@ScaledMetric` wrap:** Add `@ScaledMetric private var iconSize: CGFloat = 36` and use `.font(.system(size: iconSize, weight: .light))`. Preserves the exact base size.
2. **Semantic font:** Replace `.font(.system(size: 36, weight: .light))` with `.font(.largeTitle.weight(.light))`. Inherits Dynamic Type behavior for free, but base size shifts slightly (~34pt vs 36pt at default).

Option 1 preserves visual parity with all snapshot baselines; pick it.

- [ ] **Step 1: Write the failing test**

Create `Packages/LillistUI/Tests/LillistUITests/Components/EmptyStateViewDynamicTypeTests.swift`:

```swift
import XCTest
@testable import LillistUI

@MainActor
final class EmptyStateViewDynamicTypeTests: XCTestCase {
    /// EmptyStateView's icon must scale with Dynamic Type. We assert
    /// the source uses @ScaledMetric for the icon size rather than a
    /// hardcoded numeric literal in .font(.system(size: 36, ...)).
    func test_iconSize_isScaledMetric() throws {
        let path = "\(#filePath)"
            .replacingOccurrences(of: "Tests/LillistUITests/Components/EmptyStateViewDynamicTypeTests.swift",
                                  with: "Sources/LillistUI/Components/EmptyStateView.swift")
        let source = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(
            source.contains("@ScaledMetric"),
            "EmptyStateView must use @ScaledMetric so its icon scales with Dynamic Type."
        )
        XCTAssertFalse(
            source.contains(".font(.system(size: 36"),
            "EmptyStateView must not use a hardcoded 36pt size for its icon."
        )
    }
}
```

Run:

```bash
swift test --package-path Packages/LillistUI --filter EmptyStateViewDynamicTypeTests 2>&1 | tail -10
```

Expect: fails on both assertions.

- [ ] **Step 2: Edit `EmptyStateView`**

Edit `Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift`. Two surgical edits:

1. Add a stored property after the `systemImage` declaration:
   ```swift
       // @ScaledMetric so the icon respects the user's Dynamic Type
       // size. Default value 36 matches the visual baseline.
       @ScaledMetric private var iconSize: CGFloat = 36
   ```
2. Swap the hardcoded literal on line 17 (`.font(.system(size: 36, weight: .light))`) to consume the new property: `.font(.system(size: iconSize, weight: .light))`.

`@ScaledMetric` is part of `SwiftUI`, no extra import needed.

- [ ] **Step 3: Re-run the test**

```bash
swift test --package-path Packages/LillistUI --filter EmptyStateViewDynamicTypeTests 2>&1 | tail -5
```

Expect: PASS.

- [ ] **Step 4: Snapshot — verify default Dynamic Type renders identically**

```bash
swift test --package-path Packages/LillistUI --filter 'EmptyState|Tour' 2>&1 | tail -10
```

At the default Dynamic Type size, `@ScaledMetric` evaluates to the base value (36) — every existing snapshot baseline should match. If a diff appears (it shouldn't), investigate before re-recording.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift \
        Packages/LillistUI/Tests/LillistUITests/Components/EmptyStateViewDynamicTypeTests.swift
git commit -m "fix(a11y): EmptyStateView icon scales with Dynamic Type

Wraps the hardcoded 36pt icon size in @ScaledMetric so larger
Dynamic Type sizes proportionally enlarge the glyph. Default value
of 36 preserves the visual baseline at the default Dynamic Type
size; snapshots are unchanged."
```

---

## Task 11: Add explicit `.accessibilityLabel` to `DetailHeaderView` DatePickers

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/DetailHeaderView.swift` (the `DatePicker` `HStack` near the bottom of `body` — Plan 13 shifted line numbers by 1)

> **Plan 13 fallout (2026-05-16):** Plan 13 Task 12 inserted a `.accessibilityElement(children: .ignore)` line on the status pill `Menu` (around line 30), nudging the `DatePicker` `HStack` from its previously-documented `38-47` range. Use `rg -n 'DatePicker\("Start"|DatePicker\("Deadline"'` to locate it.

Today:

```swift
            HStack {
                DatePicker("Start", selection: Binding(
                    get: { start ?? Date() }, set: { start = $0 }
                ), displayedComponents: [.date])
                .labelsHidden()
                DatePicker("Deadline", selection: Binding(
                    get: { deadline ?? Date() }, set: { deadline = $0 }
                ), displayedComponents: [.date])
                .labelsHidden()
            }
```

`.labelsHidden()` keeps the visual layout tight, but Voice Control's label-match heuristic (which lets the user say "tap Start" or "tap Deadline") fails when no visible label exists. VoiceOver picks up the underlying `DatePicker(_:)` first argument, but Voice Control's heuristic prefers a visible label — falling back to no match. Adding an explicit `.accessibilityLabel(…)` after `.labelsHidden()` repairs the Voice Control path without changing visuals.

- [ ] **Step 1: Edit `DetailHeaderView`**

Edit `Apps/Lillist-macOS/Sources/Views/Detail/DetailHeaderView.swift`. Add `.accessibilityLabel(…)` to each DatePicker:

```swift
            HStack {
                DatePicker("Start", selection: Binding(
                    get: { start ?? Date() }, set: { start = $0 }
                ), displayedComponents: [.date])
                .labelsHidden()
                .accessibilityLabel(String(localized: "Start date"))
                DatePicker("Deadline", selection: Binding(
                    get: { deadline ?? Date() }, set: { deadline = $0 }
                ), displayedComponents: [.date])
                .labelsHidden()
                .accessibilityLabel(String(localized: "Deadline"))
            }
            .font(.subheadline)
```

- [ ] **Step 2: Build macOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expect: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Snapshot — verify visuals unchanged**

`.accessibilityLabel(…)` is a non-visual modifier. Any existing `DetailHeaderView` snapshot should remain identical:

```bash
swift test --package-path Packages/LillistUI --filter 'Detail|Tour' 2>&1 | tail -10
```

Expect: no diffs.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Detail/DetailHeaderView.swift
git commit -m "fix(a11y): label DetailHeaderView DatePickers for Voice Control

.labelsHidden() keeps the visual layout tight but breaks Voice
Control's label-match heuristic (\"tap Start\" / \"tap Deadline\").
Explicit .accessibilityLabel(...) repairs the Voice Control path
without changing visuals. VoiceOver behavior unchanged (it was
already reading the DatePicker label argument)."
```

---

## Task 12: Future-proof `TagChipView` for removability

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/TagChipView.swift`

Today (lines 1-29) the chip is pure `Text` — removal isn't possible. When a future plan adds an `onRemove` parameter (e.g. an "x" button for the tag-editor surface), the chip's accessibility contract changes. Document the contract now so the next person to add removability doesn't ship it without the a11y composition.

- [ ] **Step 1: Add a doc-comment a11y contract block**

Edit `Packages/LillistUI/Sources/LillistUI/Components/TagChipView.swift`. Prefix the `public struct TagChipView` line with the doc-comment block, leaving the body untouched:

```swift
import SwiftUI

/// A pill-shaped tag chip. Today pure-text, non-interactive.
///
/// # MARK: When tappable
///
/// When `onRemove: (() -> Void)?` becomes a parameter (planned for
/// the tag-editor surface), the contract changes:
///
/// 1. The chip becomes `Button { onRemove?() } label: { … }` (or
///    adds an inline "x" button to the right of the text).
/// 2. Add `.accessibilityAddTraits(.isButton)` so VoiceOver
///    announces "Button: Tag: work".
/// 3. Add `.accessibilityAction(named: "Remove") { onRemove?() }`
///    so Switch Control / Voice Control / VoiceOver users can
///    invoke removal without performing the visual "x" tap.
///
/// Until then, the read-only `Text` + `.accessibilityLabel("Tag: …")`
/// pattern is the correct contract.
public struct TagChipView: View {
```

(Rest of `TagChipView` — `name`, `tint`, `init`, `body` — stays untouched.)

- [ ] **Step 2: Build**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```

Expect: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/TagChipView.swift
git commit -m "docs(a11y): document TagChipView accessibility contract for future removability

No behavior change — the chip is still pure-text and non-interactive.
Documents the three-step contract change (.isButton trait,
.accessibilityAction(named: \"Remove\"), Button wrapper) for when an
onRemove callback lands."
```

---

## Task 13: Final sweep + engineering note

**Files:**
- Modify: `docs/engineering-notes.md` (append entry)

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

- [ ] **Step 2: Strict-warnings build (per CLAUDE.md house rule)**

```bash
swift build --package-path Packages/LillistCore -Xswiftc -warnings-as-errors 2>&1 | tail -3
swift build --package-path Packages/LillistUI -Xswiftc -warnings-as-errors 2>&1 | tail -3
```

Expect: `Build complete!`.

- [ ] **Step 3: Append engineering note**

Add at the top of `docs/engineering-notes.md` (above the most recent entry):

```markdown
## 2026-05-16 — Plan 20 shared polish & accessibility nits

**Context.** Plan 20 closed the cross-platform and a11y LOW/NIT items from the 2026-05-16 design review that didn't fit any single platform-specific plan: an `AccentColor` asset for both targets (placeholder brand tint), unified Quick Capture date-token chips, iPad keyboard shortcut parity with macOS, a module documentation landing page for `LillistUI`, a one-time title-case audit, and individual a11y modifier additions on `SidebarRowView`, `BreadcrumbView`, `RecurrenceEditorView`, `EmptyStateView`, `DetailHeaderView` DatePickers, and `TagChipView`. Task 4 (IOSScreenTourTests refactor) spun out to Plan 20a per the in-plan decision point.

**Rules.**

- **Shared components require shared assets.** When `LillistUI` reads `Color.accentColor`, every consuming app target needs a matching `AccentColor.colorset` **plus** `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME=AccentColor`. Without both, silent fallback to system blue.
- **Centralize parallel hardcoded lists at the seam.** Two platforms hardcoding the same short list (Quick Capture date tokens were on iOS but *missing* on macOS) drifts silently. Cure: a single `public enum X { public static let default: [Y] = [...] }` consumed by both surfaces, plus a parser-coupling regression test.
- **`@ScaledMetric` is the cure for hardcoded `.font(.system(size: N, ...))` literals.** Wrap numeric font sizes that should scale with Dynamic Type — one line preserves visual parity at the default size and respects user preference at every other size.
- **`.labelsHidden()` requires an explicit `.accessibilityLabel(...)` companion.** VoiceOver may pick up the underlying initializer label, but Voice Control's label-match heuristic prefers a visible label — falling back to no match when none exists.

**Evidence.** Plan 20 commits on `plan-20-shared-polish`.
```

- [ ] **Step 4: Commit and tag**

```bash
git add docs/engineering-notes.md
git commit -m "docs: record Plan 20 lessons (shared assets, centralized lists, @ScaledMetric, labelsHidden a11y)"
git tag plan-20-shared-polish
```

- [ ] **Step 5: Branch summary**

```bash
git log --oneline main..plan-20-shared-polish
```

---

## Plan 20 Scope

**In:** AccentColor asset + xcodegen wiring (Task 1); `QuickCaptureDateSuggestions` + dual-platform chip rows (Task 2); iPad keyboard parity for status/focus actions (Task 3); `LillistUI` module landing page (Task 5); one-time case audit + `CrashReportSheet` fix (Task 6); `SidebarRowView` a11y-ordering regression test + MARK (Task 7); `BreadcrumbView` future-tappable a11y docs (Task 8); `RecurrenceEditorView` `.isHeader` traits + test (Task 9); `EmptyStateView` `@ScaledMetric` + test (Task 10); `DetailHeaderView` DatePicker labels (Task 11); `TagChipView` future-removable a11y docs (Task 12); engineering-note + tag (Task 13).

**Out:** Task 4 (IOSScreenTourTests refactor) — spun out to **Plan 20a**; brand color decision (placeholder flagged); anything Plans 13-17 own (status cycler, design tokens, macOS chrome, iOS polish, i18n + a11y environments); Quick Capture date-token *localization* (Plan 17 Task 8); FollowUpFormView submission announcement (Plan 17 Task 19); macOS detail-view section heading traits (Plan 17 Task 27).

---

## Self-Review Checklist

- [ ] **Task 1.** Both app targets ship `AccentColor.colorset` with light + dark variants; both `project.yml`s set `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME=AccentColor`; tour snapshots re-recorded; `TODO(user: pick brand color)` flag present.
- [ ] **Task 2.** `QuickCaptureDateSuggestions.default == ["today","tomorrow","+3d","+1w"]`; macOS `QuickCaptureView.body` renders a chip row from it; iOS `QuickCaptureSheet.swift:25` consumes the shared list (no hardcoded tokens); `QuickCaptureDateSuggestionsTests` asserts parser round-trip.
- [ ] **Task 3.** `⌘⏎`, `⌘.`, `⌘⇧J`, `⌘⇧K`, `⌘1/2/3` bound on the iPad surface dispatching via the same notifications as macOS; macOS bindings unchanged (or consistent with Plan 13 rebindings).
- [ ] **Task 4.** Flagged to user; default outcome spun out to Plan 20a. If kept, 4a-4f delivered as six commits with per-screen re-recorded snapshots.
- [ ] **Task 5.** `LillistUI.swift` carries a doc-comment landing page listing Components / Theme / Accessibility / Recurrence / QuickCapture / Status / DragDrop / CrashReporting / iOS with one-line descriptions, plus Plan 14 / 17 entry-point references.
- [ ] **Task 6.** `CrashReportSheet.swift` buttons read "Don't Send" / "Send Report"; macOS menu items audited (already title case); iOS Settings audited (toolbar title case, inline sentence-case OK); audit checklist in commit message.
- [ ] **Task 7.** `SidebarRowViewA11yTests` passes; `MARK: Accessibility` block in `SidebarRowView.swift`.
- [ ] **Task 8.** `MARK: Accessibility` block in `BreadcrumbView.swift` documents the three-step contract change for future tappability.
- [ ] **Task 9.** Every titled `Section` in `RecurrenceEditorView` wraps its label in `Text(...).accessibilityAddTraits(.isHeader)`; `RecurrenceEditorHeadingTests` passes.
- [ ] **Task 10.** `@ScaledMetric private var iconSize: CGFloat = 36` present in `EmptyStateView`; `.font(.system(size: iconSize, ...))` consumes it; `EmptyStateViewDynamicTypeTests` passes; default-size snapshots unchanged.
- [ ] **Task 11.** Both DatePickers in `DetailHeaderView` carry `.accessibilityLabel(...)` after `.labelsHidden()`; visuals unchanged.
- [ ] **Task 12.** `MARK: When tappable` block in `TagChipView.swift` documents the three-step contract change for future removability.
- [ ] **Task 13.** All test suites green; strict-warnings builds clean; engineering note appended; `plan-20-shared-polish` tag exists.
- [ ] **No new managed-object entities, no migrations, no new SPM dependencies.** Build-plugin caching gotcha not triggered.
- [ ] **Conventional-commit prefixes throughout; one commit per task.**
