# CI and Build Posture Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 7 (lands LAST).**
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> **Pre-flight (run before any edit):** Confirm Waves 1–6 are on `main` (`git log --oneline main | head -20`). Read `docs/superpowers/handoffs/wave-6.md`. Re-Read every file you touch and anchor by code **structure**, not line number — each wave shifts the shared hotspot files. On completion, write `docs/superpowers/handoffs/wave-7.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a GitHub Actions macOS CI workflow that runs the full test/build matrix post-push on `main`, and align Lillist's build posture so every quality gate (warnings-as-errors, snapshots, pbxproj drift, the Core Data model rebuild) is enforced automatically rather than from memory.

**Architecture:** Add one `.github/workflows/ci.yml` that, on push to `main`, runs `swift test` for both SPM packages (with bounded parallelism + a SIGSEGV/timing-flake retry per residual #11), regenerates both pbxprojs and fails on drift, runs the iOS xcodebuild test scheme (which transitively runs the merged app-hosted `LillistCore` host-gated tests in `Lillist-iOSAppHostedTests`), runs the macOS scheme tests, runs the LillistUI localization-lint job folded in from chain #6, and does a Release-configuration archive smoke build. Separately, three source-tree posture fixes harden the same gates locally: lift `LillistUI/Package.swift` to swift-tools 6.2 with `.treatAllWarnings(as: .error)` on both source and test targets (matching `LillistCore`) while excluding the test `__Snapshots__` dirs to clear the standing manifest warning; teach the `CompileCoreDataModel` plugin to declare the inner `*.xcdatamodel/contents` and `.xccurrentversion` as `inputFiles` so model edits no longer need the manual mtime-touch ritual; and scope the brittle exact-pixel tour-snapshot precision relaxation to the single Form-bearing tour snapshot only.

**Tech Stack:** GitHub Actions (macOS runner), Swift Package Manager 6.2, `xcodebuild`, `xcodegen` 2.45, `swift-snapshot-testing`, SwiftPM build-tool plugin API (`PackagePlugin`).

**Source findings:** build-1, build-2, build-3, build-4, build-5, ui-warn-1, ui-snap-1, test-5 (roadmap item #16; closes the "No CI/CD at all" blind spot). Also absorbs index **residual #11** (bound test parallelism / retry the intermittent parallel-test SIGSEGV + `SyncQuiesceMonitor` timing flake — see `docs/engineering-notes.md` 2026-06-04 entry) and closes **chain #6** (fold `lillistui-localization-a11y`'s standalone workflow into `ci.yml`).

---

## File Structure

| Path | Create/Modify | Responsibility |
|------|---------------|----------------|
| `.github/workflows/ci.yml` | **Create** | Post-push-on-`main` macOS CI: dual `swift test` (with bounded parallelism + a SIGSEGV/timing-flake retry per residual #11), pbxproj-drift gate, iOS + macOS xcodebuild test schemes, Release archive smoke build, the LillistUI localization-lint job folded in from chain #6, and failure notification on the run. |
| `.github/workflows/lillistui-localization.yml` | **Delete** (Task 6) | `lillistui-localization-a11y` (also Wave 7) creates this standalone workflow; fold its `localization-lint` job into `ci.yml` and delete the standalone file (chain #6). |
| `Packages/LillistUI/Package.swift` | **Modify** (anchor: `swift-tools-version` line + the `targets:` block; currently swift-tools `6.0`, test target has no `swiftSettings:`) | Bump to swift-tools 6.2; add `.treatAllWarnings(as: .error)` to source + test targets; exclude test `__Snapshots__` dirs to clear the 83-file manifest warning. |
| `Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift` | **Modify** (anchor: `createBuildCommands` + the `inputFiles:` declaration) | Walk each `.xcdatamodeld` and declare the inner `*.xcdatamodel/contents` + `.xccurrentversion` files as `inputFiles` so editing the model auto-invalidates the `momc` command (retires the mtime-touch ritual). |
| `Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift` | **Modify** (anchor: `test_08_settings_light` body + the `assertScreen` helper) | Relax snapshot precision for the one Form-bearing tour snapshot (`test_08_settings_light`) via an optional `precision`/`perceptualPrecision` param on `assertScreen`; leave all non-Form tour snapshots at exact-pixel. |
| `docs/engineering-notes.md` | **Modify** (prepend a new dated entry; anchor relative to the *latest existing* entry / true EOF) | Record the CI design, the deliberate Debug-for-iteration / Release-for-CI split, the retired mtime-touch ritual, the bounded-test-parallelism remedy for residual #11, and the cross-plan dependency on store-swap-safety's app-hosted test target. |
| `CLAUDE.md` | **Modify** (the "Build-plugin caching gotcha" + "Build & test" sections) | Note CI runs post-push on `main`; mark the mtime-touch ritual as retired by the plugin fix; document the bounded-parallelism `swift test` invocation (residual #11). |

---

### Task 1: Bump LillistUI to swift-tools 6.2 with warnings-as-error and clear the manifest warning

**Files:** Modify `Packages/LillistUI/Package.swift` (whole file — the `swift-tools-version` line and the `targets:` block; ~38 lines today).

This closes `ui-warn-1` (the standing "found 83 file(s) which are unhandled" manifest warning — verified live: the warning lists every `Tests/LillistUITests/**/__Snapshots__/*.png` baseline) and the LillistUI half of `build-3`/`build-4` (inconsistent warnings posture vs `LillistCore`). `LillistCore/Package.swift` is the canonical model: swift-tools `6.2`, `.treatAllWarnings(as: .error)` on source, test, executable, and CLI-test targets.

- [ ] **Step 1: Reproduce the manifest warning** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistUI 2>&1 | grep -c "unhandled"
  ```
  Expect a count `>= 1` (the warning text is `warning: 'lillistui': found 83 file(s) which are unhandled; explicitly declare them as resources or exclude from the target`). This is the failing-precondition for `ui-warn-1`.

- [ ] **Step 2: Apply the manifest edit** — replace the entire contents of `Packages/LillistUI/Package.swift` with:
  ```swift
  // swift-tools-version: 6.2
  import PackageDescription

  let package = Package(
      name: "LillistUI",
      platforms: [
          .macOS(.v15),
          .iOS(.v18)
      ],
      products: [
          .library(name: "LillistUI", targets: ["LillistUI"])
      ],
      dependencies: [
          .package(path: "../LillistCore"),
          .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
      ],
      targets: [
          .target(
              name: "LillistUI",
              dependencies: [
                  .product(name: "LillistCore", package: "LillistCore")
              ],
              resources: [
                  .process("Resources")
              ],
              swiftSettings: [
                  .enableExperimentalFeature("StrictConcurrency"),
                  .treatAllWarnings(as: .error)
              ]
          ),
          .testTarget(
              name: "LillistUITests",
              dependencies: [
                  "LillistUI",
                  .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
              ],
              exclude: [
                  "Recurrence/__Snapshots__",
                  "DragReorder/__Snapshots__",
                  "Tour/__Snapshots__",
                  "Snapshots/__Snapshots__",
                  "CrashReporting/__Snapshots__",
                  "iOS/__Snapshots__"
              ],
              swiftSettings: [
                  .treatAllWarnings(as: .error)
              ]
          )
      ]
  )
  ```
  Notes on the choices, all verified against the tree:
  - The six excluded paths are exactly the `__Snapshots__` directories under `Tests/LillistUITests/` (confirmed via `find Packages/LillistUI/Tests -type d -name "__Snapshots__"`: `Recurrence`, `DragReorder`, `Tour`, `Snapshots`, `CrashReporting`, `iOS`). Paths in `exclude:` are relative to the test target's source root (`Tests/LillistUITests/`). `swift-snapshot-testing` reads/writes these PNGs from disk at runtime by path, not from the resource bundle, so excluding them from the build is correct — they are test fixtures, never bundled resources.
  - `.treatAllWarnings(as: .error)` is added to **both** the source and test targets (the test target currently has no `swiftSettings:` at all), matching `LillistCore`'s posture exactly.
  - `StrictConcurrency` is kept on the source target only (matching `LillistCore`, whose test targets do not enable it — CLAUDE.md: "tests are not strict").

- [ ] **Step 3: Verify the warning is gone and the build is clean** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistUI 2>&1 | grep -c "unhandled"
  ```
  Expect `0`. Then run the host-platform test suite to prove `.treatAllWarnings(as: .error)` did not surface a latent warning-as-error in the source or test target:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI 2>&1 | tail -5
  ```
  Expect the suite to compile and the host-platform tests to pass (the `#if os(iOS)` snapshot/tour tests compile out on macOS — only host tests run here; that is expected). If the build now fails with a `warning treated as error`, fix the underlying warning at the source — do **not** soften the setting (house rule: warnings-as-errors, fix at the architecture level).

- [ ] **Step 4: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistUI/Package.swift && git commit -m "build(ui): swift-tools 6.2 + warnings-as-error, exclude snapshot dirs

Lift LillistUI to swift-tools 6.2 and add .treatAllWarnings(as: .error)
to the source and test targets, matching LillistCore's posture. Exclude
the six test __Snapshots__ directories so the standing 83-file manifest
warning ('found N file(s) which are unhandled') is gone — the PNG
baselines are read/written by swift-snapshot-testing at runtime by path,
never bundled.

Closes ui-warn-1; aligns build-3/build-4 warnings posture."
  ```

---

### Task 2: Declare the inner Core Data model files as plugin inputs

**Files:** Modify `Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift` (anchor: the `createBuildCommands` body and its `inputFiles:` declaration — ~lines 13-42 today).

This closes `build-5` and retires the manual mtime-touch ritual documented in CLAUDE.md ("Build-plugin caching gotcha") and `engineering-notes.md`. The current plugin declares `inputFiles: [inputURL]` where `inputURL` is the `.xcdatamodeld` **directory** — SwiftPM/llbuild keys the `momc` command on that directory's mtime, not on the inner `LillistModel.xcdatamodel/contents` file, so editing `contents` does not re-run `momc` and the stale `.momd` is reused (runtime `NSInvalidArgumentException: must have a valid NSEntityDescription`). The fix: keep the `.xcdatamodeld` directory as the `momc` **argument** (momc needs the bundle, not the inner file), but `FileManager`-walk it and add every inner `*.xcdatamodel/contents` plus the `.xccurrentversion` to `inputFiles` so llbuild invalidates the command on a real model edit.

- [ ] **Step 1: Confirm the current input declaration is the directory only** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -n "inputFiles" Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift
  ```
  Expect a single line `inputFiles: [inputURL],` where `inputURL = file.url` and `file.url.pathExtension == "xcdatamodeld"` (the directory). This is the failing-precondition for `build-5`.

- [ ] **Step 2: Apply the plugin edit** — replace the entire contents of `Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift` with:
  ```swift
  import Foundation
  import PackagePlugin

  /// Build tool plugin that compiles `.xcdatamodeld` files to `.momd` using
  /// Xcode's `momc` model compiler. SwiftPM does not invoke `momc` automatically
  /// on Core Data resources, so this plugin closes the gap.
  ///
  /// Each `.xcdatamodeld` resource declared on the target is compiled and
  /// the resulting `.momd` directory ends up in the target's resource bundle,
  /// loadable via `Bundle.module.url(forResource: "<name>", withExtension: "momd")`.
  @main
  struct CompileCoreDataModel: BuildToolPlugin {
      func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
          guard let sourceTarget = target as? SourceModuleTarget else { return [] }

          let modelDirs = sourceTarget.sourceFiles.filter { file in
              file.url.pathExtension == "xcdatamodeld"
          }

          return modelDirs.map { file in
              let inputURL = file.url
              let name = inputURL.deletingPathExtension().lastPathComponent
              // Output filename intentionally differs from `<name>.momd` so
              // the plugin's output does NOT collide with Xcode's built-in
              // `DataModelCompile` rule when this package is consumed from a
              // workspace (Xcode auto-compiles the same .xcdatamodeld into
              // `<name>.momd` and the two copy commands both target the same
              // bundle path, raising a "Multiple commands produce…" error).
              // Loaders (PersistenceController) look for `<name>.momd`
              // first, then `<name>.spm.momd` as a fallback for builds where
              // only this plugin runs (`swift test` / `swift build`).
              let outputURL = context.pluginWorkDirectoryURL.appendingPathComponent("\(name).spm.momd")

              // llbuild keys a build command on the mtime of its declared
              // `inputFiles`. The `.xcdatamodeld` is a *directory*, and its
              // mtime does NOT change when the inner `*.xcdatamodel/contents`
              // file is edited — so declaring only the directory caused a
              // stale `.momd` to be reused after a model edit (runtime
              // `NSInvalidArgumentException: must have a valid
              // NSEntityDescription`). Declare the inner version files
              // (`*.xcdatamodel/contents`) and the `.xccurrentversion`
              // pointer as inputs so a real model edit invalidates `momc`.
              // momc itself still takes the `.xcdatamodeld` directory as its
              // argument — it needs the whole versioned bundle, not one file.
              let modelInputs = Self.modelInputFiles(in: inputURL)

              return .buildCommand(
                  displayName: "Compiling Core Data model \(name)",
                  executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                  arguments: ["momc", inputURL.path, outputURL.path],
                  inputFiles: [inputURL] + modelInputs,
                  outputFiles: [outputURL]
              )
          }
      }

      /// Enumerates the build-relevant files *inside* an `.xcdatamodeld`
      /// bundle that should invalidate the `momc` command when edited:
      /// every `*.xcdatamodel/contents` (one per model version) and the
      /// top-level `.xccurrentversion` pointer (present in versioned models).
      /// Returns an empty array on any enumeration failure so the build
      /// degrades to the previous directory-only behaviour rather than
      /// crashing the plugin.
      private static func modelInputFiles(in modelBundle: URL) -> [URL] {
          let fileManager = FileManager.default
          guard let enumerator = fileManager.enumerator(
              at: modelBundle,
              includingPropertiesForKeys: nil,
              options: [.skipsHiddenFiles]
          ) else {
              return []
          }

          var inputs: [URL] = []
          for case let url as URL in enumerator {
              let lastComponent = url.lastPathComponent
              let isModelContents =
                  lastComponent == "contents"
                  && url.deletingLastPathComponent().pathExtension == "xcdatamodel"
              let isCurrentVersionPointer = lastComponent == ".xccurrentversion"
              if isModelContents || isCurrentVersionPointer {
                  inputs.append(url)
              }
          }
          return inputs
      }
  }
  ```
  Note: `.skipsHiddenFiles` skips dotfiles *during traversal* but the enumerator still yields the top-level `.xccurrentversion` because it is a direct child being enumerated; to be safe the option is paired with an explicit name check. If `.xccurrentversion` is ever filtered by the hidden-files option on a future SDK, the `contents` inputs alone still close `build-5` — the version pointer only matters when you add/switch model versions, which is rare; the `contents` edit is the daily case.

- [ ] **Step 3: Prove the fix re-runs `momc` after a model edit *without* the mtime touch** — this is the regression that `build-5` is about. Run a clean build, then make a no-op-but-mtime-changing edit to `contents` and rebuild, asserting the recompile fires:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    swift build --package-path Packages/LillistCore 2>&1 | tail -2 && \
    touch -m -t 203001010000 Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents && \
    swift build --package-path Packages/LillistCore -v 2>&1 | grep -c "momc"
  ```
  Expect the second command's `grep -c "momc"` to be `>= 1` — the `momc` command re-ran because `contents` (now a declared input) changed mtime, **without** touching the `.xcdatamodeld` directory itself. Before this fix, the recompile would not fire on a `contents`-only mtime change. (Reset the mtime afterward so git doesn't see a spurious change: `touch Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents` — `contents` file body is unchanged so `git status` stays clean.)

- [ ] **Step 4: Run the LillistCore suite to confirm the rebuilt model loads** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -5
  ```
  Expect the full suite to pass (no `NSInvalidArgumentException: must have a valid NSEntityDescription`). This proves the freshly-compiled `.spm.momd` is valid and loadable.

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift && git commit -m "build(core): declare inner model files as plugin inputs

CompileCoreDataModel declared only the .xcdatamodeld *directory* as an
input, so llbuild keyed the momc command on the directory mtime — which
does not change when the inner LillistModel.xcdatamodel/contents is
edited. Stale .momd reuse then crashed at runtime with
NSInvalidArgumentException. FileManager-walk the bundle and declare each
*.xcdatamodel/contents and the .xccurrentversion as inputFiles; momc
still takes the .xcdatamodeld directory as its argument.

Retires the manual mtime-touch ritual. Closes build-5."
  ```

---

### Task 3: Scope the brittle tour-snapshot precision relaxation to the Form-bearing snapshot

**Files:** Modify `Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift` (anchor: the `test_08_settings_light` body — ~line 281 today — and the `private func assertScreen<V: View>` helper — ~line 558 today).

This closes `ui-snap-1` (LillistUI lane: "brittle exact-pixel snapshots"). Verified live: `assertScreen` currently calls `assertSnapshot(of: host, as: .image(size: size, traits: traits), …)` with **no** `precision:`/`perceptualPrecision:` — i.e. exact-pixel (1.0). The engineering-notes entry "Snapshot test reliability: SwiftUI `Form` views drift on cold-cache runs" (2026-05-17) establishes the precedent: **`Form`-rendered snapshots** accumulate per-section AA drift and need `precision: 0.99, perceptualPrecision: 0.98`; non-Form views stay strict so they keep catching real regressions. The scope here is deliberately narrow: only `test_08_settings_light` renders a `Form` (via `SettingsScreen`, whose body is `NavigationStack { Form { … } }`, confirmed). Every other tour snapshot stays exact-pixel.

- [ ] **Step 1: Confirm `assertScreen` is exact-pixel and `test_08` is the only Form-bearing tour test** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    grep -n "as: .image" Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift && \
    grep -n "SettingsScreen\|Form" Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift
  ```
  Expect: the `assertScreen` call uses `.image(size: size, traits: traits)` (no precision); the only `SettingsScreen` reference is in `test_08_settings_light`; no other `Form` usage in the tour file. This confirms the narrow scope.

- [ ] **Step 2: Add optional precision params to `assertScreen`** — replace the `assertScreen` helper (the `private func assertScreen<V: View>( … )` through its closing `}`, ~line 558 today — re-anchor by reading) with:
  ```swift
      private func assertScreen<V: View>(
          _ view: V,
          name: String,
          colorScheme: ColorScheme,
          size: CGSize,
          precision: Float = 1,
          perceptualPrecision: Float = 1,
          fileID: StaticString = #fileID,
          filePath: StaticString = #filePath,
          testName: String = #function,
          line: UInt = #line,
          column: UInt = #column
      ) {
          let host = UIHostingController(rootView:
              view.environment(\.colorScheme, colorScheme)
                  .environment(\.locale, Locale(identifier: "en_US"))
          )
          host.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
          host.view.frame = CGRect(origin: .zero, size: size)
          host.view.layoutIfNeeded()
          let traits = UITraitCollection(traitsFrom: [
              UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light),
              UITraitCollection(displayScale: 2)
          ])
          assertSnapshot(
              of: host,
              as: .image(precision: precision,
                         perceptualPrecision: perceptualPrecision,
                         size: size,
                         traits: traits),
              named: name,
              fileID: fileID, file: filePath, testName: testName, line: line, column: column
          )
      }
  ```
  Note: the defaults (`precision: 1, perceptualPrecision: 1`) are exact-pixel — identical to today's behaviour for every existing call site that doesn't pass them. The `Snapshotting<UIViewController, UIImage>.image(precision:perceptualPrecision:size:traits:)` factory exists in swift-snapshot-testing 1.17 (the version pinned in `Package.swift`); all four params are accepted on iOS.

- [ ] **Step 3: Apply the relaxed precision to the one Form-bearing call** — in `test_08_settings_light`, change the single `assertScreen(view, name: "08-settings-light", …)` assertion (~line 308 today) from:
  ```swift
          assertScreen(view, name: "08-settings-light", colorScheme: .light, size: phoneSize)
  ```
  to:
  ```swift
          // SettingsScreen renders a SwiftUI Form, whose per-section AA drift
          // breaches exact-pixel on cold-cache renders (see engineering-notes
          // 2026-05-17 "Form views drift on cold-cache runs"). Relax this one
          // tour snapshot to the Form precision pair; all other tour snapshots
          // stay exact-pixel so they keep catching real regressions.
          assertScreen(view, name: "08-settings-light", colorScheme: .light,
                       size: phoneSize, precision: 0.99, perceptualPrecision: 0.98)
  ```

- [ ] **Step 4: Run the tour suite under the iOS scheme and confirm green** — these snapshots are `#if os(iOS)`, so they only run under xcodebuild, not `swift test`:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test \
    -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    -only-testing:LillistUITests/IOSScreenTourTests 2>&1 | tail -15
  ```
  Expect `** TEST SUCCEEDED **` with `test_08_settings_light` passing (and all other `IOSScreenTourTests` still passing at their default exact-pixel precision). The existing `08-settings-light` baseline PNG is reused — the relaxation only widens the tolerance, it does not require re-recording.

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift && git commit -m "test(ui): relax precision for the Form-bearing tour snapshot only

assertScreen rendered every tour snapshot at exact-pixel (1.0). The one
Form-bearing screen (test_08_settings_light, via SettingsScreen's
NavigationStack+Form) accumulates per-section AA drift on cold-cache
renders, per the 2026-05-17 engineering note. Add optional
precision/perceptualPrecision params (default 1.0 = unchanged for every
other call) and apply 0.99/0.98 to test_08 only. Non-Form tour
snapshots stay strict.

Closes ui-snap-1."
  ```

---

### Task 4: Add the GitHub Actions CI workflow

**Files:** Create `.github/workflows/ci.yml`.

This closes `build-1` (no CI), `build-2` (no pbxproj-drift gate), the CI half of `build-3`/`build-4` (warnings/Release posture enforcement), and `test-5` (the test/build matrix isn't run automatically anywhere — every gate is "what the dev remembers to run locally"). It also closes the completeness-critic blind spot "No CI/CD at all." Triggered **post-push on `main`** because this is a solo project that commits directly to `main` (CLAUDE.md "Git workflow"): there are no PRs to gate, so CI is a post-push verifier with failure surfaced on the run.

> **⚠️ Execution gotcha — read the two execution-gotcha blockquotes inside Step 2 before writing the file.** The `ios` job and the `release-archive-smoke` job both interact with the now-merged `Lillist-iOSAppHostedTests` app-hosted test target (`TEST_HOST=$(BUILT_PRODUCTS_DIR)/Lillist.app/Lillist`, `CODE_SIGN_STYLE: Automatic`) and the `Lillist-iOSUITests` host-app UI-test target. The `CODE_SIGNING_ALLOWED=NO` recipe that works for plain `build` does **not** let an unsigned host `.app` install/launch on the simulator for test-hosting, so as-written the `ios` job would skip (or fail) exactly the host-gated migration/swap tests this plan exists to enforce. Step 2 contains the corrected guidance (Option (a): ad-hoc simulator signing — preferred; or Option (b): scope to standalone bundles + document the limitation) and the scoped Release-smoke build. Whether CI ends up *executing* the host-gated tests depends on which option you choose — do not claim it does until Option (a) is verified green.

- [ ] **Step 1: Confirm there is no existing workflow** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && ls .github/workflows 2>/dev/null || echo "NO .github/workflows"
  ```
  Expect `NO .github/workflows`. This is the failing-precondition for `build-1`.

- [ ] **Step 2: Create the workflow file** — write `.github/workflows/ci.yml` with exactly:
  ```yaml
  name: CI

  # Solo project: commits land directly on main (no PR review). CI runs
  # post-push as a verifier — it does not gate a merge, it surfaces a
  # red run + failure email if a pushed commit broke a quality gate.
  # Also runnable on demand via the Actions tab.
  on:
    push:
      branches: [main]
    workflow_dispatch:

  concurrency:
    # Newer pushes to main supersede in-flight runs for the same ref.
    group: ci-${{ github.ref }}
    cancel-in-progress: true

  jobs:
    spm:
      name: SPM packages (swift test)
      runs-on: macos-15
      timeout-minutes: 30
      steps:
        - uses: actions/checkout@v4

        - name: Select Xcode 26.3
          run: sudo xcode-select -switch /Applications/Xcode_26.3.app

        - name: Print toolchain
          run: |
            swift --version
            xcodebuild -version

        # LillistCore is container-heavy: dozens of suites build in-memory
        # NSPersistentContainers in parallel, which intermittently SIGSEGVs
        # inside Core Data's framework-internal per-entity state, and the
        # same CPU contention starves SyncQuiesceMonitorTests' timing window
        # (docs/engineering-notes.md 2026-06-04 "Intermittent SIGSEGV under
        # heavy parallel in-memory store creation"; index residual #11).
        # Neither is a product bug — production never creates more than one
        # container — so the deterministic, verifiable mitigation is at the
        # runner: bound parallelism (--num-workers) and retry once so a
        # one-off SIGSEGV / timing flake re-runs instead of failing CI.
        # See Task 6 for the matching CLAUDE.md note.
        - name: Test LillistCore (bounded parallelism, retry on flake)
          run: |
            swift test --package-path Packages/LillistCore --num-workers 2 \
              || swift test --package-path Packages/LillistCore --num-workers 2

        - name: Test LillistUI (host platform)
          run: swift test --package-path Packages/LillistUI --num-workers 2

    project-drift:
      name: pbxproj drift (xcodegen)
      runs-on: macos-15
      timeout-minutes: 15
      steps:
        - uses: actions/checkout@v4

        - name: Select Xcode 26.3
          run: sudo xcode-select -switch /Applications/Xcode_26.3.app

        - name: Install xcodegen
          run: brew install xcodegen

        - name: Regenerate iOS project
          working-directory: Apps/Lillist-iOS
          run: xcodegen generate --spec project.yml --project .

        - name: Regenerate macOS project
          working-directory: Apps
          run: xcodegen generate --spec project.yml --project .

        - name: Fail on uncommitted project drift
          run: |
            if ! git diff --exit-code -- '*.xcodeproj/project.pbxproj'; then
              echo "::error::Generated pbxproj differs from the committed one."
              echo "::error::Run xcodegen locally and commit the result."
              exit 1
            fi

    ios:
      name: iOS scheme (xcodebuild test)
      runs-on: macos-15
      timeout-minutes: 45
      steps:
        - uses: actions/checkout@v4

        - name: Select Xcode 26.3
          run: sudo xcode-select -switch /Applications/Xcode_26.3.app

        - name: Install xcodegen
          run: brew install xcodegen

        - name: Generate projects
          run: |
            (cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .)
            (cd Apps && xcodegen generate --spec project.yml --project .)

        - name: Provide a placeholder signing team
          # Signing.local.xcconfig is gitignored; CI builds without signing,
          # so seed the placeholder the xcconfig indirection expects. Tests
          # run on the simulator and the smoke archive uses CODE_SIGNING_ALLOWED=NO.
          run: cp Apps/Config/Signing.local.xcconfig.example Apps/Config/Signing.local.xcconfig

        - name: Test Lillist-iOS scheme
          # Runs Lillist-iOSTests, Lillist-iOSUITests, the
          # Lillist-iOSAppHostedTests app-hosted bundle (the host-gated
          # liveSwapAllowed migration/swap tests), and the
          # LillistUI/LillistUITests SPM bundle (iOS snapshot + tour tests
          # that compile out under `swift test`).
          #
          # ⚠️ The CODE_SIGNING_ALLOWED=NO recipe shown here is a
          # PLACEHOLDER and is WRONG for this scheme as written — resolve
          # it per the execution gotcha below BEFORE landing the workflow.
          run: |
            set -o pipefail
            which xcbeautify || brew install xcbeautify
            xcodebuild test \
              -workspace Lillist.xcworkspace \
              -scheme Lillist-iOS \
              -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
              CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
              | xcbeautify
  ```

  > **⚠️ Execution gotcha — the `ios` job will NOT run the host-gated tests it claims to, and may fail to build.** Two scheme targets need to **install + launch the host `Lillist.app` on the simulator** to run: `Lillist-iOSAppHostedTests` (`TEST_HOST=$(BUILT_PRODUCTS_DIR)/Lillist.app/Lillist`, `BUNDLE_LOADER=$(TEST_HOST)`, `CODE_SIGN_STYLE: Automatic` — verified in `Apps/Lillist-iOS/project.yml` lines ~187-209) and `Lillist-iOSUITests` (`type: bundle.ui-testing`, `dependencies: Lillist-iOS`, `CODE_SIGN_STYLE: Automatic` — lines ~164-180). Passing `CODE_SIGNING_ALLOWED=NO` strips signing, and an **unsigned host app cannot be installed/launched on the simulator for test-hosting** — so the `liveSwapAllowed`-gated tests (gated on `Bundle.main.bundleIdentifier?.isEmpty == false`, which is only true inside a real host) would silently skip, and the UI-test bundle's launch would error out. This is exactly the constraint engineering-notes records for the macOS lane ("With those flags the test bundle can't load a fully-signed `.app` host" — which is *why* the macOS test target is standalone `TEST_HOST=""`). The iOS app-hosted target has **no** such standalone fallback. Wave 1's own note states this target "needs a code-signed simulator host to actually RUN." Pick ONE of the following and replace the placeholder step accordingly:
  >
  > **Option (a) — sign for the simulator so the host-gated tests actually execute (preferred).** Drop `CODE_SIGNING_ALLOWED=NO`/`CODE_SIGN_IDENTITY=""`/`CODE_SIGNING_REQUIRED=NO` from the **simulator `test` step only** and let Xcode ad-hoc-sign for the simulator. GitHub-hosted macOS runners can ad-hoc-sign apps **for the simulator** without an Apple Developer team (simulator builds don't require a provisioning profile or a real signing identity — the simulator accepts ad-hoc `-` signing). Set `CODE_SIGNING_ALLOWED=YES` and let `CODE_SIGN_IDENTITY` default to `-` (ad-hoc); the seeded placeholder `Signing.local.xcconfig` keeps the xcconfig indirection resolvable even though its team value is empty. Verify locally first — run the full `xcodebuild test -scheme Lillist-iOS` on a Mac **without** the no-signing flags and confirm `Lillist-iOSAppHostedTests` and `Lillist-iOSUITests` both *install + launch* the host on the simulator and report their gated tests as **run, not skipped** (look for the `liveSwapAllowed` tests executing). The "no-signing recipe" from CLAUDE.md applies to `xcodebuild **build**`, NOT to host-app `xcodebuild test`. Concretely, the step becomes:
  > ```yaml
  >         - name: Test Lillist-iOS scheme (simulator ad-hoc signing)
  >           run: |
  >             set -o pipefail
  >             which xcbeautify || brew install xcbeautify
  >             xcodebuild test \
  >               -workspace Lillist.xcworkspace \
  >               -scheme Lillist-iOS \
  >               -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  >               CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-" \
  >               | xcbeautify
  > ```
  > If ad-hoc simulator signing turns out to need a `DEVELOPMENT_TEAM`, the team value can be injected from a CI secret into `Signing.local.xcconfig` (write `LOCAL_DEVELOPMENT_TEAM=${{ secrets.DEVELOPMENT_TEAM }}` in the "Provide a placeholder signing team" step) — but try ad-hoc `-` first, as simulator hosting generally does not require a team.
  >
  > **Option (b) — if CI cannot sign at all, scope the job and document the real limitation.** Keep `CODE_SIGNING_ALLOWED=NO` but run **only** the targets that work standalone, and EXCLUDE the two host-app targets. The standalone-runnable targets are `Lillist-iOSTests` (`TEST_HOST=""`, verified lines ~124-160) and the `LillistUI/LillistUITests` SPM bundle. `Lillist-iOSUITests` and `Lillist-iOSAppHostedTests` are NOT runnable without signing and must be excluded. Use `-only-testing`:
  > ```yaml
  >         - name: Test Lillist-iOS scheme (standalone bundles only — no signing)
  >           run: |
  >             set -o pipefail
  >             which xcbeautify || brew install xcbeautify
  >             xcodebuild test \
  >               -workspace Lillist.xcworkspace \
  >               -scheme Lillist-iOS \
  >               -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  >               -only-testing:Lillist-iOSTests \
  >               -only-testing:LillistUITests \
  >               CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  >               | xcbeautify
  > ```
  > Then EXPLICITLY document in Task 5's engineering-notes entry that the `liveSwapAllowed`-gated migration/swap tests (`Lillist-iOSAppHostedTests`) and the end-to-end UI tests (`Lillist-iOSUITests`) **do not run in CI** — they run only on a developer's signed Mac (`xcodebuild test -scheme Lillist-iOS` with a real `Signing.local.xcconfig`). This is a real, stated limitation, and it matches exactly how Wave 1 verified those tests (on a developer's signed Mac). Update the Self-review checklist and Task 5 cross-plan note to say "host-gated tests run on a signed developer Mac, not in CI" rather than claiming CI "finally executes" them.
  >
  > **Decision guidance:** Prefer (a) — it makes the host-gated tests actually enforceable in CI, which is the whole point of this plan. Only fall back to (b) if simulator ad-hoc signing cannot be made to work on the hosted runner after a genuine local attempt. Whichever you pick, the placeholder step above must be replaced — do not ship it as written.

  *(The workflow YAML continues below — this is one file. The `yaml` fence breaks in this step exist only to host the execution-gotcha blockquotes; concatenate the **2-space-indented** top-level `yaml` blocks in Step 2 — in order — into a single `.github/workflows/ci.yml`. The `yaml` snippets *inside* the gotcha blockquotes (Option (a)/(b) test steps) and the more-deeply-indented snippet in the Design-notes "Simulator runtime availability" bullet are alternatives/remedies you splice in **only if** the corresponding gotcha applies — they are NOT part of the base file.)*

  ```yaml

    macos:
      name: macOS scheme (xcodebuild test)
      runs-on: macos-15
      timeout-minutes: 30
      steps:
        - uses: actions/checkout@v4

        - name: Select Xcode 26.3
          run: sudo xcode-select -switch /Applications/Xcode_26.3.app

        - name: Install xcodegen
          run: brew install xcodegen

        - name: Generate projects
          run: |
            (cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .)
            (cd Apps && xcodegen generate --spec project.yml --project .)

        - name: Provide a placeholder signing team
          run: cp Apps/Config/Signing.local.xcconfig.example Apps/Config/Signing.local.xcconfig

        - name: Test Lillist-macOS scheme
          # macOS test target is standalone (TEST_HOST="" in Apps/project.yml),
          # so the no-signing recipe is correct here — there is no host .app to
          # install/launch (see engineering-notes: macOS test bundle made
          # standalone precisely so CODE_SIGNING_ALLOWED=NO works).
          run: |
            set -o pipefail
            which xcbeautify || brew install xcbeautify
            xcodebuild test \
              -workspace Lillist.xcworkspace \
              -scheme Lillist-macOS \
              -destination 'platform=macOS' \
              CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
              | xcbeautify

    release-archive-smoke:
      name: Release archive smoke build
      runs-on: macos-15
      timeout-minutes: 45
      steps:
        - uses: actions/checkout@v4

        - name: Select Xcode 26.3
          run: sudo xcode-select -switch /Applications/Xcode_26.3.app

        - name: Install xcodegen
          run: brew install xcodegen

        - name: Generate projects
          run: |
            (cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .)
            (cd Apps && xcodegen generate --spec project.yml --project .)

        - name: Provide a placeholder signing team
          run: cp Apps/Config/Signing.local.xcconfig.example Apps/Config/Signing.local.xcconfig

        - name: Release-configuration build (smoke)
          # deployit archives with -configuration Debug for fast iteration
          # (Apps/Lillist-iOS/project.yml scheme: archive.config: Debug). CI
          # is the *only* place a Release-configuration compile is exercised,
          # catching Release-only optimizer/dead-code/whole-module issues that
          # Debug never sees. Smoke = compile under Release without signing;
          # not a shippable archive.
          #
          # Build the app target by name (NOT the whole scheme) so the
          # no-signing build never pulls in the app-hosted test target —
          # see execution gotcha below.
          run: |
            set -o pipefail
            which xcbeautify || brew install xcbeautify
            xcodebuild build \
              -workspace Lillist.xcworkspace \
              -scheme Lillist-iOS \
              -target Lillist-iOS \
              -configuration Release \
              -destination 'generic/platform=iOS' \
              CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
              | xcbeautify
  ```

  > **⚠️ Execution gotcha — scope the Release smoke so it never builds the app-hosted test target under no-signing.** With `Lillist-iOSAppHostedTests` (`CODE_SIGN_STYLE: Automatic`) now on the `Lillist-iOS` scheme, a bare `xcodebuild build -scheme Lillist-iOS ... CODE_SIGNING_ALLOWED=NO` may attempt to compile/sign that test target and fail. In the scheme, the app-hosted target is registered as `Lillist-iOSAppHostedTests: [test]` (build phase = *test only*, verified in `Apps/Lillist-iOS/project.yml` scheme `build.targets`), so a `build` action *should* skip it — but do not rely on that silently. **Build the app target explicitly** as shown (`-target Lillist-iOS`), which compiles only the app (and its app/extension dependencies) under Release and leaves every test target out of the no-signing build. Verify locally: `xcodebuild build -scheme Lillist-iOS -target Lillist-iOS -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO ...` must reach `** BUILD SUCCEEDED **` without any `Lillist-iOSAppHostedTests` or signing-required errors. If `-target` is rejected in combination with `-scheme` on this Xcode, fall back to `-only-testing`-style narrowing is N/A for `build`; instead build via `-workspace`/`-project` + `-target Lillist-iOS` without `-scheme`, or split the app into its own scheme for the smoke. The goal is unchanged: exercise the **Release compile of the app**, nothing test-hosted.

  *(Final YAML block of `.github/workflows/ci.yml` follows — append it after the blocks above. The `localization-lint` job is folded in from chain #6; see Task 6 for the standalone-file deletion that pairs with it.)*

  ```yaml

    localization-lint:
      # Folded in from lillistui-localization-a11y (also Wave 7): instead of a
      # standalone .github/workflows/lillistui-localization.yml, run its lint
      # as a job here so .github/workflows/ holds exactly one workflow. Task 6
      # deletes the standalone file. The durable artifact is the plan-owned
      # Tools/CI/check-lillistui-localization.sh script.
      name: LillistUI localization extraction-drift lint
      runs-on: macos-15
      timeout-minutes: 20
      steps:
        - uses: actions/checkout@v4

        - name: Select Xcode 26.3
          run: sudo xcode-select -switch /Applications/Xcode_26.3.app

        - name: Verify jq is available
          run: jq --version

        - name: Run LillistUI localization extraction-drift lint
          run: ./Tools/CI/check-lillistui-localization.sh

    notify:
      name: Notify on failure
      runs-on: macos-15
      needs: [spm, project-drift, ios, macos, release-archive-smoke, localization-lint]
      if: failure()
      steps:
        - name: Mark the run failed
          # GitHub already emails the actor on a failed run on a branch they
          # pushed; this job makes the failure a single explicit signal at the
          # bottom of the matrix so a partial-green run reads as red at a glance.
          run: |
            echo "::error::A CI gate failed on $GITHUB_REF — see the failed job above."
            exit 1
  ```
  Design notes (all verified against the repo):
  - `macos-15` is the GitHub-hosted runner image that ships Xcode 26.x; the `xcode-select` step pins `Xcode_26.3.app` to match the local toolchain (Xcode 26.3 / Swift 6.2.4 / iOS 26.2 simulator) — the snapshot tests are simulator-version-sensitive (engineering-notes "canonical simulator pin: iPhone 17 on iOS 26.2"). If a future runner image drops 26.3, this step is the single place to bump.
  - `xcbeautify` is usually preinstalled on the GitHub macOS runner images, but image contents drift — every step that pipes to it guards with `which xcbeautify || brew install xcbeautify` so a missing binary self-heals instead of failing the run. `set -o pipefail` ensures a non-zero `xcodebuild` exit survives the pipe.
  - The drift gate uses `git diff --exit-code -- '*.xcodeproj/project.pbxproj'` so only the *generated* pbxproj is policed (not the user-data xcodegen also writes). This matches the two `xcodegen generate` invocations in CLAUDE.md. This plan lands **last** in Wave 7, so the gate validates the *final* committed pbxprojs after every earlier wave that moved/added source files has already regenerated them — Step 4 (and the `project-drift` job on first run) flags any pre-existing drift the prior waves left uncommitted, which must be committed before CI goes green.
  - The `ios` job **runs the existing** `Lillist-iOSAppHostedTests` target (created and wired onto the `Lillist-iOS` scheme by the merged `store-swap-safety` plan — this plan does not create it). Likewise it does not create `Lillist-iOSUITests` or the scheme; it only executes them.
  - The Release smoke uses `xcodebuild build -configuration Release -destination 'generic/platform=iOS'` (a device-generic compile) rather than `archive`, because `archive` would trip the build-number bump pre-action and require signing; the goal is to exercise the Release compile path, which deployit's Debug archives never do. It builds the app target explicitly (`-target Lillist-iOS`) so the no-signing build never pulls in the app-hosted test target (see the Release-smoke execution gotcha above).
  - The placeholder team is copied from the committed `Apps/Config/Signing.local.xcconfig.example` (confirmed present per CLAUDE.md "Code signing"). For the `build`-action jobs (drift, macOS test, Release smoke) every build sets `CODE_SIGNING_ALLOWED=NO`, so the actual team value is irrelevant — the file just has to exist so the `#include?` indirection resolves `$(LOCAL_DEVELOPMENT_TEAM)`. **Exception:** if the `ios` job adopts Option (a) (ad-hoc simulator signing so the host-gated tests run), that job builds *with* signing allowed; the placeholder is still fine for ad-hoc `-` signing, but if a `DEVELOPMENT_TEAM` proves necessary, inject it from a CI secret in the "Provide a placeholder signing team" step (see the `ios` job execution gotcha).
  - **Bounded `swift test` parallelism + flake retry (residual #11).** The `spm` job runs both `swift test`s with `--num-workers 2` and retries the LillistCore run once on non-zero exit. This is the runner-level mitigation for the intermittent parallel-test SIGSEGV and the `SyncQuiesceMonitorTests` timing flake documented in `docs/engineering-notes.md` (2026-06-04). Neither is a product bug — production never builds more than one `NSPersistentContainer` — so the fix lives in CI invocation, not source. Task 6 mirrors the same bounded invocation into CLAUDE.md's "Build & test" so local runs match. (If `--num-workers` is unavailable on the pinned toolchain, fall back to `--no-parallel` for LillistCore; confirm with `swift test --help` on the runner.)
  - **The `localization-lint` job is the merged chain #6 artifact.** `lillistui-localization-a11y` (also Wave 7) produces the durable `Tools/CI/check-lillistui-localization.sh` lint and *would* have shipped a standalone `.github/workflows/lillistui-localization.yml`. Because `.github/workflows/` is owned by this plan, the lint runs as the `localization-lint` job here instead, and Task 6 deletes the standalone file so the repo holds exactly one workflow. The `notify` job's `needs:` includes `localization-lint` so a lint failure also reads as a red run.
  - **Simulator runtime availability.** The destination pins `iPhone 17 / iOS 26.2`. The GitHub `macos-15` image with Xcode 26.3 should ship that runtime, but hosted-image contents drift and the exact iOS 26.2 runtime is not guaranteed present. If `xcodebuild test` fails with "Unable to find a destination matching the provided destination specifier" or "iOS 26.2 is not installed", the runtime must be provisioned before the test step. Remedy — add a step before the test that downloads/installs and verifies the runtime:
    ```yaml
            - name: Ensure iOS 26.2 simulator runtime
              run: |
                xcrun simctl runtime list || true
                xcodebuild -downloadPlatform iOS -buildVersion 26.2 || \
                  xcrun simctl runtime add "iOS 26.2" || true
                xcrun simctl list devices 'iOS 26.2' | grep -q "iPhone 17" || \
                  xcrun simctl create "iPhone 17" "iPhone 17" "iOS26.2"
    ```
    (The exact incantation varies by Xcode version — `xcrun simctl runtime` subcommands and `xcodebuild -downloadPlatform` are both viable; run `xcrun simctl runtime --help` on the runner to confirm. Keep the `|| true` guards so a runtime that is already present doesn't fail the step.) Only add this if the default runtime is actually missing on the chosen image — don't pre-emptively slow every run.

- [ ] **Step 3: Lint the workflow YAML locally** — GitHub Actions YAML must parse; verify with the bundled Python:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ci.yml: valid YAML')"
  ```
  Expect `ci.yml: valid YAML`. If `yaml` is unavailable, fall back to `python3 -c "import json; print('skip')"` is *not* sufficient — instead use `ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml'); puts 'ok'"` (Ruby ships on macOS). Either way the YAML must load without error.

- [ ] **Step 4: Verify the local commands the workflow runs actually pass** — before relying on CI, run the two host commands the `spm` job runs (the iOS/macOS xcodebuild jobs are too slow to fully gate here, but the SPM jobs are fast and prove the matrix's foundation):
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    swift test --package-path Packages/LillistCore 2>&1 | tail -3 && \
    swift test --package-path Packages/LillistUI 2>&1 | tail -3
  ```
  Expect both suites green. Then prove the drift gate passes on the committed tree:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    (cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .) && \
    (cd Apps && xcodegen generate --spec project.yml --project .) && \
    git diff --exit-code -- '*.xcodeproj/project.pbxproj' && echo "DRIFT GATE: clean"
  ```
  Expect `DRIFT GATE: clean` (exit 0). If the regen produces a diff, the committed pbxproj is already drifted — commit the regenerated pbxproj first (that drift is pre-existing, not caused by this plan) before proceeding, so CI starts green.

- [ ] **Step 4b: Resolve the `ios`-job signing decision locally before pushing** — the SPM/drift checks above do **not** exercise the `Lillist-iOS` xcodebuild scheme, which is where the app-hosted/signing gotcha bites. On a Mac with a populated `Apps/Config/Signing.local.xcconfig`, run the scheme *with signing allowed* and confirm the host-gated tests actually execute (Option (a) path):
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test \
    -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-" 2>&1 | tail -40
  ```
  Confirm `Lillist-iOSAppHostedTests` and `Lillist-iOSUITests` install + launch the host and that the `liveSwapAllowed`-gated tests report as **run, not skipped**. If ad-hoc `-` signing is rejected, retry with the real local team (omit the signing overrides entirely). Whichever recipe makes the host-gated tests run locally is the one to mirror into the `ios` job's test step (replacing the placeholder). If neither can be made to work on a hosted runner, fall back to Option (b) (scope to standalone bundles + document the limitation in Task 5). **Do not push the workflow with the placeholder `CODE_SIGNING_ALLOWED=NO` iOS step intact.**

  **Placeholder-detection guard (mandatory — keep this check):** the `ios` job's test step ships as a deliberately-wrong placeholder. Before committing Task 4's `ci.yml`, prove the placeholder is gone — an unscoped `CODE_SIGNING_ALLOWED=NO` `xcodebuild test -scheme Lillist-iOS` step would silently skip the host-gated tests. Run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    awk '/^    ios:/{f=1} f&&/^    [a-z].*:/&&!/^    ios:/{f=0} f' .github/workflows/ci.yml \
      | grep -q "CODE_SIGNING_ALLOWED=NO" \
      && { echo "FAIL: ios job still has CODE_SIGNING_ALLOWED=NO — resolve Option (a)/(b)"; exit 1; } \
      || echo "OK: ios job is not the no-signing placeholder"
  ```
  If you chose **Option (b)** (signing genuinely impossible on the runner), the `ios` test step *does* keep `CODE_SIGNING_ALLOWED=NO`, but ONLY together with `-only-testing:Lillist-iOSTests` + `-only-testing:LillistUITests` that exclude the two host-app targets — so adjust the guard to additionally require both `-only-testing` flags are present whenever `CODE_SIGNING_ALLOWED=NO` is, and fail if the no-signing flag appears without them. The point is identical either way: a no-signing iOS step that silently drops the host-gated tests must never be committed.

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add .github/workflows/ci.yml && git commit -m "ci: add post-push macOS workflow for the full test/build matrix

Solo project pushes land on main directly, so CI runs post-push as a
verifier: swift test for LillistCore + LillistUI (bounded --num-workers
parallelism + a retry, per the 2026-06-04 parallel-test SIGSEGV /
SyncQuiesceMonitor timing-flake note — residual #11), an xcodegen-regen +
git-diff pbxproj-drift gate, the Lillist-iOS and Lillist-macOS
xcodebuild test schemes (the iOS scheme transitively runs the
LillistUI iOS snapshot/tour bundle and — when the ios job signs for
the simulator — the merged app-hosted host-gated LillistCore tests in
Lillist-iOSAppHostedTests), the folded-in LillistUI localization-lint
job (chain #6), and a Release-configuration smoke build. deployit
archives in Debug for iteration; CI is the only Release-config compile.

Closes build-1, build-2, build-3, build-4, test-5; closes the
'No CI/CD at all' blind spot; absorbs residual #11."
  ```
  Note: the `localization-lint` job invokes `Tools/CI/check-lillistui-localization.sh`, which is created by the `lillistui-localization-a11y` plan (also Wave 7). Land that plan before this one (the index sequences `lillistui-localization-a11y` immediately before `ci-and-build-posture` for exactly this reason); the standalone `.github/workflows/lillistui-localization.yml` it ships is removed in Task 6.

---

### Task 5: Document the CI design, the Debug/Release split, and the retired ritual

**Files:** Modify `docs/engineering-notes.md` (append a new dated entry as the *newest* `##` block — anchor relative to the latest existing entry / true EOF, NOT to any `2026-05-17` heading) and `CLAUDE.md` (the "Build-plugin caching gotcha" and "Build & test" sections).

This is the append-only engineering record (CLAUDE.md mandate) for the cross-cutting decisions made in Tasks 2 and 4 that a future contributor would otherwise rediscover the hard way: why CI is post-push, the deliberate Debug-for-deployit / Release-for-CI split, the retired mtime-touch ritual, the bounded-test-parallelism remedy for residual #11, and the dependency on *store-swap-safety*'s app-hosted test target. It also keeps the two affected CLAUDE.md sections truthful.

- [ ] **Step 1: Find the current newest entry** — the log is chronological, oldest-to-newest, so the newest `##` heading is near EOF (it has been a 2026-06-xx entry as of this writing). Read the tail to confirm what to append after:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -n "^## " docs/engineering-notes.md | tail -3 && tail -5 docs/engineering-notes.md
  ```
  Append the new entry as a fresh `##` block *after* the current last entry (re-anchor by reading — do not key off any hard-coded line number, which drifts every wave).

- [ ] **Step 2: Append the engineering-notes entry** — using the Edit tool, append the following block as a new `##` block after the current newest entry (so it becomes the newest entry at the bottom of the dated log; match the surrounding blank-line spacing):
  ```markdown
  ## 2026-06-05 — CI established + build-posture alignment (Plan: ci-and-build-posture)

  **Context.** Until now every quality gate (warnings-as-errors, the
  full test matrix, snapshots, the runtime-gated migration tests, pbxproj
  drift) was enforced only by what the dev remembered to run locally. The
  foundation review's completeness critic named "No CI/CD at all" as a
  blind spot, and the `test-1` finding showed the most safety-critical
  tests could silently skip when the host bundle lacked a real
  `CFBundleIdentifier` — the reason `store-swap-safety` introduced the
  app-hosted `Lillist-iOSAppHostedTests` target (and `recovery-hardening`
  closed `test-2` with the live `MigrationRecoveryTests`). This entry
  records the CI design and three build-posture fixes that landed with
  it, so those host-gated tests actually run on a schedule, not just from
  memory.

  **Rules.**

  - **CI runs post-push on `main`, not as a PR gate.** This is a solo
    project that commits directly to `main` (no PR review). The workflow
    (`.github/workflows/ci.yml`) is therefore a *verifier*: a push to
    `main` triggers it, a broken gate goes red + emails the actor, and
    `workflow_dispatch` allows on-demand runs. Do not restructure it into
    a required-status-check on PRs unless the project moves to a PR flow.
  - **deployit archives in Debug for iteration; CI is the only Release
    compile.** `Apps/Lillist-iOS/project.yml`'s scheme sets
    `archive.config: Debug` deliberately — Debug archives are faster to
    produce for the ~3-5 min OTA round-trip. The cost is that
    Release-only behaviour (whole-module optimization, dead-code
    stripping, `-O` codegen differences) is never exercised by a deploy.
    CI's `release-archive-smoke` job is the *only* place a
    Release-configuration compile runs, so it is the net for Release-only
    breakage. It is a `build` (not `archive`) to avoid tripping the
    build-number bump pre-action and signing — a compile-only smoke, not
    a shippable artifact.
  - **The mtime-touch ritual for Core Data model edits is retired.** The
    `CompileCoreDataModel` plugin now declares the inner
    `*.xcdatamodel/contents` and `.xccurrentversion` files as
    `inputFiles` (it FileManager-walks the `.xcdatamodeld` bundle), so
    llbuild invalidates the `momc` command on a real model edit. Editing
    `contents` no longer requires touching both the `.xcdatamodel` and
    `.xcdatamodeld` directories. momc still receives the `.xcdatamodeld`
    directory as its argument — it needs the whole versioned bundle, not
    one file; only the *invalidation* keying changed.
  - **The pbxproj-drift gate depends on xcodegen idempotence.** CI
    regenerates both projects (`Apps/Lillist-iOS` and `Apps`) and fails
    on `git diff --exit-code` of `*.xcodeproj/project.pbxproj`. The
    `$(LOCAL_DEVELOPMENT_TEAM)` xcconfig indirection (see CLAUDE.md "Code
    signing") is what keeps regen idempotent — never put
    `DEVELOPMENT_TEAM` into `project.yml`'s `settings: base:` or the
    drift gate will flap on every contributor's team ID.
  - **Snapshot precision is relaxed only for Form-bearing snapshots.**
    The tour suite's `assertScreen` defaults to exact-pixel (1.0); only
    `test_08_settings_light` (which renders `SettingsScreen`'s
    `NavigationStack + Form`) uses `precision: 0.99, perceptualPrecision:
    0.98`, consistent with the 2026-05-17 "Form views drift on
    cold-cache runs" entry. Keep new non-Form snapshots strict.
  - **`swift test` runs with bounded parallelism + a retry, by design.**
    The `spm` job passes `--num-workers 2` and retries the LillistCore
    run once. This is the deterministic runner-level mitigation for the
    intermittent parallel-test SIGSEGV (dozens of concurrent in-memory
    `NSPersistentContainer` loads racing Core Data's framework-internal
    per-entity state) and the `SyncQuiesceMonitorTests` timing flake,
    both documented in the 2026-06-04 entry (index residual #11). Neither
    is a product bug — production never builds more than one container —
    so the mitigation is in CI invocation, never in shipping code. The
    CLAUDE.md "Build & test" section mirrors the bounded invocation so
    local runs match. Do not "fix" this by serializing the parity suite:
    parity-alone is clean; the trigger is cross-suite peak concurrency.

  - **Host-gated migration/swap tests need a signed simulator host —
    `CODE_SIGNING_ALLOWED=NO` is NOT enough for the iOS test job.** The
    now-merged `store-swap-safety` plan added the
    `Lillist-iOSAppHostedTests` target to the `Lillist-iOS` scheme. It
    is `TEST_HOST=$(BUILT_PRODUCTS_DIR)/Lillist.app/Lillist` +
    `CODE_SIGN_STYLE: Automatic`, so it must install + launch the host
    `Lillist.app` on the simulator; the `liveSwapAllowed` gate
    (`Bundle.main.bundleIdentifier?.isEmpty == false`) is only true
    inside that host. The same is true of the `Lillist-iOSUITests`
    UI-test bundle (`dependencies: Lillist-iOS`). An unsigned `.app`
    cannot host tests on the simulator, so the `ios` job uses ad-hoc
    simulator signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-"`)
    rather than the no-signing recipe — that is the only way these
    tests actually run in CI. This mirrors the macOS lane's lesson in
    reverse: the macOS test target was made standalone (`TEST_HOST=""`)
    *because* `CODE_SIGNING_ALLOWED=NO` can't load a signed host; the
    iOS app-hosted target has no standalone fallback, so it needs
    signing instead. [If CI could not be made to sign for the
    simulator, the documented limitation is: `Lillist-iOSAppHostedTests`
    + `Lillist-iOSUITests` run only on a developer's signed Mac
    (`xcodebuild test -scheme Lillist-iOS` with a populated
    `Signing.local.xcconfig`), exactly as Wave 1 verified them. Delete
    this bracketed sentence if Option (a) signing is in place.]

  **Cross-plan dependency.** The merged `store-swap-safety` plan wired
  the `LillistCore` migration/store-swap tests into the
  `Lillist-iOSAppHostedTests` app-hosted unit-test target on the
  *existing* `Lillist-iOS` scheme (host-gated `liveSwapAllowed` tests,
  addressing review finding `test-1`). Because it added a *target*
  to a scheme CI already runs — not a new scheme — **no extra CI job is
  needed**; the `ios` job runs them as long as it signs for the
  simulator (see the rule above). If a future plan adds a new *scheme*,
  add a matching job here.

  **Evidence.** `.github/workflows/ci.yml` with six matrix jobs (spm,
  project-drift, ios, macos, release-archive-smoke, localization-lint) +
  a failure-notify job; the `spm` job's bounded `--num-workers 2` +
  retry; the folded-in `localization-lint` job (standalone
  `lillistui-localization.yml` deleted); `Packages/LillistUI/Package.swift`
  at swift-tools 6.2 with warnings-as-error; `CompileCoreDataModel.swift`
  declaring inner-model `inputFiles`; `IOSScreenTourTests.assertScreen`
  precision params. One commit per task on `main`.
  ```

- [ ] **Step 3: Update the CLAUDE.md mtime-ritual note** — read the section first, then mark the ritual retired. Read:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -n "Build-plugin caching gotcha\|CompileCoreDataModel plugin keys\|Touch both directories\|touch Packages/LillistCore" CLAUDE.md
  ```
  Then, using the Edit tool on `CLAUDE.md`, prepend a one-line status note immediately under the `## Build-plugin caching gotcha` heading so the now-historical ritual is clearly marked superseded. Insert this line directly after the heading and before the existing paragraph that begins "SwiftPM's `CompileCoreDataModel` plugin keys on…":
  ```markdown
  > **Retired by `ci-and-build-posture`.** The `CompileCoreDataModel`
  > plugin now declares the inner `*.xcdatamodel/contents` +
  > `.xccurrentversion` as `inputFiles`, so a model edit auto-invalidates
  > `momc`. The touch ritual below is no longer required for
  > `swift build`/`swift test`; it is kept here as historical context.
  > See the "CI established + build-posture alignment" entry in
  > `docs/engineering-notes.md`.
  ```

- [ ] **Step 4: Add a CI pointer + bounded-parallelism note to the CLAUDE.md "Build & test" section** — read the section first:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -n "## Build & test\|## House rules" CLAUDE.md
  ```
  Then, using the Edit tool, insert the following note at the end of the `## Build & test` section (immediately before the `## House rules` heading that follows it). It documents both the CI workflow and the bounded-parallelism `swift test` invocation that mirrors CI (residual #11):
  ```markdown
  **CI.** `.github/workflows/ci.yml` runs the full matrix post-push on
  `main` (and via `workflow_dispatch`): `swift test` for both packages, a
  pbxproj-drift gate (`xcodegen generate` + `git diff --exit-code`), the
  `Lillist-iOS` and `Lillist-macOS` xcodebuild test schemes, a
  Release-configuration smoke build, and the LillistUI localization-lint
  job (`Tools/CI/check-lillistui-localization.sh`). It is a post-push
  verifier, not a merge gate (solo project, direct-to-`main`). deployit
  still archives in Debug for iteration — CI is the only Release-config
  compile.

  **Parallel-test flakes (`LillistCore`).** Heavy concurrent in-memory
  store creation intermittently SIGSEGVs inside Core Data, and the same
  CPU contention starves `SyncQuiesceMonitorTests`' timing window (see
  `docs/engineering-notes.md` 2026-06-04). Neither is a product bug.
  Run the suite with bounded parallelism + a one-shot retry to match CI:
  `swift test --package-path Packages/LillistCore --num-workers 2`
  (re-run once on a one-off SIGSEGV / timing flake before treating it as
  a real failure). If `--num-workers` is unavailable on your toolchain,
  use `--no-parallel` for `LillistCore`.
  ```

- [ ] **Step 5: Verify the docs render and reference real paths** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    grep -c "CI established + build-posture alignment" docs/engineering-notes.md && \
    grep -c "Retired by .ci-and-build-posture." CLAUDE.md && \
    grep -c "post-push on" CLAUDE.md && \
    grep -c "num-workers" CLAUDE.md
  ```
  Expect each `grep -c` to print `1` (the entries landed exactly once).

- [ ] **Step 6: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add docs/engineering-notes.md CLAUDE.md && git commit -m "docs: record CI design, Debug/Release split, retired mtime ritual

Add the engineering-notes entry covering: CI is a post-push verifier on
main (not a PR gate); deployit archives in Debug for iteration while
CI's smoke job is the only Release-config compile; the
CompileCoreDataModel mtime-touch ritual is retired by the inputFiles
fix; the pbxproj-drift gate depends on xcodegen idempotence; bounded
swift-test parallelism + retry as the residual-#11 SIGSEGV/timing-flake
remedy; and the cross-plan dependency on store-swap-safety's app-hosted
host-gated tests. Mark the CLAUDE.md mtime ritual retired and add a CI
pointer + bounded-parallelism note to Build & test."
  ```

---

### Task 6: Fold the LillistUI localization-lint into ci.yml and delete the standalone workflow

**Files:** Delete `.github/workflows/lillistui-localization.yml`.

This closes **chain #6**. The `lillistui-localization-a11y` plan (also Wave 7, sequenced *before* this one in the index) creates the durable lint script `Tools/CI/check-lillistui-localization.sh` and ships a standalone `.github/workflows/lillistui-localization.yml`. Because `.github/workflows/` is owned by *this* plan, Task 4 already folds the lint in as the `localization-lint` job in `ci.yml`; this task removes the now-redundant standalone file so the repo holds exactly one workflow. (If `lillistui-localization-a11y` has not yet merged when this plan runs, land it first — the index orders it immediately before `ci-and-build-posture` precisely so the lint script and standalone workflow already exist.)

- [ ] **Step 1: Confirm both the standalone workflow and the lint script exist** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    ls .github/workflows/lillistui-localization.yml && \
    ls Tools/CI/check-lillistui-localization.sh
  ```
  Expect both to exist. If `.github/workflows/lillistui-localization.yml` is absent, `lillistui-localization-a11y` already added its lint as a `ci.yml` job (it follows the same cross-plan rule) — there is nothing to delete; skip to Step 4 after confirming `ci.yml` has the `localization-lint` job. If the lint *script* is absent, `lillistui-localization-a11y` has not merged — stop and land it first.

- [ ] **Step 2: Confirm `ci.yml` already carries the folded-in job** — the `localization-lint` job (added in Task 4) must invoke the script before the standalone file is removed, so the lint never stops running:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    grep -n "localization-lint\|check-lillistui-localization.sh" .github/workflows/ci.yml
  ```
  Expect the `localization-lint:` job name and the `./Tools/CI/check-lillistui-localization.sh` invocation. If either is missing, fix Task 4's `ci.yml` first — do not delete the standalone workflow while CI lacks the job.

- [ ] **Step 3: Delete the standalone workflow** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git rm .github/workflows/lillistui-localization.yml
  ```

- [ ] **Step 4: Verify `.github/workflows/` holds exactly one workflow** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && ls .github/workflows/
  ```
  Expect only `ci.yml`.

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git commit -m "ci: fold LillistUI localization lint into ci.yml; drop standalone workflow

lillistui-localization-a11y shipped a standalone
.github/workflows/lillistui-localization.yml. .github/workflows/ is
owned by ci-and-build-posture, so the lint now runs as the
localization-lint job in ci.yml (invoking the durable
Tools/CI/check-lillistui-localization.sh) and the standalone file is
removed — one workflow in the repo. Closes chain #6."
  ```

---

## Self-review checklist

- [ ] **build-1** (no CI / no `.github/workflows`) — closed by **Task 4** (creates `.github/workflows/ci.yml` triggered post-push on `main`).
- [ ] **build-2** (no pbxproj-drift gate) — closed by **Task 4** (`project-drift` job: `xcodegen generate` for both projects + `git diff --exit-code -- '*.xcodeproj/project.pbxproj'`).
- [ ] **build-3** (inconsistent warnings posture across packages) — closed by **Task 1** (LillistUI `.treatAllWarnings(as: .error)` on source + test, matching LillistCore) and enforced in CI by **Task 4** (`spm` job runs both `swift test`s under the strict manifests).
- [ ] **build-4** (Release/Debug posture not exercised; warnings not enforced in CI) — closed by **Task 4** (`release-archive-smoke` job is the only Release-config compile) + **Task 1** (warnings-as-error) + **Task 5** (documents the deliberate deployit-Debug / CI-Release split).
- [ ] **build-5** (`CompileCoreDataModel` keys on the `.xcdatamodeld` dir mtime, not the inner `contents`) — closed by **Task 2** (declares inner `*.xcdatamodel/contents` + `.xccurrentversion` as `inputFiles`; Step 3 proves `momc` re-runs on a `contents`-only mtime change).
- [ ] **ui-warn-1** (standing "found 83 file(s) unhandled" LillistUI manifest warning) — closed by **Task 1** (excludes the six test `__Snapshots__` dirs; Step 3 asserts the unhandled-file count drops to 0).
- [ ] **ui-snap-1** (brittle exact-pixel LillistUI snapshots) — closed by **Task 3** (scopes the `precision: 0.99, perceptualPrecision: 0.98` relaxation to the single Form-bearing tour snapshot `test_08_settings_light`; all other tour snapshots stay exact-pixel).
- [ ] **test-5** (the test/build matrix is run only from memory, never automatically) — closed by **Task 4** (CI executes `swift test` ×2, both xcodebuild schemes, the drift gate, and the Release smoke on every push to `main`; the `ios` job transitively runs the iOS snapshot/tour bundle). The app-hosted host-gated `Lillist-iOSAppHostedTests` and the `Lillist-iOSUITests` run in CI **only if** the `ios` job signs for the simulator (Option (a)); if CI cannot sign (Option (b)), those two run on a developer's signed Mac, which Task 5 must state as an explicit limitation — they are not silently dropped, they are scoped out and documented.
- [ ] **residual #11** (intermittent parallel-test SIGSEGV + `SyncQuiesceMonitorTests` timing flake — see `docs/engineering-notes.md` 2026-06-04) — closed by **Task 4** (`spm` job runs `swift test --num-workers 2` + a one-shot retry) and **Task 5** (records the rationale in engineering-notes and mirrors the bounded invocation into CLAUDE.md "Build & test"). Runner-level mitigation only — no source change, because production never builds more than one container.
- [ ] **chain #6** (one workflow in `.github/workflows/`) — closed by **Task 4** (folds the `localization-lint` job into `ci.yml`, invoking `lillistui-localization-a11y`'s `Tools/CI/check-lillistui-localization.sh`) and **Task 6** (deletes the standalone `lillistui-localization.yml`). The lint runs in `ci.yml` before the standalone file is removed, so the gate never lapses.

**Strengths preserved (not refactored away):** the idempotent signing xcconfig indirection (Task 4 only *reads* the `.example` placeholder; the `build`-action jobs use `CODE_SIGNING_ALLOWED=NO`, while the `ios` test job uses ad-hoc simulator signing under Option (a) so the host-gated tests can run); the canonical iPhone 17 / iOS 26.2 simulator pin and the iPhone 16 Pro logical render size (Task 4 uses the documented destination verbatim); the monotonic tracked build-number counter (Task 4's Release smoke is a `build`, not an `archive`, so it never triggers the bump pre-action); LillistCore's existing strict-concurrency + warnings-as-error posture (Task 1 mirrors it onto LillistUI rather than altering LillistCore); the snapshot suite's overall strictness (Task 3 widens tolerance for exactly one Form-bearing snapshot, leaving every other baseline strict).
