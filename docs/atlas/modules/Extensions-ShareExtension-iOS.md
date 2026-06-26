---
module: Extensions/ShareExtension-iOS
summary: "iOS Share Extension that captures shared URLs/text as Lillist tasks via the App-Group-shared Core Data store."
read_when: "Touching share-sheet capture"
sources:
  - path: Extensions/ShareExtension-iOS/Info.plist
    blob: f885a87ce9624ba57ef98526bfb380bf1d46b44a
  - path: Extensions/ShareExtension-iOS/Lillist.entitlements
    blob: c8ba24245a40abbf2f019ee0f30fad76a2e22056
  - path: Extensions/ShareExtension-iOS/PrivacyInfo.xcprivacy
    blob: 4e7e051bbe5e2753a0a80b85ae78289d250bdce7
  - path: Extensions/ShareExtension-iOS/SharePayload.swift
    blob: 1cc6f7b55a70113401f7d165c563a00347e31c9d
  - path: Extensions/ShareExtension-iOS/ShareRootView.swift
    blob: cc1124e3f8509f6a4df90f057b6cca3a59209594
  - path: Extensions/ShareExtension-iOS/ShareSaveFlow.swift
    blob: e76d10124e5f2b6565471213778516cb7892e9cf
  - path: Extensions/ShareExtension-iOS/ShareViewController.swift
    blob: 712caf797a5dacd46b7a90f3827a5951e8bd98e4
references_modules: [Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Reminders, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Extensions/ShareExtension-iOS

## Purpose

The Share Extension is Lillist's iOS share-sheet capture surface: it receives URLs and plain text forwarded from other apps, decodes the payload into a pre-filled form, and writes the resulting task (with optional link-preview attachment) into the App-Group-shared Core Data store so the main app sees it on next foreground. The module is self-contained — UIKit entry, SwiftUI form, payload decoder, and retry-state machine — and intentionally isolated from the main app target so it can be signed and launched as a separate process. Without it, Lillist cannot receive content from the system share sheet.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Decoded` | struct | `Extensions/ShareExtension-iOS/SharePayload.swift:31` | Equatable value type; carries the decoded suggestedTitle, optional notes, and optional URL extracted from the extension context payload. |
| `Item` | enum | `Extensions/ShareExtension-iOS/SharePayload.swift:26` | Equatable discriminated union of the two accepted input types: .text(String) for plain text and .url(URL) for URLs. |
| `SharePayload` | struct | `Extensions/ShareExtension-iOS/SharePayload.swift:25` | Wraps raw NSItemProviders from the extension context; callers invoke decode() to get a Decoded; production uses init(extensionContext:), tests bypass async I/O via makeStub(items:). |
| `ShareRootView` | struct | `Extensions/ShareExtension-iOS/ShareRootView.swift:9` | Stateful SwiftUI sheet; pre-fills from SharePayload, validates the URL via URLPreviewPolicy, creates a task via TaskStore through GatedPersistenceResolver, and calls onSaved or onCancel to drive extension dismissal. |
| `ShareSaveFlow` | enum | `Extensions/ShareExtension-iOS/ShareSaveFlow.swift:12` | Namespace for the retry-state decision helper; callers use only ShareSaveFlow.next(savedTaskID:hasURL:) — the enum itself has no cases. |
| `ShareViewController` | class | `Extensions/ShareExtension-iOS/ShareViewController.swift:8` | UIKit root of the extension process; registers fonts, instantiates SharePayload from extensionContext, embeds ShareRootView in a UIHostingController, and bridges cancel/save back through NSExtensionContext. |
| `Step` | enum | `Extensions/ShareExtension-iOS/ShareSaveFlow.swift:14` | Equatable enum with two cases: .createTask(attachLink:) when no prior attempt exists, or .attachLinkOnly(taskID:) when the task was already created and only the attachment must be retried. |
| `decode` | func | `Extensions/ShareExtension-iOS/SharePayload.swift:70` | Async; resolves providers into items and returns Decoded with title capped at 80 chars, any overflow text as notes, and the URL if present; never throws — decoding errors silently yield an empty Decoded. |
| `makeStub` | func | `Extensions/ShareExtension-iOS/SharePayload.swift:66` | Returns a SharePayload pre-loaded with caller-supplied Item values; no async I/O occurs — use in tests to skip NSItemProvider loading entirely. |
| `next` | func | `Extensions/ShareExtension-iOS/ShareSaveFlow.swift:25` | Pure function; returns .createTask when savedTaskID is nil, .attachLinkOnly with the existing ID otherwise; no side effects, fully unit-testable without the signed extension target. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `cancel` | func | `Extensions/ShareExtension-iOS/ShareViewController.swift:34` | Routes the cancel action through NSExtensionContext.cancelRequest so the system properly dismisses the extension; without it the extension would hang open after the user taps Cancel (Extensions/ShareExtension-iOS/ShareViewController.swift:34-38). |
| `complete` | func | `Extensions/ShareExtension-iOS/ShareViewController.swift:40` | Routes successful save through NSExtensionContext.completeRequest; required for the system to dismiss the extension after a task is saved (Extensions/ShareExtension-iOS/ShareViewController.swift:40-43). |
| `load` | func | `Extensions/ShareExtension-iOS/ShareRootView.swift:61` | Drives the async payload decode that pre-fills the form fields at sheet presentation; without it the form always shows empty fields regardless of what was shared (Extensions/ShareExtension-iOS/ShareRootView.swift:61-66). |
| `save` | func | `Extensions/ShareExtension-iOS/ShareRootView.swift:68` | The single path that opens the App Group store via GatedPersistenceResolver, enforces the SSRF URL policy, runs the create-vs-reuse branch via ShareSaveFlow, persists the task and optional link attachment, and signals completion or surfaces errors — the entire write side of the extension (Extensions/ShareExtension-iOS/ShareRootView.swift:68-143). |

## Relationships

- `Extensions-ShareExtension-iOS.ShareViewController -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.registerIfNeeded (calls)`
- `Extensions-ShareExtension-iOS.Step -> Packages-LillistCore-Sources-LillistCore-Reminders.createTask (calls)`
- `Extensions-ShareExtension-iOS.decode -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Extensions-ShareExtension-iOS.next -> Packages-LillistCore-Sources-LillistCore-Reminders.createTask (calls)`
- `Extensions-ShareExtension-iOS.save -> Packages-LillistCore-Sources-LillistCore-Diagnostics.shared (reads)`
- `Extensions-ShareExtension-iOS.save -> Packages-LillistCore-Sources-LillistCore-LinkPreview.isAllowed (reads)`
- `Extensions-ShareExtension-iOS.save -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore (calls)`
- `Extensions-ShareExtension-iOS.save -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.addLinkPreview (writes)`
- `Extensions-ShareExtension-iOS.save -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.GatedPersistenceResolver (reads)`
- `Extensions-ShareExtension-iOS.save -> Packages-LillistCore-Sources-LillistCore-misc.DevicePreferencesStore (reads)`
- `Extensions-ShareExtension-iOS.save -> Packages-LillistCore-Sources-LillistCore-misc.diagnosticLoggingEnabled (reads)`

## Type notes

SharePayload is @unchecked Sendable because NSItemProvider is not yet formally Sendable in this SDK; the struct is constructed on the main actor in ShareViewController.viewDidLoad and then sent into the async decode() pipeline — all stored values are read-only after construction (Extensions/ShareExtension-iOS/SharePayload.swift:18-25). The extension runs in its own process, so LillistFonts.registerIfNeeded() must be called explicitly in viewDidLoad to register Plus Jakarta Sans before any SwiftUI view renders (Extensions/ShareExtension-iOS/ShareViewController.swift:13-14). ShareRootView holds @State private var savedTaskID: UUID? to track whether a prior save attempt already created the task; on retry ShareSaveFlow.next returns .attachLinkOnly to reuse that ID rather than creating a second task (Extensions/ShareExtension-iOS/ShareRootView.swift:19-22, Extensions/ShareExtension-iOS/ShareSaveFlow.swift:25-30). All store access routes through GatedPersistenceResolver(appGroupID: "group.app.lillist"), which throws LillistError.storeUnavailable if a migration is in flight; save() surfaces that message and leaves the sheet open for retry (Extensions/ShareExtension-iOS/ShareRootView.swift:74-88).

## External deps

- Foundation — imported
- LillistCore — imported
- LillistUI — imported
- SwiftUI — imported
- UIKit — imported
- UniformTypeIdentifiers — imported

## Gotchas

The synchronous, closure-less form of NSItemProvider.loadItem returns Void and silently drops the data; SharePayload must use the async overload (Extensions/ShareExtension-iOS/SharePayload.swift:12-16). Link-attachment failures surface an error but leave the task already saved in the store; ShareSaveFlow.next returns .attachLinkOnly on retry to prevent creating a duplicate task (Extensions/ShareExtension-iOS/ShareSaveFlow.swift:8-11, Extensions/ShareExtension-iOS/ShareRootView.swift:116-122). SharePayload carries @unchecked Sendable because NSItemProvider lacks formal Sendable conformance in this SDK; the safety is vouched at the struct level since all stored values are read-only after construction (Extensions/ShareExtension-iOS/SharePayload.swift:22-24).
