# Lillist Plan 10 — Onboarding and Preferences Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the first-launch onboarding experience and the cross-platform preferences/settings UI for Lillist, and idempotently install the pre-installed default smart filters described in design Section 7 ("Onboarding" and "Pre-installed defaults"). The result: a brand-new user opens Lillist (macOS or iOS), sees a single intro screen explaining iCloud/notifications/quick-capture, optionally grants notification permission inline, and lands in an app that already has the five default smart filters ready to use. They can then visit Settings/Preferences to tune defaults.

**Architecture:** A small `OnboardingState` actor in `LillistCore` reads/writes `AppPreferences.hasCompletedOnboarding` via the existing `PreferencesStore` (Plan 1). A `DefaultsInstaller` (also in `LillistCore`) idempotently installs the five default smart filters by name. The macOS app gates its main window with a `.sheet` driven by `OnboardingState`; the iOS app uses a full-screen cover on the root view. iCloud gating reuses Plan 2's `AccountStateMonitor`. Notification permission flows through Plan 5's `NotificationPermissions`. Preferences UIs are SwiftUI `Settings { … }` panes on macOS and a `Form`-based `SettingsTab` on iOS, both reading/writing through `PreferencesStore`. Snapshot tests gate visual regressions; unit tests pin first-launch detection and `DefaultsInstaller` idempotency.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing for `LillistCore` tests, XCTest + `pointfreeco/swift-snapshot-testing` for UI snapshot tests, AppKit `NSWorkspace` (macOS) and `UIApplication.openSettingsURLString` (iOS) for the Settings deep-link fallback.

**Depends on:** Plan 1 (`PreferencesStore`, `AppPreferences`, `SmartFilter` entity), Plan 2 (`AccountStateMonitor`), Plan 3 (`Predicate`, `PredicateGroup`, `Field`, `SmartFilterStore`), Plan 5 (`NotificationPermissions`), Plan 7 (macOS app shell, `Settings { … }` scene host), Plan 8 (iOS app shell, root view, Today filter wiring).

> **Plan 5 deviations baked in:**
>
> 1. **`NotificationPermissions.currentStatus()` does not exist in landed Plan 5** — only `requestAuthorization()` is shipped (it returns `.authorized | .denied`, mapping framework errors to `.denied` for graceful degradation). This plan's four call sites of `currentStatus()` need a new method on `NotificationPermissions` that queries `center.notificationSettings().authorizationStatus` without prompting. Expanding to support `.notDetermined` requires also expanding `NotificationPermissions.AuthorizationStatus` (currently a two-case enum). **Owner**: add as Plan 10 Task 0 ("Extend `NotificationPermissions` with `currentStatus()` and a `.notDetermined` case") before any UI task that calls it, and add corresponding `FakeUserNotificationCenter` plumbing — the existing fake's `notificationSettings()` is a deliberate `fatalError` because `UNNotificationSettings` is not constructible outside the framework, so the fake will need a controllable-status backdoor (e.g. an `authorizationStatusOverride: UNAuthorizationStatus` property the fake returns directly from a new `currentAuthorizationStatus()` protocol method that `NotificationPermissions.currentStatus()` calls instead of `notificationSettings()`).
> 2. **Preference-change → scheduler wiring.** When the user changes `AppPreferences.defaultAllDayNotificationHour/Minute`, the preferences tab MUST call `await env.notificationScheduler.updateDefaultAllDayTime(hour:minute:)`. When `morningSummaryEnabled` toggles or its hour/minute changes, call `await env.notificationScheduler.installMorningSummary(hour:minute:)` (enabled-true) or `await env.notificationScheduler.uninstallMorningSummary()` (enabled-false). The preferences pane already passes `env` (Plan 7/8); this plan adds the `Task { await … }` hooks in the setter paths.
> 3. **Existing preference attributes are already present.** Plan 1 landed `defaultAllDayNotificationHour/Minute`, `morningSummaryEnabled/Hour/Minute`, and `trashRetentionDays` on `AppPreferences`. Task 1's "extend AppPreferences" step adds only the *new* fields this plan introduces — re-check the current `AppPreferences+CoreData.swift` and `LillistModel.xcdatamodeld/contents` before editing to avoid duplicate `@NSManaged` declarations.

---

## File Structure

```
Lillist/
├── Packages/
│   └── LillistCore/
│       ├── Sources/
│       │   └── LillistCore/
│       │       ├── Model/
│       │       │   └── LillistModel.xcdatamodeld/
│       │       │       └── LillistModel.xcdatamodel/
│       │       │           └── contents                       (extend AppPreferences)
│       │       ├── Onboarding/
│       │       │   ├── OnboardingState.swift                  (NEW)
│       │       │   └── DefaultsInstaller.swift                (NEW)
│       │       └── Stores/
│       │           └── PreferencesStore.swift                 (extend Prefs)
│       └── Tests/
│           └── LillistCoreTests/
│               └── Onboarding/
│                   ├── OnboardingStateTests.swift             (NEW)
│                   └── DefaultsInstallerTests.swift           (NEW)
├── Apps/
│   ├── Lillist-macOS/
│   │   └── Lillist-macOS/
│   │       ├── App/
│   │       │   └── LillistMacApp.swift                        (extend — Settings scene + onboarding sheet)
│   │       ├── Onboarding/
│   │       │   ├── OnboardingSheet.swift                      (NEW)
│   │       │   └── ICloudRequiredView.swift                   (NEW)
│   │       └── Preferences/
│   │           ├── PreferencesWindow.swift                    (NEW — Settings scene root)
│   │           ├── GeneralPane.swift                          (NEW)
│   │           ├── NotificationsPane.swift                    (NEW)
│   │           ├── TrashPane.swift                            (NEW)
│   │           ├── QuickCapturePane.swift                     (NEW)
│   │           ├── CrashReportingPane.swift                   (NEW)
│   │           └── AdvancedPane.swift                         (NEW)
│   └── Lillist-iOS/
│       └── Lillist-iOS/
│           ├── App/
│           │   └── LillistIOSApp.swift                        (extend — onboarding cover + settings entry)
│           ├── Onboarding/
│           │   ├── OnboardingScreen.swift                     (NEW)
│           │   └── ICloudRequiredScreen.swift                 (NEW)
│           └── Settings/
│               ├── SettingsTab.swift                          (NEW)
│               ├── GeneralSection.swift                       (NEW)
│               ├── NotificationsSection.swift                 (NEW)
│               ├── TrashSection.swift                         (NEW)
│               ├── QuickCaptureSection.swift                  (NEW)
│               ├── CrashReportingSection.swift                (NEW)
│               └── AdvancedSection.swift                      (NEW)
└── Tests/
    ├── Lillist-macOSTests/
    │   ├── OnboardingSheetSnapshotTests.swift                 (NEW)
    │   ├── PreferencesPaneSnapshotTests.swift                 (NEW)
    │   └── NotificationPermissionFlowTests.swift              (NEW)
    └── Lillist-iOSTests/
        ├── OnboardingScreenSnapshotTests.swift                (NEW)
        ├── SettingsTabSnapshotTests.swift                     (NEW)
        └── NotificationPermissionFlowTests.swift              (NEW)
```

---

## Notes for the Implementer

**Idempotency is the hill to die on.** `DefaultsInstaller.installIfNeeded()` runs on every cold launch (cheap) — never *every* launch path should produce duplicates. Tests assert "invoke twice; exactly N filters."

**Plan 3 follow-up callout.** The "No Tags" default filter needs a way to express "task has zero tags." Per design Section 5, the `tag` field has `includesAny / includesAll / excludesAll` only. We introduce a new boolean Field, `hasTags`, with `is` operator. If Plan 3 hasn't landed `hasTags` in `Field` yet, the installer file documents this as a hard prerequisite, and Task 5 of this plan adds `hasTags` to `Field` (with a one-line note: this should ideally live in Plan 3 — log a Plan 3 follow-up if it's missing).

**Onboarding gates.** Onboarding only appears when `hasCompletedOnboarding == false`. After Step 4 of the onboarding sheet, we flip the flag *and* invoke `DefaultsInstaller.installIfNeeded()`. Crash between flag-write and installer-run is harmless: installer is idempotent and may also run from `LillistMacApp.init` (background `Task`) as a safety net.

**iCloud-required gate.** When iCloud is not usable, the onboarding sheet content is replaced with the iCloud-required screen (design Section 8). Onboarding cannot complete until iCloud is available again. We *do* let the user dismiss the iCloud screen with "Try again" and "Open Settings" affordances; we don't trap them.

> **Plan 2 deviation note (added retroactively).** The shipped Plan 2 API does
> **not** include `AccountStateMonitor.state` or an `iCloudAccountState.unavailable`
> case. The real shape is:
>
> - Property is `currentState: iCloudAccountState` (read off the actor with
>   `await accountMonitor.currentState`).
> - Cases are `.available`, `.noAccount`, `.restricted`, `.accountChanged`.
> - "iCloud unusable" = `currentState == .noAccount || currentState == .restricted`.
>   `.accountChanged` is a separate flow that goes through `QuarantineManager`
>   (design Section 8), not the same screen.
>
> When implementing the gate, treat `.noAccount` and `.restricted` as the
> conditions that show the iCloud-required screen. Subscribe via
> `accountMonitor.stateStream` for live updates (the stream replays the
> current state on subscription so initial state shows immediately).
>
> `AccountStateMonitor` requires explicit provider injection:
> `AccountStateMonitor(provider: CloudKitAccountStatusProvider(container: CKContainer.default()))`.

**Notification permission is non-blocking.** The intro screen has two buttons: "Set up notifications" (calls `NotificationPermissions.requestAuthorization()` inline, then updates a `@State` indicator) and "Get started" (proceeds regardless of permission state). If the request returns `.denied`, we show a Settings deep-link affordance ("Open Settings") and a one-line explanation — but the user can still complete onboarding.

**Preferences live in `PreferencesStore.Prefs`.** Task 2 extends `Prefs` with the fields needed by panes that don't already have a home: `quickCaptureEnabled`, `quickCaptureHotkey` (macOS), `statusBarItemVisible` (macOS), `showPostCrashPrompt` (Plan 9 already added — verify and don't duplicate), `defaultTagTintHex`. The macOS-only fields (hotkey, status-bar) compile on iOS as `Int16`/`Bool` no-ops so we can keep the Core Data schema unified.

**Snapshot tests.** Use `pointfreeco/swift-snapshot-testing` in `precisionMode: 0.99` for non-trivial views (Settings panes have subtle font rendering differences across macOS minor versions). New baselines committed under `Tests/.../__Snapshots__/`. Light + dark variants for every snapshot.

**Quick Capture hotkey recording on macOS** uses a small `HotkeyRecorderView` (NSViewRepresentable wrapping `NSEvent.addLocalMonitorForEvents`). Until Plan 7's actual hotkey registration ships, the recorder writes the configured hotkey to `Prefs` and a `// TODO(Plan 7)` notes where the real `KeyboardShortcutsRegistrar.register(...)` call should go.

**Empty tag tree is explicit.** Nowhere in this plan do we create default tags. The implementer should grep the diff for "default tag" and verify there are zero matches.

**Managed-object class generation — hand-written, not auto-generated.** `AppPreferences+CoreData.swift` is a hand-written `@NSManaged` subclass (see Plan 1 Task 8 and the same convention applied in Plans 3/4). When you add the six new attributes in Task 1, you must add a matching `@NSManaged` line per attribute to that file — the model XML change alone won't expose the properties to Swift, and Task 2's `PreferencesStore` updates won't compile without them. Task 1 below has been updated to include this step.

**Build-plugin caching gotcha.** Plan 7 removed the
`CompileCoreDataModel` SwiftPM build-tool plugin from
`Packages/LillistCore/Package.swift`. Swift 6 / Xcode 17 compile
`.xcdatamodeld` natively via `.process(...)`. The stale-`.momd` failure
mode can still appear when SwiftPM caches by directory mtime — the
`touch` workaround below remains the right fix after any model edit
(silently-masked onboarding flags as `false`, the original symptom,
is still possible):

```bash
touch Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/ \
      Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/
```

**Commits.** Each task ends with a conventional-commit prefix: `feat:`, `test:`, `chore:`, `fix:`, `refactor:`, `docs:`.

> **Plan 7 deviation notes (added retroactively).** Plan 7 established
> conventions and surfaced API realities this plan needs to honor:
>
> - **`PreferencesStore` API**: the actual public surface is
>   `.read() async throws -> Prefs` and `.update { (inout Prefs) -> Void }`.
>   There is no `.fetch()` method. The `Prefs` struct fields are
>   `defaultAllDayHour: Int16`, `defaultAllDayMinute: Int16`,
>   `morningSummaryEnabled: Bool`, `morningSummaryHour: Int16`,
>   `morningSummaryMinute: Int16`, `trashRetentionDays: Int16`,
>   `defaultTaskListSort: SortField`. New onboarding attributes added
>   in Task 1 need matching `@NSManaged` lines in
>   `AppPreferences+CoreData.swift` AND new fields on `Prefs` AND new
>   read/write paths in `PreferencesStore`.
> - **Default smart-filter installer already exists.** Plan 7's
>   `SmartFilterStore.installDefaultsIfNeeded()` (commit `20e7f39`)
>   atomically installs the five Section-7 defaults by name and is
>   idempotent across launches. Plan 10's `DefaultsInstaller` should
>   call into that, not reimplement the predicates. The Plan 7 macOS
>   app already has `Apps/Lillist-macOS/Sources/Defaults/DefaultSmartFiltersInstaller.swift`
>   as the UserDefaults-gated wrapper; mirror that on iOS.
> - **macOS `AppEnvironment` is async**: `static func make() async throws`
>   constructed in `LillistApp`'s `.task` block. Plan 10's onboarding
>   sheet gate keys off `env.preferencesStore.read().hasCompletedOnboarding`,
>   and the env is already loaded by the time the gate evaluates.
> - **macOS `SyncStatusMonitor` collision**: the UI-facing protocol is
>   `LillistUI.SyncIndicatorMonitor` (with stub `IdleSyncIndicatorMonitor`).
>   Plan 10 doesn't touch sync state directly, but anywhere this plan
>   says "SyncStatusMonitor" in the macOS context, it likely means the
>   UI protocol.
> - **Standalone macOS test target**: `Apps/Lillist-macOS/Tests/` is a
>   standalone bundle with `TEST_HOST=""` (no app host). Onboarding /
>   preferences tests in that target must NOT `@testable import
>   Lillist_macOS` — exercise `LillistCore` directly. The same applies
>   to any new iOS test bundle Plan 8 lands.
> - **macOS snapshot tests** wrap SwiftUI views in `NSHostingView` via
>   `makeHostingView(_:size:)` in
>   `Packages/LillistUI/Tests/LillistUITests/Helpers/SnapshotEnvironment.swift`.
>   `swift-snapshot-testing` 1.17 has no macOS SwiftUI `View` strategy.
> - **`XCTAssert` autoclosures don't accept `try await`**: bind to a
>   local first.
> - **`PersistenceController` init is `async throws`** and there is no
>   `.shared`. The macOS `AppEnvironment.make()` produces one; never
>   construct one directly from a view.

**Verification command throughout:**
- For `LillistCore` changes: `cd Packages/LillistCore && swift test`
- For macOS app: `xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS'`
- For iOS app: `xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 16'`

---

## Task 1: Extend `AppPreferences` entity with `hasCompletedOnboarding` and the new pref fields

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`

- [ ] **Step 1: Open the model file**

Read the existing `<entity name="AppPreferences" ...>` block (currently 7 attributes).

- [ ] **Step 2: Add the new attributes**

Edit `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`, replacing the `AppPreferences` entity block:

```xml
    <entity name="AppPreferences" representedClassName="AppPreferences" syncable="YES">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="defaultAllDayNotificationHour" optional="YES" attributeType="Integer 16" defaultValueString="9" usesScalarValueType="YES"/>
        <attribute name="defaultAllDayNotificationMinute" optional="YES" attributeType="Integer 16" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="morningSummaryEnabled" optional="YES" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
        <attribute name="morningSummaryHour" optional="YES" attributeType="Integer 16" defaultValueString="9" usesScalarValueType="YES"/>
        <attribute name="morningSummaryMinute" optional="YES" attributeType="Integer 16" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="trashRetentionDays" optional="YES" attributeType="Integer 16" defaultValueString="30" usesScalarValueType="YES"/>
        <attribute name="defaultTaskListSortRaw" optional="YES" attributeType="String" defaultValueString="manualPosition"/>
        <attribute name="hasCompletedOnboarding" optional="YES" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
        <attribute name="quickCaptureEnabled" optional="YES" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
        <attribute name="quickCaptureHotkey" optional="YES" attributeType="String" defaultValueString="ctrl+opt+space"/>
        <attribute name="statusBarItemVisible" optional="YES" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
        <attribute name="showPostCrashPrompt" optional="YES" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
        <attribute name="defaultTagTintHex" optional="YES" attributeType="String" defaultValueString="#7F8FA6"/>
    </entity>
```

This is an additive, lightweight migration; Core Data infers it.

> **Heads-up: `showPostCrashPrompt` may already exist.** Plan 9 Task 10 adds `crashPromptsEnabled` (singular, default `YES`). The field above is named `showPostCrashPrompt` and defaults to `YES`. These are *not* the same attribute. If Plan 9 has landed, decide which name wins and reconcile here — duplicating the underlying setting under two attribute names will confuse the Settings UI in Task 6+. The preferred resolution is to standardize on Plan 9's `crashPromptsEnabled` and drop `showPostCrashPrompt` from this plan; update Task 6's checklist accordingly.

- [ ] **Step 3: Add matching `@NSManaged` properties to the hand-written `AppPreferences` class**

Open `Packages/LillistCore/Sources/LillistCore/ManagedObjects/AppPreferences+CoreData.swift`. Inside the `AppPreferences` class body, append:

```swift
@NSManaged public var hasCompletedOnboarding: Bool
@NSManaged public var quickCaptureEnabled: Bool
@NSManaged public var quickCaptureHotkey: String?
@NSManaged public var statusBarItemVisible: Bool
@NSManaged public var showPostCrashPrompt: Bool   // (Skip this line if reconciling with Plan 9's crashPromptsEnabled — see note above.)
@NSManaged public var defaultTagTintHex: String?
```

This codebase does not use Core Data's class codegen — see Plan 1 Task 8 for the convention. The XML edit alone won't expose these properties to Swift; the `PreferencesStore` updates in Task 2 will fail to compile until these lines exist.

- [ ] **Step 4: Force the build plugin to pick up the model edit, then build**

```bash
touch Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/ \
      Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/
cd Packages/LillistCore && swift build
```
Expected: build succeeds. (Skip the `touch` and the new attributes will silently read as default zero values — see "Build-plugin caching gotcha" in the preamble.)

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld \
        Packages/LillistCore/Sources/LillistCore/ManagedObjects/AppPreferences+CoreData.swift
git commit -m "feat: extend AppPreferences with onboarding, quick-capture, crash-prompt prefs"
```

---

## Task 2: Extend `PreferencesStore.Prefs` with the new fields and write tests

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift`
- Modify: `Packages/LillistCore/Tests/LillistCoreTests/Stores/PreferencesStoreTests.swift`

- [ ] **Step 1: Write failing tests** appended to `PreferencesStoreTests.swift`:

```swift
    @Test("New fields default to spec values")
    func newDefaults() async throws {
        let p = try TestStore.makeInMemory()
        let store = PreferencesStore(persistence: p)
        let prefs = try await store.read()
        #expect(prefs.hasCompletedOnboarding == false)
        #expect(prefs.quickCaptureEnabled == true)
        #expect(prefs.quickCaptureHotkey == "ctrl+opt+space")
        #expect(prefs.statusBarItemVisible == true)
        #expect(prefs.showPostCrashPrompt == true)
        #expect(prefs.defaultTagTintHex == "#7F8FA6")
    }

    @Test("hasCompletedOnboarding round-trips")
    func onboardingRoundTrip() async throws {
        let p = try TestStore.makeInMemory()
        let store = PreferencesStore(persistence: p)
        try await store.update { $0.hasCompletedOnboarding = true }
        let prefs = try await store.read()
        #expect(prefs.hasCompletedOnboarding == true)
    }
```

Run: `cd Packages/LillistCore && swift test --filter PreferencesStoreTests`
Expected: compile failure — `Prefs` lacks the new fields.

- [ ] **Step 2: Extend `Prefs`** in `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift`:

```swift
    public struct Prefs: Sendable, Equatable {
        public var defaultAllDayHour: Int16
        public var defaultAllDayMinute: Int16
        public var morningSummaryEnabled: Bool
        public var morningSummaryHour: Int16
        public var morningSummaryMinute: Int16
        public var trashRetentionDays: Int16
        public var defaultTaskListSort: SortField
        public var hasCompletedOnboarding: Bool
        public var quickCaptureEnabled: Bool
        public var quickCaptureHotkey: String
        public var statusBarItemVisible: Bool
        public var showPostCrashPrompt: Bool
        public var defaultTagTintHex: String
    }
```

- [ ] **Step 3: Update `read()` to populate the new fields**

Replace the `read()` body in `PreferencesStore.swift`:

```swift
    public func read() async throws -> Prefs {
        try await context.perform { [self] in
            let row = try fetchOrCreateSingleton(in: context)
            return Prefs(
                defaultAllDayHour: row.defaultAllDayNotificationHour,
                defaultAllDayMinute: row.defaultAllDayNotificationMinute,
                morningSummaryEnabled: row.morningSummaryEnabled,
                morningSummaryHour: row.morningSummaryHour,
                morningSummaryMinute: row.morningSummaryMinute,
                trashRetentionDays: row.trashRetentionDays,
                defaultTaskListSort: row.defaultTaskListSort,
                hasCompletedOnboarding: row.hasCompletedOnboarding,
                quickCaptureEnabled: row.quickCaptureEnabled,
                quickCaptureHotkey: row.quickCaptureHotkey ?? "ctrl+opt+space",
                statusBarItemVisible: row.statusBarItemVisible,
                showPostCrashPrompt: row.showPostCrashPrompt,
                defaultTagTintHex: row.defaultTagTintHex ?? "#7F8FA6"
            )
        }
    }
```

- [ ] **Step 4: Update `update(_:)`** to read+write the new fields. Replace the body:

```swift
    public func update(_ block: @escaping (inout Prefs) -> Void) async throws {
        try await context.perform { [self] in
            let row = try fetchOrCreateSingleton(in: context)
            var prefs = Prefs(
                defaultAllDayHour: row.defaultAllDayNotificationHour,
                defaultAllDayMinute: row.defaultAllDayNotificationMinute,
                morningSummaryEnabled: row.morningSummaryEnabled,
                morningSummaryHour: row.morningSummaryHour,
                morningSummaryMinute: row.morningSummaryMinute,
                trashRetentionDays: row.trashRetentionDays,
                defaultTaskListSort: row.defaultTaskListSort,
                hasCompletedOnboarding: row.hasCompletedOnboarding,
                quickCaptureEnabled: row.quickCaptureEnabled,
                quickCaptureHotkey: row.quickCaptureHotkey ?? "ctrl+opt+space",
                statusBarItemVisible: row.statusBarItemVisible,
                showPostCrashPrompt: row.showPostCrashPrompt,
                defaultTagTintHex: row.defaultTagTintHex ?? "#7F8FA6"
            )
            block(&prefs)
            row.defaultAllDayNotificationHour = prefs.defaultAllDayHour
            row.defaultAllDayNotificationMinute = prefs.defaultAllDayMinute
            row.morningSummaryEnabled = prefs.morningSummaryEnabled
            row.morningSummaryHour = prefs.morningSummaryHour
            row.morningSummaryMinute = prefs.morningSummaryMinute
            row.trashRetentionDays = prefs.trashRetentionDays
            row.defaultTaskListSort = prefs.defaultTaskListSort
            row.hasCompletedOnboarding = prefs.hasCompletedOnboarding
            row.quickCaptureEnabled = prefs.quickCaptureEnabled
            row.quickCaptureHotkey = prefs.quickCaptureHotkey
            row.statusBarItemVisible = prefs.statusBarItemVisible
            row.showPostCrashPrompt = prefs.showPostCrashPrompt
            row.defaultTagTintHex = prefs.defaultTagTintHex
            try context.save()
        }
    }
```

- [ ] **Step 5: Update the singleton seed** in `fetchOrCreateSingleton(in:)`:

```swift
        let row = AppPreferences(context: ctx)
        row.id = UUID()
        row.defaultAllDayNotificationHour = 9
        row.defaultAllDayNotificationMinute = 0
        row.morningSummaryEnabled = true
        row.morningSummaryHour = 9
        row.morningSummaryMinute = 0
        row.trashRetentionDays = 30
        row.defaultTaskListSortRaw = SortField.manualPosition.rawValue
        row.hasCompletedOnboarding = false
        row.quickCaptureEnabled = true
        row.quickCaptureHotkey = "ctrl+opt+space"
        row.statusBarItemVisible = true
        row.showPostCrashPrompt = true
        row.defaultTagTintHex = "#7F8FA6"
        try ctx.save()
        return row
```

- [ ] **Step 6: Run tests**

Run: `cd Packages/LillistCore && swift test --filter PreferencesStoreTests`
Expected: PASS, 5 tests (3 pre-existing + 2 new).

- [ ] **Step 7: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/PreferencesStoreTests.swift
git commit -m "feat: extend PreferencesStore.Prefs with onboarding and pref fields"
```

---

## Task 3: Add `OnboardingState` to `LillistCore`

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Onboarding/OnboardingState.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Onboarding/OnboardingStateTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Onboarding/OnboardingStateTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("OnboardingState")
struct OnboardingStateTests {
    @Test("Fresh store reports not completed")
    func freshIsNotComplete() async throws {
        let p = try TestStore.makeInMemory()
        let prefs = PreferencesStore(persistence: p)
        let state = OnboardingState(preferences: prefs)
        let done = try await state.hasCompletedOnboarding()
        #expect(done == false)
    }

    @Test("markCompleted flips the flag")
    func markCompleted() async throws {
        let p = try TestStore.makeInMemory()
        let prefs = PreferencesStore(persistence: p)
        let state = OnboardingState(preferences: prefs)
        try await state.markCompleted()
        let done = try await state.hasCompletedOnboarding()
        #expect(done == true)
    }

    @Test("markCompleted is idempotent")
    func markCompletedIdempotent() async throws {
        let p = try TestStore.makeInMemory()
        let prefs = PreferencesStore(persistence: p)
        let state = OnboardingState(preferences: prefs)
        try await state.markCompleted()
        try await state.markCompleted()
        #expect(try await state.hasCompletedOnboarding() == true)
        #expect(try await prefs.rowCount() == 1)
    }
}
```

Run: `cd Packages/LillistCore && swift test --filter OnboardingStateTests`
Expected: compile failure — `OnboardingState` does not exist.

- [ ] **Step 2: Write `OnboardingState`**

Write `Packages/LillistCore/Sources/LillistCore/Onboarding/OnboardingState.swift`:

```swift
import Foundation

/// First-launch state.
///
/// Reads/writes the `hasCompletedOnboarding` flag on `AppPreferences` via
/// `PreferencesStore`. Designed for the macOS/iOS app shells to gate the
/// onboarding sheet/cover on cold start.
///
/// See design Section 7 ("Onboarding").
public final class OnboardingState: @unchecked Sendable {
    private let preferences: PreferencesStore

    public init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    /// Whether the user has completed the one-screen onboarding flow.
    public func hasCompletedOnboarding() async throws -> Bool {
        try await preferences.read().hasCompletedOnboarding
    }

    /// Mark onboarding as complete. Idempotent.
    public func markCompleted() async throws {
        try await preferences.update { $0.hasCompletedOnboarding = true }
    }

    /// Test/debug helper to reset onboarding. Not exposed in UI.
    public func resetForTesting() async throws {
        try await preferences.update { $0.hasCompletedOnboarding = false }
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd Packages/LillistCore && swift test --filter OnboardingStateTests`
Expected: PASS, 3 tests.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Onboarding/OnboardingState.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Onboarding/OnboardingStateTests.swift
git commit -m "feat: add OnboardingState for first-launch detection"
```

---

## Task 4: Plan 3 follow-up — ensure `Field.hasTags` exists

**Files:**
- Modify (only if missing): `Packages/LillistCore/Sources/LillistCore/Rules/Field.swift`
- Modify (only if missing): the NSPredicate translator and pure-Swift evaluator that back `Field`.

- [ ] **Step 1: Check for `hasTags`**

Run: `grep -n 'case hasTags' Packages/LillistCore/Sources/LillistCore/Rules/Field.swift`
- If a match is found: skip to Step 4 (commit a no-op note in `DefaultsInstaller.swift` instead — handled in Task 5).
- If no match: continue.

- [ ] **Step 2: Add `hasTags` to `Field`**

In `Packages/LillistCore/Sources/LillistCore/Rules/Field.swift`, add the case (alphabetical ordering preserved):

```swift
    case hasAttachments
    case hasChildren
    case hasNudges
    case hasTags
```

In the `operators` table on the same enum, add:

```swift
        case .hasTags: return [.is]
```

- [ ] **Step 3: Extend the evaluators**

In the NSPredicate translator, add a case for `.hasTags`:

```swift
        case .hasTags:
            guard case .bool(let want) = leaf.value, leaf.op == .is else { throw RuleError.unsupported }
            // tasks with at least one tag iff `tags.@count > 0`
            return NSPredicate(format: want ? "tags.@count > 0" : "tags.@count == 0")
```

In the pure-Swift evaluator:

```swift
        case .hasTags:
            guard case .bool(let want) = leaf.value, leaf.op == .is else { return false }
            return (task.tags.count > 0) == want
```

- [ ] **Step 4: Run the rules tests**

Run: `cd Packages/LillistCore && swift test --filter RulesEngineTests`
Expected: all pre-existing rules tests still pass. (If Plan 3 already had `hasTags`, this is a no-op.)

- [ ] **Step 5: Commit (only if Step 2 made changes)**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/
git commit -m "feat: add Field.hasTags for 'No Tags' default filter (Plan 3 follow-up)"
```

If no changes were needed, do not create an empty commit. Add a single line at the top of `DefaultsInstaller.swift` (Task 5) noting the date `hasTags` was verified present.

---

## Task 5: Implement `DefaultsInstaller` (idempotent default smart filters)

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Onboarding/DefaultsInstaller.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Onboarding/DefaultsInstallerTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Onboarding/DefaultsInstallerTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("DefaultsInstaller")
struct DefaultsInstallerTests {
    @Test("First run installs all five defaults")
    func firstRunInstalls() async throws {
        let p = try TestStore.makeInMemory()
        let filters = SmartFilterStore(persistence: p)
        let installer = DefaultsInstaller(filters: filters)
        try await installer.installIfNeeded()
        let names = try await filters.list().map(\.name).sorted()
        #expect(names == ["No Tags", "Recently Closed", "Stale", "This Week", "Today"])
    }

    @Test("Second run is a no-op")
    func secondRunIdempotent() async throws {
        let p = try TestStore.makeInMemory()
        let filters = SmartFilterStore(persistence: p)
        let installer = DefaultsInstaller(filters: filters)
        try await installer.installIfNeeded()
        try await installer.installIfNeeded()
        let count = try await filters.list().count
        #expect(count == 5)
    }

    @Test("Missing filter is restored without duplicating others")
    func restoresMissing() async throws {
        let p = try TestStore.makeInMemory()
        let filters = SmartFilterStore(persistence: p)
        let installer = DefaultsInstaller(filters: filters)
        try await installer.installIfNeeded()
        // Delete "Stale" — simulates user removing a default
        let stale = try await filters.list().first { $0.name == "Stale" }
        #expect(stale != nil)
        try await filters.delete(id: stale!.id)
        try await installer.installIfNeeded()
        let names = try await filters.list().map(\.name).sorted()
        #expect(names == ["No Tags", "Recently Closed", "Stale", "This Week", "Today"])
    }

    @Test("User-renamed default is not re-created")
    func renamedNotRecreated() async throws {
        let p = try TestStore.makeInMemory()
        let filters = SmartFilterStore(persistence: p)
        let installer = DefaultsInstaller(filters: filters)
        try await installer.installIfNeeded()
        let today = try await filters.list().first { $0.name == "Today" }!
        try await filters.rename(id: today.id, to: "My Today")
        try await installer.installIfNeeded()
        let names = try await filters.list().map(\.name).sorted()
        // "Today" gets re-created because the installer matches on name
        // (acceptable: a renamed default behaves like a user filter).
        #expect(names == ["My Today", "No Tags", "Recently Closed", "Stale", "This Week", "Today"])
    }
}
```

Run: `cd Packages/LillistCore && swift test --filter DefaultsInstallerTests`
Expected: compile failure — `DefaultsInstaller` does not exist.

- [ ] **Step 2: Implement `DefaultsInstaller`**

Write `Packages/LillistCore/Sources/LillistCore/Onboarding/DefaultsInstaller.swift`:

```swift
import Foundation

/// Idempotently installs the pre-installed default smart filters described in
/// design Section 7 ("Pre-installed defaults"):
///
/// - **Today**: tasks starting or due today, open, not in trash.
/// - **This Week**: tasks starting or due within 7 days, open, not in trash.
/// - **No Tags**: tasks with zero tags.
/// - **Recently Closed**: tasks closed within the last 7 days.
/// - **Stale**: tasks created but never modified, older than 3 days.
///
/// Matching is by exact filter name. A user who renames "Today" causes the
/// installer to re-create a fresh "Today" — that's expected. A user who
/// *deletes* a default and immediately re-runs the installer will see it
/// restored, which is also fine: the typical caller is "once per cold launch
/// during onboarding."
///
/// The empty tag tree is the other half of design Section 7's
/// "Pre-installed defaults": this installer *deliberately* never creates
/// default tags.
public final class DefaultsInstaller: @unchecked Sendable {
    private let filters: SmartFilterStore

    public init(filters: SmartFilterStore) {
        self.filters = filters
    }

    public func installIfNeeded() async throws {
        let existing = Set(try await filters.list().map(\.name))
        for spec in Self.defaults where !existing.contains(spec.name) {
            try await filters.create(
                name: spec.name,
                predicateGroup: spec.predicateGroup,
                tintColor: spec.tintHex,
                sortField: spec.sortField,
                sortAscending: spec.sortAscending,
                isPinned: spec.isPinned
            )
        }
    }

    // MARK: - Defaults

    private struct DefaultSpec {
        let name: String
        let predicateGroup: PredicateGroup
        let tintHex: String
        let sortField: SortField
        let sortAscending: Bool
        let isPinned: Bool
    }

    private static let defaults: [DefaultSpec] = [
        .init(
            name: "Today",
            predicateGroup: PredicateGroup(
                combinator: .all,
                predicates: [
                    .group(PredicateGroup(combinator: .any, predicates: [
                        .leaf(.init(field: .start, op: .withinNextDays, value: .int(0))),
                        .leaf(.init(field: .deadline, op: .withinNextDays, value: .int(0)))
                    ])),
                    .leaf(.init(field: .status, op: .isNot, value: .status(.closed))),
                    .leaf(.init(field: .inTrash, op: .is, value: .bool(false)))
                ]
            ),
            tintHex: "#3B82F6",
            sortField: .deadline,
            sortAscending: true,
            isPinned: true
        ),
        .init(
            name: "This Week",
            predicateGroup: PredicateGroup(
                combinator: .all,
                predicates: [
                    .group(PredicateGroup(combinator: .any, predicates: [
                        .leaf(.init(field: .start, op: .withinNextDays, value: .int(7))),
                        .leaf(.init(field: .deadline, op: .withinNextDays, value: .int(7)))
                    ])),
                    .leaf(.init(field: .status, op: .isNot, value: .status(.closed))),
                    .leaf(.init(field: .inTrash, op: .is, value: .bool(false)))
                ]
            ),
            tintHex: "#8B5CF6",
            sortField: .deadline,
            sortAscending: true,
            isPinned: false
        ),
        .init(
            name: "No Tags",
            predicateGroup: PredicateGroup(
                combinator: .all,
                predicates: [
                    .leaf(.init(field: .hasTags, op: .is, value: .bool(false))),
                    .leaf(.init(field: .status, op: .isNot, value: .status(.closed)))
                ]
            ),
            tintHex: "#64748B",
            sortField: .createdAt,
            sortAscending: false,
            isPinned: false
        ),
        .init(
            name: "Recently Closed",
            predicateGroup: PredicateGroup(
                combinator: .all,
                predicates: [
                    .leaf(.init(field: .closedAt, op: .withinLastDays, value: .int(7)))
                ]
            ),
            tintHex: "#10B981",
            sortField: .closedAt,
            sortAscending: false,
            isPinned: false
        ),
        .init(
            name: "Stale",
            predicateGroup: PredicateGroup(
                combinator: .all,
                predicates: [
                    .leaf(.init(field: .createdAt, op: .equalsModifiedAt, value: .bool(true))),
                    .leaf(.init(field: .modifiedAt, op: .before, value: .relativeDate(.daysAgo(3))))
                ]
            ),
            tintHex: "#F59E0B",
            sortField: .createdAt,
            sortAscending: true,
            isPinned: false
        )
    ]
}
```

> **Note:** This file assumes Plan 3 exposes `PredicateGroup`, `Predicate`, `Leaf`, `Value`, `Field`, `Op`, `RelativeDate`, plus `SmartFilterStore` with `list()` / `create(...)` / `delete(id:)` / `rename(id:to:)`. If any of those method signatures differ in the final Plan 3 implementation, fix the call sites here in a follow-up; do not change the test expectations.

- [ ] **Step 3: Run tests**

Run: `cd Packages/LillistCore && swift test --filter DefaultsInstallerTests`
Expected: PASS, 4 tests.

- [ ] **Step 4: Run full LillistCore suite**

Run: `cd Packages/LillistCore && swift test`
Expected: full pre-existing suite plus the new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Onboarding/DefaultsInstaller.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Onboarding/DefaultsInstallerTests.swift
git commit -m "feat: add idempotent DefaultsInstaller for pre-installed smart filters"
```

---

## Task 6: macOS — `OnboardingSheet` view

**Files:**
- Create: `Apps/Lillist-macOS/Lillist-macOS/Onboarding/OnboardingSheet.swift`

- [ ] **Step 1: Write `OnboardingSheet`**

Write `Apps/Lillist-macOS/Lillist-macOS/Onboarding/OnboardingSheet.swift`:

```swift
import SwiftUI
import LillistCore

/// First-launch onboarding sheet for macOS.
///
/// Single screen with: app name + tagline, three bullets (iCloud, notifications,
/// global hotkey), two primary actions (set up notifications, get started), and
/// a "skip for now" link. See design Section 7 ("Onboarding").
struct OnboardingSheet: View {
    let onboardingState: OnboardingState
    let installer: DefaultsInstaller
    let notificationPermissions: NotificationPermissions

    @Environment(\.dismiss) private var dismiss
    @State private var permissionStatus: NotificationPermissions.Status = .notDetermined
    @State private var isRequesting = false
    @State private var isCompleting = false

    var body: some View {
        VStack(spacing: 24) {
            header
            bullets
            permissionStatusRow
            buttons
            skipLink
        }
        .padding(40)
        .frame(width: 520)
        .task {
            permissionStatus = await notificationPermissions.currentStatus()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text("Welcome to Lillist")
                .font(.system(size: 28, weight: .semibold))
            Text("A pure-nesting task manager. Everything is a task.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 14) {
            bullet(icon: "icloud", text: "iCloud sync is required. Your data lives in your private CloudKit database.")
            bullet(icon: "bell", text: "Notification permission powers reminders for tasks with dates.")
            bullet(icon: "keyboard", text: "Press \u{2303}\u{2325}Space anywhere for Quick Capture.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24, height: 24)
                .foregroundStyle(.tint)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var permissionStatusRow: some View {
        switch permissionStatus {
        case .granted:
            Label("Notifications enabled.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Label("Notifications denied.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
        case .notDetermined:
            EmptyView()
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await requestPermission() }
            } label: {
                if isRequesting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Set up notifications")
                }
            }
            .disabled(isRequesting || permissionStatus != .notDetermined)

            Button {
                Task { await complete() }
            } label: {
                if isCompleting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Get started")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(isCompleting)
        }
    }

    private var skipLink: some View {
        Button("Skip for now") {
            Task { await complete() }
        }
        .buttonStyle(.link)
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func requestPermission() async {
        isRequesting = true
        defer { isRequesting = false }
        permissionStatus = await notificationPermissions.requestAuthorization()
    }

    private func complete() async {
        isCompleting = true
        defer { isCompleting = false }
        do {
            try await installer.installIfNeeded()
            try await onboardingState.markCompleted()
            dismiss()
        } catch {
            // Surface to the user — non-fatal; they can retry.
            NSAlert(error: error).runModal()
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Lillist-macOS/Onboarding/OnboardingSheet.swift
git commit -m "feat(macOS): add OnboardingSheet for first-launch flow"
```

---

## Task 7: macOS — `ICloudRequiredView` and wire onboarding into the app shell

**Files:**
- Create: `Apps/Lillist-macOS/Lillist-macOS/Onboarding/ICloudRequiredView.swift`
- Modify: `Apps/Lillist-macOS/Lillist-macOS/App/LillistMacApp.swift`

- [ ] **Step 1: Write `ICloudRequiredView`**

Write `Apps/Lillist-macOS/Lillist-macOS/Onboarding/ICloudRequiredView.swift`:

```swift
import SwiftUI
import LillistCore

/// Full-window blocker shown when iCloud is unavailable during onboarding.
/// See design Section 8 ("iCloud account states").
struct ICloudRequiredView: View {
    let accountMonitor: AccountStateMonitor
    @State private var isRechecking = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.red)
            Text("iCloud is required")
                .font(.title)
                .bold()
            Text("Lillist syncs your tasks via your private iCloud database. Please sign into iCloud in System Settings and re-launch.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            HStack(spacing: 12) {
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
        .padding(40)
        .frame(width: 520, height: 360)
    }

    private func recheck() async {
        isRechecking = true
        defer { isRechecking = false }
        await accountMonitor.refresh()
    }
}
```

- [ ] **Step 2: Wire onboarding into `LillistMacApp`**

Modify `Apps/Lillist-macOS/Lillist-macOS/App/LillistMacApp.swift` to gate the main window:

```swift
@main
struct LillistMacApp: App {
    @StateObject private var services = AppServices.shared
    @State private var showOnboarding = false
    @State private var showICloudRequired = false

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .task { await evaluateOnboarding() }
                .sheet(isPresented: $showICloudRequired) {
                    ICloudRequiredView(accountMonitor: services.accountMonitor)
                        .interactiveDismissDisabled(true)
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingSheet(
                        onboardingState: services.onboardingState,
                        installer: services.defaultsInstaller,
                        notificationPermissions: services.notificationPermissions
                    )
                    .interactiveDismissDisabled(true)
                }
                .onChange(of: services.accountMonitor.state) { _, new in
                    showICloudRequired = (new == .unavailable && !showOnboarding && needsOnboarding)
                }
        }

        Settings {
            PreferencesWindow()
                .environmentObject(services)
        }
    }

    @State private var needsOnboarding = false

    private func evaluateOnboarding() async {
        let done = (try? await services.onboardingState.hasCompletedOnboarding()) ?? false
        needsOnboarding = !done
        let accountReady = services.accountMonitor.state == .available
        if !done {
            if accountReady {
                showOnboarding = true
            } else {
                showICloudRequired = true
            }
        } else {
            // Safety-net: run installer in case a prior install died mid-flight.
            try? await services.defaultsInstaller.installIfNeeded()
        }
    }
}
```

> If `AppServices` (the DI container Plan 7 set up) is named differently, adapt accordingly. The salient bit: it exposes `onboardingState`, `defaultsInstaller`, `notificationPermissions`, and `accountMonitor`.

- [ ] **Step 3: Verify build**

Run: `xcodebuild build -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Lillist-macOS/Onboarding/ICloudRequiredView.swift \
        Apps/Lillist-macOS/Lillist-macOS/App/LillistMacApp.swift
git commit -m "feat(macOS): gate main window with onboarding + iCloud-required sheets"
```

---

## Task 8: macOS — Preferences scene scaffolding + General pane

**Files:**
- Create: `Apps/Lillist-macOS/Lillist-macOS/Preferences/PreferencesWindow.swift`
- Create: `Apps/Lillist-macOS/Lillist-macOS/Preferences/GeneralPane.swift`

- [ ] **Step 1: Write the tab host**

Write `Apps/Lillist-macOS/Lillist-macOS/Preferences/PreferencesWindow.swift`:

```swift
import SwiftUI

/// Root of the macOS `Settings { … }` scene. Six tabs match design Section 7.
struct PreferencesWindow: View {
    var body: some View {
        TabView {
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationsPane()
                .tabItem { Label("Notifications", systemImage: "bell") }
            TrashPane()
                .tabItem { Label("Trash", systemImage: "trash") }
            QuickCapturePane()
                .tabItem { Label("Quick Capture", systemImage: "keyboard") }
            CrashReportingPane()
                .tabItem { Label("Crash Reporting", systemImage: "ant") }
            AdvancedPane()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 420)
    }
}
```

- [ ] **Step 2: Write `GeneralPane`**

Write `Apps/Lillist-macOS/Lillist-macOS/Preferences/GeneralPane.swift`:

```swift
import SwiftUI
import LillistCore

struct GeneralPane: View {
    @EnvironmentObject var services: AppServices
    @State private var prefs: PreferencesStore.Prefs?
    @State private var loadError: Error?

    var body: some View {
        Form {
            if let bindingPrefs = prefsBinding {
                Section("Defaults") {
                    Picker("Default task list sort", selection: bindingPrefs.defaultTaskListSort) {
                        ForEach(SortField.allCases, id: \.self) { field in
                            Text(field.displayName).tag(field)
                        }
                    }
                    ColorPicker("Default tag tint", selection: tagTintBinding(bindingPrefs))
                }
            } else if let loadError {
                Text("Couldn't load preferences: \(loadError.localizedDescription)")
                    .foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .task { await load() }
        .onChange(of: prefs) { _, new in
            guard let new else { return }
            Task { try? await services.preferencesStore.update { $0 = new } }
        }
    }

    private var prefsBinding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }

    private func tagTintBinding(_ b: Binding<PreferencesStore.Prefs>) -> Binding<Color> {
        Binding(
            get: { Color(hex: b.wrappedValue.defaultTagTintHex) ?? .gray },
            set: { b.wrappedValue.defaultTagTintHex = $0.toHex() ?? "#7F8FA6" }
        )
    }

    private func load() async {
        do {
            prefs = try await services.preferencesStore.read()
        } catch {
            loadError = error
        }
    }
}

private extension SortField {
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

> `Color(hex:)` / `Color.toHex()` extensions are assumed to live in `LillistUI` (from Plan 7). If not, add a tiny file `Apps/Lillist-macOS/Lillist-macOS/Support/Color+Hex.swift` with the standard 6-digit hex helpers.

- [ ] **Step 3: Verify build**

Run: `xcodebuild build -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Lillist-macOS/Preferences/PreferencesWindow.swift \
        Apps/Lillist-macOS/Lillist-macOS/Preferences/GeneralPane.swift
git commit -m "feat(macOS): add Preferences scene host and General pane"
```

---

## Task 9: macOS — Notifications, Trash, QuickCapture, CrashReporting, Advanced panes

**Files:**
- Create: `Apps/Lillist-macOS/Lillist-macOS/Preferences/NotificationsPane.swift`
- Create: `Apps/Lillist-macOS/Lillist-macOS/Preferences/TrashPane.swift`
- Create: `Apps/Lillist-macOS/Lillist-macOS/Preferences/QuickCapturePane.swift`
- Create: `Apps/Lillist-macOS/Lillist-macOS/Preferences/CrashReportingPane.swift`
- Create: `Apps/Lillist-macOS/Lillist-macOS/Preferences/AdvancedPane.swift`

- [ ] **Step 1: Write `NotificationsPane`**

```swift
import SwiftUI
import LillistCore

struct NotificationsPane: View {
    @EnvironmentObject var services: AppServices
    @State private var prefs: PreferencesStore.Prefs?
    @State private var permStatus: NotificationPermissions.Status = .notDetermined

    var body: some View {
        Form {
            if let b = bindingFor(\.self) {
                Section("All-day reminder time") {
                    DatePicker("Default time", selection: hmBinding(b), displayedComponents: .hourAndMinute)
                }
                Section("Morning summary") {
                    Toggle("Send a morning summary", isOn: b.morningSummaryEnabled)
                    if b.wrappedValue.morningSummaryEnabled {
                        DatePicker("Summary time", selection: morningBinding(b), displayedComponents: .hourAndMinute)
                    }
                }
                Section("Permission") {
                    HStack {
                        permissionLabel
                        Spacer()
                        Button("Test permission") {
                            Task { permStatus = await services.notificationPermissions.requestAuthorization() }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .task {
            prefs = try? await services.preferencesStore.read()
            permStatus = await services.notificationPermissions.currentStatus()
        }
        .onChange(of: prefs) { _, new in
            guard let new else { return }
            Task { try? await services.preferencesStore.update { $0 = new } }
        }
    }

    @ViewBuilder private var permissionLabel: some View {
        switch permStatus {
        case .granted: Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied:  Label("Denied",  systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .notDetermined: Label("Not yet requested", systemImage: "questionmark.circle")
        }
    }

    private func bindingFor<T>(_ keyPath: WritableKeyPath<PreferencesStore.Prefs, T>) -> Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }

    private func hmBinding(_ b: Binding<PreferencesStore.Prefs>) -> Binding<Date> {
        Binding(
            get: { date(hour: Int(b.wrappedValue.defaultAllDayHour), minute: Int(b.wrappedValue.defaultAllDayMinute)) },
            set: {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: $0)
                b.wrappedValue.defaultAllDayHour = Int16(comps.hour ?? 9)
                b.wrappedValue.defaultAllDayMinute = Int16(comps.minute ?? 0)
            }
        )
    }

    private func morningBinding(_ b: Binding<PreferencesStore.Prefs>) -> Binding<Date> {
        Binding(
            get: { date(hour: Int(b.wrappedValue.morningSummaryHour), minute: Int(b.wrappedValue.morningSummaryMinute)) },
            set: {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: $0)
                b.wrappedValue.morningSummaryHour = Int16(comps.hour ?? 9)
                b.wrappedValue.morningSummaryMinute = Int16(comps.minute ?? 0)
            }
        )
    }

    private func date(hour: Int, minute: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c) ?? Date()
    }
}
```

- [ ] **Step 2: Write `TrashPane`**

```swift
import SwiftUI
import LillistCore

struct TrashPane: View {
    @EnvironmentObject var services: AppServices
    @State private var prefs: PreferencesStore.Prefs?
    @State private var isEmptying = false

    var body: some View {
        Form {
            if let b = binding {
                Section("Retention") {
                    let days = Double(b.wrappedValue.trashRetentionDays)
                    Slider(
                        value: Binding(get: { days }, set: { b.wrappedValue.trashRetentionDays = Int16($0.rounded()) }),
                        in: 7...365,
                        step: 1
                    ) {
                        Text("Days in Trash before auto-purge")
                    }
                    Text("\(b.wrappedValue.trashRetentionDays) days")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section {
                    Button(role: .destructive) {
                        Task { await emptyTrash() }
                    } label: {
                        if isEmptying { ProgressView() } else { Text("Empty Trash now") }
                    }
                    .disabled(isEmptying)
                }
            } else { ProgressView() }
        }
        .formStyle(.grouped)
        .task { prefs = try? await services.preferencesStore.read() }
        .onChange(of: prefs) { _, new in
            guard let new else { return }
            Task { try? await services.preferencesStore.update { $0 = new } }
        }
    }

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }

    private func emptyTrash() async {
        isEmptying = true
        defer { isEmptying = false }
        try? await services.autoPurgeJob.runNow(forceAll: true)
    }
}
```

- [ ] **Step 3: Write `QuickCapturePane`**

```swift
import SwiftUI
import LillistCore

struct QuickCapturePane: View {
    @EnvironmentObject var services: AppServices
    @State private var prefs: PreferencesStore.Prefs?

    var body: some View {
        Form {
            if let b = binding {
                Section("Quick Capture") {
                    Toggle("Enable global Quick Capture", isOn: b.quickCaptureEnabled)
                    Toggle("Show status bar icon", isOn: b.statusBarItemVisible)
                    LabeledContent("Global hotkey") {
                        HotkeyRecorder(value: b.quickCaptureHotkey)
                            .frame(width: 200)
                    }
                }
            } else { ProgressView() }
        }
        .formStyle(.grouped)
        .task { prefs = try? await services.preferencesStore.read() }
        .onChange(of: prefs) { _, new in
            guard let new else { return }
            Task { try? await services.preferencesStore.update { $0 = new } }
            // TODO(Plan 7): re-register the hotkey via KeyboardShortcutsRegistrar.
        }
    }

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }
}

/// Tiny placeholder hotkey recorder. The real recorder lives in Plan 7's
/// quick-capture work; this binds to a string for now.
struct HotkeyRecorder: View {
    @Binding var value: String
    var body: some View {
        TextField("hotkey", text: $value)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
    }
}
```

- [ ] **Step 4: Write `CrashReportingPane`**

```swift
import SwiftUI
import LillistCore

struct CrashReportingPane: View {
    @EnvironmentObject var services: AppServices
    @State private var prefs: PreferencesStore.Prefs?
    @State private var sampleVisible = false

    var body: some View {
        Form {
            if let b = binding {
                Section("Post-crash prompt") {
                    Toggle("Show prompt after Lillist quits unexpectedly", isOn: b.showPostCrashPrompt)
                    Text("Reports go directly to Mikey via email. No third-party telemetry.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup("View what would be sent", isExpanded: $sampleVisible) {
                        Text(services.crashReporter.samplePayloadPreview())
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            } else { ProgressView() }
        }
        .formStyle(.grouped)
        .task { prefs = try? await services.preferencesStore.read() }
        .onChange(of: prefs) { _, new in
            guard let new else { return }
            Task { try? await services.preferencesStore.update { $0 = new } }
        }
    }

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }
}
```

- [ ] **Step 5: Write `AdvancedPane`**

```swift
import SwiftUI
import AppKit
import LillistCore

struct AdvancedPane: View {
    @EnvironmentObject var services: AppServices
    @State private var isExporting = false

    var body: some View {
        Form {
            Section("Data") {
                Button {
                    Task { await runExport() }
                } label: {
                    if isExporting { ProgressView() } else { Text("Export now…") }
                }
                .disabled(isExporting)

                Button("Reveal store in Finder") {
                    let url = services.persistence.storeURL
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runExport() async {
        let panel = NSSavePanel()
        panel.title = "Export Lillist data"
        panel.nameFieldStringValue = "Lillist-Export"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            try await services.exporter.export(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
```

- [ ] **Step 6: Verify build**

Run: `xcodebuild build -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Apps/Lillist-macOS/Lillist-macOS/Preferences/
git commit -m "feat(macOS): add Notifications, Trash, QuickCapture, CrashReporting, Advanced panes"
```

---

## Task 10: macOS — snapshot tests for onboarding + each pref pane

**Files:**
- Create: `Tests/Lillist-macOSTests/OnboardingSheetSnapshotTests.swift`
- Create: `Tests/Lillist-macOSTests/PreferencesPaneSnapshotTests.swift`

- [ ] **Step 1: Write `OnboardingSheetSnapshotTests`**

```swift
import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lillist_macOS
@testable import LillistCore

final class OnboardingSheetSnapshotTests: XCTestCase {
    func test_onboardingSheet_lightAndDark() throws {
        let services = AppServicesFixture.inMemory()
        let view = OnboardingSheet(
            onboardingState: services.onboardingState,
            installer: services.defaultsInstaller,
            notificationPermissions: services.notificationPermissions
        )
        assertSnapshot(of: view.frame(width: 520, height: 460), as: .image(precision: 0.99))
        assertSnapshot(
            of: view.frame(width: 520, height: 460).preferredColorScheme(.dark),
            as: .image(precision: 0.99)
        )
    }

    func test_iCloudRequiredView() throws {
        let services = AppServicesFixture.inMemory()
        let view = ICloudRequiredView(accountMonitor: services.accountMonitor)
        assertSnapshot(of: view, as: .image(precision: 0.99))
    }
}
```

- [ ] **Step 2: Write `PreferencesPaneSnapshotTests`**

```swift
import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lillist_macOS
@testable import LillistCore

final class PreferencesPaneSnapshotTests: XCTestCase {
    func test_general()         { snapshot(GeneralPane()) }
    func test_notifications()   { snapshot(NotificationsPane()) }
    func test_trash()           { snapshot(TrashPane()) }
    func test_quickCapture()    { snapshot(QuickCapturePane()) }
    func test_crashReporting()  { snapshot(CrashReportingPane()) }
    func test_advanced()        { snapshot(AdvancedPane()) }

    private func snapshot<V: View>(_ v: V, file: StaticString = #file, line: UInt = #line) {
        let services = AppServicesFixture.inMemory()
        let host = v.environmentObject(services).frame(width: 520, height: 420)
        assertSnapshot(of: host, as: .image(precision: 0.99), file: file, line: line)
    }
}
```

> `AppServicesFixture.inMemory()` is assumed to exist in the macOS test target (Plan 7 introduces it). If not present, add `Tests/Lillist-macOSTests/Helpers/AppServicesFixture.swift` returning an `AppServices` wired to in-memory stores.

- [ ] **Step 3: Run tests, recording baselines first**

First pass with `record: true` to write baselines:

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
    -destination 'platform=macOS' \
    -only-testing:Lillist-macOSTests/OnboardingSheetSnapshotTests \
    -only-testing:Lillist-macOSTests/PreferencesPaneSnapshotTests \
    SNAPSHOT_RECORD=1
```

Expected: tests "fail" with "recorded new snapshot" — re-run without `SNAPSHOT_RECORD` to confirm green.

- [ ] **Step 4: Commit**

```bash
git add Tests/Lillist-macOSTests/OnboardingSheetSnapshotTests.swift \
        Tests/Lillist-macOSTests/PreferencesPaneSnapshotTests.swift \
        Tests/Lillist-macOSTests/__Snapshots__/
git commit -m "test(macOS): snapshot onboarding + every preferences pane (light/dark)"
```

---

## Task 11: macOS — notification permission flow test (mocked)

**Files:**
- Create: `Tests/Lillist-macOSTests/NotificationPermissionFlowTests.swift`

- [ ] **Step 1: Write the test**

```swift
import XCTest
@testable import Lillist_macOS
@testable import LillistCore

final class NotificationPermissionFlowTests: XCTestCase {
    func test_grantedPath_completesOnboarding() async throws {
        let services = AppServicesFixture.inMemory()
        let mockPerms = services.notificationPermissions as! MockNotificationPermissions
        mockPerms.scriptedRequestResult = .granted

        XCTAssertFalse(try await services.onboardingState.hasCompletedOnboarding())

        let status = await services.notificationPermissions.requestAuthorization()
        XCTAssertEqual(status, .granted)
        try await services.defaultsInstaller.installIfNeeded()
        try await services.onboardingState.markCompleted()

        XCTAssertTrue(try await services.onboardingState.hasCompletedOnboarding())
        let filters = try await services.smartFilters.list().map(\.name).sorted()
        XCTAssertEqual(filters, ["No Tags", "Recently Closed", "Stale", "This Week", "Today"])
    }

    func test_deniedPath_stillCompletesOnboarding() async throws {
        let services = AppServicesFixture.inMemory()
        let mockPerms = services.notificationPermissions as! MockNotificationPermissions
        mockPerms.scriptedRequestResult = .denied

        let status = await services.notificationPermissions.requestAuthorization()
        XCTAssertEqual(status, .denied)
        try await services.onboardingState.markCompleted()

        XCTAssertTrue(try await services.onboardingState.hasCompletedOnboarding())
    }
}
```

> `MockNotificationPermissions` is the Plan 5 test double. If `AppServicesFixture.inMemory()` doesn't already wire it up, add it in the fixture file.

- [ ] **Step 2: Run tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
    -destination 'platform=macOS' \
    -only-testing:Lillist-macOSTests/NotificationPermissionFlowTests
```

Expected: PASS, 2 tests.

- [ ] **Step 3: Commit**

```bash
git add Tests/Lillist-macOSTests/NotificationPermissionFlowTests.swift
git commit -m "test(macOS): cover granted + denied permission paths through onboarding"
```

---

## Task 12: iOS — `OnboardingScreen` and `ICloudRequiredScreen`

**Files:**
- Create: `Apps/Lillist-iOS/Lillist-iOS/Onboarding/OnboardingScreen.swift`
- Create: `Apps/Lillist-iOS/Lillist-iOS/Onboarding/ICloudRequiredScreen.swift`

- [ ] **Step 1: Write `OnboardingScreen`**

```swift
import SwiftUI
import LillistCore

struct OnboardingScreen: View {
    let onboardingState: OnboardingState
    let installer: DefaultsInstaller
    let notificationPermissions: NotificationPermissions

    @Environment(\.dismiss) private var dismiss
    @State private var permissionStatus: NotificationPermissions.Status = .notDetermined
    @State private var isRequesting = false
    @State private var isCompleting = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    bullets
                    permissionStatusRow
                }
                .padding(24)
            }
            actionBar
        }
        .task { permissionStatus = await notificationPermissions.currentStatus() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
            Text("Welcome to Lillist")
                .font(.largeTitle.bold())
            Text("A pure-nesting task manager. Everything is a task.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 18) {
            bullet(icon: "icloud", text: "iCloud sync is required. Your data lives in your private CloudKit database.")
            bullet(icon: "bell", text: "Notification permission powers reminders for tasks with dates.")
            bullet(icon: "plus.circle", text: "Use the Lock Screen Shortcut or the floating + button to capture anywhere.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.tint)
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var permissionStatusRow: some View {
        switch permissionStatus {
        case .granted:
            Label("Notifications enabled.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label("Notifications denied.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        case .notDetermined:
            EmptyView()
        }
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            Button {
                Task { await requestPermission() }
            } label: {
                Text(isRequesting ? "Requesting…" : "Set up notifications")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(isRequesting || permissionStatus != .notDetermined)

            Button {
                Task { await complete() }
            } label: {
                Text(isCompleting ? "Finishing…" : "Get started")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCompleting)

            Button("Skip for now") { Task { await complete() } }
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.bar)
    }

    private func requestPermission() async {
        isRequesting = true; defer { isRequesting = false }
        permissionStatus = await notificationPermissions.requestAuthorization()
    }

    private func complete() async {
        isCompleting = true; defer { isCompleting = false }
        do {
            try await installer.installIfNeeded()
            try await onboardingState.markCompleted()
            dismiss()
        } catch {
            // surface via parent in production; logged here.
            print("Onboarding completion failed: \(error)")
        }
    }
}
```

- [ ] **Step 2: Write `ICloudRequiredScreen`**

```swift
import SwiftUI
import LillistCore

struct ICloudRequiredScreen: View {
    let accountMonitor: AccountStateMonitor
    @State private var isRechecking = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.red)
            Text("iCloud is required")
                .font(.title.bold())
            Text("Lillist syncs your tasks via your private iCloud database. Sign into iCloud in Settings, then return here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

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
        .padding(32)
    }

    private func recheck() async {
        isRechecking = true; defer { isRechecking = false }
        await accountMonitor.refresh()
    }
}
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild build -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-iOS/Lillist-iOS/Onboarding/
git commit -m "feat(iOS): add OnboardingScreen and ICloudRequiredScreen"
```

---

## Task 13: iOS — wire onboarding into the app root

**Files:**
- Modify: `Apps/Lillist-iOS/Lillist-iOS/App/LillistIOSApp.swift`

- [ ] **Step 1: Gate the root with a full-screen cover**

Modify the app to present onboarding on first launch:

```swift
@main
struct LillistIOSApp: App {
    @StateObject private var services = AppServices.shared
    @State private var showOnboarding = false
    @State private var showICloudRequired = false
    @State private var didEvaluate = false

    var body: some Scene {
        WindowGroup {
            RootTabsView()
                .environmentObject(services)
                .task {
                    guard !didEvaluate else { return }
                    didEvaluate = true
                    await evaluate()
                }
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingScreen(
                        onboardingState: services.onboardingState,
                        installer: services.defaultsInstaller,
                        notificationPermissions: services.notificationPermissions
                    )
                    .interactiveDismissDisabled(true)
                }
                .fullScreenCover(isPresented: $showICloudRequired) {
                    ICloudRequiredScreen(accountMonitor: services.accountMonitor)
                        .interactiveDismissDisabled(true)
                }
                .onChange(of: services.accountMonitor.state) { _, new in
                    if new == .available, showICloudRequired {
                        showICloudRequired = false
                        showOnboarding = true
                    }
                }
        }
    }

    private func evaluate() async {
        let done = (try? await services.onboardingState.hasCompletedOnboarding()) ?? false
        if !done {
            if services.accountMonitor.state == .available {
                showOnboarding = true
            } else {
                showICloudRequired = true
            }
        } else {
            try? await services.defaultsInstaller.installIfNeeded()
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild build -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-iOS/Lillist-iOS/App/LillistIOSApp.swift
git commit -m "feat(iOS): gate root with onboarding + iCloud-required covers"
```

---

## Task 14: iOS — `SettingsTab` host + all sections

**Files:**
- Create: `Apps/Lillist-iOS/Lillist-iOS/Settings/SettingsTab.swift`
- Create: `Apps/Lillist-iOS/Lillist-iOS/Settings/GeneralSection.swift`
- Create: `Apps/Lillist-iOS/Lillist-iOS/Settings/NotificationsSection.swift`
- Create: `Apps/Lillist-iOS/Lillist-iOS/Settings/TrashSection.swift`
- Create: `Apps/Lillist-iOS/Lillist-iOS/Settings/QuickCaptureSection.swift`
- Create: `Apps/Lillist-iOS/Lillist-iOS/Settings/CrashReportingSection.swift`
- Create: `Apps/Lillist-iOS/Lillist-iOS/Settings/AdvancedSection.swift`

- [ ] **Step 1: Write `SettingsTab` host**

```swift
import SwiftUI
import LillistCore

/// Settings screen surfaced from the iOS root view's top-bar gear icon.
/// Same content matrix as the macOS Preferences scene, adapted to iOS Form style.
struct SettingsTab: View {
    @EnvironmentObject var services: AppServices
    @Environment(\.dismiss) private var dismiss
    @State private var prefs: PreferencesStore.Prefs?

    var body: some View {
        NavigationStack {
            Form {
                if let b = binding {
                    GeneralSection(prefs: b)
                    NotificationsSection(prefs: b)
                    TrashSection(prefs: b)
                    QuickCaptureSection(prefs: b)
                    CrashReportingSection(prefs: b)
                    AdvancedSection()
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { prefs = try? await services.preferencesStore.read() }
            .onChange(of: prefs) { _, new in
                guard let new else { return }
                Task { try? await services.preferencesStore.update { $0 = new } }
            }
        }
    }

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }
}
```

- [ ] **Step 2: Write the six sections**

`GeneralSection.swift`:

```swift
import SwiftUI
import LillistCore

struct GeneralSection: View {
    @Binding var prefs: PreferencesStore.Prefs

    var body: some View {
        Section("Defaults") {
            Picker("Task list sort", selection: $prefs.defaultTaskListSort) {
                ForEach(SortField.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            ColorPicker("Default tag tint", selection: tintBinding)
        }
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { Color(hex: prefs.defaultTagTintHex) ?? .gray },
            set: { prefs.defaultTagTintHex = $0.toHex() ?? "#7F8FA6" }
        )
    }
}

private extension SortField {
    var displayName: String {
        switch self {
        case .manualPosition: "Manual"
        case .start: "Start date"
        case .deadline: "Deadline"
        case .title: "Title"
        case .createdAt: "Created"
        case .modifiedAt: "Modified"
        case .closedAt: "Closed"
        case .status: "Status"
        }
    }
}
```

`NotificationsSection.swift`:

```swift
import SwiftUI
import LillistCore

struct NotificationsSection: View {
    @Binding var prefs: PreferencesStore.Prefs
    @EnvironmentObject var services: AppServices
    @State private var permStatus: NotificationPermissions.Status = .notDetermined

    var body: some View {
        Section("All-day reminder time") {
            DatePicker("Default time", selection: hmBinding, displayedComponents: .hourAndMinute)
        }
        Section("Morning summary") {
            Toggle("Send a morning summary", isOn: $prefs.morningSummaryEnabled)
            if prefs.morningSummaryEnabled {
                DatePicker("Summary time", selection: morningBinding, displayedComponents: .hourAndMinute)
            }
        }
        Section("Permission") {
            HStack {
                statusLabel
                Spacer()
                Button("Test permission") {
                    Task { permStatus = await services.notificationPermissions.requestAuthorization() }
                }
            }
            if permStatus == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .task { permStatus = await services.notificationPermissions.currentStatus() }
    }

    @ViewBuilder private var statusLabel: some View {
        switch permStatus {
        case .granted: Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied:  Label("Denied",  systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .notDetermined: Label("Not yet requested", systemImage: "questionmark.circle")
        }
    }

    private var hmBinding: Binding<Date> {
        Binding(
            get: { date(Int(prefs.defaultAllDayHour), Int(prefs.defaultAllDayMinute)) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                prefs.defaultAllDayHour = Int16(c.hour ?? 9)
                prefs.defaultAllDayMinute = Int16(c.minute ?? 0)
            }
        )
    }

    private var morningBinding: Binding<Date> {
        Binding(
            get: { date(Int(prefs.morningSummaryHour), Int(prefs.morningSummaryMinute)) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                prefs.morningSummaryHour = Int16(c.hour ?? 9)
                prefs.morningSummaryMinute = Int16(c.minute ?? 0)
            }
        )
    }

    private func date(_ h: Int, _ m: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = h; c.minute = m
        return Calendar.current.date(from: c) ?? Date()
    }
}
```

`TrashSection.swift`:

```swift
import SwiftUI
import LillistCore

struct TrashSection: View {
    @Binding var prefs: PreferencesStore.Prefs
    @EnvironmentObject var services: AppServices
    @State private var isEmptying = false

    var body: some View {
        Section("Trash") {
            VStack(alignment: .leading) {
                Slider(
                    value: Binding(
                        get: { Double(prefs.trashRetentionDays) },
                        set: { prefs.trashRetentionDays = Int16($0.rounded()) }
                    ),
                    in: 7...365,
                    step: 1
                )
                Text("Retain trashed tasks for \(prefs.trashRetentionDays) days")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                Task { await emptyTrash() }
            } label: {
                if isEmptying { ProgressView() } else { Text("Empty Trash now") }
            }
            .disabled(isEmptying)
        }
    }

    private func emptyTrash() async {
        isEmptying = true; defer { isEmptying = false }
        try? await services.autoPurgeJob.runNow(forceAll: true)
    }
}
```

`QuickCaptureSection.swift` (iOS variant — no global hotkey):

```swift
import SwiftUI
import LillistCore

struct QuickCaptureSection: View {
    @Binding var prefs: PreferencesStore.Prefs

    var body: some View {
        Section("Quick Capture") {
            Toggle("Show floating + button", isOn: $prefs.quickCaptureEnabled)
            Link("Set up Lock Screen Shortcut",
                 destination: URL(string: "shortcuts://create-shortcut")!)
            Text("On iOS, Quick Capture lives in the Shortcuts app and the share sheet. Configure the Lock Screen Shortcut for one-tap capture.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
```

`CrashReportingSection.swift`:

```swift
import SwiftUI
import LillistCore

struct CrashReportingSection: View {
    @Binding var prefs: PreferencesStore.Prefs
    @EnvironmentObject var services: AppServices
    @State private var showSample = false

    var body: some View {
        Section("Crash reporting") {
            Toggle("Show prompt after Lillist quits unexpectedly", isOn: $prefs.showPostCrashPrompt)
            Text("Reports go directly to Mikey via email. No third-party telemetry.")
                .font(.footnote).foregroundStyle(.secondary)
            DisclosureGroup("View what would be sent", isExpanded: $showSample) {
                Text(services.crashReporter.samplePayloadPreview())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }
}
```

`AdvancedSection.swift`:

```swift
import SwiftUI
import LillistCore

struct AdvancedSection: View {
    @EnvironmentObject var services: AppServices
    @State private var exportedURL: URL?
    @State private var isExporting = false
    @State private var showShareSheet = false

    var body: some View {
        Section("Advanced") {
            Button {
                Task { await runExport() }
            } label: {
                if isExporting { ProgressView() } else { Text("Export now…") }
            }
            .disabled(isExporting)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareLink(item: url)
            }
        }
    }

    private func runExport() async {
        isExporting = true; defer { isExporting = false }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Lillist-Export-\(Int(Date().timeIntervalSince1970))")
        do {
            try await services.exporter.export(to: tmp)
            exportedURL = tmp
            showShareSheet = true
        } catch {
            print("Export failed: \(error)")
        }
    }
}
```

- [ ] **Step 3: Add a gear-icon entry on the iOS root view**

In `RootTabsView.swift` (created by Plan 8), add a top-bar trailing button:

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
    }
}
.sheet(isPresented: $showSettings) {
    SettingsTab().environmentObject(services)
}
```

…with `@State private var showSettings = false` on `RootTabsView`.

- [ ] **Step 4: Verify build**

```bash
xcodebuild build -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Lillist-iOS/Settings/ \
        Apps/Lillist-iOS/Lillist-iOS/RootTabsView.swift
git commit -m "feat(iOS): add SettingsTab with all six sections + gear entry"
```

---

## Task 15: iOS — snapshot tests for onboarding + each settings section

**Files:**
- Create: `Tests/Lillist-iOSTests/OnboardingScreenSnapshotTests.swift`
- Create: `Tests/Lillist-iOSTests/SettingsTabSnapshotTests.swift`

- [ ] **Step 1: Write `OnboardingScreenSnapshotTests`**

```swift
import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lillist_iOS
@testable import LillistCore

final class OnboardingScreenSnapshotTests: XCTestCase {
    func test_onboardingScreen_phone_lightDark() {
        let services = AppServicesFixture.inMemory()
        let view = OnboardingScreen(
            onboardingState: services.onboardingState,
            installer: services.defaultsInstaller,
            notificationPermissions: services.notificationPermissions
        )
        assertSnapshot(of: view, as: .image(on: .iPhone15Pro, precision: 0.99))
        assertSnapshot(of: view.preferredColorScheme(.dark),
                       as: .image(on: .iPhone15Pro, precision: 0.99))
    }

    func test_iCloudRequiredScreen() {
        let services = AppServicesFixture.inMemory()
        let view = ICloudRequiredScreen(accountMonitor: services.accountMonitor)
        assertSnapshot(of: view, as: .image(on: .iPhone15Pro, precision: 0.99))
    }
}
```

- [ ] **Step 2: Write `SettingsTabSnapshotTests`**

```swift
import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lillist_iOS
@testable import LillistCore

final class SettingsTabSnapshotTests: XCTestCase {
    func test_settingsTab_phone() {
        let services = AppServicesFixture.inMemory()
        let view = SettingsTab().environmentObject(services)
        assertSnapshot(of: view, as: .image(on: .iPhone15Pro, precision: 0.99))
        assertSnapshot(of: view.preferredColorScheme(.dark),
                       as: .image(on: .iPhone15Pro, precision: 0.99))
    }

    func test_settingsTab_pad() {
        let services = AppServicesFixture.inMemory()
        let view = SettingsTab().environmentObject(services)
        assertSnapshot(of: view, as: .image(on: .iPadPro11, precision: 0.99))
    }
}
```

- [ ] **Step 3: Record baselines**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:Lillist-iOSTests/OnboardingScreenSnapshotTests \
    -only-testing:Lillist-iOSTests/SettingsTabSnapshotTests \
    SNAPSHOT_RECORD=1
```

Expected: tests record baselines. Re-run without `SNAPSHOT_RECORD` for a green pass.

- [ ] **Step 4: Commit**

```bash
git add Tests/Lillist-iOSTests/OnboardingScreenSnapshotTests.swift \
        Tests/Lillist-iOSTests/SettingsTabSnapshotTests.swift \
        Tests/Lillist-iOSTests/__Snapshots__/
git commit -m "test(iOS): snapshot onboarding + Settings tab (phone/pad, light/dark)"
```

---

## Task 16: iOS — notification permission flow test (mocked)

**Files:**
- Create: `Tests/Lillist-iOSTests/NotificationPermissionFlowTests.swift`

- [ ] **Step 1: Write the test**

```swift
import XCTest
@testable import Lillist_iOS
@testable import LillistCore

final class NotificationPermissionFlowTests: XCTestCase {
    func test_grantedPath_installsDefaults() async throws {
        let services = AppServicesFixture.inMemory()
        let mock = services.notificationPermissions as! MockNotificationPermissions
        mock.scriptedRequestResult = .granted

        let status = await services.notificationPermissions.requestAuthorization()
        XCTAssertEqual(status, .granted)
        try await services.defaultsInstaller.installIfNeeded()
        try await services.onboardingState.markCompleted()
        let names = try await services.smartFilters.list().map(\.name).sorted()
        XCTAssertEqual(names, ["No Tags", "Recently Closed", "Stale", "This Week", "Today"])
        XCTAssertTrue(try await services.onboardingState.hasCompletedOnboarding())
    }

    func test_deniedPath_completesAnyway() async throws {
        let services = AppServicesFixture.inMemory()
        let mock = services.notificationPermissions as! MockNotificationPermissions
        mock.scriptedRequestResult = .denied
        _ = await services.notificationPermissions.requestAuthorization()
        try await services.onboardingState.markCompleted()
        XCTAssertTrue(try await services.onboardingState.hasCompletedOnboarding())
    }
}
```

- [ ] **Step 2: Run tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:Lillist-iOSTests/NotificationPermissionFlowTests
```

Expected: PASS, 2 tests.

- [ ] **Step 3: Commit**

```bash
git add Tests/Lillist-iOSTests/NotificationPermissionFlowTests.swift
git commit -m "test(iOS): cover granted + denied permission paths through onboarding"
```

---

## Task 17: Final integration sweep + documentation

**Files:**
- Modify: `Packages/LillistCore/README.md` (append a section)

- [ ] **Step 1: Run all LillistCore tests**

Run: `cd Packages/LillistCore && swift test`
Expected: full Plan 1+ suite plus `OnboardingStateTests` (3) and `DefaultsInstallerTests` (4) all green.

- [ ] **Step 2: Run all macOS app tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
    -destination 'platform=macOS' -quiet
```

Expected: green, including the new snapshot suites and `NotificationPermissionFlowTests`.

- [ ] **Step 3: Run all iOS app tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: green.

- [ ] **Step 4: Document Plan 10 scope in the LillistCore README**

Append to `Packages/LillistCore/README.md`:

```markdown
## Plan 10 scope

Plan 10 adds first-launch onboarding and pre-installed defaults, plus the
cross-platform Preferences/Settings UIs.

- `Onboarding/OnboardingState` — reads/writes `hasCompletedOnboarding` on `AppPreferences`.
- `Onboarding/DefaultsInstaller` — idempotently installs five default smart filters: Today, This Week, No Tags, Recently Closed, Stale.
- `PreferencesStore.Prefs` gains `hasCompletedOnboarding`, `quickCaptureEnabled`, `quickCaptureHotkey`, `statusBarItemVisible`, `showPostCrashPrompt`, `defaultTagTintHex`.
- macOS app: `Settings { … }` scene with six panes (General, Notifications, Trash, Quick Capture, Crash Reporting, Advanced). Onboarding presented as a sheet on first launch.
- iOS app: `SettingsTab` with parallel sections (Quick Capture diverges to Lock Screen Shortcut). Onboarding presented as a full-screen cover on first launch.
- Plan 3 follow-up: `Field.hasTags` added (boolean) to power the "No Tags" default filter.
- Empty tag tree by design: no pre-installed tags.

See design Section 7 ("Onboarding" and "Pre-installed defaults") and Section 4 ("Permissions").
```

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/README.md
git commit -m "docs: document Plan 10 onboarding + preferences scope in LillistCore README"
```

- [ ] **Step 6: Tag the milestone**

```bash
git tag -a plan-10-onboarding-preferences -m "Lillist Plan 10: Onboarding and Preferences complete"
```

Plan 10 is complete.

---

## Self-Review Checklist (run by the implementer before merging)

- [ ] `OnboardingState.hasCompletedOnboarding()` returns `false` on a brand-new store and `true` after `markCompleted()`.
- [ ] `DefaultsInstaller.installIfNeeded()` invoked twice produces exactly five filters.
- [ ] All five default filter names match exactly: `Today`, `This Week`, `No Tags`, `Recently Closed`, `Stale`.
- [ ] No default tags are created anywhere in this plan (`grep -r 'TagStore.*create' Packages/LillistCore/Sources/LillistCore/Onboarding/` returns nothing).
- [ ] macOS onboarding sheet uses `.interactiveDismissDisabled(true)` and only dismisses via `Get started` / `Skip for now`.
- [ ] iOS onboarding cover does the same.
- [ ] iCloud-unavailable path is gated and recoverable (Try again recheck works).
- [ ] Notification permission denied path surfaces a Settings deep-link on both platforms.
- [ ] Every preferences pane reads through `PreferencesStore.read()` and writes through `PreferencesStore.update`.
- [ ] Snapshot baselines exist for all panes/sections in both light and dark, on both platforms.
- [ ] Quick Capture pane on macOS has a hotkey recorder; iOS variant only exposes the floating-+ toggle + a Lock Screen Shortcut hint.
- [ ] No `try!`, no `fatalError`, no force unwraps of `Optional` user-facing values introduced.
- [ ] `Field.hasTags` is exercised by at least one rule-engine fixture (added in Task 4 if missing).
