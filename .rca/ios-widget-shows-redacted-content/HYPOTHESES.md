# HYPOTHESES — ios-widget-shows-redacted-content

Four competing `defect → infection → failure` chains, ranked. None is verified. Falsification
designs follow each; the discriminating experiments are **blocked on a mutation decision** (see the
end of this file).

Shared failure tail for all four — the part already proven by EVIDENCE.md:

> extension not in PlugInKit registry → WidgetKit never launches it → `timeline(for:in:)` never runs
> → the placeholder entry stays on screen under placeholder redaction, and `WidgetUnavailableView`
> is never reached → *(config UI)* the widget's own `SelectFilterIntent` is unavailable, so AppIntents
> resolves against the app's other surface, whose unset `AddTaskIntent.tags: [String]?` renders as
> **"No Tags"**.

The hypotheses differ only in what produces the **first** link.

---

## H1 — Host OS refuses an extension built against a future SDK

**Defect.** The shipped appex carries `execSDK 27.0` while the host runs macOS 26.5.2. PlugInKit
declines to register a plug-in whose build SDK exceeds the running OS, even though LaunchServices
records the bundle normally.

**Infection.** `deployit` resolves the newest Xcode satisfying `min_sdk = "27"` → archive is built
with the Xcode 27 beta → `LC_BUILD_VERSION sdk = 27.0` → registration silently declines.

**For.** All 33 bundles at SDK ≤ 26.4 register (33/33); the one SDK-27 bundle is the one failing.
LS record is `link-enabled` and well-formed, so the disagreement is at the PlugInKit layer, not LS.
`minos` is correctly 26.0, so this is about *build* SDK, not deployment target. Explains both
platforms at once: the iOS artifacts are also SDK 27 on a 26.x phone — the only mechanism found so
far that is common to iOS and macOS, which GRID.md distinction 4 demands.

**Against.** n=1 at bundle level. Timery (`com.joehribar.toggl.widgets`, SDK 26.5) is installed and
also unregistered, proving SDK-27 is not *necessary* for this symptom. Apple ships no documented
rule of this shape that we have confirmed. And SDK-27 builds date from ~v0.15.0/v0.16.0 (07-19/20),
which predates `LIL-4` closing done on 07-21 — if H1 were the whole story, LIL-4 should have failed.

**Falsification (toggle gold standard).** Build the macOS app against the **26.x** SDK, install to a
scratch location, observe registration. Predict: registers under SDK 26, does not under SDK 27, with
nothing else changed. **BLOCKED** — the source cannot compile under Xcode 26.6 (`WatermarkRegistry
.swift:56`, non-`Sendable NSPersistentHistoryToken`), so the SDK cannot be varied without also
varying code; and installing a second copy mutates the registry. Requires the worktree + a mutation
decision.

**Cheaper probe (non-mutating, do first).** Find any *other* SDK-27-built extension on this Mac from
any vendor and check its registration. If one exists and registers, H1 is refuted outright at zero
cost. Prior scan says there is none — confirm that is a true absence, not a scan artifact.

---

## H2 — Duplicate/stale bundle-ID records shadow the live one

**Defect.** 22 records exist for `app.lillist.Widget` (19 DerivedData Debug, 1 archive staging, 1
`/private/tmp`, 1 `/Applications`). PlugInKit resolves one registration per bundle ID; a
non-existent or disabled DerivedData record wins, so the live `/Applications` copy never surfaces.

**Infection.** Every local Debug build registered its appex → the registry accumulated duplicates →
the winner points at a path that no longer exists or is not launchable → the extension appears absent.

**For.** 22 records for one bundle ID is a lot of collision surface. iOS and macOS deliberately share
the base bundle ID `app.lillist` (per CLAUDE.md), and LS holds iOS, simulator, *and* native records
under it. Would explain LS-vs-PlugInKit disagreement precisely: LS keeps all records, PlugInKit
exposes one.

**Against.** Does not obviously explain the iPhone, which has no DerivedData builds on it. Would
predict the symptom appears the first time a Debug build is made, not at a version boundary.

**Falsification.** Enumerate PlugInKit's *own* view per bundle ID (`pluginkit -m -v -i
app.lillist.Widget`, `-A -D` variants) and check for a disabled/duplicate entry pointing elsewhere.
Largely **non-mutating** — run this before anything destructive. A definitive fix-test (clear
duplicates, re-register) *is* mutating and would destroy evidence.

---

## H3 — Developer-ID/notarized distribution differs from the Debug path

**Defect.** Something specific to the notarized Developer-ID channel — sandbox entitlements,
provisioning, the `Installer.xpc`/`Downloader.xpc` embedding, or the DMG/zip install route — prevents
extension registration in a way local Debug builds never hit.

**Infection.** Channel-specific packaging → registration declines → same tail.

**For.** The failing copy is the notarized one; the 19 registered-in-the-past records are Debug builds.
`spctl -a` accepting is not proof PlugInKit will register.

**Against.** All 19 DerivedData Debug records are *also* currently unregistered, which weakens
"Debug works, Developer-ID doesn't" considerably. And it says nothing about iOS, which uses Ad-Hoc.

**Falsification.** Compare entitlements + `NSExtension` dictionaries between a Debug appex and the
installed one. **Non-mutating; cheap; do early.**

---

## H4 — Two unrelated failures wearing one costume

**Defect.** The macOS widget and the iOS widget fail for different reasons; the shared symptom
("no real content") misleads. E.g. macOS = registration, iOS = something else entirely.

**Infection.** n/a — this is the null hypothesis against a single unified cause.

**For.** Every fact gathered is macOS; the iOS side is entirely unverified. The macOS host runs
**v0.18.0**, not the v0.19.0 the report is framed around. macOS renders an *empty grey rect* while
iOS renders a *redacted card with correct chrome* — arguably different failure surfaces, not one.

**Against.** Parsimony, and the "No Tags" label is explained by the same registration mechanism on
both.

**Falsification.** Get iOS-side evidence: Console/`sysdiagnose` on the iPhone while the widget
reloads, looking for extension-launch or registration errors. **Requires hands-on device work.**

---

---

## H7 — Platform bug: `AppIntentTimelineProvider` calls `placeholder` but never `timeline` *(added 2026-07-31, now RANK 1)*

**Defect.** A documented, still-open WidgetKit bug: widgets built on `AppIntentTimelineProvider` /
`IntentConfiguration` have `placeholder(in:)` invoked repeatedly while `timeline(for:in:)` is
**never called at all**, leaving the widget stuck on the placeholder view. Reported console
signature: **`ApplicationExtension record not found`**. Developers report it persisting **through the
iOS 26 and watchOS 26 betas**; feedback IDs **FB13880020** and **FB18180368**. The known workaround is
reverting to `TimelineProvider` + `StaticConfiguration`, which forfeits widget configurability.

**Lillist matches the affected shape exactly:** `FilterTimelineProvider: AppIntentTimelineProvider`
with `SelectFilterIntent: WidgetConfigurationIntent`.

**Explains every observation, with no unexplained residue:**
- Gallery shows the **redacted placeholder** — `placeholder(in:)` is being called; that is the
  gallery's normal rendering.
- Freshly-added home-screen widget shows a **bare dark rectangle** — no timeline ever arrives, so
  only `containerBackground` draws.
- **No crash or jetsam logs** — nothing crashes; the timeline call simply never happens.
- **Extension registers and launches** — the gallery preview proves it, and this hypothesis requires it.
- **Config picker spins then dismisses** — same AppIntents/extension-record machinery.
- **Adding a task changes nothing** — `WidgetRefreshController` regenerates the cache and calls
  `reloadAllTimelines()`, but a reload is useless if `timeline(for:in:)` is never invoked.
- Requires **no** SDK-27 mechanism, **no** registration failure, **no** memory story.

**Against / unresolved.** Sourced from developer-forum reports, not Apple documentation — the precise
trigger conditions are unknown, and it does not explain why Lillist worked earlier (unless the
reporter's "it worked" memory is unreliable, which `exp-2` already established for macOS). It also
does not by itself explain the all-empty snapshot cache (see below) — that may be an independent
second defect.

**Discriminator (free, visual).** Does the dark rectangle carry the **rainbow border**?
- **Rainbow border present, no rows** → a timeline WAS delivered carrying an empty snapshot →
  empty-cache defect, H7 not implicated.
- **Plain rectangle, no border** → no timeline was ever delivered → **H7**.

**Confirming signature.** Console.app attached to the device during a widget reload, searching for
`ApplicationExtension record not found`.

Sources: `developer.apple.com/forums/tags/widgetkit`, `developer.apple.com/forums/thread/814463`
("Widget & Snapshot Blank on iOS 26" — same shape: `AppIntentTimelineProvider`, blank even though
fallback sample data exists, tens of reports, **no root cause found**, Apple DTS awaiting a sample
project), `github.com/feedback-assistant/reports/issues/359`.

---

## H6 — The snapshot cache is written empty, and the write path swallows errors

**Defect (confirmed in code).** `WidgetSnapshotBuilder.performRegenerate` uses two different error
postures. Saved filters fail **safe** — `guard let matches = try? await smartFilterStore
.evaluate(id:) else { continue }` skips the write. The unfiltered sentinel fails **unsafe**:

```swift
let openMatches = (try? await smartFilterStore.evaluate(group: Self.unfilteredOpenGroup, …)) ?? []
writeSnapshot(filterID: WidgetSnapshot.unfilteredID, filterName: "", …, matches: openMatches, …)
```

A thrown error becomes `[]` and is **persisted as an authoritative empty snapshot**, indistinguishable
from "no open tasks". Same for `closedToday`. This is the X5 empty-vs-failed conflation surviving in
the *writing* path — X5 (`a0963538`) only fixed *pruning*. It also violates CLAUDE.md's tenet:
"Errors fail loud and travel with context — never swallow or blanket-catch."

**Evidence.** Local macOS App Group cache: all six snapshots (five named filters + the sentinel) have
`totalCount: 0, openCount: 0, tasks: []`, all stamped `2026-07-23T09:00:53Z`. `index.json` lists all
five filters with correct names, so `smartFilterStore.list()` succeeded — the builder saw the filters
and then wrote zeros for every one, including "all open tasks".

**Age.** The `?? []` predates the hardening batch — present since `96ee2360` (2026-07-02).
**Longstanding, not introduced by X5/X6.**

**Testability gap that likely explains its survival.** `WidgetSnapshotBuilder.init` takes a
**concrete** `SmartFilterStore`, not a protocol. There is no seam to inject a throwing double, so the
fail-unsafe branch is **unreachable from a unit test** without a production change (DIP violation).

**Scope caveat.** The observed cache is **macOS**, which has its own store-location history
(X1/`c7538745`, `621e6ded`) that could independently explain an empty read there. The iOS container
has never been observed. Real defect either way; its role in the iOS symptom is unproven.

---

## H5 — The macOS widget extension is not sandboxed, and never has been *(macOS only)*

**Defect.** macOS app extensions must be sandboxed — emphatically so when the host app is
sandboxed. The installed appex's signed entitlements contain **no `com.apple.security.app-sandbox`**,
while the containing app has `com.apple.security.app-sandbox => true`.

**Infection.** `Apps/project.yml` points the macOS widget at
`CODE_SIGN_ENTITLEMENTS: ../Extensions/LillistWidget/Lillist.entitlements` — the **same file the iOS
widget uses**. That file declares only iCloud/ubiquity/app-group keys plus `aps-environment` (the
*iOS* spelling; macOS requires the `com.apple.developer.`-prefixed form). It has no sandbox key, so
the macOS appex ships unsandboxed → the system declines to register it → shared failure tail.

**For — this is the strongest evidence in the investigation:**
- Signed installed appex entitlement keys: `com.apple.application-identifier`,
  `…icloud-container-environment`, `…icloud-container-identifiers`, `…icloud-services`,
  `…team-identifier`, `…ubiquity-*`, `com.apple.security.application-groups`. **No `app-sandbox`.**
- Host app has it. An unsandboxed extension inside a sandboxed app is not a valid configuration.
- `git log -S "com.apple.security.app-sandbox" -- Extensions/LillistWidget/Lillist.entitlements`
  across **all refs** returns **nothing**: the key has never existed in that file since the widget
  landed (`ae004da5`, 2026-07-01).
- This repo has the **exact same bug class on record**: CLAUDE.md's "macOS push entitlement — FIXED
  (2026-06-24)" documents the main macOS app declaring iOS's `aps-environment` instead of
  `com.apple.developer.aps-environment` and having it silently stripped. The shared widget
  entitlements file still declares the bare iOS `aps-environment` today — the same cross-platform
  entitlement-sharing mistake, unfixed in this file.

**Against.** Does **not** explain iOS at all — iOS extensions do not require `app-sandbox`. And it
predicts the macOS widget **never worked**, which must be reconciled against the reporter's "it
worked previously."

**Falsification.** Non-mutating first: confirm from Apple's documentation that macOS app extensions
require sandboxing, and check whether any *other* installed macOS appex on this Mac lacks
`app-sandbox` yet registers (that would refute). Mutating toggle: add the key in a worktree,
rebuild, install to scratch, observe registration.

**Consequence if true.** The macOS reproduction test is reproducing a **longstanding macOS-only
defect** — not the iOS regression that was reported. The gate would be latched to the wrong bug.

---

## Ranking (revised after the entitlement probe)

1. **H5** — direct, documented-in-this-repo bug class, confirmed by signed-artifact inspection and
   an all-refs pickaxe. Explains macOS completely. Explains iOS not at all.
2. **H4** — now strongly supported: H5 accounts for macOS, so iOS very likely has a *separate*
   cause. The two platforms failing is looking like coincidence of symptom, not of mechanism.
3. **H1** — still the only single mechanism that could span both platforms; n=1, and now less
   necessary for macOS since H5 covers it. Retained for the iOS side.
4. **H2** — **effectively refuted.** `pluginkit -m -v -i app.lillist.Widget` and `-mAvD` both return
   "(no matches)": PlugInKit holds *no* record, not a stale or shadowed one. There is no duplicate to
   win the race.
5. **H3** — weakened; the Debug-vs-Developer-ID distinction is subsumed by H5, which is a property of
   the entitlements file rather than the channel.

## AND-condition check

H1 alone does not explain Timery. H2 alone does not explain iOS. If the true cause is a conjunction
— e.g. *SDK-27 build* **AND** *duplicate registration* — then no single-variable experiment flips the
repro, and each will read as "refuted" in isolation. Watch for that signature: two experiments that
each fail to reproduce the flip while the symptom persists.

## Blocked on a decision

Every **discriminating** experiment for H1 and H2 mutates the LaunchServices/PlugInKit registry
(installing a second build, re-registering, or clearing duplicates). That is precisely the state this
investigation has been preserving. The non-mutating probes listed under H1 (other SDK-27 vendors),
H2 (PlugInKit's per-bundle view), and H3 (entitlement diff) should run first and may refute cheaply.

Beyond those, proceeding requires the user's decision to spend the evidence.
