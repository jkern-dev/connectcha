#!/usr/bin/env bash
# Usage: ensure-sim.sh "<name>" "<device type>" "<runtime id>"
# Creates the simulator if it doesn't exist and prints its UDID.
set -euo pipefail
name="$1"; devtype="$2"; runtime="$3"
existing=$(xcrun simctl list devices -j | python3 -c '
import json,sys
name=sys.argv[1]
d=json.load(sys.stdin)["devices"]
for rt,devs in d.items():
    for dev in devs:
        if dev["name"]==name and dev.get("isAvailable",True):
            print(dev["udid"]); sys.exit(0)
' "$name" || true)
if [[ -n "$existing" ]]; then
  echo "$existing"
else
  xcrun simctl create "$name" "$devtype" "$runtime"
fi
