# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [v0.14.0] - 2026-07-14

### Added
- compact detail card with in-card child popups (50b747f0)
- inline "+ Tag" affordance in TagAssignmentField (08372592)
- add DueLineFormatter for the compact detail schedule line (2e5cf74f)

### Fixed
- rows fill card height, "+" moves to corner overlay (#9) (d8a253c0)
- keep in-progress rows in place; only completed sink (#9) (dcbab646)

### Changed
- Merge pull request #11 from mikeydotio/worktree-lil-8 (1ddd4e43)
- drop the reminders section from the task editor (bf06119b)
- Merge pull request #10 from mikeydotio/worktree-lil-9 (acaf7b4b)

### Documentation
- worktree signing, Form-composition seam, snapshot-stable relative dates (119f3cc9)

### Testing
- re-record the detail editor baselines (89911187)

### Maintenance
- prune LillistUI strings orphaned by the detail redesign (9802529c)
- untrack xcodegen-generated Xcode schemes (cec85c39)
- bump iOS build number to 84 (69f9d39a)

_[manual]_

## [v0.13.0] - 2026-07-03

### Added
- container-relative corners, ring-less header, multi-step chips (ef98d041)
- No Filter default + completed-today grace period (96ee2360)

### Fixed
- dedup default smart filters to end CloudKit seed-race duplicates (55e524fe)

### Documentation
- widget corner/dedup/chip/sentinel lessons (829bb482)

### Maintenance
- bump iOS build number to 83 (50ed6357)

_[force]_

## [v0.12.0] - 2026-07-02

### Added
- per-task + macOS filter deep links (LIL-2, LIL-3) (a6ac60b4)
- reload wiring + lillist:// deep-link routing (49476837)
- iOS + macOS widget extension targets & plumbing (ae004da5)
- LillistUI widget presentation views + snapshot tests (a88be7ad)
- snapshot cache + deep-link model in LillistCore (26351d9b)

### Documentation
- note task-open + macOS filter-focus deep links (LIL-2/3) (80e2f363)
- document widget architecture (367dcabc)
- update (2 docs re-projected, 23 cells re-judged) (2d7375c6)

### Maintenance
- commit-link bookkeeping (842a58e1)
- commit-link bookkeeping for LIL-4 (22b50b61)
- sync xcodegen config with new capabilities + build settings (776da080)
- close LIL-1..3, unblock LIL-4 (cb2df7b9)
- plan widget follow-up stories (LIL-1..4) (302fdd1f)
- initialize task tracking (prefix LIL) (e83ea7f7)
- bump iOS build number to 82 (5882526e)

_[force]_

## [v0.11.10] - 2026-06-29

### Fixed
- equalize leading/trailing swipe-control gaps on task rows (f2ddbd3d)

### Documentation
- update (12 docs re-projected, 119 cells re-judged) (caad2df1)

### Maintenance
- bump iOS build number to 81 (99321d77)

_[force]_

## [v0.11.9] - 2026-06-28

### Fixed
- correct contradictory iCloud Sync subtitle ("Off" while ON) (e26f3a7d)

### Maintenance
- bump iOS build number to 80 (4a356ca5)

_[manual]_

## [v0.11.8] - 2026-06-27

### Added
- add "Reset & Download Data" reset option (3a46b620)

### Fixed
- humanize migration failure and auto-dismiss on success (92824529)
- remove no-op "Sync Now" button (8b54ce1e)

### Maintenance
- bump iOS build number to 79 (e7feabfc)

_[force]_

## [v0.11.7] - 2026-06-27

### Added
- show local + iCloud-mirrored task counts in sync settings (aaf98784)

### Fixed
- don't latch a red error for transient CloudKit partial-failures (9a67e69f)

### Documentation
- CKError 2 was a latched transient, not a schema issue (09a375a1)

### Maintenance
- bump iOS build number to 78 (98625052)

_[force]_

## [v0.11.6] - 2026-06-27

### Added
- export the diagnostic package via the share sheet (0fdb1ac1)

### Maintenance
- bump iOS build number to 77 (4a0bce33)

_[force]_

## [v0.11.5] - 2026-06-27

### Fixed
- host settings sub-page modals on the Form container, not the Section (24c3aea5)

### Documentation
- real cause of the Settings-sheet nuke (sheet on a Section) (cb283d4d)

### Maintenance
- bump iOS build number to 76 (8208101d)

_[force]_

## [v0.11.4] - 2026-06-27

### Documentation
- update (16 docs, 93 cells re-judged) (4ea2b6f2)

### Maintenance
- bump iOS build number to 75 (8e926f08)

_[force]_

## [v0.11.3] - 2026-06-26

### Added
- capture unified log in the diagnostic package (bb54a619)

### Fixed
- stop stacked presentations from dismissing the parent (549f9ad8)
- drive iCloud-sync modals through one sheet route (390c33c6)
- reveal swipe actions from behind the row with a gap (90528a50)

### Documentation
- one presentation modifier per view; swipe-reveal card model (864e36af)
- full codebase map regenerate (61 modules, cartographer/4) (9f96532e)
- overlay-after-offset blankets the full hit region (515f2473)

### Maintenance
- bump iOS build number to 74 (7d5394ad)

_[manual]_

## [v0.11.2] - 2026-06-26

### Fixed
- route taps to the revealed swipe Delete button (5faebc51)

### Maintenance
- bump iOS build number to 73 (e5afaf34)

_[force]_

## [v0.11.1] - 2026-06-25

### Fixed
- swipe reveals Delete instead of auto-deleting task rows (1cea6164)

### Maintenance
- sync LillistUI Package.resolved (ZIPFoundation pin) (5b103bb1)
- bump iOS build number to 72 (5468ccbb)

_[force]_

## [v0.11.0] - 2026-06-25

### Added
- voice Add Task, Quick Capture seed, Tasks from Reminders (f0325e6a)
- Reminders import engine + Quick Capture handoff (839caaae)

### Documentation
- AppIntents free-text + drain-actor reentrancy gotchas (ce62e096)

### Maintenance
- bump iOS build number to 71 (4e1fda7a)

_[manual]_

## [v0.10.1] - 2026-06-24

### Added
- render main window at 75% scale (3726a9fd)

### Changed
- move sync indicator from main toolbar into iCloud Sync settings (e3254831)

### Maintenance
- bump iOS build number to 70 (b1c09db3)

_[force]_

## [v0.10.0] - 2026-06-24

### Added
- adopt the shared iOS single-column UI for the main window (2c860e59)

### Changed
- un-gate the shared iOS Tasks screen for macOS (764482fc)

### Documentation
- log the macOS iOS-UI adoption and the tag/filter-mgmt follow-up (020b0662)

### Maintenance
- bump iOS build number to 69 (7d0d0d4e)

_[manual]_

## [v0.9.1] - 2026-06-24

### Fixed
- carry CloudKit push via the correct macOS entitlement key (9b471be1)

### Maintenance
- bump iOS build number to 68 (68e14cac)

_[force]_

## [v0.9.0] - 2026-06-24

### Added
- cut iOS + macOS deploys over to Production CloudKit (d7ff2429)
- add Data Management backup controls on iOS and macOS (issue #7) (b0f20ed9)
- wire the backup subsystem into both app environments (issue #7) (1da16af7)
- on-disk JSON backup engine with schema versioning (issue #7) (39c7ee7e)

### Fixed
- development-sign the macOS test build (stay on Development) (4766e249)
- adopt Production cutover — Developer-ID export is Production-only (c6a440d5)

### Changed
- rename Apple identifier namespace to io.mikey.lillist (35410ce4)

### Documentation
- record local-backup engineering notes (issue #7) (f8c782af)
- update identifier references for io.mikey.lillist rename (d9cd32fe)

### Maintenance
- bump iOS build number to 66 (8161cefb)
- rename identifier namespace io.mikey.lillist → app.lillist (96df1a4d)

_[force]_

## [v0.8.14] - 2026-06-23

### Fixed
- pin macOS Developer-ID export to Development CloudKit env (0c1033bc)

_[force]_

## [v0.8.13] - 2026-06-23

### Maintenance
- bump iOS build number to 63 (40b762a1)

_[force]_

## [v0.8.12] - 2026-06-23

### Fixed
- surface CloudKit partialFailure per-item errors (0281c0ed)

### Maintenance
- bump iOS build number to 62 (8bb5936b)

_[force]_

## [v0.8.11] - 2026-06-23

### Fixed
- consistent Preferences width + chrome polish (45766c80)
- relocate build-version footer + live sidebar refresh (8b7cd040)

### Documentation
- macOS visual design pass review + login-keychain signing (b44e1332)
- warn this is early alpha and sync uses the Debug CloudKit env (86286508)

### Testing
- add XCUITest screenshot harness + launch-arg seams (ad4d5f08)

### Maintenance
- bump iOS build number to 61 (856911e6)

_[force]_

## [v0.8.10] - 2026-06-22

### Fixed
- converge iOS/macOS on one CloudKit env + real sync status (cb0e5cd1)

_[manual]_

## [v0.8.9] - 2026-06-22

### Maintenance
- bump iOS build number to 60 (2b10f250)

_[force]_

## [v0.8.8] - 2026-06-22

### Fixed
- pre-bump hook reads NEW_VERSION env + derives repo root (4af43f16)

### Changed
- resolve crash-report email + Sparkle feed from build config (e909b1d5)

### Documentation
- add MIT LICENSE, third-party attributions, and README (8d145b0e)

### Maintenance
- guard against literal Team IDs in committed project files (09c1cf49)
- bump iOS build number to 59 (35bbe7e4)

_[force]_

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
