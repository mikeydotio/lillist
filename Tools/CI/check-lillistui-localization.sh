#!/usr/bin/env bash
#
# check-lillistui-localization.sh
#
# Fails if any localizable string used in LillistUI source is missing
# from Resources/Localizable.xcstrings. Re-runs the compiler's string
# extraction (-emit-localized-strings) and diffs the extracted keys
# against the committed catalog.
#
# We diff keys directly with jq rather than `xcstringstool sync` because
# `sync` does not merge SwiftPM-emitted .stringsdata in the current
# toolchain (it exits 0 and changes nothing).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_PATH="${REPO_ROOT}/Packages/LillistUI"
CATALOG="${PACKAGE_PATH}/Sources/LillistUI/Resources/Localizable.xcstrings"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "${SCRATCH}"' EXIT

echo "==> Building LillistUI with string extraction"
swift build --package-path "${PACKAGE_PATH}" \
  -Xswiftc -emit-localized-strings \
  -Xswiftc -emit-localized-strings-path -Xswiftc "${SCRATCH}" >/dev/null

echo "==> Collecting extracted keys"
jq -r '.tables.Localizable[]?.key' "${SCRATCH}"/*.stringsdata 2>/dev/null \
  | sort -u > "${SCRATCH}/extracted.txt"

echo "==> Collecting catalog keys"
jq -r '.strings | keys[]' "${CATALOG}" | sort -u > "${SCRATCH}/catalog.txt"

# Keys present in source extraction but absent from the catalog.
MISSING="$(comm -23 "${SCRATCH}/extracted.txt" "${SCRATCH}/catalog.txt" || true)"

if [[ -n "${MISSING}" ]]; then
  echo "ERROR: localizable strings missing from ${CATALOG#${REPO_ROOT}/}:" >&2
  echo "${MISSING}" | sed 's/^/  - /' >&2
  echo >&2
  echo "Run Tools/CI/check-lillistui-localization.sh locally, then add the" >&2
  echo "missing keys to Localizable.xcstrings (empty {} entries are fine for" >&2
  echo "source-language-only strings)." >&2
  exit 1
fi

echo "==> OK: all $(wc -l < "${SCRATCH}/extracted.txt" | tr -d ' ') extracted keys are present in the catalog"
