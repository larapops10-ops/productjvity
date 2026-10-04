#!/bin/sh
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

printf '%s\n' 'Paste your Gemini API key and press Return. It will stay hidden.'
stty -echo
read GEMINI_KEY
stty echo
printf '\n'

if [ -z "$GEMINI_KEY" ]; then
  printf '%s\n' 'No key was entered; nothing was saved.' >&2
  exit 1
fi

umask 077
{
  printf '%s\n' 'AI_REVIEW_ENABLED=true'
  printf '%s\n' 'AI_REVIEW_PROVIDER=gemini'
  printf '%s\n' 'AI_REVIEW_MODEL=gemini-3.1-flash-lite'
  printf 'GEMINI_API_KEY=%s\n' "$GEMINI_KEY"
} > "$ENV_FILE"

printf '%s\n' 'Gemini settings saved locally. They are excluded from Git.'
