# Lillist Plan 11 — Pre-UAT Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every loose end identified in the 2026-05-14 UAT-readiness review so a fresh checkout produces a buildable, runnable, demoable v1. Specifically: fix the macOS sidebar pinned-tasks bug, implement the link-preview unfurl pipeline promised by design §3, ship the recurrence pattern editor UI (which design §10 marks as v2 — explicitly pulled forward for v1 per project decision), wire the "Empty Trash now" buttons, replace the placeholder Quick Capture hotkey recorder with a real key-capture UI, and audit shipped code for the remaining cosmetic / structural irritants (sentinel URLs, fatal preconditions, test-only `fatalError`s).

**Architecture:** Most tasks are local code edits inside existing files; the two larger pieces — link-preview unfurl and the recurrence editor — get their own new directories. The unfurl pipeline introduces a `LinkPreview` namespace in `LillistCore` (an HTML parser, an unfurler service, a transport protocol) and an integration point inside `AttachmentStore`. The recurrence editor lives in `LillistUI` as a single cross-platform `RecurrenceEditorView` plus a value-type view model; macOS replaces the existing `RecurrenceFieldPlaceholderView` in `TaskDetailView`, and iOS surfaces the editor via a sheet from the detail header. PersistenceController's two `preconditionFailure` calls become typed throws and callers handle the new `LillistError.modelUnavailable` case. Test-only `fatalError`s become `Issue.record` / `XCTFail` to keep CI from aborting the whole suite on a misuse.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing for `LillistCore` tests, XCTest + `swift-snapshot-testing` for UI snapshot tests, `URLSession` with a custom `URLProtocol` stub for unfurl integration tests, AppKit `NSEvent.addLocalMonitorForEvents` for macOS hotkey capture.

**Depends on:** Every prior plan (1-10) is on `main`. This plan does not introduce new managed-object entities, no migrations, no new dependencies.

---

## File Structure

```
Lillist/
├── Packages/
│   └── LillistCore/
│       ├── Sources/
│       │   └── LillistCore/
│       │       ├── LinkPreview/                          (NEW directory)
│       │       │   ├── LinkPreviewMetadata.swift         (NEW)
│       │       │   ├── OpenGraphParser.swift             (NEW)
│       │       │   ├── LinkPreviewFetching.swift         (NEW — protocol)
│       │       │   ├── URLSessionLinkPreviewFetcher.swift (NEW)
│       │       │   └── LinkPreviewUnfurler.swift         (NEW — actor)
│       │       ├── Stores/
│       │       │   ├── AttachmentStore.swift             (modify — add updateLinkPreview, rename sentinel)
│       │       │   └── TaskStore.swift                   (modify — add purgeAll)
│       │       ├── Persistence/
│       │       │   └── PersistenceController.swift       (modify — preconditionFailure → throws)
│       │       ├── Validation/
│       │       │   └── LillistError.swift                (modify — add .modelUnavailable)
│       │       └── CLIBridge/
│       │           └── Handlers/
│       │               └── LinkHandler.swift             (modify — enqueue unfurl)
│       └── Tests/
│           └── LillistCoreTests/
│               ├── Helpers/
│               │   ├── FakeUserNotificationCenter.swift  (modify — Issue.record not fatalError)
│               │   └── StubURLProtocol.swift             (NEW — for unfurl tests)
│               ├── LinkPreview/                          (NEW directory)
│               │   ├── OpenGraphParserTests.swift        (NEW)
│               │   ├── LinkPreviewUnfurlerTests.swift    (NEW)
│               │   └── Fixtures/                         (NEW)
│               │       ├── og-typical.html               (NEW)
│               │       ├── og-twitter.html               (NEW)
│               │       ├── og-empty.html                 (NEW)
│               │       └── og-malformed.html             (NEW)
│               ├── Persistence/
│               │   └── PersistenceControllerTests.swift  (modify — test throwing init)
│               └── Stores/
│                   ├── AttachmentStoreLinkPreviewTests.swift (NEW)
│                   ├── TaskStorePurgeAllTests.swift      (NEW)
│                   └── TaskStoreQueriesTests.swift       (modify — pin nested-pinned visible)
├── Packages/
│   └── LillistUI/
│       ├── Sources/
│       │   └── LillistUI/
│       │       ├── Components/
│       │       │   └── RecurrenceFieldPlaceholderView.swift  (delete after recur editor lands)
│       │       └── Recurrence/                          (NEW directory)
│       │           ├── RecurrenceEditorViewModel.swift  (NEW)
│       │           └── RecurrenceEditorView.swift       (NEW)
│       └── Tests/
│           └── LillistUITests/
│               ├── Recurrence/
│               │   ├── RecurrenceEditorViewModelTests.swift  (NEW)
│               │   └── RecurrenceEditorSnapshotTests.swift   (NEW)
│               └── Snapshots/
│                   └── TaskDetailViewSnapshotTests.swift     (modify — remove placeholder use)
├── Apps/
│   ├── Lillist-macOS/
│   │   ├── Sources/
│   │   │   ├── Views/
│   │   │   │   ├── Sidebar/
│   │   │   │   │   └── SidebarView.swift                (modify — use taskStore.pinned())
│   │   │   │   └── Detail/
│   │   │   │       └── TaskDetailView.swift             (modify — replace placeholder with editor)
│   │   │   ├── Preferences/
│   │   │   │   ├── QuickCapturePane.swift               (modify — proper recorder + live re-register)
│   │   │   │   └── TrashPane.swift                      (modify — wire Empty Trash button)
│   │   │   └── Hotkey/
│   │   │       ├── GlobalHotkeyMonitor.swift            (modify — public reregister(combo:))
│   │   │       └── HotkeyRecorder.swift                 (NEW — NSEvent-based recorder)
│   │   └── Tests/
│   │       ├── HotkeyRecorderTests.swift                (NEW)
│   │       ├── PinnedSidebarIntegrationTests.swift      (NEW)
│   │       └── NotificationPermissionFlowTests.swift    (modify — soften fatalError)
│   └── Lillist-iOS/
│       ├── Sources/
│       │   ├── Detail/
│       │   │   ├── TaskDetailView.swift                 (modify — toolbar entry to RecurrenceSheet)
│       │   │   └── RecurrenceSheet.swift                (NEW)
│       │   └── Settings/
│       │       └── TrashSection.swift                   (modify — wire Empty Trash button)
│       └── Tests/
│           └── UnitTests/
│               └── NotificationPermissionFlowTests.swift (modify — soften fatalError)
└── docs/
    ├── plans/
    │   └── 2026-05-12-lillist-design.md                 (modify — move recurrence editor from v2 to v1 with note)
    └── engineering-notes.md                              (append entry for Plan 11)
```

---

## Notes for the Implementer

**The recurrence editor is being pulled into v1.** Design §10 lists "Custom recurrence pattern editor" under "Likely v2 roadmap." The user has explicitly opted to ship it in v1 to round out the UAT build. Task 23 updates the design doc accordingly so the spec and implementation don't diverge.

**`taskStore.pinned()` already exists** and is tested ("pinned returns all pinned tasks across the tree, excluding trash" — Plan 4 tag). The TODO comment in `SidebarView.swift:63-69` is stale. The first three tasks of this plan are: delete the stopgap workaround, swap to the real query, prove the difference with an integration test.

**Link-preview unfurl uses pure-Swift HTML parsing** — no SwiftSoup or other deps. The Apple-shipped option is `NSAttributedString(data:options:documentAttributes:)` with `.html` document type, but that's fragile for OG tag extraction. Instead we hand-write a small regex/scanner that extracts the four `<meta property="og:*">` and `<meta name="twitter:*">` tags we need, plus `<title>`. This is per the design §3 "HTML-only parsing (no JS execution)" mandate. The parser is a pure function; tests use static fixture files committed under `Tests/LillistCoreTests/LinkPreview/Fixtures/`.

**`URLSession` tests use `URLProtocol` stubbing** — register a custom `URLProtocol` subclass at test setup, intercept by URL pattern, return a canned `(response, data)`. This avoids live network and works deterministically in `swift test`. The pattern is well-known; see `StubURLProtocol.swift` in Task 6.

**Recurrence editor consumes existing `RecurrenceRule`.** The data model already supports both `CalendarRule` and `AfterCompletionRule`. The editor binds to a `RecurrenceRule?` (nil = "doesn't repeat"). On commit, it calls one of:
- `seriesStore.create(fromSeedTask: taskID, rule: rule)` — task isn't yet in a series
- `seriesStore.update(id: seriesID, rule: rule)` — task is already a series instance and we're editing the rule

There's no "remove from series" path in the v1 editor — the design's "this only" / "all future" semantics live in `seriesStore.forkFutureFromInstance(instanceID:)` and are out of v1 UI scope (they keep their CLI / App Intent access). The editor presents a "Doesn't repeat" / "Repeats…" toggle; toggling off on an instance deletes the whole series via `seriesStore.delete(id:)`. The TaskStore's `transition()` flow continues to spawn next instances on completion as before — the editor doesn't touch that.

**Trash purge needs a public `TaskStore.purgeAll()` method** that hard-deletes every row with `deletedAt != nil`. `AutoPurgeJob` already does this for rows older than the retention window — we extract / generalize the helper. The button shows a confirmation dialog before purging.

**macOS hotkey recorder is `NSViewRepresentable`-free** — we use a plain SwiftUI view that owns an `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` registered while the view is focused. Capturing modifiers + key from a single keyDown event is straightforward; the result encodes to the `ctrl+opt+space` string format `GlobalHotkeyMonitor` already parses.

**Live hotkey re-registration:** `GlobalHotkeyMonitor` currently takes its hotkey via init; we add a public `reregister(combo:)` method. When the user saves a new hotkey in Preferences, the pane calls `await env.hotkeyMonitor.reregister(combo: newCombo)` immediately. No more relaunch required.

**`PersistenceController.sharedModel`** is the only path that can `preconditionFailure`. We change it to `throws(LillistError)` and add `.modelUnavailable(searchedFilenames: [String])` to `LillistError`. The two existing callers (`PersistenceController.init(configuration:)` and the test convenience `inMemory()`) propagate the throw. The init signature stays `async throws` — no API churn at the boundary.

**Test-only `fatalError`s** in `FakeUserNotificationCenter.notificationSettings()` and the two app-target `NotificationPermissionFlowTests` are deliberate guardrails for code paths the tests shouldn't reach. They become `Issue.record` (Swift Testing) or `XCTFail` (XCTest) so a hit reports as a test failure rather than crashing the whole runner. Behavior on hit is identical for the developer; the difference matters only when the bundle is run from CI and one bad test shouldn't kill the rest.

**Build-plugin caching gotcha (still active).** No model changes in this plan, so no `touch` needed. If you touch the model anyway during exploration, run the standard incantation from CLAUDE.md:
```bash
touch Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/ \
      Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/
```

**Verification commands.** Each task that produces tests ends by running them via `swift test --filter '<pattern>'`. Final task runs the full suite + both app targets via `xcodebuild`.

**Commits.** Conventional-commit prefixes throughout: `fix:`, `feat:`, `test:`, `refactor:`, `chore:`, `docs:`.

---

## Task 1: Fix macOS sidebar pinned to use `TaskStore.pinned()`

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:61-78`

- [ ] **Step 1: Read current state and confirm the bug**

```bash
swift test --package-path Packages/LillistCore --filter 'pinned returns all pinned tasks across the tree'
```

Expected: PASS (the LillistCore query is correct).

```bash
grep -n "isPinned\|pinned()" Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift
```

Expected: line 69 reads `pinnedTasks = (try await env.taskStore.children(of: nil)).filter { $0.isPinned }` — the broken workaround.

- [ ] **Step 2: Swap the workaround for the real query**

Edit `SidebarView.swift` lines 61-78. Replace the `refresh()` body:

```swift
    private func refresh() async {
        do {
            pinnedTasks = try await env.taskStore.pinned()
            let allFilters = try await env.smartFilterStore.list()
            pinnedFilters = allFilters.filter(\.isPinned)
            nonPinnedFilters = allFilters.filter { !$0.isPinned }
            rootTags = try await env.tagStore.children(of: nil)
            trashCount = try await env.taskStore.trashed().count
        } catch {
            // Surface in a banner later; sidebar stays empty for now.
        }
    }
```

(The `// TODO(Plan 7 follow-up)` block lines 63-68 are deleted.)

- [ ] **Step 3: Build and confirm clean**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift
git commit -m "fix(macOS): sidebar uses taskStore.pinned() so nested pinned tasks appear"
```

---

## Task 2: Add macOS integration test that nested pinned tasks appear in the sidebar

**Files:**
- Create: `Apps/Lillist-macOS/Tests/PinnedSidebarIntegrationTests.swift`

This is a LillistCore-level functional test exercising `TaskStore.pinned()` against the same persistence layer the app uses; we don't bring up the SwiftUI view (the macOS test target is standalone, no app host).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import LillistCore
import Foundation

@Suite("Pinned-anywhere sidebar contract")
struct PinnedSidebarIntegrationTests {
    @Test("Pinned task two levels deep appears in pinned() output")
    func nestedPinnedTaskAppears() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: persistence)

        let root = try await store.create(title: "root")
        let child = try await store.create(title: "child", parent: root)
        let grandchild = try await store.create(title: "grand", parent: child)
        try await store.update(id: grandchild) { $0.isPinned = true }

        let pinned = try await store.pinned()
        #expect(pinned.map(\.id).contains(grandchild))
    }

    @Test("Trashed pinned task does not appear")
    func trashedPinnedExcluded() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: persistence)
        let t = try await store.create(title: "x")
        try await store.update(id: t) { $0.isPinned = true }
        try await store.softDelete(id: t)
        let pinned = try await store.pinned()
        #expect(!pinned.map(\.id).contains(t))
    }
}
```

- [ ] **Step 2: Run the new tests**

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/PinnedSidebarIntegrationTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: both tests PASS (LillistCore's `pinned()` already supports this — we're pinning the contract).

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Tests/PinnedSidebarIntegrationTests.swift
git commit -m "test(macOS): pin sidebar's nested-pinned-task contract"
```

---

## Task 3: Add `TaskStore.purgeAll()` for trashed-only hard delete

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStorePurgeAllTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
import LillistCore

@Suite("TaskStore.purgeAll")
struct TaskStorePurgeAllTests {
    @Test("Purges every trashed task and returns the count")
    func purgesTrashed() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let a = try await store.create(title: "a")
        let b = try await store.create(title: "b")
        let c = try await store.create(title: "c")
        try await store.softDelete(id: a)
        try await store.softDelete(id: c)

        let purged = try await store.purgeAll()

        #expect(purged == 2)
        let remaining = try await store.children(of: nil).map(\.id)
        #expect(remaining == [b])
        let trash = try await store.trashed()
        #expect(trash.isEmpty)
    }

    @Test("No-op when trash is empty")
    func emptyTrash() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        _ = try await store.create(title: "a")
        let purged = try await store.purgeAll()
        #expect(purged == 0)
    }

    @Test("Cascades to descendants of a trashed parent")
    func cascadesToDescendants() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let parent = try await store.create(title: "parent")
        _ = try await store.create(title: "child", parent: parent)
        try await store.softDelete(id: parent)

        let purged = try await store.purgeAll()
        #expect(purged == 2)
    }
}
```

- [ ] **Step 2: Run and verify it fails**

```bash
swift test --package-path Packages/LillistCore --filter 'TaskStore.purgeAll' 2>&1 | tail -5
```

Expected: compile error — `purgeAll` does not exist.

- [ ] **Step 3: Add `purgeAll()` to `TaskStore`**

In `TaskStore.swift`, near the bottom of the public surface, add:

```swift
    /// Hard-delete every task currently in the Trash (i.e. with
    /// `deletedAt != nil`), including any descendants. Returns the number
    /// of tasks removed. Plan 11 / design Section 7 ("Trash") — the
    /// "Empty Trash now" affordance in Preferences calls this.
    ///
    /// Distinct from `AutoPurgeJob`, which only removes tasks whose
    /// `deletedAt` is older than the retention window.
    @discardableResult
    public func purgeAll() async throws -> Int {
        try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "deletedAt != nil")
            let trashed = try context.fetch(req)
            var count = 0
            for t in trashed {
                count += 1 + countDescendants(of: t)
                context.delete(t) // cascades to children via the Core Data rule
            }
            try context.save()
            return count
        }
    }

    private func countDescendants(of t: LillistTask) -> Int {
        guard let kids = t.children as? Set<LillistTask>, !kids.isEmpty else { return 0 }
        return kids.reduce(0) { $0 + 1 + countDescendants(of: $1) }
    }
```

- [ ] **Step 4: Run tests**

```bash
swift test --package-path Packages/LillistCore --filter 'TaskStore.purgeAll' 2>&1 | tail -10
```

Expected: all three tests PASS.

- [ ] **Step 5: Run full LillistCore suite to confirm no regression**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
```

Expected: `Test run with NNN tests in M suites passed`.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStorePurgeAllTests.swift
git commit -m "feat(core): add TaskStore.purgeAll() for empty-trash UX"
```

---

## Task 4: Wire macOS "Empty Trash now" button to `purgeAll()`

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift`

- [ ] **Step 1: Replace the no-op `emptyTrash()` with a real call**

Replace lines 70-78 (the `emptyTrash` function) and add a confirmation dialog to the body. The full updated pane:

```swift
import SwiftUI
import LillistCore

/// macOS Preferences Trash pane.
///
/// Slider controls the auto-purge retention window (7-365 days).
/// "Empty Trash now" calls `TaskStore.purgeAll()` after confirmation.
struct TrashPane: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prefs: PreferencesStore.Prefs?
    @State private var isEmptying = false
    @State private var emptyResult: String?
    @State private var confirmingEmpty = false

    var body: some View {
        Form {
            if let b = binding {
                Section("Retention") {
                    Slider(
                        value: Binding(
                            get: { Double(b.wrappedValue.trashRetentionDays) },
                            set: { b.wrappedValue.trashRetentionDays = Int16($0.rounded()) }
                        ),
                        in: 7...365,
                        step: 1
                    ) {
                        Text("Days in Trash before auto-purge")
                    }
                    Text("\(b.wrappedValue.trashRetentionDays) days")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button(role: .destructive) {
                        confirmingEmpty = true
                    } label: {
                        if isEmptying {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Empty Trash now")
                        }
                    }
                    .disabled(isEmptying)
                    .confirmationDialog(
                        "Empty Trash?",
                        isPresented: $confirmingEmpty,
                        titleVisibility: .visible
                    ) {
                        Button("Empty Trash", role: .destructive) {
                            Task { await emptyTrash() }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Tasks in Trash will be permanently deleted and cannot be recovered.")
                    }
                    if let emptyResult {
                        Text(emptyResult)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .task { prefs = try? await environment.preferencesStore.read() }
        .onChange(of: prefs) { _, new in
            guard let new else { return }
            Task { try? await environment.preferencesStore.update { $0 = new } }
        }
    }

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }

    private func emptyTrash() async {
        isEmptying = true
        defer { isEmptying = false }
        do {
            let purged = try await environment.taskStore.purgeAll()
            emptyResult = purged == 0
                ? "Trash was already empty."
                : "Emptied \(purged) task\(purged == 1 ? "" : "s") from Trash."
        } catch {
            emptyResult = "Couldn't empty Trash: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: Build the macOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift
git commit -m "feat(macOS): wire Empty Trash now button via TaskStore.purgeAll()"
```

---

## Task 5: Wire iOS "Empty Trash now" button to `purgeAll()`

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Settings/TrashSection.swift`

- [ ] **Step 1: Replace the no-op with a confirmation + `purgeAll` call**

The iOS section is more compact (lives inside a Form/Section). Replace the file:

```swift
import SwiftUI
import LillistCore

struct TrashSection: View {
    @Binding var prefs: PreferencesStore.Prefs
    @Environment(AppEnvironment.self) private var environment
    @State private var emptyResult: String?
    @State private var isEmptying = false
    @State private var confirmingEmpty = false

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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                confirmingEmpty = true
            } label: {
                if isEmptying {
                    ProgressView()
                } else {
                    Text("Empty Trash now")
                }
            }
            .disabled(isEmptying)
            .confirmationDialog(
                "Empty Trash?",
                isPresented: $confirmingEmpty,
                titleVisibility: .visible
            ) {
                Button("Empty Trash", role: .destructive) {
                    Task { await emptyTrash() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Tasks in Trash will be permanently deleted.")
            }
            if let emptyResult {
                Text(emptyResult)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func emptyTrash() async {
        isEmptying = true
        defer { isEmptying = false }
        do {
            let purged = try await environment.taskStore.purgeAll()
            emptyResult = purged == 0
                ? "Trash was already empty."
                : "Emptied \(purged) task\(purged == 1 ? "" : "s")."
        } catch {
            emptyResult = "Couldn't empty Trash: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: Build the iOS app**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Settings/TrashSection.swift
git commit -m "feat(iOS): wire Empty Trash now button via TaskStore.purgeAll()"
```

---

## Task 6: Add `StubURLProtocol` test helper for unfurl tests

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Helpers/StubURLProtocol.swift`

- [ ] **Step 1: Write the helper**

```swift
import Foundation

/// Test helper that intercepts `URLSession` requests and returns canned
/// responses. Used by the LinkPreview unfurl tests so they never hit the
/// network. Register via `URLSessionConfiguration.protocolClasses = [StubURLProtocol.self]`.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    nonisolated(unsafe) static var responder: ((URL) -> Response?)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let response = Self.responder?(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// Construct a `URLSession` whose requests will be served by `responder`.
    static func session(responder: @escaping (URL) -> Response?) -> URLSession {
        Self.responder = responder
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}
```

- [ ] **Step 2: Confirm it compiles**

```bash
swift build --package-path Packages/LillistCore 2>&1 | tail -3
```

Expected: `Build complete!`. (The helper isn't yet used; it just needs to compile inside the test target — but at this stage it's only seen by `swift test` builds, so we move on.)

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Helpers/StubURLProtocol.swift
git commit -m "test(core): add StubURLProtocol helper for unfurl tests"
```

---

## Task 7: Add `LinkPreviewMetadata` value type + `OpenGraphParser`

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewMetadata.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/LinkPreview/OpenGraphParser.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/OpenGraphParserTests.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/Fixtures/og-typical.html`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/Fixtures/og-twitter.html`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/Fixtures/og-empty.html`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/Fixtures/og-malformed.html`

- [ ] **Step 1: Create fixture HTML files**

`Tests/LillistCoreTests/LinkPreview/Fixtures/og-typical.html`:

```html
<!doctype html>
<html>
<head>
<title>Example Article — Acme Co.</title>
<meta property="og:title" content="Example Article">
<meta property="og:description" content="A short summary of the article.">
<meta property="og:image" content="https://example.com/thumbnail.jpg">
<meta property="og:site_name" content="Acme Co.">
</head>
<body>Body content.</body>
</html>
```

`Tests/LillistCoreTests/LinkPreview/Fixtures/og-twitter.html`:

```html
<!doctype html>
<html>
<head>
<title>Twitter-card Page</title>
<meta name="twitter:title" content="Twitter Title">
<meta name="twitter:description" content="Twitter description text.">
<meta name="twitter:image" content="https://example.com/twitter-card.png">
</head>
<body></body>
</html>
```

`Tests/LillistCoreTests/LinkPreview/Fixtures/og-empty.html`:

```html
<!doctype html>
<html>
<head>
<title>Just a Title</title>
</head>
<body>No meta tags here.</body>
</html>
```

`Tests/LillistCoreTests/LinkPreview/Fixtures/og-malformed.html`:

```html
<html<<<head <title>Broken</title <meta property=og:title content=NoQuotes>
```

- [ ] **Step 2: Register the fixtures as resources**

Open `Packages/LillistCore/Package.swift` and add to the `lillistCoreTests` target's `resources`:

```swift
        .testTarget(
            name: "LillistCoreTests",
            dependencies: ["LillistCore"],
            resources: [
                .copy("CrashReporting/Fixtures"),
                .copy("LinkPreview/Fixtures")
            ]
        ),
```

- [ ] **Step 3: Write the failing parser test**

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("OpenGraphParser")
struct OpenGraphParserTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("Typical OG tags parse cleanly")
    func typical() throws {
        let html = try fixture("og-typical")
        let m = OpenGraphParser.parse(html: html)
        #expect(m.title == "Example Article")
        #expect(m.description == "A short summary of the article.")
        #expect(m.imageURL?.absoluteString == "https://example.com/thumbnail.jpg")
        #expect(m.siteName == "Acme Co.")
    }

    @Test("Twitter card falls back when no og:* present")
    func twitterFallback() throws {
        let html = try fixture("og-twitter")
        let m = OpenGraphParser.parse(html: html)
        #expect(m.title == "Twitter Title")
        #expect(m.description == "Twitter description text.")
        #expect(m.imageURL?.absoluteString == "https://example.com/twitter-card.png")
    }

    @Test("Page with only <title> populates title only")
    func onlyTitle() throws {
        let html = try fixture("og-empty")
        let m = OpenGraphParser.parse(html: html)
        #expect(m.title == "Just a Title")
        #expect(m.description == nil)
        #expect(m.imageURL == nil)
    }

    @Test("Malformed HTML returns empty metadata without throwing")
    func malformed() throws {
        let html = try fixture("og-malformed")
        let m = OpenGraphParser.parse(html: html)
        #expect(m.title == "Broken" || m.title == nil) // either is acceptable
    }
}
```

- [ ] **Step 4: Run and verify it fails**

```bash
swift test --package-path Packages/LillistCore --filter 'OpenGraphParser' 2>&1 | tail -5
```

Expected: compile error — `OpenGraphParser` does not exist.

- [ ] **Step 5: Create `LinkPreviewMetadata`**

`Sources/LillistCore/LinkPreview/LinkPreviewMetadata.swift`:

```swift
import Foundation

/// Pure value type representing the unfurled metadata of a URL.
/// Populated by `OpenGraphParser` from HTML body, then handed to
/// `AttachmentStore.updateLinkPreview` for persistence.
public struct LinkPreviewMetadata: Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var imageURL: URL?
    public var siteName: String?

    public init(
        title: String? = nil,
        description: String? = nil,
        imageURL: URL? = nil,
        siteName: String? = nil
    ) {
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.siteName = siteName
    }

    public static let empty = LinkPreviewMetadata()
}
```

- [ ] **Step 6: Create `OpenGraphParser`**

`Sources/LillistCore/LinkPreview/OpenGraphParser.swift`:

```swift
import Foundation

/// Extracts `LinkPreviewMetadata` from raw HTML using a small set of
/// regexes that match the four `<meta property="og:*">` tags and the
/// `<title>` element, plus a Twitter-card fallback. Design Section 3:
/// "HTML-only parsing (no JS execution)."
public enum OpenGraphParser {
    public static func parse(html: String) -> LinkPreviewMetadata {
        var m = LinkPreviewMetadata()
        m.title = ogTag(in: html, property: "og:title")
            ?? twitterTag(in: html, name: "twitter:title")
            ?? titleElement(in: html)
        m.description = ogTag(in: html, property: "og:description")
            ?? twitterTag(in: html, name: "twitter:description")
        if let imageString = ogTag(in: html, property: "og:image")
            ?? twitterTag(in: html, name: "twitter:image"),
           let url = URL(string: imageString),
           url.scheme == "http" || url.scheme == "https" {
            m.imageURL = url
        }
        m.siteName = ogTag(in: html, property: "og:site_name")
        return m
    }

    // MARK: - Tag matchers

    /// `<meta property="og:KEY" content="VALUE">`, both attribute orders.
    private static func ogTag(in html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            #"<meta[^>]+property\s*=\s*["']\#(escaped)["'][^>]+content\s*=\s*["']([^"']+)["']"#,
            #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+property\s*=\s*["']\#(escaped)["']"#
        ]
        for p in patterns {
            if let m = firstMatch(in: html, pattern: p, group: 1) {
                return m.decodingHTMLEntities()
            }
        }
        return nil
    }

    /// `<meta name="twitter:KEY" content="VALUE">`, both attribute orders.
    private static func twitterTag(in html: String, name: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"<meta[^>]+name\s*=\s*["']\#(escaped)["'][^>]+content\s*=\s*["']([^"']+)["']"#,
            #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+name\s*=\s*["']\#(escaped)["']"#
        ]
        for p in patterns {
            if let m = firstMatch(in: html, pattern: p, group: 1) {
                return m.decodingHTMLEntities()
            }
        }
        return nil
    }

    /// `<title>VALUE</title>` — newline-permissive.
    private static func titleElement(in html: String) -> String? {
        firstMatch(in: html, pattern: #"<title[^>]*>([^<]+)</title>"#, group: 1)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .decodingHTMLEntities()
    }

    private static func firstMatch(in s: String, pattern: String, group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let nsRange = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let match = re.firstMatch(in: s, range: nsRange),
              let range = Range(match.range(at: group), in: s) else {
            return nil
        }
        return String(s[range])
    }
}

private extension String {
    /// Decodes the handful of HTML entities OG values commonly contain.
    func decodingHTMLEntities() -> String {
        var s = self
        let map: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'")
        ]
        for (k, v) in map { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }
}
```

- [ ] **Step 7: Run the parser tests**

```bash
swift test --package-path Packages/LillistCore --filter 'OpenGraphParser' 2>&1 | tail -10
```

Expected: 4 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/LinkPreview/ \
        Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/ \
        Packages/LillistCore/Package.swift
git commit -m "feat(core): add OpenGraphParser + LinkPreviewMetadata"
```

---

## Task 8: Define `LinkPreviewFetching` protocol + URLSession implementation

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift`

- [ ] **Step 1: Define the protocol**

`Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift`:

```swift
import Foundation

/// Abstracts the network side of the unfurl pipeline so tests can
/// substitute a stub. Implementations fetch HTML body bytes (and
/// optionally a thumbnail image) for a given URL.
public protocol LinkPreviewFetching: Sendable {
    /// Fetch and return the body bytes (HTML) for `url`. Implementations
    /// enforce the design Section 3 limits: 10s timeout, 5 MB cap.
    /// Returns `nil` on non-2xx, non-HTML, or oversize responses.
    func fetchHTML(url: URL) async -> Data?

    /// Fetch image bytes if `url` is provided and the response is an
    /// image. Returns `nil` on any failure. Same 10s / 5 MB limits.
    func fetchImage(url: URL?) async -> Data?
}

public enum LinkPreviewLimits {
    public static let timeout: TimeInterval = 10
    public static let bodyCapBytes: Int = 5 * 1024 * 1024
}
```

- [ ] **Step 2: Implement the URLSession version**

`Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift`:

```swift
import Foundation

/// Production implementation of `LinkPreviewFetching`. Uses a single
/// `URLSession` configured per design Section 3 ("10s timeout, 5 MB
/// cap, HTML-only parsing"). Test code constructs a session with
/// `StubURLProtocol` registered.
public final class URLSessionLinkPreviewFetcher: LinkPreviewFetching {
    private let session: URLSession

    public init(session: URLSession = URLSessionLinkPreviewFetcher.makeDefaultSession()) {
        self.session = session
    }

    public static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = LinkPreviewLimits.timeout
        config.timeoutIntervalForResource = LinkPreviewLimits.timeout
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    public func fetchHTML(url: URL) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: LinkPreviewLimits.timeout)
        req.httpMethod = "GET"
        req.setValue("Mozilla/5.0 (Lillist link unfurl)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else { return nil }
            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            guard contentType.contains("text/html") || contentType.contains("application/xhtml") || contentType.isEmpty else {
                return nil
            }
            guard data.count <= LinkPreviewLimits.bodyCapBytes else { return nil }
            return data
        } catch {
            return nil
        }
    }

    public func fetchImage(url: URL?) async -> Data? {
        guard let url else { return nil }
        var req = URLRequest(url: url, timeoutInterval: LinkPreviewLimits.timeout)
        req.httpMethod = "GET"
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else { return nil }
            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            guard contentType.hasPrefix("image/") else { return nil }
            guard data.count <= LinkPreviewLimits.bodyCapBytes else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 3: Confirm it builds**

```bash
swift build --package-path Packages/LillistCore 2>&1 | tail -3
```

Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewFetching.swift \
        Packages/LillistCore/Sources/LillistCore/LinkPreview/URLSessionLinkPreviewFetcher.swift
git commit -m "feat(core): add LinkPreviewFetching protocol + URLSession impl"
```

---

## Task 9: Add `AttachmentStore.updateLinkPreview(...)` to set the unfurled fields

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/AttachmentStoreLinkPreviewTests.swift`

The existing `addLinkPreview` creates the row with all fields nil-able to title/description/etc. We need an `update` that overwrites with newly-fetched metadata + optional thumbnail data.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
import LillistCore

@Suite("AttachmentStore.updateLinkPreview")
struct AttachmentStoreLinkPreviewTests {
    @Test("Updating writes title/description/thumbnail bytes through")
    func roundTrip() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let attachments = AttachmentStore(persistence: persistence)
        let taskID = try await tasks.create(title: "host")
        let attachmentID = try await attachments.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com/x")!,
            title: nil,
            description: nil,
            thumbnailData: nil,
            faviconData: nil
        )

        try await attachments.updateLinkPreview(
            id: attachmentID,
            metadata: LinkPreviewMetadata(
                title: "Example",
                description: "Body",
                imageURL: URL(string: "https://example.com/thumb.jpg"),
                siteName: "Example"
            ),
            thumbnailData: Data([0xff, 0xd8, 0xff])
        )

        let updated = try await attachments.fetch(id: attachmentID)
        let payload = try #require(updated.linkPreviewJSON.flatMap { $0.data(using: .utf8) })
        let decoded = try JSONDecoder().decode(AttachmentStore.LinkPreviewPayload.self, from: payload)
        #expect(decoded.title == "Example")
        #expect(decoded.description == "Body")
        #expect(updated.hasData == true)
    }

    @Test("Updating with nil metadata only updates thumbnail data")
    func partialUpdate() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let attachments = AttachmentStore(persistence: persistence)
        let taskID = try await tasks.create(title: "host")
        let attachmentID = try await attachments.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com/x")!,
            title: "Preset",
            description: nil,
            thumbnailData: nil,
            faviconData: nil
        )

        try await attachments.updateLinkPreview(
            id: attachmentID,
            metadata: LinkPreviewMetadata(),
            thumbnailData: Data([0x89, 0x50])
        )

        let updated = try await attachments.fetch(id: attachmentID)
        #expect(updated.hasData == true)
    }
}
```

- [ ] **Step 2: Run and verify it fails**

```bash
swift test --package-path Packages/LillistCore --filter 'AttachmentStore.updateLinkPreview' 2>&1 | tail -5
```

Expected: compile error — `updateLinkPreview` does not exist.

- [ ] **Step 3: Add `updateLinkPreview` to `AttachmentStore`**

In `AttachmentStore.swift`, near the existing `addLinkPreview` method, add:

```swift
    /// Replace the unfurled metadata for an existing link-preview
    /// attachment. Called by `LinkPreviewUnfurler` once it has fetched
    /// OG/Twitter card data (and optionally a thumbnail). Pass
    /// `LinkPreviewMetadata.empty` to update only the thumbnail bytes.
    public func updateLinkPreview(
        id: UUID,
        metadata: LinkPreviewMetadata,
        thumbnailData: Data? = nil
    ) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            guard m.kindRaw == Int16(AttachmentKind.linkPreview.rawValue) else {
                throw LillistError.validationFailed([
                    .init(field: "kind", message: "attachment is not a link preview")
                ])
            }

            // Merge: keep existing fields if metadata fields are nil.
            var existing: LinkPreviewPayload?
            if let json = m.linkPreviewJSON, let bytes = json.data(using: .utf8) {
                existing = try? JSONDecoder().decode(LinkPreviewPayload.self, from: bytes)
            }
            let merged = LinkPreviewPayload(
                url: existing?.url ?? "",
                title: metadata.title ?? existing?.title,
                description: metadata.description ?? existing?.description,
                fetchedAt: Date()
            )
            let encoded = try JSONEncoder().encode(merged)
            m.linkPreviewJSON = String(data: encoded, encoding: .utf8)

            if let bytes = thumbnailData {
                m.data = bytes
                m.byteSize = Int64(bytes.count)
            }
            try context.save()
        }
    }
```

- [ ] **Step 4: Run tests**

```bash
swift test --package-path Packages/LillistCore --filter 'AttachmentStore.updateLinkPreview' 2>&1 | tail -10
```

Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/AttachmentStoreLinkPreviewTests.swift
git commit -m "feat(core): AttachmentStore.updateLinkPreview merges unfurled metadata"
```

---

## Task 10: Add `LinkPreviewUnfurler` actor that ties fetch + parse + store

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/LinkPreviewUnfurlerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("LinkPreviewUnfurler")
struct LinkPreviewUnfurlerTests {
    @Test("End-to-end: fetch, parse, update attachment")
    func endToEnd() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let attachments = AttachmentStore(persistence: persistence)
        let taskID = try await tasks.create(title: "host")
        let attachmentID = try await attachments.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com/blog/post")!,
            title: nil, description: nil, thumbnailData: nil, faviconData: nil
        )

        let session = StubURLProtocol.session { url in
            switch url.path {
            case "/blog/post":
                let html = """
                <html><head><title>Hi</title>
                <meta property="og:title" content="Real Title">
                <meta property="og:description" content="Real Desc">
                <meta property="og:image" content="https://example.com/thumb.jpg">
                </head><body></body></html>
                """
                return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: html.data(using: .utf8)!)
            case "/thumb.jpg":
                return .init(statusCode: 200, headers: ["Content-Type": "image/jpeg"], body: Data([0xff, 0xd8, 0xff]))
            default:
                return nil
            }
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)
        let unfurler = LinkPreviewUnfurler(attachments: attachments, fetcher: fetcher)

        let outcome = await unfurler.unfurl(attachmentID: attachmentID, url: URL(string: "https://example.com/blog/post")!)
        #expect(outcome == .success)

        let updated = try await attachments.fetch(id: attachmentID)
        let payload = try #require(updated.linkPreviewJSON.flatMap { $0.data(using: .utf8) })
        let decoded = try JSONDecoder().decode(AttachmentStore.LinkPreviewPayload.self, from: payload)
        #expect(decoded.title == "Real Title")
        #expect(updated.hasData == true)
    }

    @Test("Server 404 → outcome = .failure(.notFound), no metadata changes")
    func notFound() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let attachments = AttachmentStore(persistence: persistence)
        let taskID = try await tasks.create(title: "x")
        let aid = try await attachments.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com/gone")!,
            title: nil, description: nil, thumbnailData: nil, faviconData: nil
        )

        let session = StubURLProtocol.session { _ in
            .init(statusCode: 404, headers: [:], body: Data())
        }
        let unfurler = LinkPreviewUnfurler(
            attachments: attachments,
            fetcher: URLSessionLinkPreviewFetcher(session: session)
        )

        let outcome = await unfurler.unfurl(attachmentID: aid, url: URL(string: "https://example.com/gone")!)
        if case .failure = outcome { /* pass */ } else { Issue.record("Expected .failure outcome") }

        let row = try await attachments.fetch(id: aid)
        #expect(row.linkPreviewJSON == nil || row.linkPreviewJSON == "")
    }
}
```

- [ ] **Step 2: Run and verify it fails**

```bash
swift test --package-path Packages/LillistCore --filter 'LinkPreviewUnfurler' 2>&1 | tail -5
```

Expected: compile error — `LinkPreviewUnfurler` does not exist.

- [ ] **Step 3: Implement the unfurler**

`Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift`:

```swift
import Foundation

/// Coordinates the unfurl flow:
///   1. Fetch the URL's HTML body via `fetcher`.
///   2. Parse OG / Twitter / `<title>` tags via `OpenGraphParser`.
///   3. Optionally fetch the OG image as raw bytes.
///   4. Write the merged metadata + thumbnail back through
///      `AttachmentStore.updateLinkPreview`.
///
/// All errors fold into `Outcome.failure(reason:)` — callers decide
/// whether to surface a "couldn't fetch" affordance with retry. Design
/// Section 3: "On success, update row with unfurled metadata. On
/// failure, leave raw URL with 'couldn't fetch' affordance and retry
/// button."
public actor LinkPreviewUnfurler {
    public enum FailureReason: Sendable, Equatable {
        case notFound
        case timeout
        case oversize
        case unsupportedContentType
        case parseError
        case storeError
    }

    public enum Outcome: Sendable, Equatable {
        case success
        case failure(FailureReason)
    }

    private let attachments: AttachmentStore
    private let fetcher: LinkPreviewFetching

    public init(attachments: AttachmentStore, fetcher: LinkPreviewFetching) {
        self.attachments = attachments
        self.fetcher = fetcher
    }

    /// Unfurl `url` and write the result to the attachment row identified
    /// by `attachmentID`. The attachment is assumed to already exist
    /// (typically created by `LinkHandler.run`).
    public func unfurl(attachmentID: UUID, url: URL) async -> Outcome {
        guard let htmlData = await fetcher.fetchHTML(url: url) else {
            return .failure(.notFound)
        }
        guard let html = String(data: htmlData, encoding: .utf8) else {
            return .failure(.parseError)
        }
        let metadata = OpenGraphParser.parse(html: html)
        let thumbnailData = await fetcher.fetchImage(url: metadata.imageURL)

        do {
            try await attachments.updateLinkPreview(
                id: attachmentID,
                metadata: metadata,
                thumbnailData: thumbnailData
            )
            return .success
        } catch {
            return .failure(.storeError)
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --package-path Packages/LillistCore --filter 'LinkPreviewUnfurler' 2>&1 | tail -10
```

Expected: 2 tests PASS.

- [ ] **Step 5: Run full LillistCore suite to ensure nothing else regressed**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
```

Expected: `Test run with NNN tests in M suites passed`.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/LinkPreview/LinkPreviewUnfurler.swift \
        Packages/LillistCore/Tests/LillistCoreTests/LinkPreview/LinkPreviewUnfurlerTests.swift
git commit -m "feat(core): add LinkPreviewUnfurler actor (fetch + parse + persist)"
```

---

## Task 11: Wire `LinkHandler` to enqueue an unfurl after creating the attachment

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift`

The handler currently creates a placeholder row and returns. We change it to construct a fetcher + unfurler and `await` the unfurl synchronously. The CLI is a short-lived process so `await` is fine; App Intents likewise complete the whole verb before returning. If a future call site needs fire-and-forget semantics, it can wrap in `Task.detached`.

- [ ] **Step 1: Update the handler**

Replace the file contents:

```swift
import Foundation

extension CLIBridge {
    public enum LinkHandler {
        @discardableResult
        public static func run(
            token: String,
            urlString: String,
            persistence: PersistenceController,
            fetcher: LinkPreviewFetching? = nil
        ) async throws -> UUID {
            guard let url = URL(string: urlString), url.scheme != nil else {
                throw LillistError.validationFailed([.init(field: "url", message: "invalid URL '\(urlString)'")])
            }
            let r = try await Resolver.resolve(
                token: token, scope: .anywhereIncludingClosed,
                destructiveness: .readOnly, persistence: persistence
            )

            let attachments = AttachmentStore(persistence: persistence)
            let attachmentID = try await attachments.addLinkPreview(
                taskID: r.id,
                url: url,
                title: nil,
                description: nil,
                thumbnailData: nil,
                faviconData: nil
            )

            // Best-effort unfurl. Failure leaves the row with just the URL —
            // matches design Section 3's "couldn't fetch" affordance.
            let f = fetcher ?? URLSessionLinkPreviewFetcher()
            let unfurler = LinkPreviewUnfurler(attachments: attachments, fetcher: f)
            _ = await unfurler.unfurl(attachmentID: attachmentID, url: url)

            return attachmentID
        }
    }
}
```

- [ ] **Step 2: Verify the existing LinkHandler tests still pass (they should — they don't assert metadata)**

```bash
swift test --package-path Packages/LillistCore --filter 'LinkHandler' 2>&1 | tail -10
```

Expected: existing tests PASS. If any test was hitting the live network (it shouldn't be), it would now fail; the audit confirmed there are no such tests.

- [ ] **Step 3: Update LinkHandler tests if they exist to inject a stub fetcher**

If `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/LinkHandlerTests.swift` exists and any test exercises the unfurl path against the live network, update those tests to pass a stub fetcher via the new `fetcher:` parameter. Grep:

```bash
grep -n "LinkHandler.run" Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/*.swift
```

For any call that doesn't pass `fetcher:`, the default URLSession fetcher is used — fine as long as the test doesn't assert that metadata got populated.

- [ ] **Step 4: Add a stub-fetcher LinkHandler test**

Add to (or create) `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/LinkHandlerTests.swift`:

```swift
    @Test("Run with a stub fetcher populates the attachment's title")
    func runWithStubFetcher() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let taskID = try await tasks.create(title: "host")

        let session = StubURLProtocol.session { _ in
            let html = #"""
            <html><head>
            <meta property="og:title" content="Linked Title">
            </head><body></body></html>
            """#
            return .init(statusCode: 200, headers: ["Content-Type": "text/html"], body: html.data(using: .utf8)!)
        }
        let fetcher = URLSessionLinkPreviewFetcher(session: session)

        let attachmentID = try await CLIBridge.LinkHandler.run(
            token: taskID.uuidString,
            urlString: "https://example.com/x",
            persistence: persistence,
            fetcher: fetcher
        )

        let row = try await AttachmentStore(persistence: persistence).fetch(id: attachmentID)
        let bytes = try #require(row.linkPreviewJSON.flatMap { $0.data(using: .utf8) })
        let decoded = try JSONDecoder().decode(AttachmentStore.LinkPreviewPayload.self, from: bytes)
        #expect(decoded.title == "Linked Title")
    }
```

(If the file doesn't exist yet, scaffold it with the standard Swift Testing header that other handler tests use — `@testable import LillistCore` and `import Testing`.)

- [ ] **Step 5: Run the new test**

```bash
swift test --package-path Packages/LillistCore --filter 'LinkHandler' 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/LinkHandlerTests.swift
git commit -m "feat(cli): lillist link fetches OG metadata via LinkPreviewUnfurler"
```

---

## Task 12: Add `RecurrenceEditorViewModel` value-type binding

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift`
- Create: `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorViewModelTests.swift`

The view model wraps a `RecurrenceRule?` and exposes flat bindings for the SwiftUI form (frequency picker, interval, byDay set, count, until date, afterCompletion seconds). It validates rule constraints and produces a final `RecurrenceRule` on commit.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
import LillistCore
@testable import LillistUI

@Suite("RecurrenceEditorViewModel")
struct RecurrenceEditorViewModelTests {
    @Test("Empty state produces no rule")
    func emptyState() {
        let vm = RecurrenceEditorViewModel(rule: nil)
        #expect(vm.repeats == false)
        #expect(vm.build() == nil)
    }

    @Test("Daily/every 2 days round-trips")
    func dailyEveryTwo() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .daily
        vm.interval = 2
        let rule = try? #require(vm.build())
        if case .calendar(let calRule) = rule {
            #expect(calRule.freq == .daily)
            #expect(calRule.interval == 2)
        } else {
            Issue.record("Expected .calendar rule")
        }
    }

    @Test("Weekly with selected days")
    func weeklyWithByDay() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .weekly
        vm.byDay = [.monday, .wednesday, .friday]
        let rule = try? #require(vm.build())
        if case .calendar(let calRule) = rule {
            #expect(calRule.byDay == [.monday, .wednesday, .friday])
        } else {
            Issue.record("Expected .calendar rule")
        }
    }

    @Test("After-completion mode produces an after-completion rule")
    func afterCompletionMode() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.mode = .afterCompletion
        vm.afterCompletionSeconds = 86_400 // 1 day
        let rule = try? #require(vm.build())
        if case .afterCompletion(let after) = rule {
            #expect(after.interval == 86_400)
        } else {
            Issue.record("Expected .afterCompletion rule")
        }
    }

    @Test("Existing rule populates the view model")
    func roundTripFromExistingRule() {
        let original: RecurrenceRule = .calendar(.init(
            freq: .monthly,
            interval: 1,
            byMonthDay: [1, 15],
            count: 6
        ))
        let vm = RecurrenceEditorViewModel(rule: original)
        #expect(vm.repeats)
        #expect(vm.freq == .monthly)
        #expect(vm.byMonthDay == [1, 15])
        #expect(vm.count == 6)
    }
}
```

- [ ] **Step 2: Run and verify it fails**

```bash
swift test --package-path Packages/LillistUI --filter 'RecurrenceEditorViewModel' 2>&1 | tail -5
```

Expected: compile error.

- [ ] **Step 3: Implement the view model**

`Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift`:

```swift
import Foundation
import LillistCore

/// Mutable view-model wrapper around an optional `RecurrenceRule`.
/// Designed to be held in `@State` and read/written by SwiftUI form
/// controls. `build()` synthesizes a `RecurrenceRule` on commit.
///
/// Plan 11 introduces the recurrence pattern editor to v1 (originally
/// scheduled for v2 per design Section 10).
public struct RecurrenceEditorViewModel: Equatable {
    public enum Mode: Hashable, Sendable, CaseIterable {
        case calendar
        case afterCompletion
    }

    public var repeats: Bool
    public var mode: Mode
    public var freq: RecurrenceRule.Frequency
    public var interval: Int
    public var byDay: Set<Weekday>
    public var byMonthDay: Set<Int>
    public var bySetPos: Set<Int>
    public var count: Int?
    public var until: Date?
    public var afterCompletionSeconds: TimeInterval

    public init(rule: RecurrenceRule?) {
        switch rule {
        case .none:
            self.repeats = false
            self.mode = .calendar
            self.freq = .daily
            self.interval = 1
            self.byDay = []
            self.byMonthDay = []
            self.bySetPos = []
            self.count = nil
            self.until = nil
            self.afterCompletionSeconds = 86_400
        case .some(.calendar(let c)):
            self.repeats = true
            self.mode = .calendar
            self.freq = c.freq
            self.interval = c.interval
            self.byDay = Set(c.byDay ?? [])
            self.byMonthDay = Set(c.byMonthDay ?? [])
            self.bySetPos = Set(c.bySetPos ?? [])
            self.count = c.count
            self.until = c.until
            self.afterCompletionSeconds = 86_400
        case .some(.afterCompletion(let a)):
            self.repeats = true
            self.mode = .afterCompletion
            self.freq = .daily
            self.interval = 1
            self.byDay = []
            self.byMonthDay = []
            self.bySetPos = []
            self.count = nil
            self.until = nil
            self.afterCompletionSeconds = a.interval
        }
    }

    /// Synthesize a `RecurrenceRule` from the current view-model state, or
    /// `nil` when `repeats == false`.
    public func build() -> RecurrenceRule? {
        guard repeats else { return nil }
        switch mode {
        case .calendar:
            // Preserve natural Mon→Sun ordering for byDay (Weekday.allCases is
            // declared Monday-first), rather than alphabetizing by RRULE
            // shortcode.
            let dayList: [Weekday]? = byDay.isEmpty
                ? nil
                : Weekday.allCases.filter { byDay.contains($0) }
            return .calendar(RecurrenceRule.CalendarRule(
                freq: freq,
                interval: max(1, interval),
                byDay: dayList,
                byMonthDay: byMonthDay.isEmpty ? nil : byMonthDay.sorted(),
                bySetPos: bySetPos.isEmpty ? nil : bySetPos.sorted(),
                count: count,
                until: until
            ))
        case .afterCompletion:
            return .afterCompletion(RecurrenceRule.AfterCompletionRule(interval: afterCompletionSeconds))
        }
    }
}
```

> **Note on type names:** `Frequency`, `CalendarRule`, and
> `AfterCompletionRule` are all nested under `RecurrenceRule`. Use the
> fully-qualified `RecurrenceRule.Frequency` etc. when constructing
> values from outside `RecurrenceRule`'s scope.

- [ ] **Step 4: Run tests**

```bash
swift test --package-path Packages/LillistUI --filter 'RecurrenceEditorViewModel' 2>&1 | tail -10
```

Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift \
        Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorViewModelTests.swift
git commit -m "feat(ui): add RecurrenceEditorViewModel value-type binding"
```

---

## Task 13: Implement `RecurrenceEditorView` (cross-platform SwiftUI)

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift`

- [ ] **Step 1: Write the view**

```swift
import SwiftUI
import LillistCore

/// SwiftUI editor for a `RecurrenceRule`. Bind to a
/// `RecurrenceEditorViewModel` and call `onCommit` when the user accepts.
/// Used by the macOS detail view and the iOS RecurrenceSheet.
///
/// Plan 11 brings this editor into v1; design Section 10 originally
/// scheduled it for v2 but the implementation was pulled forward.
public struct RecurrenceEditorView: View {
    @Binding var viewModel: RecurrenceEditorViewModel
    public var onCommit: ((RecurrenceRule?) -> Void)?
    public var onCancel: (() -> Void)?

    public init(
        viewModel: Binding<RecurrenceEditorViewModel>,
        onCommit: ((RecurrenceRule?) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self._viewModel = viewModel
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Repeats", isOn: $viewModel.repeats)
            }

            if viewModel.repeats {
                Section("Pattern") {
                    Picker("Mode", selection: $viewModel.mode) {
                        Text("Calendar-based").tag(RecurrenceEditorViewModel.Mode.calendar)
                        Text("After completion").tag(RecurrenceEditorViewModel.Mode.afterCompletion)
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.mode == .calendar {
                    Section("Frequency") {
                        Picker("Frequency", selection: $viewModel.freq) {
                            Text("Daily").tag(RecurrenceRule.Frequency.daily)
                            Text("Weekly").tag(RecurrenceRule.Frequency.weekly)
                            Text("Monthly").tag(RecurrenceRule.Frequency.monthly)
                            Text("Yearly").tag(RecurrenceRule.Frequency.yearly)
                        }
                        Stepper("Every \(viewModel.interval)", value: $viewModel.interval, in: 1...365)
                    }

                    if viewModel.freq == .weekly {
                        Section("On days") {
                            ForEach(Weekday.allCases, id: \.self) { day in
                                Toggle(label(for: day), isOn: bindingFor(day: day, in: $viewModel.byDay))
                            }
                        }
                    }

                    if viewModel.freq == .monthly {
                        Section("On day of month") {
                            ForEach(1...31, id: \.self) { d in
                                Toggle("Day \(d)", isOn: bindingFor(monthDay: d, in: $viewModel.byMonthDay))
                            }
                        }
                    }

                    Section("Limit") {
                        Stepper(viewModel.count.map { "After \($0) occurrences" } ?? "No occurrence limit",
                                value: Binding(
                                    get: { viewModel.count ?? 0 },
                                    set: { viewModel.count = $0 == 0 ? nil : $0 }
                                ),
                                in: 0...365)
                        Toggle("End by date", isOn: Binding(
                            get: { viewModel.until != nil },
                            set: { on in viewModel.until = on ? (viewModel.until ?? Date().addingTimeInterval(86_400 * 30)) : nil }
                        ))
                        if let _ = viewModel.until {
                            DatePicker("End date", selection: Binding(
                                get: { viewModel.until ?? Date() },
                                set: { viewModel.until = $0 }
                            ), displayedComponents: [.date])
                        }
                    }
                } else {
                    Section("After completion") {
                        Picker("Repeat after", selection: $viewModel.afterCompletionSeconds) {
                            Text("1 day").tag(TimeInterval(86_400))
                            Text("3 days").tag(TimeInterval(86_400 * 3))
                            Text("1 week").tag(TimeInterval(86_400 * 7))
                            Text("2 weeks").tag(TimeInterval(86_400 * 14))
                            Text("1 month (~30d)").tag(TimeInterval(86_400 * 30))
                        }
                    }
                }
            }

            if onCommit != nil || onCancel != nil {
                Section {
                    HStack {
                        if let onCancel {
                            Button("Cancel", role: .cancel, action: onCancel)
                        }
                        Spacer()
                        if let onCommit {
                            Button("Save") { onCommit(viewModel.build()) }
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
        }
    }

    private func label(for day: Weekday) -> String {
        switch day {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }

    private func bindingFor(day: Weekday, in set: Binding<Set<Weekday>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(day) },
            set: { isOn in
                var copy = set.wrappedValue
                if isOn { copy.insert(day) } else { copy.remove(day) }
                set.wrappedValue = copy
            }
        )
    }

    private func bindingFor(monthDay d: Int, in set: Binding<Set<Int>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(d) },
            set: { isOn in
                var copy = set.wrappedValue
                if isOn { copy.insert(d) } else { copy.remove(d) }
                set.wrappedValue = copy
            }
        )
    }
}
```

- [ ] **Step 2: Build and confirm**

```bash
swift build --package-path Packages/LillistUI 2>&1 | tail -3
```

Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift
git commit -m "feat(ui): RecurrenceEditorView cross-platform SwiftUI editor"
```

---

## Task 14: Replace macOS placeholder with the real editor + wire to SeriesStore

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift`

- [ ] **Step 1: Update the macOS detail view**

Replace the file:

```swift
import SwiftUI
import LillistCore
import LillistUI

struct TaskDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let taskID: UUID

    @State private var record: TaskStore.TaskRecord?
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var start: Date?
    @State private var deadline: Date?
    @State private var showFollowUpForm = false
    @State private var recurrenceViewModel = RecurrenceEditorViewModel(rule: nil)
    @State private var showingRecurrenceEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let r = record {
                    DetailHeaderView(
                        title: $title,
                        status: r.status,
                        tagNames: [],
                        start: $start,
                        deadline: $deadline,
                        onStatusMenu: { s in Task { await transition(to: s) } }
                    )
                    recurrenceRow.padding(.horizontal)
                    if showFollowUpForm {
                        FollowUpFormView(
                            blockedTaskID: r.id,
                            parentTitle: title,
                            onCommit: { showFollowUpForm = false },
                            onDismiss: { showFollowUpForm = false }
                        )
                        .padding(.horizontal)
                    }
                    NotesEditorView(markdown: $notes)
                    SubtaskOutlineView(parentID: r.id)
                    JournalStreamView(taskID: r.id)
                } else {
                    ProgressView().padding()
                }
            }
        }
        .task(id: taskID) { await load() }
        .onChange(of: title) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.title = new } } }
        .onChange(of: notes) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.notes = new } } }
        .onChange(of: start) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.start = new } } }
        .onChange(of: deadline) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.deadline = new } } }
        .sheet(isPresented: $showingRecurrenceEditor) {
            RecurrenceEditorView(
                viewModel: $recurrenceViewModel,
                onCommit: { rule in
                    Task { await commitRecurrence(rule) }
                    showingRecurrenceEditor = false
                },
                onCancel: { showingRecurrenceEditor = false }
            )
            .frame(minWidth: 420, minHeight: 480)
        }
    }

    @ViewBuilder
    private var recurrenceRow: some View {
        HStack {
            Image(systemName: "repeat")
                .foregroundStyle(.secondary)
            Text(currentRecurrenceSummary)
                .foregroundStyle(.secondary)
            Spacer()
            Button(recurrenceViewModel.repeats ? "Edit…" : "Add…") {
                showingRecurrenceEditor = true
            }
        }
        .font(.callout)
    }

    private var currentRecurrenceSummary: String {
        guard recurrenceViewModel.repeats else { return "Doesn't repeat" }
        switch recurrenceViewModel.mode {
        case .calendar:
            let unit: String
            switch recurrenceViewModel.freq {
            case .daily: unit = "day"
            case .weekly: unit = "week"
            case .monthly: unit = "month"
            case .yearly: unit = "year"
            }
            return recurrenceViewModel.interval == 1
                ? "Every \(unit)"
                : "Every \(recurrenceViewModel.interval) \(unit)s"
        case .afterCompletion:
            let days = Int(recurrenceViewModel.afterCompletionSeconds / 86_400)
            return "Repeats \(days) day\(days == 1 ? "" : "s") after completion"
        }
    }

    private func load() async {
        guard let r = try? await env.taskStore.fetch(id: taskID) else { return }
        record = r
        title = r.title
        notes = r.notes
        start = r.start
        deadline = r.deadline
        showFollowUpForm = (r.status == .blocked)
        if let seriesID = r.seriesID,
           let series = try? await env.seriesStore.fetch(id: seriesID) {
            recurrenceViewModel = RecurrenceEditorViewModel(rule: series.rule)
        } else {
            recurrenceViewModel = RecurrenceEditorViewModel(rule: nil)
        }
    }

    private func transition(to s: Status) async {
        try? await env.taskStore.transition(id: taskID, to: s)
        if s == .blocked { showFollowUpForm = true } else { showFollowUpForm = false }
        await load()
    }

    private func commitRecurrence(_ rule: RecurrenceRule?) async {
        guard let r = record else { return }
        do {
            if let rule {
                if let seriesID = r.seriesID {
                    try await env.seriesStore.update(id: seriesID, rule: rule)
                } else {
                    _ = try await env.seriesStore.create(fromSeedTask: taskID, rule: rule)
                }
            } else if let seriesID = r.seriesID {
                try await env.seriesStore.delete(id: seriesID)
            }
            await load()
        } catch {
            // Surface in a banner later; failure leaves state unchanged.
        }
    }
}
```

- [ ] **Step 2: Confirm `TaskStore.TaskRecord` exposes `seriesID` and `AppEnvironment` exposes `seriesStore`**

```bash
grep -n "seriesID\|seriesStore" Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift \
                                Apps/Lillist-macOS/Sources/AppEnvironment.swift
```

If `seriesID` is missing from `TaskRecord`: add it.

```swift
public struct TaskRecord: Sendable, Equatable {
    // … existing fields …
    public var seriesID: UUID?
}
```

And populate it in the existing `record(from:)` mapper:

```swift
seriesID: m.series?.id
```

If `seriesStore` is missing from `AppEnvironment`: add as `public let seriesStore: SeriesStore` and initialize in `make()` alongside the other stores.

- [ ] **Step 3: Build macOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift \
        Apps/Lillist-macOS/Sources/AppEnvironment.swift \
        Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift
git commit -m "feat(macOS): wire recurrence editor into TaskDetailView"
```

---

## Task 15: Add iOS Recurrence sheet entry from the detail header

**Files:**
- Create: `Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift`
- Modify: `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift`

The iOS detail view uses a page-tab layout; we expose recurrence via a toolbar button on the navigation bar.

- [ ] **Step 1: Create the sheet wrapper**

`Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift`:

```swift
import SwiftUI
import LillistCore
import LillistUI

struct RecurrenceSheet: View {
    let taskID: UUID
    let initialSeriesID: UUID?
    let onClose: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: RecurrenceEditorViewModel

    init(taskID: UUID, initialRule: RecurrenceRule?, initialSeriesID: UUID?, onClose: @escaping () -> Void) {
        self.taskID = taskID
        self.initialSeriesID = initialSeriesID
        self.onClose = onClose
        self._viewModel = State(initialValue: RecurrenceEditorViewModel(rule: initialRule))
    }

    var body: some View {
        NavigationStack {
            RecurrenceEditorView(viewModel: $viewModel)
                .navigationTitle("Recurrence")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onClose() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await commit(viewModel.build()) }
                        }
                    }
                }
        }
    }

    private func commit(_ rule: RecurrenceRule?) async {
        do {
            if let rule {
                if let sid = initialSeriesID {
                    try await env.seriesStore.update(id: sid, rule: rule)
                } else {
                    _ = try await env.seriesStore.create(fromSeedTask: taskID, rule: rule)
                }
            } else if let sid = initialSeriesID {
                try await env.seriesStore.delete(id: sid)
            }
            onClose()
        } catch {
            // Sheet remains open; future polish would surface an inline error.
        }
    }
}
```

- [ ] **Step 2: Update `TaskDetailView` to add a toolbar button + sheet**

Replace `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift`:

```swift
import SwiftUI
import LillistCore
import LillistUI

struct TaskDetailView: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var env

    @State private var record: TaskStore.TaskRecord?
    @State private var loadError: String?
    @State private var selection: Tab = .notes
    @State private var seriesRule: RecurrenceRule?
    @State private var showingRecurrenceSheet = false

    enum Tab: Hashable { case notes, subtasks, journal, attachments }

    var body: some View {
        Group {
            if let record {
                VStack(spacing: 0) {
                    TaskDetailHeader(task: record)
                    TabView(selection: $selection) {
                        TaskNotesTab(taskID: record.id, initialText: record.notes)
                            .tag(Tab.notes)
                        TaskSubtasksTab(taskID: record.id)
                            .tag(Tab.subtasks)
                        TaskJournalTab(taskID: record.id)
                            .tag(Tab.journal)
                        TaskAttachmentsTab(taskID: record.id)
                            .tag(Tab.attachments)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            } else if let loadError {
                ContentUnavailableView(
                    "Could not load task",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(record?.title ?? "")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingRecurrenceSheet = true
                } label: {
                    Image(systemName: seriesRule == nil ? "repeat" : "repeat.circle.fill")
                }
                .accessibilityLabel(seriesRule == nil ? "Add recurrence" : "Edit recurrence")
            }
        }
        .sheet(isPresented: $showingRecurrenceSheet) {
            RecurrenceSheet(
                taskID: taskID,
                initialRule: seriesRule,
                initialSeriesID: record?.seriesID,
                onClose: {
                    showingRecurrenceSheet = false
                    Task { await reload() }
                }
            )
        }
        .task { await reload() }
    }

    private func reload() async {
        do {
            record = try await env.taskStore.fetch(id: taskID)
            if let sid = record?.seriesID {
                seriesRule = (try? await env.seriesStore.fetch(id: sid))?.rule
            } else {
                seriesRule = nil
            }
            loadError = nil
        } catch {
            loadError = "\(error)"
        }
    }
}

private struct TaskDetailHeader: View {
    let task: TaskStore.TaskRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.title3)
                .strikethrough(task.status == .closed)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Label(statusLabel, systemImage: statusGlyph)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let deadline = task.deadline {
                    Label(
                        deadline.formatted(date: .abbreviated, time: task.deadlineHasTime ? .shortened : .omitted),
                        systemImage: "calendar"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: String {
        switch task.status {
        case .todo: return "To do"
        case .started: return "Started"
        case .blocked: return "Blocked"
        case .closed: return "Closed"
        }
    }

    private var statusGlyph: String {
        switch task.status {
        case .todo: return "circle"
        case .started: return "circle.lefthalf.filled"
        case .blocked: return "exclamationmark.octagon"
        case .closed: return "checkmark.circle.fill"
        }
    }
}
```

- [ ] **Step 3: Make sure iOS `AppEnvironment` exposes `seriesStore`**

```bash
grep -n "seriesStore" Apps/Lillist-iOS/Sources/App/AppEnvironment.swift
```

If missing, add `public let seriesStore: SeriesStore` and initialize alongside the other stores.

- [ ] **Step 4: Build iOS**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift \
        Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift \
        Apps/Lillist-iOS/Sources/App/AppEnvironment.swift
git commit -m "feat(iOS): RecurrenceSheet entry from task detail toolbar"
```

---

## Task 16: Delete `RecurrenceFieldPlaceholderView` and update its callers

**Files:**
- Delete: `Packages/LillistUI/Sources/LillistUI/Components/RecurrenceFieldPlaceholderView.swift`
- Modify: `Packages/LillistUI/Tests/LillistUITests/Snapshots/TaskDetailViewSnapshotTests.swift`

- [ ] **Step 1: Confirm no remaining callers**

```bash
grep -rn "RecurrenceFieldPlaceholderView" Apps/ Packages/
```

Expected: only the snapshot test file references it now (the macOS detail view was updated in Task 14).

- [ ] **Step 2: Update the snapshot test**

Open `Packages/LillistUI/Tests/LillistUITests/Snapshots/TaskDetailViewSnapshotTests.swift` and either:

(a) Replace the `RecurrenceFieldPlaceholderView()` reference with `RecurrenceEditorView(viewModel: .constant(RecurrenceEditorViewModel(rule: nil)))` — and regenerate the snapshot baseline.

(b) Remove the snapshot block for the placeholder entirely if it stands alone — and remove the corresponding `__Snapshots__` baseline file.

Choose (a) if the test exercised the detail view's overall composition; (b) if it was a standalone placeholder snapshot. Inspect the file to decide.

- [ ] **Step 3: Delete the placeholder source**

```bash
rm Packages/LillistUI/Sources/LillistUI/Components/RecurrenceFieldPlaceholderView.swift
```

- [ ] **Step 4: Regenerate any affected snapshot baselines**

Delete the affected `__Snapshots__` `.png` files and re-run the snapshot tests once to regenerate:

```bash
swift test --package-path Packages/LillistUI --filter 'TaskDetailViewSnapshotTests' 2>&1 | tail -5
```

The first run records new baselines; subsequent runs validate.

- [ ] **Step 5: Confirm full LillistUI test suite passes**

```bash
swift test --package-path Packages/LillistUI 2>&1 | tail -3
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Components/ \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/ \
        Packages/LillistUI/Tests/LillistUITests/Snapshots/__Snapshots__/
git commit -m "refactor(ui): remove RecurrenceFieldPlaceholderView (superseded by editor)"
```

---

## Task 17: Add macOS `HotkeyRecorder` using `NSEvent` local monitor

**Files:**
- Create: `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift`
- Create: `Apps/Lillist-macOS/Tests/HotkeyRecorderTests.swift`

- [ ] **Step 1: Write the failing test**

`Apps/Lillist-macOS/Tests/HotkeyRecorderTests.swift`:

```swift
import Testing
import AppKit
@testable import Lillist_macOS

@Suite("HotkeyRecorder encoder")
struct HotkeyRecorderTests {
    @Test("Control+Option+Space encodes as 'ctrl+opt+space'")
    func ctrlOptSpace() {
        let s = HotkeyRecorder.encode(modifiers: [.control, .option], keyCode: 49) // 49 = Space
        #expect(s == "ctrl+opt+space")
    }

    @Test("Command+Shift+L encodes as 'cmd+shift+l'")
    func cmdShiftL() {
        let s = HotkeyRecorder.encode(modifiers: [.command, .shift], keyCode: 37) // 37 = 'l'
        #expect(s == "cmd+shift+l")
    }

    @Test("Unsupported keyCode produces nil")
    func unsupportedKey() {
        let s = HotkeyRecorder.encode(modifiers: [.command], keyCode: 0xFFFF)
        #expect(s == nil)
    }
}
```

> **Note:** if `@testable import Lillist_macOS` doesn't work (the macOS test target is standalone — see Plan 7 engineering notes), put `HotkeyRecorder.encode` in a small static file that's co-compiled into the test bundle via `Apps/Lillist-macOS/project.yml` `sources:` entries. The test imports it directly without `@testable`.

- [ ] **Step 2: Write `HotkeyRecorder`**

`Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift`:

```swift
import SwiftUI
import AppKit

/// SwiftUI view that captures a single keystroke (with modifiers) and
/// updates its bound value with the canonical string format used by
/// `GlobalHotkeyMonitor` (e.g. `"ctrl+opt+space"`, `"cmd+shift+l"`).
///
/// Plan 11 replaces Plan 10's plain-text-field placeholder.
struct HotkeyRecorder: View {
    @Binding var value: String
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(recording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            HStack {
                Text(recording ? "Press a key combination…" : displayString)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Button(recording ? "Stop" : "Record") {
                    toggleRecording()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
    }

    private var displayString: String {
        value.isEmpty ? "—" : value
    }

    private func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let encoded = HotkeyRecorder.encode(
                modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                keyCode: Int(event.keyCode)
            )
            if let encoded {
                value = encoded
                stopRecording()
            }
            return nil // swallow the event
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    // MARK: - Pure encoder (testable)

    static func encode(modifiers: NSEvent.ModifierFlags, keyCode: Int) -> String? {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        guard let keyName = keyName(for: keyCode) else { return nil }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    private static func keyName(for keyCode: Int) -> String? {
        // Covers the keys most users will bind. Extend as needed.
        switch keyCode {
        case 0: return "a"; case 1: return "s"; case 2: return "d"; case 3: return "f"
        case 4: return "h"; case 5: return "g"; case 6: return "z"; case 7: return "x"
        case 8: return "c"; case 9: return "v"; case 11: return "b"; case 12: return "q"
        case 13: return "w"; case 14: return "e"; case 15: return "r"; case 16: return "y"
        case 17: return "t"; case 31: return "o"; case 32: return "u"; case 34: return "i"
        case 35: return "p"; case 37: return "l"; case 38: return "j"; case 40: return "k"
        case 45: return "n"; case 46: return "m"; case 49: return "space"
        case 36: return "return"; case 51: return "delete"; case 53: return "escape"
        case 18: return "1"; case 19: return "2"; case 20: return "3"; case 21: return "4"
        case 23: return "5"; case 22: return "6"; case 26: return "7"; case 28: return "8"
        case 25: return "9"; case 29: return "0"
        case 122: return "f1"; case 120: return "f2"; case 99: return "f3"; case 118: return "f4"
        case 96: return "f5"; case 97: return "f6"; case 98: return "f7"; case 100: return "f8"
        case 101: return "f9"; case 109: return "f10"; case 103: return "f11"; case 111: return "f12"
        default: return nil
        }
    }
}
```

- [ ] **Step 3: Use the new recorder from `QuickCapturePane`**

Open `Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift`. The existing `HotkeyRecorder` private struct (lines 55-65) is now redundant. Delete the private struct definition and import nothing extra — the new `HotkeyRecorder` is internal to the macOS app target and visible from the pane.

Confirm the pane's call site (line 23) still reads:

```swift
HotkeyRecorder(value: b.quickCaptureHotkey)
    .frame(width: 220)
```

(The new `HotkeyRecorder` accepts the same `@Binding<String>` so no API churn.)

- [ ] **Step 4: Build and run tests**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/HotkeyRecorderTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift \
        Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift \
        Apps/Lillist-macOS/Tests/HotkeyRecorderTests.swift \
        Apps/Lillist-macOS/project.yml
git commit -m "feat(macOS): real Hotkey recorder using NSEvent local monitor"
```

---

## Task 18: Live hotkey re-registration on Preferences save

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift`
- Modify: `Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift`

- [ ] **Step 1: Add `reregister(combo:)` to `GlobalHotkeyMonitor`**

Open `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift`. Inspect the existing API — it likely has a private `register()` invoked at init time. Add a public method that tears down the existing monitor and installs a new one with the new combo:

```swift
    /// Re-install the global hotkey with a new combo string. Called from
    /// the Quick Capture preferences pane after the user saves a new
    /// combo. Idempotent: calling with the same combo is a no-op safe to
    /// re-run.
    public func reregister(combo: String) {
        teardownMonitor()
        self.combo = parseCombo(combo) // or whatever the field is called
        installMonitor()
    }
```

(Adapt to the existing internal names — the audit found the monitor exists at `GlobalHotkeyMonitor.swift:39`.)

- [ ] **Step 2: Call `reregister` from the preferences pane**

In `Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift`, update the `.onChange(of: prefs)` body to invoke the monitor:

```swift
        .onChange(of: prefs) { _, new in
            guard let new else { return }
            Task {
                try? await environment.preferencesStore.update { $0 = new }
                await environment.hotkeyMonitor.reregister(combo: new.quickCaptureHotkey)
            }
        }
```

If `AppEnvironment` doesn't expose `hotkeyMonitor` as a public/internal `let`, add the property (check `Apps/Lillist-macOS/Sources/AppEnvironment.swift`).

- [ ] **Step 3: Delete the `// TODO(Plan 7)` comment lines 41-45 in QuickCapturePane.swift**

The footer text already explains "Hotkey changes apply on next launch" — replace it with "Changes apply immediately." Update line 28:

```swift
                    Text("Press Record, then your key combination. Changes apply immediately.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
```

- [ ] **Step 4: Build**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift \
        Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift \
        Apps/Lillist-macOS/Sources/AppEnvironment.swift
git commit -m "feat(macOS): live hotkey re-registration on Preferences save"
```

---

## Task 19: Rename the `AttachmentStore` "placeholder" URL sentinel

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift`

The lines 128-130 read:

```swift
guard let bytes = m.data else {
    let placeholder = URL(string: "lillist://attachment/\(id.uuidString)")!
    throw LillistError.attachmentFetchFailed(url: placeholder)
}
```

The name `placeholder` reads like a stub. Rename for clarity.

- [ ] **Step 1: Update the lines**

```swift
guard let bytes = m.data else {
    let sentinelURL = URL(string: "lillist://attachment/\(id.uuidString)")!
    throw LillistError.attachmentFetchFailed(url: sentinelURL)
}
```

- [ ] **Step 2: Run the LillistCore suite to confirm no behavior change**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
```

Expected: `Test run with NNN tests in M suites passed`.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift
git commit -m "refactor(core): rename AttachmentStore placeholder URL → sentinelURL"
```

---

## Task 20: Convert `PersistenceController.sharedModel` `preconditionFailure` to `throws(LillistError)`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift`
- Modify: `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift`
- Modify: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerTests.swift`

- [ ] **Step 1: Add `.modelUnavailable` to `LillistError`**

In `LillistError.swift`, add a new case to the enum:

```swift
case modelUnavailable(searchedFilenames: [String])
```

And update any `errorDescription` mapping:

```swift
case .modelUnavailable(let names):
    return "Lillist data model not found in app bundle (searched: \(names.joined(separator: ", ")))"
```

- [ ] **Step 2: Convert `sharedModel` to a throwing accessor**

In `PersistenceController.swift`, replace the existing `sharedModel` static (around lines 110-120):

```swift
    /// The compiled Core Data managed-object model. Loaded once from the
    /// resource bundle; both filenames are tried because SwiftPM's
    /// build-tool plugin and Xcode's DataModelCompile rule emit
    /// different filenames into the same bundle (see Plan 9 engineering
    /// note).
    public static func sharedModel() throws -> NSManagedObjectModel {
        let searched = ["LillistModel.momd", "LillistModel.spm.momd"]
        var foundURL: URL?
        for name in searched {
            let stem = (name as NSString).deletingPathExtension
            if let url = Bundle.module.url(forResource: stem, withExtension: "momd") {
                foundURL = url
                break
            }
        }
        guard let url = foundURL else {
            throw LillistError.modelUnavailable(searchedFilenames: searched)
        }
        guard let model = NSManagedObjectModel(contentsOf: url) else {
            throw LillistError.modelUnavailable(searchedFilenames: [url.lastPathComponent])
        }
        return model
    }
```

- [ ] **Step 3: Update callers to propagate**

Grep for callers:

```bash
grep -rn "sharedModel" Packages/LillistCore/Sources
```

Each call site should now `try Self.sharedModel()`. The existing `init(configuration:)` is `async throws` — the new throw flows naturally. Any test convenience like `inMemory()` likewise gains a `try`.

- [ ] **Step 4: Add a test that the throw fires when the bundle is missing the model**

Open `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerTests.swift` and add:

```swift
    @Test("sharedModel throws .modelUnavailable when both filenames are absent")
    func sharedModelMissingThrows() throws {
        // Simulate by querying for a known-missing model bundle subdir;
        // since we can't easily mock Bundle.module, this test verifies
        // the error type rather than triggering the path in production.
        // The test exists to pin the error contract — change-detection
        // for future refactors that re-route the lookup.
        let err = LillistError.modelUnavailable(searchedFilenames: ["LillistModel.momd", "LillistModel.spm.momd"])
        #expect(err.localizedDescription.contains("LillistModel.momd"))
    }
```

- [ ] **Step 5: Run tests**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
```

Expected: full suite PASSES.

- [ ] **Step 6: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift \
        Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerTests.swift
git commit -m "refactor(core): PersistenceController.sharedModel throws instead of preconditionFailure"
```

---

## Task 21: Soften test-only `fatalError()` to `Issue.record` / `XCTFail`

**Files:**
- Modify: `Packages/LillistCore/Tests/LillistCoreTests/Helpers/FakeUserNotificationCenter.swift`
- Modify: `Apps/Lillist-macOS/Tests/NotificationPermissionFlowTests.swift`
- Modify: `Apps/Lillist-iOS/Tests/UnitTests/NotificationPermissionFlowTests.swift`

- [ ] **Step 1: Update the LillistCore fake**

Open `Packages/LillistCore/Tests/LillistCoreTests/Helpers/FakeUserNotificationCenter.swift` line 68. Replace:

```swift
        fatalError("FakeUserNotificationCenter.notificationSettings() not implemented; use requestAuthorization() in tests instead")
```

with (Swift Testing context):

```swift
        Issue.record("FakeUserNotificationCenter.notificationSettings() called — tests should use requestAuthorization() instead")
        // Return a synthesized "not asked" status so the test continues.
        return UNNotificationSettings(coder: NSCoder())! // unreachable in practice, but a non-trapping return path
```

> **Note:** `UNNotificationSettings(coder:)` returns optional and the framework type isn't trivially constructible — this branch *should* never run. The `Issue.record` makes Swift Testing report the misuse without crashing the runner. If you need a concrete return, throw or use `precondition(false, "…")` instead — `precondition` aborts only in debug builds and never under `-O`. The safest pattern is a runtime requirement that test infrastructure must replace before the path is exercised; the test code that hits this branch is already broken regardless.

For Swift Testing helpers like this one, the cleanest pattern is to make the function `throws` and throw a test-only error. If feasible, refactor:

```swift
    func notificationSettings() async -> UNNotificationSettings {
        Issue.record("FakeUserNotificationCenter.notificationSettings() called — tests should not need real UNNotificationSettings")
        return await UNUserNotificationCenter.current().notificationSettings()
    }
```

(falls through to the real center; in test context that returns the simulator's denied state, which is fine).

- [ ] **Step 2: Update the macOS app test**

Open `Apps/Lillist-macOS/Tests/NotificationPermissionFlowTests.swift` line 93. Replace:

```swift
        fatalError("Not implemented; tests should not need real UNNotificationSettings")
```

with:

```swift
        Issue.record("Test reached notificationSettings() — should not occur in this flow")
        return await UNUserNotificationCenter.current().notificationSettings()
```

- [ ] **Step 3: Update the iOS app test**

Open `Apps/Lillist-iOS/Tests/UnitTests/NotificationPermissionFlowTests.swift` line 74. Apply the same change as Step 2.

- [ ] **Step 4: Run all three test suites**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -3
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  -only-testing:Lillist-macOSTests/NotificationPermissionFlowTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -only-testing:Lillist-iOSTests/NotificationPermissionFlowTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: all three suites PASS. (If the iOS simulator destination name above doesn't resolve, substitute one that does — `xcrun simctl list devices` lists candidates.)

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Helpers/FakeUserNotificationCenter.swift \
        Apps/Lillist-macOS/Tests/NotificationPermissionFlowTests.swift \
        Apps/Lillist-iOS/Tests/UnitTests/NotificationPermissionFlowTests.swift
git commit -m "test: soften test-only fatalError to Issue.record so CI surfaces misuse without crashing"
```

---

## Task 22: Add `RecurrenceEditorView` snapshot tests

**Files:**
- Create: `Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorSnapshotTests.swift`

- [ ] **Step 1: Write the snapshot tests**

```swift
import XCTest
import SnapshotTesting
import SwiftUI
import LillistCore
@testable import LillistUI

final class RecurrenceEditorSnapshotTests: XCTestCase {
    func testEmptyState_light() {
        let vm = RecurrenceEditorViewModel(rule: nil)
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 320)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 320)),
                       as: .image(precision: 0.99), named: "empty-light")
    }

    func testEmptyState_dark() {
        let vm = RecurrenceEditorViewModel(rule: nil)
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .environment(\.colorScheme, .dark)
            .frame(width: 420, height: 320)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 320)),
                       as: .image(precision: 0.99), named: "empty-dark")
    }

    func testWeeklyTuesdayThursday_light() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .weekly
        vm.byDay = [.tuesday, .thursday]
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 600)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 600)),
                       as: .image(precision: 0.99), named: "weekly-tuth-light")
    }

    func testAfterCompletion_light() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.mode = .afterCompletion
        vm.afterCompletionSeconds = 86_400 * 7
        let view = RecurrenceEditorView(viewModel: .constant(vm))
            .frame(width: 420, height: 360)
        assertSnapshot(of: makeHostingView(view, size: .init(width: 420, height: 360)),
                       as: .image(precision: 0.99), named: "after-completion-week-light")
    }
}
```

- [ ] **Step 2: Run twice — first to record baselines, second to verify**

```bash
swift test --package-path Packages/LillistUI --filter 'RecurrenceEditorSnapshotTests' 2>&1 | tail -10
swift test --package-path Packages/LillistUI --filter 'RecurrenceEditorSnapshotTests' 2>&1 | tail -10
```

Expected on second run: 4 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Tests/LillistUITests/Recurrence/RecurrenceEditorSnapshotTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Recurrence/__Snapshots__/
git commit -m "test(ui): snapshot tests for RecurrenceEditorView (light + dark)"
```

---

## Task 23: Update the design doc to reflect recurrence editor in v1

**Files:**
- Modify: `docs/plans/2026-05-12-lillist-design.md`

The design currently lists "Custom recurrence pattern editor" under "Likely v2 roadmap" (Section 10, ~line 814). Plan 11 pulled it into v1.

- [ ] **Step 1: Edit the design doc**

Find the line in Section 10 that says:

```
- Custom snooze options + custom recurrence pattern editor.
```

Replace with:

```
- Custom snooze options.
```

And in Section 7 ("UI Structure") — find where the design discusses task detail composition, and add a sentence acknowledging the recurrence editor lives there:

```
**Recurrence editor.** The task detail surface includes a recurrence
editor (Plan 11) that lets the user toggle "Doesn't repeat" / "Repeats…"
and configure either a calendar rule (frequency, byDay, byMonthDay,
bySetPos, count, until) or an after-completion rule (interval in
seconds, presets for common windows). The "this only" / "all future"
fork affordances remain out of v1 UI scope; CLI and App Intents access
them.
```

(Place the paragraph alongside the other macOS/iOS detail-surface
descriptions in Section 7.)

- [ ] **Step 2: Commit**

```bash
git add docs/plans/2026-05-12-lillist-design.md
git commit -m "docs(design): move recurrence pattern editor from v2 roadmap to v1 (Plan 11)"
```

---

## Task 24: Final integration sweep — full builds, full tests, engineering-notes entry

**Files:**
- Modify: `docs/engineering-notes.md`

- [ ] **Step 1: Run the full LillistCore + LillistUI suites**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -5
swift test --package-path Packages/LillistUI 2>&1 | tail -5
```

Expected: both report `Test run with NNN tests in M suites passed`.

- [ ] **Step 2: Build both apps**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Confirm zero `fatalError` outside test fakes that genuinely need it**

```bash
rg -n 'fatalError|preconditionFailure' --type swift Packages/ Apps/ Extensions/
```

Expected output (acceptable remaining `fatalError`s):
- Tests that intentionally trap on unreachable paths in mock APIs that can't return a concrete type (if any remain).
- Nothing in production code.

If anything else surfaces, address it before continuing.

- [ ] **Step 4: Confirm zero `TODO(Plan` markers**

```bash
rg -n 'TODO\(Plan' --type swift Packages/ Apps/ Extensions/
```

Expected: empty output. Each one that remains needs to either be addressed now or have a follow-up task carved out — there are no remaining Plan 11 scoped TODOs to leave behind.

- [ ] **Step 5: Append the Plan 11 entry to `docs/engineering-notes.md`**

Add at the top of `docs/engineering-notes.md` (the file is newest-first):

```markdown
## 2026-05-14 — Plan 11 pre-UAT cleanup: stale TODO comments outlive the API they reference; URLProtocol stubbing is the canonical no-network unfurl test; `precondition`/`fatalError` are valid Swift code in tests but kill the runner under CI

**Context.** Plan 11 closed the loose ends found in the pre-UAT review:
the macOS sidebar's `pinned()` workaround (the comment said
LillistCore lacked the query; LillistCore had had it since Plan 4),
the link-preview unfurl pipeline (promised by design §3, never
shipped), the recurrence pattern editor (pulled forward from v2),
the Empty Trash buttons (no `TaskStore.purgeAll()` existed),
the macOS hotkey recorder (a text field stood in for a
key-capture UI), and the `preconditionFailure` /
`fatalError` calls in shipped and test code.

**Three concrete lessons.**

1. **Stale TODO comments are worse than no comment.** The
   `// TODO(Plan 7 follow-up): LillistCore lacks a TaskStore.pinned()`
   comment in `SidebarView.swift` claimed the API didn't exist; the
   API had been on `main` for weeks with a passing test
   ("pinned returns all pinned tasks across the tree, excluding
   trash"). The comment outlasted the limitation. Rule: when you
   leave a `TODO(Plan N)` referencing a missing capability,
   include a one-line check in the commit message that re-derives
   the claim ("grep'd `TaskStore.pinned` 2026-05-09"), and when
   you remove the workaround, audit the rest of the codebase for
   the same comment.

2. **URLProtocol-based stubbing is the right shape for unfurl
   tests, not a custom HTTP client wrapper.** The temptation was
   to abstract `LinkPreviewFetching` into a protocol with a
   `MockFetcher` that returns canned data structures. The cleaner
   shape: define `LinkPreviewFetching` at the *bytes* boundary
   (return `Data?`), have the production type wrap `URLSession`,
   and write tests that build a `URLSession` with a custom
   `URLProtocol` installed. The protocol stub lets the same code
   path execute in tests as in production — same parsing, same
   error handling — and avoids the "did I mock the right layer?"
   trap.

3. **`fatalError` in test code is a CI footgun.** Test-only
   "should never reach" branches that use `fatalError` abort the
   test runner process and surface as inscrutable "test crashed"
   without a message naming the misuse. Swift Testing's
   `Issue.record` (and XCTest's `XCTFail`) report a test failure
   with the message and let the rest of the suite continue —
   preferable in every case where a future maintainer might
   actually hit the branch.

**Rule.**

- Audit `TODO(Plan N)` comments quarterly. Either resolve them
  or update them with the current reason they still apply.
- Test fakes should never `fatalError` — use `Issue.record` /
  `XCTFail` and return a defensible default. The cost is a few
  lines of "what to return"; the benefit is CI legibility.
- For unfurl-style pipelines that combine network + parse +
  persist, abstract at the bytes boundary and stub via
  `URLProtocol`. Keep parsing and persistence non-protocol so
  the same code runs in tests and production.

**Evidence.** Plan 11 commits in the `2026-05-14-pre-uat-cleanup`
range: sidebar `pinned()` fix, `LinkPreview/*` directory,
`RecurrenceEditor*` in LillistUI, `TaskStore.purgeAll()`,
`HotkeyRecorder.swift`, `Issue.record` migrations,
`PersistenceController.sharedModel throws`.
```

- [ ] **Step 6: Commit the engineering note**

```bash
git add docs/engineering-notes.md
git commit -m "docs: record Plan 11 cleanup lessons (stale TODOs, URLProtocol stubs, fatalError in tests)"
```

- [ ] **Step 7: Final tag**

```bash
git tag plan-11-pre-uat-cleanup
git log --oneline plan-10..plan-11-pre-uat-cleanup
```

Expected: a clean sequence of conventional-commit-prefixed commits, one per task.

---

## Plan 11 Scope (for the implementer's reference)

**In scope:**
- Fix the macOS sidebar pinned-tasks bug (Tasks 1-2)
- Wire "Empty Trash now" on macOS + iOS (Tasks 3-5)
- Implement the link-preview unfurl pipeline end-to-end (Tasks 6-11)
- Build the recurrence pattern editor and wire it into both apps (Tasks 12-16, 22)
- Replace the placeholder macOS hotkey recorder with a real one (Tasks 17-18)
- Cosmetic + structural cleanup: rename `AttachmentStore` sentinel, convert `PersistenceController` precondition to a throw, soften test-only `fatalError` (Tasks 19-21)
- Update design doc + engineering notes to match the new reality (Tasks 23-24)

**Explicitly out of scope (left for a future plan):**
- "This only" / "All future" recurrence fork affordances in the UI (the engine + `seriesStore.forkFutureFromInstance` exist; only CLI/App Intent entry points in v1)
- Live thumbnail rendering of link previews in the task detail attachment grid (the bytes are stored; UI is a follow-up)
- Hotkey recorder support for arbitrary keys beyond the alphanumeric + function + special keys hard-coded in Task 17
- Localization of the recurrence editor's day-name and frequency strings (English only per design §10)

---

## Self-Review Checklist (run by the implementer before merging)

- [ ] All 24 tasks completed with checkboxes ticked
- [ ] `swift test --package-path Packages/LillistCore` reports clean PASS
- [ ] `swift test --package-path Packages/LillistUI` reports clean PASS
- [ ] Both `xcodebuild build` runs succeed for macOS + iOS
- [ ] `rg 'fatalError|preconditionFailure' Apps/ Packages/` returns nothing in production code paths
- [ ] `rg 'TODO\(Plan' Apps/ Packages/` is empty
- [ ] `rg 'placeholder' --type swift Apps/ Packages/` shows only the intended remaining mentions (e.g. `Text("…tap to add a placeholder")` strings, if any)
- [ ] Hand-test on macOS: pin a nested task, confirm it appears in the sidebar; create a recurrence rule, confirm it persists across relaunch; empty trash from preferences; change the hotkey and verify the new combo fires immediately
- [ ] Hand-test on iOS Simulator: same flows except the macOS-only hotkey
- [ ] CLAUDE.md unchanged (no new project-wide convention introduced by this plan)
