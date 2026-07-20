#!/usr/bin/env bash
#
# check-macos-sparkle-feed.sh
#
# Guards the two silent regression classes behind issue #55 (a distributed
# Developer-ID macOS build whose Sparkle auto-updater could never actually
# complete an update):
#
#   1. A private/tailnet feed URL leaking back into SU_FEED_URL. Before the
#      fix, a gitignored per-machine Signing.local.xcconfig could override
#      the committed public default with a Tailscale-served URL, and that
#      override baked straight into distribution builds. SU_FEED_URL is now
#      pinned directly in Distribution.xcconfig with no override mechanism —
#      this resolves the FINAL build setting (whatever xcconfig chain
#      produced it) rather than grepping one file, so it fails on any future
#      reintroduction of an override, from any file.
#   2. CFBundleVersion silently going back to a hardcoded literal. Sparkle
#      decides "newer" purely by CFBundleVersion; before the fix, macOS
#      hardcoded it (20260517) and never incremented, so Sparkle always
#      reported "up to date" regardless of the feed. Info.plist must read
#      $(CURRENT_PROJECT_VERSION), and that build setting must resolve to a
#      plain integer.
#
# Prerequisite: the Lillist-macOS Xcode project must already be generated
# (`(cd Apps && xcodegen generate --spec project.yml --project .)`) — this
# script only inspects it, matching the other CI jobs' step ordering.
#
# Usage: run from anywhere; paths are repo-root-relative internally.
#   Tools/CI/check-macos-sparkle-feed.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

INFOPLIST="Apps/Lillist-macOS/Info.plist"
FAIL=0

echo "==> Checking ${INFOPLIST} for a hardcoded CFBundleVersion literal"
CFBUNDLEVERSION_VALUE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFOPLIST}")"
if [[ "${CFBUNDLEVERSION_VALUE}" != '$(CURRENT_PROJECT_VERSION)' ]]; then
  echo "ERROR: ${INFOPLIST}'s CFBundleVersion is '${CFBUNDLEVERSION_VALUE}', not the" >&2
  echo "\$(CURRENT_PROJECT_VERSION) build variable. A hardcoded literal never" >&2
  echo "increments, so Sparkle can never detect a newer macOS build (issue #55)." >&2
  FAIL=1
fi

if [[ ! -d "Apps/Lillist-macOS.xcodeproj" ]]; then
  echo "ERROR: Apps/Lillist-macOS.xcodeproj not found — run xcodegen first:" >&2
  echo "  (cd Apps && xcodegen generate --spec project.yml --project .)" >&2
  exit 1
fi

echo "==> Resolving Lillist-macOS build settings"
SETTINGS="$(xcodebuild -project Apps/Lillist-macOS.xcodeproj -scheme Lillist-macOS \
  -showBuildSettings CODE_SIGNING_ALLOWED=NO 2>/dev/null)"

SU_FEED_URL="$(awk -F'= ' '/^[[:space:]]*SU_FEED_URL = /{print $2; exit}' <<<"${SETTINGS}")"
echo "    SU_FEED_URL = ${SU_FEED_URL}"
if [[ -z "${SU_FEED_URL}" ]]; then
  echo "ERROR: SU_FEED_URL did not resolve to any value." >&2
  FAIL=1
elif [[ ! "${SU_FEED_URL}" =~ ^https://github\.com/ ]]; then
  echo "ERROR: SU_FEED_URL resolves to '${SU_FEED_URL}', not a public" >&2
  echo "https://github.com/... URL. A distributed build must never ship a" >&2
  echo "private, tailnet, or plain-http feed (issue #55) — check for a stray" >&2
  echo "override anywhere in the Signing*.xcconfig / Distribution.xcconfig chain." >&2
  FAIL=1
fi

BUILD_NUMBER="$(awk -F'= ' '/^[[:space:]]*CURRENT_PROJECT_VERSION = /{print $2; exit}' <<<"${SETTINGS}")"
echo "    CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}"
if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: CURRENT_PROJECT_VERSION resolves to '${BUILD_NUMBER}', not a plain" >&2
  echo "integer. Check Apps/Config/BuildNumber-macOS.xcconfig." >&2
  FAIL=1
fi

if [[ "${FAIL}" -ne 0 ]]; then
  exit 1
fi

echo "==> OK: Sparkle feed is public, and CFBundleVersion is a live, numeric build variable"
