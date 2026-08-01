# exp-2 — Reporter follow-up + App Group cache inspection: the investigation was chasing artifacts

**Type:** non-mutating observation (reporter actions on device + read-only inspection of the local
App Group container). No runtime builds, no installs.

**Outcome: three load-bearing premises of this investigation are FALSE.** A concrete, confirmed
defect replaces them.

## Reporter observations (2026-07-31)

1. **Analytics Data contains no Lillist entries** — no `LillistWidget-*.ips`, no `JetsamEvent-*.ips`.
2. **The widget could be removed and re-added from the widget gallery.**
3. **After re-adding, it renders "a large dark gray rectangle"** — no longer the redacted card.

## Falsified premise 1 — the widget IS registered and DOES launch

Adding a widget from the gallery requires the extension to be registered *and* launched to render
its preview. **H1's first link is broken**, and with it the entire registration framing carried over
from macOS. `EVIDENCE.md`'s "central anomaly" (LaunchServices vs PlugInKit disagreement) is a
**macOS-only** fact belonging to LIL-92; it was never an iOS fact.

## Falsified premise 2 — process death is out

No crash or jetsam report across a window covering several forced reloads and a remove/re-add cycle.
The challenger's promoted mechanism (pre-X15 CloudKit mirroring inside the ~30 MB widget budget)
predicts a `JetsamEvent` report. **None exists.** Not conclusive alone, but it is the evidence that
mechanism most needed, and it did not appear.

Note a logical tension that also weakens it independently: X15 (`73c2fbf8`) *removed* the mirroring
hazard and shipped in **b92** — the build reported broken. If mirroring-induced jetsam were the
cause, b92 should have improved.

## Falsified premise 3 — "No Tags" was never a defect signal

**"No Tags" is the name of one of the reporter's own saved smart filters.** From the local App Group
index:

```json
{"id":"68785E8B-A708-4F94-9E49-970D121F3C8A","name":"No Tags"}
```

`SmartFilterEntity.displayRepresentation` returns `DisplayRepresentation(title: "\(name)")` for a
saved filter, so the picker was **correctly displaying the selected filter's name**. There was no
AppIntents fallback, no cross-extension metadata leak, no ineligible-intent substitution.

`GRID.md` called this "the sharpest distinction" and ranked it first. It is **void**. Neither the
orchestrator nor the challenger checked what the user's filters were actually named — the whole
thread was built on an unexamined assumption about a string.

## Falsified premise 4 — the screenshot was the widget GALLERY, not the home screen

Re-reading the original screenshot: the card sits on a blurred wallpaper with the label **"Lillist"
centered beneath it** — the widget picker's presentation. WidgetKit renders `placeholder(in:)` under
`.redacted(reason: .placeholder)` in the gallery **by design**.

**The redaction was correct behavior.** `GRID.md`'s WHAT-IS — the entire "frozen redacted
placeholder" framing, and distinction 2's inference that `timeline(for:in:)` "is not completing
usably at all" — described an expected rendering in a context nobody established.

The challenger explicitly asked for the observation context to be established and for the screenshot
to be re-read (`CHALLENGE.md`, discriminators 2 and 3). Both were skipped.

## The actual finding — every cached snapshot is empty

Local App Group container, `~/Library/Group Containers/group.app.lillist/Widget/`:

| file | filterName | totalCount | openCount | tasks | generatedAt |
|---|---|---|---|---|---|
| `00000000-…` (unfiltered sentinel) | `""` | 0 | 0 | 0 | 2026-07-23T09:00:53Z |
| `68785E8B-…` | `No Tags` | 0 | 0 | 0 | 2026-07-23T09:00:53Z |
| `83911DF2-…` | `Stale` | 0 | 0 | 0 | 2026-07-23T09:00:53Z |
| `AC14ABFC-…` | `This Week` | 0 | 0 | 0 | 2026-07-23T09:00:53Z |
| `B3771C7B-…` | `Recently Closed` | 0 | 0 | 0 | 2026-07-23T09:00:53Z |
| `C11EDAC6-…` | `Today` | 0 | 0 | 0 | 2026-07-23T09:00:53Z |

`index.json` lists all five filters with correct names, so **`SmartFilterStore.list()` succeeded** —
the builder saw the filters. It then wrote `totalCount: 0` for every one of them, including the
unfiltered "all tasks" sentinel, which cannot legitimately be empty while the app shows tasks.

A single pass at `2026-07-23T09:00:53Z` wrote empty snapshots for everything, and **nothing has
regenerated them since** — despite X6 (`7a9f90e5`/`59809ee3`) existing specifically to regenerate on
local writes.

## Why this explains the symptom exactly

A freshly-added widget defaults to `SmartFilterEntity.noFilter` → `WidgetSnapshot.unfilteredID` →
reads `00000000-….json` → gets a snapshot with `filterName: ""`, `totalCount: 0`, `tasks: []` →
`WidgetFilterCardView` renders a card with no title and no rows → **a large dark rectangle.**

No hang, no crash, no registration failure, no SDK mechanism required. The widget is faithfully
rendering an empty snapshot.

## Scope caveat — this is the macOS container

These files are the **macOS** App Group container, and macOS has its own confirmed defect (LIL-92)
plus a store-location history (X1/`c7538745`, `621e6ded`) that could independently explain an empty
read there: before the App-Group store migration, the macOS app's store lived outside the group, so a
widget reading the group store would find an empty database and — per X5's "empty is success" class —
write that as authoritative. **The iOS container has not been observed.**

So: the *mechanism class* is confirmed here; its applicability to iOS is inferred, not measured. That
inference is exactly the error this experiment just caught twice, and it is flagged rather than
repeated.

## Next discriminator (cheap, on-device, no build)

**Open the Lillist iOS app, then look at the widget.** In b92, X6 wires `WidgetRefreshController` to
regenerate snapshots on local saves.

- Widget populates → the cache was stale/empty and the regeneration *trigger* is the defect.
- Widget stays blank → regeneration itself writes empty snapshots, implicating
  `WidgetSnapshotBuilder` / the store the widget process resolves.
