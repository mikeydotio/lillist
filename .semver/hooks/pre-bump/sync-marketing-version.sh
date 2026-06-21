#!/usr/bin/env bash
# sync-marketing-version.sh — keep the apps' MARKETING_VERSION in lockstep
# with the semver VERSION file.
#
# Runs as a semver **pre-bump** hook (the plugin invokes every executable
# `.semver/hooks/pre-bump/*.sh` with the bump context). Pre-bump fires
# BEFORE the `chore(release)` commit, so the edits this script makes are
# folded into that single commit (and covered by the version tag).
#
#   args: <phase> <bump_type> <old_version> <new_version> <project_dir>
#
# Why a bump hook and not a build-phase script or an Archive pre-action:
#   - A post-build script can't write the product Info.plist under
#     ENABLE_USER_SCRIPT_SANDBOXING at *archive* time (it lands in
#     UninstalledProducts/, outside the script sandbox's writable roots).
#   - An Archive pre-action that rewrites an xcconfig is off-by-one (the
#     current archive uses the settings resolved *before* the pre-action
#     ran — same reason BuildNumber.xcconfig ships the pre-bump value),
#     and deployit bumps VERSION immediately before archiving, so the
#     first archive after a bump would ship the previous version.
#   - The marketing version only changes at bump time, and deployit always
#     bumps before it archives — so syncing here is both correct and
#     sandbox-free. MARKETING_VERSION stays in project.yml (deployit reads
#     it from there); the pbxprojs are regenerated so the build agrees.
#
# See docs/engineering-notes.md (2026-06-20 entry) for the full history.

set -euo pipefail

NEW_VERSION="${4:-}"
PROJECT_DIR="${5:-}"

if [ -z "$NEW_VERSION" ] || [ -z "$PROJECT_DIR" ]; then
    echo "sync-marketing-version: missing new_version/project_dir args — skipping" >&2
    exit 0
fi

# Strip the semver `v` prefix; CFBundleShortVersionString must be numeric
# (e.g. 0.8.7), not "v0.8.7".
marketing="${NEW_VERSION#v}"

SPECS=(
    "$PROJECT_DIR/Apps/Lillist-iOS/project.yml"
    "$PROJECT_DIR/Apps/project.yml"
)

changed=()
for spec in "${SPECS[@]}"; do
    if [ ! -f "$spec" ]; then
        echo "sync-marketing-version: $spec not found — skipping" >&2
        continue
    fi
    # Replace the value of the (indented) MARKETING_VERSION key in place.
    # BSD sed (macOS) in-place form.
    sed -i '' -E "s/^([[:space:]]*MARKETING_VERSION:[[:space:]]*).*/\1\"${marketing}\"/" "$spec"

    if ! grep -Eq "^[[:space:]]*MARKETING_VERSION:[[:space:]]*\"${marketing}\"" "$spec"; then
        echo "sync-marketing-version: WARNING — no MARKETING_VERSION key updated in $spec" >&2
    else
        changed+=("$spec")
    fi
done

# Regenerate the pbxprojs so the build (which reads MARKETING_VERSION from
# the project-level settings baked into the pbxproj) agrees with project.yml.
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "sync-marketing-version: ERROR — xcodegen not found; pbxprojs would be" \
         "stale relative to project.yml. Install xcodegen and re-run the bump." >&2
    exit 1
fi

( cd "$PROJECT_DIR/Apps/Lillist-iOS" && xcodegen generate --spec project.yml --project . >/dev/null )
( cd "$PROJECT_DIR/Apps"             && xcodegen generate --spec project.yml --project . >/dev/null )

# Stage the synced files so they're guaranteed to land in the chore(release)
# commit regardless of how the bump handles a dirty tree.
git -C "$PROJECT_DIR" add \
    Apps/Lillist-iOS/project.yml \
    Apps/Lillist-iOS/Lillist-iOS.xcodeproj/project.pbxproj \
    Apps/project.yml \
    Apps/Lillist-macOS.xcodeproj/project.pbxproj >/dev/null 2>&1 || true

echo "sync-marketing-version: MARKETING_VERSION -> ${marketing} (${#changed[@]} spec(s) updated, pbxprojs regenerated)"
