---
module: Apps/Lillist-macOS/Sources/Hotkey
summary: "Global hotkey monitor, Quick Capture panel controller, hotkey recorder UI, and placement math for macOS"
read_when: "Touching the macOS global hotkey"
sources:
  - path: Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift
    blob: aabfdf309ae61b86c6315570445b023b79f9dfca
  - path: Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift
    blob: 3d177e8680a0aee5d6228b0b090193f1d50571d5
  - path: Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift
    blob: f62390a36a429269bee13dc122ad58d397fe4b49
  - path: Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift
    blob: 88cf1b1b08f3f31ab6b652a0fe12febcab8ca796
  - path: Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePlacementMath.swift
    blob: e38650e29d0abcec51fa15a17dc25951b981d8ae
references_modules: [Packages-LillistUI-Sources-LillistUI-Editor, Apps-Lillist-macOS-Sources-misc, Apps-Lillist-macOS-Sources-Preferences]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Apps/Lillist-macOS/Sources/Hotkey

## Purpose

Owns the macOS Quick Capture trigger end-to-end: a system-wide `NSEvent` hotkey monitor, the canonical combo string codec shared with the preferences recorder, and the floating non-activating `NSPanel` that hosts `TaskEditorView`. The design idea is one canonical combo string (`"ctrl+opt+space"`) round-tripped through a single key table so the matcher, the encoder, and the preferences UI never diverge. Without this module the macOS app loses both its global capture affordance and its inline task-editor panel.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `GlobalHotkeyMonitor` | class | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:11` | `@MainActor`; arm with `install()`, disarm with `uninstall()`; set `onHotkey` before installing |
| `GlobalHotkeyMonitor.defaultCombo` | static let | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:15` | Canonical default `"ctrl+opt+space"`; mirrors `PreferencesStore` default |
| `GlobalHotkeyMonitor.reregister(combo:)` | func | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:73` | Hot-swaps the armed combo at runtime; silently ignores unparseable strings; idempotent |
| `GlobalHotkeyMonitor.parse(combo:)` | static func | `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:101` | Pure inverse of `HotkeyRecorder.encode`; order-tolerant; returns `nil` for malformed or unknown tokens |
| `HotkeyKeyTable` | enum | `Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift:13` | Namespace; single source of truth for keyCode ↔ canonical-name mapping |
| `HotkeyRecorder` | struct | `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift:14` | SwiftUI `View`; captures one keystroke into a `@Binding<String>`; hosts a local `NSEvent` monitor only while recording |
| `HotkeyRecorder.encode(modifiers:keyCode:)` | static func | `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift:157` | Pure `nonisolated` encoder; rejects bare-⌘ and no-modifier combos; returns canonical `"ctrl+opt+…+key"` string or `nil` |
| `QuickCapturePanelController` | class | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:21` | `@MainActor` singleton-style; owns floating `NSPanel` lifecycle; call `toggle()` from hotkey, `open(taskID:)` from row click |
| `QuickCapturePanelController.toggle()` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:49` | Opens a new-capture draft if closed; no-op if panel already visible |
| `QuickCapturePanelController.open(taskID:)` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:62` | Opens an existing task in full mode; re-targets panel in-place rather than stacking a second |
| `QuickCapturePanelController.close(cancelled:)` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:194` | Tears down panel; `cancelled: true` discards a capture draft before dismissing |
| `QuickCapturePlacementMath` | enum | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePlacementMath.swift:7` | Pure-math namespace; no stored state; isolated to allow test-bundle co-compilation without `AppEnvironment` |
| `QuickCapturePlacementMath.placementOrigin(screenFrame:visibleFrame:panelSize:)` | static func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePlacementMath.swift:16` | Centers panel horizontally; places top edge ~1/3 down from visible area top; AppKit bottom-left coords |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `HotkeyKeyTable.entries` | static let | `Apps/Lillist-macOS/Sources/Hotkey/HotkeyKeyTable.swift:28` | Master table that drives both `codeToName` and `nameToCode`; the only place to add or rename a bindable key |
| `QuickCapturePanelController.observeMode()` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:135` | Re-arming `withObservationTracking` loop; fires `resizeForMode` on every `TaskEditorModel.mode` flip; must re-arm itself or subsequent mode changes are silently dropped |
| `QuickCapturePanelController.resizeForMode(animated:)` | func | `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:148` | Pins top edge while growing panel downward (quick→full); respects `accessibilityDisplayShouldReduceMotion` |

## Relationships

- `Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePanelController -> Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView (owns)` — `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:121` hosts `TaskEditorView` inside the panel's `NSHostingController`
- `Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePanelController -> Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel (owns)` — `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:24` holds the model and constructs it at lines 54, 66, 70
- `Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePanelController -> Apps-Lillist-macOS-Sources-misc.EditorOpenDecision (calls)` — `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:50,63` calls `EditorOpenDecision.decide` to route toggle/open decisions
- `Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePanelController -> Apps-Lillist-macOS-Sources-misc.AppEnvironment (reads)` — `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:25,35-40` holds and reads all store references from `AppEnvironment`
- `Apps-Lillist-macOS-Sources-Preferences.QuickCapturePane -> Apps-Lillist-macOS-Sources-Hotkey.HotkeyRecorder (calls)` — grounded by grep: `Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift` references `HotkeyRecorder`

## Type notes

`GlobalHotkeyMonitor` caches parsed modifier flags and key code at install/reregister time so `matchesHotkey` is a pure equality check on every `keyDown` event with no re-parsing. Both global and local monitors are installed together; the local monitor swallows the event (returns `nil`) so the host app does not also handle it. `HotkeyRecorder` installs its own separate local monitor only during recording mode and swallows just the captured event, then immediately stops — it does not interfere with `GlobalHotkeyMonitor`. `QuickCapturePanelController` is effectively a singleton (one panel at a time enforced by `EditorOpenDecision`). Closing the panel posts `lillistTasksDidChange` unconditionally so list views refresh without a separate Core Data observer (`Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:207`). The panel is configured `.nonactivatingPanel` and never calls `NSApp.activate`, so it floats over other apps without stealing focus.

## External deps

- AppKit — `NSPanel`, `NSEvent` global/local monitors, `NSHostingController`, `NSScreen`, `NSOpenPanel`
- SwiftUI — `View`, `@Binding`, `NSHostingController` root view
- Observation — `withObservationTracking` used in `observeMode` to watch `TaskEditorModel.mode` without Combine

## Gotchas

- `HotkeyRecorder.encode` rejects combos whose only modifier is `⌘` to avoid shadowing system shortcuts (⌘Q, ⌘W, ⌘Space); the recording loop should keep listening until a valid combo arrives — `Apps/Lillist-macOS/Sources/Hotkey/HotkeyRecorder.swift:163–167`
- `observeMode` must re-arm itself inside the `onChange` closure; `withObservationTracking` fires exactly once per observation — `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:141–143`
- The panel does NOT dismiss on resign-key: the status `Menu` opens a child popover that resigns key, and that must not close the editor — `Apps/Lillist-macOS/Sources/Hotkey/QuickCapturePanelController.swift:17–19`
- `parse` is order-tolerant on read although `encode` emits a fixed `ctrl,opt,cmd,shift` order, so hand-edited preferences still round-trip — `Apps/Lillist-macOS/Sources/Hotkey/GlobalHotkeyMonitor.swift:97–99`
