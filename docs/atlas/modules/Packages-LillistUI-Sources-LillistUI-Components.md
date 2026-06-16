---
module: Packages/LillistUI/Sources/LillistUI/Components
summary: "Shared cross-platform SwiftUI row/chip/empty-state widgets both apps render"
read_when: Shared SwiftUI row widgets
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
    blob: 2c4cc98753dfa85326b234c64740e392dde6af4c
  - path: Packages/LillistUI/Sources/LillistUI/Components/RainbowEmptyStateView.swift
    blob: 53610b2d3ffd8906b213cd9b9b652a78fefbf1ee
  - path: Packages/LillistUI/Sources/LillistUI/Components/ReorderActionDispatch.swift
    blob: d003af836af61b395d86b30749b4ea9e26e3c7b3
  - path: Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift
    blob: dbb33dba3b233d3b5da45981806e3463f57c424d
  - path: Packages/LillistUI/Sources/LillistUI/Components/StatusCubeView.swift
    blob: 3803a29e4efcfef948ff89b2d259ce78fe182f7b
  - path: Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift
    blob: 122166666a5b0b9cc725e703b24bf447078f192a
  - path: Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift
    blob: dbc3a9bc1d13fef3c9ed1eefc6e7871c9291bf27
  - path: Packages/LillistUI/Sources/LillistUI/Components/TagChipView.swift
    blob: fe7f32f66f4aff83ad028f9d2626f63ced2e4fe0
  - path: Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift
    blob: be869c93455b323a44844a3d0392ff2c63238193
references_modules: [Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-misc, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistCore-Sources-LillistCore-Model, Apps-Lillist-macOS-Sources-Views-TaskList, Apps-Lillist-macOS-Sources-Views-Sidebar, Apps-Lillist-iOS-Sources-Detail, Packages-LillistUI-Sources-LillistUI-iOS-Tasks]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistUI/Sources/LillistUI/Components

## Purpose

The shared widget vocabulary both apps draw from: the task row and its status
chip, tag/sidebar chrome, sync dot, empty states, and the card-chrome modifier.
Each view is pure presentation — data and action closures arrive via `init`, no
`@State` lifecycle or store reads — so the same code renders identically on
macOS and iOS and can be snapshot-toured with frozen mock data. The design idea
holding it together is Rainbow Glass: flat tinted content rows separated by
surface value and a hairline (not shadows), with depth reserved for the floating
control layer. If this module vanished, both apps would lose their shared row
rendering and diverge visually.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `BreadcrumbView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/BreadcrumbView.swift:23` | Read-only `A › B › C` path; whole stack is one combined a11y element |
| `BuildVersionLabel` | struct | `Packages/LillistUI/Sources/LillistUI/Components/BuildVersionLabel.swift:7` | Muted centered "version (build)" footer; caller passes the string |
| `ConfettiBurstView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/ConfettiBurstView.swift:34` | One-shot deterministic 600ms burst; non-interactive, a11y-hidden |
| `ConfettiPolicy` | enum | `Packages/LillistUI/Sources/LillistUI/Components/ConfettiBurstView.swift:8` | `shouldBurst` decides burst eligibility; bursts only on transition into `.closed` |
| `DotGridBackdrop` | struct | `Packages/LillistUI/Sources/LillistUI/Components/RainbowEmptyStateView.swift:59` | Rasterized dot-grid texture; design rule limits it to heroes/empty states |
| `EmptyStateView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/EmptyStateView.swift:16` | macOS-only placeholder; iOS callers prefer `ContentUnavailableView` |
| `JournalEntryRow` | struct | `Packages/LillistUI/Sources/LillistUI/Components/JournalEntryRow.swift:11` | Renders a `JournalRecord` with kind glyph, timestamp, Markdown body |
| `JournalGlyph` | enum | `Packages/LillistUI/Sources/LillistUI/Components/JournalEntryRow.swift:42` | `symbol(for:)` maps `JournalEntryKind` to an SF Symbol name |
| `RainbowCardModifier` | struct | `Packages/LillistUI/Sources/LillistUI/Components/RainbowCard.swift:21` | Card surface + hairline + optional accent stripe; `.xs` flat by default |
| `RainbowEmptyStateView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/RainbowEmptyStateView.swift:8` | Themed empty state with spectrum glyph + optional CTA actions slot |
| `SidebarRowView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift:3` | Icon-chip + label + optional badge sidebar row; `Kind` drives semantics |
| `StatusCubeView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/StatusCubeView.swift:30` | Purely-visual status squircle; hosts the confetti burst on close |
| `StatusIndicatorView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift:16` | Tappable status control; tap cycles, long-press menu sets explicit status |
| `SyncStatusDotView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/SyncStatusDotView.swift:4` | Sync dot with popover/retry; posts a11y announcements on indicator change |
| `TagChipView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/TagChipView.swift:31` | Pure-text tag chip in `.pill` or `.meta` style; swatch from `TagTint` |
| `TaskRowView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:4` | Status control + label row; wired reorder closures become VoiceOver actions |
| `TaskRowLabel` | struct | `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:87` | Title + tag/deadline caption; split out so iOS can wrap only this region |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `rainbowCard` | func | `Packages/LillistUI/Sources/LillistUI/Components/RainbowCard.swift:71` | The `View` extension every repeating row reaches for to get card chrome |
| `ReorderActionDispatch` | struct | `Packages/LillistUI/Sources/LillistUI/Components/ReorderActionDispatch.swift:28` | Maps reorder closures to actions; only wired ones are advertised to AT |
| `composedAccessibilityLabel` | func | `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:60` | `nonisolated static`; builds the row's combined VoiceOver label, unit-tested |
| `isOverdue` | func | `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:130` | `nonisolated static` deadline math; closed tasks are never overdue |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Components.TaskRowView -> Packages-LillistUI-Sources-LillistUI-Components.StatusIndicatorView (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components.TaskRowLabel -> Packages-LillistUI-Sources-LillistUI-Components.TagChipView (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components.StatusIndicatorView -> Packages-LillistUI-Sources-LillistUI-Components.StatusCubeView (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components.StatusCubeView -> Packages-LillistUI-Sources-LillistUI-Components.ConfettiBurstView (owns)`
- `Packages-LillistUI-Sources-LillistUI-Components.StatusCubeView -> Packages-LillistUI-Sources-LillistUI-Components.ConfettiPolicy (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components.EmptyStateView -> Packages-LillistUI-Sources-LillistUI-Components.DotGridBackdrop (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components.TaskRowView -> Packages-LillistUI-Sources-LillistUI-Components.ReorderActionDispatch (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components.StatusCubeView -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistUI-Sources-LillistUI-Components.JournalEntryRow -> Packages-LillistCore-Sources-LillistCore-Model.JournalEntryKind (reads)`
- `Packages-LillistUI-Sources-LillistUI-Components.TaskRowView -> Packages-LillistCore-Sources-LillistCore-Model.TaskStore (reads)`
- `Packages-LillistUI-Sources-LillistUI-Components.StatusIndicatorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.StatusGlyph (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components.TagChipView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.TagTint (reads)`
- `Packages-LillistUI-Sources-LillistUI-Components.SyncStatusDotView -> Packages-LillistUI-Sources-LillistUI-misc.SyncIndicator (reads)`
- `Packages-LillistUI-Sources-LillistUI-Components.SyncStatusDotView -> Packages-LillistUI-Sources-LillistUI-Accessibility.AccessibilityAnnouncements (calls)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskListView -> Packages-LillistUI-Sources-LillistUI-Components.TaskRowView (calls)`
- `Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarView -> Packages-LillistUI-Sources-LillistUI-Components.SidebarRowView (calls)`
- `Apps-Lillist-iOS-Sources-Detail.TaskJournalTab -> Packages-LillistUI-Sources-LillistUI-Components.JournalEntryRow (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView -> Packages-LillistUI-Sources-LillistUI-Components.TaskRowLabel (calls)`

## Type notes

All views are `@MainActor`-isolated SwiftUI structs; the two value-math helpers
on `TaskRowView`/`TaskRowLabel` (`composedAccessibilityLabel`,
`isOverdue`) are `public nonisolated static` so XCTest and background callers
use them without crossing the View isolation boundary
(`Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:60`,
`Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:130`).
`StatusCubeView` owns burst lifecycle through a `@State burstID`: a status
change sets it, a structured `.task(id:)` clears it after 650ms, and the
`ConfettiBurstView` lives only inside that window so static fixtures can never
contain one (`Packages/LillistUI/Sources/LillistUI/Components/StatusCubeView.swift:56`).
`StatusCubeView` is purely visual — all interaction lives in `StatusIndicatorView`,
which renders the cube as a clear-label `Menu` because macOS drops Shape fills
when a cube is the Menu label
(`Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift:31`).

## External deps

- SwiftUI — every view; `Canvas`/`TimelineView` drive the confetti and dot grid
- LillistCore — `Status`, `TaskStore.TaskRecord`, `JournalStore.JournalRecord`, `JournalEntryKind` DTOs

## Gotchas

- `StatusIndicatorView` uses `Menu(primaryAction:)` not a simultaneous long-press gesture — the older gesture was flaky and could swallow the tap (`Packages/LillistUI/Sources/LillistUI/Components/StatusIndicatorView.swift:12`).
- `SidebarRowView`'s combined-a11y + label pair runs last in the body chain so a consumer's `.tag(...)` selection doesn't mask the label; a regression test pins the order (`Packages/LillistUI/Sources/LillistUI/Components/SidebarRowView.swift:56`).
- `ReorderActionsModifier` builds VoiceOver labels from compile-time literals; a runtime `String(localized:)` would not be extractable and left them English-only (`Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:169`).
- `TaskRowLabel` exists because a row-level long-press drag gesture over the status control eats its tap, so iOS wraps only the label region (`Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:87`).
