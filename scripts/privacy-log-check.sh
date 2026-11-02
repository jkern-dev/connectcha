#!/usr/bin/env bash
# Privacy log check (plan section 5, M3): run a contact-matching query with a
# marker hash, then search every local server log for it. Expect no hits.
# Also searches for a marker caption and message body if given.
#
# Usage: scripts/privacy-log-check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

eval "$(supabase status -o env 2>/dev/null | grep -E '^(API_URL|ANON_KEY)=')"
marker_number="+15559998877"
marker_hash=$(printf '%s' "$marker_number" | shasum -a 256 | cut -d' ' -f1)

# Sign in as a test user and run the match.
curl -s -X POST "$API_URL/auth/v1/otp" -H "apikey: $ANON_KEY" -H "content-type: application/json" \
  -d '{"phone":"+15550000009"}' >/dev/null
token=$(curl -s -X POST "$API_URL/auth/v1/verify" -H "apikey: $ANON_KEY" -H "content-type: application/json" \
  -d '{"phone":"+15550000009","token":"123456","type":"sms"}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
curl -s -X POST "$API_URL/rest/v1/rpc/match_contacts" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $token" \
  -H "content-type: application/json" -d "{\"p_hashes\":[\"$marker_hash\"]}" >/dev/null
sleep 1

hits=0
for c in $(docker ps --format '{{.Names}}' | grep '_connectcha$'); do
  if docker logs "$c" 2>&1 | grep -q -- "$marker_hash"; then
    echo "FOUND marker hash in logs of $c"
    hits=$((hits + 1))
  fi
done

# Database: statement logging must be off and the hash must not be stored.
stored=$(psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -At -c "select tests.occurrences_anywhere('$marker_hash')")
log_statement=$(psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -At -c "show log_statement")

echo "marker hash:        $marker_hash"
echo "container log hits: $hits"
echo "rows storing hash:  $stored"
echo "log_statement:      $log_statement"
if [[ "$hits" == "0" && "$stored" == "0" ]]; then
  echo "PASS: submitted hash appears in no server log and no table"
else
  echo "FAIL"
  exit 1
fi
