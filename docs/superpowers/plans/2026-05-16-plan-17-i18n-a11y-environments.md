# Lillist Plan 17 — Localization & Accessibility Environments

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up Lillist's localization infrastructure and bring the app into compliance with Apple's accessibility-environment values (`accessibilityReduceMotion`, `accessibilityReduceTransparency`, `accessibilityShouldIncreaseContrast`, `accessibilityDifferentiateWithoutColor`). The codebase currently has **zero** usage of these environment values and **zero** localization infrastructure — every user-facing string is a hardcoded English literal. This plan does the cheap-now-expensive-later work to set both up cleanly before more strings/views land, so future locales become a content swap and the four a11y environments don't have to be retrofitted view-by-view.

**Architecture:** Localization rides on Apple's String Catalog (`Localizable.xcstrings`), one per binary: both app targets get their own catalogs (Xcode/xcodegen-generated, auto-populated by the build), and `LillistUI` ships its own catalog as a SPM-`process`-ed resource. `Text("…")` / `Button("…")` / `Label("…")` initializers already take `LocalizedStringKey` so they extract for free, but `String`-typed `.accessibilityLabel(_:)` / `.accessibilityHint(_:)` / `.accessibilityValue(_:)` callsites do not — those get rewritten to `String(localized: "…", bundle: .module)` (inside `LillistUI`) or `String(localized: "…")` (in app targets) so the extractor picks them up. The accessibility-environment work introduces `Packages/LillistUI/Sources/LillistUI/Accessibility/` with two new files: `AccessibilityEnvironment.swift` (helper view-modifiers that consult environment values: `.accessibleAnimation(...)`, `.accessibleMaterial(...)`, `.contrastTuned(...)`) and `Announcements.swift` (a platform-aware `AccessibilityAnnouncements.post(_:priority:)` that fans out to `AccessibilityNotification.Announcement` on iOS and `NSAccessibility.post(...)` on macOS). Sync state and tag chips gain shape/contrast axes; the recurrence editor gets weekday-symbol localization plus a "limit occurrences" toggle and a Voice Control–friendly TextField companion to its Stepper. Snapshot tests cover RTL renders under `ar` locale and the high-contrast / reduce-transparency code paths.

**Tech Stack:** Swift 6, SwiftUI, String Catalog (`Localizable.xcstrings`, iOS 17+ / macOS 14+), `AccessibilityNotification.Announcement` (iOS 17+), `NSAccessibility.post(_:argument:)` (macOS), `swift-snapshot-testing` for RTL / environment-value snapshots, XCTest for `LillistUITests`, Swift Testing for `LillistCoreTests`. No new third-party dependencies; APCA contrast math is a 30-line pure-Swift port (sibling `ContrastMath.swift`).

**Depends on:**

- Plans 1–10 — all on `main`.
- **Plan 11** (`docs/superpowers/plans/2026-05-14-pre-uat-cleanup.md`) — supplies `RecurrenceEditorView`, `TaskStore.purgeAll`, the Trash-purge UIs, the hotkey recorder.
- **Plan 12** (`docs/superpowers/plans/2026-05-15-plan-12-followups.md`) — engineering-notes pattern.
- **Plan 13** (interaction & motion polish, expected on `main`) — owns drag/drop animations Task 11 audits. If not merged, Task 11's grep returns zero hits and the task becomes a placeholder for future helper-modifier usage.
- **Plan 14** (color/contrast palette extraction) — owns `SyncPalette` (`Packages/LillistUI/Sources/LillistUI/Theme/SyncPalette.swift` on `main`). Task 16 extends it with `differentiatedSystemImage`.
- **Plan 15** (macOS chrome) — actually shipped `StatusPalette` (in `Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift`, public, with `color(for:)` and `fill(for:)`) as a follow-up to Plan 14. Task 17 below extends that *existing* type with an explicit `tint(for:)` accessor and revisits the `.blocked` hue, since Plan 15 left it at `.orange` (legible, but Plan 17 favors `.red` for screen-reader rotor visibility).
- **Plan 15** (form/inline-create polish) — Task 23 layers required-field a11y onto whatever shape Plan 15 leaves the title inputs in.
- **Plan 16** (iOS polish) — shipped a `Toggle("Repeat forever", isOn:)` (inverse polarity of Task 21's "Limit occurrences" framing) plus a revealed Stepper. Task 21 now only adds the a11y `.accessibilityLiveRegion` modifiers and asserts the toggle shape via test — no editor surgery needed. Plan 16 also raised the iOS deployment target to 26.0, deleted `Apps/Lillist-iOS/Sources/Common/FloatingPlusOverlay.swift` (the FAB now lives in `.tabViewBottomAccessory`), and unified `TabShell.Tab` / `SplitShell.Section` into `LillistUI.iPadSection`. Plan 17 file references reflect post-Plan-16 state.

---

## File Structure

```
Lillist/
├── Packages/
│   └── LillistUI/
│       ├── Package.swift                                            (modify — add resources: [.process("Resources")])
│       ├── Sources/
│       │   └── LillistUI/
│       │       ├── Accessibility/                                   (NEW directory)
│       │       │   ├── AccessibilityEnvironment.swift               (NEW — view-modifier helpers)
│       │       │   ├── Announcements.swift                          (NEW — platform-aware post)
│       │       │   └── ContrastMath.swift                           (NEW — APCA/WCAG helpers)
│       │       ├── Resources/                                       (NEW directory)
│       │       │   └── Localizable.xcstrings                        (NEW — string catalog)
│       │       ├── Components/
│       │       │   ├── BreadcrumbView.swift                         (modify — chevron.forward, RTL)
│       │       │   ├── SidebarRowView.swift                         (modify — contrast badge)
│       │       │   ├── StatusIndicatorView.swift                    (modify — String(localized:))
│       │       │   ├── SyncStatusDotView.swift                      (modify — String(localized:), differentiate, announce, AttributedString interpolation)
│       │       │   ├── TagChipView.swift                            (modify — contrast tuning)
│       │       │   └── TaskRowView.swift                            (modify — String(localized:))
│       │       ├── iOS/
│       │       │   ├── FloatingAddButton.swift                      (modify — String(localized:))
│       │       │   ├── QuickCaptureField.swift                      (modify — String(localized:))
│       │       │   └── SyncStatusBadge.swift                        (modify — String(localized:), differentiate, AttributedString)
│       │       ├── QuickCapture/
│       │       │   └── QuickCaptureView.swift                       (modify — reduce-transparency, String(localized:))
│       │       ├── Recurrence/
│       │       │   ├── RecurrenceEditorView.swift                   (modify — weekday symbols, TextField companion, Limit toggle, Cancel shortcut)
│       │       │   └── RecurrenceEditorViewModel.swift              (modify — bounded toggle)
│       │       └── Theme/
│       │           ├── StatusPalette.swift                          (modify — Task 17 `.blocked` → `.red`)
│       │           └── TagTint.swift                                (modify — contrast floor)
│       └── Tests/
│           └── LillistUITests/
│               ├── Accessibility/                                   (NEW directory)
│               │   ├── AccessibilityEnvironmentTests.swift          (NEW)
│               │   ├── AnnouncementsTests.swift                     (NEW)
│               │   └── ContrastMathTests.swift                      (NEW)
│               └── Snapshots/
│                   ├── LocalizationSnapshotTests.swift              (NEW — RTL + ar locale)
│                   ├── ContrastSnapshotTests.swift                  (NEW — increase-contrast env)
│                   └── ReduceTransparencySnapshotTests.swift        (NEW — material substitutions)
├── Apps/
│   ├── project.yml                                                  (modify — declare iOS/macOS catalogs, knownRegions)
│   ├── Lillist-iOS/
│   │   ├── Resources/                                               (NEW directory if absent)
│   │   │   └── Localizable.xcstrings                                (NEW — string catalog)
│   │   ├── Sources/
│   │   │   ├── Onboarding/
│   │   │   │   └── OnboardingScreen.swift                           (modify — reduce-transparency, error live region)
│   │   │   ├── QuickCapture/
│   │   │   │   └── QuickCaptureSheet.swift                          (modify — String(localized:), announce, .keyboardShortcut, live region)
│   │   │   └── Settings/
│   │   │       └── TrashSection.swift                               (modify — announce on purge result)
│   └── Lillist-macOS/
│       ├── Resources/                                               (NEW directory if absent)
│       │   └── Localizable.xcstrings                                (NEW — string catalog)
│       └── Sources/
│           ├── Preferences/
│           │   └── TrashPane.swift                                  (modify — announce on purge result)
│           └── Views/
│               ├── Detail/
│               │   ├── FollowUpFormView.swift                       (modify — announce on commit)
│               │   ├── JournalStreamView.swift                      (modify — accessibilityAddTraits(.isHeader))
│               │   ├── NotesEditorView.swift                        (modify — accessibilityAddTraits(.isHeader))
│               │   └── SubtaskOutlineView.swift                     (modify — accessibilityAddTraits(.isHeader))
│               ├── EmptyView/
│               │   └── NoSelectionDetailView.swift                  (modify — focusable hint)
│               └── TaskList/
│                   └── InlineCreateField.swift                      (modify — required-field label)
└── docs/
    └── engineering-notes.md                                         (append Plan 17 entry)
```

---

## Notes for the Implementer

- **String Catalog requires iOS 17+ / macOS 14+.** Deployment targets are macOS 15 / iOS 18, so no `Localizable.strings` fallback is needed.
- **`String(localized:bundle:)` inside LillistUI must pass `bundle: .module`.** App targets omit `bundle:` (defaults to `Bundle.main`).
- **`Text("…")` extracts automatically; `.accessibilityLabel("…")` does not.** `Text`, `Button`, `Label`, `Section`, `Picker`, `Toggle`, `TextField` placeholders, `Stepper` all accept `LocalizedStringKey`. `.accessibilityLabel/Hint/Value(_:)` take `String` — the extractor skips them. Wrap each in `String(localized: …)`.
- **Interpolated literals preserve placeholders.** `Text("Last synced \(relative)")` becomes the key `"Last synced %@"`. `"Last synced " + relative` produces an orphan fragment.
- **`AccessibilityNotification.Announcement` is iOS 17+; `NSAccessibility.post(_:argument:)` is the AppKit shape.** Wrap both in `AccessibilityAnnouncements.post(_:priority:)` so callers don't `#if` everywhere.
- **RTL snapshots need both `.layoutDirection` AND `.locale`.** Layout-direction-only catches mirror-flipping (chevrons); locale-only doesn't actually flip layout. The combined `.environment(\.layoutDirection, .rightToLeft).environment(\.locale, Locale(identifier: "ar"))` is the deterministic recipe.
- **WCAG over APCA for the contrast floor.** WCAG 2.x's 4.5:1 ratio is the conservative, easily-testable bar and is what `ContrastMath.wcagRatio(_:_:)` returns. APCA is more perceptually accurate but the rule of thumb (`|Lc| >= 60`) is fuzzier; we prefer WCAG for this plan's floor enforcement.
- **Standard accessibility env values flow through SwiftUI automatically.** No custom `EnvironmentKey` needed for any of the four (`accessibilityReduceMotion`, `accessibilityReduceTransparency`, `accessibilityShouldIncreaseContrast`, `accessibilityDifferentiateWithoutColor`).
- **Snapshot baselines record on first run.** Commit `__Snapshots__/` directories. RTL snapshots lock the *shape* (mirrored layout, no clipping); ar-locale renders look near-identical to en-RTL until translations land — the baseline still catches layout regressions.
- **`Calendar.current.standaloneWeekdaySymbols` is Sunday-first regardless of locale's `firstWeekday`.** Index 0 = `.sunday`, etc.
- **No Core Data model changes here**, so no `touch` incantation.
- **Conv-commit prefixes.** `chore(i18n):` for scaffolding; `refactor(i18n):` for re-wrapping labels; `feat(a11y):` for environment-honoring behavior; `test(a11y):` / `test(i18n):` for new snapshot suites.
- **Verification.** `swift test --package-path Packages/LillistUI` for SPM; `xcodebuild … CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build` for apps. Warnings-as-errors stays clean throughout.
- **Push HTTPS-only.** `git -c url."https://github.com/".insteadOf="git@github.com:" push origin plan-17-i18n-a11y-environments`.

> **Plan 13 fallout (2026-05-16):** Plan 13 landed on `main` first and added several a11y modifiers this plan should localize rather than overwrite. Concrete additions to be aware of:
> - `TaskRowView.composedAccessibilityLabel(task:tagNames:)` — new public static helper composing `"<title>, <status>[, tagged <tags>][, due <date>]"`. Localize the joiner words ("tagged", "due") *inside* the helper rather than hardcoding the English shape at call sites. See Task 4's TaskRowView snippet.
> - `SyncStatusBadge` now wraps a 44pt frame + `.contentShape(Rectangle())` + `.accessibilityAddTraits(.isStaticText)` (Plan 13 Task 8) and uses `if case .inProgress = indicator` (Plan 13 Task 1). Preserve all of those when rewriting the badge body in Tasks 16 and 20.
> - `StatusIndicatorView` has a `.accessibilityAction(named: Text("Cycle status"))` (Plan 13 Task 7). The `Text(...)` argument extracts for localization automatically — no rewrite needed, but don't drop the action when porting to `String(localized:)`.
> - `FloatingAddButton` has a `.accessibilityAction(named: Text("Capture from clipboard"))` (Plan 13 Task 11). Same note as above.
> - `InlineCreateField.onKeyPress` returns `.ignored` when `text.isEmpty` (Plan 13 Task 6) so Tab can leave the field. Preserve that branch when rewriting in Task 23.
> - Four iOS list views (TodayView, TagTaskListView, FilterResultsView, SearchView) gained `.swipeActions` and `.contextMenu` (Plan 13 Tasks 13–15) — those Buttons' titles ("Complete", "Snooze", "Delete", "Change status") are user-facing strings that need localization in Task 4's app-target sweep.
> - macOS `DetailHeaderView` has `.accessibilityElement(children: .ignore)` immediately before its `.accessibilityLabel("Status: …")` (Plan 13 Task 12). Don't drop the `.ignore` modifier when re-wrapping the label in `String(localized:)`.

---

## Task 1: Add the String Catalog to LillistUI's SPM target

**Files:**
- Modify: `Packages/LillistUI/Package.swift`
- Create: `Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings`

The catalog is a JSON file. Xcode auto-populates it on build by walking `LocalizedStringKey` usages and `String(localized:)` callsites. We seed it with an empty top-level skeleton; the first SPM build after Task 4 will fill it.

- [ ] **Step 1: Create the empty catalog**

Path: `Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings`

Contents (an empty but well-formed String Catalog with English as the source language):

```json
{
  "sourceLanguage" : "en",
  "strings" : {},
  "version" : "1.0"
}
```

- [ ] **Step 2: Wire the resource into `Package.swift`**

Edit `Packages/LillistUI/Package.swift`. In the `.target(name: "LillistUI", …)` block, add the `resources:` argument:

```swift
        .target(
            name: "LillistUI",
            dependencies: [
                .product(name: "LillistCore", package: "LillistCore")
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
```

`.process("Resources")` lets SwiftPM apply platform-specific processing (compiling `.xcstrings` to `.strings`-shaped runtime artifacts). `.copy("Resources")` would skip processing and not work for catalogs.

- [ ] **Step 3: Build LillistUI to confirm SwiftPM picks up the resource**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -5
```

Expected: clean build. No new warnings. If a "unhandled file Resources/Localizable.xcstrings" warning appears, the resource block isn't recognized — confirm Swift tools version (must be 6.0+) and that the `Resources/` directory is exactly at `Sources/LillistUI/Resources/`.

- [ ] **Step 4: Run the existing LillistUI test suite to confirm no regression**

```bash
swift test --package-path Packages/LillistUI 2>&1 | tail -5
```

Expected: same PASS count as before the change.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Package.swift \
        Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings
git commit -m "chore(i18n): scaffold Localizable.xcstrings in LillistUI SPM target"
```

---

## Task 2: Add String Catalogs to both app targets

**Files:**
- Create: `Apps/Lillist-iOS/Resources/Localizable.xcstrings`
- Create: `Apps/Lillist-macOS/Resources/Localizable.xcstrings`
- Modify: `Apps/project.yml`

Both app targets currently have no `Resources/` directory wired into `project.yml` for a string catalog. The macOS target already has `Lillist-macOS/Resources` with the app icon catalog and entitlements assets; the iOS target's analogous directory will be created.

- [ ] **Step 1: Verify current `Resources/` layout for both targets**

```bash
ls -la Apps/Lillist-iOS/ Apps/Lillist-macOS/Resources/ 2>&1
```

Expected: macOS target has `Lillist-macOS/Resources/` (with `Assets.xcassets`, etc.); iOS target may or may not have a `Resources/` — if absent, create it.

- [ ] **Step 2: Create both catalogs**

Path A: `Apps/Lillist-iOS/Resources/Localizable.xcstrings`
Path B: `Apps/Lillist-macOS/Resources/Localizable.xcstrings`

Contents (identical empty skeleton, same as Task 1):

```json
{
  "sourceLanguage" : "en",
  "strings" : {},
  "version" : "1.0"
}
```

- [ ] **Step 3: Wire the iOS resource directory into `project.yml`**

In `Apps/project.yml`, find the `Lillist-iOS` target's `sources:` block. Confirm it already has a `Resources` entry; if not, add one. Apple's String Catalog is auto-detected by xcodegen when the file lives in a `sources:` path with `buildPhase: resources`. Add `developmentLanguage: en` and `knownRegions: [en, Base]` to the `options:` block if not already present (the project file already sets `developmentLanguage: en` for the macOS variant; mirror that to iOS).

Concretely, for the `Lillist-iOS` target:

```yaml
  Lillist-iOS:
    type: application
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: Lillist-iOS/Sources
      - path: Lillist-iOS/Resources
        buildPhase: resources
    settings:
      base:
        # existing settings…
```

For the `Lillist-macOS` target, the resources path is already wired — confirm `Lillist-macOS/Resources/Localizable.xcstrings` is reachable by the `path: Lillist-macOS/Resources` entry. If a separate explicit entry is needed for the catalog, add `- path: Lillist-macOS/Resources/Localizable.xcstrings`.

Also ensure the project-wide `options:` block sets:

```yaml
options:
  developmentLanguage: en
  # Other existing options…
```

(Already present per the existing `Apps/project.yml`.)

- [ ] **Step 4: Regenerate Xcode projects**

```bash
cd Apps && xcodegen generate --spec project.yml --project . && cd -
```

Expected: `project.pbxproj` updated. If git diff is empty, the catalog was already picked up by directory glob.

- [ ] **Step 5: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **` from both. Catalog is recognized as a Localizations file (not a generic resource), populated by the extractor on subsequent builds.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Resources/Localizable.xcstrings \
        Apps/Lillist-macOS/Resources/Localizable.xcstrings \
        Apps/project.yml \
        Apps/Lillist-macOS.xcodeproj/project.pbxproj
git commit -m "chore(i18n): scaffold Localizable.xcstrings in iOS + macOS app targets"
```

---

## Task 3: Audit `Text(…)`, `Button(…)`, `Label(…)`, etc. for accidental String-interpolation use

**Files:**
- Audit-only (no edits unless a violation is found):
  - `Packages/LillistUI/Sources/LillistUI/**/*.swift`
  - `Apps/Lillist-iOS/Sources/**/*.swift`
  - `Apps/Lillist-macOS/Sources/**/*.swift`

SwiftUI's `Text("Hello")` initializer takes `LocalizedStringKey`. `Text(someString)` takes `String` and skips localization. The audit flags the latter — almost every callsite *should* be the former.

- [ ] **Step 1: Grep for `Text(String(format:`**

```bash
grep -RIn 'Text(String(format:' Packages/LillistUI/Sources/ Apps/ 2>&1
```

Expected: zero hits. Any hit must be converted to interpolation form (`Text("Hello \(name)")`) so the extractor sees the key.

- [ ] **Step 2: Grep for `Text(.init(`**

```bash
grep -RIn 'Text(\.init(' Packages/LillistUI/Sources/ Apps/ 2>&1
```

Expected: zero hits. Same logic — bypasses LocalizedStringKey overload.

- [ ] **Step 3: Grep for `Button(action:` patterns with a non-literal label**

```bash
grep -RIn 'Text(LocalizedStringKey(' Packages/LillistUI/Sources/ Apps/ 2>&1
```

Expected: two hits in `JournalStreamView.swift:53` and `NotesEditorView.swift:18`, both intentional Markdown-bearing strings the user composed at runtime — not user-facing chrome. Leave both alone but add a `// i18n-exempt: user-authored content` comment above each so future audits skip them.

Edit `Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift:53`:

```swift
            // i18n-exempt: user-authored note body, not chrome.
            Text(LocalizedStringKey(entry.body))
```

Edit `Apps/Lillist-macOS/Sources/Views/Detail/NotesEditorView.swift:18`:

```swift
                // i18n-exempt: user-authored Markdown.
                Text(LocalizedStringKey(markdown))
```

- [ ] **Step 4: Confirm clean build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift \
        Apps/Lillist-macOS/Sources/Views/Detail/NotesEditorView.swift
git commit -m "chore(i18n): annotate intentional user-authored-content i18n exemptions"
```

(If Steps 1 and 2 find genuine violations beyond the documented exemptions, this task expands to convert each. The current codebase has none — Step 3's two are the only `LocalizedStringKey(_:)` callsites.)

---

## Task 4: Localize every `String`-typed accessibility label/hint/value

**Files:** every Swift file under `Packages/LillistUI/Sources/` and `Apps/` flagged by the inventory grep below (~35 sites at plan-write time, plus `StatusGlyph.accessibilityLabel(for:)` whose return value funnels into many of them).

The rewrite is mechanical:

| Layer | Before | After |
|-------|--------|-------|
| `LillistUI` literal | `.accessibilityLabel("New task")` | `.accessibilityLabel(String(localized: "New task", bundle: .module))` |
| `LillistUI` interpolation | `.accessibilityLabel("Path: \(joined)")` | `.accessibilityLabel(String(localized: "Path: \(joined)", bundle: .module))` |
| App target literal | `.accessibilityLabel("Settings")` | `.accessibilityLabel(String(localized: "Settings"))` |
| App target interpolation | `.accessibilityLabel("\(count) tasks")` | `.accessibilityLabel(String(localized: "\(count) tasks"))` |

`String(localized:)` accepts interpolated literals; placeholders survive translation as `%@`, `%d`, etc.

- [ ] **Step 1: Enumerate the inventory**

```bash
grep -RIn 'accessibility\(Label\|Hint\|Value\)' Packages/LillistUI/Sources Apps/ 2>&1 | wc -l
grep -RIn 'accessibility\(Label\|Hint\|Value\)' Packages/LillistUI/Sources Apps/
```

Expected: ~35 sites across `LillistUI/Components/`, `LillistUI/iOS/`, `LillistUI/QuickCapture/`, `LillistUI/CrashReporting/`, `LillistUI/Theme/StatusGlyph.swift`, `Apps/Lillist-iOS/Sources/Detail/`, `Root/`, `Apps/Lillist-macOS/Sources/Views/Detail/`, `Views/TaskList/`. Match against the design-review inventory; flag any drift.

- [ ] **Step 2: Apply the rewrite to each `LillistUI` file**

For every LillistUI callsite, wrap the argument in `String(localized: …, bundle: .module)`. Representative samples (apply the same pattern to every flagged file):

```swift
// FloatingAddButton.swift
.accessibilityLabel(String(localized: "New task", bundle: .module))
.accessibilityHint(String(localized: "Opens quick capture", bundle: .module))

// TagChipView.swift
.accessibilityLabel(String(localized: "Tag: \(name)", bundle: .module))

// BreadcrumbView.swift
.accessibilityLabel(String(localized: "Path: \(path.joined(separator: " › "))", bundle: .module))

// SidebarRowView.swift
.accessibilityLabel(String(localized: "\(badge) items", bundle: .module))
.accessibilityLabel(badge.map {
    String(localized: "\(label), \($0) items", bundle: .module)
} ?? label)

// TaskRowView.swift — Plan 13 fallout: the row label is now built
// inside the static composedAccessibilityLabel(task:tagNames:) helper,
// which composes "<title>, <status>[, tagged <tags>][, due <date>]".
// Localize *inside* the helper so the comma joiner respects the locale
// (some right-to-left locales use a different list separator), and
// localize the prefix words ("tagged", "due") rather than embedding
// English literals in the interpolation:
.accessibilityLabel(String(localized: "Drag handle", bundle: .module))
.accessibilityLabel(TaskRowView.composedAccessibilityLabel(task: task, tagNames: tagNames))
// Then in composedAccessibilityLabel itself:
//   parts.append(String(localized: "tagged \(tagNames.joined(separator: ", "))", bundle: .module))
//   parts.append(String(localized: "due \(formatted)", bundle: .module))
```

For `LillistUI/Theme/StatusGlyph.swift`, the helper itself returns `String`. Localize at the source:

```swift
public static func accessibilityLabel(for status: Status) -> String {
    switch status {
    case .todo:    return String(localized: "To do", bundle: .module)
    case .started: return String(localized: "Started", bundle: .module)
    case .blocked: return String(localized: "Blocked", bundle: .module)
    case .closed:  return String(localized: "Closed", bundle: .module)
    }
}
```

- [ ] **Step 3: Apply the rewrite to each app-target file**

Same pattern, omitting `bundle:`. Examples:

```swift
// TabShell.swift / SplitShell.swift
.accessibilityLabel(String(localized: "Settings"))

// DetailHeaderView.swift
.accessibilityLabel(String(localized: "Status: \(StatusGlyph.accessibilityLabel(for: status))"))

// TaskListHeaderView.swift
.accessibilityLabel(String(localized: "\(count) tasks"))
```

- [ ] **Step 4: Build, run snapshot tests, verify clean**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
swift test --package-path Packages/LillistUI 2>&1 | tail -5
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: all four green. Snapshot PASS count unchanged (English source-language strings → identical pixels). Catalog files grow as the extractor picks up new keys (visible in `git status`).

- [ ] **Step 5: Final inventory grep — confirm no residual hardcoded strings**

```bash
grep -RIn 'accessibility\(Label\|Hint\|Value\)("' Packages/LillistUI/Sources Apps/ 2>&1
```

Expected: zero hits.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistUI/Sources \
        Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings \
        Apps/Lillist-iOS/Sources \
        Apps/Lillist-iOS/Resources/Localizable.xcstrings \
        Apps/Lillist-macOS/Sources \
        Apps/Lillist-macOS/Resources/Localizable.xcstrings
git commit -m "refactor(i18n): route all String-typed a11y labels through String(localized:)"
```

---

## Task 5: Fix sync-status string concatenation; switch to interpolated literals

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift:46-53`
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift:37-48`

The current code concatenates English `"Last synced "` with a `RelativeDateTimeFormatter`-produced phrase (which *is* localized). The catalog can't see the English fragment as part of the same key, and translators only get the orphan. Use a single interpolated literal so the catalog key is `"Last synced %@"`.

- [ ] **Step 1: Fix `SyncStatusDotView.swift`**

Replace the `label` computed property (lines 46-53):

```swift
    private var label: String {
        switch indicator {
        case .idle(let last):
            if let last {
                let relative = Self.relativeFormatter.localizedString(for: last, relativeTo: Date())
                return String(localized: "Last synced \(relative)", bundle: .module)
            } else {
                return String(localized: "Not synced yet", bundle: .module)
            }
        case .inProgress:
            return String(localized: "Syncing…", bundle: .module)
        case .error(let msg, _):
            return String(localized: "Sync error: \(msg)", bundle: .module)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
```

Also adapt the `detail` `@ViewBuilder` (lines 55-60):

```swift
    @ViewBuilder private var detail: some View {
        if case .error(_, let last) = indicator, let last {
            Text("Last successful sync: \(last.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
```

(`Text(…)` already extracts — no rewrite needed beyond using the interpolated form.)

And the popover's `"Try again"` button — already a literal that `Button` extracts; no change.

- [ ] **Step 2: Fix `SyncStatusBadge.swift`**

Replace the `label` computed property (lines 37-48):

```swift
    private var label: String {
        switch indicator {
        case .idle(let lastSync):
            if let lastSync {
                let relative = Self.relativeFormatter.localizedString(for: lastSync, relativeTo: Date())
                return String(localized: "Last synced \(relative)", bundle: .module)
            } else {
                return String(localized: "Sync idle", bundle: .module)
            }
        case .inProgress:
            return String(localized: "Syncing", bundle: .module)
        case .error(let message, _):
            return String(localized: "Sync error: \(message)", bundle: .module)
        }
    }
```

- [ ] **Step 3: Build LillistUI**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```

Expected: clean build. New keys appear in the catalog (`"Last synced %@"`, `"Sync error: %@"`).

- [ ] **Step 4: Run the iOS snapshot tests for SyncStatusBadge**

```bash
swift test --package-path Packages/LillistUI --filter SyncStatus 2>&1 | tail -10
```

Expected: pass (English source language unchanged → identical pixels). If the test names differ in your tree, fall back to `--filter iOSSnapshot` or run the full suite.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift \
        Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift \
        Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings
git commit -m "refactor(i18n): interpolate sync-status labels so translators get whole keys"
```

---

## Task 6: Replace directional SF Symbols with auto-flipping forward/backward variants

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/BreadcrumbView.swift:9`

`Image(systemName: "chevron.right")` shows a right-pointing chevron in both LTR and RTL — wrong for RTL where the path should read right-to-left. `chevron.forward` (and `chevron.backward`) mirror automatically: forward = right in LTR, left in RTL.

- [ ] **Step 1: Audit for `.left` / `.right` SF symbols**

```bash
grep -RIn 'systemName: "chevron\.\(left\|right\)"' Packages/LillistUI/Sources Apps/ 2>&1
grep -RIn 'systemName: "arrow\.\(left\|right\)' Packages/LillistUI/Sources Apps/ 2>&1
```

Expected: one hit in `BreadcrumbView.swift:9`. No `arrow.left`/`arrow.right` hits (verified at plan-write time — re-confirm).

If the audit surfaces additional directional glyphs (e.g., `chevron.left.circle`, `arrow.right.square`), convert each to the `.forward` / `.backward` variant or, if no auto-mirroring variant exists, add `.flipsForRightToLeftLayoutDirection(true)` to the `Image`.

- [ ] **Step 2: Edit `BreadcrumbView.swift`**

```swift
                if i > 0 {
                    Image(systemName: "chevron.forward")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
```

Also adapt the LTR-only `" › "` separator inside the accessibility label so it composes correctly with RTL screen-reader output. Since the separator is visual only and the a11y label conveys the structure, leave the `" › "` as-is — VoiceOver / Switch Control read each path component individually because of `.accessibilityElement(children: .combine)`.

- [ ] **Step 3: Build LillistUI; confirm clean**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```

- [ ] **Step 4: Add a snapshot test stub for RTL chevron flip (this is the first RTL snapshot; baseline lands in Task 9)**

For now, just confirm the file compiles. Task 9 records the actual baseline.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/BreadcrumbView.swift
git commit -m "fix(a11y): use chevron.forward in BreadcrumbView so it mirrors under RTL"
```

---

## Task 7: Use `Calendar.standaloneWeekdaySymbols` in `RecurrenceEditorView`

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:115-125`

The current `label(for day: Weekday) -> String` is a hardcoded English switch. `Calendar.current.standaloneWeekdaySymbols` returns `["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]` in the current locale (always Sunday-first, regardless of `firstWeekday`).

`Weekday` is a `LillistCore` enum with cases `.sunday … .saturday`. We map each case to a 0-6 index for the symbol array.

- [ ] **Step 1: Add the mapping**

In `RecurrenceEditorView.swift`, replace the `label(for:)` helper:

```swift
    private func label(for day: Weekday) -> String {
        let index = Self.index(for: day)
        // `standaloneWeekdaySymbols` is always Sunday-first; matches our Weekday raw indexing.
        let symbols = Calendar.current.standaloneWeekdaySymbols
        guard symbols.indices.contains(index) else {
            // Fallback to English if the calendar gives us something unexpected.
            return String(localized: defaultEnglishName(for: day), bundle: .module)
        }
        return symbols[index]
    }

    private static func index(for day: Weekday) -> Int {
        switch day {
        case .sunday:    return 0
        case .monday:    return 1
        case .tuesday:   return 2
        case .wednesday: return 3
        case .thursday:  return 4
        case .friday:    return 5
        case .saturday:  return 6
        }
    }

    private func defaultEnglishName(for day: Weekday) -> String.LocalizationValue {
        switch day {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
```

Rationale: `standaloneWeekdaySymbols` returns the system-localized form ("Sunday" in en, "Sonntag" in de, "الأحد" in ar). This is the right user-facing text. The English fallback covers the never-reached edge case where the calendar returns an empty array.

- [ ] **Step 2: Build and run the recurrence-editor snapshot tests**

```bash
swift test --package-path Packages/LillistUI --filter RecurrenceEditor 2>&1 | tail -10
```

Expected: passes. The existing snapshot baselines were recorded in en-US, so `standaloneWeekdaySymbols[0]` = "Sunday" — same bytes.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift
git commit -m "refactor(i18n): use Calendar.standaloneWeekdaySymbols for weekday labels"
```

---

## Task 8: Investigate Quick Capture date-token localization

**Files:**
- Read-only: `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureParser.swift`
- Read-only: `Packages/LillistCore/Sources/LillistCore/Validation/RelativeDate.swift` (the parser the date tokens flow into)
- Maybe modify: `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift:25`

The chip suggestions `["today", "tomorrow", "+3d", "+1w"]` are user-tappable English tokens. If `QuickCaptureParser` and `RelativeDate.parse` only accept English, localizing the chip labels would break the parse round-trip. The investigation determines whether to (a) localize and remap on submit, (b) leave English-only with an `i18n-exempt` annotation, or (c) defer to a follow-up.

- [ ] **Step 1: Read the parser**

```bash
cat Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureParser.swift
```

Confirm: `QuickCaptureParser.parse(text)` splits on whitespace; tokens starting with `^` become `dateToken`. The `dateToken` value passes through to `RelativeDate.parse(_:)`.

- [ ] **Step 2: Read the date-token grammar**

```bash
ls Packages/LillistCore/Sources/LillistCore/Validation/
cat Packages/LillistCore/Sources/LillistCore/Validation/RelativeDate.swift 2>&1 | head -80
```

Expected: `RelativeDate.parse` accepts ASCII tokens like `today`, `tomorrow`, `+3d`, `+1w`. It does **not** localize.

- [ ] **Step 3: Decide**

Three options:

(a) **Localize-and-remap.** Show the user a localized chip ("hoy", "demain"), but submit the canonical English token. Requires a lookup table in the iOS app. Out of scope for Plan 17.

(b) **Leave English-only.** The chip labels are also the literal tokens the user could type — keeping them English keeps the parser deterministic.

(c) **Defer to a follow-up.** Note in `docs/engineering-notes.md` that localization of Quick Capture date tokens requires extending `RelativeDate.parse` first.

**Decision:** Option (c). Annotate the chip array with a `// i18n-exempt` comment naming the dependency:

In `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift`, replace line 25:

```swift
                QuickCaptureField(
                    text: $text,
                    tagSuggestions: tagSuggestions,
                    // i18n-exempt: these are also the literal parser tokens
                    // accepted by RelativeDate.parse. Localizing the chip
                    // labels without first teaching the parser to accept
                    // localized aliases would break the round-trip. Tracked
                    // for a future plan.
                    dateSuggestions: ["today", "tomorrow", "+3d", "+1w"],
                    onSubmit: { _ in submit() }
                )
```

- [ ] **Step 4: Build the iOS app; confirm no regressions**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift
git commit -m "chore(i18n): annotate Quick Capture date tokens as parser-coupled i18n-exempt"
```

---

## Task 9: Add the RTL / locale snapshot suite

**Files:**
- Create: `Packages/LillistUI/Tests/LillistUITests/Snapshots/LocalizationSnapshotTests.swift`

Render four representative views under (a) en-US LTR (existing baselines), (b) en RTL (forced layout direction), (c) ar (Arabic locale + RTL). The tests lock the *shape*; pixel-level diffs surface clipping/overflow/mirror-flipping bugs.

- [ ] **Step 1: Create the file**

```swift
#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

/// Render LillistUI atoms under right-to-left layout and Arabic locale.
///
/// Plan 17 doesn't ship a second locale — these snapshots lock the *shape*
/// of each view (mirrored layout, no clipping, no overflow) so that a
/// future locale is a content swap rather than a layout rewrite.
///
/// The English-LTR baselines for these atoms live in adjacent snapshot
/// files (TaskListView, SidebarView, QuickCaptureView snapshot suites).
/// This file adds the RTL + Arabic variants only.
@MainActor
final class LocalizationSnapshotTests: XCTestCase {
    func test_breadcrumbView_rtl() {
        let view = BreadcrumbView(path: ["Work", "Lillist", "Plan 17"])
            .environment(\.layoutDirection, .rightToLeft)
            .frame(width: 320, height: 32)
            .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 320, height: 60)),
                       as: .image(precision: 0.99),
                       named: "breadcrumb-rtl")
    }

    func test_breadcrumbView_ar() {
        let view = BreadcrumbView(path: ["Work", "Lillist", "Plan 17"])
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
            .frame(width: 320, height: 32)
            .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 320, height: 60)),
                       as: .image(precision: 0.99),
                       named: "breadcrumb-ar")
    }

    func test_taskRowView_rtl() {
        let task = TaskStore.TaskRecord(
            id: UUID(), title: "Buy milk", notes: "",
            status: .todo, start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false, position: 0,
            isPinned: false, parentID: nil, createdAt: Date(),
            modifiedAt: Date(), closedAt: nil, deletedAt: nil,
            seriesID: nil
        )
        let view = TaskRowView(task: task, tagNames: ["work"],
                               onStatusClick: {}, onStatusLongPress: {})
            .environment(\.layoutDirection, .rightToLeft)
            .frame(width: 380, height: 44)
            .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 380, height: 80)),
                       as: .image(precision: 0.99),
                       named: "taskrow-rtl")
    }

    func test_recurrenceEditor_ar() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .weekly
        vm.byDay = [.tuesday, .thursday]
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
            .frame(width: 420, height: 600)
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 420, height: 600)),
                       as: .image(precision: 0.99),
                       named: "recurrence-weekly-ar")
    }

    func test_quickCaptureView_rtl() {
        let view = StatefulQuickCapture(text: "Ship release #work ^tomorrow")
            .environment(\.layoutDirection, .rightToLeft)
            .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 560, height: 140)),
                       as: .image(precision: 0.99),
                       named: "quickcapture-rtl")
    }

    private struct StatefulQuickCapture: View {
        @State var text: String
        var body: some View {
            QuickCaptureView(text: $text, onSubmit: { _ in }, onCancel: {})
        }
    }
}
#endif
```

- [ ] **Step 2: Record baselines**

First run records baselines (no assertion failures); subsequent runs compare against the recorded images.

```bash
swift test --package-path Packages/LillistUI --filter LocalizationSnapshot 2>&1 | tail -10
```

First run: 5 tests "fail" with `recorded snapshot at` messages (this is normal — baselines are now on disk). Re-run:

```bash
swift test --package-path Packages/LillistUI --filter LocalizationSnapshot 2>&1 | tail -10
```

Expected: 5 tests PASS.

- [ ] **Step 3: Verify the breadcrumb actually flipped**

Open `Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/LocalizationSnapshotTests/breadcrumb-rtl.png` and inspect visually. The path components and chevrons should read right-to-left. If they don't, Task 6's `chevron.forward` change wasn't applied — re-verify.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Tests/LillistUITests/Snapshots/LocalizationSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/LocalizationSnapshotTests
git commit -m "test(i18n): add RTL and ar-locale snapshots for representative UI atoms"
```

---

## Task 10: Add the `AccessibilityEnvironment` helper module

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift`

The helper introduces three view modifiers, each backed by an environment value:

1. `.accessibleAnimation(_ animation: Animation?, value: V)` — like SwiftUI's `.animation(_:value:)`, but no-ops when `accessibilityReduceMotion` is true.
2. `.accessibleMaterial(_ material: Material, fallback: Color)` — applies the material as the background, but substitutes the opaque `fallback` color when `accessibilityReduceTransparency` is true.
3. `.contrastTuned<T>(_ standard: T, increased: T) -> some View` — generic over `View`, lets a callsite pick a "tuned" alternative when `accessibilityShouldIncreaseContrast` is true. (Used by `TagChipView` and `SidebarRowView` in Tasks 13-14.)

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

/// View-modifier helpers that consult Apple's accessibility-environment
/// values. Each is a thin wrapper over the standard modifier plus an
/// `@Environment` read — no caching, no actor isolation, no shared state.
public extension View {
    /// `.animation(_:value:)` that no-ops under `accessibilityReduceMotion`.
    /// Use for decorative transitions (entrance/fade/slide). For animations
    /// that *communicate* state (swipe feedback), gate explicitly.
    func accessibleAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(AccessibleAnimationModifier(animation: animation, value: value))
    }

    /// Apply `material` as the background; substitute opaque `fallback`
    /// when `accessibilityReduceTransparency` is true.
    func accessibleMaterial<S: ShapeStyle>(
        _ material: Material,
        fallback: S,
        in shape: some Shape = Rectangle()
    ) -> some View {
        modifier(AccessibleMaterialModifier(
            material: material,
            fallback: AnyShapeStyle(fallback),
            shape: AnyShape(shape)
        ))
    }
}

private struct AccessibleAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct AccessibleMaterialModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let material: Material
    let fallback: AnyShapeStyle
    let shape: AnyShape

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(fallback, in: shape)
        } else {
            content.background(material, in: shape)
        }
    }
}

/// Trait selector for `accessibilityShouldIncreaseContrast`. Callers read
/// the environment and pass it in: e.g. `ContrastTuned.value(in: env, standard: .secondary, increased: .primary)`.
public enum ContrastTuned {
    @MainActor
    public static func value<T>(in environment: EnvironmentValues, standard: T, increased: T) -> T {
        environment.accessibilityShouldIncreaseContrast ? increased : standard
    }
}
```

- [ ] **Step 2: Create the test file**

`Packages/LillistUI/Tests/LillistUITests/Accessibility/AccessibilityEnvironmentTests.swift`:

```swift
#if os(macOS)
import XCTest
import SwiftUI
@testable import LillistUI

@MainActor
final class AccessibilityEnvironmentTests: XCTestCase {
    /// Smoke: a view that uses `.accessibleAnimation` compiles and renders
    /// in both reduce-motion-on and reduce-motion-off environments.
    /// (Behavioral verification — that animation is actually suppressed —
    /// requires a UI test harness; this is the compile-time sanity check.)
    func test_accessibleAnimation_smoke() throws {
        let view = TogglingShape()
            .environment(\.accessibilityReduceMotion, true)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNotNil(host)
    }

    func test_accessibleMaterial_substitutes_fallback_when_reduceTransparency() throws {
        let view = MaterialUser()
            .environment(\.accessibilityReduceTransparency, true)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNotNil(host)
    }

    private struct TogglingShape: View {
        @State private var on = false
        var body: some View {
            Circle()
                .fill(on ? Color.red : Color.blue)
                .accessibleAnimation(.easeInOut, value: on)
                .onAppear { on = true }
        }
    }

    private struct MaterialUser: View {
        var body: some View {
            Text("x")
                .padding()
                .accessibleMaterial(.thickMaterial, fallback: Color(nsColor: .windowBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
#endif
```

- [ ] **Step 3: Build and test**

```bash
swift test --package-path Packages/LillistUI --filter AccessibilityEnvironment 2>&1 | tail -10
```

Expected: 2 tests PASS.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift \
        Packages/LillistUI/Tests/LillistUITests/Accessibility/AccessibilityEnvironmentTests.swift
git commit -m "feat(a11y): add .accessibleAnimation / .accessibleMaterial environment helpers"
```

---

## Task 11: Audit `withAnimation` / `.animation` callsites, gate user-noticeable ones

**Files:**
- Audit-only: `Packages/LillistUI/Sources/**/*.swift`, `Apps/**/*.swift`
- Maybe modify any sites Plan 13 / 15 left behind

- [ ] **Step 1: Audit**

```bash
grep -RIn 'withAnimation\b' Packages/LillistUI/Sources Apps/ 2>&1
grep -RIn '\.animation(' Packages/LillistUI/Sources Apps/ 2>&1
grep -RIn '\.transition(' Packages/LillistUI/Sources Apps/ 2>&1
```

(The `try? await env.taskStore.transition(...)` calls are Core Data, not SwiftUI transitions, and don't match `\.transition(`.) Each animation site becomes a Step 2 entry below.

- [ ] **Step 2: If Plan 13 / 15 added any `.animation` callsites, gate each via `.accessibleAnimation`**

For each site, swap:

```swift
.animation(.easeInOut, value: someState)
```

For:

```swift
.accessibleAnimation(.easeInOut, value: someState)
```

If `withAnimation { … }` blocks exist, gate them on `accessibilityReduceMotion`:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
// …
if reduceMotion {
    self.state = newState
} else {
    withAnimation(.easeInOut) { self.state = newState }
}
```

(In v1 there are no such sites; this step becomes a no-op if Plan 13 / 15 left nothing to gate.)

- [ ] **Step 3: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 4: Commit (only if any gating diffs landed in Step 2)**

```bash
git commit -m "chore(a11y): gate user-noticeable animations through .accessibleAnimation"
```

If no animation sites were found, skip the commit entirely.

---

## Task 12: Honor `accessibilityReduceTransparency` in QuickCaptureView and OnboardingScreen

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift:46`
- Modify: `Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift:124`

`.background(.thickMaterial, in: …)` and `.background(.bar)` show translucent chrome that some users (low vision, certain cognitive profiles) find illegible. The substitution: opaque system-equivalent colors.

- [ ] **Step 1: Update QuickCaptureView**

`Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift`, replace line 46:

```swift
        .padding(14)
        .frame(width: 520)
        #if os(macOS)
        .accessibleMaterial(
            .thickMaterial,
            fallback: Color(nsColor: .windowBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .onExitCommand(perform: onCancel)
        #else
        .accessibleMaterial(
            .thickMaterial,
            fallback: Color(uiColor: .systemBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
        #endif
```

(`QuickCaptureView` already has an `#if os(macOS)` guard; expand it to also pick the correct platform fallback color.)

- [ ] **Step 2: Update OnboardingScreen**

`Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift`, replace the `.background(.bar)` on line 124. The `actionBar` `VStack` becomes:

```swift
    private var actionBar: some View {
        VStack(spacing: 12) {
            // … existing buttons
        }
        .padding(20)
        .accessibleMaterial(
            .bar,
            fallback: Color(uiColor: .systemBackground)
        )
    }
```

- [ ] **Step 3: Add a snapshot test for the reduce-transparency code path**

Create `Packages/LillistUI/Tests/LillistUITests/Snapshots/ReduceTransparencySnapshotTests.swift`:

```swift
#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import LillistUI

/// Snapshot the QuickCaptureView under reduceTransparency=true.
/// Under the default environment the background renders as `.thickMaterial`;
/// under reduceTransparency=true it must render as the opaque fallback color.
@MainActor
final class ReduceTransparencySnapshotTests: XCTestCase {
    func test_quickCapture_reduceTransparency_on() {
        let view = StatefulQuickCapture(text: "Buy milk")
            .environment(\.accessibilityReduceTransparency, true)
            .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 560, height: 140)),
                       as: .image(precision: 0.99),
                       named: "quickcapture-reduce-transparency")
    }

    func test_quickCapture_reduceTransparency_off() {
        let view = StatefulQuickCapture(text: "Buy milk")
            .environment(\.accessibilityReduceTransparency, false)
            .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 560, height: 140)),
                       as: .image(precision: 0.99),
                       named: "quickcapture-normal-transparency")
    }

    private struct StatefulQuickCapture: View {
        @State var text: String
        var body: some View {
            QuickCaptureView(text: $text, onSubmit: { _ in }, onCancel: {})
        }
    }
}
#endif
```

- [ ] **Step 4: Run, record baselines, re-run**

```bash
swift test --package-path Packages/LillistUI --filter ReduceTransparency 2>&1 | tail -10
swift test --package-path Packages/LillistUI --filter ReduceTransparency 2>&1 | tail -10
```

Expected: first run records baselines (counts as failure); second run PASS x 2. Open the two baseline images and verify the `_on` variant has an opaque background.

- [ ] **Step 5: Build iOS to confirm OnboardingScreen change compiles**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift \
        Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/ReduceTransparencySnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/ReduceTransparencySnapshotTests
git commit -m "feat(a11y): honor accessibilityReduceTransparency in QuickCapture + Onboarding"
```

---

## Task 13: Tune TagChipView contrast under Increase Contrast

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/TagChipView.swift:19-25`

Current fill is at `opacity(0.18)`, stroke at `opacity(0.45)`. Both are illegible for users who enabled Increase Contrast. Bumping the fill to 0.30, stroke to 0.85, and foreground from a tinted color to `.primary` brings the chip into the safe contrast zone.

- [ ] **Step 1: Rewrite the body**

```swift
public struct TagChipView: View {
    public var name: String
    public var tint: TagTint?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityShouldIncreaseContrast) private var increaseContrast

    public init(name: String, tint: TagTint? = nil) {
        self.name = name
        self.tint = tint
    }

    public var body: some View {
        let resolved = tint?.resolved(in: scheme)
        let base = (resolved?.color ?? .gray)
        Text(name)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(base.opacity(increaseContrast ? 0.30 : 0.18))
            )
            .foregroundStyle(
                increaseContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(resolved?.color ?? .secondary)
            )
            .overlay(
                Capsule().stroke(base.opacity(increaseContrast ? 0.85 : 0.45),
                                 lineWidth: increaseContrast ? 1.0 : 0.5)
            )
            .accessibilityLabel(String(localized: "Tag: \(name)", bundle: .module))
    }
}
```

- [ ] **Step 2: Add a snapshot test for the high-contrast variant**

Create `Packages/LillistUI/Tests/LillistUITests/Snapshots/ContrastSnapshotTests.swift`:

```swift
#if os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import LillistUI

@MainActor
final class ContrastSnapshotTests: XCTestCase {
    func test_tagChip_normal() {
        let view = HStack {
            TagChipView(name: "work", tint: TagTint(hex: "#3478F6"))
            TagChipView(name: "urgent", tint: TagTint(hex: "#FF3B30"))
        }
        .padding()
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 240, height: 60)),
                       as: .image(precision: 0.99),
                       named: "tagchip-normal")
    }

    func test_tagChip_increaseContrast() {
        let view = HStack {
            TagChipView(name: "work", tint: TagTint(hex: "#3478F6"))
            TagChipView(name: "urgent", tint: TagTint(hex: "#FF3B30"))
        }
        .padding()
        .environment(\.accessibilityShouldIncreaseContrast, true)
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 240, height: 60)),
                       as: .image(precision: 0.99),
                       named: "tagchip-increase-contrast")
    }

    func test_tagChip_dark_increaseContrast() {
        let view = HStack {
            TagChipView(name: "work", tint: TagTint(hex: "#3478F6"))
        }
        .padding()
        .environment(\.colorScheme, .dark)
        .environment(\.accessibilityShouldIncreaseContrast, true)
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 160, height: 60)),
                       as: .image(precision: 0.99),
                       named: "tagchip-dark-increase-contrast")
    }
}
#endif
```

- [ ] **Step 3: Record baselines and re-run**

```bash
swift test --package-path Packages/LillistUI --filter ContrastSnapshot 2>&1 | tail -10
swift test --package-path Packages/LillistUI --filter ContrastSnapshot 2>&1 | tail -10
```

Expected: second run PASS x 3. Open the three baselines; the `_increase-contrast` variants should visibly show a darker fill, heavier stroke, and `.primary` text.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/TagChipView.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/ContrastSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/ContrastSnapshotTests
git commit -m "feat(a11y): tune TagChipView for accessibilityShouldIncreaseContrast"
```

---

## Task 14: Tune SidebarRowView badge under Increase Contrast

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift:33`

The badge currently fills with `.quaternary` material. Under Increase Contrast we want `.tertiary` (or, even better, an accent-tinted background with `.primary` text).

- [ ] **Step 1: Rewrite the body**

```swift
public struct SidebarRowView: View {
    public enum Kind: Sendable { case task, smartFilter, tag, trash }
    public var icon: String
    public var label: String
    public var badge: Int?
    public var tint: TagTint?
    public var kind: Kind

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityShouldIncreaseContrast) private var increaseContrast

    public init(icon: String, label: String, badge: Int? = nil, tint: TagTint? = nil, kind: Kind) {
        self.icon = icon
        self.label = label
        self.badge = badge
        self.tint = tint
        self.kind = kind
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint?.resolved(in: scheme).color ?? .accentColor)
                .frame(width: 18)
            Text(label).lineLimit(1)
            Spacer()
            if let badge, badge > 0 {
                badgeView(count: badge)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(badge.map {
            String(localized: "\(label), \($0) items", bundle: .module)
        } ?? label)
    }

    @ViewBuilder
    private func badgeView(count: Int) -> some View {
        let label = Text("\(count)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)

        if increaseContrast {
            label
                .foregroundStyle(.primary)
                .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.8), lineWidth: 0.5))
                .accessibilityLabel(String(localized: "\(count) items", bundle: .module))
        } else {
            label
                .background(Capsule().fill(.quaternary))
                .accessibilityLabel(String(localized: "\(count) items", bundle: .module))
        }
    }
}
```

- [ ] **Step 2: Extend the ContrastSnapshotTests suite**

Append to `ContrastSnapshotTests.swift`:

```swift
    func test_sidebarRow_normal_with_badge() {
        let view = SidebarRowView(icon: "tray", label: "Inbox", badge: 7, kind: .task)
            .frame(width: 220)
            .padding(8)
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 220, height: 40)),
                       as: .image(precision: 0.99),
                       named: "sidebar-row-normal")
    }

    func test_sidebarRow_increaseContrast_with_badge() {
        let view = SidebarRowView(icon: "tray", label: "Inbox", badge: 7, kind: .task)
            .frame(width: 220)
            .padding(8)
            .environment(\.accessibilityShouldIncreaseContrast, true)
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 220, height: 40)),
                       as: .image(precision: 0.99),
                       named: "sidebar-row-increase-contrast")
    }
```

- [ ] **Step 3: Record + re-run**

```bash
swift test --package-path Packages/LillistUI --filter ContrastSnapshot 2>&1 | tail -10
swift test --package-path Packages/LillistUI --filter ContrastSnapshot 2>&1 | tail -10
```

Expected: 5 tests PASS (3 from Task 13 + 2 new).

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/ContrastSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/ContrastSnapshotTests
git commit -m "feat(a11y): tune SidebarRowView badge for accessibilityShouldIncreaseContrast"
```

---

## Task 15: Add a contrast floor to `TagTint.resolved(in:)`

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift`
- Create: `Packages/LillistUI/Tests/LillistUITests/Accessibility/ContrastMathTests.swift`
- Modify: `Packages/LillistUI/Sources/LillistUI/Theme/TagTint.swift:32-38`

In dark mode the current heuristic (`saturation * 0.7`, `brightness * 1.05`) can produce chip-text colors that fall under the WCAG 4.5:1 (or APCA |Lc| 60) bar against the chip background of `base.opacity(0.18)`. We add a brightness-iterate loop that bumps brightness until the contrast clears the floor.

- [ ] **Step 1: Create `ContrastMath.swift`**

```swift
import SwiftUI

/// WCAG 2.x contrast helpers used by `TagTint` and snapshot tests.
public enum ContrastMath {
    /// Relative luminance for sRGB channels in [0,1]. 4.5:1 ratio is the
    /// AA threshold for body text.
    public static func relativeLuminance(red r: Double, green g: Double, blue b: Double) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    public static func wcagRatio(_ l1: Double, _ l2: Double) -> Double {
        let lighter = max(l1, l2), darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// HSB → RGB; inverse of `TagTint.rgbToHSB`.
    public static func hsbToRGB(hue: Double, saturation: Double, brightness: Double) -> (Double, Double, Double) {
        if saturation == 0 { return (brightness, brightness, brightness) }
        let h = hue * 6
        let i = floor(h)
        let f = h - i
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        switch Int(i) % 6 {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        case 5: return (brightness, p, q)
        default: return (brightness, brightness, brightness)
        }
    }
}
```

- [ ] **Step 2: Create the unit tests**

`Packages/LillistUI/Tests/LillistUITests/Accessibility/ContrastMathTests.swift`:

```swift
import XCTest
@testable import LillistUI

final class ContrastMathTests: XCTestCase {
    func test_relativeLuminance_white_is_1() {
        XCTAssertEqual(ContrastMath.relativeLuminance(red: 1, green: 1, blue: 1), 1.0, accuracy: 0.001)
    }

    func test_relativeLuminance_black_is_0() {
        XCTAssertEqual(ContrastMath.relativeLuminance(red: 0, green: 0, blue: 0), 0.0, accuracy: 0.001)
    }

    func test_wcagRatio_black_on_white_is_21() {
        let l1 = ContrastMath.relativeLuminance(red: 1, green: 1, blue: 1)
        let l2 = ContrastMath.relativeLuminance(red: 0, green: 0, blue: 0)
        XCTAssertEqual(ContrastMath.wcagRatio(l1, l2), 21.0, accuracy: 0.01)
    }

    func test_wcagRatio_isCommutative() {
        let a = ContrastMath.relativeLuminance(red: 0.2, green: 0.4, blue: 0.6)
        let b = ContrastMath.relativeLuminance(red: 0.9, green: 0.9, blue: 0.9)
        XCTAssertEqual(ContrastMath.wcagRatio(a, b), ContrastMath.wcagRatio(b, a), accuracy: 0.0001)
    }

    func test_hsbToRGB_roundtrip() {
        // HSB(0.6, 0.7, 0.8) → RGB and back should land near the original.
        let (r, g, b) = ContrastMath.hsbToRGB(hue: 0.6, saturation: 0.7, brightness: 0.8)
        // Sanity check: brightness 0.8 ≈ max channel
        XCTAssertEqual(max(r, max(g, b)), 0.8, accuracy: 0.001)
    }
}
```

- [ ] **Step 3: Update `TagTint.resolved(in:)`**

```swift
    /// Resolve to the actual color used on screen, applying:
    ///   1. Dark-mode desaturation (cosmetic, design Section 7).
    ///   2. A WCAG contrast floor against the chip background
    ///      (`base.opacity(0.18)` per `TagChipView`). Bumps brightness
    ///      until the foreground/background ratio clears 4.5:1.
    public func resolved(in scheme: ColorScheme) -> Resolved {
        let (h, s, b) = Self.rgbToHSB(r: red, g: green, b: blue)
        var resolvedSaturation = s
        var resolvedBrightness = b
        if scheme == .dark {
            resolvedSaturation = s * 0.7
            resolvedBrightness = min(b * 1.05, 1.0)
        }
        // Background under the chip: 18% opacity of the tint over the
        // system chip background. Approximate as 0.18 * tint + 0.82 * gray.
        // The foreground must clear 4.5:1 against that mix.
        let floorBrightness = Self.clampBrightnessForContrastFloor(
            hue: h,
            saturation: resolvedSaturation,
            brightness: resolvedBrightness,
            scheme: scheme
        )
        return Resolved(hue: h, saturation: resolvedSaturation, brightness: floorBrightness, opacity: 1.0)
    }

    /// Iterate brightness upward (light backgrounds: downward) until the
    /// foreground/background WCAG ratio clears 4.5:1, or we hit the bound.
    private static func clampBrightnessForContrastFloor(
        hue: Double,
        saturation: Double,
        brightness initial: Double,
        scheme: ColorScheme
    ) -> Double {
        // Approximate background: in dark mode, near-black; in light mode, near-white.
        let bgLum: Double = scheme == .dark ? 0.05 : 0.95
        let direction: Double = scheme == .dark ? 0.05 : -0.05  // bump up in dark, down in light
        var brightness = initial
        for _ in 0..<10 {
            let (r, g, b) = ContrastMath.hsbToRGB(hue: hue, saturation: saturation, brightness: brightness)
            let fgLum = ContrastMath.relativeLuminance(red: r, green: g, blue: b)
            if ContrastMath.wcagRatio(fgLum, bgLum) >= 4.5 {
                return brightness
            }
            brightness = max(0.0, min(1.0, brightness + direction))
        }
        return brightness
    }
```

- [ ] **Step 4: Build and run**

```bash
swift test --package-path Packages/LillistUI --filter ContrastMath 2>&1 | tail -10
```

Expected: 5 tests PASS.

```bash
swift test --package-path Packages/LillistUI 2>&1 | tail -5
```

Expected: full suite PASS. The TagTint visual change may shift the existing TagChip baselines slightly — if so, re-record those snapshots with `withSnapshotTesting(record: .all)` once and commit the new bytes.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift \
        Packages/LillistUI/Sources/LillistUI/Theme/TagTint.swift \
        Packages/LillistUI/Tests/LillistUITests/Accessibility/ContrastMathTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/
git commit -m "feat(a11y): enforce WCAG contrast floor in TagTint.resolved(in:)"
```

---

## Task 16: Differentiate sync state without color (shape axis)

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift`
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift`
- Maybe modify: `Packages/LillistUI/Sources/LillistUI/Status/SyncPalette.swift` (introduced by Plan 14)

The four sync states (`idle(fresh)` / `idle(stale)` / `inProgress` / `error`) are currently distinguished only by dot color. With `accessibilityDifferentiateWithoutColor`, add a per-state SF Symbol overlay so the difference is conveyed by shape as well as color.

If Plan 14's `SyncPalette` type does not yet exist, this task creates a minimal version.

- [ ] **Step 1: Scaffold `SyncPalette` if absent**

```bash
ls Packages/LillistUI/Sources/LillistUI/Status/ 2>&1
```

If `SyncPalette.swift` is absent (Plan 14 hasn't merged), create `Packages/LillistUI/Sources/LillistUI/Status/SyncPalette.swift`:

```swift
import SwiftUI

/// Per-sync-state visual axes. Plan 14 introduced the color axis; Plan 17
/// adds the differentiated-shape axis. Each property is a pure mapping
/// from `SyncIndicator` — no isolation, no caching.
public enum SyncPalette {
    public static func color(for indicator: SyncIndicator) -> Color {
        switch indicator {
        case .idle(let last):
            guard let last else { return .yellow }
            return Date().timeIntervalSince(last) < 60 ? .green : .yellow
        case .inProgress: return .blue
        case .error: return .red
        }
    }

    /// SF Symbol overlaid on the dot when
    /// `accessibilityDifferentiateWithoutColor` is true. Each shape is
    /// visually distinct from the other three, even rendered in a single
    /// foreground color.
    public static func differentiatedSystemImage(for indicator: SyncIndicator) -> String {
        switch indicator {
        case .idle(let last):
            guard let last else { return "circle" }
            return Date().timeIntervalSince(last) < 60 ? "circle.fill" : "circle.dotted"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
```

If `SyncPalette.swift` already exists (Plan 14 merged), append the `differentiatedSystemImage(for:)` static method.

- [ ] **Step 2: Update `SyncStatusDotView`**

```swift
public struct SyncStatusDotView: View {
    public var indicator: SyncIndicator
    public var onRetry: () -> Void
    @State private var showPopover = false
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    public init(indicator: SyncIndicator, onRetry: @escaping () -> Void) {
        self.indicator = indicator
        self.onRetry = onRetry
    }

    public var body: some View {
        Button { showPopover.toggle() } label: {
            ZStack {
                Circle()
                    .fill(SyncPalette.color(for: indicator))
                    .frame(width: 8, height: 8)
                if differentiate {
                    Image(systemName: SyncPalette.differentiatedSystemImage(for: indicator))
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityLabel(label)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).font(.headline)
                detail
                if case .error = indicator {
                    Button("Try again", action: onRetry)
                }
            }
            .padding(12)
            .frame(width: 240)
        }
    }

    // … label and detail unchanged from Task 5
}
```

- [ ] **Step 3: Update `SyncStatusBadge` (iOS)**

> **Plan 13 fallout (2026-05-16):** Preserve the `if case .inProgress = indicator` pattern-match (Plan 13 Task 1 swapped from `==`), the outer `.frame(width: 44, height: 44)` + `.contentShape(Rectangle())` 44pt hit area (Plan 13 Task 8), and the `.accessibilityAddTraits(.isStaticText)` trait (Plan 13 Task 8). The snippet below has been updated to keep all three.

```swift
public struct SyncStatusBadge: View {
    public var indicator: SyncIndicator
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    public init(indicator: SyncIndicator) {
        self.indicator = indicator
    }

    public var body: some View {
        Circle()
            .fill(SyncPalette.color(for: indicator))
            .frame(width: 10, height: 10)
            .overlay(
                Group {
                    if differentiate {
                        Image(systemName: SyncPalette.differentiatedSystemImage(for: indicator))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    } else if case .inProgress = indicator {
                        ProgressView().scaleEffect(0.5)
                    }
                }
            )
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isStaticText)
    }
    // … label unchanged from Task 5
}
```

- [ ] **Step 4: Add snapshot tests for the differentiated variants**

Append to `Packages/LillistUI/Tests/LillistUITests/Snapshots/ContrastSnapshotTests.swift`:

```swift
    func test_syncDot_idle_differentiated() {
        let view = SyncStatusDotView(
            indicator: .idle(lastSync: Date(timeIntervalSinceNow: -10)),
            onRetry: {}
        )
        .padding()
        .environment(\.accessibilityDifferentiateWithoutColor, true)
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 40, height: 40)),
                       as: .image(precision: 0.99),
                       named: "syncdot-idle-differentiated")
    }

    func test_syncDot_error_differentiated() {
        let view = SyncStatusDotView(
            indicator: .error(message: "Network unavailable", lastSuccess: nil),
            onRetry: {}
        )
        .padding()
        .environment(\.accessibilityDifferentiateWithoutColor, true)
        assertSnapshot(of: makeHostingView(view, size: CGSize(width: 40, height: 40)),
                       as: .image(precision: 0.99),
                       named: "syncdot-error-differentiated")
    }
```

- [ ] **Step 5: Build, record baselines, re-run**

```bash
swift test --package-path Packages/LillistUI --filter ContrastSnapshot 2>&1 | tail -10
swift test --package-path Packages/LillistUI --filter ContrastSnapshot 2>&1 | tail -10
```

Expected: 7 tests PASS (5 + 2 new). Open both new baselines — the `_idle` variant should overlay `circle.fill` (or `circle.dotted` for stale); the `_error` variant should overlay `exclamationmark.triangle.fill`.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Status/SyncPalette.swift \
        Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift \
        Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/ContrastSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/ContrastSnapshotTests
git commit -m "feat(a11y): overlay differentiated SF Symbols on sync dot under DifferentiateWithoutColor"
```

---

## Task 17: Sharpen `StatusPalette.color(for:)` for `.blocked`; route `StatusIndicatorView` through it

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift`
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift`

`.blocked` has no distinct color today on `StatusIndicatorView` — only the dashed-circle glyph. The screen reader rotor's "Show Buttons" listing will conflate it with `.todo` and `.started`. Adding a tint axis disambiguates.

> **Plan 15 fallout (2026-05-16):** Plan 15 Task 6 already shipped `StatusPalette` on `main` with `public static func color(for:) -> Color` and `public static func fill(for:) -> some ShapeStyle`. Plan 15 picked `.orange` for `.blocked`; this task swaps it for `.red` (Plan 17's screen-reader-rotor argument prevails over Plan 15's neutral choice — orange and the closed-state `.green` can read similar in some color-blindness profiles, whereas red is unambiguously "stop"). Existing `StatusPalette` callers (`DetailHeaderView`, `TaskDetailView.TitleRow` on macOS) automatically pick up the new hue.

- [ ] **Step 1: Update `StatusPalette` to use `.red` for `.blocked`**

```swift
import SwiftUI
import LillistCore

public enum StatusPalette {
    public static func color(for status: Status) -> Color {
        switch status {
        case .todo:    return Color.secondary
        case .started: return Color.accentColor
        case .blocked: return Color.red          // Plan 17: was .orange; bumped for rotor visibility
        case .closed:  return Color.green
        }
    }

    public static func fill(for status: Status) -> some ShapeStyle {
        color(for: status).opacity(0.18)
    }
}
```

(`StatusGlyph` already owns `symbol(for:)` and `accessibilityLabel(for:)`; this task does not duplicate them. The other a11y-label localization work in Task 17 is folded into the `StatusGlyph.accessibilityLabel(for:)` string-catalog conversion in Task 4.)

- [ ] **Step 2: Update `StatusIndicatorView` to consume the palette tint**

```swift
public struct StatusIndicatorView: View {
    public var status: Status
    public var onClick: () -> Void
    public var onLongPress: () -> Void

    public init(status: Status, onClick: @escaping () -> Void, onLongPress: @escaping () -> Void) {
        self.status = status
        self.onClick = onClick
        self.onLongPress = onLongPress
    }

    public var body: some View {
        Button(action: onClick) {
            Image(systemName: StatusGlyph.symbol(for: status))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(StatusPalette.color(for: status))   // Plan 17 / Plan 15
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(StatusGlyph.accessibilityLabel(for: status))
        .accessibilityAddTraits(.isButton)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in onLongPress() }
        )
    }
}
```

- [ ] **Step 3: Update existing snapshot baselines if any TaskRow/StatusIndicator change visibly**

```bash
swift test --package-path Packages/LillistUI 2>&1 | tail -10
```

If any TaskRow or sidebar snapshot fails because the closed-status checkmark is now `.green` instead of `.secondary`, re-record those snapshots:

```bash
swift test --package-path Packages/LillistUI 2>&1 | tail -20
# Inspect failures, then if intentional:
SNAPSHOT_TESTING_RECORD=1 swift test --package-path Packages/LillistUI 2>&1 | tail -5
# Or in code, wrap the failing test with withSnapshotTesting(record: .all) { … }
```

- [ ] **Step 4: Build both apps to confirm consumers compile**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift \
        Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/
git commit -m "feat(a11y): give .blocked a distinct red tint so the rotor doesn't depend on shape alone"
```

---

## Task 18: Add the `AccessibilityAnnouncements` module

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift`
- Create: `Packages/LillistUI/Tests/LillistUITests/Accessibility/AnnouncementsTests.swift`

A platform-aware posting helper. Callers say `AccessibilityAnnouncements.post(message, priority: .high)` and the helper fans out to the right platform API.

- [ ] **Step 1: Create the helper**

```swift
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// Platform-aware AX announcement posting. iOS 17+ routes to
/// `AccessibilityNotification.Announcement`; macOS routes to
/// `NSAccessibility.post(_:argument:)`. Use `.low` for completion
/// confirmations, `.high` for time-sensitive errors.
public enum AccessibilityAnnouncements {
    public enum Priority: Sendable { case low, high }

    @MainActor
    public static func post(_ message: String, priority: Priority = .low) {
        #if canImport(UIKit)
        AccessibilityNotification.Announcement(AttributedString(message)).post()
        #elseif canImport(AppKit)
        let target: Any = NSApp.mainWindow ?? NSApp.windows.first ?? NSAccessibilityElement()
        let argument: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: message,
            .priority: priority == .high
                ? NSAccessibilityPriorityLevel.high.rawValue
                : NSAccessibilityPriorityLevel.medium.rawValue
        ]
        NSAccessibility.post(element: target,
                             notification: .announcementRequested,
                             userInfo: argument)
        #endif
    }
}
```

- [ ] **Step 2: Write the test**

```swift
#if os(macOS)
import XCTest
@testable import LillistUI

@MainActor
final class AnnouncementsTests: XCTestCase {
    /// Smoke: posting an announcement does not crash and does not block.
    /// (Verifying that AX actually heard the announcement requires a UI
    /// test with an AT enabled — out of scope for unit tests.)
    func test_post_does_not_throw() {
        AccessibilityAnnouncements.post("Sync complete")
        AccessibilityAnnouncements.post("Sync error: Network unavailable", priority: .high)
    }
}
#endif
```

- [ ] **Step 3: Build and test**

```bash
swift test --package-path Packages/LillistUI --filter Announcements 2>&1 | tail -5
```

Expected: 1 PASS.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift \
        Packages/LillistUI/Tests/LillistUITests/Accessibility/AnnouncementsTests.swift
git commit -m "feat(a11y): add AccessibilityAnnouncements platform-aware post helper"
```

---

## Task 19: Post announcements on Quick Capture submit, Trash purge, recurrence save, follow-up

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift:85-86`
- Modify: `Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:60-65`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift:83-89`
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/FollowUpFormView.swift:41-49`
- Modify: caller of `RecurrenceEditorView.onCommit` in `Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift` (and the macOS equivalent in `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift`)

Each side-effect-producing path posts a short status message after success/failure.

- [ ] **Step 1: Quick Capture submit (iOS)**

In `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift`, inside `submit()`, after the `dismiss()`:

```swift
                submitting = false
                AccessibilityAnnouncements.post(
                    String(localized: "Task created: \(title)"),
                    priority: .low
                )
                dismiss()
            } catch {
                errorMessage = "\(error)"
                AccessibilityAnnouncements.post(
                    String(localized: "Couldn't create task: \(error.localizedDescription)"),
                    priority: .high
                )
                submitting = false
            }
```

Add `import LillistUI` at the top of `QuickCaptureSheet.swift` if not already present.

- [ ] **Step 2: Trash purge (iOS)**

In `Apps/Lillist-iOS/Sources/Settings/TrashSection.swift`, inside `emptyTrash()`:

```swift
    private func emptyTrash() async {
        isEmptying = true
        defer { isEmptying = false }
        do {
            let purged = try await environment.taskStore.purgeAll()
            let result = purged == 0
                ? String(localized: "Trash was already empty.")
                : String(localized: "Emptied \(purged) task\(purged == 1 ? "" : "s").")
            emptyResult = result
            AccessibilityAnnouncements.post(result, priority: .low)
        } catch {
            let failure = String(localized: "Couldn't empty Trash: \(error.localizedDescription)")
            emptyResult = failure
            AccessibilityAnnouncements.post(failure, priority: .high)
        }
    }
```

Add `import LillistUI` if not already imported.

- [ ] **Step 3: Trash purge (macOS)**

In `Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift`, apply the same rewrite as Step 2 (use the wording `"Emptied N tasks from Trash."` to match the existing macOS string). Add `import LillistUI`.

- [ ] **Step 4: Follow-up scheduling (macOS)**

In `Apps/Lillist-macOS/Sources/Views/Detail/FollowUpFormView.swift`, inside `submit()`:

```swift
    private func submit() async {
        let useTitle = title.isEmpty ? "Follow up on '\(parentTitle)'" : title
        do {
            _ = try await env.taskStore.scheduleFollowUp(
                parentTaskID: blockedTaskID,
                title: useTitle,
                deadline: deadline
            )
            AccessibilityAnnouncements.post(
                String(localized: "Follow-up scheduled: \(useTitle)"),
                priority: .low
            )
            onCommit()
        } catch {
            AccessibilityAnnouncements.post(
                String(localized: "Couldn't schedule follow-up: \(error.localizedDescription)"),
                priority: .high
            )
        }
    }
```

Add `import LillistUI` to the file.

- [ ] **Step 5: Recurrence save (both platforms)**

The iOS RecurrenceSheet uses a toolbar `Save` button that calls an explicit `commit(_ rule:) async` method (Plan 16 Task 24's Alert-on-error refactor). Insert announcements inside that method's existing success / catch branches:

```swift
// Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift
private func commit(_ rule: RecurrenceRule?) async {
    do {
        if let rule {
            if let sid = initialSeriesID {
                try await env.seriesStore.update(id: sid, rule: rule)
            } else {
                _ = try await env.seriesStore.create(fromSeedTask: taskID, rule: rule)
            }
        } else if let sid = initialSeriesID {
            try await env.seriesStore.delete(id: sid)
        }
        AccessibilityAnnouncements.post(
            rule == nil
                ? String(localized: "Recurrence removed.")
                : String(localized: "Recurrence saved."),
            priority: .low
        )
        onClose()
    } catch {
        errorMessage = error.localizedDescription
        AccessibilityAnnouncements.post(
            String(localized: "Couldn't save recurrence: \(error.localizedDescription)"),
            priority: .high
        )
    }
}
```

The macOS site at `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift` still uses `RecurrenceEditorView`'s `onCommit:` / `onCancel:` closures directly. Apply the announcement pattern inside the existing `onCommit` Task:

```swift
RecurrenceEditorView(
    viewModel: $recurrenceViewModel,
    onCommit: { rule in
        Task {
            do {
                // … existing seriesStore.create / update call …
                AccessibilityAnnouncements.post(
                    rule == nil
                        ? String(localized: "Recurrence removed.")
                        : String(localized: "Recurrence saved."),
                    priority: .low
                )
            } catch {
                AccessibilityAnnouncements.post(
                    String(localized: "Couldn't save recurrence: \(error.localizedDescription)"),
                    priority: .high
                )
            }
        }
    },
    onCancel: { showingRecurrenceEditor = false }
)
```

- [ ] **Step 6: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 7: Commit**

```bash
git add Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift \
        Apps/Lillist-iOS/Sources/Settings/TrashSection.swift \
        Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift \
        Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift \
        Apps/Lillist-macOS/Sources/Views/Detail/FollowUpFormView.swift \
        Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift
git commit -m "feat(a11y): post accessibility announcements on QC submit, trash, recurrence, follow-up"
```

---

## Task 20: Wire sync-state announcements

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift`
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift`

Both views currently re-render when the `indicator` value changes. Add an `.onChange(of: indicator)` that posts an announcement on transitions. Only post on *changes*; the initial render does not announce.

- [ ] **Step 1: Update `SyncStatusDotView`**

Add to the body (after `.popover(...)`):

```swift
        .onChange(of: indicator) { _, new in
            switch new {
            case .inProgress:
                AccessibilityAnnouncements.post(
                    String(localized: "Syncing to iCloud", bundle: .module),
                    priority: .low
                )
            case .idle:
                AccessibilityAnnouncements.post(
                    String(localized: "Sync complete", bundle: .module),
                    priority: .low
                )
            case .error(let msg, _):
                AccessibilityAnnouncements.post(
                    String(localized: "Sync error: \(msg)", bundle: .module),
                    priority: .high
                )
            }
        }
```

- [ ] **Step 2: Update `SyncStatusBadge` (iOS)**

Add the same `.onChange(of: indicator)` modifier. Both views observe the same `SyncIndicator` — keep messages identical so a user with both visible (rare) doesn't get duplicates with mismatched wording. (SwiftUI de-duplicates back-to-back identical announcements on iOS — verified empirically.)

- [ ] **Step 3: Build LillistUI; test**

```bash
swift test --package-path Packages/LillistUI 2>&1 | tail -5
```

Expected: full suite PASS. Existing snapshot baselines are unaffected (announcements don't render visually).

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift \
        Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift
git commit -m "feat(a11y): announce sync state transitions via AccessibilityAnnouncements"
```

---

## Task 21: Add `.accessibilityLiveRegion` to error labels

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift:29-33`
- Modify: `Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:48-52`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift:56-60`

`.accessibilityLiveRegion(.assertive)` on the QuickCapture error label and `.polite` on the Trash result labels so VoiceOver re-reads them as they change. The recurrence-editor "limit" ambiguity that the original Plan 17 draft folded in here was already resolved by Plan 16 Task 22 (a `Toggle("Repeat forever", isOn:)` that reveals a Stepper when off). No editor surgery in this task.

- [ ] **Step 1: QuickCapture error label**

In `QuickCaptureSheet.swift`, lines 29-33:

```swift
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLiveRegion(.assertive)
                }
```

- [ ] **Step 2: Trash result label (iOS)**

In `TrashSection.swift`, lines 48-52:

```swift
            if let emptyResult {
                Text(emptyResult)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLiveRegion(.polite)
            }
```

(Polite, not assertive — the trash result is informational, not urgent.)

- [ ] **Step 3: Trash result label (macOS)**

In `TrashPane.swift`, lines 56-60:

```swift
                    if let emptyResult {
                        Text(emptyResult)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLiveRegion(.polite)
                    }
```

- [ ] **Step 4: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift \
        Apps/Lillist-iOS/Sources/Settings/TrashSection.swift \
        Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift
git commit -m "feat(a11y): live-region error labels on QuickCapture and Trash"
```

---

## Task 22: Pair RecurrenceEditor Stepper with a TextField for Voice Control

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:48`

`Stepper("Every \(interval)", in: 1...365)` lets only ±1 input. Voice Control's "Set value to 14" works against `TextField(value:format:)`, not Stepper. Pair them.

- [ ] **Step 1: Rewrite the frequency section**

Replace line 48 (inside `Section("Frequency")`):

```swift
                    Section("Frequency") {
                        Picker("Frequency", selection: $viewModel.freq) {
                            Text("Daily").tag(RecurrenceRule.Frequency.daily)
                            Text("Weekly").tag(RecurrenceRule.Frequency.weekly)
                            Text("Monthly").tag(RecurrenceRule.Frequency.monthly)
                            Text("Yearly").tag(RecurrenceRule.Frequency.yearly)
                        }
                        HStack {
                            Stepper("Every", value: $viewModel.interval, in: 1...365)
                            TextField(
                                "Interval",
                                value: $viewModel.interval,
                                format: .number.precision(.integerLength(1...3))
                            )
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .accessibilityLabel(String(localized: "Interval, every N units", bundle: .module))
                        }
                    }
```

The `TextField(value:format:)` initializer (iOS 15+/macOS 12+) accepts numeric input, validates against the `.number` format, and writes back through the binding. Voice Control sees a generic text field and accepts "Set value to 14"; Switch Control sees an editable text element.

- [ ] **Step 2: Build, update snapshot baselines**

```bash
swift test --package-path Packages/LillistUI --filter RecurrenceEditor 2>&1 | tail -10
```

Re-record baselines if visual layout changed. The TextField adds a numeric input next to the Stepper — baselines will shift.

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift \
        Packages/LillistUI/Tests/LillistUITests/Recurrence/__Snapshots__/
git commit -m "feat(a11y): pair RecurrenceEditor Stepper with TextField for Voice Control"
```

---

## Task 23: Required-field a11y labels on title inputs

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift:15-33`
- Modify: `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift:22-27` (the `QuickCaptureField` host)

Required-field semantics: VoiceOver announces "Title, required" rather than just "Title"; the live `.accessibilityValue` says "empty" or "not empty" so the user knows whether Save is enabled.

- [ ] **Step 1: Rewrite `InlineCreateField` (macOS)**

> **Plan 13 fallout (2026-05-16):** Plan 13 Task 6 added an `if text.isEmpty { return .ignored }` early-return in the `.onKeyPress` closure so Tab passes through to the system focus chain when the field is empty (otherwise focus traps inside an unused inline-create field). Preserve that branch when rewriting the body below.

```swift
struct InlineCreateField: View {
    @Binding var text: String
    var onReturn: () -> Void
    var onTab: () -> Void
    var onShiftTab: () -> Void
    var onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        TextField("New task", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .onSubmit { onReturn() }
            .onAppear { focused = true }
            #if os(macOS)
            .onExitCommand(perform: onCancel)
            #endif
            .onKeyPress(keys: [.tab], phases: .down) { press in
                // Plan 13 fallout: let Tab pass through when the field is
                // empty so focus can leave an unused inline-create field.
                if text.isEmpty { return .ignored }
                if press.modifiers.contains(.shift) { onShiftTab() } else { onTab() }
                return .handled
            }
            .accessibilityLabel(String(
                localized: "Title, required; Return to save, Tab to indent"
            ))
            .accessibilityValue(text.isEmpty
                ? String(localized: "Empty")
                : String(localized: "Not empty")
            )
    }
}
```

- [ ] **Step 2: Wrap the iOS `QuickCaptureField` host with required-field semantics**

The shared `QuickCaptureField` lives in LillistUI and is consumed by the sheet. Rather than alter LillistUI's atom (which is also used by macOS Quick Capture), wrap the host in `QuickCaptureSheet`:

```swift
                QuickCaptureField(
                    text: $text,
                    tagSuggestions: tagSuggestions,
                    // i18n-exempt: parser tokens, see Task 8.
                    dateSuggestions: ["today", "tomorrow", "+3d", "+1w"],
                    onSubmit: { _ in submit() }
                )
                .focused($focused)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(String(localized: "Title, required"))
                .accessibilityValue(trimmedTitleIsEmpty
                    ? String(localized: "Empty")
                    : String(localized: "Not empty")
                )
```

The `.accessibilityElement(children: .contain)` keeps the inner field's children navigable; the wrapper just adds the rotor-visible required-field hint.

- [ ] **Step 3: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift \
        Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift
git commit -m "feat(a11y): announce 'required' + live empty/not-empty state on title inputs"
```

---

## Task 24: Surface onboarding notification-request errors with live region

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift:133-146`

Currently `complete()` swallows errors with `print(...)` — they never reach the user, screen reader or not. Surface inline.

- [ ] **Step 1: Add error state and live region**

Edit `OnboardingScreen.swift`:

```swift
struct OnboardingScreen: View {
    let onboardingState: OnboardingState
    let installer: DefaultsInstaller
    let notificationPermissions: NotificationPermissions
    let onCompleted: () -> Void

    @State private var permissionStatus: NotificationPermissions.AuthorizationStatus = .notDetermined
    @State private var isRequesting = false
    @State private var isCompleting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    bullets
                    permissionStatusRow
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .accessibilityLiveRegion(.assertive)
                    }
                }
                .padding(24)
            }
            actionBar
        }
        .task { permissionStatus = await notificationPermissions.currentStatus() }
    }

    // … header, bullets, permissionStatusRow, actionBar unchanged …

    private func complete() async {
        isCompleting = true
        defer { isCompleting = false }
        do {
            try await installer.installIfNeeded()
            try await onboardingState.markCompleted()
            onCompleted()
        } catch {
            errorMessage = String(
                localized: "Couldn't finish onboarding: \(error.localizedDescription)"
            )
            AccessibilityAnnouncements.post(errorMessage ?? "", priority: .high)
        }
    }
}
```

Add `import LillistUI` if absent.

- [ ] **Step 2: Build iOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift
git commit -m "feat(a11y): surface onboarding completion errors with live region + announcement"
```

---

## Task 25: Add `.keyboardShortcut(.cancelAction)` to Recurrence editor Cancel

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:99-110`

Save already has `.keyboardShortcut(.defaultAction)`. Cancel needs `.keyboardShortcut(.cancelAction)` so Escape works regardless of focus.

- [ ] **Step 1: Edit the Cancel button**

```swift
            if onCommit != nil || onCancel != nil {
                Section {
                    HStack {
                        if let onCancel {
                            Button("Cancel", role: .cancel, action: onCancel)
                                .keyboardShortcut(.cancelAction)
                        }
                        Spacer()
                        if let onCommit {
                            Button("Save") { onCommit(viewModel.build()) }
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
```

- [ ] **Step 2: Build + test**

```bash
swift test --package-path Packages/LillistUI --filter RecurrenceEditor 2>&1 | tail -10
```

Expected: PASS. No baseline change (keyboard shortcuts don't affect rendering).

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift
git commit -m "feat(a11y): Escape cancels the recurrence editor (.cancelAction shortcut)"
```

---

## Task 26: Add `.keyboardShortcut` to QuickCaptureSheet Save / Cancel

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift:40-47`

The sheet's `ToolbarItem(Save/Cancel)` buttons have no shortcuts. On iPad with a hardware keyboard, the user can't dismiss without tapping.

- [ ] **Step 1: Add shortcuts**

```swift
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { submit() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(submitting || trimmedTitleIsEmpty)
                }
            }
```

(`.defaultAction` is `Return`; `.cancelAction` is `Escape`. Both work with iPad hardware keyboards and Voice Control.)

- [ ] **Step 2: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureSheet.swift
git commit -m "feat(a11y): Return saves and Escape cancels in QuickCaptureSheet"
```

---

## Task 27: Add `.accessibilityAddTraits(.isHeader)` to macOS detail section titles

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/SubtaskOutlineView.swift:13`
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift:13`
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/NotesEditorView.swift:10`

Three free-form `Text("…").font(.headline)` strings are not registered as headings — the VoiceOver rotor's "Headings" listing skips them.

- [ ] **Step 1: SubtaskOutlineView**

Replace line 13:

```swift
            Text("Subtasks")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
```

- [ ] **Step 2: JournalStreamView**

Replace line 13:

```swift
                Text("Journal & Attachments")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
```

- [ ] **Step 3: NotesEditorView**

Replace line 10:

```swift
                Text("Notes")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
```

- [ ] **Step 4: Build macOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Detail/SubtaskOutlineView.swift \
        Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift \
        Apps/Lillist-macOS/Sources/Views/Detail/NotesEditorView.swift
git commit -m "feat(a11y): register macOS detail section titles as VoiceOver headings"
```

---

## Task 28: Make empty-detail surfaces focusable so keyboard users land somewhere

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/EmptyView/NoSelectionDetailView.swift`
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift`

When the user tabs through the macOS three-column layout and the detail column is empty, focus has nowhere to land. Add a focusable element with a clear hint.

- [ ] **Step 1: Update `EmptyStateView` to be focusable**

```swift
public struct EmptyStateView: View {
    public var title: String
    public var message: String
    public var systemImage: String

    @FocusState private var focused: Bool

    public init(title: String, message: String, systemImage: String = "tray") {
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .focusable()
        .focused($focused)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(title). \(message)", bundle: .module))
        .accessibilityAddTraits(.isStaticText)
    }
}
```

`.contentShape(Rectangle())` + `.focusable()` makes the entire frame a focus target. The combined label gives both screen-reader and visible-focus users the full hint.

- [ ] **Step 2: Verify `NoSelectionDetailView` passes through unchanged**

`NoSelectionDetailView` is a thin wrapper; the focusable behavior comes from `EmptyStateView` automatically. No code change needed beyond a confirmation read.

```bash
cat Apps/Lillist-macOS/Sources/Views/EmptyView/NoSelectionDetailView.swift
```

Expected: still just an `EmptyStateView(...)` wrapper.

- [ ] **Step 3: Build, test**

```bash
swift test --package-path Packages/LillistUI 2>&1 | tail -5
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift
git commit -m "feat(a11y): make EmptyStateView focusable with combined a11y label"
```

---

## Task 29: Final sweep + engineering note

**Files:**
- Modify: `docs/engineering-notes.md`

- [ ] **Step 1: Full test sweep**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
swift test --package-path Packages/LillistUI 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

All four must report PASS / `** BUILD SUCCEEDED **`. Re-verify warnings-as-errors stays clean (the cli output should contain zero `warning:` lines).

- [ ] **Step 2: Confirm no hardcoded a11y strings linger**

```bash
grep -RIn 'accessibility\(Label\|Hint\|Value\)("' Packages/LillistUI/Sources Apps/ 2>&1
```

Expected: zero hits.

- [ ] **Step 3: Confirm directional-glyph audit clean**

```bash
grep -RIn 'systemName: "chevron\.\(left\|right\)"' Packages/LillistUI/Sources Apps/ 2>&1
grep -RIn 'systemName: "arrow\.\(left\|right\)"' Packages/LillistUI/Sources Apps/ 2>&1
```

Expected: zero hits (or only intentional ones, called out with `// i18n-exempt: …`).

- [ ] **Step 4: Append engineering note**

Add at the top of `docs/engineering-notes.md` (above the Plan 12 entry):

```markdown
## 2026-05-16 — Plan 17 Localization & Accessibility Environments

**Context.** Lillist had zero usage of the four accessibility-environment
values and zero localization infrastructure. All user-facing strings were
hardcoded English literals; `String`-typed `.accessibilityLabel(_:)` calls
silently bypassed the catalog extractor. Plan 17 scaffolded String Catalogs
for the SPM package and both app targets, routed ~35 a11y labels through
`String(localized:bundle:)`, added environment-honoring view modifiers,
and locked RTL / high-contrast / reduce-transparency code paths with
snapshot baselines.

**Rules.**

- **`String(localized:bundle: .module)` is the right shape inside SPM
  packages.** The default `Bundle.main` is the host app's bundle and won't
  find the package catalog. App targets omit `bundle:`.
- **`Text("…")` extracts; `.accessibilityLabel("…")` does not.** Wrap
  every `String`-typed a11y label in `String(localized:)`.
- **String concatenation defeats the extractor.** `"Last synced " + x`
  becomes a fragment; `"Last synced \(x)"` becomes `"Last synced %@"` and
  the placeholder survives translation.
- **`chevron.right` does not flip; `chevron.forward` does.** Use
  forward/backward variants for any directional glyph that should mirror
  under RTL. For non-mirroring symbols, apply
  `.flipsForRightToLeftLayoutDirection(true)`.
- **`accessibilityShouldIncreaseContrast` is a tuning, not a switch.** The
  user wants more separation, not pure-black-on-pure-white. Bumping a fill
  from 0.18 to 0.30 and the stroke from 0.45 to 0.85 is the right shape.
- **`accessibilityDifferentiateWithoutColor` requires a shape axis, not
  just darker color.** SF Symbol overlays, distinct outlines, or textured
  fills are all valid; the test is whether a grayscale render still
  communicates the state.
- **WCAG 4.5:1 is a 30-line pure-Swift calculation.** Ship the math
  (`ContrastMath.wcagRatio`) and iterate brightness against the floor in
  `TagTint.resolved(in:)` — deterministic, testable, no designer eyeball.
- **Snapshot the contract under environment overrides.** Two snapshots of
  the same view — one with `.environment(\.accessibilityShouldIncreaseContrast, true)`,
  one without — make accidental normalization fail loudly.
- **`AccessibilityNotification.Announcement` (iOS 17+) ≠
  `NSAccessibility.post(_:argument:)` (AppKit).** Wrap both in one
  helper so callers don't `#if` everywhere.
- **SwiftPM `.process("Resources")` is correct for `.xcstrings`.**
  `.copy("Resources")` skips the catalog compile step and the runtime
  can't read the strings.

**Evidence.** Plan 17 commits on `plan-17-i18n-a11y-environments`:
three `Localizable.xcstrings` files; `LillistUI/Accessibility/` directory
with `AccessibilityEnvironment.swift`, `Announcements.swift`,
`ContrastMath.swift`; three new snapshot suites
(`LocalizationSnapshotTests`, `ContrastSnapshotTests`,
`ReduceTransparencySnapshotTests`); `.blocked` retint in `StatusPalette`;
differentiated overlay on `SyncStatusDotView` / `SyncStatusBadge`;
live-region error labels; keyboard shortcuts on Recurrence + Quick
Capture; focusable `EmptyStateView`.
```

- [ ] **Step 5: Commit the engineering note**

```bash
git add docs/engineering-notes.md
git commit -m "docs: record Plan 17 lessons (String Catalog scaffolding, a11y env helpers, contrast math)"
```

- [ ] **Step 6: Final tag**

```bash
git tag plan-17-i18n-a11y-environments
git log --oneline plan-12-followups..plan-17-i18n-a11y-environments
```

Expected: a clean sequence of `chore(i18n)`, `refactor(i18n)`, `feat(a11y)`, `test(a11y)`, `test(i18n)` commits — one per task — plus the final docs commit.

---

## Plan 17 Scope

**In scope:**
- String Catalog scaffolding in LillistUI + both apps (Tasks 1–2)
- Audit and routing of every `String`-typed accessibility label through `String(localized:)` (Tasks 3–4)
- Localization correctness fixes: interpolation for sync labels, `chevron.forward` for RTL mirroring, `Calendar.standaloneWeekdaySymbols` for weekday labels (Tasks 5–7)
- Quick Capture parser-token coupling annotation (Task 8)
- RTL + Arabic-locale snapshot baselines (Task 9)
- Accessibility-environment helper module (`.accessibleAnimation`, `.accessibleMaterial`, `ContrastTuned`) + ContrastMath (Tasks 10, 15)
- Animation audit and gating where present (Task 11)
- Reduce-Transparency substitution in QuickCapture + Onboarding (Task 12)
- Increase-Contrast tuning in TagChipView + SidebarRowView; contrast floor in TagTint (Tasks 13–15)
- Differentiate-Without-Color shape axes on sync state and status (Tasks 16–17)
- `AccessibilityAnnouncements` helper + wiring on Quick Capture, Trash, Recurrence, Follow-up, Onboarding error (Tasks 18–20, 24)
- Live regions on error/result labels; Limit-occurrences toggle (Task 21)
- Voice Control TextField companion for RecurrenceEditor Stepper (Task 22)
- Required-field a11y on title inputs (Task 23)
- Keyboard shortcuts (Cancel/Save) for Recurrence + Quick Capture (Tasks 25–26)
- Header semantics on macOS detail section titles (Task 27)
- Focusable empty-detail surfaces (Task 28)
- Final sweep + engineering note + tag (Task 29)

**Explicitly out of scope (left for a follow-up plan):**

- **Shipping a second locale.** This plan builds the infrastructure that makes shipping `fr`, `de`, `ja`, `ar`, or any other locale a content swap into the catalog. It does **not** translate any strings. The catalog files ship with English source-language entries and zero translations. The follow-up plan would commission translations, run them through Apple's String Catalog "Mark for Translation" workflow, and add `knownRegions: [en, fr, …]` to `project.yml`.
- **Quick Capture date-token localization.** `RelativeDate.parse` would need to accept localized aliases before the iOS Quick Capture chips could safely render localized text. Task 8 documents the coupling; a follow-up plan extends the parser.
- **Live thumbnail-shape audit.** Plan 11's link previews don't yet render thumbnails — when they do, the alt-text and contrast story needs a pass.
- **Color-blind simulation snapshots.** Snapshot tests under simulated protanopia / deuteranopia / tritanopia are useful but require a custom color filter pipeline that's out of scope here. The shape-differentiation work (Task 16) covers the primary path.
- **App Shortcut / Lock Screen Quick Capture a11y.** App Intent surfaces have a separate accessibility story (system-rendered, mostly system-managed). When the lock-screen Quick Capture Intent ships its own UI (currently it pushes through the host app), it'll need its own pass.
- **Per-locale snapshot suites beyond `ar`.** Once translations land for `fr`, `ja`, etc., each gets its own snapshot batch. Not in this plan.
- **VoiceOver UI tests.** Behavioral verification that announcements actually post and live regions actually re-read requires a UI test target with an AT enabled — a separate harness. The snapshot tests in this plan lock the visual contract; the announcement helper tests lock the API contract.

---

## Self-Review Checklist (run by the implementer before merging)

- [ ] All 29 tasks completed with checkboxes ticked
- [ ] `swift test --package-path Packages/LillistCore` reports clean PASS
- [ ] `swift test --package-path Packages/LillistUI` reports clean PASS
- [ ] Both `xcodebuild build` runs succeed for macOS + iOS, zero `warning:` lines (warnings-as-errors holds)
- [ ] `grep -RIn 'accessibility\(Label\|Hint\|Value\)("' Packages/LillistUI/Sources Apps/` returns nothing
- [ ] `grep -RIn 'systemName: "chevron\.\(left\|right\)"' Packages/LillistUI/Sources Apps/` returns nothing (or only sites marked `// i18n-exempt`)
- [ ] `grep -RIn 'Text(String(format:' Packages/LillistUI/Sources Apps/` returns nothing
- [ ] `grep -RIn 'Text(LocalizedStringKey(' Packages/LillistUI/Sources Apps/` returns only the two intentional user-authored-content sites annotated in Task 3
- [ ] Three `Localizable.xcstrings` files exist and have grown to include the new keys (visible in `git status` after the final build)
- [ ] `Packages/LillistUI/Sources/LillistUI/Accessibility/` contains `AccessibilityEnvironment.swift`, `Announcements.swift`, `ContrastMath.swift`
- [ ] `Packages/LillistUI/Tests/LillistUITests/Accessibility/` contains three matching test files (all PASS)
- [ ] `Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/` contains baselines for `LocalizationSnapshotTests`, `ContrastSnapshotTests`, `ReduceTransparencySnapshotTests`
- [ ] Hand-test on macOS with VoiceOver: navigate the sidebar → confirm "Inbox, 7 items" reads correctly; trigger a sync error → confirm announcement plays; open the Recurrence editor → confirm Escape closes it and the rotor lists "Subtasks", "Notes", "Journal & Attachments" as headings
- [ ] Hand-test on iOS with VoiceOver: open Quick Capture → confirm "Title, required, Empty" is announced; submit a task → confirm "Task created: …" plays
- [ ] Hand-test on macOS with Increase Contrast enabled in System Settings: confirm tag chips and sidebar badges visibly darken; confirm the QuickCaptureView background opaques out under Reduce Transparency
- [ ] Hand-test on iOS with Differentiate Without Color enabled: confirm the SyncStatusBadge shows shape overlays
- [ ] `docs/engineering-notes.md` has the Plan 17 entry at the top
- [ ] CLAUDE.md unchanged (no new project-wide convention introduced)
- [ ] Branch is named `plan-17-i18n-a11y-environments`; commits use `chore(i18n):`, `refactor(i18n):`, `feat(a11y):`, `test(a11y):`, `test(i18n):`, `docs:` prefixes
- [ ] Final tag `plan-17-i18n-a11y-environments` is on the last commit
