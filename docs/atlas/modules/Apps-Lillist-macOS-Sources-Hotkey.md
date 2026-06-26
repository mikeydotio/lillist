---
module: Apps/Lillist-macOS/Sources/Hotkey
summary: "macOS global hotkey monitor, floating Quick Capture panel, hotkey-combo codec, and panel placement math"
read_when: "Touching macOS global hotkey or capture panel"
sources:
  - path: Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift
    blob: aabfdf309ae61b86c6315570445b023b79f9dfca
  - path: Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift
    blob: 3d177e8680a0aee5d6228b0b090193f1d50571d5
  - path: Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift
    blob: 318da9fea641ea7180bec2173ec570cfec982549
  - path: Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift
    blob: 88cf1b1b08f3f31ab6b652a0fe12febcab8ca796
  - path: Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePlacementMath.swift
    blob: e38650e29d0abcec51fa15a17dc25951b981d8ae
references_modules: [Apps-Lillist-macOS-Sources-chunk-1, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Editor, Packages-LillistUI-Sources-LillistUI-Recurrence, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Apps/Lillist-macOS/Sources/Hotkey

## Purpose

This module implements the macOS global-hotkey Quick Capture surface: a system-wide key-combo monitor that fires over any foreground app, a floating non-activating NSPanel that hosts TaskEditorView, and the supporting codec and placement math. The core idea is that a single combo-string serialization format ties together HotkeyRecorder (captures a keystroke into a string), HotkeyKeyTable (single-source lookup), and GlobalHotkeyMonitor (arms from that string) so all three stay in sync without duplication. Without this module the macOS app loses its primary cross-app entry point for fast task capture and inline editing.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `GlobalHotkeyMonitor` | class | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:11` | @MainActor final class; set onHotkey, then call install() to arm; change the live combo at runtime via reregister(combo:) without re-creating the monitor. |
| `HotkeyKeyTable` | enum | `Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift:13` | Caseless-enum namespace; single canonical mapping between macOS virtual key codes and the lowercase token strings used in hotkey combo serialization (Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift:13-55). |
| `HotkeyRecorder` | struct | `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift:15` | SwiftUI View with @Binding<String>; static encode(modifiers:keyCode:) is nonisolated — callable from tests without a main-actor context (Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift:160). |
| `QuickCapturePanelController` | class | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:21` | @MainActor final class; holds at most one floating NSPanel; toggle() is the hotkey entry point, open(taskID:) is the row-click entry; panel is non-activating so the user's active app is unaffected (Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:21-27). |
| `QuickCapturePlacementMath` | enum | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePlacementMath.swift:7` | Caseless-enum namespace for pure placement math; isolated from AppEnvironment and SwiftUI so standalone test targets can compile and exercise placement logic (Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePlacementMath.swift:7-25). |
| `close` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:194` | Tears down the panel; cancelled=true discards a capture draft via model.discard() before clearing state; cancelled=false closes after a commit (Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:194-204). |
| `install` | func | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:42` | Idempotent: tears down any existing monitors before re-registering, so repeated calls with the same or a new combo are safe (Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:42-56). |
| `keyCode` | func | `Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift:22` | Returns the macOS virtual key code for a lowercase token (e.g. "space" -> 49); nil for unknown names; covers letters, digits, F1-F12, space/return/delete/escape (Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift:22-24). |
| `name` | func | `Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift:16` | Returns the canonical lowercase token for a macOS virtual key code; nil for codes outside the supported set (Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift:16-18). |
| `open` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:62` | Opens an existing task for editing; if a panel is already open retargets it in place rather than stacking; loads the task model asynchronously after presenting (Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:62-78). |
| `parse` | func | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:101` | Returns (modifiers, keyCode) for any combo round-tripped from HotkeyRecorder.encode; nil for unknown keys or non-modifier tokens; order-tolerant on modifiers (Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:101-117). |
| `placementOrigin` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePlacementMath.swift:16` | Returns bottom-left origin centering the panel horizontally on the mouse's screen with its top edge ~1/3 down from the visible area top; uses AppKit bottom-left coordinates (Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePlacementMath.swift:16-24). |
| `reregister` | func | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:73` | Updates the armed combo and reinstalls monitors; silently ignores unparseable strings so a malformed preference cannot disarm the hotkey (Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:73-79). |
| `toggle` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:49` | Opens a new-capture draft panel if none is open; no-ops if one is already visible; delegates the open/noop decision to EditorOpenDecision (Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:49-57). |
| `uninstall` | func | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:58` | Removes both global and local NSEvent monitors and nils the tokens; safe to call on an already-uninstalled monitor (Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:58-62). |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `place` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:161` | Single site for multi-screen mouse-location detection; queries the screen under the cursor, delegates to QuickCapturePlacementMath.placementOrigin, and applies the result — the only place where screen selection logic executes (Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:161-171). |
| `present` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:82` | Single factory for NSPanel creation; sets all floating, non-activating, transparent-titlebar, and deactivate-hide policy; mounts the SwiftUI hosting controller, positions the panel via place(), and arms the mode observer — all open paths pass through here (Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:82-117). |

## Relationships

- `Apps-Lillist-macOS-Sources-Hotkey.HotkeyRecorder -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.HotkeyRecorder -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.HotkeyRecorder -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.KeyCap -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePanelController -> Packages-LillistUI-Sources-LillistUI-Editor.Stores (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.close -> Packages-LillistUI-Sources-LillistUI-Editor.discard (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.editorRoot -> Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.matchesHotkey -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.notifyChanged -> Packages-LillistUI-Sources-LillistUI-Accessibility.post (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.open -> Apps-Lillist-macOS-Sources-chunk-1.decide (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.open -> Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.parse -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.presentAttachmentPicker -> Packages-LillistUI-Sources-LillistUI-Editor.addImageAttachment (writes)`
- `Apps-Lillist-macOS-Sources-Hotkey.toggle -> Apps-Lillist-macOS-Sources-chunk-1.decide (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.toggle -> Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel (calls)`

## Type notes

GlobalHotkeyMonitor is @MainActor final class (Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:10); NSEvent callbacks re-enter the main actor via Task { @MainActor in } (Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:46). QuickCapturePanelController is @MainActor final class (Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:20); holds at most one NSPanel and one TaskEditorModel at a time — retarget replaces both in place rather than stacking. HotkeyRecorder.encode and all display helpers are nonisolated static func to avoid inheriting View's implicit @MainActor isolation, making them callable from tests without a main-actor context (Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift:160). HotkeyKeyTable and QuickCapturePlacementMath are caseless enums used as pure namespaces with no stored state and no actor isolation requirement.

## External deps

- AppKit — imported
- Foundation — imported
- LillistCore — imported
- LillistUI — imported
- Observation — imported
- SwiftUI — imported

## Gotchas

matchesHotkey intersects deviceIndependentFlagsMask to exclude caps-lock and numeric-pad sentinel bits from modifier comparison (Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:85). The panel sets hidesOnDeactivate=false with no resign-key observer so the status Menu's child popover (which resigns key) does not dismiss the panel mid-edit (Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:100). HotkeyRecorder.encode rejects combos with only Command as modifier to avoid shadowing system shortcuts such as Cmd+Q and Cmd+Space (Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift:163). QuickCapturePlacementMath is extracted to its own file so standalone test targets can compile placement math without pulling in AppEnvironment or SwiftUI (Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePlacementMath.swift:6).
