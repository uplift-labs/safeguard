#!/bin/bash
# permission-request.sh - Codex PermissionRequest adapter for Safeguard.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
. "$ROOT/core/lib/json-field.sh"
. "$HOOK_DIR/lib-codex.sh"

INPUT=$(cat)
TOOL=$(json_field "tool_name" "$INPUT")

case "$TOOL" in
  Bash)
    RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/safeguard-run.sh" pre-bash 2>/dev/null) || true
    sg_emit_permission_result "$RESULT" || true
    ;;
esac

exit 0
