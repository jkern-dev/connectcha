#!/usr/bin/env bash
# Configures the hosted Supabase project from supabase/.hosted.env. Every step
# is safe to rerun: migrations are applied once, secrets and settings are
# overwritten, the cron job is replaced. Run `supabase login` once beforehand.
#
# What it does NOT do (dashboard only, see OPERATIONS.md "Hosted setup"):
#   - Auth: Twilio Verify provider, the reviewer test number, rate limits, the
#     before_user_created hook switch. `supabase config push` must never be run:
#     supabase/config.toml holds the local demo numbers with code 123456.
set -euo pipefail
cd "$(dirname "$0")/.."

env_file=supabase/.hosted.env
if [ ! -f "$env_file" ]; then
  echo "Missing $env_file. Copy supabase/.hosted.env.example and fill it in." >&2
  exit 1
fi
set -a; . "$env_file"; set +a

for v in SUPABASE_PROJECT_REF SUPABASE_DB_PASSWORD PUSH_WEBHOOK_SECRET; do
  [ -n "${!v:-}" ] || { echo "$env_file: $v is empty" >&2; exit 1; }
done

step() { printf '\n▶ %s\n' "$*"; }
skipped=()

step "Link the CLI to project $SUPABASE_PROJECT_REF"
supabase link --project-ref "$SUPABASE_PROJECT_REF" --password "$SUPABASE_DB_PASSWORD" >/dev/null

step "Apply migrations (seeds stay local)"
supabase db push --yes --password "$SUPABASE_DB_PASSWORD"

step "Deploy the Edge Functions (verify_jwt per supabase/config.toml)"
supabase functions deploy --use-api

step "Set function secrets (webhook secret, APNs)"
supabase secrets set \
  "PUSH_WEBHOOK_SECRET=${PUSH_WEBHOOK_SECRET}" \
  "APNS_MODE=${APNS_MODE:-stub}" \
  "APNS_KEY_ID=${APNS_KEY_ID:-}" \
  "APNS_TEAM_ID=${APNS_TEAM_ID:-}" \
  "APNS_BUNDLE_ID=${APNS_BUNDLE_ID:-com.connectcha.app}" \
  "APNS_PRIVATE_KEY=${APNS_PRIVATE_KEY:-}" >/dev/null

if [ -n "${R2_ACCOUNT_ID:-}" ] && [ -n "${R2_ACCESS_KEY_ID:-}" ] && [ -n "${R2_SECRET_ACCESS_KEY:-}" ]; then
  step "Set the media bucket secrets (Cloudflare R2)"
  supabase secrets set \
    "S3_ENDPOINT=https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" \
    "S3_BUCKET=${R2_BUCKET:-connectcha-media}" \
    "S3_REGION=auto" \
    "S3_ACCESS_KEY_ID=${R2_ACCESS_KEY_ID}" \
    "S3_SECRET_ACCESS_KEY=${R2_SECRET_ACCESS_KEY}" >/dev/null
else
  skipped+=("media bucket secrets: fill the R2_* values in $env_file and rerun")
fi

functions_url="https://${SUPABASE_PROJECT_REF}.supabase.co/functions/v1"

# The session-pooler URL the CLI recorded at link time, with the password filled in,
# unless SUPABASE_DB_URL is set explicitly.
if [ -z "${SUPABASE_DB_URL:-}" ] && [ -f supabase/.temp/pooler-url ]; then
  pooler="$(cat supabase/.temp/pooler-url)"
  case "$pooler" in
    *"[YOUR-PASSWORD]"*) SUPABASE_DB_URL="${pooler/\[YOUR-PASSWORD\]/${SUPABASE_DB_PASSWORD}}" ;;
    *) SUPABASE_DB_URL="${pooler/@/:${SUPABASE_DB_PASSWORD}@}" ;;
  esac
fi
[ -n "${SUPABASE_DB_URL:-}" ] || { echo "No database URL: set SUPABASE_DB_URL in $env_file" >&2; exit 1; }

step "Point the push webhook at send-push and schedule cleanup-orphans daily"
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -q \
  -v url="${functions_url}/send-push" -v secret="$PUSH_WEBHOOK_SECRET" -v cleanup="${functions_url}/cleanup-orphans" <<'SQL'
insert into private.settings (key, value) values
  ('push_webhook_url', :'url'),
  ('push_webhook_secret', :'secret')
on conflict (key) do update set value = excluded.value;

create extension if not exists pg_cron with schema pg_catalog;
select cron.unschedule(jobid) from cron.job where jobname = 'cleanup-orphans';
select cron.schedule(
  'cleanup-orphans',
  '0 9 * * *',
  format(
    $job$ select net.http_post(url := %L, headers := jsonb_build_object('x-webhook-secret', %L), body := '{}'::jsonb, timeout_milliseconds := 30000) $job$,
    :'cleanup', :'secret'));
SQL

step "Done"
for s in "${skipped[@]:-}"; do [ -n "$s" ] && echo "Skipped: $s"; done
cat <<EOF
Still to do in the Supabase dashboard (Authentication):
  1. Providers → Phone: enable, provider Twilio Verify, Account SID, Auth Token, Verify Service SID.
  2. Providers → Phone → Test phone numbers: the reviewer number and code only (OPEN_QUESTIONS Q8).
  3. Hooks: enable "Before User Created" → Postgres function public.before_user_created_hook.
Then fill ios/Config/Hosted.xcconfig (URL https://${SUPABASE_PROJECT_REF}.supabase.co and the anon key).
EOF
