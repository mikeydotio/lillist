# Lillist — Project Conventions

Repo-scoped guidance for Claude Code and humans. User-global rules live in
`~/.claude/CLAUDE.md`; this file adds only Lillist-specific knowledge.

## What Lillist is

Task manager for macOS + iOS, with a `lillist` CLI. Apple-platform-only:
Swift 6, SwiftUI, Core Data via `NSPersistentCloudKitContainer`, CloudKit
sync. Features include a predicate-driven smart-filter engine, recurrence,
notifications, journal, attachments, an iOS Share Extension + App Intents
extension, and crash reporting.

## Topology

- **`Packages/LillistCore/`** — data model, stores, notification
  scheduler, recurrence expander, predicate engine, crash reporter, CLI
  handlers. All public APIs return value-type DTOs. Strict concurrency
  on the source target.
- **`Packages/LillistUI/`** — cross-platform SwiftUI library shared by
  both apps. Design tokens (`Theme/Tokens.swift`), accessibility
  helpers, Quick Capture parser, recurrence editor, status surfaces,
  the iOS Tab Screens at `iOS/Screens/<Tab>Screen.swift`, snapshot
  tests at `Tests/LillistUITests/`.
- **`Apps/Lillist-macOS/`** — macOS shell (`RootSplitView`, command
  menu, Preferences scene, AppDelegate window management).
- **`Apps/Lillist-iOS/`** — `AppEnvironment`, the `TabShell` (compact) /
  `SplitShell` (regular) shells, thin per-tab wrappers around LillistUI
  Screens, Settings sub-sections, Share Extension, App Intents
  extension. All extensions share App Group
  `group.io.mikeydotio.Lillist`.
- **CLI** — `lillist` target under `Packages/LillistCore`,
  `swift-argument-parser`-based; handlers thin-wrap stores.

## Design and history

- **Design doc:** `docs/plans/2026-05-12-lillist-design.md`. Section
  numbers are the canonical reference for product behavior.
- **Engineering notes:** `docs/engineering-notes.md`. Append-only log of
  non-obvious gotchas — concurrency surprises, framework-shape issues,
  cross-cutting patterns. Add an entry when a future contributor would
  otherwise rediscover the lesson the hard way. Don't put bug-fix
  details (commit message has those), code patterns (the code shows
  those), or feature decisions (the design doc captures those).
- **Past plans:** `docs/superpowers/plans/`. Historical record of how
  features landed (Plans 1–20 plus 20a are complete). Useful as
  archaeology — *not* the current source of truth.

## Build & test

```bash
# LillistCore and LillistUI on the host platform (macOS):
swift test --package-path Packages/LillistCore
swift test --package-path Packages/LillistUI   # iOS-only #if blocks compile out

# iOS-only tests (iOSSnapshotTests, IOSScreenTourTests):
xcodebuild test -workspace Lillist.xcworkspace \
  -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'

# App-target builds without code signing (Claude Code can't sign):
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-{iOS,macOS} \
  -destination '<see above>' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

**iPhone 17 + iOS 26.2 is the canonical snapshot baseline pin.** Re-record on
the same destination so diffs stay device-neutral.

After moving/deleting source files, regenerate the matching pbxproj:
```bash
(cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .)
(cd Apps            && xcodegen generate --spec project.yml --project .)
```

## House rules

- **Treat build warnings as errors.** Across SPM and Xcode targets. Fix
  warnings at the architecture level — don't paper over them with
  attribute or pragma noise.
- **Follow SOLID, DRY, YAGNI, separation of concerns.** You are an excellent engineer. Write software that we can be truly proud of publishing.
- **Read a file before a fresh set of edits** It may have moved or been edited by the user since the last visit.
- **Never force-push without explicit user permission on a per-case basis.**
- **Write robust tests designed to enforce high quality standards.** The job of tests is not to pass. The job of tests is to hold us accountable to writing excellent and defect-resistant software, and if the tests are poorly designed or give us a false sense of success, then we have failed our task.

## Code conventions

### Data layer

- **Hand-written `@NSManaged` subclasses.** Every Core Data entity has a
  hand-written `@objc(Name) public final class Name: NSManagedObject {
  @NSManaged … }` in
  `Packages/LillistCore/Sources/LillistCore/ManagedObjects/`. Do not
  rely on Core Data's class codegen.
- **No `NSManagedObject` escapes `LillistCore`.** Public store APIs
  return value-type DTOs (`TaskStore.TaskRecord`,
  `SeriesStore.SeriesRecord`, `SmartFilterStore.SmartFilterRecord`, …).
  Tests and downstream layers never see Core Data types.
- **Every public DTO needs an explicit public `init`.** Swift's
  synthesized memberwise init is internal-only even when all fields are
  public — write the init by hand so callers outside the defining
  module can construct mocks.
- **Date math through `Calendar`, not `Date.addingTimeInterval`.**
  `RecurrenceExpander` is the canonical example: DST and month-length
  correctness require `Calendar.date(byAdding:)` and `DateComponents`
  round-trips. The only `addingTimeInterval` callsite in the recurrence
  engine is the `afterCompletion` rule, which is *defined* in absolute
  seconds.

### UI layer

- **iOS Tab screens use a container/presenter split.** The five primary
  iOS surfaces (Today, AllTags, FiltersList, Search, Settings) compose
  their bodies in
  `Packages/LillistUI/Sources/LillistUI/iOS/Screens/<Tab>Screen.swift`
  as **pure presentation** — data and action closures in via `init`, no
  `@State`, no `.task`. The corresponding
  `Apps/Lillist-iOS/Sources/<Tab>/<Tab>View.swift` is a thin wrapper
  that owns `@State`, `.task` lifecycle, `AppEnvironment` reads, and
  `.navigationDestination` handlers (because the destination views
  reference iOS-app types LillistUI can't import). This split lets
  `IOSScreenTourTests` render the real screens with frozen mock data.
- **Settings is a chrome-only split.**
  `LillistUI.SettingsScreen<SectionsContent: View>` owns the
  `NavigationStack + Form + title + Done` chrome; the env-coupled
  sections (General, Notifications, Trash, QuickCapture, CrashReporting,
  Advanced) stay in the iOS app target where their `AppEnvironment`
  dependencies live. The app target passes sections via a ViewBuilder;
  tour tests pass mock placeholders.
- **`@MainActor` on SwiftUI Views ripples to static helpers.** Pure
  value-math hung off a `View` should be `public nonisolated static func`
  so non-MainActor callers (XCTestCase, background tasks) can use it
  without crossing the isolation boundary.
- **Cross-platform user-visible strings must match verbatim.** If you
  touch a welcome line, error message, or tagline on one platform, sync
  the other in the same change. Snapshot tests guard the visible
  surface.
- **`Text(LocalizedStringKey)` auto-link detection is literal-only.**
  Markdown auto-links fire on compile-time string literals;
  interpolated values render as plain text. Spell links explicitly —
  `[\(addr)](mailto:\(addr))` — to survive `\(interpolation)`.

### Cross-cutting

- **Strict concurrency on LillistCore source target; tests are not
  strict.** Concurrency bugs can surface at runtime without a
  compile-time warning. Don't treat a clean test build as proof of
  correctness — add stress repetitions for any code crossing actor
  boundaries.

## Build-plugin caching gotcha

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

`Apps/Config/` holds an xcconfig indirection that keeps the team ID out
of the pbxproj:

- `Signing.xcconfig` — committed scaffold. Contains
  `#include? "Signing.local.xcconfig"` and
  `DEVELOPMENT_TEAM = $(LOCAL_DEVELOPMENT_TEAM)`. Both `project.yml`s
  reference this via `configFiles:` so it survives every
  `xcodegen generate`.
- `Signing.local.xcconfig` — **gitignored.** Contains the one real
  line: `LOCAL_DEVELOPMENT_TEAM = <your 10-char Team ID>`.
- `Signing.local.xcconfig.example` — committed template; new
  contributors `cp` it to `Signing.local.xcconfig` and fill in the team
  ID (developer.apple.com → Membership → Team ID).

Why the indirection: xcodegen mirrors any resolved `DEVELOPMENT_TEAM`
into the pbxproj's `TargetAttributes.DevelopmentTeam` at generation
time. The `$(LOCAL_DEVELOPMENT_TEAM)` placeholder is literal to
xcodegen but resolves at build time via the `#include?` chain — so the
pbxproj only ever contains the placeholder, and `xcodegen generate` is
idempotent.

Never put `DEVELOPMENT_TEAM` in `project.yml`'s `settings: base:` —
that would leak the team ID into pbxproj and wipe out the indirection.
`CODE_SIGN_STYLE: Automatic` is fine in `project.yml`.

## Git workflow

- Branch off `main`, PR back to `main`. Repo lives under the
  `mikeydotio` GitHub org.
- Land work as a series of small, focused commits using
  conventional-commit prefixes: `feat:`, `fix:`, `refactor:`, `test:`,
  `docs:`, `chore:`.
- Push over HTTPS (the user's SSH agent requires interactive approval):
  ```bash
  git -c url."https://github.com/".insteadOf="git@github.com:" push origin <branch>
  ```
- Never force-push without explicit confirmation.

## When in doubt

1. Check `docs/engineering-notes.md` for a known gotcha.
2. Check the design doc at `docs/plans/2026-05-12-lillist-design.md`.
3. Past plans under `docs/superpowers/plans/` are historical reference
   only — they show how features landed but are not the current source
   of truth.
4. Ask.
