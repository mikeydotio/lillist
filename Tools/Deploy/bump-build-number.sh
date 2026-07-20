#!/usr/bin/env bash
# Increment CFBundleVersion (CURRENT_PROJECT_VERSION) by one each time
# an Archive runs. Invoked as an Xcode scheme's Archive pre-action —
# Xcode 26+ runs scheme pre-actions for both IDE and CLI
# (`xcodebuild archive`) invocations, so this single hook covers
# every archive path.
#
# Can also be run manually if you ever need to bump out of band.
#
# Lillist-iOS and Lillist-macOS keep SEPARATE, dedicated build-number
# counters (BuildNumber.xcconfig / BuildNumber-macOS.xcconfig — see issue
# #55, where the macOS app previously hardcoded CFBundleVersion and never
# incremented it, breaking Sparkle's "is this newer?" check). Pass the
# target xcconfig as $1; each platform's Signing*.xcconfig #includes its
# own counter file, so the new value flows through every target that
# shares that project's xcconfig. xcconfig precedence is above
# `settings.base` in project.yml, so the bumped value wins over the
# fallback there.
#
# The target xcconfig is **tracked in git** — the counter is the single
# source of truth for that platform's build numbers across all machines
# and archives. After bumping, commit the change so the next archive (on
# any machine) starts from the correct value.
#
# Usage: bump-build-number.sh [path/to/BuildNumber*.xcconfig]
#        Defaults to Apps/Config/BuildNumber.xcconfig (iOS) for backward
#        compatibility with the existing Lillist-iOS scheme pre-action.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

XCCONFIG="${1:-$REPO_ROOT/Apps/Config/BuildNumber.xcconfig}"
LABEL="$(basename "$XCCONFIG" .xcconfig)"

PREV=0
if [[ -f $XCCONFIG ]]; then
    PREV=$(awk -F'=' '/^CURRENT_PROJECT_VERSION/ {gsub(/[[:space:]]/, "", $2); print $2}' "$XCCONFIG" 2>/dev/null || true)
fi
[[ ${PREV:-} =~ ^[0-9]+$ ]] || PREV=0

NEXT=$((PREV + 1))

cat > "$XCCONFIG" <<EOF
// Tracked in git — the single source of truth for this platform's build
// number. Incremented automatically by its Xcode scheme's Archive
// pre-action (Tools/Deploy/bump-build-number.sh). Commit after each
// archive so the counter never regresses.
CURRENT_PROJECT_VERSION = $NEXT
EOF

echo "note: $LABEL CFBundleVersion -> $NEXT (previous: $PREV)"
echo "note: commit $XCCONFIG to lock in the bump."
