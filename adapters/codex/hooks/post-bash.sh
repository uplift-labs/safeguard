#!/bin/bash
# post-bash.sh - Codex PostToolUse Bash adapter for Safeguard.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
. "$HOOK_DIR/lib-codex.sh"

INPUT=$(cat)
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/safeguard-run.sh" post-bash 2>/dev/null) || true

sg_emit_posttooluse_result "$RESULT" || true
exit 0
