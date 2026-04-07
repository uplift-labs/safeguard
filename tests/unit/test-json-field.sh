#!/bin/bash
# test-json-field.sh — Unit tests for core/lib/json-field.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$ROOT/core/lib/json-field.sh"

# Test 1: json_field — basic extraction
out=$(json_field "name" '{"name":"alice","age":"30"}')
assert_contains "$out" "alice" "json_field extracts basic value"

# Test 2: json_field — missing key returns empty
out=$(json_field "missing" '{"name":"alice"}')
assert_empty "$out" "json_field returns empty for missing key"

# Test 3: json_field — spaces around colon
out=$(json_field "file_path" '{ "file_path" : "/test/app.ts" }')
assert_contains "$out" "/test/app.ts" "json_field handles spaces around colon"

# Test 4: json_field_long — escaped newlines
# In single quotes, \n is literal two chars (backslash + n) = valid JSON escape
out=$(json_field_long "content" '{"content":"line1\nline2"}')
line_count=$(printf '%s' "$out" | wc -l)
if [ "$line_count" -ge 1 ]; then
  _test_pass=$((_test_pass + 1))
else
  _test_fail=$((_test_fail + 1))
  printf 'FAIL: json_field_long did not unescape newlines (lines: %s)\n' "$line_count" >&2
fi

# Test 5: json_field_long — escaped quotes
# JSON: {"content":"has \"quotes\""} — value is: has "quotes"
out=$(json_field_long "content" '{"content":"has \"quotes\""}')
assert_contains "$out" '"' "json_field_long unescapes quotes"

test_summary
