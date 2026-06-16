---
module: Apps/Lillist-macOS/Sources/Commands
summary: "macOS menu-bar commands and keyboard shortcuts that post notifications views observe"
read_when: "macOS menu commands"
sources:
  - path: Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift
    blob: a4a22becc50b0609cc4a941cacf1c88596f7d137
  - path: Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift
    blob: 12c29f7c53e5616d78e81607e76ad8fde76d8440
  - path: Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift
    blob: 145b249573a6cc4ac62e26ec526d42d6c80927a1
references_modules: [Apps-Lillist-macOS-Sources-misc, Apps-Lillist-macOS-Sources-Views-misc, Apps-Lillist-macOS-Sources-Views-TaskList]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
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
| `ListColumn` | enum | `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift:8` | `sidebar`/`list`/`detail`; identifies which split column holds focus |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `LillistCommands` | struct | `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift:9` | The entire menu/shortcut tree; each button posts one notification |
| `Notification.Name` (lillist*) | extension | `Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift:8` | Canonical names linking command buttons to view observers |
| `CommandNotifications.postedByCommands` | enum prop | `Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift:32` | Registry a guard test walks to fail the build on dead commands |
| `TaskListShortcutGate.isDisabled` | func | `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift:20` | Sole truth for disabling list shortcuts when no column is focused |
| `FocusedListColumnKey` | struct | `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift:34` | `FocusedValueKey` carrying `ListColumn` from the split view to commands |
| `FocusedValues.listColumn` | extension | `Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift:38` | The `@FocusedValue` accessor `LillistCommands` reads to gate shortcuts |

## Relationships

- `Apps-Lillist-macOS-Sources-Commands.LillistCommands -> Apps-Lillist-macOS-Sources-misc.AppEnvironment (owns)`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-Commands.LillistCommands (calls)`
- `Apps-Lillist-macOS-Sources-Commands.LillistCommands -> Apps-Lillist-macOS-Sources-Commands.TaskListShortcutGate (calls)`
- `Apps-Lillist-macOS-Sources-Commands.LillistCommands -> Apps-Lillist-macOS-Sources-Commands.FocusedValues (reads)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Apps-Lillist-macOS-Sources-Commands.FocusedValues (writes)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Apps-Lillist-macOS-Sources-Commands.ListColumn (reads)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskListView -> Apps-Lillist-macOS-Sources-Commands.Notification.Name (reads)`

## Type notes

`LillistCommands` holds an `AppEnvironment` (`Apps/Lillist-macOS/Sources/LillistCommands.swift:10`)
and reads `listColumn` via `@FocusedValue` (`Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift:11`);
that value is published from `RootSplitView` through `.focusedValue(\.listColumn, …)`. A `nil`
`listColumn` means no Lillist window is key or a TextField is first responder, so
`TaskListShortcutGate.isDisabled` returns `true` and Space/⌘-Return/⌘-. go inert
(`Apps/Lillist-macOS/Sources/Commands/FocusedListColumn.swift:19`). `ListColumn` is
`Hashable, Sendable`; `CommandNotifications` and `Notification.Name` extensions are stateless
statics. Commands never mutate model state directly — they only post notifications.

## External deps

- SwiftUI — `Commands`, `CommandMenu`, `CommandGroup`, `@FocusedValue`, `FocusedValueKey`
- AppKit — `NSApp.orderFrontStandardAboutPanel`, `NSAttributedString`/`NSFont` for the About panel
- LillistCore, LillistUI — imported by `LillistCommands.swift`; provide `AppEnvironment`'s types

## Gotchas

- `postedByCommands` must stay in sync with posting buttons; `CommandNotificationObserverGuardTests` asserts each name has a live observer (`Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift:28`).
- `CommandGroup(replacing: .newItem)` removed SwiftUI's implicit ⌘N "New Window"; multi-window is deferred pending focus/onboarding verification (`Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift:14`).
