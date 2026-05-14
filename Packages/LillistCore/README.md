# LillistCore

The model + persistence + business-logic core of Lillist. Shared by every client (macOS app, iOS app, CLI).

## Plan 1 scope

Plan 1 establishes local-only persistence (`NSPersistentContainer`) with:

- `LillistTask` / `Tag` / `JournalEntry` / `Attachment` / `AppPreferences` entities
- `TaskStore`, `TagStore`, `JournalStore`, `AttachmentStore`, `PreferencesStore`
- Soft delete + Trash + `AutoPurgeJob`
- Cycle prevention for task and tag re-parenting
- Sibling-name uniqueness with auto-suffix collisions
- Fractional sibling ordering with `FractionalPosition` + `PositionCompactor`
- JSON + assets folder export via `Exporter`

Plan 2 swaps `NSPersistentContainer` for `NSPersistentCloudKitContainer`; no public-API changes.

## Build tool plugin

SwiftPM does not invoke Core Data's `momc` model compiler on `.xcdatamodeld`
resources, so the package ships a `CompileCoreDataModel` build tool plugin
that shells out to `xcrun momc`. The plugin runs automatically as part of
`swift build` / `swift test`; no extra setup needed.

The `.xcdatamodeld` entities are marked `codeGenerationType="manual/none"`
because we hand-write the `NSManagedObject` subclasses under
`Sources/LillistCore/ManagedObjects/` — SwiftPM doesn't run Core Data's
"Class Definition" codegen either, so opening the model in Xcode must not
re-generate them.

## Running tests

```bash
cd Packages/LillistCore
swift test
```

## Public API

All entry points return value-type `*Record` DTOs. No `NSManagedObject` escapes the package.

## Plan 10 scope

Plan 10 adds first-launch onboarding and pre-installed defaults, plus the
cross-platform Preferences/Settings UIs.

- `Onboarding/OnboardingState` — reads/writes `hasCompletedOnboarding` on `AppPreferences`.
- `Onboarding/DefaultsInstaller` — idempotent wrapper around `SmartFilterStore.installDefaultsIfNeeded()` (Plan 7); installs five default smart filters: Today, This Week, No Tags, Recently Closed, Stale.
- `PreferencesStore.Prefs` gains `hasCompletedOnboarding`, `quickCaptureEnabled`, `quickCaptureHotkey`, `statusBarItemVisible`, `defaultTagTintHex`. (`crashPromptsEnabled` is already present from Plan 9 and is bound by the Settings UI's crash-reporting toggle.)
- `NotificationPermissions.AuthorizationStatus` gains a third case `.notDetermined`, and a new `currentStatus()` method exposes the authorization snapshot without prompting.
- macOS app: `Settings { … }` scene with six panes (General, Notifications, Trash, Quick Capture, Crash Reporting, Advanced). Onboarding presented as a sheet on first launch.
- iOS app: `SettingsTab` with parallel sections (Quick Capture diverges to the Shortcuts app per design Section 7). Onboarding presented as a full-screen cover on first launch. A gear-icon entry point lives on every NavigationStack tab in `TabShell` and on the sidebar in `SplitShell`.
- `AccountStateMonitor` is now wired into both apps' `AppEnvironment` so the onboarding iCloud gate has a live observable signal.
- Empty tag tree by design: no pre-installed tags.

See design Section 7 ("Onboarding" and "Pre-installed defaults") and Section 4 ("Permissions").
