# `Tools/Deploy` — build-number bump (only)

Deployment moved to the **`deployit` plugin** on 2026-05-23. Run
`/deployit deploy` from Claude Code (or `deployit deploy` via the
shipped CLI) to build a Development-signed `.ipa` and stage it for
OTA install via Tailscale Serve. The plugin replaces the previous
`deploy-ios.sh` orchestrator, the `ExportOptions.plist`, and the
HTML/manifest templates that used to live here.

## What's still in this directory

- `bump-build-number.sh` — Archive *pre-action* on the `Lillist-iOS`
  scheme. Increments `CURRENT_PROJECT_VERSION` in
  `Apps/Config/BuildNumber.xcconfig` on every archive (Xcode UI or
  `xcodebuild archive`). Build-number bumping is the host repo's
  responsibility; the deployit plugin reads the resolved
  `CFBundleVersion` from the built `Info.plist`.

That file is tracked in git so the counter is monotonic across
machines and never regresses. Commit the bump after every successful
deploy:

```text
chore(deploy): bump iOS build number to <N>
```

## Pointer

- Plugin command: `/deployit deploy`
- Per-Mac bootstrap (once): `/deployit bootstrap`
- Plugin docs: see `~/.claude/plugins/cache/agentics/deployit/` and the
  upstream `agentics` plugin source.
- Migration post-mortem: `docs/engineering-notes.md` (2026-05-23
  entry).
