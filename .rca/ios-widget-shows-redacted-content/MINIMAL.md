# MINIMAL — ios-widget-shows-redacted-content

FULL-tier minimization. Goal: the smallest system state that still reproduces. Every observation
below is **read-only**; nothing on the system was mutated (no `pluginkit -a`, no `lsregister -f`, no
reinstall, no delete) because doing so would repair the registry and destroy the evidence.

> **Revision note.** An earlier draft of this file was written by the orchestrator while the
> qa-engineer's minimization run was still in flight. Two of its findings were wrong and are
> corrected below with reproducible evidence (§1 and §3). Its §2 (artifact eliminations) and §5
> (installed version is 0.18.0, not 0.19.0) were correct and are retained.

## The repro, minimized

The reproduction reduces to a single read-only system query:

```bash
pluginkit -m -A -D -i app.lillist.Widget   # → empty; expected: one registration line
```

Everything else in the test file is a safety rail (skip-not-fail preconditions), not a repro input.

**Toolchain is load-bearing for the automated form.** `swift test` must run under
`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. Under the `xcode-select` default
(Xcode 26.6) `LillistCore` fails to compile — `WatermarkRegistry.swift:56`, non-`Sendable`
`NSPersistentHistoryToken` — and the run exits **1 with zero tests executed**. Exit code alone
therefore cannot distinguish a genuine RED from a build failure. Verify a genuine RED by grepping
the output for both `Executed 1 test, with 1 failure` and `is NOT registered with the system`.
Confirmed: 10/10 genuine RED under Xcode 27; 0 tests executed under 26.6.

## What was stripped, and what it revealed

### 1. CORRECTION — the failure is *not* wider than the widget

The earlier draft read `pluginkit -m -A -D | grep -i lillist → EMPTY` as evidence that "no Lillist
extension of any kind is registered," widening the failure beyond the widget. That inference does
not hold: **the macOS app ships exactly one extension.**

```
/Applications/Lillist.app/Contents/PlugIns/          → LillistWidget-macOS.appex   (only entry)
deployit v0.19.0 macOS artifact, Contents/PlugIns/   → LillistWidget-macOS.appex   (only entry)
Apps/project.yml, targets of type app-extension      → LillistWidget-macOS         (only one)
```

`ShareExtension-iOS` and `ShortcutsActions` are **iOS-only targets**; they have no macOS product and
cannot appear in this Mac's registry. The empty grep is therefore the *same single fact* as the
widget being unregistered, restated — not a second, broader symptom. Scope is unchanged: **one
extension, one platform, observed here.**

### 2. The artifact is NOT malformed — candidate explanations eliminated (retained, extended)

| Candidate | Observation | Verdict |
|---|---|---|
| Missing/incorrect extension point | Installed appex `Info.plist` → `NSExtension.NSExtensionPointIdentifier = "com.apple.widgetkit-extension"`; repo source declares the identical value | **ELIMINATED** |
| Appex missing from the bundle | Present; `codesign -v --deep --strict` passes; `spctl -a` → `accepted / Notarized Developer ID` | **ELIMINATED** |
| Gatekeeper quarantine | `xattr -l` → `com.apple.macl`, `com.apple.provenance`, Spotlight metadata. **No `com.apple.quarantine`** | **ELIMINATED** |
| App/appex version skew | app `0.18.0`/`52`, appex `0.18.0`/`52` — aligned on macOS; iOS `0.19.0`/`92` likewise aligned | **ELIMINATED** |
| Wrong `minos` from the Xcode 27 pin | Mach-O `LC_BUILD_VERSION minos = 26.0` on **every** archived build back to b83 | **ELIMINATED** |
| Stale/duplicate bundle-ID registration winning the race | 97 distinct widget bundle IDs in LS; `app.lillist.Widget` has 22 records, but the `/Applications` one is present and well-formed (§3) | **NOT ELIMINATED — see §4** |

Independently corroborated on the **iOS** artifact by direct inspection of the shipped
`Lillist.ipa` (build 92, `bb68168d`) against the nearest known-good (build 88): the widget's
`Metadata.appintents/extract.actionsdata` is **semantically identical** between them — the only diff
is array ordering inside `AdvanceTaskStatusFromWidget.taskID.resolvableInputTypes` plus the
generator version string. `SelectFilterIntent` correctly declares one parameter titled **"Filter"**,
entity `SmartFilterEntity`, `systemProtocols: ["com.apple.link.systemProtocol.WidgetConfiguration"]`.
**No `"Tags"`-titled parameter exists in the widget's metadata.** Entitlements, `Info.plist`, and
Swift type metadata are likewise correct and unchanged.

### 3. CORRECTION — LaunchServices *does* hold a record for the installed appex

The earlier draft stated "No record anywhere points at the installed
`/Applications/…/PlugIns/LillistWidget-macOS.appex`" and concluded LS only knows DerivedData copies.
**That is false.** A fresh dump:

```bash
lsregister -dump | grep -n "/Applications/Lillist.app/Contents/PlugIns/LillistWidget-macOS.appex"
404818:path:  /Applications/Lillist.app/Contents/PlugIns/LillistWidget-macOS.appex (0xf5b4)
404864:       Path = "/Applications/Lillist.app/Contents/PlugIns/LillistWidget-macOS.appex";
```

The record is complete and well-formed:

```
plugin id:      Lillist (0x42dc)
path:           /Applications/Lillist.app/Contents/PlugIns/LillistWidget-macOS.appex (0xf5b4)
identifier:     app.lillist.Widget
teamID:         VMY8R4T742
base flags:     link-enabled
platform:       native      slices: x86_64 arm64
execSDK ver:    27.0
CFBundleVersion = 52 ; CFBundleShortVersionString = "0.18.0"
NSExtensionPointIdentifier = "com.apple.widgetkit-extension"
```

Distribution of all 22 `LillistWidget-macOS.appex` path records: 19 DerivedData `Debug`, 1
DerivedData archive staging, 1 `/private/tmp/lillist-build-check`, **1 `/Applications`**.

**This inverts the shape of the problem.** The minimal surprising fact is not "the system has never
seen the appex." It is:

> **LaunchServices has a complete, correct, `link-enabled` record for the installed widget
> extension, and PlugInKit does not list it.** The two databases disagree.

That is a much sharper starting point for diagnosis than "it was never registered."

### 4. The one discriminator that survives: `execSDK 27.0` on a macOS 26.5.2 host

Host: **macOS 26.5.2 (25F84)**. Correlating every widgetkit-extension record in LS against
`pluginkit`'s live registry, **per distinct bundle ID** (97 total):

| max execSDK | bundle IDs | registered | unregistered |
|---|---|---|---|
| 12.1 | 1 | 1 | 0 |
| 15.5 | 2 | 2 | 0 |
| 26.0 | 23 | 23 | 0 |
| 26.2 | 1 | 1 | 0 |
| 26.4 | 6 | 6 | 0 |
| 26.5 | 63 | 45 | 18 |
| **27.0** | **1** | **0** | **1** ← `app.lillist.Widget` |

Everything built against an SDK **≤ 26.4 registers 100%** (33/33). The single SDK-27 bundle on this
Mac is the one that fails.

**Honest strength of this evidence.** It is n=1 at the bundle-ID level — the 8 SDK-27 *records* are
8 copies of the same bundle, so they are not independent samples. And of the 18 unregistered 26.5
bundle IDs, 17 are stale paths whose bundle no longer exists, but one — `com.joehribar.toggl.widgets`
(Timery) — **is installed and alive and also unregistered**. So "installed but unregistered" is not
unique to SDK 27. This is a strong lead, **not** a proven cause; falsification belongs to diagnose.

The SDK history of this bundle in LS tracks the reported timeline:

| execSDK | Lillist versions recorded |
|---|---|
| 26.2 | 0.13.0 – 0.14.1 (the era the widget demonstrably worked; shipped 2026-07-01) |
| 26.5 | 0.15.0 |
| **27.0** | 0.15.0, 0.16.0, 0.17.0, **0.18.0 (INSTALLED)**, 0.18.1, 0.19.0 |

This aligns with the `.deployit/config.toml` `[toolchain] min_sdk = "27"` pin inside the boundary
window, and — because the **iOS** artifacts are likewise `sdk=27.0` on `minos=26.0` while the phone
runs iOS 26.x — it is the first mechanism found that is **common to both platforms**, which
distinction 4 of the grid demands.

### 5. The installed macOS app is older than the report assumes (retained)

| Source | Version | Build |
|---|---|---|
| `/Applications/Lillist.app` (under test) | **0.18.0** | **52** |
| deployit staging, 2026-07-29 20:47 | v0.19.0 | 56 |
| Repo HEAD | 0.19.0 | 57 |

The v0.19.0 macOS build was published but **never installed**. Note the earlier draft's claim that
LS holds a *stale* native record at build 49 conflates records: build 49 is a DerivedData build
product; the record for the installed app reads build **52**, matching what is on disk.

### 6. Self-contamination check

My own unzipped copies of the shipped artifacts live under this session's scratchpad
(`…/f692919e-…/scratchpad/…`). `grep -c f692919e … lsdump.txt → 0` — none was ever registered, so
the investigation did not pollute its own evidence. (Two *other* sessions' scratchpad copies do
appear, from earlier work.)

## Smallest honest precondition set for the test

| Precondition | Keep? | Why |
|---|---|---|
| `#if os(macOS)` | **keep** | `pluginkit` is macOS-only |
| `/Applications/Lillist.app` exists | **keep** | nothing to observe otherwise |
| `…/PlugIns/LillistWidget-macOS.appex` exists | **keep** | its absence is a *packaging* defect — a different bug, must not be read as this one |
| `pluginkit` returns ≥ 5 widget extensions | **keep** | the only guard against a tooling failure masquerading as the defect (actual: 78) |
| signature/notarization check | **drop** | already verified once (§2); re-checking per-run adds a failure mode without adding signal |
| version/build assertions | **drop** | ambient; would make the test fail on upgrade rather than on the defect |
| "did the test actually execute" | **cannot self-guard** | must live in the runner recipe — grep for the assertion text, not the exit code |

Net: the three preconditions already in the file are exactly the necessary set; no additions, one
optional removal considered and rejected as already-absent.

## Open, and deliberately not resolved here

1. **Does a locally-built Debug macOS app register its extensions on this Mac?** Blocked twice over,
   and I did not attempt it: (a) the current source **cannot** be built against SDK 26.x at all
   (`LillistCore` fails to compile under Xcode 26.6), so the SDK variable cannot be toggled without
   changing code; and (b) building and letting LaunchServices pick the product up would mutate the
   registry — the exact evidence-destroying action the brief prohibits. **Escalated rather than
   performed.** Note the 19 existing DerivedData Debug records are *all* execSDK 27.0 and *all*
   unregistered, so they do not discriminate.
2. Is the iOS failure the *same* failure? Every fact here is macOS. The report and screenshot are
   iOS. Two platforms failing need not share a cause — though §4 now supplies a candidate that would.
3. Would installing v0.19.0 change the outcome? (Mutating — do not run before diagnose has taken
   its evidence.)
4. Why is Timery's widget also unregistered at SDK 26.5? Either a second instance of the same
   mechanism, or a coincidence that bounds how much §4 can carry.
