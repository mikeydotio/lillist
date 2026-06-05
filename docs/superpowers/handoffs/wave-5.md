# Wave 5 handoff (P2)
From: Wave 5 executor   To: Wave 6 executor   Date: 2026-06-05

## What landed
- **crash-reporter-privacy** (fully isolated): commits `4dc1f96`..`5df296c` (9 commits).
  Closed redact-1, redact-5, canary-4, test-6. LillistCore 808 → 819 Swift-Testing
  tests (+11), warning-free; verified green serially (`--no-parallel`, 819/175).
- **app-layer-test-rehab**: commits `bcc1e57`..`656e353` (7 commits — `656e353` is a
  post-review doc-comment fix). Closed ios-2,
  ios-3, macos-4, ext-6. Introduced the three Wave-6 seams: `GatedPersistenceResolver`
  (LillistCore), `DragDropResolver`/`DragMutation` (LillistUI), `TaskListShortcutGate`
  (macOS). iOS app + both extensions build; macOS app builds; iOS standalone
  `Lillist-iOSTests` bundle = 29 tests pass; macOS full scheme = TEST SUCCEEDED (40);
  LillistUI +5 `DragDropResolverTests` pass (the only 10 LillistUI failures are the
  pre-existing host snapshot/Tour baseline drift documented in CLAUDE.md).
- Both plans adversarially reviewed (3 parallel dimensions each). **Crash review:
  unconditional approve** (spec + regression no findings; 3 INFO security
  observations — see Residuals). **App-layer review: regression approve (no findings);
  spec + code-quality `approve_with_notes`** — the two spec notes were doc-bookkeeping
  (commit this handoff; flip the banners/index — done here), and the one code finding (the
  `GatedPersistenceResolver` header overclaimed CLI adoption when the CLI's `StoreLocator`
  still builds the gate inline) was fixed in `656e353`.

## Shared files I moved / created (anchor by STRUCTURE — line numbers are as-of-landing)
- **`Sync/GatedPersistenceResolver.swift` (NEW)** — pure `Sendable` value type wrapping
  `MigrationGate` resolution. Injection init `(appGroupID:journal:modeStore:)` + failable
  production init `(appGroupID:)`. `resolveStoreConfiguration()` and two `makePersistence`
  overloads (one takes a `build:` closure seam for tests). **Wave 6
  `extension-persistence-unification` builds its per-process cache + `ShareSaveFlow` ON
  TOP of this, and routes `TaskEntityQuery` through it (ext-1/ext-2).**
- `Extensions/ShortcutsActions/IntentSupport.swift` — `makePersistence()` now delegates
  to `GatedPersistenceResolver(appGroupID:)`; inline gate wiring gone. Behavior identical.
- `Extensions/ShareExtension-iOS/ShareRootView.swift` — `save()` resolves via the resolver;
  the App-Group-unavailable early return + the `catch LillistError.storeUnavailable` path
  are preserved; **the `try?` on `addLinkPreview` is UNCHANGED** (ext-4 + link-preview
  Task 6 stay Wave-6 — residual #10).
- `LillistUI/DragReorder/DragDropResolver.swift` (NEW) — `DragMutation` enum +
  `DragDropResolver.resolve(target:flatRows:)`. Both `TaskListView.applyDrop` (macOS) and
  `TasksView.applyDrop` (iOS) now dispatch through it (semantics-identical to the old inline
  switch: `.between → reorder(after: afterID, before: beforeID)`, `.onto`+visible-child →
  `reorder(after: nil, before: firstChild.id)`, else `reparent`, `.rejected/.none → noop`).
- `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift` — added the
  `TaskListShortcutGate` namespace beside `ListColumn` (this file is co-compiled into the
  standalone `Lillist-macOSTests` bundle). `LillistCommands.swift`: all THREE
  `.disabled(listColumn == nil)` callsites now call `TaskListShortcutGate.isDisabled(...)`.
- `Apps/Lillist-iOS/project.yml` — the **`Lillist-iOSTests`** target now co-compiles
  `../../Extensions/ShortcutsActions/IntentSupport.swift` (after the `ReportCrashIntent.swift`
  line). The three Wave-4 `Lillist-iOSAppHostedTests` entries
  (`StoreReconfigureConcurrencyTests.swift`, `MigrationCoordinatorRestoreTests.swift`,
  `Helpers/FakeUserNotificationCenter.swift`) are **untouched and confirmed present** after
  regeneration.
- `docs/engineering-notes.md` — appended one section (crash-redaction layering + canary
  PID-recycling). Read the true EOF before appending; do not assume it is last.

## Deleted / renamed tests (no genuine coverage lost — all were substitution/tautology)
- Deleted: `DragDropInteractionTests.swift` (re-implemented + mis-mapped `.onto`),
  `FocusedShortcutGatingTests.swift` (re-typed the predicate), and three iOS tautologies
  (`SegmentedDetailTabPersistenceTests`, `NotesDebounceTests`,
  `CrashReportingDisclosureGateTests` — each asserted a literal against itself).
- Renamed: `QuickCaptureFlowTests` → `LillistCoreQuickCaptureCompositionTests`,
  `ShareExtensionPayloadTests` → `LillistCoreSharePayloadCompositionTests` (bodies
  unchanged; names now admit they exercise LillistCore composition, not the app types).
- `AppIntentHandlerTests.swift` left UNTOUCHED (genuine `CLIBridge` coverage).

## Assumptions I established / invalidated for later waves
- **`GatedPersistenceResolver` is THE canonical out-of-process store-resolution seam.**
  Wave 6 must route through it, not re-build the gate. Its `makePersistence(build:)` closure
  seam is how you test resolution without a live App Group.
- **`DragDropResolver` is the single source of truth for drag-drop mapping.** Do not
  re-introduce an inline `switch target` in either app.
- **The iOS `Lillist-iOSTests` bundle co-compiles `IntentSupport.swift`** (alongside the
  pre-existing `SharePayload.swift` + `ReportCrashIntent.swift`). The macOS Xcode project is
  at **`Apps/Lillist-macOS.xcodeproj`** (not `Apps/Lillist.xcodeproj` — the plan's stale
  git-add path; the index already records this correction). The iOS project is at
  `Apps/Lillist-iOS/Lillist-iOS.xcodeproj`.
- **Every Wave-6+ editor of `Apps/Lillist-iOS/project.yml` must re-Read it and preserve
  BOTH the 3 Wave-4 AppHostedTests entries AND the new `IntentSupport.swift` co-compile;
  grep the pbxproj after each `xcodegen generate`.**

## Deviations from the plans (all documented in commit messages; all verified correct)
1. **crash Task 1**: used a capture-group regex `(title=)[^\s\n]*` → `$1<redacted>` (with
   `.caseInsensitive`) instead of the plan's printed bare lowercase literal template. The
   literal template rewrites the whole match and LOWERCASES the key, which fails the plan's
   OWN Task-1 test and Task-5 golden (both expect `Title=<redacted>` casing preserved).
   Verified empirically with NSRegularExpression; the adversarial spec + regression
   reviewers independently confirmed the golden output is byte-for-byte correct.
2. **crash Task 7**: `BreadcrumbBufferStressTests`' second test needs `try await
   withThrowingTaskGroup` (plan printed bare `await`) because its body iterates
   `for try await … in group`.
3. **app-layer commits**: plan Tasks 5+6 landed as one commit (`b11f9d5`) and Tasks 7+8+9
   as one commit (`97eb948`) because the pbxprojs were regenerated once after batching the
   edits — each commit is internally coherent and buildable. (Per-task source RED→GREEN was
   still followed for the swift-test-gated Tasks 1 and 4.)

## Residuals I opened / closed
- **Closed**: redact-1, redact-5, canary-4, test-6, ios-2, ios-3, macos-4, ext-6.
- **Still open (carried to Wave 6, unchanged)**: residual #10 — the link-preview
  `URLPreviewPolicy` gate around the Share-Extension `addLinkPreview` (now delegated through
  the resolver but still un-gated for SSRF); owner = `extension-persistence-unification`.
- **New INFO observations from the crash adversarial-security review (non-blocking, NOT
  product bugs; recorded so coverage isn't overstated)**:
  - `LogRedactor` container pass is case-insensitive on the hex UUID segment but
    case-SENSITIVE on the literal `Data/Application`/`Shared/AppGroup` segments. A
    lowercased-segment variant in synthetic/third-party log text would leak the path
    prefix. Not changed: iOS emits canonical casing, and making the whole pattern
    `.caseInsensitive` would also widen the `\s(?=[A-Z][a-z])` capitalized-space lookahead
    (over-consume trailing components). Candidate for a future surgical inline-flag fix.
  - iCloud `…/Mobile Documents/iCloud~…/` ubiquity-container paths are matched by no path
    pass; a future "Mobile Documents" redaction pass is a candidate.
  - `subtitle=`/`mytag=` also redact (no key word-boundary) — intentional over-redaction,
    consistent with the crash-reporter philosophy; no action.

## Pre-flight the next executor (Wave 6) should run
- `git log --oneline 78efec9..HEAD | head -20` — confirm the 15 Wave-5 commits
  (`4dc1f96`..`97eb948`) are present.
- `swift test --package-path Packages/LillistCore` — expect green (re-run on a single
  SyncQuiesceMonitor / TaskStoreRecurrenceSpawn timing flake; residual #11). The
  `GatedPersistenceResolver` XCTest cases are counted separately from the Swift-Testing total.
- Re-Read before edits: `Sync/GatedPersistenceResolver.swift` (the seam Wave 6 extends),
  `Extensions/ShareExtension-iOS/ShareRootView.swift` (where residual #10's link-preview
  gate goes — the `addLinkPreview` `try?` survives here), `Apps/Lillist-iOS/project.yml`
  (preserve the 3 Wave-4 AppHostedTests entries + the new IntentSupport co-compile).
- Wave 6 plans: `extension-persistence-unification` (FIRST — depends on this wave's
  `GatedPersistenceResolver`; absorbs link-preview Task 6 / residual #10),
  `export-import-robustness`, `cli-robustness`, `performance-budgets-and-paging`,
  `observability-logging`.
