---
module: Packages/LillistCore/Sources/LillistCore/Model
summary: "Domain vocabulary enums (Status, SortField, NotificationKind, etc.) and the Core Data schema (.xcdatamodeld)"
read_when: "Touching Core Data entities or domain enums"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Model/AttachmentKind.swift
    blob: 71c49cd3ddb11ee8616dfe2f26f48750b7f72d57
  - path: Packages/LillistCore/Sources/LillistCore/Model/JournalEntryKind.swift
    blob: 93d02c6c8bf56046428b4deeebcd3991b2e03bb5
  - path: Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/.xccurrentversion
    blob: 0b7ad51749d1fec30479832e5654dc4ab039a7bc
  - path: Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents
    blob: e4d6712d6a05a0184ea93acc19217b125927d8e9
  - path: Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift
    blob: 19eca0cca8609b9de59145cea207f200f95fbfad
  - path: Packages/LillistCore/Sources/LillistCore/Model/SortField.swift
    blob: 8813896cae4dfd955cc80e81553f4c68b1065893
  - path: Packages/LillistCore/Sources/LillistCore/Model/Status.swift
    blob: 2b474b3b3224e2f4963e5e230484a29ed438478e
references_modules: [Packages-LillistCore-Sources-LillistCore-Stores-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/Model

## Purpose

This module is the closed vocabulary of domain discriminators — Status, NotificationKind, AttachmentKind, JournalEntryKind, SortField — that every other layer uses to tag and branch on data, plus the Core Data schema (LillistModel.xcdatamodeld) that is the single source of truth for all entity shapes and CloudKit-sync relationships. These two responsibilities belong together because every entity in the schema maps to at least one enum here, and the Int16 or String column values in Core Data must match the enum raw values exactly. Without this module there is no canonical terminology: stores would invent conflicting type representations and cross-layer predicates would break.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Anchor` | enum | `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:22` | Returned by `NotificationKind.anchor`; .start and .deadline each map to a task date field; absence (nil anchor) means the notification carries its own absolute fire date. |
| `AttachmentKind` | enum | `Packages/LillistCore/Sources/LillistCore/Model/AttachmentKind.swift:3` | Raw Int persisted as Int16; three cases (image, file, linkPreview) govern which Attachment entity fields are populated — callers may switch exhaustively. |
| `JournalEntryKind` | enum | `Packages/LillistCore/Sources/LillistCore/Model/JournalEntryKind.swift:3` | Raw Int persisted as Int16; callers must check `isUserEditable` before mutating body — system-generated kinds (.statusChange, .createdFollowUp) reject edits. |
| `NotificationKind` | enum | `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:8` | Raw Int persisted as Int16; `anchor` property is the canonical mapping to task date field; raw values are stable — never reorder or remove cases. |
| `SortField` | enum | `Packages/LillistCore/Sources/LillistCore/Model/SortField.swift:9` | String-backed; `manualPosition` is only valid for single-parent lists — store layer rejects it with LillistError.validationFailed for cross-parent queries. |
| `Status` | enum | `Packages/LillistCore/Sources/LillistCore/Model/Status.swift:7` | Raw Int persisted as Int16; `isClosed` is the canonical terminal-state test; raw values are stable — never reorder or remove cases. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Model.JournalEntryKind -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.entries (calls)`

## Type notes

All five enums conform to `Codable` and `Sendable` with either `Int` or `String` raw values, making them safe to cross actor boundaries and serialize without wrappers. `Status` and `NotificationKind` persist as `Int16` in Core Data (Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents:7 and :97); `SortField` persists as a `String` attribute (contents:68,81) — the raw-value backing type is part of the schema contract and must not change. `JournalEntryKind.isUserEditable` (Packages/LillistCore/Sources/LillistCore/Model/JournalEntryKind.swift:11-18) is the only computed property in this module that guards a behavioral invariant; JournalStore enforces it before any write. `NotificationKind.Anchor` is a nested enum (Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:22-25) with no stored state — it exists solely as a named discriminator returned by `NotificationKind.anchor`. All entities in the xcdatamodel have `usedWithCloudKit="YES"` and all attributes are optional, satisfying CloudKit's mirrored-store constraint (contents:2).

## External deps

- Foundation — imported

## Gotchas

Persisted raw values must never be reordered or removed: `NotificationKind` (Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:5) and `Status` (Packages/LillistCore/Sources/LillistCore/Model/Status.swift:3) each carry an explicit doc-comment warning — new cases must take an unused raw value. `SortField.manualPosition` (Packages/LillistCore/Sources/LillistCore/Model/SortField.swift:5-7) is silently invalid for cross-parent queries; the store layer enforces this by throwing `LillistError.validationFailed`, but nothing in this module signals the restriction at the call site.
