# Lillist — Project Conventions

Repo-scoped guidance for Claude Code and humans. User-global rules live
in `~/.claude/CLAUDE.md`; this file adds only Lillist-specific knowledge.

## What Lillist is

Task manager for macOS + iOS, with a `lillist` CLI. Apple-only: Swift 6,
SwiftUI, Core Data via `NSPersistentCloudKitContainer`, CloudKit sync.
Features: predicate-driven smart filters, recurrence, notifications,
journal, attachments, iOS Share Extension, App Intents extension,
in-house crash reporter.

## Topology

- **`Packages/LillistCore/`** — data model, stores, notification
  scheduler, recurrence expander, predicate engine, crash reporter,
  CLI. Public APIs return value-type DTOs. Strict concurrency on the
  source target.
- **`Packages/LillistUI/`** — cross-platform SwiftUI library shared by
  both apps. Design tokens (`Theme/Tokens.swift`), Quick Capture
  parser, recurrence editor, status surfaces, iOS Tab Screens at
  `iOS/Screens/<Tab>Screen.swift`, snapshot tests at
  `Tests/LillistUITests/`.
- **`Apps/Lillist-macOS/`** — macOS shell (`RootSplitView`, command
  menu, Preferences scene, AppDelegate window management).
- **`Apps/Lillist-iOS/`** — `AppEnvironment`, `TabShell` (compact) /
  `SplitShell` (regular), thin per-tab wrappers around LillistUI
  Screens, Settings sub-sections.
- **`Extensions/`** *(top-level, not under the iOS app)* —
  `ShareExtension-iOS/` (share-sheet capture) and `ShortcutsActions/`
  (App Intents). All targets share App Group
  `group.io.mikeydotio.Lillist`.
- **CLI** — `lillist-cli` target under `Packages/LillistCore`,
  `swift-argument-parser`-based; handlers thin-wrap stores.
- **`Tools/Deploy/`** — `deploy-ios.sh` archives Lillist-iOS, exports a
  Development-signed `.ipa`, and serves it over Tailscale Serve for OTA
  install on registered devices. See *Deploy (iOS test builds)* below
  and `Tools/Deploy/README.md` for one-time setup.

## Design and history

- **Design doc:** `docs/plans/2026-05-12-lillist-design.md`. Section
  numbers are the canonical reference for product behavior.
- **Visual design system:** `docs/plans/2026-06-12-rainbow-logic-design-system.md`
  ("Rainbow Logic" / Structured Whimsy). Canonical for tokens, color
  semantics, elevation, typography, density, and component treatments.
  House rules from it: color is functional, never decorative; text
  never uses functional `base` hues (use `ink`); list rows cap at `xs`
  elevation; full rainbow gradient only on heroes/success moments.
- **Engineering notes:** `docs/engineering-notes.md`. Append-only log
  of non-obvious gotchas — concurrency surprises, framework-shape
  issues, cross-cutting patterns. Add an entry only when a future
  contributor would otherwise rediscover the lesson the hard way. *Not*
  for bug-fix details (commit message), code patterns (the code), or
  feature decisions (the design doc).
- **Past plans:** `docs/superpowers/plans/` — historical record of how
  features landed (Plans 1–20 are checked in; Plan 20a is captured in
  engineering-notes; Plan 21 is in flight on branches/commits). Useful
  as archaeology, *not* the current source of truth.
- **Completed program — Foundation Hardening:** the 2026-05-28 code review
  (`docs/reviews/2026-05-28-foundation-review.md`) and its 22 follow-up
  plans are **all complete and merged to `main`** (Waves 1–7). The index
  `docs/superpowers/plans/2026-05-29-foundation-hardening-index.md` is the
  historical record of how it landed; `docs/superpowers/handoffs/wave-7.md`
  is the closing handoff (and notes the CI scope: host-pinned snapshot tests
  and the iCloud-dependent app-hosted/UI tests are verified on a signed Mac,
  not in CI). The plans under `docs/superpowers/plans/` are now **archaeology**,
  not an active to-do list. CI (`.github/workflows/ci.yml`) now enforces the
  test/build matrix post-push on `main` (see *Build & test*).

## Build & test

```bash
# LillistCore and LillistUI on the host platform (macOS):
swift test --package-path Packages/LillistCore
swift test --package-path Packages/LillistUI   # iOS-only #if blocks compile out

# ⚠️ LillistUI snapshot tests FAIL under host `swift test`: ~10 deterministic
# mismatches from cross-host font/anti-aliasing baseline drift — NOT a regression.
# Baselines are pinned to this Mac; the trustworthy run is the signed
# `xcodebuild test -scheme Lillist-iOS` recipe below (Claude Code can run this).
# Use host `swift test --package-path Packages/LillistUI` only to confirm the
# package compiles + its non-snapshot tests pass. (See engineering-notes.md
# baseline-drift entries.)
#
# To regenerate baselines after a visual change: run `xcodebuild test -scheme
# Lillist-iOS` on this Mac, set RECORD_SNAPSHOTS=YES via the scheme's env vars
# or pass `-testArguments RECORD_SNAPSHOTS=YES`, then commit the updated
# ReferenceImages in Packages/LillistUI/Tests/LillistUITests/ReferenceImages/.

# iOS-only tests (iOSSnapshotTests, IOSScreenTourTests):
xcodebuild test -workspace Lillist.xcworkspace \
  -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'

# App-target builds (signed — Keychain must be unlocked, Signing.local.xcconfig present):
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' build

# Unsigned fallback (CI, fresh machine without certs):
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-{iOS,macOS} \
  -destination '<see above>' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

The **migration/store-swap tests are app-hosted**: `MigrationCoordinatorTests`,
`PersistenceHostTests`, and `StoreLevelModeSwapSpike` gate their
live-container cases on a real `CFBundleIdentifier` (`liveSwapAllowed`),
which the standalone `LillistCoreTests` SPM bundle and the
`TEST_HOST=""` `Lillist-iOSTests` bundle both lack — so those cases
*silently skip* under `swift test`. The `Lillist-iOSAppHostedTests`
target hosts them inside `Lillist-iOS` (real bundle ID) so they
actually execute; `LiveSwapHostMetaTests` fails loudly if the host is
ever misconfigured back to standalone. Run them with:

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:Lillist-iOSAppHostedTests
```

The fully-executing state-machine tests (`MigrationRunnerExecutingTests`,
`MigrationRecoveryTests`) run under plain `swift test` because they use
the `PersistenceReconfiguring` fake instead of a live container.

The xcodebuild destination is **iPhone 17 / iOS 26.2** (test runner
host). Snapshot rendering itself is pinned to **iPhone 16 Pro logical
size (393×852)** via `phoneSize` in `IOSScreenTourTests.swift` — so
snapshot diffs stay device-neutral regardless of which simulator runs
the suite. Don't change either pin casually.

After moving/deleting source files, regenerate the matching pbxproj:
```bash
(cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .)
(cd Apps            && xcodegen generate --spec project.yml --project .)
```

**CI.** `.github/workflows/ci.yml` runs the matrix post-push on `main`
(and via `workflow_dispatch`): `swift test` for both packages, a
pbxproj-drift gate (`xcodegen generate` + `git diff --exit-code`), the
`Lillist-iOS` standalone bundle + the `Lillist-macOS` scheme, a
Release-configuration smoke build, and the LillistUI localization lint
(`Tools/CI/check-lillistui-localization.sh`). It's a post-push verifier,
not a merge gate (solo project, direct-to-`main`). deployit still
archives Debug — CI is the only Release-config compile. Two things CI
deliberately does **not** run: the **host-pinned snapshot tests** (LillistUI
`*SnapshotTests`/`*ScreenTourTests` — baselines drift on any other host;
CI runs LillistUI with `--skip Snapshot --skip Tour` and skips the
`LillistUITests` iOS bundle — Claude Code *can* run these via the signed
`xcodebuild test -scheme Lillist-iOS` recipe and regenerate baselines when
needed) and the **`Lillist-iOSAppHostedTests` live-swap tests +
`Lillist-iOSUITests`** (the live `NSPersistentCloudKitContainer` fails
`CKAccountStatusNoAccount` without iCloud — these require a Mac with an
active iCloud account and must be verified by Mikey). See the
"CI established + build-posture alignment" entry in
`docs/engineering-notes.md`.

**Parallel-test flakes (`LillistCore`).** Heavy concurrent in-memory
store creation intermittently SIGSEGVs inside Core Data, and the same CPU
contention starves wall-clock-sensitive tests (`SyncQuiesceMonitorTests`
and `TaskStoreRecurrenceSpawnTests`'s `< 2.0s` tolerance) — see
`docs/engineering-notes.md` 2026-06-04. None is a product bug. Run the
suite with bounded parallelism + a one-shot retry to match CI:
`swift test --package-path Packages/LillistCore --parallel --num-workers 2`
(re-run once on a one-off SIGSEGV / timing flake before treating it as a
real failure). NB: `--num-workers N` **requires** `--parallel` on this
toolchain (Swift 6.2.4); the bare form errors. `--no-parallel` is the
serial fallback but does not by itself eliminate the timing flakes.

## House rules

- **Treat build warnings as errors** across SPM and Xcode. Fix at the
  architecture level — don't paper over with attribute or pragma noise.
- **Follow SOLID, DRY, YAGNI, separation of concerns.** Write software
  worth publishing. Tests exist to enforce quality, not to pass; a
  poorly designed test that gives a false sense of success is a defect.
- **Read a file before each fresh edit pass** — it may have moved or
  been edited by the user since you last looked.
- **Strict concurrency on `LillistCore` source target; tests are not
  strict.** A clean build is not proof of correctness — add stress
  repetitions for any code that crosses actor boundaries.
- **Never force-push without explicit per-case user permission.**

## Code conventions

### Data layer

- **Hand-written `@NSManaged` subclasses.** Every Core Data entity has
  a hand-written `@objc(Name) public final class Name: NSManagedObject`
  in `Packages/LillistCore/Sources/LillistCore/ManagedObjects/`. Do not
  rely on Core Data's class codegen.
- **No `NSManagedObject` escapes `LillistCore`.** Public store APIs
  return value-type DTOs (`TaskStore.TaskRecord`,
  `SeriesStore.SeriesRecord`, `SmartFilterStore.SmartFilterRecord`,
  `TagStore.TagRecord`, `JournalStore.JournalRecord`,
  `AttachmentStore.AttachmentRecord`). Tests and downstream layers
  never see Core Data types.
- **Every public DTO needs an explicit public `init`.** Swift's
  synthesized memberwise init is internal-only even when all fields
  are public — write it by hand so callers outside the module can
  construct mocks.
- **Date math through `Calendar`, not `Date.addingTimeInterval`.**
  `RecurrenceExpander` is canonical: DST and month-length correctness
  require `Calendar.date(byAdding:)` and `DateComponents` round-trips.
  The one `addingTimeInterval` callsite is the `afterCompletion` rule,
  which is *defined* in absolute seconds.

### UI layer

- **iOS Tab screens use a container/presenter split.** The five
  primary surfaces (Today, AllTags, FiltersList, Search, Settings)
  live in `Packages/LillistUI/Sources/LillistUI/iOS/Screens/<Tab>Screen.swift`
  as **pure presentation** — data and action closures via `init`, no
  `@State`, no `.task`. The matching `Apps/Lillist-iOS/Sources/<Tab>/`
  wrapper owns `@State`, `.task` lifecycle, `AppEnvironment` reads,
  and `.navigationDestination` handlers (destination views reference
  iOS-app types LillistUI can't import). This split lets
  `IOSScreenTourTests` render real screens with frozen mock data.
- **Settings is a chrome-only split.** `LillistUI.SettingsScreen<SectionsContent: View>`
  owns `NavigationStack + Form + title + Done`; env-coupled sections
  (General, Notifications, Trash, QuickCapture, CrashReporting,
  Advanced) stay in the iOS app target where their `AppEnvironment`
  dependencies live. The app target passes sections via a ViewBuilder;
  tour tests pass mock placeholders.
- **`@MainActor` on SwiftUI Views ripples to static helpers.** Pure
  value-math hung off a `View` should be `public nonisolated static func`
  so non-MainActor callers (XCTestCase, background tasks) can use it
  without crossing the isolation boundary.
- **Cross-platform user-visible strings must match verbatim.** Touch a
  welcome line, error message, or tagline on one platform — sync the
  other in the same change. Snapshot tests guard the visible surface.
  All three `Localizable.xcstrings` (iOS app, macOS app, LillistUI)
  must stay aligned with the code.
- **`Text(LocalizedStringKey)` auto-link detection is literal-only.**
  Markdown auto-links fire on compile-time literals; interpolated
  values render as plain text. Spell links explicitly —
  `[\(addr)](mailto:\(addr))` — to survive interpolation.

## Build-plugin caching gotcha

> **Retired by `ci-and-build-posture`.** The `CompileCoreDataModel`
> plugin now declares the inner `*.xcdatamodel/contents` +
> `.xccurrentversion` as `inputFiles`, so a model edit auto-invalidates
> `momc`. The touch ritual below is no longer required for
> `swift build`/`swift test`; it is kept here as historical context.
> See the "CI established + build-posture alignment" entry in
> `docs/engineering-notes.md`.

SwiftPM's `CompileCoreDataModel` plugin keys on the `.xcdatamodeld`
directory's mtime, not on the inner `LillistModel.xcdatamodel/contents`
file. After editing `contents`, the old `.momd` is reused and runtime
crashes with `NSInvalidArgumentException: must have a valid
NSEntityDescription`. Touch both directories to force a rebuild:

```bash
touch Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/ \
      Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/
```

## Code signing

`Apps/Config/` holds an xcconfig indirection that keeps the team ID
out of the pbxproj:

- `Signing.xcconfig` (committed) — `#include? "Signing.local.xcconfig"`
  + `DEVELOPMENT_TEAM = $(LOCAL_DEVELOPMENT_TEAM)`. Both `project.yml`s
  reference this via `configFiles:`.
- `Signing.local.xcconfig` (gitignored) — one line:
  `LOCAL_DEVELOPMENT_TEAM = <10-char Team ID>`.
- `Signing.local.xcconfig.example` (committed) — new-contributor
  template.

The `$(LOCAL_DEVELOPMENT_TEAM)` placeholder is literal to xcodegen but
resolves at build time, so `xcodegen generate` is idempotent and the
team ID never lands in the pbxproj. **Never put `DEVELOPMENT_TEAM`
into `project.yml`'s `settings: base:`** — that breaks the indirection.
`CODE_SIGN_STYLE: Automatic` in `project.yml` is fine.

## Deploy (iOS test builds)

Deployment is handled by the **`deployit` plugin** (`/deployit`),
which replaced the previous in-repo `Tools/Deploy/deploy-ios.sh` on
2026-05-23. It does the same job — archive `Lillist-iOS`, export a
Development-signed `.ipa`, stage it under
`$HOME/Library/Application Support/deployit/serve/`, and point you at
a Tailscale-served landing URL — plus it indexes every build into the
shared `mikeydotio/deployit-index` repo so deploys are visible across
machines. Round-trip is still ~3–5 min and the `.ipa` never leaves the
contributor's tailnet.

**Required (per-contributor):**

- `Apps/Config/Signing.local.xcconfig` populated (see *Code signing*).
- The target iPhone's UDID is in the team's Development provisioning
  profile — i.e., the device has been used with Xcode on this team
  at least once. Development-method signing installs OTA on
  registered devices without Ad-Hoc.
- Run `/deployit bootstrap` once on each Mac. The plugin owns its
  Tailscale Serve config and the localhost HTTP backend on
  `127.0.0.1:8729`; no shell-rc env vars are required.

**Run:**

```text
/deployit deploy
```

The plugin auto-detects Lillist's Apps-layout
(`./Lillist.xcworkspace` + `./Apps/Lillist-iOS/project.yml`), reads
`MARKETING_VERSION` / `PRODUCT_BUNDLE_IDENTIFIER` from the project.yml,
and reads the resolved `CFBundleVersion` from the built `Info.plist`.
`/deployit list`, `/deployit url`, `/deployit status`, and
`/deployit gc` round out the surface.

**After every successful deploy, commit the bumped
`Apps/Config/BuildNumber.xcconfig`.** The `Lillist-iOS` scheme's
Archive *pre-action* (`Tools/Deploy/bump-build-number.sh`) increments
`CURRENT_PROJECT_VERSION` on every archive — this is the *only*
piece of the old `Tools/Deploy/` infrastructure that survived the
migration, because build-number bumping is the host repo's
responsibility (deployit reads the resolved value, doesn't write it).
The file is tracked in git so the counter is monotonic across
machines and never regresses — a `chore(deploy): bump iOS build
number to N` commit per deploy keeps it that way.

**On the iPhone:**

1. Open the printed landing URL in Safari (bookmark it the first time).
2. Tap **Install**.
3. First time on a fresh profile: Settings → General → VPN & Device
   Management → trust the developer profile, then retry the install.

## Git workflow

Solo project — commit and push directly to `main`. No PR review is
required (and none is performed). Repo lives under `mikeydotio`. Use
conventional-commit prefixes (`feat:`, `fix:`, `refactor:`, `test:`,
`docs:`, `chore:`) and land small, focused commits. HTTPS push and
never-force-push rules are in `~/.claude/CLAUDE.md`.

## Rainbow Logic redesign — COMPLETE (2026-06-12)

The Rainbow Logic design system ("Structured Whimsy") is applied across
both apps and the share extension. Spec:
`docs/plans/2026-06-12-rainbow-logic-design-system.md`. Theme layer in
`Packages/LillistUI/Sources/LillistUI/Theme/` (RainbowPalette,
LillistColor, LillistElevation, LillistMotion, RainbowGradient,
RainbowButtonStyle, RainbowToggleStyle, Fonts/LillistFonts +
LillistColor/typography tokens in Tokens.swift). Signature components:
StatusCubeView, ConfettiBurstView, RainbowCard, RainbowEmptyStateView.
Plus Jakarta Sans is bundled + process-registered; AccentColor is
script-purple. Verified: LillistUI 147/147, LillistCore 895/895, both
app builds, iOS scheme green (bar the 2 known iCloud live-swap cases).
Gotchas captured in `docs/engineering-notes.md` (2026-06-12 entry).

## Rainbow Glass redesign — COMPLETE (2026-06-15)

Rainbow Logic evolved onto Apple's iOS 26 Liquid Glass: the whimsical
palette became functional *glass tints*, and faux-depth (drop shadows,
top highlights, inset wells, the 3D cube) was retired for native glass.
All waves landed, including the Wave 6 snapshot reconciliation.

- **Seam:** `Theme/GlassSurface.swift` — `glassSurface(_:in:)`,
  `glassGroup()`, `glassElevation()`. Centralizes the OS-26 `#available`
  gate + degradation (glass → solid fill for tints / `.regularMaterial`
  for chrome → opaque under Reduce Transparency). No surface uses
  `.interactive()` glass — the FAB shares the `.statusTinted(.lavender)`
  surface with the Quick Capture "Add task" button (see engineering-notes
  2026-06-16).
- **Snapshot rules (hard-won — see engineering-notes 2026-06-12/14/15/16):**
  - The `StatusIndicatorView` `Menu` hit layer and **`.drawingGroup()`/
    Metal** (e.g. `RainbowEmptyStateView`'s `DotGridBackdrop`) blank the
    **whole** offscreen capture. Plain tinted glass (the FAB, panels,
    toasts, `.rainbow` buttons/toggles) renders offscreen fine with the
    tour strategy.
  - The app-hosted `Lillist-iOSAppHostedTests/GlassSnapshotTests` hosts the
    glass surfaces (FAB, buttons, toggles, QuickCaptureDialog, status
    control, empty state). The status control and empty state *must* live
    here (they blank offscreen); the FAB/buttons/toggles live here with
    them for grouping. Everything else stays in offscreen `LillistUITests`.
  - **macOS glass is NOT offscreen-snapshottable and has no app-hosted
    path** — AppKit has no `drawHierarchyInKeyWindow`, and window-server
    capture needs `CGWindowListCreateImage` (obsoleted in macOS 15) or
    ScreenCaptureKit (Screen Recording permission). The three `#if
    os(macOS)` glass snapshot suites are **`XCTSkip`-quarantined**; macOS
    glass is verified manually. Revisit if Apple ships a capture API.

## When in doubt

1. Check `docs/engineering-notes.md` for a known gotcha.
2. Check the design doc (`docs/plans/2026-05-12-lillist-design.md`)
   and, for anything visual, the Rainbow Logic design system
   (`docs/plans/2026-06-12-rainbow-logic-design-system.md`).
3. `docs/superpowers/plans/` is archaeology — useful for *how* a
   feature landed, never as the current spec.
4. Ask.

<!-- semver:start -->
## Semantic Versioning

This project uses semantic versioning managed by the `/semver` plugin.

### Version Awareness
- Read the `VERSION` file at the start of each conversation to know the current version.
- Read `.semver/config.yaml` to understand the versioning configuration.
- When discussing releases, deployments, or changes, reference the current version.

### Commit Discipline
- Write meaningful, descriptive commit messages. Each commit message may appear in an auto-generated changelog.
- Use conventional-commit-style prefixes when they fit naturally: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.
- The first line of the commit message should be a concise summary (under 72 characters). Add detail in the body if needed.

### Version Bump Guidance
When recommending or performing a version bump:
- **patch** (0.0.x): Bug fixes, documentation corrections, minor refactors with no behavior change.
- **minor** (0.x.0): New features, new capabilities, non-breaking additions to the public API or user-facing behavior.
- **major** (x.0.0): Breaking changes — removed features, changed interfaces, incompatible API modifications, behavior changes that require consumers to update.

When you notice the user has completed a logical unit of work, suggest running `/semver bump` with the appropriate level.

### Hooks
- Custom pre-bump and post-bump hooks can be added in `.semver/hooks/`.
- Never trigger `/semver bump` from within a hook — this causes infinite recursion.

### Configuration
Versioning settings are in `.semver/config.yaml`. Do not modify this file unless the user explicitly asks to change semver settings.
<!-- semver:end -->

<!-- atlas:start -->
## Codebase Map (atlas)

@docs/atlas/INDEX.md

- The imported INDEX above is this project's codebase map. Use its routing
  table: read the listed module doc before working in that area.
- The map covers code structure only; build/test/workflow guidance lives in
  the rest of this file.
- After committing changes to mapped source files, suggest running
  `/atlas update`.
<!-- atlas:end -->
