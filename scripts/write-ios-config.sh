#!/usr/bin/env bash
# Writes ios/Config/Local.xcconfig from the running local Supabase stack.
set -euo pipefail
cd "$(dirname "$0")/.."
eval "$(supabase status -o env 2>/dev/null | grep -E '^(API_URL|ANON_KEY)=')"
url="${API_URL/\/\//\/\$()\/}"
cat > ios/Config/Local.xcconfig <<EOF
// Build-time configuration for the local stack. Regenerate with \`make ios-config\`
// after \`supabase start\` if your local keys differ. \`\$()\` splits the \`//\` so
// xcconfig doesn't treat the URL as a comment.
SUPABASE_URL = ${url}
SUPABASE_ANON_KEY = ${ANON_KEY}
INVITE_URL = http:/\$()/127.0.0.1:8787/
SUPPORT_EMAIL = ask.connectcha@gmail.com
EOF
echo "wrote ios/Config/Local.xcconfig for ${API_URL}"
