---
module: Extensions/ShareExtension-iOS
summary: "iOS share-sheet extension that captures shared text/URLs into a task via the App-Group store"
read_when: iOS Share Extension capture
sources:
  - path: Extensions/ShareExtension-iOS/Info.plist
    blob: 71d0dc72cdff29eb19d3eeb77caf214255b3b5c3
  - path: Extensions/ShareExtension-iOS/Lillist.entitlements
    blob: dc82d6a78df2d35115ff154e8888e3d7e0ef3469
  - path: Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy
    blob: 4e7e051bbe5e2753a0a80b85ae78289d250bdce7
  - path: Extensions/ShareExtension-iOS/SharePayload.swift
    blob: 1cc6f7b55a70113401f7d165c563a00347e31c9d
  - path: Extensions/ShareExtension-iOS/ShareRootView.swift
    blob: 81f5afdb40d9a2b94bffd08b8422136237b9fd6d
  - path: Extensions/ShareExtension-iOS/ShareSaveFlow.swift
    blob: e76d10124e5f2b6565471213778516cb7892e9cf
  - path: Extensions/ShareExtension-iOS/ShareViewController.swift
    blob: 824f5b49a323d6341a59dcd07922257f22a02a13
references_modules: [Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Extensions/ShareExtension-iOS

## Purpose

The iOS share-sheet target: when a user taps "Add to Lillist" from another app,
this extension turns the inbound text/URL into a task written to the
App-Group-shared Core Data store, so the main app sees it on next foreground.
It runs as its own process, so it independently registers fonts, stamps a
distinct Core Data author, and resolves the gated persistence container. The
create-then-attach retry semantics are factored out into a pure helper precisely
because the signed extension target cannot be `@testable import`ed.

## Public API

This is an app-extension target with no exported library surface; the only
externally referenced symbol is the principal class named in `Info.plist`.

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `ShareViewController` | class | `Extensions/ShareExtension-iOS/ShareViewController.swift:8` | `NSExtensionPrincipalClass`; UIKit entry point hosting the SwiftUI sheet |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `SharePayload` | struct | `Extensions/ShareExtension-iOS/SharePayload.swift:25` | Captures inbound `NSItemProvider`s; `@unchecked Sendable` bridge into async decode |
| `SharePayload.decode` | func | `Extensions/ShareExtension-iOS/SharePayload.swift:70` | Async; resolves providers into a `Decoded` title/notes/url for prefill |
| `ShareRootView` | struct | `Extensions/ShareExtension-iOS/ShareRootView.swift:9` | The save sheet; owns the persistence-resolve + create-and-attach flow |
| `ShareRootView.save` | func | `Extensions/ShareExtension-iOS/ShareRootView.swift:68` | Resolves the gated store, gates the URL, then creates task + attaches link |
| `ShareSaveFlow` | enum | `Extensions/ShareExtension-iOS/ShareSaveFlow.swift:12` | Pure create-vs-reuse decision, unit-testable apart from the signed target |
| `ShareSaveFlow.next` | func | `Extensions/ShareExtension-iOS/ShareSaveFlow.swift:25` | Returns `createTask` or `attachLinkOnly` so a retry never duplicates a task |

## Relationships

- `Extensions-ShareExtension-iOS.ShareViewController -> Extensions-ShareExtension-iOS.SharePayload (calls)`
- `Extensions-ShareExtension-iOS.ShareViewController -> Extensions-ShareExtension-iOS.ShareRootView (owns)`
- `Extensions-ShareExtension-iOS.ShareViewController -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.LillistFonts (calls)`
- `Extensions-ShareExtension-iOS.ShareRootView.save -> Extensions-ShareExtension-iOS.ShareSaveFlow (calls)`
- `Extensions-ShareExtension-iOS.ShareRootView.save -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.GatedPersistenceResolver (calls)`
- `Extensions-ShareExtension-iOS.ShareRootView.save -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (reads)`
- `Extensions-ShareExtension-iOS.ShareRootView.save -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Extensions-ShareExtension-iOS.ShareRootView.save -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore (calls)`
- `Extensions-ShareExtension-iOS.ShareRootView.save -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticLog (calls)`
- `Extensions-ShareExtension-iOS.ShareRootView.save -> Packages-LillistCore-Sources-LillistCore-misc.DevicePreferencesStore (reads)`
- `Extensions-ShareExtension-iOS.ShareRootView.save -> Packages-LillistCore-Sources-LillistCore-LinkPreview.URLPreviewPolicy (calls)`
- `Extensions-ShareExtension-iOS.ShareRootView.save -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (reads)`
- `Extensions-ShareExtension-iOS.ShareRootView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowPalette (reads)`

## Type notes

`SharePayload` is `@unchecked Sendable`: it is built on the main actor in
`ShareViewController.viewDidLoad` then sent into `ShareRootView`'s async
`decode()` pipeline; the unchecked vouch covers the not-yet-`Sendable`
`NSItemProvider` (`Extensions/ShareExtension-iOS/SharePayload.swift:18`). Its
private `Source` enum funnels two construction paths — production providers and
test-injected items — into one `decode()` (`SharePayload.swift:41`).
`init(extensionContext:)` only **captures** matching providers; the data is
loaded later via the async `loadItem` overload, because the synchronous form
returns `Void` and silently drops the payload (`SharePayload.swift:11`).
`ShareRootView.savedTaskID` is the retry latch: set once a task is created so a
re-save after a failed link attachment reuses it instead of duplicating
(`ShareRootView.swift:22`). Writes are stamped with
`PersistenceController.shareExtensionTransactionAuthor` so the main app's
diagnostics observer attributes extension-authored rows
(`ShareRootView.swift:86`).

## External deps

- UIKit — `ShareViewController` subclasses `UIViewController`; `UIHostingController` hosts the SwiftUI root
- SwiftUI — `ShareRootView` is the capture sheet (`NavigationStack` + `Form`)
- UniformTypeIdentifiers — `UTType.url` / `UTType.plainText` gate which providers are captured
- Foundation — `NSItemProvider`, `NSExtensionContext`, `NSError` for system payload + dismissal

## Gotchas

- `NSExtensionActivationRule` only fires on text + web URL/page (max 1 each), set in `Extensions/ShareExtension-iOS/Info.plist:27`.
- A private/loopback/non-http(s) URL is rejected before persistence by the SSRF gate at `Extensions/ShareExtension-iOS/ShareRootView.swift:104`.
- Link-attachment failure keeps the sheet open and surfaces the error rather than swallowing it (`Extensions/ShareExtension-iOS/ShareRootView.swift:124`).
