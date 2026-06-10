# HANDOFF — Reorder fix in PR, ready to merge

**Date:** 2026-06-10 · **PR:** [#3 fix/reorder-anchors-out-of-order](https://github.com/mikeydotio/lillist/pull/3)

## What's done ✅

### Diagnostic logging (merged to `main`)
Full JSONL diagnostic system for diagnosing the reorder-tie bug in the field.
See the 2026-06-06 entry in `docs/engineering-notes.md`.

### Reorder fix (PR #3, 14 commits)
- `SiblingOrder` canonical comparator — one source of truth for all presenters and recompaction
- `TaskStore.reorder` / `SmartFilterStore.reorder` heal equal-position ties before re-checking
- `SmartFilterStore.sortDescriptors(.manualPosition)` latent bug fixed (`"position"` not `"deadline"`)
- Idempotent load-time `normalizeSiblingsIfDegenerate` at iOS + macOS load seams
- `ReorderFailureToast` on both platforms — write failures are transient, not `loadError`
- 890 LillistCore + 40 LillistUI tests passing; both app schemes build signed

## To merge PR #3

Run the two things CI can't do (both require this Mac):

1. **Snapshot suite** (Claude Code can do this once Keychain is unlocked):
   ```bash
   xcodebuild test -workspace Lillist.xcworkspace \
     -scheme Lillist-iOS \
     -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
   ```
   Snapshot tests may produce new failures for the `DiagnosticsIncludeSheet` tour
   frame (`test_11`) — if so, regenerate baselines and commit.

2. **iCloud-dependent tests** (requires active iCloud account — Mikey only):
   ```bash
   xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
     -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
     -only-testing:Lillist-iOSAppHostedTests
   ```

Then merge and delete the branch.

## Untracked files
`.rca/reorder-anchors-out-of-order/` — RCA archaeology, intentionally untracked.
Commit or delete it after merge as you see fit.

## Conventions
Solo repo; conventional commits; rebase-and-merge to `main`; HTTPS push; never force-push.
Signed builds are now the default (Keychain unlocked = no `CODE_SIGN_IDENTITY=""` flags needed).
iCloud-dependent tests are the only thing that requires Mikey's manual sign-off.
