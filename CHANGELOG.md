# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [v0.20.0] - 2026-07-31

### Fixed
- give the widget extension its own sandboxed entitlements (LIL-92) (c75564ad)
- stop persisting a failed read as an authoritative empty snapshot (04136f2f)
- bound and short-circuit configuration-intent resolution (LIL-91) (6917c20f)

### Changed
- Merge pull request #82 from mikeydotio/fix/lil-92-macos-widget-sandbox (8badd3ab)
- Merge pull request #81 from mikeydotio/rca-fix/ios-widget-shows-redacted-content (5f0a6b6f)
- Merge pull request #80 from mikeydotio/chore/storyhook-store-migration (93a042ab)
- Merge pull request #79 from mikeydotio/chore/v0.19.0-deploy-bookkeeping (2ac50cb5)
- Merge pull request #78 from mikeydotio/chore/post-hardening-tidy-and-release (bb68168d)

### Documentation
- why v0.19.0 shipped without Sparkle (88574102)

### Testing
- guard macOS app extensions against shipping unsandboxed (1b5e3cf8)

### Maintenance
- migrate the tracker to the store and retire .storyhook (907e6a11)
- bump iOS and macOS build numbers for v0.19.0 (e2ec3eca)

_[force]_

## [v0.19.0] - 2026-07-29

### Added
- X6 — WidgetRefreshController observes local saves, not just remote changes (7a9f90e5)
- add withMutationRollback shared mutation helper (642312bb)
- X7 — deterministic UUIDv5 identity for recurrence spawns and their deep-copied children (6d4a53e0)
- X8 — extension processes construct a wired notification scheduler (56c0bcd0)
- X9 — give macOS its own RemoteChangeReconciler (b45005e5)
- wire pending-reset dialog, discard notices, broadcast copy, real retry, and quarantine cleanup into both apps (S9c, S10, S18, S19, S20, X11) (89c34aa0)
- MigrationCoordinator gains an iCloud-not-empty guard, a real "Try Again" retry, and X11 watermark/widget clearing (S19, X11) (bd6fe02f)
- DataStoreResetService reports broadcast reach, waits for re-export quiesce before broadcasting, and clears the history/widget caches after every destructive reset (S20, S9c, X11) (0875470d)
- ResetSignalMonitor becomes an always-prompt actor with dead-letter quarantine and a bounded AppliedEventStore (d3897ee7)
- wire LiveNetworkReachability into PauseReasonClassifier (S24) (137a6d54)
- real reachability + real iCloudDriveDisabled signal (S24) (fae77f8e)
- wire syncStatusReset + activate MigrationCoordinator's account preflight (S21, S3) (2216ea08)
- wire SyncStatusMonitor.resetStallState into migration/reset success paths (S21) (f628f370)
- import-axis stall escalation + resetStallState (S21) (645e9c80)
- wire AccountIdentityStore into launch + settings UI (S3, S13) (eee6fd67)
- resolveAccountMismatchByRedownloading — narrow, re-validating S3 resolution entry point (c72c2d5c)
- wire AccountIdentityStore into AccountStateMonitor.refresh (S3, S13) (53fc6719)
- AccountIdentityStore — persist and compare iCloud identity (S3 foundation) (df522814)
- durable crash recovery for resetAndReseedFromThisDevice (S9b) (11e24b70)
- add DestructiveOpGate (S11) (071c9440)
- export schema completeness — Series, NotificationSpec, SmartFilter, archivedAt, defaultTagTintHex (X3, X18) (16bb7125)
- one-time macOS App-Group store migration (X1) (c7538745)
- suppress CloudKit mirroring for extension/widget roles (X15) (73c2fbf8)
- add StoreLocation, the canonical store-path + mirroring-role resolver (397f3ddb)
- wire TreeIntegrityChecker.repair into launch bootstrap (56100933)
- add TreeIntegrityChecker, the trash-tree class-killer (f40d7892)

### Fixed
- recoverInterruptedReseed also broadcasts to peers on resume (f65b3b7b)
- LocalBackupCoordinator.bootstrapAtLaunch catches up on history (cebda48d)
- restoreFromBackup gains an account guard and backup resync (bdec5bde)
- wire three missing bootstrap/settings self-heal steps (89d560dc)
- pinned filter chip row uses canonical SiblingOrder tie-break (1936ea0c)
- Series.rule throws on encode failure; Importer restores preferences (4da89d70)
- X12/L7 — WatermarkRegistry replaces HistoryWatermarks; HistoryPruner prunes to min(consumer watermarks) (7764c221)
- X6 — wire WidgetRefreshController into both apps' bootstrap (59809ee3)
- X5 — split WidgetSnapshotBuilder.regenerate into additive vs. authoritative (a0963538)
- L5 — archive/unarchive skip missing ids instead of failing the batch (ae47939d)
- L3 — syncCounts runs off the main-queue viewContext (de65d178)
- M6 — reorder rejects a single explicit-parent anchor from another group (22725503)
- X19 + H5 — TaskDuplicateReconciler.reconcileDuplicates rolls back on failure (62d90d5f)
- X19 + H5 — NotificationSpecStore routes through withMutationRollback (137e57d0)
- M4 + X20 — PreferencesStore.read() becomes read-only; deterministic singleton survivor (623abe1c)
- M7 — AttachmentStore.delete reaps its auto-created JournalEntry (765da9dd)
- H5 — AttachmentStore mutators route through withMutationRollback (bad11f0d)
- H5 — SeriesStore mutators route through withMutationRollback (e400c92e)
- H5 — JournalStore mutators route through withMutationRollback (35e2bf55)
- H5 — SmartFilterStore mutators route through withMutationRollback (bcdf4101)
- H5 — TagStore mutators route through withMutationRollback (114d4af9)
- H5 — TaskStore mutators route through withMutationRollback (8d3cbafc)
- X17 — weekly byDay respects calendar.firstWeekday, not a hardcoded Sunday boundary (e0630a4e)
- X16 — clamp AfterCompletionRule.interval at both trust boundaries (372273cc)
- H1 — recurrence spawn uses live sibling positioning, not a stale seed offset (47953dee)
- X10 — hydrate all-day default from prefs, document rewrite semantics, pin the timezone dedup limitation (f1883ef1)
- X9 — widen RemoteChangeReconciler to spec insert/delete + task soft-delete/restore (cf867f8c)
- H2 — reconcile notifications for the full softDelete/restore subtree (3d76911e)
- serialize and coalesce concurrent remote-change drains in RemoteChangeReconciler and TaskDuplicateReconciler (M3) (84f77d85)
- RemoteChangeReconciler advances its watermark only after a successful reconcile (H6) (40bd3895)
- replaceLocalWithICloud gains the missing account-changed preflight (S3) (29449d44)
- PersistenceHost preserves armsCloudKitMirroring across every swap (S3 fix 1) (93a858bb)
- three backup-correctness gaps — schema gate, torn snapshots, stale package (S23) (d43afe1f)
- live-package restore stages before the wipe, prune guarded during destructive ops (S4) (7c863ebd)
- quarantine anchor for 3 migration ops now comes from a closed store (S7) (959a5e65)
- restoreFromBackup closes the store before file ops (S2) (42b2e657)
- wire shared DestructiveOpGate, fix launch-time gates (S11 S16 S17) (02a183ac)
- wire DestructiveOpGate into DataStoreResetService, close S12 gap (S11 S12 S14 S15) (b63f0f52)
- MigrationCoordinator honest state machine (S1 S5 S6 S8 S11 S12 S14 S15) (1156c808)
- SyncQuiesceMonitor honors setup events + isolates waiters (S14) (38c7d1cf)
- eliminate GatedPersistenceResolverTests' shared UserDefaults suite race (d4f942f8)
- thread assetsDirectory through every importBundle caller (S9a) (2e4f1856)
- .skipExisting import no longer rewrites parents (X13) (2d99e623)
- disambiguate QuarantineManager folder names for same-second calls (070ba738)
- resolve the app-group store through StoreLocation, removing the silent defaultOnDisk fallback (621e6ded)
- cancel pending OS notifications on hard delete/purge (H3) (a4af7b8c)
- retire NSBatchDeleteRequest from trash purge (C4/X4, X14) (c2284a1a)
- merge duplicate tasks without destroying the loser's subtree (C3/M5) (cf6447ab)
- bound trash purge at live descendants of a trashed ancestor (d5c9d191)
- fix the restore half of the trash state machine (C2/M2/H4) (ed058fd4)
- reject a soft-deleted parent in create/reparent/reorder (72f67668)
- guard every ancestor/descendant walk against a pre-existing parent cycle (2e95f293)

### Changed
- Merge pull request #77 from mikeydotio/hardening/data-sync-2026-07 (8f1b6fc0)
- extract DiagnosticHistoryObserver's DrainGate into a public LillistCore type (5078cbfd)
- Merge pull request #76 from mikeydotio/chore/retire-atlas (a0c06aef)
- Merge pull request #75 from mikeydotio/chore/release-v0.18.1 (efe4642e)

### Documentation
- close out the Data & Sync Hardening program post-merge (bcb0696d)
- replace HANDOFF.md with the program-complete handoff (f7f4066d)
- data-sync-hardening mini-roadmap — all waves complete (6a48bd90)
- close out the data-sync-hardening program in the ledger (f3bf26be)
- four data-sync-hardening lessons (d179dd39)
- add Gotchas section for two upstream storyhook-CLI defects (95183f93)
- plan 6a — completeness-and-lows design + close-vs-defer table (ec7ccaf7)
- close out plan 5c in the ledger — Wave 5 complete, HANDOFF refreshed for Wave 6 (1c889cc4)
- add plan 5c — watermark-registry-pruning (1dfedd84)
- close out plan 5b in the ledger; refresh HANDOFF for 5c (4ce7959d)
- add plan 5b — widget-snapshot-correctness (a4f1b832)
- update HANDOFF for LIL-86's in-plan fix and zero-skip verification (10748be7)
- update ledger for LIL-86's in-plan fix and the zero-skip verification close (ee39e8eb)
- close out plan 5a — Wave 5's first plan complete, ledger + HANDOFF updated for 5b (d704bcf0)
- plan-5a mutation-scope-discipline (84dd7a39)
- close out plan 4c — Wave 4 complete, ledger + HANDOFF updated for 5a (6cc5fa4c)
- plan-4c recurrence-correctness (02bffffb)
- record team-lead's deferred-schema decision for LIL-83 (ee44c0a2)
- refresh HANDOFF for plan-4b -> plan-4c (c533d55a)
- update ledger with the plan-4b closing report (46001e7e)
- plan-4b notification-truthfulness (03575539)
- close out wave 4a in the ledger, hand off to wave 4b (672e8f47)
- plan-4a history-consumer-discipline (7e60d23d)
- refresh HANDOFF.md for wave 3b -> wave 4a (29e36d7d)
- close out wave 3b in the ledger, hand off to wave 4a (67298bb2)
- plan-3b reset-propagation-safety (9843f6fc)
- refresh HANDOFF.md for wave 3a -> wave 3b (9b244a0b)
- close out wave 3a in the ledger, hand off to wave 3b (593c6ed4)
- design doc for plan 3a — account identity and status (b180d4de)
- refresh HANDOFF.md for wave 2b -> wave 3a (535d0fb4)
- close out wave 2b in the ledger, hand off to wave 3a (ebdc0129)
- design doc for plan 2b — backup/restore correctness (eed4e709)
- close out wave 2a in the ledger, hand off to wave 2b (40e661c9)
- design doc for plan 2a — migration transitions (dce3b354)
- correct the ledger for LIL-79, add binding verification protocol (f70ec9ef)
- file LIL-77 (crash-prompt persistence defect) for 6a (e911e306)
- refresh HANDOFF.md for wave 1d -> wave 2a (b804caf6)
- close out wave 1d in the ledger, hand off to wave 2a (65f714d3)
- plan 1d — export-schema-completeness (8d1472fb)
- close out wave 1c in the ledger, hand off to wave 1d (d7d8e04a)
- plan 1c store-location-unification — resolver + migration design (07545d4d)
- close out wave 1b in the ledger, hand off to wave 1c (3b81f32f)
- plan 1b purge-cloudkit-retirement — chunked context-delete design (bcfa04ac)
- close out wave 1a in the ledger, hand off to wave 1b (f7f823d6)
- plan 1a trash-tree-integrity — state machine, TreeIntegrityChecker design (8e13b98f)
- pin the storyhook root cause to open/stories/, credit team-lead (e33d20b3)
- add data-sync hardening mini-roadmap, refresh HANDOFF (243329d7)
- add 2026-07-28 data & sync hardening review (911da81c)

### Testing
- X20 flip-flop stress across two real cross-process controllers (d4be6b0f)
- harden three timing-sensitive tests against parallel contention (f796407d)
- X12/L7 — WatermarkRegistry unit coverage, conformance class-kill, pruner-level regression (ff167ceb)
- poll on reload count, not the snapshot write, in WidgetRefreshControllerTests (a8b83770)
- harden WidgetRefreshControllerTests against parallel-run contention (93d0de1f)
- LIL-86 — pin X10's timezone-dedup fixture to a fixed clock (79fc1f68)
- L4 — regression coverage for unassignTag's no-op guard (644b5626)
- model-derived export-schema completeness class-killer (ff8ac9e4)
- multi-process store harness + path-pin regression test (e9b57e43)

### Maintenance
- mark plan-6a stories done — program complete (f5262b41)
- file LIL-90 (NotificationSpec in-place edit residual, deferred) (4c3c4303)
- mark plan-6a stories in-progress (1a3699e5)
- file the backup-consumer launch catch-up residual from wave 5c (4767c8a3)
- record the third contention-flaky test on the timing-hardening item (d431ef38)
- move plan-5c stories to done (bec420da)
- move plan-5c stories to in-progress (d1dd61e3)
- move plan-5b stories to done (4a7502e4)
- move plan-5b stories to in-progress (9345962a)
- record the second contention-flaky test on the timing-hardening item (ab1d739b)
- move LIL-86 to done (9c5aecef)
- move plan-5a stories to done (6b84143f)
- move plan-5a stories to in-progress (87454042)
- move plan-4c stories to done (3b377f58)
- move plan-4c stories to in-progress (1fc5db7a)
- file the quiesce-test timing-sensitivity hardening item for the 6a sweep (6b1a2c42)
- confirm the X10-residual story stays in the todo state (8974f3ab)
- correct LIL-83 state to todo after another git-hook auto-flip (67e79348)
- move plan-4b stories to done, file LIL-83 for X10's deferred schema change (6ef9d7d1)
- file the unwired duplicate-reconciler diagnostics residual from wave 4a (f44275b9)
- move LIL-24, LIL-47 to done (H6/M3 fixed in 40bd3895/84f77d85) (a809d74b)
- move plan-3b stories to done (4d492c9e)
- finish relabeling the restore account-guard residual (62eb6107)
- move the 3a-discovered restore account-guard residual to the 6a sweep (85017bb2)
- move plan-3a stories to in-progress (1d4668ef)
- file the stale-backup-package residual from the wave 2b closing report (70ba7065)
- move plan-2b stories to done (4cdfa6b4)
- move plan-2b stories to in-progress (15ee6e3e)
- move plan-2a stories to done (568f7807)
- drop orchestrator's duplicate crash-prompt story (agent's copy is canonical) (1b392974)
- file the crash-prompt persistence defect discovered during wave 1d (25165350)
- move LIL-17, LIL-67 to done (2b1b7ad2)
- move LIL-44, LIL-30 to done (57d7fd71)
- move LIL-64 to done (X15 fixed in 397f3ddb, 73c2fbf8, c7538745) (bcfd091c)
- move LIL-15 to done (X1 fixed in 397f3ddb..c7538745) (18fabaf4)
- move LIL-16 to done (X2 fixed in 397f3ddb) (91f49d2e)
- move LIL-21 to done (H3 fixed in a4af7b8c) (33170218)
- move LIL-10, LIL-63 to done (C4/X4, X14 fixed in c2284a1a) (f79d8cd7)
- move LIL-9, LIL-49 to done (C3/M5 fixed in cf6447ab) (9243751a)
- move LIL-7 to done (C1 fixed in d5c9d191) (9518f232)
- move LIL-8, LIL-46, LIL-22 to done (C2/M2/H4 fixed in ed058fd4) (f1ed6c5c)
- move LIL-45 to done (M1 fixed in 72f67668) (37cc1d24)
- move LIL-25 to done (H7 fixed in 2e95f293) (f210a768)
- correct council-vote wording on the merged CloudKit-purge story (538fb8b9)
- revert two stories the commit-message hook mis-flipped (cc4081ac)
- file 70 data-sync hardening stories (LIL-7..LIL-76) (4db049eb)
- remove remaining atlas references from docs and ignore rules (6b966a30)
- retire the atlas plugin and delete its codebase map (388e5384)
- bump macOS build number to 54 (13128ce6)
- bump iOS build number to 92 (800bc60f)

_[manual]_

## [v0.18.1] - 2026-07-22

### Changed
- Merge pull request #74 from mikeydotio/chore/release-v0.18.0 (d98f1bf5)

### Maintenance
- bump macOS build number to 53 (b249ec2f)
- bump iOS build number to 91 (f598e58e)

_[force]_

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
