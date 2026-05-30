# Fractional-Ordering Compaction Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 2.**
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> ⚠️ **Wave 1 (`store-swap-safety`) is merged to `main`.** It changed several shared files (`MigrationCoordinator`, `PersistenceHost`, `QuarantineManager`, `MigrationJournal`, both `AppEnvironment`s, `PersistenceController`). **Re-Read every file before editing and anchor by code structure — the line numbers in this plan may have drifted.**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the dead `PositionCompactor` into both `TaskStore.reorder` and `SmartFilterStore.reorder` so a repeated same-gap insert recompacts siblings instead of underflowing to colliding positions, and unify the out-of-order anchor guard behind one shared `FractionalPosition` helper.

**Architecture:** Add two `nonisolated static` helpers to `FractionalPosition` (`anchorsAreOutOfOrder` and `needsCompaction`) as the single source of truth for both stores. In each `reorder`, after computing the midpoint, detect a too-small gap, fetch the sorted non-trashed siblings, `PositionCompactor.recompact` them, persist every sibling in the **same** `context.perform` block, then recompute the target's position against the freshly-spaced neighbors. All math stays in the existing `FractionalPosition`/`PositionCompactor` enums (DRY); the stores only orchestrate fetch + persist.

**Tech Stack:** Swift 6.2, Core Data (`NSManagedObjectContext.perform` on the main-queue `viewContext`), Swift Testing (`import Testing`, `@Test`/`#expect`), in-memory `TestStore.make()` persistence.

**Source findings:** stores-1 (dead compaction valve; positions underflow and collide on repeated same-gap drag), stores-3 (missing out-of-order anchor guard in `TaskStore.reorder`; `SmartFilterStore` has an ad-hoc one that should be shared).

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift` | Add `anchorsAreOutOfOrder(after:before:)` and `needsCompaction(after:before:)` shared helpers. |
| Modify | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` | Rewrite `reorder` to add the anchor guard and recompact-on-collision path; add private `recompactSiblings` helper. |
| Modify | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift` | Replace the ad-hoc anchor guard with the shared helper and add the recompact-on-collision path; add private `recompactSiblings` helper. |
| Modify (test) | `Packages/LillistCore/Tests/LillistCoreTests/Ordering/FractionalPositionTests.swift` | Unit tests for the two new helpers. |
| Modify (test) | `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreOrderingTests.swift` | Out-of-order anchor rejection test + 60-insert compaction integration test. |
| Modify (test) | `Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift` | 60-insert compaction integration test (anchor-guard already covered by existing suite). |

---

## Task 1: Add shared anchor-order and compaction-trigger helpers to `FractionalPosition`

**Files:**
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Ordering/FractionalPositionTests.swift` (append new `@Test` methods inside the existing `FractionalPositionTests` struct, before the closing `}` at line 56)
- Modify: `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift` (add two static funcs after `gapIsTooSmall`, currently ending line 29)

The current `FractionalPosition` has `position(after:before:)` and `gapIsTooSmall(after:before:)` (both non-optional `Double` args). We add `anchorsAreOutOfOrder` (optional args, so callers don't unwrap) and `needsCompaction` (optional args; only two real neighbors can collide — a nil neighbor means head/tail where `position` returns `a+1`/`b-1`/`1.0`, which can never collide).

- [ ] **Step 1: Write the failing test** — append these `@Test` methods to `FractionalPositionTests` (insert immediately before the struct's closing brace at line 56):

```swift
    @Test("anchorsAreOutOfOrder is true only when after >= before")
    func anchorOrdering() {
        #expect(FractionalPosition.anchorsAreOutOfOrder(after: 3.0, before: 2.0) == true)
        #expect(FractionalPosition.anchorsAreOutOfOrder(after: 2.0, before: 2.0) == true)
        #expect(FractionalPosition.anchorsAreOutOfOrder(after: 2.0, before: 3.0) == false)
    }

    @Test("anchorsAreOutOfOrder is false when either anchor is nil")
    func anchorOrderingWithNil() {
        #expect(FractionalPosition.anchorsAreOutOfOrder(after: nil, before: 2.0) == false)
        #expect(FractionalPosition.anchorsAreOutOfOrder(after: 2.0, before: nil) == false)
        #expect(FractionalPosition.anchorsAreOutOfOrder(after: nil, before: nil) == false)
    }

    @Test("needsCompaction fires only when both real neighbors are too close")
    func needsCompactionTwoNeighbors() {
        let after = 1.0
        #expect(FractionalPosition.needsCompaction(after: after, before: after.nextUp) == true)
        #expect(FractionalPosition.needsCompaction(after: 1.0, before: 2.0) == false)
    }

    @Test("needsCompaction is false at the head or tail (nil neighbor)")
    func needsCompactionEdges() {
        #expect(FractionalPosition.needsCompaction(after: nil, before: 1.0) == false)
        #expect(FractionalPosition.needsCompaction(after: 1.0, before: nil) == false)
        #expect(FractionalPosition.needsCompaction(after: nil, before: nil) == false)
    }
```

- [ ] **Step 2: Run the test, expect failure** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter FractionalPosition
```

Expect a **compile failure**: `error: type 'FractionalPosition' has no member 'anchorsAreOutOfOrder'` (and `...has no member 'needsCompaction'`). The suite cannot build until Step 3 lands.

- [ ] **Step 3: Implement the minimal change** — in `FractionalPosition.swift`, add the two helpers immediately after the `gapIsTooSmall` function (after line 29, before the enum's closing `}` at line 30). The file becomes:

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

    /// True when two real (non-nil) anchors are equal or inverted, i.e. the
    /// caller asked to drop a row into a degenerate gap. Single source of
    /// truth for the reorder anchor-validation guard in both stores.
    /// A nil anchor means "the corresponding list end," which is never
    /// out of order.
    public static func anchorsAreOutOfOrder(after: Double?, before: Double?) -> Bool {
        guard let a = after, let b = before else { return false }
        return a >= b
    }

    /// True when the midpoint between `after` and `before` would underflow —
    /// i.e. both neighbors are real and `gapIsTooSmall`. Head/tail inserts
    /// (a nil neighbor) place at `±1.0` and never collide, so they return
    /// `false`. When `true`, the caller must recompact siblings before
    /// recomputing the target position.
    public static func needsCompaction(after: Double?, before: Double?) -> Bool {
        guard let a = after, let b = before else { return false }
        return gapIsTooSmall(after: a, before: b)
    }
}
```

- [ ] **Step 4: Run the test, expect pass** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter FractionalPosition
```

Expect: the `FractionalPosition` suite passes, including the four new tests (`anchorOrdering`, `anchorOrderingWithNil`, `needsCompactionTwoNeighbors`, `needsCompactionEdges`). Output ends with `Test Suite 'FractionalPosition' passed` (or the Swift Testing equivalent `✔ Suite "FractionalPosition" passed`) and no warnings.

- [ ] **Step 5: Commit** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && \
git add Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Ordering/FractionalPositionTests.swift && \
git commit -m "feat(ordering): add shared anchor-order and compaction-trigger helpers

Adds FractionalPosition.anchorsAreOutOfOrder(after:before:) and
needsCompaction(after:before:) as the single source of truth for the
reorder anchor guard and the compaction trigger, ahead of wiring them
into TaskStore/SmartFilterStore. Part of stores-1, stores-3."
```

---

## Task 2: Add the out-of-order anchor guard to `TaskStore.reorder`

**Files:**
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreOrderingTests.swift` (append a `@Test` inside `TaskStoreOrderingTests`, before the closing `}` at line 57)
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` (`reorder`, lines 245–275)

`TaskStore.reorder` currently computes the midpoint with **no** anchor-order validation (unlike `SmartFilterStore`, which guards `a >= b`). A caller passing inverted/equal anchors silently corrupts ordering. Close stores-3 for `TaskStore` first, using the shared helper from Task 1.

- [ ] **Step 1: Write the failing test** — append this `@Test` to `TaskStoreOrderingTests` (insert immediately before the struct's closing brace at line 57):

```swift
    @Test("Reorder rejects out-of-order anchors")
    func outOfOrderAnchors() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        let c = try await store.create(title: "C", parent: parent)
        // Ask to drop C with after=B, before=A — anchors are inverted.
        await #expect(throws: LillistError.self) {
            try await store.reorder(id: c, after: b, before: a)
        }
    }
```

- [ ] **Step 2: Run the test, expect failure** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "TaskStore ordering"
```

Expect: `outOfOrderAnchors` **fails** — no error is thrown because `reorder` does not yet validate anchor order, so `#expect(throws:)` reports `Expected an error to be thrown, but none was`.

- [ ] **Step 3: Implement the minimal change** — replace the body of `reorder` (lines 245–275). Add the anchor guard after the mixed-parent check, before computing the position:

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
            if FractionalPosition.anchorsAreOutOfOrder(
                after: afterTask?.position,
                before: beforeTask?.position
            ) {
                throw LillistError.validationFailed([
                    .init(field: "neighbors", message: "anchors out of order")
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

- [ ] **Step 4: Run the test, expect pass** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "TaskStore ordering"
```

Expect: all `TaskStore ordering` tests pass, including `outOfOrderAnchors`, and the pre-existing `reorderBetween`, `reorderToHead`, `reorderToTail`, `mixedParents` still pass. No warnings.

- [ ] **Step 5: Commit** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && \
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreOrderingTests.swift && \
git commit -m "fix(stores): reject out-of-order anchors in TaskStore.reorder

Routes the anchor guard through the shared
FractionalPosition.anchorsAreOutOfOrder helper so TaskStore matches the
guard SmartFilterStore already had. Closes stores-3 for TaskStore."
```

---

## Task 3: Route `SmartFilterStore.reorder`'s anchor guard through the shared helper

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift` (`reorder`, lines 245–259)

`SmartFilterStore.reorder` already rejects out-of-order anchors with an ad-hoc `if let a = afterPos, let b = beforePos, a >= b`. Replace it with the shared `FractionalPosition.anchorsAreOutOfOrder` helper (DRY — one source of truth across both stores). The existing `SmartFilterStore — pinning and reorder` suite already exercises the happy path; behavior is unchanged, so this is a pure refactor verified by the existing suite (no new test needed — YAGNI).

- [ ] **Step 1: Confirm the existing suite is green (baseline)** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "SmartFilterStore — pinning and reorder"
```

Expect: `reorder` and `reorderEdges` both pass. This is the regression baseline for the refactor.

- [ ] **Step 2: Implement the change** — replace the body of `reorder` (lines 245–259):

```swift
    /// Place `id` immediately between `after` and `before` (either may be nil).
    /// Uses `FractionalPosition` for gap-based insertion.
    public func reorder(id: UUID, after: UUID?, before: UUID?) async throws {
        try await context.perform { [self] in
            let target = try fetchManagedObject(id: id, in: context)
            let afterPos: Double? = try after.map { try fetchManagedObject(id: $0, in: context).position }
            let beforePos: Double? = try before.map { try fetchManagedObject(id: $0, in: context).position }
            if FractionalPosition.anchorsAreOutOfOrder(after: afterPos, before: beforePos) {
                throw LillistError.validationFailed([
                    .init(field: "reorder", message: "anchors out of order")
                ])
            }
            target.position = FractionalPosition.position(after: afterPos, before: beforePos)
            target.modifiedAt = Date()
            try context.save()
        }
    }
```

- [ ] **Step 3: Run the suite, expect pass** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "SmartFilterStore — pinning and reorder"
```

Expect: `reorder` and `reorderEdges` still pass — identical behavior, now sharing the guard. No warnings.

- [ ] **Step 4: Commit** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && \
git add Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift && \
git commit -m "refactor(stores): share anchor-order guard in SmartFilterStore.reorder

Replaces the ad-hoc a >= b check with the shared
FractionalPosition.anchorsAreOutOfOrder helper so both stores validate
reorder anchors through one source of truth. Part of stores-3."
```

---

## Task 4: Wire compaction into `TaskStore.reorder`

**Files:**
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreOrderingTests.swift` (append a `@Test` inside `TaskStoreOrderingTests`, before the closing `}`)
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` (`reorder`, and a new private `recompactSiblings` helper near the other helpers around line 534)

When a power user repeatedly drops a row into the same gap, the midpoint underflows and positions collide. Detect `FractionalPosition.needsCompaction`, then: fetch the sorted non-trashed siblings, `PositionCompactor.recompact` them, persist all in the same `perform`, and recompute the target against the freshly-spaced neighbors. The integration test inserts 60+ rows into the same region and asserts positions stay strictly increasing (the dataset reproduces the collision the review describes in stores-1).

- [ ] **Step 1: Write the failing test** — append this `@Test` to `TaskStoreOrderingTests` (insert before the struct's closing brace):

```swift
    @Test("60 successive same-region inserts keep positions strictly increasing")
    func repeatedSameGapInsertsCompact() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "P")
        // Two stable bookends; every insert targets the gap between them.
        let head = try await store.create(title: "head", parent: parent)
        let tail = try await store.create(title: "tail", parent: parent)

        // Repeatedly drop a fresh row into the (head, currentSecond) gap.
        // Without compaction the midpoint underflows and positions collide.
        for i in 0..<60 {
            let row = try await store.create(title: "row\(i)", parent: parent)
            let children = try await store.children(of: parent)
            // The row immediately after `head` in current order is the
            // "before" anchor; `head` is the "after" anchor.
            let afterID = head
            let beforeID = children.first { $0.id != head && $0.id != row }!.id
            try await store.reorder(id: row, after: afterID, before: beforeID)
        }

        let positions = (try await store.children(of: parent)).map(\.position)
        // Strictly increasing — no collisions, no underflow.
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i - 1])
        }
        // All distinct.
        #expect(Set(positions).count == positions.count)
        _ = tail
    }
```

- [ ] **Step 2: Run the test, expect failure** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "TaskStore ordering"
```

Expect: `repeatedSameGapInsertsCompact` **fails** — after enough same-gap inserts the midpoint underflows so two rows share a position. The failure is a `#expect(positions[i] > positions[i - 1])` violation (equal adjacent positions) and/or `Set(positions).count == positions.count` failing because the distinct count drops below the row count.

- [ ] **Step 3: Implement the minimal change** — two edits in `TaskStore.swift`.

First, update `reorder` (lines 245–275 as left by Task 2) to recompact when the gap underflows, then recompute against the re-spaced neighbors:

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
            if FractionalPosition.anchorsAreOutOfOrder(
                after: afterTask?.position,
                before: beforeTask?.position
            ) {
                throw LillistError.validationFailed([
                    .init(field: "neighbors", message: "anchors out of order")
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

            // If the target gap underflows, re-space all siblings evenly,
            // then recompute against the freshly-spaced neighbors. Recompaction
            // and the target update persist together in this one perform block.
            if FractionalPosition.needsCompaction(
                after: afterTask?.position,
                before: beforeTask?.position
            ) {
                recompactSiblings(ofParent: newParent)
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

Second, add the private `recompactSiblings` helper next to the other helpers (insert after `nextPosition(forParent:)`, which currently ends at line 545):

```swift
    /// Re-space every non-trashed sibling under `parent` to even 1.0 gaps,
    /// preserving their current order. Mutates the managed objects in place;
    /// the caller's `context.save()` persists them. Must run inside the
    /// reorder `perform` block so recompaction and the target update commit
    /// atomically. The anchor managed objects the caller is holding pick up
    /// their new `position` values, so a post-recompaction
    /// `FractionalPosition.position` call sees the widened gaps.
    private func recompactSiblings(ofParent parent: LillistTask?) {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        if let parent {
            req.predicate = NSPredicate(format: "parent == %@ AND deletedAt == nil", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil AND deletedAt == nil")
        }
        req.sortDescriptors = [
            NSSortDescriptor(key: "position", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
        guard let siblings = try? context.fetch(req) else { return }
        let respaced = PositionCompactor.recompact(positions: siblings.map(\.position))
        for (sibling, newPosition) in zip(siblings, respaced) {
            sibling.position = newPosition
        }
    }
```

Note: `recompactSiblings` re-reads `afterTask`/`beforeTask` positions transparently — they are the same managed-object instances the fetch returns (Core Data uniques objects per context), so mutating `sibling.position` updates the anchors the subsequent `FractionalPosition.position(after:before:)` call reads. The sort ties broken by `createdAt` match `children(of:)`'s order so the re-spaced order equals the visible order.

- [ ] **Step 4: Run the test, expect pass** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "TaskStore ordering"
```

Expect: all `TaskStore ordering` tests pass, including `repeatedSameGapInsertsCompact` (60 inserts, positions strictly increasing and all distinct) and the still-passing `outOfOrderAnchors`, `reorderBetween`, `reorderToHead`, `reorderToTail`, `mixedParents`. No warnings.

- [ ] **Step 5: Commit** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && \
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreOrderingTests.swift && \
git commit -m "fix(stores): recompact siblings when TaskStore.reorder gap underflows

When the target gap is too small to bisect, re-space all non-trashed
siblings via PositionCompactor in the same perform block, then recompute
the target against the widened neighbors. Adds a 60-insert integration
test asserting positions stay strictly increasing. Closes stores-1 for
TaskStore."
```

---

## Task 5: Wire compaction into `SmartFilterStore.reorder`

**Files:**
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift` (append a `@Test` inside the existing `SmartFilterStorePinReorderTests` suite, before its closing `}` at line 138)
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift` (`reorder` as left by Task 3, and a new private `recompactSiblings` helper near `nextPosition`, currently ending line 165)

`SmartFilter` rows form one flat list (no parent), so recompaction re-spaces the whole table. Same pattern as Task 4: detect `needsCompaction`, recompact in the same `perform`, recompute against the re-spaced anchors.

- [ ] **Step 1: Write the failing test** — append this `@Test` to `SmartFilterStorePinReorderTests` (insert before the struct's closing brace at line 138):

```swift
    @Test("60 successive same-region inserts keep filter positions strictly increasing")
    func repeatedSameGapInsertsCompact() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let head = try await store.create(name: "head", group: sample())
        let tail = try await store.create(name: "tail", group: sample())

        for i in 0..<60 {
            let row = try await store.create(name: "row\(i)", group: sample())
            let list = try await store.list()
            let afterID = head
            let beforeID = list.first { $0.id != head && $0.id != row }!.id
            try await store.reorder(id: row, after: afterID, before: beforeID)
        }

        let positions = (try await store.list()).map(\.position)
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i - 1])
        }
        #expect(Set(positions).count == positions.count)
        _ = tail
    }
```

- [ ] **Step 2: Run the test, expect failure** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "SmartFilterStore — pinning and reorder"
```

Expect: `repeatedSameGapInsertsCompact` **fails** — the midpoint underflows after repeated same-gap inserts, so adjacent positions become equal: the `#expect(positions[i] > positions[i - 1])` and/or `Set(positions).count == positions.count` assertions fail.

- [ ] **Step 3: Implement the minimal change** — two edits in `SmartFilterStore.swift`.

First, update `reorder` (as left by Task 3) to recompact on underflow then recompute:

```swift
    /// Place `id` immediately between `after` and `before` (either may be nil).
    /// Uses `FractionalPosition` for gap-based insertion.
    public func reorder(id: UUID, after: UUID?, before: UUID?) async throws {
        try await context.perform { [self] in
            let target = try fetchManagedObject(id: id, in: context)
            let afterRow = try after.map { try fetchManagedObject(id: $0, in: context) }
            let beforeRow = try before.map { try fetchManagedObject(id: $0, in: context) }
            if FractionalPosition.anchorsAreOutOfOrder(
                after: afterRow?.position,
                before: beforeRow?.position
            ) {
                throw LillistError.validationFailed([
                    .init(field: "reorder", message: "anchors out of order")
                ])
            }
            // If the target gap underflows, re-space all rows evenly, then
            // recompute against the freshly-spaced neighbors. Recompaction and
            // the target update persist together in this one perform block.
            if FractionalPosition.needsCompaction(
                after: afterRow?.position,
                before: beforeRow?.position
            ) {
                recompactSiblings()
            }
            target.position = FractionalPosition.position(
                after: afterRow?.position,
                before: beforeRow?.position
            )
            target.modifiedAt = Date()
            try context.save()
        }
    }
```

Second, add the private `recompactSiblings` helper after `nextPosition()` (currently ending line 165):

```swift
    /// Re-space every smart-filter row to even 1.0 gaps, preserving current
    /// order. Mutates the managed objects in place; the caller's
    /// `context.save()` persists them. Must run inside the reorder `perform`
    /// block so recompaction and the target update commit atomically. The
    /// anchor managed objects the caller holds pick up their new `position`
    /// values, so a post-recompaction `FractionalPosition.position` call sees
    /// the widened gaps.
    private func recompactSiblings() {
        let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
        req.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
        guard let rows = try? context.fetch(req) else { return }
        let respaced = PositionCompactor.recompact(positions: rows.map(\.position))
        for (row, newPosition) in zip(rows, respaced) {
            row.position = newPosition
        }
    }
```

Note: `list()` (line 101) sorts by `position` ascending only, matching this helper's single sort descriptor, so the re-spaced order equals the visible order. The `afterRow`/`beforeRow` instances are the same managed objects the fetch returns (Core Data uniques per context), so they pick up the widened positions before the recompute.

- [ ] **Step 4: Run the test, expect pass** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "SmartFilterStore — pinning and reorder"
```

Expect: all tests in the suite pass — `setPinned`, `reorder`, `reorderEdges`, and the new `repeatedSameGapInsertsCompact` (60 inserts, strictly increasing, all distinct). No warnings.

- [ ] **Step 5: Commit** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && \
git add Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift && \
git commit -m "fix(stores): recompact rows when SmartFilterStore.reorder gap underflows

When the target gap is too small to bisect, re-space all filter rows via
PositionCompactor in the same perform block, then recompute the target
against the widened neighbors. Adds a 60-insert integration test
asserting positions stay strictly increasing. Closes stores-1 for
SmartFilterStore."
```

---

## Task 6: Full-suite regression and warnings-as-errors check

**Files:** none (verification only)

Compaction touches the reorder path shared by ordering, hierarchy, and query suites. Confirm the entire `LillistCore` test suite is green and that the build is warning-clean (house rule: warnings are errors).

- [ ] **Step 1: Run the whole LillistCore suite** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -30
```

Expect: the full suite passes (the pre-existing count plus the new ordering, compaction, and `FractionalPosition` helper tests). No test failures.

- [ ] **Step 2: Confirm no new warnings** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | grep -i 'warning:' || echo "NO WARNINGS"
```

Expect: `NO WARNINGS`. If any warning appears, fix it at the source (no `@available`/pragma suppression) before proceeding — the changed files (`FractionalPosition.swift`, `TaskStore.swift`, `SmartFilterStore.swift`) are the likely sources.

- [ ] **Step 3: Confirm the working tree is clean** — run:

```bash
cd /Volumes/Code/mikeyward/Lillist && git status --short
```

Expect: empty output — every change from Tasks 1–5 is already committed. No stray edits, no untracked files.

---

## Self-review checklist

- [ ] **stores-1** (dead compaction valve; positions underflow and collide on repeated same-gap drag) — closed by **Task 4** (`TaskStore.reorder` recompaction + 60-insert test) and **Task 5** (`SmartFilterStore.reorder` recompaction + 60-insert test), built on the shared `FractionalPosition.needsCompaction` trigger from **Task 1**. `PositionCompactor.recompact` (previously dead code) is now called from both `recompactSiblings` helpers.
- [ ] **stores-3** (missing out-of-order anchor guard in `TaskStore.reorder`; `SmartFilterStore`'s ad-hoc guard not shared) — closed by **Task 1** (shared `FractionalPosition.anchorsAreOutOfOrder` helper + unit tests), **Task 2** (`TaskStore.reorder` now rejects out-of-order anchors via the shared helper + rejection test), and **Task 3** (`SmartFilterStore.reorder` refactored to use the shared helper, behavior-verified by its existing suite).
- [ ] **DRY** — all ordering math stays in `FractionalPosition`/`PositionCompactor`; both stores share `anchorsAreOutOfOrder`, `needsCompaction`, and `PositionCompactor.recompact`; each store has a tightly-scoped `recompactSiblings` orchestrator differing only by entity/predicate (flat table vs. parent-scoped), which is genuine per-entity fetch shape, not duplicated math.
- [ ] **Atomicity** — recompaction and the target update happen inside the **same** `context.perform` block and are committed by a single `context.save()` in each store (per the review's "persist all in one perform").
- [ ] **Strengths preserved** — no `NSManagedObject` escapes `LillistCore` (helpers are private; DTO boundary untouched); date math unchanged (`modifiedAt = Date()` matches existing reorder); the synchronous AsyncStream registration pattern is not touched; `viewContext`-on-main default is unchanged.
- [ ] **No `.xcdatamodel` edits** — this plan touches no Core Data model files, so the `CompileCoreDataModel` mtime touch ritual does not apply.
- [ ] **Cross-plan coordination** — `Stores/TaskStore.swift` is also edited by `breadcrumb-truthfulness` (`reorder` has no breadcrumb today; that plan may add one) and `background-context-seam` (`context.rollback()` in mutating `perform` catch). These are non-overlapping concerns; land order is flexible but re-read `reorder` before editing if those plans merged first.
