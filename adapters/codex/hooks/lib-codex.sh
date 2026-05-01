#!/bin/bash
# lib-codex.sh - shared helpers for Codex hook adapters.

_sg_json_escape_flat() {
  local s="${1:-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\r'/ }
  s=${s//$'\n'/ }
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

_sg_json_escape_string() {
  local s="${1:-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\r'/\\r}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

sg_emit_pretooluse_result() {
  local result="${1:-}" reason ctx mode

  case "$result" in
    BLOCK:*)
      reason=$(_sg_json_escape_flat "${result#BLOCK:}")
      printf '{"decision":"block","reason":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$reason" "$reason"
      return 0
      ;;
    ASK:*)
      mode="${SAFEGUARD_CODEX_ASK_MODE:-block}"
      reason="${result#ASK:}"
      case "$mode" in
        warn)
          ctx=$(_sg_json_escape_flat "[safeguard:codex] Approval recommended: $reason")
          printf '{"systemMessage":"%s"}' "$ctx"
          ;;
        *)
          reason=$(_sg_json_escape_flat "Requires explicit user approval: $reason")
          printf '{"decision":"block","reason":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$reason" "$reason"
          ;;
      esac
      return 0
      ;;
    WARN:*)
      ctx=$(_sg_json_escape_flat "${result#WARN:}")
      printf '{"systemMessage":"%s"}' "$ctx"
      return 0
      ;;
  esac

  return 1
}

sg_emit_permission_result() {
  local result="${1:-}" reason

  case "$result" in
    BLOCK:*)
      reason=$(_sg_json_escape_flat "${result#BLOCK:}")
      printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"%s"}}}' "$reason"
      return 0
      ;;
    ASK:*)
      # Let Codex show its normal approval prompt.
      return 1
      ;;
  esac

  return 1
}

sg_emit_posttooluse_result() {
  local result="${1:-}" reason

  case "$result" in
    BLOCK:*)
      reason=$(_sg_json_escape_flat "${result#BLOCK:}")
      printf '{"decision":"block","reason":"%s","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$reason" "$reason"
      return 0
      ;;
  esac

  return 1
}
