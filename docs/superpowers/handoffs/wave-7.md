# Wave 7 handoff (closing wave — ship-blockers + posture)
From: Wave 7 executor   To: future contributors   Date: 2026-06-05

**Wave 7 is the LAST Foundation-Hardening wave. With it merged, all 22 plans
are complete.** This handoff is therefore also the program's closing note.

## What landed (28 commits, `6fdb728`..HEAD on `main`; in plan order)

- **privacy-manifest-export-compliance** (`6fdb728`..`9d5778d`, 9 commits): closed
  critic blind-spot #3. Four byte-identical `PrivacyInfo.xcprivacy` manifests
  (iOS app, macOS app, ShareExtension-iOS, ShortcutsActions) declaring
  `NSPrivacyTracking=false`, CloudKit `OtherUserContent` (linked, not tracking),
  and the two required-reason APIs the code uses — `UserDefaults` **CA92.1** +
  `FileTimestamp` **C617.1**; `ITSAppUsesNonExemptEncryption=false` in all four
  `Info.plist`s; `PrivacyManifestComplianceTests` in BOTH app test bundles
  (`#filePath`-relative, since the bundles are host-less). xcodegen auto-routed
  the `.xcprivacy` into the resource phase (apps' `Resources/` already a resource
  phase; xcodegen created fresh resource phases for the two extensions) — no
  `project.yml` source edits were needed; verified one copy lands in each
  `.app`/`.appex`.
- **recovery-hardening** (`39bd707`..`729c3d6`, 7 commits): closed critic
  blind-spot #5 + reaffirmed `test-2`. `LillistError.insufficientDiskSpace`;
  injectable `DiskSpaceProbe` (`DiskSpaceProbing` + `FileManagerDiskSpaceProbe`);
  `QuarantineManager.copyStore` pre-flight (refuses to copy unless `2×` the live
  footprint is free, throwing **before touching any file**); a comment-only
  invariant note pinning the disk check ahead of the CloudKit erase in
  `runMigration`; an ungated coordinator-level disk-full test (uses
  `FakePersistenceReconfigurer`, asserts journal `.failed` + eraser never ran +
  store untouched + post-reconfigure mode); recovery-sheet low-storage copy via a
  `nonisolated static detailText(for:)`. `restoreFromBackup` stays covered by the
  pre-existing ungated `MigrationRecoveryTests`.
- **lillistui-localization-a11y** (`ccab595`..`72d319c`, 5 commits): closed
  ui-a11y-1, ui-loc-1, ui-loc-2, ui-test-1. `ReorderActionDispatch` (pure router)
  gates reorder accessibility actions on their non-nil closure (no phantom
  no-op actions); the tautological reorder test replaced by direct dispatch
  coverage; `RecurrenceEditorViewModel.humanSummary` → structured
  `RecurrenceSummary` + a `.module`-localized `RecurrenceSummaryFormatter` (both
  app detail views rewired); remaining bare-`Text` a11y strings `.module`-pinned;
  `defaultLocalization: "en"` + a populated `Localizable.xcstrings` (162 keys, 5
  recurrence plural variations) + `Tools/CI/check-lillistui-localization.sh`
  extraction-drift lint (proven to fail on drift via canary).
- **ci-and-build-posture** (`4d…`/Task1..Task6, 6 commits): closed build-1…5,
  ui-warn-1, ui-snap-1, test-5; absorbed residual #11; closed chain #6. LillistUI
  → swift-tools 6.2 + `.treatAllWarnings(as: .error)` on source+test + excluded
  the six `__Snapshots__` dirs (kills the 83-file manifest warning);
  `CompileCoreDataModel` declares the inner `*.xcdatamodel/contents` +
  `.xccurrentversion` as `inputFiles` (mtime-touch ritual retired, proven by a
  contents-only mtime re-run of `momc`); `IOSScreenTourTests.assertScreen` gained
  optional `precision`/`perceptualPrecision` (only `test_08_settings_light`
  relaxed to 0.99/0.98); `.github/workflows/ci.yml` (post-push verifier, 7 jobs);
  standalone `lillistui-localization.yml` folded into `ci.yml` + deleted.

## Deliberate deviations from the plans (and why)

These were forced by EMPIRICAL findings the plans (verified only under host
`swift test`) did not anticipate. Each is documented in
`docs/engineering-notes.md` (2026-06-05 entries):

1. **`RecurrenceSummaryFormatter` branches on count instead of relying on
   catalog plural variations.** SwiftPM copies `.xcstrings` into the resource
   bundle **verbatim** (it does NOT run `xcstringstool` like Xcode), so a
   `.xcstrings` plural rule is inert under `swift test`. The plan's design
   (`String(localized: key)` + `String(format:)`) genuinely cannot produce the
   singular "1 day" (the plan's "all 5 tests pass pre-catalog" claim was false
   for `days==1`). The formatter now uses a dedicated singular key for
   `interval==1`/`days==1` (mirroring the existing calendar `interval==1`
   pattern) — correct in English from source AND fully localizable. The catalog
   still carries the plural variations for translators / the Xcode-compiled app.
2. **CI iOS coverage is scoped (Option b), not Option a.** The
   `Lillist-iOSAppHostedTests` `liveSwapAllowed` tests stand up a live
   `NSPersistentCloudKitContainer` that fails `CKAccountStatusNoAccount` on any
   host without a signed-in iCloud account — confirmed locally: ad-hoc simulator
   signing DOES launch the host app, so signing is not the blocker; the **missing
   iCloud account** is. So the `ios` CI job runs ONLY the standalone
   `Lillist-iOSTests` bundle; the app-hosted + UI tests run on a developer's
   signed Mac w/ iCloud (as Waves 1/4 verified them). The host-pinned LillistUI
   snapshot/tour tests are excluded everywhere (`--skip Snapshot --skip Tour`;
   no `LillistUITests` in the iOS job) — their PNG baselines drift on any host
   but the recording one. Fully disclosed in the engineering note + CLAUDE.md.
3. **`FakeDiskSpaceProbe` extracted to its own file + added to the app-hosted
   target** (`b718e89`): `MigrationCoordinatorTests` (co-compiled into
   `Lillist-iOSAppHostedTests`) references it, but it lived inside
   `DiskSpaceProbeTests.swift` which that target does not co-compile — the
   app-hosted target failed to build. Recovery-hardening had only verified `swift
   test` (SPM) + unsigned app builds, never the app-hosted target. Now mirrors the
   `FakePersistenceReconfigurer` shared-helper pattern.
4. **`UITraitCollection(traitsFrom:)` → `(mutations:)`** in two snapshot helpers:
   Task 1's warnings-as-error on the test target turned this iOS-17 deprecation
   into a build error, but only under xcodebuild iOS (the `#if os(iOS)` snapshot
   code never compiles under host `swift test`). Style+scale-equivalent; both
   snapshot suites stay green.
5. **`SyncMigrationRecoverySheetTests` arg order**: the plan listed
   `MigrationJournal(... failureReason: ... previousMode: ...)` but the init
   declares `previousMode` before `failureReason` — Swift forbids the reorder,
   so the test as printed would not compile. Fixed the order (same semantics).
   Also: `try? #require(vm.build())` → `vm.build()` ×3 (build() is non-optional;
   warnings-as-error flagged the redundant `#require`).

## CI: what runs and what does NOT (read before trusting CI green)

`.github/workflows/ci.yml` is a **post-push verifier on `main`** (not a PR gate).
Jobs: `spm` (LillistCore `--parallel --num-workers 2` + retry; LillistUI
`--skip Snapshot --skip Tour`), `project-drift`, `ios` (standalone
`Lillist-iOSTests` only), `macos` (full scheme — standalone, snapshot-free),
`release-archive-smoke` (Release-config app compile), `localization-lint`,
`notify`. **NOT in CI** (verified only on a dev's signed Mac w/ iCloud): the
`Lillist-iOSAppHostedTests` live-swap tests, `Lillist-iOSUITests`, and all
host-pinned snapshot/tour tests. **Toolchain quirk:** `--num-workers N` requires
`--parallel` on Swift 6.2.4 (bare form errors).

## Verification (all green on `main`, this machine: Xcode 26.3 / iOS 26.2 sim)

- LillistCore `swift test --parallel --num-workers 2`: **868 passed** (modulo the
  2 documented residual-#11 timing flakes that pass on retry / in isolation).
- LillistUI `swift test --skip Snapshot --skip Tour`: 40 Swift-Testing + 60 XCTest, 0 failures.
- iOS `-only-testing:Lillist-iOSTests` (no signing): **40 passed, TEST SUCCEEDED**.
- macOS scheme (no signing): **45 passed, TEST SUCCEEDED**.
- iOS + macOS unsigned app builds: **BUILD SUCCEEDED**; Release smoke: **BUILD SUCCEEDED**.
- pbxproj drift gate: **clean**. Localization lint: **OK (162 keys)**.
- Privacy compliance tests: 5/5 in both app bundles.

## Known residual (pre-existing, NOT a Wave-7 regression)

The iOS-simulator snapshot baselines (`iOSSnapshotTests`, etc.) drift on this
Xcode 26.3 / iOS 26.2 machine — ~10 failures in components Wave 7 never touched
(`syncStatusBadge`, `quickCaptureDialog`, `taskNotesTab`), and the failing set
varies run-to-run. **Proven pre-existing**: they fail identically with all Wave-7
localization changes reverted. The recurrence snapshots (the only rendering Wave 7
could affect) PASS. This is the same host-pinning the host-`swift test` drift note
documents; re-recording the iOS baselines on the canonical host is an unscoped
follow-up. It is why CI excludes the snapshot suites.

## Adversarial review

A 4-dimension multi-agent review (regression, spec×2, correctness) → per-finding
skeptical verification (workflow `wf_9134372e-371`, 28 agents) surfaced **24 raw
findings → 9 confirmed / 15 rejected**. The 9 cluster into 4 issues; **3 were fixed
in code + re-verified, 1 was already-documented behavior:**

1. **HIGH — DiskSpace privacy manifest (cross-plan defect; #3/#4/#5).** recovery-
   hardening's `DiskSpaceProbe` reads `volumeAvailableCapacityForImportantUsageKey`
   — an `NSPrivacyAccessedAPICategoryDiskSpace` required-reason API — but the four
   manifests (privacy plan, landed first) declared only UserDefaults + FileTimestamp.
   A submission scan would flag ITMS-91053, reopening the exact stall the privacy
   plan prevents. **Fixed:** added `DiskSpace`/`85F4.1` to all four byte-identical
   manifests + both `PrivacyManifestComplianceTests` (5/5 green).
2. **MEDIUM — reorder a11y strings not extractable/localizable (#1/#6/#8).** The four
   `TaskRowView` reorder VoiceOver actions used a runtime key, so they were
   English-only and invisible to the drift lint. **Fixed:** literal-keyed
   `label(for:)` switch (extractable) + the 4 keys added to the catalog (now
   lint-enforced); the 3 iOS-gated `FloatingAddButton` `.module` strings added to
   the catalog by hand; both extraction blind spots documented in engineering-notes.
3. **MEDIUM — `CompileCoreDataModel` `.xccurrentversion` dead branch (#2/#7).** The
   plugin claimed to track `.xccurrentversion`, but it's a dotfile the enumerator
   skips, and — verified empirically — neither enumeration nor an explicit input
   path makes llbuild re-run `momc` on its mtime from a build-tool plugin. **Fixed:**
   track only `*.xcdatamodel/contents` (the verified daily-edit invalidation) and
   document why `.xccurrentversion` is omitted + why it's harmless (a version switch
   always edits a `contents` file too).
4. **LOW — low-disk abort leaves mode flipped (#9).** This is the *already-documented*
   recovery-hardening tradeoff (reconfigure step 4 precedes the copyStore pre-flight
   step 5; "free space and try again"; no data loss — the original store is untouched).
   No code change; the existing engineering note already states it.

The 15 rejected findings were false positives (e.g. claims already handled, out of
Wave-7 scope, or pre-existing documented issues). Post-fix re-verification: drift
gate clean; LillistCore 868 green (modulo the 2 documented flakes); LillistUI logic
green; iOS standalone + macOS scheme green; privacy 5/5 both bundles; lint OK (166
keys); iOS+macOS+Release builds succeed.

## Pre-flight for anyone building on this

- `git log --oneline 1d9ff57..HEAD` — 28 Wave-7 commits.
- `swift test --package-path Packages/LillistCore --parallel --num-workers 2` (retry once on a flake).
- Snapshot tests: run on the canonical snapshot host (`xcodebuild test -scheme Lillist-iOS`), not CI / not host `swift test`.
- App-hosted live-swap + UI tests: run on a signed Mac with an iCloud account.
