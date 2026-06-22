# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [v0.8.7] - 2026-06-21

### Fixed
- pin MARKETING_VERSION to 0.8.6; drop sandbox-incompatible stamp phase (ee4a32d)

### Changed
- restore original Tasks toolbar chip size (308a605)

### Maintenance
- auto-sync MARKETING_VERSION with semver via pre-bump hook (cd640e4)
- bump iOS build number to 58 (1db01eb)

_[force]_

## [v0.8.6] - 2026-06-20

### Added
- shrink Tasks top-of-list toolbar chips ~30% (e74b497)

### Maintenance
- stamp marketing version from semver VERSION at build time (5459b9b)
- bump iOS build number to 57 (e4f8106)

_[force]_

## [v0.8.5] - 2026-06-19

### Fixed
- single rainbow-bordered ghost, clean lift, deduped indicator, parent cue (d15f167)

### Maintenance
- bump iOS build number to 56 (4c7b0c3)

_[manual]_

## [v0.8.4] - 2026-06-19

### Fixed
- shrink-wrap ghost, align indicator to landing edge + current gap (a6892e7)

### Maintenance
- bump iOS build number to 55 (f18cfcd)

_[manual]_

## [v0.8.3] - 2026-06-19

### Added
- gap+horizontal-depth reorder with de-parenting (3996ae9)
- thread an explicit parent through TaskStore.reorder (8d07037)

### Documentation
- record drag-reorder gap/depth model (19b5a02)

### Maintenance
- bump iOS build number to 54 (703abcb)

_[manual]_

## [v0.8.2] - 2026-06-19

### Added
- add trailing Delete swipe on task rows (e507f76)

### Maintenance
- bump iOS build number to 53 (25d166d)

_[force]_

## [v0.8.1] - 2026-06-18

### Added
- add trackpad swipe-to-reset on task rows (fc9c96b)
- make status-control cycling one-way (open → in-progress → done) (fa7fdd6)

### Maintenance
- bump iOS build number to 52 (9bf92ac)

_[manual]_

## [v0.8.0] - 2026-06-18

### Added
- group Settings into icon-row sub-pages (69e6d39)
- add full data-store reset for debugging (caccf93)

### Documentation
- note the destructive debug data-store reset (a30cd21)

### Maintenance
- bump iOS build number to 51 (8f4f991)

_[manual]_

## [v0.7.0] - 2026-06-17

### Added
- row-style title header, collapsible journal, leaner activity (a42698a)

### Fixed
- restore task-row swipe actions via a custom gesture (79524c2)

### Changed
- stop auto-creating default notifications (8f7a5d6)

### Documentation
- record no-default-notifications + custom-swipe decisions (f2d6d80)

### Testing
- rebaseline DragReorder snapshots (stale since 9f37a24) (cb66086)

### Maintenance
- bump iOS build number to 50 (a9369df)

_[manual]_

## [v0.6.1] - 2026-06-17

### Fixed
- restore long-press-to-reorder on task rows (d762a96)

### Documentation
- full codebase map (58 modules) (75fb608)
- checkpoint — overview (8c52c45)
- checkpoint — verified docs (3 regenerated) (4234727)
- checkpoint — module docs wave 8 (all 58) (1a1562b)
- checkpoint — module docs wave 7 (d59010b)
- checkpoint — module docs wave 6 (7ddc69e)
- checkpoint — module docs wave 5 (f243d59)
- checkpoint — module docs wave 4 (7100e2e)
- checkpoint — module docs wave 3 (0c9f79c)
- checkpoint — module docs wave 2 (8beac75)
- checkpoint — module docs wave 1 (9553b23)
- checkpoint — orphan removal + module-id corrections (34dfea7)
- checkpoint — module docs wave 8 (all 58) (8368a0d)
- checkpoint — module docs wave 7 (ad8b1a3)
- checkpoint — module docs wave 6 (259cfd7)
- checkpoint — module docs wave 5 (b6e6936)
- checkpoint — module docs wave 4 (dc2cdba)
- checkpoint — module docs wave 3 (39c56d4)
- checkpoint — module docs wave 2 (a859ee1)
- checkpoint — module docs wave 1 (8745b6c)

### Maintenance
- mark docs/atlas as linguist-generated to collapse map diffs (028aa1b)
- bump iOS build number to 49 (a8f7bfc)

_[force]_

## [v0.6.0] - 2026-06-17

### Added
- localization sync + iOS discard-undo toast (Wave 5) (8cac861)
- macOS hosting + retire detail column (Wave 4) (e3fd38d)
- iOS hosting + retire pushed detail (Wave 3) (0c2761e)
- shared TaskEditorView + tag/reminder editors (Wave 2) (2c7c5a9)
- TaskEditorModel state machine + auto-promote (Wave 1) (2169193)

### Maintenance
- bump iOS build number to 48 (7cab4b6)

_[manual]_

## [v0.5.3] - 2026-06-17

### Documentation
- update map (10 docs — new-task top-insert + FAB glass) (50a41fd)

### Maintenance
- bump iOS build number to 47 (4cc3bb2)

_[force]_

## [v0.5.2] - 2026-06-16

### Fixed
- insert new tasks at top, show them immediately, unify FAB glass (1e47172)

### Maintenance
- bump iOS build number to 46 (6f8f3ae)

_[manual]_

## [v0.5.1] - 2026-06-16

### Added
- Sparkle auto-update (85a4dc8)

### Documentation
- finalize source-scope codebase map (61 modules + overview) (b03c50f)

### Maintenance
- bump CFBundleVersion to 20260517 (d5a9111)
- checkpoint — 61 module docs + ARCHITECTURE overview (f01d150)
- bump iOS build number to 45 (a0ee2dc)

_[force]_

## [v0.5.0] - 2026-06-16

- Initial version tracking

_[manual]_
