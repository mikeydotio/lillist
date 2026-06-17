---
module: Apps/Lillist-macOS/Sources/Commands
summary: "macOS menu bar commands and keyboard shortcuts wired via Notification broadcast"
read_when: "Touching macOS menu commands"
sources:
  - path: Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift
    blob: 81e589f69219472b3db0c94bf82379bd82b13916
  - path: Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift
    blob: 7d3bfea4ff5ac04bdc336b4638311b7f19fb10f4
  - path: Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift
    blob: 619f36e358e5539e180aaade98f648b998e8d8ea
references_modules: [Apps-Lillist-macOS-Sources-misc, Apps-Lillist-macOS-Sources-Views]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Apps/Lillist-macOS/Sources/Commands

## Purpose

Defines the macOS app's menu-bar `Commands` surface and the keyboard shortcuts from
design Section 7. The design idea is decoupling: each command posts a `Notification`
rather than calling a view directly, so the command tree stays target-agnostic and any
view can observe the action it cares about. Notification names and the focus-gating
helper are deliberately split into dependency-free files so the standalone
`Lillist-macOSTests` bundle (no app test host) can co-compile them without
`@testable import`.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `ListColumn` | enum | `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift:8` | `Hashable, Sendable` enum with `sidebar`/`list`; `.detail` retired when docked column was replaced by the floating editor |
| `LillistCommands` | struct | `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift:9` | SwiftUI `Commands` conformer installed in the macOS scene; provides all menu items and shortcuts |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Notification.Name` (lillist* extension) | extension | `Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift:8` | Canonical names linking command buttons to view observers; lives in its own file for test-bundle co-compilation |
| `CommandNotifications.postedByCommands` | enum prop | `Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift:38` | Registry a guard test walks to fail the build on dead commands; must stay in sync with posting buttons |
| `TaskListShortcutGate.isDisabled` | func | `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift:21` | Sole truth for disabling list shortcuts when `listColumn == nil`; used at every `.disabled(…)` call site in `LillistCommands` |
| `FocusedListColumnKey` | struct | `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift:35` | `FocusedValueKey` carrying `ListColumn` from the split view to `LillistCommands` |
| `FocusedValues.listColumn` | extension | `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift:39` | The `@FocusedValue` accessor `LillistCommands` reads to gate shortcuts |

## Relationships

- `Apps-Lillist-macOS-Sources-Commands.LillistCommands -> Apps-Lillist-macOS-Sources-misc.AppEnvironment (owns)`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-Commands.LillistCommands (calls)`
- `Apps-Lillist-macOS-Sources-Commands.LillistCommands -> Apps-Lillist-macOS-Sources-Commands.TaskListShortcutGate (calls)`
- `Apps-Lillist-macOS-Sources-Commands.LillistCommands -> Apps-Lillist-macOS-Sources-Commands.FocusedValues (reads)`
- `Apps-Lillist-macOS-Sources-Views.RootSplitView -> Apps-Lillist-macOS-Sources-Commands.FocusedValues (writes)`
- `Apps-Lillist-macOS-Sources-Views.RootSplitView -> Apps-Lillist-macOS-Sources-Commands.ListColumn (reads)`

## Type notes

`LillistCommands` holds an `AppEnvironment` (`Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift:10`)
and reads `listColumn` via `@FocusedValue` (`Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift:11`);
that value is published from `RootSplitView` through `.focusedValue(\.listColumn, …)`. A `nil`
`listColumn` means no Lillist window is key or a TextField is first responder, so
`TaskListShortcutGate.isDisabled` returns `true` and Space/⌘-Return/⌘-. go inert
(`Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift:21`). `lillistTasksDidChange` is
excluded from `CommandNotifications.postedByCommands` because it is posted by the editor panel on
close, not by a command-menu action (`Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift:21`).
Commands never mutate model state directly — they only post notifications.

## External deps

- SwiftUI — `Commands`, `CommandMenu`, `CommandGroup`, `@FocusedValue`, `FocusedValueKey`
- AppKit — `NSApp.orderFrontStandardAboutPanel`, `NSAttributedString`/`NSFont` for the About panel
- Foundation — `Notification.Name`, `NotificationCenter`
- LillistCore, LillistUI — imported by `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift:3`; provide `AppEnvironment`'s types

## Gotchas

- `postedByCommands` must stay in sync with posting buttons; `CommandNotificationObserverGuardTests` asserts each name has a live observer (`Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift:36`).
- `CommandGroup(replacing: .newItem)` removed SwiftUI's implicit ⌘N "New Window"; multi-window is deferred pending focus/onboarding verification (`Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift:14`).
- `FocusedValues.listColumn` becomes `nil` when any `TextField` captures first responder — SwiftUI clears `@FocusState` in that case, which propagates through `FocusedListColumnKey` and disables list-action shortcuts (`Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift:30`).
