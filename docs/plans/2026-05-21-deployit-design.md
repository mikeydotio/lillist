# `deployit` — Design

Plan to convert Lillist's local iOS deploy strategy into a reusable
Claude Code plugin published from `mikeydotio/agentics`, backed by a
shared cross-machine build index, and supporting iOS, macOS, and
visionOS targets.

The terminal acceptance gate is a fresh end-to-end deploy of Lillist
through the new plugin. The current `Tools/Deploy/` strategy is
removed as part of the work.

## Goals

- Any Claude instance on any tailnet Mac can deploy any project that
  ships an Xcode workspace, by invoking `/deployit deploy`.
- Every deploy lands in a single shared listing that the user can
  bookmark on iPhone (or any tailnet device) and read from any
  tailnet Mac.
- Binaries never leave the user's tailnet.
- The plugin is published to and installed from
  `mikeydotio/agentics`. No infrastructure or templates live in
  consuming repositories.

## Non-goals

- TestFlight / App Store Connect distribution.
- GitHub Actions or any non-local CI participation.
- Public (non-tailnet) hosting of binaries or the listing.
- Cross-user multi-tenancy. This is single-user, multi-machine.
- Auth beyond tailnet membership.
- Automatic build-number bumping policy. The host repo owns its
  build counter (Lillist already does, via `BuildNumber.xcconfig`).

## Architecture

### Three artifacts

```
┌────────────────────────────────────────────────────────────────┐
│  PLUGIN — mikeydotio/agentics/plugins/deployit/                │
│  Code. Installed via /plugin install deployit@agentics.        │
│  No per-user state.                                            │
└────────────────────────────────────────────────────────────────┘
                              │
                              │ writes to / reads from
                              ▼
┌────────────────────────────────────────────────────────────────┐
│  INDEX — mikeydotio/deployit-index/                            │
│  Data only. Single shared source of truth for "what builds     │
│  exist across the tailnet." Append-only builds.json + schema.  │
└────────────────────────────────────────────────────────────────┘
                              │
                              │ cloned into
                              ▼
┌────────────────────────────────────────────────────────────────┐
│  PER-MACHINE STATE — ~/Library/Application Support/deployit/   │
│  index/   — git clone of deployit-index                        │
│  serve/   — IPAs / DMGs / per-build pages                      │
│  logs/    — backend logs                                       │
│  config.toml                                                   │
└────────────────────────────────────────────────────────────────┘
```

Tailscale Serve on each machine proxies
`https://<host>.<tailnet>.ts.net/deployit/` → `127.0.0.1:8729`. The
backend on that port is a long-running Python service installed by
`/deployit bootstrap` and supervised by launchd.

### Topology — origin-machine self-serves, shared git-backed index

Each deploying machine archives, exports, and serves its own
binaries locally via its own Tailscale Serve. After a successful
deploy, the plugin appends an entry to its local clone of the index
repo and pushes to GitHub. Other machines pick up new entries by
pulling on demand — every `GET /deployit/` runs `git pull` first.

iPhone (or any tailnet device) bookmarks any one Mac's Tailscale
Serve URL. The listing renders the union of all builds across the
tailnet; install links point at the origin Mac.

Trade-off acknowledged: if the origin Mac is asleep, that build is
not installable. The listing still shows the entry. New deploys from
any other Mac are unaffected.

## Plugin layout (`agentics/plugins/deployit/`)

```
.claude-plugin/
  plugin.json
skills/deployit/
  SKILL.md                          # thin router; mirrors semver
bin/
  deployit-router.sh                # entry point invoked by SKILL.md
  deployit-cli                      # main Python CLI
  deployit-backend                  # long-running http server (launchd)
references/
  bootstrap.md                      # per-machine one-time setup
  ios.md                            # iOS archive/export/sign specifics
  macos.md                          # .dmg + notarytool flow
  visionos.md                       # mostly ≡ iOS
  tailscale-serve.md                # proxy config + common failures
  troubleshooting.md                # adapted from Tools/Deploy/README
assets/
  manifest.template.plist           # OTA manifest (unchanged from today)
  index.template.html               # per-build landing page
  listing.template.html             # cross-machine listing page
  launchd.plist.template            # com.mikeydotio.deployit.backend
  ExportOptions.ios.plist
  ExportOptions.macos.plist
  ExportOptions.visionos.plist
config.example.toml
```

### Pattern adherence

Follows `agentics/plugins/semver/`'s discipline:

- `SKILL.md` ≤ 200 lines, pure orchestration. Routes user input to
  `bin/deployit-router.sh`, presents CLI-returned questions via
  `AskUserQuestion`, displays results.
- `bin/deployit-cli` is a Python script. It is the source of truth for
  every deterministic operation (archive, export, stage, push). Tests
  exercise the CLI directly, not through SKILL.md.
- References stay out of context until needed. A user running
  `/deployit deploy --platform ios` causes the CLI to inline whatever
  it needs from `references/ios.md` only when an error surfaces a
  matching recipe.

## Index repo (`mikeydotio/deployit-index`)

```
README.md       # what this repo is, who writes to it, who can read it
schema.json     # JSON Schema for a build entry
builds.json     # append-only; newest first
```

### `builds.json` schema

```json
{
  "version": 1,
  "builds": [
    {
      "id": "lillist-ios-20260521-153012-a7c4f9b",
      "platform": "ios",
      "project": "Lillist",
      "bundle_id": "app.lillist",
      "marketing_version": "0.1.0",
      "build_number": "16",
      "commit": "a7c4f9b",
      "timestamp": "2026-05-21T15:30:12-07:00",
      "origin_host": "studio.tail-abc123.ts.net",
      "origin_base_url": "https://studio.tail-abc123.ts.net/deployit",
      "install": {
        "kind": "itms-services",
        "manifest_url": "<origin_base_url>/<id>/manifest.plist",
        "ipa_url": "<origin_base_url>/<id>/Lillist.ipa"
      },
      "size_bytes": 12345678,
      "archived": false,
      "notes": null
    }
  ]
}
```

`install.kind` is `itms-services` for iOS/visionOS and
`direct-download` for macOS (`ipa_url` becomes `dmg_url`).

`archived: true` marks a build whose binary has been garbage-collected
from the origin Mac. The entry persists for history; install links 404.

### Push protocol

```
git pull --rebase
append entry to builds.json (newest first)
git commit -m "feat(deploy): <project> <platform> <version> (<build>) from <host>"
git push                          # retry up to 3× on conflict
```

Conflicts are vanishingly rare (only appends, newest-first). A failure
after 3 retries surfaces as a clear error from `/deployit deploy` and
the local artifacts stay in `serve/` so the deploy is recoverable.

## Backend service

Long-running Python process per machine, supervised by launchd:

```
~/Library/LaunchAgents/com.mikeydotio.deployit.backend.plist
  KeepAlive       = true
  RunAtLoad       = true
  StandardOutPath = ~/Library/Logs/deployit/backend.log
  StandardErrorPath = ~/Library/Logs/deployit/backend.err.log
  ProgramArguments = [
    "<plugin-root>/bin/deployit-backend",
    "--port", "8729",
    "--root", "~/Library/Application Support/deployit",
  ]
```

### Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/deployit/` | `git pull` index, render `listing.template.html` |
| GET | `/deployit/<build_id>/` | per-build landing page |
| GET | `/deployit/<build_id>/manifest.plist` | OTA manifest (iOS/visionOS only) |
| GET | `/deployit/<build_id>/<artifact>` | the IPA or DMG |
| POST | `/deployit/_internal/refresh` | force `git pull`; called by CLI after deploy |
| GET | `/deployit/_healthz` | liveness probe (used by bootstrap) |

### `git pull` cadence

- On every listing request (`GET /deployit/`). The index repo is KB-
  scale; latency is sub-second on warm cache.
- Hourly background pull keeps state warm between visits.
- `If-None-Match` / `ETag` on the rendered listing so iPhone reloads
  are instant when nothing changed.

## CLI surface

```
/deployit bootstrap                       one-time per-machine setup
/deployit deploy [--platform P] [--scheme S]
/deployit list   [--platform P] [--project N]
/deployit url                             print this Mac's listing URL
/deployit status                          backend + index health, recent deploys
/deployit gc [--keep N | --older-than D]  prune local IPAs, archive in index
```

`bootstrap` is idempotent and re-runnable. It:

1. Verifies `tailscale` is installed and the daemon is up.
2. Creates `~/Library/Application Support/deployit/{index,serve,logs}`.
3. Clones `mikeydotio/deployit-index` into `index/` if missing.
4. Writes `config.toml` (auto-derived from `tailscale status`).
5. Installs the launchd agent and `launchctl bootstrap`s it.
6. Runs `tailscale serve --bg 8729` if not already configured.
7. Polls `/deployit/_healthz` until ready.
8. Prints the bookmark URL.

`deploy` argument inference: if a workspace and `project.yml` are
present in the current directory, project name, bundle ID, marketing
version, and a single matching scheme are auto-discovered. When more
than one scheme matches the requested platform, the CLI returns a
`questions` array that SKILL.md presents via `AskUserQuestion`.

## Deploy data flow

### iOS path

```
preflight
  ├─ tailscale up?
  ├─ Signing.local.xcconfig present?         (host-repo concern)
  ├─ backend healthy? else start it
  └─ index clone exists? else bootstrap      (auto-recover)
derive metadata
  └─ project, bundle_id, marketing_version, commit, timestamp
archive                                       (xcodebuild archive)
  └─ host repo's Archive pre-action bumps build #
read CFBundleVersion from built Info.plist
export                                        (ExportOptions.ios.plist)
build_id = "<project>-<platform>-<YYYYMMDD-HHMMSS>-<short_sha>"
stage
  ├─ mv <App>.ipa  → serve/<build_id>/<App>.ipa
  ├─ render manifest.plist
  └─ render per-build index.html
update index
  ├─ git pull --rebase
  ├─ append entry
  ├─ commit + push (up to 3 retries)
POST /deployit/_internal/refresh              local view updates instantly
print install URL + QR code
```

### macOS path

Same archive flow with a macOS scheme. Export uses Developer ID
method (or Development if no ID is configured); the resulting `.app`
is wrapped in a `.dmg` via `hdiutil create`. Optional `xcrun
notarytool submit --wait` + `xcrun stapler staple` step, controlled
by `config.toml` (`macos.notarize = true|false`). Staged as
`serve/<build_id>/<App>.dmg` with a per-build landing page whose
button is a direct download rather than `itms-services://`.

### visionOS path

Identical to iOS, with `--destination 'generic/platform=visionOS'`
and `ExportOptions.visionos.plist`. Same OTA install model.

## Lillist migration

| File | Action |
|---|---|
| `Tools/Deploy/deploy-ios.sh` | delete |
| `Tools/Deploy/ExportOptions.plist` | delete |
| `Tools/Deploy/manifest.template.plist` | delete |
| `Tools/Deploy/index.template.html` | delete |
| `Tools/Deploy/README.md` | replace with a 5-line pointer to the plugin |
| `Tools/Deploy/bump-build-number.sh` | keep — repo-specific Archive pre-action |
| `Apps/Config/BuildNumber.xcconfig` | keep |
| `CLAUDE.md` "Deploy (iOS test builds)" | rewrite to point at `/deployit deploy`; keep the prerequisites paragraph |
| `~/.zshrc` `LILLIST_DEPLOY_BASE_URL` | remove (config.toml replaces it; derived from `tailscale status` during bootstrap) |

The host repo retains exactly one deploy-related responsibility: its
own build-number policy. Everything else (templates, server,
publishing, listing) moves into the plugin.

## Acceptance gate

The work is complete when, on a fresh Mac (or one cleanly reset):

1. `/plugin marketplace add mikeydotio/agentics`
2. `/plugin install deployit@agentics`
3. `/deployit bootstrap`
4. `cd /Volumes/Code/mikeyward/Lillist && /deployit deploy`
5. The CLI prints an install URL.
6. iPhone visits that URL in Safari, taps Install, the app launches.

## Open questions deferred to plan stage

- **macOS notarization defaults.** Whether `config.toml` defaults
  `notarize = true` or `false`. Notarization needs an App Store
  Connect API key; mandating it raises the setup bar. Plan-stage
  decision.
- **visionOS test target.** Lillist has no visionOS target. visionOS
  validation depends on either adding one (out of scope) or
  validating against a synthetic sample app inside the plugin's tests.
- **GC strategy for the origin's `serve/` directory.** v1 ships with
  `gc` available manually; auto-prune (e.g. keep last 5 per project)
  is plan-stage.
- **Push conflict ceiling.** v1 retries 3× then surfaces a clear
  error. If conflict rate ever becomes non-zero in practice, a small
  CAS-style optimistic lock or a single-writer queue is the next step.
- **Backend port collisions.** v1 hard-codes 8729 (matches today's
  Lillist deploy). Plan stage decides whether to make this
  `config.toml`-configurable.

## Risks

- **Tailscale Serve daemon state.** The Mac App Store Tailscale
  variant cannot serve filesystem paths. `bootstrap` documents and
  validates the `tailscale serve --bg 8729` proxy form; the launchd-
  managed backend is what serves files.
- **launchd quirks.** `KeepAlive=true` will respawn the backend
  rapidly if it crashes on startup. The bootstrap step does a real
  liveness probe before declaring success so this fails loudly rather
  than silently flapping.
- **Apple Developer 2FA expiration.** Inherited from today's flow;
  the plugin's preflight surfaces the exact same error recipes as
  the current `deploy-ios.sh` (already in `references/troubleshooting.md`).
- **Index repo as SPOF for the listing.** If GitHub is unreachable,
  `git pull` fails and the listing falls back to the local clone
  with a "stale since <timestamp>" banner. New deploys queue the
  push for retry.
