# LillistCore

The model + persistence + business-logic core of Lillist. Shared by every client (macOS app, iOS app, CLI).

## Plan 1 scope

Plan 1 establishes local-only persistence (`NSPersistentContainer`) with:

- `LillistTask` / `Tag` / `JournalEntry` / `Attachment` / `AppPreferences` entities
- `TaskStore`, `TagStore`, `JournalStore`, `AttachmentStore`, `PreferencesStore`
- Soft delete + Trash + `AutoPurgeJob`
- Cycle prevention for task and tag re-parenting
- Sibling-name uniqueness with auto-suffix collisions
- Fractional sibling ordering with `FractionalPosition` + `PositionCompactor`
- JSON + assets folder export via `Exporter`

Plan 2 swaps `NSPersistentContainer` for `NSPersistentCloudKitContainer`; no public-API changes.

## Build tool plugin

SwiftPM does not invoke Core Data's `momc` model compiler on `.xcdatamodeld`
resources, so the package ships a `CompileCoreDataModel` build tool plugin
that shells out to `xcrun momc`. The plugin runs automatically as part of
`swift build` / `swift test`; no extra setup needed.

The `.xcdatamodeld` entities are marked `codeGenerationType="manual/none"`
because we hand-write the `NSManagedObject` subclasses under
`Sources/LillistCore/ManagedObjects/` — SwiftPM doesn't run Core Data's
"Class Definition" codegen either, so opening the model in Xcode must not
re-generate them.

## Running tests

```bash
cd Packages/LillistCore
swift test
```

## Public API

All entry points return value-type `*Record` DTOs. No `NSManagedObject` escapes the package.
