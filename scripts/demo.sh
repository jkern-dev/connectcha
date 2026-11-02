#!/usr/bin/env bash
# One command to a running demo (DEMO.md):
#   1. start the local Supabase stack
#   2. reset the database to the demo seed and upload demo media
#   3. build the app for the simulator
#   4. create/boot two simulators, grant permissions, seed camera rolls
#   5. launch "Connectcha A" signed in as Josh and "Connectcha B" as Ana
#   6. serve the invite web page on http://127.0.0.1:8787
#   7. run the push bridge so notification banners appear on the simulators
#
# `scripts/demo.sh stop` shuts the simulators, the web server and the bridge down.
# `scripts/demo.sh as <sim A|B> <persona>` relaunches a simulator as another person,
#   e.g. `scripts/demo.sh as B ben`.
# `scripts/demo.sh allow <A|B>` answers the notification permission prompt for you.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
export SUPABASE_AUTH_SMS_TWILIO_AUTH_TOKEN=${SUPABASE_AUTH_SMS_TWILIO_AUTH_TOKEN:-placeholder-local-only}

APP="$ROOT/.derived/Build/Products/Debug-iphonesimulator/Connectcha.app"
BUNDLE_ID="com.connectcha.app"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-3"
STATE="$ROOT/.demo"
mkdir -p "$STATE"

persona_number() {
  case "$1" in
    josh) echo 15550000001 ;; mom|linda) echo 15550000002 ;; dad|robert) echo 15550000003 ;;
    ana) echo 15550000004 ;; ben) echo 15550000005 ;; priya) echo 15550000006 ;; sam) echo 15550000007 ;;
    nia|new|fresh) echo 15550000008 ;; spare) echo 15550000009 ;;
    1555*) echo "$1" ;;
    *) echo "unknown persona: $1 (use josh, mom, dad, ana, ben, priya, sam, nia)" >&2; exit 1 ;;
  esac
}

sim_id() { ./scripts/sim-id.sh "$1"; }

launch_as() {
  # $1 = simulator name, $2 = persona
  local udid number
  udid=$(sim_id "$1")
  number=$(persona_number "$2")
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  SIMCTL_CHILD_CONNECTCHA_DEMO=1 SIMCTL_CHILD_CONNECTCHA_AUTO_SIGNIN="$number" SIMCTL_CHILD_CONNECTCHA_START_TAB=home \
    xcrun simctl launch "$udid" "$BUNDLE_ID" -reset-session >/dev/null
  echo "$1 → signed in as $2 (+1 ${number:1:3} ${number:4:3} ${number:7:4})"
}

stop_all() {
  if [[ -f "$STATE/bridge.pid" ]]; then kill "$(cat "$STATE/bridge.pid")" 2>/dev/null || true; rm -f "$STATE/bridge.pid"; fi
  if [[ -f "$STATE/web.pid" ]]; then kill "$(cat "$STATE/web.pid")" 2>/dev/null || true; rm -f "$STATE/web.pid"; fi
  for name in "Connectcha A" "Connectcha B"; do
    udid=$(sim_id "$name" 2>/dev/null || true)
    [[ -n "$udid" ]] && xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  done
  echo "demo stopped (the Supabase stack is still running; 'make down' stops it)"
}

case "${1:-start}" in
  stop) stop_all; exit 0 ;;
  as)
    shift
    sim="${1:-}"; persona="${2:-}"
    [[ -z "$sim" || -z "$persona" ]] && { echo "usage: scripts/demo.sh as <A|B> <persona>"; exit 1; }
    launch_as "Connectcha $sim" "$persona"; exit 0 ;;
  allow)
    # Answer the notification permission prompt on a simulator with a tiny UI test.
    shift
    sim="${1:-A}"
    udid=$(sim_id "Connectcha $sim")
    ( cd ios && TEST_RUNNER_CONNECTCHA_HELPER=allow xcodebuild -project Connectcha.xcodeproj -scheme Connectcha \
        -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$ROOT/.derived" \
        -only-testing:ConnectchaUITests/DemoHelperUITests test 2>&1 | xcbeautify --quiet | grep -E "Executed|error" | head -2 )
    exit 0 ;;
  start) ;;
  *) echo "usage: scripts/demo.sh [start|stop|as <A|B> <persona>|allow <A|B>]"; exit 1 ;;
esac

echo "▶ 1/7 Starting the local Supabase stack"
if ! supabase status >/dev/null 2>&1; then
  supabase start >/dev/null
fi
[[ -f supabase/functions/.env ]] || cp supabase/functions/.env.example supabase/functions/.env

echo "▶ 2/7 Resetting the database to the demo seed and uploading demo media"
supabase db reset >/dev/null
./scripts/seed-media.sh >/dev/null
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -At -q -c \
  "select tests.create_user('demo_nia','15550000008','Nia','Newcomer');" >/dev/null

echo "▶ 3/7 Building the app (first build takes a few minutes)"
( cd ios && xcodegen generate >/dev/null && xcodebuild -project Connectcha.xcodeproj -scheme Connectcha \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$ROOT/.derived" build 2>&1 | xcbeautify --quiet )

echo "▶ 4/7 Preparing two simulators"
A=$(./scripts/ensure-sim.sh "Connectcha A" "iPhone 17 Pro" "$RUNTIME")
B=$(./scripts/ensure-sim.sh "Connectcha B" "iPhone 17" "$RUNTIME")
for udid in "$A" "$B"; do
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP"
  xcrun simctl privacy "$udid" grant contacts "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl privacy "$udid" grant photos "$BUNDLE_ID" >/dev/null 2>&1 || true
  # Sample photos and videos in the camera roll for creating posts and stories.
  xcrun simctl addmedia "$udid" supabase/seed/media/photos/p0{1,5,9}.jpg supabase/seed/media/videos/v1.mp4 >/dev/null 2>&1 || true
done
open -a Simulator >/dev/null 2>&1 || true

echo "▶ 5/7 Launching: A as Josh, B as Ana"
launch_as "Connectcha A" josh
launch_as "Connectcha B" ana

echo "▶ 6/7 Invite page on http://127.0.0.1:8787"
if ! lsof -i :8787 >/dev/null 2>&1; then
  ( cd web && python3 -m http.server 8787 >/dev/null 2>&1 & echo $! > "$STATE/web.pid" )
fi

echo "▶ 7/7 Push bridge (banners on the simulators)"
if [[ -f "$STATE/bridge.pid" ]] && kill -0 "$(cat "$STATE/bridge.pid")" 2>/dev/null; then
  :
else
  ( ./scripts/push-bridge.sh >"$STATE/bridge.log" 2>&1 & echo $! > "$STATE/bridge.pid" )
fi

cat <<EOF

Ready. Both simulators ask once for notification permission: tap Allow.
  A = Josh (+1 555 000 0001)   B = Ana (+1 555 000 0004)   code for everyone: 123456
  Switch a person:  scripts/demo.sh as B ben      Stop:  scripts/demo.sh stop
  Studio: http://127.0.0.1:54323   Invite page: http://127.0.0.1:8787
Follow DEMO.md for the scripted walkthrough.
EOF
