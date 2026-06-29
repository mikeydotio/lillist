---
module: "Packages/LillistUI/Sources/LillistUI/Components (chunk 1)"
summary: "Reusable Rainbow Glass SwiftUI components: status chips, swipeable rows, sync dot, card chrome, and empty states"
read_when: "Touching task rows, chips, swipe, or sync dot"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Components/BreadcrumbView.swift
    blob: c662c04cec8fb460c17ca9cfea3f78578e3d444a
  - path: Packages/LillistUI/Sources/LillistUI/Components/BuildVersionLabel.swift
    blob: 8623d335a16e13884f0d8985100db6a3e6f6b079
  - path: Packages/LillistUI/Sources/LillistUI/Components/ConfettiBurstView.swift
    blob: 9a7d9046cea6ecf02cba1784d60f393c8e812bb7
  - path: Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift
    blob: fd41846d18ba5b3c9409c5d35a3d9114325b3d3d
  - path: Packages/LillistUI/Sources/LillistUI/Components/JournalEntryRow.swift
    blob: d483247acd32c1841e88d0d2e472e904a083c170
  - path: Packages/LillistUI/Sources/LillistUI/Components/RainbowCard.swift
    blob: d8c379261aae4ece42386982a0a03fd877ea15ea
  - path: Packages/LillistUI/Sources/LillistUI/Components/RainbowEmptyStateView.swift
    blob: 53610b2d3ffd8906b213cd9b9b652a78fefbf1ee
  - path: Packages/LillistUI/Sources/LillistUI/Components/ReorderActionDispatch.swift
    blob: d003af836af61b395d86b30749b4ea9e26e3c7b3
  - path: Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift
    blob: dbb33dba3b233d3b5da45981806e3463f57c424d
  - path: Packages/LillistUI/Sources/LillistUI/Components/StatusCubeView.swift
    blob: 3803a29e4efcfef948ff89b2d259ce78fe182f7b
  - path: Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift
    blob: e5dbfb00dc8bf90717b46f21432a78c956139c58
  - path: Packages/LillistUI/Sources/LillistUI/Components/SwipeSettleArbiter.swift
    blob: cf59ef5568e46e40829aefc608d36daea124a53f
  - path: Packages/LillistUI/Sources/LillistUI/Components/SwipeableRow.swift
    blob: 50dff04de22eb32e3da4feeba199b7c9ca08958e
  - path: Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift
    blob: dbc3a9bc1d13fef3c9ed1eefc6e7871c9291bf27
  - path: Packages/LillistUI/Sources/LillistUI/Components/TagChipView.swift
    blob: fe7f32f66f4aff83ad028f9d2626f63ced2e4fe0
references_modules: [Apps-Lillist-macOS-Sources-Hotkey, Extensions-ShareExtension-iOS, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 99321d774840d17affd02fe2ac63b01b3d8cbec3
---

# Module: Packages/LillistUI/Sources/LillistUI/Components (chunk 1)

## Purpose

This module houses the reusable SwiftUI building blocks through which the Rainbow Glass design system becomes visible: the status squircle chip and its confetti burst, the custom swipe-gesture row, the sync dot, card chrome, sidebar rows, tag chips, and empty states. It is the concrete composition layer between raw LillistCore value types (Status, TagTint, SyncIndicator) and the rendered list surfaces in both apps. Remove it and every task row, status interaction, and empty surface reverts to an unthemed stub that both app targets would have to reimplement independently.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `BreadcrumbView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/BreadcrumbView.swift:23` | Callers pass path: [String]; the view renders a non-interactive breadcrumb trail as one combined a11y element with label "Path: A › B › C". BreadcrumbView.swift:23-41. |
| `BuildVersionLabel` | struct | `Packages/LillistUI/Sources/LillistUI/Components/BuildVersionLabel.swift:7` | Callers pass version: String; the view renders it full-width centered in caption2, Dynamic-Type-safe, with accessibility label "App version <version>". BuildVersionLabel.swift:7-22. |
| `CardBorderTreatment` | enum | `Packages/LillistUI/Sources/LillistUI/Components/RainbowCard.swift:28` | Sendable enum gating how rainbowCard draws its border: .hairline is resting; .rainbow and .dropTargetParent are transient drag-reorder cues. Equatable for change detection. RainbowCard.swift:28-32. |
| `ConfettiBurstView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/ConfettiBurstView.swift:34` | One-shot 600 ms burst; geometry is deterministic (fixed-seed SplitMix64). The parent removes the view to end it; the view is accessibility-hidden. ConfettiBurstView.swift:34-91. |
| `ConfettiPolicy` | enum | `Packages/LillistUI/Sources/LillistUI/Components/ConfettiBurstView.swift:8` | shouldBurst(from:to:reduceMotion:) returns true only on a transition into .closed from a non-closed state with motion enabled; all other combinations return false. ConfettiBurstView.swift:8-17. |
| `DotGridBackdrop` | struct | `Packages/LillistUI/Sources/LillistUI/Components/RainbowEmptyStateView.swift:59` | Rasterized dot-grid Canvas (drawingGroup()); hit-testing disabled; accessibility-hidden. Design-system rule: heroes and empty states only. DotGridBackdrop causes blank offscreen snapshots when drawingGroup/Metal is active. RainbowEmptyStateView.swift:59-84. |
| `EmptyStateView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift:16` | macOS-primary empty state; title/message/systemImage are plain strings; icon scales with Dynamic Type via @ScaledMetric. iOS callers should prefer ContentUnavailableView. EmptyStateView.swift:16-58. |
| `JournalEntryRow` | struct | `Packages/LillistUI/Sources/LillistUI/Components/JournalEntryRow.swift:11` | Renders a JournalStore.JournalRecord with leading glyph (from JournalGlyph.symbol), timestamp, and Markdown body; the row is one combined a11y element. JournalEntryRow.swift:11-37. |
| `JournalGlyph` | enum | `Packages/LillistUI/Sources/LillistUI/Components/JournalEntryRow.swift:42` | Namespace for symbol(for:); no cases to instantiate. symbol(for:) is the single authoritative SF Symbol mapping for journal entry kinds. JournalEntryRow.swift:42-51. |
| `Kind` | enum | `Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift:4` | Sendable enum classifying sidebar row type (task/smartFilter/tag/trash); passed at init alongside icon and label to parameterize the row's chip tint source. SidebarRowView.swift:4. |
| `Outcome` | enum | `Packages/LillistUI/Sources/LillistUI/Components/SwipeSettleArbiter.swift:15` | Equatable enum of five settle outcomes (commitLeading/Trailing, openLeading/Trailing, close). No side effects; safe to construct and compare in unit tests. SwipeSettleArbiter.swift:15-21. |
| `RainbowCardModifier` | struct | `Packages/LillistUI/Sources/LillistUI/Components/RainbowCard.swift:34` | ViewModifier applying card chrome: surface fill, border (hairline/rainbow/dropTarget), optional accent stripe, 0.62 done-opacity, and elevation shadow. Reads increaseContrastOverride from the environment. RainbowCard.swift:34-96. |
| `RainbowEmptyStateView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/RainbowEmptyStateView.swift:8` | Themed empty state with dot-grid backdrop, rainbow SF Symbol, title, message, and an optional @ViewBuilder actions slot. For iOS-themed surfaces where brand treatment is required. RainbowEmptyStateView.swift:8-52. |
| `ReorderAction` | enum | `Packages/LillistUI/Sources/LillistUI/Components/ReorderActionDispatch.swift:5` | CaseIterable, Equatable enum of four VoiceOver reorder ops with stable accessibilityKey strings used as accessibilityAction(named:) labels. ReorderActionDispatch.swift:5-21. |
| `ReorderActionDispatch` | struct | `Packages/LillistUI/Sources/LillistUI/Components/ReorderActionDispatch.swift:28` | Pure closure router: availableActions returns only actions with wired closures; invoke(_:) fires or no-ops. No phantom actions are ever advertised to assistive technology. ReorderActionDispatch.swift:28-65. |
| `SidebarRowView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift:3` | Renders an icon chip (tinted at rest, color-fills on isSelected), label, and optional badge count. Accessibility label concatenates label and badge count. SidebarRowView.swift:3-90. |
| `SplitMix64` | struct | `Packages/LillistUI/Sources/LillistUI/Components/ConfettiBurstView.swift:96` | Deterministic PRNG seeded at init; next() mutates state each call; unitDouble() returns a value in [0, 1). Output is stable across platforms for a given seed sequence. ConfettiBurstView.swift:96-113. |
| `StatusCubeView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/StatusCubeView.swift:30` | Renders the status squircle chip for status: Status with shape-axis differentiation; hosts the one-shot confetti burst internally via burstID. Tap/menu handling lives in StatusIndicatorView. StatusCubeView.swift:30-144. |
| `StatusIndicatorView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift:16` | 44pt tap target: StatusCubeView under a transparent Menu(primaryAction:) overlay. Primary action calls onClick (forward-cycle); long-press exposes explicit setters via onSetStatus. The cube is NOT the Menu label (macOS rendering constraint). StatusIndicatorView.swift:16-81. |
| `Style` | enum | `Packages/LillistUI/Sources/LillistUI/Components/TagChipView.swift:32` | Two-case enum: .pill (card capsule + swatch + name, detail surfaces) or .meta (bare swatch + muted name, dense task-row meta lines). TagChipView.swift:32-37. |
| `SwipeActionSpec` | struct | `Packages/LillistUI/Sources/LillistUI/Components/SwipeableRow.swift:7` | Value type: titleKey, systemImage, tint, isDestructive, allowsFullSwipe (defaults true), and a perform closure. allowsFullSwipe:false guards destructive actions by forcing reveal-then-tap. SwipeableRow.swift:7-35. |
| `SwipeSettleArbiter` | enum | `Packages/LillistUI/Sources/LillistUI/Components/SwipeSettleArbiter.swift:14` | Pure namespace; outcome(offset:predictedTranslation:actionWidth:fullSwipeThreshold:hasLeading:leadingAllowsFullSwipe:hasTrailing:trailingAllowsFullSwipe:) is the only entry point. No UI side effects. SwipeSettleArbiter.swift:14-64. |
| `SwipeableRow` | struct | `Packages/LillistUI/Sources/LillistUI/Components/SwipeableRow.swift:60` | Custom-gesture swipe row with axis arbitration; openRowID binding enforces single-open-at-a-time. isReorderActive:true hard-disables the swipe gesture. Do not combine with .swipeActions. SwipeableRow.swift:60-261. |
| `SyncStatusDotView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift:4` | Renders iCloud sync dot/icon; tapping paused state calls onPausedTap; other states toggle a popover with retry. Posts VoiceOver announcements on every indicator change. SyncStatusDotView.swift:4-128. |
| `TagChipView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/TagChipView.swift:31` | Non-interactive tag chip in .pill or .meta style; swatch color from TagTint.resolved(in:); accessibility label is always "Tag: name". TagChipView.swift:31-99. |
| `View` | extension | `Packages/LillistUI/Sources/LillistUI/Components/RainbowCard.swift:98` | Adds rainbowCard(accent:isDone:elevation:border:) to all Views. Default elevation is .xs; keep it there for list rows per the Rainbow Glass content rule. RainbowCard.swift:98-110. |
| `body` | func | `Packages/LillistUI/Sources/LillistUI/Components/RainbowCard.swift:47` | Applies card fill, border overlay, accent stripe, done-opacity (0.62), and elevation shadow. .xs elevation is flat (no shadow); higher elevations add a rainbowShadow. RainbowCard.swift:47-79. |
| `invoke` | func | `Packages/LillistUI/Sources/LillistUI/Components/ReorderActionDispatch.swift:53` | Fires the registered closure for action if one exists; silently no-ops otherwise. Safe to call without checking availableActions first. ReorderActionDispatch.swift:53-55. |
| `outcome` | func | `Packages/LillistUI/Sources/LillistUI/Components/SwipeSettleArbiter.swift:35` | Pure function: given offset, fling, widths, and per-side flags, returns an Outcome. Trailing is checked before leading; full-swipe before open. allowsFullSwipe:false forces reveal-only. SwipeSettleArbiter.swift:35-63. |
| `rainbowCard` | func | `Packages/LillistUI/Sources/LillistUI/Components/RainbowCard.swift:100` | Entry point for Rainbow card chrome; all parameters have safe defaults. Elevation defaults to .xs — callers must not raise it for List/ForEach rows. RainbowCard.swift:100-110. |
| `symbol` | func | `Packages/LillistUI/Sources/LillistUI/Components/JournalEntryRow.swift:43` | Returns a stable SF Symbol name string for each JournalEntryKind; callers rely on this mapping being the canonical glyph table across all journal surfaces. JournalEntryRow.swift:43-51. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `close` | func | `Packages/LillistUI/Sources/LillistUI/Components/SwipeableRow.swift:278` | Atomically resets offset to 0 and clears openRowID if this row owns the open slot; called from settle, both onChange handlers, and the tap-to-close overlay. The invariant — visual snap paired with coordination state — is enforced only here. SwipeableRow.swift:249-252. |
| `closure` | func | `Packages/LillistUI/Sources/LillistUI/Components/ReorderActionDispatch.swift:57` | Routing kernel for the dispatch: both availableActions (which filters it) and invoke (which calls its result) depend entirely on closure(for:) to map each ReorderAction to its handler. Its switch is the single source of truth for the action-to-handler mapping. ReorderActionDispatch.swift:57-65. |
| `perform` | func | `Packages/LillistUI/Sources/LillistUI/Components/SwipeableRow.swift:272` | `perform(_:)` is the single convergence point that enforces the close-before-fire invariant for every swipe action. It calls `close()` (Packages/LillistUI/Sources/LillistUI/Components/SwipeableRow.swift:245) to snap the row shut visually before `spec.perform()` fires (line 246), preventing a data mutation from racing an open animation. All three internal paths that trigger an action route here: the action-button tap handler (line 149) and both full-swipe commit branches in `settle` (lines 227 and 229). Bypassing it would break the visual settle-before-mutate contract. |
| `reasonDescription` | func | `Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift:105` | Single source of all PauseReason-to-string conversions; its output feeds both the popover label (via the label computed property) and the VoiceOver announcement in onChange. All pause-reason UI text is owned here. SyncStatusDotView.swift:105-114. |
| `settle` | func | `Packages/LillistUI/Sources/LillistUI/Components/SwipeableRow.swift:239` | The sole bridge between raw gesture physics and observable side effects: on every drag release, `settle` invokes `SwipeSettleArbiter.outcome` with the current rubber-banded offset and the gesture's predicted fling translation, then exhaustively dispatches the five possible outcomes — commit leading, commit trailing, open leading, open trailing, or close. Without it, no swipe gesture ever resolves into an action fire, a held-open reveal, or a snap-closed return. It also stamps `openRowID = rowID` for the open cases, which is the entire mechanism by which sibling rows detect that they should close. Removing or bypassing it leaves the swipe gesture permanently unresolved and the single-open-row invariant unenforceable. |
| `snap` | func | `Packages/LillistUI/Sources/LillistUI/Components/SwipeableRow.swift:283` | Single animation entry point for all positional transitions: applies LillistMotion.squish(LillistMotion.fast) or skips animation under Reduce Motion. Every branch of settle and close flows through snap. SwipeableRow.swift:254-261. |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Axis2D -> Packages-LillistCore-Sources-LillistCore-Notifications.action (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Axis2D -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.BreadcrumbView -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.BreadcrumbView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.BuildVersionLabel -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.BuildVersionLabel -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.ConfettiPolicy -> Apps-Lillist-macOS-Sources-Hotkey.open (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.DotGridBackdrop -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.color (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.DotGridBackdrop -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.EmptyStateView -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.EmptyStateView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Kind -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Kind -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Kind -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Kind -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.color (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Kind -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Kind -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.resolved (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Particle -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.color (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Particle -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.RainbowCardModifier -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.SplitMix64 -> Extensions-ShareExtension-iOS.next (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.StatusCubeView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.StatusCubeView -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.StatusCubeView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.StatusIndicatorView -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.StatusIndicatorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Style -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Style -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Style -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Style -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.Style -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.resolved (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.SyncStatusDotView -> Apps-Lillist-macOS-Sources-Hotkey.toggle (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.SyncStatusDotView -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.SyncStatusDotView -> Packages-LillistUI-Sources-LillistUI-Accessibility.post (emits)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.SyncStatusDotView -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.SyncStatusDotView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.SyncStatusDotView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.actionCard -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.badgeView -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.badgeView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.badgeView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.body -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.body -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbowShadow (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.outcome -> Apps-Lillist-macOS-Sources-Hotkey.open (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.reasonDescription -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.settle -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.Decision (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.snap -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.squish (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1.swatch -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`

## Type notes

All View structs are implicitly @MainActor. StatusCubeView owns @State private var burstID: UInt64? to track the confetti burst; a .task(id: burstID) structured task clears it after 650 ms — the parent does not need to manage burst lifetime (StatusCubeView.swift:42-74). ConfettiBurstView holds no timers; TimelineView(.animation) drives frames and the parent's .task is the only lifecycle owner (ConfettiBurstView.swift:34-91). SwipeableRow owns offset/axis/dragStartOffset as @State and coordinates the single-open-at-a-time invariant through an external @Binding var openRowID: UUID? — the binding is the only shared mutable state between row instances (SwipeableRow.swift:60-82). SplitMix64 uses a fixed seed (0x5EED_C0DE_CAFE_F00D) so particle geometry is deterministic across hosts and render passes (ConfettiBurstView.swift:49). ReorderActionDispatch and SwipeSettleArbiter are pure value types with no actor isolation — fully unit-testable without a main-thread constraint (ReorderActionDispatch.swift, SwipeSettleArbiter.swift). All components reading accessibility environment values (increaseContrastOverride, reduceMotionOverride, differentiateWithoutColorOverride) accept an override key that wins over the system value, enabling snapshot-test injection without modifying system accessibility settings.

## External deps

- CoreGraphics — imported
- LillistCore — imported
- SwiftUI — imported
- old: — imported

## Gotchas

StatusIndicatorView uses a transparent Color.clear Menu label — NOT StatusCubeView as the label — because macOS drops Shape fills inside Menu label rendering machinery (Images survive, fills vanish). Documented at StatusIndicatorView.swift:32-39. // SidebarRowView: .accessibilityElement(children: .combine) + .accessibilityLabel must run last in body so a .tag(SidebarSelection.…) modifier applied by callers doesn't mask the label; pinned by SidebarRowViewA11yTests at SidebarRowView.swift:56-63. // SwipeableRow requires a custom DragGesture because placing SwiftUI DragGesture on cell content claims horizontal pans before UIKit .swipeActions fires, silently killing swipe-to-delete; documented at SwipeableRow.swift:40-56. // DotGridBackdrop wraps its Canvas in .drawingGroup() to rasterize to Metal once and avoid re-running the dot loop on every scroll; this also blanks offscreen snapshot capture (the snapshot gotcha is noted in CLAUDE.md). RainbowEmptyStateView.swift:55-56.
