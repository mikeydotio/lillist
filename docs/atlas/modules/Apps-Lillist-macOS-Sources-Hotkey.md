---
module: Apps/Lillist-macOS/Sources/Hotkey
summary: "System-wide Quick Capture hotkey monitor, key-combo codec, and the borderless floating capture panel"
read_when: macOS global hotkey/capture
sources:
  - path: Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift
    blob: aabfdf309ae61b86c6315570445b023b79f9dfca
  - path: Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift
    blob: 3d177e8680a0aee5d6228b0b090193f1d50571d5
  - path: Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift
    blob: f62390a36a429269bee13dc122ad58d397fe4b49
  - path: Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift
    blob: 0f04e35542b6cdf014f7f540707be0d70c9fe31d
  - path: Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePlacementMath.swift
    blob: e38650e29d0abcec51fa15a17dc25951b981d8ae
references_modules: [Apps-Lillist-macOS-Sources-misc, Apps-Lillist-macOS-Sources-Preferences, Packages-LillistUI-Sources-LillistUI-QuickCapture, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Apps/Lillist-macOS/Sources/Hotkey

## Purpose

Owns the macOS Quick Capture trigger end-to-end: a system-wide `NSEvent`
hotkey monitor, the canonical combo string codec it shares with the
preferences recorder, and the borderless floating panel that hosts the
capture form. The design idea is a single canonical combo string
(`"ctrl+opt+space"`) round-tripped through one key table, so the matcher
arming and the preferences UI never diverge. Without this module the macOS
app loses its global capture affordance.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `GlobalHotkeyMonitor.reregister(combo:)` | func | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:73` | Re-arms the monitor with a new combo; idempotent; unparseable combos ignored |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `GlobalHotkeyMonitor` | class | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:11` | `@MainActor` monitor held on `AppEnvironment`; routes the armed combo to `onHotkey` |
| `GlobalHotkeyMonitor.install` | func | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:42` | Installs global+local `NSEvent` keyDown monitors; tears down first (idempotent) |
| `GlobalHotkeyMonitor.parse` | func | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:101` | Pure inverse of the recorder encoder; combo string -> (modifiers, keyCode) |
| `GlobalHotkeyMonitor.uninstall` | func | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:58` | Removes both `NSEvent` monitors; called before every (re)install |
| `HotkeyKeyTable` | enum | `Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift:13` | Single source of truth keyCode<->token, shared by encoder and parser |
| `HotkeyRecorder` | struct | `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift:14` | SwiftUI keystroke-capture control; `encode` is its pure, testable core |
| `HotkeyRecorder.encode` | func | `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift:157` | Pure encoder; rejects modifier-free and bare-⌘ combos to avoid shadowing shortcuts |
| `QuickCapturePanelController` | class | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:8` | `@MainActor`; hosts `QuickCaptureView` in a floating borderless `NSPanel` |
| `QuickCapturePanelController.toggle` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:15` | Show/hide entry point invoked by the hotkey callback |
| `QuickCapturePanelController.submit` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:87` | Creates the task + assigns parsed tags via the environment stores |
| `QuickCapturePlacementMath.placementOrigin` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePlacementMath.swift:16` | Pure panel-origin math; isolated in its own file for the standalone test bundle |

## Relationships

- `Apps-Lillist-macOS-Sources-Hotkey.GlobalHotkeyMonitor.parse -> Apps-Lillist-macOS-Sources-Hotkey.HotkeyKeyTable (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.HotkeyRecorder.encode -> Apps-Lillist-macOS-Sources-Hotkey.HotkeyKeyTable (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePanelController.present -> Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePlacementMath (calls)`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Apps-Lillist-macOS-Sources-Hotkey.GlobalHotkeyMonitor (owns)`
- `Apps-Lillist-macOS-Sources-misc.AppDelegate -> Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePanelController (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.QuickCapturePane -> Apps-Lillist-macOS-Sources-Hotkey.HotkeyRecorder (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePanelController -> Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView (owns)`
- `Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePanelController.submit -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore (calls)`

## Type notes

`GlobalHotkeyMonitor` and `QuickCapturePanelController` are `@MainActor`-isolated;
the monitor's `onHotkey` callback fires on the main actor and bounces store work
onto `Task { @MainActor }`. The monitor caches the parsed combo into
`armedModifiers`/`armedKeyCode` so per-keystroke matching stays branch-free
(`Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:84`). `install`
tears down before re-adding so monitor tokens always reflect the current combo.
`HotkeyRecorder.encode`/`parse` and the `HotkeyKeyTable` lookups are
`nonisolated`/static pure functions usable off the main actor (tests, encoder).
`QuickCapturePanelController` clears `panel`/`text` on `close` and dismisses on
`didResignKey` (`Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:71`).

## External deps

- AppKit — `NSEvent` global/local monitors, `NSPanel`, `NSScreen`, key codes
- SwiftUI — `HotkeyRecorder` view, `NSHostingController` panel hosting

## Gotchas

- Encoder rejects bare-⌘ and modifier-free combos so a global hotkey can't shadow ⌘Q/⌘Space or every keystroke (`Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift:157`).
- `present` deliberately avoids `NSApp.activate(ignoringOtherApps:)` to keep `.nonactivatingPanel` from stealing menu-bar focus (`Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:59`).
- `parse` is order-tolerant on read though `encode` emits a fixed `ctrl,opt,cmd,shift` order, so hand-edited preferences still round-trip (`Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:97`).
