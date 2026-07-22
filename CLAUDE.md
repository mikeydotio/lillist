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
  scheduler, recurrence expander, predicate engine, crash reporter.
  Public APIs return value-type DTOs. Strict concurrency on the
  source target. No FoundationModels dependency, by design (see
  `LillistSearchIntelligence` below) — importable and testable on any
  Xcode install.
- **`Packages/LillistUI/`** — cross-platform SwiftUI library shared by
  both apps. Design tokens (`Theme/Tokens.swift`), Quick Capture
  parser, recurrence editor, status surfaces, iOS Tab Screens at
  `iOS/Screens/<Tab>Screen.swift`, snapshot tests at
  `Tests/LillistUITests/`.
- **`Packages/LillistSearchIntelligence/`** *(added for agentic search,
  issue #51)* — the on-device (`SystemLanguageModel`, iOS/macOS 26+)
  and Private Cloud Compute (`PrivateCloudComputeLanguageModel`,
  iOS/macOS 27+) `FilterQueryTranslator` implementations, selected by
  `FilterTranslatorFactory`. Depends on `LillistCore` (for `Field`/`Op`/
  `PredicateGroup`/the `Search/` translation types) but nothing depends
  on it *from within* `LillistCore` — that would be circular, which is
  exactly why the CLI lives in its own package (next). Needs the Xcode
  27 beta SDK to compile — see *Two Xcode toolchains* below.
- **`Packages/LillistCLI/`** — the `lillist` CLI executable
  (`lillist-cli` target, `swift-argument-parser`-based; handlers
  thin-wrap `LillistCore` stores). Split out from `Packages/LillistCore`
  specifically so it can depend on both `LillistCore` *and*
  `LillistSearchIntelligence` without the latter creating a package
  cycle back through `LillistCore`.
- **`Apps/Lillist-macOS/`** — macOS shell (`RootSplitView`, command
  menu, Preferences scene, AppDelegate window management).
- **`Apps/Lillist-iOS/`** — `AppEnvironment`, `TabShell` (compact) /
  `SplitShell` (regular), thin per-tab wrappers around LillistUI
  Screens, Settings sub-sections.
- **`Extensions/`** *(top-level, not under the iOS app)* —
  `ShareExtension-iOS/` (share-sheet capture) and `ShortcutsActions/`
  (App Intents). All targets share App Group
  `group.app.lillist`.
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

**Two Xcode toolchains.** `/Applications/Xcode.app` (26.6, iOS 26.5 SDK) is
the `xcode-select`ed default and builds the **whole app**, including
`Packages/LillistSearchIntelligence` — as of #70, the reference to
`FoundationModels.PrivateCloudComputeLanguageModel` (the `@available(iOS 27,
macOS 27, *)` agentic-search PCC tier) is compile-gated behind `#if
canImport(FoundationModels, _version: 2)`, which is false on the 26.5 SDK, so
that one tier compiles out and the on-device tier (`SystemLanguageModel`,
iOS/macOS 26) keeps working. **You only need the iOS 27 / macOS 27 SDK to
*include* the PCC tier** — for local PCC iteration/testing, or for a deploy
that should ship it (see *Deploy* below). Only `/Applications/Xcode-beta.app`
(Xcode 27.0) has that SDK. Drive it per-command via `DEVELOPER_DIR`, never a
global `xcode-select -switch` (keeps the GUI + everything else on the stable
default):

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test --package-path Packages/LillistCore --parallel --num-workers 2
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' build
```

See the "Issue #51" entry in `docs/engineering-notes.md` for how the two
toolchains were discovered and verified (full `LillistCore`/`LillistUI`
suites + both app builds pass unmodified under the beta), and the "Issue
#70" entry for the compile-gate mechanism and its obsolescence trigger
(delete the `_version: 2` gates once the default Xcode ships the 27 SDK).

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

**Shared schemes are git-ignored, not committed** (`.gitignore`:
`**/*.xcodeproj/xcshareddata/xcschemes/*.xcscheme`). xcodegen writes the scheme's
`BuildableName` from the target name (`Lillist-{iOS,macOS}.app`) while
`xcodebuild archive` rewrites it to the real product (`Lillist.app`, since
`PRODUCT_NAME = Lillist`), so a *committed* scheme flip-flopped on every deploy.
`xcodegen generate` runs before every CI build/test and every `/deployit`
archive, so the configured scheme (Archive build-number pre-action +
`RECORD_SNAPSHOTS` env var) is always present when needed — but **run `xcodegen
generate` before opening the workspace in Xcode's GUI**, or Xcode falls back to
an auto-generated scheme lacking those settings.

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

Starting with the agentic-search feature (#51), the `cli`, `ios`, `macos`,
and `release-archive-smoke` jobs select an **Xcode 27 (beta) toolchain when
present, falling back to 26.3 otherwise**, so the PCC search tier's path
still gets exercised when a 27 runner is available. As of #70 the fallback
is no longer a failure: `FoundationModels.PrivateCloudComputeLanguageModel`
is compile-gated (`#if canImport(FoundationModels, _version: 2)`), so 26.3
compiles green with the PCC tier gated out and the on-device tier still
built/tested. The `spm` job (LillistCore/LillistUI) and `project-drift` job
are unaffected — neither package depends on `LillistSearchIntelligence`. See
"Two Xcode toolchains" above and the "Issue #51"/"Issue #70" entries in
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

**Signing identity & keychain.** The signing certificates live in the
**login keychain** — `Apple Development: Michael Ward (39D9SZ7GT8)` for
Development-signed builds (CloudKit Development; `/deployit` OTA test
installs) and `Developer ID Application: Michael Ward (VMY8R4T742)` for
the Developer-ID macOS distribution build. The login keychain is the
**single** signing keychain used from **every** path: GUI Xcode, headless
`xcodebuild` over SSH/mosh, and `/deployit`. It's set `no-timeout`, so it
stays unlocked for headless SSH/mosh signing without a separate "build"
keychain. CI signs nothing — it builds with
`CODE_SIGNING_ALLOWED=NO`. **Do not add a second keychain ahead of
`login.keychain-db`** in the `security list-keychains -d user` search
list: a signing keychain placed first shadows the login identity and makes
GUI Xcode prompt for that keychain's password (while still appearing to
"work" over SSH if it happens to be unlocked there). The search list
should read only `login.keychain-db` + `System.keychain`.

## CloudKit / iCloud sync environment

`NSPersistentCloudKitContainer` mirrors to one **private** CloudKit
database in container **`iCloud.app.lillist`** (single custom
zone). Container ID + database scope are set in
`PersistenceController.makeStoreDescription` and
`StoreConfiguration.defaultCloudKitContainerIdentifier`. All targets
share App Group `group.app.lillist`. iOS and macOS share the
same bundle ID (`app.lillist`) and App ID (Push + CloudKit
enabled on it).

**The hard-won rule: CloudKit environment follows the distribution
channel, not the build config.** Development-signed builds talk to the
**Development** CloudKit environment; **Ad-Hoc** / Developer-ID / App Store /
TestFlight builds talk to **Production**. Both `/deployit` channels must agree
on the environment or they split into two databases that never sync.
`xcodebuild -exportArchive` **re-stamps both
`com.apple.developer.icloud-container-environment` *and* the push entitlement
from the export profile/options** — so the source `.entitlements` values are
*cosmetic for exported builds* and govern only local Xcode-run builds. **Always
verify the signed binary, never the source `.entitlements`:** `codesign -d
--entitlements :- <app> | plutil -p - | grep -iE
'icloud-container-environment|aps-environment'`.

**Posture — PRODUCTION (cutover completed 2026-06-24).** Both `/deployit`
channels are on the **Production** CloudKit database (schema deployed
Development→Production in the Console). **Local Xcode-run builds
(Apple-Development-signed) stay on Development** — the source entitlements are
unchanged; only the distribution *exports* flip to Production. Develop against
Development, ship against Production.

- **iOS** (`.deployit/ExportOptions.ios.plist`): `method = ad-hoc` →
  Apple-Distribution-signed → **Production** CloudKit. Verified signed binary:
  `aps-environment = production`, `icloud-container-environment = Production`
  (main app + Share/Shortcuts extensions). Installs OTA on **registered
  devices** (UDIDs in the "Lillist Ad Hoc Distribution" profile) — the
  Tailscale OTA flow is unchanged. `-allowProvisioningUpdates` auto-generates
  the ad-hoc profiles for the extensions.
- **macOS** (`.deployit/ExportOptions.macos.plist`): `method = developer-id` +
  **notarized** → **Production** CloudKit. Verified signed binary:
  `icloud-container-environment = Production`, Developer-ID-Application-signed.
  Runs on **any** Mac past Gatekeeper (notarized — no per-Mac registration);
  `/deployit` publishes a stapled GitHub release (no `--no-release`).
  Notarization is driven by deployit `config.toml` (`[macos] notarize = true`,
  `notary_profile = "lillist-notary"`; one-time `xcrun notarytool
  store-credentials "lillist-notary" --apple-id … --team-id VMY8R4T742
  --password <app-specific>`).
- **macOS push entitlement — FIXED (2026-06-24).** macOS uses
  `com.apple.developer.aps-environment` (prefixed), not the iOS
  `aps-environment`. The macOS source declared the iOS key, so it was silently
  stripped and the build carried no push. Correcting the key in
  `Apps/Lillist-macOS/Lillist.entitlements` (value `development`) was the whole
  fix: automatic signing + `-allowProvisioningUpdates` regenerated the
  Developer-ID profile *with* push (App ID already had the capability) and the
  export re-stamps to `production`. Verified on the signed binary. No profile
  pinning or portal action was needed — kept on automatic signing.

**The CloudKit schema is deployed to Production** (2026-06-24; permanent,
additive-only). `NSPersistentCloudKitContainer` auto-creates schema only in
*Development*, so any **new** record types/fields must be exercised on a
Development build first and then re-deployed Development→Production in the
Console before a Production build can use them. `CloudKitSchemaInitializer` is
DEBUG-only and is *not* wired into launch.

**Sync status is real, not a stub.** `CloudKitSyncStatusAdapter`
(LillistUI `Status/`) bridges `LillistCore.SyncStatusMonitor` /
`CloudKitEventBridge` (fed by `eventChangedNotification`) onto the UI's
`SyncIndicatorMonitor`; both apps call `syncMonitor.start()` in
`bootstrap()`. Account-level pauses are overlaid separately by
`pauseReason` ahead of the indicator. (The old `IdleSyncIndicatorMonitor`
that always reported "synced just now" survives only for previews/tours.)

**Production cutover — DONE (2026-06-24).** Schema deployed
Development→Production; `.deployit/ExportOptions.ios.plist` = `ad-hoc` (Apple
Distribution), `.deployit/ExportOptions.macos.plist` = `developer-id` +
notarized; both verified on the signed binary as `icloud-container-environment
= Production`. Production started empty (data re-seeds on-device). Remaining for
an eventual public ship: move iOS from Ad-Hoc to **TestFlight/App Store** (also
Production, no device registration) and the macOS Developer-ID build is already
shippable. macOS Developer-ID builds cannot use Development — never re-attempt
that pin.

## Sparkle auto-update (macOS)

The macOS app's Sparkle updater (`SPUStandardUpdaterController`, "Check for
Updates…" menu item) reads `SUFeedURL` from `Info.plist`, resolved from
`Apps/Config/Distribution.xcconfig`'s **pinned** `SU_FEED_URL` — a public
`https://github.com/mikeydotio/lillist/releases/latest/download/appcast.xml`.
There is **no per-machine override** for this value (unlike
`LOCAL_CONTACT_EMAIL`) — every distributed build must ship the same public
feed; see the issue #55 entry in `docs/engineering-notes.md` (2026-07-20) for
why a per-machine override previously leaked a private tailnet feed into
Developer-ID exports.

- **Build number is a dedicated, monotonic counter.** Sparkle decides
  "newer" purely by `CFBundleVersion`. macOS uses its own
  `Apps/Config/BuildNumber-macOS.xcconfig` (bumped by the `Lillist-macOS`
  scheme's Archive pre-action), separate from iOS's `BuildNumber.xcconfig` —
  never point one platform's `Info.plist` at the other's counter, and never
  hardcode `CFBundleVersion` to a literal (it must always read
  `$(CURRENT_PROJECT_VERSION)`).
- **Sandboxed installer path.** `Info.plist` sets
  `SUEnableInstallerLauncherService`; `Lillist.entitlements` carries the
  `com.apple.security.temporary-exception.mach-lookup.global-name` exception
  Sparkle's `Installer.xpc` needs under App Sandbox. `Installer.xpc` /
  `Downloader.xpc` embed automatically from the Sparkle SPM package — no
  Copy Files build phase needed.
- **CI guard:** `Tools/CI/check-macos-sparkle-feed.sh` (wired into the
  `macos` job) fails the build if `SU_FEED_URL` ever resolves to anything
  but a public GitHub URL, or if `CFBundleVersion` isn't the live
  `$(CURRENT_PROJECT_VERSION)` variable.
- **The appcast itself is published by `deployit`, not this repo** — tracked
  as `mikeydotio/agentics#111`. Until that lands, `SU_FEED_URL` is correct
  but 404s; full end-to-end update verification needs both halves shipped
  together from `main`.

## Deploy (iOS test builds)

Deployment is handled by the **`deployit` plugin** (`/deployit`),
which replaced the previous in-repo `Tools/Deploy/deploy-ios.sh` on
2026-05-23. It does the same job — archive `Lillist-iOS`, export an
**Ad-Hoc** (Apple-Distribution-signed) `.ipa` → **Production** CloudKit, stage
it under `$HOME/Library/Application Support/deployit/serve/`, and point you at
a Tailscale-served landing URL — plus it indexes every build into the
shared `mikeydotio/deployit-index` repo so deploys are visible across
machines. Round-trip is still ~3–5 min and the `.ipa` never leaves the
contributor's tailnet.

**Required (per-contributor):**

- `Apps/Config/Signing.local.xcconfig` populated (see *Code signing*).
- The target iPhone's UDID is in the team's **Ad-Hoc** provisioning
  profile — i.e., the device has been used with Xcode on this team
  at least once. Development-method signing installs OTA on
  registered devices without Ad-Hoc.
- Run `/deployit bootstrap` once on each Mac. The plugin owns its
  Tailscale Serve config and the localhost HTTP backend on
  `127.0.0.1:8729`; no shell-rc env vars are required.
- An Xcode install with the iOS/macOS 27 SDK (currently
  `/Applications/Xcode-beta.app`). Not a manual step at deploy time — see
  below.

**Toolchain — no hand-set `DEVELOPER_DIR` needed.** The repo's
`.deployit/config.toml` pins `[toolchain] min_sdk = "27"`
(`mikeydotio/agentics#116`), so `/deployit deploy` resolves the newest
matching `/Applications/Xcode*.app` itself and fails loudly, before
archiving, if none satisfies it. This matters because of #70's compile-gate:
`Packages/LillistSearchIntelligence`'s Private Cloud Compute search tier now
compiles out cleanly on the default Xcode 26.x SDK (see *Two Xcode
toolchains* above), which means an **unpinned** deploy would *build
successfully but silently ship without the PCC tier* — a build failure
would have been safer than that. The pin exists specifically to prevent it;
don't remove it without confirming the default Xcode ships the 27 SDK (see
the "Issue #70" entry in `docs/engineering-notes.md` for the obsolescence
trigger).

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

Solo project, but **`main` is PR-only**: the org-wide `mikeydotio`
`protect-main` ruleset rejects direct pushes (and force-pushes and
`main` deletion), so *every* change — even a one-line release-bookkeeping
commit — reaches `main` through a PR. No external review is performed;
you land your own completed, tested work end-to-end: branch → HTTPS push
→ open PR (`Closes #N` where it applies) → **merge commit** (squash and
rebase-merge are disabled org-wide) → verify the merge → delete the
branch. Tags are *not* branch-protected and push directly. Use
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

## Widgets — COMPLETE (2026-07-01)

Configurable WidgetKit widget (iOS + macOS) showing a saved smart filter's
tasks: rainbow-bordered dark card, header (filter name + done-progress ring +
remaining count), status-glyph rows, "+" quick-add; all system families +
iOS Lock Screen accessories. Interactive: tap a row's circle to complete it in
place; "+" opens Quick Capture; whole-widget tap opens the filter.

- **Target:** `Extensions/LillistWidget/` — one shared source dir compiled into
  both the `LillistWidget` (iOS) and `LillistWidget-macOS` app-extension targets
  (macOS's *first* extension). Bundle id `app.lillist.Widget`.
- **Data:** snapshot-cache (`LillistCore/Widgets/` — `WidgetSnapshot`,
  `WidgetSnapshotStore`, `WidgetSnapshotBuilder`, pure Foundation). The app +
  writing extensions regenerate `<AppGroup>/Widget/**` on store changes and call
  `WidgetCenter.reloadAllTimelines()`; the timeline provider only reads the JSON.
- **Views:** `LillistUI/Widgets/` (WidgetKit-free, snapshot-tested via the macOS
  host harness — `WidgetFilterCardSnapshotTests`).
- **Deep links:** `lillist://` (`quickcapture` / `filter/<id>` / `task/<id>`),
  parsed by `LillistCore` `DeepLink`.
- **Gotchas** (see engineering-notes 2026-07-01): never `import WidgetKit` in
  LillistCore (CLI link); fonts are process-scoped (`registerIfNeeded()` in the
  bundle init); glass doesn't render in widgets (solid fills + rainbow stroke +
  `.contentMarginsDisabled()`); the macOS widget overrides
  `CURRENT_PROJECT_VERSION` to match the app's hardcoded CFBundleVersion; the new
  `app.lillist.Widget` App ID needs a provisioning profile before any *signed*
  device/desktop build (simulator + unsigned are fine).

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

<!-- BEGIN STORYHOOK -->
## Storyhook

This project uses **storyhook** for task tracking. Full usage instructions are in `.storyhook/CLAUDE.md` — read that file before starting work.

Quick start: run `story load-context` at session start, `story next` to pick a task.

Run `story help <command>` for detailed usage on any command, or `story help --compact` for the full reference.
<!-- END STORYHOOK -->
