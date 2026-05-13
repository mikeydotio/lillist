# Lillist Plan 5 — Notifications, Snooze, and Nudges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the full notifications layer in `LillistCore` per design **Section 4 (Notifications, Snooze, and Nudges)** — a CloudKit-compatible `NotificationSpec` entity, a protocol-wrapped `NotificationScheduler` actor that reconciles desired vs. pending `UNUserNotificationCenter` requests on every relevant task mutation, the four delivery layers (time-bearing dates, all-day defaults, per-task offsets, morning summary), the extensible snooze registry, the nudge API, the blocked-status follow-up affordance on `TaskStore`, and a `NotificationPermissions` actor that requests/queries authorization with graceful degradation.

**Architecture:** A new `Notifications/` source folder inside the `LillistCore` SPM target. Public API surface:

- `NotificationKind` (typed enum over `kindRaw`)
- `NotificationSpec` (Core Data managed object — fifth entity-level addition to the model, joining `LillistTask`/`Tag`/`JournalEntry`/`Attachment`/`AppPreferences`)
- `NotificationSpecStore` (CRUD over specs)
- `UNUserNotificationCenterProtocol` (testability seam wrapping `UNUserNotificationCenter`'s scheduling surface)
- `NotificationScheduler` (actor; owns reconcile/diff/dispatch)
- `NotificationCategoryFactory` (builds `UNNotificationCategory` set from registered snooze actions)
- `SnoozeAction` (value type)
- `SnoozeRegistry` (actor; defaults registered at init)
- `NotificationPermissions` (actor)
- `TaskStore.scheduleFollowUp(...)` (extension method)

Reconciliation is **idempotent and diff-based**: compute the desired set of `UNNotificationRequest`s from `NotificationSpec` rows + task fields, fetch the pending set from the center, add what's missing, remove what's stale. Identifiers follow `"\(specID)#\(deviceFingerprint)"` for cross-device de-dup; on firing, `lastFiredAt` is written via CloudKit so other devices remove the matching pending request before they fire locally.

**Tech Stack:** Swift 6, Swift Package Manager, Core Data (the CloudKit-mirrored container from Plan 2 — this plan does not depend on that being enabled; it works against Plan 1's `NSPersistentContainer` and assumes Plan 2's swap is a no-op for callers), `UserNotifications` framework, Swift Testing. No third-party dependencies.

---

## File Structure

```
Packages/LillistCore/
├── Sources/
│   └── LillistCore/
│       ├── Model/
│       │   ├── NotificationKind.swift                       (NEW)
│       │   └── LillistModel.xcdatamodeld/...                (MODIFIED — add NotificationSpec entity + inverse on LillistTask)
│       ├── ManagedObjects/
│       │   └── NotificationSpec+CoreData.swift              (NEW — typed kind accessor)
│       ├── Notifications/                                   (NEW folder)
│       │   ├── DeviceFingerprint.swift                      (per-device stable id)
│       │   ├── UNUserNotificationCenterProtocol.swift       (testability seam)
│       │   ├── NotificationSpecStore.swift                  (CRUD over specs)
│       │   ├── SnoozeAction.swift                           (value type)
│       │   ├── SnoozeRegistry.swift                         (actor)
│       │   ├── NotificationCategoryFactory.swift            (kind × snooze → categories)
│       │   ├── NotificationPermissions.swift                (actor)
│       │   ├── NotificationScheduler.swift                  (actor — reconcile/diff/dispatch)
│       │   └── MorningSummaryRequestID.swift                (well-known constants)
│       └── Stores/
│           └── TaskStore+FollowUp.swift                     (NEW — scheduleFollowUp extension)
└── Tests/
    └── LillistCoreTests/
        ├── Helpers/
        │   └── FakeUserNotificationCenter.swift             (recorder fake)
        └── Notifications/
            ├── NotificationKindTests.swift
            ├── NotificationSpecStoreTests.swift
            ├── SnoozeActionTests.swift
            ├── SnoozeRegistryTests.swift
            ├── NotificationCategoryFactoryTests.swift
            ├── NotificationPermissionsTests.swift
            ├── NotificationSchedulerLayer1TimeBearingTests.swift
            ├── NotificationSchedulerLayer2AllDayTests.swift
            ├── NotificationSchedulerLayer3OffsetTests.swift
            ├── NotificationSchedulerLayer4MorningSummaryTests.swift
            ├── NotificationSchedulerNudgeTests.swift
            ├── NotificationSchedulerSnoozeTests.swift
            ├── NotificationSchedulerStatusTransitionsTests.swift
            ├── NotificationSchedulerCrossDeviceDedupTests.swift
            ├── NotificationSchedulerDSTTests.swift
            ├── NotificationSchedulerPreferenceChangeTests.swift
            └── TaskStoreFollowUpTests.swift
```

---

## Notes for the Implementer

**TDD discipline (same as Plan 1).** Every functional task follows red → green → refactor → commit. Write the test first, run it, watch it fail, write minimal code, watch it pass, commit. Don't write code without a failing test.

**CloudKit-compatible schema (same as Plan 1).** Every new attribute on `NotificationSpec` is optional at the schema level; required-ness is enforced in `NotificationSpecStore`. The `task` relationship has an inverse (`LillistTask.notificationSpecs`) and uses `Cascade` deletion from task to spec, `Nullify` on the reverse. No `Deny` rules.

**Concurrency.** All public-facing types either run on `viewContext.perform` (the stores) or are actors (`NotificationScheduler`, `SnoozeRegistry`, `NotificationPermissions`). `SnoozeAction.compute` is a `@Sendable` closure. `UNUserNotificationCenter` itself is not `Sendable`-checked in current SDKs — the protocol wrapper crosses the actor boundary as `any UNUserNotificationCenterProtocol` and the production impl is a thin `final class` that synchronizes via the underlying framework's own concurrency model. We do not allow `UNUserNotificationCenter` instances to escape into stored properties on Sendable types except through the protocol.

**Reconciliation contract.** `NotificationScheduler.reconcile(taskID:)` is the single entry point. Every code path that affects scheduling (`TaskStore.update`, `TaskStore.transition`, `TaskStore.softDelete`, `TaskStore.restore`, `NotificationSpecStore.add/update/delete`, recurrence spawn from Plan 4, snooze handler) calls `reconcile(taskID:)` after its own `save`. Reconciliation is *idempotent* — calling it twice with no underlying change leaves the pending set untouched.

**Wall-clock vs interval triggers.** Layers 1 and 2 use `UNCalendarNotificationTrigger` (DST-safe per design Section 8). Layers 3 and 5 (offsets and nudges) use `UNCalendarNotificationTrigger` against an absolute date computed once. Layer 4 (morning summary) uses a repeating `UNCalendarNotificationTrigger` keyed only on hour+minute.

**Blocked tasks are NOT suppressed** (design Section 4: "Status transitions are notification-aware → Blocked: notifications NOT suppressed"). The follow-up affordance is an *additional* mechanism, not a replacement.

**Commits.** Each task ends in a commit. Use conventional-commit prefixes: `feat:`, `test:`, `chore:`, `fix:`, `refactor:`.

**Verification command throughout:** `cd Packages/LillistCore && swift test`.

---

## Task 1: Add `NotificationSpec` entity to the Core Data model

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`

This adds the fifth+sixth pieces to the model: the `NotificationSpec` entity itself, and a new `notificationSpecs` inverse relationship on `LillistTask`. All attributes optional, no `Deny` rules, inverse always set — same CloudKit constraints Plan 1 followed.

- [ ] **Step 1: Open the model contents file and add the `notificationSpecs` relationship to `LillistTask`**

Find the `<entity name="LillistTask" ...>` block. Immediately before its closing `</entity>` tag, add:

```xml
        <relationship name="notificationSpecs" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="NotificationSpec" inverseName="task" inverseEntity="NotificationSpec"/>
```

- [ ] **Step 2: Append the new entity after the `AppPreferences` entity**

In `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`, immediately before the closing `</model>` tag, insert:

```xml
    <entity name="NotificationSpec" representedClassName="NotificationSpec" syncable="YES">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="kindRaw" optional="YES" attributeType="Integer 16" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="offsetMinutes" optional="YES" attributeType="Integer 32" usesScalarValueType="NO"/>
        <attribute name="fireDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="lastFiredAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="snoozedUntil" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="createdAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <relationship name="task" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="LillistTask" inverseName="notificationSpecs" inverseEntity="LillistTask"/>
    </entity>
```

- [ ] **Step 3: Build and run the full existing test suite to confirm the model still loads**

Run: `cd Packages/LillistCore && swift test`
Expected: all previously-passing tests still pass; no new tests yet.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/
git commit -m "feat: add NotificationSpec entity to Core Data model"
```

---

## Task 2: Define `NotificationKind` enum

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationKindTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationKindTests.swift`:

```swift
import Testing
@testable import LillistCore

@Suite("NotificationKind")
struct NotificationKindTests {
    @Test("Raw values are stable for persistence")
    func rawValuesStable() {
        #expect(NotificationKind.defaultStart.rawValue == 0)
        #expect(NotificationKind.defaultDeadline.rawValue == 1)
        #expect(NotificationKind.offsetStart.rawValue == 2)
        #expect(NotificationKind.offsetDeadline.rawValue == 3)
        #expect(NotificationKind.nudge.rawValue == 4)
    }

    @Test("All cases enumerable")
    func allCases() {
        #expect(NotificationKind.allCases.count == 5)
    }

    @Test("Anchor classifies kinds by their anchor field")
    func anchor() {
        #expect(NotificationKind.defaultStart.anchor == .start)
        #expect(NotificationKind.offsetStart.anchor == .start)
        #expect(NotificationKind.defaultDeadline.anchor == .deadline)
        #expect(NotificationKind.offsetDeadline.anchor == .deadline)
        #expect(NotificationKind.nudge.anchor == nil)
    }

    @Test("isOffset distinguishes the offset variants")
    func isOffset() {
        #expect(NotificationKind.offsetStart.isOffset == true)
        #expect(NotificationKind.offsetDeadline.isOffset == true)
        #expect(NotificationKind.defaultStart.isOffset == false)
        #expect(NotificationKind.defaultDeadline.isOffset == false)
        #expect(NotificationKind.nudge.isOffset == false)
    }

    @Test("Round-trip through Int16")
    func int16RoundTrip() {
        for kind in NotificationKind.allCases {
            let int16 = Int16(kind.rawValue)
            #expect(NotificationKind(rawValue: Int(int16)) == kind)
        }
    }
}
```

- [ ] **Step 2: Run tests to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter NotificationKindTests`
Expected: FAIL — `NotificationKind` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift`:

```swift
import Foundation

/// Kinds of `NotificationSpec`, matching the four-layer delivery model in
/// design Section 4.
///
/// Raw values are persisted; never reorder or remove cases. New kinds must
/// take an unused raw value. Stored in Core Data as `Int16`.
public enum NotificationKind: Int, CaseIterable, Codable, Sendable {
    /// Layer 1/2 auto-spec keyed off `LillistTask.start`.
    case defaultStart = 0
    /// Layer 1/2 auto-spec keyed off `LillistTask.deadline`.
    case defaultDeadline = 1
    /// Layer 3 user-added offset relative to `start`.
    case offsetStart = 2
    /// Layer 3 user-added offset relative to `deadline`.
    case offsetDeadline = 3
    /// Independent absolute-date nudge.
    case nudge = 4

    /// Which task field this kind is anchored to, or `nil` for nudges (which
    /// carry their own absolute `fireDate`).
    public enum Anchor: Sendable {
        case start
        case deadline
    }

    public var anchor: Anchor? {
        switch self {
        case .defaultStart, .offsetStart: return .start
        case .defaultDeadline, .offsetDeadline: return .deadline
        case .nudge: return nil
        }
    }

    public var isOffset: Bool {
        self == .offsetStart || self == .offsetDeadline
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationKindTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationKindTests.swift
git commit -m "feat: add NotificationKind enum with anchor classification"
```

---

## Task 3: Typed accessors on `NotificationSpec` managed object

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/ManagedObjects/NotificationSpec+CoreData.swift`

Mirrors the pattern from Plan 1 Task 8 — bridge `kindRaw: Int16` to `NotificationKind`.

- [ ] **Step 1: Write the extension**

Write `Packages/LillistCore/Sources/LillistCore/ManagedObjects/NotificationSpec+CoreData.swift`:

```swift
import Foundation
import CoreData

extension NotificationSpec {
    /// Typed accessor over `kindRaw`.
    public var kind: NotificationKind {
        get { NotificationKind(rawValue: Int(kindRaw)) ?? .defaultStart }
        set { kindRaw = Int16(newValue.rawValue) }
    }
}
```

- [ ] **Step 2: Build to confirm no compile errors**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/ManagedObjects/NotificationSpec+CoreData.swift
git commit -m "feat: add typed kind accessor on NotificationSpec"
```

---

## Task 4: `DeviceFingerprint` — stable per-device identifier

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Notifications/DeviceFingerprint.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/DeviceFingerprintTests.swift`

Used in notification request identifiers (`"\(specID)#\(deviceFingerprint)"`) for cross-device de-dup per design Section 4. Stored once in `UserDefaults` so the same device always emits the same fingerprint; not synced.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/DeviceFingerprintTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("DeviceFingerprint")
struct DeviceFingerprintTests {
    @Test("First read generates and persists a value")
    func generatesAndPersists() {
        let defaults = UserDefaults(suiteName: "test.devicefp.\(UUID().uuidString)")!
        let fp1 = DeviceFingerprint.current(defaults: defaults)
        let fp2 = DeviceFingerprint.current(defaults: defaults)
        #expect(fp1.isEmpty == false)
        #expect(fp1 == fp2)
    }

    @Test("Different defaults containers produce different fingerprints")
    func differentContainers() {
        let a = UserDefaults(suiteName: "test.devicefp.\(UUID().uuidString)")!
        let b = UserDefaults(suiteName: "test.devicefp.\(UUID().uuidString)")!
        let fpA = DeviceFingerprint.current(defaults: a)
        let fpB = DeviceFingerprint.current(defaults: b)
        #expect(fpA != fpB)
    }

    @Test("Fingerprint is URL-safe (no #, no spaces)")
    func urlSafe() {
        let defaults = UserDefaults(suiteName: "test.devicefp.\(UUID().uuidString)")!
        let fp = DeviceFingerprint.current(defaults: defaults)
        #expect(fp.contains("#") == false)
        #expect(fp.contains(" ") == false)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter DeviceFingerprintTests`
Expected: FAIL — `DeviceFingerprint` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Notifications/DeviceFingerprint.swift`:

```swift
import Foundation

/// A stable per-device identifier used to disambiguate notification
/// request identifiers across devices (design Section 4 cross-device
/// de-duplication: identifiers are `"\(specID)#\(deviceFingerprint)"`).
///
/// Stored in `UserDefaults` so each device's fingerprint persists across
/// launches. NOT synced via CloudKit — that's the point.
public enum DeviceFingerprint {
    static let userDefaultsKey = "com.mikeydotio.lillist.deviceFingerprint"

    /// Returns the fingerprint, generating and persisting a new one on first call.
    public static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: userDefaultsKey), existing.isEmpty == false {
            return existing
        }
        let fresh = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(fresh, forKey: userDefaultsKey)
        return fresh
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter DeviceFingerprintTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/DeviceFingerprint.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/DeviceFingerprintTests.swift
git commit -m "feat: add DeviceFingerprint for cross-device notification de-dup"
```

---

## Task 5: `UNUserNotificationCenterProtocol` + `FakeUserNotificationCenter`

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Helpers/FakeUserNotificationCenter.swift`

This is the testability seam. The real `UNUserNotificationCenter` cannot be instantiated outside an app process and cannot be inspected synchronously in tests. The protocol abstracts the four operations the scheduler actually needs: add, getPending, removePending(identifiers), setNotificationCategories.

- [ ] **Step 1: Write the protocol**

Write `Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift`:

```swift
import Foundation
import UserNotifications

/// The slice of `UNUserNotificationCenter`'s API the `NotificationScheduler`
/// depends on. Wrapped in a protocol so tests can substitute a recording fake.
public protocol UNUserNotificationCenterProtocol: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func notificationSettings() async -> UNNotificationSettings
}

/// Production adapter wrapping the real center.
public final class SystemUserNotificationCenter: UNUserNotificationCenterProtocol, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async {
        center.setNotificationCategories(categories)
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func notificationSettings() async -> UNNotificationSettings {
        await center.notificationSettings()
    }
}
```

- [ ] **Step 2: Write the recording fake**

Write `Packages/LillistCore/Tests/LillistCoreTests/Helpers/FakeUserNotificationCenter.swift`:

```swift
import Foundation
import UserNotifications
@testable import LillistCore

/// Test double that records added requests, supports removal by identifier,
/// and exposes the most recent category set. Authorization is controllable
/// per-instance.
actor FakeUserNotificationCenter: UNUserNotificationCenterProtocol {
    private(set) var added: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []
    private(set) var categories: Set<UNNotificationCategory> = []
    private(set) var authorizationGranted: Bool = true
    private(set) var requestAuthorizationCallCount = 0

    func setAuthorizationGranted(_ granted: Bool) {
        self.authorizationGranted = granted
    }

    nonisolated func add(_ request: UNNotificationRequest) async throws {
        await self._add(request)
    }

    private func _add(_ request: UNNotificationRequest) {
        added.append(request)
    }

    nonisolated func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await self._pending()
    }

    private func _pending() -> [UNNotificationRequest] { added }

    nonisolated func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        await self._remove(identifiers)
    }

    private func _remove(_ identifiers: [String]) {
        removedIdentifiers.append(identifiers)
        let set = Set(identifiers)
        added.removeAll { set.contains($0.identifier) }
    }

    nonisolated func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async {
        await self._setCategories(categories)
    }

    private func _setCategories(_ c: Set<UNNotificationCategory>) {
        self.categories = c
    }

    nonisolated func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        await self._incRequestAuth()
        return await self.authorizationGranted
    }

    private func _incRequestAuth() {
        requestAuthorizationCallCount += 1
    }

    nonisolated func notificationSettings() async -> UNNotificationSettings {
        // We can't easily construct UNNotificationSettings from outside the
        // framework; tests that need to inspect settings should use
        // requestAuthorization() instead. Trap if called from a test path.
        fatalError("FakeUserNotificationCenter.notificationSettings() not implemented; use requestAuthorization() in tests instead")
    }

    func reset() {
        added.removeAll()
        removedIdentifiers.removeAll()
        categories.removeAll()
        requestAuthorizationCallCount = 0
    }
}
```

- [ ] **Step 3: Build to confirm compile**

Run: `cd Packages/LillistCore && swift build && swift test --filter SmokeTests`
Expected: build succeeds, smoke tests still pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/UNUserNotificationCenterProtocol.swift Packages/LillistCore/Tests/LillistCoreTests/Helpers/FakeUserNotificationCenter.swift
git commit -m "feat: add UNUserNotificationCenterProtocol with system + fake adapters"
```

---

## Task 6: `NotificationSpecStore` — CRUD over specs

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSpecStoreTests.swift`

Pure persistence — no scheduling side effects. The `NotificationScheduler` is what reacts to changes; the store is just persistence.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSpecStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("NotificationSpecStore")
struct NotificationSpecStoreTests {
    @Test("add creates a spec with the given fields")
    func add() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        let id = try await specs.add(taskID: taskID, kind: .offsetStart, offsetMinutes: -15, fireDate: nil)
        let record = try await specs.fetch(id: id)
        #expect(record.kind == .offsetStart)
        #expect(record.offsetMinutes == -15)
        #expect(record.taskID == taskID)
    }

    @Test("specs(forTask:) returns all specs for a task, sorted by createdAt")
    func specsForTask() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        _ = try await specs.add(taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)
        _ = try await specs.add(taskID: taskID, kind: .offsetStart, offsetMinutes: -30, fireDate: nil)
        let all = try await specs.specs(forTask: taskID)
        #expect(all.count == 2)
    }

    @Test("update mutates fields and only saves on commit")
    func update() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let id = try await specs.add(taskID: taskID, kind: .nudge, offsetMinutes: nil, fireDate: Date(timeIntervalSince1970: 1_000_000))

        let newDate = Date(timeIntervalSince1970: 2_000_000)
        try await specs.update(id: id) { draft in
            draft.fireDate = newDate
            draft.snoozedUntil = Date(timeIntervalSince1970: 3_000_000)
        }
        let record = try await specs.fetch(id: id)
        #expect(record.fireDate == newDate)
        #expect(record.snoozedUntil == Date(timeIntervalSince1970: 3_000_000))
    }

    @Test("delete removes the spec")
    func delete() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let id = try await specs.add(taskID: taskID, kind: .nudge, offsetMinutes: nil, fireDate: Date())
        try await specs.delete(id: id)
        await #expect(throws: LillistError.self) {
            _ = try await specs.fetch(id: id)
        }
    }

    @Test("Deleting a task cascades to its specs")
    func cascadeDelete() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .nudge, offsetMinutes: nil, fireDate: Date())
        try await tasks.hardDelete(id: taskID)
        await #expect(throws: LillistError.self) {
            _ = try await specs.fetch(id: specID)
        }
    }

    @Test("recordLastFired writes lastFiredAt")
    func recordLastFired() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let id = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)
        let at = Date(timeIntervalSince1970: 5_000_000)
        try await specs.recordLastFired(id: id, at: at)
        let record = try await specs.fetch(id: id)
        #expect(record.lastFiredAt == at)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter NotificationSpecStoreTests`
Expected: FAIL — `NotificationSpecStore` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift`:

```swift
import Foundation
import CoreData

public final class NotificationSpecStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public struct SpecRecord: Sendable, Equatable {
        public var id: UUID
        public var taskID: UUID
        public var kind: NotificationKind
        public var offsetMinutes: Int32?
        public var fireDate: Date?
        public var lastFiredAt: Date?
        public var snoozedUntil: Date?
        public var createdAt: Date?
    }

    public struct SpecDraft {
        public var kind: NotificationKind
        public var offsetMinutes: Int32?
        public var fireDate: Date?
        public var snoozedUntil: Date?
    }

    @discardableResult
    public func add(
        taskID: UUID,
        kind: NotificationKind,
        offsetMinutes: Int32?,
        fireDate: Date?
    ) async throws -> UUID {
        try await context.perform { [self] in
            let task = try fetchTask(id: taskID, in: context)
            let spec = NotificationSpec(context: context)
            let id = UUID()
            spec.id = id
            spec.task = task
            spec.kind = kind
            if let offsetMinutes {
                spec.offsetMinutes = NSNumber(value: offsetMinutes)
            } else {
                spec.offsetMinutes = nil
            }
            spec.fireDate = fireDate
            spec.createdAt = Date()
            try context.save()
            return id
        }
    }

    public func fetch(id: UUID) async throws -> SpecRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return Self.record(from: m)
        }
    }

    public func specs(forTask taskID: UUID) async throws -> [SpecRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "task.id == %@", taskID as CVarArg)
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(req).map(Self.record(from:))
        }
    }

    public func update(id: UUID, _ block: @escaping (inout SpecDraft) -> Void) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            var draft = SpecDraft(
                kind: m.kind,
                offsetMinutes: m.offsetMinutes?.int32Value,
                fireDate: m.fireDate,
                snoozedUntil: m.snoozedUntil
            )
            block(&draft)
            m.kind = draft.kind
            if let offset = draft.offsetMinutes {
                m.offsetMinutes = NSNumber(value: offset)
            } else {
                m.offsetMinutes = nil
            }
            m.fireDate = draft.fireDate
            m.snoozedUntil = draft.snoozedUntil
            try context.save()
        }
    }

    public func delete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            context.delete(m)
            try context.save()
        }
    }

    public func recordLastFired(id: UUID, at date: Date) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            m.lastFiredAt = date
            try context.save()
        }
    }

    // MARK: - Helpers

    private func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> NotificationSpec {
        let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
        return m
    }

    private func fetchTask(id: UUID, in ctx: NSManagedObjectContext) throws -> LillistTask {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
        return m
    }

    static func record(from m: NotificationSpec) -> SpecRecord {
        SpecRecord(
            id: m.id ?? UUID(),
            taskID: m.task?.id ?? UUID(),
            kind: m.kind,
            offsetMinutes: m.offsetMinutes?.int32Value,
            fireDate: m.fireDate,
            lastFiredAt: m.lastFiredAt,
            snoozedUntil: m.snoozedUntil,
            createdAt: m.createdAt
        )
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationSpecStoreTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSpecStoreTests.swift
git commit -m "feat: add NotificationSpecStore with CRUD and lastFiredAt recording"
```

---

## Task 7: `SnoozeAction` value type

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeAction.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/SnoozeActionTests.swift`

Per design Section 4: `SnoozeAction = {id, displayName, compute: (NotificationSpec, deliveredAt) -> Date}`. Value type, `Sendable`. The `compute` closure takes the *spec record* (not the managed object) so it stays Sendable across the actor boundary.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/SnoozeActionTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("SnoozeAction")
struct SnoozeActionTests {
    @Test("tenMinutes adds 10 minutes to delivery time")
    func tenMinutes() {
        let action = SnoozeAction.tenMinutes
        let delivered = Date(timeIntervalSince1970: 1_000_000)
        let spec = NotificationSpecStore.SpecRecord(
            id: UUID(), taskID: UUID(), kind: .defaultStart,
            offsetMinutes: nil, fireDate: nil, lastFiredAt: nil,
            snoozedUntil: nil, createdAt: nil
        )
        let result = action.compute(spec, delivered)
        #expect(result.timeIntervalSince(delivered) == 600)
    }

    @Test("oneHour adds 3600 seconds to delivery time")
    func oneHour() {
        let action = SnoozeAction.oneHour
        let delivered = Date(timeIntervalSince1970: 1_000_000)
        let spec = NotificationSpecStore.SpecRecord(
            id: UUID(), taskID: UUID(), kind: .defaultStart,
            offsetMinutes: nil, fireDate: nil, lastFiredAt: nil,
            snoozedUntil: nil, createdAt: nil
        )
        let result = action.compute(spec, delivered)
        #expect(result.timeIntervalSince(delivered) == 3600)
    }

    @Test("tomorrowMorning targets the next day at the given default hour:minute")
    func tomorrowMorning() {
        // Use Pacific time for a deterministic check.
        let cal = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = 22
        components.minute = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let delivered = cal.date(from: components)!

        let action = SnoozeAction.tomorrowMorning(hour: 9, minute: 0, timeZone: TimeZone(identifier: "UTC")!)
        let spec = NotificationSpecStore.SpecRecord(
            id: UUID(), taskID: UUID(), kind: .defaultStart,
            offsetMinutes: nil, fireDate: nil, lastFiredAt: nil,
            snoozedUntil: nil, createdAt: nil
        )
        let result = action.compute(spec, delivered)

        var resultCal = Calendar(identifier: .gregorian)
        resultCal.timeZone = TimeZone(identifier: "UTC")!
        let resultComponents = resultCal.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        #expect(resultComponents.year == 2026)
        #expect(resultComponents.month == 1)
        #expect(resultComponents.day == 16)
        #expect(resultComponents.hour == 9)
        #expect(resultComponents.minute == 0)
    }

    @Test("Action identity for category serialization")
    func identity() {
        #expect(SnoozeAction.tenMinutes.id == "snooze.10m")
        #expect(SnoozeAction.oneHour.id == "snooze.1h")
        #expect(SnoozeAction.tomorrowMorning(hour: 9, minute: 0, timeZone: .current).id == "snooze.tomorrow")
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter SnoozeActionTests`
Expected: FAIL — `SnoozeAction` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeAction.swift`:

```swift
import Foundation

/// A user-facing snooze choice. Value type so the registry stays Sendable.
///
/// Design Section 4: "`SnoozeAction` value type: `{id, displayName,
/// compute: (NotificationSpec, deliveredAt) -> Date}`."
public struct SnoozeAction: Sendable {
    public typealias Compute = @Sendable (NotificationSpecStore.SpecRecord, Date) -> Date

    public let id: String
    public let displayName: String
    public let compute: Compute

    public init(id: String, displayName: String, compute: @escaping Compute) {
        self.id = id
        self.displayName = displayName
        self.compute = compute
    }
}

extension SnoozeAction {
    /// Ten-minute snooze (relative to delivery time).
    public static let tenMinutes = SnoozeAction(
        id: "snooze.10m",
        displayName: "Snooze 10 min"
    ) { _, deliveredAt in
        deliveredAt.addingTimeInterval(600)
    }

    /// One-hour snooze (relative to delivery time).
    public static let oneHour = SnoozeAction(
        id: "snooze.1h",
        displayName: "Snooze 1 hour"
    ) { _, deliveredAt in
        deliveredAt.addingTimeInterval(3600)
    }

    /// Snooze until the next morning at the user's default all-day notification time.
    /// Used by `SnoozeRegistry` with `AppPreferences.defaultAllDayHour/Minute`.
    public static func tomorrowMorning(hour: Int, minute: Int, timeZone: TimeZone) -> SnoozeAction {
        SnoozeAction(
            id: "snooze.tomorrow",
            displayName: "Snooze until tomorrow morning"
        ) { _, deliveredAt in
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            let tomorrow = cal.date(byAdding: .day, value: 1, to: deliveredAt) ?? deliveredAt
            var components = cal.dateComponents([.year, .month, .day], from: tomorrow)
            components.hour = hour
            components.minute = minute
            components.second = 0
            return cal.date(from: components) ?? deliveredAt
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter SnoozeActionTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeAction.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/SnoozeActionTests.swift
git commit -m "feat: add SnoozeAction value type with tenMinutes/oneHour/tomorrowMorning defaults"
```

---

## Task 8: `SnoozeRegistry` actor

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeRegistry.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/SnoozeRegistryTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/SnoozeRegistryTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("SnoozeRegistry")
struct SnoozeRegistryTests {
    @Test("Default registry contains tenMinutes, oneHour, tomorrowMorning")
    func defaults() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let ids = await registry.actions.map(\.id)
        #expect(ids.contains("snooze.10m"))
        #expect(ids.contains("snooze.1h"))
        #expect(ids.contains("snooze.tomorrow"))
        #expect(ids.count == 3)
    }

    @Test("register appends a custom action")
    func registerCustom() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let custom = SnoozeAction(id: "snooze.custom", displayName: "Custom") { _, d in d }
        await registry.register(custom)
        let ids = await registry.actions.map(\.id)
        #expect(ids.contains("snooze.custom"))
        #expect(ids.count == 4)
    }

    @Test("register replaces an action with the same id")
    func registerReplaces() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let replacement = SnoozeAction(id: "snooze.10m", displayName: "Custom 10m") { _, d in d }
        await registry.register(replacement)
        let actions = await registry.actions
        let tenMinAction = actions.first { $0.id == "snooze.10m" }
        #expect(tenMinAction?.displayName == "Custom 10m")
        #expect(actions.count == 3)
    }

    @Test("action(id:) looks up a registered action")
    func lookupByID() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let action = await registry.action(id: "snooze.10m")
        #expect(action?.id == "snooze.10m")
        let missing = await registry.action(id: "nope")
        #expect(missing == nil)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter SnoozeRegistryTests`
Expected: FAIL — `SnoozeRegistry` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeRegistry.swift`:

```swift
import Foundation

/// The active set of snooze actions, configurable at runtime.
///
/// Defaults registered at init per design Section 4: `tenMinutes`,
/// `oneHour`, `tomorrowMorning` (using `AppPreferences.defaultAllDayHour:Minute`).
public actor SnoozeRegistry {
    private var _actions: [SnoozeAction]

    public init(defaultAllDayHour: Int, defaultAllDayMinute: Int, timeZone: TimeZone) {
        self._actions = [
            .tenMinutes,
            .oneHour,
            .tomorrowMorning(hour: defaultAllDayHour, minute: defaultAllDayMinute, timeZone: timeZone)
        ]
    }

    public var actions: [SnoozeAction] { _actions }

    /// Register a new action, or replace one with the same `id`.
    public func register(_ action: SnoozeAction) {
        if let idx = _actions.firstIndex(where: { $0.id == action.id }) {
            _actions[idx] = action
        } else {
            _actions.append(action)
        }
    }

    public func action(id: String) -> SnoozeAction? {
        _actions.first { $0.id == id }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter SnoozeRegistryTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/SnoozeRegistry.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/SnoozeRegistryTests.swift
git commit -m "feat: add SnoozeRegistry actor with default actions and replacement-by-id"
```

---

## Task 9: `NotificationCategoryFactory`

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationCategoryFactory.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/Notifications/MorningSummaryRequestID.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationCategoryFactoryTests.swift`

Per design Section 4: one `UNNotificationCategory` per kind, each including one `UNNotificationAction` per registered snooze action.

- [ ] **Step 1: Write the well-known constants**

Write `Packages/LillistCore/Sources/LillistCore/Notifications/MorningSummaryRequestID.swift`:

```swift
import Foundation

/// Well-known notification request identifier for the daily morning summary
/// (design Section 4 Layer 4). One per device.
public enum MorningSummary {
    public static let requestID = "com.mikeydotio.lillist.morningSummary"
    public static let categoryID = "lillist.morningSummary"
}

/// Category identifier prefixes used by `NotificationCategoryFactory`.
/// One category per `NotificationKind`.
public enum NotificationCategoryID {
    public static func categoryID(for kind: NotificationKind) -> String {
        switch kind {
        case .defaultStart:    return "lillist.defaultStart"
        case .defaultDeadline: return "lillist.defaultDeadline"
        case .offsetStart:     return "lillist.offsetStart"
        case .offsetDeadline:  return "lillist.offsetDeadline"
        case .nudge:           return "lillist.nudge"
        }
    }
}
```

- [ ] **Step 2: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationCategoryFactoryTests.swift`:

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationCategoryFactory")
struct NotificationCategoryFactoryTests {
    @Test("Produces one category per NotificationKind")
    func oneCategoryPerKind() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let categories = await NotificationCategoryFactory.makeCategories(registry: registry)
        let ids = Set(categories.map(\.identifier))
        #expect(ids.contains("lillist.defaultStart"))
        #expect(ids.contains("lillist.defaultDeadline"))
        #expect(ids.contains("lillist.offsetStart"))
        #expect(ids.contains("lillist.offsetDeadline"))
        #expect(ids.contains("lillist.nudge"))
    }

    @Test("Each category includes one action per registered snooze action")
    func actionsPerCategory() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let categories = await NotificationCategoryFactory.makeCategories(registry: registry)
        for category in categories where category.identifier != MorningSummary.categoryID {
            #expect(category.actions.count == 3)
            let actionIDs = Set(category.actions.map(\.identifier))
            #expect(actionIDs.contains("snooze.10m"))
            #expect(actionIDs.contains("snooze.1h"))
            #expect(actionIDs.contains("snooze.tomorrow"))
        }
    }

    @Test("Custom snooze additions show up in next factory call")
    func customAction() async {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        await registry.register(SnoozeAction(id: "snooze.custom", displayName: "Custom") { _, d in d })
        let categories = await NotificationCategoryFactory.makeCategories(registry: registry)
        for category in categories where category.identifier == "lillist.nudge" {
            let actionIDs = Set(category.actions.map(\.identifier))
            #expect(actionIDs.contains("snooze.custom"))
        }
    }
}
```

- [ ] **Step 3: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter NotificationCategoryFactoryTests`
Expected: FAIL — `NotificationCategoryFactory` undefined.

- [ ] **Step 4: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationCategoryFactory.swift`:

```swift
import Foundation
import UserNotifications

/// Builds the `UNNotificationCategory` set for the app, one per
/// `NotificationKind`, each carrying actions for every action currently
/// registered in the given `SnoozeRegistry`.
public enum NotificationCategoryFactory {
    public static func makeCategories(registry: SnoozeRegistry) async -> Set<UNNotificationCategory> {
        let snoozeActions = await registry.actions
        let unActions: [UNNotificationAction] = snoozeActions.map { snooze in
            UNNotificationAction(
                identifier: snooze.id,
                title: snooze.displayName,
                options: []
            )
        }

        var categories: Set<UNNotificationCategory> = []
        for kind in NotificationKind.allCases {
            let cat = UNNotificationCategory(
                identifier: NotificationCategoryID.categoryID(for: kind),
                actions: unActions,
                intentIdentifiers: [],
                options: []
            )
            categories.insert(cat)
        }

        // Morning summary has no actions (tap to open the app).
        categories.insert(UNNotificationCategory(
            identifier: MorningSummary.categoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        ))
        return categories
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationCategoryFactoryTests`
Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationCategoryFactory.swift Packages/LillistCore/Sources/LillistCore/Notifications/MorningSummaryRequestID.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationCategoryFactoryTests.swift
git commit -m "feat: add NotificationCategoryFactory and morning summary identifiers"
```

---

## Task 10: `NotificationPermissions` actor

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationPermissions.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationPermissionsTests.swift`

Per design Section 4 (Permissions): "First-launch authorization request with a one-screen explanation. Denial → in-app banner with Settings deep-link." The actor delegates to the protocol-wrapped center so tests can simulate denial.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationPermissionsTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("NotificationPermissions")
struct NotificationPermissionsTests {
    @Test("requestAuthorization granted returns .authorized")
    func granted() async throws {
        let fake = FakeUserNotificationCenter()
        await fake.setAuthorizationGranted(true)
        let perms = NotificationPermissions(center: fake)
        let status = try await perms.requestAuthorization()
        #expect(status == .authorized)
        #expect(await fake.requestAuthorizationCallCount == 1)
    }

    @Test("requestAuthorization denied returns .denied")
    func denied() async throws {
        let fake = FakeUserNotificationCenter()
        await fake.setAuthorizationGranted(false)
        let perms = NotificationPermissions(center: fake)
        let status = try await perms.requestAuthorization()
        #expect(status == .denied)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter NotificationPermissionsTests`
Expected: FAIL — `NotificationPermissions` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationPermissions.swift`:

```swift
import Foundation
import UserNotifications

/// Wraps notification authorization. Apps call `requestAuthorization` on
/// first launch; on denial they surface a banner with a Settings deep-link
/// per design Section 4.
public actor NotificationPermissions {
    public enum AuthorizationStatus: Sendable, Equatable {
        case authorized
        case denied
    }

    private let center: any UNUserNotificationCenterProtocol

    public init(center: any UNUserNotificationCenterProtocol = SystemUserNotificationCenter()) {
        self.center = center
    }

    /// Requests the standard `[.alert, .sound, .badge]` authorization.
    /// Returns `.authorized` if granted, `.denied` otherwise. Errors from
    /// the underlying center are mapped to `.denied` so callers can degrade
    /// gracefully without try/catch.
    public func requestAuthorization() async -> AuthorizationStatus {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }
}
```

Note: the tests use `try` because Swift Testing requires it for `async` calls returning the actor; `requestAuthorization` itself is non-throwing — adjust the test to drop `try`.

- [ ] **Step 4: Fix the test signature**

Edit `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationPermissionsTests.swift`, removing `throws` and `try`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("NotificationPermissions")
struct NotificationPermissionsTests {
    @Test("requestAuthorization granted returns .authorized")
    func granted() async {
        let fake = FakeUserNotificationCenter()
        await fake.setAuthorizationGranted(true)
        let perms = NotificationPermissions(center: fake)
        let status = await perms.requestAuthorization()
        #expect(status == .authorized)
        #expect(await fake.requestAuthorizationCallCount == 1)
    }

    @Test("requestAuthorization denied returns .denied")
    func denied() async {
        let fake = FakeUserNotificationCenter()
        await fake.setAuthorizationGranted(false)
        let perms = NotificationPermissions(center: fake)
        let status = await perms.requestAuthorization()
        #expect(status == .denied)
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationPermissionsTests`
Expected: PASS, 2 tests.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationPermissions.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationPermissionsTests.swift
git commit -m "feat: add NotificationPermissions actor with graceful degradation on denial"
```

---

## Task 11: `NotificationScheduler` skeleton + Layer 1 (time-bearing dates)

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerLayer1TimeBearingTests.swift`

Implements design Section 4 Layer 1: "Time-bearing dates auto-schedule. `start` or `deadline` with a time → `UNCalendarNotificationTrigger`." On `reconcile(taskID:)`, the scheduler:

1. Loads the task and its specs.
2. Computes the desired set of `UNNotificationRequest`s.
3. Diffs against pending requests matching the task's spec IDs.
4. Adds/removes as needed.

In this task we only implement the path for `defaultStart`/`defaultDeadline` against a `*HasTime == true` field. The auto-spec is materialized **lazily on reconcile** rather than persisted on task save — design Section 4 says "the reconciler emits a `defaultStart`/`defaultDeadline` spec." We persist exactly one default-kind spec per anchor when its anchor field is non-nil, and remove it when the anchor goes nil.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerLayer1TimeBearingTests.swift`:

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Layer 1 (time-bearing dates)")
struct NotificationSchedulerLayer1TimeBearingTests {
    @Test("Setting deadline with time schedules a defaultDeadline request")
    func deadlineWithTimeSchedules() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p,
            specs: specs,
            center: fake,
            snoozeRegistry: registry,
            deviceFingerprint: "devA",
            defaultAllDayHour: 9,
            defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "Submit report")
        let when = Date().addingTimeInterval(7 * 24 * 3600)
        try await tasks.update(id: taskID) { d in
            d.deadline = when
            d.deadlineHasTime = true
        }
        await scheduler.reconcile(taskID: taskID)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        let r = pending[0]
        #expect(r.identifier.hasSuffix("#devA"))
        #expect(r.content.categoryIdentifier == "lillist.defaultDeadline")
    }

    @Test("Clearing the deadline removes the pending request")
    func clearDeadlineRemoves() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        let when = Date().addingTimeInterval(7 * 24 * 3600)
        try await tasks.update(id: taskID) { d in d.deadline = when; d.deadlineHasTime = true }
        await scheduler.reconcile(taskID: taskID)
        #expect(await fake.added.count == 1)

        try await tasks.update(id: taskID) { d in d.deadline = nil; d.deadlineHasTime = false }
        await scheduler.reconcile(taskID: taskID)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.isEmpty)
    }

    @Test("Reconcile is idempotent: calling twice produces one pending request")
    func idempotent() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        let when = Date().addingTimeInterval(3600)
        try await tasks.update(id: taskID) { d in d.deadline = when; d.deadlineHasTime = true }
        await scheduler.reconcile(taskID: taskID)
        await scheduler.reconcile(taskID: taskID)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerLayer1TimeBearingTests`
Expected: FAIL — `NotificationScheduler` undefined.

- [ ] **Step 3: Write the scheduler skeleton with Layer 1 support**

Write `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`:

```swift
import Foundation
import CoreData
import UserNotifications

/// Reconciles `NotificationSpec` rows against the system notification center.
///
/// Single entry point: `reconcile(taskID:)`. Every mutation that affects
/// scheduling (`TaskStore.update`, `.transition`, soft-delete, restore,
/// `NotificationSpecStore.add/update/delete`, recurrence spawn, snooze
/// handler) calls this method after its own save.
///
/// Identifier format (design Section 4 cross-device de-dup):
/// `"\(specID)#\(deviceFingerprint)"`.
public actor NotificationScheduler {
    private let persistence: PersistenceController
    private let specStore: NotificationSpecStore
    private let center: any UNUserNotificationCenterProtocol
    private let snoozeRegistry: SnoozeRegistry
    private let deviceFingerprint: String
    private(set) public var defaultAllDayHour: Int
    private(set) public var defaultAllDayMinute: Int
    private let timeZone: TimeZone

    public init(
        persistence: PersistenceController,
        specs: NotificationSpecStore,
        center: any UNUserNotificationCenterProtocol,
        snoozeRegistry: SnoozeRegistry,
        deviceFingerprint: String,
        defaultAllDayHour: Int,
        defaultAllDayMinute: Int,
        timeZone: TimeZone
    ) {
        self.persistence = persistence
        self.specStore = specs
        self.center = center
        self.snoozeRegistry = snoozeRegistry
        self.deviceFingerprint = deviceFingerprint
        self.defaultAllDayHour = defaultAllDayHour
        self.defaultAllDayMinute = defaultAllDayMinute
        self.timeZone = timeZone
    }

    // MARK: - Public reconciliation entry point

    public func reconcile(taskID: UUID) async {
        do {
            let snapshot = try await loadTaskSnapshot(taskID: taskID)
            // Ensure default specs exist (or don't) per the task's anchor fields.
            try await materializeDefaultSpecs(for: snapshot)

            let specs = try await specStore.specs(forTask: taskID)
            let desired = computeDesiredRequests(task: snapshot, specs: specs)

            let pending = await center.pendingNotificationRequests()
            let ourPending = pending.filter { matchesOurIdentifier($0.identifier, taskID: taskID, specs: specs) }
            let pendingByID = Dictionary(uniqueKeysWithValues: ourPending.map { ($0.identifier, $0) })
            let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.identifier, $0) })

            // Remove stale.
            let toRemove = ourPending.map(\.identifier).filter { desiredByID[$0] == nil }
            if toRemove.isEmpty == false {
                await center.removePendingNotificationRequests(withIdentifiers: toRemove)
            }
            // Add missing.
            for req in desired where pendingByID[req.identifier] == nil {
                try await center.add(req)
            }
        } catch {
            // Reconciliation must not throw outward — log via OSLog from
            // the app layer if needed. Failures here mean a transient
            // store/center error; next reconcile will retry.
        }
    }

    // MARK: - Snapshot

    struct TaskSnapshot: Sendable {
        let id: UUID
        let title: String
        let status: Status
        let start: Date?
        let startHasTime: Bool
        let deadline: Date?
        let deadlineHasTime: Bool
        let deletedAt: Date?
    }

    private func loadTaskSnapshot(taskID: UUID) async throws -> TaskSnapshot {
        let ctx = persistence.container.viewContext
        return try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            req.fetchLimit = 1
            guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
            return TaskSnapshot(
                id: m.id ?? UUID(),
                title: m.title ?? "",
                status: m.status,
                start: m.start,
                startHasTime: m.startHasTime,
                deadline: m.deadline,
                deadlineHasTime: m.deadlineHasTime,
                deletedAt: m.deletedAt
            )
        }
    }

    // MARK: - Default spec materialization (Layer 1/2)

    private func materializeDefaultSpecs(for task: TaskSnapshot) async throws {
        let existing = try await specStore.specs(forTask: task.id)
        let existingDefaultStart = existing.first { $0.kind == .defaultStart }
        let existingDefaultDeadline = existing.first { $0.kind == .defaultDeadline }

        // Default start: present iff task.start != nil and not soft-deleted and not closed.
        let needsStart = task.start != nil && task.deletedAt == nil && task.status != .closed
        if needsStart && existingDefaultStart == nil {
            _ = try await specStore.add(taskID: task.id, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)
        } else if needsStart == false, let s = existingDefaultStart {
            try await specStore.delete(id: s.id)
        }

        let needsDeadline = task.deadline != nil && task.deletedAt == nil && task.status != .closed
        if needsDeadline && existingDefaultDeadline == nil {
            _ = try await specStore.add(taskID: task.id, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)
        } else if needsDeadline == false, let s = existingDefaultDeadline {
            try await specStore.delete(id: s.id)
        }
    }

    // MARK: - Desired request computation

    func computeDesiredRequests(
        task: TaskSnapshot,
        specs: [NotificationSpecStore.SpecRecord]
    ) -> [UNNotificationRequest] {
        // Closed or soft-deleted tasks: no pending requests at all
        // (design Section 4: "→ Closed: cancel all pending").
        guard task.status != .closed, task.deletedAt == nil else { return [] }

        var out: [UNNotificationRequest] = []
        for spec in specs {
            guard let fireDate = computeFireDate(for: spec, task: task) else { continue }
            // Skip past-due fire dates.
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = task.title
            content.categoryIdentifier = NotificationCategoryID.categoryID(for: spec.kind)
            content.userInfo = [
                "taskID": task.id.uuidString,
                "specID": spec.id.uuidString,
                "kind": spec.kind.rawValue
            ]

            let trigger = makeCalendarTrigger(for: fireDate)
            let identifier = identifier(for: spec.id)
            out.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
        return out
    }

    func computeFireDate(
        for spec: NotificationSpecStore.SpecRecord,
        task: TaskSnapshot
    ) -> Date? {
        // Snooze: if `snoozedUntil` is in the future, that wins.
        if let snoozed = spec.snoozedUntil, snoozed > Date() {
            return snoozed
        }

        switch spec.kind {
        case .defaultStart:
            return resolvedAnchorDate(date: task.start, hasTime: task.startHasTime)
        case .defaultDeadline:
            return resolvedAnchorDate(date: task.deadline, hasTime: task.deadlineHasTime)
        case .offsetStart:
            guard let anchor = resolvedAnchorDate(date: task.start, hasTime: task.startHasTime),
                  let offset = spec.offsetMinutes else { return nil }
            return anchor.addingTimeInterval(TimeInterval(offset) * 60)
        case .offsetDeadline:
            guard let anchor = resolvedAnchorDate(date: task.deadline, hasTime: task.deadlineHasTime),
                  let offset = spec.offsetMinutes else { return nil }
            return anchor.addingTimeInterval(TimeInterval(offset) * 60)
        case .nudge:
            return spec.fireDate
        }
    }

    /// Resolves an anchor date: time-bearing returns the raw date; all-day
    /// returns the date with the default all-day hour:minute applied in the
    /// configured time zone (design Section 4 Layer 2).
    func resolvedAnchorDate(date: Date?, hasTime: Bool) -> Date? {
        guard let date else { return nil }
        if hasTime { return date }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var components = cal.dateComponents([.year, .month, .day], from: date)
        components.hour = defaultAllDayHour
        components.minute = defaultAllDayMinute
        components.second = 0
        return cal.date(from: components) ?? date
    }

    /// `UNCalendarNotificationTrigger` is DST-safe: it stores the components,
    /// not an absolute interval (design Section 8 — "DST: wall-clock time
    /// preserved across transitions via DateComponents-based triggers").
    func makeCalendarTrigger(for fireDate: Date) -> UNCalendarNotificationTrigger {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var components = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        components.timeZone = timeZone
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    // MARK: - Identifier helpers

    func identifier(for specID: UUID) -> String {
        "\(specID.uuidString)#\(deviceFingerprint)"
    }

    private func matchesOurIdentifier(_ identifier: String, taskID: UUID, specs: [NotificationSpecStore.SpecRecord]) -> Bool {
        let specIDs = Set(specs.map(\.id.uuidString))
        let prefix = identifier.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
        return specIDs.contains(prefix)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerLayer1TimeBearingTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerLayer1TimeBearingTests.swift
git commit -m "feat: add NotificationScheduler with Layer 1 (time-bearing date) reconciliation"
```

---

## Task 12: Layer 2 — all-day dates use the default time

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerLayer2AllDayTests.swift`

Layer 2 was already implemented by `resolvedAnchorDate` in Task 11; this task pins the behavior with focused tests, per design Section 4: "All-day dates use the user's default time."

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerLayer2AllDayTests.swift`:

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Layer 2 (all-day default time)")
struct NotificationSchedulerLayer2AllDayTests {
    @Test("All-day deadline fires at the default time on that date")
    func allDayDeadlineUsesDefault() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 8, defaultAllDayMinute: 30, timeZone: TimeZone(identifier: "UTC")!)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 8, defaultAllDayMinute: 30,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "All-day deadline")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: 2099, month: 6, day: 15)
        let allDayDate = cal.date(from: comps)!
        try await tasks.update(id: taskID) { d in
            d.deadline = allDayDate
            d.deadlineHasTime = false
        }
        await scheduler.reconcile(taskID: taskID)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        let trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 8)
        #expect(trigger?.dateComponents.minute == 30)
        #expect(trigger?.dateComponents.year == 2099)
        #expect(trigger?.dateComponents.month == 6)
        #expect(trigger?.dateComponents.day == 15)
    }

    @Test("Time-bearing date uses its own time, not the default")
    func timeBearingIgnoresDefault() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 8, defaultAllDayMinute: 30, timeZone: TimeZone(identifier: "UTC")!)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 8, defaultAllDayMinute: 30,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: 2099, month: 6, day: 15, hour: 14, minute: 0)
        let timed = cal.date(from: comps)!
        try await tasks.update(id: taskID) { d in
            d.deadline = timed
            d.deadlineHasTime = true
        }
        await scheduler.reconcile(taskID: taskID)

        let pending = await fake.pendingNotificationRequests()
        let trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 14)
        #expect(trigger?.dateComponents.minute == 0)
    }
}
```

- [ ] **Step 2: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerLayer2AllDayTests`
Expected: PASS, 2 tests (no implementation change required — Layer 2 was implemented in Task 11).

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerLayer2AllDayTests.swift
git commit -m "test: pin Layer 2 all-day-default-time behavior with focused tests"
```

---

## Task 13: Layer 3 — per-task offsets + `addOffset` public API

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerLayer3OffsetTests.swift`

Per design Section 4: "Per-task overrides. Zero or more additional `NotificationSpec`s with `offsetMinutes`." Public API: `addOffset(taskID:anchor:offsetMinutes:)`.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerLayer3OffsetTests.swift`:

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Layer 3 (per-task offsets)")
struct NotificationSchedulerLayer3OffsetTests {
    @Test("addOffset(.deadline, -60) creates a spec firing one hour before deadline")
    func addOffsetBeforeDeadline() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        let deadline = Date().addingTimeInterval(7 * 24 * 3600)
        try await tasks.update(id: taskID) { d in d.deadline = deadline; d.deadlineHasTime = true }

        let specID = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -60)
        await scheduler.reconcile(taskID: taskID)

        let pending = await fake.pendingNotificationRequests()
        // Two pending: the defaultDeadline + the offsetDeadline.
        #expect(pending.count == 2)
        let offsetReq = pending.first { $0.identifier.hasPrefix(specID.uuidString) }
        #expect(offsetReq?.content.categoryIdentifier == "lillist.offsetDeadline")
    }

    @Test("addOffset(.start, -30) creates a spec firing 30 minutes before start")
    func addOffsetBeforeStart() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        let start = Date().addingTimeInterval(7 * 24 * 3600)
        try await tasks.update(id: taskID) { d in d.start = start; d.startHasTime = true }

        _ = try await scheduler.addOffset(taskID: taskID, anchor: .start, offsetMinutes: -30)
        await scheduler.reconcile(taskID: taskID)

        let pending = await fake.pendingNotificationRequests()
        let offsetReq = pending.first { $0.content.categoryIdentifier == "lillist.offsetStart" }
        #expect(offsetReq != nil)
    }

    @Test("Offsets are skipped when the anchor field is nil")
    func offsetWithoutAnchorSkipped() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .start, offsetMinutes: -15)
        await scheduler.reconcile(taskID: taskID)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.isEmpty)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerLayer3OffsetTests`
Expected: FAIL — `addOffset` undefined.

- [ ] **Step 3: Add `addOffset` to the scheduler**

Append the following inside the `NotificationScheduler` actor in `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift` (before the closing brace):

```swift
    // MARK: - Public Layer 3 API

    /// Add a per-task offset reminder relative to either `start` or `deadline`.
    /// Negative `offsetMinutes` fires before the anchor; positive after.
    @discardableResult
    public func addOffset(
        taskID: UUID,
        anchor: NotificationKind.Anchor,
        offsetMinutes: Int32
    ) async throws -> UUID {
        let kind: NotificationKind
        switch anchor {
        case .start: kind = .offsetStart
        case .deadline: kind = .offsetDeadline
        }
        let id = try await specStore.add(
            taskID: taskID,
            kind: kind,
            offsetMinutes: offsetMinutes,
            fireDate: nil
        )
        await reconcile(taskID: taskID)
        return id
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerLayer3OffsetTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerLayer3OffsetTests.swift
git commit -m "feat: add addOffset for Layer 3 per-task notification offsets"
```

---

## Task 14: Layer 4 — morning summary scheduling

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerLayer4MorningSummaryTests.swift`

Per design Section 4 Layer 4: "Daily repeating trigger at user-configured time. Body computed at delivery from `LillistCore`." Single well-known request ID (`MorningSummary.requestID`). Identified separately from per-task requests; not part of `reconcile(taskID:)`. Called once on app launch or when preferences change.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerLayer4MorningSummaryTests.swift`:

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Layer 4 (morning summary)")
struct NotificationSchedulerLayer4MorningSummaryTests {
    @Test("installMorningSummary schedules a repeating request with the well-known ID")
    func installs() async throws {
        let p = try await TestStore.make()
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        await scheduler.installMorningSummary(hour: 7, minute: 15)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        let r = pending[0]
        #expect(r.identifier == MorningSummary.requestID)
        #expect(r.content.categoryIdentifier == MorningSummary.categoryID)
        let trigger = r.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == true)
        #expect(trigger?.dateComponents.hour == 7)
        #expect(trigger?.dateComponents.minute == 15)
    }

    @Test("Calling installMorningSummary twice replaces (one pending)")
    func replaces() async throws {
        let p = try await TestStore.make()
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        await scheduler.installMorningSummary(hour: 7, minute: 0)
        await scheduler.installMorningSummary(hour: 8, minute: 0)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        let trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 8)
    }

    @Test("uninstallMorningSummary removes the pending request")
    func uninstalls() async throws {
        let p = try await TestStore.make()
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        await scheduler.installMorningSummary(hour: 7, minute: 0)
        await scheduler.uninstallMorningSummary()
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.isEmpty)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerLayer4MorningSummaryTests`
Expected: FAIL — `installMorningSummary` undefined.

- [ ] **Step 3: Add morning-summary methods to the scheduler**

Append to `NotificationScheduler` in `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`:

```swift
    // MARK: - Public Layer 4 API

    /// Install or replace the daily morning summary at the given time.
    /// The body is supplied at delivery via a notification content extension
    /// that queries `LillistCore` for today's tasks (design Section 4 Layer 4).
    public func installMorningSummary(hour: Int, minute: Int) async {
        await center.removePendingNotificationRequests(withIdentifiers: [MorningSummary.requestID])

        let content = UNMutableNotificationContent()
        content.title = "Today in Lillist"
        content.body = ""  // Filled by content extension at delivery time.
        content.categoryIdentifier = MorningSummary.categoryID

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.timeZone = timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: MorningSummary.requestID,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    public func uninstallMorningSummary() async {
        await center.removePendingNotificationRequests(withIdentifiers: [MorningSummary.requestID])
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerLayer4MorningSummaryTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerLayer4MorningSummaryTests.swift
git commit -m "feat: add Layer 4 daily morning summary install/uninstall"
```

---

## Task 15: Nudge API — `addNudge`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerNudgeTests.swift`

Per design Section 4: "Nudges. First-class `NotificationSpec` of kind `nudge` with an absolute `fireDate`. Independent of start/deadline."

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerNudgeTests.swift`:

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Nudges")
struct NotificationSchedulerNudgeTests {
    @Test("addNudge schedules a nudge-category request at the given fireDate")
    func addNudge() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        let when = Date().addingTimeInterval(3 * 24 * 3600)
        let nudgeID = try await scheduler.addNudge(taskID: taskID, fireDate: when)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        #expect(pending[0].identifier == "\(nudgeID.uuidString)#devA")
        #expect(pending[0].content.categoryIdentifier == "lillist.nudge")
    }

    @Test("Nudges are independent of start/deadline")
    func nudgeIndependent() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        // No start, no deadline.
        let when = Date().addingTimeInterval(3 * 24 * 3600)
        _ = try await scheduler.addNudge(taskID: taskID, fireDate: when)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerNudgeTests`
Expected: FAIL — `addNudge` undefined.

- [ ] **Step 3: Add `addNudge` to the scheduler**

Append to `NotificationScheduler` in `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`:

```swift
    // MARK: - Public Nudge API

    /// Schedule a first-class nudge with an absolute `fireDate`. The nudge
    /// is independent of `start`/`deadline` and survives changes to them
    /// (design Section 4: "Nudges. First-class NotificationSpec of kind
    /// nudge with an absolute fireDate. Independent of start/deadline").
    @discardableResult
    public func addNudge(taskID: UUID, fireDate: Date) async throws -> UUID {
        let id = try await specStore.add(
            taskID: taskID,
            kind: .nudge,
            offsetMinutes: nil,
            fireDate: fireDate
        )
        await reconcile(taskID: taskID)
        return id
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerNudgeTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerNudgeTests.swift
git commit -m "feat: add addNudge for absolute-date nudges (independent of start/deadline)"
```

---

## Task 16: Snooze flow — `handleSnoozeAction`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerSnoozeTests.swift`

Per design Section 4 Snooze: tap action → handler writes `snoozedUntil` to the spec, triggers reconciliation. The `snoozedUntil` field is already honored by `computeFireDate` (Task 11). This task adds the handler and verifies the flow end-to-end.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerSnoozeTests.swift`:

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Snooze")
struct NotificationSchedulerSnoozeTests {
    @Test("handleSnoozeAction writes snoozedUntil and reschedules to that date")
    func snoozeTenMinutes() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        let nudgeID = try await scheduler.addNudge(taskID: taskID, fireDate: Date().addingTimeInterval(60))

        let deliveredAt = Date().addingTimeInterval(60)
        try await scheduler.handleSnoozeAction(
            actionID: "snooze.10m",
            specID: nudgeID,
            deliveredAt: deliveredAt
        )

        let record = try await specs.fetch(id: nudgeID)
        let expected = deliveredAt.addingTimeInterval(600)
        let drift = abs(record.snoozedUntil!.timeIntervalSince(expected))
        #expect(drift < 1.0)

        let pending = await fake.pendingNotificationRequests()
        let trigger = pending.first?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger != nil)
    }

    @Test("Unknown snooze action ID is rejected")
    func unknownAction() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        let nudgeID = try await scheduler.addNudge(taskID: taskID, fireDate: Date().addingTimeInterval(60))

        await #expect(throws: LillistError.self) {
            try await scheduler.handleSnoozeAction(
                actionID: "nope",
                specID: nudgeID,
                deliveredAt: Date()
            )
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerSnoozeTests`
Expected: FAIL — `handleSnoozeAction` undefined.

- [ ] **Step 3: Add `handleSnoozeAction` and `recordFired` to the scheduler**

Append to `NotificationScheduler` in `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`:

```swift
    // MARK: - Snooze handling

    /// Apply a snooze action to a spec. Writes `snoozedUntil` and reconciles.
    /// Call from your `UNUserNotificationCenterDelegate` `didReceive` handler.
    public func handleSnoozeAction(
        actionID: String,
        specID: UUID,
        deliveredAt: Date
    ) async throws {
        guard let action = await snoozeRegistry.action(id: actionID) else {
            throw LillistError.validationFailed([
                .init(field: "actionID", message: "unknown snooze action: \(actionID)")
            ])
        }
        let spec = try await specStore.fetch(id: specID)
        let until = action.compute(spec, deliveredAt)
        try await specStore.update(id: specID) { d in
            d.snoozedUntil = until
        }
        await reconcile(taskID: spec.taskID)
    }

    // MARK: - Fired-handler

    /// Record that a notification fired on this device. Call from your
    /// `UNUserNotificationCenterDelegate` `willPresent` handler. Other
    /// devices observe the change via CloudKit and remove their matching
    /// pending request (design Section 4 cross-device de-dup).
    public func recordFired(specID: UUID, at date: Date = Date()) async {
        try? await specStore.recordLastFired(id: specID, at: date)
        if let spec = try? await specStore.fetch(id: specID) {
            await reconcile(taskID: spec.taskID)
        }
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerSnoozeTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerSnoozeTests.swift
git commit -m "feat: add snooze handler and lastFired recorder on NotificationScheduler"
```

---

## Task 17: Status-transition reconciliation (Closed cancels, Re-open re-registers, Blocked stays)

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerStatusTransitionsTests.swift`

Per design Section 4: "→ Closed: cancel all pending deliveries (spec rows preserved for history). ← Closed: re-register any still-future specs. → Blocked: notifications NOT suppressed." All the underlying behavior is in `computeDesiredRequests` (closed → empty set). This task pins it with focused tests. **Note:** callers must call `reconcile(taskID:)` after every relevant mutation — see Task 18 for the integration hook in `TaskStore`.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerStatusTransitionsTests.swift`:

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Status transitions")
struct NotificationSchedulerStatusTransitionsTests {
    private func makeScheduler(_ p: PersistenceController, fake: FakeUserNotificationCenter, specs: NotificationSpecStore) -> NotificationScheduler {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        return NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
    }

    @Test("Closing a task cancels all pending deliveries (specs preserved)")
    func closedCancels() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let scheduler = makeScheduler(p, fake: fake, specs: specs)

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        await scheduler.reconcile(taskID: taskID)
        #expect(await fake.added.count == 1)

        try await tasks.transition(id: taskID, to: .closed)
        await scheduler.reconcile(taskID: taskID)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.isEmpty)

        // Specs preserved (defaultDeadline still in store, not cascaded away).
        let allSpecs = try await specs.specs(forTask: taskID)
        #expect(allSpecs.contains { $0.kind == .defaultDeadline })
    }

    @Test("Re-opening a closed task re-registers future specs")
    func reopenRegisters() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let scheduler = makeScheduler(p, fake: fake, specs: specs)

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        await scheduler.reconcile(taskID: taskID)
        try await tasks.transition(id: taskID, to: .closed)
        await scheduler.reconcile(taskID: taskID)
        #expect(await fake.pendingNotificationRequests().isEmpty)

        try await tasks.transition(id: taskID, to: .todo)
        await scheduler.reconcile(taskID: taskID)
        #expect(await fake.pendingNotificationRequests().count == 1)
    }

    @Test("Blocked tasks keep their notifications (design Section 4: not suppressed)")
    func blockedNotSuppressed() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let scheduler = makeScheduler(p, fake: fake, specs: specs)

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        await scheduler.reconcile(taskID: taskID)
        #expect(await fake.added.count == 1)

        try await tasks.transition(id: taskID, to: .blocked)
        await scheduler.reconcile(taskID: taskID)
        #expect(await fake.pendingNotificationRequests().count == 1)
    }

    @Test("Soft-deleted tasks cancel all pending")
    func softDeleteCancels() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let scheduler = makeScheduler(p, fake: fake, specs: specs)

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        await scheduler.reconcile(taskID: taskID)
        #expect(await fake.added.count == 1)

        try await tasks.softDelete(id: taskID)
        await scheduler.reconcile(taskID: taskID)
        #expect(await fake.pendingNotificationRequests().isEmpty)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerStatusTransitionsTests`
Expected: PASS, 4 tests (the behavior is already implemented; this task pins it).

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerStatusTransitionsTests.swift
git commit -m "test: pin status-transition reconciliation behavior (closed cancels, re-open re-registers, blocked stays)"
```

---

## Task 18: Cross-device de-dup — identifier format + lastFired-driven removal

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerCrossDeviceDedupTests.swift`

Per design Section 4: "Each device schedules its own local notification, tagged with `\(specID)#\(deviceFingerprint)`. On firing, write `lastFiredAt` to the spec. Other devices observe the change via CloudKit sync, remove the matching pending notification before it fires."

Implementation: when reconcile sees `lastFiredAt != nil` and the fire date has passed (i.e., another device already fired this), the desired set excludes the request → reconcile removes it locally.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerCrossDeviceDedupTests.swift`:

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Cross-device de-dup")
struct NotificationSchedulerCrossDeviceDedupTests {
    @Test("Identifier format is \"{specID}#{fingerprint}\"")
    func identifierFormat() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "phone-7",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        let nudgeID = try await scheduler.addNudge(taskID: taskID, fireDate: Date().addingTimeInterval(60))

        let pending = await fake.pendingNotificationRequests()
        #expect(pending[0].identifier == "\(nudgeID.uuidString)#phone-7")
    }

    @Test("Recording lastFiredAt removes the pending request on this device")
    func lastFiredRemoves() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        let fireDate = Date().addingTimeInterval(3600)
        let nudgeID = try await scheduler.addNudge(taskID: taskID, fireDate: fireDate)
        #expect(await fake.added.count == 1)

        // Simulate another device firing it; lastFiredAt is set in the spec.
        try await specs.recordLastFired(id: nudgeID, at: Date())
        await scheduler.reconcile(taskID: taskID)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.isEmpty)
    }

    @Test("Different device fingerprints produce different identifiers for the same spec")
    func differentDevicesDifferentIdentifiers() async throws {
        let p1 = try await TestStore.make()
        let p2 = try await TestStore.make()
        let tasks1 = TaskStore(persistence: p1)
        let specs1 = NotificationSpecStore(persistence: p1)
        let tasks2 = TaskStore(persistence: p2)
        let specs2 = NotificationSpecStore(persistence: p2)
        let fakeA = FakeUserNotificationCenter()
        let fakeB = FakeUserNotificationCenter()
        let registry1 = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let registry2 = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)

        let schedulerA = NotificationScheduler(
            persistence: p1, specs: specs1, center: fakeA,
            snoozeRegistry: registry1, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let schedulerB = NotificationScheduler(
            persistence: p2, specs: specs2, center: fakeB,
            snoozeRegistry: registry2, deviceFingerprint: "devB",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskA = try await tasks1.create(title: "T")
        let taskB = try await tasks2.create(title: "T")
        let nudgeA = try await schedulerA.addNudge(taskID: taskA, fireDate: Date().addingTimeInterval(60))
        let nudgeB = try await schedulerB.addNudge(taskID: taskB, fireDate: Date().addingTimeInterval(60))

        let pendingA = await fakeA.pendingNotificationRequests()
        let pendingB = await fakeB.pendingNotificationRequests()
        #expect(pendingA[0].identifier == "\(nudgeA.uuidString)#devA")
        #expect(pendingB[0].identifier == "\(nudgeB.uuidString)#devB")
    }
}
```

- [ ] **Step 2: Modify scheduler to exclude lastFired-recent specs from desired set**

Edit `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift` and modify `computeDesiredRequests` to skip specs where `lastFiredAt` is non-nil (and recent enough that we should consider them already delivered). Replace the body of `computeDesiredRequests` with:

```swift
    func computeDesiredRequests(
        task: TaskSnapshot,
        specs: [NotificationSpecStore.SpecRecord]
    ) -> [UNNotificationRequest] {
        guard task.status != .closed, task.deletedAt == nil else { return [] }

        var out: [UNNotificationRequest] = []
        for spec in specs {
            // Cross-device de-dup: if any device has recorded this fired
            // for the current scheduled fireDate, drop the pending here.
            if let lastFired = spec.lastFiredAt,
               let fireDate = computeFireDate(for: spec, task: task),
               lastFired >= fireDate.addingTimeInterval(-60) {
                continue
            }
            guard let fireDate = computeFireDate(for: spec, task: task) else { continue }
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = task.title
            content.categoryIdentifier = NotificationCategoryID.categoryID(for: spec.kind)
            content.userInfo = [
                "taskID": task.id.uuidString,
                "specID": spec.id.uuidString,
                "kind": spec.kind.rawValue
            ]

            let trigger = makeCalendarTrigger(for: fireDate)
            let identifier = identifier(for: spec.id)
            out.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
        return out
    }
```

- [ ] **Step 3: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerCrossDeviceDedupTests`
Expected: PASS, 3 tests.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerCrossDeviceDedupTests.swift
git commit -m "feat: honor lastFiredAt for cross-device notification de-duplication"
```

---

## Task 19: DST edge case — wall-clock fire time preserved across DST

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerDSTTests.swift`

Per design Section 8: "DST: wall-clock time preserved across transitions via `DateComponents`-based triggers." We use `UNCalendarNotificationTrigger` for everything, so this should hold; we pin it.

- [ ] **Step 1: Write the test**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerDSTTests.swift`:

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — DST safety")
struct NotificationSchedulerDSTTests {
    @Test("Scheduling at 09:00 the day before US spring-forward yields a calendar trigger at 09:00")
    func dstSpringForward() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let nyc = TimeZone(identifier: "America/New_York")!
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: nyc
        )

        // 2099-03-08 is a Sunday before a (hypothetical) DST transition.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = nyc
        let comps = DateComponents(year: 2099, month: 3, day: 8, hour: 9, minute: 0)
        let when = cal.date(from: comps)!

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = when
            d.deadlineHasTime = true
        }
        await scheduler.reconcile(taskID: taskID)

        let pending = await fake.pendingNotificationRequests()
        let trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        // Trigger stores components, not interval — the system reapplies the
        // calendar at fire time so 09:00 remains 09:00 regardless of DST.
        #expect(trigger?.dateComponents.hour == 9)
        #expect(trigger?.dateComponents.minute == 0)
        #expect(trigger?.dateComponents.timeZone == nyc)
    }

    @Test("All-day date during DST transition still uses configured default hour:minute")
    func allDayDuringDST() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 7, defaultAllDayMinute: 0, timeZone: TimeZone(identifier: "America/New_York")!)
        let nyc = TimeZone(identifier: "America/New_York")!
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 7, defaultAllDayMinute: 0,
            timeZone: nyc
        )

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = nyc
        let comps = DateComponents(year: 2099, month: 3, day: 8)
        let allDay = cal.date(from: comps)!

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = allDay
            d.deadlineHasTime = false
        }
        await scheduler.reconcile(taskID: taskID)

        let pending = await fake.pendingNotificationRequests()
        let trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 7)
        #expect(trigger?.dateComponents.minute == 0)
        #expect(trigger?.dateComponents.timeZone == nyc)
    }
}
```

- [ ] **Step 2: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerDSTTests`
Expected: PASS, 2 tests.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerDSTTests.swift
git commit -m "test: pin DST safety using UNCalendarNotificationTrigger components"
```

---

## Task 20: Default-time preference change reschedules existing all-day specs

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerPreferenceChangeTests.swift`

When the user changes `AppPreferences.defaultAllDayNotificationTime`, every all-day default spec needs to be rescheduled at the new time. Add `updateDefaultAllDayTime(hour:minute:)` to the scheduler; it changes its stored hour/minute and reconciles all tasks that have all-day defaults.

- [ ] **Step 1: Write failing test**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerPreferenceChangeTests.swift`:

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Preference change rescheduling")
struct NotificationSchedulerPreferenceChangeTests {
    @Test("Changing default all-day time reschedules existing all-day specs")
    func updateDefaultTime() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: TimeZone(identifier: "UTC")!)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: 2099, month: 1, day: 15)
        let allDay = cal.date(from: comps)!
        try await tasks.update(id: taskID) { d in
            d.deadline = allDay
            d.deadlineHasTime = false
        }
        await scheduler.reconcile(taskID: taskID)
        var pending = await fake.pendingNotificationRequests()
        var trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 9)

        await scheduler.updateDefaultAllDayTime(hour: 17, minute: 30)
        pending = await fake.pendingNotificationRequests()
        trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 17)
        #expect(trigger?.dateComponents.minute == 30)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerPreferenceChangeTests`
Expected: FAIL — `updateDefaultAllDayTime` undefined.

- [ ] **Step 3: Add the API**

Append to `NotificationScheduler` in `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`:

```swift
    // MARK: - Preference change

    /// Update the default all-day notification time. Reconciles every task
    /// that has at least one all-day default spec (design Section 4 Layer 2:
    /// the configured time is used at delivery, so changing it must
    /// re-trigger every dependent request).
    public func updateDefaultAllDayTime(hour: Int, minute: Int) async {
        self.defaultAllDayHour = hour
        self.defaultAllDayMinute = minute
        let affected = await tasksWithAllDayDefaults()
        for taskID in affected {
            await reconcile(taskID: taskID)
        }
    }

    private func tasksWithAllDayDefaults() async -> [UUID] {
        let ctx = persistence.container.viewContext
        return await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(
                format: "(start != nil AND startHasTime == NO) OR (deadline != nil AND deadlineHasTime == NO)"
            )
            let tasks = (try? ctx.fetch(req)) ?? []
            return tasks.compactMap(\.id)
        }
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NotificationSchedulerPreferenceChangeTests`
Expected: PASS, 1 test.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerPreferenceChangeTests.swift
git commit -m "feat: reschedule all-day specs when default notification time changes"
```

---

## Task 21: `TaskStore.scheduleFollowUp` — blocked-status follow-up helper

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+FollowUp.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/TaskStoreFollowUpTests.swift`

Per design Section 4 (Blocked-status follow-up affordance): "Submitting creates a **sibling** task (same parent), `status=todo`, with the title/deadline; the blocked task gets a `createdFollowUp` journal entry linking to it."

The journal payload is `{followUpTaskID}` — matches design Section 2 (`JournalEntry.payload` for `createdFollowUp` kind).

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Notifications/TaskStoreFollowUpTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore.scheduleFollowUp")
struct TaskStoreFollowUpTests {
    @Test("Creates a sibling with status .todo, given title and deadline")
    func createsSibling() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let parent = try await tasks.create(title: "Project")
        let blocked = try await tasks.create(title: "Wait on team", parent: parent)
        try await tasks.transition(id: blocked, to: .blocked)

        let when = Date().addingTimeInterval(24 * 3600)
        let followUp = try await tasks.scheduleFollowUp(
            parentTaskID: blocked,
            title: "Follow up",
            deadline: when
        )

        let followUpRecord = try await tasks.fetch(id: followUp)
        #expect(followUpRecord.title == "Follow up")
        #expect(followUpRecord.status == .todo)
        #expect(followUpRecord.deadline == when)
        // Same parent as the blocked task (i.e., sibling).
        #expect(followUpRecord.parentID == parent)
    }

    @Test("Blocked task gets a createdFollowUp journal entry with payload referencing the follow-up")
    func journalEntry() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let parent = try await tasks.create(title: "Project")
        let blocked = try await tasks.create(title: "Wait", parent: parent)
        try await tasks.transition(id: blocked, to: .blocked)

        let followUp = try await tasks.scheduleFollowUp(
            parentTaskID: blocked,
            title: "Follow up",
            deadline: Date().addingTimeInterval(24 * 3600)
        )

        let entries = try await journals.entries(forTask: blocked)
        let followUpEntries = entries.filter { $0.kind == .createdFollowUp }
        #expect(followUpEntries.count == 1)

        let payload = followUpEntries[0].payload!
        let decoded = try JSONSerialization.jsonObject(with: payload) as? [String: String]
        #expect(decoded?["followUpTaskID"] == followUp.uuidString)
    }

    @Test("Root-level blocked task creates a root-level sibling")
    func rootLevel() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let blocked = try await tasks.create(title: "Wait")
        try await tasks.transition(id: blocked, to: .blocked)

        let followUp = try await tasks.scheduleFollowUp(
            parentTaskID: blocked,
            title: "Follow up",
            deadline: Date().addingTimeInterval(24 * 3600)
        )
        let followUpRecord = try await tasks.fetch(id: followUp)
        #expect(followUpRecord.parentID == nil)
    }

    @Test("Missing parent task throws .notFound")
    func missingParent() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        await #expect(throws: LillistError.notFound) {
            _ = try await tasks.scheduleFollowUp(
                parentTaskID: UUID(),
                title: "x",
                deadline: Date()
            )
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreFollowUpTests`
Expected: FAIL — `scheduleFollowUp` undefined.

- [ ] **Step 3: Write the extension**

Write `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+FollowUp.swift`:

```swift
import Foundation
import CoreData

extension TaskStore {
    /// Create a sibling follow-up task and append a `createdFollowUp`
    /// journal entry on the parent. Per design Section 4: "Sibling rather
    /// than child so collapsing the blocked task doesn't hide the follow-up."
    ///
    /// - Parameters:
    ///   - parentTaskID: the blocked task to attach the journal entry to.
    ///     The new task becomes its sibling (same `parent`).
    ///   - title: title of the new task.
    ///   - deadline: deadline for the new task (time-bearing is preserved).
    /// - Returns: the new task's UUID.
    @discardableResult
    public func scheduleFollowUp(
        parentTaskID: UUID,
        title: String,
        deadline: Date
    ) async throws -> UUID {
        try validateTitle(title)
        let ctx = persistence.container.viewContext
        return try await ctx.perform { [self] in
            let blocked = try fetchManagedObject(id: parentTaskID, in: ctx)
            let siblingParent: LillistTask? = blocked.parent

            let followUp = LillistTask(context: ctx)
            let newID = UUID()
            followUp.id = newID
            followUp.title = title
            followUp.notes = ""
            followUp.status = .todo
            followUp.startHasTime = false
            followUp.deadlineHasTime = true
            followUp.deadline = deadline
            followUp.isPinned = false
            followUp.createdAt = Date()
            followUp.modifiedAt = followUp.createdAt
            followUp.parent = siblingParent
            followUp.position = try nextPosition(forParent: siblingParent)

            // Journal entry on the blocked task.
            let entry = JournalEntry(context: ctx)
            entry.id = UUID()
            entry.task = blocked
            entry.kind = .createdFollowUp
            entry.body = "Created follow-up: \(title)"
            entry.createdAt = Date()
            let payload: [String: String] = ["followUpTaskID": newID.uuidString]
            entry.payload = try JSONSerialization.data(withJSONObject: payload)

            try ctx.save()
            return newID
        }
    }
}
```

Note: this extension depends on `fetchManagedObject(id:in:)`, `nextPosition(forParent:)`, and `validateTitle(_:)` being accessible — they are declared internal (default) on `TaskStore` in Plan 1, which is sufficient for same-module access. It also requires a `public` getter to access `persistence`. Update `TaskStore` to expose `internal var persistence: PersistenceController { get }` (already private in Plan 1's draft — promote to internal).

- [ ] **Step 4: Promote `persistence` to internal in `TaskStore`**

Edit `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`. Find the line:

```swift
    private let persistence: PersistenceController
```

and change it to:

```swift
    let persistence: PersistenceController
```

- [ ] **Step 5: Run to verify pass**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreFollowUpTests`
Expected: PASS, 4 tests.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+FollowUp.swift Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/TaskStoreFollowUpTests.swift
git commit -m "feat: add TaskStore.scheduleFollowUp blocked-status follow-up helper"
```

---

## Task 22: Final integration sweep — full suite green, install categories on scheduler init

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`

The scheduler should publish its category set to the center on first reconciliation so taps on system notifications find their action handlers. Add a `bootstrap()` method that callers invoke once on app launch.

- [ ] **Step 1: Add `bootstrap()` to the scheduler**

Append to `NotificationScheduler` in `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`:

```swift
    // MARK: - Bootstrap

    /// Call once on app launch. Publishes the notification categories
    /// (one per `NotificationKind`, plus the morning summary category)
    /// so that the system can dispatch action taps to the app.
    public func bootstrap() async {
        let categories = await NotificationCategoryFactory.makeCategories(registry: snoozeRegistry)
        await center.setNotificationCategories(categories)
    }
```

- [ ] **Step 2: Add a test for bootstrap**

Append to `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationCategoryFactoryTests.swift`:

```swift
    @Test("Scheduler.bootstrap publishes categories to the center")
    func bootstrapPublishesCategories() async throws {
        let p = try await TestStore.make()
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: .current
        )
        await scheduler.bootstrap()
        let categoryIDs = Set((await fake.categories).map(\.identifier))
        #expect(categoryIDs.contains("lillist.defaultStart"))
        #expect(categoryIDs.contains("lillist.defaultDeadline"))
        #expect(categoryIDs.contains("lillist.offsetStart"))
        #expect(categoryIDs.contains("lillist.offsetDeadline"))
        #expect(categoryIDs.contains("lillist.nudge"))
        #expect(categoryIDs.contains(MorningSummary.categoryID))
    }
```

- [ ] **Step 3: Run the full Notifications test suite**

Run: `cd Packages/LillistCore && swift test`
Expected: every test, old and new, passes. Resolve any concurrency warnings introduced by the new actors (most likely candidate: `Sendable` conformance issues in `FakeUserNotificationCenter` — add `@unchecked Sendable` to any non-Sendable closures or values that the compiler flags).

- [ ] **Step 4: Tag the milestone**

```bash
git tag -a notifications-v1 -m "Plan 5 complete: notifications, snooze, nudges, blocked follow-up"
```

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationCategoryFactoryTests.swift
git commit -m "feat: add bootstrap() to publish notification categories on launch"
```

---

## Done.

The notifications layer per design Section 4 is complete: `NotificationSpec` entity in the model, `NotificationSpecStore` for CRUD, `NotificationScheduler` actor reconciling all four delivery layers (time-bearing dates, all-day defaults, per-task offsets, morning summary) plus nudges, snooze flow with extensible `SnoozeRegistry`, cross-device de-dup via `lastFiredAt`, status-transition awareness (closed cancels, re-open re-registers, blocked stays), DST safety via `UNCalendarNotificationTrigger`, default-time preference change rescheduling, `TaskStore.scheduleFollowUp` blocked follow-up helper, and `NotificationPermissions` actor with graceful denial. Full test suite green.
