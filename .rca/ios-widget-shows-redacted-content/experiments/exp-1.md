# exp-1 — Static boundary sweep + differential across the SDK transition

**Type:** non-mutating static artifact forensics (no runtime available — user constraint,
2026-07-30). No worktree required; nothing on the host or in the repo was modified.

## Prediction (stated before running)

If H1 is right (widget extension built against a future/beta SDK fails on a 26.x device), then
somewhere in the historical build corpus the widget's build SDK crosses from 26.x to 27.0, that
crossing lands inside the reporter's "it used to work" window, and **nothing else about the widget
changes at that crossing**. If instead some code/packaging change is responsible, the differential
at the boundary will show it.

## Method

All 11 staged iOS builds under `~/Library/Application Support/deployit/serve/lillist-ios-*` were
unpacked and their widget appex `LC_BUILD_VERSION` extracted
(`scratchpad/sdk-sweep.sh`), then the two builds straddling the transition were diffed.

## Result 1 — the transition is sharp and single-variable

| Build | Version | Date | App SDK | Widget SDK | Widget minos | appex |
|---|---|---|---|---|---|---|
| 63 | 0.8.14 | 06-23 | 26.2 | — | — | ABSENT (pre-feature) |
| 83 | 0.13.0 | 07-03 | 26.2 | 26.2 | 26.0 | yes |
| 84 | 0.14.0 | 07-14 | 26.2 | 26.2 | 26.0 | yes |
| 85 | 0.14.1 | 07-15 | 26.2 | 26.2 | 26.0 | yes |
| 86 | 0.15.0 | 07-19 | 26.5 | 26.5 | 26.0 | yes |
| **87** | **0.16.0** | **07-20** | **27.0** | **27.0** | 26.0 | yes ← **transition** |
| 88 | 0.16.1 | 07-21 | 27.0 | 27.0 | 26.0 | yes |
| 89 | 0.17.0 | 07-21 | 27.0 | 27.0 | 26.0 | yes |
| 90 | 0.18.0 | 07-21 | 27.0 | 27.0 | 26.0 | yes |
| 91 | 0.18.1 | 07-22 | 27.0 | 27.0 | 26.0 | yes |
| 92 | 0.19.0 | 07-29 | 27.0 | 27.0 | 26.0 | yes |

`minos` is **26.0 on every build** — the deployment target never moved. Only the build SDK did.
The widget appex is present in every post-feature build, so nothing dropped it from packaging.

## Result 2 — the b86 → b87 differential shows only the toolchain

```
file set (find . | sort)          → IDENTICAL
entitlements (codesign -d)        → IDENTICAL
Info.plist                        → version bump + toolchain stamps ONLY:
    DTPlatformVersion  26.5        → 27.0
    DTSDKName          iphoneos26.5 → iphoneos27.0
    DTSDKBuild         23F81a      → 24A5380g
    DTXcode            2660        → 2700
    DTXcodeBuild       17F113      → 27A5218g      ← beta Xcode
otool -L                          → one addition: /usr/lib/swift/libswiftCoreAudio.dylib
```

## Result 3 — the contradiction against H1 is removed

`LIL-4 "On-device widget verification"` was closed `2026-07-21T05:07:13Z` — after the transition —
which previously looked like evidence the widget worked on SDK 27. Reading the story: it carries
**no verification comment whatsoever**. Its only comments are git bookkeeping from 2026-07-02. Its
"done" state records no observed result, so it is **not** evidence of a working widget at any date.
`GRID.md`'s "nearest evidenced good point: 2026-07-21" was overstated and is corrected here: the
last build with an SDK ≤ 26.5 is **b86, 2026-07-19**.

## Verdict on the prediction

> ### ⚠️ RETRACTED — this experiment was methodologically unsound. See `CHALLENGE.md`.
>
> The original verdict read "**SUPPORTED, not proven** … an otherwise byte-comparable artifact."
> **Both halves are wrong.**
>
> 1. **The artifact was not byte-comparable — this experiment never looked at the binary.**
>    b86 → b87: `LillistWidget` executable **+885,232 bytes (+6.4%)**, `__TEXT.__text` **+428,016**,
>    `__swift5_typeref` +8,322, plus section-set changes (`__swift_as_cont` appears,
>    `__init_offsets` disappears). Only file set, `Info.plist`, entitlements, and `otool -L` were
>    compared — surfaces that structurally *cannot* change without a source edit. **The prediction
>    therefore had no possible refuting observation.**
> 2. **No control for source change.** `v0.15.0..v0.16.0` = **64 files, +1,626 / −1,490** across
>    `LillistCore`/`LillistUI`, both statically linked into the appex.
> 3. **No negative control.** The same differential was never run against the **app**, which crossed
>    the identical SDK boundary at the identical build and works fine. The method cannot distinguish
>    a broken binary from a working one.
> 4. A new `LC_LOAD_DYLIB` (`libswiftCoreAudio.dylib`) was reported and then summarized as "only the
>    toolchain." A load command is not a stamp.
> 5. **§Result 3 draws the wrong conclusion.** Withdrawing `LIL-4` removed the datum that could have
>    **falsified** H1. That widens the window to 2026-07-03 → 07-29 and destroys discrimination; it
>    does not support H1. The heading "the contradiction against H1 is removed" should read *the last
>    remaining constraint was withdrawn*.
> 6. **The b87 boundary is circular** — selected because the SDK changed there, then reported as the
>    only change there. Decisively: **there are zero widget-source commits between 2026-07-14 and
>    2026-07-28**, so b86 and b87 contain *identical widget-specific source*, while six
>    widget-behavior commits land in **b92** — the only build with a confirmed bad observation.
>
> **Corrected grade: *consistent with, and not discriminating against any rival.*** A static corpus
> cannot support a hypothesis whose entire content is a runtime claim.
>
> What remains valid from this experiment: the **build-identity table** (SDK per build, `minos`
> pinned at 26.0 throughout, appex present in every post-feature build) and the observation that
> entitlements/`Info.plist`/file set are unchanged across the boundary. Those facts stand; the
> inference drawn from them does not.

## The unresolved objection

**The app binary crossed to SDK 27.0 at the same build and the app works fine on the phone.** So
"built with SDK 27" is not sufficient on its own to break a binary on iOS 26.x — the mechanism must
be something that applies to *extension loading/registration* specifically and not to app launch.
This investigation has not established such a mechanism for iOS. (On macOS the analogous
app-works/extension-fails split had a completely different cause — the missing sandbox entitlement,
LIL-92 — which is a caution against assuming the two platforms share one.)

## What would settle it (requires runtime — currently unavailable)

1. Install b86 (SDK 26.5) and b92 (SDK 27.0) on an iOS 26.x device; observe widget registration in
   each. Toggle gold standard.
2. Or: `xcrun simctl spawn <26.x sim> pluginkit -m -A -D -i app.lillist.Widget` against a
   simulator build from each toolchain.
3. Or: device Console/`sysdiagnose` during a widget reload, looking for the extension-launch error.
