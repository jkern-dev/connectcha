#!/usr/bin/env bash
# Delivers stubbed pushes to the simulators so notification banners really
# appear during the demo. The app registers the token "sim:<SIMULATOR_UDID>"
# in debug builds; send-push (APNS_MODE=stub) records each delivery in
# push_deliveries; this loop hands them to `xcrun simctl push`. The simulator
# does not run Notification Service Extensions, so the bridge applies the same
# saved-name rewrite from the simulator's App Group match map.
#
# Usage: scripts/push-bridge.sh [--once]
set -euo pipefail
cd "$(dirname "$0")/.."
DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
BUNDLE_ID="com.connectcha.app"
TMP=$(mktemp -d)

deliver_once() {
  local rows
  rows=$(psql "$DB_URL" -At -c "select public.push_pending_deliveries()")
  [[ -z "$rows" || "$rows" == "[]" ]] && return 0
  local ids=()
  while IFS=$'\t' read -r id token payload; do
    [[ -z "$id" ]] && continue
    local udid="${token#sim:}"
    # The simulator does not run Notification Service Extensions for simctl
    # pushes, so apply the extension's rewrite here from the same on-device
    # match map (App Group container) it would read: saved contact name in,
    # profile name out. Real phones do this inside the extension.
    local group_dir
    group_dir=$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" groups 2>/dev/null | awk '{print $2}' | head -1)
    printf '%s' "$payload" | python3 -c 'import sys, json
payload = json.load(sys.stdin)
path = sys.argv[1] + "/match-map.json" if sys.argv[1] else ""
names = {}
try:
    m = json.load(open(path))
    e = m.get("entries", [])
    if isinstance(e, list):
        names = {str(e[i]).lower(): e[i + 1].get("savedName") for i in range(0, len(e) - 1, 2)}
    elif isinstance(e, dict):
        names = {k.lower(): v.get("savedName") for k, v in e.items()}
except Exception:
    pass
actor = str(payload.get("actor_id", "")).lower()
template = payload.get("body_template")
if actor in names and names[actor] and template:
    payload["aps"]["alert"]["body"] = template.replace("{name}", names[actor])
json.dump(payload, sys.stdout)' "$group_dir" > "$TMP/$id.json"
    if xcrun simctl push "$udid" "$BUNDLE_ID" "$TMP/$id.json" >/dev/null 2>&1; then
      echo "delivered push $id to simulator ${udid:0:8}…"
    else
      echo "simulator ${udid:0:8}… not booted; push $id marked delivered anyway" >&2
    fi
    ids+=("$id")
  done < <(printf '%s' "$rows" | python3 -c 'import sys, json
for d in json.load(sys.stdin):
    print("%s\t%s\t%s" % (d["id"], d["token"], json.dumps(d["payload"])))')
  if ((${#ids[@]})); then
    local list; list=$(IFS=,; echo "${ids[*]}")
    psql "$DB_URL" -q -c "select public.push_mark_delivered(array[$list]::bigint[])" >/dev/null
  fi
}

if [[ "${1:-}" == "--once" ]]; then
  deliver_once
  exit 0
fi
echo "push bridge running (Ctrl-C to stop)"
while true; do
  deliver_once || true
  sleep 2
done
