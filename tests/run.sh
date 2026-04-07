#!/bin/bash
# run.sh — Safeguard test runner.
# Usage:
#   bash tests/run.sh              # all tests
#   bash tests/run.sh fixtures     # fixture tests only
#   bash tests/run.sh unit         # unit tests only
#   bash tests/run.sh <guard>      # single guard fixtures

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MUX="$ROOT/core/cmd/safeguard-run.sh"

PASS=0
FAIL=0
SKIP=0

pass() { PASS=$((PASS + 1)); printf '  ok  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s -- %s\n' "$1" "$2" >&2; }
skip() { SKIP=$((SKIP + 1)); printf '  skip %s\n' "$1"; }

guard_group() {
  case "$1" in
    damage-control|no-push-to-main|loop-detector) echo "pre-bash" ;;
    sensitive-file-guard|error-suppression-scanner) echo "pre-edit" ;;
    input-sanitizer) echo "pre-read" ;;
    *) echo "" ;;
  esac
}

check_triggered() {
  case "$1" in
    BLOCK:*|ASK:*|WARN:*) return 0 ;;
    *) return 1 ;;
  esac
}

run_fixture_tests() {
  local filter="${1:-}"
  for guard_dir in "$SCRIPT_DIR/fixtures"/*/; do
    guard=$(basename "$guard_dir")
    [ -n "$filter" ] && [ "$filter" != "$guard" ] && continue
    group=$(guard_group "$guard")
    [ -z "$group" ] && { skip "$guard (unknown group)"; continue; }
    printf '\n%s:\n' "$guard"
    for fixture in "$guard_dir"/*.json; do
      [ -f "$fixture" ] || continue
      fname=$(basename "$fixture" .json)
      tmpdir=$(mktemp -d)
      fixture_content=$(sed "s|{{TMPDIR}}|$tmpdir|g" "$fixture")
      for companion in "$guard_dir"/*.md "$guard_dir"/*.txt "$guard_dir"/.*.rs; do
        [ -f "$companion" ] && cp "$companion" "$tmpdir/"
      done
      if [ "$guard" = "loop-detector" ]; then
        case "$fname" in
          tp-*)
            export SAFEGUARD_LOOP_THRESHOLD=5
            for _i in 1 2 3 4; do
              printf '%s' "$fixture_content" | bash "$MUX" "$group" >/dev/null 2>&1 || true
            done
            output=$(printf '%s' "$fixture_content" | bash "$MUX" "$group" 2>/dev/null) || true
            unset SAFEGUARD_LOOP_THRESHOLD
            ;;
          *)
            output=$(printf '%s' "$fixture_content" | bash "$MUX" "$group" 2>/dev/null) || true
            ;;
        esac
      else
        output=$(printf '%s' "$fixture_content" | bash "$MUX" "$group" 2>/dev/null) || true
      fi
      rm -f /tmp/safeguard-loop-* 2>/dev/null
      rm -rf "$tmpdir"
      case "$fname" in
        tp-*)
          if check_triggered "$output"; then pass "$fname (TP)"
          else fail "$fname" "expected trigger, got: '$output'"; fi ;;
        tn-*)
          if ! check_triggered "$output"; then pass "$fname (TN)"
          else fail "$fname" "unexpected trigger: '$output'"; fi ;;
      esac
    done
  done
}

run_unit_tests() {
  printf '\nunit tests:\n'
  for test_file in "$SCRIPT_DIR/unit"/*.sh; do
    [ -f "$test_file" ] || { printf '  (no unit tests found)\n'; return; }
    tname=$(basename "$test_file" .sh)
    if uout=$(bash "$test_file" 2>&1); then pass "$tname"
    else fail "$tname" "$(printf '%s' "$uout" | grep FAIL | head -3)"; fi
  done
}

MODE="${1:-all}"
case "$MODE" in
  fixtures) run_fixture_tests ;;
  unit)     run_unit_tests ;;
  all)      run_fixture_tests; run_unit_tests ;;
  *)        run_fixture_tests "$MODE" ;;
esac

printf '\n=============================\n'
printf 'Results: %s passed, %s failed, %s skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
