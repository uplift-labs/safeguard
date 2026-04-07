#!/bin/bash
# test-multiplexer.sh — Unit tests for safeguard-run.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"

MUX="$ROOT/core/cmd/safeguard-run.sh"

# Test 1: BLOCK on rm -rf /
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | bash "$MUX" pre-bash 2>/dev/null)
assert_contains "$out" "BLOCK:" "BLOCK on rm -rf /"

# Test 2: ASK on git reset --hard
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}' | bash "$MUX" pre-bash 2>/dev/null)
assert_contains "$out" "ASK:" "ASK on git reset --hard"

# Test 3: Allow on safe command
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' | bash "$MUX" pre-bash 2>/dev/null)
assert_empty "$out" "allow on echo hello"

# Test 4: SAFEGUARD_DISABLED
out=$(SAFEGUARD_DISABLED=1 bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /\"}}' | bash '$MUX' pre-bash 2>/dev/null")
assert_empty "$out" "SAFEGUARD_DISABLED bypasses all"

# Test 5: Per-guard disable
out=$(SAFEGUARD_DISABLE_DAMAGE_CONTROL=1 bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /\"}}' | bash '$MUX' pre-bash 2>/dev/null")
assert_not_contains "$out" "damage-control" "per-guard disable works"

# Test 6: CI skip
out=$(CI=true bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /\"}}' | bash '$MUX' pre-bash 2>/dev/null")
assert_empty "$out" "CI=true bypasses all"

# Test 7: Unknown group
out=$(echo '{}' | bash "$MUX" unknown-group 2>/dev/null)
assert_empty "$out" "unknown group passes through"

# Test 8: BLOCK on .env write
out=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/app/.env"}}' | bash "$MUX" pre-edit 2>/dev/null)
assert_contains "$out" "BLOCK:" "BLOCK on .env write"

# Test 9: Allow on .env.example
out=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/app/.env.example"}}' | bash "$MUX" pre-edit 2>/dev/null)
assert_empty "$out" "allow .env.example"

rm -f /tmp/safeguard-loop-* 2>/dev/null
test_summary
