#!/usr/bin/env python3
"""Enumerate macOS app-extension targets and the entitlements file each signs with.

Support for Tools/CI/check-macos-extension-sandbox.sh (LIL-92). Emits one
TSV row per macOS app-extension target:

    <target-name>\t<repo-relative-entitlements-path>\t<ok|SHARED_WITH_IOS>

Reads the xcodegen specs rather than the generated pbxproj, so a drifted or
uncommitted project can never mask a bad spec.

Deliberately dependency-free: CI runners have python3 but not necessarily
PyYAML, and the shape needed here (target name -> type / platform /
CODE_SIGN_ENTITLEMENTS) is flat enough to read with an indent-aware scan.

Usage:
    macos_extension_entitlements.py <macos-spec.yml> <ios-spec.yml>
"""

import os
import re
import sys


def targets(path):
    """Return {target_name: {type, platform, entitlements}} from an xcodegen spec."""
    found, name, current, in_targets = {}, None, {}, False
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if re.match(r"^targets:\s*$", line):
                in_targets = True
                continue
            if in_targets and re.match(r"^\S", line):
                break  # dedented out of the targets block
            if not in_targets:
                continue

            header = re.match(r"^  (\S+):\s*$", line)  # target name at 2 spaces
            if header:
                if name:
                    found[name] = current
                name, current = header.group(1), {}
                continue

            for key in ("type", "platform"):
                match = re.match(rf"^\s+{key}:\s*(\S+)\s*$", line)
                if match:
                    current[key] = match.group(1).strip("\"'")

            entitlements = re.match(r"^\s+CODE_SIGN_ENTITLEMENTS:\s*(\S+)\s*$", line)
            if entitlements:
                current["entitlements"] = entitlements.group(1).strip("\"'")

    if name:
        found[name] = current
    return found


def normalize(spec_path, entitlements_path):
    """Resolve a spec-relative entitlements path to a repo-relative one.

    The two specs sit at different depths and so use different relative
    prefixes (../ vs ../../) for the same file; normalizing lets them compare.
    """
    return os.path.normpath(os.path.join(os.path.dirname(spec_path), entitlements_path))


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    macos_spec, ios_spec = argv[1], argv[2]
    macos_targets = targets(macos_spec)
    ios_targets = targets(ios_spec) if os.path.exists(ios_spec) else {}

    ios_entitlements = {
        normalize(ios_spec, target["entitlements"])
        for target in ios_targets.values()
        if "entitlements" in target
    }

    for name, target in sorted(macos_targets.items()):
        if target.get("type") != "app-extension":
            continue
        # A target in the macOS spec with no explicit platform inherits macOS.
        if target.get("platform") not in (None, "macOS"):
            continue

        declared = target.get("entitlements", "")
        resolved = normalize(macos_spec, declared) if declared else ""
        shared = "SHARED_WITH_IOS" if resolved and resolved in ios_entitlements else "ok"
        print(f"{name}\t{resolved}\t{shared}")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
