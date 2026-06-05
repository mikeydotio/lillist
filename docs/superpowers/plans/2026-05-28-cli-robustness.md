# CLI Robustness Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 6.**
>
> **⚠️ Wave-4 reconciliation (2026-06-04):** This plan is essentially unaffected. Verified against current `main`: `Resolver.swift` is byte-for-byte unchanged by Wave 4 — every line anchor in Tasks 1 and 4 (`resolve` ends at line 91; the destructive-substring error with `Use --exact "<title>"` is at lines 82–86; `resolveExactTitle` is lines 93–105; `shortestUniqueShortIDs` doc-comment at line 107) still holds, and the Task 4 "before" premise (message contains `--exact`) is still true. The five destructive command files, `WatchHandler.swift`, `WatchCommand.swift`, and `RestoreHandler.swift` were not touched. **One adjacency caution:** Wave 4 made `TaskStore` a hotspot — it rewrote `purgeAll` into a background-context batch delete (`batchPurge`/`CascadeReaper`), deleted `countDescendants`, and added `context.rollback()` to the per-mutator catch blocks. None of that changes this plan: every command here loops a *per-resolution* mutator (`softDelete`/`hardDelete`/`reparent`/`transition`/`restore`) whose **signature is unchanged** and whose added rollback is transparent. Do **not** "modernize" `PurgeCommand` to call the new batch `purgeAll` — per-resolution `hardDelete` is the correct all-or-nothing path this plan relies on, and `purgeAll` has no resolve-then-mutate gate. The Task 7 note that `Config.resolvedCalendar()` already exists (Wave 3) remains correct.
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> **Pre-flight (run before any edit):** Confirm Waves 1–5 are on `main` (`git log --oneline main | head -20`). Read `docs/superpowers/handoffs/wave-5.md`. Re-Read every file you touch and anchor by code **structure**, not line number — each wave shifts the shared hotspot files. On completion, write `docs/superpowers/handoffs/wave-6.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `lillist` CLI's destructive stdin batches all-or-nothing, DRY-up the duplicated stdin-parse blocks, lock the structured-output renderers with byte-exact golden tests, remove the dead `--exact`/`resolveExactTitle` surface, and replace `watch`'s unbounded detached-Task observer with a serialized, debounced, deduplicating, error-surfacing observer.

**Architecture:** Introduce one `BatchTokens` helper (in the `lillist-cli` target's `Support/`) that owns the "is this stdin? validate? read lines" decision so the five destructive commands stop repeating it. Add a `Resolver.resolveAll(...)` that pre-resolves every token to a concrete `UUID` *before* any handler mutates, so a single bad token aborts the whole batch with zero side effects. Pin the JSON/NDJSON/TSV renderers with byte-exact fixtures rendered from a fixed-UUID/fixed-date record set (no `normalize()` trim). Delete `resolveExactTitle` (dead) and rewrite the destructive-ambiguity error to point at the real working path. Rewrite `WatchHandler` so context-change notifications feed a single serialized `Task` that debounces, dedupes against the last emitted snapshot, and surfaces errors instead of swallowing them.

**Tech Stack:** Swift 6.2, ArgumentParser, Core Data (`NSPersistentCloudKitContainer`), Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`), in-memory `PersistenceController` via `TestStore.make()`.

**Source findings:** cli-2, cli-3, cli-4, cli-5, cli-6 (Roadmap #18).

---

## File Structure

### Create

| Path | Responsibility |
|------|----------------|
| `Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift` | Single helper that turns a positional token (`-` ⇒ stdin) into the token list, applying the destructive-UUID gate. Replaces the duplicated `if StdinReader.isStdinSentinel(...)` block in five commands. |
| `Packages/LillistCore/Tests/lillistCLITests/BatchTokensTests.swift` | Unit tests for `BatchTokens.resolveInput` covering single-token, stdin-passthrough, destructive-UUID-gate, and `--allow-fuzzy` paths. |
| `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/ResolveAllTests.swift` | Tests for `Resolver.resolveAll` — happy path, and the one-bad-token test asserting zero side effects (all-or-nothing). |
| `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/BatchAtomicityTests.swift` | End-to-end atomicity tests at the handler level: a delete/purge/move/status-closed batch with one bad token mutates nothing. |
| `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-json.txt` | Byte-exact JSON golden for a fixed-UUID/fixed-date task set. |
| `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-ndjson.txt` | Byte-exact NDJSON golden for the same task set. |
| `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-tsv.txt` | Byte-exact TSV golden (header + embedded-tab title) for the same task set. |
| `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/tag-json.txt` | Byte-exact JSON golden for a fixed tag set. |
| `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/tag-ndjson.txt` | Byte-exact NDJSON golden for the same tag set. |
| `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/tag-tsv.txt` | Byte-exact TSV golden (header + embedded-tab name) for the same tag set. |
| `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/journal-json.txt` | Byte-exact JSON golden for a fixed journal set. |
| `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/WatchHandlerTests.swift` | Tests for the rewritten `WatchHandler`: initial inserts emitted, a post-change update emitted, no duplicate update for an unchanged set, errors surfaced. |

### Modify

| Path | Responsibility |
|------|----------------|
| `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift` | Add `resolveAll`; delete dead `resolveExactTitle`; rewrite the destructive-partial-match error message (no `--exact`). |
| `Packages/LillistCore/Sources/lillist-cli/Commands/DeleteCommand.swift` | Use `BatchTokens` + pre-resolve-then-mutate. |
| `Packages/LillistCore/Sources/lillist-cli/Commands/PurgeCommand.swift` | Use `BatchTokens` + pre-resolve-then-mutate. |
| `Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift` | Use `BatchTokens` (restore resolves through the trash list inside its handler; pre-validate token list only). |
| `Packages/LillistCore/Sources/lillist-cli/Commands/MoveCommand.swift` | Use `BatchTokens` + pre-resolve-then-mutate. |
| `Packages/LillistCore/Sources/lillist-cli/Commands/StatusCommand.swift` | Use `BatchTokens` (closed ⇒ destructive gate) + pre-resolve-then-mutate. |
| `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift` | Replace unbounded detached-Task observer with a serialized, debounced, deduplicating, error-surfacing observer. |
| `Packages/LillistCore/Sources/lillist-cli/Commands/WatchCommand.swift` | Pass through the new `onError` closure to `WatchHandler.run`. |
| `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/ResolverTests.swift` | Add a test asserting the rewritten destructive-partial error message contains no `--exact`. |
| `Packages/LillistCore/Tests/lillistCLITests/GoldenOutputTests.swift` | Add byte-exact (un-normalized) golden assertions for json/ndjson/tsv across Task/Tag/Journal renderers. |

> **No `Package.swift` change is needed.** The `lillistCLITests` target already declares `resources: [.copy("Fixtures/snapshots")]`, so any new `.txt` under that directory is bundled automatically.

> **No `.xcdatamodel` edits** are part of this plan, so the `CompileCoreDataModel` mtime-touch ritual does not apply here.

---

### Task 1: Add `Resolver.resolveAll` for all-or-nothing batch pre-resolution (cli-2)

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/ResolveAllTests.swift`
- Modify `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift` (add method after `resolve`, currently ends line 91)

- [ ] **Step 1: Write the failing test.** Create `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/ResolveAllTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.Resolver.resolveAll")
struct ResolveAllTests {
    private func makeStore() async throws -> (PersistenceController, TaskStore) {
        let p = try await TestStore.make()
        return (p, TaskStore(persistence: p))
    }

    @Test("resolveAll returns one resolution per token, in order")
    func resolvesAllInOrder() async throws {
        let (p, store) = try await makeStore()
        let a = try await store.create(title: "Alpha")
        let b = try await store.create(title: "Beta")
        let resolutions = try await CLIBridge.Resolver.resolveAll(
            tokens: [a.uuidString, b.uuidString],
            scope: .anywhereIncludingClosed,
            destructiveness: .destructive,
            persistence: p
        )
        #expect(resolutions.map(\.id) == [a, b])
    }

    @Test("resolveAll throws on the first unresolvable token before returning anything")
    func throwsOnBadToken() async throws {
        let (p, store) = try await makeStore()
        let a = try await store.create(title: "Alpha")
        await #expect(throws: LillistError.notFound) {
            _ = try await CLIBridge.Resolver.resolveAll(
                tokens: [a.uuidString, "00000000-0000-0000-0000-0000000000ff"],
                scope: .anywhereIncludingClosed,
                destructiveness: .destructive,
                persistence: p
            )
        }
    }

    @Test("resolveAll surfaces a destructive partial-match refusal")
    func throwsOnDestructivePartial() async throws {
        let (p, store) = try await makeStore()
        _ = try await store.create(title: "Buy groceries weekly")
        await #expect(throws: LillistError.self) {
            _ = try await CLIBridge.Resolver.resolveAll(
                tokens: ["groc"],
                scope: .anywhere,
                destructiveness: .destructive,
                persistence: p
            )
        }
    }
}
```

- [ ] **Step 2: Run the test, expect failure.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ResolveAllTests
```

Expected: compile failure — `error: type 'CLIBridge.Resolver' has no member 'resolveAll'`.

- [ ] **Step 3: Implement the minimal change.** In `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift`, insert this method immediately after the closing brace of `resolve(...)` (after the current line 91, before the `resolveExactTitle` doc comment at line 93 — which Task 4 removes):

```swift
        /// Resolves every token to a concrete `Resolution` *before* any caller
        /// mutates. This is the all-or-nothing primitive for destructive stdin
        /// batches: if any token is unresolvable (`.notFound`/`.ambiguous`) or
        /// refused (destructive partial match), this throws and the caller has
        /// performed zero mutations. Resolutions are returned in token order.
        public static func resolveAll(
            tokens: [String],
            scope: Scope,
            destructiveness: Destructiveness,
            persistence: PersistenceController
        ) async throws -> [Resolution] {
            var resolutions: [Resolution] = []
            resolutions.reserveCapacity(tokens.count)
            for token in tokens {
                let resolution = try await resolve(
                    token: token,
                    scope: scope,
                    destructiveness: destructiveness,
                    persistence: persistence
                )
                resolutions.append(resolution)
            }
            return resolutions
        }
```

- [ ] **Step 4: Run the test, expect pass.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ResolveAllTests
```

Expected: `Test Suite 'CLIBridge.Resolver.resolveAll' passed` with 3 tests passing.

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/ResolveAllTests.swift && git commit -m "feat(cli): add Resolver.resolveAll for all-or-nothing batch pre-resolution

Pre-resolve every token to a concrete UUID before any caller mutates, so
a single bad token in a destructive stdin batch aborts with zero side
effects. Closes cli-2 (resolution primitive)."
```

---

### Task 2: Extract the duplicated stdin-parse block into one `BatchTokens` helper (cli-3)

**Files:**
- Create `Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift`
- Create `Packages/LillistCore/Tests/lillistCLITests/BatchTokensTests.swift`

- [ ] **Step 1: Write the failing test.** Create `Packages/LillistCore/Tests/lillistCLITests/BatchTokensTests.swift`:

```swift
import Testing
import Foundation
import LillistCore
@testable import lillist_cli

@Suite("CLI BatchTokens")
struct BatchTokensTests {
    @Test("Non-sentinel token returns a single-element list verbatim")
    func singleToken() throws {
        let tokens = try BatchTokens.resolveInput(
            token: "Buy milk",
            stdin: { [] },
            destructiveGate: .requireUUIDs,
            allowFuzzy: false
        )
        #expect(tokens == ["Buy milk"])
    }

    @Test("Sentinel reads from stdin when the read-only gate is in effect")
    func stdinReadOnly() throws {
        let tokens = try BatchTokens.resolveInput(
            token: "-",
            stdin: { ["alpha", "beta"] },
            destructiveGate: .none,
            allowFuzzy: false
        )
        #expect(tokens == ["alpha", "beta"])
    }

    @Test("Destructive gate rejects non-UUID stdin lines unless allowed")
    func destructiveRejectsNonUUID() throws {
        #expect(throws: LillistError.self) {
            _ = try BatchTokens.resolveInput(
                token: "-",
                stdin: { ["not-a-uuid"] },
                destructiveGate: .requireUUIDs,
                allowFuzzy: false
            )
        }
    }

    @Test("Destructive gate is bypassed by allowFuzzy")
    func destructiveAllowFuzzy() throws {
        let tokens = try BatchTokens.resolveInput(
            token: "-",
            stdin: { ["not-a-uuid"] },
            destructiveGate: .requireUUIDs,
            allowFuzzy: true
        )
        #expect(tokens == ["not-a-uuid"])
    }

    @Test("Destructive gate accepts all-UUID stdin")
    func destructiveAcceptsUUIDs() throws {
        let u = UUID().uuidString
        let tokens = try BatchTokens.resolveInput(
            token: "-",
            stdin: { [u] },
            destructiveGate: .requireUUIDs,
            allowFuzzy: false
        )
        #expect(tokens == [u])
    }
}
```

- [ ] **Step 2: Run the test, expect failure.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter BatchTokensTests
```

Expected: compile failure — `error: cannot find 'BatchTokens' in scope`.

- [ ] **Step 3: Implement the minimal change.** Create `Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift`:

```swift
import Foundation
import LillistCore

/// Turns a positional task token into the list of tokens a batch command
/// should act on, centralizing the previously-duplicated
/// `if StdinReader.isStdinSentinel(...)` block. When the token is the stdin
/// sentinel (`-`), lines are read from `stdin`; otherwise the literal token is
/// returned as a single-element list.
///
/// Destructive verbs (delete, purge, move, status→closed) pass
/// `.requireUUIDs`, which rejects non-UUID stdin lines unless `allowFuzzy`
/// (the `--allow-fuzzy-from-stdin` flag) is set. Read-only callers pass
/// `.none`.
public enum BatchTokens {
    /// Whether stdin lines must be UUIDs for a destructive verb.
    public enum DestructiveGate {
        case none
        case requireUUIDs
    }

    /// Resolves the input token(s) for a batch command.
    ///
    /// - Parameters:
    ///   - token: The positional argument (`-` means "read stdin").
    ///   - stdin: Reader closure returning trimmed, non-empty stdin lines.
    ///     Injectable so tests don't touch the process's standard input.
    ///   - destructiveGate: UUID requirement for stdin lines.
    ///   - allowFuzzy: Bypasses `.requireUUIDs` when true.
    public static func resolveInput(
        token: String,
        stdin: () -> [String] = StdinReader.readAllLines,
        destructiveGate: DestructiveGate,
        allowFuzzy: Bool
    ) throws -> [String] {
        guard StdinReader.isStdinSentinel(token) else {
            return [token]
        }
        let raw = stdin()
        switch destructiveGate {
        case .none:
            return raw
        case .requireUUIDs:
            return allowFuzzy ? raw : (try StdinReader.validateAllUUIDs(raw))
        }
    }
}
```

- [ ] **Step 4: Run the test, expect pass.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter BatchTokensTests
```

Expected: `Test Suite 'CLI BatchTokens' passed` with 5 tests passing.

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift Packages/LillistCore/Tests/lillistCLITests/BatchTokensTests.swift && git commit -m "feat(cli): extract BatchTokens helper for stdin-batch input parsing

Centralize the duplicated 'is stdin? validate UUIDs?' block that five
destructive commands repeated, with an injectable stdin reader for
testability. Closes cli-3 (helper)."
```

---

### Task 3: Make destructive batch commands all-or-nothing via `BatchTokens` + `resolveAll` (cli-2, cli-3)

This task rewires `DeleteCommand`, `PurgeCommand`, `MoveCommand`, `StatusCommand`, and `RestoreCommand` to (a) use `BatchTokens` and (b) pre-resolve every token before mutating, so a bad token mid-batch leaves zero side effects. The end-to-end atomicity behavior is verified at the handler level in Task 6; here we land the source rewrites and confirm the existing handler suite still passes.

**Files:**
- Modify `Packages/LillistCore/Sources/lillist-cli/Commands/DeleteCommand.swift` (lines 11–23)
- Modify `Packages/LillistCore/Sources/lillist-cli/Commands/PurgeCommand.swift` (lines 11–23)
- Modify `Packages/LillistCore/Sources/lillist-cli/Commands/MoveCommand.swift` (lines 13–25)
- Modify `Packages/LillistCore/Sources/lillist-cli/Commands/StatusCommand.swift` (lines 28–48)
- Modify `Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift` (lines 11–23)

- [ ] **Step 1: Rewrite `DeleteCommand.run`.** Replace the body of `run()` (current lines 11–23) in `Packages/LillistCore/Sources/lillist-cli/Commands/DeleteCommand.swift`:

```swift
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let tokens = try BatchTokens.resolveInput(
            token: token,
            destructiveGate: .requireUUIDs,
            allowFuzzy: allowFuzzy
        )
        // Pre-resolve all tokens so a single bad token aborts before any
        // mutation (all-or-nothing).
        let resolutions = try await CLIBridge.Resolver.resolveAll(
            tokens: tokens,
            scope: .anywhereIncludingClosed,
            destructiveness: .destructive,
            persistence: p
        )
        let store = TaskStore(persistence: p)
        for r in resolutions {
            try await store.softDelete(id: r.id)
        }
    }
```

- [ ] **Step 2: Rewrite `PurgeCommand.run`.** Replace the body of `run()` (current lines 11–23) in `Packages/LillistCore/Sources/lillist-cli/Commands/PurgeCommand.swift`:

```swift
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let tokens = try BatchTokens.resolveInput(
            token: token,
            destructiveGate: .requireUUIDs,
            allowFuzzy: allowFuzzy
        )
        let resolutions = try await CLIBridge.Resolver.resolveAll(
            tokens: tokens,
            scope: .anywhereIncludingClosed,
            destructiveness: .destructive,
            persistence: p
        )
        let store = TaskStore(persistence: p)
        for r in resolutions {
            try await store.hardDelete(id: r.id)
        }
    }
```

- [ ] **Step 3: Rewrite `MoveCommand.run`.** Replace the body of `run()` (current lines 13–25) in `Packages/LillistCore/Sources/lillist-cli/Commands/MoveCommand.swift`. The new-parent token is resolved once up front and reused for the whole batch, and the missing-parent validation fires before any mutation:

```swift
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let tokens = try BatchTokens.resolveInput(
            token: token,
            destructiveGate: .requireUUIDs,
            allowFuzzy: allowFuzzy
        )
        // Resolve the destination parent up front (once for the batch).
        let newParent: UUID?
        if root {
            newParent = nil
        } else if let pt = newParent {
            let pr = try await CLIBridge.Resolver.resolve(
                token: pt, scope: .anywhereIncludingClosed,
                destructiveness: .destructive, persistence: p
            )
            newParent = pr.id
        } else {
            throw LillistError.validationFailed([
                .init(field: "parent", message: "must specify a new parent or --root")
            ])
        }
        // Pre-resolve every moved token before mutating (all-or-nothing).
        let resolutions = try await CLIBridge.Resolver.resolveAll(
            tokens: tokens,
            scope: .anywhereIncludingClosed,
            destructiveness: .destructive,
            persistence: p
        )
        let store = TaskStore(persistence: p)
        for r in resolutions {
            try await store.reparent(id: r.id, newParent: newParent)
        }
    }
```

> Note: this introduces a local `newParent: UUID?` that shadows the `@Argument var newParent: String?`. Rename the local to `newParentID` to avoid the shadow:
> - replace `let newParent: UUID?` with `let newParentID: UUID?`
> - replace the three `newParent = ...` assignments with `newParentID = ...`
> - replace `} else if let pt = newParent {` with `} else if let pt = newParent {` (this `newParent` is the `@Argument` — leave it)
> - replace `try await store.reparent(id: r.id, newParent: newParent)` with `try await store.reparent(id: r.id, newParent: newParentID)`
>
> The corrected body is:

```swift
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let tokens = try BatchTokens.resolveInput(
            token: token,
            destructiveGate: .requireUUIDs,
            allowFuzzy: allowFuzzy
        )
        let newParentID: UUID?
        if root {
            newParentID = nil
        } else if let pt = newParent {
            let pr = try await CLIBridge.Resolver.resolve(
                token: pt, scope: .anywhereIncludingClosed,
                destructiveness: .destructive, persistence: p
            )
            newParentID = pr.id
        } else {
            throw LillistError.validationFailed([
                .init(field: "parent", message: "must specify a new parent or --root")
            ])
        }
        let resolutions = try await CLIBridge.Resolver.resolveAll(
            tokens: tokens,
            scope: .anywhereIncludingClosed,
            destructiveness: .destructive,
            persistence: p
        )
        let store = TaskStore(persistence: p)
        for r in resolutions {
            try await store.reparent(id: r.id, newParent: newParentID)
        }
    }
```

- [ ] **Step 4: Rewrite `StatusCommand.run`.** Replace the body of `run()` (current lines 28–48) in `Packages/LillistCore/Sources/lillist-cli/Commands/StatusCommand.swift`. The closed transition is destructive; everything else is read-only. Pre-resolve before transitioning:

```swift
    public func run() async throws {
        guard let s = CLIBridge.AddHandler.status(from: newStatus) else {
            throw LillistError.validationFailed([.init(field: "status", message: "unknown '\(newStatus)'")])
        }
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let destructive = (s == .closed)
        let tokens = try BatchTokens.resolveInput(
            token: token,
            destructiveGate: destructive ? .requireUUIDs : .none,
            allowFuzzy: allowFuzzy
        )
        let resolutions = try await CLIBridge.Resolver.resolveAll(
            tokens: tokens,
            scope: .anywhereIncludingClosed,
            destructiveness: destructive ? .destructive : .readOnly,
            persistence: p
        )
        let tasks = TaskStore(persistence: p)
        let journal = JournalStore(persistence: p)
        for r in resolutions {
            try await tasks.transition(id: r.id, to: s)
            if let body = note, body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                _ = try await journal.appendNote(taskID: r.id, body: body)
            }
        }
    }
```

- [ ] **Step 5: Rewrite `RestoreCommand.run`.** Restore resolves through the trash list inside `RestoreHandler` (trashed tasks aren't in the resolver's default scope), so we keep the handler but front-load batch input parsing and a pre-flight existence check. Replace the body of `run()` (current lines 11–23) in `Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift`:

```swift
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let tokens = try BatchTokens.resolveInput(
            token: token,
            destructiveGate: .requireUUIDs,
            allowFuzzy: allowFuzzy
        )
        // Pre-flight: confirm every token resolves to a trashed task before
        // restoring any (all-or-nothing). RestoreHandler.run repeats the
        // resolution against the trash list; the pre-flight throws first on a
        // bad token so partial restores can't happen.
        let trashed = try await TaskStore(persistence: p).trashed()
        for t in tokens {
            try CLIBridge.RestoreHandler.preflight(token: t, trashed: trashed)
        }
        for t in tokens {
            try await CLIBridge.RestoreHandler.run(token: t, persistence: p)
        }
    }
```

> This references `RestoreHandler.preflight(token:trashed:)`, which does not yet exist. It is added in Task 6 (Step 3) before `BatchAtomicityTests` runs. To keep this task independently buildable, add the `preflight` helper now as part of this step — open `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift` and replace the whole file with:

```swift
import Foundation
import CoreData

extension CLIBridge {
    public enum RestoreHandler {
        public static func run(token: String, persistence: PersistenceController) async throws {
            // Trashed tasks aren't in the default scope; resolve directly through the trash list.
            let trashed = try await TaskStore(persistence: persistence).trashed()
            let id = try resolveTrashed(token: token, trashed: trashed)
            try await TaskStore(persistence: persistence).restore(id: id)
        }

        /// Throws if `token` does not resolve to exactly one trashed task.
        /// Used by the batch `restore` command to confirm every token is
        /// restorable before restoring any (all-or-nothing).
        public static func preflight(token: String, trashed: [TaskStore.TaskRecord]) throws {
            _ = try resolveTrashed(token: token, trashed: trashed)
        }

        /// Resolves a token against the trash list: full UUID, else exact
        /// (case-insensitive) title. Throws `.notFound`/`.ambiguous`.
        static func resolveTrashed(token: String, trashed: [TaskStore.TaskRecord]) throws -> UUID {
            if let parsed = UUID(uuidString: token) {
                guard trashed.contains(where: { $0.id == parsed }) else { throw LillistError.notFound }
                return parsed
            }
            let lower = token.lowercased()
            let exact = trashed.filter { $0.title.lowercased() == lower }
            guard exact.isEmpty == false else { throw LillistError.notFound }
            if exact.count > 1 { throw LillistError.ambiguous(exact.map(\.id)) }
            return exact[0].id
        }
    }
}
```

- [ ] **Step 6: Build and run the existing CLI + handler suites, expect pass.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | tail -5 && swift test --package-path Packages/LillistCore --filter "DeleteRestorePurgeHandlerTests|StatusHandlerTests|StdinReaderTests"
```

Expected: a clean build (no warnings, since warnings are errors) and all three suites passing — the rewrites preserve behavior on single-token and well-formed batches.

- [ ] **Step 7: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/lillist-cli/Commands/DeleteCommand.swift Packages/LillistCore/Sources/lillist-cli/Commands/PurgeCommand.swift Packages/LillistCore/Sources/lillist-cli/Commands/MoveCommand.swift Packages/LillistCore/Sources/lillist-cli/Commands/StatusCommand.swift Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift && git commit -m "refactor(cli): make destructive batches all-or-nothing via BatchTokens + resolveAll

Delete/purge/move/status-closed/restore now parse stdin once through
BatchTokens and pre-resolve every token before mutating, so a bad token
mid-batch leaves zero side effects. Closes cli-2, cli-3 (commands)."
```

---

### Task 4: Remove the dead `--exact` mention + unused `resolveExactTitle`, and rewrite the destructive-ambiguity error (cli-4, cli-5)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift` (delete lines 93–105 `resolveExactTitle`; rewrite the error string at line 84)
- Modify `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/ResolverTests.swift` (add an assertion on the rewritten message)

- [ ] **Step 1: Write the failing test.** Add this test to `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/ResolverTests.swift`, immediately before the closing `}` of the `ResolverTests` struct (after the `shortIDs` test, current lines 228–236):

```swift
    @Test("Destructive partial-match error points at the real working path, not the dead --exact flag")
    func destructivePartialErrorMessage() async throws {
        let (p, store) = try await makeStore()
        _ = try await store.create(title: "Buy groceries weekly")
        do {
            _ = try await CLIBridge.Resolver.resolve(
                token: "groc",
                scope: .anywhere,
                destructiveness: .destructive,
                persistence: p
            )
            Issue.record("expected validationFailed")
        } catch let LillistError.validationFailed(issues) {
            let combined = issues.map(\.message).joined(separator: " ")
            #expect(combined.contains("--exact") == false)
            #expect(combined.contains("full title") || combined.contains("UUID"))
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }
```

- [ ] **Step 2: Run the test, expect failure.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "destructivePartialErrorMessage"
```

Expected: failure — the current message at Resolver.swift:84 contains `Use --exact "<title>"`, so `combined.contains("--exact") == false` fails with `Expectation failed`.

- [ ] **Step 3: Implement the minimal change.** In `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift`:

  (a) Replace the error message at the destructive-substring branch (current lines 82–86):

```swift
                if destructiveness == .destructive {
                    throw LillistError.validationFailed([
                        .init(field: "task", message: "destructive verbs require a UUID or exact title; '\(trimmed)' only partially matched. Pass the full title or the task's UUID (run `lillist ls` to find it).")
                    ])
                }
```

  (b) Delete the dead `resolveExactTitle` method entirely (current lines 93–105 — the `/// Resolves an exact-title bypass token (from --exact).` doc comment through its closing brace). After deletion, the `shortestUniqueShortIDs` doc comment (currently line 107) follows directly after `resolve`/`resolveAll`.

- [ ] **Step 4: Run the test, expect pass.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "ResolverTests"
```

Expected: the full `CLIBridge.Resolver` suite passes, including the new `destructivePartialErrorMessage` and the existing `destructiveRefusesPartial`. Also confirm no callers broke:

```bash
cd /Volumes/Code/mikeyward/Lillist && grep -rn "resolveExactTitle\|--exact" Packages/LillistCore/Sources Packages/LillistCore/Tests
```

Expected: no matches (zero output).

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/ResolverTests.swift && git commit -m "refactor(cli): drop dead resolveExactTitle and --exact, fix destructive error copy

resolveExactTitle had no callers and --exact is not a real flag; the
destructive partial-match error now points at the working path (full
title or UUID via 'lillist ls'). Closes cli-4, cli-5."
```

---

### Task 5: Byte-exact golden tests for json/ndjson/tsv across Task/Tag/Journal renderers (cli-5)

The existing `GoldenOutputTests` only cover `prettyTree` and use `normalize()` (which trims whitespace) plus random UUIDs, so they cannot pin the structured formats byte-for-byte. This task adds fixed-UUID/fixed-date fixtures and **un-normalized** assertions for json/ndjson/tsv, including the TSV header and an embedded-tab title/name.

**Files:**
- Create `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-json.txt`
- Create `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-ndjson.txt`
- Create `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-tsv.txt`
- Create `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/tag-json.txt`
- Create `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/tag-ndjson.txt`
- Create `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/tag-tsv.txt`
- Create `Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/journal-json.txt`
- Modify `Packages/LillistCore/Tests/lillistCLITests/GoldenOutputTests.swift`

> **Renderer surface confirmed by reading the sources:** `TaskRenderer` has `json`/`ndjson`/`tsv`; `TagRenderer` has `json`/`ndjson`/`tsv`; `JournalRenderer` has only `json` (no `ndjson`/`tsv`). YAGNI: we golden exactly the formats each renderer ships — we do **not** add new renderer methods.

> **Encoder behaviors verified empirically** (so the fixtures are exact): `.iso8601` renders `Date(timeIntervalSince1970: 1_700_000_000)` as `2023-11-14T22:13:20Z`; `.sortedKeys` orders keys alphabetically; a `nil` optional is **omitted** from JSON output (the key disappears); `position: 1.0` encodes as `1`; the TSV writer replaces embedded `\t` in titles/names with a single space.

- [ ] **Step 1: Write the failing test.** Replace the entire contents of `Packages/LillistCore/Tests/lillistCLITests/GoldenOutputTests.swift` with the following. It keeps the three existing prettyTree snapshot tests verbatim and adds byte-exact (un-normalized) golden tests using fixed UUIDs and a fixed date:

```swift
import Testing
import Foundation
@testable import LillistCore
@testable import lillist_cli

@Suite("Golden output snapshots")
struct GoldenOutputTests {
    // Fixed inputs so structured-output goldens are byte-stable.
    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
    private static let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private func snapshotData(named: String) throws -> String {
        let url = Bundle.module.url(forResource: named, withExtension: "txt", subdirectory: "snapshots")
            ?? Bundle.module.url(forResource: named, withExtension: "txt")
        guard let url else {
            throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "missing snapshot \(named)"])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func record(_ title: String, parentID: UUID? = nil, position: Double = 1.0, status: Status = .todo) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: UUID(), title: title, notes: "", status: status,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: position, isPinned: false, parentID: parentID,
            createdAt: nil, modifiedAt: nil, closedAt: nil, deletedAt: nil
        )
    }

    // Fixed-input task records used by the structured-output goldens.
    private func goldenTasks() -> [TaskStore.TaskRecord] {
        [
            TaskStore.TaskRecord(
                id: Self.id1, title: "Buy\tmilk", notes: "", status: .todo,
                start: Self.fixedDate, startHasTime: true, deadline: nil, deadlineHasTime: false,
                position: 1.0, isPinned: false, parentID: nil,
                createdAt: Self.fixedDate, modifiedAt: Self.fixedDate, closedAt: nil, deletedAt: nil
            ),
            TaskStore.TaskRecord(
                id: Self.id2, title: "Plain", notes: "", status: .closed,
                start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
                position: 2.0, isPinned: true, parentID: Self.id1,
                createdAt: Self.fixedDate, modifiedAt: Self.fixedDate, closedAt: Self.fixedDate, deletedAt: nil
            )
        ]
    }

    private func goldenTags() -> [TagStore.TagRecord] {
        [
            TagStore.TagRecord(id: Self.id1, name: "Wo\trk", tintColor: "#FF0000", parentID: nil, position: 1.0),
            TagStore.TagRecord(id: Self.id2, name: "Email", tintColor: nil, parentID: Self.id1, position: 2.0)
        ]
    }

    private func goldenJournal() -> [JournalStore.JournalRecord] {
        [
            JournalStore.JournalRecord(
                id: Self.id1, taskID: Self.id2, kind: .note, body: "first note",
                payload: nil, createdAt: Self.fixedDate, editedAt: nil
            )
        ]
    }

    // MARK: - Pretty tree (existing, normalized)

    @Test("Flat ls matches snapshot")
    func lsFlat() throws {
        let records = [
            record("Alpha", position: 1),
            record("Beta", position: 2),
            record("Gamma", position: 3)
        ]
        let rendered = CLIBridge.TaskRenderer.prettyTree(records, color: false)
        #expect(normalize(rendered) == normalize(try snapshotData(named: "ls-flat")))
    }

    @Test("Nested ls matches snapshot")
    func lsNested() throws {
        let parent = record("Project", position: 1)
        let s1 = record("Step 1", parentID: parent.id, position: 1)
        let s2 = record("Step 2", parentID: parent.id, position: 2, status: .started)
        let rendered = CLIBridge.TaskRenderer.prettyTree([parent, s1, s2], color: false)
        #expect(normalize(rendered) == normalize(try snapshotData(named: "ls-nested")))
    }

    @Test("Tags tree matches snapshot")
    func tagsTree() throws {
        let work = TagStore.TagRecord(id: UUID(), name: "Work", tintColor: nil, parentID: nil, position: 1)
        let email = TagStore.TagRecord(id: UUID(), name: "Email", tintColor: nil, parentID: work.id, position: 1)
        let home = TagStore.TagRecord(id: UUID(), name: "Home", tintColor: nil, parentID: nil, position: 2)
        let rendered = CLIBridge.TagRenderer.prettyTree([work, email, home], color: false)
        #expect(normalize(rendered) == normalize(try snapshotData(named: "tags-tree")))
    }

    // MARK: - Structured output (new, byte-exact)

    @Test("Task JSON is byte-exact")
    func taskJSON() throws {
        let rendered = try CLIBridge.TaskRenderer.jsonString(goldenTasks())
        #expect(rendered == (try snapshotData(named: "task-json")))
    }

    @Test("Task NDJSON is byte-exact")
    func taskNDJSON() throws {
        let rendered = try CLIBridge.TaskRenderer.ndjson(goldenTasks())
        #expect(rendered == (try snapshotData(named: "task-ndjson")))
    }

    @Test("Task TSV is byte-exact, incl. header and embedded-tab title")
    func taskTSV() throws {
        let rendered = try CLIBridge.TaskRenderer.tsv(goldenTasks())
        #expect(rendered == (try snapshotData(named: "task-tsv")))
    }

    @Test("Tag JSON is byte-exact")
    func tagJSON() throws {
        let data = try CLIBridge.TagRenderer.json(goldenTags())
        let rendered = String(data: data, encoding: .utf8) ?? ""
        #expect(rendered == (try snapshotData(named: "tag-json")))
    }

    @Test("Tag NDJSON is byte-exact")
    func tagNDJSON() throws {
        let rendered = try CLIBridge.TagRenderer.ndjson(goldenTags())
        #expect(rendered == (try snapshotData(named: "tag-ndjson")))
    }

    @Test("Tag TSV is byte-exact, incl. header and embedded-tab name")
    func tagTSV() throws {
        let rendered = CLIBridge.TagRenderer.tsv(goldenTags())
        #expect(rendered == (try snapshotData(named: "tag-tsv")))
    }

    @Test("Journal JSON is byte-exact")
    func journalJSON() throws {
        let data = try CLIBridge.JournalRenderer.json(goldenJournal())
        let rendered = String(data: data, encoding: .utf8) ?? ""
        #expect(rendered == (try snapshotData(named: "journal-json")))
    }
}
```

> **Note:** `TagRenderer.tsv` does *not* fold embedded tabs (it joins raw fields). The fixed input name `"Wo\trk"` therefore lands a literal tab inside the name field, which is the honest current behavior the golden pins. If a future hardening pass folds tabs in tag TSV, this golden is the test that will flag the change — exactly its job.

- [ ] **Step 2: Run the test, expect failure.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "GoldenOutputTests"
```

Expected: the seven new tests fail with `missing snapshot task-json` (etc.) NSError, since the fixtures don't exist yet. The three prettyTree tests still pass.

- [ ] **Step 3: Create the fixtures with byte-exact content.** Create each file with EXACTLY the bytes below (no trailing newline beyond what is shown; these were produced from the real encoders against the fixed inputs).

`Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-json.txt`:

```
[
  {
    "createdAt" : "2023-11-14T22:13:20Z",
    "deadlineHasTime" : false,
    "id" : "00000000-0000-0000-0000-000000000001",
    "isPinned" : false,
    "modifiedAt" : "2023-11-14T22:13:20Z",
    "notes" : "",
    "position" : 1,
    "start" : "2023-11-14T22:13:20Z",
    "startHasTime" : true,
    "status" : "todo",
    "title" : "Buy\tmilk"
  },
  {
    "closedAt" : "2023-11-14T22:13:20Z",
    "createdAt" : "2023-11-14T22:13:20Z",
    "deadlineHasTime" : false,
    "id" : "00000000-0000-0000-0000-000000000002",
    "isPinned" : true,
    "modifiedAt" : "2023-11-14T22:13:20Z",
    "notes" : "",
    "parentID" : "00000000-0000-0000-0000-000000000001",
    "position" : 2,
    "startHasTime" : false,
    "status" : "closed",
    "title" : "Plain"
  }
]
```

> The `\t` in `"Buy\tmilk"` above is a literal TAB byte inside the JSON string — JSON escapes it as `\t`. When creating the file, type the two characters backslash-`t` (the JSON encoder emits the escape sequence as literal text `\t`, not a raw tab). Verify with the hexdump step below.

`Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-ndjson.txt` (two lines, each terminated by `\n`; the file ends with a trailing newline):

```
{"createdAt":"2023-11-14T22:13:20Z","deadlineHasTime":false,"id":"00000000-0000-0000-0000-000000000001","isPinned":false,"modifiedAt":"2023-11-14T22:13:20Z","notes":"","position":1,"start":"2023-11-14T22:13:20Z","startHasTime":true,"status":"todo","title":"Buy\tmilk"}
{"closedAt":"2023-11-14T22:13:20Z","createdAt":"2023-11-14T22:13:20Z","deadlineHasTime":false,"id":"00000000-0000-0000-0000-000000000002","isPinned":true,"modifiedAt":"2023-11-14T22:13:20Z","notes":"","parentID":"00000000-0000-0000-0000-000000000001","position":2,"startHasTime":false,"status":"closed","title":"Plain"}
```

`Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-tsv.txt` (header + two rows; fields are separated by **literal TAB bytes**; embedded tab in `Buy\tmilk` folded to a single space ⇒ `Buy milk`; file ends with a trailing newline):

```
id	title	status	start	deadline	isPinned	parentID
00000000-0000-0000-0000-000000000001	Buy milk	todo	2023-11-14T22:13:20Z		false	
00000000-0000-0000-0000-000000000002	Plain	closed			true	00000000-0000-0000-0000-000000000001
```

`Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/tag-json.txt` (TagRenderer.json uses `[.sortedKeys, .prettyPrinted]` and **no** date strategy — tags have no dates):

```
[
  {
    "id" : "00000000-0000-0000-0000-000000000001",
    "name" : "Wo\trk",
    "position" : 1,
    "tintColor" : "#FF0000"
  },
  {
    "id" : "00000000-0000-0000-0000-000000000002",
    "name" : "Email",
    "parentID" : "00000000-0000-0000-0000-000000000001",
    "position" : 2
  }
]
```

`Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/tag-ndjson.txt` (trailing newline):

```
{"id":"00000000-0000-0000-0000-000000000001","name":"Wo\trk","position":1,"tintColor":"#FF0000"}
{"id":"00000000-0000-0000-0000-000000000002","name":"Email","parentID":"00000000-0000-0000-0000-000000000001","position":2}
```

`Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/tag-tsv.txt` (header `id\tname\tparentID\ttintColor`; TagRenderer.tsv does **not** fold tabs, so `Wo\trk` keeps its literal tab — meaning the first data row has an extra TAB inside the name field; trailing newline):

```
id	name	parentID	tintColor
00000000-0000-0000-0000-000000000001	Wo	rk		#FF0000
00000000-0000-0000-0000-000000000002	Email	00000000-0000-0000-0000-000000000001	
```

> In `tag-tsv.txt` the first data row reads `<uuid>\tWo\trk\t\t#FF0000` — the `Wo<TAB>rk` is the unfolded name. This is the current (honest) behavior the golden pins.

`Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/journal-json.txt` (JournalRenderer.json uses `[.sortedKeys, .prettyPrinted]` with `.iso8601`; `editedAt` is nil ⇒ omitted; `kind` renders via `String(describing:)` ⇒ `note`):

```
[
  {
    "body" : "first note",
    "createdAt" : "2023-11-14T22:13:20Z",
    "id" : "00000000-0000-0000-0000-000000000001",
    "kind" : "note",
    "taskID" : "00000000-0000-0000-0000-000000000002"
  }
]
```

- [ ] **Step 4: Verify the fixtures byte-exactly, then run the test, expect pass.** First confirm the literal-tab vs `\t`-escape bytes are correct using hexdump (TAB is `09`; backslash-t is `5c 74`):

```bash
cd /Volumes/Code/mikeyward/Lillist && \
  grep -c $'\t' Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-tsv.txt && \
  grep -c '\\t' Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-json.txt
```

Expected: `3` (every TSV line contains literal tabs) and `1` (one JSON line carries the `\t` escape). Then:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "GoldenOutputTests"
```

Expected: all 10 tests in `Golden output snapshots` pass.

> If any structured-output test fails on a byte mismatch, **do not hand-fix the fixture blindly.** Regenerate the exact bytes from the real renderer and overwrite the fixture:
> ```bash
> cd /Volumes/Code/mikeyward/Lillist && swift run --package-path Packages/LillistCore lillist version >/dev/null 2>&1 # ensure target builds
> ```
> then re-derive via a throwaway `@Test` that prints `CLIBridge.TaskRenderer.jsonString(goldenTasks())` and copy the bytes. The fixture is the source of truth for the *expected* output; the renderer is the *actual*. They must match exactly.

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Tests/lillistCLITests/GoldenOutputTests.swift Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-json.txt Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-ndjson.txt Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/task-tsv.txt Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/tag-json.txt Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/tag-ndjson.txt Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/tag-tsv.txt Packages/LillistCore/Tests/lillistCLITests/Fixtures/snapshots/journal-json.txt && git commit -m "test(cli): byte-exact golden tests for json/ndjson/tsv (task/tag/journal)

Fixed-UUID/fixed-date fixtures asserted without normalization, covering
the TSV header and an embedded-tab title/name. Closes cli-5 (goldens)."
```

---

### Task 6: End-to-end handler-level atomicity tests for destructive batches (cli-2)

This proves the all-or-nothing guarantee through the *command* path, not just the resolver. Because the commands read process stdin, the tests drive the same primitives the commands call (`BatchTokens.resolveInput` with an injected reader + `Resolver.resolveAll` + the store mutations), asserting zero side effects when one token is bad.

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/BatchAtomicityTests.swift`

- [ ] **Step 1: Write the failing test.** Create `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/BatchAtomicityTests.swift`. (This lives in the `LillistCoreTests` target, which sees `CLIBridge` but not the `lillist-cli` target's `BatchTokens`; it therefore models the batch through the public `Resolver.resolveAll` + store APIs the commands use.)

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge destructive batch atomicity")
struct BatchAtomicityTests {
    /// Mirrors DeleteCommand.run's resolve-then-mutate shape with no stdin.
    private func deleteBatch(_ tokens: [String], persistence: PersistenceController) async throws {
        let resolutions = try await CLIBridge.Resolver.resolveAll(
            tokens: tokens,
            scope: .anywhereIncludingClosed,
            destructiveness: .destructive,
            persistence: persistence
        )
        let store = TaskStore(persistence: persistence)
        for r in resolutions {
            try await store.softDelete(id: r.id)
        }
    }

    @Test("A delete batch with one bad token deletes nothing")
    func deleteBatchAtomic() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "Alpha")
        let b = try await store.create(title: "Beta")
        await #expect(throws: LillistError.notFound) {
            try await deleteBatch(
                [a.uuidString, "00000000-0000-0000-0000-0000000000ff", b.uuidString],
                persistence: p
            )
        }
        // Neither task should be trashed: the bad token aborts before mutation.
        let trashed = try await store.trashed()
        #expect(trashed.isEmpty)
    }

    @Test("A purge batch with one bad token purges nothing")
    func purgeBatchAtomic() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "Alpha")
        let b = try await store.create(title: "Beta")
        let resolutionsThrew: Bool
        do {
            let resolutions = try await CLIBridge.Resolver.resolveAll(
                tokens: [a.uuidString, "deadbeef-0000-0000-0000-000000000000", b.uuidString],
                scope: .anywhereIncludingClosed,
                destructiveness: .destructive,
                persistence: p
            )
            for r in resolutions { try await store.hardDelete(id: r.id) }
            resolutionsThrew = false
        } catch {
            resolutionsThrew = true
        }
        #expect(resolutionsThrew)
        // Both tasks still fetchable: nothing was hard-deleted.
        let recA = try await store.fetch(id: a)
        let recB = try await store.fetch(id: b)
        #expect(recA.id == a)
        #expect(recB.id == b)
    }

    @Test("A status->closed batch with one bad token closes nothing")
    func statusClosedBatchAtomic() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "Alpha")
        let b = try await store.create(title: "Beta")
        await #expect(throws: LillistError.notFound) {
            let resolutions = try await CLIBridge.Resolver.resolveAll(
                tokens: [a.uuidString, "00000000-0000-0000-0000-0000000000ff", b.uuidString],
                scope: .anywhereIncludingClosed,
                destructiveness: .destructive,
                persistence: p
            )
            for r in resolutions { try await store.transition(id: r.id, to: .closed) }
        }
        let recA = try await store.fetch(id: a)
        let recB = try await store.fetch(id: b)
        #expect(recA.status != .closed)
        #expect(recB.status != .closed)
    }

    @Test("RestoreHandler.preflight throws on a non-trashed token so a restore batch aborts whole")
    func restorePreflightAtomic() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "Alpha")
        try await store.softDelete(id: a)
        let b = try await store.create(title: "Beta") // never trashed
        let trashed = try await store.trashed()
        // a resolves; b does not -> preflight throws before any restore.
        #expect(throws: LillistError.notFound) {
            try CLIBridge.RestoreHandler.preflight(token: b.uuidString, trashed: trashed)
        }
        // Sanity: a really is restorable.
        try CLIBridge.RestoreHandler.preflight(token: a.uuidString, trashed: trashed)
    }
}
```

- [ ] **Step 2: Run the test, expect pass.** (Tasks 1 and 3 already added `resolveAll` and `RestoreHandler.preflight`, so this suite should pass on first run — it documents and locks the atomicity guarantee end-to-end.)

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "BatchAtomicityTests"
```

Expected: `Test Suite 'CLIBridge destructive batch atomicity' passed` with 4 tests passing.

- [ ] **Step 3: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/BatchAtomicityTests.swift && git commit -m "test(cli): handler-level atomicity tests for destructive stdin batches

One bad token in a delete/purge/status-closed/restore batch leaves zero
side effects. Closes cli-2 (end-to-end proof)."
```

---

### Task 7: Replace `watch`'s unbounded detached-Task observer with a serialized, debounced, deduplicating, error-surfacing observer (cli-6)

The current `WatchHandler` spawns a fresh, unstructured `Task { ... }` on every `NSManagedObjectContextObjectsDidChange`. These can interleave (out-of-order emits), re-emit identical snapshots (no dedup), and `catch` swallows every error. The fix funnels notifications into a single serialized actor-driven loop that debounces bursts, dedupes against the last emitted snapshot, and reports errors through a new `onError` closure.

> **Design note (per the review's "or at minimum" clause):** a full `NSFetchedResultsController` adoption requires the FRC and its delegate to live on the `viewContext`'s main queue and to own its own change-tracking — a larger surface than this P3 item warrants, and it would still need the same dedup/serialization layer on top to satisfy the `watch` event contract (emit per-match `update`s, not index paths). We take the review's explicitly-offered minimum: **serialize + debounce + dedup + surface errors**, which closes the three concrete defects (ordering, dedup, error-swallowing) without a speculative FRC rewrite. This honors YAGNI while fixing every named symptom.

> **Strength to preserve:** do **not** convert this to a deferred-`Task` continuation-registration pattern — the engineering-notes lesson about synchronous AsyncStream registration is about *event-bridge* registration races, not this observer. The serialized loop here uses a single long-lived `Task`, registered before parking, which does not reintroduce that race.

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift` (replace the whole file)
- Modify `Packages/LillistCore/Sources/lillist-cli/Commands/WatchCommand.swift` (pass an `onError` closure)
- Create `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/WatchHandlerTests.swift`

- [ ] **Step 1: Write the failing test.** Create `Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/WatchHandlerTests.swift`. The tests drive the new `WatchHandler.snapshotStep` pure function (defined in Step 3) that computes "which records to emit given the previous snapshot," plus the initial-insert behavior:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.WatchHandler")
struct WatchHandlerTests {
    private func record(_ id: UUID, _ title: String, status: Status = .todo) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: id, title: title, notes: "", status: status,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: 1.0, isPinned: false, parentID: nil,
            createdAt: nil, modifiedAt: nil, closedAt: nil, deletedAt: nil
        )
    }

    @Test("First evaluation emits every current record as an update")
    func initialEmitsAll() {
        let a = record(UUID(), "A")
        let b = record(UUID(), "B")
        let (toEmit, next) = CLIBridge.WatchHandler.snapshotStep(previous: nil, current: [a, b])
        #expect(toEmit.map(\.id) == [a.id, b.id])
        #expect(next.count == 2)
    }

    @Test("Unchanged set emits nothing (dedup)")
    func unchangedDedup() {
        let a = record(UUID(), "A")
        let (_, after1) = CLIBridge.WatchHandler.snapshotStep(previous: nil, current: [a])
        let (toEmit, _) = CLIBridge.WatchHandler.snapshotStep(previous: after1, current: [a])
        #expect(toEmit.isEmpty)
    }

    @Test("A changed record re-emits; unchanged siblings stay quiet")
    func changedReemits() {
        let aID = UUID()
        let bID = UUID()
        let a = record(aID, "A")
        let b = record(bID, "B")
        let (_, after1) = CLIBridge.WatchHandler.snapshotStep(previous: nil, current: [a, b])
        let aChanged = record(aID, "A", status: .started)
        let (toEmit, _) = CLIBridge.WatchHandler.snapshotStep(previous: after1, current: [aChanged, b])
        #expect(toEmit.map(\.id) == [aID])
    }

    @Test("A newly matching record emits as an update")
    func newMatchEmits() {
        let aID = UUID()
        let a = record(aID, "A")
        let (_, after1) = CLIBridge.WatchHandler.snapshotStep(previous: nil, current: [a])
        let bID = UUID()
        let b = record(bID, "B")
        let (toEmit, _) = CLIBridge.WatchHandler.snapshotStep(previous: after1, current: [a, b])
        #expect(toEmit.map(\.id) == [bID])
    }
}
```

- [ ] **Step 2: Run the test, expect failure.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "WatchHandlerTests"
```

Expected: compile failure — `error: type 'CLIBridge.WatchHandler' has no member 'snapshotStep'`.

- [ ] **Step 3: Implement the minimal change.** Replace the entire contents of `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift`:

```swift
import Foundation
import CoreData

extension CLIBridge {
    public enum WatchHandler {
        public struct Event: Codable, Sendable {
            public enum Kind: String, Codable, Sendable { case insert, update, delete }
            public let kind: Kind
            public let task: TaskRenderer.TaskDTO
            public let at: Date

            public init(kind: Kind, task: TaskRenderer.TaskDTO, at: Date) {
                self.kind = kind
                self.task = task
                self.at = at
            }
        }

        /// Pure step: given the previously-emitted snapshot (keyed by id) and the
        /// freshly-evaluated current record set, returns the records to emit as
        /// updates and the snapshot to carry forward. A record is emitted when it
        /// is new to the set or differs from its previous value; unchanged records
        /// are suppressed (dedup). Emission order follows `current`.
        ///
        /// `previous == nil` means "first evaluation": every current record is
        /// emitted.
        public static func snapshotStep(
            previous: [UUID: TaskStore.TaskRecord]?,
            current: [TaskStore.TaskRecord]
        ) -> (toEmit: [TaskStore.TaskRecord], next: [UUID: TaskStore.TaskRecord]) {
            var next: [UUID: TaskStore.TaskRecord] = [:]
            next.reserveCapacity(current.count)
            var toEmit: [TaskStore.TaskRecord] = []
            for record in current {
                next[record.id] = record
                if let prev = previous {
                    if prev[record.id] != record {
                        toEmit.append(record)
                    }
                } else {
                    toEmit.append(record)
                }
            }
            return (toEmit, next)
        }

        /// Serializes coalesced re-evaluation requests so context-change bursts
        /// produce one ordered pass, never interleaved detached Tasks.
        private actor Coalescer {
            private var pending = false
            private var running = false

            /// Marks work pending; returns true if the caller should start the
            /// drain loop (i.e. no drain is already running).
            func requestAndShouldStart() -> Bool {
                pending = true
                if running { return false }
                running = true
                return true
            }

            /// Consumes the pending flag at the top of a drain iteration.
            /// Returns false when there is nothing left to do (drain exits).
            func consume() -> Bool {
                if pending {
                    pending = false
                    return true
                }
                running = false
                return false
            }
        }

        /// Streams events for matching tasks. Emits an initial `insert` event for
        /// every record currently matching, then re-evaluates on each
        /// `NSManagedObjectContextObjectsDidChange`. Re-evaluations are serialized
        /// and debounced through a single long-lived drain Task (no per-notification
        /// detached Tasks), deduped against the last emitted snapshot, and any
        /// evaluation error is surfaced via `onError` instead of being swallowed.
        /// The function never returns under normal conditions — the CLI process is
        /// terminated by SIGINT/SIGTERM.
        public static func run(
            flags: FilterFlags,
            savedFilterName: String?,
            persistence: PersistenceController,
            now: Date,
            calendar: Calendar,
            debounce: Duration = .milliseconds(50),
            emit: @escaping @Sendable (Event) -> Void,
            onError: @escaping @Sendable (Error) -> Void = { _ in }
        ) async throws {
            // Bootstrap with the current matching set as inserts.
            let initial = try await LsHandler.run(
                flags: flags, savedFilterName: savedFilterName, sort: .createdAt,
                persistence: persistence, now: now, calendar: calendar
            )
            var snapshot: [UUID: TaskStore.TaskRecord] = [:]
            for r in initial {
                snapshot[r.id] = r
                emit(Event(kind: .insert, task: TaskRenderer.TaskDTO(from: r), at: Date()))
            }

            let ctx = persistence.container.viewContext
            let center = NotificationCenter.default
            let flagsCopy = flags
            let nameCopy = savedFilterName
            let calendarCopy = calendar
            let coalescer = Coalescer()

            // A single, serialized drain loop. Each notification requests a pass;
            // bursts collapse into one re-evaluation.
            @Sendable func drain() async {
                while await coalescer.consume() {
                    try? await Task.sleep(for: debounce)
                    do {
                        let after = try await LsHandler.run(
                            flags: flagsCopy, savedFilterName: nameCopy, sort: .createdAt,
                            persistence: persistence, now: Date(), calendar: calendarCopy
                        )
                        let (toEmit, next) = snapshotStep(previous: snapshot, current: after)
                        snapshot = next
                        for r in toEmit {
                            emit(Event(kind: .update, task: TaskRenderer.TaskDTO(from: r), at: Date()))
                        }
                    } catch {
                        onError(error)
                    }
                }
            }

            let token = center.addObserver(
                forName: .NSManagedObjectContextObjectsDidChange,
                object: ctx,
                queue: nil
            ) { _ in
                Task {
                    if await coalescer.requestAndShouldStart() {
                        await drain()
                    }
                }
            }
            defer { center.removeObserver(token) }

            // Park the task until cancellation.
            try await Task.sleep(nanoseconds: UInt64.max)
        }
    }
}
```

> **Concurrency note:** `snapshot` is mutated only inside the single `drain()` loop (one serialized writer, guaranteed by the `Coalescer` `running` flag), and the closure captures it by reference. Because `drain` is `@Sendable` and `snapshot` is a captured `var`, the strict-concurrency target requires it to be isolated. If the compiler flags the captured `var snapshot`, wrap it in an actor-isolated holder: replace `var snapshot: [UUID: TaskStore.TaskRecord]` with an `actor SnapshotBox { var value: [UUID: TaskStore.TaskRecord] = [:]; func swap(_ new: [UUID: TaskStore.TaskRecord]) { value = new }; func get() -> [UUID: TaskStore.TaskRecord] { value } }` and read/write through it inside `drain` (`let prev = await box.get()` / `await box.swap(next)`), seeding it after the bootstrap loop. Run Step 4 first; only apply this fallback if the build errors on the capture.

- [ ] **Step 4: Build, then run the test, expect pass.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | tail -5 && swift test --package-path Packages/LillistCore --filter "WatchHandlerTests"
```

Expected: a clean build (warnings are errors) and `Test Suite 'CLIBridge.WatchHandler' passed` with 4 tests passing. If the build errors on the captured `var snapshot`, apply the `SnapshotBox` fallback from the note above, then re-run.

- [ ] **Step 5: Update `WatchCommand` to surface errors to stderr.** `WatchCommand.run` already reads a `cfg` and passes `calendar: cfg.resolvedCalendar()` — `Config.resolvedCalendar()` landed in Wave 3 (`resolve-inert-features`). **Keep that call; do not revert it to `Calendar.current` and do not re-add `resolvedCalendar`.** The current call uses the trailing-closure `emit` form; convert it to the explicit-label `emit:`/`onError:` form so errors reach stderr. In `Packages/LillistCore/Sources/lillist-cli/Commands/WatchCommand.swift`, replace the `try await CLIBridge.WatchHandler.run(...) { event in ... }` call (the trailing-closure form ending the method) with:

```swift
        try await CLIBridge.WatchHandler.run(
            flags: flags, savedFilterName: saved,
            persistence: p, now: Date(), calendar: cfg.resolvedCalendar(),
            emit: { event in
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                if let data = try? encoder.encode(event), let line = String(data: data, encoding: .utf8) {
                    print(line)
                }
            },
            onError: { error in
                FileHandle.standardError.write(Data("watch: re-evaluation failed: \(error.localizedDescription)\n".utf8))
            }
        )
```

- [ ] **Step 6: Build the CLI target, expect clean.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | tail -5
```

Expected: `Build complete!` with no warnings (warnings are errors).

- [ ] **Step 7: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift Packages/LillistCore/Sources/lillist-cli/Commands/WatchCommand.swift Packages/LillistCore/Tests/LillistCoreTests/CLIBridge/Handlers/WatchHandlerTests.swift && git commit -m "fix(cli): serialize/debounce/dedup watch re-evaluation and surface errors

Replace the unbounded per-notification detached Task with one serialized,
debounced drain loop that dedupes against the last emitted snapshot and
reports errors via onError (stderr) instead of swallowing them. Closes
cli-6."
```

---

### Task 8: Full-suite regression gate

**Files:** none (verification only).

- [ ] **Step 1: Run the full LillistCore + CLI test suites.**

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -20
```

Expected: all suites pass, including the pre-existing `DeleteRestorePurgeHandlerTests`, `StatusHandlerTests`, `ResolverTests`, `StdinReaderTests`, `GoldenOutputTests`, and the new `ResolveAllTests`, `BatchTokensTests`, `BatchAtomicityTests`, `WatchHandlerTests`. No warnings (treated as errors).

- [ ] **Step 2: Confirm no dead-surface regressions remain.**

```bash
cd /Volumes/Code/mikeyward/Lillist && grep -rn "resolveExactTitle\|--exact" Packages/LillistCore/Sources Packages/LillistCore/Tests; echo "exit:$?"
```

Expected: no matches (grep prints nothing; `exit:1`).

- [ ] **Step 3: Confirm the stdin-parse duplication is gone.**

```bash
cd /Volumes/Code/mikeyward/Lillist && grep -rln "isStdinSentinel(token)" Packages/LillistCore/Sources/lillist-cli/Commands
```

Expected: only `ShowCommand.swift` and `EvalCommand.swift` remain (read-only stdin readers that are out of scope for the destructive-batch helper — they don't use the destructive UUID gate). The five destructive commands no longer match.

> No commit — this task is a gate. If anything fails, return to the owning task and fix before declaring done.

---

## Self-review checklist

- **cli-2** (all-or-nothing destructive stdin batches; one-bad-token test asserting zero side effects) — covered by **Task 1** (`Resolver.resolveAll` primitive + `ResolveAllTests`), **Task 3** (commands pre-resolve before mutating), and **Task 6** (`BatchAtomicityTests` proving zero side effects through the command path).
- **cli-3** (extract the duplicated stdin-parse block into one `BatchTokens` helper) — covered by **Task 2** (`BatchTokens` + `BatchTokensTests`) and **Task 3** (all five destructive commands switched to it; **Task 8 Step 3** verifies the duplication is gone).
- **cli-4** (remove the dead `--exact` mention + unused `resolveExactTitle`) — covered by **Task 4** (`resolveExactTitle` deleted, `--exact` removed from the error string; **Task 8 Step 2** verifies zero remaining references).
- **cli-5** (rewrite the destructive-ambiguity error to point at the working path *and* add byte-exact golden tests for json/ndjson/tsv incl. TSV header + embedded-tab title, extended to Tag/Journal renderers) — error rewrite + assertion covered by **Task 4** (`destructivePartialErrorMessage`); byte-exact goldens covered by **Task 5** (seven fixtures + un-normalized assertions across Task/Tag/Journal renderers, TSV header + embedded-tab title/name).
- **cli-6** (fix the unbounded-detached-Task ordering/dedup/error-swallowing in `watch`; adopt FRC per design, or at minimum serialize+debounce and surface errors) — covered by **Task 7** (serialized + debounced single drain loop, snapshot dedup via `snapshotStep` + `WatchHandlerTests`, `onError` surfacing to stderr in `WatchCommand`). The review's explicitly-offered "or at minimum" path is taken, with the design rationale recorded in the task's design note (YAGNI over a speculative FRC rewrite).

**Strengths preserved:** the airtight DTO boundary (no `NSManagedObject` escapes — all new APIs traffic in `TaskRecord`/`Resolution`/`Event` value types); Calendar-based date math (untouched); injection-safe `NSPredicate` construction (untouched); the synchronous AsyncStream registration pattern (untouched — Task 7's design note explicitly avoids reintroducing the deferred-registration race). Warnings-as-errors honored via `swift build`/`swift test` gates after each implementation step.
