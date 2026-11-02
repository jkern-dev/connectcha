#!/usr/bin/env bash
# Uploads the demo photos, videos and thumbnails to the local private bucket so
# the seeded media rows (supabase/seed/10_demo.sql) have real bytes behind them.
# Object keys look like media/<user>/demo-<name>.<ext>; <name> maps to a file in
# supabase/seed/media.
set -euo pipefail
cd "$(dirname "$0")/.."

DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
eval "$(supabase status -o env 2>/dev/null | grep -E '^(API_URL|SERVICE_ROLE_KEY)=')"
MEDIA_DIR="supabase/seed/media"

file_for() {
  # $1 = object key. Prints the local file path, or nothing if unknown.
  local key="$1" name base
  name="${key##*/demo-}"
  base="${name%%.*}"
  case "$base" in
    a[0-9]*)        echo "$MEDIA_DIR/avatars/${base}.jpg" ;;
    v[0-9]*_thumb)  echo "$MEDIA_DIR/videos/${base}.jpg" ;;
    v[0-9]*)        echo "$MEDIA_DIR/videos/${base}.mp4" ;;
    p[0-9]*)        echo "$MEDIA_DIR/photos/${base}.jpg" ;;
    s-mom)          echo "$MEDIA_DIR/photos/p19.jpg" ;;
    s-mom_thumb)    echo "$MEDIA_DIR/photos/p19_thumb.jpg" ;;
    s-ana)          echo "$MEDIA_DIR/videos/v3.mp4" ;;
    s-ana_thumb)    echo "$MEDIA_DIR/videos/v3_thumb.jpg" ;;
    s-priya)        echo "$MEDIA_DIR/photos/p14.jpg" ;;
    s-priya_thumb)  echo "$MEDIA_DIR/photos/p14_thumb.jpg" ;;
    s-josh)         echo "$MEDIA_DIR/photos/p11.jpg" ;;
    s-josh_thumb)   echo "$MEDIA_DIR/photos/p11_thumb.jpg" ;;
    s-josh-old)     echo "$MEDIA_DIR/photos/p09.jpg" ;;
    s-josh-old_thumb) echo "$MEDIA_DIR/photos/p09_thumb.jpg" ;;
    *)              echo "" ;;
  esac
}

upload() {
  local key="$1" file="$2" ctype
  case "$file" in *.mp4) ctype="video/mp4" ;; *) ctype="image/jpeg" ;; esac
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_URL/storage/v1/object/media/$key" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H "apikey: $SERVICE_ROLE_KEY" \
    -H "Content-Type: $ctype" -H "x-upsert: true" --data-binary @"$file")
  if [[ "$code" != "200" ]]; then
    echo "upload failed ($code): $key" >&2
    return 1
  fi
}

count=0
while IFS='|' read -r object_key thumb_key; do
  for key in "$object_key" "$thumb_key"; do
    [[ -z "$key" ]] && continue
    file=$(file_for "$key")
    if [[ -z "$file" || ! -f "$file" ]]; then
      echo "no local file for $key" >&2
      continue
    fi
    upload "$key" "$file"
    count=$((count + 1))
  done
done < <(psql "$DB_URL" -At -c "select object_key, coalesce(thumb_key, '') from public.media where object_key like '%/demo-%' order by object_key")

# Byte counts for the seeded rows, so the API reports real sizes.
psql "$DB_URL" -q -c "update public.media set bytes = 250000 where object_key like '%/demo-%' and bytes = 0" >/dev/null
echo "uploaded $count demo objects"
