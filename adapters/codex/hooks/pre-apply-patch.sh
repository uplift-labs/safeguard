#!/bin/bash
# pre-apply-patch.sh - Codex PreToolUse apply_patch adapter for Safeguard.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
. "$ROOT/core/lib/json-field.sh"
. "$HOOK_DIR/lib-codex.sh"

INPUT=$(cat)
PATCH=$(json_field_long "command" "$INPUT")
[ -z "$PATCH" ] && PATCH=$(json_field_long "patch" "$INPUT")
[ -z "$PATCH" ] && exit 0

CURRENT_PATH=""
ADDED_CONTENT=""

flush_patch_file() {
  [ -n "$CURRENT_PATH" ] || return 0

  local path_json content_json synthetic result
  path_json=$(_sg_json_escape_string "$CURRENT_PATH")
  content_json=$(_sg_json_escape_string "$ADDED_CONTENT")
  synthetic=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"}}' "$path_json" "$content_json")
  result=$(printf '%s' "$synthetic" | bash "$ROOT/core/cmd/safeguard-run.sh" pre-edit 2>/dev/null) || true

  if sg_emit_pretooluse_result "$result"; then
    exit 0
  fi

  CURRENT_PATH=""
  ADDED_CONTENT=""
}

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    "*** Add File: "*)
      flush_patch_file
      CURRENT_PATH="${line#"*** Add File: "}"
      ADDED_CONTENT=""
      ;;
    "*** Update File: "*)
      flush_patch_file
      CURRENT_PATH="${line#"*** Update File: "}"
      ADDED_CONTENT=""
      ;;
    "*** Delete File: "*)
      flush_patch_file
      CURRENT_PATH="${line#"*** Delete File: "}"
      ADDED_CONTENT=""
      ;;
    "*** Move to: "*)
      CURRENT_PATH="${line#"*** Move to: "}"
      ;;
    "*** End Patch")
      flush_patch_file
      ;;
    +*)
      if [ -n "$CURRENT_PATH" ]; then
        if [ -n "$ADDED_CONTENT" ]; then
          ADDED_CONTENT="${ADDED_CONTENT}
${line#+}"
        else
          ADDED_CONTENT="${line#+}"
        fi
      fi
      ;;
  esac
done <<PATCH_EOF
$PATCH
PATCH_EOF

flush_patch_file
exit 0
