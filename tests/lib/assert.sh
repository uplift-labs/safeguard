#!/bin/bash
# assert.sh — Minimal test assertion library for Safeguard.

_test_pass=0
_test_fail=0

assert_exit() {
  local expected="$1" actual="$2" label="${3:-}"
  if [ "$expected" = "$actual" ]; then
    _test_pass=$((_test_pass + 1))
  else
    _test_fail=$((_test_fail + 1))
    printf 'FAIL: %s — expected exit %s, got %s
' "$label" "$expected" "$actual" >&2
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    _test_pass=$((_test_pass + 1))
  else
    _test_fail=$((_test_fail + 1))
    printf 'FAIL: %s — output does not contain "%s"
' "$label" "$needle" >&2
    printf '  got: %s
' "$haystack" >&2
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  if ! printf '%s' "$haystack" | grep -qF "$needle"; then
    _test_pass=$((_test_pass + 1))
  else
    _test_fail=$((_test_fail + 1))
    printf 'FAIL: %s — output should not contain "%s"
' "$label" "$needle" >&2
  fi
}

assert_empty() {
  local value="$1" label="${2:-}"
  if [ -z "$value" ]; then
    _test_pass=$((_test_pass + 1))
  else
    _test_fail=$((_test_fail + 1))
    printf 'FAIL: %s — expected empty, got "%s"
' "$label" "$value" >&2
  fi
}

test_summary() {
  printf '
  %s passed, %s failed
' "$_test_pass" "$_test_fail"
  [ "$_test_fail" -eq 0 ]
}
