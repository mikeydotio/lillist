#!/usr/bin/env bash
#
# check-macos-extension-sandbox.sh
#
# Guards the defect class behind LIL-92: a macOS app extension shipping
# WITHOUT App Sandbox, and — the underlying mistake — a macOS target pointed at
# an iOS target's entitlements file.
#
# macOS app extensions must be sandboxed. An unsandboxed extension inside a
# sandboxed host app is not a valid configuration: the system declines to
# register it, so `pluginkit` never lists it, WidgetKit never launches it, and
# the widget silently never renders. There is no build error, no crash, and no
# log — the widget simply does nothing, which is why this shipped undetected
# from 2026-07-01 to 2026-07-31.
#
# This is the SECOND instance of the cross-platform entitlements-sharing
# mistake in this repo. The first is recorded in CLAUDE.md as "macOS push
# entitlement — FIXED (2026-06-24)": the main macOS app declared iOS's
# `aps-environment` instead of the prefixed `com.apple.developer.aps-environment`
# and had it silently stripped. Both share a root: an entitlement key that is
# wrong for the platform produces no diagnostic, only missing capability.
#
# Checks, per macOS app-extension target:
#   1. CODE_SIGN_ENTITLEMENTS is set at all.
#   2. It does NOT point at a file another platform's target also uses
#      (detected structurally: the same path referenced by an iOS target).
#   3. The resolved entitlements file declares com.apple.security.app-sandbox
#      = true.
#   4. It does NOT declare the iOS-only bare `aps-environment` key, which macOS
#      silently strips.
#
# Prerequisite: the Xcode projects must already be generated
# (`(cd Apps && xcodegen generate --spec project.yml --project .)` and the iOS
# equivalent) — this script only inspects them, matching the other CI guards'
# step ordering.
#
# Usage: run from anywhere; paths are repo-root-relative internally.
#   Tools/CI/check-macos-extension-sandbox.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

MACOS_SPEC="Apps/project.yml"
IOS_SPEC="Apps/Lillist-iOS/project.yml"

fail() { printf '\n\033[31mFAIL\033[0m  %s\n' "$1" >&2; exit 1; }
pass() { printf '\033[32m  ok\033[0m  %s\n' "$1"; }

[ -f "${MACOS_SPEC}" ] || fail "missing ${MACOS_SPEC}"

echo "Checking macOS app-extension sandbox entitlements…"

# Enumerate macOS targets of type app-extension, and the entitlements path each
# one signs with. Parsed from the xcodegen spec (the source of truth) rather
# than the generated pbxproj, so a drifted-but-uncommitted project cannot mask
# a bad spec.
ROWS_RAW="$(python3 Tools/CI/macos_extension_entitlements.py "${MACOS_SPEC}" "${IOS_SPEC}")"

[ -n "${ROWS_RAW}" ] || fail "no macOS app-extension targets found in ${MACOS_SPEC} — parser broken or targets removed"

while IFS=$'\t' read -r TARGET ENT SHARED; do
  [ -n "${TARGET}" ] || continue

  [ -n "${ENT}" ] || fail "${TARGET}: no CODE_SIGN_ENTITLEMENTS set. A macOS app extension must sign with an entitlements file declaring App Sandbox."

  [ "${SHARED}" = "ok" ] || fail "${TARGET}: signs with '${ENT}', which an iOS target also uses. Cross-platform entitlements sharing is the LIL-92 root cause — macOS needs its own file (App Sandbox is required on macOS and meaningless on iOS; push uses a different key spelling)."

  [ -f "${ENT}" ] || fail "${TARGET}: CODE_SIGN_ENTITLEMENTS points at '${ENT}', which does not exist."

  if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "${ENT}" 2>/dev/null | grep -qi '^true$'; then
    fail "${TARGET}: '${ENT}' does not declare com.apple.security.app-sandbox = true. macOS app extensions must be sandboxed; an unsandboxed one is silently never registered by the system (no build error, no crash — the extension just never runs). See LIL-92."
  fi

  if /usr/libexec/PlistBuddy -c 'Print :aps-environment' "${ENT}" >/dev/null 2>&1; then
    fail "${TARGET}: '${ENT}' declares the iOS-only bare 'aps-environment' key. macOS requires 'com.apple.developer.aps-environment'; the bare key is silently stripped. See CLAUDE.md, 'macOS push entitlement — FIXED (2026-06-24)'."
  fi

  pass "${TARGET} → ${ENT} (sandboxed, macOS-specific)"
done <<< "${ROWS_RAW}"

echo "macOS app-extension sandbox guard passed."
