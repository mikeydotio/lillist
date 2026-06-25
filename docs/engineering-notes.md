# Engineering Notes

Append-only log of cross-cutting engineering lessons learned while building
Lillist. Each entry captures a non-obvious gotcha — usually one that took real
investigation to find — so future work doesn't re-learn it the hard way.

## 2026-06-19 — Drag-reorder: gap+horizontal-depth model, de-parent fix

The drag-reorder resolver moved from a vertical-only 25/50/25 zone model (with a
middle "onto" zone for nesting) to a **gap + horizontal-depth** model, reversing
the explicit *non-goal* in `docs/plans/2026-05-26-drag-reorder-redesign-design.md`
("Indent/outdent via horizontal cursor movement"). Vertical position now picks a
*gap* between two reference rows; horizontal translation picks the *depth* within
that gap's valid range (`min = below.depth`, `max = above.depth + 1`), Reminders-
style. The `.onto` target/gesture was removed entirely; nesting under a childless
or collapsed parent is a `.between` with no anchors → `reparent`-append.

Three non-obvious traps:

1. **De-parent to top level was silently refused.** `TaskStore.reorder` inferred
   the parent as `afterParent ?? beforeParent ?? m.parent`, which cannot tell
   "top level" (`nil`) apart from "no anchor info" — so dragging a child above
   its top-level parent collapsed back to the current parent. Fix: the resolver
   now carries an **authoritative** `parentID` (`DragTarget.between`), threaded
   through `DragMutation.reorder(parent:)` to `TaskStore.reorder(…, parent:)`
   with a `ReparentTarget.explicit(UUID?)` (default `.infer` preserves every
   existing caller/test). Never re-infer a parent the UI already resolved.

2. **The dragged row's subtree must be excluded from the reference list, by
   walking parent links — not by visibility.** During a drag only the dragged
   row itself is hidden (`opacity 0`); its descendants stay visible and still
   occupy slots. If they're left in the reference list a parent can resolve to
   its own child. Exclusion relies on `flatRows` being DFS-ordered (one forward
   pass propagates the excluded set).

3. **The depth-aware drop indicator needs platform-specific inset math.** On iOS
   every row reports a *full-width* frame (depth is rendered *inside* via a
   leading spacer), so all `frame.minX` are equal and the divider insets by
   `targetDepth * indentPerLevel`. On macOS `OutlineGroup` shifts each row's
   *frame* by its depth, so the divider insets by the *delta*
   `(targetDepth − referenceDepth) * macOutlineIndentPerLevel`. `DragOverlay`
   takes an `indentLeadingX` closure; iOS uses the default, macOS passes its own.
   `macOutlineIndentPerLevel` (16 pt) approximates OutlineGroup's private indent
   metric and is **tunable on-device**.

macOS gets horizontal depth too: once the axis arbiter commits to `.vertical`
(see 2026-06-18) the horizontal component is free to drive depth — so reorder is
"drag down to start, then sideways to nest." The horizontal *feel* (dead-zone,
baseline = keep-current-nesting, the macOS indent step) is empirical and must be
verified on device; unit tests pin the depth-derivation math, not the feel.

## 2026-06-18 — macOS trackpad swipe coexists with reorder via axis-gating

When the status cycle went one-way (forward-only; reset moved off the tap),
macOS lost its only "send a task backward" affordance — Space used to un-start,
and the iOS "Mark open" swipe is iOS-only. The fix gives macOS the same leading
"Mark open" trackpad swipe on task rows.

`SwipeableRow`/`SwipeActionSpec` were already pure SwiftUI (no UIKit) despite an
`#if os(iOS)` gate, so generalizing was just un-gating + making the type
`public`; the file moved to `Components/SwipeableRow.swift`.

The hard part is gesture arbitration. On iOS the reorder is long-press gated
(0.3 s), so a quick horizontal flick fails it and reads as a swipe. **macOS
reorder has no long-press gate** — it's a bare `DragGesture(minimumDistance: 4)`
(`DragReorderable`'s `#else` branch) that begins on *any* 4 pt drag, horizontal
included. A naive swipe + reorder would both claim a horizontal pan.

Resolution: the macOS reorder gesture now **commits to an axis** on first
movement (`DragAxisArbiter`, unit-tested) and only begins a reorder for a
`.vertical` commit; a `.horizontal` commit is yielded to the swipe (the reorder
returns early and never touches the controller). The swipe's own axis check
(horizontal-only) makes the pair mutually exclusive regardless of which gesture
SwiftUI recognizes first. Ties (diagonal) favour vertical so reorder — the
row's primary gesture — wins ambiguous drags. The commit distance (8 pt,
`LillistDragTokens.macReorderAxisCommitDistance`) sits between reorder's 4 pt
min and the swipe's 10 pt commit.

Scope: leading "Mark open" + trailing "Delete" (soft-delete to Trash,
recoverable — mirrors iOS), but **not in Trash** itself (where reset/delete
semantics differ; both edges are suppressed there). As with iOS, the trackpad
feel (which gesture wins a near-45° drag, rubber-band, full-swipe threshold) is
**empirical and must be verified on a real trackpad** — the unit tests pin the
decision boundary, not SwiftUI's runtime recognizer arbitration.

## 2026-06-17 — Custom row swipe can't share a cell with `.swipeActions`; removing default notifications

**Swipe vs. the custom drag.** `.swipeActions` is a UIKit-layer `List`
feature: it natively arbitrates horizontal-swipe vs. vertical-scroll, but it
loses every time to a SwiftUI `DragGesture` placed on the cell's content. The
iOS task rows carry exactly such a gesture (the `DragController` long-press
reorder, on the inert label region). So even though `TasksScreen` still had a
`.swipeActions(edge: .trailing) { Delete }` block, the drag recognizer claimed
the horizontal pan the instant the finger landed and swipe-to-delete silently
never fired. This is the same family as the 2026-06-12 / 2026-06-17 reorder
regressions: a control with an intrinsic gesture and the long-press drag can't
both own the same region.

The fix is `Packages/LillistUI/.../iOS/Tasks/SwipeableRow.swift`: drop
`.swipeActions` and own *both* gestures so arbitration is deterministic, not
left to UIKit. Mechanics that matter:
- The swipe gesture is a `simultaneousGesture` (not `.gesture`) so it runs
  *alongside* the List's scroll rather than starving it. It commits to an axis
  on the first ≥10 pt of movement and **returns early for vertical drags**, so
  the scroll keeps the touch.
- The reorder long-press (0.3 s) is what disambiguates: a quick horizontal
  flick fails it and reads as a swipe; a held drag reads as reorder. A hard
  gate (`isReorderActive = dragController.state != .idle`) disables the swipe
  entirely once a drag is confirmed, so a diagonal reorder can't trip Delete.
- "One row open at a time" is a `@Binding openRowID` threaded from
  `TasksScreen`; an open row overlays a transparent tap-catcher so a tap
  closes it instead of opening the editor.
- Tuning (`actionWidth`, `fullSwipeThreshold`, axis ratio, rubber-band) is
  empirical — `.swipeActions`' scroll arbitration is free; rolling our own
  means verifying on the simulator/device.

**No default notifications (app-wide).** Setting a `start`/`deadline` used to
auto-create a `defaultStart`/`defaultDeadline` `NotificationSpec` inside
`NotificationScheduler.reconcile` (`materializeDefaultSpecs`). That is gone:
the method is now `purgeDefaultSpecs` — it creates nothing and deletes any
existing default specs, so legacy ones are cleaned up on the next reconcile
and only user-added reminders (`offsetStart/offsetDeadline/nudge`) ever fire.
The *machinery* survives: `resolvedAnchorDate` (all-day → default time) and the
DST-safe `makeCalendarTrigger` are still used by **offset** reminders, and
`updateDefaultAllDayTime` reschedules by all-day *anchor* (not spec kind), so
all of Layer 2 / DST / preference-change behavior is still exercised — the
tests for those were converted from bare-date defaults to `addOffset(…, 0)`.
Blast radius was wider than "a few tests": every scheduler suite that scheduled
by setting a date alone had to move to a user reminder (Layer1, Layer2AllDay,
DST, PreferenceChange, StatusTransitions, ConcurrentReconcile, RestoreSteady,
and the live-swap `MigrationCoordinatorRestoreTests`). Suites driven by nudges
or manual specs (Nudge, Snooze, SnoozeAction, CrossDeviceDedup) were untouched.

## 2026-05-17 — Plan 20a IOSScreenTourTests refactor: container/presenter split for testable iOS screens

**Context.** Plan 20a executed the deferred Task 4 from Plan 20. The
five primary iOS Tab screens (`TodayView`, `AllTagsView`,
`FiltersListView`, `SearchView`, `SettingsTab`) used to live entirely
in `Apps/Lillist-iOS/Sources/` because they read `@Environment(AppEnvironment.self)`
and the iOS app bundle is not `@testable import`-able from the
LillistUI snapshot suite. The tour at
`Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift`
worked around the gap by rebuilding each screen visually from inline
mock chrome (`tabScaffold`/`navBar`/`tabBar`/`tagRow`/`filterRow`/etc.) —
which meant the tour was testing *fake* screens, not the real
composition users see.

Plan 20a's goal: make the tour test the real screens. The migration
moves each screen's composition into
`Packages/LillistUI/Sources/LillistUI/iOS/Screens/<Tab>Screen.swift`,
turns the app-target view into a thin wrapper that owns the
`AppEnvironment` machinery, and rewrites the tour to instantiate the
real Screens with frozen mock data.

**Rules.**

- **Container/presenter split is the right pattern when a SwiftUI
  view's "data needs" can't cross a test boundary.** The migrated
  Screens are *pure presentation*: data + action closures in via
  `init`, no `@State`, no `.task`. The app wrapper owns the
  `@State results`, the `.task { await reload() }`, the AppEnvironment
  reads, and the `.navigationDestination` (the destination view
  references iOS-app types like `TaskDetailView` that LillistUI can't
  import). The tour test then constructs the Screen with hardcoded
  records, no async loader to race. This produces deterministic
  snapshot tests — no Combine timing flake risk, no need for
  `Task.yield()` barriers (which aren't happens-before barriers
  anyway, per the May 12 entry).
- **Settings is the awkward case — pull only the chrome up, leave
  the env-coupled sections down.** The iOS Settings sub-sections
  (`GeneralSection`, `NotificationsSection`, `TrashSection`,
  `QuickCaptureSection`, `CrashReportingSection`, `AdvancedSection`)
  reach deep into `AppEnvironment` (NotificationPermissions,
  NotificationScheduler, TaskStore.purgeAll, Persistence, build/os
  metadata, and debounced `.task(id:)` writebacks). Migrating *those*
  into LillistUI would be a scope explosion. The right design is a
  `SettingsScreen<SectionsContent: View>` generic that owns the
  NavigationStack + Form + title + Done toolbar but takes the sections
  as a ViewBuilder; the iOS app target passes the real sections in,
  and the tour passes mock placeholders. `[AnyView]` was rejected
  because it erases section identity and breaks Form's grouped
  styling.
- **DTOs without explicit public memberwise inits aren't actually
  public.** `SmartFilterStore.SmartFilterRecord` had only
  `public var` fields and relied on Swift's synthesized memberwise
  init, which is `internal` by default even when all fields are
  public. Constructing one from the tour suite failed with
  "initializer is inaccessible due to 'internal' protection level."
  `TaskStore.TaskRecord` already had a hand-written public init —
  the gap shows up only the day a caller outside the defining
  module needs to fabricate the type. Cure: every public DTO with
  public fields needs an explicit public init.
- **SwiftUI `View` static helpers default to MainActor; mark pure
  ones `nonisolated`.** `SearchResultRowView` is a `View`, so all
  members inherit `@MainActor` isolation in Swift 6. The
  `highlightedTitle(title:query:)` helper is pure string math —
  callers (`SearchHighlightTests`) hit "main actor-isolated static
  method in a synchronous nonisolated context" when invoking it from
  an XCTestCase. Cure: `public nonisolated static func` — keeps the
  helper available off the main actor without leaking isolation
  through the View conformance.
- **Cross-target environment values live in the shared module.**
  The iOS shells (`TabShell`, `SplitShell`) supply
  `\.taskSelectionBinding` and `\.quickCaptureAction` via
  `.environment(\..., ...)`; the leaf screens read those values.
  Before Plan 20a the `EnvironmentKey` definitions were in
  `Apps/Lillist-iOS/Sources/Common/`. Moving the screens into
  LillistUI required moving the env keys with them. The shell setters
  still live in the iOS app target — only the *type* moves to where
  the consumer lives.
- **Multiple `.navigationDestination(for: UUID.self)` registrations
  in the same NavigationStack scope would collide, but each
  Tab gets its own NavigationStack — collisions don't actually
  happen.** The old `TagDestination` / `FilterDestination` wrapper
  types existed to disambiguate tag-UUID vs filter-UUID vs task-UUID
  destinations within a single NavigationStack. After the Plan-16
  TabShell refactor (each tab is its own NavigationStack), the
  disambiguation became dead weight. Plan 20a drops both wrappers;
  `TodayView`, `AllTagsView`, `FiltersListView`, `SearchView`, and
  `FilterResultsView` each register their own `for: UUID.self`
  handler against their own NavigationStack.
- **Tour snapshots after migration are visually *different* — that's
  the point.** The old mock chrome (custom navBar with title +
  subtitle, custom tabBar at bottom, etc.) approximated iOS's native
  navigation chrome. The new tour wraps the real Screens in a
  NavigationStack, which renders system chrome (large titles, system
  tab bar would render if the test included a TabView host, etc.).
  The plan explicitly accepts re-recording. The six baselines
  affected are test_01 through test_05 and test_08; test_06/07/09/10
  cover surfaces Plan 20a did not migrate and their baselines are
  unchanged.

**Evidence.** Plan 20a commits on `main`: one commit per task (4a–4f).
Full `swift test --package-path Packages/LillistCore` (572 tests),
`swift test --package-path Packages/LillistUI` (31 host-platform
tests; iOS-only tests run via the Lillist-iOS xcodebuild scheme),
plus both app-target builds, all clean after the migration.

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


## Offline mode / sync-mode switching (Plan 21)

**Context.** Pre-Plan-21 the app hard-required iCloud — first launch
gated behind `ICloudRequiredScreen` blocked everything until the user
signed in. Plan 21 introduces an explicit per-device sync mode
(`SyncMode.localOnly` / `.iCloudSync`) so the app stays usable
without iCloud, with destructive but explicit migration when the user
opts into mirroring.

### Architectural rule: never re-instantiate `NSPersistentCloudKitContainer`

The framework's `_loadStoreDescriptions` / `PFCloudKitSetupAssistant`
have documented internal races that fire when multiple container
instances spin up in close succession. Plan 21 sidesteps the whole
class by keeping the **same** container instance for the app's
lifetime and implementing mode change as a store-level remove+re-add
on its coordinator with different `cloudKitContainerOptions`. The
`PersistenceHost` actor (in `LillistCore/Persistence/PersistenceHost.swift`)
is the only place in the codebase that mutates the coordinator after
initial bring-up. Every Store still reads
`controller.container.viewContext` exactly as before — the context
survives the swap because it stays attached to the same coordinator.

The `Wave 1.6 store-level mode swap` spike in
`StoreLevelModeSwapSpike.swift` is the decision gate. The
description-contrast assertions run everywhere; the live-swap tests
are gated behind a bundle-ID check because swift-test crashes on
`NSCloudKitMirroringDelegate` dealloc (no `CFBundleIdentifier` in the
swift-test binary; `PKPushRegistry` faults). Run the gated tests via
`xcodebuild test` to validate live behavior.

### `MigrationJournal` is a file, not a UserDefaults bool

Mid-migration state lives in `<AppGroup>/Lillist/migration.json`,
written atomically via `Data.write(options: .atomic)`. Three reasons:

1. **Atomic cross-process visibility.** `UserDefaults` writes go
   through a flush boundary that isn't immediate to other processes;
   a file is visible to extension readers as soon as the rename
   returns.
2. **Failure-mode richness.** Recovery needs to know which `op` was
   in flight, when the heartbeat last fired, what mode to revert to,
   and which quarantine backup to restore. A bool can't carry that.
3. **Heartbeat semantics.** A crashed process leaves the journal
   non-idle; the recovery flow classifies a stale heartbeat as
   "recoverable" rather than "in-flight migration; back off."

### Quiesce heuristic for migration completion

`NSPersistentCloudKitContainer.eventChangedNotification` doesn't emit
a terminal "all done" event. `SyncQuiesceMonitor` uses a quiesce
heuristic: a watcher Task drains the event bridge and updates
`lastEventAt` for every real `.import` / `.export`; a polling loop
returns `.quiesced` when no event has arrived for at least
`minQuietWindow` (default 5s) or `.timedOut` when `hardTimeout`
(default 300s) elapses first. On timeout the progress sheet
dismisses and the app surfaces "Still syncing in background." —
mode flips even though CloudKit may still be catching up.

This is intentionally not bulletproof. Live integration testing
against a real CloudKit account is required at least once per
release (Wave 7 runbook in the Plan 21 spec).

### CLI App Group ID mismatch fix

The CLI used `"group.com.mikeydotio.lillist"` (a typo) where every
other target used `"group.io.mikeydotio.Lillist"`. The CLI therefore
read a totally separate (empty) container from the apps. Plan 21
Wave 0 fixes the constant in `CLIBridge/StoreLocator.swift`. The
test `appGroupIdentifier_matchesAppsAndExtensions` locks the
correct value in to prevent regression.

### `DevicePreferencesStore` partition

Plan 21 splits the pre-existing `AppPreferences` row in Core Data
into two stores:

- **`DevicePreferencesStore`** (App Group UserDefaults): per-device
  fields that must survive a destructive sync-mode wipe — onboarding
  completion, Quick Capture enable/hotkey, macOS status-bar
  visibility, crash-prompt opt-in.
- **`PreferencesStore`** (Core Data, CloudKit-mirrored): account-wide
  fields — notification cadence, trash retention, default sort,
  default tag tint.

`AppPreferencesPartitionMigrator` copies the device-local fields
forward on first launch after the partition lands, with a sticky
marker so it's a one-shot. The legacy Core Data attributes are
intentionally **not** removed — eliminating them can wait for a
future model version bump (so the build-plugin caching gotcha
documented above doesn't fire as a side effect).

### `MigrationGate` for extensions + CLI

Background helpers (Share Extension, App Intents, the `lillist`
CLI) consult `MigrationGate.evaluate()` before opening the store.
A non-idle journal aborts with the message "Sync settings are being
changed. Try again in a moment." — the user sees the message
inline and can retry. This prevents a foreground sync-mode change
from racing a Share-sheet write that might land against a
half-swapped store.

### Files of interest

- `Packages/LillistCore/Sources/LillistCore/Sync/SyncMode.swift`
- `Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift`
- `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift`
- `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift`
- `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift`
- `Packages/LillistCore/Sources/LillistCore/Sync/MigrationGate.swift`
- `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraser.swift` (+ Impl)
- `Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift`
- `Packages/LillistCore/Sources/LillistCore/Sync/PauseReason.swift` (+ Classifier)
- `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift`
- `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift`
- `Packages/LillistCore/Sources/LillistCore/Preferences/AppPreferencesPartitionMigrator.swift`
- `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift`
- `Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudUnavailableScreen.swift`
- `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift`
- `Packages/LillistUI/Sources/LillistUI/Sync/PauseExplainerDialog.swift`
- `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigration*Sheet.swift`

## 2026-05-19 — On-demand iOS test build deploy (`Tools/Deploy/`)

**Context.** Lillist has no TestFlight presence and no App Store
Connect record. To still get iterative builds onto the user's iPhone,
`Tools/Deploy/deploy-ios.sh` archives the `Lillist-iOS` scheme, exports
a **Development**-method `.ipa`, and stages it for OTA install via
Tailscale Serve. Round-trip is ≈3–5 min, end-to-end. Distribution is
locked to the user's tailnet.

**Non-obvious bits.**

- **Development signing supports OTA install.** The folklore that
  "iTMS-services OTA install requires Ad-Hoc method" is outdated. The
  actual gate is "is the device's UDID in the embedded profile" —
  Development-method profiles on a paid Apple Developer account
  include the team's registered devices, so a Development-signed
  `.ipa` installs OTA on anything you've already plugged into Xcode.
  Ad-Hoc method would also work but requires extra App Store Connect
  setup; Development is one less moving part.
- **`-allowProvisioningUpdates` depends on a live Apple ID 2FA
  session.** When the session expires (silently, after a few weeks
  without Xcode use), the next headless `xcodebuild archive` dies
  with `No profiles for ... were found`. There is no scriptable
  recovery: the fix is to open Xcode → Settings → Accounts and
  re-enter the 2FA code. The deploy script's error block names this
  case explicitly so future-you doesn't spend an hour diagnosing it.
- **Tailscale Serve as HTTPS source — proxy mode, not path mode.**
  OTA manifest *and* `.ipa` must be served over trusted HTTPS or iOS
  silently refuses to install. Tailscale Serve fronts the local
  origin with a real Let's Encrypt cert tied to
  `<machine>.<tailnet>.ts.net` — the iPhone, when on the tailnet,
  trusts it natively. No domain, no ACME, no public exposure. The
  **Mac App Store variant of Tailscale cannot serve filesystem paths
  directly** (sandbox restriction — see
  <https://tailscale.com/kb/1065/macos-variants>). The workaround:
  run `python3 -m http.server --bind 127.0.0.1 --directory <serve>
  <port>` as a localhost backend, and configure Tailscale Serve to
  proxy to that port (`tailscale serve --bg <port>`). The deploy
  script spawns the Python server with `nohup` in pre-flight, so it
  survives terminal close. Reboot kills it; the next deploy
  re-spawns it idempotently.
- **Build-number bump runs as an Archive scheme pre-action.** The
  `Lillist-iOS` scheme's Archive pre-action calls
  `Tools/Deploy/bump-build-number.sh`, which reads the current
  `CURRENT_PROJECT_VERSION` from `Apps/Config/BuildNumber.xcconfig`
  and writes back `current + 1`. The counter is a plain integer
  representing the cumulative archive count for the whole project.
  **`BuildNumber.xcconfig` is tracked in git** so the counter is
  monotonic across machines and never regresses — commit the bump
  after each archive. `Apps/Config/Signing.xcconfig` includes it via
  a required `#include` (not `#include?`) so a missing file is a
  loud build error, not a silent fallback. xcconfig precedence in
  Xcode is above `settings.base` in `project.yml`, so the bumped
  value wins over the `CURRENT_PROJECT_VERSION: "1"` fallback there.
  Xcode 26+ runs scheme pre-actions for **both** the IDE and
  `xcodebuild archive` from the CLI, so the single pre-action
  covers every archive path — verified empirically (older threads
  online claim the CLI ignores pre-actions; that's stale for the
  Xcode-26 era). Don't add a redundant explicit invocation in the
  deploy script: doing so double-bumps the counter, and the second
  bump happens *after* Info.plist resolves, so the archive ships
  the lower value while the file moves up two — a confusing 1-off
  gap that's a real footgun if you try to "make sure" the bump
  runs. The three iOS Info.plists
  (`Apps/Lillist-iOS/Info.plist`,
  `Extensions/ShareExtension-iOS/Info.plist`,
  `Extensions/ShortcutsActions/Info.plist`) all reference
  `$(CURRENT_PROJECT_VERSION)`, so they stay in lockstep —
  extensions matching the parent app is required by App Store
  validation.
- **Manifest `bundle-version` ↔ marketing version, not build number.**
  The OTA install dialog reads `bundle-version` from the manifest
  and displays it as the version string. The deploy script
  substitutes `MARKETING_VERSION` (from `project.yml`), not
  `CURRENT_PROJECT_VERSION`. iOS's "is this an upgrade?" decision
  uses the `.ipa`'s own Info.plist; the manifest is for display only.

**Files of interest**

- `Tools/Deploy/deploy-ios.sh` — orchestrator.
- `Tools/Deploy/bump-build-number.sh` — Archive scheme pre-action;
  writes `Apps/Config/BuildNumber.xcconfig`.
- `Tools/Deploy/ExportOptions.plist` — `method: development`, automatic
  signing.
- `Tools/Deploy/manifest.template.plist` — OTA manifest template.
- `Tools/Deploy/index.template.html` — phone landing page template.
- `Tools/Deploy/README.md` — one-time setup, troubleshooting.
- `Apps/Config/Signing.xcconfig` — includes the gitignored
  `BuildNumber.xcconfig` via `#include?`.
- `Apps/Lillist-iOS/project.yml` — defines the
  `schemes.Lillist-iOS.archive.preActions` that invokes the bumper.

## 2026-05-20 — Crash-canary lifecycle on iOS, and the `.sheet(item:)` rule

**Context.** Lillist popped an empty card sheet (no title, no buttons,
no body) on every iOS cold launch — dismissable, but useless. The
bug had two intertwined causes worth recording together because
either one alone is plausible architecture that hides the other.

**Empty-sheet root cause: `.sheet(isPresented:) + if let model`.**
`CrashReporterHost` modeled presentation with two pieces of state —
`@State var presenting: Bool` *and* `@State var model: CrashReportViewModel?` —
and bound the sheet to `presenting`, guarding the body with
`if let model { … }`. Any state where `presenting == true` while
`model == nil` produces an empty sheet because the `if let` evaluates
to `EmptyView`. The three-line assignment in `.task`
(`pending = …; model = …; presenting = true`) *looks* atomic, but a
SwiftUI render pass can land between them, and the dismiss path
lowers `presenting` while `model` stays set — so any later flip of
`presenting` re-presents whatever the inner `if let` resolves to.

**Rule.** A modal whose content is *optional* must bind directly to
that content. Use `.sheet(item: $model) { model in … }` (or
`.fullScreenCover(item:)`) so SwiftUI cannot present the sheet
without a non-nil value. Never combine `.sheet(isPresented:)` with an
inner `if let` for an optional model; the failure mode is "empty
modal" and it'll happen.

**Why-it-fires-at-all root cause: bootstrap pre-armed the canary.**
`AppEnvironment.bootstrap()` used to call `try? await
crashReporter.start()` "defensively in case the host never gets a
chance to render." But `CrashReporter.detectAndPrepare()` (the
caller in `CrashReporterHost.task`) read whatever canary was on disk
and treated it as the prior run's. The bootstrap-written canary
*was* on disk by the time `detectAndPrepare` ran — so every launch
looked like a crashed prior run. On iOS this race is deterministic
(LillistApp `await`s `bootstrap` before setting `environment`); on
macOS it's a coin-flip.

**iOS canary lifecycle.** iOS apps are usually killed from a
suspended background state without `UIApplication.willTerminateNotification`
ever firing, so a `willTerminate`-based `markCleanExit` hook leaves
the canary on disk for nearly every "normal" exit. Use the
foreground transition hooks instead:

- `didBecomeActiveNotification` → `crashReporter.start()` (re-arm).
- `willResignActiveNotification` → `crashReporter.markCleanExit()`
  (delete). Block briefly with a `DispatchGroup` so the delete lands
  before the OS suspends the app; otherwise the canary survives and
  next launch shows a false stale-crash.

A real foreground crash leaves the canary on disk (no
`willResignActive` ever fires for a SIGKILL/abort). A normal
"backgrounded then OS-killed later" sequence runs `willResignActive`
*before* suspension, deleting the canary — so the next launch sees
nothing on disk.

**Defense in depth: pid-aware `detectAndPrepare`.**
`CrashReporter.detectAndPrepare` now drops any canary whose `pid`
matches the current process. A same-pid canary is impossible across
processes, so it must be a self-write from earlier in this same
launch (a lifecycle observer firing before `detectAndPrepare`, or
some future caller pre-arming again). This closes the
"background-during-bootstrap then return" edge case without
constraining the call order.

**macOS is similar but simpler.** `applicationWillTerminate` fires
reliably on macOS (Cmd-Q), so the macOS `AppDelegate` keeps its
`markCleanExit` hook there. `crashReporter.start()` has been
removed from macOS `bootstrap()` too — `detectAndPrepare()` is the
sole launch-time canary writer on both platforms now.

**Rules.**

- **iOS canary lifecycle uses foreground transitions, not termination.**
  Wire `didBecomeActive` → `start()` and `willResignActive` →
  `markCleanExit()`. Don't add a `willTerminate` observer on iOS —
  it nearly never fires for a real exit.
- **Bootstrap never pre-arms the canary.** `detectAndPrepare()` owns
  arming on launch; lifecycle observers own it thereafter. A
  bootstrap-time `start()` will be read back by `detectAndPrepare`
  and surface as a phantom prior crash.
- **`detectAndPrepare` filters self-pid canaries.** Tests planting a
  canary as a "prior crash" must use a pid that is not the test
  process's pid (e.g., 1 or 99) — same-pid canaries will be dropped
  as self-writes.

**Files of interest**

- `Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift` — `.sheet(item: $model)`.
- `Apps/Lillist-macOS/Sources/CrashReporterHost.swift` — same pattern.
- `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift`
  — `Identifiable` conformance (UUID id) so the model can drive
  `.sheet(item:)`.
- `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift` — drops
  bootstrap `start()`; installs `didBecomeActive`/`willResignActive`
  observers via `installCanaryLifecycleObservers()`.
- `Apps/Lillist-macOS/Sources/AppEnvironment.swift` — drops
  bootstrap `start()`.
- `Apps/Lillist-macOS/Sources/AppDelegate.swift` — unchanged;
  `applicationWillTerminate` continues to delete the canary on
  Cmd-Q.
- `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift`
  — pid-aware `detectAndPrepare`.
- `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReporterFlowTests.swift`
  — `selfPidCanary_isNotPending` regression test.

## 2026-05-23 — `Tools/Deploy/deploy-ios.sh` retired; deploys now go through the `deployit` plugin

**Context.** The 2026-05-19 entry above documented the in-repo
`Tools/Deploy/deploy-ios.sh` infrastructure: archive → export →
local Python HTTP server → Tailscale Serve → OTA install. That whole
flow has been replaced by the **`deployit` plugin** (`/deployit
deploy`), which the user now uses across multiple projects (Lillist,
moshtail, …). The plugin does the same archive/export/serve work,
plus indexes every build into the shared `mikeydotio/deployit-index`
repo and exposes `bootstrap` / `list` / `url` / `status` / `gc`
subcommands.

**Why this matters.** The 2026-05-19 entry is now historical — useful
for *why* the deploy infrastructure exists at all, but not for *how*
to use it today. Don't follow its filenames or commands; follow
`/deployit` instead.

**What survived.** Build-number bumping stays in-repo. The Archive
*pre-action* on the `Lillist-iOS` scheme still invokes
`Tools/Deploy/bump-build-number.sh`, which writes
`Apps/Config/BuildNumber.xcconfig`. The plugin reads the resolved
`CFBundleVersion` off the built `Info.plist` and never writes the
version. So the monotonic-build-number invariant from the 2026-05-19
entry still holds, and the same "commit `BuildNumber.xcconfig` after
every successful deploy" discipline applies.

**Deleted files** (2026-05-23 migration):
- `Tools/Deploy/deploy-ios.sh`
- `Tools/Deploy/ExportOptions.plist`
- `Tools/Deploy/index.template.html`
- `Tools/Deploy/manifest.template.plist`

`Tools/Deploy/README.md` was rewritten as a brief pointer to the
plugin. `CLAUDE.md`'s *Deploy (iOS test builds)* section was
rewritten the same day.

**Env-var hygiene.** Contributors who set
`LILLIST_DEPLOY_BASE_URL` in their shell rc as required by the old
script can remove it — the plugin owns its own Tailscale Serve
config and doesn't read any project-specific env var.

## 2026-05-26 — Drag-reorder coordinate space and platform gesture wiring

`DragReorder/` uses a single named SwiftUI coordinate space
(`DragCoordinateSpace.name = "TaskListDrag"`) shared by the list
container, each row's geometry reporter, and the gesture's
`.coordinateSpace(.named(...))`. All three must agree or row frames
report in the wrong space and the overlay positions wrong.

iOS gesture activation is `LongPressGesture(0.3s, 4pt slop).sequenced(before:
DragGesture(0pt))`. The macOS gesture is a bare `DragGesture(minDist: 4)`.
The unification point is `DragReorderableModifier`'s `#if os(iOS) / #else`
branches — both call into the same `DragController` methods.

`DragController.state.dropping` is reserved for a future drop-animation
phase; today `endDrag()` transitions directly from `.dragging` to `.idle`.
See `docs/plans/2026-05-26-drag-reorder-redesign-design.md`
§"Animation and gap behavior" for the full intended sequence.

Auto-scroll near list edges (design §"Auto-scroll near edges") is not yet
implemented. Implementing it requires a `ScrollViewProxy.scrollTo(...)` on
a timer driven by `DragController`, gated on cursor proximity to the
list's top/bottom edge.

## 2026-05-27 — Drag-reorder hit testing must claim the inter-row gap

SwiftUI `List` rows with `listRowInsets(top: N, …, bottom: N)` produce a
`2N`-point vertical gap between consecutive rows' reported geometry —
`RowGeometryReporter` measures the row's *content* frame, not the
inset row container, so consecutive `controller.geometry` rects are
non-contiguous. `TasksScreen.listBody` uses `top: 2, bottom: 2`, so
the gap is 4pt.

The `.between(...)` insertion indicator capsule is drawn *inside*
that gap (at `afterID.maxY`). A naive strict half-open row hit test
(`y >= frame.minY && y < frame.maxY`) finds no row for cursors in
the gap and the resolver returns `.none`, which makes the indicator
fade out via its `.transition(.opacity)` — i.e. the line vanishes
exactly when the user hovers their finger on it.

Fix: `DragController.hitRow(atY:)` expands each row's effective
hit range to claim half of every inter-row gap (midpoint split).
Zone classification still uses the row's *real* frame, so the
top/middle/bottom 25/50/25 thresholds inside a row are unchanged.
Gap positions fall outside the top/bottom-25% bands and naturally
classify as the edge zone of whichever row owns that half of the
gap; both halves of any given gap resolve to the same `.between`
target (or, across a depth change, to two adjacent valid targets —
never `.none`). Contiguous geometry is a no-op.

Don't try to "fix" this by inflating the reported geometry inside
`RowGeometryReporter`. The reporter doesn't see neighbors (it's a
per-row preference) and hardcoding the inset there would couple the
shared module to one screen's layout. The resolver already
understands inter-row structure; that's where the fix belongs.

## 2026-05-29 — Store-swap safety: live empty-store guard + tracked follow-up

`MigrationCoordinator.runMigration` now refuses the irreversible
`replaceICloudWithLocal` erase when the local store is empty (sync-7).
That guard is only as good as the row counter wired into it. The
counter is now **live in production**: both `AppEnvironment`s
(`Apps/Lillist-iOS/Sources/App/AppEnvironment.swift`,
`Apps/Lillist-macOS/Sources/AppEnvironment.swift`) pass
`localStoreRowCount: { await persistence.localTaskRowCount() }` into
the coordinator. The default `{ 1 }` (always "non-empty") survives
only for tests/previews — production must pass a real counter or the
guard is inert.

`PersistenceController.localTaskRowCount()` is the canonical counter
and is deliberately **fail-closed**: it runs a
`count(for:)` on `LillistTask` where `deletedAt == nil` inside
`viewContext.perform`, and `(try? …) ?? 0` returns `0` on *any*
error. Zero means "empty", which *blocks* the erase. This is
intentional — an uncertain count must never bypass a data-loss guard.
The fetch stays inside `LillistCore` so no `NSManagedObject` escapes
the module (the app targets only see the `Int`).

One follow-up intentionally deferred (not yet done):

1. **`wal_checkpoint(TRUNCATE)` around the quarantine copy** — owner:
   recovery-hardening plan. `PersistenceHost.flushAndSwap` re-attaches
   the store on the same URL, so `QuarantineManager.copyStore` copies a
   live WAL-mode triplet (`main` + `-wal` + `-shm`); the backup's
   restorability depends on the `-wal` sidecar being copied
   consistently. Forcing a `wal_checkpoint(TRUNCATE)` before (or after)
   the copy would fold the WAL into the main `.sqlite` so the backup is
   a single self-contained file with no sidecar dependency.

A second consideration — `restoreFromBackup` restoring the *exact*
journaled backup rather than guessing the latest — was implemented in
this wave (commit `c3d202e`): it now prefers
`quarantine.quarantinedStore(folderName: journal.quarantineFolderName)`
and falls back to `latestQuarantinedStore` only when the recorded
folder is missing or absent (legacy journals). Proven by
`restoreHonorsRecordedFolder` in `MigrationRecoveryTests`.

## 2026-06-03 — Recurrence input hardening: `count=0` is intentional; `interval` is two-sided-clamped

`recurrence-input-hardening` (commits `758a14b`..`b6b80dd`) made the
recurrence engine crash-safe against untrusted `interval`/`count` arriving
via CloudKit decode, the Importer, or the CLI. Two non-obvious things a
future contributor will otherwise rediscover the hard way:

1. **Do NOT "normalize" a non-positive `count`.** `count = 0` means *zero
   occurrences* — a deliberate, **tested** contract
   (`RecurrenceExpanderLimitTests."count=0 yields no occurrences"`; the
   mechanism is `hardCap = rule.count.map { min($0, count) } ?? count` in
   `RecurrenceExpander.nextOccurrences`). A fix that treated `count <= 0`
   as "unbounded" was written and **reverted** during this wave precisely
   because it reversed that contract and turned the LimitTests red.
   `CalendarRule` clamps `interval` but assigns `count` raw — that
   asymmetry is on purpose. Whether a *corrupt* `count <= 0` from sync
   should instead fall back to unbounded is a product decision, tracked as
   residual #8 in the foundation-hardening index, not a bug to silently
   "fix".

2. **`interval` is clamped on BOTH sides.** `CalendarRule.maxInterval =
   1000` plus `clampedInterval(_:) = min(maxInterval, max(1, raw))` is
   applied at the trust boundary (`normalizedInterval`, which logs the
   change) and silently at every `RecurrenceExpander` step/modulo site
   (`effectiveInterval`). The low side stops `interval = 0` dividing by
   zero / a negative interval walking backwards; the **high** side stops a
   huge positive `interval` (e.g. `Int.max`) overflowing the monthly
   `12 * n + 1` month-scan bound (a trap) or forcing an `O(interval)` scan
   (an effective hang). The recurrence editor's stepper is bounded
   `1...365`, so `maxInterval = 1000` only ever bites untrusted data. The
   high-side half was found by a post-merge adversarial audit, not the
   original plan — see the plan's status banner for the full deviation log.

## CloudKit cross-device convergence (2026-05-28)

- **`AppPreferences` uses a well-known constant id, not `UUID()`.**
  `PreferencesStore.singletonID` is a fixed UUID literal. Before this,
  every device minted its own random id, so CloudKit mirrored two
  distinct "singleton" records and the devices flip-flopped. Never
  regenerate the literal — existing stores depend on it.
  `normalizeSingletons()` (called once at bootstrap) collapses any
  legacy multi-row store down to one canonical row by id-sort, keeping
  the first and reassigning it `singletonID`. It is idempotent.
- **`viewContext.transactionAuthor`/`.name` are set to
  `PersistenceController.localTransactionAuthor` at store load.** This
  is load-bearing: the persistent-history diff in
  `RemoteChangeReconciler` separates our own writes from CloudKit
  imports purely by author. Removing it makes every local write look
  like a remote change and triggers redundant reconcile cycles.
- **Steady-state merge policy stays `mergeByPropertyObjectTrump` — on
  purpose.** `CloudKitErrorClassifier` now gives `CKError` a typed
  posture, but the conflict policy is intentionally last-writer-wins
  per property. The known cost is that a concurrent edit to the *same
  property* on another device is silently discarded on merge; per-field
  CRDT reconciliation is YAGNI until a real conflict report appears.
  Documented here so the choice is explicit, not inherited.
- **History-token diffing resumes from a persisted watermark.**
  `PersistentHistoryTokenStore` archives the `NSPersistentHistoryToken`
  (via `NSKeyedArchiver`, `requiringSecureCoding: true`) into App-Group
  `UserDefaults`. The reconciler fetches `fetchHistory(after:)` the
  watermark, flattens transactions to `SyntheticChange`s, and only
  reacts to `NotificationSpec.lastFiredAt` changes from a foreign
  author — then advances the watermark. The diffing core
  (`RemoteChangeReconciler.affectedTaskIDs`) is a `nonisolated static`
  pure function so it's unit-testable without a live container.

## Intermittent SIGSEGV under heavy parallel in-memory store creation (2026-06-04)

- **Symptom.** `swift test --package-path Packages/LillistCore` occasionally
  aborts the whole process with `error: Exited with unexpected signal code 11`
  (SIGSEGV), with the crash trace pointing at a `ParitySuiteTests` parameterized
  case. It is **rare** (~1 in 15–20 full-suite runs) and **does not reproduce on
  demand** (parity suite alone: 8/8 clean; full suite: 10/10 clean in a stress
  loop right after a crash).
- **Root cause (investigated 2026-06-04, systematic-debugging).** It is **not** a
  product bug and **not** in our code. Swift Testing runs the package's suites
  (and parameterized cases) in parallel; very many tests call `TestStore.make()`
  → `PersistenceController(configuration: .inMemory)`. At peak, dozens of
  `NSPersistentContainer`s call `loadPersistentStores` concurrently while sharing
  the single cached `NSManagedObjectModel` (`PersistenceController.sharedModel()`,
  kept shared on purpose to avoid the "claims Entity" warning). Core Data's
  framework-internal, lazily-built per-entity state (`NSEntityDescription`)
  races across the concurrent loads → intermittent memory corruption. This is the
  plain-container residue of the same class the code already mitigated for
  `NSPersistentCloudKitContainer` (see `makeContainer`'s in-memory→plain comment),
  and the reason the other container-heavy suites (`MigrationCoordinatorTests`,
  `PersistenceHostTests`, `MigrationRunnerExecutingTests`, …) carry `.serialized`.
  Wave 2's `ParitySuiteTests` matrix added ~100 more concurrent container
  creations (51 fixtures × 2 calendars) — the densest single contributor to the
  parallel burst — which is why the crash surfaces there.
- **Why no code fix was applied.** The crash is timing-dependent and not
  reproducible on demand, so no source change can be *verified* to remove it with
  a feasible number of runs; and parity-alone being clean shows the trigger is
  cross-suite peak concurrency, not any one suite (so a speculative `.serialized`
  on the parity suite wouldn't reliably target it). Production never creates more
  than one container, so there is **nothing to fix in shipping code**.
- **Second manifestation — timing flakes, not just crashes.** The same
  parallel-test CPU contention also intermittently fails *wall-clock* tests when a
  `Task` is starved past a timing window. Confirmed case (2026-06-04):
  `SyncQuiesceMonitorTests."Times out when events arrive faster than the quiet
  window"` occasionally gets `.quiesced` instead of `.timedOut` — under load the
  churner/watcher Task stalls past the 300ms quiet window, so the monitor sees a
  false quiet gap. This is a **test-fidelity artifact, not a product bug**:
  `SyncQuiesceMonitor` is an explicit best-effort heuristic ("intentionally not
  bulletproof; live CloudKit integration testing covers the ground truth"), and
  real CloudKit events don't get "starved" the way a fake churner Task does.
  Tightening the churn interval would NOT robustly fix it (a single big stall
  defeats any interval), and a clock-injection refactor is disproportionate for a
  best-effort heuristic the migration coordinator depends on — so no source change
  was made. The systemic remedy is the same: bound test parallelism.
- **Correct remedy (owned by Wave 7 `ci-and-build-posture`).** Bound test
  parallelism at the runner — e.g. `swift test --num-workers <small N>` or
  `--no-parallel` for the container-heavy / timing-sensitive suites — and/or add a
  retry so a one-off SIGSEGV or timing flake re-runs rather than failing CI. That
  is a deterministic, verifiable runner-level mitigation. Tracked as index
  residual #11. **A green `swift test` is not undermined by a single observed
  SIGSEGV or a single `SyncQuiesceMonitor`/contention timing flake — re-run before
  treating it as a real failure.**


## Concurrency invariants proven by the stress suites (Plan: concurrency-stress-tests, Wave 4)

CLAUDE.md mandates stress repetitions for any code crossing actor
boundaries. The following invariants are not obvious from the happy-path
code; each is now pinned by a stress test, and each has a sharp edge a
refactor can silently break.

### find-or-create single-context invariant

`TagStore.findOrCreate` is atomic **only** because every production caller
shares the one main-queue `viewContext`: the existence check and the
optional insert run inside a single `context.perform`, so concurrent callers
serialize and the later ones observe the row the first inserted. This is a
property of the *shared context*, not of the `name ==[c]` predicate. Two
independent `NSManagedObjectContext`s whose find-then-insert interleaves
(both read the row absent, then both insert) **will** produce a duplicate
tag — `TagStoreFindOrCreateRaceTests.secondContextCanRace` reproduces it
**deterministically** (it interleaves the two contexts by hand rather than
racing a `withTaskGroup`, so it proves the duplicate window every run without
adding CI timing flakiness).

Consequence: never open a second writer context for tag creation. Route all
tag creation through the shared `TagStore`. The duplicate-tag race is
prevented by discipline, not by the schema.

We **declined** a `Tag` `uniquenessConstraints` on `(parent, name)` (YAGNI):
every production caller already routes through the shared store; a unique
constraint forces a store-wide merge-conflict policy that would interact with
the existing `mergeByPropertyObjectTrump`; editing the `.xcdatamodel` triggers
the CompileCoreDataModel mtime-touch ritual and a model-version bump; and Core
Data unique constraints are **not** mirrored to CloudKit, so the constraint
would give false cross-device confidence. If that calculus ever changes,
`secondContextCanRace` is the signal to flip the test to assert the constraint
and update this note.

### at-most-one default notification spec per (taskID, kind)

`NotificationScheduler.materializeDefaultSpecs` does a check-then-add:
`specStore.specs(forTask:)` → (if absent) `specStore.add(...)`. Because
`NotificationScheduler` is an `actor`, `reconcile(taskID:)` is reentrant at
every `await`, so two interleaved reconciles can each observe the default spec
absent and both attempt to insert.
`NotificationSchedulerConcurrentReconcileTests` drives this with a 16-wide
`withTaskGroup` across 50 fresh-store iterations and asserts exactly one
default spec + one pending request hold under contention.

The **enforcement** lives in `NotificationSpecStore.add` (the default-kind
guard fetches existing specs, returns the survivor, and deletes any duplicate
rows a prior race created — shipped in `cloudkit-convergence`, commit
893c359). The store is where the dedup belongs — it scopes via a `task == %@`
predicate rather than a model-level unique constraint, so it composes with
CloudKit. Do not "fix" a regression here by adding a lock or dedup inside the
scheduler's reconcile loop; restore the per-(task,kind) row guard in
`NotificationSpecStore`.

Test-infra dependency worth knowing: the stress test only holds because the
test double `FakeUserNotificationCenter.add` is **upsert-faithful** to the real
`UNUserNotificationCenter.add` (a request whose identifier matches a pending
one *replaces* it). `NotificationScheduler` builds
`Dictionary(uniqueKeysWithValues:)` over pending identifiers, which traps on
duplicates; concurrent reconciles legitimately call `add` with the same
identifier, and only an upsert-faithful fake (matching the documented real
API) keeps pending identifiers unique. A fake that appended unconditionally
crashed the scheduler on a duplicate key — a fake-fidelity bug, not a
production bug (the real center never holds two pending requests under one
identifier).

### AsyncStream synchronous registration — what the N-subscriber suite does and does NOT guard

`CloudKitEventBridge` registers its `AsyncStream` continuation **synchronously**
inside the actor-isolated `eventStream` getter (not via a deferred
`Task { register }`). That is the fix for the pre-subscription drop (Race A)
diagnosed in `.rca/sync-status-monitor-event-drop/`.

`CloudKitEventBridgeConcurrentSubscriberTests` guards three real properties
under contention: N-subscriber fan-out delivers every event in order (no
drops/reorder), terminating a subscriber unregisters its continuation without
starving survivors or leaking, and subscribe/terminate churn never wedges the
actor.

It does **NOT** detect a regression that reverts to deferred `Task { register }`.
This was verified empirically: with the deferred revert in place, the existing
`preSubscriptionEventBuffering` test AND all three new tests still pass. The
reason is structural — via the `recordEvent` test seam every `await` lets the
enqueued registration Task run before the event is recorded, so actor
scheduling masks Race A. Race A is a latent *production* hazard on the
NotificationCenter-driven `handleEvent` path, where events can arrive between
the getter returning and a deferred registration running. Synchronous
registration is therefore held by the iterator-pattern design + code review,
**not** by an executing canary. Do not remove the synchronous registration on
the strength of "the tests still pass."

### xcodebuild-gated store-reconfigure stress

`StoreReconfigureConcurrencyTests` hammers `TaskStore.create`/`fetch` against a
live `PersistenceHost.reconfigure` swap. It is gated by the same
`liveSwapAllowed` bundle-ID check as `StoreLevelModeSwapSpike` because
`NSCloudKitMirroringDelegate.dealloc` faults under the swift-test binary (no
`CFBundleIdentifier`), so under `swift test` it skips cleanly. To actually
*execute* the gated cases it is listed in the `Lillist-iOSAppHostedTests`
target (real bundle ID); the standalone `LillistCoreTests` bundle skips it even
under xcodebuild. Its real run is on a code-signed simulator host (CI / dev
Mac). A fetch that lands mid-swap may throw `.notFound` (no attached store) — a
tolerable transient; a crash or a lost committed row is not.


## 2026-06-04 — Single shared viewContext is deliberate; bulk work gets a targeted background seam (Plan: background-context-seam, Wave 4)

**The default is one main-queue context.** `PersistenceController`
exposes a single shared `container.viewContext` and every interactive
store mutation runs on it via `context.perform`. This is intentional, not
an oversight: `viewContext.automaticallyMergesChangesFromParent = true`
is **active** — it is the channel through which
`NSPersistentCloudKitContainer` merges remote CloudKit changes into the
UI's context. Do **not** "clean up" by claiming auto-merge is dead or by
fanning every store onto private contexts; you would break CloudKit
mirroring's path to the UI.

**The seam.** Three jobs are bulk, not interactive — full-store export,
full-store import, and Trash purge. Those run on a dedicated
`PersistenceController.makeBackgroundContext()` (a `newBackgroundContext`
with auto-merge ON and the same trump merge policy) so a 10k-row pass
never freezes the main queue. Background saves propagate up to the
`viewContext`, which auto-merges them, so callers don't refetch after an
import. Everything else stays on `viewContext`.

**Batch delete skips delete rules — and the result set lies.**
`NSBatchDeleteRequest` bypasses Core Data's delete-rule machinery. The
*DB rows* are still cascaded, but `NSBatchDeleteResult`
(`resultTypeObjectIDs`) reports only the *explicitly-named* objectIDs.
Merging that partial set into the `viewContext` leaves the cascaded
children as dangling in-memory objects (rows gone from SQLite, still
"live" in the context). `CascadeReaper` therefore enumerates every
cascade-reachable objectID (`children` recursively → `journalEntries` →
`attachments` / `notificationSpecs`; `JournalEntry.attachments`) and the
full set is both deleted and merged. `purgeAll` and `AutoPurgeJob` use it.
Nullify relationships (`tags`, `series`, `parent`) are not reaped.
`purgeAll`'s returned count is exactly the reaped set (matched victims +
their full cascade). `AutoPurgeJob`'s returned count carries the same
meaning: matched victims plus every cascade-reachable descendant — it
diverges from a "matched rows only" tally only when a soft-deleted parent
and child have `deletedAt` values that straddle the retention cutoff (child
pruned separately from parent). The DATA outcome is identical either way
(the cascade deleted the child regardless), and both app callers discard the
return value, so the discrepancy is informational only.

**`NSBatchDeleteRequest(objectIDs:)` is single-entity.** A non-obvious
trap the plan's first draft hit: that initializer requires *all* IDs to
belong to **one** entity — passing the mixed-entity cascade closure throws
`NSInvalidArgumentException: mismatched objectIDs in batch delete
initializer` at runtime. So `CascadeReaper.batchDelete(objectIDs:in:)`
groups the reaped IDs by `entity.name` and issues one batch per entity,
**leaf-first** (Attachment → NotificationSpec → JournalEntry →
LillistTask), returning the union of executed IDs to merge. The in-memory
test store is SQLite-at-`/dev/null` (not `NSInMemoryStoreType`), so the
batch-delete + FK-cascade path is exercised with production fidelity.

**Rollback on save failure.** A failed `ctx.save()` inside a mutating
`perform` leaves the dirtied objects pending in the shared `viewContext`;
the next op then inherits or compounds the failed change. Every mutating
`TaskStore` method calls `context.rollback()` (hopped back onto
`context.perform`) as the first line of its catch — a single inserted line
that does **not** disturb the breadcrumb-truthfulness success/failure crumb
shape. To test deterministically: pin `viewContext` at a stale row version
(auto-merge OFF + a pending change + `NSMergePolicy.error`), bump the row
from a second context, then call the mutator — the save throws
`NSCocoaErrorDomain` 133020 and the catch's rollback leaves the context
clean. (`purgeAll` is the only exclusion: it runs the batch on a discarded
background context, so there is nothing in the shared context to roll back.
`transition`, `reorder`, `assignTag`, and `unassignTag` were subsequently
fixed to roll back as well — a Wave-4 cross-cutting review found they had
been missed.)

**localOnly history grows unbounded.** `.localOnly` stores keep
`NSPersistentHistoryTrackingKey` ON (so the sync-mode swap is a pure
description mutation), but nothing consumes the history. `HistoryPruner`
sweeps it (token-bounded, idempotent), gated to `.localOnly` —
`.iCloudSync` trims behind its own export cursor and must not be swept.
`NSPersistentHistoryToken` is not `Sendable`: read it, use it in
`deleteHistory(before:)`, and archive it to `Data` all inside one
`perform`; only the `Data` may escape. `sweep()` is wired fire-and-forget
into both apps' `bootstrap()` after the launch purge.

**Acknowledged limitation (index residual #3):** the purge reaps
`NotificationSpec` *rows* but does **not** cancel the OS-level pending
`UNNotificationRequest`s those specs scheduled — a purged task whose
fire-date is still future will fire its banner until the OS drops it.
Cancelling the OS-level requests is a named follow-up, out of this plan's
threading/cascade scope.

## 2026-05-28 — Crash-reporter redaction is layered, and the canary can't trust PID alone

**Redaction: wrapped markers are authoritative; key=value is single-token
defense-in-depth.** `LogRedactor` runs an ordered list of regex passes.
The wrapped-marker passes (`<title>…</title>`, `<notes>`, `<journal>`,
`<tag>`) redact arbitrary content *including spaces* via a non-greedy
`[\s\S]*?`. The `key=value` passes (`title=…`, `notes=…`, `tag=…`) stop at
the first whitespace, so a bare multi-word value (`title=Buy milk`) is
**not** fully redacted — only the first token is. This is intentional: the
key=value passes exist purely as a backstop for accidental single-token
leaks; any code logging user content must wrap it in a marker. The
adversarial golden fixture
(`Tests/.../CrashReporting/Fixtures/raw-logs-adversarial.{txt,expected.txt}`)
pins this contract, including the deliberately-only-partially-redacted
multi-word line. Don't "fix" that fixture line by greedily extending the
key=value passes to end-of-line — that would over-redact legitimate
trailing log structure (` to closed`, ` to task`) and break the
human-readability the crash reports depend on. The key=value passes
capture the key (`$1`) and re-emit it verbatim so a mixed-case key
(`Title=`, `NOTES=`) keeps its original casing while only the value is
redacted — a bare literal replacement template would rewrite the whole
match and silently lowercase the key, which the Task-1 unit test and the
golden fixture both catch.

The path/container passes use a capitalized-space lookahead
(`\s(?=[A-Z][a-z])`) so a path can swallow a literal-space component like
`Application Support`. The container/temp passes use a case-insensitive
hex class (`[0-9A-Fa-f-]`) and cover both the per-app `Data/Application`
subtree and the shared `Shared/AppGroup` subtree, plus
`/private/var/folders`, `/var/folders`, and `/tmp`. UUIDs are redacted
last so paths/emails are gone before the bare-UUID fallback runs.

**The canary cannot suppress a prior crash on PID equality alone.**
`CrashReporter.detectAndPrepare()` must ignore a canary it wrote *earlier
in this same launch* (a lifecycle pre-arm) without ignoring a *real* prior
crash. The original filter compared `pid` only, on the assumption that a
cross-process crash always has a different PID. That assumption is false:
the OS recycles PIDs, so a genuine prior crash can carry this process's
PID and would be silently swallowed. The fix adds a `startedAt` recency
check (same-PID **and** `startedAt` within a 30 s window of `now()` ⇒
treat as a same-launch pre-arm; otherwise surface it). The reporter's
injectable `now` clock makes this deterministic in tests. If you ever see
a real crash go unreported with a matching PID, this window is the first
place to look.

## 2026-06-04 — Performance budgets are gated by explicit timed assertions, not `measure()` baselines

**Context.** Design §761 promises an assertion-tested smart-filter budget
("< 100ms against 10,000 tasks"). The perf suite lives at
`Packages/LillistCore/Tests/LillistCoreTests/Performance/` — the *only*
`XCTestCase`-based files in LillistCore (every other suite is Swift
Testing). They are deliberately segregated there.

**Gotcha 1 — `measure()` does not fail under `swift test`.** XCTest's
`measure(metrics:)` records performance numbers and, *in Xcode*, diffs them
against a stored baseline to fail on regression. Under `swift test` (SwiftPM)
there is **no baseline store**, so `measure()` runs the block and reports a
number but **never fails the build**, no matter how slow. Therefore the real
budget gate is `XCTAssertWithinBudget` in `PerfBudget.swift`: it times a
synchronous block `PerfBudget.assertionReps` times (after a warm-up), takes
the **median** (so one scheduling spike can't flake CI), and hard-asserts it
against a constant. The `measure()` blocks are kept only for human-visible
trend data in Xcode. **Do not delete the explicit `XCTAssertWithinBudget`
gates in favour of `measure()` — that silently removes the regression
tripwire.**

**Gotcha 2 — async stores, synchronous timing.** The stores are `async`;
the budget helper times a *synchronous* closure. Each timed block bridges
the actor boundary with a `DispatchSemaphore` (`Task { await … }; sem.wait()`)
so the evaluation still runs on the `viewContext` queue exactly as in
production, but the wall-clock measurement stays synchronous and
deterministic. Seeding (10k `create` calls) happens *outside* the timed
block — only the fetch/evaluate is measured.

**Policy — list fetches are batched; the UI pages.** Every list fetch in
`TaskStore`/`TaskStore+Queries`/`SmartFilterStore` sets
`fetchBatchSize = TaskStore.listFetchBatchSize` (100) so Core Data returns
rows as faults in pages and only realizes each page when touched, instead of
faulting and DTO-projecting an entire sibling/result set on the main-queue
`viewContext` per reload. For windows the UI doesn't fully scroll, prefer the
paged overloads — `TaskStore.children(of:limit:offset:)` and
`SmartFilterStore.evaluate(group:limit:offset:)` — which map to
`fetchLimit`/`fetchOffset`. The `NSPredicateCompiler` doc comment notes the
compiled predicate is also `NSFetchedResultsController`-ready; an FRC-backed
list is the natural next step if a single window proves insufficient, but
YAGNI until a real screen needs it.

## 2026-05-28 — Observability: the logging subsystem is load-bearing for the crash reporter

`LillistLog` (`Support/LillistLog.swift`) deliberately pins its
`subsystem` to `CrashReporting.subsystemIdentifier`
(`io.mikeydotio.lillist.crash`). This is not cosmetic. The crash
report's "Recent app logs" section is assembled by
`CrashReporter.submit(includeLogs:)`, which calls
`OSLogFetcher.fetchRecentLines(since:subsystem:)` with that exact
subsystem and **discards every unified-log entry whose `subsystem`
differs** (`OSLogFetcher.swift`). Before Plan "observability-logging"
nothing in production wrote on that subsystem, so the toggle was inert
(`logs-2`): the section was always empty.

Consequences for future work:

- **Never give `LillistLog` its own vanity subsystem.** Categories
  (`sync`, `store`, `indexing`, `app`, `metrics`, `signpost`) are the
  Console.app filtering axis; the subsystem stays pinned. Split the
  subsystem and the crash report goes silent again with no compile
  error and no test failure unless you run the OSLogFetcher round-trip
  on a host with log access.
- **`OSLogFetcherRoundTripTests` only enforces the contract when the
  runner has unified-log access.** Sandboxed `swift test` runners often
  deny it, so the strict branch is skipped and the test still passes.
  `LillistLogTests.subsystemMatchesCrashReporter` is the always-on
  guard — keep it.
- **Privacy:** every collected line passes through `LogRedactor.redact`
  before leaving the device, but that is a backstop. Log verbs, counts,
  durations, mode raw values, and error *type* names with
  `privacy: .public`; never titles, notes, journal bodies, paths, or
  raw `error` descriptions (which interpolate user content). MetricKit
  call-stack JSON is intentionally not emitted.
- **CLI `print()` is not a logging gap.** Those are stdout *output*
  (design §454: "stdout for data; stderr for diagnostics") and must
  stay `print`. The 43-`print()` figure in the foundation review counts
  these; do not "fix" them into loggers.

## 2026-06-05 — Privacy manifests are per-bundle, not per-project (Plan: privacy-manifest-export-compliance, Wave 7)

`PrivacyInfo.xcprivacy` and `ITSAppUsesNonExemptEncryption` live in
*each* shipping bundle, not once at the project level. Lillist ships
four uploadable bundles — the iOS app, the macOS app, `ShareExtension-iOS`,
and `ShortcutsActions` — so each carries its own manifest (apps in
`Resources/`, extensions at their source-dir root) and its own
`ITSAppUsesNonExemptEncryption=false` in `Info.plist`. The four manifests
are intentionally byte-identical (same `UserDefaults` CA92.1 +
file-timestamp C617.1 required-reason APIs via shared `LillistCore`, same
private-CloudKit user-content collection model); keep them in sync — a
guard test (`PrivacyManifestComplianceTests` in both app test bundles)
parses all four and asserts the reasons match exactly. Those test bundles
are host-less (`TEST_HOST=""`), so the test reads the manifests from the
repo tree via `#filePath`, not from `Bundle.main`. If you add a new
required-reason API (e.g. `systemBootTime`, `diskSpace`), update all four
manifests and the test's expected-reason assertions together.

xcodegen auto-routes a non-buildable `.xcprivacy` to the resources build
phase: for the apps it lands in the already-declared `Resources/`
(`buildPhase: resources`); for the two extensions xcodegen *creates* a
fresh resources build phase to hold it (the source-dir `sources` path
already covers the file). No explicit `buildPhase: resources` entry was
needed in either `project.yml` — verified by `find … -name
PrivacyInfo.xcprivacy` against an unsigned build (one copy per `.app` /
`.appex`). The macOS standalone test bundle (`Lillist-macOSTests`,
`TEST_HOST=""`) still requires the `CODE_SIGNING_ALLOWED=NO` recipe for
headless `xcodebuild test` because the scheme also builds the macOS app
target, which needs a Mac provisioning profile a headless runner cannot
auto-generate; the iOS standalone bundle ad-hoc-signs on the simulator
without it.

## 2026-06-05 — Recovery pre-flight: disk-space check lives in QuarantineManager.copyStore, not the coordinator (Plan: recovery-hardening, Wave 7)

The destructive sync-mode swap's only recovery anchor is the quarantine
copy of the live SQLite store. A copy that runs out of room mid-write is
worse than no copy — so `QuarantineManager.copyStore(at:)` now runs a
**pre-flight** disk-space check (via an injectable `DiskSpaceProbing`)
and throws `LillistError.insufficientDiskSpace` *before touching any
file*. It requires `2×` the live footprint (`quarantineHeadroomFactor`)
to cover source+copy coexistence plus WAL-checkpoint inflation. The
check lives in `copyStore` (not the move-based `quarantineStore`)
because that is the method `runMigration` calls — a check in
`quarantineStore` would never fire during a migration.

Two ordering invariants a future refactor must preserve:

1. In `MigrationCoordinator.runMigration` the merged step order is
   precondition → `reconfigure` (step 4) → `copyStore` (step 5) →
   CloudKit zone erase (step 6). The disk check is inside `copyStore`
   (step 5), so a shortfall aborts before the irreversible erase. Do
   not reorder. NOTE: because `reconfigure` (step 4) precedes the copy,
   a disk-shortfall abort leaves the sync mode **already flipped to the
   target** — the recovery sheet's "Try Again" is what re-runs the now
   partially-applied swap; the user must free space first.
2. The check uses `volumeAvailableCapacityForImportantUsageKey` (honest
   "space the OS would free for a real write"), not the raw
   `.volumeAvailableCapacityKey`.

Residual: a `PRAGMA wal_checkpoint(TRUNCATE)` around `copyStore` would
shrink the WAL before the copy and tighten the 2× headroom estimate. It
is **not** implemented here — recorded as a known follow-up so a future
contributor doesn't assume the copy already checkpoints.

`restoreFromBackup` is covered by ungated `swift test` cases in
`MigrationRecoveryTests.swift` (the `test-2` gap, already closed before
this plan). Its happy-path test keeps `previousMode == host.currentMode`
so `reconfigure` is a no-op early-return and the test doesn't need a real
bundle id (`liveSwapAllowed`).

## 2026-06-05 — CI established + build-posture alignment (Plan: ci-and-build-posture, Wave 7)

**Context.** Until now every quality gate (warnings-as-errors, the full
test matrix, snapshots, the runtime-gated migration tests, pbxproj
drift) was enforced only by what the dev remembered to run locally. The
foundation review's completeness critic named "No CI/CD at all" as a
blind spot. This entry records the CI design and three build-posture
fixes that landed with it, plus the empirical limits that shaped what CI
can and cannot run.

**Rules.**

- **CI runs post-push on `main`, not as a PR gate.** Solo project,
  direct-to-`main`. `.github/workflows/ci.yml` is a *verifier*: a push
  triggers it, a broken gate goes red + emails the actor, and
  `workflow_dispatch` allows on-demand runs. Don't restructure it into a
  required-status-check unless the project moves to a PR flow.
- **deployit archives in Debug; CI is the only Release compile.** The
  `Lillist-iOS` scheme's `archive.config` is `Debug` (fast OTA
  round-trip), so Release-only behaviour (WMO, dead-code stripping, `-O`
  codegen) is never exercised by a deploy. The `release-archive-smoke`
  job is the only Release-config compile. It is a `build` (not
  `archive`) to avoid the build-number bump pre-action and signing. NB:
  `-target` cannot be combined with `-workspace`; a bare `build` action
  on the scheme builds only the app + its two embedded extensions (the
  three test targets are registered build-for-`[test]`-only, so `build`
  skips them) — verified no app-hosted-test build, no signing error.
- **The mtime-touch ritual for Core Data model edits is retired.** The
  `CompileCoreDataModel` plugin now declares the inner
  `*.xcdatamodel/contents` and `.xccurrentversion` files as `inputFiles`
  (it `FileManager`-walks the `.xcdatamodeld` bundle), so llbuild
  invalidates the `momc` command on a real model edit. momc still
  receives the `.xcdatamodeld` directory as its argument — only the
  *invalidation* keying changed. Proven: a `contents`-only mtime change
  (dir untouched) re-runs `momc`.
- **The pbxproj-drift gate depends on xcodegen idempotence.** CI
  regenerates both projects and fails on `git diff --exit-code` of
  `*.xcodeproj/project.pbxproj`. The `$(LOCAL_DEVELOPMENT_TEAM)` xcconfig
  indirection keeps regen idempotent — never put `DEVELOPMENT_TEAM` into
  `project.yml`'s `settings: base:` or the gate flaps on every team ID.
- **Snapshot precision is relaxed only for the Form-bearing tour
  snapshot.** `IOSScreenTourTests.assertScreen` defaults to exact-pixel
  (1.0); only `test_08_settings_light` (SettingsScreen's
  `NavigationStack + Form`) uses `precision: 0.99, perceptualPrecision:
  0.98`, per the 2026-05-17 "Form views drift" entry. New non-Form
  snapshots stay strict.
- **`swift test` runs with bounded parallelism + a retry, by design.**
  The `spm` job runs LillistCore with `--parallel --num-workers 2` and
  retries once. **Toolchain quirk (Swift 6.2.4): `--num-workers N`
  requires `--parallel` — the bare form errors `--num-workers must be
  used with --parallel`** (the plan's printed `--num-workers 2` was
  corrected accordingly). This is the runner-level mitigation for
  residual #11's THREE manifestations: (1) the ParitySuiteTests-triggered
  parallel-container SIGSEGV, (2) the `SyncQuiesceMonitorTests` quiet-
  window timing flake, and (3) the Wave-4 `TaskStoreRecurrenceSpawnTests`
  "After-completion series spawns at completedAt + interval" `< 2.0s`
  wall-clock flake. None is a product bug — production never builds more
  than one container — so the mitigation is in CI invocation, not source.
  CLAUDE.md "Build & test" mirrors the bounded invocation. Note: even
  `--no-parallel` does not fully eliminate the timing flakes (they trip
  under external CPU load too), which is why the *retry* is the real net.

- **Host-pinned snapshot tests are EXCLUDED from CI.** The LillistUI
  `*SnapshotTests` / `*ScreenTourTests` PNG baselines are pinned to the
  recording host; they drift on any other machine (cross-host
  font/anti-aliasing) and so cannot pass on a hosted runner. The `spm`
  job runs LillistUI with `--skip Snapshot --skip Tour` (the logic
  suites — 40 Swift-Testing + 60 non-snapshot XCTest — stay green), and
  the `ios` job does NOT run the `LillistUITests` bundle. Snapshot
  verification stays on the developer's pinned snapshot host (the
  `xcodebuild test -scheme Lillist-iOS` recipe in CLAUDE.md). This was
  verified empirically: on this Xcode 26.3 / iOS 26.2 machine the iOS
  `iOSSnapshotTests` suite fails ~10 baselines in components untouched by
  Wave 7 (e.g. `syncStatusBadge`, `quickCaptureDialog`), and the failing
  set even varies run-to-run — pre-existing environment drift, not a
  regression. (Re-recording the iOS baselines on the CI runner is an
  unscoped follow-up if snapshot coverage in CI is ever wanted.)

- **The app-hosted live-swap tests and the UI tests do NOT run in CI;
  they run on a developer's signed Mac with an iCloud account.** The
  `Lillist-iOSAppHostedTests` target hosts the `liveSwapAllowed`
  migration/swap tests, which stand up a live
  `NSPersistentCloudKitContainer`. On any host **without a signed-in
  iCloud account** — including a GitHub hosted runner — CloudKit setup
  fails with `CKAccountStatusNoAccount`, after which the test SQLite
  stores corrupt ("database disk image is malformed") and the bundle
  aborts. Verified locally: ad-hoc simulator signing
  (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-"`) DOES install +
  launch the host app on the simulator, so signing is not the blocker —
  the **missing iCloud account** is. `Lillist-iOSUITests` likewise needs
  a launchable signed host. So the `ios` CI job runs ONLY the standalone
  `Lillist-iOSTests` bundle (`TEST_HOST=""`, no container, no iCloud);
  the app-hosted + UI tests are verified exactly as Wave 1/4 verified
  them — on a developer's signed Mac with iCloud. This is the inverse of
  the macOS lane's lesson: the macOS test target was made standalone
  (`TEST_HOST=""`) so `CODE_SIGNING_ALLOWED=NO` works; the iOS app-hosted
  target has no standalone fallback AND needs iCloud, so it stays out of
  CI rather than being forced to sign.

- **Warnings-as-error on the LillistUI *test* target surfaced iOS-only
  deprecations.** Adding `.treatAllWarnings(as: .error)` to
  `LillistUITests` turned a pre-existing `UITraitCollection(traitsFrom:)`
  iOS-17 deprecation (in two snapshot helpers) into a build error — but
  only under `xcodebuild` iOS, since the `#if os(iOS)` snapshot code never
  compiles under host `swift test` (where the plan's Task 1 was verified).
  Migrated both sites to the `UITraitCollection(mutations:)` closure API
  (style+scale-equivalent; both snapshot suites stay green). Lesson: a
  warnings-as-error change to a cross-platform test target must be
  verified under `xcodebuild` for the iOS-only code, not just host
  `swift test`.

**Cross-plan dependency.** `store-swap-safety` (Wave 1) created the
`Lillist-iOSAppHostedTests` target and Wave 4 grew its source list; this
plan does not create it, and — per the iCloud limit above — CI does not
run it. If a future plan adds a *new scheme*, add a matching CI job.

**Evidence.** `.github/workflows/ci.yml` (seven jobs: spm, project-drift,
ios, macos, release-archive-smoke, localization-lint, notify); the folded-in
`localization-lint` (standalone `lillistui-localization.yml` deleted);
`Packages/LillistUI/Package.swift` at swift-tools 6.2 with warnings-as-error
+ excluded snapshot dirs; `CompileCoreDataModel.swift` declaring inner-model
`inputFiles`; `IOSScreenTourTests.assertScreen` precision params. One commit
per task on `main`.

## 2026-06-05 — LillistUI localization extraction has two blind spots (Plan: lillistui-localization-a11y, Wave 7)

The `-emit-localized-strings` extraction (and the
`Tools/CI/check-lillistui-localization.sh` drift lint built on it) only
sees a string when (a) its key is a **compile-time literal** in a
`String(localized:)` / `Text(...)` / `LocalizedStringResource(...)` call,
and (b) the call site **actually compiles in the build the extractor
runs**. Two consequences a future contributor must keep in mind:

- **Runtime-keyed strings are invisible.**
  `String(localized: .init(someRuntimeString))` extracts nothing (no
  data-flow analysis). The four `TaskRowView` reorder VoiceOver actions
  originally did exactly this (`.init(action.accessibilityKey)`) and were
  therefore English-only AND undetectable by the lint. Fixed by rendering
  them through a compile-time literal switch (`ReorderActionsModifier.label(for:)`
  — `String(localized: "Move up", bundle: .module)` etc.); they now extract
  and are in the catalog. **Always use literal keys for `.module` strings.**

- **The lint runs the macOS HOST build, so `#if os(iOS)` strings are never
  extracted.** `FloatingAddButton` is iOS-only, so its `.module` strings
  ("New task", "Opens quick capture", "Capture from clipboard") compile out
  on the host and the lint cannot see them. They are correct (`.module`-pinned)
  and were **added to `Localizable.xcstrings` by hand** so they are
  translatable, but the lint does **not** guard them — a future edit to an
  iOS-gated `.module` string won't be caught. Closing this fully would need
  an iOS-target extraction pass (xcodebuild-based) wired into the lint; that
  is an unscoped follow-up. Until then: when you add/rename a `.module`
  string inside `#if os(iOS)`, update the catalog by hand.

## 2026-06-06 — Diagnostic logging: attribution, watermarks, and the read-only WAL snapshot (Plan: diagnostic-logging)

File-based diagnostic logging (`Packages/LillistCore/Sources/LillistCore/Diagnostics/`)
landed a few traps a future contributor would otherwise rediscover the hard way:

- **`DiagnosticLog` stamps the authoritative `process` + per-file monotonic
  `seq` at write time; emitters pass placeholders.** Only the per-process log
  instance knows its true process, and centralizing `seq` gives one ordering
  across every emitter sharing a file (observer + stores + drag). So a
  `DiagnosticEvent` constructed by an emitter has `process: .app, seq: 0` until
  it passes through `DiagnosticLog.log` — never trust those fields off an
  emitter-built event (e.g. a test spy captures the placeholder, not the final
  value).

- **The history observer MUST use its own watermark key.**
  `DiagnosticHistoryObserver` consumes the same persistent-history stream as
  `RemoteChangeReconciler`. Two consumers sharing one
  `PersistentHistoryTokenStore` key clobber each other's progress, so the token
  store now takes a `key:` param and the observer uses
  `PersistentHistoryTokenStore.diagnosticsKey`. NB: **macOS had no history
  consumer at all** before this — the observer is the *first* one there, wired
  net-new in `AppEnvironment.bootstrap()`.

- **Per-process `transactionAuthor` keeps the app's default as `"Lillist.app"`
  on purpose.** `RemoteChangeReconciler.affectedTaskIDs` classifies local vs
  foreign (CloudKit import) history by `change.author != localAuthor`. The
  extensions/CLI stamp *distinct* authors (so the observer can attribute their
  writes), but if you change the **app's** default author the reconciler will
  misclassify the app's own writes as foreign imports and reconcile in a loop.

- **`VACUUM INTO` opened `SQLITE_OPEN_READONLY` works against the *live* WAL
  store precisely because the app holds it open.** The read-only connection can
  read committed WAL frames only while the live writer's `-shm` exists — which
  is why we never close the store for the snapshot, and why the snapshot is one
  consistent file (no `-wal`/`-shm` to copy). The dest path is interpolated into
  a SQL string literal, so it is single-quote-escaped (`'' `); keep that if the
  path ever becomes user-influenced.

- **`value(forKey:)` on an undeclared Core Data attribute raises an *uncatchable*
  Obj-C exception.** `DiagnosticHistoryObserver.flatten` reads `id`/`position`
  off arbitrary history-change objects, so every dynamic read is guarded by
  `entity.attributesByName[key] != nil`. Do not read an attribute off a
  history-resolved object without that guard — a Swift `do/catch` will not save
  you.

- **`TaskStore.create` computes `nextPositionDetail` *before* inserting the new
  row** so `observedMaxPosition` reflects real siblings, not the new task's
  default `position == 0.0`. This is behavior-preserving for the assigned value
  because `FractionalPosition.position(after: nil) == position(after: 0.0) == 1.0`.

## 2026-06-08 — SiblingOrder: one canonical sibling comparator for all presenters and recompaction

**Context.** The reorder-tie RCA (`.rca/reorder-anchors-out-of-order/`) found that `TaskStore.recompactSiblings` and the iOS `TaskTree.applySort(.personalized)` each had their own sort closure, and the macOS `TaskListView.buildTree` relied on Core Data fetch order as a secondary tiebreak. Because `NSManagedObject.id` is a UUID and Core Data orders UUID attributes as raw bytes, not as Swift's `uuidString` lexicographic order, the three orderings were not guaranteed to agree on ties.

**The invariant.** Every place that orders siblings — recompaction, iOS tree presentation, macOS tree presentation, and the `SmartFilterStore.list()` fetch — must use exactly one comparator: `SiblingOrder.precedes(positionA:idA:positionB:idB:)` (position ascending, `id.uuidString` ascending on ties). This is the only order that is device-independent (no `createdAt`, no locale, no raw byte UUID), so when two devices recompact the same tied pair they arrive at the same `1..n` positions and CloudKit does not ping-pong.

**The gotcha: never sort by UUID via NSSortDescriptor.** An `NSSortDescriptor(key: "id", ascending: true)` sorts UUIDs by their raw `NSData` byte representation. Swift's `UUID.uuidString` is a hexadecimal text representation with hyphens; byte order and string order disagree for many UUID values. Code that appears to work under a single context (all UUIDs are distinct and the sort is "some order") can silently produce a different order than `uuidString`, making recompaction non-idempotent across contexts. Always sort UUIDs in Swift in-memory via `uuidString` comparison.

**The heal path.** `TaskStore.reorder` and `SmartFilterStore.reorder` now heal a tied anchor pair before re-checking the out-of-order guard: `recompactSiblings` (via `SiblingOrder`) → positions updated in-memory → re-check. A tie heals; a genuine inversion (after.position > before.position) still throws. The throw is surfaced as a transient toast, not as `loadError`, so users see a recoverable "Couldn't move that item" message rather than a full-screen brick. Load-time `normalizeSiblingsIfDegenerate` additionally pre-cleans degenerate data before the first reorder attempt.

## 2026-06-12 — Row-level drag gestures eat embedded-control taps (RCA: status-tap-primaryaction-dead)

**Context.** From build 26 (2026-05-26) to build 40, tapping the status
circle on an iOS task row did nothing — no cycle, no error, no navigation —
while long-press (the explicit status menu) worked. Full investigation in
`.rca/status-tap-primaryaction-dead/`; fixed across 1d1f285 / 2ee2a6d /
a8ac881 / ac7ad90.

**The rule: a `.gesture(LongPressGesture.sequenced(before: DragGesture))`
attached to a row must never cover interactive controls.** Even plain
`.gesture` (lowest priority, which "should" yield to child controls)
consumes quick taps on an embedded `Menu(primaryAction:)` — the
primaryAction simply never fires, while the long-press context-menu
interaction (an independent UIKit recognizer) keeps working, and UIKit
cell-selection taps (row navigation) keep working on device. The three tap
mechanisms arbitrate independently; testing one tells you nothing about the
others. Falsified single-variable on the simulator: removing the
NavigationLink wrapper alone left the tap dead; removing the row gesture
alone revived it.

**The shape of the fix.** Scope the gesture, don't tune arbitration:
`TaskOutlineRowView` hands callers ONLY the inert text label
(`TaskOutlineRowLabel`) for wrapping in `NavigationLink` +
`.dragReorderGesture` (gesture-only sibling of `.dragReorderable`);
chevron and status control are composed outside the closure, so the type
system prevents re-introducing the overlap. `.reportRowGeometry` stays on
the full row — drag-overlay geometry is unaffected by where the gesture
lives. Consequence: drags start from the text region, not the status
circle (whose long-press belongs to the menu anyway).

**Why five deploys shipped it.** (1) No test at any layer exercised a real
tap — closure-unit tests, static snapshots, and store-API tests all pass
with a dead control; `StatusCycleUITests` now drives the real
tap→closure→store→relaunch chain on the localOnly `--ui-test-*` seams.
(2) The pipeline was silent by design: `try?` around `transition`, silent
no-op on equal status, no `task.transition` diagnostic (now emitted, with
`noop:` flagging stale-UI anomalies), no failure surface (now a transient
toast).

**Bonus gotchas from the same investigation.**
- `for i in 1..<collection.count` traps on empty collections
  (`Range requires lowerBound <= upperBound`); both load-seam normalizers
  shipped it, so every FRESH install of build 41 would have crashed at
  launch — dev devices never hit it because their stores are non-empty.
  Pairwise `zip(xs, xs.dropFirst())` is total. A fresh-install launch is
  worth one smoke check per deploy.
- XCUITest on the iOS 26.2 simulator does not push `NavigationLink(value:)`
  detail views from List rows (selection highlights, no push) even with all
  custom gestures removed; on-device navigation is fine. Positive
  navigation assertions stay device-only.
- Nested types of a generic SwiftUI view can't be ViewBuilder closure
  parameters (`TaskOutlineRowView<LinkContent>.Label` makes inference
  circular) — hoist them to file scope (`TaskOutlineRowLabel`).

## 2026-06-12 — Rainbow Logic design system: cross-cutting SwiftUI lessons

**Context.** Applied the Rainbow Logic ("Structured Whimsy") design
system across both apps in seven waves (spec:
`docs/plans/2026-06-12-rainbow-logic-design-system.md`). A handful of
framework-shape surprises are worth recording so the next visual change
doesn't re-hit them.

**Rules.**

- **macOS `Menu` labels drop `Shape` fills in hosted/headless render
  contexts.** The `StatusCubeView` (a `RoundedRectangle().fill(...)`
  composition) rendered as a bare SF checkmark when used directly as a
  `Menu`'s `label:`, both in `NSHostingView` snapshots and the menu-bar
  popover — `Image`s survive that path, arbitrary `Shape` fills do not.
  Fix: render the cube as a *plain* view and overlay a `Menu` whose
  `label:` is `Color.clear` as a transparent hit layer
  (`StatusIndicatorView`). Identical tap/long-press semantics, and the
  cube draws everywhere. This is why the status control is a
  view-with-overlaid-Menu, not a Menu-with-cube-label.

- **Custom fonts need a one-time text-system warm-up before
  deterministic snapshots.** The first hosted render in a fresh process
  after `CTFontManagerRegisterFontURLs` lays text out with unsettled
  metrics (seen as a vertically-clipped `QuickCaptureView` placeholder
  that differed between the record pass and the verify pass). Rendering
  a throwaway line per typography token once per process
  (`RecordableSnapshotTestCase.textSystemWarmedUp`) makes the first
  *real* snapshot match the settled layout. Without it, record/verify
  disagree by one render.

- **`RECORD_SNAPSHOTS=YES` must travel two different roads.** Plain env
  vars reach the `swift test` host but NOT the `xcodebuild test` test
  host. The single switch (`RecordableSnapshotTestCase`, gating
  `withSnapshotTesting(record: .all)`) works for both because the
  `Lillist-iOS` scheme maps the env var to the `$(RECORD_SNAPSHOTS)`
  build setting, set on the CLI as `xcodebuild test … RECORD_SNAPSHOTS=YES`.
  This retired the old "temporarily thread `record: .all` and revert"
  ritual.

- **Dark snapshot fixtures need an opaque themed background or they
  verify nothing.** Pre-redesign dark baselines rendered near-white
  text onto the bitmap's default white canvas — visually broken and
  catching no regressions. `SnapshotHost` now backs every fixture with
  `LillistColor.workspace`, so dark baselines exercise real contrast.

- **Code-defined dynamic colors over asset catalogs for a testable
  palette.** `RainbowPalette.dynamic(light:dark:)` builds a
  trait-resolving `Color` from raw hex via `UIColor {trait}` /
  `NSColor(name:dynamicProvider:)`. This let `RainbowPaletteTests` pin
  every value per scheme (resolve under a forced
  `UITraitCollection`/`NSAppearance`) and `RainbowContrastTests` gate
  WCAG ratios — both impossible against opaque catalog entries. It also
  means one Swift source serves both apps + both extensions with no
  per-target duplication. NB: the iOS `UIColor.getRed(_:green:blue:alpha:)`
  branch only compiles under `xcodebuild` (it is `#if canImport(UIKit)`),
  so argument-label slips there pass host `swift build` but fail the
  iOS scheme — build the iOS scheme before trusting cross-platform
  color test code.

- **Functional `base` hues are never text; `ink` is.** The exported
  light `ink` values for orange/green/blue did not clear 4.5:1 on their
  own `soft` surfaces; `RainbowContrastTests` is the authority that
  darkened them (e.g. `#C2530A` → `#B34C09`). When adding a hue, add the
  contrast case first and let it dictate the ink.

- **The share extension is its own process — register fonts there too.**
  `LillistFonts.registerIfNeeded()` is `.process`-scoped, so the share
  sheet needs its own call in `ShareViewController.viewDidLoad()`, and
  the target needs the `LillistUI` product dependency in `project.yml`
  (then `xcodegen generate`). Symbols-not-found at link time for
  `LillistUI.*` from the extension means the dependency edge is missing.

## 2026-06-12 — Liquid Glass does not render in offscreen snapshots (Rainbow Glass)

**Context.** The Rainbow Glass adoption (`Theme/GlassSurface.swift`)
moves the app's floating control layer and signature components onto
Apple's iOS 26 `glassEffect`. The first attempt to capture a glass view
through the existing snapshot harness produced a **completely white
image** — not just the glass region, the *entire* capture, including
non-glass siblings (text labels, the rainbow background, the legacy
non-glass `StatusCubeView` rendered in the same tree). A committed
non-glass baseline (`StatusCubeSnapshotTests`) rendered fine on the same
host, so offscreen snapshotting itself works — it is glass specifically
that voids the image.

**Cause.** `swift-snapshot-testing`'s default `.image` strategy
rasterizes via `CALayer.render(in:)` (an offscreen context). Liquid
Glass is composited by a live display/Metal pass that does not
participate in `render(in:)`; its presence blanks the surrounding layer
capture. The library's `drawHierarchyInKeyWindow: true` option *does*
render through the simulator's live window (where glass composites) —
but it **fatal-errors with "requires tests to be run in a host
application,"** and the `LillistUITests` SPM bundle is hosted standalone
(`TEST_HOST=""`, by deliberate design — see the *Build & test* notes on
the standalone bundle). So glass cannot be captured from the standard
LillistUI snapshot suite at all.

**Rules.**

- **Do not snapshot glass through `LillistUITests`.** Re-recording a
  glassified view's baseline yields a blank PNG, which is worse than no
  test: a blank "passes" against any other blank glass render and masks
  real regressions. The plan's "re-record baselines per wave" only
  applies to the *non-glass* portions of the UI.
- **Faithful glass renders come from a live window:** the Xcode canvas
  (`#Preview` on an iOS/macOS 26 device — see `StatusCubeGlassPrototype`,
  `GlassRowSpike`), the running app + `xcrun simctl io booted
  screenshot`, or a snapshot suite hosted in an **app target** (e.g.
  `Lillist-iOSAppHostedTests`, which has a host app, so
  `drawHierarchyInKeyWindow: true` works there). Verifying glass dark
  mode still requires real hardware (the device-only dark-glass
  rendering issue).
- **Snapshot regression for glass surfaces is an open decision** — keep
  it out of `LillistUITests` until an app-hosted glass-snapshot suite is
  in place, or accept manual visual verification (consistent with CI
  already carving out the host-pinned snapshots).

**2026-06-14 refinement (from the reconciliation pass).** The blanking is
not uniform — the rules that actually matter for the standalone
`LillistUITests` (offscreen `.image`) suite:

- **Interactive glass (`.interactive()`) reliably blanks the *entire*
  offscreen capture.** The add-task FAB (`GlassSurface.primaryAction`,
  the only interactive glass) blanked every tour screen it was overlaid
  on. Removing the FAB overlay from the tour's `phoneShell` un-blanked
  the lot. The interactive status control (`StatusIndicatorView`'s Menu)
  similarly blanks `test_06`.
- **An always-present `GlassEffectContainer` blanks too — even with no
  visible glass inside it.** The Wave-1 `glassGroup()` wrapping the
  (usually-empty) toast overlay blanked *all* TasksScreen snapshots until
  it was replaced with a plain `VStack` (non-overlapping toasts need no
  container).
- **Non-interactive glass mostly *does* render offscreen** with the
  tour's strategy (`.image(precision:perceptualPrecision:size:traits:)`
  + `displayScale` trait + `layoutIfNeeded()`): the archive toast and the
  expanded filter-header panel both captured correctly. So the
  reconciliation is: strip interactive glass (FAB, status Menu) from
  offscreen tests and cover it app-hosted; non-interactive glass can stay
  in `LillistUITests`. macOS still has no app-hosted glass target.

## 2026-06-15 — Snapshot reconciliation close-out: `.drawingGroup()` blanks offscreen too, and macOS glass is not offscreen-snapshottable

Two non-obvious findings from finishing the Rainbow Glass snapshot
reconciliation (the Wave 6 close-out).

**1. `.drawingGroup()` (Metal) blanks offscreen snapshots exactly like
Liquid Glass does.** The iOS empty-state tour snapshot
(`IOSScreenTourTests.test_05`, `TasksScreen` with `roots: []`) re-recorded
as a near-empty capture: the toolbar + footer rendered, but the entire
empty-state body was gone. The body is `RainbowEmptyStateView`, whose
`DotGridBackdrop` rasterizes its `Canvas` through **`.drawingGroup()`** —
which composites via Metal, and Metal does **not** participate in the
offscreen `CALayer.render(in:)` path the default `.image` strategy uses.
So `.drawingGroup()` voids the surrounding capture the same way glass
does. It is *not* the `.rainbow` glass button that blanked here — that's
non-interactive glass and renders offscreen fine (confirmed: every other
`.rainbow`-button baseline records correctly). `drawingGroup` is the only
such call in `LillistUI/Sources`, so the empty state is the lone victim;
its coverage moved to `Lillist-iOSAppHostedTests/GlassSnapshotTests`
(`test_emptyState_*`), where the live key window composites both Metal and
glass. Rule: treat any `.drawingGroup()`/`Canvas`-rasterized surface like
glass for snapshot purposes — capture it app-hosted, never offscreen.

**2. macOS Liquid Glass cannot be captured in an automated snapshot — the
AppKit capture path is gone.** The iOS app-hosted trick relies on
`UIView.drawViewHierarchy(in:afterScreenUpdates:)` via SnapshotTesting's
`.image(drawHierarchyInKeyWindow: true)`. **AppKit has no equivalent** —
`NSView`'s strategy is offscreen-only (`bitmapImageRepForCachingDisplay` +
`cacheDisplay`), which blanks glass. The only way to capture composited
glass on macOS is a window-server screenshot of an on-screen `NSWindow` —
but **`CGWindowListCreateImage` is obsoleted (unavailable, a hard compile
error) as of macOS 15** ("Please use ScreenCaptureKit instead"), and
ScreenCaptureKit requires **Screen Recording (TCC) permission**, which
prompts interactively and fails unattended/CI. A standalone spike
confirmed the obsoletion at compile time on the macOS 26.2 SDK.

Decision (with Mikey): **defer + document.** No `Lillist-macOSAppHostedTests`
target — the only macOS-*unique* glass is `QuickCaptureView`'s `.panel`;
the `.rainbow` buttons/toggles and the `GlassSurface` seam itself are
already covered by `Lillist-iOSAppHostedTests/GlassSnapshotTests`. The
three `#if os(macOS)` snapshot suites that render glass on the 26 host are
**quarantined** with `XCTSkip` (`QuickCaptureViewSnapshotTests`,
`ReduceTransparencySnapshotTests`, `MacOSScreenTourTests`) so the host
`swift test` signal stays honest; macOS glass is verified manually.
Revisit if Apple ships an offscreen glass-capture API.

**3. `ReduceTransparencySnapshotTests` is obsolete on OS 26, not just
un-capturable.** On OS 26 the seam (`GlassSurfaceModifier`) deliberately
does **not** branch on `reduceTransparencyOverride` for the glass path —
the renderer self-handles Reduce Transparency. So the override no longer
flips a glass surface to its opaque fallback; both on/off render identical
glass. The opaque-fallback path is pre-26-only and therefore not
exercisable from a 26 host at all. Its *logic* stays unit-covered in
`GlassSurfaceTests` (`prefersSolidFallback`, chrome-vs-fill); the now-dead
snapshot pair is quarantined alongside the other macOS glass suites.

## 2026-06-16 — A per-row visual change must be re-recorded on BOTH snapshot paths

**Context.** Reshaping the status chip (`StatusCubeView`: circle → squircle,
started's leading-half → centered dot) and squaring the menu/picker glyphs
(`StatusGlyph.symbol`: `circle*` → `square*`) touched a visual that appears in
*every task row and detail surface*. The trap: the affected baselines are split
across two recording mechanisms that don't overlap.

- **iOS-rendered suites** (`LillistUITests` Tour/DragReorder + app-hosted
  `GlassSnapshotTests`) record via the simulator:
  `xcodebuild test -scheme Lillist-iOS -only-testing:LillistUITests
  -only-testing:Lillist-iOSAppHostedTests/GlassSnapshotTests RECORD_SNAPSHOTS=YES`.
  This pass compiles out every `#if os(macOS)` suite, so it silently leaves the
  macOS cube/row/detail baselines stale.
- **macOS-only suites** (`#if os(macOS)`: `StatusCubeSnapshotTests`,
  `TaskListViewSnapshotTests`, `TaskDetailViewSnapshotTests`,
  `LocalizationSnapshotTests`) render `NSView` and record **only** on the host:
  `RECORD_SNAPSHOTS=YES swift test --package-path Packages/LillistUI --filter <suite>`.

Lesson: when you change a shared per-row/per-detail visual, grep for every
snapshot suite that renders it across **both** platforms and re-record both —
`TEST SUCCEEDED` on the iOS scheme is *not* proof the macOS baselines are
current (and CI doesn't run the host-pinned macOS suites, so the drift hides
until someone runs host `swift test` snapshots). Quarantined glass suites
(`QuickCaptureViewSnapshotTests`, `MacOSScreenTourTests`) stay manual.

Tangent found en route: `Theme/GlassRowSpike.swift` (a dev preview harness) had
three `Text`/`Picker` literals missing from `Localizable.xcstrings` — a
pre-existing `check-lillistui-localization.sh` failure unrelated to this change,
since the lint *does* extract SwiftUI `Text`/`Picker` `LocalizedStringKey`
literals (not only `String(localized:)`). Added the empty `{}` entries.

## 2026-06-16 — The FAB dropped interactive glass; `GlassSurface.primaryAction` is gone

**Context.** The add-task FAB was the *only* `.interactive()` glass in the app
(`GlassSurface.primaryAction`, tinted `scriptPurple.base`). To unify it with the
Quick Capture "Add task" button — itself `.rainbow(.lavender)` →
`.glassSurface(.statusTinted(LillistColor.lavender))` — the FAB moved to that
same surface (`FloatingAddButton` now does
`.glassSurface(.statusTinted(LillistColor.lavender), in: Circle())`). With no
remaining caller, the `.primaryAction` enum case **and the whole interactive-
glass path** (`isInteractive`, the `glass.interactive()` branch) were removed
from `GlassSurface`. There is now **no interactive glass anywhere** in Lillist.

Consequences for anyone re-reading the older glass notes (2026-06-12/14):
- The "interactive glass reliably blanks the *entire* offscreen capture" lesson
  is now **moot for the FAB** — non-interactive tinted glass renders offscreen
  fine. The surfaces that still blank offscreen are the `StatusIndicatorView`
  `Menu` hit layer and `.drawingGroup()`/Metal (`DotGridBackdrop`). Those, not
  interactivity, are why `GlassSnapshotTests` is app-hosted.
- The FAB snapshot (`test_fab_light/dark`) **stays app-hosted** with the other
  glass surfaces even though it no longer *needs* a live window — kept there for
  grouping, not necessity. Its baselines were re-recorded for the new lavender
  tint (the only visual delta: saturated purple → softer lavender, no shimmer).
- The FAB's pre-26 opaque fallback is unchanged: `.primaryAction` already fell
  back to `LillistColor.lavender`, and `.statusTinted(.lavender)` resolves to the
  same color — so Sequoia keeps the identical solid lavender fill.

Lesson: when retiring the sole user of a design-token case, delete the case *and*
the machinery it was the only trigger for (here, the entire `.interactive()`
branch), rather than leaving an always-false vestige — and append a note so the
prior "interactive glass blanks offscreen" entry isn't mistaken for current law.

## 2026-06-17 — A `Button` in the drag region starves the long-press reorder (inverse of the 2026-06-12 rule)

**Context.** Wave 3 (`0c2761e`) wired the unified editor into iOS and retired the
pushed detail view. The iOS task-row label changed from `NavigationLink(value:)`
to `Button { onOpenTask(id) }`, keeping `.dragReorderGesture(...)` on it — the
commit even claimed "drag gesture preserved." It wasn't: tapping a row opened the
editor, but long/force-pressing to begin a reorder no longer fired.

**The rule (the other face of 2026-06-12).** A SwiftUI `Button` wrapping the row
label **starves** the row's `.gesture(LongPressGesture.sequenced(before:
DragGesture))`. The `Button`'s intrinsic press recognizer wins gesture arbitration
over the lower-priority added `.gesture`, so the sequence never reaches `.second`
and `controller.beginDrag` is never called — tap works, reorder is dead. The
2026-06-12 entry recorded the *inverse* (an added long-press eating an embedded
`Menu`'s taps); both are the same underlying truth: **a control with an intrinsic
gesture and an added `.gesture` in the same region arbitrate unreliably.**

**The fix — own the tap, don't tune arbitration.** Open the editor via
`.onTapGesture { onOpenTask(id) }` on the inert `TaskOutlineRowLabel` (no
`Button`), with `.dragReorderGesture` applied after it so the long-press is the
higher-priority gesture. A quick tap fails the 0.3s long-press and falls through
to the tap; a held press wins the long-press and starts the drag — the two
disambiguate purely by time because neither is a control's intrinsic gesture. This
is exactly what macOS `TaskListView` already did
(`.onTapGesture { openTaskEditorAction(id) }` + `.dragReorderable`), so the fix
brings iOS in line with the existing convention rather than inventing one. Restore
the VoiceOver button affordance the `Button` provided for free with
`.accessibilityElement(children: .combine)` + `.accessibilityAddTraits(.isButton)`
+ `.accessibilityAction { onOpenTask(id) }`.

**Why no test caught it.** As in 2026-06-12, no test exercises real gesture
arbitration — the `DragController*Tests` drive the state machine directly, and
snapshots render a visually identical row. Simulator XCUITest gesture arbitration
also differs from device (it won't even push `NavigationLink` details), so the
long-press-drag path is a manual on-device check. Rejected alternatives:
`.highPriorityGesture`/`.simultaneousGesture` on the `Button` (still fighting the
control's recognizer; `.simultaneous` risks the tap *also* firing after a
settle-in-place drag), and composing the tap into `.dragReorderGesture` via
`.exclusively(before:)` (more deterministic but changes a shared cross-platform API
and diverges iOS from the proven macOS `.onTapGesture` convention).

## 2026-06-18 — Debug data-store reset: `reconfigure` preserves data, a wipe must `destroyPersistentStore`

The Settings → Debug "Reset data store…" button (for a suspected-corrupt
store) needed a **full, irreversible wipe**: back up → erase the CloudKit zone
→ destroy the local store → rebuild empty. The non-obvious trap: the existing
Plan 21 machinery looks like it already does this, but it does **not**.
`PersistenceHost.reconfigure(to:)` and `MigrationCoordinator` only ever *swap
the store description* (sync mode) on a coordinator that keeps the same on-disk
files — they **preserve data by design**. `QuarantineManager.copyStore` copies;
nothing in the codebase ever called `destroyPersistentStore`. So "rebuild
empty" was genuinely new behavior, not a reuse.

**What was added.** A focused `PersistenceResetting` protocol (segregated from
`PersistenceReconfiguring` so `MigrationCoordinator` never gains a destroy
surface and the reset service never gains a mode-swap surface) with three
primitives on `PersistenceHost`: `tearDownStore(backupVia:)` (flush →
`coordinator.remove(store)` → quarantine copy of the now-closed files),
`rebuildEmptyStore()` (`coordinator.destroyPersistentStore(at:type:.sqlite,...)`
→ re-add a fresh empty store for `currentMode` → `viewContext.reset()`), and
`reattachStore()` (re-add the original files — the rollback path). The
`@MainActor DataStoreResetService` orchestrates, **reusing** the same building
blocks as `MigrationCoordinator` (zone eraser, quiesce monitor, notification
cancel, quarantine).

**Ordering invariants (same as the migration path, re-derived):**
1. `cancelAllPending()` *first* — a wipe must not leave stale fires pointing at
   deleted rows (skeptic G9).
2. Account-changed pre-flight *before* the zone erase — never wipe the wrong
   account's zone after an identity switch.
3. Backup *before* the irreversible erase — `copyStore`'s disk-space pre-flight
   throws ahead of the cloud erase (blind-spot #5).
4. On zone-erase failure, `reattachStore()` so the coordinator is never left
   store-less, then rethrow.

**Two deliberate departures from the migration machinery.** (a) It is **not**
journaled — the `MigrationJournal` invariants (`previousMode`, restore-reverts-
mode) are transition-shaped and a same-mode wipe would corrupt them; the
quarantine copy (30-day retention) is the recovery anchor instead. (b) There is
a brief **store-less window** between `tearDownStore` and `rebuildEmptyStore`
(the async zone erase runs in between); this is acceptable only because the op
is behind a blocking Settings modal with notifications already cancelled.

**Testing.** The orchestration (ordering, localOnly-skips-erase, erase-failure-
reattaches, account-changed-aborts) is covered by fakes under plain `swift test`
(`DataStoreResetServiceTests`). The live destroy/rebuild/reattach primitives
touch a real container, so — like the other `PersistenceHost` live cases — they
are `liveSwapAllowed`-gated (skip under `swift test`, run in
`Lillist-iOSAppHostedTests`). They use `.localOnly` so they need no iCloud
account, unlike the iCloudSync swap cases. The real full-wipe-including-iCloud
path is a manual on-device check (CloudKit zone erase needs a signed-in account).

## 2026-06-20 — A post-build script that patches the product `Info.plist` cannot run under the script sandbox at *archive* time

Goal: drive `CFBundleShortVersionString` from the repo `VERSION` file (semver
source of truth) so the built app's marketing version always tracks semver. The
obvious implementation — a `postBuildScripts` phase that `PlistBuddy`-sets the
key on the built bundle — **works for `xcodebuild build` but fails `xcodebuild
archive`**, which is the path that actually matters (deploy/TestFlight).

The trap is build-vs-archive output redirection crossed with
`ENABLE_USER_SCRIPT_SANDBOXING: YES` (set repo-wide in both project.yml
`settings.base`):

- A normal **build** puts the product at `BUILT_PRODUCTS_DIR` (==
  `TARGET_BUILD_DIR`), which is a writable script-sandbox root — so the
  PlistBuddy write succeeds. (Verified: a simulator build stamped `0.8.5` into
  the app + both `.appex`es.)
- An **archive** redirects the product to
  `…/ArchiveIntermediates/<scheme>/IntermediateBuildFilesPath/UninstalledProducts/iphoneos/…`,
  which is **outside** the script sandbox's writable roots. The exact failure:
  `Set: Entry, ":CFBundleShortVersionString", Does Not Exist` followed by
  `Error Opening Destination: …/UninstalledProducts/…/Info.plist [Operation not
  permitted]` → `Command PhaseScriptExecution failed`.

You cannot declare the plist as the script's `outputFiles` to widen the sandbox:
Xcode's own `ProcessInfoPlistFile` task already declares that exact path as its
output, so a second declaration yields `error: Multiple commands produce
'.../Info.plist'`. (Separately: `inputFiles` *is* needed for the script to
*read* `$(SRCROOT)/../../VERSION` under the sandbox.) So the in-place-patch idea
is a dead end while sandboxing stays on.

**Why an Archive pre-action is *also* wrong here (the non-obvious part).** The
tempting fix is to mirror `bump-build-number.sh` — a scheme Archive pre-action
(which *does* run outside the script sandbox) that writes the version into an
xcconfig. But scheme pre-actions are **off-by-one**: the current archive uses
the build settings resolved *before* the pre-action ran, so the write only takes
effect on the *next* archive. That's harmless for an ever-incrementing build
number (the file just "holds the next build's number"), but fatal for the
marketing version, because deployit bumps `VERSION` and then *immediately*
archives — the first archive after a bump would ship the previous version.

**The fix that shipped: sync at *bump* time, not build time.** The marketing
version only changes when semver bumps, and deployit always bumps before it
archives. So a semver **pre-bump** hook
(`.semver/hooks/pre-bump/sync-marketing-version.sh`) rewrites `MARKETING_VERSION`
in both `project.yml` `settings.base` and regenerates both pbxprojs from the
new version. Pre-bump fires before the `chore(release)` commit, and the hook
`git add`s the four touched files, so the sync lands in that one commit and is
covered by the version tag. No build-time script → the sandbox is irrelevant;
no off-by-one → the bump completes before xcodebuild resolves settings.
`MARKETING_VERSION` stays in `project.yml` because **deployit hard-fails if it
can't parse it there** (`_read_marketing_version` → `fail(...)`), which also
rules out moving the value into an xcconfig. Other options considered and
rejected: `xcodebuild archive … MARKETING_VERSION=$(cat VERSION)` (clean in raw
CI, but deployit builds its own invocation and exposes no setting override) and
disabling `ENABLE_USER_SCRIPT_SANDBOXING` on the stamp targets (keeps a literal
build phase but weakens the repo-wide posture).

App Store note: an `.appex`'s short version must match its host app, so
`MARKETING_VERSION` lives at the project (not target) level and the pbxproj
regen covers `ShareExtension-iOS` and `ShortcutsActions` along with the app.

## 2026-06-23 — Code signing uses the login keychain from every path; never add a signing keychain ahead of it

**Rule.** All Lillist code signing — GUI Xcode, headless `xcodebuild` over
SSH/mosh, and `/deployit` — uses the certificates in the **login keychain**:
`Apple Development: Michael Ward (39D9SZ7GT8)` (Development) and
`Developer ID Application: Michael Ward (VMY8R4T742)` (Developer-ID macOS
distribution). The login keychain is set `no-timeout`, so it stays unlocked
for headless SSH/mosh `xcodebuild` runs — no separate "build" keychain is
needed. CI signs nothing (`CODE_SIGNING_ALLOWED=NO`).

**Gotcha (why this is written down).** A second signing keychain placed
*ahead* of `login.keychain-db` in the user search list
(`security list-keychains -d user`) silently breaks **GUI Xcode** signing:
automatic signing picks the first matching identity, hits the extra (locked)
keychain, and prompts for a password — even though headless SSH builds keep
"working" because that keychain happens to be unlocked in the SSH session.
The two contexts then sign with *different* identities, which is invisible
until Xcode prompts. Keep the search list at exactly
`login.keychain-db` + `/Library/Keychains/System.keychain`. Verify a clean
state with:

```bash
security list-keychains -d user            # → login.keychain-db, System.keychain
security find-identity -v -p codesigning   # → the two Michael Ward identities
```

XCUITest screenshot harness, related: `Lillist-macOSUITests` needs a *signed*
host app, so it relies on this login-keychain signing path; it runs on a
signed Mac (developer-mode enabled for the test runner), not in CI. See
`docs/reviews/2026-06-23-macos-visual-design-pass.md`.

## 2026-06-23 — `xcodebuild -exportArchive` re-stamps the iCloud environment; the entitlements file is not enough (RCA: secondary-Mac sync partialFailure)

**Symptom.** Enabling iCloud sync on a *second* Mac and choosing "Replace this
device with iCloud data" failed with `Sync failed: The operation couldn't be
completed. (CKErrorDomain error 2.)` — `CKError.partialFailure`. Nothing synced
between the Mac and the (working) iPhone.

**Root cause — the entitlement was right in source and wrong in the binary.**
`Apps/Lillist-macOS/Lillist.entitlements` correctly declares
`com.apple.developer.icloud-container-environment = Development` (the
load-bearing override that is *supposed* to keep the Developer-ID macOS test
build on the same Development database as the Development-signed iOS build).
But `codesign -d --entitlements :- Lillist.app` on the **shipped** build showed
`Production`. The reason: `xcodebuild -exportArchive` **re-stamps** that
entitlement from the export options' `iCloudContainerEnvironment` key, and for a
`developer-id` export the default *when the key is absent* is **Production** —
overwriting whatever the source `.entitlements` says. deployit's bundled
`assets/ExportOptions.macos.plist` set only `method`/`signingStyle`, so every
`/deployit` macOS build silently exported onto Production.

Production has **no deployed CloudKit schema** (the Development→Production
cutover is deferred, and `NSPersistentCloudKitContainer` only auto-creates the
schema in *Development*). So the only device that ever wrote successfully was the
iOS build (Development); the Macs were all pointed at an empty, schema-less
Production container. The first "replace local with iCloud" import against it
failed per-record → `partialFailure`.

**The decisive twist: Developer-ID export is Production-ONLY.** The obvious fix —
pin `iCloudContainerEnvironment = Development` in the export options — is
*rejected by Apple*:

```
error: exportArchive exportOptionsPlist error for key
"iCloudContainerEnvironment": value "Development" is not allowed
```

A Developer-ID provisioning profile only permits the **Production** CloudKit
environment at export. So a Developer-ID (distribution-signed) macOS build can
**never** join the Development database, no matter what the source entitlement
says. The `Development` value in `Apps/Lillist-macOS/Lillist.entitlements` was
always going to be overwritten to Production — the entitlement was cosmetic.
The only way to put a *macOS* build on Development is to `method =
development`-sign it (registered Macs only), exactly like the iOS test build.

**Lessons:**

1. **Verify the signed binary, never the source `.entitlements`.** For any
   CloudKit app distributed by *export*, the final
   `icloud-container-environment` comes from the ExportOptions plist + the
   profile, not the source file: `codesign -d --entitlements :- <app> |
   plutil -p - | grep icloud-container-environment`.
2. **Distribution channel dictates the CloudKit environment, hard.**
   Developer-ID / App Store / TestFlight → Production (no choice).
   `development`-signed → Development. You cannot mix: to test cross-device
   sync, *every* device must be on the same channel-implied environment.

**Resolution chosen: development-sign the macOS test build.** A Production
cutover was considered and rejected — the Production CloudKit environment is
too inflexible to commit to mid-development (schema deploys are permanent and
additive-only; iOS would have to move to TestFlight; data must be re-seeded).
Instead, `.deployit/ExportOptions.macos.plist` now uses `method = development`
(not `developer-id`), exactly mirroring the iOS test build: the macOS app is
Apple-Development-signed, talks to the **Development** CloudKit database (where
the data lives), and runs on **registered Macs** (the target Mac's UDID must be
in the team's Mac development profile — automatic signing +
`-allowProvisioningUpdates` fetches the regenerated profile incl. newly-added
devices). Trade-offs accepted: not notarized (Gatekeeper needs a one-time
right-click-Open / Settings approval per Mac) and no useful GitHub release
(deploy with `--no-release`). Developer-ID + Production + notarization is
deferred to the eventual shipping cutover.

**Secondary defect surfaced + fixed in the same pass.** The partialFailure was
undiagnosable because `CloudKitErrorClassifier` had no `.partialFailure` case
(collapsed to the opaque top-level description) and `CloudKitEventBridge` never
logged the raw error. Both now unwrap/log `CKPartialErrorsByItemIDKey` per item.
That logging is what let us read the per-item codes off the device.

## 2026-06-23 — Reverse-DNS namespace rename to `io.mikey.lillist`: per-pattern, not a blind sed; new IDs can't be provisioned headlessly

The whole identifier namespace moved off `io.mikeydotio.*` / `com.mikeydotio.*`
(a literal mis-read of the org string `mikeydotio`, which spells the domain
**mikey.io** → reverses to **`io.mikey`**) onto **`io.mikey.lillist`**: bundle
IDs, App Group `group.io.mikey.lillist`, CloudKit container
`iCloud.io.mikey.lillist`, the BGTask/user-activity IDs, and every internal
OSLog subsystem / UserDefaults key / notification ID / Spotlight domain (the
old mix of `io.` and `com.` prefixes was unified to `io.mikey.lillist.*`).

**A blind `s/mikeydotio/mikey/g` is wrong — four things must survive it.**
The rename was done as four *dotted* per-pattern replacements
(`io.mikeydotio.Lillist`, `io.mikeydotio.lillist`, `com.mikeydotio.lillist`,
then bare `io.mikeydotio`), applied specific-before-bare. That structure
deliberately skips:
- **GitHub paths** — `github.com/mikeydotio/Lillist` (the macOS Help-menu link),
  `mikeydotio/deployit-index`, `mikeydotio/agentics`. They use *slashes*
  (`mikeydotio/…`), so the dotted patterns never match them. These are repo/org
  references, not Apple IDs.
- **deployit's own launchd label** `com.mikeydotio.deployit.backend` — matched by
  neither `com.mikeydotio.lillist` nor `io.mikeydotio`. It's a different tool's
  identifier; leave it.
- **Two historical-typo records** of `group.com.mikeydotio.lillist` (the old CLI
  app-group bug) in `StoreLocatorTests.swift` and `engineering-notes.md` — these
  document a past mistake; flattening them to the new value destroys the lesson.
  `com.mikeydotio.lillist`→`io.mikey.lillist` hit them, so they were restored by
  hand. `engineering-notes.md` is append-only: old entries (incl. the
  `io.mikeydotio.lillist.crash` mention) stay verbatim; this entry is the record
  of the change.
- The user-facing **name** stays `Lillist` (`PRODUCT_NAME`, `CFBundleDisplayName`,
  the `Lillist.sqlite` store dir are not identifiers — don't touch them).

The pbxprojs are regenerated from the two `project.yml` specs via `xcodegen`,
not edited; `Apps/Config/Signing.local.xcconfig`'s `LOCAL_SU_FEED_URL` is
gitignored and carries the bundle ID in its deployit-served path, so it must be
updated by hand on each Mac.

**The wall: a brand-new App ID can't be provisioned from a headless build.**
Renaming the bundle ID/App Group/container means none of the new registered
records exist yet. A signed `xcodebuild … -allowProvisioningUpdates` over
SSH/mosh fails with `No Accounts: Add a new account in Accounts settings` +
`No profiles for 'io.mikey.lillist' were found` — auto-creating an App ID +
profile + iCloud container needs the interactive Apple-ID account that lives in
**GUI Xcode**, which the headless toolchain can't reach. (Builds against an
*already-provisioned* ID work headlessly because they reuse the cached profile
with no account.) So: unsigned builds
(`CODE_SIGNING_ALLOWED=NO`) confirm the *code* compiles; the first signed build
of the renamed app must be run once from Xcode (or have the IDs registered in
the portal) to mint the new records. The new CloudKit container starts **empty**
(old data abandoned) and the renamed bundle ID installs as a *separate* app — a
fresh install is cleanest, since the on-disk store's CloudKit mirror metadata is
bound to the old container name.

## 2026-06-23 — Local JSON backup (issue #7): schema stamping + change hooks

The local-backup subsystem (`Packages/LillistCore/Sources/LillistCore/Backup/`)
keeps an on-disk package of one JSON file per task in step with the live store,
rolls a daily zip snapshot, and restores from either. Three non-obvious traps:

1. **Stamp the CloudKit schema version explicitly at mutation sites — never in
   `awakeFromInsert`/`willSave`.** Issue #7 wants every task record to carry an
   integer `schemaVersion`. The tempting DRY move is a Core Data lifecycle hook,
   but both fire during `NSPersistentCloudKitContainer`'s *import* of a remote
   record: re-setting the attribute there re-dirties the imported object and
   echoes a redundant write back to CloudKit (a feedback loop). The setter
   (`LillistTask.stampCurrentSchemaVersion()`) is therefore called *explicitly*
   from every local write — the 12 `TaskStore` mutation methods (via the same
   lines that bump `modifiedAt`), plus the three non-`TaskStore` creation paths
   (`RecurrenceSpawner` spawn + deep-copy, `scheduleFollowUp`) and `Importer`.
   Imports never run through these paths, so no echo. The attribute is additive,
   optional, default `0` → a lightweight inferred migration; CloudKit
   auto-creates it on Development.

2. **One did-save chokepoint + one remote-change observer, projecting *inside*
   `perform`.** `LocalBackupCoordinator` does NOT thread a hook through each
   mutation. It observes `NSManagedObjectContextDidSave` on the `viewContext`
   (catches all local commits, spawns, journal/attachment writes, and merged
   background imports in one place) and `NSPersistentStoreRemoteChange` (catches
   cross-device CloudKit imports, cloned from `RemoteChangeReconciler`). The
   load-bearing discipline: extract only *Sendable* identifiers (`UUID`s, a
   sidecar-dirty flag) synchronously on the posting context queue — reading
   `id`/entity name never faults attributes — then re-fetch + DTO-project
   (faulting attachment bytes) on a *background* context and write on the
   `TaskBackupStore` **actor**. No managed object or history token ever crosses
   an `await`. Remote *deletes* carry no UUID without tombstones, so the remote
   path prunes by set-difference (live task IDs vs. package file IDs) rather than
   trusting the history change list.

3. **ZIPFoundation, because the repo's only zip was one-way.** Restoring "from a
   .zip archive" needs *unzip*; the existing `DiagnosticPackageBuilder` zips via
   `NSFileCoordinator(.forUploading)`, which has no inverse. Added ZIPFoundation
   (first dependency beyond swift-argument-parser) for real `.zip` create *and*
   extract. It resolves transitively into both app targets through the LillistCore
   SPM package — no pbxproj edit needed (only the two new app-target *.swift files
   needed `xcodegen generate`). Snapshot filenames are ISO-8601 with the *time*
   colons swapped to `-` (the date hyphens stay), so they sort chronologically
   and round-trip back to a `Date`.

Restore reuses the hardened destructive primitives: `DataStoreResetService`
(wipe local + iCloud) behind a `BackupDataResetting` seam, then
`Importer.apply(…, assetsDirectory:)` (extended this round to reload attachment
bytes). The schema-version gate runs *before* the reset (defense in depth even
though the UI gates first). The live-CloudKit halves — the remote-change file
sync and the real-iCloud-wipe restore — are **Mikey-verified on a signed Mac**,
not CI (same posture as the live-swap tests).

## 2026-06-24 — Production cutover: `-exportArchive` re-stamps the push entitlement too, macOS uses a *different* push key, and new signing keys need partition-list access

The deferred Production cutover landed: schema deployed Development→Production
in the Console; iOS `/deployit` export switched to `method = ad-hoc` (Apple
Distribution → Production), macOS to `method = developer-id` + notarized
(Production). Four non-obvious things surfaced, each verified on the *signed
binary* (`codesign -d --entitlements :- <app> | plutil -p -`), never the source
`.entitlements`:

1. **`-exportArchive` re-stamps `aps-environment` *and*
   `icloud-container-environment` — both are cosmetic in source for exported
   builds.** The 2026-06-23 RCA established the iCloud-env re-stamp; this round
   proved the push entitlement is re-stamped the same way. The iOS source
   declares `aps-environment = development` and *omits* the iCloud env, yet the
   ad-hoc-exported binary came out `aps-environment = production` +
   `icloud-container-environment = Production` (main app **and** both
   extensions). Consequence: **no source entitlement edits were needed for the
   cutover.** Local Xcode-run builds (Apple-Development-signed, entitlements used
   as-is) stay on Development; only the distribution *exports* flip to
   Production. Develop against Development, ship against Production, one
   unchanged entitlements file per target.

2. **macOS push uses a different entitlement key than iOS —
   `com.apple.developer.aps-environment` (prefixed) vs iOS `aps-environment`
   (unprefixed).** Proven by this project's own profiles: the iOS ad-hoc profile
   grants `aps-environment = production`; the macOS team profile grants
   `com.apple.developer.aps-environment = development`. `Apps/Lillist-macOS/Lillist.entitlements`
   declares the *iOS* key, so it is silently stripped at signing — the macOS
   build has **never** carried a push entitlement (verified absent in *both* the
   old `development` export and the new `developer-id` export; not a cutover
   regression). CloudKit sync still works via foreground/launch fetches; only
   real-time push is missing on macOS. **Fixed same day:** correcting the key in
   `Apps/Lillist-macOS/Lillist.entitlements` to
   `com.apple.developer.aps-environment` (value `development`) was the *entire*
   fix — automatic signing + `-allowProvisioningUpdates` regenerated the
   Developer-ID profile (`Mac Team Direct…`) *with* push (the App ID already had
   the capability from iOS), and the export re-stamped it to `production`
   (verified on the signed binary). The manually-named
   `Lillist Mac Developer ID Distribution` profile still grants no push, but it
   isn't used — automatic signing is retained precisely because it re-stamps
   `development`→`production` from one entitlements file; manual-pinning that
   named profile would have forced a single value and broken local dev.

3. **A freshly-imported signing identity blocks non-interactive codesign over
   SSH with `errSecInternalComponent`.** The ad-hoc export failed re-signing the
   Share extension even though the keychain was unlocked (`no-timeout`) and the
   cert was present — because in the *same* build, codesign used the older Apple
   Development key fine but the brand-new Apple Distribution key threw
   `errSecInternalComponent`. The new key's partition list lacked codesign
   access. Fix (one-time per identity): `security set-key-partition-list -S
   apple-tool:,apple:,codesign: -s -k <login-keychain-password>
   ~/Library/Keychains/login.keychain-db` (or Keychain Access → key → Get Info →
   Access Control → "Allow all applications"). The login keychain being unlocked
   is necessary but **not sufficient**; the per-key ACL is the other half.

4. **Ad-Hoc keeps the `/deployit` OTA flow for iOS Production; extension
   profiles are auto-generated.** Ad-Hoc (Apple-Distribution-signed,
   `aps-environment = production`) installs OTA on registered devices via the
   same Tailscale-served manifest as the old Development build — no TestFlight
   needed for test distribution. `-allowProvisioningUpdates` auto-generated the
   ad-hoc profiles for the Share/Shortcuts extensions (only the main app's
   "Lillist Ad Hoc Distribution" profile existed beforehand). Namespace hygiene
   matters: 17 stale `io.Mikey.Lillist` / `io.mikeydotio.Lillist` profiles were
   removed first so automatic signing couldn't pick a wrong-bundle-id match.

## 2026-06-24 — macOS main window adopts the shared iOS single-column UI

The bespoke macOS `NavigationSplitView` (sidebar + list) was retired; the macOS
main window now renders the same iOS surface — `LillistUI.TasksScreen` — in a
narrow, freely-resizable window, with the in-window overlay editor. macOS is now
"the iOS app running on a Mac," diverging only for desktop-only chrome (global
hotkey, menu-bar extra, Dock menu, Preferences scene). Four non-obvious things a
future contributor will otherwise re-learn:

1. **The `iOS/` folder is a misnomer now — several files in it compile on
   macOS.** `TasksScreen`, `iOS/Tasks/*` (TaskTree, FlatTaskRow, TasksSort,
   FilterChip, TaskOutlineRowView, FilterHeader), the toasts (ArchiveToast,
   ReorderFailureToast + StatusChangeFailureToast, ToastChrome), SyncStatusBadge,
   FloatingAddButton, TaskEditorOverlay, and QuickCaptureActionEnvironment had
   their top-level `#if os(iOS)` gates **removed in place** (not moved — the
   package globs its own sources, so a move buys nothing but churn + lost blame).
   Editing any of them with an iOS-only API now breaks the **macOS** build, which
   is warnings-as-errors. The three iOS-only modifiers that had to be
   platform-branched were `.navigationBarTitleDisplayMode(.inline)`, the
   `.topBarLeading`/`.topBarTrailing` toolbar placements (mapped to
   `.navigation`/`.primaryAction` on macOS via computed `ToolbarItemPlacement`
   helpers in `TasksScreen`), and `.textInputAutocapitalization(.never)` in
   `FilterHeader`. Genuinely iOS-only files stay gated: `SizeClassRouter`,
   `DiagnosticsIncludeSheet`, the legacy `QuickCaptureDialog*`,
   `QuickCaptureDiscardToast`, and `Screens/SettingsScreen` (macOS keeps its
   native `Settings` scene).

2. **The macOS editor has a deliberate TWO-PATH split — don't collapse it.**
   In-app opens (row tap / FAB / ⌘N) use the in-window `.taskEditorOverlay` via
   `MacTaskEditorHost`. The system-wide global hotkey (⌃⌥Space) still uses the
   separate `QuickCapturePanelController` **NSPanel**, because it must present
   capture when the main window is closed or another app is frontmost — an
   in-window overlay can't. `MacTaskEditorHost` mirrors the iOS `TaskEditorHost`
   but swaps `PhotosPicker` for `NSOpenPanel` (lifted from the panel controller)
   and omits the discard-undo toast (kept iOS-gated this pass).

3. **Tag + saved-filter management now exists on NEITHER platform — a tracked
   parity gap, not a relocation.** Rename / recolor / delete for tags and
   rename / delete for saved filters lived *only* in the macOS sidebar's context
   menus; iOS never had them. Removing the sidebar reaches parity by subtraction.
   The fix belongs in the **shared** UI (a Settings sub-screen) so both platforms
   gain it together — never a macOS-only Preferences pane (that would re-break
   parity). The underlying store ops and their guards survive untouched
   (`SidebarContextMenuTests`, `PinnedSidebarIntegrationTests` are pure
   LillistCore), so re-exposing it is UI-only. See `HANDOFF.md`.

4. **Window posture: `.contentMinSize`, not `.contentSize`.** `.contentSize`
   locks both window edges to the content's intrinsic size (no free resize);
   `.contentMinSize` honors the content's `minWidth` floor (~360) with no ceiling
   — that's what makes the window narrow-by-default yet freely resizable. The
   single command-menu fallout: the single-column `TasksScreen` exposes no
   row-selection model, so every selection/sidebar-dependent command (New
   Sibling, Advance Status, Mark Closed/Blocked, Open Task, Focus Sidebar/List,
   Show Sidebar) was retired; ⌘N now just flips the quick-capture binding.
   `CommandNotifications.postedByCommands` is consequently empty.

## 2026-06-25 — Reminders import + Quick Capture/Add Task intents: AppIntents won't take free-text inline, and a drain actor must flip its guard before the first await

Three gotchas from wiring the App Intents up and adding the EventKit
Reminders drain (settings page + drain-on-activate, iOS + macOS).

1. **`AppShortcut` phrases only accept `AppEntity`/`AppEnum` parameters
   inline — never a `String`.** Writing `"Add \(\.$taskTitle) to
   \(.applicationName)"` where `taskTitle: String` fails the build at
   `appintentsmetadataprocessor` with *"Invalid parameter type. AppEntity
   and AppEnum are the only allowed types"* — a halting metadata-export
   error, so the extension silently becomes "not usable with AppIntents."
   There is therefore **no way to capture a dictated free-text title inline
   in a Siri phrase.** The supported path is a trigger-only phrase ("Add to
   Lillist", "Lillist task") plus `@Parameter(requestValueDialog:)` on the
   String so Siri asks "What's the task?" and collects the value
   conversationally. Inline capture is reserved for finite/queryable types.
   (`LillistShortcuts.swift`, `AddTaskIntent.swift`.)

2. **A drain `actor` must set its re-entrancy flag synchronously, before the
   first `await`.** `RemindersImporter.drainIfNeeded()` originally checked
   `guard !isDraining` and then set `isDraining = true` *after* three awaits
   (read prefs, check authorization). Because an actor releases isolation at
   every `await`, four concurrent activations all passed the guard before any
   set the flag → parallel drains → duplicate tasks. The stress test
   (`RemindersImporterTests.stressNoDuplicates`, 25× of 4 concurrent drains)
   caught it; a single-call test never would. Fix: `guard !isDraining;
   isDraining = true; defer { … }` with **no await between the check and the
   set**. This is the canonical "clean build ≠ correctness across actor
   boundaries" case the house rules warn about.

3. **Reminders import prefs are device-local on purpose; cross-process
   Quick Capture handoff rides App Group UserDefaults, not
   `NotificationCenter`.** A Reminders `calendarIdentifier` is
   device/account scoped, so the enable flag + selected list live in
   `DevicePreferencesStore` (App Group UserDefaults), **not** the
   CloudKit-synced `AppPreferences` row — which also dodges a
   Development→Production schema redeploy. Separately, the Quick Capture
   App Intent runs in the ShortcutsActions *extension process*, so it can't
   post a `NotificationCenter` signal to the app; it stashes seed text via
   `QuickCaptureHandoff` (App Group UserDefaults + TTL) and the app consumes
   it on activation — in `bootstrap()` for the cold launch (which runs
   *after* the first `didBecomeActive`) and in the `didBecomeActive`
   observer for warm returns. `TaskEditorHost` consumes the seed both via
   `.onChange` and a `.task` (the value may already be set before the view
   appears). macOS gained its first foreground-activation observer
   (`NSApplication.didBecomeActiveNotification`) to drive the same drain;
   the Quick Capture handoff is iOS-only (App Intents aren't embedded on
   macOS).
