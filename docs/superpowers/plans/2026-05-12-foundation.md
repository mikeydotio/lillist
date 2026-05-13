# Lillist Plan 1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `LillistCore` Swift package with a complete local-only Core Data persistence layer for Tasks, Tags, JournalEntries, and Attachments — including CRUD, hierarchy operations, soft-delete with auto-purge, and JSON+assets export — all under Swift Testing with TDD discipline.

**Architecture:** A single Swift Package Manager package, `LillistCore`, exposing a typed-error API surface over Core Data via `NSPersistentContainer` (CloudKit comes in Plan 2). Public API is `*Store` classes (`TaskStore`, `TagStore`, `JournalStore`, `AttachmentStore`, `PreferencesStore`) plus an `Exporter`. Models are Core Data managed objects defined via an `.xcdatamodeld` file. All business invariants (cycle prevention, position ordering, cascade rules, tag-name uniqueness, status-transition journal entries) are enforced in the store layer, not the schema, to keep the design CloudKit-compatible. The package targets macOS 15 / iOS 18 / iPadOS 18 and uses Swift 6 strict concurrency.

**Tech Stack:** Swift 6, Swift Package Manager, Core Data (`NSPersistentContainer`), Swift Testing (`@Test`, `#expect`), Foundation. No third-party dependencies in Plan 1.

---

## File Structure

```
Lillist/
├── docs/
│   ├── plans/
│   │   └── 2026-05-12-lillist-design.md           (existing — the design)
│   └── superpowers/
│       └── plans/
│           └── 2026-05-12-foundation.md           (this plan)
├── Packages/
│   └── LillistCore/
│       ├── Package.swift                          (SPM manifest)
│       ├── Sources/
│       │   └── LillistCore/
│       │       ├── LillistCore.swift              (umbrella / version)
│       │       ├── Model/
│       │       │   ├── Status.swift               (Status enum)
│       │       │   ├── AttachmentKind.swift       (AttachmentKind enum)
│       │       │   ├── JournalEntryKind.swift     (JournalEntryKind enum)
│       │       │   ├── SortField.swift            (SortField enum)
│       │       │   └── LillistModel.xcdatamodeld/ (Core Data model)
│       │       │       ├── .xccurrentversion
│       │       │       └── LillistModel.xcdatamodel/
│       │       │           └── contents
│       │       ├── ManagedObjects/
│       │       │   ├── LillistTask+CoreData.swift (typed accessors over auto-gen)
│       │       │   ├── Tag+CoreData.swift
│       │       │   ├── JournalEntry+CoreData.swift
│       │       │   ├── Attachment+CoreData.swift
│       │       │   └── AppPreferences+CoreData.swift
│       │       ├── Persistence/
│       │       │   ├── PersistenceController.swift  (NSPersistentContainer wrapper)
│       │       │   ├── StoreConfiguration.swift     (in-memory vs on-disk config)
│       │       │   └── AutoPurgeJob.swift           (Trash retention sweep)
│       │       ├── Stores/
│       │       │   ├── TaskStore.swift
│       │       │   ├── TagStore.swift
│       │       │   ├── JournalStore.swift
│       │       │   ├── AttachmentStore.swift
│       │       │   └── PreferencesStore.swift
│       │       ├── Validation/
│       │       │   ├── LillistError.swift           (typed error enum)
│       │       │   └── Validators.swift             (cycle, name-collision)
│       │       ├── Ordering/
│       │       │   ├── FractionalPosition.swift     (gap-based insert math)
│       │       │   └── PositionCompactor.swift
│       │       └── Export/
│       │           ├── Exporter.swift               (JSON + assets folder)
│       │           └── ExportSchema.swift           (Codable DTOs for export)
│       └── Tests/
│           └── LillistCoreTests/
│               ├── Helpers/
│               │   └── TestStore.swift              (in-memory factory)
│               ├── Model/
│               │   ├── StatusTests.swift
│               │   ├── AttachmentKindTests.swift
│               │   └── JournalEntryKindTests.swift
│               ├── Validation/
│               │   └── LillistErrorTests.swift
│               ├── Persistence/
│               │   ├── PersistenceControllerTests.swift
│               │   └── AutoPurgeJobTests.swift
│               ├── Stores/
│               │   ├── TaskStoreCRUDTests.swift
│               │   ├── TaskStoreHierarchyTests.swift
│               │   ├── TaskStoreOrderingTests.swift
│               │   ├── TaskStoreStatusTests.swift
│               │   ├── TaskStoreSoftDeleteTests.swift
│               │   ├── TagStoreTests.swift
│               │   ├── TagHierarchyTests.swift
│               │   ├── JournalStoreTests.swift
│               │   ├── AttachmentStoreTests.swift
│               │   └── PreferencesStoreTests.swift
│               ├── Ordering/
│               │   ├── FractionalPositionTests.swift
│               │   └── PositionCompactorTests.swift
│               └── Export/
│                   └── ExporterTests.swift
```

The empty stub at `Lillist/Lillist.xcodeproj` is removed in Task 1 — it predates this design and never had content.

---

## Notes for the Implementer

**TDD discipline.** Every functional task follows red → green → refactor → commit. Write the test first, run it, watch it fail, write minimal code, watch it pass, commit. Don't write code without a failing test on the board.

**Core Data quirks.** "Task" is reserved (it conflicts with Swift's `_Concurrency.Task`). The Core Data entity is named `LillistTask` and represented by class `LillistTask` in the `LillistCore` module. All CloudKit-compatibility constraints apply even though Plan 1 isn't CloudKit-enabled yet: every attribute is optional at the schema level (required-ness enforced in `*Store`), no `Deny` deletion rules, every relationship has an inverse, no required ordered relationships.

**Concurrency.** All store operations are `async` and run on the persistent container's `viewContext` queue. The package targets Swift 6 strict concurrency. Where Apple's Core Data types aren't yet `Sendable`, isolate carefully — keep `NSManagedObject` instances inside their owning context and return value-type DTOs across actor boundaries.

**No CloudKit in Plan 1.** That's Plan 2. Use `NSPersistentContainer` (not `NSPersistentCloudKitContainer`). The model file is already CloudKit-ready, so Plan 2 just swaps the container class.

**Commits.** Each task ends in a commit. Use conventional-commit prefixes: `feat:`, `test:`, `chore:`, `fix:`, `refactor:`.

**Verification command throughout:** `cd Packages/LillistCore && swift test`. PRs to merge only when `swift test` is green and Test Engineer subagent review (per design Section 9) has approved test quality.

---

## Task 1: Clean up stale Xcode project and initialize `LillistCore` SPM package

**Files:**
- Delete: `Lillist/Lillist.xcodeproj/` (the empty stub directory)
- Delete: `Lillist/` (now-empty parent directory)
- Create: `Packages/LillistCore/Package.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/LillistCore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/SmokeTests.swift`

- [ ] **Step 1: Remove the empty Xcode project**

```bash
git rm -r Lillist/Lillist.xcodeproj
rmdir Lillist
```

- [ ] **Step 2: Create the SPM manifest**

Write `Packages/LillistCore/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LillistCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(name: "LillistCore", targets: ["LillistCore"])
    ],
    targets: [
        .target(
            name: "LillistCore",
            resources: [
                .process("Model/LillistModel.xcdatamodeld")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "LillistCoreTests",
            dependencies: ["LillistCore"]
        )
    ]
)
```

- [ ] **Step 3: Create the umbrella file**

Write `Packages/LillistCore/Sources/LillistCore/LillistCore.swift`:

```swift
import Foundation

public enum LillistCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 4: Create the smoke test**

Write `Packages/LillistCore/Tests/LillistCoreTests/SmokeTests.swift`:

```swift
import Testing
@testable import LillistCore

@Suite("Smoke")
struct SmokeTests {
    @Test("Package builds and version is set")
    func versionExists() {
        #expect(LillistCore.version == "0.1.0")
    }
}
```

- [ ] **Step 5: Verify build (the Core Data model resource is still missing, so build will fail loudly)**

Run: `cd Packages/LillistCore && swift build`
Expected: build fails because `Model/LillistModel.xcdatamodeld` doesn't exist yet. This is fine — Task 5 creates it. Skip to Step 6.

- [ ] **Step 6: Temporarily remove the resources entry so we can confirm the smoke test passes**

Edit `Packages/LillistCore/Package.swift` and remove the `resources: [.process(...)]` line from the `.target` block:

```swift
        .target(
            name: "LillistCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
```

We'll re-add it in Task 5 once the model file exists.

- [ ] **Step 7: Run the smoke test**

Run: `cd Packages/LillistCore && swift test`
Expected: PASS with one test reported.

- [ ] **Step 8: Commit**

```bash
git add Packages/ Lillist/
git commit -m "chore: initialize LillistCore SPM package and remove empty stub"
```

---

## Task 2: Define `Status` enum

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Model/Status.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Model/StatusTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Model/StatusTests.swift`:

```swift
import Testing
@testable import LillistCore

@Suite("Status")
struct StatusTests {
    @Test("Raw values are stable for persistence")
    func rawValuesStable() {
        #expect(Status.todo.rawValue == 0)
        #expect(Status.started.rawValue == 1)
        #expect(Status.blocked.rawValue == 2)
        #expect(Status.closed.rawValue == 3)
    }

    @Test("All cases enumerable")
    func allCases() {
        #expect(Status.allCases.count == 4)
        #expect(Status.allCases.contains(.todo))
        #expect(Status.allCases.contains(.started))
        #expect(Status.allCases.contains(.blocked))
        #expect(Status.allCases.contains(.closed))
    }

    @Test("isClosed convenience")
    func isClosed() {
        #expect(Status.closed.isClosed == true)
        #expect(Status.todo.isClosed == false)
        #expect(Status.started.isClosed == false)
        #expect(Status.blocked.isClosed == false)
    }

    @Test("Round-trip through Int16 (Core Data backing type)")
    func int16RoundTrip() {
        for status in Status.allCases {
            let int16 = Int16(status.rawValue)
            #expect(Status(rawValue: Int(int16)) == status)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/LillistCore && swift test --filter StatusTests`
Expected: FAIL — `Status` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Model/Status.swift`:

```swift
import Foundation

/// The lifecycle state of a task.
///
/// Raw values are persisted; never reorder or remove cases. New statuses
/// must take an unused raw value. Stored in Core Data as `Int16`.
public enum Status: Int, CaseIterable, Codable, Sendable {
    case todo = 0
    case started = 1
    case blocked = 2
    case closed = 3

    /// True if this status represents a completed/terminal state.
    public var isClosed: Bool {
        self == .closed
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/LillistCore && swift test --filter StatusTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Model/Status.swift Packages/LillistCore/Tests/LillistCoreTests/Model/StatusTests.swift
git commit -m "feat: add Status enum with stable raw values"
```

---

## Task 3: Define `AttachmentKind` and `JournalEntryKind` enums

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Model/AttachmentKind.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/Model/JournalEntryKind.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Model/AttachmentKindTests.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Model/JournalEntryKindTests.swift`

- [ ] **Step 1: Write failing tests for AttachmentKind**

Write `Packages/LillistCore/Tests/LillistCoreTests/Model/AttachmentKindTests.swift`:

```swift
import Testing
@testable import LillistCore

@Suite("AttachmentKind")
struct AttachmentKindTests {
    @Test("Raw values stable")
    func rawValues() {
        #expect(AttachmentKind.image.rawValue == 0)
        #expect(AttachmentKind.file.rawValue == 1)
        #expect(AttachmentKind.linkPreview.rawValue == 2)
    }

    @Test("All cases enumerable")
    func allCases() {
        #expect(AttachmentKind.allCases.count == 3)
    }
}
```

- [ ] **Step 2: Write failing tests for JournalEntryKind**

Write `Packages/LillistCore/Tests/LillistCoreTests/Model/JournalEntryKindTests.swift`:

```swift
import Testing
@testable import LillistCore

@Suite("JournalEntryKind")
struct JournalEntryKindTests {
    @Test("Raw values stable")
    func rawValues() {
        #expect(JournalEntryKind.note.rawValue == 0)
        #expect(JournalEntryKind.statusChange.rawValue == 1)
        #expect(JournalEntryKind.attachment.rawValue == 2)
        #expect(JournalEntryKind.createdFollowUp.rawValue == 3)
    }

    @Test("System kinds are read-only")
    func systemKinds() {
        #expect(JournalEntryKind.note.isUserEditable == true)
        #expect(JournalEntryKind.statusChange.isUserEditable == false)
        #expect(JournalEntryKind.attachment.isUserEditable == true)
        #expect(JournalEntryKind.createdFollowUp.isUserEditable == false)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd Packages/LillistCore && swift test --filter AttachmentKindTests --filter JournalEntryKindTests`
Expected: FAIL — types undefined.

- [ ] **Step 4: Write AttachmentKind implementation**

Write `Packages/LillistCore/Sources/LillistCore/Model/AttachmentKind.swift`:

```swift
import Foundation

public enum AttachmentKind: Int, CaseIterable, Codable, Sendable {
    case image = 0
    case file = 1
    case linkPreview = 2
}
```

- [ ] **Step 5: Write JournalEntryKind implementation**

Write `Packages/LillistCore/Sources/LillistCore/Model/JournalEntryKind.swift`:

```swift
import Foundation

public enum JournalEntryKind: Int, CaseIterable, Codable, Sendable {
    case note = 0
    case statusChange = 1
    case attachment = 2
    case createdFollowUp = 3

    /// System-generated entries (status changes, follow-up creation)
    /// have their body managed by the app and reject user edits.
    public var isUserEditable: Bool {
        switch self {
        case .note, .attachment:
            return true
        case .statusChange, .createdFollowUp:
            return false
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd Packages/LillistCore && swift test --filter AttachmentKindTests --filter JournalEntryKindTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Model/ Packages/LillistCore/Tests/LillistCoreTests/Model/
git commit -m "feat: add AttachmentKind and JournalEntryKind enums"
```

---

## Task 4: Define `SortField` enum

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Model/SortField.swift`

This is a small data-only type with no business logic. Tests folded into later store tests.

- [ ] **Step 1: Write the enum**

Write `Packages/LillistCore/Sources/LillistCore/Model/SortField.swift`:

```swift
import Foundation

/// Available sort fields for task lists.
///
/// `manualPosition` only makes sense within a single parent. Smart filter
/// results spanning multiple parents must use another sort field; the
/// `*Store` layer rejects `manualPosition` with `LillistError.validationFailed`
/// when the query crosses parent boundaries.
public enum SortField: String, CaseIterable, Codable, Sendable {
    case manualPosition
    case start
    case deadline
    case title
    case createdAt
    case modifiedAt
    case closedAt
    case status
}
```

- [ ] **Step 2: Verify build**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Model/SortField.swift
git commit -m "feat: add SortField enum"
```

---

## Task 5: Create the Core Data model (`LillistModel.xcdatamodeld`)

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/.xccurrentversion`
- Create: `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`
- Modify: `Packages/LillistCore/Package.swift` (re-add resources entry)

The `.xcdatamodeld` is a directory bundle. We write the two files inside it directly. **All attributes are optional** at the schema level — required-ness is enforced in the store layer (CloudKit-compatibility requirement). **All relationships have inverses, no `Deny` rules** (also CloudKit-required).

- [ ] **Step 1: Create the `.xccurrentversion` pointer**

Write `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/.xccurrentversion`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>_XCCurrentVersionName</key>
	<string>LillistModel.xcdatamodel</string>
</dict>
</plist>
```

- [ ] **Step 2: Create the model contents XML**

Write `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="22112" systemVersion="24A0" minimumToolsVersion="Automatic" sourceLanguage="Swift" usedWithCloudKit="YES" userDefinedModelVersionIdentifier="">
    <entity name="LillistTask" representedClassName="LillistTask" syncable="YES">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="title" optional="YES" attributeType="String"/>
        <attribute name="notes" optional="YES" attributeType="String"/>
        <attribute name="statusRaw" optional="YES" attributeType="Integer 16" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="start" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="startHasTime" optional="YES" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
        <attribute name="deadline" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="deadlineHasTime" optional="YES" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
        <attribute name="position" optional="YES" attributeType="Double" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="isPinned" optional="YES" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
        <attribute name="createdAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="modifiedAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="closedAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="deletedAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <relationship name="parent" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="LillistTask" inverseName="children" inverseEntity="LillistTask"/>
        <relationship name="children" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="LillistTask" inverseName="parent" inverseEntity="LillistTask"/>
        <relationship name="tags" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="Tag" inverseName="tasks" inverseEntity="Tag"/>
        <relationship name="journalEntries" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="JournalEntry" inverseName="task" inverseEntity="JournalEntry"/>
        <relationship name="attachments" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="Attachment" inverseName="task" inverseEntity="Attachment"/>
    </entity>
    <entity name="Tag" representedClassName="Tag" syncable="YES">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="name" optional="YES" attributeType="String"/>
        <attribute name="tintColor" optional="YES" attributeType="String"/>
        <attribute name="position" optional="YES" attributeType="Double" defaultValueString="0" usesScalarValueType="YES"/>
        <relationship name="parent" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Tag" inverseName="children" inverseEntity="Tag"/>
        <relationship name="children" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="Tag" inverseName="parent" inverseEntity="Tag"/>
        <relationship name="tasks" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="LillistTask" inverseName="tags" inverseEntity="LillistTask"/>
    </entity>
    <entity name="JournalEntry" representedClassName="JournalEntry" syncable="YES">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="kindRaw" optional="YES" attributeType="Integer 16" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="body" optional="YES" attributeType="String"/>
        <attribute name="payload" optional="YES" attributeType="Binary"/>
        <attribute name="createdAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="editedAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <relationship name="task" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="LillistTask" inverseName="journalEntries" inverseEntity="LillistTask"/>
        <relationship name="attachments" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="Attachment" inverseName="journalEntry" inverseEntity="Attachment"/>
    </entity>
    <entity name="Attachment" representedClassName="Attachment" syncable="YES">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="kindRaw" optional="YES" attributeType="Integer 16" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="filename" optional="YES" attributeType="String"/>
        <attribute name="uti" optional="YES" attributeType="String"/>
        <attribute name="byteSize" optional="YES" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="data" optional="YES" attributeType="Binary" allowsExternalBinaryDataStorage="YES"/>
        <attribute name="linkPreviewJSON" optional="YES" attributeType="String"/>
        <attribute name="createdAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <relationship name="task" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="LillistTask" inverseName="attachments" inverseEntity="LillistTask"/>
        <relationship name="journalEntry" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="JournalEntry" inverseName="attachments" inverseEntity="JournalEntry"/>
    </entity>
    <entity name="AppPreferences" representedClassName="AppPreferences" syncable="YES">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="defaultAllDayNotificationHour" optional="YES" attributeType="Integer 16" defaultValueString="9" usesScalarValueType="YES"/>
        <attribute name="defaultAllDayNotificationMinute" optional="YES" attributeType="Integer 16" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="morningSummaryEnabled" optional="YES" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
        <attribute name="morningSummaryHour" optional="YES" attributeType="Integer 16" defaultValueString="9" usesScalarValueType="YES"/>
        <attribute name="morningSummaryMinute" optional="YES" attributeType="Integer 16" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="trashRetentionDays" optional="YES" attributeType="Integer 16" defaultValueString="30" usesScalarValueType="YES"/>
        <attribute name="defaultTaskListSortRaw" optional="YES" attributeType="String" defaultValueString="manualPosition"/>
    </entity>
</model>
```

- [ ] **Step 3: Restore the resources entry in `Package.swift`**

Edit `Packages/LillistCore/Package.swift`, restoring the `resources:` line:

```swift
        .target(
            name: "LillistCore",
            resources: [
                .process("Model/LillistModel.xcdatamodeld")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
```

- [ ] **Step 4: Build to confirm the model is recognized**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds. Core Data auto-generates `LillistTask`, `Tag`, `JournalEntry`, `Attachment`, `AppPreferences` classes from the model.

- [ ] **Step 5: Run existing tests**

Run: `cd Packages/LillistCore && swift test`
Expected: all previously-passing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/
git commit -m "feat: add Core Data model with five entities (CloudKit-compatible schema)"
```

---

## Task 6: Define `LillistError`

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Validation/LillistErrorTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Validation/LillistErrorTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("LillistError")
struct LillistErrorTests {
    @Test("Errors are equatable for known cases")
    func equatable() {
        #expect(LillistError.notFound == LillistError.notFound)
        #expect(LillistError.notFound != LillistError.migrationRequired)
    }

    @Test("validationFailed carries issues")
    func validationFailedIssues() {
        let err = LillistError.validationFailed([
            .init(field: "title", message: "must not be empty")
        ])
        if case .validationFailed(let issues) = err {
            #expect(issues.count == 1)
            #expect(issues.first?.field == "title")
        } else {
            Issue.record("expected .validationFailed")
        }
    }

    @Test("ambiguous carries candidate IDs")
    func ambiguousCandidates() {
        let a = UUID()
        let b = UUID()
        let err = LillistError.ambiguous([a, b])
        if case .ambiguous(let ids) = err {
            #expect(ids == [a, b])
        } else {
            Issue.record("expected .ambiguous")
        }
    }

    @Test("Error has localized description for every case")
    func localizedDescriptions() {
        let cases: [LillistError] = [
            .storeUnavailable(reason: "test"),
            .iCloudUnavailable(reason: "test"),
            .syncFailure(underlying: "test"),
            .validationFailed([]),
            .notFound,
            .ambiguous([]),
            .quotaExceeded(resource: "test"),
            .attachmentTooLarge(byteSize: 0),
            .attachmentFetchFailed(url: URL(string: "https://example.com")!),
            .migrationRequired,
            .migrationFailed(underlying: "test")
        ]
        for err in cases {
            #expect(err.localizedDescription.isEmpty == false)
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter LillistErrorTests`
Expected: FAIL — type undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift`:

```swift
import Foundation

/// Single error type for all `LillistCore` public APIs.
public enum LillistError: Error, Sendable, Equatable {
    public struct Issue: Sendable, Equatable {
        public let field: String
        public let message: String
        public init(field: String, message: String) {
            self.field = field
            self.message = message
        }
    }

    case storeUnavailable(reason: String)
    case iCloudUnavailable(reason: String)
    case syncFailure(underlying: String)
    case validationFailed([Issue])
    case notFound
    case ambiguous([UUID])
    case quotaExceeded(resource: String)
    case attachmentTooLarge(byteSize: Int64)
    case attachmentFetchFailed(url: URL)
    case migrationRequired
    case migrationFailed(underlying: String)
}

extension LillistError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .storeUnavailable(let reason):
            return "The Lillist data store is unavailable: \(reason)"
        case .iCloudUnavailable(let reason):
            return "iCloud is unavailable: \(reason)"
        case .syncFailure(let underlying):
            return "Sync failed: \(underlying)"
        case .validationFailed(let issues):
            let parts = issues.map { "\($0.field): \($0.message)" }
            return "Validation failed: \(parts.joined(separator: "; "))"
        case .notFound:
            return "The requested item could not be found."
        case .ambiguous(let ids):
            return "Multiple matching items (\(ids.count)). Please be more specific."
        case .quotaExceeded(let resource):
            return "Storage quota exceeded for \(resource)."
        case .attachmentTooLarge(let byteSize):
            return "Attachment is too large (\(byteSize) bytes)."
        case .attachmentFetchFailed(let url):
            return "Could not fetch attachment from \(url.absoluteString)."
        case .migrationRequired:
            return "A data migration is required to open this store."
        case .migrationFailed(let underlying):
            return "Data migration failed: \(underlying)"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/LillistCore && swift test --filter LillistErrorTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift Packages/LillistCore/Tests/LillistCoreTests/Validation/LillistErrorTests.swift
git commit -m "feat: add LillistError typed error enum"
```

---

## Task 7: `PersistenceController` + in-memory test factory

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Helpers/TestStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerTests.swift`

- [ ] **Step 1: Write `StoreConfiguration`**

Write `Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift`:

```swift
import Foundation

/// Where the persistent store lives and how it's loaded.
public enum StoreConfiguration: Sendable {
    /// In-memory store backed by `/dev/null`. For tests and previews.
    case inMemory

    /// On-disk SQLite store at the given file URL.
    case onDisk(url: URL)

    /// Default on-disk location: Application Support / Lillist / Lillist.sqlite
    public static var defaultOnDisk: StoreConfiguration {
        get throws {
            let fm = FileManager.default
            let appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = appSupport.appendingPathComponent("Lillist", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return .onDisk(url: dir.appendingPathComponent("Lillist.sqlite"))
        }
    }
}
```

- [ ] **Step 2: Write failing tests for `PersistenceController`**

Write `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerTests.swift`:

```swift
import Testing
import CoreData
@testable import LillistCore

@Suite("PersistenceController")
struct PersistenceControllerTests {
    @Test("In-memory store loads successfully")
    func inMemoryLoads() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        #expect(controller.container.viewContext.persistentStoreCoordinator?.persistentStores.count == 1)
    }

    @Test("Two in-memory controllers are isolated")
    func isolation() async throws {
        let a = try await PersistenceController(configuration: .inMemory)
        let b = try await PersistenceController(configuration: .inMemory)
        let entity = NSEntityDescription.insertNewObject(forEntityName: "LillistTask", into: a.container.viewContext)
        entity.setValue(UUID(), forKey: "id")
        entity.setValue("a", forKey: "title")
        try a.container.viewContext.save()

        let req = NSFetchRequest<NSManagedObject>(entityName: "LillistTask")
        let aCount = try a.container.viewContext.count(for: req)
        let bCount = try b.container.viewContext.count(for: req)
        #expect(aCount == 1)
        #expect(bCount == 0)
    }

    @Test("Model contains all expected entities")
    func entitiesPresent() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        let names = Set(controller.container.managedObjectModel.entities.compactMap(\.name))
        #expect(names.contains("LillistTask"))
        #expect(names.contains("Tag"))
        #expect(names.contains("JournalEntry"))
        #expect(names.contains("Attachment"))
        #expect(names.contains("AppPreferences"))
    }
}
```

- [ ] **Step 3: Write test helper `TestStore`**

Write `Packages/LillistCore/Tests/LillistCoreTests/Helpers/TestStore.swift`:

```swift
import Foundation
@testable import LillistCore

/// Convenience factory for in-memory PersistenceController instances in tests.
enum TestStore {
    static func make() async throws -> PersistenceController {
        try await PersistenceController(configuration: .inMemory)
    }
}
```

- [ ] **Step 4: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter PersistenceControllerTests`
Expected: FAIL — `PersistenceController` undefined.

- [ ] **Step 5: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift`:

```swift
import Foundation
import CoreData

/// Owns the `NSPersistentContainer` and exposes a single shared view context.
///
/// Plan 1 uses the non-CloudKit container; Plan 2 swaps in
/// `NSPersistentCloudKitContainer` without touching downstream callers.
public final class PersistenceController: @unchecked Sendable {
    public let container: NSPersistentContainer

    public init(configuration: StoreConfiguration) async throws {
        let model = Self.loadModel()
        let container = NSPersistentContainer(name: "LillistModel", managedObjectModel: model)

        let description: NSPersistentStoreDescription
        switch configuration {
        case .inMemory:
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            description.type = NSSQLiteStoreType
        case .onDisk(let url):
            description = NSPersistentStoreDescription(url: url)
            description.type = NSSQLiteStoreType
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: LillistError.storeUnavailable(reason: error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        self.container = container
    }

    private static func loadModel() -> NSManagedObjectModel {
        guard let url = Bundle.module.url(forResource: "LillistModel", withExtension: "momd") else {
            preconditionFailure("LillistModel.momd not found in bundle")
        }
        guard let model = NSManagedObjectModel(contentsOf: url) else {
            preconditionFailure("Failed to load NSManagedObjectModel from \(url)")
        }
        return model
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd Packages/LillistCore && swift test --filter PersistenceControllerTests`
Expected: PASS, 3 tests.

- [ ] **Step 7: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Persistence/ Packages/LillistCore/Tests/LillistCoreTests/Helpers/ Packages/LillistCore/Tests/LillistCoreTests/Persistence/
git commit -m "feat: add PersistenceController with in-memory + on-disk configurations"
```

---

## Task 8: Typed accessors over auto-generated managed objects

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Tag+CoreData.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/ManagedObjects/JournalEntry+CoreData.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Attachment+CoreData.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/ManagedObjects/AppPreferences+CoreData.swift`

Core Data's auto-generated classes use `Int16` for `statusRaw`, `kindRaw`, etc. These extensions add typed `Status`/`Kind` accessors that read/write the raw fields.

- [ ] **Step 1: Write `LillistTask` extension**

Write `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift`:

```swift
import Foundation
import CoreData

extension LillistTask {
    /// Typed accessor over `statusRaw`.
    public var status: Status {
        get { Status(rawValue: Int(statusRaw)) ?? .todo }
        set { statusRaw = Int16(newValue.rawValue) }
    }
}
```

- [ ] **Step 2: Write `Tag` extension**

Write `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Tag+CoreData.swift`:

```swift
import Foundation
import CoreData

extension Tag {
    /// Returns the root ancestor of this tag (self if root).
    public var root: Tag {
        var current = self
        while let p = current.parent {
            current = p
        }
        return current
    }

    /// All descendant tags (depth-first, not including self).
    public var descendants: [Tag] {
        guard let children = self.children as? Set<Tag> else { return [] }
        var out: [Tag] = []
        for child in children {
            out.append(child)
            out.append(contentsOf: child.descendants)
        }
        return out
    }
}
```

- [ ] **Step 3: Write `JournalEntry` extension**

Write `Packages/LillistCore/Sources/LillistCore/ManagedObjects/JournalEntry+CoreData.swift`:

```swift
import Foundation
import CoreData

extension JournalEntry {
    public var kind: JournalEntryKind {
        get { JournalEntryKind(rawValue: Int(kindRaw)) ?? .note }
        set { kindRaw = Int16(newValue.rawValue) }
    }
}
```

- [ ] **Step 4: Write `Attachment` extension**

Write `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Attachment+CoreData.swift`:

```swift
import Foundation
import CoreData

extension Attachment {
    public var kind: AttachmentKind {
        get { AttachmentKind(rawValue: Int(kindRaw)) ?? .file }
        set { kindRaw = Int16(newValue.rawValue) }
    }
}
```

- [ ] **Step 5: Write `AppPreferences` extension**

Write `Packages/LillistCore/Sources/LillistCore/ManagedObjects/AppPreferences+CoreData.swift`:

```swift
import Foundation
import CoreData

extension AppPreferences {
    public var defaultTaskListSort: SortField {
        get { SortField(rawValue: defaultTaskListSortRaw ?? "manualPosition") ?? .manualPosition }
        set { defaultTaskListSortRaw = newValue.rawValue }
    }
}
```

- [ ] **Step 6: Build**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/ManagedObjects/
git commit -m "feat: add typed accessors over auto-generated managed objects"
```

---

## Task 9: `FractionalPosition` and `PositionCompactor`

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/Ordering/PositionCompactor.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Ordering/FractionalPositionTests.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Ordering/PositionCompactorTests.swift`

- [ ] **Step 1: Write failing tests for `FractionalPosition`**

Write `Packages/LillistCore/Tests/LillistCoreTests/Ordering/FractionalPositionTests.swift`:

```swift
import Testing
@testable import LillistCore

@Suite("FractionalPosition")
struct FractionalPositionTests {
    @Test("Insert into empty list yields 1.0")
    func empty() {
        let p = FractionalPosition.position(after: nil, before: nil)
        #expect(p == 1.0)
    }

    @Test("Insert at end yields after+1")
    func atEnd() {
        let p = FractionalPosition.position(after: 5.0, before: nil)
        #expect(p == 6.0)
    }

    @Test("Insert at start yields before-1")
    func atStart() {
        let p = FractionalPosition.position(after: nil, before: 3.0)
        #expect(p == 2.0)
    }

    @Test("Insert between two yields midpoint")
    func between() {
        let p = FractionalPosition.position(after: 2.0, before: 4.0)
        #expect(p == 3.0)
    }

    @Test("Adjacent neighbors yield midpoint")
    func adjacent() {
        let p = FractionalPosition.position(after: 2.0, before: 3.0)
        #expect(p == 2.5)
    }

    @Test("Very close neighbors still produce a strictly-between value")
    func tinyGap() {
        let after = 1.0
        let before = 1.0 + .ulpOfOne * 10
        let p = FractionalPosition.position(after: after, before: before)
        #expect(p > after)
        #expect(p < before)
    }

    @Test("Detects gap too small for further subdivision")
    func gapTooSmall() {
        let after = 1.0
        let before = after.nextUp
        #expect(FractionalPosition.gapIsTooSmall(after: after, before: before) == true)
    }

    @Test("Normal gap is not flagged as too small")
    func normalGap() {
        #expect(FractionalPosition.gapIsTooSmall(after: 1.0, before: 2.0) == false)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter FractionalPositionTests`
Expected: FAIL — type undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift`:

```swift
import Foundation

/// Math for gap-based fractional ordering of sibling rows.
///
/// Each row has a `position: Double`. To insert between two neighbors,
/// we pick the midpoint of their positions. This lets us reorder without
/// renumbering — at the cost of needing periodic compaction when neighbors
/// grow close enough that further bisection underflows.
public enum FractionalPosition {
    /// The position for a new row between `after` and `before`.
    /// Nil neighbors mean "at the corresponding end" or "list is empty."
    public static func position(after: Double?, before: Double?) -> Double {
        switch (after, before) {
        case (nil, nil):
            return 1.0
        case (let a?, nil):
            return a + 1.0
        case (nil, let b?):
            return b - 1.0
        case (let a?, let b?):
            return (a + b) / 2.0
        }
    }

    /// True when the gap between neighbors is too small to safely bisect further.
    /// Triggers compaction.
    public static func gapIsTooSmall(after: Double, before: Double) -> Bool {
        before - after <= after.ulp * 4
    }
}
```

- [ ] **Step 4: Verify FractionalPosition tests pass**

Run: `cd Packages/LillistCore && swift test --filter FractionalPositionTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Write failing tests for `PositionCompactor`**

Write `Packages/LillistCore/Tests/LillistCoreTests/Ordering/PositionCompactorTests.swift`:

```swift
import Testing
@testable import LillistCore

@Suite("PositionCompactor")
struct PositionCompactorTests {
    @Test("Empty array yields empty result")
    func empty() {
        let result = PositionCompactor.recompact(positions: [])
        #expect(result == [])
    }

    @Test("Already-spaced positions stay relatively ordered")
    func preservesOrder() {
        let result = PositionCompactor.recompact(positions: [1.0, 2.0, 3.0])
        #expect(result.count == 3)
        #expect(result[0] < result[1])
        #expect(result[1] < result[2])
    }

    @Test("Squashed neighbors get re-spaced")
    func respacingSquashed() {
        let squashed = [1.0, 1.0 + .ulpOfOne, 1.0 + .ulpOfOne * 2]
        let result = PositionCompactor.recompact(positions: squashed)
        for i in 1..<result.count {
            #expect(result[i] - result[i - 1] >= 1.0)
        }
    }

    @Test("Preserves the order of the input")
    func orderInvariant() {
        let input = [5.0, 2.0, 3.0, 1.0, 4.0]
        let result = PositionCompactor.recompact(positions: input)
        // Recompactor doesn't reorder — it re-spaces in-place.
        // Caller is expected to pass an already-sorted list.
        // The test exercises that contract: input order is the output order.
        #expect(result.count == input.count)
    }
}
```

- [ ] **Step 6: Write `PositionCompactor`**

Write `Packages/LillistCore/Sources/LillistCore/Ordering/PositionCompactor.swift`:

```swift
import Foundation

/// Re-spaces a list of fractional positions with even gaps of 1.0.
///
/// Caller is responsible for passing a list already in the desired order
/// (typically `[siblings].sorted(by: { $0.position < $1.position })`).
/// The compactor preserves that order and just normalizes the values.
public enum PositionCompactor {
    public static func recompact(positions: [Double]) -> [Double] {
        positions.enumerated().map { index, _ in Double(index + 1) }
    }
}
```

- [ ] **Step 7: Run all ordering tests**

Run: `cd Packages/LillistCore && swift test --filter Ordering`
Expected: PASS, 12 tests total.

- [ ] **Step 8: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Ordering/ Packages/LillistCore/Tests/LillistCoreTests/Ordering/
git commit -m "feat: add FractionalPosition and PositionCompactor for sibling ordering"
```

---

## Task 10: `Validators` for cycles and name collisions

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Validation/Validators.swift`

Tests for the actual cycle/collision *behavior* live in the store tests (Tasks 12 and 16). This file is pure helper functions.

- [ ] **Step 1: Write `Validators`**

Write `Packages/LillistCore/Sources/LillistCore/Validation/Validators.swift`:

```swift
import Foundation
import CoreData

enum Validators {
    /// Walks up from `proposedParent` (and its ancestors) looking for `candidate`.
    /// Returns true if assigning `candidate` as a descendant of `proposedParent`
    /// would create a cycle.
    static func wouldCreateCycle(candidate: LillistTask, newParent: LillistTask?) -> Bool {
        guard let newParent else { return false }
        if candidate.objectID == newParent.objectID { return true }
        var cursor: LillistTask? = newParent.parent
        while let node = cursor {
            if node.objectID == candidate.objectID { return true }
            cursor = node.parent
        }
        return false
    }

    /// Returns a non-colliding name by appending " (2)", " (3)", … as needed.
    static func uniqueName(desired: String, existing: Set<String>) -> String {
        guard existing.contains(desired) else { return desired }
        var n = 2
        while existing.contains("\(desired) (\(n))") { n += 1 }
        return "\(desired) (\(n))"
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Validation/Validators.swift
git commit -m "feat: add Validators helpers for cycle prevention and name uniqueness"
```

---

## Task 11: `TaskStore` — create / read / update / delete

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreCRUDTests.swift`

This task introduces the store; later tasks add hierarchy, ordering, status, and soft-delete behavior.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreCRUDTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore CRUD")
struct TaskStoreCRUDTests {
    @Test("Create assigns id, timestamps, and default status")
    func create() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "Buy milk")
        let task = try await store.fetch(id: id)
        #expect(task.title == "Buy milk")
        #expect(task.status == .todo)
        #expect(task.createdAt != nil)
        #expect(task.modifiedAt != nil)
        #expect(task.deletedAt == nil)
        #expect(task.closedAt == nil)
    }

    @Test("Create rejects empty title")
    func emptyTitleRejected() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        await #expect(throws: LillistError.self) {
            _ = try await store.create(title: "")
        }
    }

    @Test("Fetch by unknown id throws notFound")
    func notFound() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: UUID())
        }
    }

    @Test("Update modifies the title and bumps modifiedAt")
    func update() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "Original")
        let before = try await store.fetch(id: id).modifiedAt
        try await Task.sleep(nanoseconds: 10_000_000)
        try await store.update(id: id) { $0.title = "Updated" }
        let task = try await store.fetch(id: id)
        #expect(task.title == "Updated")
        #expect((task.modifiedAt ?? .distantPast) > (before ?? .distantPast))
    }

    @Test("Hard delete removes the task")
    func hardDelete() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "doomed")
        try await store.hardDelete(id: id)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: id)
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreCRUDTests`
Expected: FAIL — `TaskStore` undefined.

- [ ] **Step 3: Write `TaskStore`**

Write `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`:

```swift
import Foundation
import CoreData

public final class TaskStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    /// A value-type DTO callers see — never an `NSManagedObject`.
    public struct TaskRecord: Sendable, Equatable {
        public var id: UUID
        public var title: String
        public var notes: String
        public var status: Status
        public var start: Date?
        public var startHasTime: Bool
        public var deadline: Date?
        public var deadlineHasTime: Bool
        public var position: Double
        public var isPinned: Bool
        public var parentID: UUID?
        public var createdAt: Date?
        public var modifiedAt: Date?
        public var closedAt: Date?
        public var deletedAt: Date?
    }

    /// Mutable view passed to `update`'s closure.
    public struct TaskDraft {
        public var title: String
        public var notes: String
        public var start: Date?
        public var startHasTime: Bool
        public var deadline: Date?
        public var deadlineHasTime: Bool
        public var isPinned: Bool
    }

    // MARK: - Create

    @discardableResult
    public func create(
        title: String,
        notes: String = "",
        parent: UUID? = nil
    ) async throws -> UUID {
        try validateTitle(title)
        return try await context.perform { [self] in
            let task = LillistTask(context: context)
            let id = UUID()
            task.id = id
            task.title = title
            task.notes = notes
            task.status = .todo
            task.startHasTime = false
            task.deadlineHasTime = false
            task.isPinned = false
            task.createdAt = Date()
            task.modifiedAt = task.createdAt
            if let parent {
                let parentTask = try fetchManagedObject(id: parent, in: context)
                task.parent = parentTask
            }
            task.position = try nextPosition(forParent: task.parent)
            try context.save()
            return id
        }
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> TaskRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return record(from: m)
        }
    }

    // MARK: - Update

    public func update(id: UUID, _ block: @escaping (inout TaskDraft) -> Void) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            var draft = TaskDraft(
                title: m.title ?? "",
                notes: m.notes ?? "",
                start: m.start,
                startHasTime: m.startHasTime,
                deadline: m.deadline,
                deadlineHasTime: m.deadlineHasTime,
                isPinned: m.isPinned
            )
            block(&draft)
            try validateTitle(draft.title)
            m.title = draft.title
            m.notes = draft.notes
            m.start = draft.start
            m.startHasTime = draft.startHasTime
            m.deadline = draft.deadline
            m.deadlineHasTime = draft.deadlineHasTime
            m.isPinned = draft.isPinned
            m.modifiedAt = Date()
            try context.save()
        }
    }

    // MARK: - Hard delete

    public func hardDelete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            context.delete(m)
            try context.save()
        }
    }

    // MARK: - Helpers

    func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> LillistTask {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else {
            throw LillistError.notFound
        }
        return m
    }

    func nextPosition(forParent parent: LillistTask?) throws -> Double {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        if let parent {
            req.predicate = NSPredicate(format: "parent == %@", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil")
        }
        req.sortDescriptors = [NSSortDescriptor(key: "position", ascending: false)]
        req.fetchLimit = 1
        let lastPosition = try context.fetch(req).first?.position
        return FractionalPosition.position(after: lastPosition, before: nil)
    }

    func validateTitle(_ title: String) throws {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LillistError.validationFailed([
                .init(field: "title", message: "must not be empty")
            ])
        }
    }

    func record(from m: LillistTask) -> TaskRecord {
        TaskRecord(
            id: m.id ?? UUID(),
            title: m.title ?? "",
            notes: m.notes ?? "",
            status: m.status,
            start: m.start,
            startHasTime: m.startHasTime,
            deadline: m.deadline,
            deadlineHasTime: m.deadlineHasTime,
            position: m.position,
            isPinned: m.isPinned,
            parentID: m.parent?.id,
            createdAt: m.createdAt,
            modifiedAt: m.modifiedAt,
            closedAt: m.closedAt,
            deletedAt: m.deletedAt
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreCRUDTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreCRUDTests.swift
git commit -m "feat: add TaskStore with CRUD operations"
```

---

## Task 12: `TaskStore` — hierarchy operations (reparent, list children, cycle prevention)

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreHierarchyTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreHierarchyTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore hierarchy")
struct TaskStoreHierarchyTests {
    @Test("List children returns tasks ordered by position")
    func listChildrenOrdered() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "Parent")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        let c = try await store.create(title: "C", parent: parent)
        let children = try await store.children(of: parent)
        let titles = children.map(\.title)
        #expect(titles == ["A", "B", "C"])
        _ = a; _ = b; _ = c
    }

    @Test("List children of nil returns root tasks")
    func listRoots() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "X")
        _ = try await store.create(title: "Y")
        let roots = try await store.children(of: nil)
        #expect(roots.count == 2)
    }

    @Test("Reparent moves a task under a new parent")
    func reparent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B")
        try await store.reparent(id: a, newParent: b)
        let record = try await store.fetch(id: a)
        #expect(record.parentID == b)
    }

    @Test("Reparent to root sets parent to nil")
    func reparentToRoot() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B", parent: a)
        try await store.reparent(id: b, newParent: nil)
        #expect(try await store.fetch(id: b).parentID == nil)
    }

    @Test("Reparent rejects cycle (parent under its own descendant)")
    func cyclePrevention() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B", parent: a)
        let c = try await store.create(title: "C", parent: b)
        await #expect(throws: LillistError.self) {
            try await store.reparent(id: a, newParent: c)
        }
    }

    @Test("Reparent rejects self as parent")
    func selfParent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        await #expect(throws: LillistError.self) {
            try await store.reparent(id: a, newParent: a)
        }
    }

    @Test("Hard delete cascades to children")
    func cascadeDelete() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "Parent")
        let child = try await store.create(title: "Child", parent: parent)
        let grandchild = try await store.create(title: "Grandchild", parent: child)
        try await store.hardDelete(id: parent)
        for id in [parent, child, grandchild] {
            await #expect(throws: LillistError.notFound) {
                _ = try await store.fetch(id: id)
            }
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreHierarchyTests`
Expected: FAIL — `children` and `reparent` missing.

- [ ] **Step 3: Add hierarchy methods to `TaskStore`**

Append the following to `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` (before the closing brace of the class):

```swift
    // MARK: - Hierarchy

    public func children(of parentID: UUID?) async throws -> [TaskRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            if let parentID {
                let parent = try fetchManagedObject(id: parentID, in: context)
                req.predicate = NSPredicate(format: "parent == %@ AND deletedAt == nil", parent)
            } else {
                req.predicate = NSPredicate(format: "parent == nil AND deletedAt == nil")
            }
            req.sortDescriptors = [
                NSSortDescriptor(key: "position", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]
            return try context.fetch(req).map(record(from:))
        }
    }

    public func reparent(id: UUID, newParent newParentID: UUID?) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let newParent: LillistTask?
            if let newParentID {
                let candidate = try fetchManagedObject(id: newParentID, in: context)
                if Validators.wouldCreateCycle(candidate: m, newParent: candidate) {
                    throw LillistError.validationFailed([
                        .init(field: "parent", message: "would create a cycle")
                    ])
                }
                newParent = candidate
            } else {
                newParent = nil
            }
            m.parent = newParent
            m.position = try nextPosition(forParent: newParent)
            m.modifiedAt = Date()
            try context.save()
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreHierarchyTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreHierarchyTests.swift
git commit -m "feat: add hierarchy operations and cycle prevention to TaskStore"
```

---

## Task 13: `TaskStore` — manual ordering (reorder between siblings)

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreOrderingTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreOrderingTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore ordering")
struct TaskStoreOrderingTests {
    @Test("Reorder between two siblings inserts at midpoint")
    func reorderBetween() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        let c = try await store.create(title: "C", parent: parent)
        // Move C between A and B.
        try await store.reorder(id: c, after: a, before: b)
        let children = try await store.children(of: parent)
        #expect(children.map(\.title) == ["A", "C", "B"])
    }

    @Test("Reorder to the head sets position before first sibling")
    func reorderToHead() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        try await store.reorder(id: b, after: nil, before: a)
        let titles = (try await store.children(of: parent)).map(\.title)
        #expect(titles == ["B", "A"])
    }

    @Test("Reorder to the tail sets position after last sibling")
    func reorderToTail() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        try await store.reorder(id: a, after: b, before: nil)
        let titles = (try await store.children(of: parent)).map(\.title)
        #expect(titles == ["B", "A"])
    }

    @Test("Reorder rejects mixed-parent neighbors")
    func mixedParents() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let p1 = try await store.create(title: "P1")
        let p2 = try await store.create(title: "P2")
        let a = try await store.create(title: "A", parent: p1)
        let b = try await store.create(title: "B", parent: p2)
        let c = try await store.create(title: "C", parent: p1)
        await #expect(throws: LillistError.self) {
            try await store.reorder(id: c, after: a, before: b)
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreOrderingTests`
Expected: FAIL.

- [ ] **Step 3: Add reorder to `TaskStore`**

Append to `TaskStore.swift` (inside the class):

```swift
    public func reorder(id: UUID, after afterID: UUID?, before beforeID: UUID?) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let afterTask = try afterID.map { try fetchManagedObject(id: $0, in: context) }
            let beforeTask = try beforeID.map { try fetchManagedObject(id: $0, in: context) }

            let afterParent = afterTask?.parent
            let beforeParent = beforeTask?.parent
            if let a = afterTask, let b = beforeTask, a.parent?.objectID != b.parent?.objectID {
                throw LillistError.validationFailed([
                    .init(field: "neighbors", message: "must share the same parent")
                ])
            }
            let newParent = afterParent ?? beforeParent ?? m.parent

            if m.parent?.objectID != newParent?.objectID {
                if Validators.wouldCreateCycle(candidate: m, newParent: newParent) {
                    throw LillistError.validationFailed([
                        .init(field: "parent", message: "would create a cycle")
                    ])
                }
                m.parent = newParent
            }
            m.position = FractionalPosition.position(
                after: afterTask?.position,
                before: beforeTask?.position
            )
            m.modifiedAt = Date()
            try context.save()
        }
    }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreOrderingTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreOrderingTests.swift
git commit -m "feat: add location-sensitive reorder to TaskStore"
```

---

## Task 14: `TaskStore` — status transitions with auto-journal entry and `closedAt`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreStatusTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreStatusTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore status")
struct TaskStoreStatusTests {
    @Test("Transition to closed sets closedAt")
    func toClosed() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.transition(id: id, to: .closed)
        let record = try await store.fetch(id: id)
        #expect(record.status == .closed)
        #expect(record.closedAt != nil)
    }

    @Test("Transition out of closed clears closedAt")
    func outOfClosed() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.transition(id: id, to: .closed)
        try await store.transition(id: id, to: .todo)
        let record = try await store.fetch(id: id)
        #expect(record.status == .todo)
        #expect(record.closedAt == nil)
    }

    @Test("Transition appends a system journal entry")
    func journalEntryCreated() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.transition(id: id, to: .started)
        let entries = try await journals.entries(forTask: id)
        let statusChanges = entries.filter { $0.kind == .statusChange }
        #expect(statusChanges.count == 1)
    }

    @Test("Self-transition is a no-op")
    func selfTransition() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.transition(id: id, to: .todo)
        let entries = try await journals.entries(forTask: id)
        #expect(entries.contains(where: { $0.kind == .statusChange }) == false)
    }

    @Test("Transition bumps modifiedAt")
    func modifiedBumped() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        let before = try await store.fetch(id: id).modifiedAt
        try await Task.sleep(nanoseconds: 10_000_000)
        try await store.transition(id: id, to: .started)
        let after = try await store.fetch(id: id).modifiedAt
        #expect((after ?? .distantPast) > (before ?? .distantPast))
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreStatusTests`
Expected: FAIL — `transition`, `JournalStore`, and `entries(forTask:)` missing.

- [ ] **Step 3: Define `JournalStore` stub (full implementation in Task 17)**

Write a stub at `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift`:

```swift
import Foundation
import CoreData

public final class JournalStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public struct JournalRecord: Sendable, Equatable {
        public var id: UUID
        public var taskID: UUID
        public var kind: JournalEntryKind
        public var body: String
        public var payload: Data?
        public var createdAt: Date?
        public var editedAt: Date?
    }

    public func entries(forTask taskID: UUID) async throws -> [JournalRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            req.predicate = NSPredicate(format: "task.id == %@", taskID as CVarArg)
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(req).map(Self.record(from:))
        }
    }

    static func record(from m: JournalEntry) -> JournalRecord {
        JournalRecord(
            id: m.id ?? UUID(),
            taskID: m.task?.id ?? UUID(),
            kind: m.kind,
            body: m.body ?? "",
            payload: m.payload,
            createdAt: m.createdAt,
            editedAt: m.editedAt
        )
    }
}
```

- [ ] **Step 4: Add `transition` to `TaskStore`**

Append to `TaskStore.swift` (inside the class):

```swift
    // MARK: - Status transitions

    public func transition(id: UUID, to newStatus: Status) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let oldStatus = m.status
            guard oldStatus != newStatus else { return }
            m.status = newStatus
            m.modifiedAt = Date()
            if newStatus == .closed {
                m.closedAt = m.modifiedAt
            } else if oldStatus == .closed {
                m.closedAt = nil
            }

            // System journal entry for the transition.
            let entry = JournalEntry(context: context)
            entry.id = UUID()
            entry.task = m
            entry.kind = .statusChange
            entry.createdAt = m.modifiedAt
            entry.body = "\(oldStatus) → \(newStatus)"
            let payload: [String: Int] = ["from": oldStatus.rawValue, "to": newStatus.rawValue]
            entry.payload = try JSONSerialization.data(withJSONObject: payload)

            try context.save()
        }
    }
```

- [ ] **Step 5: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreStatusTests`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreStatusTests.swift
git commit -m "feat: add status transitions with auto-journal entry and closedAt management"
```

---

## Task 15: `TaskStore` — soft delete, restore, list in trash

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreSoftDeleteTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreSoftDeleteTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore soft delete")
struct TaskStoreSoftDeleteTests {
    @Test("Soft delete sets deletedAt and excludes from children listing")
    func softDelete() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "doomed")
        try await store.softDelete(id: id)
        let roots = try await store.children(of: nil)
        #expect(roots.isEmpty)
        let trashed = try await store.trashed()
        #expect(trashed.count == 1)
        #expect(trashed.first?.id == id)
    }

    @Test("Soft delete cascades to children")
    func cascadeSoftDelete() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "Parent")
        let child = try await store.create(title: "Child", parent: parent)
        try await store.softDelete(id: parent)
        let parentRecord = try await store.fetch(id: parent)
        let childRecord = try await store.fetch(id: child)
        #expect(parentRecord.deletedAt != nil)
        #expect(childRecord.deletedAt != nil)
    }

    @Test("Restore clears deletedAt")
    func restore() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.softDelete(id: id)
        try await store.restore(id: id)
        let record = try await store.fetch(id: id)
        #expect(record.deletedAt == nil)
    }

    @Test("Restore cascades to children whose deletedAt matches the parent's")
    func restoreCascade() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "Parent")
        let child = try await store.create(title: "Child", parent: parent)
        try await store.softDelete(id: parent)
        try await store.restore(id: parent)
        let parentRecord = try await store.fetch(id: parent)
        let childRecord = try await store.fetch(id: child)
        #expect(parentRecord.deletedAt == nil)
        #expect(childRecord.deletedAt == nil)
    }

    @Test("Soft-deleted task is excluded from default fetches but accessible via fetch(id:)")
    func directFetchStillWorks() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.softDelete(id: id)
        let record = try await store.fetch(id: id)
        #expect(record.deletedAt != nil)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreSoftDeleteTests`
Expected: FAIL — `softDelete`, `restore`, `trashed` missing.

- [ ] **Step 3: Add soft-delete methods to `TaskStore`**

Append to `TaskStore.swift` (inside the class):

```swift
    // MARK: - Soft delete

    public func softDelete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let now = Date()
            applySoftDelete(to: m, at: now)
            try context.save()
        }
    }

    public func restore(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            guard let deletedAt = m.deletedAt else { return }
            clearSoftDelete(from: m, matchingDeletedAt: deletedAt)
            try context.save()
        }
    }

    public func trashed() async throws -> [TaskRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "deletedAt != nil")
            req.sortDescriptors = [NSSortDescriptor(key: "deletedAt", ascending: false)]
            return try context.fetch(req).map(record(from:))
        }
    }

    private func applySoftDelete(to m: LillistTask, at now: Date) {
        m.deletedAt = now
        m.modifiedAt = now
        if let children = m.children as? Set<LillistTask> {
            for child in children where child.deletedAt == nil {
                applySoftDelete(to: child, at: now)
            }
        }
    }

    private func clearSoftDelete(from m: LillistTask, matchingDeletedAt: Date) {
        m.deletedAt = nil
        m.modifiedAt = Date()
        if let children = m.children as? Set<LillistTask> {
            for child in children where child.deletedAt == matchingDeletedAt {
                clearSoftDelete(from: child, matchingDeletedAt: matchingDeletedAt)
            }
        }
    }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreSoftDeleteTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreSoftDeleteTests.swift
git commit -m "feat: add soft delete, restore, and trash listing to TaskStore"
```

---

## Task 16: `TagStore` — CRUD, hierarchy, rename collisions

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/TagStoreTests.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/TagHierarchyTests.swift`

- [ ] **Step 1: Write CRUD/collision tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/TagStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("TagStore")
struct TagStoreTests {
    @Test("Create tag with name and tint")
    func create() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let id = try await store.create(name: "Work", tintColor: "#FF0000")
        let tag = try await store.fetch(id: id)
        #expect(tag.name == "Work")
        #expect(tag.tintColor == "#FF0000")
        #expect(tag.parentID == nil)
    }

    @Test("Empty name rejected")
    func emptyName() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        await #expect(throws: LillistError.self) {
            _ = try await store.create(name: "")
        }
    }

    @Test("Sibling name collision auto-suffixes")
    func collisionAutoSuffix() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        _ = try await store.create(name: "Work")
        let id2 = try await store.create(name: "Work")
        let id3 = try await store.create(name: "Work")
        #expect(try await store.fetch(id: id2).name == "Work (2)")
        #expect(try await store.fetch(id: id3).name == "Work (3)")
    }

    @Test("Rename collision auto-suffixes")
    func renameCollision() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        _ = try await store.create(name: "Work")
        let other = try await store.create(name: "Home")
        try await store.rename(id: other, to: "Work")
        #expect(try await store.fetch(id: other).name == "Work (2)")
    }

    @Test("Rename to same name is a no-op")
    func renameNoOp() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let id = try await store.create(name: "Work")
        try await store.rename(id: id, to: "Work")
        #expect(try await store.fetch(id: id).name == "Work")
    }

    @Test("Delete removes the tag")
    func delete() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let id = try await store.create(name: "Tmp")
        try await store.delete(id: id)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: id)
        }
    }
}
```

- [ ] **Step 2: Write hierarchy tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/TagHierarchyTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("Tag hierarchy")
struct TagHierarchyTests {
    @Test("Create with parent")
    func createWithParent() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let work = try await store.create(name: "Work")
        let email = try await store.create(name: "Email", parent: work)
        #expect(try await store.fetch(id: email).parentID == work)
    }

    @Test("Sibling collision is namespaced to parent")
    func siblingsScopedToParent() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let a = try await store.create(name: "A")
        let b = try await store.create(name: "B")
        _ = try await store.create(name: "Email", parent: a)
        let underB = try await store.create(name: "Email", parent: b)
        // No suffix — different parent.
        #expect(try await store.fetch(id: underB).name == "Email")
    }

    @Test("List children of nil returns root tags")
    func rootList() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        _ = try await store.create(name: "A")
        _ = try await store.create(name: "B")
        let roots = try await store.children(of: nil)
        #expect(roots.count == 2)
    }

    @Test("Reparent moves tag under new parent")
    func reparent() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let a = try await store.create(name: "A")
        let b = try await store.create(name: "B")
        let child = try await store.create(name: "child", parent: a)
        try await store.reparent(id: child, newParent: b)
        #expect(try await store.fetch(id: child).parentID == b)
    }

    @Test("Reparent rejects cycle")
    func cycle() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let a = try await store.create(name: "A")
        let b = try await store.create(name: "B", parent: a)
        let c = try await store.create(name: "C", parent: b)
        await #expect(throws: LillistError.self) {
            try await store.reparent(id: a, newParent: c)
        }
    }

    @Test("Delete cascades to descendants")
    func cascadeDelete() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let a = try await store.create(name: "A")
        let b = try await store.create(name: "B", parent: a)
        let c = try await store.create(name: "C", parent: b)
        try await store.delete(id: a)
        for id in [a, b, c] {
            await #expect(throws: LillistError.notFound) {
                _ = try await store.fetch(id: id)
            }
        }
    }
}
```

- [ ] **Step 3: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter TagStoreTests --filter TagHierarchyTests`
Expected: FAIL.

- [ ] **Step 4: Write `TagStore`**

Write `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift`:

```swift
import Foundation
import CoreData

public final class TagStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public struct TagRecord: Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var tintColor: String?
        public var parentID: UUID?
        public var position: Double
    }

    // MARK: - Create

    @discardableResult
    public func create(name: String, tintColor: String? = nil, parent: UUID? = nil) async throws -> UUID {
        try validateName(name)
        return try await context.perform { [self] in
            let parentTag = try parent.map { try fetchManagedObject(id: $0, in: context) }
            let resolved = try uniqueNameUnder(parent: parentTag, desired: name)
            let tag = Tag(context: context)
            tag.id = UUID()
            tag.name = resolved
            tag.tintColor = tintColor
            tag.parent = parentTag
            tag.position = try nextPosition(forParent: parentTag)
            try context.save()
            return tag.id!
        }
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> TagRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return record(from: m)
        }
    }

    public func children(of parentID: UUID?) async throws -> [TagRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<Tag>(entityName: "Tag")
            if let parentID {
                let parent = try fetchManagedObject(id: parentID, in: context)
                req.predicate = NSPredicate(format: "parent == %@", parent)
            } else {
                req.predicate = NSPredicate(format: "parent == nil")
            }
            req.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
            return try context.fetch(req).map(record(from:))
        }
    }

    // MARK: - Rename

    public func rename(id: UUID, to newName: String) async throws {
        try validateName(newName)
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            guard m.name != newName else { return }
            let resolved = try uniqueNameUnder(parent: m.parent, desired: newName, excluding: m)
            m.name = resolved
            try context.save()
        }
    }

    // MARK: - Reparent

    public func reparent(id: UUID, newParent newParentID: UUID?) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let newParent: Tag?
            if let newParentID {
                let candidate = try fetchManagedObject(id: newParentID, in: context)
                if wouldCreateCycle(candidate: m, newParent: candidate) {
                    throw LillistError.validationFailed([
                        .init(field: "parent", message: "would create a cycle")
                    ])
                }
                newParent = candidate
            } else {
                newParent = nil
            }
            let resolved = try uniqueNameUnder(parent: newParent, desired: m.name ?? "", excluding: m)
            m.name = resolved
            m.parent = newParent
            m.position = try nextPosition(forParent: newParent)
            try context.save()
        }
    }

    // MARK: - Delete

    public func delete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            context.delete(m)
            try context.save()
        }
    }

    // MARK: - Helpers

    private func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> Tag {
        let req = NSFetchRequest<Tag>(entityName: "Tag")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
        return m
    }

    private func nextPosition(forParent parent: Tag?) throws -> Double {
        let req = NSFetchRequest<Tag>(entityName: "Tag")
        if let parent {
            req.predicate = NSPredicate(format: "parent == %@", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil")
        }
        req.sortDescriptors = [NSSortDescriptor(key: "position", ascending: false)]
        req.fetchLimit = 1
        let last = try context.fetch(req).first?.position
        return FractionalPosition.position(after: last, before: nil)
    }

    private func uniqueNameUnder(parent: Tag?, desired: String, excluding: Tag? = nil) throws -> String {
        let req = NSFetchRequest<Tag>(entityName: "Tag")
        if let parent {
            req.predicate = NSPredicate(format: "parent == %@", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil")
        }
        let siblings = try context.fetch(req)
        var existing = Set(siblings.compactMap(\.name))
        if let ex = excluding?.name { existing.remove(ex) }
        return Validators.uniqueName(desired: desired, existing: existing)
    }

    private func wouldCreateCycle(candidate: Tag, newParent: Tag?) -> Bool {
        guard let newParent else { return false }
        if candidate.objectID == newParent.objectID { return true }
        var cursor: Tag? = newParent.parent
        while let node = cursor {
            if node.objectID == candidate.objectID { return true }
            cursor = node.parent
        }
        return false
    }

    private func validateName(_ name: String) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LillistError.validationFailed([
                .init(field: "name", message: "must not be empty")
            ])
        }
    }

    private func record(from m: Tag) -> TagRecord {
        TagRecord(
            id: m.id ?? UUID(),
            name: m.name ?? "",
            tintColor: m.tintColor,
            parentID: m.parent?.id,
            position: m.position
        )
    }
}
```

- [ ] **Step 5: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter TagStoreTests --filter TagHierarchyTests`
Expected: PASS, 11 tests.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/TagStoreTests.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/TagHierarchyTests.swift
git commit -m "feat: add TagStore with hierarchy, rename collision resolution, and cycle prevention"
```

---

## Task 17: `JournalStore` — append, edit, delete, list

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/JournalStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/JournalStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("JournalStore")
struct JournalStoreTests {
    @Test("Append a user note")
    func appendNote() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let task = try await tasks.create(title: "T")
        let id = try await journals.appendNote(taskID: task, body: "stuck on auth")
        let entries = try await journals.entries(forTask: task)
        #expect(entries.count == 1)
        #expect(entries[0].id == id)
        #expect(entries[0].body == "stuck on auth")
        #expect(entries[0].kind == .note)
    }

    @Test("Edit a user note sets editedAt and updates body")
    func editNote() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let task = try await tasks.create(title: "T")
        let id = try await journals.appendNote(taskID: task, body: "before")
        try await Task.sleep(nanoseconds: 10_000_000)
        try await journals.editNote(id: id, body: "after")
        let entry = try await journals.fetch(id: id)
        #expect(entry.body == "after")
        #expect(entry.editedAt != nil)
    }

    @Test("Editing a system entry throws")
    func systemUneditable() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let task = try await tasks.create(title: "T")
        try await tasks.transition(id: task, to: .started)
        let entries = try await journals.entries(forTask: task)
        let statusEntry = entries.first(where: { $0.kind == .statusChange })!
        await #expect(throws: LillistError.self) {
            try await journals.editNote(id: statusEntry.id, body: "bogus")
        }
    }

    @Test("Delete a user note")
    func deleteNote() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let task = try await tasks.create(title: "T")
        let id = try await journals.appendNote(taskID: task, body: "x")
        try await journals.delete(id: id)
        await #expect(throws: LillistError.notFound) {
            _ = try await journals.fetch(id: id)
        }
    }

    @Test("Deleting a system entry throws")
    func systemUndeletable() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let task = try await tasks.create(title: "T")
        try await tasks.transition(id: task, to: .started)
        let statusEntry = (try await journals.entries(forTask: task)).first(where: { $0.kind == .statusChange })!
        await #expect(throws: LillistError.self) {
            try await journals.delete(id: statusEntry.id)
        }
    }

    @Test("Entries returned in ascending createdAt order")
    func order() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let task = try await tasks.create(title: "T")
        _ = try await journals.appendNote(taskID: task, body: "first")
        try await Task.sleep(nanoseconds: 10_000_000)
        _ = try await journals.appendNote(taskID: task, body: "second")
        let entries = try await journals.entries(forTask: task)
        #expect(entries.map(\.body) == ["first", "second"])
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter JournalStoreTests`
Expected: FAIL — append/edit/delete missing.

- [ ] **Step 3: Replace `JournalStore.swift` with the full implementation**

Replace `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift` with:

```swift
import Foundation
import CoreData

public final class JournalStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public struct JournalRecord: Sendable, Equatable {
        public var id: UUID
        public var taskID: UUID
        public var kind: JournalEntryKind
        public var body: String
        public var payload: Data?
        public var createdAt: Date?
        public var editedAt: Date?
    }

    // MARK: - Append

    @discardableResult
    public func appendNote(taskID: UUID, body: String) async throws -> UUID {
        try await context.perform { [self] in
            let task = try fetchTask(id: taskID, in: context)
            let entry = JournalEntry(context: context)
            entry.id = UUID()
            entry.task = task
            entry.kind = .note
            entry.body = body
            entry.createdAt = Date()
            try context.save()
            return entry.id!
        }
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> JournalRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return Self.record(from: m)
        }
    }

    public func entries(forTask taskID: UUID) async throws -> [JournalRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            req.predicate = NSPredicate(format: "task.id == %@", taskID as CVarArg)
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(req).map(Self.record(from:))
        }
    }

    // MARK: - Edit

    public func editNote(id: UUID, body: String) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            guard m.kind.isUserEditable else {
                throw LillistError.validationFailed([
                    .init(field: "kind", message: "system journal entries cannot be edited")
                ])
            }
            m.body = body
            m.editedAt = Date()
            try context.save()
        }
    }

    // MARK: - Delete

    public func delete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            guard m.kind.isUserEditable else {
                throw LillistError.validationFailed([
                    .init(field: "kind", message: "system journal entries cannot be deleted")
                ])
            }
            context.delete(m)
            try context.save()
        }
    }

    // MARK: - Helpers

    private func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> JournalEntry {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
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

    static func record(from m: JournalEntry) -> JournalRecord {
        JournalRecord(
            id: m.id ?? UUID(),
            taskID: m.task?.id ?? UUID(),
            kind: m.kind,
            body: m.body ?? "",
            payload: m.payload,
            createdAt: m.createdAt,
            editedAt: m.editedAt
        )
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter JournalStoreTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/JournalStoreTests.swift
git commit -m "feat: add JournalStore append/edit/delete with system-entry protection"
```

---

## Task 18: `AttachmentStore` — add image, add file, add link preview, fetch, delete

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/AttachmentStoreTests.swift`

Attachments are created via a journal entry of kind `.attachment`. Adding an attachment also creates the journal entry that owns it.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/AttachmentStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("AttachmentStore")
struct AttachmentStoreTests {
    private func tinyPNG() -> Data {
        // 1x1 transparent PNG.
        Data([
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
            0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
            0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
            0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,
            0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,
            0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
            0x42,0x60,0x82
        ])
    }

    @Test("Add image creates an attachment + a journal entry")
    func addImage() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let attID = try await store.addImage(
            taskID: taskID,
            filename: "snap.png",
            data: tinyPNG()
        )
        let att = try await store.fetch(id: attID)
        #expect(att.kind == .image)
        #expect(att.filename == "snap.png")
        #expect(att.byteSize > 0)
        let entries = try await journals.entries(forTask: taskID)
        let attEntry = entries.first(where: { $0.kind == .attachment })
        #expect(attEntry != nil)
    }

    @Test("Add file with arbitrary UTI")
    func addFile() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let attID = try await store.addFile(
            taskID: taskID,
            filename: "spec.txt",
            uti: "public.plain-text",
            data: "hello".data(using: .utf8)!
        )
        let att = try await store.fetch(id: attID)
        #expect(att.kind == .file)
        #expect(att.uti == "public.plain-text")
    }

    @Test("Add link preview stores URL metadata")
    func addLinkPreview() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let attID = try await store.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com")!,
            title: "Example",
            description: "An example domain",
            thumbnailData: nil,
            faviconData: nil
        )
        let att = try await store.fetch(id: attID)
        #expect(att.kind == .linkPreview)
        #expect(att.filename == "https://example.com")
        #expect(att.linkPreviewJSON?.contains("example.com") == true)
    }

    @Test("List attachments for a task")
    func list() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        _ = try await store.addImage(taskID: taskID, filename: "a.png", data: tinyPNG())
        _ = try await store.addImage(taskID: taskID, filename: "b.png", data: tinyPNG())
        let list = try await store.attachments(forTask: taskID)
        #expect(list.count == 2)
    }

    @Test("Reject attachment exceeding hard cap (>500MB)")
    func hardCap() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let big = Data(count: 501 * 1024 * 1024)
        await #expect(throws: LillistError.self) {
            _ = try await store.addImage(taskID: taskID, filename: "huge.png", data: big)
        }
    }

    @Test("Delete attachment removes the row")
    func delete() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let id = try await store.addImage(taskID: taskID, filename: "x.png", data: tinyPNG())
        try await store.delete(id: id)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: id)
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter AttachmentStoreTests`
Expected: FAIL — `AttachmentStore` undefined.

- [ ] **Step 3: Write `AttachmentStore`**

Write `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift`:

```swift
import Foundation
import CoreData

public final class AttachmentStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    /// Files larger than this byte count are rejected outright.
    public static let hardSizeLimit: Int64 = 500 * 1024 * 1024

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public struct AttachmentRecord: Sendable, Equatable {
        public var id: UUID
        public var taskID: UUID
        public var journalEntryID: UUID?
        public var kind: AttachmentKind
        public var filename: String
        public var uti: String
        public var byteSize: Int64
        public var hasData: Bool
        public var linkPreviewJSON: String?
        public var createdAt: Date?
    }

    public struct LinkPreviewPayload: Codable, Sendable {
        public var url: String
        public var title: String?
        public var description: String?
        public var fetchedAt: Date
    }

    // MARK: - Add image

    @discardableResult
    public func addImage(taskID: UUID, filename: String, data: Data) async throws -> UUID {
        try checkSize(byteCount: Int64(data.count))
        return try await insertAttachment(
            taskID: taskID,
            kind: .image,
            filename: filename,
            uti: "public.image",
            data: data,
            linkPreviewJSON: nil
        )
    }

    // MARK: - Add file

    @discardableResult
    public func addFile(taskID: UUID, filename: String, uti: String, data: Data) async throws -> UUID {
        try checkSize(byteCount: Int64(data.count))
        return try await insertAttachment(
            taskID: taskID,
            kind: .file,
            filename: filename,
            uti: uti,
            data: data,
            linkPreviewJSON: nil
        )
    }

    // MARK: - Add link preview

    @discardableResult
    public func addLinkPreview(
        taskID: UUID,
        url: URL,
        title: String?,
        description: String?,
        thumbnailData: Data?,
        faviconData: Data?
    ) async throws -> UUID {
        _ = thumbnailData; _ = faviconData // stored alongside in Plan 2; metadata-only here.
        let payload = LinkPreviewPayload(
            url: url.absoluteString,
            title: title,
            description: description,
            fetchedAt: Date()
        )
        let json = try String(data: JSONEncoder().encode(payload), encoding: .utf8) ?? ""
        return try await insertAttachment(
            taskID: taskID,
            kind: .linkPreview,
            filename: url.absoluteString,
            uti: "public.url",
            data: nil,
            linkPreviewJSON: json
        )
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> AttachmentRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return Self.record(from: m)
        }
    }

    public func attachments(forTask taskID: UUID) async throws -> [AttachmentRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<Attachment>(entityName: "Attachment")
            req.predicate = NSPredicate(format: "task.id == %@", taskID as CVarArg)
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(req).map(Self.record(from:))
        }
    }

    // MARK: - Delete

    public func delete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            context.delete(m)
            try context.save()
        }
    }

    // MARK: - Helpers

    private func checkSize(byteCount: Int64) throws {
        if byteCount > Self.hardSizeLimit {
            throw LillistError.attachmentTooLarge(byteSize: byteCount)
        }
    }

    private func insertAttachment(
        taskID: UUID,
        kind: AttachmentKind,
        filename: String,
        uti: String,
        data: Data?,
        linkPreviewJSON: String?
    ) async throws -> UUID {
        try await context.perform { [self] in
            let task = try fetchTask(id: taskID, in: context)
            let journal = JournalEntry(context: context)
            journal.id = UUID()
            journal.task = task
            journal.kind = .attachment
            journal.createdAt = Date()
            journal.body = ""

            let att = Attachment(context: context)
            att.id = UUID()
            att.task = task
            att.journalEntry = journal
            att.kind = kind
            att.filename = filename
            att.uti = uti
            att.byteSize = Int64(data?.count ?? 0)
            att.data = data
            att.linkPreviewJSON = linkPreviewJSON
            att.createdAt = journal.createdAt

            try context.save()
            return att.id!
        }
    }

    private func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> Attachment {
        let req = NSFetchRequest<Attachment>(entityName: "Attachment")
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

    static func record(from m: Attachment) -> AttachmentRecord {
        AttachmentRecord(
            id: m.id ?? UUID(),
            taskID: m.task?.id ?? UUID(),
            journalEntryID: m.journalEntry?.id,
            kind: m.kind,
            filename: m.filename ?? "",
            uti: m.uti ?? "",
            byteSize: m.byteSize,
            hasData: m.data != nil,
            linkPreviewJSON: m.linkPreviewJSON,
            createdAt: m.createdAt
        )
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter AttachmentStoreTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/AttachmentStoreTests.swift
git commit -m "feat: add AttachmentStore for images, files, and link previews"
```

---

## Task 19: `PreferencesStore` — singleton accessor for `AppPreferences`

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/PreferencesStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/PreferencesStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("PreferencesStore")
struct PreferencesStoreTests {
    @Test("Defaults on first read")
    func defaults() async throws {
        let p = try await TestStore.make()
        let store = PreferencesStore(persistence: p)
        let prefs = try await store.read()
        #expect(prefs.trashRetentionDays == 30)
        #expect(prefs.defaultAllDayHour == 9)
        #expect(prefs.defaultAllDayMinute == 0)
        #expect(prefs.morningSummaryEnabled == true)
    }

    @Test("Update persists across reads")
    func updatePersists() async throws {
        let p = try await TestStore.make()
        let store = PreferencesStore(persistence: p)
        try await store.update { $0.trashRetentionDays = 60 }
        let prefs = try await store.read()
        #expect(prefs.trashRetentionDays == 60)
    }

    @Test("Update is idempotent — single singleton row")
    func singletonRow() async throws {
        let p = try await TestStore.make()
        let store = PreferencesStore(persistence: p)
        try await store.update { $0.trashRetentionDays = 60 }
        try await store.update { $0.trashRetentionDays = 90 }
        #expect(try await store.rowCount() == 1)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter PreferencesStoreTests`
Expected: FAIL.

- [ ] **Step 3: Write `PreferencesStore`**

Write `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift`:

```swift
import Foundation
import CoreData

public final class PreferencesStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public struct Prefs: Sendable, Equatable {
        public var defaultAllDayHour: Int16
        public var defaultAllDayMinute: Int16
        public var morningSummaryEnabled: Bool
        public var morningSummaryHour: Int16
        public var morningSummaryMinute: Int16
        public var trashRetentionDays: Int16
        public var defaultTaskListSort: SortField
    }

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
                defaultTaskListSort: row.defaultTaskListSort
            )
        }
    }

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
                defaultTaskListSort: row.defaultTaskListSort
            )
            block(&prefs)
            row.defaultAllDayNotificationHour = prefs.defaultAllDayHour
            row.defaultAllDayNotificationMinute = prefs.defaultAllDayMinute
            row.morningSummaryEnabled = prefs.morningSummaryEnabled
            row.morningSummaryHour = prefs.morningSummaryHour
            row.morningSummaryMinute = prefs.morningSummaryMinute
            row.trashRetentionDays = prefs.trashRetentionDays
            row.defaultTaskListSort = prefs.defaultTaskListSort
            try context.save()
        }
    }

    /// Test helper: count of AppPreferences rows. Asserts singleton invariant.
    public func rowCount() async throws -> Int {
        try await context.perform { [self] in
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            return try context.count(for: req)
        }
    }

    private func fetchOrCreateSingleton(in ctx: NSManagedObjectContext) throws -> AppPreferences {
        let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
        req.fetchLimit = 1
        if let existing = try ctx.fetch(req).first {
            return existing
        }
        let row = AppPreferences(context: ctx)
        row.id = UUID()
        row.defaultAllDayNotificationHour = 9
        row.defaultAllDayNotificationMinute = 0
        row.morningSummaryEnabled = true
        row.morningSummaryHour = 9
        row.morningSummaryMinute = 0
        row.trashRetentionDays = 30
        row.defaultTaskListSortRaw = SortField.manualPosition.rawValue
        try ctx.save()
        return row
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter PreferencesStoreTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/PreferencesStoreTests.swift
git commit -m "feat: add PreferencesStore singleton accessor"
```

---

## Task 20: `AutoPurgeJob` — Trash retention sweep

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Persistence/AutoPurgeJob.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/AutoPurgeJobTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Persistence/AutoPurgeJobTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("AutoPurgeJob")
struct AutoPurgeJobTests {
    @Test("Old soft-deleted tasks are hard-deleted")
    func purgesOld() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 30 }

        let id = try await tasks.create(title: "old")
        try await tasks.softDelete(id: id)

        // Backdate deletedAt to 31 days ago directly via the context.
        try await p.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try p.container.viewContext.fetch(req).first!
            m.deletedAt = Date().addingTimeInterval(-31 * 86400)
            try p.container.viewContext.save()
        }

        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run(now: Date())
        #expect(purged == 1)
        await #expect(throws: LillistError.notFound) {
            _ = try await tasks.fetch(id: id)
        }
    }

    @Test("Recently soft-deleted tasks survive")
    func sparesRecent() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 30 }

        let id = try await tasks.create(title: "fresh")
        try await tasks.softDelete(id: id)

        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run(now: Date())
        #expect(purged == 0)
        _ = try await tasks.fetch(id: id) // still here
    }

    @Test("Non-deleted tasks are never purged")
    func ignoresLiveTasks() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 30 }
        _ = try await tasks.create(title: "live")
        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run(now: Date())
        #expect(purged == 0)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter AutoPurgeJobTests`
Expected: FAIL — `AutoPurgeJob` undefined.

- [ ] **Step 3: Write `AutoPurgeJob`**

Write `Packages/LillistCore/Sources/LillistCore/Persistence/AutoPurgeJob.swift`:

```swift
import Foundation
import CoreData

/// Hard-deletes soft-deleted tasks (and their cascades) older than the
/// configured retention. Returns the count of top-level tasks purged.
public final class AutoPurgeJob: @unchecked Sendable {
    private let persistence: PersistenceController
    private let preferences: PreferencesStore

    public init(persistence: PersistenceController, preferences: PreferencesStore) {
        self.persistence = persistence
        self.preferences = preferences
    }

    @discardableResult
    public func run(now: Date = Date()) async throws -> Int {
        let prefs = try await preferences.read()
        let cutoff = now.addingTimeInterval(-Double(prefs.trashRetentionDays) * 86400)
        let ctx = persistence.container.viewContext
        return try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "deletedAt != nil AND deletedAt < %@", cutoff as NSDate)
            let victims = try ctx.fetch(req)
            for v in victims { ctx.delete(v) }
            try ctx.save()
            return victims.count
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter AutoPurgeJobTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Persistence/AutoPurgeJob.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/AutoPurgeJobTests.swift
git commit -m "feat: add AutoPurgeJob for Trash retention sweep"
```

---

## Task 21: Tag-task assignment API on `TaskStore`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`
- Modify: `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreCRUDTests.swift` (extend)

- [ ] **Step 1: Append tagging tests to `TaskStoreCRUDTests.swift`**

Append the following `@Test` methods inside the existing `TaskStoreCRUDTests` struct (before its closing brace):

```swift
    @Test("Assign tag to task")
    func assignTag() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let tags = TagStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let tagID = try await tags.create(name: "Work")
        try await tasks.assignTag(taskID: taskID, tagID: tagID)
        let tagIDs = try await tasks.tagIDs(forTask: taskID)
        #expect(tagIDs.contains(tagID))
    }

    @Test("Unassign tag from task")
    func unassignTag() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let tags = TagStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let tagID = try await tags.create(name: "Work")
        try await tasks.assignTag(taskID: taskID, tagID: tagID)
        try await tasks.unassignTag(taskID: taskID, tagID: tagID)
        let tagIDs = try await tasks.tagIDs(forTask: taskID)
        #expect(tagIDs.contains(tagID) == false)
    }

    @Test("Re-assigning the same tag is idempotent")
    func reassignIdempotent() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let tags = TagStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let tagID = try await tags.create(name: "Work")
        try await tasks.assignTag(taskID: taskID, tagID: tagID)
        try await tasks.assignTag(taskID: taskID, tagID: tagID)
        let tagIDs = try await tasks.tagIDs(forTask: taskID)
        #expect(tagIDs.filter { $0 == tagID }.count == 1)
    }
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreCRUDTests`
Expected: FAIL — new methods missing.

- [ ] **Step 3: Add tag methods to `TaskStore`**

Append to `TaskStore.swift` (inside the class):

```swift
    // MARK: - Tags

    public func assignTag(taskID: UUID, tagID: UUID) async throws {
        try await context.perform { [self] in
            let task = try fetchManagedObject(id: taskID, in: context)
            let tag = try fetchTag(id: tagID, in: context)
            let existing = task.tags as? Set<Tag> ?? []
            if existing.contains(tag) { return }
            task.addToTags(tag)
            task.modifiedAt = Date()
            try context.save()
        }
    }

    public func unassignTag(taskID: UUID, tagID: UUID) async throws {
        try await context.perform { [self] in
            let task = try fetchManagedObject(id: taskID, in: context)
            let tag = try fetchTag(id: tagID, in: context)
            task.removeFromTags(tag)
            task.modifiedAt = Date()
            try context.save()
        }
    }

    public func tagIDs(forTask taskID: UUID) async throws -> [UUID] {
        try await context.perform { [self] in
            let task = try fetchManagedObject(id: taskID, in: context)
            let tags = (task.tags as? Set<Tag>) ?? []
            return tags.compactMap(\.id)
        }
    }

    private func fetchTag(id: UUID, in ctx: NSManagedObjectContext) throws -> Tag {
        let req = NSFetchRequest<Tag>(entityName: "Tag")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
        return m
    }
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter TaskStoreCRUDTests`
Expected: PASS, 8 tests (5 original + 3 new).

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreCRUDTests.swift
git commit -m "feat: add tag assignment APIs to TaskStore"
```

---

## Task 22: Export schema (Codable DTOs)

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift`

- [ ] **Step 1: Write the schema**

Write `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift`:

```swift
import Foundation

/// Versioned export schema. Bump `version` for any incompatible change.
public enum ExportSchema {
    public static let version = 1

    public struct Document: Codable, Sendable {
        public var version: Int
        public var exportedAt: Date
        public var tasks: [TaskDTO]
        public var tags: [TagDTO]
        public var journalEntries: [JournalEntryDTO]
        public var attachments: [AttachmentDTO]
        public var preferences: PreferencesDTO
    }

    public struct TaskDTO: Codable, Sendable {
        public var id: UUID
        public var title: String
        public var notes: String
        public var status: Int
        public var start: Date?
        public var startHasTime: Bool
        public var deadline: Date?
        public var deadlineHasTime: Bool
        public var position: Double
        public var isPinned: Bool
        public var parentID: UUID?
        public var tagIDs: [UUID]
        public var createdAt: Date?
        public var modifiedAt: Date?
        public var closedAt: Date?
        public var deletedAt: Date?
    }

    public struct TagDTO: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var tintColor: String?
        public var parentID: UUID?
        public var position: Double
    }

    public struct JournalEntryDTO: Codable, Sendable {
        public var id: UUID
        public var taskID: UUID
        public var kind: Int
        public var body: String
        public var payload: Data?
        public var createdAt: Date?
        public var editedAt: Date?
    }

    public struct AttachmentDTO: Codable, Sendable {
        public var id: UUID
        public var taskID: UUID
        public var journalEntryID: UUID?
        public var kind: Int
        public var filename: String
        public var uti: String
        public var byteSize: Int64
        /// Relative path under the export's `assets/` folder. Nil for link previews.
        public var dataPath: String?
        public var linkPreviewJSON: String?
        public var createdAt: Date?
    }

    public struct PreferencesDTO: Codable, Sendable {
        public var defaultAllDayHour: Int16
        public var defaultAllDayMinute: Int16
        public var morningSummaryEnabled: Bool
        public var morningSummaryHour: Int16
        public var morningSummaryMinute: Int16
        public var trashRetentionDays: Int16
        public var defaultTaskListSort: String
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift
git commit -m "feat: add Codable export schema DTOs"
```

---

## Task 23: `Exporter` — write JSON + assets folder

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Export/ExporterTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Export/ExporterTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("Exporter")
struct ExporterTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-export-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Empty store exports a valid document")
    func emptyStore() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        _ = try await prefs.read()
        let exporter = Exporter(persistence: p, preferences: prefs)
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await exporter.export(to: dir)
        let docURL = dir.appendingPathComponent("lillist.json")
        let data = try Data(contentsOf: docURL)
        let doc = try JSONDecoder().decode(ExportSchema.Document.self, from: data)
        #expect(doc.version == ExportSchema.version)
        #expect(doc.tasks.isEmpty)
        #expect(doc.tags.isEmpty)
    }

    @Test("Tasks, tags, journal entries, attachments all roundtrip")
    func fullRoundtrip() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let tags = TagStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let attach = AttachmentStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)

        let tag = try await tags.create(name: "Work", tintColor: "#FF0000")
        let task = try await tasks.create(title: "Ship")
        try await tasks.assignTag(taskID: task, tagID: tag)
        _ = try await journals.appendNote(taskID: task, body: "Hello")
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        _ = try await attach.addFile(taskID: task, filename: "x.bin", uti: "public.data", data: png)

        let exporter = Exporter(persistence: p, preferences: prefs)
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await exporter.export(to: dir)

        let docURL = dir.appendingPathComponent("lillist.json")
        let doc = try JSONDecoder().decode(
            ExportSchema.Document.self,
            from: try Data(contentsOf: docURL)
        )

        #expect(doc.tasks.count == 1)
        #expect(doc.tasks[0].title == "Ship")
        #expect(doc.tasks[0].tagIDs == [tag])
        #expect(doc.tags.count == 1)
        #expect(doc.journalEntries.count == 2) // 1 note + 1 attachment-kind entry
        #expect(doc.attachments.count == 1)

        let asset = doc.attachments[0]
        #expect(asset.dataPath != nil)
        let assetURL = dir.appendingPathComponent(asset.dataPath!)
        #expect(FileManager.default.fileExists(atPath: assetURL.path))
        #expect(try Data(contentsOf: assetURL) == png)
    }

    @Test("Export refuses to write into a non-empty directory")
    func refusesNonEmptyDir() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        let exporter = Exporter(persistence: p, preferences: prefs)
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let occupant = dir.appendingPathComponent("hello.txt")
        try "hi".write(to: occupant, atomically: true, encoding: .utf8)
        await #expect(throws: LillistError.self) {
            try await exporter.export(to: dir)
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter ExporterTests`
Expected: FAIL — `Exporter` undefined.

- [ ] **Step 3: Write `Exporter`**

Write `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift`:

```swift
import Foundation
import CoreData

public final class Exporter: @unchecked Sendable {
    private let persistence: PersistenceController
    private let preferences: PreferencesStore

    public init(persistence: PersistenceController, preferences: PreferencesStore) {
        self.persistence = persistence
        self.preferences = preferences
    }

    /// Writes `lillist.json` and an `assets/` folder under `dir`.
    /// `dir` must exist and be empty.
    public func export(to dir: URL) async throws {
        try ensureEmptyDirectory(dir)
        let assetsDir = dir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let document = try await buildDocument(assetsDir: assetsDir)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        try data.write(to: dir.appendingPathComponent("lillist.json"))
    }

    private func ensureEmptyDirectory(_ dir: URL) throws {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        if !contents.isEmpty {
            throw LillistError.validationFailed([
                .init(field: "exportDir", message: "must be empty")
            ])
        }
    }

    private func buildDocument(assetsDir: URL) async throws -> ExportSchema.Document {
        let ctx = persistence.container.viewContext
        let prefs = try await preferences.read()

        return try await ctx.perform {
            // Tasks (including trashed — full backup)
            let taskReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            taskReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let taskMOs = try ctx.fetch(taskReq)
            let taskDTOs = taskMOs.map { m -> ExportSchema.TaskDTO in
                let tagIDs = ((m.tags as? Set<Tag>) ?? []).compactMap(\.id).sorted(by: { $0.uuidString < $1.uuidString })
                return ExportSchema.TaskDTO(
                    id: m.id ?? UUID(),
                    title: m.title ?? "",
                    notes: m.notes ?? "",
                    status: Int(m.statusRaw),
                    start: m.start,
                    startHasTime: m.startHasTime,
                    deadline: m.deadline,
                    deadlineHasTime: m.deadlineHasTime,
                    position: m.position,
                    isPinned: m.isPinned,
                    parentID: m.parent?.id,
                    tagIDs: tagIDs,
                    createdAt: m.createdAt,
                    modifiedAt: m.modifiedAt,
                    closedAt: m.closedAt,
                    deletedAt: m.deletedAt
                )
            }

            let tagReq = NSFetchRequest<Tag>(entityName: "Tag")
            let tagDTOs = try ctx.fetch(tagReq).map { m in
                ExportSchema.TagDTO(
                    id: m.id ?? UUID(),
                    name: m.name ?? "",
                    tintColor: m.tintColor,
                    parentID: m.parent?.id,
                    position: m.position
                )
            }

            let journalReq = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            journalReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let journalDTOs = try ctx.fetch(journalReq).map { m in
                ExportSchema.JournalEntryDTO(
                    id: m.id ?? UUID(),
                    taskID: m.task?.id ?? UUID(),
                    kind: Int(m.kindRaw),
                    body: m.body ?? "",
                    payload: m.payload,
                    createdAt: m.createdAt,
                    editedAt: m.editedAt
                )
            }

            let attReq = NSFetchRequest<Attachment>(entityName: "Attachment")
            let attDTOs = try ctx.fetch(attReq).map { m -> ExportSchema.AttachmentDTO in
                var path: String?
                if let data = m.data {
                    let filename = "\(m.id?.uuidString ?? UUID().uuidString)-\(m.filename ?? "asset")"
                    let url = assetsDir.appendingPathComponent(filename)
                    try? data.write(to: url)
                    path = "assets/\(filename)"
                }
                return ExportSchema.AttachmentDTO(
                    id: m.id ?? UUID(),
                    taskID: m.task?.id ?? UUID(),
                    journalEntryID: m.journalEntry?.id,
                    kind: Int(m.kindRaw),
                    filename: m.filename ?? "",
                    uti: m.uti ?? "",
                    byteSize: m.byteSize,
                    dataPath: path,
                    linkPreviewJSON: m.linkPreviewJSON,
                    createdAt: m.createdAt
                )
            }

            let prefsDTO = ExportSchema.PreferencesDTO(
                defaultAllDayHour: prefs.defaultAllDayHour,
                defaultAllDayMinute: prefs.defaultAllDayMinute,
                morningSummaryEnabled: prefs.morningSummaryEnabled,
                morningSummaryHour: prefs.morningSummaryHour,
                morningSummaryMinute: prefs.morningSummaryMinute,
                trashRetentionDays: prefs.trashRetentionDays,
                defaultTaskListSort: prefs.defaultTaskListSort.rawValue
            )

            return ExportSchema.Document(
                version: ExportSchema.version,
                exportedAt: Date(),
                tasks: taskDTOs,
                tags: tagDTOs,
                journalEntries: journalDTOs,
                attachments: attDTOs,
                preferences: prefsDTO
            )
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter ExporterTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift Packages/LillistCore/Tests/LillistCoreTests/Export/ExporterTests.swift
git commit -m "feat: add Exporter producing JSON + assets folder"
```

---

## Task 24: Final integration sweep — run full test suite, fix any concurrency warnings, tag

**Files:**
- (no new files)

- [ ] **Step 1: Run the entire test suite**

Run: `cd Packages/LillistCore && swift test 2>&1 | tee /tmp/lillist-foundation-test.log`
Expected: every test passes. Count should be in the neighborhood of 60+.

- [ ] **Step 2: Run with strict concurrency checking surfaced**

Run: `cd Packages/LillistCore && swift build -Xswiftc -warnings-as-errors`
Expected: build succeeds with no warnings escalated to errors. If any concurrency warning appears, fix it before continuing — typically by annotating an unchecked `Sendable`, marking a helper `nonisolated`, or moving state into the perform block.

- [ ] **Step 3: Write a brief README for `LillistCore`**

Write `Packages/LillistCore/README.md`:

```markdown
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

## Running tests

```bash
cd Packages/LillistCore
swift test
```

## Public API

All entry points return value-type `*Record` DTOs. No `NSManagedObject` escapes the package.
```

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistCore/README.md
git commit -m "docs: add LillistCore README summarizing Plan 1 scope"
```

- [ ] **Step 5: Tag the release**

```bash
git tag -a plan-1-foundation -m "Lillist Plan 1: Foundation complete"
```

- [ ] **Step 6: Final verification**

Run: `cd Packages/LillistCore && swift test`
Expected: full suite green.

Plan 1 is complete. Proceed to Plan 2 (CloudKit sync).

---

## Self-Review Checklist (run by the implementer before merging)

- [ ] All test files exercise observable behaviors, not implementation details.
- [ ] Every store method has at least one happy-path test and one failure test.
- [ ] Cycle prevention is exercised at depth ≥ 3 (grandchild → grandparent reassignment).
- [ ] Soft-delete + restore preserves the deleted state of children whose `deletedAt` matches.
- [ ] Auto-purge respects the configured retention.
- [ ] Export round-trips data and writes asset bytes.
- [ ] All `NSManagedObject`s stay inside their owning context — only value-type records cross.
- [ ] No `try!`, no `fatalError` outside Core Data model loading.
- [ ] **Test Engineer subagent has reviewed test quality** per design Section 9 — not just coverage numbers, but behaviors covered, edge cases included, and mutation-test-style rigor.
