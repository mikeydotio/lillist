# Lillist — Project Conventions

Repo-scoped notes for Claude Code (and humans).
User-global rules live in `~/.claude/CLAUDE.md`; this file only adds Lillist-specific guidance.

## Project shape

- **What it is:** A task manager for macOS + iOS, with a CLI, CloudKit sync, a
  predicate-driven smart-filter engine, recurrence, notifications, and crash
  reporting. Apple-platform-only (Swift 6, SwiftUI, Core Data,
  `NSPersistentCloudKitContainer`).
- **Topology:**
  - `Packages/LillistCore/` — the SPM package that owns the data model, stores,
    sync, rules engine, notifications, and recurrence. Most plans land code here.
  - `Packages/LillistUI/` — SwiftUI components (lands in Plan 7).
  - macOS app target, iOS app target, and `lillist` CLI target (land in Plans
    6/7/8 — not yet present).
- **Build/test:** From `Packages/LillistCore`, use `swift build` and
  `swift test`. The package uses `-enable-experimental-feature StrictConcurrency`
  on the source target.

## Plans live in `docs/superpowers/plans/`

Numbered Plans 1–10. Always check what plan numbering refers to before
acting — slugs in filenames are descriptive (`recurrence`, `cli`, `ios-app`),
but the *number* in the title is the canonical reference. Plans completed so
far (in order on `main`): 1, 2, 3, 4. Plans 5–10 pending.

The design doc is `docs/plans/2026-05-12-lillist-design.md`. Plans reference
section numbers from it.

## House rules specific to this repo

- **Maintain high quality standards** Follow software engineering best practices, 
  including SOLID, DRY, YAGNI, and separation of concerns. Treat build warnings as errors.
  Do not seek to merely resolve or work around warnings and errors; instead, strive to write well-architected software that doesn't have any.
- **Hand-written `@NSManaged` subclasses.** Every Core Data entity has a
  hand-written `@objc(Name) public final class Name: NSManagedObject { @NSManaged … }`
  in `Packages/LillistCore/Sources/LillistCore/ManagedObjects/`. Don't rely on
  Core Data class codegen — Plans 1, 3, 4 all wrote the classes by hand. Plans
  5, 9, 10 still need this correction folded into their model-edit tasks (the
  plan documents have been patched; the convention is documented here for
  future plan authors).
- **Build-plugin caching gotcha.** SwiftPM's `CompileCoreDataModel` plugin
  keys on the `.xcdatamodeld` directory's mtime, not on the inner
  `LillistModel.xcdatamodel/contents` file. After editing `contents`, the old
  `.momd` is reused and the new entities/attributes are invisible at runtime
  — tests crash with `NSInvalidArgumentException: must have a valid
  NSEntityDescription`. Touch the model dirs to force a rebuild:
  ```bash
  touch Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/ \
        Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/
  ```
- **Strict concurrency is on for the source target.** The test target is not
  strict, so concurrency bugs surface at runtime, not compile time. Don't
  treat a clean test build as proof of correctness; add stress repetitions
  for any code that crosses actor boundaries.
- **Date math through `Calendar`, not `Date.addingTimeInterval`.** Plan 4's
  `RecurrenceExpander` is the canonical example: DST and month-length
  correctness require `Calendar.date(byAdding:)` and `DateComponents` round
  trips. The only `addingTimeInterval` usage in the recurrence engine is the
  `afterCompletion` rule, which is *defined* in absolute seconds.
- **No `NSManagedObject` escapes `LillistCore`.** All public store APIs
  return value-type DTOs (`TaskStore.TaskRecord`, `SeriesStore.SeriesRecord`,
  etc.). Tests and downstream layers never see Core Data types.

## Engineering lessons live in `docs/engineering-notes.md`

When a non-obvious gotcha gets identified during work — particularly a
concurrency or framework-shape issue that future-you would otherwise rediscover
the hard way — record it in `docs/engineering-notes.md` as a short entry. The
file is an append-only log keyed by date.

Examples of lessons that belong there: "Task.yield() is not a happens-before
barrier"; "same-actor `Task { method() }` is almost always wrong"; etc.

Examples that don't: bug fix details (commit message has those), specific code
patterns (the code itself shows those), feature decisions (the design doc
captures those).

## Git workflow

- Branch off `main`, PR back to `main`. The user (mikeyward) reviews and
  merges. Repo lives under the `mikeydotio` GitHub org.
- Plans land as a series of small commits — usually one per plan task —
  using conventional-commit prefixes (`feat:`, `test:`, `fix:`, `chore:`,
  `docs:`, `refactor:`). See git log for the established style.
- Push over HTTPS, never SSH (the user's SSH agent requires interactive
  approval). User's global gitconfig already maps `git@github.com:` to HTTPS.
- Never force-push without explicit confirmation.

## When in doubt

- Read the relevant plan in `docs/superpowers/plans/`.
- Read the relevant section of the design doc at
  `docs/plans/2026-05-12-lillist-design.md`.
- Check `docs/engineering-notes.md` for a known gotcha.
- Then ask.
