#!/bin/bash
# pre-read.sh — Claude Code PreToolUse Read adapter for Safeguard.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

INPUT=$(cat)
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/safeguard-run.sh" pre-read 2>/dev/null) || true

_sg_escape() {
  local s="$1"
  s=${s//\/\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/ }
  printf '%s' "$s"
}

case "$RESULT" in
  WARN:*)
    ctx=$(_sg_escape "${RESULT#WARN:}")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}' "$ctx"
    ;;
  BLOCK:*)
    reason=$(_sg_escape "${RESULT#BLOCK:}")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$reason"
    ;;
esac
exit 0
