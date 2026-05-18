# Engineering Notes

Append-only log of cross-cutting engineering lessons learned while building
Lillist. Each entry captures a non-obvious gotcha — usually one that took real
investigation to find — so future work doesn't re-learn it the hard way.

## 2026-05-17 — Closing the iOS LillistUITests scheme gap

**Context.** `LillistUITests/iOS/iOSSnapshotTests.swift` (14 tests) and
the iOS branches of `LillistUITests/Tour/IOSScreenTourTests.swift` (10
tests) had been checked into the repo since May 14–16 but never
executed — `swift test --package-path Packages/LillistUI` builds for
the host platform (macOS), so the `#if os(iOS)` blocks compile out,
and the Lillist-iOS scheme only listed `Lillist-iOSTests` in its test
action. The previous engineering-notes entry called this "the scheme
gap" with a manual workaround. It's now closed.

**The new workflow.**

1. **Scheme wiring.** `Apps/Lillist-iOS/project.yml` lists the SPM
   test bundle alongside the iOS-app test bundle under the scheme's
   test action:
   ```yaml
   schemes:
     Lillist-iOS:
       test:
         targets:
           - Lillist-iOSTests
           - package: LillistUI/LillistUITests
   ```
   `xcodegen generate` translates `package: <name>/<test-target>` into
   a `<TestableReference>` block in the xcscheme XML whose
   `ReferencedContainer` points at `../../Packages/LillistUI`. The
   syntax is documented in xcodegen's ProjectSpec "Testable Target
   Reference" section.

2. **Canonical simulator pin: iPhone 17 on iOS 26.2.** Snapshot tests
   are simulator-version-sensitive; render output differs by iOS
   version and device class. iPhone 17 + iOS 26.2 is the latest
   available pair, matches the iOS deployment target (`iOS: "26.0"`),
   and is the device class most users will be on by ship. Going
   forward, baselines are recorded against this destination and any
   re-record uses the same destination.

3. **Running the tests.**
   ```sh
   xcodebuild test \
     -workspace Lillist.xcworkspace \
     -scheme Lillist-iOS \
     -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
   ```
   This runs all four iOS test bundles: Lillist-iOSTests (38 tests)
   and LillistUITests on iOS (47 tests, 1 currently XCTSkip-ed; see
   below).

4. **Re-recording iOS baselines.** `SNAPSHOT_TESTING_RECORD=all` and
   `TEST_RUNNER_*`-prefixed env vars are *not* propagated through
   `xcodebuild test` to the test-host process (this works for `swift
   test` but not xcodebuild). The reliable workaround is to thread
   `record: .all` directly through the assertion API for the run.
   Plan 20 documented `withSnapshotTesting(record: .all) { … }` as
   one option; the cleaner one for a whole suite is to add a `record:
   .all` parameter to the per-suite helper (`assertScreen` in
   `IOSScreenTourTests.swift`) temporarily, run, then revert. This
   leaves the source untouched between record sessions.

**Rules.**

- **Don't probe SwiftUI accessibility via UIKit view-hierarchy
  traversal.** A test that asks `host.view.subviews`'
  `.accessibilityLabel` recursively — even with the host attached to
  a key-and-visible window, a forced render via `drawHierarchy`, and
  a runloop spin — finds *nothing*: SwiftUI only surfaces the a11y
  tree to the real assistive-technology runtime (VoiceOver / Voice
  Control), not to introspection. The `.accessibilityLabel(...)`
  modifier *is* working; the tooling is wrong. To test a11y in unit
  tests, either (a) use an accessibility-snapshot strategy (text
  snapshot of the AT tree), or (b) hit the label via an `XCUITest`
  whose `XCUIElement` queries go through the real AT layer.
  `test_floatingAddButton_accessibilityLabel_is_present` is currently
  `XCTSkip`-ed for this reason — the FAB has the right modifier;
  there's just no working harness for verifying that here.
- **SF Symbol glyphs render differently headless vs. in an attached
  UI.** Recording a `FloatingAddButton` snapshot via xcodebuild test
  produces a flat blue circle *without* the `+` glyph; the same view
  in the iOS app shows the symbol correctly. The headless test
  process doesn't fully resolve the SF Symbols rendering pipeline.
  Snapshot tests still catch regressions because the headless render
  is *deterministic* — it's only the human-readable preview that
  looks off. Don't treat the missing glyph as a bug; check the live
  app for visual correctness, and pin behaviour via the snapshot.
- **Pre-commit iOS-LillistUI checks belong on `xcodebuild test`, not
  `swift test`.** `swift test --package-path Packages/LillistUI` will
  always under-report iOS coverage (anything `#if os(iOS)` compiles
  out). Make `xcodebuild test -scheme Lillist-iOS -destination
  'platform=iOS Simulator,name=iPhone 17,OS=26.2'` the canonical
  pre-merge command for iOS UI changes.

**Evidence.** `Apps/Lillist-iOS/project.yml` adds `- package:
LillistUI/LillistUITests` under `schemes.Lillist-iOS.test.targets`;
`xcodegen generate` regenerates the xcscheme accordingly. 13 new
baselines in `Tests/LillistUITests/iOS/__Snapshots__/iOSSnapshotTests/`
and 7 re-recorded baselines in
`Tests/LillistUITests/Tour/__Snapshots__/IOSScreenTourTests/` (the
latter were stale from before the May 17 AccentColor commit). Full
iOS scheme test passes 47 tests on the LillistUITests bundle (1
skipped) plus 38 in Lillist-iOSTests, 3× consecutive runs.

## 2026-05-17 — Snapshot test reliability: SwiftUI `Form` views drift on cold-cache runs

**Context.** Three `RecurrenceEditorSnapshotTests` Form-rendered
baselines (`testWeeklyTuesdayThursday_light`, `testMonthlyDay15_light`,
`testMonthlyMultipleDays_light`) failed on a cold-cache `swift test
--package-path Packages/LillistUI` run with actual precision
0.977–0.979 vs the required 0.99. Visual diff showed the entire Form
content shifted by sub-pixel amounts — classic anti-aliasing /
font-hinting drift, invisible to a human but enough to breach a strict
raw-pixel threshold. The drift cleared on the next run in the same
shell. Re-recording with `SNAPSHOT_TESTING_RECORD=all` produced
byte-identical baselines to what was already in git — confirmation
that the on-disk baselines were *correct*; the cold-cache render was
the outlier. Other snapshot tests in the suite (custom layouts,
sidebars, tag chips) weren't affected because their frames are smaller
and they don't go through AppKit's Form chrome.

**Rules.**

- **`Form`-rendered snapshots need `perceptualPrecision: 0.98`
  alongside `precision: 0.99`.** AppKit Form rendering accumulates
  per-section AA drift that breaches 0.99 precision on larger frames
  (420×600+) when the render pipeline is cold. `precision` still
  catches real layout regressions (different row counts, different
  section heights, accidental padding changes); `perceptualPrecision`
  tolerates the sub-pixel font-edge drift you wouldn't see visually
  anyway. Don't soften globally — most non-Form views pass at 0.99
  alone, and that strictness is the regression net for everything
  else.
- **A 0.97–0.98 precision failure that clears on the next run is
  render non-determinism, not a stale baseline.** Re-recording will
  *appear* to fix it (the warm second run produces the "matching"
  image), but check `git status` after a re-record: if the working
  tree is clean, the new bytes are byte-identical to the existing
  baseline — the existing baseline was right all along, and the cure
  is precision tuning (add `perceptualPrecision`), not committing new
  baselines.
- **Read the diff before re-recording.** When a snapshot fails after
  an a11y-only or copy-only commit ("baselines verified unchanged"),
  copy the baseline and the temp render into `/tmp/`, open both in
  Preview side by side. If the diff is real (layout shifted, section
  metrics changed, padding moved), the prior commit's claim was
  wrong and the failure is the snapshot test doing its job. If the
  diff is invisible to you (everything looks identical), it's
  AA/cold-cache drift and `perceptualPrecision` is the fix.

**Evidence.** `RecurrenceEditorSnapshotTests` assertions now use
`precision: 0.99, perceptualPrecision: 0.98`. Verified 10× consecutive
clean runs (including a fresh `swift package clean && rm -rf .build`)
after the change with no failures.

## 2026-05-17 — Plan 20 shared polish & accessibility nits

**Context.** Plan 20 closed the cross-platform and a11y LOW/NIT
items from the 2026-05-16 design review that didn't fit any single
platform-specific plan: an `AccentColor` asset for both targets
(placeholder brand tint), unified Quick Capture date-token chips,
iPad keyboard shortcut parity with macOS, a module documentation
landing page for `LillistUI`, a one-time copy audit (title-case
fixes + cross-platform onboarding tagline parity), and individual
a11y modifier additions on `SidebarRowView`, `BreadcrumbView`,
`RecurrenceEditorView`, `EmptyStateView`, `DetailHeaderView`
DatePickers, and `TagChipView`. Task 4 (IOSScreenTourTests
refactor) was deferred to Plan 20a per the in-plan decision point.

A precursor `fix(UI)` commit also restored the clickable mailto
link on the `CrashReportSheet` footer that silently regressed in
Plan 19 — see the LocalizedStringKey rule below.

**Rules.**

- **Shared components require shared assets.** When `LillistUI`
  reads `Color.accentColor`, every consuming app target needs a
  matching `AccentColor.colorset` **plus**
  `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME=AccentColor`.
  Without both, silent fallback to system blue.
- **Centralize parallel hardcoded lists at the seam.** Two
  platforms hardcoding the same short list (Quick Capture date
  tokens were on iOS but *missing* on macOS) drifts silently.
  Cure: a single `public enum X { public static let default: [Y]
  = [...] }` consumed by both surfaces, plus a parser-coupling
  regression test.
- **Cross-platform user-visible strings must match verbatim.** A
  single-platform copy rewrite leaves the other platform's string
  stale and the product feels uneven on first launch. When you
  touch a welcome line, error message, or tagline on macOS, sync
  the iOS twin in the same change (and vice versa); copy that
  exists on both platforms is a shared surface even when the
  files live apart.
- **`Text(LocalizedStringKey)` auto-link detection is
  literal-only.** SwiftUI auto-detects URLs and emails when the
  `LocalizedStringKey` is a compile-time string literal; values
  inserted via `\(interpolation)` render as plain text. The
  one-line refactor "literal email → `\(constant)`" silently
  drops the clickable mailto link. Cure: spell the link with
  explicit markdown `[\(addr)](mailto:\(addr))` so the markdown
  parser (which *does* run after interpolation) keeps the link
  alive. Caught in Plan 20 only because snapshot tests showed
  the visual diff — the swift-snapshot-testing baseline was the
  thing standing between this regression and a silent ship.
- **`@ScaledMetric` is the cure for hardcoded
  `.font(.system(size: N, ...))` literals, but its base value
  does *not* match `.largeTitle`'s native metric.** On macOS,
  `.largeTitle` resolves to 34pt; `@ScaledMetric` with base 36
  renders +2pt larger at default Dynamic Type. The trade-off:
  pin the visual baseline locally and accept a one-time +2pt
  shift, or stay coupled to Apple's evolving metric. Plan 20
  Task 10 chose the former and re-recorded the affected
  baselines.
- **`.labelsHidden()` requires an explicit
  `.accessibilityLabel(...)` companion.** VoiceOver may pick up
  the underlying initializer label, but Voice Control's
  label-match heuristic prefers a visible label — falling back
  to no match when none exists. Two-line fix: keep
  `.labelsHidden()` for the visual layout, follow with an
  explicit `.accessibilityLabel(...)` for the AT path.
- **Source-reading regression tests need indent-anchored
  patterns.** A test that asserts "the body's closing brace is at
  4-space indent" via `range(of: "    }")` matches *any* line
  whose `}` is preceded by ≥4 spaces — the search treats the
  pattern as a substring. Cure: search for a discriminator that
  uniquely identifies the target line (e.g.
  `.accessibilityLabel(badge.map`), or anchor with surrounding
  newlines (`\n    }\n`).
- **Snapshot tests are how you discover regressions you didn't
  ship knowingly.** Several Plan 19 / Plan 20 commits ostensibly
  did one thing (refactor a string constant, add an a11y trait)
  but quietly diffed a snapshot baseline elsewhere. Run the full
  `swift test --package-path Packages/LillistUI` after any
  change to a shared SwiftUI view — coverage-by-snapshot is the
  blast-radius detector for SwiftUI behavior we can't otherwise
  unit-test.

**Evidence.** Plan 20 commits on `main`: one commit per task,
plus a precursor `fix(UI)` for the CrashReportSheet mailto
regression and two `test(...)` follow-ups for snapshots missed in
the Task 2 / Task 10 commits. Tag: `plan-20-shared-polish`.

## 2026-05-17 — Plan 19 macOS polish sweep: WindowGroup chrome, live preference streams, sidebar context menus, list-column source-name resolution, single contact-info constant

**Context.** Plan 19 closed the LOW/NIT-severity macOS findings from
the 2026-05-16 design review that weren't addressed by Plans 13–17.
Most tasks were 1–5-file surgical edits; the load-bearing structural
change was a hot `AsyncStream<Prefs>` on `PreferencesStore` so the
six Preferences panes stay current under CloudKit-pushed setting
changes. A secondary structural change was extracting
`SourceTitleResolver` from `TaskListView` so both the toolbar's
principal slot and the WindowGroup chrome can feed off the same
resolved-name computation.

**Rules.**

- **`WindowGroup` title flows from the deepest `.navigationTitle`.**
  Set the title on the column whose content the user is editing,
  not on the `WindowGroup` itself — the system promotes it. Same
  computation feeds the toolbar (Plan 15 Task 1) and the window
  chrome (Plan 19 Task 1). When the toolbar has a `.principal`
  item, that overrides the title-bar text, so both surfaces need
  to converge on the same resolver.
- **`@unchecked Sendable` final classes expose `AsyncStream` with
  `NSLock` + a continuation dictionary.** Copy the shape from
  `AccountStateMonitor.stateStream` / `CloudKitEventBridge.eventStream`
  / `SyncStatusMonitor.statusStream` — but the actor versions use
  the actor's own queue for serialization, while a class-based
  store needs an explicit `NSLock`. Pair every `update`-then-`save`
  with `broadcast(snapshot)` *after* the `context.perform` block
  returns (broadcasting from inside the perform closure works but
  invites lock-order surprises later).
- **`NSPersistentStoreRemoteChange` fires for in-memory stores too**
  when `NSPersistentStoreRemoteChangeNotificationPostOptionKey` is
  set on the description. Tests that exercise an in-memory store
  through `update` *will* see remote-change echoes through the
  same broadcast path. Don't write the test as "exactly N
  snapshots arrive"; write it as "all expected field values land
  somewhere in the snapshot sequence" — eventual consistency is
  the real contract.
- **Subscribers that round-trip their own writes must echo-suppress.**
  When a Preferences pane writes `prefs` and the store broadcasts
  the snapshot back, compare to local state and skip if equal.
  Otherwise the form fights itself mid-edit (the field's
  `onChange` handler kicks the store, the store broadcasts back,
  the binding fires `onChange` again, and so on).
- **`applicationShouldHandleReopen(_:hasVisibleWindows:)` is the
  AppKit-native recovery for `⌘W`-closes-only-window.** SwiftUI's
  `WindowGroup` does not auto-reopen. The system asks AppDelegate
  via the reopen callback; combine with `NotificationCenter` →
  `@Environment(\.openWindow)` to spawn a fresh window if the
  group is empty. Give the `WindowGroup` an explicit `id:` so
  `openWindow(id:)` is unambiguous.
- **One constant beats six copies.** Six files held
  `"mikeyward@gmail.com"`. The right shape is
  `LillistCoreContact.crashReportRecipient`. Cost of the one-file
  abstraction: zero; cost of copies diverging on the next email
  change: a bug-report round.
- **Standalone macOS test bundle: extract pure helpers, co-compile
  them.** The bundle has no test host so it can't `@testable
  import Lillist_macOS`. The pattern (used by
  `QuickCapturePlacementMath`, `IndexingMappers`, and now
  `SourceTitleResolver` / `SelectionAdvance`) is: extract the
  pure logic from the view into its own file under `Sources/`,
  then add a co-compile entry to `project.yml`'s test target.
  Re-run `xcodegen generate` after editing the YAML so the
  pbxproj picks up the new source.

**Evidence.** Plan 19 commits on `main`: one commit per task,
tagged `plan-19-macos-polish-sweep`.

## 2026-05-16 — Plan 18 iOS polish sweep: gesture-reliable status indicator, Form footers, MailComposer clipboard fallback

**Context.** Plan 18 closed eleven LOW / NIT items from the 2026-05-16
design review that Plans 13-17 didn't cover. The headline correctness
fix is the StatusIndicatorView gesture rewrite:
`simultaneousGesture(LongPressGesture)` on a `.plain` Button is
known-flaky (the tap can swallow the long-press depending on press
duration), so Plan 13's `.accessibilityAction(named: "Cycle status")`
was the only reliable path for AT users. Plan 18 swapped the
underlying mechanism to `Menu(primaryAction:)` — primary action fires
the cycle, long-press expands a Started / Blocked / Closed menu —
giving sighted-touch users the same reliability AT users got in
Plan 13.

**Rules.**

- **`simultaneousGesture(LongPressGesture)` on a `.plain` Button is
  flaky.** SwiftUI's `Button` consumes the press for itself; the
  simultaneous long-press fires inconsistently depending on press
  duration. If you need tap + long-press on the same surface, reach
  for `Menu(primaryAction:)` (tap = primary action, long-press =
  expand) or `.contextMenu` on the surrounding container. Don't layer
  a `simultaneousGesture` on a Button.
- **`Menu` with a custom label shows a disclosure chevron on macOS by
  default.** If the label is the affordance (an icon, a glyph), add
  `.menuIndicator(.hidden)` to suppress the chevron — otherwise you
  ship a glyph + chevron compound visual that wasn't in the design.
  iOS Menu doesn't show the indicator by default, so the modifier is
  a no-op there.
- **`Section(footer:)` is the right place for non-obvious Form
  defaults.** SwiftUI's `Section { content } header: { Text(...) }
  footer: { Text(...) }` shape renders the footer beneath the section's
  last row in subdued type. Non-obvious behavioural impact ("affects
  all task lists" / "applied to new tags only") goes here, not in a
  label modifier or a tooltip. Tooltips don't exist on iOS Form.
- **Don't show preview UI for a feature that's gated off.**
  `CrashReportingSection` showed a hardcoded "View what would be sent"
  disclosure even when crash prompts were disabled, misleading users
  into thinking content was being collected. Gate preview UI behind
  the same toggle that controls the feature; reset the disclosure's
  expanded state on toggle-off so re-enables start collapsed.
- **`PresentationDetent` `selection:` `.constant(...)` is read-only.**
  If users should be able to drag-resize between detents, the
  `selection:` parameter must be a `@State` binding, not `.constant`.
  Use `.onAppear { detent = ... }` to set the initial value from
  external state (e.g. an `@AppStorage` flag) while still allowing
  user drags.
- **MailComposer fallbacks need a recourse.** When
  `MFMailComposeViewController.canSendMail()` returns false (which is
  the default state in fresh simulators and on devices with no Mail
  account), don't render a dead-end text view. Provide a "Copy to
  clipboard" button so the user can paste into any email or messaging
  app, and confirm the copy via `.alert(...)`.

**Evidence.** Plan 18 commits on `main` between `b131247` and the
`plan-18-ios-polish-sweep` tag.

## 2026-05-16 — Plan 17 Localization & Accessibility Environments

**Context.** Lillist had zero usage of the four accessibility-environment
values (`accessibilityReduceMotion`, `accessibilityReduceTransparency`,
`accessibilityShouldIncreaseContrast`, `accessibilityDifferentiateWithoutColor`)
and zero localization infrastructure. All user-facing strings were
hardcoded English literals; `String`-typed `.accessibilityLabel(_:)`
calls silently bypassed the catalog extractor. Plan 17 scaffolded
String Catalogs for the SPM package and both app targets, routed all
~50 `String`-typed a11y labels through `String(localized:bundle:)`,
added environment-honoring view modifiers, and locked RTL,
high-contrast, reduce-transparency, and differentiate-without-color
code paths with snapshot baselines.

**Rules.**

- **`String(localized:bundle: .module)` is the right shape inside SPM
  packages.** The default `Bundle.main` is the host app's bundle and
  won't find the package catalog. App targets omit `bundle:`.
- **`Text("…")` extracts; `.accessibilityLabel("…")` does not.** Wrap
  every `String`-typed a11y label in `String(localized:)`.
- **String concatenation defeats the extractor.** `"Last synced " + x`
  becomes an orphan fragment; `"Last synced \(x)"` becomes
  `"Last synced %@"` and the placeholder survives translation.
- **`chevron.right` does not flip; `chevron.forward` does.** Use
  forward/backward variants for any directional glyph that should
  mirror under RTL. For non-mirroring symbols, apply
  `.flipsForRightToLeftLayoutDirection(true)`.
- **`accessibilityShouldIncreaseContrast` is iOS-only on the
  EnvironmentValues type; the cross-platform spelling is
  `colorSchemeContrast` (returns `ColorSchemeContrast.standard` or
  `.increased`).** Three-agent panel chose to add a one-line boolean
  shim `EnvironmentValues.accessibilityShouldIncreaseContrast: Bool`
  computed from `colorSchemeContrast == .increased` so view callsites
  read in the boolean shape they actually use.
- **`\.accessibilityReduceMotion`, `\.accessibilityReduceTransparency`,
  `\.accessibilityDifferentiateWithoutColor`, and `\.colorSchemeContrast`
  are read-only `KeyPath`s in SDK 26.2, not `WritableKeyPath`s.** The
  call `.environment(\.accessibilityReduceMotion, true)` that the
  plan's snapshot tests assumed does NOT compile. The fix is to add
  internal-only `*Override: Bool?` env keys (`reduceMotionOverride`,
  `reduceTransparencyOverride`, `differentiateWithoutColorOverride`,
  `increaseContrastOverride`). Each helper modifier reads both the
  system value and the override, prefers the override when non-nil.
  Production code never touches the override key (it's `internal` to
  LillistUI). Tests using `@testable import LillistUI` inject via the
  override for deterministic snapshot baselines.
- **SwiftUI has no `.accessibilityLiveRegion(_:)` modifier.** That's
  an HTML/UIKit concept; the closest equivalent is
  `.accessibilityAddTraits(.updatesFrequently)` plus an explicit
  `AccessibilityNotification.Announcement` (or
  `NSAccessibility.post`) when the value changes. The platform-aware
  `AccessibilityAnnouncements.post(_:priority:)` helper wraps both
  APIs so callers don't `#if` per platform.
- **`accessibilityShouldIncreaseContrast` is a tuning, not a switch.**
  Bumping a fill from 0.18 to 0.30 and the stroke from 0.45 to 0.85
  is the right shape. Black-on-white is overkill and reads worse.
- **`accessibilityDifferentiateWithoutColor` requires a shape axis,
  not just darker color.** SF Symbol overlays, distinct outlines, or
  textured fills are all valid; the test is whether a grayscale
  render still communicates the state.
- **WCAG 4.5:1 is a 30-line pure-Swift calculation.** Ship the math
  (`ContrastMath.relativeLuminance` / `wcagRatio` / `hsbToRGB`) and
  iterate brightness against the floor in `TagTint.resolved(in:)` —
  deterministic, testable, no designer eyeball.
- **`NSApp` is implicitly unwrapped and can crash in unit-test
  contexts.** `NSApplication.shared as NSApplication?` forces a real
  optional that can be safely `guard let`-ed before reading
  `mainWindow` / `windows.first`.
- **SwiftPM `.process("Resources")` is correct for `.xcstrings`.**
  `.copy("Resources")` skips the catalog compile step and the
  runtime can't read the strings.
- **`Calendar.current.standaloneWeekdaySymbols` is Sunday-first
  regardless of the locale's `firstWeekday`.** Index 0 = `.sunday`,
  etc. The returned strings are already localized.
- **xcodegen auto-detects new files under a path with
  `buildPhase: resources`.** Both app `project.yml`s already had a
  `Resources` entry; just dropping `Localizable.xcstrings` into
  `Apps/Lillist-iOS/Resources/` and `Apps/Lillist-macOS/Resources/`
  and re-running `xcodegen generate` picks it up automatically — no
  YAML changes needed.

**Evidence.** Plan 17 commits on `main` (tag
`plan-17-i18n-a11y-environments`): three `Localizable.xcstrings`
files; `LillistUI/Accessibility/` directory with
`AccessibilityEnvironment.swift`, `Announcements.swift`,
`ContrastMath.swift`; three new snapshot suites
(`LocalizationSnapshotTests`, `ContrastSnapshotTests`,
`ReduceTransparencySnapshotTests`); `.blocked` retint in
`StatusPalette`; differentiated overlay on `SyncStatusDotView` and
`SyncStatusBadge`; `.updatesFrequently` trait on error labels;
keyboard shortcuts on Recurrence + Quick Capture; focusable
`EmptyStateView`; `withAnimation` gates on `accessibilityReduceMotion`
in `RootSplitView.toggleSidebar()` and `TaskJournalTab.scrollTo`.

## 2026-05-16 — Plan 16 iOS polish: `tabViewBottomAccessory` is iOS 26, three-column iPad via env-binding, segmented detail tabs, live Quick Capture chips, monthly day grid, CommandMenu shortcuts

**Context.** Plan 16 closed the visual / navigational gap between Lillist on iOS and first-tier iOS task managers (Reminders, Things, Todoist). Changes ran the gamut from per-screen polish (empty-state CTAs, notification-permission label conditionality, trash-retention picker) to structural shifts (three-column iPad split, segmented detail tabs replacing page-style TabView, FAB lifted off the tab bar into iOS 26's `tabViewBottomAccessory` slot, hardware keyboard shortcuts moved from a hidden-Button hack into Scene-level `CommandMenu`).

**Six concrete lessons.**

1. **`tabViewBottomAccessory` is iOS 26.0+, not iOS 18.** The plan author believed Apple shipped it in iOS 18; the SDK actually marks it `@available(iOS 26.0, *)`. With a deployment target of iOS 18 the compiler refused. Trade space: (A) raise deployment target, (B) guard with `#available` and keep the old overlay as fallback, (C) skip the API entirely and use `topBarTrailing` toolbar on every NavigationStack. Three-agent panel chose A 2–1 (architect + QA prioritized single code path; UX preferred B for thumb-zone coverage). For an in-development app with no shipped users the deployment-target bump is cheap; for a shipped app the calculus flips. Rule: when the SDK contradicts a plan's claimed API availability, panel-vote the trade-off before committing — don't silently pick the path of least immediate resistance, because each `#available` guard tends to multiply across the rest of the plan.

2. **Environment-value indirection beats binding-threading for "leaf views need this state" patterns.** The plan asked us to thread `init(taskSelection: Binding<UUID?>?)` through `TodayView`, `AllTagsView`, `FiltersListView`, `FilterResultsView`, `SearchView` so iPad's three-column SplitShell could drive the detail column. But `AllTagsView` and `FiltersListView` are middle-column shells that don't render tasks themselves — they'd be carrying a pass-through binding their own code never uses. Lifting `taskSelection` into an `@Environment(\.taskSelectionBinding)` skips the intermediate layers entirely. Same observable contract, half the plumbing. Same pattern works for the Quick Capture action (`@Environment(\.quickCaptureAction)`) — empty-state CTAs deep in the view tree can fire the shell's sheet without threading a binding to every screen.

3. **Page-style TabView is for unlabeled carousels, not named functional sections.** Four named tabs in a `TabView(.page)` give the user no preview of section names, no random-access (must swipe sequentially), and no visual representation of the current selection beyond dim/lit dots. A segmented `Picker(.segmented)` anchored above a content area gives all three. Rule: if you'd write a name for each tab, use a Picker. If the content is self-describing (images, animations), use `TabView(.page)`.

4. **`@SceneStorage` for per-window state; `@AppStorage` for per-app state.** Plan 16's detail-tab selection (Notes / Subtasks / Journal / Attachments) is per-task in the current navigation flow — the user's choice should survive a back-and-forth between tasks but doesn't need to survive app relaunch on iPhone. `@SceneStorage("taskDetailTab")` is right. Recent searches are per-app and want to survive relaunch — `@AppStorage` (backed by `UserDefaults`) is right. Pick the wrong one and the persistence surprises the user (`@AppStorage`-backed tab selection would persist forever across every task, which isn't what we want).

5. **iPadOS hold-⌘ overlay only enumerates `CommandMenu` / `CommandGroup` entries.** Burying `.keyboardShortcut("n", modifiers: .command)` inside a hidden `Button.background` (the pre-Plan-16 approach in `KeyboardShortcuts.swift`) works — the shortcut fires — but it's invisible to the discovery surface. Users on iPad never learn the shortcut exists. Moving to a Scene-level `CommandMenu` makes the shortcut self-documenting via the system overlay. To bind a `Commands` struct to view state, hoist that state to the `App`-level `@State`, expose via env values for view-side consumption, and pass `Binding`s into the `Commands` body directly. Bonus: visibly rebinding `⌘N → ⌘⇧N` avoids colliding with iPadOS's reserved `⌘N` "New Window" multi-window shortcut.

6. **`SearchFieldPlacement` has no `.adaptive` case (yet) on iOS 26.** The plan's `.searchable(placement: .adaptive)` doesn't compile. `.automatic` is the closest existing intent — SwiftUI picks toolbar on iPad / drawer on iPhone — but the rule is "the plan's APIs may be aspirational; check the SDK before assuming." Same lesson surfaced once for `tabViewBottomAccessory` and a couple of times for `EnvironmentKey` default-value Sendability under strict concurrency (the env's `() -> Void` default must be `@MainActor () -> Void` so the static `let` is Sendable-safe).

**Rules.**

- For iOS apps with an iOS 18 deployment target: do not assume new iOS 18 APIs Apple announced; verify each in the SDK. The "iOS 18" floor advertised in marketing slid forward to iOS 26 for a number of polish APIs.
- For "binding from shell to leaf view" patterns where intermediate views don't use the binding, prefer `EnvironmentKey` + `Binding<T>?` env value over threading a parameter through every init.
- Four named functional sections in a detail view: use a segmented `Picker` above a switch. Reserve `TabView(.page)` for image / media carousels where indicator dots are sufficient.
- Use `@SceneStorage` for per-window UI state, `@AppStorage` for per-app preferences. Pick the wrong one and the persistence surprises the user.
- Hardware keyboard shortcuts on iPad: declare via `CommandMenu` at the Scene level (the overlay only enumerates these). Hoist any state the menu binds to up to `App`-level `@State`, expose via env values, and bind directly in the `Commands` body.
- Avoid colliding with iPadOS's reserved `⌘N` (use `⌘⇧N` instead).
- `EnvironmentKey` `defaultValue` for closure types under Swift 6 strict concurrency: type the closure as `@MainActor () -> Void` (or whatever isolation matches the consumers) so the static `let` is Sendable-safe.

**Evidence.** Plan 16 commits on `main` (tag `plan-16-ios-polish`): segmented detail tabs (`TaskDetailView`); FAB to `tabViewBottomAccessory` + topBar toolbar (deployment-target bump iOS 18 → 26); three-column iPad SplitShell + `TaskSelectionEnvironment`; unified `iPadSection`; live Quick Capture chips (`QuickCaptureTokenChips.swift`); monthly day-of-month grid (`RecurrenceEditorView.swift`) + plain-English labels + toggle-revealed limit + smart "End by" default + commit-error alert; empty-state CTAs (`QuickCaptureAction` env value); search scopes, recent searches, highlight, debounce, automatic placement; trash retention preset picker; conditional notification permission label + 750ms time-picker debounce; `LillistCommands` CommandMenu + Scene-level state hoist.

## 2026-05-16 — Plan 15 macOS chrome: toolbar over header views, MenuBarExtra over NSStatusBar, `.nonactivatingPanel` quirks, dock/Spotlight/Services integration, SceneBuilder type-checker timeouts with conditional Scenes

**Context.** Plan 15 swapped the macOS app's ad-hoc column headers for a real `.toolbar`, migrated the status item to a SwiftUI `MenuBarExtra(.window)` scene, polished the Quick Capture panel, and added system-citizen integrations (dock badge / menu, About / Help command groups, Services provider, Spotlight indexing, NSUserActivity, animated Preferences). Several non-obvious gotchas surfaced.

**Rules.**

- **`NavigationSplitView`'s `columnVisibility:` binding is the only stable handle on sidebar state.** Toolbar buttons need to flip it imperatively (and persist the result via `@SceneStorage`) — there's no "sidebar is visible" environment value to query. The Tahoe-native auto-toggle still works without the binding, but a custom toolbar button that flips it gives you a stable target for the `⌃⌘S` menu command and persistence across launches.
- **`MenuBarExtra(.window)` reanchors automatically; `.menu` style does not.** The pre-`MenuBarExtra` `NSPopover.show(relativeTo:of:preferredEdge:)` call needed manual edge selection (often wrong — anchoring `.minY` opens *into* the menu bar). `MenuBarExtra(.window)` reads the screen geometry itself and picks above-or-below correctly.
- **SwiftUI's `@SceneBuilder` type-checker can time out on conditional Scenes that wrap complex generic Scene types.** Wrapping `MenuBarExtra` in an `if let env = environment { MenuBarExtraScene(...) }` at the top level of `App.body` produced "failed to produce diagnostic for expression" — Swift's bug-report-please mode. Fix: declare the scene unconditionally and let it take an `AppEnvironment?`, rendering a placeholder when `nil`. The SceneBuilder's optional-scene support is brittle when the conditional's body contains framework types with deep generic parameter lists.
- **`@SceneStorage` is the right home for window-level UI state.** `UserDefaults` works but is the wrong shape for state that varies per window/scene. `@SceneStorage` survives window restoration, scopes per scene, and doesn't pollute `UserDefaults`. Use `UserDefaults` for state that *must* persist across launches in a per-machine way (per-source task selection, per-source sort).
- **`.nonactivatingPanel` is undone by `NSApp.activate(ignoringOtherApps:)`.** The whole point of the non-activating panel style is that the panel can be key without bringing the app forward — calling `activate(ignoringOtherApps:)` immediately after `makeKeyAndOrderFront(nil)` steals focus from the user's previous app and breaks ⌘Tab muscle memory.
- **`NSPanel.center()` always picks the primary screen.** Multi-monitor users expect floating panels to appear under the cursor. `NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? .main` is the conventional pattern; place the panel ~1/3 from the top of that screen's `visibleFrame`.
- **`.task { ... }` on a `MenuBarExtra` popover view fires once and never again.** The popover content view stays alive across open/close cycles, so `.task` doesn't re-trigger. Use `.onAppear { Task { await load() } }` (which fires every appearance) plus a `NotificationCenter` subscription on `NSManagedObjectContextDidSave` so external changes refresh the popover too.
- **`CommandGroup(replacing: .textEditing)` destroys the standard Find submenu.** Always use `CommandGroup(after: .textEditing)` if you want to *add* to a built-in menu, not replace it. The same caveat applies to `.appInfo` (replacing is fine for About — you're meant to override that), `.help` (replacing is fine; Help has no built-in items worth keeping), and `.sidebar` (use `after:` so the OS-provided "Show Sidebar" item survives).
- **`CSSearchableIndex` is upsert-shaped.** `indexSearchableItems(_:)` overwrites existing items by `uniqueIdentifier`, so re-pushing the same item on every save is correct (just inefficient). The optimization path is `NSManagedObjectContextObjectsDidChange` for per-save deltas; skip until measurement says it matters.
- **`NSAppleEventsUsageDescription` triggers a permission prompt every launch.** Don't declare it unless the app actually uses Apple Events (`NSAppleScript`, `NSAppleEventDescriptor`, `AESendMessage`, …). `NSEvent.addGlobalMonitorForEvents` uses Quartz Event Services, which doesn't need the declaration.
- **Co-compiling app-target source into a standalone test bundle pulls in its transitive dependencies.** `QuickCapturePanelController` references `AppEnvironment`, so adding it to the test bundle's `sources:` would drag in CloudKit and the full LillistCore graph. The right shape is to extract the pure logic to its own file (here: `QuickCapturePlacementMath.swift` and `IndexingMappers.swift`) and co-compile only that. The original class then delegates to the helper, keeping the production seam thin and the test surface narrow.
- **`glassBackgroundEffect()` is visionOS-only as of SDK 26.2.** The Tahoe equivalent for "Liquid Glass" on macOS isn't yet a single SwiftUI modifier — the materials API (`.regularMaterial`, `.thinMaterial`, etc.) is still the cross-platform path. When `.glassBackgroundEffect()` ships on macOS, wire it in via a `#available(macOS XX.0, *)`-guarded `ViewModifier` (the pattern is in `QuickCaptureView.swift`'s comment, ready to be uncommented).
- **`NSApp.servicesProvider` is `unowned`.** The provider instance must be held by some long-lived owner (`AppDelegate` in this app). Without a strong reference, the provider is deallocated immediately after `bootstrap()` returns and the Services menu item silently fails.

**Evidence.** Plan 15 commits on `main`: `feat(macOS): wire .toolbar on RootSplitView`, `feat(macOS): persist sidebar visibility and per-source task selection`, `refactor(macOS): convert TaskDetailView to grouped Form sections`, `refactor(macOS): migrate status bar to MenuBarExtra(.window) scene`, `feat(macOS): Quick Capture panel opens on cursor's screen, 1/3 from top`, `feat(macOS): dock badge`, `feat(macOS): Spotlight indexing`, `feat(macOS): Services menu item`, `fix(macOS): preserve standard Find submenu`.

## 2026-05-16 — Plan 14 Design System: hardcoded sizes defeat Dynamic Type; "no visual change" refactors need snapshot baselines first; SyncIndicator palette divergence

**Context.** Plan 14 introduced `LillistSpacing`/`LillistRadius`/`LillistTiming`/`LillistTypography` tokens to `LillistUI`, lifted three duplicated app-target helpers (`Color+Hex`, `SortField.displayName`, `HourMinuteDate`, `CrashReportSample`) into the shared package, and unified the per-platform `SyncIndicator → Color` switch into a single `SyncPalette` extension. The plan is a pure refactor with snapshot tests as the regression net.

**Rules.**

- **`.font(.system(size: N, weight: …))` defeats Dynamic Type.** A user who's bumped their accessibility text size to "Extra Large" gets no help from chrome that hardcodes a pixel size. Use semantic styles (`.body`, `.headline`, `.title`, etc.) wherever possible; reach for `.system(size:)` only for an SF Symbol that explicitly needs a different size from the surrounding text (a rare case, almost never the right answer for app chrome). The replacement for "I want this to look big" is `.largeTitle.weight(.light)`, not `.system(size: 64, weight: .light)`.
- **For "no visual change" refactors, pin the visuals first.** Record snapshot baselines before touching any code. If the post-refactor diff is non-zero, either (a) the token's numeric value diverged from the original literal (a bug — fix the token), or (b) you're crossing a Dynamic-Type boundary intentionally (record explicitly, note in commit). Never re-record blindly; always inspect the diff. **Corollary:** if the *pre-Plan* baseline doesn't render cleanly on the current host (font/AA drift between the snapshot author's machine and yours), refresh the baseline as a separate dedicated commit *before* starting refactor commits — otherwise post-refactor diffs conflate two sources of drift and become uninterpretable. Plan 14 hit this with four `MacOSScreenTourTests` that were stale on a Tahoe 26.2 host and had to be re-recorded as a standalone "test(ui): refresh stale baselines" commit before Task 3.
- **A `==` against an associated-value enum case is always false.** `if indicator == .inProgress` does not match `.inProgress`, because the enum is `Equatable` but `.inProgress` here is a *case-without-payload* literal that the compiler treats as `SyncIndicator.inProgress(payload: ?)`. Always use `if case .inProgress = indicator`. Surfaced as the `SyncStatusBadge.swift:20-21` bug Plan 13 fixed and Plan 14 consumed; the pattern recurs whenever someone adds `case .foo(payload: T)` to an enum that previously had a bare `.foo`.
- **One source of truth per inversion.** `SyncStatusDotView` (macOS) and `SyncStatusBadge` (iOS) each had their own `switch indicator { … }` returning a `Color`. They drifted: macOS rendered stale `.idle` as `.yellow`, iOS rendered any `.idle` as `.green`. The collapse into `SyncPalette` is the same shape as Plan 12's `HotkeyKeyTable` consolidation: when two pieces of code derive the same value from the same input, they should call through one extension method, not maintain parallel tables.
- **Audit greps catch duplicates the plan author missed.** Plan 14 flagged two `SortField.displayName` extensions to consolidate; the audit grep found a third (`TaskListSortControl.swift`) the plan didn't mention. Whether to fold extras into the in-flight plan is a real scoping call — the right answer depends on context (is the third duplicate visibly identical, or does it intentionally diverge?). When in doubt, document the residual duplicate and a follow-up rather than silently change user-visible strings without test coverage.
- **`SNAPSHOT_TESTING_RECORD=all swift test ...` is the cleanest one-shot re-record for `swift-snapshot-testing`.** Editing assertion call-sites to add `record: .all` works but leaves the test bundle in a transitional state; setting the env var for one run leaves the source untouched. Plan 14 used both: env-var for bulk re-record of expected-diff Dynamic-Type migrations, `withSnapshotTesting(record: .all) { … }` block wraps for the specific four pre-existing stale baselines.

**Evidence.** Plan 14 commits on `main`: `Tokens.swift`, `SyncPalette.swift`, `SyncPaletteTests.swift`, `Color+Hex.swift`, `JournalEntryRow.swift`, `Settings/` helpers, `Onboarding/` shared content, `humanSummary` view-model property, plus the seven app-target migration commits.

## 2026-05-16 — Plan 13 a11y & correctness sweep: pattern-matching enums with mixed-shape cases, the canonical-helper anti-pattern (inline switches), `@FocusedValue` for command gating, swipe + context actions are table-stakes on iOS

**Context.** Plan 13 closed the correctness and accessibility findings from the 2026-05-16 design review. The most consequential bug — `SyncStatusBadge` rendering nothing during a sync — was a one-line equality check (`indicator == .inProgress`) against a mixed-shape enum, paired with a `.clear` paint. Four iOS surfaces re-implemented the status-click cycle inline and drifted from the canonical `StatusCycler.nextOnClick`. macOS command-menu shortcuts (Space, ⌘D, ⌘., Tab) fired while TextFields were editing because there was no `@FocusedValue` gate. iOS list rows lacked swipe and context actions entirely. Several gesture-only interactions were unreachable from VoiceOver / Switch Control / Voice Control.

**Rules.**

- **`==` against an enum with mixed-shape cases is a footgun; prefer `if case` pattern matching.** `SyncIndicator` mixes a bare `.inProgress` case with `.idle(lastSync: Date?)` / `.error(message: String, lastSuccess: Date?)` cases that carry associated values. While the Equatable conformance is synthesized and the comparison technically works for the bare case, the convention everywhere else in the codebase (`SyncStatusDotView.swift`) is `if case .inProgress = indicator` — keeping the test style uniform avoids the question of whether two `.error` values compare equal on their messages and the temptation to special-case. Use `if case` or `switch` consistently.
- **When a shared helper exists, the inline implementation is the bug.** `StatusCycler.nextOnClick` was pinned by a test (`blocked → todo`). Four iOS files re-implemented the switch and the diverged-from-test branch (`.blocked → .started`) had been on `main` since Plan 8. The rule is mechanical: grep for `case .todo: next = .started` (or any inline status switch) anywhere outside `StatusCycler`/`StatusGlyph` and replace with the helper call. CI could enforce this with a `grep -L 'StatusCycler\.nextOnClick' Apps/Lillist-iOS/Sources/**/*.swift` linter that fails when any file mentions the cycle inline without going through the helper — out of scope here, but worth tracking.
- **macOS command-menu shortcuts must gate on `@FocusedValue`, not on `@FocusState` directly.** `@FocusState` is local to its declaring View; commands defined in a `Commands` block have no access to it. The bridge is `FocusedValueKey` + `.focusedValue(\.key, focusedState)` from the View, read in the Command via `@FocusedValue(\.key)`. When a TextField captures focus, SwiftUI clears `@FocusState`, propagating `nil` through `FocusedValue`, which disables `.disabled(value == nil)` commands. Without this, raw shortcuts like Space and Tab fire while typing and steal keys.
- **The `FocusedValueKey`'s `Value` type must be reachable from the test bundle.** Standalone macOS test bundles (`TEST_HOST=""` + `BUNDLE_LOADER=""`) can't `@testable import` the app module — so a `FocusedValueKey` whose `Value` is a nested type on a View (e.g. `RootSplitView.Column`) forces co-compiling the View *and* every dependency the View pulls in (`AppEnvironment`, `SidebarSelection`, `UIStatePersistence` …). Hoist the enum to file-level (`ListColumn` in `FocusedListColumn.swift`) so co-compiling just the focus file gives tests the type. SwiftUI's `FocusedValues` also has no public initializer, so don't write tests that try to round-trip a value through the storage directly; assert the enum surface + the gating predicate instead.
- **iOS list rows need `swipeActions` + `contextMenu` to feel native.** A `NavigationLink(value:)`-wrapped row with no swipe affordance reads as half-finished to iOS users. Leading swipe for Complete (full-swipe enabled, green tint), trailing swipe for Snooze + Delete, and a long-press context menu with Change status + Delete is the table-stakes pattern. The cost is ~30 lines per list view; the benefit is the difference between "designed for iOS" and "ported from macOS."
- **Wrap small visual controls in a 44pt hit area; keep the inner frame for visual size.** Double-`.frame` (inner small for visuals, outer 44pt for touch) is the SwiftUI idiom for HIG-compliant tap targets without changing the visible design. `.contentShape(Rectangle())` on the outer frame ensures the entire hit region is tappable, not just the inner glyph.
- **Every gesture-only interaction needs an `.accessibilityAction(named:)` equivalent.** Long-presses, swipes, drag handles — none are reachable from VoiceOver, Switch Control, or Voice Control by default. `.accessibilityAction(named: "Cycle status") { onLongPress() }` reuses the same closure so the two paths can't drift. The named action also surfaces in Voice Control's "Show Names" overlay so users see what verbs are available.
- **`Date.formatted(date: .abbreviated, ...)` honors the runner's local timezone.** Fixture dates pinned at `T00:00:00Z` for a deadline check format as the *previous* day in negative-offset zones (US Pacific is UTC-7). Use noon UTC (`T12:00:00Z`) for fixtures whose date portion matters; the abbreviated format is then stable across CI runner locales.
- **iOS-only LillistUI tests (`#if os(iOS)`) are not reachable from `swift test` on a macOS host.** `swift test --package-path Packages/LillistUI` builds for the host platform; iOS-conditional snapshot tests compile out and report "0 tests run." The current workspace also has no scheme with the `LillistUITests` target wired into an iOS test action, so these tests can only be exercised inside Xcode (or by adding the SPM test target to `Lillist-iOS.xcscheme`). Verify iOS-LillistUI changes via builds + the iOS app test bundle until the scheme gap is closed. **2026-05-17 update:** the scheme gap is now closed — `Apps/Lillist-iOS/project.yml` includes `- package: LillistUI/LillistUITests` in the test action and `xcodebuild test -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'` now runs the iOS-conditional tests. See the new entry at the top of this file for the full workflow.

**Evidence.** Plan 13 commits on `main`: SyncStatusBadge inProgress fix + snapshot; four iOS StatusCycler routings; iOS TaskDetailView consumes StatusGlyph; @FocusedValue gating + ListColumn hoist + 2 rebound shortcuts; InlineCreateField empty-tab .ignored; 44pt hit areas on StatusIndicatorView + SyncStatusBadge; QuickCaptureField chips become Buttons; TaskRowView reorder actions + fuller a11y label; FloatingAddButton a11y action; DetailHeaderView a11y double-spoken fix; swipe + context menu across TodayView / TagTaskListView / FilterResultsView / SearchView.

---

## 2026-05-15 — Zero-warning sweep: NSItemProvider's closure-less `loadItem`, `appintentsmetadataprocessor`, `NSFetchRequest` Sendable captures, View-inherited `@MainActor` on pure helpers, NSManagedObjectModel duplicate-registration runtime warnings, UIKit-delegate isolation crossings

**Context.** A `Treat warnings as errors` audit before turning on
`SWIFT_TREAT_WARNINGS_AS_ERRORS` surfaced several kinds of recurring
warnings, each pointing at a quietly broken or fragile piece of code.

**Rules.**

- **`NSItemProvider.loadItem(forTypeIdentifier:options:)` has a
  closure-less form that silently returns Void.** The
  `(NSSecureCoding?, Error?) -> Void` completion handler is *optional*.
  Calling `loadItem(forTypeIdentifier:options:)` without a trailing
  closure resolves to the completion-handler overload with
  `completionHandler == nil`, which kicks off the load and discards the
  result. The cast that follows (`as? URL`) always fails. Use the
  async overload (`try await provider.loadItem(forTypeIdentifier:)`)
  inside an `async` context instead. The Share Extension's
  `SharePayload` shipped with this bug — the share sheet never
  actually received the inbound URL — until the zero-warning sweep.
- **`appintentsmetadataprocessor` runs on every app/extension target by
  default and warns if `AppIntents.framework` isn't linked.** Auto-link
  from `import AppIntents` is enough for the compiler but isn't enough
  for the metadata processor; targets that don't define any App
  Intents still need an explicit `- sdk: AppIntents.framework` in
  their `project.yml` `dependencies:` to keep the build clean.
- **Capturing `NSFetchRequest` / `NSPredicate` in a `ctx.perform`
  closure trips the `@SendableClosureCaptures` warning.** Both Core
  Data types are unannotated for Sendability. The fix is to construct
  them *inside* the `perform` closure, capturing the inputs they're
  built from (e.g., a Sendable `PredicateGroup`) rather than the
  Core Data products themselves.
- **A SwiftUI `View`'s `@MainActor` flows through static members.**
  A pure static function declared inside `struct MyView: View` is
  main-actor-isolated even if it never touches View state. If the
  function is genuinely actor-agnostic (pure logic over plain
  values/enums), mark it `nonisolated static` so callers from any
  context — tests, background work, other actors — can use it.
- **`NSManagedObjectModel` should be loaded once per process.** Tests
  that construct multiple `PersistenceController` instances will each
  call `NSManagedObjectModel(contentsOf:)` afresh, producing distinct
  model objects that all claim the same Swift entity classes. Core
  Data logs a noisy `'<Entity>' from NSManagedObjectModel <addr>
  claims '<Entity>'` runtime warning per entity per registration —
  in our test suite, > 1100 lines. Cache the model in a
  `nonisolated(unsafe) static let` of type `Result<NSManagedObjectModel,
  LillistError>` and `try cachedModelResult.get()` from the public
  accessor. The compiled model is effectively immutable so sharing is
  safe.
- **UIKit delegate protocols that pre-date Swift 6 force an isolation
  bridge.** Protocols like `MFMailComposeViewControllerDelegate` are
  declared `nonisolated`, so a delegate-conforming class can't be
  `@MainActor`. But every documented callback fires on the main
  thread, and the work inside (`controller.dismiss`, SwiftUI state
  updates) is main-actor-only. The clean shape is:
  1. Type the user-supplied callback closure as `@MainActor`
     (`let onFinish: @MainActor (Result<…>) -> Void`).
  2. In the nonisolated delegate method, copy `self.onFinish` to a
     local first, then call into a `MainActor.assumeIsolated { … }`
     block. The local-capture step keeps the assumed-isolated closure
     from carrying `self` across the actor boundary.

**Side note.** The unsigned headless macOS test build wants
`CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
on the `xcodebuild` invocation; without those overrides Xcode 17/SDK
26 fails the entitlements-without-signature check at build time. The
overrides match how the standalone `TEST_HOST=""` bundle was already
configured.

**Bundled SwiftPM bump.** `treatAllWarnings(as: .error)` (the modern
SwiftPM API for warnings-as-errors) is only available with
`swift-tools-version: 6.2`. Bumped the manifest.

**Evidence.** See the commits in this sweep:
`SharePayload` refactored to async-resolve providers;
`PersistenceController` caches `sharedModel()`; iOS + macOS
`project.yml` files all gain `SWIFT_TREAT_WARNINGS_AS_ERRORS`,
`GCC_TREAT_WARNINGS_AS_ERRORS`, and `- sdk: AppIntents.framework`
on every app/extension/test target; `NSPredicateCompilerTests` builds
its fetch request and predicate inside the perform closure;
`HotkeyRecorder`'s encoder helpers are `nonisolated`;
`MailComposerView.Coordinator` uses the local-capture +
`MainActor.assumeIsolated` pattern with a `@MainActor` `onFinish`
closure.

## 2026-05-15 — Plan 12 Plan 11 follow-ups: parallel `record(from:)` mappers, shared key-code table

**Context.** Plan 11 added `TaskRecord.seriesID` and populated it in
the canonical `TaskStore.record(from:)` mapper. Two parallel mappers —
`SmartFilterStore.record(from:)` and `CLIBridge.LsHandler.record(from:)` —
were not updated at the time, leaving smart-filter results and
`lillist ls` output without series info. Plan 12 backfilled both with
regression tests. Separately, Plan 11's macOS hotkey stack had two
duplicated keyCode↔keyName tables (in `HotkeyRecorder` and
`GlobalHotkeyMonitor`); Plan 12 consolidated them into `HotkeyKeyTable`
with a round-trip test and exposed the test via a co-compile of
`GlobalHotkeyMonitor.swift` into the standalone macOS test bundle.

**Rule.**

- **When you add a field to a public DTO, grep the entire codebase
  for parallel mappers that construct that DTO.**
  `TaskStore.record(from:)` was not the only place that produced
  `TaskRecord`; `SmartFilterStore` and `LsHandler` each had their own
  static mapper. Adding the field with a default value in the `init`
  keeps callers compiling, but parallel mappers silently omit it.
  `grep -rn 'TaskRecord(' --include='*.swift'` surfaces every site.
- **Don't duplicate inversion tables.** When two pieces of code map
  A→B and B→A, the inversion is one source of truth: a `[(A, B)]`
  master list plus two `Dictionary(uniqueKeysWithValues:)` lookups.
  Adding a row in one place propagates to both directions.
  Duplicated tables drift silently and produce confusing round-trip
  failures.
- **`@MainActor` isolation flows through `static` members.** A
  `static func` on a `@MainActor` class is itself main-actor isolated.
  Tests calling it from a synchronous nonisolated context must be
  `@MainActor` themselves. The compiler error
  ("Call to main actor-isolated static method … in a synchronous
  nonisolated context") points at the call site but the fix is on the
  caller's annotation.

**Evidence.** Plan 12 commits on `plan-12-followups`:
SmartFilterStore + test, LsHandler + test, `HotkeyKeyTable.swift`,
both Hotkey delegates, round-trip test.

## 2026-05-15 — Plan 11 pre-UAT cleanup: stale TODO comments outlive the API they reference; URLProtocol stubbing needs per-session keying when tests run in parallel; recurrence type names are nested under `RecurrenceRule` not `CalendarRule`; SwiftPM `.copy(...)` resources can't share a basename across directories

**Context.** Plan 11 closed the loose ends found in the pre-UAT review:
the macOS sidebar's `pinned()` workaround (the comment claimed
LillistCore lacked the query; LillistCore had had it since Plan 4),
the link-preview unfurl pipeline (promised by design §3, never
shipped), the recurrence pattern editor (pulled forward from v2),
the Empty Trash buttons (no `TaskStore.purgeAll()` existed),
the macOS hotkey recorder (a text field stood in for a key-capture UI),
and the `preconditionFailure` / `fatalError` calls in shipped and
test code. Five concrete realities surfaced that future work should
not re-learn:

1. **Stale TODO comments are worse than no comment.** The
   `// TODO(Plan 7 follow-up): LillistCore lacks a TaskStore.pinned()`
   comment in `SidebarView.swift` claimed the API didn't exist; the
   API had been on `main` since Plan 4 with a passing test
   ("pinned returns all pinned tasks across the tree, excluding
   trash"). The comment outlasted the limitation. Rule: when you
   leave a `TODO(Plan N)` referencing a missing capability,
   include a one-line check in the commit message that re-derives
   the claim ("grep'd `TaskStore.pinned` 2026-05-09"), and when you
   remove the workaround, audit the rest of the codebase for the
   same comment.

2. **`URLProtocol`-based test stubbing needs per-session keying when
   tests run in parallel.** Swift Testing runs cases in parallel by
   default; a single `static var responder: ((URL) -> Response?)?`
   on a `URLProtocol` subclass is a data race when two tests inside
   the same suite construct different responders. With one consumer
   (just `LinkPreviewUnfurlerTests`) the tests happened to serialise;
   adding a second consumer surfaced the race immediately
   ("End-to-end" passing in isolation but corrupting the 404 case
   and vice versa, depending on scheduling). The fix is to key
   responders by a per-session token: every
   `StubURLProtocol.session(responder:)` writes its responder to a
   keyed dictionary under a fresh UUID and threads that UUID via
   `URLSessionConfiguration.httpAdditionalHeaders`, so each request
   `startLoading` looks up *its* responder. Public API
   (`StubURLProtocol.session { ... }`) doesn't change.

3. **Recurrence type names are nested under `RecurrenceRule`, not
   `CalendarRule`.** `RecurrenceRule.Frequency` is the canonical
   path (`CalendarRule.Frequency` does NOT exist — `Frequency` and
   `CalendarRule` are sibling members of `RecurrenceRule`).
   `CalendarRule.freq` (not `.frequency`) is the field name. When
   writing UI code that constructs rules outside `RecurrenceRule`'s
   scope, fully-qualify the type. Plan 11's Task 12-13 spec went
   through three rounds of corrections before settling.

4. **SwiftPM `.copy(...)` resources can't share a basename across
   directories in the same target.** Two `.copy("CrashReporting/Fixtures")`
   and `.copy("LinkPreview/Fixtures")` rules collide on the
   `Fixtures` basename and produce `multiple resources named
   'Fixtures'`. The fix is to rename one directory (Plan 11 went
   with `LinkPreview/HTMLFixtures`). The plan author can't see
   this from the file structure alone — the surprise is the
   SwiftPM-side basename uniqueness rule.

5. **`fatalError` in test code is a CI footgun.** Test-only
   "should never reach" branches that use `fatalError` abort the
   test runner process and surface as inscrutable "test crashed"
   without a message naming the misuse. Swift Testing's
   `Issue.record` (and XCTest's `XCTFail`) report a test failure
   with the message and let the rest of the suite continue —
   preferable in every case where a future maintainer might
   actually hit the branch.

**Rule.**

- Audit `TODO(Plan N)` comments at every plan-close milestone.
  Either resolve them or update them with the current reason they
  still apply. The same goes for "this stopgap is here because X is
  missing" comments — verify X is still missing before perpetuating
  the stopgap.
- Test fakes never `fatalError`. Use `Issue.record` / `XCTFail` and
  return a defensible default. The cost is a few lines of "what to
  return"; the benefit is CI legibility.
- For unfurl-style pipelines that combine network + parse +
  persist, abstract at the bytes boundary (return `Data?`), have
  the production type wrap `URLSession`, and stub via
  `URLProtocol` with per-session keying for parallel-safety.
  Don't share static responder state across tests.
- For SwiftPM build-tool resources, give each `.copy(...)`
  directory a unique basename across the target. The CrashReporting
  / LinkPreview collision is the canonical example.
- For recurrence types: `RecurrenceRule.Frequency`, `RecurrenceRule.CalendarRule`,
  `RecurrenceRule.AfterCompletionRule`. Fields are `freq`, `interval`,
  `byDay`, `byMonthDay`, `bySetPos`, `count`, `until` (calendar) and
  `interval` (after-completion). Don't guess at "frequency" — the
  shorter `freq` is canonical.

**Evidence.** Plan 11 commits in the `2026-05-14-pre-uat-cleanup`
branch: `de719f8` (sidebar `pinned()` fix), `cf8f561` /
`47205321` / `842ed72` / `fccb4be` / `98914df` (LinkPreview
pipeline), `c539658` / `94076c8` / `69900e4` / `f8c754d`
(Recurrence editor), `5bd92d2` / `caf66d9` / `8b932b9` (purgeAll
+ Empty Trash wiring), `2c49d1d` / `923abce` (HotkeyRecorder +
re-registration), `cba1776` (fatalError softening), `d452686`
(PersistenceController throws), `5dfab87` (snapshot tests), `e41b90c`
(design doc update).

---

## 2026-05-14 — Plan 10 onboarding + preferences: SwiftUI `.sheet` and `.fullScreenCover` content can't rely on `@Environment(AppEnvironment.self)`; `UNAuthorizationStatus.ephemeral` is `@available(macOS, unavailable)`; SwiftFilterStore has no `rename` or `create(... isPinned:)`; bootstrapping AccountStateMonitor needs an explicit `Task` to bridge actor → `@Observable` mirror

**Context.** Plan 10 wired the first-launch onboarding sheet/cover and
the cross-platform Preferences/Settings UI on top of Plans 1-9. Five
realities the plan didn't anticipate showed up during implementation:

1. **`.sheet` / `.fullScreenCover` content lives in its own SwiftUI
   environment chain.** The presenting view's `@Environment(AppEnvironment.self)`
   is NOT inherited automatically — looking it up inside the sheet
   produces a runtime crash with a confusing stack frame. The Plan 10
   panel's unanimous fix: pass the env-derived dependencies in via
   explicit constructor arguments to the sheet's root view, then
   re-inject inside that root with `.environment(env)` so descendants
   can resume the `@Environment` lookup pattern. Plan 10 commits use
   `OnboardingSheet(onboardingState:, installer:, notificationPermissions:, onCompleted:)`
   as the canonical four-arg shape.

2. **`UNAuthorizationStatus.ephemeral` is iOS-only.** Plan 10 Task 0
   added a `currentStatus()` accessor to `NotificationPermissions`
   that folds `.provisional` and `.ephemeral` into `.authorized` for
   UI purposes. Writing a single test that exercises both cases trips
   `'ephemeral' is unavailable in macOS` because Apple marks the case
   `@available(macOS, unavailable)`. Stop at `.provisional` in the
   shared LillistCore test; document that the same switch arm covers
   `.ephemeral` at runtime on iOS.

3. **SmartFilterStore exposes `update(id:_:)`, not `rename(id:to:)`,
   and `create` does not take `isPinned`.** The plan's
   `DefaultsInstallerTests."Renamed default is treated as a user filter"`
   originally called `filters.rename(id: today.id, to: "My Today")`,
   which doesn't compile. Rename via the closure shape:
   `filters.update(id: today.id) { $0.name = "My Today" }`. Likewise,
   pinning is a separate call: `filters.setPinned(id:, pinned:)` after
   `create(...)`. This matters because Plan 10's `DefaultsInstaller`
   delegates to Plan 7's `SmartFilterStore.installDefaultsIfNeeded()`
   (the existing canonical installer), so the plan's "reimplement the
   five filter specs" never had to happen — the wrapper is a one-line
   delegate.

4. **`AccountStateMonitor` is an `actor`; views need a `@Observable`
   mirror to react to state-stream changes.** The `AppEnvironment.make()`
   path can `await accountStateMonitor.currentState` once to seed the
   mirror, but views observing future changes need a `Task { for await
   state in await monitor.stateStream { … } }` started during
   `bootstrap()`. Plan 10's `startObservingAccountState()` is the
   reference pattern (with a `[weak self]` capture so the env can
   dealloc cleanly if the app ever shut down before the stream ends).
   Without this, the iCloud-required cover never auto-dismisses when
   the user fixes their account state in the Settings app.

5. **First-launch notification prompt belongs to onboarding, not the
   bootstrap path.** Plan 8 had iOS `LillistApp.loadEnvironmentIfNeeded()`
   call `await env.notificationPermissions.requestAuthorization()`
   unconditionally on every cold launch. Plan 10's design moves that
   prompt into the OnboardingScreen's "Set up notifications" button,
   so the user reads the explanation first. Removing the bootstrap
   call is non-obvious because of the dual concern: don't re-prompt
   returning users, but also don't silently lose permission-state
   visibility. The fix is simply to delete the bootstrap call;
   returning users have already responded, and `currentStatus()` can
   query the state without prompting whenever a UI surface needs to
   render the current authorization state.

**Rule.**

- For SwiftUI `.sheet` and `.fullScreenCover` content, design the
  root view to receive its dependencies via init arguments. Inject
  the parent's environment back via `.environment(env)` if descendants
  want to keep using `@Environment`. Never rely on environment
  propagation across presentations.
- For `NotificationPermissions`-shaped APIs that distinguish
  "never asked" from "user declined," add an explicit `notDetermined`
  state and a non-prompting accessor. The UI's first-launch copy is
  user-facing critical: "Tap to enable" reads very differently from
  "Go to Settings and enable" if you've already asked.
- When wrapping an actor's `AsyncStream` for `@Observable` use, kick
  off a `Task` during the env's `bootstrap()` and bridge the stream's
  values into a `@MainActor` property write. Don't rely on getter
  calls to refresh — actor properties don't fire change notifications.
- When the plan's API calls don't match reality, the right fix is
  almost always to adapt the test calls, not to change the test
  expectations or shape the production code around fictional helpers.
- When the existing implementation already covers a "Plan 10 follow-up"
  (here: `Field.tag` + `Op.isUnset` already expresses "task has no
  tags"), document the no-op in the wrapping code and skip the
  duplicate-work commit rather than introducing parallel APIs.

**Three-agent panel ruling.** The architect / QA / UX panel
unanimously chose: keep the existing `@Observable AppEnvironment`
injection (do not switch to `AppServices.shared`); wire
`AccountStateMonitor` into both apps' env; thin `DefaultsInstaller`
that delegates to `SmartFilterStore.installDefaultsIfNeeded()`; skip
snapshot tests for Plan 10 (functional permission-flow tests cover
the contract; visual snapshots are a Plan 11 candidate). The ruling
is captured in the Plan 10 task commits and applied to every
deviation in this entry.

**Evidence.** Plan 10 commits `43fb891` (NotificationPermissions
extension + UNAuthorizationStatus iOS-only handling), `024c847`
(PreferencesStore.Prefs extension), `d8d04e9` (OnboardingState),
`31392c5` (DefaultsInstaller — note the SmartFilterStore API
adaptation), `5d0ebbb` (OnboardingSheet — constructor injection
pattern), `eadab0a` (AppEnvironment wiring of accountStateMonitor +
preferencesStore + onboardingState), `581d17c` (mocked permission
flow test pattern that the iOS version `9fd3c48` reuses).

---


Scope:
- **Belongs here:** framework shape, concurrency invariants, build-system
  surprises, type-system gotchas — anything where the "right answer" isn't
  obvious from reading docs or skimming related code.
- **Doesn't belong here:** specific bug fixes (the commit explains those),
  domain decisions (the design doc owns those), or per-feature mechanics
  (the implementation plan covers them).

Entries are dated and ordered newest-first. Each entry is short — a paragraph
of context, a paragraph of rule, and a pointer to evidence (commit, RCA
artifact, test).

---

## 2026-05-14 — Plan 9 crash reporting: `.process("…xcdatamodeld")` does NOT compile Core Data models under Swift 6.2.4 / SPM CLI; the workaround is to keep the `CompileCoreDataModel` plugin AND rename its output so it doesn't collide with Xcode's auto-DataModelCompile; ISO8601 date round-trips lose sub-second precision

**Context.** Plan 9 needed Core Data tests to pass against the
LillistCore SPM target via `swift test`. After cleaning `.build`, all
Core Data tests started crashing with `LillistModel.momd not found in
bundle`. Three concrete realities surfaced:

1. **`.process("…xcdatamodeld")` does not compile the model.** Plan 7's
   engineering note claimed that "SwiftPM 6 now compiles `.xcdatamodeld`
   natively via `.process(...)`". On this toolchain
   (`swift-driver 1.127.15`, Swift 6.2.4) the resource pipeline copies
   the `.xcdatamodeld` directory into the bundle as-is — no `.momd` is
   produced. Plan 7's evidence was tainted by stale `.momd` artifacts
   left in `.build` from before the plugin removal; a fresh build would
   have failed.

2. **Re-applying the plugin re-introduces the duplicate-output error in
   workspace builds.** With the plugin back on the LillistCore target,
   `swift test` succeeds (plugin produces `LillistModel.momd`) but
   `xcodebuild` fails: Xcode's SPM integration *also* applies its
   built-in `DataModelCompile` rule to any `.xcdatamodeld` it finds in
   the source tree, and both copy commands target the same bundle path
   (`…/LillistCore_LillistCore.bundle/Contents/Resources/LillistModel.momd`).

3. **The escape hatch is to rename the plugin's output.** Change the
   plugin to write `LillistModel.spm.momd` instead of
   `LillistModel.momd`. Both producers now write distinct filenames into
   the bundle; no collision. `PersistenceController.sharedModel` falls
   back from `LillistModel.momd` (preferred — what `xcodebuild` produces
   via DataModelCompile) to `LillistModel.spm.momd` (what the plugin
   produces in `swift test` / `swift build`). Both code paths load the
   same model and tests pass in both contexts.

4. **`Date` ISO8601 round-trips drop sub-second precision.** The
   crash-canary file uses `JSONEncoder` with
   `dateEncodingStrategy = .iso8601`, which serializes only to
   second-granularity (e.g. `"2026-05-14T20:28:24Z"`). Comparing a
   `Date(timeIntervalSinceNow: 0)` to its decoded equivalent
   `XCTAssertEqual`s as not-equal because the original has nanoseconds
   and the decoded does not — and Swift's default `Date.description`
   formats both identically, making the failure look like the assertion
   library is broken. Tests that round-trip a `Date` through ISO8601
   should pin fixtures to whole-second timestamps:
   `Date(timeIntervalSince1970: 1_500_000)`.

5. **`LogRedactor` path passes need a lookahead to handle macOS paths
   with literal spaces.** The naïve `~/[^\s]*` stops at the first space,
   so `~/Library/Application Support/Lillist` only redacts to
   `<path> Support/Lillist` — leaving a real path fragment in the
   "preview what will be sent" sheet. The fix is to allow a literal
   space inside the path *if* the next character is a capitalized
   letter: `~/(?:[^\s]|\s(?=[A-Z][a-z]))*`. Apply symmetrically to the
   `/Users/<name>/...` and `/var/mobile/Containers/...` patterns. Risk:
   over-redacts capitalized-word-after-path-prefix text like
   `~/Foo Bar baz` → `<path> baz` (eats `Bar`). Acceptable per
   redactor's "prefer over-redaction" stance.

**Rule.**

- When writing tests that round-trip `Date` through `JSONEncoder`'s
  `.iso8601` strategy (or `ISO8601DateFormatter`), pin fixtures to
  `Date(timeIntervalSince1970: N)` with `N` an integer. Don't use
  `.now`, `Date()`, or any non-integer interval — sub-second precision
  loss will make equality comparisons false-fail in confusing ways.
- For SwiftPM build-tool plugins that produce a resource that *might*
  collide with Xcode's built-in compiler for that file type
  (DataModelCompile, AssetCatalogCompile, etc.), give the plugin's
  output a distinct filename and let the consuming code fall back
  through both names. Trying to suppress Xcode's auto-compile via build
  settings or by manipulating the `resources:` declaration didn't work
  in 2026-05-14 testing; the rename is the only clean cross-tool path.
- Don't trust prior engineering notes' claims that "SPM auto-compiles
  X" without a fresh-`.build` repro on the current toolchain — Plan 7's
  similar claim about `.xcdatamodeld` was wrong, almost certainly due
  to a stale-artifact false negative.
- For redactors that pattern-match macOS paths, account for literal
  spaces inside known path components (`Application Support`,
  `Mobile Documents`, etc.). The cheapest fix is a
  `\s(?=[A-Z][a-z])` lookahead inside the path body.

**Evidence.** Plan 9 commits `e86cbd0` (preference + plugin re-apply),
`71a2546` (rename plugin output to `.spm.momd` + macOS app wiring),
`265eddb` (CLI ISO8601 date fixture rule), `e2bfd3c` (LogRedactor
greedier path regex with three-agent panel ranked-choice ballot
captured in commit message).

---

## 2026-05-14 — Plan 8 iOS app: AppIntent metadata must be `static let` under Swift 6; `@Parameter` wrappers can't be set via `init()`; App Group container is the only path for app/extension store sharing; standalone iOS test bundle (`TEST_HOST=""`) cannot `@testable import` the app module; `Foundation.localizedStandardContains("")` returns `false`

**Context.** Five gotchas surfaced while wiring up the iOS app, Share
Extension, and App Intents extension on top of the macOS work from
Plan 7.

1. **AppIntent metadata must be `static let`, not `static var`, under
   Swift 6 strict concurrency.** `AppIntent`'s protocol requirements
   (`title`, `description`, `openAppWhenRun`, `isDiscoverable`,
   `typeDisplayRepresentation`, `caseDisplayRepresentations`,
   `defaultQuery`) are declared `var x: T { get }` — but you satisfy
   them with `static let x: T` and side-step "nonisolated mutable
   global state". Plan 8 commit `0d45a36` does this across every
   intent / entity / enum file.

2. **`@Parameter`-wrapped properties can't be set via `init()`.** The
   property wrapper makes the stored type `IntentParameter<T>`, not
   `T`. To prefill an intent value before passing to
   `.result(opensIntent:)`, construct the intent with `init()` and
   then assign through the wrappedValue:
   ```swift
   var inner = OpenTaskInAppIntent()
   inner.taskID = task.id.uuidString
   return .result(opensIntent: inner)
   ```
   You also need an explicit `init() {}` on the helper intent if you
   want the no-arg constructor — synthesized inits are problematic
   when only `@Parameter` fields exist.

3. **Sharing the SQLite store between the iOS app and its extensions
   requires App Group container URL.** `FileManager.containerURL(
   forSecurityApplicationGroupIdentifier:)` returns the per-group
   sandbox directory; both the main app and every embedded extension
   point their `PersistenceController` at the same SQLite file inside
   that directory. `FileManager.default.homeDirectoryForCurrentUser`
   is macOS-only — `NSHomeDirectory()` is portable but inside the
   per-app sandbox on iOS, so it doesn't satisfy the sharing
   requirement. Plan 8 added `StoreConfiguration.appGroupOnDisk(
   groupID:)` to LillistCore for this.

4. **A standalone iOS test bundle (`TEST_HOST=""` + `BUNDLE_LOADER=""`)
   cannot `@testable import` the app module.** With no test host the
   app target's symbols aren't reachable from the test bundle. Two
   options: (a) test the underlying LillistCore/LillistUI paths
   (preferred — the app code is mostly glue, and the cores have their
   own deep coverage); (b) co-compile specific source files into the
   test bundle via `sources: - path: ../../Extensions/.../X.swift`
   in `project.yml`. Plan 8 uses (b) for `SharePayload.swift` so its
   pure-decode logic gets tested without a signed host.

5. **`Foundation.localizedStandardContains("")` returns `false` on
   iOS 18.** Counterintuitive — you might expect "every string
   contains the empty string". The practical consequence: a search
   path that does `title.localizedStandardContains(query)` won't
   accidentally return every task when the query is empty. That's
   safe default behavior but worth pinning with a regression test in
   case Foundation changes its mind.

**Rule.**

- For every `AppIntent` / `AppEntity` / `AppEnum` declaration in Swift
  6, use `static let` for metadata (`title`, `description`,
  `openAppWhenRun`, `isDiscoverable`, `typeDisplayRepresentation`,
  `caseDisplayRepresentations`, `defaultQuery`). Use `static var` only
  for accessors that genuinely compute, e.g. `parameterSummary`.
- To prefill an `@Parameter` value in a helper intent, call its
  `init()` and assign to the wrappedValue. Never try to pass through
  a custom init that takes the parameter value directly.
- For any iOS app that ships extensions, point `PersistenceController`
  at the App Group container URL via
  `StoreConfiguration.appGroupOnDisk(groupID:)`. Falling back to
  `defaultOnDisk` (per-app Application Support) silently breaks the
  sharing contract.
- For standalone iOS test bundles, design tests against LillistCore /
  LillistUI surfaces, not against the iOS app module. When a specific
  iOS-app source file needs coverage and is pure (no UIKit-only
  dependencies), co-compile it into the test bundle via project.yml.
- Don't assume `localizedStandardContains` matches everything on an
  empty needle; assert the actual behavior in a test.

**Evidence.** Plan 8 commits `0d45a36` (Swift 6 fixes), `905d0a5`
(App Group plumbing), `a3f9d08` (SharePayload co-compile),
`184b2ef` (empty-query regression test).

---

## 2026-05-14 — Plan 7 macOS app: SwiftPM 6 + Xcode SPM both auto-compile `.xcdatamodeld`; macOS SwiftUI View snapshots need `NSHostingView`; xcodegen path resolution; entitlements need development cert for `xcodebuild`; XCTAssert autoclosures don't accept `try await`

**Context.** Five concrete gotchas surfaced while wiring up the macOS
app on top of the SwiftPM packages built in Plans 1–5.

1. **Swift Package Manager 6 compiles `.xcdatamodeld` natively, and
   so does Xcode's SPM integration.** Plan 1 shipped a
   `CompileCoreDataModel` build-tool plugin that ran `momc`. Under SPM
   CLI (`swift build`) the plugin produced `LillistModel.momd` and the
   resource pipeline silently de-duplicated. Under `xcodebuild`
   consuming the same package from a workspace, both the plugin and
   Xcode's `DataModelCompile` task ran, hitting "Multiple commands
   produce …/LillistModel.momd". The fix: remove the plugin and rely
   on SwiftPM's `.process("LillistModel.xcdatamodeld")` resource entry
   alone. SPM 6 + Xcode 17 both handle it. Plan 7 commit
   `7715ec0` does this.
2. **`swift-snapshot-testing` 1.17 has no macOS SwiftUI `View`
   snapshot strategy.** The plan's `SnapshotEnvironment` extension
   tried to declare `Snapshotting where Value: View, Format == NSImage`
   and call `.image(size:traits:)` directly. On macOS the library
   provides image strategies only for `NSView` /
   `NSViewController` — not for SwiftUI `View`. The fix is to host
   each SwiftUI view in an `NSHostingView` and snapshot the resulting
   `NSView`. Helper: `makeHostingView(_:size:) -> NSView`.
3. **xcodegen path resolution is anchored at the spec file's
   directory.** Generating the project with `xcodegen generate --spec
   project.yml --project Apps` from a repo-root `project.yml` stored
   `Apps/Lillist-macOS/Sources` as the source path *literally* —
   which Xcode then resolved against `$(SRCROOT) = Apps/`, yielding
   `Apps/Apps/Lillist-macOS/Sources/`. The fix is to put `project.yml`
   inside `Apps/` so source paths are relative to the project
   location, and to drop the `info:` / `entitlements:` blocks from
   the YAML (xcodegen regenerates default minimal versions of those
   files on every run, clobbering hand-written contents — just set
   `INFOPLIST_FILE` and `CODE_SIGN_ENTITLEMENTS` in build settings
   instead).
4. **The macOS entitlements in this repo require a development
   signing identity for `xcodebuild build`.** App-group +
   iCloud-container-identifiers + CloudKit-services entitlements all
   trigger Xcode's "requires signing with a development certificate"
   gate. Headless CI / CLI builds work with
   `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
   CODE_SIGNING_ALLOWED=NO`. With those flags the test bundle can't
   load a fully-signed `.app` host, so the macOS test target is
   configured with `TEST_HOST=""` and `BUNDLE_LOADER=""` as a
   standalone bundle. The plan's test bodies were rewritten to import
   only `LillistCore` / `LillistUI`, never `@testable import
   Lillist_macOS`, so this works.
5. **`XCTAssertEqual(try await store.foo(), expected)` doesn't
   compile.** XCTAssert's autoclosures are non-async, so a `try
   await` inside trips
   `'async' call in an autoclosure that does not support concurrency`.
   The fix is mechanical: `let v = try await store.foo();
   XCTAssertEqual(v, expected)`.

**Rule.**

- Use SwiftPM's native `.process("Foo.xcdatamodeld")` resource
  declaration; do NOT layer a build-tool plugin on top of it.
- For macOS SwiftUI view snapshots, host the view in `NSHostingView`
  first; the snapshotter only knows about `NSView` /
  `NSViewController` on macOS.
- Place `project.yml` in the same directory you want xcodegen to
  generate the `.xcodeproj` into; leave the `info` / `entitlements`
  blocks out and use build settings to point at hand-written files.
- For headless macOS app builds with CloudKit / app-group
  entitlements, expect to pass code-signing-disabled flags. Configure
  the test target to be standalone (no host) so it builds without a
  signed `.app`.
- Never embed `try await` inside XCTAssert; compute the value first.

**Evidence.** Plan 7 commits `7715ec0`, `40ca007`, `2caa014`,
`93333dc`. The new build-system gotcha is captured in this note;
the macOS snapshot-testing one is enshrined in
`Packages/LillistUI/Tests/LillistUITests/Helpers/SnapshotEnvironment.swift`.

---

## 2026-05-14 — Plan 6 CLI: NSPredicate is non-Sendable, hex-only fuzzy tokens collide with UUID prefix routing, `localizedStandardContains` does not fold diacritics, and the `@main` annotation conflicts with a `main.swift` file

**Context.** Three concrete gotchas surfaced while building the `lillist` CLI
(see commits `0ab5e94`, `2a2b7a5`, `1771301`):

1. **`NSPredicate` is not `Sendable` in Swift 6.** Capturing a pre-built
   predicate into a `context.perform { ... }` closure trips
   `[#SendableClosureCaptures]` even though `NSManagedObjectContext.perform`
   itself runs on its own queue. The strict-concurrency-clean shape is to
   build the predicate **inside** the perform closure from a `Sendable`
   `PredicateGroup`. See `LsHandler` and `EvalHandler`.
2. **Hex-only tokens like `cafe` route to UUID-prefix matching, not title
   substring.** Design Section 6 says "tokens matching `^[0-9a-f]{4,}$`
   resolve as UUID prefixes." That rule preempts the title path even when
   the user typed an English word that happens to be all-hex (`cafe`,
   `face`, `dead`, `beef`). Tests for diacritic folding must use a token
   with at least one non-hex character (`naive`, `resume`).
3. **`localizedStandardContains` is unreliable for diacritic folding.** It
   does case folding but its diacritic behavior depends on the current
   locale. The robust path is to fold both sides explicitly via
   `applyingTransform(.stripDiacritics, reverse: false)`, then case-fold
   via `lowercased()`, then `contains`. See `Resolver.foldedContains`.
4. **`@main` on a type cannot coexist with a `main.swift` file in the same
   executable target.** SwiftPM treats `main.swift` as the entry point and
   `@main` is rejected. Plan 6 Task 1 had the executable target use only
   `@main`; Task 24 swapped to a `main.swift` that calls
   `Lillist.runWithExitCodes()` and removed the `@main` annotation. Both
   are valid; pick one and don't ship both.
5. **`ISO8601DateFormatter` is not `Sendable` and cannot be a `static let`
   under strict concurrency** — it triggers `[#MutableGlobalVariable]`.
   Construct it per-call inside the function that needs it; instantiation
   is cheap.

**Rule.**

- Build any `NSPredicate` *inside* the `context.perform` closure that uses
  it. Pass `Sendable` value types (`PredicateGroup`, `UUID`, `String`,
  `Date`) across the boundary, not predicates.
- When the design specifies a UUID-prefix routing rule, design test
  fixtures so all-hex words (`cafe`, `dead`, `beef`) are not used as
  title-substring inputs. Document the precedence rule in the resolver's
  doc comment.
- For substring matching that needs both case- and diacritic-insensitivity,
  always fold via `applyingTransform(.stripDiacritics, reverse: false)`
  before `lowercased().contains(...)`. Don't rely on
  `localizedStandardContains`.
- For executable targets, choose either `@main` on a type or a `main.swift`
  file with top-level code, never both.
- For `Foundation` formatter types that aren't `Sendable`
  (`ISO8601DateFormatter`, `DateFormatter`, `JSONEncoder`/`Decoder` are
  `Sendable` since macOS 14), construct them per-call rather than as
  static singletons under strict concurrency.

**Evidence.** `git show 0ab5e94 1771301 9e9f37d 2a2b7a5`.

---

## 2026-05-14 — Swift 6 strict concurrency in the test target; `@preconcurrency import UserNotifications`; `OSAllocatedUnfairLock`

**Context.** Plan 5 (notifications layer) needed an `actor`-based
`FakeUserNotificationCenter` per its written code. Three concrete
strict-concurrency surprises came up:

1. **The test target IS strict in Swift 6 mode.** The earlier project
   note "the test target is not strict, so concurrency bugs surface at
   runtime" was wrong. With `swift-tools-version: 6.0`, Swift 6 language
   mode is on for the whole package; the `-enable-experimental-feature
   StrictConcurrency` flag on the source target is redundant on Swift 6
   and the test target inherits strict checking.
2. **`@preconcurrency import UserNotifications` only relaxes individual
   `UN*` arguments, not collection-typed ones.** It fixes
   `func add(_ request: UNNotificationRequest)` crossing an actor, but
   returning `[UNNotificationRequest]` or `Set<UNNotificationCategory>`
   from an actor method still trips `non-Sendable result can not be
   returned from actor-isolated instance method to nonisolated context`.
   For a fake that owns a list of `UN*` values, the cleanest shape is a
   `final class @unchecked Sendable` backed by
   `OSAllocatedUnfairLock<State>` — see Plan 5 commit
   `01f47a2` and the architect/QA/UX panel ruling captured in the commit
   message.
3. **`NSLock.lock()/unlock()` is unavailable from async contexts in
   modern SDKs.** The async-safe alternative is `OSAllocatedUnfairLock<State>`
   with `state.withLock { ... }`. Stored properties on a `final class
   @unchecked Sendable` become `private let state =
   OSAllocatedUnfairLock<State>(initialState: State())`, mutated only
   inside the closure.
4. **Capturing actor-isolated dictionaries into non-async closures
   (`compactMap`, `filter`, …) triggers `SendingRisksDataRace`.** Even
   when the enclosing function is on the actor and the closure is
   non-`@Sendable`, the compiler diagnoses possible concurrent access.
   The mechanical fix is to rewrite the closure-based code as a
   `for ... in` loop in the actor-isolated function body — no closure,
   no capture, no diagnostic.

**Rule.**

- For test doubles of `UserNotifications`-like APIs, prefer
  `final class @unchecked Sendable` + `OSAllocatedUnfairLock<State>`
  over `actor + nonisolated func X() async { await self._X() }`. Expose
  inspection state through `async` accessor methods that return Sendable
  snapshots (e.g. `func addedRequests() async -> [UNNotificationRequest]`).
- Reach for `@preconcurrency import` first when an external-framework
  type without `Sendable` conformance crosses an isolation boundary,
  but be prepared to fall back to `@unchecked Sendable` wrappers if a
  collection of those types needs to flow.
- If the compiler complains about `SendingRisksDataRace` in
  `compactMap`/`filter`/`map` over an actor-isolated dictionary,
  un-functional-ize the loop. The performance cost is nil; the
  diagnostic disappears.

**Evidence.** Plan 5 commits `01f47a2`, `ef16409`, `bb38508`.
`Packages/LillistCore/Tests/LillistCoreTests/Helpers/FakeUserNotificationCenter.swift`
is the canonical example of the lock-based fake shape.

---

## 2026-05-14 — `Task { same-actor-method() }` is almost always wrong; `Task.yield()` is not a barrier

**Context.** While running Plan 4 implementation, the test
`SyncStatusMonitorTests."Failed export records the error and clears
inProgress"` flaked once. Root-cause investigation (`.rca/sync-status-monitor-event-drop/`)
revealed two distinct ordering hazards in
`Packages/LillistCore/Sources/LillistCore/Sync/`:

1. **Deferred registration via Task wrapper.** `CloudKitEventBridge.eventStream`,
   `SyncStatusMonitor.statusStream`, and `AccountStateMonitor.stateStream`
   each wrapped their `self.register(id:continuation:)` call in
   `Task { ... }`. The getter returned before the registration ran, so any
   `recordEvent` that arrived in that window iterated an empty `continuations`
   dictionary and silently dropped the event. AsyncStream's `.unbounded`
   buffer was fine — the bug was upstream: `continuation.yield(...)` was
   never called, so nothing landed in the buffer.

2. **Yield-polling as a synchronization primitive.** Tests used
   `for _ in 0..<5 { await Task.yield() }` between `recordEvent` and the
   subsequent `currentStatus` read, expecting that to "let the consumer
   catch up." Empirically: 26 reorders / 1000 trials of two `await
   monitor.X()` calls on the same actor. Under cooperative-pool contention
   (parallel test execution), the test's read can win the race against the
   consumer's `apply()` and return pre-apply state.

**Rule.**

- **Same-actor synchronous calls do not need `Task { }` wrappers.** Inside
  an actor-isolated context (including the builder closure of
  `AsyncStream { continuation in ... }` when the enclosing computed property
  is on an actor), call same-actor methods directly. Swift 6 strict
  concurrency permits it; the compiler will not warn or error. Wrapping the
  call in `Task { }` defers it to a later executor tick for no benefit, and
  creates an ordering hazard between the actor-isolated function returning
  and the deferred call running.
- **`Task.yield()` is a cooperative-scheduling hint, not a synchronization
  primitive.** It raises the probability that other tasks run before
  resumption; it does not establish happens-before with any specific task.
  Adding more yields raises probability but never reaches certainty.
- **When the compiler emits "no async operations" inside `Task { method() }`,
  the surrounding scaffolding is usually unnecessary — drop the `Task`, not
  just the `await`.** The four "drop redundant await on same-actor X
  registration" commits in `Sync/` (`e2a3a5f`, `f310020`, `7049a3f`,
  `3b5f59f`) silenced the warning by removing the `await` but kept the
  `Task` — which left the race intact. The warning was pointing at the
  whole scaffold, not the keyword inside.
- **For async-event pipelines, the canonical observation primitive is the
  stream's iterator, not a synchronous snapshot read.** Tests that need to
  observe downstream effects should use `var iterator = await source.stream.makeAsyncIterator(); _ = await iterator.next()` as the wait
  point. `iterator.next()` only returns when a value has been yielded —
  that yield is downstream of the work it depends on, so it's a real
  happens-before barrier. Synchronous reads (`actor.currentStatus`,
  `actor.currentState`) are for snapshot/debug use, after the observer has
  synchronized via the stream.

**Evidence.**
- RCA artifacts: `.rca/sync-status-monitor-event-drop/` (SYMPTOM, EVIDENCE,
  HYPOTHESES, CHALLENGER, VERIFICATION, REMEDIATION).
- Runnable verification: `.rca/sync-status-monitor-event-drop/scratch/exp1-9.swift`
  (AsyncStream pre-iterator buffering, Swift 6 isolation inference, actor
  non-FIFO, iterator pattern as barrier, etc.).
- Fix commit: `2db9a69` (fix(sync): register AsyncStream continuations
  synchronously…).
- Production blast radius improvement: the fix also closed a small leak
  window in `CloudKitEventBridge.attach(to:)` where `detach()` could race
  ahead of a deferred `setObserverToken` write.

**Generalize when.** Any new use of `AsyncStream { ... }` inside an actor,
any test that observes downstream effects across actor boundaries, any
`Task { }` you're about to write inside an already-actor-isolated function.
