#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE="$PROJECT_ROOT/.env"

printf 'ZeptoMail sender email: '
read ZEPTO_FROM_ADDRESS
printf 'ZeptoMail sender name (Productjvity is fine): '
read ZEPTO_FROM_NAME
printf 'ZeptoMail Send Mail token (hidden): '
stty -echo
read ZEPTO_API_KEY
stty echo
printf '\n'

[ -n "$ZEPTO_FROM_ADDRESS" ] && [ -n "$ZEPTO_API_KEY" ] || { echo "Nothing was saved: an email and token are required."; exit 1; }
touch "$ENV_FILE"
TMP_FILE="$ENV_FILE.zeptomail.tmp"
grep -v '^ZEPTO_API_KEY=' "$ENV_FILE" | grep -v '^ZEPTO_FROM=' > "$TMP_FILE" || true
printf 'ZEPTO_API_KEY=%s\nZEPTO_FROM="%s <%s>"\n' "$ZEPTO_API_KEY" "${ZEPTO_FROM_NAME:-Productjvity}" "$ZEPTO_FROM_ADDRESS" >> "$TMP_FILE"
mv "$TMP_FILE" "$ENV_FILE"
echo "ZeptoMail is ready. Restart Productjvity before sending a test invitation."
