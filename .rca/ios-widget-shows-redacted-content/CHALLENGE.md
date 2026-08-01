# CHALLENGE — H1 (iOS: beta-SDK widget extension fails to load/register)

Adversarial review by `agents:hypothesis-challenger`, read-only (verified: no repo or `.rca/`
modifications). It re-derived the artifact facts independently and unpacked b86/b87/b92 itself.

**Verdict: INSUFFICIENT, leaning REFUTED on the stated mechanism.** → `INCONCLUSIVE.md`.

## Per-link

| Link | Verdict |
|---|---|
| **L1** widget appex is SDK 27 while the phone runs iOS 26.x | **SURVIVES** — independently re-verified |
| **L2** …and that prevents the extension loading/registering | **BROKEN AS STATED** |
| **L3** so `timeline(for:in:)` never runs → frozen redacted placeholder | **WOUNDED** — conclusion sound, reasoning conceals rivals |
| **L4** "No Tags" proves fallback to another AppIntents surface | **WOUNDED, near broken** |
| **L5** the boundary is b87 | **BROKEN** — the most serious defect in the case |

## Why L2 breaks — no mechanism exists

- Loaders gate on `LC_BUILD_VERSION.minos` + platform; installd/LaunchServices gate on `Info.plist`
  `MinimumOSVersion`. **Both are 26.0 on the app and the appex in every build.** The `sdk` field is
  not a load gate — it drives linked-on-or-after behavior checks (`dyld_program_sdk_at_least`).
  App Store review rejects beta-SDK *submissions*: a submission policy, not a runtime rule.
- **Precedent supports the trigger and contradicts the mechanism.** Real cases exist of beta-Xcode
  widget extensions breaking on older iOS while the host app is fine (Xcode 14 beta 3/4; Xcode 16
  beta gallery threads). In every one the mechanism is **a crash at extension launch** or the
  `ENABLE_DEBUG_DYLIB` packaging change — never a registration refusal.
- **Debug-dylib variant ruled out here:** no `*.debug.dylib` in the shipped appex in b86/b87/b92 and
  no debug-dylib references in `otool -L`. (Worth stating because deployit archives Debug.)
- The one defensible app-vs-extension asymmetry — an appex is its own "program" for linked-on-or-after
  purposes, so it can get different framework behavior than its host — produces *behavior* differences
  inside WidgetKit/AppIntents/SwiftUI, **not** a refusal to load. That is a different hypothesis with
  a different fix.
- Provisioning/entitlements eliminated: `embedded.mobileprovision` is content-equivalent across
  b86/b87/b92; b92's signed appex carries `com.apple.security.application-groups =
  ["group.app.lillist"]`, so `FileManager.containerURL(...)` won't return nil and
  `GatedPersistenceResolver.init?` won't fail. **This eliminates H1's rivals by exhaustion rather
  than establishing H1.**

## Why L5 breaks — the boundary is circular, and a sharper rival exists

exp-1 selected b87 *because* the SDK changed there, then reported the SDK as the only thing that
changed there. Worse, withdrawing `LIL-4` removed the datum that could have **falsified** H1 — that
widens the window to 2026-07-03 → 07-29 and destroys discrimination. exp-1 recorded it as
"the contradiction against H1 is removed"; it should read *the last remaining constraint was withdrawn*.

**Decisive counter-fact — full history of every widget-behavior path:**

```
59809ee3 2026-07-29 fix(widgets): X6 — wire WidgetRefreshController into both apps' bootstrap
7a9f90e5 2026-07-29 feat(widgets): X6 — WidgetRefreshController observes local saves
a0963538 2026-07-29 fix(widgets): X5 — split WidgetSnapshotBuilder.regenerate
56c0bcd0 2026-07-28 feat(core): X8 — extension processes construct a wired notification scheduler
0875470d 2026-07-28 …clears the history/widget caches after every destructive reset
73c2fbf8 2026-07-28 feat(core): suppress CloudKit mirroring for extension/widget roles (X15)
d8a253c0 2026-07-14 fix(widget): rows fill card height, "+" to corner overlay (#9)
      … NOTHING between 07-14 and 07-28 …
```

**b86 and b87 contain identical widget-specific source.** Six widget-behavior commits land in **b92**
— the only build with a confirmed bad observation. b91→b92 is single-variable in the right
direction in a way b86→b87 is not.

## Why L3 is wounded — the registration tail was inherited, not measured

`HYPOTHESES.md`'s shared failure tail ("not in PlugInKit registry → …") was justified **entirely** by
the macOS `pluginkit` measurement. macOS has since been re-attributed to LIL-92. **Once macOS leaves,
every measurement behind the tail leaves with it.** On iOS the tail is assumed.

Also, `GRID.md` distinction 2 is **wrong as written**: it claims a cold-cache return would carry
`snapshot: nil` → `WidgetUnavailableView`. That holds for `timeline(for:in:)` only.
`FilterTimelineProvider.swift:44-47` shows `snapshot(for:in:)` returns **the sample** on a cold cache.
(Redaction still points specifically at `placeholder(in:)`, so this doesn't overturn the reading —
but the distinction as stated is unsound.)

**The skipped class** — all produce an identical frozen redacted placeholder, none was considered:

1. **Extension launches and crashes.** (Font registration is *not* a vector — `LillistFonts.registered`
   fails soft, `LillistFonts.swift:37-51`.)
2. **Jetsam on the ~30 MB budget — documented in your own commit.** `73c2fbf8` (X15) says it closes
   *"the gap the widget's ~30MB memory budget couldn't previously afford"*. Before X15,
   `WidgetIntentSupport.makePersistence()` called `GatedPersistenceResolver(appGroupID:)` with **no
   role**, and `StoreConfiguration.appGroupOnDisk` armed `cloudKitContainerOptions` whenever the
   persisted mode was `.iCloudSync`. **Every build from the widget's ship (2026-07-01) through b91
   stood up a CloudKit-mirroring container inside the widget process on any cold-cache miss.**
3. **Hang in the resolution chain.** `timeline(for:in:)` has no timeout; `WidgetIntentSupport.Cache`
   (`WidgetIntentSupport.swift:16-44`) awaits a single in-flight build task, so a blocked
   `PersistenceController` init blocks every caller until WidgetKit's budget expires.

## Why L4 is wounded — "No Tags" has a mundane rival

Metadata claims verified: widget metadata declares `SelectFilterIntent` → parameter `Filter`, entity
`SmartFilterEntity`, `systemProtocols: [com.apple.link.systemProtocol.WidgetConfiguration]`;
`grep -c 'Tags'` over the widget's metadata = **0**.

But in `ShortcutsActions.appex`, `AddTaskIntent` has **`systemProtocols: []`** — a plain `AppIntent`,
**not eligible** to configure a widget. "AppIntents fell back to it" is not a described mechanism.

Rival that needs no defect: `AddTaskIntent` is exposed via `LillistShortcuts: AppShortcutsProvider`.
A **Shortcuts-app widget, Smart Stack entry, or Control/Lock-Screen accessory** pointed at "Add Task"
shows exactly `Title / Deadline / **Tags** / Notes`, the unset optional array rendering "No Tags".
Plus: if `SelectFilterIntent` were truly unavailable, WidgetKit would far more plausibly offer *no*
configuration than substitute a sibling extension's non-widget intent.

One datum does survive toward "the query ran and died": `SmartFilterEntityQuery.suggestedEntities()`
(`SmartFilterEntityQuery.swift:21-24`) returns `[.noFilter] + saved` and **cannot return empty**. So
"spinner, then dismisses with nothing" means the query never returned — process death mid-query or no
launch. It does not discriminate H1 from crash/jetsam, and says nothing about "Tags".

## exp-1's defects (my experiment — recorded against myself)

1. **The prediction had no possible refuting observation.** It tested only surfaces that structurally
   cannot change without a source edit (file set, entitlements, `Info.plist`, `otool -L`).
2. **It never looked at the binary** — the fatal omission:

   | | b86 | b87 | Δ |
   |---|---|---|---|
   | `LillistWidget` executable | 13,865,376 | 14,750,608 | **+885,232 (+6.4%)** |
   | `__TEXT.__text` | 5,380,864 | 5,808,880 | **+428,016** |
   | `__swift5_typeref` | 162,209 | 170,531 | +8,322 |

   Plus section-set changes (`__swift_as_cont` appears, `__init_offsets` disappears). exp-1 called
   this "an otherwise byte-comparable artifact." **It is not.**
3. **No control for source change:** `v0.15.0..v0.16.0` = **64 files, +1,626 / −1,490** across
   `LillistCore`/`LillistUI`, which the widget statically links.
4. **No negative control.** The same diff was never run on the **app**, which crossed the identical
   SDK boundary at the identical build and works. (Challenger ran it: the app gained
   `FoundationModels.framework`, lost `libswiftCoreMedia.dylib`.) The method cannot distinguish a
   broken binary from a working one.
5. It reported a new `LC_LOAD_DYLIB` (`libswiftCoreAudio.dylib`) and then summarized the diff as
   "only the toolchain."
6. **"SUPPORTED, not proven" was too generous.** A static corpus cannot support a hypothesis whose
   entire content is a runtime claim. Honest grade: *consistent with, and not discriminating against
   any rival.*

Useful negative finding: **#51/#70 do not reach the widget's runtime.** The widget links no new module
across the boundary (9 embedded Swift module names, identical both sides); `FoundationModels.framework`
was gained by the **app** only. #51/#70 changed the widget's code size and codegen via
LillistCore/LillistUI, not its behavior surface.

## Promoted ahead of H1

1. **The b91→b92 boundary** — the only boundary with a confirmed bad observation on the far side and a
   concentration of widget-behavior change (X5/X6/X8/X15/X11).
2. **Extension process death (jetsam or crash) rather than registration refusal**, with the pre-X15
   "widget arms CloudKit mirroring inside a ~30 MB budget" gap as leading mechanism. It explains both
   symptoms, needs no undocumented Apple behavior, spans both platforms, and **leaves physical
   evidence on the device retrievable today**.

## Caution on reporter recall

The macOS widget **provably never worked** (LIL-92's entitlement key has never existed since
2026-07-01), yet the report says "it worked previously" for both platforms. Discount "it worked
previously" and the "No Tags" string on iOS accordingly.
