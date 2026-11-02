#!/usr/bin/env bash
# Prints the UDID of the named simulator, or exits 1.
set -euo pipefail
xcrun simctl list devices -j | python3 -c '
import json,sys
name=sys.argv[1]
d=json.load(sys.stdin)["devices"]
for rt,devs in d.items():
    for dev in devs:
        if dev["name"]==name and dev.get("isAvailable",True):
            print(dev["udid"]); sys.exit(0)
sys.exit(1)
' "$1"
