---
module: "Packages/LillistUI/Sources/LillistUI/Components (chunk 2)"
summary: "TaskRowView + TaskRowLabel: shared rendering atom for every task list row across iOS and macOS"
read_when: "Touching task row detail or VoiceOver reorder"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift
    blob: be869c93455b323a44844a3d0392ff2c63238193
references_modules: [Packages-LillistCore-Sources-LillistCore-CLIBridge-misc, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/Components (chunk 2)

## Purpose

This module is the shared rendering atom for individual task rows across every list surface in both apps. TaskRowView composes the full row (status indicator + label) for macOS and detail views; TaskRowLabel is the textual sub-component — title, tag chips, deadline — extracted so iOS drag-to-reorder surfaces can wrap only the label in their NavigationLink while the status indicator tap target sits outside the gesture. Without this module no surface can display a task row.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `TaskRowLabel` | struct | `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:87` | Stateless textual row region (title, tags, deadline) from value DTOs; isOverdue is nonisolated and safe for background callers. |
| `TaskRowView` | struct | `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:4` | Full task row composing status indicator and label; callers own all state and supply all action closures; adds VoiceOver reorder actions only for non-nil closures. |
| `body` | func | `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:153` | Attaches exactly the VoiceOver accessibility actions whose closures are non-nil; never registers a phantom no-op action for an unwired operation. |
| `composedAccessibilityLabel` | func | `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:60` | Returns localized "<title>, <status>[, tagged <tags>][, due <date>]"; public static, stable format, exposed for unit testing. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `label` | func | `Packages/LillistUI/Sources/LillistUI/Components/TaskRowView.swift:175` | Guards localization extractability for VoiceOver reorder action names: uses compile-time string literals so the four strings are visible to the localization-drift lint. A runtime String(localized:) from a computed key would silently leave them English-only; the literals must match ReorderAction.accessibilityKey and are pinned by ReorderActionDispatchTests (TaskRowView.swift:170-174). |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2.TaskRowLabel -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.startOfDay (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2.TaskRowLabel -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.TagChipView (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2.TaskRowView -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.StatusIndicatorView (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2.TaskRowView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2.body -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2.body -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.ReorderActionDispatch (owns)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2.body -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.invoke (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2.body -> Packages-LillistUI-Sources-LillistUI-DragReorder.reduce (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2.composedAccessibilityLabel -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2.composedAccessibilityLabel -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2.label -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`

## Type notes

Both public views are pure presenters: they accept TaskStore.TaskRecord (LillistCore value-type DTO) and [String] tag names with no @State, environment reads, or .task lifecycle (TaskRowView.swift:4-32, 87-94). TaskRowLabel.isOverdue is public nonisolated static so tests and background callers can invoke it without crossing the View's @MainActor boundary (TaskRowView.swift:130); the nonisolated keyword is deliberate and documented in the inline comment. TaskRowView.composedAccessibilityLabel is public static and exposed explicitly for unit testing (TaskRowView.swift:58-59). ReorderActionsModifier is private to the file and attaches VoiceOver actions only for non-nil closures, so surfaces that omit indent/outdent never advertise phantom no-op actions to assistive technology (TaskRowView.swift:147-183).

## External deps

- LillistCore — imported
- SwiftUI — imported

## Gotchas

TaskRowLabel was extracted from TaskRowView specifically to fix an iOS gesture conflict: a row-level long-press drag placed over the status control eats the status tap (TaskRowView.swift:83-86; cross-ref engineering-notes 2026-06-12). iOS outline rows wrap only TaskRowLabel in the NavigationLink + drag gesture while StatusIndicatorView sits outside both. VoiceOver reorder action names in ReorderActionsModifier.label(for:) use compile-time string literals (TaskRowView.swift:170-174) — a runtime String(localized: .init(action.accessibilityKey)) is not extractable by the localization-drift lint and previously left all four names English-only; the literals are pinned to match ReorderAction.accessibilityKey by ReorderActionDispatchTests.
