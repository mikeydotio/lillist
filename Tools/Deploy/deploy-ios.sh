#!/usr/bin/env bash
# Build a Development-signed Lillist .ipa and stage it for OTA install
# via Tailscale Serve. See Tools/Deploy/README.md for one-time setup.

set -euo pipefail

# ----- Paths -------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY_DIR="$HOME/Library/Application Support/Lillist-Deploy"
SERVE_DIR="$DEPLOY_DIR/serve"
BUILD_DIR="$DEPLOY_DIR/builds"
ARCHIVE_PATH="$BUILD_DIR/Lillist.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
# Local HTTP server backend port. Tailscale Serve proxies HTTPS:443 → this.
# Why: the Mac App Store Tailscale variant can't serve filesystem paths
# directly (sandbox restriction), so we run a localhost HTTP server and
# proxy through Tailscale Serve.
SERVE_PORT=8729
readonly SCRIPT_DIR REPO_ROOT DEPLOY_DIR SERVE_DIR BUILD_DIR ARCHIVE_PATH EXPORT_DIR SERVE_PORT

# ----- Output helpers ----------------------------------------------------

if [[ -t 1 ]]; then
  C_HEAD=$'\033[1;36m'
  C_WARN=$'\033[1;33m'
  C_ERR=$'\033[1;31m'
  C_DIM=$'\033[2m'
  C_RESET=$'\033[0m'
else
  C_HEAD='' ; C_WARN='' ; C_ERR='' ; C_DIM='' ; C_RESET=''
fi

say()  { printf '%s==>%s %s\n'   "$C_HEAD" "$C_RESET" "$*"; }
warn() { printf '%swarn%s %s\n'  "$C_WARN" "$C_RESET" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$C_ERR"  "$C_RESET" "$*" >&2; exit 1; }

# Escape backslash and ampersand for safe use as a sed replacement
# string. Without this, `&` in the replacement is interpreted as the
# matched text (sed's "ampersand magic"), corrupting any value that
# contains literal `&` — notably the HTML-encoded itms-services URL.
sed_escape() {
  printf '%s' "$1" | sed -e 's/[&\\]/\\&/g'
}

# ----- Local HTTP server -------------------------------------------------

ensure_http_server() {
  local pid
  pid=$(lsof -ti:"$SERVE_PORT" -sTCP:LISTEN 2>/dev/null | head -1 || true)
  if [[ -n $pid ]]; then
    say "Local HTTP server already up on :$SERVE_PORT (pid $pid)"
    return
  fi

  mkdir -p "$SERVE_DIR" "$DEPLOY_DIR/logs"
  say "Starting localhost HTTP server on :$SERVE_PORT"
  nohup python3 -m http.server --bind 127.0.0.1 --directory "$SERVE_DIR" "$SERVE_PORT" \
    > "$DEPLOY_DIR/logs/http-server.log" 2>&1 &
  local server_pid=$!
  disown "$server_pid" 2>/dev/null || true
  echo "$server_pid" > "$DEPLOY_DIR/http-server.pid"

  # Give it a beat to bind, then verify.
  local tries=0
  while (( tries < 20 )); do
    if curl -fs -o /dev/null "http://127.0.0.1:$SERVE_PORT/"; then
      return
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
      die "HTTP server died on startup. See $DEPLOY_DIR/logs/http-server.log"
    fi
    sleep 0.1
    ((tries++))
  done
  die "HTTP server did not become ready on :$SERVE_PORT within 2s."
}

# ----- Pre-flight --------------------------------------------------------

preflight() {
  say "Pre-flight"

  cd "$REPO_ROOT"

  [[ -d Lillist.xcworkspace ]] \
    || die "Lillist.xcworkspace not found at $REPO_ROOT"

  command -v xcodebuild >/dev/null \
    || die "xcodebuild not found — install Xcode and run 'xcode-select --install'"

  command -v xcodegen >/dev/null \
    || die "xcodegen not found — 'brew install xcodegen'"

  # Refresh pbxprojs from project.yml. Idempotent.
  (cd "$REPO_ROOT/Apps/Lillist-iOS" && xcodegen generate --spec project.yml --project . >/dev/null)
  (cd "$REPO_ROOT/Apps"             && xcodegen generate --spec project.yml --project . >/dev/null)

  # Tailscale must be reachable.
  command -v tailscale >/dev/null \
    || die "tailscale not found — install from https://tailscale.com/download"
  tailscale status >/dev/null 2>&1 \
    || die "tailscale is not up. Start it (menubar app or 'sudo tailscale up')."

  # Local HTTP server (Tailscale Serve proxy backend). See header comment.
  ensure_http_server

  # Signing.local.xcconfig must exist with a team ID.
  local signing_local="$REPO_ROOT/Apps/Config/Signing.local.xcconfig"
  [[ -f $signing_local ]] \
    || die "Missing $signing_local — copy Signing.local.xcconfig.example and fill in your Apple Developer Team ID."
  grep -q '^LOCAL_DEVELOPMENT_TEAM' "$signing_local" \
    || die "$signing_local must define LOCAL_DEVELOPMENT_TEAM."

  # Base URL must be set, no trailing slash.
  if [[ -z "${LILLIST_DEPLOY_BASE_URL:-}" ]]; then
    local suggested
    suggested=$(tailscale status --json 2>/dev/null \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null \
      || true)
    if [[ -n $suggested ]]; then
      die $'LILLIST_DEPLOY_BASE_URL not set. Likely value:\n    export LILLIST_DEPLOY_BASE_URL="https://'"$suggested"$'/lillist"\nAdd that to your shell rc and re-run.'
    fi
    die "LILLIST_DEPLOY_BASE_URL not set. See Tools/Deploy/README.md."
  fi
  LILLIST_DEPLOY_BASE_URL="${LILLIST_DEPLOY_BASE_URL%/}"

  # qrencode is optional but nicer.
  command -v qrencode >/dev/null \
    || warn "qrencode not installed — install URL will print but no QR code ('brew install qrencode')."
}

# ----- Build metadata ----------------------------------------------------

derive_metadata() {
  say "Derive build metadata"

  COMMIT_SHORT=$(git -C "$REPO_ROOT" rev-parse --short HEAD)
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

  MARKETING_VERSION=$(grep -E '^[[:space:]]*MARKETING_VERSION:' "$REPO_ROOT/Apps/Lillist-iOS/project.yml" \
    | head -1 \
    | sed -E 's/.*"([^"]+)".*/\1/')
  [[ -n $MARKETING_VERSION ]] \
    || die "Could not parse MARKETING_VERSION from Apps/Lillist-iOS/project.yml"

  if ! git -C "$REPO_ROOT" diff --quiet HEAD 2>/dev/null; then
    warn "Working tree has uncommitted changes — landing page will still build, but the commit SHA shown won't match the archive."
  fi

  printf '  marketing version : %s\n' "$MARKETING_VERSION"
  printf '  commit            : %s\n' "$COMMIT_SHORT"
  # BUILD_NUMBER is set after the archive completes — see read_archive_build_number.
}

read_archive_build_number() {
  local plist="$ARCHIVE_PATH/Products/Applications/Lillist.app/Info.plist"
  [[ -f $plist ]] || die "Built Info.plist not found at $plist"
  BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")
  printf '  build number      : %s (set by Archive pre-action)\n' "$BUILD_NUMBER"
}

# ----- Archive -----------------------------------------------------------

archive_app() {
  say "Archive (Debug)"
  mkdir -p "$BUILD_DIR"
  rm -rf "$ARCHIVE_PATH"

  # CFBundleVersion is bumped by the scheme's Archive pre-action
  # (Tools/Deploy/bump-build-number.sh → Apps/Config/BuildNumber.xcconfig).
  # That runs whether you invoke from here or Xcode UI, so no CLI override here.
  local rc=0
  xcodebuild \
    -workspace Lillist.xcworkspace \
    -scheme Lillist-iOS \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive \
  || rc=$?

  if (( rc != 0 )); then
    cat >&2 <<'EOF'

Archive failed. Common causes:

  1. Apple ID 2FA session expired
     Fix: open Xcode → Settings → Accounts → re-enter 2FA, then re-run.

  2. Keychain locked
     Fix: security unlock-keychain ~/Library/Keychains/login.keychain-db
     then re-run.

  3. iPhone UDID not registered with the developer account
     Fix: connect the iPhone to Xcode and run-on-device once to register
     the device. Re-run the deploy script after.

  4. Stale provisioning profile
     Fix: open the Xcode project, click any target → Signing &
     Capabilities → toggle "Automatically manage signing" off and back
     on. Re-run.

EOF
    exit "$rc"
  fi
}

# ----- Export ------------------------------------------------------------

export_ipa() {
  say "Export Development-signed .ipa"
  rm -rf "$EXPORT_DIR"
  mkdir -p "$EXPORT_DIR"

  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates

  [[ -f $EXPORT_DIR/Lillist.ipa ]] \
    || die "Export did not produce $EXPORT_DIR/Lillist.ipa"
}

# ----- Stage serve dir ---------------------------------------------------

stage_serve() {
  say "Stage serve dir"

  # On-disk layout under $SERVE_DIR must mirror the URL path. Tailscale
  # Serve proxies the tailnet root to 127.0.0.1:$SERVE_PORT, so a base
  # URL like `https://host/lillist` requires files at
  # `$SERVE_DIR/lillist/`. Extract the path component from the base URL
  # so callers can host at any prefix (or none) without re-editing
  # this script.
  local stage_subdir stage_root
  stage_subdir=$(python3 - "$LILLIST_DEPLOY_BASE_URL" <<'PY'
import sys
from urllib.parse import urlparse
print(urlparse(sys.argv[1]).path.strip("/"))
PY
)

  if [[ -n $stage_subdir ]]; then
    stage_root="$SERVE_DIR/$stage_subdir"
    # Wipe previous content at this path so stale files don't linger,
    # and sweep any same-named siblings older versions of this script
    # left at the SERVE_DIR root — those would otherwise keep getting
    # served at the bare host URL alongside the new build.
    rm -rf "$stage_root"
    rm -f "$SERVE_DIR/Lillist.ipa" \
          "$SERVE_DIR/manifest.plist" \
          "$SERVE_DIR/index.html"
  else
    stage_root="$SERVE_DIR"
    rm -f "$stage_root/Lillist.ipa" \
          "$stage_root/manifest.plist" \
          "$stage_root/index.html"
  fi
  mkdir -p "$stage_root"

  mv -f "$EXPORT_DIR/Lillist.ipa" "$stage_root/Lillist.ipa"

  local ipa_url="$LILLIST_DEPLOY_BASE_URL/Lillist.ipa"
  local manifest_url="$LILLIST_DEPLOY_BASE_URL/manifest.plist"
  local itms_url_raw="itms-services://?action=download-manifest&url=$manifest_url"
  local itms_url_html="${itms_url_raw//&/&amp;}"

  sed \
    -e "s|{{BUNDLE_ID}}|$(sed_escape "io.mikeydotio.Lillist")|g" \
    -e "s|{{BUNDLE_VERSION}}|$(sed_escape "$MARKETING_VERSION")|g" \
    -e "s|{{IPA_URL}}|$(sed_escape "$ipa_url")|g" \
    -e "s|{{TITLE}}|$(sed_escape "Lillist")|g" \
    "$SCRIPT_DIR/manifest.template.plist" \
    > "$stage_root/manifest.plist"

  sed \
    -e "s|{{INSTALL_URL}}|$(sed_escape "$itms_url_html")|g" \
    -e "s|{{VERSION}}|$(sed_escape "$MARKETING_VERSION (build $BUILD_NUMBER)")|g" \
    -e "s|{{COMMIT}}|$(sed_escape "$COMMIT_SHORT")|g" \
    -e "s|{{TIMESTAMP}}|$(sed_escape "$TIMESTAMP")|g" \
    "$SCRIPT_DIR/index.template.html" \
    > "$stage_root/index.html"

  if grep -l '{{' "$stage_root"/*.plist "$stage_root"/*.html 2>/dev/null; then
    die "Unsubstituted placeholders remain in serve dir."
  fi

  # Remember the raw itms-services URL for the terminal print step.
  ITMS_URL="$itms_url_raw"
}

# ----- Print install info ------------------------------------------------

print_install_info() {
  printf '\n'
  say "Install info"
  printf '\n'
  printf '  %sLanding%s  %s/\n'   "$C_HEAD" "$C_RESET" "$LILLIST_DEPLOY_BASE_URL"
  printf '  %sDirect%s   %s\n\n'  "$C_DIM"  "$C_RESET" "$ITMS_URL"

  if command -v qrencode >/dev/null; then
    qrencode -t ANSIUTF8 -m 1 "$LILLIST_DEPLOY_BASE_URL/"
    printf '\n'
  fi

  cat <<EOF
On iPhone:
  1. Open the landing page in Safari (bookmark it first time).
  2. Tap "Install".
  3. First time only: Settings → General → VPN & Device Management
     → trust your Apple Developer team, then retry the install.

EOF
}

# ----- Cleanup -----------------------------------------------------------

cleanup_intermediates() {
  rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
}

# ----- Main --------------------------------------------------------------

main() {
  preflight
  derive_metadata
  # CFBundleVersion is incremented by the Lillist-iOS scheme's Archive
  # pre-action (Tools/Deploy/bump-build-number.sh). Xcode 26+ fires
  # scheme pre/post-actions for both IDE and `xcodebuild` archive
  # invocations, so we don't need an extra call here.
  archive_app
  read_archive_build_number
  export_ipa
  stage_serve
  cleanup_intermediates
  print_install_info
}

main "$@"
