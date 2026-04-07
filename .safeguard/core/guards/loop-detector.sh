#!/bin/bash
# loop-detector.sh — Safeguard Guard
# Blocks repeated identical commands (25+ = loop).
# Input: JSON on stdin. Output: BLOCK:<reason> | empty (allow).

INPUT=$(cat)
. "$(dirname "$0")/../lib/json-field.sh"

CMD=$(json_field "command" "$INPUT")
[ -z "$CMD" ] && exit 0

SESSION_ID=$(json_field "session_id" "$INPUT")
[ -z "$SESSION_ID" ] && SESSION_ID="default"

# Normalize command to reduce false positives
NORM_CMD=$(printf '%s' "$CMD" | sed \
  -e 's/[[:space:]]\+/ /g' \
  -e 's|/tmp/[^ ]*|/tmp/...|g' \
  -e 's/[0-9a-f]\{7,\}/.../g' \
)

# Extract base command + subcommand for identity
BASE_CMD=$(printf '%s' "$NORM_CMD" | awk '{
  cmd = $1
  if (cmd == "git" || cmd == "npm" || cmd == "npx" || cmd == "docker" || cmd == "cargo" || cmd == "kubectl")
    print cmd " " $2
  else
    print cmd
}')

# Hash base command + full normalized command + CWD
CWD=$(json_field "cwd" "$INPUT")
[ -z "$CWD" ] && CWD="$(pwd)"
CMD_HASH=$(printf '%s|%s|%s' "$BASE_CMD" "$NORM_CMD" "$CWD" | cksum | cut -d' ' -f1)
COUNTER_FILE="/tmp/safeguard-loop-${SESSION_ID}-${CMD_HASH}"

# Time decay — reset counter if last hit was 10+ minutes ago
if [ -f "$COUNTER_FILE" ]; then
  LAST_MOD=$(stat -c %Y "$COUNTER_FILE" 2>/dev/null || stat -f %m "$COUNTER_FILE" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  if [ $((NOW - LAST_MOD)) -ge 600 ]; then
    COUNT=1
  else
    COUNT=$(($(cat "$COUNTER_FILE") + 1))
  fi
else
  COUNT=1
fi
printf '%s' "$COUNT" > "$COUNTER_FILE"

# Thresholds — override via SAFEGUARD_LOOP_THRESHOLD for testing
if [ -n "${SAFEGUARD_LOOP_THRESHOLD:-}" ]; then
  THRESHOLD="$SAFEGUARD_LOOP_THRESHOLD"
else
  case "$BASE_CMD" in
    git\ *) THRESHOLD=30 ;;
    *)       THRESHOLD=25 ;;
  esac
fi

if [ "$COUNT" -ge "$THRESHOLD" ]; then
  rm -f "$COUNTER_FILE"
  printf 'BLOCK:[safeguard:loop-detector] Same command run %s+ times. Stop and ask the user for guidance.' "$COUNT"
  exit 0
fi

exit 0
