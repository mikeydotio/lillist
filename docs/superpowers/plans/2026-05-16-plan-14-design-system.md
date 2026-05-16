# Lillist Plan 14 — Design System & Shared Components

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce the design-token infrastructure currently missing from `LillistUI`, unify the cross-platform sync-status indicator so macOS and iOS encode the same `SyncIndicator → (Color, SF Symbol)` mapping, and lift five duplicated app-target helpers/components into shared `LillistUI` modules. Restore Dynamic Type by replacing every `.font(.system(size: N, weight: …))` callsite with a semantic `LillistTypography` token. This is a **refactor plan** — no user-visible behavior change. Snapshot tests (recorded before each migration) are the regression net.

**Architecture:** Three new modules under `Packages/LillistUI/Sources/LillistUI/Theme/`:
- `Tokens.swift` — namespaced `enum`s for spacing, corner radius, gesture timing, and a `LillistTypography` mapping semantic styles to SwiftUI `Font`s.
- `SyncPalette.swift` — `extension SyncIndicator` exposing `color` and `systemImage`, the single source of truth for sync visuals.
- `Color+Hex.swift` — cross-platform (`#if canImport(AppKit) / UIKit`) hex round-trip, replacing the two duplicated app-target copies.

Promoted shared components under `Packages/LillistUI/Sources/LillistUI/Components/` (`JournalEntryRow.swift`) and a new `Packages/LillistUI/Sources/LillistUI/Settings/` directory (`SortField+DisplayName.swift`, `HourMinuteDate.swift`, `CrashReportSample.swift`). Promoted shared onboarding content under `Packages/LillistUI/Sources/LillistUI/Onboarding/` (`OnboardingContent.swift`, `ICloudRequiredContent.swift`). `RecurrenceEditorViewModel` gains a `humanSummary` computed property so iOS and macOS render identical text.

Migration tasks follow a strict pattern: (1) record a fresh snapshot to pin current visuals, (2) refactor to consume the token / shared component, (3) re-run the snapshot — diff must be **zero**. The goal of every migration in this plan is "no visual change"; any non-zero diff is a bug in the refactor, not a reason to re-record.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing for LillistCore tests, XCTest + `swift-snapshot-testing` for `LillistUI` snapshot tests. No new dependencies.

**Depends on:** Plan 13 (the `SyncStatusBadge` `.inProgress` associated-value pattern-match fix in Task 6 below intersects with Plan 13's badge work — Plan 14 lands second and consumes the Plan 13 fix rather than re-implementing it).

---

## File Structure

```
Lillist/
├── Packages/
│   └── LillistUI/
│       ├── Sources/
│       │   └── LillistUI/
│       │       ├── Theme/
│       │       │   ├── Tokens.swift               (NEW — LillistSpacing/Radius/Timing/Typography + LillistTokens.defaultTagTintHex)
│       │       │   ├── SyncPalette.swift          (NEW — extension SyncIndicator)
│       │       │   ├── Color+Hex.swift            (NEW — cross-platform hex)
│       │       │   ├── StatusGlyph.swift          (unchanged)
│       │       │   └── TagTint.swift              (unchanged — distinct from Color+Hex; see Notes)
│       │       ├── Components/
│       │       │   ├── TaskRowView.swift          (modify — tokens for padding)
│       │       │   ├── SidebarRowView.swift       (modify — tokens for badge padding)
│       │       │   ├── EmptyStateView.swift       (modify — tokens + typography)
│       │       │   ├── StatusIndicatorView.swift  (modify — typography + tokens for frame + timing)
│       │       │   ├── SyncStatusDotView.swift    (modify — consume SyncPalette, drop local switch)
│       │       │   └── JournalEntryRow.swift      (NEW — promoted from both apps)
│       │       ├── iOS/
│       │       │   ├── SyncStatusBadge.swift      (modify — consume SyncPalette; Plan 13 patches the associated-value bug)
│       │       │   └── FloatingAddButton.swift    (modify — typography + tokens for padding/long-press)
│       │       ├── QuickCapture/
│       │       │   └── QuickCaptureView.swift     (modify — typography + radius token)
│       │       ├── Recurrence/
│       │       │   └── RecurrenceEditorViewModel.swift (modify — add humanSummary)
│       │       ├── Settings/                      (NEW directory)
│       │       │   ├── SortField+DisplayName.swift (NEW — promoted)
│       │       │   ├── HourMinuteDate.swift       (NEW — promoted)
│       │       │   └── CrashReportSample.swift    (NEW — promoted)
│       │       └── Onboarding/                    (NEW directory)
│       │           ├── OnboardingContent.swift    (NEW — bullets + permission row)
│       │           └── ICloudRequiredContent.swift (NEW — shared body)
│       └── Tests/
│           └── LillistUITests/
│               ├── Theme/
│               │   └── SyncPaletteTests.swift     (NEW — pure-Swift assertion on palette mapping)
│               ├── Recurrence/
│               │   └── RecurrenceEditorViewModelTests.swift (modify — append humanSummary cases)
│               ├── iOS/
│               │   └── iOSSnapshotTests.swift     (modify — extend for SyncIndicator states light + dark)
│               └── Snapshots/
│                   └── __Snapshots__/             (existing — pinned visuals updated only if intentional)
├── Apps/
│   ├── Lillist-iOS/
│   │   └── Sources/
│   │       ├── Settings/
│   │       │   ├── Color+Hex.swift                (DELETE — replaced by LillistUI/Theme/Color+Hex.swift)
│   │       │   ├── GeneralSection.swift           (modify — consume LillistTokens.defaultTagTintHex + SortField extension)
│   │       │   ├── NotificationsSection.swift     (modify — consume HourMinuteDate)
│   │       │   └── CrashReportingSection.swift    (modify — consume CrashReportSample)
│   │       ├── Detail/
│   │       │   ├── TaskAttachmentsTab.swift       (modify — typography on tile glyph)
│   │       │   ├── TaskJournalTab.swift           (modify — consume promoted JournalEntryRow)
│   │       │   └── TaskDetailView.swift           (modify — show recurrenceViewModel.humanSummary next to toolbar icon)
│   │       └── Onboarding/
│   │           ├── OnboardingScreen.swift         (modify — typography + consume OnboardingContent)
│   │           └── ICloudRequiredScreen.swift     (modify — typography + consume ICloudRequiredContent)
│   └── Lillist-macOS/
│       └── Sources/
│           ├── Support/
│           │   └── Color+Hex.swift                (DELETE — replaced by LillistUI/Theme/Color+Hex.swift)
│           ├── Preferences/
│           │   ├── GeneralPane.swift              (modify — consume LillistTokens.defaultTagTintHex + SortField extension)
│           │   ├── NotificationsPane.swift        (modify — consume HourMinuteDate)
│           │   └── CrashReportingPane.swift       (modify — consume CrashReportSample)
│           ├── Views/Detail/
│           │   ├── JournalStreamView.swift        (modify — consume promoted JournalEntryRow with macOS glyph set)
│           │   └── TaskDetailView.swift           (modify — currentRecurrenceSummary delegates to viewModel.humanSummary)
│           └── Onboarding/
│               ├── OnboardingSheet.swift          (modify — typography + consume OnboardingContent)
│               └── ICloudRequiredView.swift       (modify — typography + consume ICloudRequiredContent)
└── docs/
    └── engineering-notes.md                       (append Plan 14 entry)
```

---

## Notes for the Implementer

**Token replacement is intentionally a no-op visually.** Every spacing/radius/timing constant is mapped 1:1 onto a token whose numeric value equals the prior literal. The snapshot diff after each migration MUST be zero pixels; a non-zero diff means the mapping is wrong. If you find yourself reaching for `--record` after a token migration, stop and re-check the token value.

**`LillistTypography` must use semantic styles**, not hardcoded sizes. The whole reason these need migrating is that `.font(.system(size: 28))` defeats Dynamic Type — the user's accessibility text size has no effect. The replacement is `.title`, `.title2`, `.headline`, `.body`, `.subheadline`, `.caption`, `.largeTitle`, etc. **For onboarding hero icons** (currently 56 and 64pt), the canonical replacement is `.font(.largeTitle.weight(.light))`. This is *not* pixel-identical at the default Dynamic Type size, but `.largeTitle` is the largest semantic style and is the right answer; the snapshot diff for these specific sites is expected to be small but non-zero. Record those updated snapshots intentionally and explicitly note them in the commit body.

**`Color+Hex` exists three times today.** One in `Apps/Lillist-iOS/Sources/Settings/Color+Hex.swift`, one in `Apps/Lillist-macOS/Sources/Support/Color+Hex.swift`, and a hex *parser* in `Packages/LillistUI/Sources/LillistUI/Theme/TagTint.swift:19-30`. The third is *not* duplicate work: `TagTint.init?(hex:)` builds a `TagTint` value with dark-mode desaturation logic, while `Color(hex:)` builds a SwiftUI `Color` directly. They serve distinct purposes and **must remain separate**. The plan does NOT unify them. Document this in `Color+Hex.swift`'s leading comment so future maintainers don't repeat the question.

**`SyncIndicator` is an associated-value enum.** The pattern `if indicator == .inProgress` (currently on `SyncStatusBadge.swift:20`) cannot match associated-value cases via `==`. Plan 13 is fixing this bug as part of its `SyncStatusBadge` work. Plan 14's Task 6 follows Plan 13 in chronological order and consumes the fix rather than re-implementing it. If Plan 13 lands a different shape for the badge (e.g. it extracts a different palette helper), reconcile before starting Task 6.

**Snapshot record / verify flow.** The `swift-snapshot-testing` library auto-records on first run when no reference image exists; subsequent runs compare. To explicitly re-record an existing snapshot, pass `record: .all` to the `assertSnapshot` call temporarily, or set the environment-variable override the library supports. The recording pattern already used in this repo: edit the call to add `record: .all`, run the test, confirm the new image is correct, then revert the `record: .all` argument. Example (from `MacOSScreenTourTests.swift`):
```swift
assertSnapshot(of: host, as: .image(size: CGSize(width: 360, height: 50)), record: .all)
```
Then commit the new image and the same line **without** `record: .all`.

**LillistUI snapshot tests live at** `Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/`. The path is auto-derived from the test class name. Removing tests removes orphan snapshots — `swift test` will report unused-snapshot warnings; clean those up in the same commit.

**Build/test cadence.** Both packages compile with `-Xswiftc -warnings-as-errors` (see `Package.swift` `.treatAllWarnings(as: .error)` settings). Run after every task:
```bash
swift build --package-path Packages/LillistCore
swift build --package-path Packages/LillistUI
swift test  --package-path Packages/LillistUI
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

**Commits.** Conventional-commit prefixes throughout: `refactor:` for token migrations and component lifts, `feat:` for new shared modules, `test:` for snapshot/regression tests, `docs:` for the engineering note.

**SwiftPM source globbing.** Adding a new directory (`Settings/`, `Onboarding/`) under `Packages/LillistUI/Sources/LillistUI/` requires no `Package.swift` change — SwiftPM picks them up automatically. No xcodegen pass needed for LillistUI changes.

---

## Task 1: Create `Theme/Tokens.swift` with spacing, radius, timing, and typography tokens

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift`

- [ ] **Step 1: Author the file**

```swift
import SwiftUI
import Foundation

/// Lillist design tokens, Plan 14.
///
/// All shared visual constants live here. Adding a new spacing /
/// radius / timing value? Put it in the relevant enum and use the
/// token at the callsite rather than a magic number. Typography is
/// **semantic** — `LillistTypography.title2` maps to SwiftUI's
/// `.title2`, which respects Dynamic Type. Never reintroduce
/// `.font(.system(size: N, weight: …))` for app chrome; it freezes
/// the user's accessibility text-size preference.

/// Vertical and horizontal spacing scale. Use these instead of raw
/// CGFloat literals for padding, stack spacing, and frame insets.
public enum LillistSpacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 40
}

/// Corner-radius scale for cards, popovers, and floating surfaces.
public enum LillistRadius {
    public static let s: CGFloat = 6
    public static let m: CGFloat = 12
    public static let l: CGFloat = 18
}

/// Gesture-timing constants. `longPress` is the duration we expect a
/// user to hold before a long-press-bound action fires. Used by
/// `StatusIndicatorView` and `FloatingAddButton`.
public enum LillistTiming {
    public static let longPress: TimeInterval = 0.4
}

/// Semantic typography. Each case maps to a SwiftUI `Font` that
/// participates in Dynamic Type. Use `LillistTypography.title` not
/// `.font(.system(size: 28, weight: .semibold))` so user accessibility
/// settings actually affect chrome text size.
public enum LillistTypography {
    /// `.largeTitle` — onboarding heroes, splash screens.
    public static let largeTitle: Font = .largeTitle
    /// `.title` — major headings.
    public static let title: Font = .title
    /// `.title2` — sheet headers like the onboarding "Welcome to Lillist".
    public static let title2: Font = .title2
    /// `.title3` — secondary headings, sub-section titles.
    public static let title3: Font = .title3
    /// `.headline` — emphasized body, sidebar group labels.
    public static let headline: Font = .headline
    /// `.body` — default text in most form rows.
    public static let body: Font = .body
    /// `.subheadline` — captions under titles, supporting text.
    public static let subheadline: Font = .subheadline
    /// `.caption` — small descriptive labels (tag chips, badges).
    public static let caption: Font = .caption
    /// `.caption2` — date/time stamps in journal rows.
    public static let caption2: Font = .caption2
    /// Status-indicator glyph. Semantic equivalent of a 16pt SF Symbol
    /// rendered at body weight. Used by `StatusIndicatorView`.
    public static let statusGlyph: Font = .body
    /// Quick-capture field text. Semantic equivalent of a slightly-
    /// larger body weight.
    public static let quickCaptureField: Font = .title3
    /// Floating add button "+" glyph.
    public static let floatingAddGlyph: Font = .title.weight(.semibold)
}

/// Reusable string constants used by app-target preferences UI.
public enum LillistTokens {
    /// Default tint hex applied to new tags when the user hasn't
    /// overridden the preference. Previously duplicated as a string
    /// literal in `GeneralSection.swift` (iOS) and `GeneralPane.swift`
    /// (macOS). Plan 14 collapsed those into this single constant.
    public static let defaultTagTintHex: String = "#7F8FA6"
}
```

- [ ] **Step 2: Build and confirm clean**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```

Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift
git commit -m "feat(ui): add LillistUI design tokens (spacing, radius, timing, typography)"
```

---

## Task 2: Create `Theme/SyncPalette.swift` and `Theme/SyncPaletteTests.swift`

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/Theme/SyncPalette.swift`
- Create: `Packages/LillistUI/Tests/LillistUITests/Theme/SyncPaletteTests.swift`

- [ ] **Step 1: Confirm `SyncIndicator` shape**

The enum lives in `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:5-9`:

```swift
public enum SyncIndicator: Sendable, Equatable {
    case idle(lastSync: Date?)
    case inProgress
    case error(message: String, lastSuccess: Date?)
}
```

- [ ] **Step 2: Author `SyncPalette.swift`**

```swift
import SwiftUI

/// Canonical sync-indicator palette. Single source of truth for
/// `SyncIndicator → (Color, SF Symbol)` across macOS (`SyncStatusDotView`)
/// and iOS (`SyncStatusBadge`).
///
/// Plan 14 unified the two per-platform `switch` statements that had
/// drifted: the iOS badge previously returned `.green` for any `.idle`
/// regardless of age, while the macOS dot returned `.yellow` for stale
/// idles and `.green` only for recent ones. The macOS rule was
/// canonical (and matches design Section 8); this extension encodes it
/// for both platforms.
public extension SyncIndicator {
    /// Threshold for "recently synced" in seconds. Idles newer than this
    /// render green; older render yellow.
    static let recencyWindow: TimeInterval = 60

    /// The tint color for this indicator's dot/badge.
    /// - `.idle(nil)` → `.secondary` (never synced)
    /// - `.idle(within recencyWindow)` → `.green`
    /// - `.idle(older)` → `.yellow`
    /// - `.inProgress` → `.blue`
    /// - `.error` → `.red`
    var color: Color {
        switch self {
        case .idle(let last):
            guard let last else { return .secondary }
            return Date().timeIntervalSince(last) < Self.recencyWindow ? .green : .yellow
        case .inProgress:
            return .blue
        case .error:
            return .red
        }
    }

    /// The SF Symbol name for this indicator. Some surfaces (the iOS
    /// badge today) render only a dot; the symbol is available for
    /// surfaces that include a glyph alongside the tint.
    /// - `.idle` → `checkmark`
    /// - `.inProgress` → `arrow.triangle.2.circlepath`
    /// - `.error` → `exclamationmark.triangle.fill`
    var systemImage: String {
        switch self {
        case .idle: return "checkmark"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
```

- [ ] **Step 3: Author the regression test**

```swift
import XCTest
@testable import LillistUI
import SwiftUI

final class SyncPaletteTests: XCTestCase {
    func test_idle_with_nil_lastSync_uses_secondary() {
        XCTAssertEqual(SyncIndicator.idle(lastSync: nil).systemImage, "checkmark")
        // Color equality is intentionally compared via description because
        // SwiftUI's Color does not synthesize Equatable beyond rendering;
        // .secondary stringifies stably.
        XCTAssertEqual(String(describing: SyncIndicator.idle(lastSync: nil).color),
                       String(describing: Color.secondary))
    }

    func test_idle_recent_is_green() {
        let recent = Date().addingTimeInterval(-30)  // within recencyWindow
        XCTAssertEqual(String(describing: SyncIndicator.idle(lastSync: recent).color),
                       String(describing: Color.green))
    }

    func test_idle_stale_is_yellow() {
        let stale = Date().addingTimeInterval(-120)  // outside recencyWindow
        XCTAssertEqual(String(describing: SyncIndicator.idle(lastSync: stale).color),
                       String(describing: Color.yellow))
    }

    func test_inProgress_is_blue_with_arrow_glyph() {
        XCTAssertEqual(String(describing: SyncIndicator.inProgress.color),
                       String(describing: Color.blue))
        XCTAssertEqual(SyncIndicator.inProgress.systemImage, "arrow.triangle.2.circlepath")
    }

    func test_error_is_red_with_warning_glyph() {
        let err = SyncIndicator.error(message: "boom", lastSuccess: nil)
        XCTAssertEqual(String(describing: err.color), String(describing: Color.red))
        XCTAssertEqual(err.systemImage, "exclamationmark.triangle.fill")
    }
}
```

- [ ] **Step 4: Build and run**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
swift test --package-path Packages/LillistUI --filter SyncPaletteTests 2>&1 | tail -10
```

Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Theme/SyncPalette.swift \
        Packages/LillistUI/Tests/LillistUITests/Theme/SyncPaletteTests.swift
git commit -m "feat(ui): add SyncPalette as canonical SyncIndicator color/glyph mapping"
```

---

## Task 3: Migrate LillistUI component callsites to tokens (snapshot-pin first)

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift`
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift`
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift`
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift`
- Modify: `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift`
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift`

- [ ] **Step 1: Pin current visuals via snapshot run**

The existing `MacOSScreenTourTests`, `IOSScreenTourTests`, `TaskListViewSnapshotTests`, `SidebarViewSnapshotTests`, `QuickCaptureViewSnapshotTests`, and `iOSSnapshotTests` already render every component touched by this task. If reference images exist (`Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/` and per-test subfolders), keep them — they are the pre-migration baseline. If you started from a clean checkout, record once now:

```bash
swift test --package-path Packages/LillistUI 2>&1 | tail -10
```

If any snapshot test reports "no reference found, recording…", commit the new images as a separate baseline commit:

```bash
git add Packages/LillistUI/Tests/LillistUITests/**/__Snapshots__
git commit -m "test(ui): record pre-Plan-14 component snapshot baseline"
```

- [ ] **Step 2: Migrate `TaskRowView`**

In `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift`, change lines 53-54:

```diff
-        .padding(.vertical, 4)
-        .padding(.horizontal, 6)
+        .padding(.vertical, LillistSpacing.xs)
+        .padding(.horizontal, LillistSpacing.xs + 2)  // 6pt — between xs (4) and s (8)
```

Rationale for the `xs + 2`: design tokens are not a Procrustean bed. 6pt sits between `xs` (4) and `s` (8); using `xs + 2` documents the intent ("a touch more than xs") without inventing a new token for a single site. If a second callsite wants the same value later, promote it to a real token.

Same file, also migrate the HStack spacing and lookup of the row's inner spacing (`spacing: 8`) and intermediate `spacing: 4`, `spacing: 2`:

```diff
-        HStack(spacing: 8) {
+        HStack(spacing: LillistSpacing.s) {
```
```diff
-            VStack(alignment: .leading, spacing: 2) {
+            VStack(alignment: .leading, spacing: LillistSpacing.xs / 2) {
```
```diff
-                    HStack(spacing: 4) {
+                    HStack(spacing: LillistSpacing.xs) {
```

- [ ] **Step 3: Migrate `SidebarRowView`**

In `Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift`, lines 22-34:

```diff
-        HStack(spacing: 8) {
+        HStack(spacing: LillistSpacing.s) {
             Image(systemName: icon)
                 .foregroundStyle(tint?.resolved(in: scheme).color ?? .accentColor)
                 .frame(width: 18)
             Text(label).lineLimit(1)
             Spacer()
             if let badge, badge > 0 {
                 Text("\(badge)")
                     .font(.caption2)
-                    .padding(.horizontal, 6)
+                    .padding(.horizontal, LillistSpacing.xs + 2)
                     .padding(.vertical, 1)
                     .background(Capsule().fill(.quaternary))
```

- [ ] **Step 4: Migrate `EmptyStateView`**

In `Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift`, lines 14-25:

```diff
-        VStack(spacing: 10) {
+        VStack(spacing: LillistSpacing.s + 2) {
             Image(systemName: systemImage)
-                .font(.system(size: 36, weight: .light))
+                .font(LillistTypography.largeTitle.weight(.light))
                 .foregroundStyle(.tertiary)
-            Text(title).font(.headline)
+            Text(title).font(LillistTypography.headline)
             Text(message)
-                .font(.subheadline)
+                .font(LillistTypography.subheadline)
                 .multilineTextAlignment(.center)
                 .foregroundStyle(.secondary)
                 .frame(maxWidth: 320)
         }
```

The 36pt → `.largeTitle` change is intentional: the previous fixed size defeated Dynamic Type. The new snapshot will differ slightly; this is an accepted regression (see Notes for the Implementer).

- [ ] **Step 5: Migrate `StatusIndicatorView`**

In `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift`, lines 16-29:

```diff
-        Button(action: onClick) {
-            Image(systemName: StatusGlyph.symbol(for: status))
-                .font(.system(size: 16, weight: .regular))
-                .foregroundStyle(status == .closed ? .green : .secondary)
-                .frame(width: 22, height: 22)
-                .contentShape(Rectangle())
-        }
-        .buttonStyle(.plain)
-        .accessibilityLabel(StatusGlyph.accessibilityLabel(for: status))
-        .accessibilityAddTraits(.isButton)
-        .simultaneousGesture(
-            LongPressGesture(minimumDuration: 0.4).onEnded { _ in onLongPress() }
-        )
+        Button(action: onClick) {
+            Image(systemName: StatusGlyph.symbol(for: status))
+                .font(LillistTypography.statusGlyph)
+                .foregroundStyle(status == .closed ? .green : .secondary)
+                .frame(width: LillistSpacing.xl - 2, height: LillistSpacing.xl - 2)
+                .contentShape(Rectangle())
+        }
+        .buttonStyle(.plain)
+        .accessibilityLabel(StatusGlyph.accessibilityLabel(for: status))
+        .accessibilityAddTraits(.isButton)
+        .simultaneousGesture(
+            LongPressGesture(minimumDuration: LillistTiming.longPress).onEnded { _ in onLongPress() }
+        )
```

The `22 = LillistSpacing.xl - 2` mapping (xl=24) keeps the frame numerically identical. The 16pt → `LillistTypography.statusGlyph` (which is `.body`) change *may* render a slightly different glyph size at the default Dynamic Type setting. Re-run the snapshot; if the diff is more than a couple of pixels, fall back to `.body.weight(.regular)` for parity. Document the choice in the commit message.

- [ ] **Step 6: Migrate `QuickCaptureView`**

In `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift`, lines 20-46:

```diff
-            TextField("New task… (#tag, ^date)", text: $text)
-                .textFieldStyle(.plain)
-                .font(.system(size: 18))
-                .onSubmit { onSubmit(parsed) }
+            TextField("New task… (#tag, ^date)", text: $text)
+                .textFieldStyle(.plain)
+                .font(LillistTypography.quickCaptureField)
+                .onSubmit { onSubmit(parsed) }
```
```diff
-        .padding(14)
+        .padding(LillistSpacing.m + 2)
         .frame(width: 520)
-        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
+        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: LillistRadius.m))
```

The 18pt → `.title3` (≈20pt at default Dynamic Type) change is intentional — same Dynamic Type rationale as Step 4. Re-record snapshots if the diff is non-trivial.

- [ ] **Step 7: Migrate `FloatingAddButton` (iOS)**

In `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift`, lines 17-34:

```diff
-        Button(action: onTap) {
-            Image(systemName: "plus")
-                .font(.system(size: 24, weight: .semibold))
-                .frame(width: 56, height: 56)
-                .background(Circle().fill(Color.accentColor))
-                .foregroundStyle(.white)
-                .shadow(radius: 6, y: 3)
-        }
-        .accessibilityLabel("New task")
-        .accessibilityHint("Opens quick capture")
-        .simultaneousGesture(
-            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
-                onLongPress?()
-            }
-        )
-        .padding(.trailing, 20)
-        .padding(.bottom, 20)
+        Button(action: onTap) {
+            Image(systemName: "plus")
+                .font(LillistTypography.floatingAddGlyph)
+                .frame(width: LillistSpacing.xxl + LillistSpacing.l, height: LillistSpacing.xxl + LillistSpacing.l)  // 56pt
+                .background(Circle().fill(Color.accentColor))
+                .foregroundStyle(.white)
+                .shadow(radius: 6, y: 3)
+        }
+        .accessibilityLabel("New task")
+        .accessibilityHint("Opens quick capture")
+        .simultaneousGesture(
+            LongPressGesture(minimumDuration: LillistTiming.longPress).onEnded { _ in
+                onLongPress?()
+            }
+        )
+        .padding(.trailing, LillistSpacing.l + LillistSpacing.xs)  // 20pt
+        .padding(.bottom, LillistSpacing.l + LillistSpacing.xs)
```

Two intentional changes here besides the token swap:
- `minimumDuration: 0.5 → LillistTiming.longPress (0.4)`. The earlier value was a different magic number from the one used in `StatusIndicatorView`. Plan 14 collapses both onto the same token. If 0.4s feels too quick in app QA, add a second token (`longPressFloating: 0.5`) rather than reintroducing a literal.
- Frame size 56pt is expressed as `xxl + l = 40 + 16`. An alternative is to add a new `LillistSpacing.huge = 56` token if the value recurs; for one site, the additive expression is clearer.

- [ ] **Step 8: Re-run all snapshot tests**

```bash
swift test --package-path Packages/LillistUI 2>&1 | tail -20
```

Expected outcomes:
- Pure-spacing migrations (TaskRowView, SidebarRowView, StatusIndicatorView frame, FloatingAddButton padding) — zero pixel diff.
- Dynamic-Type-restoring migrations (EmptyStateView 36pt, QuickCaptureView 18pt, FloatingAddButton 24pt) — small pixel diff is acceptable. If a snapshot reports failure, inspect the diff image. If the new rendering is visually equivalent (just a different DPI/sub-pixel rasterization), re-record with `record: .all` per Notes, then revert the flag.

- [ ] **Step 9: Build both targets**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 10: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift \
        Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift \
        Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift \
        Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift \
        Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift \
        Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift \
        Packages/LillistUI/Tests/LillistUITests/**/__Snapshots__
git commit -m "refactor(ui): migrate LillistUI component spacing/typography to design tokens

Replaces hardcoded CGFloat / Font literals with LillistSpacing,
LillistRadius, LillistTiming, and LillistTypography tokens. Dynamic-
Type-restoring sites (EmptyStateView icon, QuickCaptureView field,
FloatingAddButton glyph) intentionally swap to semantic font styles
and re-record snapshots."
```

---

## Task 4: Migrate app-target callsites to `LillistTypography`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift`
- Modify: `Apps/Lillist-iOS/Sources/Onboarding/ICloudRequiredScreen.swift`
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskAttachmentsTab.swift`
- Modify: `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift`
- Modify: `Apps/Lillist-macOS/Sources/Onboarding/ICloudRequiredView.swift`

- [ ] **Step 1: Audit all remaining hardcoded font sizes in app targets**

```bash
grep -rn 'font(.system(size:' Apps/ 2>&1
```

Expected (per design review): the five sites in the file list above. If grep returns additional sites, fold them into this task before committing.

- [ ] **Step 2: Migrate `OnboardingScreen.swift` (iOS)**

In `Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift`, lines 40-46:

```diff
     private var header: some View {
         VStack(spacing: 8) {
             Image(systemName: "checklist")
-                .font(.system(size: 64, weight: .light))
+                .font(LillistTypography.largeTitle.weight(.light))
                 .foregroundStyle(.tint)
             Text("Welcome to Lillist")
                 .font(.largeTitle.bold())
```

Add `import LillistUI` at the top if not already present.

- [ ] **Step 3: Migrate `ICloudRequiredScreen.swift` (iOS)**

In `Apps/Lillist-iOS/Sources/Onboarding/ICloudRequiredScreen.swift`, lines 13-17:

```diff
         VStack(spacing: 20) {
             Image(systemName: "icloud.slash")
-                .font(.system(size: 64, weight: .light))
+                .font(LillistTypography.largeTitle.weight(.light))
                 .foregroundStyle(.red)
             Text("iCloud is required")
                 .font(.title.bold())
```

Add `import LillistUI`.

- [ ] **Step 4: Migrate `TaskAttachmentsTab.swift` (iOS)**

In `Apps/Lillist-iOS/Sources/Detail/TaskAttachmentsTab.swift`, lines 43-52:

```diff
     var body: some View {
         VStack(spacing: 6) {
             Image(systemName: glyph)
-                .font(.system(size: 32))
-                .frame(width: 96, height: 96)
-                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.15)))
+                .font(LillistTypography.title)
+                .frame(width: 96, height: 96)
+                .background(RoundedRectangle(cornerRadius: LillistRadius.m).fill(Color.secondary.opacity(0.15)))
             Text(attachment.filename)
-                .font(.caption)
+                .font(LillistTypography.caption)
                 .lineLimit(1)
                 .truncationMode(.middle)
         }
```

The 96pt tile is hardcoded with `@ScaledMetric` already in TaskAttachmentsTab (per the design-review note); leave the frame value alone and replace only the font and corner radius. If the file uses raw `96` rather than `@ScaledMetric`, leave it — Plan 14 is about typography and tokenized constants, not about converting fixed frames to scaled frames. (If the design review is wrong about `@ScaledMetric`, that's a separate cleanup task.)

- [ ] **Step 5: Migrate `OnboardingSheet.swift` (macOS)**

In `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift`, lines 51-63:

```diff
     private var header: some View {
         VStack(spacing: 8) {
             Image(systemName: "checklist")
-                .font(.system(size: 56, weight: .light))
+                .font(LillistTypography.largeTitle.weight(.light))
                 .foregroundStyle(.tint)
             Text("Welcome to Lillist")
-                .font(.system(size: 28, weight: .semibold))
+                .font(LillistTypography.title2.weight(.semibold))
             Text("A pure-nesting task manager. Everything is a task.")
                 .font(.title3)
                 .foregroundStyle(.secondary)
                 .multilineTextAlignment(.center)
         }
     }
```

Add `import LillistUI`.

- [ ] **Step 6: Migrate `ICloudRequiredView.swift` (macOS)**

In `Apps/Lillist-macOS/Sources/Onboarding/ICloudRequiredView.swift`, lines 17-24:

```diff
         VStack(spacing: 20) {
             Image(systemName: "icloud.slash")
-                .font(.system(size: 56, weight: .light))
+                .font(LillistTypography.largeTitle.weight(.light))
                 .foregroundStyle(.red)
             Text("iCloud is required")
-                .font(.title)
-                .bold()
+                .font(LillistTypography.title.weight(.bold))
```

Add `import LillistUI`.

- [ ] **Step 7: Re-grep to confirm zero remaining hits**

```bash
grep -rn 'font(.system(size:' Apps/ 2>&1
```

Expected: no output.

- [ ] **Step 8: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 9: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift \
        Apps/Lillist-iOS/Sources/Onboarding/ICloudRequiredScreen.swift \
        Apps/Lillist-iOS/Sources/Detail/TaskAttachmentsTab.swift \
        Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift \
        Apps/Lillist-macOS/Sources/Onboarding/ICloudRequiredView.swift
git commit -m "refactor(apps): migrate hardcoded font sizes to LillistTypography

Onboarding heroes and attachment tile glyphs lose their .system(size:)
overrides and gain Dynamic-Type-respecting semantic styles. Numeric
font sizes are no longer permitted in app chrome — see CLAUDE.md."
```

---

## Task 5: Refactor `SyncStatusDotView` to consume `SyncPalette`

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift`

- [ ] **Step 1: Snapshot the current rendering**

`SyncStatusDotView` is rendered through `MacOSScreenTourTests` — verify a baseline exists:

```bash
swift test --package-path Packages/LillistUI --filter MacOSScreenTour 2>&1 | tail -10
```

Expected: all PASS, snapshot images present under `Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__/MacOSScreenTourTests/`.

- [ ] **Step 2: Replace the local `color` switch with `indicator.color`**

In `Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift`, lines 12-44:

```diff
     public var body: some View {
         Button { showPopover.toggle() } label: {
             Circle()
-                .fill(color)
-                .frame(width: 8, height: 8)
+                .fill(indicator.color)
+                .frame(width: LillistSpacing.s, height: LillistSpacing.s)
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
-            .padding(12)
+            .padding(LillistSpacing.m)
             .frame(width: 240)
         }
     }
-
-    private var color: Color {
-        switch indicator {
-        case .idle(let last):
-            guard let last else { return .yellow }
-            return Date().timeIntervalSince(last) < 60 ? .green : .yellow
-        case .inProgress:
-            return .blue
-        case .error:
-            return .red
-        }
-    }

     private var label: String {
```

Note one semantic change: `.idle(nil)` previously rendered `.yellow` ("never synced is stale"). The new `SyncPalette` renders `.idle(nil)` as `.secondary` ("never synced is informational, not warning"). This matches the macOS design more literally and is the canonical mapping going forward; document the choice in the commit body.

- [ ] **Step 3: Re-run snapshots**

```bash
swift test --package-path Packages/LillistUI --filter MacOSScreenTour 2>&1 | tail -10
```

If `MacOSScreenTourTests` renders a `SyncStatusDotView` with `.idle(nil)`, the snapshot will differ. Inspect the diff image to confirm the only change is dot color (`.yellow → .secondary`). Re-record:

```swift
// Temporarily in the offending test:
assertSnapshot(of: host, as: .image(size: …), record: .all)
```

Then revert the `record: .all`.

- [ ] **Step 4: Build**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift \
        Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__/MacOSScreenTourTests
git commit -m "refactor(ui): SyncStatusDotView consumes shared SyncPalette

Drops the local color switch in favor of SyncIndicator.color from the
canonical palette. Snapshot updated for the .idle(nil) → .secondary
mapping change (previously rendered .yellow on macOS only)."
```

---

## Task 6: Refactor `SyncStatusBadge` (iOS) to consume `SyncPalette`

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift`

**Prerequisite:** Plan 13 has landed and fixed the `if indicator == .inProgress` associated-value pattern-match bug. If Plan 13 is not on `main` yet, pause and complete it first — Task 6 builds on that fix.

> **Plan 13 fallout (2026-05-16):** Plan 13 Task 1 changed the `.inProgress` color from `.clear` to `.blue` and switched the overlay test to `if case .inProgress = indicator`. Plan 13 Task 8 then wrapped the badge in an outer `.frame(width: 44, height: 44)` + `.contentShape(Rectangle())` + `.accessibilityAddTraits(.isStaticText)` to meet HIG's 44pt tap-target floor. Plan 14 Task 6's `SyncPalette` already returns `.blue` for `.inProgress`, so the migration is just a delete-the-local-switch operation; the 44pt outer frame and the `.isStaticText` trait must be preserved through the migration.

- [ ] **Step 1: Verify Plan 13's fix is in place**

```bash
grep -n "case .inProgress = indicator\|indicator == .inProgress\|frame(width: 44, height: 44)\|isStaticText" Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift
```

Expected: the file contains `if case .inProgress = indicator` (Plan 13's fix), the outer `.frame(width: 44, height: 44)`, and `.accessibilityAddTraits(.isStaticText)`. If `if indicator == .inProgress` is still present, STOP and merge Plan 13 first.

- [ ] **Step 2: Snapshot baseline**

The existing `iOSSnapshotTests.test_syncStatusBadge_idle` and `test_syncStatusBadge_error` provide baseline images.

```bash
swift test --package-path Packages/LillistUI --filter iOSSnapshotTests 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 3: Replace local `color` switch with `indicator.color`**

In `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift`, modify the `body` and delete the local `color` switch:

```diff
     public var body: some View {
         Circle()
-            .fill(color)
-            .frame(width: 10, height: 10)
+            .fill(indicator.color)
+            .frame(width: LillistSpacing.s + 2, height: LillistSpacing.s + 2)
             .overlay(
                 Group {
                     if case .inProgress = indicator {
                         ProgressView()
                             .scaleEffect(0.5)
                     }
                 }
             )
+            // Plan 13 fallout: keep the outer 44pt hit area + content
+            // shape + .isStaticText trait introduced by Plan 13 Task 8.
+            .frame(width: 44, height: 44)
+            .contentShape(Rectangle())
             .accessibilityLabel(label)
+            .accessibilityAddTraits(.isStaticText)
     }
-
-    private var color: Color {
-        switch indicator {
-        case .idle: return .green
-        case .inProgress: return .blue
-        case .error: return .red
-        }
-    }

     private var label: String {
```

Semantic changes worth calling out in the commit body:
- `.idle(nil)` was `.green` on iOS (treated as "synced fine"); now `.secondary` ("never synced"). This is more honest about the actual state.
- `.idle(stale)` was `.green` on iOS; now `.yellow`. This matches macOS and the design Section 8 spec.
- `.inProgress` was already `.blue` after Plan 13; the `SyncPalette` mapping matches — no visual change for this state.

If the `.idle(stale)` yellow is undesired (i.e. the design explicitly wants green for any idle on iOS), document the deviation in the commit body rather than re-introducing a local override; the cross-platform palette is the source of truth going forward.

- [ ] **Step 4: Re-record snapshots if the visual diff is real**

```bash
swift test --package-path Packages/LillistUI --filter iOSSnapshotTests 2>&1 | tail -10
```

Inspect any failing snapshots; if the color change is the only delta and is intentional, re-record per Notes.

- [ ] **Step 5: Add new snapshot tests for the third state and dark mode**

Extend `Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift` (after `test_syncStatusBadge_error`):

```swift
    @MainActor
    func test_syncStatusBadge_inProgress() {
        let view = SyncStatusBadge(indicator: .inProgress)
            .padding()
            .background(Color(.systemBackground))
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 60, height: 40)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }

    @MainActor
    func test_syncStatusBadge_idle_dark() {
        let view = SyncStatusBadge(indicator: .idle(lastSync: Date(timeIntervalSince1970: 0)))
            .padding()
            .background(Color(.systemBackground))
            .environment(\.colorScheme, .dark)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 60, height: 40)
        host.overrideUserInterfaceStyle = .dark
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }

    @MainActor
    func test_syncStatusBadge_error_dark() {
        let view = SyncStatusBadge(
            indicator: .error(message: "Network unavailable", lastSuccess: nil)
        )
        .padding()
        .background(Color(.systemBackground))
        .environment(\.colorScheme, .dark)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 60, height: 40)
        host.overrideUserInterfaceStyle = .dark
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }

    @MainActor
    func test_syncStatusBadge_inProgress_dark() {
        let view = SyncStatusBadge(indicator: .inProgress)
            .padding()
            .background(Color(.systemBackground))
            .environment(\.colorScheme, .dark)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 60, height: 40)
        host.overrideUserInterfaceStyle = .dark
        assertSnapshot(of: host, as: .image(size: CGSize(width: 60, height: 40)))
    }
```

First run records the new snapshots; commit them with the test file.

- [ ] **Step 6: Run iOS snapshot suite**

```bash
swift test --package-path Packages/LillistUI --filter iOSSnapshotTests 2>&1 | tail -15
```

Expected: all PASS (with new snapshots recorded on first run).

- [ ] **Step 7: Build iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 8: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/iOSSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/iOS/__Snapshots__
git commit -m "refactor(ui-iOS): SyncStatusBadge consumes shared SyncPalette

Replaces the iOS-local color switch with SyncPalette. Snapshots now
cover all three SyncIndicator states in both light and dark mode."
```

---

## Task 7: Create `Theme/Color+Hex.swift` (cross-platform) and delete app-target copies

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/Theme/Color+Hex.swift`
- Delete: `Apps/Lillist-iOS/Sources/Settings/Color+Hex.swift`
- Delete: `Apps/Lillist-macOS/Sources/Support/Color+Hex.swift`

- [ ] **Step 1: Author the cross-platform extension**

```swift
import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Cross-platform hex round-trip for SwiftUI `Color`. Used by
/// Preferences UI to round-trip the `defaultTagTintHex` preference
/// string.
///
/// **Distinct from `TagTint.init?(hex:)`** (`Packages/LillistUI/Sources/
/// LillistUI/Theme/TagTint.swift:19-30`), which constructs a `TagTint`
/// value with dark-mode desaturation logic for tag chips. `Color(hex:)`
/// here produces a raw SwiftUI `Color` for use anywhere a `Color` is
/// expected (notably `ColorPicker` bindings in Preferences). Both forms
/// are needed; do not collapse them.
public extension Color {
    /// Parse a 6-digit hex RGB string into a `Color`. Accepts an
    /// optional leading `#`. Three-digit shorthand (`#FA0`) is expanded.
    /// Returns nil if the string can't be parsed.
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self = Color(
            red:   Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >>  8) & 0xFF) / 255.0,
            blue:  Double( v        & 0xFF) / 255.0
        )
    }

    /// Render a `Color` as a 6-digit hex RGB string (with leading `#`).
    /// Returns nil if the color can't be reduced to sRGB components.
    func toHex() -> String? {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB)
        guard let ns else { return nil }
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
        #elseif canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
        #else
        return nil
        #endif
    }
}
```

- [ ] **Step 2: Delete the iOS and macOS copies**

```bash
git rm Apps/Lillist-iOS/Sources/Settings/Color+Hex.swift
git rm Apps/Lillist-macOS/Sources/Support/Color+Hex.swift
```

- [ ] **Step 3: Verify all consumers import LillistUI**

```bash
grep -rn "Color(hex:\|toHex()" Apps/ 2>&1
```

Expected callsites (all should also have `import LillistUI` in their file):
- `Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift:18-19`
- `Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift:52-55`

If either file lacks `import LillistUI`, add it.

- [ ] **Step 4: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: both succeed. If xcodegen needs a regen for the deletions to be picked up:

```bash
cd Apps && xcodegen generate --spec project.yml --project . && cd ..
```

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Theme/Color+Hex.swift \
        Apps/Lillist-iOS.xcodeproj/project.pbxproj \
        Apps/Lillist-macOS.xcodeproj/project.pbxproj
# git rm of the two app-target Color+Hex.swift files is already staged
git commit -m "refactor(ui): lift Color+Hex into LillistUI, delete duplicates from app targets

The iOS and macOS app targets each carried a near-identical hex
round-trip extension. Plan 14 consolidates them into a single
cross-platform LillistUI extension (using #if canImport for the
NSColor / UIColor split). Distinct from TagTint(hex:), which serves
a different purpose — see comment in the new file."
```

---

## Task 8: Migrate Preferences callsites to `LillistTokens.defaultTagTintHex`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift`

- [ ] **Step 1: Migrate `GeneralSection.swift` (iOS)**

In `Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift`, line 19:

```diff
     private var tintBinding: Binding<Color> {
         Binding(
             get: { Color(hex: prefs.defaultTagTintHex) ?? .gray },
-            set: { prefs.defaultTagTintHex = $0.toHex() ?? "#7F8FA6" }
+            set: { prefs.defaultTagTintHex = $0.toHex() ?? LillistTokens.defaultTagTintHex }
         )
     }
```

- [ ] **Step 2: Migrate `GeneralPane.swift` (macOS)**

In `Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift`, line 55:

```diff
     private var tagTintBinding: Binding<Color> {
         Binding(
             get: { Color(hex: prefs?.defaultTagTintHex) ?? .gray },
             set: { newColor in
                 guard prefs != nil else { return }
-                prefs!.defaultTagTintHex = newColor.toHex() ?? "#7F8FA6"
+                prefs!.defaultTagTintHex = newColor.toHex() ?? LillistTokens.defaultTagTintHex
             }
         )
     }
```

- [ ] **Step 3: Verify both files import LillistUI**

```bash
grep -n "import LillistUI" Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift \
                          Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift
```

If either is missing the import, add it after `import SwiftUI`.

- [ ] **Step 4: grep for any remaining `"#7F8FA6"` literals**

```bash
grep -rn '#7F8FA6' Apps/ Packages/ 2>&1
```

Expected: a single hit in `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift` (the token definition). No others.

- [ ] **Step 5: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift \
        Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift
git commit -m "refactor(apps): consume LillistTokens.defaultTagTintHex in Preferences"
```

---

## Task 9: Promote `JournalEntryRow` into `LillistUI/Components/`

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/Components/JournalEntryRow.swift`
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift`
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskJournalTab.swift`

- [ ] **Step 1: Author the shared `JournalEntryRow`**

The macOS implementation has richer glyphs (`text.bubble` / `arrow.triangle.2.circlepath` / `paperclip` / `arrow.uturn.right.circle`); iOS shows no glyphs at all. The canonical choice is the macOS set — adopt for both. Extract the glyph mapping into a `JournalGlyph` enum analogous to `StatusGlyph`.

```swift
import SwiftUI
import LillistCore

/// Shared journal-entry row. Renders a `JournalStore.JournalRecord`
/// with a leading glyph derived from `entry.kind`, a timestamp, and
/// the entry body (Markdown-rendered).
///
/// Plan 14 lifted this from the macOS `JournalStreamView` (which had
/// the canonical glyph set) and the iOS `TaskJournalTab` (which had
/// no glyphs at all). Both apps now consume this view.
public struct JournalEntryRow: View {
    public var entry: JournalStore.JournalRecord

    public init(entry: JournalStore.JournalRecord) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.xs / 2) {
            HStack(spacing: LillistSpacing.xs) {
                Image(systemName: JournalGlyph.symbol(for: entry.kind))
                    .foregroundStyle(.secondary)
                Text(entry.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    .font(LillistTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Text(LocalizedStringKey(entry.body))
                .textSelection(.enabled)
        }
        .padding(.vertical, LillistSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// SF Symbol mapping for `JournalStore.JournalKind`. Parallel to
/// `StatusGlyph` in shape — keeps glyph choices testable and replaces
/// the inline `switch` previously duplicated in two views.
public enum JournalGlyph {
    public static func symbol(for kind: JournalStore.JournalKind) -> String {
        switch kind {
        case .note: return "text.bubble"
        case .statusChange: return "arrow.triangle.2.circlepath"
        case .attachment: return "paperclip"
        case .createdFollowUp: return "arrow.uturn.right.circle"
        }
    }
}
```

(If `JournalStore.JournalKind` is namespaced differently in `LillistCore`, adjust accordingly. The values must match the four cases used in the macOS `JournalStreamView.swift:58-65` inline switch.)

- [ ] **Step 2: Update macOS `JournalStreamView.swift` to consume the shared row**

In `Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift`, delete lines 43-66 (the private `JournalEntryRow` struct). The outer `ForEach` (line 21-23) already calls `JournalEntryRow(entry: entry)`; SwiftUI will now resolve the symbol from the LillistUI module. Add `import LillistUI` at the top if not already present.

- [ ] **Step 3: Update iOS `TaskJournalTab.swift` to consume the shared row**

In `Apps/Lillist-iOS/Sources/Detail/TaskJournalTab.swift`, delete lines 46-62 (the private `JournalEntryRow` struct). The outer `List` (line 15-17) already calls `JournalEntryRow(entry: entry)`. Add `import LillistUI`.

- [ ] **Step 4: Verify visual parity**

The iOS rendering now gains glyphs it didn't have before. This is an intentional regression of the existing iOS behavior toward the canonical macOS shape. Run snapshot tests if any cover the journal tab; if no snapshot exists, document the visual change in the commit body.

```bash
swift test --package-path Packages/LillistUI 2>&1 | tail -10
```

- [ ] **Step 5: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/JournalEntryRow.swift \
        Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift \
        Apps/Lillist-iOS/Sources/Detail/TaskJournalTab.swift
git commit -m "refactor: promote JournalEntryRow into LillistUI, unify glyph set across platforms

Both apps duplicated this row in slightly-divergent shapes — macOS had
SF Symbols for each JournalKind, iOS rendered none. Plan 14 lifts the
macOS shape into a shared LillistUI component (with a JournalGlyph
enum analogous to StatusGlyph) and consumes from both. iOS now gains
the kind-glyphs."
```

---

## Task 10: Promote settings-shared helpers (`SortField.displayName`, `HourMinuteDate`, `CrashReportSample`)

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/Settings/SortField+DisplayName.swift`
- Create: `Packages/LillistUI/Sources/LillistUI/Settings/HourMinuteDate.swift`
- Create: `Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift`
- Modify: `Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift`
- Modify: `Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift`
- Modify: `Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift`

- [ ] **Step 1: Author `SortField+DisplayName.swift`**

```swift
import LillistCore

/// Display labels for `SortField` cases used in Preferences. Previously
/// duplicated verbatim in iOS `GeneralSection.swift` and macOS
/// `GeneralPane.swift` as `private extension SortField`. Plan 14 lifts
/// the extension into LillistUI and drops `private` to make it visible
/// to both app targets.
public extension SortField {
    var displayName: String {
        switch self {
        case .manualPosition: return "Manual"
        case .start: return "Start date"
        case .deadline: return "Deadline"
        case .title: return "Title"
        case .createdAt: return "Created"
        case .modifiedAt: return "Modified"
        case .closedAt: return "Closed"
        case .status: return "Status"
        }
    }
}
```

- [ ] **Step 2: Author `HourMinuteDate.swift`**

```swift
import Foundation

/// Build a `Date` whose date components match today and whose hour /
/// minute match the supplied values. Used by Preferences DatePickers
/// that bind to (Int16 hour, Int16 minute) prefs columns.
///
/// Previously duplicated verbatim in iOS `NotificationsSection.swift`
/// and macOS `NotificationsPane.swift`. Plan 14 lifts to LillistUI.
public enum HourMinuteDate {
    public static func date(hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
        var c = calendar.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour
        c.minute = minute
        return calendar.date(from: c) ?? Date()
    }
}
```

- [ ] **Step 3: Author `CrashReportSample.swift`**

The macOS and iOS samples diverge in their footer line: macOS shows the explicit `mailto:` recipient and method, iOS abbreviates to "Sent via: Mail". Pick a single canonical form — the macOS form is more informative and aligns with Plan 9's privacy disclosure goal. Parametrize on `recipient` and `methodSuffix` so callers can vary only the platform-specific bits.

```swift
import Foundation

/// Sample-preview text shown in the Preferences "View what would be
/// sent" disclosure. Plan 9 ships the post-crash prompt; Plan 14
/// consolidates the two app-target preview builders that had drifted.
public enum CrashReportSample {
    public struct Environment: Sendable, Equatable {
        public var buildVersion: String
        public var osVersion: String
        public var deviceModel: String
        public var recipient: String
        public var methodSuffix: String

        public init(
            buildVersion: String,
            osVersion: String,
            deviceModel: String,
            recipient: String,
            methodSuffix: String
        ) {
            self.buildVersion = buildVersion
            self.osVersion = osVersion
            self.deviceModel = deviceModel
            self.recipient = recipient
            self.methodSuffix = methodSuffix
        }
    }

    /// Render the multi-line preview string. macOS callers pass
    /// `methodSuffix: "macOS Mail.app draft via mailto: — you choose
    /// whether to send."`; iOS uses `"Mail (you choose whether to
    /// send.)"`.
    public static func preview(_ env: Environment) -> String {
        """
        Build: \(env.buildVersion)
        OS: \(env.osVersion)
        Device: \(env.deviceModel)
        Breadcrumbs:
          (Anonymized verbs from your last ~50 mutations.)
        Logs:
          (System logs from the last ~30 seconds of the crashed run.)
        Sent to: \(env.recipient)
        Method: \(env.methodSuffix)
        """
    }
}
```

- [ ] **Step 4: Update `GeneralSection.swift` (iOS) — delete the private `displayName` extension**

In `Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift`, delete lines 24-37 (the `private extension SortField`). The remaining `ForEach` loop on line 10 (`Text($0.displayName)`) now resolves the property from the LillistUI extension. Confirm `import LillistUI` is present.

- [ ] **Step 5: Update `GeneralPane.swift` (macOS) — delete the private `displayName` extension**

In `Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift`, delete lines 69-82 (the `private extension SortField`). Confirm `import LillistUI`.

- [ ] **Step 6: Update `NotificationsSection.swift` (iOS) — consume `HourMinuteDate.date(hour:minute:)`**

In `Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift`, delete the private `date(_:_:)` method (lines 78-83) and update both `Binding.get` blocks (lines 58, 69):

```diff
-            get: { date(Int(prefs.defaultAllDayHour), Int(prefs.defaultAllDayMinute)) },
+            get: { HourMinuteDate.date(hour: Int(prefs.defaultAllDayHour), minute: Int(prefs.defaultAllDayMinute)) },
```
```diff
-            get: { date(Int(prefs.morningSummaryHour), Int(prefs.morningSummaryMinute)) },
+            get: { HourMinuteDate.date(hour: Int(prefs.morningSummaryHour), minute: Int(prefs.morningSummaryMinute)) },
```

- [ ] **Step 7: Update `NotificationsPane.swift` (macOS) — consume `HourMinuteDate.date(hour:minute:)`**

In `Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift`, delete the private `date(hour:minute:)` method (lines 109-114) and update both `Binding.get` blocks (lines 89, 100) to call `HourMinuteDate.date(hour:minute:)` instead.

- [ ] **Step 8: Update `CrashReportingSection.swift` (iOS) — consume `CrashReportSample.preview(...)`**

In `Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift`, replace the `samplePreview` computed property (lines 30-41) with:

```swift
    private var samplePreview: String {
        CrashReportSample.preview(.init(
            buildVersion: environment.buildVersion,
            osVersion: environment.osVersion,
            deviceModel: environment.deviceModel,
            recipient: "mikeyward@gmail.com",
            methodSuffix: "Mail (you choose whether to send)."
        ))
    }
```

- [ ] **Step 9: Update `CrashReportingPane.swift` (macOS) — consume `CrashReportSample.preview(...)`**

In `Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift`, replace the `samplePreview` computed property (lines 54-66) with:

```swift
    private var samplePreview: String {
        CrashReportSample.preview(.init(
            buildVersion: environment.buildVersion,
            osVersion: environment.osVersion,
            deviceModel: environment.deviceModel,
            recipient: "mikeyward@gmail.com",
            methodSuffix: "macOS Mail.app draft via mailto: — you choose whether to send."
        ))
    }
```

- [ ] **Step 10: Verify no orphan duplication**

```bash
grep -rn "case .manualPosition: return" Apps/ Packages/ 2>&1
grep -rn "private func date(hour:\|private func date(_:" Apps/ 2>&1
grep -rn 'Sent via: Mail\|macOS Mail.app draft' Apps/ Packages/ 2>&1
```

Each grep should return either zero hits or only the canonical LillistUI definition. App-target duplicates should be gone.

- [ ] **Step 11: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 12: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Settings/SortField+DisplayName.swift \
        Packages/LillistUI/Sources/LillistUI/Settings/HourMinuteDate.swift \
        Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift \
        Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift \
        Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift \
        Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift \
        Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift \
        Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift \
        Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift
git commit -m "refactor: promote SortField.displayName, HourMinuteDate, CrashReportSample into LillistUI

Three helpers were duplicated near-verbatim across iOS and macOS
Preferences screens. Plan 14 lifts each into LillistUI/Settings/ and
deletes the app-target copies. CrashReportSample takes the macOS
form's more-informative footer as canonical."
```

---

## Task 11: Promote `OnboardingContent` into `LillistUI/Onboarding/`

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift`
- Modify: `Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift`
- Modify: `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift`

- [ ] **Step 1: Identify the shared shape**

Both files have:
1. A `header` (icon + title + tagline) — already migrated to typography in Task 4. Keep per-platform because text and icon vary slightly.
2. A `bullets` section — three rows, each `bullet(icon: String, text: String)`. **Shared candidate.**
3. A `permissionStatusRow` switching on `NotificationPermissions.AuthorizationStatus` — shared in shape but each platform deep-links into Settings via a different URL (`UIApplication.openSettingsURLString` vs `x-apple.systempreferences:com.apple.preference.notifications`). **Shared candidate** with an injected "open Settings" action closure.
4. An action bar (iOS `.bordered` Buttons stacked vertically; macOS `HStack` with `.borderedProminent`) — keep per-platform.

- [ ] **Step 2: Author `OnboardingContent.swift`**

```swift
import SwiftUI
import LillistCore

/// Shared onboarding body content used by iOS (`OnboardingScreen`) and
/// macOS (`OnboardingSheet`). Renders the three feature bullets and a
/// permission-status row driven by the current
/// `NotificationPermissions.AuthorizationStatus`.
///
/// Per-platform pieces (the header icon size/text, the action bar
/// shape, the deep-link URL to the Settings/System Preferences screen)
/// remain in the app-target wrappers — they diverge enough that
/// sharing them would introduce more conditionals than it removes.
public struct OnboardingContent: View {
    public struct Bullet: Identifiable, Equatable {
        public let id = UUID()
        public let icon: String
        public let text: String
        public init(icon: String, text: String) {
            self.icon = icon
            self.text = text
        }
    }

    public var bullets: [Bullet]
    public var permissionStatus: NotificationPermissions.AuthorizationStatus
    public var onOpenSettings: () -> Void

    public init(
        bullets: [Bullet],
        permissionStatus: NotificationPermissions.AuthorizationStatus,
        onOpenSettings: @escaping () -> Void
    ) {
        self.bullets = bullets
        self.permissionStatus = permissionStatus
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.l) {
            ForEach(bullets) { b in
                bulletRow(icon: b.icon, text: b.text)
            }
            permissionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: LillistSpacing.m) {
            Image(systemName: icon)
                .font(LillistTypography.title3)
                .frame(width: LillistSpacing.xl + LillistSpacing.xs)
                .foregroundStyle(.tint)
            Text(text)
                .font(LillistTypography.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var permissionRow: some View {
        switch permissionStatus {
        case .authorized:
            Label("Notifications enabled.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            VStack(alignment: .leading, spacing: LillistSpacing.s) {
                Label("Notifications denied.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Open Settings", action: onOpenSettings)
            }
        case .notDetermined:
            EmptyView()
        }
    }
}
```

- [ ] **Step 3: Update `OnboardingScreen.swift` (iOS) to consume**

Replace the inline `bullets` and `permissionStatusRow` computed properties (lines 54-93) with a single call to `OnboardingContent` from the body:

```diff
     var body: some View {
         VStack(spacing: 0) {
             ScrollView {
                 VStack(spacing: 28) {
                     header
-                    bullets
-                    permissionStatusRow
+                    OnboardingContent(
+                        bullets: Self.iOSBullets,
+                        permissionStatus: permissionStatus,
+                        onOpenSettings: {
+                            if let url = URL(string: UIApplication.openSettingsURLString) {
+                                UIApplication.shared.open(url)
+                            }
+                        }
+                    )
                 }
                 .padding(24)
             }
             actionBar
         }
         .task { permissionStatus = await notificationPermissions.currentStatus() }
     }
-
-    private var bullets: some View { … }                        // delete
-    private func bullet(icon:text:) -> some View { … }          // delete
-    @ViewBuilder private var permissionStatusRow: some View { … } // delete
```

Add at the bottom of the struct:

```swift
    private static let iOSBullets: [OnboardingContent.Bullet] = [
        .init(icon: "icloud", text: "iCloud sync is required. Your data lives in your private CloudKit database."),
        .init(icon: "bell", text: "Notification permission powers reminders for tasks with dates."),
        .init(icon: "plus.circle", text: "Use the Lock Screen Shortcut or the floating + button to capture anywhere.")
    ]
```

- [ ] **Step 4: Update `OnboardingSheet.swift` (macOS) to consume**

Replace the inline `bullets` and `permissionStatusRow` computed properties (lines 65-104) similarly:

```diff
     var body: some View {
         VStack(spacing: 24) {
             header
-            bullets
-            permissionStatusRow
+            OnboardingContent(
+                bullets: Self.macOSBullets,
+                permissionStatus: permissionStatus,
+                onOpenSettings: {
+                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
+                        NSWorkspace.shared.open(url)
+                    }
+                }
+            )
             buttons
             skipLink
         }
```

Add at the bottom of the struct:

```swift
    private static let macOSBullets: [OnboardingContent.Bullet] = [
        .init(icon: "icloud", text: "iCloud sync is required. Your data lives in your private CloudKit database."),
        .init(icon: "bell", text: "Notification permission powers reminders for tasks with dates."),
        .init(icon: "keyboard", text: "Press \u{2303}\u{2325}Space anywhere for Quick Capture.")
    ]
```

- [ ] **Step 5: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift \
        Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift \
        Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift
git commit -m "refactor: promote OnboardingContent into LillistUI

Both onboarding flows now consume a shared bullet-list + permission-
status row. Platform-specific pieces (action bar shape, deep-link
URL) stay in the app-target wrappers."
```

---

## Task 12: Promote `ICloudRequiredContent` into `LillistUI/Onboarding/`

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudRequiredContent.swift`
- Modify: `Apps/Lillist-iOS/Sources/Onboarding/ICloudRequiredScreen.swift`
- Modify: `Apps/Lillist-macOS/Sources/Onboarding/ICloudRequiredView.swift`

- [ ] **Step 1: Author `ICloudRequiredContent.swift`**

```swift
import SwiftUI

/// Shared body content for the "iCloud is required" full-screen
/// blocker. Renders the heading, descriptive copy, and an optional
/// error line. The action bar (Open Settings + Try again) lives in
/// the per-platform wrapper because the destination URLs and button
/// styling differ.
///
/// Plan 14 lifted this from the iOS `ICloudRequiredScreen` and macOS
/// `ICloudRequiredView`, which had drifted in wording and font
/// treatment.
public struct ICloudRequiredContent: View {
    public var lastError: String?

    public init(lastError: String? = nil) {
        self.lastError = lastError
    }

    public var body: some View {
        VStack(spacing: LillistSpacing.l) {
            Image(systemName: "icloud.slash")
                .font(LillistTypography.largeTitle.weight(.light))
                .foregroundStyle(.red)
            Text("iCloud is required")
                .font(LillistTypography.title.weight(.bold))
            Text("Lillist syncs your tasks via your private iCloud database. Sign into iCloud in Settings, then return here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            if let lastError {
                Text(lastError)
                    .font(LillistTypography.body)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 420)
            }
        }
    }
}
```

The text "Sign into iCloud in Settings, then return here" is taken from the iOS version (more directive); the macOS version's longer copy ("Please sign into iCloud in System Settings and try again") is collapsed into this single line. If the macOS team prefers the longer form, parameterize the copy on init — but the canonical Plan-14 choice is the iOS form.

- [ ] **Step 2: Update `ICloudRequiredScreen.swift` (iOS) to consume**

Replace the body's content stack (lines 13-30) with a call to `ICloudRequiredContent`:

```diff
     var body: some View {
-        VStack(spacing: 20) {
-            Image(systemName: "icloud.slash")
-                .font(LillistTypography.largeTitle.weight(.light))
-                .foregroundStyle(.red)
-            Text("iCloud is required")
-                .font(.title.bold())
-            Text("Lillist syncs your tasks via your private iCloud database. Sign into iCloud in Settings, then return here.")
-                .multilineTextAlignment(.center)
-                .foregroundStyle(.secondary)
-                .padding(.horizontal, 32)
-            if let lastError {
-                Text(lastError)
-                    .font(.callout)
-                    .foregroundStyle(.orange)
-                    .padding(.horizontal, 32)
-            }
+        VStack(spacing: LillistSpacing.l) {
+            ICloudRequiredContent(lastError: lastError)

             Button("Open Settings") {
                 if let url = URL(string: UIApplication.openSettingsURLString) {
                     UIApplication.shared.open(url)
                 }
             }
             .buttonStyle(.bordered)

             Button {
                 Task { await recheck() }
             } label: {
                 if isRechecking {
                     ProgressView()
                 } else {
                     Text("Try again").frame(maxWidth: 180)
                 }
             }
             .buttonStyle(.borderedProminent)
         }
-        .padding(32)
+        .padding(LillistSpacing.xl + LillistSpacing.s)
     }
```

- [ ] **Step 3: Update `ICloudRequiredView.swift` (macOS) to consume**

Replace the body's content stack (lines 17-34) similarly:

```diff
     var body: some View {
-        VStack(spacing: 20) {
-            Image(systemName: "icloud.slash") … }
-            Text("iCloud is required") … }
-            Text("Lillist syncs …") … }
-            if let lastError { … }
+        VStack(spacing: LillistSpacing.l) {
+            ICloudRequiredContent(lastError: lastError)

             HStack(spacing: LillistSpacing.m) {
                 Button("Open System Settings") {
                     if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
                         NSWorkspace.shared.open(url)
                     }
                 }
                 Button {
                     Task { await recheck() }
                 } label: {
                     if isRechecking {
                         ProgressView().controlSize(.small)
                     } else {
                         Text("Try again")
                     }
                 }
                 .keyboardShortcut(.defaultAction)
                 .buttonStyle(.borderedProminent)
             }
         }
-        .padding(40)
-        .frame(width: 520, height: 360)
+        .padding(LillistSpacing.xxl)
+        .frame(width: 520, height: 360)
     }
```

- [ ] **Step 4: Build both apps**

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
git add Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudRequiredContent.swift \
        Apps/Lillist-iOS/Sources/Onboarding/ICloudRequiredScreen.swift \
        Apps/Lillist-macOS/Sources/Onboarding/ICloudRequiredView.swift
git commit -m "refactor: promote ICloudRequiredContent into LillistUI

Body content (icon + heading + copy + error line) is now shared. Per-
platform action bars stay in the app-target wrappers (different URLs
for Settings/System Preferences and different button styling)."
```

---

## Task 13: Add `RecurrenceEditorViewModel.humanSummary` and consume from both platforms

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift`
- Modify: `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorViewModelTests.swift`
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift`
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift`

- [ ] **Step 1: Write the failing tests for `humanSummary`**

Append to `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorViewModelTests.swift`:

```swift
    func test_humanSummary_doesNotRepeat() {
        let vm = RecurrenceEditorViewModel(rule: nil)
        XCTAssertEqual(vm.humanSummary, "Doesn't repeat")
    }

    func test_humanSummary_everyDay() {
        let rule: RecurrenceRule = .calendar(.init(freq: .daily, interval: 1))
        let vm = RecurrenceEditorViewModel(rule: rule)
        XCTAssertEqual(vm.humanSummary, "Every day")
    }

    func test_humanSummary_everyWeek() {
        let rule: RecurrenceRule = .calendar(.init(freq: .weekly, interval: 1))
        let vm = RecurrenceEditorViewModel(rule: rule)
        XCTAssertEqual(vm.humanSummary, "Every week")
    }

    func test_humanSummary_everyNMonths() {
        let rule: RecurrenceRule = .calendar(.init(freq: .monthly, interval: 3))
        let vm = RecurrenceEditorViewModel(rule: rule)
        XCTAssertEqual(vm.humanSummary, "Every 3 months")
    }

    func test_humanSummary_afterCompletion_singularDay() {
        let rule: RecurrenceRule = .afterCompletion(.init(interval: 86_400))
        let vm = RecurrenceEditorViewModel(rule: rule)
        XCTAssertEqual(vm.humanSummary, "Repeats 1 day after completion")
    }

    func test_humanSummary_afterCompletion_pluralDays() {
        let rule: RecurrenceRule = .afterCompletion(.init(interval: 86_400 * 7))
        let vm = RecurrenceEditorViewModel(rule: rule)
        XCTAssertEqual(vm.humanSummary, "Repeats 7 days after completion")
    }
```

- [ ] **Step 2: Run and verify they fail**

```bash
swift test --package-path Packages/LillistUI --filter RecurrenceEditorViewModelTests 2>&1 | tail -10
```

Expected: compile error — `humanSummary` does not exist.

- [ ] **Step 3: Add `humanSummary` to the view model**

At the end of `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift` (before the closing brace), add:

```swift
    /// Human-readable summary of the current recurrence configuration.
    /// Mirrors the inline `currentRecurrenceSummary` previously built in
    /// the macOS `TaskDetailView` (Plan 11). Lifted to the view model
    /// so iOS can show the same string next to its toolbar icon.
    public var humanSummary: String {
        guard repeats else { return "Doesn't repeat" }
        switch mode {
        case .calendar:
            let unit: String
            switch freq {
            case .daily: unit = "day"
            case .weekly: unit = "week"
            case .monthly: unit = "month"
            case .yearly: unit = "year"
            }
            return interval == 1
                ? "Every \(unit)"
                : "Every \(interval) \(unit)s"
        case .afterCompletion:
            let days = Int(afterCompletionSeconds / 86_400)
            return "Repeats \(days) day\(days == 1 ? "" : "s") after completion"
        }
    }
```

- [ ] **Step 4: Re-run tests**

```bash
swift test --package-path Packages/LillistUI --filter RecurrenceEditorViewModelTests 2>&1 | tail -10
```

Expected: all PASS.

- [ ] **Step 5: Migrate macOS `TaskDetailView.swift` to delegate**

In `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift`, replace the `currentRecurrenceSummary` private computed property (lines 81-99) with a one-liner that delegates to the view model:

```diff
-    private var currentRecurrenceSummary: String {
-        guard recurrenceViewModel.repeats else { return "Doesn't repeat" }
-        switch recurrenceViewModel.mode {
-        case .calendar:
-            let unit: String
-            switch recurrenceViewModel.freq {
-            case .daily: unit = "day"
-            case .weekly: unit = "week"
-            case .monthly: unit = "month"
-            case .yearly: unit = "year"
-            }
-            return recurrenceViewModel.interval == 1
-                ? "Every \(unit)"
-                : "Every \(recurrenceViewModel.interval) \(unit)s"
-        case .afterCompletion:
-            let days = Int(recurrenceViewModel.afterCompletionSeconds / 86_400)
-            return "Repeats \(days) day\(days == 1 ? "" : "s") after completion"
-        }
-    }
+    private var currentRecurrenceSummary: String {
+        recurrenceViewModel.humanSummary
+    }
```

- [ ] **Step 6: Surface the summary in iOS `TaskDetailView.swift`**

In `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift`, the recurrence toolbar button (lines 57-66) currently renders an icon only. Add the human summary as a label next to the icon. The toolbar item becomes:

```diff
         .toolbar {
             ToolbarItem(placement: .topBarTrailing) {
                 Button {
                     showingRecurrenceSheet = true
                 } label: {
-                    Image(systemName: seriesRule == nil ? "repeat" : "repeat.circle.fill")
+                    HStack(spacing: LillistSpacing.xs) {
+                        Image(systemName: seriesRule == nil ? "repeat" : "repeat.circle.fill")
+                        Text(seriesRuleSummary)
+                            .font(LillistTypography.caption)
+                    }
                 }
                 .accessibilityLabel(seriesRule == nil ? "Add recurrence" : "Edit recurrence")
+                .accessibilityValue(seriesRuleSummary)
             }
         }
```

Add a computed property at the end of the struct (before the closing brace, alongside `reload()`):

```swift
    private var seriesRuleSummary: String {
        RecurrenceEditorViewModel(rule: seriesRule).humanSummary
    }
```

Note: this builds a transient view model on every body render. The cost is negligible (it's a value type, no Core Data fetch). If perf shows up as an issue in profiling, cache via `@State` synced through an `.onChange(of: seriesRule)`. Don't pre-optimize.

- [ ] **Step 7: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

- [ ] **Step 8: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift \
        Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorViewModelTests.swift \
        Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift \
        Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift
git commit -m "feat(ui): RecurrenceEditorViewModel.humanSummary, consumed from both detail views

Lifts the recurrence-summary string builder from macOS TaskDetailView
into RecurrenceEditorViewModel so iOS can render the same text next
to its toolbar icon. Replaces icon-only iOS affordance with icon +
caption."
```

---

## Task 14: Final sweep + engineering-notes entry

**Files:**
- Modify: `docs/engineering-notes.md`

- [ ] **Step 1: Full test + build sweep**

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

All green.

- [ ] **Step 2: Strict-warnings sanity check**

```bash
swift build --package-path Packages/LillistCore 2>&1 | grep -E 'warning|error' | head -10
swift build --package-path Packages/LillistUI 2>&1 | grep -E 'warning|error' | head -10
```

Expected: no output (CLAUDE.md mandates warnings-as-errors and the package settings already enforce it).

- [ ] **Step 3: Final hardcoded-literal sweep**

```bash
grep -rn 'font(.system(size:' Packages/LillistUI/Sources/ Apps/ 2>&1
grep -rn '#7F8FA6' Apps/ Packages/LillistUI/Sources/Components Packages/LillistUI/Sources/iOS Packages/LillistUI/Sources/QuickCapture 2>&1
grep -rn "private extension SortField" Apps/ 2>&1
grep -rn "private func date(hour:\|private func date(_:" Apps/ 2>&1
grep -rn "struct JournalEntryRow" Apps/ 2>&1
```

Each grep should return zero output (or only the LillistUI canonical definition for `#7F8FA6`).

- [ ] **Step 4: Append the engineering note**

Insert at the top of `docs/engineering-notes.md` (above the 2026-05-15 Plan 12 entry):

```markdown
## 2026-05-16 — Plan 14 Design System: hardcoded sizes defeat Dynamic Type; "no visual change" refactors need snapshot baselines first; SyncIndicator palette divergence

**Context.** Plan 14 introduced `LillistSpacing`/`LillistRadius`/`LillistTiming`/`LillistTypography` tokens to `LillistUI`, lifted three duplicated app-target helpers (`Color+Hex`, `SortField.displayName`, `HourMinuteDate`, `CrashReportSample`) into the shared package, and unified the per-platform `SyncIndicator → Color` switch into a single `SyncPalette` extension. The plan is a pure refactor with snapshot tests as the regression net.

**Rules.**

- **`.font(.system(size: N, weight: …))` defeats Dynamic Type.** A user who's bumped their accessibility text size to "Extra Large" gets no help from chrome that hardcodes a pixel size. Use semantic styles (`.body`, `.headline`, `.title`, etc.) wherever possible; reach for `.system(size:)` only for an SF Symbol that explicitly needs a different size from the surrounding text (a rare case, almost never the right answer for app chrome). The replacement for "I want this to look big" is `.largeTitle.weight(.light)`, not `.system(size: 64, weight: .light)`.
- **For "no visual change" refactors, pin the visuals first.** Record snapshot baselines before touching any code. If the post-refactor diff is non-zero, either (a) the token's numeric value diverged from the original literal (a bug — fix the token), or (b) you're crossing a Dynamic-Type boundary intentionally (record explicitly, note in commit). Never re-record blindly; always inspect the diff.
- **A `==` against an associated-value enum case is always false.** `if indicator == .inProgress` does not match `.inProgress`, because the enum is `Equatable` but `.inProgress` here is a *case-without-payload* literal that the compiler treats as `SyncIndicator.inProgress(payload: ?)`. Always use `if case .inProgress = indicator`. Surfaced as the `SyncStatusBadge.swift:20-21` bug Plan 13 fixed and Plan 14 consumed; the pattern recurs whenever someone adds `case .foo(payload: T)` to an enum that previously had a bare `.foo`.
- **One source of truth per inversion.** `SyncStatusDotView` (macOS) and `SyncStatusBadge` (iOS) each had their own `switch indicator { … }` returning a `Color`. They drifted: macOS rendered stale `.idle` as `.yellow`, iOS rendered any `.idle` as `.green`. The collapse into `SyncPalette` is the same shape as Plan 12's `HotkeyKeyTable` consolidation: when two pieces of code derive the same value from the same input, they should call through one extension method, not maintain parallel tables.

**Evidence.** Plan 14 commits on `plan-14-design-system` (merged into `main` as such): `Tokens.swift`, `SyncPalette.swift`, `SyncPaletteTests.swift`, `Color+Hex.swift`, `JournalEntryRow.swift`, `Settings/` helpers, `Onboarding/` shared content, `humanSummary` view-model property, plus the seven app-target migration commits.
```

- [ ] **Step 5: Commit and tag**

```bash
git add docs/engineering-notes.md
git commit -m "docs: record Plan 14 lessons (Dynamic Type, snapshot pinning, palette inversion)"
git tag plan-14-design-system
```

- [ ] **Step 6: Branch summary**

```bash
git log --oneline plan-13..plan-14-design-system 2>&1
```

(If Plan 13's tag has a different name, adjust the lower bound.)

---

## Plan 14 Scope

**In:**
- `Theme/Tokens.swift` — spacing/radius/timing/typography tokens + `LillistTokens.defaultTagTintHex`.
- `Theme/SyncPalette.swift` — canonical `SyncIndicator` color + glyph mapping, with regression tests.
- `Theme/Color+Hex.swift` — cross-platform hex round-trip, replacing two app-target copies.
- `Components/JournalEntryRow.swift` — promoted from both apps, macOS glyph set canonical.
- `Settings/SortField+DisplayName.swift`, `Settings/HourMinuteDate.swift`, `Settings/CrashReportSample.swift` — promoted Preferences helpers.
- `Onboarding/OnboardingContent.swift`, `Onboarding/ICloudRequiredContent.swift` — promoted onboarding bodies.
- `RecurrenceEditorViewModel.humanSummary` + iOS toolbar consumption.
- Token migration across all flagged `Packages/LillistUI/Sources/` callsites and the five flagged app-target callsites.
- Snapshot test extensions for `SyncStatusBadge` (third state + dark mode).
- Engineering-notes entry.
- `plan-14-design-system` tag.

**Out:**
- Adding new tokens beyond the explicit list (do this in a follow-up plan if the need arises during execution).
- Refactoring `TagTint.init?(hex:)` to share code with `Color(hex:)` — they serve distinct purposes (see Notes).
- Converting fixed frame sizes to `@ScaledMetric` (separate accessibility plan).
- Touching the recurrence editor's *form controls* — only `humanSummary` is added to the view model.
- Anything outside `LillistUI` and the app targets (no `LillistCore` changes).

---

## Self-Review Checklist

- [ ] `Tokens.swift` declares `LillistSpacing`, `LillistRadius`, `LillistTiming`, `LillistTypography`, `LillistTokens.defaultTagTintHex` — all `public` and documented.
- [ ] `SyncPalette.swift` provides `color` and `systemImage` on `SyncIndicator`. Tests cover all five color cases (idle-nil, idle-recent, idle-stale, inProgress, error).
- [ ] `Color+Hex.swift` is the only `Color(hex:)` / `Color.toHex()` definition in the codebase. The two app-target copies are deleted.
- [ ] `JournalEntryRow.swift` is consumed by both apps; the macOS-style glyph set (`text.bubble` / `arrow.triangle.2.circlepath` / `paperclip` / `arrow.uturn.right.circle`) renders in iOS too.
- [ ] `SortField.displayName`, `HourMinuteDate.date(hour:minute:)`, `CrashReportSample.preview(_:)` each live in `LillistUI/Settings/` and the app-target duplicates are deleted.
- [ ] `OnboardingContent` and `ICloudRequiredContent` are consumed by both apps; only action-bar shape and Settings-URL closures remain per-platform.
- [ ] `RecurrenceEditorViewModel.humanSummary` returns "Doesn't repeat" / "Every day" / "Every N weeks" / "Repeats N days after completion" with correct singular/plural. macOS `TaskDetailView` delegates to it; iOS `TaskDetailView` surfaces it in the toolbar.
- [ ] No `grep` for `font(.system(size:` in `Packages/LillistUI/Sources/` or `Apps/` returns a hit (except for SF Symbol sizing where genuinely required — none are expected).
- [ ] No `grep` for `#7F8FA6` returns a hit outside `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift`.
- [ ] Snapshot diffs for pure-spacing migrations (Tasks 3 steps 2-5/7) are zero pixels; Dynamic-Type-restoring migrations (Tasks 3 step 4/6/7, Task 4) are re-recorded with intent noted in commit body.
- [ ] All snapshot reference images committed under `Packages/LillistUI/Tests/LillistUITests/**/__Snapshots__/`.
- [ ] `swift build --package-path Packages/LillistUI` reports `Build complete!` with zero warnings (warnings-as-errors enforced).
- [ ] `swift build --package-path Packages/LillistCore` reports `Build complete!` with zero warnings.
- [ ] `xcodebuild` for both `Lillist-iOS` and `Lillist-macOS` reports `** BUILD SUCCEEDED **`.
- [ ] Engineering note appended to `docs/engineering-notes.md` with the 2026-05-16 header and the four rules.
- [ ] `plan-14-design-system` tag created on the final commit.
