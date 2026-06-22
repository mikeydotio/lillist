#!/usr/bin/env bash
#
# check-no-team-id.sh
#
# Fails if a literal 10-character Apple Developer Team ID appears in any
# tracked *.pbxproj or *.xcconfig. The only DEVELOPMENT_TEAM value allowed
# in committed files is the `$(LOCAL_DEVELOPMENT_TEAM)` placeholder, which
# resolves at build time from the gitignored Apps/Config/Signing.local.xcconfig.
#
# This guards the exact regression that leaked two Team IDs into project.pbxproj
# before the repo went public: xcodegen / Xcode auto-mirror the *resolved*
# DEVELOPMENT_TEAM into the project file, defeating the indirection unless the
# local override is absent at generation time.
#
# Usage: run from anywhere; scans tracked files via `git grep`.
#   Tools/CI/check-no-team-id.sh
#
# Also usable as a pre-commit hook — symlink or call it from .git/hooks/pre-commit.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

# A Team ID is exactly 10 uppercase letters/digits. Allow an optional opening
# quote (pbxproj sometimes quotes values); the `$(...)` placeholder and an
# empty/`""` value never match.
PATTERN='DEVELOPMENT_TEAM = "?[A-Z0-9]{10}'

MATCHES="$(git grep -nE "${PATTERN}" -- '*.pbxproj' '*.xcconfig' || true)"

if [[ -n "${MATCHES}" ]]; then
  echo "ERROR: literal Apple Developer Team ID found in committed files:" >&2
  echo "${MATCHES}" | sed 's/^/  /' >&2
  echo >&2
  echo "DEVELOPMENT_TEAM must use the \$(LOCAL_DEVELOPMENT_TEAM) placeholder." >&2
  echo "The real Team ID belongs only in the gitignored" >&2
  echo "Apps/Config/Signing.local.xcconfig (see Signing.local.xcconfig.example)." >&2
  exit 1
fi

echo "==> OK: no literal Team ID in tracked pbxproj/xcconfig"
