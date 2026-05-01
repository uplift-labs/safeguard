#!/bin/bash
# test-adapter-codex.sh - Unit tests for Codex adapter hooks.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"

TMPD=$(mktemp -d)
git init "$TMPD" >/dev/null 2>&1
bash "$ROOT/install.sh" --target "$TMPD" --with-codex >/dev/null 2>&1
ADAPTER="$TMPD/.uplift/safeguard/adapter-codex/hooks"

# Test 1: pre-bash BLOCK -> PreToolUse deny
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"mkfs /dev/safeguard-test"}}' \
  | bash "$ADAPTER/pre-bash.sh" 2>/dev/null)
assert_contains "$out" '"permissionDecision":"deny"' "pre-bash BLOCK translates to deny"

# Test 2: pre-bash ASK -> default deny because Codex PreToolUse ask is fail-open today
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}' \
  | bash "$ADAPTER/pre-bash.sh" 2>/dev/null)
assert_contains "$out" '"permissionDecision":"deny"' "pre-bash ASK defaults to deny"
assert_contains "$out" "Requires explicit user approval" "pre-bash ASK explains approval"

# Test 3: pre-bash ASK can be downgraded to warning by environment
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}' \
  | SAFEGUARD_CODEX_ASK_MODE=warn bash "$ADAPTER/pre-bash.sh" 2>/dev/null)
assert_contains "$out" '"systemMessage"' "pre-bash ASK warn mode emits systemMessage"
assert_not_contains "$out" '"permissionDecision"' "pre-bash ASK warn mode does not deny"

# Test 4: pre-bash allow -> empty output
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' \
  | bash "$ADAPTER/pre-bash.sh" 2>/dev/null)
assert_empty "$out" "pre-bash allow produces empty output"

# Test 5: apply_patch to .env -> deny
payload='{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: .env\n+SECRET=1\n*** End Patch\n"}}'
out=$(printf '%s' "$payload" | bash "$ADAPTER/pre-apply-patch.sh" 2>/dev/null)
assert_contains "$out" '"permissionDecision":"deny"' "apply_patch sensitive file denies"
assert_contains "$out" "sensitive-file" "apply_patch sensitive file uses sensitive guard"

# Test 6: apply_patch with suppression pattern -> deny
payload='{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: src/main.rs\n@@\n+let value = thing.unwrap();\n*** End Patch\n"}}'
out=$(printf '%s' "$payload" | bash "$ADAPTER/pre-apply-patch.sh" 2>/dev/null)
assert_contains "$out" '"permissionDecision":"deny"' "apply_patch suppression denies"
assert_contains "$out" "error-suppression" "apply_patch suppression uses scanner"

# Test 7: safe apply_patch -> empty output
payload='{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: src/main.rs\n@@\n+let value = thing?;\n*** End Patch\n"}}'
out=$(printf '%s' "$payload" | bash "$ADAPTER/pre-apply-patch.sh" 2>/dev/null)
assert_empty "$out" "safe apply_patch produces empty output"

# Test 8: permission request BLOCK -> deny request
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"mkfs /dev/safeguard-test","description":"needs approval"}}' \
  | bash "$ADAPTER/permission-request.sh" 2>/dev/null)
assert_contains "$out" '"hookEventName":"PermissionRequest"' "permission request emits PermissionRequest"
assert_contains "$out" '"behavior":"deny"' "permission request BLOCK denies"

# Test 9: permission request ASK -> no decision, normal Codex approval flow continues
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD","description":"needs approval"}}' \
  | bash "$ADAPTER/permission-request.sh" 2>/dev/null)
assert_empty "$out" "permission request ASK leaves normal approval prompt"

# Test 10: post-bash -> silent below threshold, counter file created
rm -f /tmp/safeguard-loop-* 2>/dev/null
out=$(echo '{"session_id":"test-codex-post","tool_name":"Bash","tool_input":{"command":"echo hello"}}' \
  | bash "$ADAPTER/post-bash.sh" 2>/dev/null)
assert_empty "$out" "post-bash below threshold produces no stdout"
counter_exists=false
for f in /tmp/safeguard-loop-test-codex-post-*; do
  [ -f "$f" ] && counter_exists=true && break
done
if [ "$counter_exists" = true ]; then
  _test_pass=$((_test_pass + 1))
else
  _test_fail=$((_test_fail + 1))
  printf 'FAIL: post-bash did not create loop counter file\n' >&2
fi

rm -f /tmp/safeguard-loop-* 2>/dev/null
rm -rf "$TMPD"

test_summary
