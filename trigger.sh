#!/usr/bin/env bash
# Optional local test of the exact same call GitHub Actions makes.
#   TRENDPLUS_CRON_URL="https://.../api/admin/run" TRENDPLUS_AUTH_TOKEN="..." ./trigger.sh
set -uo pipefail

: "${TRENDPLUS_CRON_URL:?set TRENDPLUS_CRON_URL}"
TRENDPLUS_AUTH_TOKEN="${TRENDPLUS_AUTH_TOKEN:-}"
AUTH_HEADER_NAME="${AUTH_HEADER_NAME:-X-Admin-Secret}"
HTTP_METHOD="${HTTP_METHOD:-GET}"

BODY_FILE="$(mktemp)"
ARGS=(--silent --show-error --request "$HTTP_METHOD"
      --connect-timeout 20 --max-time 120 --location --max-redirs 3
      --header 'Accept: application/json'
      --output "$BODY_FILE" --write-out '%{http_code}')
[ -n "$TRENDPLUS_AUTH_TOKEN" ] && ARGS+=(--header "$AUTH_HEADER_NAME: $TRENDPLUS_AUTH_TOKEN")

STATUS="$(curl "${ARGS[@]}" "$TRENDPLUS_CRON_URL")" || { echo "request failed (curl exit $?)"; exit 1; }
echo "HTTP status: $STATUS"
head -c 300 "$BODY_FILE"; echo
