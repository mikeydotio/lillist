---
module: Extensions/ShareExtension-iOS
summary: iOS Share Extension — captures URLs and text from other apps into a new Lillist task via the shared App Group store
read_when: Touching share-sheet capture, extension lifecycle, or App-Group task creation
sources:
  - path: Extensions/ShareExtension-iOS/Info.plist
  - path: Extensions/ShareExtension-iOS/Lillist.entitlements
  - path: Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy
  - path: Extensions/ShareExtension-iOS/SharePayload.swift
  - path: Extensions/ShareExtension-iOS/ShareRootView.swift
  - path: Extensions/ShareExtension-iOS/ShareSaveFlow.swift
  - path: Extensions/ShareExtension-iOS/ShareViewController.swift
references_modules:
  - Packages-LillistCore-Sources-LillistCore-Stores-chunk-2
  - Packages-LillistCore-Sources-LillistCore-Stores-chunk-1
  - Packages-LillistCore-Sources-LillistCore-Persistence
  - Packages-LillistCore-Sources-LillistCore-Diagnostics
  - Packages-LillistCore-Sources-LillistCore-misc
  - Packages-LillistCore-Sources-LillistCore-LinkPreview
  - Packages-LillistUI-Sources-LillistUI-Theme-chunk-1
generator: cartographer/1 model=claude-sonnet-4-6
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
- `Extensions-ShareExtension-iOS.ShareRootView.save -> Packages-LillistCore-Sources-LillistCore-Persistence.GatedPersistenceResolver (calls)`
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
test-injected items — into one `decode()` (`Extensions/ShareExtension-iOS/SharePayload.swift:41`).
`init(extensionContext:)` only **captures** matching providers; the data is
loaded later via the async `loadItem` overload, because the synchronous form
returns `Void` and silently drops the payload (`Extensions/ShareExtension-iOS/SharePayload.swift:11`).
`ShareRootView.savedTaskID` is the retry latch: set once a task is created so a
re-save after a failed link attachment reuses it instead of duplicating
(`Extensions/ShareExtension-iOS/ShareRootView.swift:22`). The `create` call passes `placement: .top` so
shared tasks land at the top of the inbox rather than the bottom
(`Extensions/ShareExtension-iOS/ShareRootView.swift:118`). Writes are stamped with
`PersistenceController.shareExtensionTransactionAuthor` so the main app's
diagnostics observer attributes extension-authored rows
(`Extensions/ShareExtension-iOS/ShareRootView.swift:86`).

## External deps

- UIKit — `ShareViewController` subclasses `UIViewController`; `UIHostingController` hosts the SwiftUI root
- SwiftUI — `ShareRootView` is the capture sheet (`NavigationStack` + `Form`)
- UniformTypeIdentifiers — `UTType.url` / `UTType.plainText` gate which providers are captured
- Foundation — `NSItemProvider`, `NSExtensionContext`, `NSError` for system payload + dismissal

## Gotchas

- `NSExtensionActivationRule` only fires on text + web URL/page (max 1 each), set in `Extensions/ShareExtension-iOS/Info.plist:27`.
- A private/loopback/non-http(s) URL is rejected before persistence by the SSRF gate at `Extensions/ShareExtension-iOS/ShareRootView.swift:104`.
- Link-attachment failure keeps the sheet open and surfaces the error rather than swallowing it (`Extensions/ShareExtension-iOS/ShareRootView.swift:124`).
