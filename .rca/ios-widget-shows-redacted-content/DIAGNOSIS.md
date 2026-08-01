# DIAGNOSIS — ios-widget-shows-redacted-content (LIL-91, iOS)

**Confidence: HIGH on mechanism shape, UNCONFIRMED at runtime.** Every observation is explained by
one chain with no residue, and the chain's key defect is visible in source. What is *not* yet proven
is the final step — that `makePersistence()` actually blocks rather than merely being slow. That step
needs a device (`Console.app`) and is stated as unproven rather than assumed.

## Root cause

**`SmartFilterEntityQuery.entities(for:)` unconditionally awaits an unbounded Core Data stack
spin-up inside the widget process, so WidgetKit can never resolve the widget's configuration intent,
so `timeline(for:in:)` is never called.**

`Extensions/LillistWidget/SmartFilterEntityQuery.swift:12-18`:

```swift
func entities(for identifiers: [SmartFilterEntity.ID]) async throws -> [SmartFilterEntity] {
    let set = Set(identifiers)
    var result: [SmartFilterEntity] = []
    if set.contains(WidgetSnapshot.unfilteredID) { result.append(.noFilter) }   // answer already known…
    result += await allFilters().filter { set.contains($0.id) }                  // …but this runs anyway
    return result
}
```

`allFilters()` → `WidgetIntentSupport.makePersistence()` → `GatedPersistenceResolver` → `MigrationGate`
→ `PersistenceController.init`. **No timeout exists anywhere in that chain.** `try?` handles a *throw*;
nothing handles a *hang*.

## Chain

```
widget added / reloaded (configuration = No Filter sentinel — the default)
  → WidgetKit must resolve SelectFilterIntent before requesting a timeline
  → SmartFilterEntityQuery.entities(for: [unfilteredID])
  → .noFilter appended (correct answer, already in hand)
  → BUT: await allFilters() runs unconditionally
  → WidgetIntentSupport.makePersistence() blocks (Core Data stack in the widget process)
  → entities(for:) never returns
  → the configuration intent never resolves
  → timeline(for:in:) is NEVER CALLED
  → no entry ever reaches the host
  → only .containerBackground draws → a bare dark rectangle
```

## Every observation, accounted for

| Observation | Explanation |
|---|---|
| Home screen: plain dark rectangle, **no rainbow border** | `WidgetFilterCardView` never rendered; only `containerBackground` drew. **The discriminating datum** — a delivered-but-empty snapshot would have drawn the border. |
| Gallery: redacted card with sample rows | `placeholder(in:)` rendered under `.redacted(.placeholder)` — **normal gallery behavior**, never a defect |
| Config picker spins, then dismisses | `suggestedEntities()` → same `allFilters()` hang. `suggestedEntities` returns `[.noFilter] + saved` and **cannot** return empty, so a dismissal means it never returned |
| No crash / no jetsam reports | Nothing crashes — it hangs |
| Widget re-addable from the gallery | Extension registers and launches fine; this diagnosis requires that |
| Adding a task changes nothing | `WidgetRefreshController` regenerates and calls `reloadAllTimelines()` — worthless when `timeline(for:in:)` is never invoked |
| macOS also broken | Shares this source path — **plus** its own independent defect, LIL-92 |

## Contributing defects (independent, both real)

**C1 — the sentinel path does not short-circuit.** For `identifiers == [unfilteredID]` the answer is a
compile-time constant. Awaiting a Core Data stack to satisfy it is pure waste, and it is precisely the
default configuration of every freshly added widget.

**C2 — no bounded wait in an extension with a hard budget.** The widget process has a ~30 MB memory
budget and a short wall-clock budget. Every store-touching path (`entities(for:)`,
`suggestedEntities()`, `FilterTimelineProvider.loadSnapshot`'s cold-cache rebuild) can block
indefinitely. `WidgetIntentSupport.Cache` compounds it: callers await a single in-flight build task, so
one blocked init blocks every caller in the process.

**C3 — the fallback ordering is inverted.** `allFilters()` tries the **expensive** path (live Core Data)
first and falls back to the **cheap** one (`WidgetSnapshotStore.readIndex()`, a plain file read) only on
*throw* — never on slowness. For a configuration picker the cheap path is sufficient and should lead.

**C4 — unrelated but confirmed: the empty-snapshot write path swallows errors.**
`WidgetSnapshotBuilder.performRegenerate` writes the sentinel via `(try? …) ?? []`, persisting a thrown
error as an authoritative empty snapshot, while the saved-filter loop fails safe with `continue`. Present
since `96ee2360` (2026-07-02). Not the iOS cause (the border test ruled that out) but a genuine defect —
and the likely reason the local macOS cache is all zeros. Violates CLAUDE.md's "errors fail loud" tenet.

## Platform context (does not change the fix)

Independent developer reports describe `AppIntentTimelineProvider` widgets where `placeholder` is called
repeatedly and `timeline` never is, with console signature `ApplicationExtension record not found`,
persisting through the iOS 26 betas (FB13880020, FB18180368); and
[Apple Forums 814463](https://developer.apple.com/forums/thread/814463) documents the same shape — blank
`AppIntentTimelineProvider` widget despite fallback sample data, tens of reports, **no root cause found**.

Whether Lillist is hitting that platform bug or merely a self-inflicted hang, **the remediation is the
same**: never let intent resolution depend on an unbounded store open. C1–C3 remove the dependency.

## ODC classification

- **Type:** Algorithm/Method — a control-flow defect (missing short-circuit, missing bound), not
  assignment or interface.
- **Qualifier:** Missing — the guard and the timeout were never written.
- **Trigger:** Startup/Restart — surfaces when WidgetKit resolves configuration on add/reload.

## Verdict: **SURGICAL**

C1 is a two-line guard. C2 is a bounded `withTimeout` around the store open with a documented fallback.
C3 is an ordering swap in one function. All three are local to
`SmartFilterEntityQuery` / `WidgetIntentSupport`, blast radius confined to the widget extension, and
each is independently revertible. No redesign is warranted.

C4 is a separate one-line-shaped fix in `WidgetSnapshotBuilder` **plus** a testability change — the
builder takes a *concrete* `SmartFilterStore`, so the fail-unsafe branch is unreachable from a unit
test without introducing a protocol seam (DIP violation). That seam is the preventative action for the
defect class.

## Before fixing — the one runtime confirmation still owed

Attach Console.app to the iPhone, force a widget reload, and look for `ApplicationExtension record not
found` and/or an extension-timeout entry. This distinguishes "our hang" from "Apple's bug" and would
raise confidence from *high-unconfirmed* to *verified*. The fix is worth making either way, but the
RCA should not claim verification it does not have.

## Repro gate status

**NOT MET for iOS.** The only automated test in this investigation
(`WidgetExtensionRegistrationReproTests`) reproduces **LIL-92 (macOS)**, not this. A true iOS repro
needs either a device or a bounded-wait unit test written against the seam C2 introduces — that test
should be written **as part of the fix**, red first.

---

## ADDENDUM 2026-07-31 — the "no residue" claim was wrong; the "No Tags" residual, resolved

This document claimed above that the hypothesis explains every observation **with no residue**. That
was an overclaim. It never accounted for the report's *sharpest distinction* — the configuration row
being **labeled "No Tags"**. A hang explains a spinner dismissing empty; it cannot explain a wrong
parameter *title*. Resolved here by inspecting the compiled AppIntents metadata in the built product
rather than reasoning from source.

**The scary hypothesis is REFUTED.** The intake wrote: *"The configuration UI is resolving against
AppIntents metadata that does not belong to the widget's intent."* There is no such contamination in
the build:

- `LillistWidget.appex/Metadata.appintents/extract.actionsdata` declares
  `SelectFilterIntent/parameters[0]/title/key = **Filter**`, entity `SmartFilterEntity`
  ("Smart Filter"), query `SmartFilterEntityQuery`. **Zero** occurrences of the byte string `Tags`.
- The two intent-vending appexes have **completely disjoint** identifier namespaces — zero collisions
  across `actions`, `entities`, `queries`, `enums`:
  - widget → `{AdvanceTaskStatusFromWidget, SelectFilterIntent}`, `{SmartFilterEntity}`,
    `{SmartFilterEntityQuery}`
  - shortcuts → `{AddNote, AddNudge, AddTask, CompleteTask, OpenTask, QuickCaptureLockScreen,
    ReportCrash, SearchTasks, ToggleStatus}`, `{TaskEntity}`, `{TaskEntityQuery}`, `{StatusAppEnum}`
- `@Parameter(title: "Filter")` has been the declaration in **every commit that file has ever had**
  (`ae004da5` 2026-07-01, `96ee2360`) — it has never read `Tags`.

**The only source of the literal string in the entire app** is
`Extensions/ShortcutsActions/AddTaskIntent.swift:17` — `@Parameter(title: "Tags") var tags: [String]?`,
metadata `AddTaskIntent/parameters[2] = Tags` (array). An **unset optional** parameter is rendered by
AppIntents as `No <Title>` → **"No Tags"**. That same intent is also `autoShortcuts[0]` — Lillist's
most prominent App Shortcut ("Add Task", `plus` glyph, phrases "Add to Lillist" / "Lillist task"),
i.e. a *second configurable Lillist surface* that the system exposes independently of the widget.

**Two candidate explanations remain, both benign, and the choice between them changes nothing about
the fix:**

1. **Wrong surface.** The "No Tags" row belongs to the **Add Task App Shortcut**, not to
   `SelectFilterIntent`. Two Lillist-branded configurable surfaces exist; the observation conflated
   them. Note the internal tension in the intake that this reading dissolves: the *spinner* behavior
   matches the Filter row (`suggestedEntities()` hanging), while the *label* matches the Tags row —
   two different surfaces, reported as one.
2. **System-side fallback.** While `SelectFilterIntent` was unresolvable (the hang), the widget-edit
   sheet fell back to another intent from the app's aggregate catalog — plausibly the primary
   auto-shortcut, `AddTaskIntent`. Under this reading the label is a *downstream symptom of the same
   hang* and disappears with the fix.

**Verdict: no second defect, and no code change is warranted.** The widget's metadata is correct and
provably always has been. Distinguishing (1) from (2) is a ten-second on-device check and is recorded
on LIL-91; neither outcome implicates our code.
