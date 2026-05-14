# Engineering Notes

Append-only log of cross-cutting engineering lessons learned while building
Lillist. Each entry captures a non-obvious gotcha — usually one that took real
investigation to find — so future work doesn't re-learn it the hard way.

Scope:
- **Belongs here:** framework shape, concurrency invariants, build-system
  surprises, type-system gotchas — anything where the "right answer" isn't
  obvious from reading docs or skimming related code.
- **Doesn't belong here:** specific bug fixes (the commit explains those),
  domain decisions (the design doc owns those), or per-feature mechanics
  (the implementation plan covers them).

Entries are dated and ordered newest-first. Each entry is short — a paragraph
of context, a paragraph of rule, and a pointer to evidence (commit, RCA
artifact, test).

---

## 2026-05-14 — Plan 9 crash reporting: `.process("…xcdatamodeld")` does NOT compile Core Data models under Swift 6.2.4 / SPM CLI; the workaround is to keep the `CompileCoreDataModel` plugin AND rename its output so it doesn't collide with Xcode's auto-DataModelCompile; ISO8601 date round-trips lose sub-second precision

**Context.** Plan 9 needed Core Data tests to pass against the
LillistCore SPM target via `swift test`. After cleaning `.build`, all
Core Data tests started crashing with `LillistModel.momd not found in
bundle`. Three concrete realities surfaced:

1. **`.process("…xcdatamodeld")` does not compile the model.** Plan 7's
   engineering note claimed that "SwiftPM 6 now compiles `.xcdatamodeld`
   natively via `.process(...)`". On this toolchain
   (`swift-driver 1.127.15`, Swift 6.2.4) the resource pipeline copies
   the `.xcdatamodeld` directory into the bundle as-is — no `.momd` is
   produced. Plan 7's evidence was tainted by stale `.momd` artifacts
   left in `.build` from before the plugin removal; a fresh build would
   have failed.

2. **Re-applying the plugin re-introduces the duplicate-output error in
   workspace builds.** With the plugin back on the LillistCore target,
   `swift test` succeeds (plugin produces `LillistModel.momd`) but
   `xcodebuild` fails: Xcode's SPM integration *also* applies its
   built-in `DataModelCompile` rule to any `.xcdatamodeld` it finds in
   the source tree, and both copy commands target the same bundle path
   (`…/LillistCore_LillistCore.bundle/Contents/Resources/LillistModel.momd`).

3. **The escape hatch is to rename the plugin's output.** Change the
   plugin to write `LillistModel.spm.momd` instead of
   `LillistModel.momd`. Both producers now write distinct filenames into
   the bundle; no collision. `PersistenceController.sharedModel` falls
   back from `LillistModel.momd` (preferred — what `xcodebuild` produces
   via DataModelCompile) to `LillistModel.spm.momd` (what the plugin
   produces in `swift test` / `swift build`). Both code paths load the
   same model and tests pass in both contexts.

4. **`Date` ISO8601 round-trips drop sub-second precision.** The
   crash-canary file uses `JSONEncoder` with
   `dateEncodingStrategy = .iso8601`, which serializes only to
   second-granularity (e.g. `"2026-05-14T20:28:24Z"`). Comparing a
   `Date(timeIntervalSinceNow: 0)` to its decoded equivalent
   `XCTAssertEqual`s as not-equal because the original has nanoseconds
   and the decoded does not — and Swift's default `Date.description`
   formats both identically, making the failure look like the assertion
   library is broken. Tests that round-trip a `Date` through ISO8601
   should pin fixtures to whole-second timestamps:
   `Date(timeIntervalSince1970: 1_500_000)`.

5. **`LogRedactor` path passes need a lookahead to handle macOS paths
   with literal spaces.** The naïve `~/[^\s]*` stops at the first space,
   so `~/Library/Application Support/Lillist` only redacts to
   `<path> Support/Lillist` — leaving a real path fragment in the
   "preview what will be sent" sheet. The fix is to allow a literal
   space inside the path *if* the next character is a capitalized
   letter: `~/(?:[^\s]|\s(?=[A-Z][a-z]))*`. Apply symmetrically to the
   `/Users/<name>/...` and `/var/mobile/Containers/...` patterns. Risk:
   over-redacts capitalized-word-after-path-prefix text like
   `~/Foo Bar baz` → `<path> baz` (eats `Bar`). Acceptable per
   redactor's "prefer over-redaction" stance.

**Rule.**

- When writing tests that round-trip `Date` through `JSONEncoder`'s
  `.iso8601` strategy (or `ISO8601DateFormatter`), pin fixtures to
  `Date(timeIntervalSince1970: N)` with `N` an integer. Don't use
  `.now`, `Date()`, or any non-integer interval — sub-second precision
  loss will make equality comparisons false-fail in confusing ways.
- For SwiftPM build-tool plugins that produce a resource that *might*
  collide with Xcode's built-in compiler for that file type
  (DataModelCompile, AssetCatalogCompile, etc.), give the plugin's
  output a distinct filename and let the consuming code fall back
  through both names. Trying to suppress Xcode's auto-compile via build
  settings or by manipulating the `resources:` declaration didn't work
  in 2026-05-14 testing; the rename is the only clean cross-tool path.
- Don't trust prior engineering notes' claims that "SPM auto-compiles
  X" without a fresh-`.build` repro on the current toolchain — Plan 7's
  similar claim about `.xcdatamodeld` was wrong, almost certainly due
  to a stale-artifact false negative.
- For redactors that pattern-match macOS paths, account for literal
  spaces inside known path components (`Application Support`,
  `Mobile Documents`, etc.). The cheapest fix is a
  `\s(?=[A-Z][a-z])` lookahead inside the path body.

**Evidence.** Plan 9 commits `e86cbd0` (preference + plugin re-apply),
`71a2546` (rename plugin output to `.spm.momd` + macOS app wiring),
`265eddb` (CLI ISO8601 date fixture rule), `e2bfd3c` (LogRedactor
greedier path regex with three-agent panel ranked-choice ballot
captured in commit message).

---

## 2026-05-14 — Plan 8 iOS app: AppIntent metadata must be `static let` under Swift 6; `@Parameter` wrappers can't be set via `init()`; App Group container is the only path for app/extension store sharing; standalone iOS test bundle (`TEST_HOST=""`) cannot `@testable import` the app module; `Foundation.localizedStandardContains("")` returns `false`

**Context.** Five gotchas surfaced while wiring up the iOS app, Share
Extension, and App Intents extension on top of the macOS work from
Plan 7.

1. **AppIntent metadata must be `static let`, not `static var`, under
   Swift 6 strict concurrency.** `AppIntent`'s protocol requirements
   (`title`, `description`, `openAppWhenRun`, `isDiscoverable`,
   `typeDisplayRepresentation`, `caseDisplayRepresentations`,
   `defaultQuery`) are declared `var x: T { get }` — but you satisfy
   them with `static let x: T` and side-step "nonisolated mutable
   global state". Plan 8 commit `0d45a36` does this across every
   intent / entity / enum file.

2. **`@Parameter`-wrapped properties can't be set via `init()`.** The
   property wrapper makes the stored type `IntentParameter<T>`, not
   `T`. To prefill an intent value before passing to
   `.result(opensIntent:)`, construct the intent with `init()` and
   then assign through the wrappedValue:
   ```swift
   var inner = OpenTaskInAppIntent()
   inner.taskID = task.id.uuidString
   return .result(opensIntent: inner)
   ```
   You also need an explicit `init() {}` on the helper intent if you
   want the no-arg constructor — synthesized inits are problematic
   when only `@Parameter` fields exist.

3. **Sharing the SQLite store between the iOS app and its extensions
   requires App Group container URL.** `FileManager.containerURL(
   forSecurityApplicationGroupIdentifier:)` returns the per-group
   sandbox directory; both the main app and every embedded extension
   point their `PersistenceController` at the same SQLite file inside
   that directory. `FileManager.default.homeDirectoryForCurrentUser`
   is macOS-only — `NSHomeDirectory()` is portable but inside the
   per-app sandbox on iOS, so it doesn't satisfy the sharing
   requirement. Plan 8 added `StoreConfiguration.appGroupOnDisk(
   groupID:)` to LillistCore for this.

4. **A standalone iOS test bundle (`TEST_HOST=""` + `BUNDLE_LOADER=""`)
   cannot `@testable import` the app module.** With no test host the
   app target's symbols aren't reachable from the test bundle. Two
   options: (a) test the underlying LillistCore/LillistUI paths
   (preferred — the app code is mostly glue, and the cores have their
   own deep coverage); (b) co-compile specific source files into the
   test bundle via `sources: - path: ../../Extensions/.../X.swift`
   in `project.yml`. Plan 8 uses (b) for `SharePayload.swift` so its
   pure-decode logic gets tested without a signed host.

5. **`Foundation.localizedStandardContains("")` returns `false` on
   iOS 18.** Counterintuitive — you might expect "every string
   contains the empty string". The practical consequence: a search
   path that does `title.localizedStandardContains(query)` won't
   accidentally return every task when the query is empty. That's
   safe default behavior but worth pinning with a regression test in
   case Foundation changes its mind.

**Rule.**

- For every `AppIntent` / `AppEntity` / `AppEnum` declaration in Swift
  6, use `static let` for metadata (`title`, `description`,
  `openAppWhenRun`, `isDiscoverable`, `typeDisplayRepresentation`,
  `caseDisplayRepresentations`, `defaultQuery`). Use `static var` only
  for accessors that genuinely compute, e.g. `parameterSummary`.
- To prefill an `@Parameter` value in a helper intent, call its
  `init()` and assign to the wrappedValue. Never try to pass through
  a custom init that takes the parameter value directly.
- For any iOS app that ships extensions, point `PersistenceController`
  at the App Group container URL via
  `StoreConfiguration.appGroupOnDisk(groupID:)`. Falling back to
  `defaultOnDisk` (per-app Application Support) silently breaks the
  sharing contract.
- For standalone iOS test bundles, design tests against LillistCore /
  LillistUI surfaces, not against the iOS app module. When a specific
  iOS-app source file needs coverage and is pure (no UIKit-only
  dependencies), co-compile it into the test bundle via project.yml.
- Don't assume `localizedStandardContains` matches everything on an
  empty needle; assert the actual behavior in a test.

**Evidence.** Plan 8 commits `0d45a36` (Swift 6 fixes), `905d0a5`
(App Group plumbing), `a3f9d08` (SharePayload co-compile),
`184b2ef` (empty-query regression test).

---

## 2026-05-14 — Plan 7 macOS app: SwiftPM 6 + Xcode SPM both auto-compile `.xcdatamodeld`; macOS SwiftUI View snapshots need `NSHostingView`; xcodegen path resolution; entitlements need development cert for `xcodebuild`; XCTAssert autoclosures don't accept `try await`

**Context.** Five concrete gotchas surfaced while wiring up the macOS
app on top of the SwiftPM packages built in Plans 1–5.

1. **Swift Package Manager 6 compiles `.xcdatamodeld` natively, and
   so does Xcode's SPM integration.** Plan 1 shipped a
   `CompileCoreDataModel` build-tool plugin that ran `momc`. Under SPM
   CLI (`swift build`) the plugin produced `LillistModel.momd` and the
   resource pipeline silently de-duplicated. Under `xcodebuild`
   consuming the same package from a workspace, both the plugin and
   Xcode's `DataModelCompile` task ran, hitting "Multiple commands
   produce …/LillistModel.momd". The fix: remove the plugin and rely
   on SwiftPM's `.process("LillistModel.xcdatamodeld")` resource entry
   alone. SPM 6 + Xcode 17 both handle it. Plan 7 commit
   `7715ec0` does this.
2. **`swift-snapshot-testing` 1.17 has no macOS SwiftUI `View`
   snapshot strategy.** The plan's `SnapshotEnvironment` extension
   tried to declare `Snapshotting where Value: View, Format == NSImage`
   and call `.image(size:traits:)` directly. On macOS the library
   provides image strategies only for `NSView` /
   `NSViewController` — not for SwiftUI `View`. The fix is to host
   each SwiftUI view in an `NSHostingView` and snapshot the resulting
   `NSView`. Helper: `makeHostingView(_:size:) -> NSView`.
3. **xcodegen path resolution is anchored at the spec file's
   directory.** Generating the project with `xcodegen generate --spec
   project.yml --project Apps` from a repo-root `project.yml` stored
   `Apps/Lillist-macOS/Sources` as the source path *literally* —
   which Xcode then resolved against `$(SRCROOT) = Apps/`, yielding
   `Apps/Apps/Lillist-macOS/Sources/`. The fix is to put `project.yml`
   inside `Apps/` so source paths are relative to the project
   location, and to drop the `info:` / `entitlements:` blocks from
   the YAML (xcodegen regenerates default minimal versions of those
   files on every run, clobbering hand-written contents — just set
   `INFOPLIST_FILE` and `CODE_SIGN_ENTITLEMENTS` in build settings
   instead).
4. **The macOS entitlements in this repo require a development
   signing identity for `xcodebuild build`.** App-group +
   iCloud-container-identifiers + CloudKit-services entitlements all
   trigger Xcode's "requires signing with a development certificate"
   gate. Headless CI / CLI builds work with
   `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
   CODE_SIGNING_ALLOWED=NO`. With those flags the test bundle can't
   load a fully-signed `.app` host, so the macOS test target is
   configured with `TEST_HOST=""` and `BUNDLE_LOADER=""` as a
   standalone bundle. The plan's test bodies were rewritten to import
   only `LillistCore` / `LillistUI`, never `@testable import
   Lillist_macOS`, so this works.
5. **`XCTAssertEqual(try await store.foo(), expected)` doesn't
   compile.** XCTAssert's autoclosures are non-async, so a `try
   await` inside trips
   `'async' call in an autoclosure that does not support concurrency`.
   The fix is mechanical: `let v = try await store.foo();
   XCTAssertEqual(v, expected)`.

**Rule.**

- Use SwiftPM's native `.process("Foo.xcdatamodeld")` resource
  declaration; do NOT layer a build-tool plugin on top of it.
- For macOS SwiftUI view snapshots, host the view in `NSHostingView`
  first; the snapshotter only knows about `NSView` /
  `NSViewController` on macOS.
- Place `project.yml` in the same directory you want xcodegen to
  generate the `.xcodeproj` into; leave the `info` / `entitlements`
  blocks out and use build settings to point at hand-written files.
- For headless macOS app builds with CloudKit / app-group
  entitlements, expect to pass code-signing-disabled flags. Configure
  the test target to be standalone (no host) so it builds without a
  signed `.app`.
- Never embed `try await` inside XCTAssert; compute the value first.

**Evidence.** Plan 7 commits `7715ec0`, `40ca007`, `2caa014`,
`93333dc`. The new build-system gotcha is captured in this note;
the macOS snapshot-testing one is enshrined in
`Packages/LillistUI/Tests/LillistUITests/Helpers/SnapshotEnvironment.swift`.

---

## 2026-05-14 — Plan 6 CLI: NSPredicate is non-Sendable, hex-only fuzzy tokens collide with UUID prefix routing, `localizedStandardContains` does not fold diacritics, and the `@main` annotation conflicts with a `main.swift` file

**Context.** Three concrete gotchas surfaced while building the `lillist` CLI
(see commits `0ab5e94`, `2a2b7a5`, `1771301`):

1. **`NSPredicate` is not `Sendable` in Swift 6.** Capturing a pre-built
   predicate into a `context.perform { ... }` closure trips
   `[#SendableClosureCaptures]` even though `NSManagedObjectContext.perform`
   itself runs on its own queue. The strict-concurrency-clean shape is to
   build the predicate **inside** the perform closure from a `Sendable`
   `PredicateGroup`. See `LsHandler` and `EvalHandler`.
2. **Hex-only tokens like `cafe` route to UUID-prefix matching, not title
   substring.** Design Section 6 says "tokens matching `^[0-9a-f]{4,}$`
   resolve as UUID prefixes." That rule preempts the title path even when
   the user typed an English word that happens to be all-hex (`cafe`,
   `face`, `dead`, `beef`). Tests for diacritic folding must use a token
   with at least one non-hex character (`naive`, `resume`).
3. **`localizedStandardContains` is unreliable for diacritic folding.** It
   does case folding but its diacritic behavior depends on the current
   locale. The robust path is to fold both sides explicitly via
   `applyingTransform(.stripDiacritics, reverse: false)`, then case-fold
   via `lowercased()`, then `contains`. See `Resolver.foldedContains`.
4. **`@main` on a type cannot coexist with a `main.swift` file in the same
   executable target.** SwiftPM treats `main.swift` as the entry point and
   `@main` is rejected. Plan 6 Task 1 had the executable target use only
   `@main`; Task 24 swapped to a `main.swift` that calls
   `Lillist.runWithExitCodes()` and removed the `@main` annotation. Both
   are valid; pick one and don't ship both.
5. **`ISO8601DateFormatter` is not `Sendable` and cannot be a `static let`
   under strict concurrency** — it triggers `[#MutableGlobalVariable]`.
   Construct it per-call inside the function that needs it; instantiation
   is cheap.

**Rule.**

- Build any `NSPredicate` *inside* the `context.perform` closure that uses
  it. Pass `Sendable` value types (`PredicateGroup`, `UUID`, `String`,
  `Date`) across the boundary, not predicates.
- When the design specifies a UUID-prefix routing rule, design test
  fixtures so all-hex words (`cafe`, `dead`, `beef`) are not used as
  title-substring inputs. Document the precedence rule in the resolver's
  doc comment.
- For substring matching that needs both case- and diacritic-insensitivity,
  always fold via `applyingTransform(.stripDiacritics, reverse: false)`
  before `lowercased().contains(...)`. Don't rely on
  `localizedStandardContains`.
- For executable targets, choose either `@main` on a type or a `main.swift`
  file with top-level code, never both.
- For `Foundation` formatter types that aren't `Sendable`
  (`ISO8601DateFormatter`, `DateFormatter`, `JSONEncoder`/`Decoder` are
  `Sendable` since macOS 14), construct them per-call rather than as
  static singletons under strict concurrency.

**Evidence.** `git show 0ab5e94 1771301 9e9f37d 2a2b7a5`.

---

## 2026-05-14 — Swift 6 strict concurrency in the test target; `@preconcurrency import UserNotifications`; `OSAllocatedUnfairLock`

**Context.** Plan 5 (notifications layer) needed an `actor`-based
`FakeUserNotificationCenter` per its written code. Three concrete
strict-concurrency surprises came up:

1. **The test target IS strict in Swift 6 mode.** The earlier project
   note "the test target is not strict, so concurrency bugs surface at
   runtime" was wrong. With `swift-tools-version: 6.0`, Swift 6 language
   mode is on for the whole package; the `-enable-experimental-feature
   StrictConcurrency` flag on the source target is redundant on Swift 6
   and the test target inherits strict checking.
2. **`@preconcurrency import UserNotifications` only relaxes individual
   `UN*` arguments, not collection-typed ones.** It fixes
   `func add(_ request: UNNotificationRequest)` crossing an actor, but
   returning `[UNNotificationRequest]` or `Set<UNNotificationCategory>`
   from an actor method still trips `non-Sendable result can not be
   returned from actor-isolated instance method to nonisolated context`.
   For a fake that owns a list of `UN*` values, the cleanest shape is a
   `final class @unchecked Sendable` backed by
   `OSAllocatedUnfairLock<State>` — see Plan 5 commit
   `01f47a2` and the architect/QA/UX panel ruling captured in the commit
   message.
3. **`NSLock.lock()/unlock()` is unavailable from async contexts in
   modern SDKs.** The async-safe alternative is `OSAllocatedUnfairLock<State>`
   with `state.withLock { ... }`. Stored properties on a `final class
   @unchecked Sendable` become `private let state =
   OSAllocatedUnfairLock<State>(initialState: State())`, mutated only
   inside the closure.
4. **Capturing actor-isolated dictionaries into non-async closures
   (`compactMap`, `filter`, …) triggers `SendingRisksDataRace`.** Even
   when the enclosing function is on the actor and the closure is
   non-`@Sendable`, the compiler diagnoses possible concurrent access.
   The mechanical fix is to rewrite the closure-based code as a
   `for ... in` loop in the actor-isolated function body — no closure,
   no capture, no diagnostic.

**Rule.**

- For test doubles of `UserNotifications`-like APIs, prefer
  `final class @unchecked Sendable` + `OSAllocatedUnfairLock<State>`
  over `actor + nonisolated func X() async { await self._X() }`. Expose
  inspection state through `async` accessor methods that return Sendable
  snapshots (e.g. `func addedRequests() async -> [UNNotificationRequest]`).
- Reach for `@preconcurrency import` first when an external-framework
  type without `Sendable` conformance crosses an isolation boundary,
  but be prepared to fall back to `@unchecked Sendable` wrappers if a
  collection of those types needs to flow.
- If the compiler complains about `SendingRisksDataRace` in
  `compactMap`/`filter`/`map` over an actor-isolated dictionary,
  un-functional-ize the loop. The performance cost is nil; the
  diagnostic disappears.

**Evidence.** Plan 5 commits `01f47a2`, `ef16409`, `bb38508`.
`Packages/LillistCore/Tests/LillistCoreTests/Helpers/FakeUserNotificationCenter.swift`
is the canonical example of the lock-based fake shape.

---

## 2026-05-14 — `Task { same-actor-method() }` is almost always wrong; `Task.yield()` is not a barrier

**Context.** While running Plan 4 implementation, the test
`SyncStatusMonitorTests."Failed export records the error and clears
inProgress"` flaked once. Root-cause investigation (`.rca/sync-status-monitor-event-drop/`)
revealed two distinct ordering hazards in
`Packages/LillistCore/Sources/LillistCore/Sync/`:

1. **Deferred registration via Task wrapper.** `CloudKitEventBridge.eventStream`,
   `SyncStatusMonitor.statusStream`, and `AccountStateMonitor.stateStream`
   each wrapped their `self.register(id:continuation:)` call in
   `Task { ... }`. The getter returned before the registration ran, so any
   `recordEvent` that arrived in that window iterated an empty `continuations`
   dictionary and silently dropped the event. AsyncStream's `.unbounded`
   buffer was fine — the bug was upstream: `continuation.yield(...)` was
   never called, so nothing landed in the buffer.

2. **Yield-polling as a synchronization primitive.** Tests used
   `for _ in 0..<5 { await Task.yield() }` between `recordEvent` and the
   subsequent `currentStatus` read, expecting that to "let the consumer
   catch up." Empirically: 26 reorders / 1000 trials of two `await
   monitor.X()` calls on the same actor. Under cooperative-pool contention
   (parallel test execution), the test's read can win the race against the
   consumer's `apply()` and return pre-apply state.

**Rule.**

- **Same-actor synchronous calls do not need `Task { }` wrappers.** Inside
  an actor-isolated context (including the builder closure of
  `AsyncStream { continuation in ... }` when the enclosing computed property
  is on an actor), call same-actor methods directly. Swift 6 strict
  concurrency permits it; the compiler will not warn or error. Wrapping the
  call in `Task { }` defers it to a later executor tick for no benefit, and
  creates an ordering hazard between the actor-isolated function returning
  and the deferred call running.
- **`Task.yield()` is a cooperative-scheduling hint, not a synchronization
  primitive.** It raises the probability that other tasks run before
  resumption; it does not establish happens-before with any specific task.
  Adding more yields raises probability but never reaches certainty.
- **When the compiler emits "no async operations" inside `Task { method() }`,
  the surrounding scaffolding is usually unnecessary — drop the `Task`, not
  just the `await`.** The four "drop redundant await on same-actor X
  registration" commits in `Sync/` (`e2a3a5f`, `f310020`, `7049a3f`,
  `3b5f59f`) silenced the warning by removing the `await` but kept the
  `Task` — which left the race intact. The warning was pointing at the
  whole scaffold, not the keyword inside.
- **For async-event pipelines, the canonical observation primitive is the
  stream's iterator, not a synchronous snapshot read.** Tests that need to
  observe downstream effects should use `var iterator = await source.stream.makeAsyncIterator(); _ = await iterator.next()` as the wait
  point. `iterator.next()` only returns when a value has been yielded —
  that yield is downstream of the work it depends on, so it's a real
  happens-before barrier. Synchronous reads (`actor.currentStatus`,
  `actor.currentState`) are for snapshot/debug use, after the observer has
  synchronized via the stream.

**Evidence.**
- RCA artifacts: `.rca/sync-status-monitor-event-drop/` (SYMPTOM, EVIDENCE,
  HYPOTHESES, CHALLENGER, VERIFICATION, REMEDIATION).
- Runnable verification: `.rca/sync-status-monitor-event-drop/scratch/exp1-9.swift`
  (AsyncStream pre-iterator buffering, Swift 6 isolation inference, actor
  non-FIFO, iterator pattern as barrier, etc.).
- Fix commit: `2db9a69` (fix(sync): register AsyncStream continuations
  synchronously…).
- Production blast radius improvement: the fix also closed a small leak
  window in `CloudKitEventBridge.attach(to:)` where `detach()` could race
  ahead of a deferred `setObserverToken` write.

**Generalize when.** Any new use of `AsyncStream { ... }` inside an actor,
any test that observes downstream effects across actor boundaries, any
`Task { }` you're about to write inside an already-actor-isolated function.
