#!/bin/bash
# error-suppression-scanner.sh — Safeguard Guard
# Blocks edits that introduce error suppression patterns.
# Input: JSON on stdin. Output: BLOCK:<reason> | empty (allow).

INPUT=$(cat)
. "$(dirname "$0")/../lib/json-field.sh"

FILE=$(json_field "file_path" "$INPUT")
[ -z "$FILE" ] && exit 0

# Skip non-code files
case "$FILE" in
  *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.lock|*.svg|*.png|*.jpg|*.dat) exit 0 ;;
esac

# Extract content to scan: new_string (Edit) or content (Write)
TOOL=$(json_field "tool_name" "$INPUT")
case "$TOOL" in
  Edit)  CONTENT=$(json_field_long "new_string" "$INPUT") ;;
  Write) CONTENT=$(json_field_long "content" "$INPUT") ;;
  *)     exit 0 ;;
esac
[ -z "$CONTENT" ] && exit 0

# Cross-language error suppression patterns (POSIX classes only)
_S='[[:space:]]*'
_W='[[:alnum:]_]*'
PATTERNS="catch${_S}\(${_S}${_W}${_S}\)${_S}\{${_S}\}|except:${_S}pass|except[[:space:]]+[[:alnum:]_]+.*:${_S}pass|\.unwrap\(\)|#\[allow\(unused|dead_code\)\]|// eslint-disable|# type: ignore|catch${_S}\{${_S}\}|on${_S}${_W}${_S}catch${_S}\(${_S}${_W}${_S}\)${_S}\{${_S}\}|rescue${_S}=>?${_S}nil"

HITS=$(printf '%s\n' "$CONTENT" | grep -nE "$PATTERNS" 2>/dev/null || true)

# Multi-line patterns: except/catch block followed by pass/empty on next line
MULTI=$(printf '%s\n' "$CONTENT" | awk '
  /except[[:space:]]*:/ || /except[[:space:]]+[[:alnum:]_]+.*:/ || /catch[[:space:]]*\(/ {
    prev = NR; prev_line = $0; next
  }
  prev && NR == prev + 1 {
    if (/^[[:space:]]*(pass|\.\.\.)[[:space:]]*$/ || /^[[:space:]]*\}[[:space:]]*$/) {
      print prev ":" prev_line " -> " NR ":" $0
    }
    prev = 0
  }
' 2>/dev/null || true)

if [ -n "$MULTI" ]; then
  HITS=$(printf '%s\n%s' "$HITS" "$MULTI" | sed '/^$/d')
fi

# Filter out intentional suppression (comment on preceding line)
if [ -n "$HITS" ]; then
  FILTERED=""
  while IFS= read -r hit; do
    LINE_NUM=$(printf '%s' "$hit" | cut -d: -f1)
    [ -z "$LINE_NUM" ] && continue
    PREV=$((LINE_NUM - 1))
    [ "$PREV" -lt 1 ] && { FILTERED=$(printf '%s\n%s' "$FILTERED" "$hit"); continue; }
    PREV_LINE=$(printf '%s\n' "$CONTENT" | sed -n "${PREV}p")
    case "$PREV_LINE" in
      *intentional*|*Intentional*|*INTENTIONAL*|*safe\ here*|*Safe\ here*|*allow*suppression*|*TODO*|*SAFETY*) ;;
      *) FILTERED=$(printf '%s\n%s' "$FILTERED" "$hit") ;;
    esac
  done <<HITS_EOF
$HITS
HITS_EOF
  HITS=$(printf '%s' "$FILTERED" | sed '/^$/d')
fi

if [ -n "$HITS" ]; then
  COUNT=$(printf '%s\n' "$HITS" | wc -l | tr -d ' ')
  printf 'BLOCK:[safeguard:error-suppression] %s suppression pattern(s) in new code for %s. Add error handling or a comment explaining why suppression is intentional.' "$COUNT" "$FILE"
  exit 0
fi

exit 0
