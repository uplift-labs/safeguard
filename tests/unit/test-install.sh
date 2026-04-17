#!/bin/bash
# test-install.sh — Unit tests for install.sh
# All tests use temporary directories; nothing touches the real filesystem.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"

INSTALLER="$ROOT/install.sh"

# Test 1: --target installs core guards, cmd, lib
tmpd=$(mktemp -d)
git init "$tmpd" >/dev/null 2>&1
bash "$INSTALLER" --target "$tmpd" >/dev/null 2>&1
guard_count=$(ls "$tmpd/.uplift/safeguard/core/guards/"*.sh 2>/dev/null | wc -l)
if [ "$guard_count" -ge 6 ]; then
  _test_pass=$((_test_pass + 1))
else
  _test_fail=$((_test_fail + 1))
  printf 'FAIL: --target core install — expected >=6 guards, got %s\n' "$guard_count" >&2
fi
rm -rf "$tmpd"

# Test 2: --with-claude-code installs adapter hooks and settings
tmpd=$(mktemp -d)
git init "$tmpd" >/dev/null 2>&1
bash "$INSTALLER" --target "$tmpd" --with-claude-code >/dev/null 2>&1
hook_count=$(ls "$tmpd/.uplift/safeguard/adapter/hooks/"*.sh 2>/dev/null | wc -l)
if [ "$hook_count" -ge 4 ] && [ -f "$tmpd/.claude/settings.json" ]; then
  _test_pass=$((_test_pass + 1))
else
  _test_fail=$((_test_fail + 1))
  printf 'FAIL: --with-claude-code — hooks: %s, settings.json exists: %s\n' \
    "$hook_count" "$([ -f "$tmpd/.claude/settings.json" ] && echo yes || echo no)" >&2
fi
rm -rf "$tmpd"

# Test 3: non-git directory → exit 1
tmpd=$(mktemp -d)
out=$(bash "$INSTALLER" --target "$tmpd" 2>&1)
ec=$?
assert_exit "1" "$ec" "non-git repo exits 1"
rm -rf "$tmpd"

# Test 4: --help shows usage text
out=$(bash "$INSTALLER" --help 2>&1)
assert_contains "$out" "install" "--help shows usage"

# Test 5: unknown argument → exit 2
out=$(bash "$INSTALLER" --badarg 2>&1)
ec=$?
assert_exit "2" "$ec" "unknown arg exits 2"

# Test 6: install does not modify .gitignore (safeguard should be committed)
tmpd=$(mktemp -d)
git init "$tmpd" >/dev/null 2>&1
bash "$INSTALLER" --target "$tmpd" >/dev/null 2>&1
if [ ! -f "$tmpd/.gitignore" ]; then
  _test_pass=$((_test_pass + 1))
else
  _test_fail=$((_test_fail + 1))
  printf 'FAIL: install.sh should not create .gitignore\n' >&2
fi
rm -rf "$tmpd"

test_summary
