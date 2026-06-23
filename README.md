# Lillist

A task manager for macOS and iOS, with a `lillist` command-line companion.
Apple-only: Swift 6, SwiftUI, Core Data over `NSPersistentCloudKitContainer`,
and CloudKit sync.

Features include predicate-driven smart filters, recurrence, notifications, a
journal, attachments, an iOS Share Extension, an App Intents (Shortcuts)
extension, and an in-house, opt-in, user-mediated crash reporter.

> [!WARNING]
> **🚧 Early alpha — NOT production ready.** Lillist is under active
> development. Expect bugs, breaking changes, incomplete features, and
> **data loss**. Don't rely on it for anything you can't afford to lose, and
> keep your own independent backups.
>
> **Even iCloud sync uses the CloudKit _Development_ (Debug) environment — not
> Production.** Concretely:
>
> - Your data lives in the app's **development** CloudKit database — a sandbox
>   that can be **reset or wiped at any time** (including by the maintainers
>   during schema changes).
> - Only **development-signed builds** sync together — local `xcodebuild`/Xcode
>   Debug builds and the Developer-ID test builds distributed via `deployit`.
>   A future App Store / TestFlight (Production) build will **not** see this
>   data, and there is **no migration path** from Development to Production yet.

## Architecture

Four layers, lower depends on nothing above it:

- **`Packages/LillistCore`** — data model, stores, notification scheduler,
  recurrence expander, predicate engine, crash reporter, and the CLI. Public
  APIs return value-type DTOs; no `NSManagedObject` escapes the package.
- **`Packages/LillistUI`** — cross-platform SwiftUI library shared by both
  apps (design tokens, Quick Capture parser, recurrence editor, screens).
- **`Apps/Lillist-macOS`** and **`Apps/Lillist-iOS`** — the platform shells.
- **`Extensions/`** — the Share Extension and Shortcuts (App Intents) actions.

## Building

The Xcode projects are generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from the `project.yml` specs. Signing values are kept out of the repository
via an xcconfig indirection — copy the template and fill in your Apple
Developer Team ID:

```bash
cp Apps/Config/Signing.local.xcconfig.example Apps/Config/Signing.local.xcconfig
# then set LOCAL_DEVELOPMENT_TEAM to your 10-character Team ID
```

Build and test the packages on the host:

```bash
swift test --package-path Packages/LillistCore
swift test --package-path Packages/LillistUI
```

Build the apps (unsigned is fine without certificates):

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' build
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build
```

## Configuration

Two values are neutral by default so the public build ships no personal or
private data; set them per-machine in the gitignored
`Apps/Config/Signing.local.xcconfig` (see the template for both):

- `LOCAL_CONTACT_EMAIL` — the address crash reports are emailed to. Empty by
  default; when unset, the crash-report UI hides its email affordances.
- `LOCAL_SU_FEED_URL` — the Sparkle auto-update appcast feed (macOS). Defaults
  to a GitHub Releases-hosted appcast.

## License

Lillist is released under the [MIT License](LICENSE).

Third-party components (Swift Argument Parser, Sparkle, the Plus Jakarta Sans
font, and the test-only Point-Free libraries) retain their own permissive
licenses; see [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) for the full
attribution.
