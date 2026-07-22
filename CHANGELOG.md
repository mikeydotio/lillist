# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [v0.18.0] - 2026-07-21

### Added
- wire DeviceRoster/ControlInbox/ResetSignalMonitor into iOS and macOS AppEnvironment (face4c7d)
- fan out a control event after a successful restore (9655dbaf)
- add resetEverywhereToEmpty and resetAndReseedFromThisDevice (14219c81)
- add ResetSignalMonitor and ResetPropagator (4cc73e54)
- add ControlInbox (per-event, per-recipient KVS keys) (977f44f4)
- add KeyValueSyncStore seam + DeviceRoster (d5c26a5f)

### Fixed
- compile-gate PCC tier so app/CLI build without the 27 SDK (11b67324)
- honest three-button reset copy (iOS + macOS) (7fe07c84)

### Changed
- Merge pull request #73 from mikeydotio/worktree-lil-70 (ab7f6c1c)
- Merge pull request #72 from mikeydotio/fix/71-reset-propagation (64d41298)
- Merge pull request #69 from mikeydotio/chore/release-v0.17.0 (b8dc2942)

### Documentation
- record #70 compile-gate + deploy protocol (906f0bcf)

### Maintenance
- pin Xcode 27 via repo .deployit/config.toml (716981a9)
- 26.x fallback now compiles green; refresh stale Xcode-27 notices (427a6c7d)
- bump macOS build number to 52 (797bfe50)
- bump iOS build number to 90 (913a0ce8)

_[manual]_

## [v0.17.0] - 2026-07-21

### Added
- cap the automatic drain and add preview + undo (63125f6f)
- instrument restore with a diagnostic event (fb0f9c08)
- merge LillistTask rows that share one app id after a resync (ab7859fc)
- surface recovery guidance and give macOS parity with iOS's Reset tools (39c6f675)
- capture export-stall health in diagnostic packages (e64200ed)
- detect persistent CloudKit export stalls (65ffb939)

### Fixed
- correct the divergence warning's disproven root-cause claim (d3de45f0)

### Changed
- Merge pull request #68 from mikeydotio/chore/restore-macos-build-number (6b23de2f)
- Merge pull request #67 from mikeydotio/fix/66-icloud-sync-stall-detection (a3b11671)
- Merge pull request #65 from mikeydotio/chore/release-v0.16.1 (979daa7a)

### Maintenance
- restore macOS build number to 51 (v0.16.1 shipped 50) (80fa056f)
- bump iOS build number to 89 (73403722)

_[manual]_

## [v0.16.1] - 2026-07-21

### Fixed
- sidebar-based, resizable Settings window (#62) (dc6490c2)

### Changed
- Merge pull request #64 from mikeydotio/chore/storyhook-lil4-archive (e67c4e59)
- Merge pull request #63 from mikeydotio/worktree-lil-62 (a4edc7a8)
- Merge pull request #61 from mikeydotio/chore/release-v0.16.0 (ed7631ce)

### Testing
- update Settings UITest helpers for the sidebar (#62) (9c491706)
- add PreferencesPane enum + regression guard (#62) (0c41d2dd)

### Maintenance
- archive LIL-4 (On-device widget verification) (98d1458e)
- catalog the Settings sidebar's 11 pane labels (#62) (6dc9ef0b)
- bump macOS build number to 50 (9ec5168a)
- bump iOS build number to 88 (65d186ab)

_[manual]_

## [v0.16.0] - 2026-07-20

### Added
- add smart-search UI to the macOS Tasks window (#51) (d7f8d5b6)
- add smart-search UI to the iOS Tasks screen (#51) (aa589e67)
- wire --smart onto lillist search and the Shortcuts intent (#51) (133e50f2)
- add the FoundationModels translator tiers (#51) (6ef1bf4e)
- add the deterministic NL-query mapping core (#51) (7207dc29)
- surface the divergence warning inline in iCloud Sync settings (7c02a005)
- add pure divergenceWarning decision function (965d810e)
- populate provenance snapshot + surface CloudKit Environment row (984eef0e)
- fold provenance snapshot into the diagnostic manifest (8e54b555)
- add runtime CloudKit provenance probe (5e5a8c79)
- group the list picker by account, show incomplete counts (847b0acd)
- add pure ReminderListGrouping helper (3de9eaf8)
- carry account + incomplete count on ReminderListInfo (f20db2ab)

### Fixed
- give macOS its own monotonic Sparkle build-number counter (8663bd97)
- enable Sparkle's sandboxed installer path (01b73950)
- pin Sparkle distribution feed, retire per-machine override (6157cf8e)
- SecTask entitlement API is macOS-only, not cross-platform (a730093c)
- show why Reminders drain imported nothing, and kill the picker race (c152c256)
- stop conflating Reminders drain failures with an empty list (26555eef)
- drain skips completed reminders (d3e9db53)

### Changed
- Merge pull request #60 from mikeydotio/chore/untrack-claude-settings-local (bf963776)
- Merge pull request #57 from mikeydotio/feat/agentic-search-51 (c5a05763)
- extract lillist-cli into its own package (#51) (ffab2005)
- Merge pull request #59 from mikeydotio/fix/55-sparkle-appcast-feed (28c1d768)
- Merge pull request #56 from mikeydotio/worktree-lil-54 (df2b300f)
- Merge pull request #53 from mikeydotio/fix/reminders-drain-now-silent-zero (126551f2)
- Merge pull request #52 from mikeydotio/worktree-lil-49 (1c1e65a5)
- Merge pull request #48 from mikeydotio/chore/release-v0.15.0 (844d203b)

### Testing
- guard against the Sparkle feed/build-number regression class (6240b0fb)

### Maintenance
- stop tracking .claude/settings.local.json (machine-local) (b794dd02)
- adopt Xcode 27 beta for the agentic-search PCC path (#51) (3f4c173f)
- add divergence-warning strings to LillistUI catalog (58597542)
- bump iOS build number to 87 (598315c0)

_[manual]_

## [v0.15.0] - 2026-07-19

### Added
- add self-measuring NSTextView notes editor for macOS (0b58267a)
- expose dynamic NSColor accessors for AppKit-backed views (d77f8c26)
- add editorHasOuterScroll env flag + overlay scroll-and-center (9d3adb7f)

### Fixed
- grow the iOS notes field instead of scrolling it in place (#34) (7930e93b)
- remember only the collapsed main-card height (#35) (2d256963)
- align the notes placeholder vertically; pin the notes-metric estimates (#33 review) (e43e29f2)
- one shared glass panel + passive outer scroll for the nested notes field (#33 review) (515832a9)
- seed each card's height per route so drill-in → Back doesn't pop-resize (#33 review) (2109c94e)
- show the wrap card at a bounded first-pass height, not an opacity gate (#33 review) (d41bf63b)
- gate each card's reveal inside its own glass, robust to Back rebuilds (#33 review) (31b43007)
- gate the card reveal per route so child cards don't flash either (#33 review) (c0c71431)
- gate the whole card (glass included) on measurement; add notes vertical slack (#33 review) (60f5732e)
- hide the wrap card until measured, and widen the macOS notes sizer (#33 review) (18d6601f)
- hide the invisible notes sizer from VoiceOver (#33 review) (e18bbcf6)
- seed a bounded first-pass height so the wrap card doesn't flash greedy (#33 review) (062562dc)
- count a trailing newline in the notes sizer height (#29 review) (2f1b1506)
- hugging TextEditor notes field so Return breaks lines (#29) (5636ce2e)
- eliminate the ViewThatFits swap that tore down the focused tag field (#32) (0f690ba6)
- collapse the tag field on drill-in navigation (#26) (c5b5754e)

### Changed
- Merge pull request #47 from mikeydotio/docs/engineering-notes-apphosted-worktree (c01b8a6b)
- Merge pull request #46 from mikeydotio/test/editor-45-snapshot-baselines (7f2a4434)
- Merge pull request #42 from mikeydotio/fix/editor-38-overlay-scroll (1d3c9236)
- Merge remote-tracking branch 'origin/main' into fix/editor-38-overlay-scroll (9e984fd2)
- Merge pull request #43 from mikeydotio/fix/editor-36-nstextview-measurer (be15ad69)
- drive the macOS notes hug with MacNotesTextView (91040ba4)
- retire MeasuredGlassCard for a synchronous self-sizing card (3dde0e0c)
- Merge pull request #39 from mikeydotio/fix/editor-33-followups-35-36 (a46ac11f)
- Merge pull request #33 from mikeydotio/worktree-lil-31 (31026bde)
- extract .editorGlassPanel() so the card chrome has one definition (#33 review) (b10ab5d0)
- Merge pull request #30 from mikeydotio/chore/release-v0.14.1 (e6e88b05)

### Documentation
- correct the worktree app-hosted snapshot recipe (f7546c6d)
- record the NSTextView notes-hug redesign (#36) (fb39163e)
- record the overlay-scroll cutover; drop stale MeasuredGlassCard refs (f1f0732c)
- correct the stale gate comment; document the async-cap growth trail (#33 review) (53bb8657)
- replace phantom WrapToContentThenScroll/settledEditorHeight names after the rename (#33 review) (289b535c)
- downgrade the overstated @FocusState ordering comment (#28) (fa073aa4)

### Testing
- re-record editor baselines for overlay-scroll redesign (#45) (68717db8)
- migrate the async-measurement probes to synchronous assertions (707fd93f)
- pin the macOS notes-sizer over-count contract (#36) (0eeb4b40)
- pin the fat-notes boundary proxy to iPhone-17, drop the over-strict margin (#33 review) (b80e999f)
- assert the fat card clears the keyboard offer by a margin, not a knife-edge (#33 review) (60276a23)
- drop the no-op snapshot settle; rely on drawHierarchyInKeyWindow (#33 review) (e7bbddb1)
- derive the keyboard-up offer from the live screen, not a hardcoded 387 (#33 review) (2ca3d7b8)
- make editorContentHeight actually settle, not break on the first read (#33 review) (c3d38fa1)
- settle async layout before capturing editor snapshots (#33 review) (1b0bbd81)
- assert the fat-notes boundary crossing on real content, not tautologies (#33 review) (d2f9b54e)
- converge settledEditorHeight via a huge-offer probe, no deadline spin (#33 review) (44cf1d14)
- make the settled-height poll immune to the greedy pre-measure read (#33 review) (feedbaef)
- poll until the editor height settles instead of a fixed sleep (#33 review) (8327e8b8)
- address PR #33 review — window leak, shared fixture, post-#32 wording (89c85dbc)
- cross the ViewThatFits fit boundary and pin tag-field survival (#27) (f4bbda04)

### Maintenance
- bump iOS build number to 86 (add305c7)

_[manual]_

## [v0.14.1] - 2026-07-15

### Added
- wire Tags & Filters into iOS Settings + macOS Preferences (#16) (0cd4930c)
- shared Tags & Filters management UI (#16) (564b4bca)

### Fixed
- hoist the tag field's edit state above the wrap valve (147bf343)
- preserve field focus across the wrap-valve candidate swap (ca0a68b4)
- keep the self-sizing capture panel on-screen and settle its resize (c738a1a7)
- size the quick-capture panel to the editor's content (cc3de67e)
- wrap the full-mode detail card to its content (b79006ac)
- keep the Closed status control hittable at its 44pt target (4dfe5dc9)
- regenerate pbxprojs with the canonical root group name (0b501821)
- review fixes — cancellation aborts, begin retries, session ownership (be7c3bba)
- bridge row gestures to UIKit recognizers so the list scrolls (ac312790)

### Changed
- Merge pull request #25 from mikeydotio/fix/22-task-detail-wraps-content (3ac70acb)
- Merge pull request #24 from mikeydotio/fix/22-task-detail-wraps-content (cf976e40)
- unify the wrap-then-scroll valve; fix a stale doc reference (56cb41ce)
- add LillistSizing tokens; migrate editor width literals (c47c1f10)
- Merge pull request #23 from mikeydotio/test/18-macos-row-gesture-harness (6a963190)
- route SwipeableRow axis through shared DragAxisArbiter (issue #18) (f96148ac)
- Merge pull request #21 from mikeydotio/worktree-lil-16 (b1fb8074)
- Merge pull request #20 from mikeydotio/fix/15-status-indicator-closed-hittable (7057eac4)
- Merge pull request #17 from mikeydotio/fix/12-list-scroll-blocked (b1bf6c6a)
- dedupe launch/capture plumbing into UITestHelpers (5d0933b7)
- Merge pull request #14 from mikeydotio/docs/claude-md-pr-only-main (63b83b2c)
- Merge pull request #13 from mikeydotio/chore/release-v0.14.0 (139ce21a)

### Documentation
- correct stale panel doc + wrap-assertion message; note valve gotchas (8db085b1)
- record the ViewThatFits wrap + vertical-axis TextField gotchas (#22) (42dcbacf)
- record issue #18 verify-first resolution + macOS gesture harness (758bd5ec)
- record the collapsed-AX-frame gotcha (2de73570)
- cite tech-debt issues #18/#19; record post-review hardening (3fc9e201)
- postmortem for issue #12 + engineering-notes entry + handoff (f1bcf314)
- correct Git workflow — main is PR-only, not direct-push (00503df7)

### Testing
- wait for editor load before asserting the notes edit (7309b85d)
- add real-input row-gesture UITest harness (issue #18) (984b9e82)
- pin Closed-state StatusIndicator hittability + 44pt frame (25f4874e)

### Maintenance
- close LIL-5 — issue-#12 fix delivered via PR #17 (cfc4bcbd)
- track story LIL-5; gitignore rca/council plugin state dirs (b6ab8214)
- align macOS pbxproj with xcodegen 2.45.4 output (37f3d350)
- bump iOS build number to 85 (36aed8a9)

_[force]_

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
