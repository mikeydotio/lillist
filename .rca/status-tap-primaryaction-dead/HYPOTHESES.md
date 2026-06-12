# Hypothesis Report

## 5 Whys Analysis
1. Symptom: tapping the status circle does nothing (no cycle, no navigation).
2. Why? The Menu's backing control claims the touch but `primaryAction` never
   runs (menu-set path works ⇒ downstream healthy; no navigation ⇒ touch
   claimed).
3. Why? A competing structure introduced in build 26 interferes with the
   control's tap recognition → branch:
   - **H1**: `NavigationLink(value:)` wrapping the row label suppresses the
     embedded Menu's primary tap (cell-selection arbitration).
   - **H2**: the row-level `.gesture(LongPress.sequenced(DragGesture(min: 0)))`
     eats quick taps on the embedded control.
   - **H3**: deprecated `.menuStyle(.borderlessButton)` misbehaving on iOS 26.
4. Why shippable? Zero interaction-layer coverage: unit tests invoke closures
   directly, snapshots render statically, store tests call the API — a dead
   tap passes every suite.
5. Why invisible for 2+ weeks? The action pipeline swallows everything
   (`try?`, equal-status no-op, no transition diagnostic, no error surface).

## Hypotheses (Ranked at formation)
### H1 — NavigationLink suppression — Confidence: MEDIUM-HIGH (favored pre-test)
- For: macOS (no link) works; a11y tree shows the row collapsed into the
  link's single flat button; known SwiftUI pattern risk.
- Against: title taps work through the same structures on device.
- Falsification: remove the link only → tap revives?

### H2 — Row drag gesture eats the tap — Confidence: MEDIUM
- For: shipped in the same build; long-press menu survives because
  UIContextMenuInteraction is an independent recognizer.
- Against: plain `.gesture` (lowest priority) normally yields to child
  controls; title taps (cell selection) unaffected.
- Falsification: remove `.dragReorderable` only → tap revives?

### H3 — Deprecated menuStyle — Confidence: LOW
- Falsification: delete `.menuStyle(.borderlessButton)` → tap revives?

## Verdict (runtime falsification, iPhone 17 / iOS 26.2 sim)
- V1 (no NavigationLink, gesture kept): tap STILL DEAD → **H1 refuted**.
- V2 (link kept, gesture removed): tap WORKS → **H2 confirmed**.
- V4 not needed (H2 confirmed cleanly); menuStyle left untouched.
