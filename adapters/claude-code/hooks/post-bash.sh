#!/bin/bash
# post-bash.sh — Claude Code PostToolUse Bash adapter for Safeguard.
# Feeds loop-detector counter tracking (no blocking on PostToolUse).
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

INPUT=$(cat)
# Run but discard output — PostToolUse only tracks counters
printf '%s' "$INPUT" | bash "$ROOT/core/cmd/safeguard-run.sh" post-bash >/dev/null 2>&1 || true
exit 0
