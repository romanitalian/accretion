#!/usr/bin/env bash
# Resolve a single simulator UDID by exact device name when multiple runtimes share the same name.
# Picks the highest iOS runtime (newest). Prints nothing if no match.
# Usage: resolve_screenshot_sim_udid.sh "iPad Pro 13-inch (M5)"
set -euo pipefail
NAME="${1:?device name required}"
exec python3 - "$NAME" <<'PY'
import json, subprocess, sys

name = sys.argv[1]
raw = subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"],
    text=True,
)
data = json.loads(raw)
best_udid = None
best_key = ""
for runtime_key, devices in data.get("devices", {}).items():
    if "iOS" not in runtime_key and "xrOS" not in runtime_key:
        continue
    for d in devices:
        if d.get("name") != name:
            continue
        if d.get("isAvailable") is not True:
            continue
        udid = d.get("udid")
        if not udid:
            continue
        # Lexicographic sort on SimRuntime keys matches iOS version ordering for same major.
        if runtime_key > best_key:
            best_key = runtime_key
            best_udid = udid
if best_udid:
    print(best_udid)
PY
