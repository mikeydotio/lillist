# `Tools/Deploy` — on-demand iOS test build to phone

A single command (`./Tools/Deploy/deploy-ios.sh`) that produces a fresh
**Development**-signed `.ipa` of Lillist-iOS and stages it for OTA
install on your phone via Tailscale Serve. Round-trip is ≈3–5 min from
terminal to running build.

```
┌──────────────┐  archive +     ┌──────────────┐  proxy    ┌──────────────┐  install   ┌────────┐
│ deploy-ios.sh│ ─── export ──▶ │ python3      │ ◀──────── │ Tailscale    │ ── OTA  ─▶ │ iPhone │
│ on the Mac   │                │ http.server  │           │ Serve (HTTPS)│            │        │
└──────────────┘                │ 127.0.0.1    │           └──────────────┘            └────────┘
                                └──────────────┘
```

There is no TestFlight, App Store Connect, or GitHub Actions involved.
The `.ipa` never leaves your tailnet.

## Why it works (the short version)

iOS will install any `itms-services://` payload provided the device's
UDID is inside the embedded provisioning profile. **Development-method
profiles include the team's registered device list**, so a
Development-signed `.ipa` installs OTA on devices you've already used
in Xcode — no Ad-Hoc method required.

Tailscale Serve fronts a local backend with a real Let's Encrypt HTTPS
cert (`https://<machine>.<tailnet>.ts.net/`). iOS only accepts the
manifest over HTTPS; the tailnet hostname satisfies that for free.

### Why the localhost HTTP server in the middle

The Mac App Store variant of Tailscale **cannot serve filesystem paths
directly** (sandbox restriction; see
<https://tailscale.com/kb/1065/macos-variants>). It can, however, proxy
to a local HTTP backend. So the deploy script runs `python3 -m
http.server --bind 127.0.0.1 --directory <serve> <port>` (Python 3 is
already on every macOS) and Tailscale Serve proxies HTTPS:443 to that
port. From the iPhone's perspective it's still a single TLS connection
to the tailnet hostname.

The HTTP server persists across terminal sessions (started with
`nohup ... &`) but dies on reboot. The next deploy re-spawns it; the
pre-flight check is idempotent.

## One-time setup

### 1. Create the serve directory

```bash
mkdir -p "$HOME/Library/Application Support/Lillist-Deploy/serve"
```

### 2. Configure Tailscale Serve (HTTPS → localhost proxy)

```bash
tailscale serve --bg 8729
tailscale serve status   # confirm: https://<host>/ → http://127.0.0.1:8729
```

Tailscale Serve config persists across reboots (the daemon restores it
on startup). The Python HTTP server backend does NOT — the deploy
script will start it automatically when needed.

### 3. Set `LILLIST_DEPLOY_BASE_URL`

Find your tailnet hostname:

```bash
tailscale status --json | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))'
```

Add to your shell rc (`~/.zshrc`):

```bash
export LILLIST_DEPLOY_BASE_URL="https://<host>"
```

Source the file (`source ~/.zshrc`) or open a new terminal.

### 4. Confirm signing prerequisites

- `Apps/Config/Signing.local.xcconfig` exists with
  `LOCAL_DEVELOPMENT_TEAM = <your-10-char-team-id>` (see
  `Apps/Config/Signing.local.xcconfig.example`).
- Your iPhone is registered with your Apple Developer team — happens
  automatically the first time you run-on-device from Xcode. If you've
  never done that, plug in the phone, open Xcode, select it as a run
  destination once, run any target. Done.

### 5. (Optional) Install QR-code helper

```bash
brew install qrencode
```

Pretty terminal QR codes for the install URL. The script works without
it; you'll just paste the URL instead.

## Daily use

```bash
./Tools/Deploy/deploy-ios.sh
```

The script:
1. Refreshes `pbxproj` from `project.yml` (idempotent).
2. Ensures the localhost Python HTTP server is running (spawns one
   with `nohup` if not). Survives terminal close, dies on reboot.
3. Archives the `Lillist-iOS` scheme in Debug config.
4. Exports a Development-signed `.ipa`.
5. Stages the `.ipa`, manifest, and landing page into the serve dir.
6. Prints the install URL (and a QR code if `qrencode` is installed).

Open the landing page on your phone, tap Install. On first deploy iOS
will show an "untrusted developer" error — trust the team via
*Settings → General → VPN & Device Management → tap team → Trust*.
After that, every subsequent deploy installs silently.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `tailscale is not up` | Daemon stopped | Open the menubar app or `sudo tailscale up`. |
| `LILLIST_DEPLOY_BASE_URL not set` | Env var missing | Step 3 above. |
| Archive fails with "No profiles for X were found" | Apple ID 2FA session expired | Open Xcode → Settings → Accounts → re-enter 2FA. |
| Archive fails with `errSecInteractionNotAllowed` | Login keychain locked | `security unlock-keychain ~/Library/Keychains/login.keychain-db`. |
| Install dialog shows blank version | Manifest's `bundle-version` doesn't match `CFBundleShortVersionString` | Should be auto-handled; verify `MARKETING_VERSION` in `Apps/Lillist-iOS/project.yml` if it isn't. |
| Phone reports "Cannot install" | UDID not in profile, or another app with the same bundle ID already installed | Re-run-on-device from Xcode to refresh device registration; delete any conflicting install. |
| `xcodebuild` succeeds but install URL 404s | Tailscale Serve not configured, or local HTTP server down | `tailscale serve status` to confirm proxy; `lsof -ti:8729` to check the backend. Re-running the script restarts the backend. |
| Tailscale Serve fails with "Path serving not supported" | You're on the Mac App Store Tailscale variant | Use the proxy command in step 2 (`tailscale serve --bg 8729`), not a path-based command. The deploy script handles the HTTP backend automatically. |

### Sanity-check Tailscale Serve MIME types (run once after first deploy)

```bash
curl -sI "$LILLIST_DEPLOY_BASE_URL/manifest.plist" | grep -i content-type
curl -sI "$LILLIST_DEPLOY_BASE_URL/Lillist.ipa"     | grep -i content-type
```

`manifest.plist` should be `application/x-plist` (or `text/xml`); `.ipa`
should be `application/octet-stream`. iOS accepts all three; this is
just confirming Tailscale Serve isn't doing anything unusual.

## File layout

```
Tools/Deploy/
├── deploy-ios.sh             # The orchestrator (this is what you run)
├── ExportOptions.plist       # method=development, automatic signing
├── manifest.template.plist   # OTA manifest (substituted at deploy time)
├── index.template.html       # Phone landing page (substituted at deploy time)
└── README.md                 # ← you are here

~/Library/Application Support/Lillist-Deploy/
├── serve/                    # ← Python http.server serves this dir
│   ├── index.html            # Rendered landing page
│   ├── manifest.plist        # Rendered OTA manifest
│   └── Lillist.ipa           # Latest build
├── builds/                   # Intermediate xcarchive + export — cleaned after success
├── logs/                     # http-server.log (rotated by reboot)
└── http-server.pid           # PID of the running Python http.server
```

The serve directory location is fixed (matches what the script's
HTTP server binds to). The repo holds only the templates and the
script.

## Tearing down

```bash
# Stop Tailscale Serve
tailscale serve --https=443 off

# Stop the local HTTP server
kill "$(cat "$HOME/Library/Application Support/Lillist-Deploy/http-server.pid")" 2>/dev/null || true

# Remove all build artifacts
rm -rf "$HOME/Library/Application Support/Lillist-Deploy"

# Remove the env var from your shell rc (edit ~/.zshrc)
```
