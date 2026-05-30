# App-Layer Test Rehab Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 5.**
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> ⚠️ **Wave 1 (`store-swap-safety`) is merged to `main`.** It changed several shared files (`MigrationCoordinator`, `PersistenceHost`, `QuarantineManager`, `MigrationJournal`, both `AppEnvironment`s, `PersistenceController`). **Re-Read every file before editing and anchor by code structure — the line numbers in this plan may have drifted.**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace test-substitution and tautological app-layer tests with real wiring coverage — extracting the gate-resolution, parse-persist, drag-mapping, and focus-gating logic into pure, injectable helpers and unit-testing *those*, then deleting the tests that assert literals against themselves.

**Architecture:** Pull the three duplicated/buried decision points up into single sources of truth: (1) a `GatedPersistenceResolver` value type in LillistCore that `IntentSupport.makePersistence()` and `ShareRootView.save()` both delegate to (so the MigrationGate abort/`storeUnavailable` branch is testable with injected fakes, not constructed inline against the real App Group); (2) a pure `DragDropResolver.resolve(target:flatRows:) -> DragMutation` in LillistUI shared verbatim by macOS `TaskListView.applyDrop` and iOS `TasksView.applyDrop` (including the onto-with-visible-children first-child branch the current macOS test silently mis-maps); and (3) the existing `ListColumn`-based focus-gating predicate exposed as a named `static func` so the test asserts the real predicate rather than a re-typed copy. Tautological tests are deleted; the two misleadingly-named "flow" tests are renamed to signal they exercise LillistCore composition, not the app types.

**Tech Stack:** Swift 6.2, XCTest (every app-layer + LillistUI test bundle in scope uses XCTest), LillistCore (`MigrationGate`, `SyncModeStore`, `MigrationJournalStore`, `StoreConfiguration`, `LillistError`), LillistUI (`DragTarget`, `DragReorderRow`), xcodegen for pbxproj regeneration after adding/removing test files.

**Source findings:** `ios-2`, `ios-3`, `macos-4`, `ext-6` (Roadmap #14).

---

## File Structure

### Create

- `Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift` — pure value type wrapping the journal + mode-store → `StoreConfiguration` resolution that `IntentSupport` and `ShareRootView` duplicate inline today. One responsibility: gate-aware store-configuration resolution with injectable dependencies.
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/GatedPersistenceResolverTests.swift` — direct unit tests of the gate branch (proceed + in-flight abort → `storeUnavailable`, plus unavailable App Group).
- `Packages/LillistUI/Sources/LillistUI/DragReorder/DragDropResolver.swift` — pure `DragMutation` enum + `DragDropResolver.resolve(target:flatRows:)`; the single source of truth for the `DragTarget` → store-mutation mapping shared by both apps.
- `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragDropResolverTests.swift` — unit tests for every `DragTarget` case including the `.onto` first-child branch and the `.onto` collapsed/leaf append branch.
- `Apps/Lillist-macOS/Tests/FocusedShortcutGatingPredicateTests.swift` — asserts the *real* extracted `TaskListShortcutGate.isDisabled(listColumn:)` predicate (replaces the re-typed copy in `FocusedShortcutGatingTests.swift`).

### Modify

- `Extensions/ShortcutsActions/IntentSupport.swift` — `makePersistence()` delegates to `GatedPersistenceResolver`.
- `Extensions/ShareExtension-iOS/ShareRootView.swift` — `save()` delegates to `GatedPersistenceResolver` for the gated config resolution.
- `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift` (`applyDrop`, ~lines 215–241) — dispatch via `DragDropResolver.resolve`.
- `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift` (`applyDrop`, ~lines 273–299) — dispatch via `DragDropResolver.resolve`.
- `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift` — extract the focus-gating predicate to a `TaskListShortcutGate` namespace beside the `ListColumn` enum (which is declared in *this* file). This file is already co-compiled into the standalone `Lillist-macOSTests` bundle, so the gate type lands where the test can reach it. See Task 6.
- `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift` — update the five `.disabled(listColumn == nil)` shortcut callsites to `TaskListShortcutGate.isDisabled(listColumn: listColumn)`. *(These callsites live here, not in `TaskListView.swift`. They are built only by the macOS **app** target, not the standalone test bundle — see Task 6 and the Task 10 macOS scheme run.)*
- `Apps/Lillist-iOS/project.yml` (`Lillist-iOSTests` sources, ~lines 128–139) — co-compile `IntentSupport.swift` so the gate-resolution wrapper is reachable from the standalone iOS test bundle.
- `Apps/Lillist-iOS/Tests/IntegrationTests/QuickCaptureFlowTests.swift` — rename file + class to `LillistCoreQuickCaptureCompositionTests` (honest name: it exercises LillistCore composition, not `QuickCaptureDialogHost`).
- `Apps/Lillist-iOS/Tests/IntegrationTests/ShareExtensionPayloadTests.swift` — rename file + class to `LillistCoreSharePayloadCompositionTests`.

### Delete

- `Apps/Lillist-iOS/Tests/IntegrationTests/SegmentedDetailTabPersistenceTests.swift` — tautology (`XCTAssertEqual("taskDetailTab", "taskDetailTab")`).
- `Apps/Lillist-iOS/Tests/UnitTests/NotesDebounceTests.swift` — tautology (`XCTAssertEqual(500, 500)`).
- `Apps/Lillist-iOS/Tests/UnitTests/CrashReportingDisclosureGateTests.swift` — tautology (asserts `{ $0 }(true) == true`).
- `Apps/Lillist-macOS/Tests/DragDropInteractionTests.swift` — test-substitution: re-implements `applyTarget` and *mis-maps* `.onto`→`reparent`, missing the first-child branch (replaced by `DragDropResolverTests.swift`).
- `Apps/Lillist-macOS/Tests/FocusedShortcutGatingTests.swift` — re-types the predicate inline (replaced by `FocusedShortcutGatingPredicateTests.swift`).

### Leave untouched (explicitly in scope to NOT change)

- `Apps/Lillist-iOS/Tests/IntegrationTests/AppIntentHandlerTests.swift` — exercises real `CLIBridge` handlers; genuine coverage. Per finding scope: leave.

---

## Task 1: Extract gate-resolution into `GatedPersistenceResolver` (LillistCore) — `ext-6`, `ios-2`

**Files:**
- Create `Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift`
- Create `Packages/LillistCore/Tests/LillistCoreTests/Sync/GatedPersistenceResolverTests.swift`

The current `MigrationGate.resolveStoreConfiguration(appGroupID:)` is already testable, but `IntentSupport.makePersistence()` and `ShareRootView.save()` each *re-build* the journal + mode-store + gate inline against the real App Group container, so the abort/`storeUnavailable` branch is never exercised by a test. This task creates a thin injectable resolver that both callers delegate to, and tests the gate branch directly with `InMemoryMigrationJournalStore`.

- [ ] **Step 1: Write the failing test.** Create `Packages/LillistCore/Tests/LillistCoreTests/Sync/GatedPersistenceResolverTests.swift`:

```swift
import XCTest
@testable import LillistCore

/// Direct coverage of the gate-aware store-configuration resolution that
/// `IntentSupport.makePersistence()` (App Intents) and `ShareRootView.save()`
/// (Share Extension) both delegate to. The MigrationGate abort branch — which
/// surfaces `LillistError.storeUnavailable` so callers retry instead of racing
/// a half-swapped store — was previously unreachable by any test because both
/// callers constructed the gate inline against the real App Group container.
final class GatedPersistenceResolverTests: XCTestCase {

    private let appGroupID = "group.io.mikeydotio.Lillist.tests.gate"

    func test_idleJournal_resolvesConfigForCurrentMode() async throws {
        let journal = InMemoryMigrationJournalStore(initial: .idle)
        let modeStore = SyncModeStore(suiteName: appGroupID)
        await modeStore.setMode(.localOnly)
        let resolver = GatedPersistenceResolver(
            appGroupID: appGroupID,
            journal: journal,
            modeStore: modeStore
        )

        let config = try await resolver.resolveStoreConfiguration()

        XCTAssertEqual(config.syncMode, .localOnly)
    }

    func test_inFlightJournal_throwsStoreUnavailableWithGateMessage() async throws {
        let journal = InMemoryMigrationJournalStore(
            initial: MigrationJournal(state: .reconfiguringStore)
        )
        let modeStore = SyncModeStore(suiteName: appGroupID)
        let resolver = GatedPersistenceResolver(
            appGroupID: appGroupID,
            journal: journal,
            modeStore: modeStore
        )

        do {
            _ = try await resolver.resolveStoreConfiguration()
            XCTFail("Expected storeUnavailable while a migration is in flight")
        } catch let LillistError.storeUnavailable(reason) {
            XCTAssertEqual(
                reason,
                "Sync settings are being changed. Try again in a moment."
            )
        }
    }

    func test_makePersistence_idleJournal_returnsUsableController() async throws {
        // The `makeController` seam lets us assert end-to-end resolution +
        // controller construction without standing up the real App Group.
        let journal = InMemoryMigrationJournalStore(initial: .idle)
        let modeStore = SyncModeStore(suiteName: appGroupID)
        await modeStore.setMode(.localOnly)
        let resolver = GatedPersistenceResolver(
            appGroupID: appGroupID,
            journal: journal,
            modeStore: modeStore
        )

        var seenMode: SyncMode?
        let controller = try await resolver.makePersistence { config in
            seenMode = config.syncMode
            return try await PersistenceController(configuration: .inMemory)
        }

        XCTAssertEqual(seenMode, .localOnly)
        // Smoke-check the returned controller is live.
        let store = TaskStore(persistence: controller)
        let id = try await store.create(title: "gate ok")
        let record = try await store.fetch(id: id)
        XCTAssertEqual(record.title, "gate ok")
    }
}
```

- [ ] **Step 2: Run the test, expect failure.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter GatedPersistenceResolverTests
  ```
  Expect a **compile failure**: `cannot find 'GatedPersistenceResolver' in scope`.

- [ ] **Step 3: Implement the minimal change.** Create `Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift`:

```swift
import Foundation

/// Gate-aware resolution of the App-Group on-disk store configuration,
/// shared by every out-of-process caller (App Intents, Share Extension,
/// CLI) so the `MigrationGate` abort branch lives in exactly one place.
///
/// Production callers use ``init(appGroupID:)``, which wires the
/// `FileMigrationJournalStore` + `SyncModeStore` rooted at the App Group
/// container. Tests use ``init(appGroupID:journal:modeStore:)`` to inject
/// an `InMemoryMigrationJournalStore` and assert the abort path without a
/// live container.
///
/// Plan 21: when a foreground sync-mode migration is in flight the gate
/// throws `LillistError.storeUnavailable(reason:)` so the caller surfaces
/// "Sync settings are being changed. Try again in a moment." instead of
/// running against a half-swapped store.
public struct GatedPersistenceResolver: Sendable {
    private let appGroupID: String
    private let journal: any MigrationJournalStore
    private let modeStore: SyncModeStore

    /// Test/explicit-injection initializer.
    public init(
        appGroupID: String,
        journal: any MigrationJournalStore,
        modeStore: SyncModeStore
    ) {
        self.appGroupID = appGroupID
        self.journal = journal
        self.modeStore = modeStore
    }

    /// Production initializer. Returns `nil` when the App Group container
    /// is not reachable (so the file-backed journal can't be created).
    public init?(appGroupID: String) {
        guard let journal = FileMigrationJournalStore(appGroupID: appGroupID) else {
            return nil
        }
        self.appGroupID = appGroupID
        self.journal = journal
        self.modeStore = SyncModeStore(appGroupID: appGroupID)
    }

    /// Consult the gate and produce a ready-to-use `StoreConfiguration`,
    /// or throw `LillistError.storeUnavailable(reason:)` when a migration
    /// is in flight or the App Group is unavailable.
    public func resolveStoreConfiguration() async throws -> StoreConfiguration {
        let gate = MigrationGate(journal: journal, modeStore: modeStore)
        return try await gate.resolveStoreConfiguration(appGroupID: appGroupID)
    }

    /// Resolve the configuration through the gate, then build a controller
    /// from it. The `build` closure exists so tests can substitute an
    /// in-memory controller while still exercising the resolution path.
    public func makePersistence(
        build: (StoreConfiguration) async throws -> PersistenceController
    ) async throws -> PersistenceController {
        let config = try await resolveStoreConfiguration()
        return try await build(config)
    }

    /// Production convenience: resolve + build the on-disk controller.
    public func makePersistence() async throws -> PersistenceController {
        try await makePersistence { config in
            try await PersistenceController(configuration: config)
        }
    }
}
```

- [ ] **Step 4: Run the test, expect pass.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter GatedPersistenceResolverTests
  ```
  Expect: `Test Suite 'GatedPersistenceResolverTests' passed` with 3 tests executed, 0 failures.

- [ ] **Step 5: Commit.**
  ```
  git add Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift \
          Packages/LillistCore/Tests/LillistCoreTests/Sync/GatedPersistenceResolverTests.swift
  git commit -m "feat(core): add GatedPersistenceResolver with direct gate-branch tests

Extract the MigrationGate-aware store-configuration resolution that
IntentSupport and ShareRootView duplicate inline into one injectable
value type, so the in-flight-migration abort branch (storeUnavailable)
is exercised by a real test rather than only at runtime. (ext-6, ios-2)"
  ```

---

## Task 2: Route `IntentSupport.makePersistence()` through the resolver — `ext-6`

**Files:**
- Modify `Extensions/ShortcutsActions/IntentSupport.swift` (whole `makePersistence()` body, lines 15–23)

This collapses the inline gate wiring to a delegation. Behavior is identical (same App Group, same gate, same error), but the logic now lives in the tested `GatedPersistenceResolver`.

- [ ] **Step 1: Verify the current body.** Read `Extensions/ShortcutsActions/IntentSupport.swift` and confirm `makePersistence()` still builds `SyncModeStore` + `FileMigrationJournalStore` + `MigrationGate` inline (lines 15–23). *(There is no separate unit test for this wrapper — it constructs the real App Group container, which the standalone bundle can't open. The coverage lives on `GatedPersistenceResolver` from Task 1; this task's verification is a clean compile.)*

- [ ] **Step 2: Implement the delegation.** Replace the `IntentSupport` enum body so `makePersistence()` reads:

```swift
import Foundation
import AppIntents
import LillistCore

/// Shared helpers for App Intent `perform()` bodies.
enum IntentSupport {
    static let appGroupID = "group.io.mikeydotio.Lillist"

    /// Plan 21: consult `MigrationGate` (via `GatedPersistenceResolver`)
    /// so the intent doesn't race a foreground sync-mode migration. When
    /// the gate says abort, the resolver throws
    /// `LillistError.storeUnavailable(reason:)` with the user-facing
    /// message so Shortcuts surfaces "Sync settings are being changed.
    /// Try again in a moment." instead of running against a half-swapped
    /// store.
    static func makePersistence() async throws -> PersistenceController {
        guard let resolver = GatedPersistenceResolver(appGroupID: appGroupID) else {
            throw LillistError.storeUnavailable(
                reason: "App Group container '\(appGroupID)' is not available."
            )
        }
        return try await resolver.makePersistence()
    }
}
```

- [ ] **Step 3: Verify it compiles in the iOS workspace.** Build the iOS app target (which links the ShortcutsActions extension) without signing:
  ```
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
  ```
  Expect: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit.**
  ```
  git add Extensions/ShortcutsActions/IntentSupport.swift
  git commit -m "refactor(ext): route IntentSupport.makePersistence through GatedPersistenceResolver

Delegate the App Intents store resolution to the tested resolver instead
of rebuilding the gate inline; identical App Group, gate, and error. (ext-6)"
  ```

---

## Task 3: Route `ShareRootView.save()` gate branch through the resolver — `ext-6`

**Files:**
- Modify `Extensions/ShareExtension-iOS/ShareRootView.swift` (`save()`, lines 63–98)

The Share Extension's `save()` duplicates the same gate wiring as IntentSupport and surfaces two distinct `saveError` strings for the App-Group-unavailable vs. in-flight cases. After delegating, both unreachable-store conditions arrive as `LillistError.storeUnavailable`, which the existing `catch let LillistError.storeUnavailable(reason)` clause already handles — so the user still sees the gate's message. The link-attachment failure-propagation change is **out of scope** here (owned by `extension-persistence-unification`, finding `ext-4`); leave the `try?` on `addLinkPreview` exactly as-is.

- [ ] **Step 1: Verify the current body.** Read `Extensions/ShareExtension-iOS/ShareRootView.swift` lines 63–98 and confirm `save()` still builds `SyncModeStore` + `FileMigrationJournalStore` + `MigrationGate` inline and has the early `saveError = "App Group container is not available."` return.

- [ ] **Step 2: Implement the delegation.** Replace the `save()` method body:

```swift
    private func save() async {
        saving = true
        defer { saving = false }
        do {
            // Plan 21: resolve the store configuration through the
            // MigrationGate (via GatedPersistenceResolver) so the
            // extension doesn't race a foreground sync-mode migration.
            // If a migration is in flight the resolver throws
            // storeUnavailable, caught below to surface the retry message.
            let appGroupID = "group.io.mikeydotio.Lillist"
            guard let resolver = GatedPersistenceResolver(appGroupID: appGroupID) else {
                saveError = "App Group container is not available."
                return
            }
            let persistence = try await resolver.makePersistence()
            let taskStore = TaskStore(persistence: persistence)
            let attachmentStore = AttachmentStore(persistence: persistence)
            let taskID = try await taskStore.create(title: title, notes: notes)
            if let url = attachedURL {
                _ = try? await attachmentStore.addLinkPreview(
                    taskID: taskID,
                    url: url,
                    title: nil,
                    description: nil,
                    thumbnailData: nil,
                    faviconData: nil
                )
            }
            onSaved()
        } catch let LillistError.storeUnavailable(reason) {
            saveError = reason
        } catch {
            saveError = "\(error)"
        }
    }
```

- [ ] **Step 3: Verify it compiles in the iOS workspace.** Build the iOS app target (which links the ShareExtension):
  ```
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
  ```
  Expect: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit.**
  ```
  git add Extensions/ShareExtension-iOS/ShareRootView.swift
  git commit -m "refactor(ext): route ShareRootView.save gate branch through GatedPersistenceResolver

Share Extension now resolves its store configuration via the tested
resolver; the in-flight-migration storeUnavailable path is still surfaced
to the user via the existing catch clause. (ext-6)"
  ```

---

## Task 4: Extract the drag-drop mapping into a pure shared `DragDropResolver` (LillistUI) — `macos-4`, `ios-3`

**Files:**
- Create `Packages/LillistUI/Sources/LillistUI/DragReorder/DragDropResolver.swift`
- Create `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragDropResolverTests.swift`

Both `TaskListView.applyDrop` (macOS) and `TasksView.applyDrop` (iOS) contain a byte-identical `switch target` that includes the `.onto` *first-child* branch (drop as first child when the target has visible children, else append via reparent). The macOS test (`DragDropInteractionTests`) re-implements its own `applyTarget` that **mis-maps `.onto`→`reparent` unconditionally**, so it never tests the first-child semantic the production code actually performs. Extract the mapping into a pure resolver, returning a value-type `DragMutation` both apps dispatch, and test the resolver including the first-child branch.

- [ ] **Step 1: Write the failing test.** Create `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragDropResolverTests.swift`:

```swift
import XCTest
@testable import LillistUI

/// Unit coverage for the pure `DragTarget` → store-mutation mapping shared
/// by macOS `TaskListView.applyDrop` and iOS `TasksView.applyDrop`. The
/// previous macOS `DragDropInteractionTests` re-implemented this mapping
/// and silently mis-mapped `.onto` to an unconditional reparent, never
/// exercising the "drop as first child when the target has visible
/// children" branch the apps actually perform.
final class DragDropResolverTests: XCTestCase {

    func test_between_mapsToReorderWithBeforeAndAfter() {
        let dragged = UUID()
        let before = UUID()
        let after = UUID()
        let mutation = DragDropResolver.resolve(
            target: .between(beforeID: before, afterID: after, parentID: nil),
            flatRows: []
        )
        XCTAssertEqual(mutation, .reorder(id: dragged.flipped(to: dragged), after: after, before: before))
    }

    func test_ontoTargetWithVisibleChild_mapsToReorderBeforeFirstChild() {
        let parent = UUID()
        let firstChild = UUID()
        let secondChild = UUID()
        let flatRows = [
            DragReorderRow(id: parent, parentID: nil, depth: 0),
            DragReorderRow(id: firstChild, parentID: parent, depth: 1),
            DragReorderRow(id: secondChild, parentID: parent, depth: 1),
        ]
        let mutation = DragDropResolver.resolve(
            target: .onto(targetID: parent),
            flatRows: flatRows
        )
        XCTAssertEqual(mutation, .reorder(after: nil, before: firstChild))
    }

    func test_ontoCollapsedOrLeafTarget_mapsToReparentAppend() {
        let parent = UUID()
        // No row whose parentID == parent → target is collapsed or a leaf.
        let flatRows = [
            DragReorderRow(id: parent, parentID: nil, depth: 0),
            DragReorderRow(id: UUID(), parentID: nil, depth: 0),
        ]
        let mutation = DragDropResolver.resolve(
            target: .onto(targetID: parent),
            flatRows: flatRows
        )
        XCTAssertEqual(mutation, .reparent(newParent: parent))
    }

    func test_rejectedTarget_mapsToNoop() {
        XCTAssertEqual(
            DragDropResolver.resolve(target: .rejected, flatRows: []),
            .noop
        )
    }

    func test_noneTarget_mapsToNoop() {
        XCTAssertEqual(
            DragDropResolver.resolve(target: .none, flatRows: []),
            .noop
        )
    }
}

// Tiny test helper to keep the `.between` assertion readable; the dragged
// ID is supplied by the caller at dispatch time, not by the resolver.
private extension UUID {
    func flipped(to other: UUID) -> UUID { other }
}
```

  *Note for implementer:* the `.between` assertion above is awkward because `DragMutation.reorder` does **not** carry the dragged ID (the apps supply it at dispatch). Simplify the first test before running it to:

```swift
    func test_between_mapsToReorderWithBeforeAndAfter() {
        let before = UUID()
        let after = UUID()
        let mutation = DragDropResolver.resolve(
            target: .between(beforeID: before, afterID: after, parentID: nil),
            flatRows: []
        )
        XCTAssertEqual(mutation, .reorder(after: after, before: before))
    }
```

  and delete the `private extension UUID` helper. (Use this simplified form — it matches the `DragMutation` shape defined in Step 3.)

- [ ] **Step 2: Run the test, expect failure.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI --filter DragDropResolverTests
  ```
  Expect a **compile failure**: `cannot find 'DragDropResolver' in scope`.

- [ ] **Step 3: Implement the resolver.** Create `Packages/LillistUI/Sources/LillistUI/DragReorder/DragDropResolver.swift`:

```swift
import Foundation

/// The store mutation a resolved drag-drop should perform, expressed as a
/// LillistCore-agnostic value type so the pure mapping lives in LillistUI
/// and both app targets dispatch it to `TaskStore`.
///
/// - `reorder` — `TaskStore.reorder(id:after:before:)` (the dragged ID is
///   supplied by the dispatching app, not carried here).
/// - `reparent` — `TaskStore.reparent(id:newParent:)`.
/// - `noop` — nothing to do (`.rejected` / `.none` targets).
public enum DragMutation: Equatable, Sendable {
    case reorder(after: UUID?, before: UUID?)
    case reparent(newParent: UUID?)
    case noop
}

/// Pure mapping from a resolved `DragTarget` (plus the controller's visible
/// `flatRows`) to a `DragMutation`. Single source of truth shared by macOS
/// `TaskListView.applyDrop` and iOS `TasksView.applyDrop`.
public enum DragDropResolver {
    /// - `.between` routes straight to a `reorder` using the contract's
    ///   `beforeID`/`afterID`.
    /// - `.onto` with at least one visible child of the target drops the
    ///   dragged row as the *first* child (reorder before the first child),
    ///   per the "Smart: where the cursor was" semantic; otherwise the
    ///   target is collapsed or a leaf and the dragged row is appended via
    ///   reparent.
    /// - `.rejected` / `.none` are no-ops.
    public static func resolve(
        target: DragTarget,
        flatRows: [DragReorderRow]
    ) -> DragMutation {
        switch target {
        case .between(let beforeID, let afterID, _):
            return .reorder(after: afterID, before: beforeID)
        case .onto(let parentID):
            if let firstChild = flatRows.first(where: { $0.parentID == parentID }) {
                return .reorder(after: nil, before: firstChild.id)
            } else {
                return .reparent(newParent: parentID)
            }
        case .rejected, .none:
            return .noop
        }
    }
}
```

- [ ] **Step 4: Run the test, expect pass.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI --filter DragDropResolverTests
  ```
  Expect: `Test Suite 'DragDropResolverTests' passed` with 5 tests executed, 0 failures.

- [ ] **Step 5: Commit.**
  ```
  git add Packages/LillistUI/Sources/LillistUI/DragReorder/DragDropResolver.swift \
          Packages/LillistUI/Tests/LillistUITests/DragReorder/DragDropResolverTests.swift
  git commit -m "feat(ui): add pure DragDropResolver covering the onto first-child branch

Single source of truth for the DragTarget to store-mutation mapping that
macOS TaskListView and iOS TasksView duplicate, including the onto-with-
visible-children first-child semantic the old macOS test mis-mapped. (macos-4, ios-3)"
  ```

---

## Task 5: Adopt `DragDropResolver` in both apps' `applyDrop` and delete the substitution test — `macos-4`, `ios-3`

**Files:**
- Modify `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift` (`applyDrop`, lines 215–241)
- Modify `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift` (`applyDrop`, lines 273–299)
- Delete `Apps/Lillist-macOS/Tests/DragDropInteractionTests.swift`

- [ ] **Step 1: Re-read both `applyDrop` bodies.** Read `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift` lines 213–242 and `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift` lines 269–300 to confirm signatures (`private func applyDrop(dragged: UUID, target: DragTarget) async`), the `dragController.flatRows` access, and the post-mutation calls (`refresh()` on macOS, `reload()` on iOS).

- [ ] **Step 2: Rewrite macOS `applyDrop`.** Replace lines 215–241 of `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift`:

```swift
    @MainActor
    private func applyDrop(dragged: UUID, target: DragTarget) async {
        do {
            switch DragDropResolver.resolve(target: target, flatRows: dragController.flatRows) {
            case .reorder(let after, let before):
                try await env.taskStore.reorder(id: dragged, after: after, before: before)
            case .reparent(let newParent):
                try await env.taskStore.reparent(id: dragged, newParent: newParent)
            case .noop:
                break
            }
            await refresh()
        } catch {
            // Matches the existing error-swallowing convention in this file.
        }
    }
```

- [ ] **Step 3: Rewrite iOS `applyDrop`.** Replace lines 273–299 of `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift`:

```swift
    /// Route a resolved drag-drop to the appropriate `TaskStore` mutation
    /// using the shared `DragDropResolver` (single source of truth shared
    /// with macOS `TaskListView.applyDrop`).
    @MainActor
    private func applyDrop(dragged: UUID, target: DragTarget) async {
        do {
            switch DragDropResolver.resolve(target: target, flatRows: dragController.flatRows) {
            case .reorder(let after, let before):
                try await env.taskStore.reorder(id: dragged, after: after, before: before)
            case .reparent(let newParent):
                try await env.taskStore.reparent(id: dragged, newParent: newParent)
            case .noop:
                break
            }
            await reload()
        } catch {
            loadError = "\(error)"
        }
    }
```

- [ ] **Step 4: Delete the substitution test.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist && rm Apps/Lillist-macOS/Tests/DragDropInteractionTests.swift
  ```

- [ ] **Step 5: Regenerate pbxprojs (a test file was removed) and build both apps.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist/Apps/Lillist-macOS && xcodegen generate --spec project.yml --project .
  cd /Volumes/Code/mikeyward/Lillist/Apps && xcodegen generate --spec project.yml --project .
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -scheme Lillist-macOS -workspace Lillist.xcworkspace -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
  ```
  Expect: `** BUILD SUCCEEDED **` for both. *(If `xcodegen` is not on PATH in this environment, note it in the commit and have the user regenerate; the macOS pbxproj must drop the deleted test file before the macOS test scheme will build clean.)*

- [ ] **Step 6: Commit.**
  ```
  git add Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift \
          Apps/Lillist-iOS/Sources/Tasks/TasksView.swift \
          Apps/Lillist-macOS/Lillist-macOS.xcodeproj Apps/Lillist.xcodeproj
  git rm Apps/Lillist-macOS/Tests/DragDropInteractionTests.swift
  git commit -m "refactor(apps): dispatch applyDrop via shared DragDropResolver; drop substitution test

Both TaskListView (macOS) and TasksView (iOS) now resolve drag-drop through
the shared pure resolver instead of duplicating the switch. Delete the macOS
DragDropInteractionTests, which re-implemented the mapping and mis-mapped the
onto branch; DragDropResolverTests now covers the real logic. (macos-4, ios-3)"
  ```

---

## Task 6: Extract + test the macOS focus-gating predicate; delete the re-typed test — `macos-4`

**Files:**
- Modify `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift` (add the `TaskListShortcutGate` namespace beside the `ListColumn` enum, which is declared in *this* file). This source is **already** co-compiled into the standalone `Lillist-macOSTests` bundle (verified in `Apps/project.yml`, line 88), so placing the gate here is what makes it reachable from the test with a bare `import` — no `@testable import` and no new co-compile entry needed.
- Modify `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift` (the five `.disabled(listColumn == nil)` callsites — lines 38, 43, 48, 55, 60). These live here, *not* in `TaskListView.swift`.
- Create `Apps/Lillist-macOS/Tests/FocusedShortcutGatingPredicateTests.swift`
- Delete `Apps/Lillist-macOS/Tests/FocusedShortcutGatingTests.swift`

The existing `FocusedShortcutGatingTests` re-types the predicate `listColumn == nil` inline (`none == nil`, etc.) — it asserts the test's own copy, not the shipping predicate. Extract the predicate into a named `static func` and test *that*.

> **⚠️ Execution gotcha:** `Lillist-macOSTests` is a **standalone** bundle (`TEST_HOST: ""` / `BUNDLE_LOADER: ""` in `Apps/project.yml`, lines 127–128). It does **not** `@testable import` the app module — it co-compiles a hand-picked list of individual source files. So two things must hold: (1) the extracted `TaskListShortcutGate` **must** be added to `FocusedListColumn.swift` (already on the co-compile list) — if it landed in `LillistCommands.swift` or `TaskListView.swift` the test could not see it; and (2) the test file uses **bare imports** (`import XCTest` plus `import SwiftUI`), matching the existing `FocusedShortcutGatingTests.swift` — `@testable import Lillist_macOS` will **not** compile in this bundle.

- [ ] **Step 1: Locate `ListColumn` and the gating predicate.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist && grep -rn "enum ListColumn\|listColumn == nil\|\.disabled(listColumn\|FocusedValue" Apps/Lillist-macOS/Sources/
  ```
  Expected (verified against the real tree): `enum ListColumn` is declared in `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift`, and the five `.disabled(listColumn == nil)` callsites are in `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift` (lines 38, 43, 48, 55, 60). These are **two different files** — the new `TaskListShortcutGate` type goes in `FocusedListColumn.swift` (beside `ListColumn`, and on the test bundle's co-compile list), while the callsite edits happen in `LillistCommands.swift`.

- [ ] **Step 2: Write the failing test.** Create `Apps/Lillist-macOS/Tests/FocusedShortcutGatingPredicateTests.swift`:

```swift
import XCTest
import SwiftUI

/// Asserts the *shipping* focus-gating predicate — not a re-typed copy.
/// `TaskListShortcutGate.isDisabled(listColumn:)` is the single source the
/// Space / Cmd-Return / Cmd-. / Tab / Shift-Tab `.disabled(...)` modifiers
/// call; gating those shortcuts off only when no list column holds focus
/// keeps them from firing while a TextField is first responder.
///
/// Bare imports (`XCTest` + `SwiftUI`), matching the existing
/// `FocusedShortcutGatingTests.swift` — the `Lillist-macOSTests` bundle is
/// standalone (no app test host) and co-compiles `FocusedListColumn.swift`
/// directly, so both `ListColumn` and `TaskListShortcutGate` are in-scope
/// without a `@testable import`.
@MainActor
final class FocusedShortcutGatingPredicateTests: XCTestCase {
    func test_nilColumn_disablesShortcuts() {
        XCTAssertTrue(
            TaskListShortcutGate.isDisabled(listColumn: nil),
            "No focused list column must disable Space/Cmd-Return/Cmd-./Tab"
        )
    }

    func test_focusedColumns_enableShortcuts() {
        XCTAssertFalse(TaskListShortcutGate.isDisabled(listColumn: .sidebar))
        XCTAssertFalse(TaskListShortcutGate.isDisabled(listColumn: .list))
        XCTAssertFalse(TaskListShortcutGate.isDisabled(listColumn: .detail))
    }

    func test_listColumn_hasExactlyThreeCases() {
        XCTAssertEqual(Set<ListColumn>([.sidebar, .list, .detail]).count, 3)
    }
}
```

  *Note for implementer:* the bundle is standalone — do **not** add an `@testable import`. `ListColumn` and `TaskListShortcutGate` are both visible because `FocusedListColumn.swift` is already on the co-compile list in `Apps/project.yml` (line 88, the `Lillist-macOS` test target — note the macOS test target's sources live in `Apps/project.yml`, *not* in `Apps/Lillist-macOS/project.yml`). No new co-compile entry is required for this task; you are adding a type to a file that is already compiled into the bundle.

- [ ] **Step 3: Implement the extraction.** In `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift` (where `enum ListColumn` is declared, per Step 1), add:

```swift
/// Single source of truth for whether the list-navigation keyboard
/// shortcuts (Space, Cmd-Return, Cmd-., Tab, Shift-Tab) should be
/// disabled. They fire only when a list column holds focus; when no
/// column is focused (e.g. a TextField is first responder) they must be
/// inert so typing doesn't trigger them.
enum TaskListShortcutGate {
    static func isDisabled(listColumn: ListColumn?) -> Bool {
        listColumn == nil
    }
}
```

  Then, in `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift`, update all five `.disabled(listColumn == nil)` callsites (lines 38, 43, 48, 55, 60) to `.disabled(TaskListShortcutGate.isDisabled(listColumn: listColumn))`. The focused-value binding is named `listColumn` here; if a re-Read shows it differs, substitute the real binding name — the predicate body stays `listColumn == nil`.

> **⚠️ Execution gotcha:** the `.disabled(...)` callsites in `LillistCommands.swift` are compiled **only by the macOS app target**, not by the standalone `Lillist-macOSTests` bundle (`LillistCommands.swift` is not on the bundle's co-compile list). A typo or arity mismatch in those callsites will therefore **not** surface in the `-only-testing:` run in Step 5 — only a full macOS-app or macOS-scheme build catches it. **Task 10, Step 4** (`xcodebuild test ... -scheme Lillist-macOS`, which builds `Lillist-macOS: all`) is the real guard for the callsite edits; do not consider this task verified until that full scheme run is green.

- [ ] **Step 4: Delete the re-typed test.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist && rm Apps/Lillist-macOS/Tests/FocusedShortcutGatingTests.swift
  ```

- [ ] **Step 5: Regenerate pbxprojs and run the macOS tests.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist/Apps/Lillist-macOS && xcodegen generate --spec project.yml --project .
  cd /Volumes/Code/mikeyward/Lillist/Apps && xcodegen generate --spec project.yml --project .
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:Lillist-macOSTests/FocusedShortcutGatingPredicateTests
  ```
  Expect: `Test Suite 'FocusedShortcutGatingPredicateTests' passed` with 3 tests, 0 failures. *(Adjust the `-only-testing:` bundle name to the real macOS test target name if it differs.)*

- [ ] **Step 6: Commit.**
  ```
  git add Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift \
          Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift \
          Apps/Lillist-macOS/Tests/FocusedShortcutGatingPredicateTests.swift \
          Apps/Lillist-macOS/Lillist-macOS.xcodeproj Apps/Lillist.xcodeproj
  git rm Apps/Lillist-macOS/Tests/FocusedShortcutGatingTests.swift
  git commit -m "refactor(macos): extract TaskListShortcutGate predicate and test the real one

Replace the re-typed inline predicate test with one asserting the shipping
TaskListShortcutGate.isDisabled(listColumn:) used by the shortcut .disabled
modifiers. (macos-4)"
  ```

---

## Task 7: Delete the three tautological iOS tests — `ios-2`, `ios-3`

**Files:**
- Delete `Apps/Lillist-iOS/Tests/IntegrationTests/SegmentedDetailTabPersistenceTests.swift`
- Delete `Apps/Lillist-iOS/Tests/UnitTests/NotesDebounceTests.swift`
- Delete `Apps/Lillist-iOS/Tests/UnitTests/CrashReportingDisclosureGateTests.swift`

Each of these asserts a literal against an identical literal (`"taskDetailTab" == "taskDetailTab"`, `500 == 500`, `{ $0 }(true) == true`). They cannot fail when the production value changes because they hold no reference to it — pure false-confidence noise. Remove them; the SceneStorage key / debounce constant / disclosure gate are better protected by the snapshot + tour suites that render the real views.

- [ ] **Step 1: Confirm each is tautological.** Read all three files and verify none import the app module or reference any production symbol (they don't — confirmed: they declare local copies of the value and assert it equals itself).

- [ ] **Step 2: Delete the files.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist && rm Apps/Lillist-iOS/Tests/IntegrationTests/SegmentedDetailTabPersistenceTests.swift Apps/Lillist-iOS/Tests/UnitTests/NotesDebounceTests.swift Apps/Lillist-iOS/Tests/UnitTests/CrashReportingDisclosureGateTests.swift
  ```

- [ ] **Step 3: Regenerate pbxprojs and build the iOS test bundle.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist/Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .
  cd /Volumes/Code/mikeyward/Lillist/Apps && xcodegen generate --spec project.yml --project .
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild build-for-testing -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  ```
  Expect: `** TEST BUILD SUCCEEDED **` (the three deleted files no longer appear in the `Lillist-iOSTests` compile list).

- [ ] **Step 4: Commit.**
  ```
  git add Apps/Lillist-iOS/Lillist-iOS.xcodeproj Apps/Lillist.xcodeproj
  git rm Apps/Lillist-iOS/Tests/IntegrationTests/SegmentedDetailTabPersistenceTests.swift \
         Apps/Lillist-iOS/Tests/UnitTests/NotesDebounceTests.swift \
         Apps/Lillist-iOS/Tests/UnitTests/CrashReportingDisclosureGateTests.swift
  git commit -m "test(ios): delete tautological self-asserting app-layer tests

SegmentedDetailTabPersistence / NotesDebounce / CrashReportingDisclosureGate
each asserted a literal against an identical literal with no reference to the
production value, so they could never fail on a real change. (ios-2, ios-3)"
  ```

---

## Task 8: Add a real iOS gate-resolution test by co-compiling `IntentSupport.swift` — `ios-2`, `ext-6`

**Files:**
- Modify `Apps/Lillist-iOS/project.yml` (`Lillist-iOSTests` sources block, lines 128–139)
- Create `Apps/Lillist-iOS/Tests/UnitTests/IntentSupportGateTests.swift`

The iOS test bundle already co-compiles `SharePayload.swift` and `ReportCrashIntent.swift` so their logic is reachable headlessly. Co-compile `IntentSupport.swift` the same way and assert it exposes the shared `appGroupID` and is wired to the resolver. The deep gate-branch coverage lives in `GatedPersistenceResolverTests` (Task 1, no App Group needed); this iOS test pins that the iOS-side wrapper still delegates to it and that the App-Group-fallback message is correct.

- [ ] **Step 1: Add `IntentSupport.swift` to the iOS test bundle sources.** In `Apps/Lillist-iOS/project.yml`, after the `ReportCrashIntent.swift` co-compile line (line 139), add:

```yaml
      # Co-compile IntentSupport so the gate-aware persistence resolution
      # wrapper can be exercised from the standalone iOS test bundle without
      # a ShortcutsActions extension test host. The deep gate-branch coverage
      # lives in LillistCore's GatedPersistenceResolverTests; this pins the
      # iOS-side wrapper delegation.
      - path: ../../Extensions/ShortcutsActions/IntentSupport.swift
```

- [ ] **Step 2: Write the failing test.** Create `Apps/Lillist-iOS/Tests/UnitTests/IntentSupportGateTests.swift`:

```swift
import XCTest
import LillistCore

/// `IntentSupport` (co-compiled into this bundle) is the App Intents
/// entry point that resolves the shared store through the MigrationGate.
/// The deep gate-branch behavior is covered by LillistCore's
/// `GatedPersistenceResolverTests`; this test pins that the iOS-side
/// wrapper still targets the canonical App Group and surfaces a
/// storeUnavailable error rather than crashing when the group is absent.
final class IntentSupportGateTests: XCTestCase {
    func test_usesCanonicalAppGroupID() {
        XCTAssertEqual(IntentSupport.appGroupID, "group.io.mikeydotio.Lillist")
    }

    func test_resolverConstructibleForCanonicalGroup_orThrowsStoreUnavailable() async {
        // In the headless test bundle the real App Group may or may not be
        // reachable. Either way makePersistence must not crash: it either
        // resolves a controller or throws a typed storeUnavailable error.
        do {
            _ = try await IntentSupport.makePersistence()
            // App Group reachable in this environment — acceptable.
        } catch LillistError.storeUnavailable {
            // App Group not provisioned for the headless bundle — the
            // wrapper degraded gracefully to the typed error. Acceptable.
        } catch {
            XCTFail("makePersistence threw an unexpected error type: \(error)")
        }
    }
}
```

- [ ] **Step 3: Run the test, expect failure.** First regenerate the pbxproj so the co-compiled source + new test are in the bundle, then run the single test:
  ```
  cd /Volumes/Code/mikeyward/Lillist/Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .
  cd /Volumes/Code/mikeyward/Lillist/Apps && xcodegen generate --spec project.yml --project .
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:Lillist-iOSTests/IntentSupportGateTests
  ```
  Expect failure on the **first** run only if Tasks 2/8 ordering left `IntentSupport` not yet delegating — since Task 2 already landed the delegation, the expected first failure here is instead a **compile error** if the pbxproj wasn't regenerated (`cannot find 'IntentSupport' in scope`). After regeneration the test should compile; if it does not yet pass, read the failure and fix.

- [ ] **Step 4: Run the test, expect pass.** Re-run:
  ```
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:Lillist-iOSTests/IntentSupportGateTests
  ```
  Expect: `Test Suite 'IntentSupportGateTests' passed` with 2 tests, 0 failures.

- [ ] **Step 5: Commit.**
  ```
  git add Apps/Lillist-iOS/project.yml Apps/Lillist-iOS/Tests/UnitTests/IntentSupportGateTests.swift \
          Apps/Lillist-iOS/Lillist-iOS.xcodeproj Apps/Lillist.xcodeproj
  git commit -m "test(ios): co-compile IntentSupport and pin its gate-resolution wrapper

Reach IntentSupport from the headless iOS test bundle (like SharePayload /
ReportCrashIntent) and assert it targets the canonical App Group and
degrades to a typed storeUnavailable error. (ios-2, ext-6)"
  ```

---

## Task 9: Rename the misleading composition tests — `ios-2`, `ext-6`

**Files:**
- Rename `Apps/Lillist-iOS/Tests/IntegrationTests/QuickCaptureFlowTests.swift` → `LillistCoreQuickCaptureCompositionTests.swift` (and the class)
- Rename `Apps/Lillist-iOS/Tests/IntegrationTests/ShareExtensionPayloadTests.swift` → `LillistCoreSharePayloadCompositionTests.swift` (and the class)

Both files' names imply they test `QuickCaptureDialogHost.submit()` / `ShareRootView.save()`, but their own doc-comments admit they "cannot `@testable import`" the app and instead re-walk the equivalent LillistCore + LillistUI path. They're genuine *composition* tests (they exercise real `QuickCaptureParser` + `TaskStore` + `TagStore` / `SharePayload` + `AttachmentStore`), so keep the coverage but rename to stop implying app-type coverage that doesn't exist.

- [ ] **Step 1: Git-move both files.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist && git mv Apps/Lillist-iOS/Tests/IntegrationTests/QuickCaptureFlowTests.swift Apps/Lillist-iOS/Tests/IntegrationTests/LillistCoreQuickCaptureCompositionTests.swift
  cd /Volumes/Code/mikeyward/Lillist && git mv Apps/Lillist-iOS/Tests/IntegrationTests/ShareExtensionPayloadTests.swift Apps/Lillist-iOS/Tests/IntegrationTests/LillistCoreSharePayloadCompositionTests.swift
  ```

- [ ] **Step 2: Rename the class + sharpen the doc-comment in the QuickCapture file.** In `Apps/Lillist-iOS/Tests/IntegrationTests/LillistCoreQuickCaptureCompositionTests.swift` replace the header block + class declaration:

```swift
import XCTest
import LillistCore
import LillistUI

/// LillistCore + LillistUI composition test for the Quick Capture pipeline.
/// This bundle cannot `@testable import Lillist_iOS` (no signed app host),
/// so it does NOT exercise `QuickCaptureDialogHost.submit()` directly — it
/// re-walks the equivalent parse → create → resolve-tags → resolve-deadline
/// path through `QuickCaptureParser` + `TaskStore` + `TagStore`. Named to
/// signal that it covers the composition, not the app-layer view model.
final class LillistCoreQuickCaptureCompositionTests: XCTestCase {
```

  Leave the two test methods (`test_parse_create_resolve_tag_and_deadline`, `test_empty_title_rejected`) and their bodies unchanged.

- [ ] **Step 3: Rename the class + sharpen the doc-comment in the SharePayload file.** In `Apps/Lillist-iOS/Tests/IntegrationTests/LillistCoreSharePayloadCompositionTests.swift` replace the header block + class declaration:

```swift
import XCTest
import Foundation
import LillistCore

/// LillistCore composition test for the Share Extension persistence path.
/// This bundle cannot `@testable import` the ShareExtension target, so it
/// does NOT exercise `ShareRootView.save()` directly — it re-walks the
/// equivalent decode → create-task → attach-URL path through `SharePayload`
/// (co-compiled), `TaskStore`, and `AttachmentStore`. Named to signal that
/// it covers the composition, not the SwiftUI view.
final class LillistCoreSharePayloadCompositionTests: XCTestCase {
```

  Leave the three test methods and their bodies unchanged.

- [ ] **Step 4: Regenerate pbxprojs and build-for-testing.** Run:
  ```
  cd /Volumes/Code/mikeyward/Lillist/Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .
  cd /Volumes/Code/mikeyward/Lillist/Apps && xcodegen generate --spec project.yml --project .
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:Lillist-iOSTests/LillistCoreQuickCaptureCompositionTests -only-testing:Lillist-iOSTests/LillistCoreSharePayloadCompositionTests
  ```
  Expect: both suites pass (2 + 3 tests), 0 failures.

- [ ] **Step 5: Commit.**
  ```
  git add Apps/Lillist-iOS/Tests/IntegrationTests/LillistCoreQuickCaptureCompositionTests.swift \
          Apps/Lillist-iOS/Tests/IntegrationTests/LillistCoreSharePayloadCompositionTests.swift \
          Apps/Lillist-iOS/Lillist-iOS.xcodeproj Apps/Lillist.xcodeproj
  git commit -m "test(ios): rename composition tests to stop implying app-type coverage

QuickCaptureFlowTests/ShareExtensionPayloadTests re-walk LillistCore +
LillistUI paths (no app host), not the named app types. Rename to
LillistCore*CompositionTests and sharpen the doc-comments. (ios-2, ext-6)"
  ```

---

## Task 10: Full-suite regression — confirm nothing broke

**Files:** none (verification only)

- [ ] **Step 1: Run the full LillistCore suite.**
  ```
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore
  ```
  Expect: all tests pass, including `GatedPersistenceResolverTests`. 0 failures, 0 warnings (warnings-as-errors).

- [ ] **Step 2: Run the full LillistUI suite.**
  ```
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI
  ```
  Expect: all tests pass, including `DragDropResolverTests`. 0 failures.

- [ ] **Step 3: Run the full iOS test scheme.**
  ```
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  ```
  Expect: `** TEST SUCCEEDED **`; the three deleted tautologies are gone, the two renamed composition suites and `IntentSupportGateTests` run green.

- [ ] **Step 4: Run the full macOS test scheme.**
  ```
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  ```
  Expect: `** TEST SUCCEEDED **`; `DragDropInteractionTests` and `FocusedShortcutGatingTests` are gone, `FocusedShortcutGatingPredicateTests` runs green.

- [ ] **Step 5: Confirm pbxproj has no uncommitted drift.**
  ```
  cd /Volumes/Code/mikeyward/Lillist && git status --porcelain
  ```
  Expect: empty output (all generated pbxproj changes already committed in their respective tasks). If non-empty and it's pbxproj drift, regenerate + amend the relevant commit.

---

## Self-review checklist

- [ ] **`ios-2`** (iOS test-substitution: MigrationGate-gated persistence resolution untested; tautological tests) — covered by **Task 1** (direct `GatedPersistenceResolver` gate-branch tests), **Task 7** (delete the three tautologies), **Task 8** (real iOS `IntentSupportGateTests`), and **Task 9** (honest rename of the QuickCapture composition test).
- [ ] **`ios-3`** (iOS drag-mapping duplicated/untested; tautological tests) — covered by **Task 4** (pure `DragDropResolver` + tests), **Task 5** (iOS `TasksView.applyDrop` dispatches via the resolver), and **Task 7** (delete tautologies).
- [ ] **`macos-4`** (macOS test-substitution: `applyDrop` mapping re-implemented and mis-mapped; focus-gating predicate re-typed) — covered by **Task 4** (resolver incl. onto-first-child branch), **Task 5** (macOS `applyDrop` dispatch + delete `DragDropInteractionTests`), and **Task 6** (extract `TaskListShortcutGate` + test the real predicate, delete `FocusedShortcutGatingTests`).
- [ ] **`ext-6`** (extension test-substitution: `ShareRootView.save()` / `IntentSupport.makePersistence()` gate branch incl. `storeUnavailable` untested; misleading composition test names) — covered by **Task 1** (gate-branch incl. `storeUnavailable`), **Task 2** (IntentSupport delegation), **Task 3** (ShareRootView delegation), **Task 8** (iOS-side wrapper pin), and **Task 9** (rename the SharePayload composition test).

### Scope guards (DRY/YAGNI)
- [ ] `AppIntentHandlerTests.swift` left untouched (genuine `CLIBridge` coverage — explicitly out of scope).
- [ ] No change to `ShareRootView`'s `try?`-on-`addLinkPreview` failure handling (owned by `extension-persistence-unification`, finding `ext-4`).
- [ ] No change to `TaskEntityQuery.makePersistence()` routing (owned by `extension-persistence-unification`, finding `ext-1`/`ext-2`).
- [ ] Strengths preserved: airtight DTO boundary (resolver returns `PersistenceController`/`StoreConfiguration`, no `NSManagedObject` escapes), container/presenter split (resolver + `DragDropResolver` are pure helpers, not new state), disciplined composition roots (constructor injection on `GatedPersistenceResolver`).
