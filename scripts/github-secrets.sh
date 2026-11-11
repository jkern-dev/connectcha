#!/usr/bin/env bash
# Sets the repository secrets and variable that turn on the keep-alive and
# weekly backup workflows (OPERATIONS.md "Hosted setup" step 7). Reads
# supabase/.hosted.env; generates BACKUP_PASSPHRASE once and stores it there
# (you need it to decrypt a backup). Safe to rerun. Needs `gh auth login`.
set -euo pipefail
cd "$(dirname "$0")/.."

env_file=supabase/.hosted.env
[ -f "$env_file" ] || { echo "Missing $env_file" >&2; exit 1; }
set -a; . "$env_file"; set +a
for v in SUPABASE_PROJECT_REF SUPABASE_DB_PASSWORD; do
  [ -n "${!v:-}" ] || { echo "$env_file: $v is empty" >&2; exit 1; }
done

if [ -z "${SUPABASE_DB_URL:-}" ] && [ -f supabase/.temp/pooler-url ]; then
  pooler="$(cat supabase/.temp/pooler-url)"
  case "$pooler" in
    *"[YOUR-PASSWORD]"*) SUPABASE_DB_URL="${pooler/\[YOUR-PASSWORD\]/${SUPABASE_DB_PASSWORD}}" ;;
    *) SUPABASE_DB_URL="${pooler/@/:${SUPABASE_DB_PASSWORD}@}" ;;
  esac
fi
[ -n "${SUPABASE_DB_URL:-}" ] || { echo "No database URL: run make hosted-setup first or set SUPABASE_DB_URL" >&2; exit 1; }

if [ -z "${BACKUP_PASSPHRASE:-}" ]; then
  BACKUP_PASSPHRASE="$(openssl rand -hex 32)"
  printf '\n# Decrypts the weekly backup artifacts (scripts/github-secrets.sh). Keep a copy outside this Mac.\nBACKUP_PASSPHRASE=%s\n' "$BACKUP_PASSPHRASE" >> "$env_file"
  echo "Generated BACKUP_PASSPHRASE and saved it in $env_file"
fi

anon_key="$(sed -n 's/^SUPABASE_ANON_KEY *= *//p' ios/Config/Hosted.xcconfig)"
[ -n "$anon_key" ] || { echo "SUPABASE_ANON_KEY missing from ios/Config/Hosted.xcconfig" >&2; exit 1; }

gh secret set SUPABASE_URL --body "https://${SUPABASE_PROJECT_REF}.supabase.co"
gh secret set SUPABASE_ANON_KEY --body "$anon_key"
gh secret set SUPABASE_DB_URL --body "$SUPABASE_DB_URL"
gh secret set BACKUP_PASSPHRASE --body "$BACKUP_PASSPHRASE"
gh variable set HOSTED_ENABLED --body true

echo "Running both workflows once now:"
gh workflow run keepalive.yml
gh workflow run backup.yml
echo "Watch them: gh run list --limit 2   (or the repository's Actions tab)"
