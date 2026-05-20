#!/usr/bin/env bash
# Increment CFBundleVersion (CURRENT_PROJECT_VERSION) by one each time
# an Archive runs. Invoked as the Lillist-iOS scheme's Archive
# pre-action — Xcode 26+ runs scheme pre-actions for both IDE and CLI
# (`xcodebuild archive`) invocations, so this single hook covers
# every archive path.
#
# Can also be run manually if you ever need to bump out of band.
#
# Apps/Config/Signing.xcconfig includes BuildNumber.xcconfig, so the
# new value flows through every target that shares the project's
# xcconfig. xcconfig precedence is above `settings.base` in
# project.yml, so the bumped value wins over the fallback there.
#
# BuildNumber.xcconfig is **tracked in git** — the counter is the
# single source of truth for build numbers across all machines and
# archives. After bumping, commit the change so the next archive (on
# any machine) starts from the correct value.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

XCCONFIG="$REPO_ROOT/Apps/Config/BuildNumber.xcconfig"

PREV=0
if [[ -f $XCCONFIG ]]; then
    PREV=$(awk -F'=' '/^CURRENT_PROJECT_VERSION/ {gsub(/[[:space:]]/, "", $2); print $2}' "$XCCONFIG" 2>/dev/null || true)
fi
[[ ${PREV:-} =~ ^[0-9]+$ ]] || PREV=0

NEXT=$((PREV + 1))

cat > "$XCCONFIG" <<EOF
// Tracked in git — the single source of truth for Lillist's build number.
// Incremented automatically by the Lillist-iOS scheme's Archive
// pre-action (Tools/Deploy/bump-build-number.sh). Commit after each
// archive so the counter never regresses.
CURRENT_PROJECT_VERSION = $NEXT
EOF

echo "note: Lillist CFBundleVersion -> $NEXT (previous: $PREV)"
echo "note: commit Apps/Config/BuildNumber.xcconfig to lock in the bump."
