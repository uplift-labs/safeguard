#!/bin/bash
# install.sh — install safeguard into a target git repo.
#
# Usage:
#   bash install.sh [--target <repo-dir>] [--with-claude-code]
#
# By default installs only the core guards. With --with-claude-code,
# also installs the Claude Code adapter hooks and merges hook config
# into .claude/settings.json.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET=""
WITH_CC=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target)           TARGET="$2"; shift 2 ;;
    --with-claude-code) WITH_CC=1; shift ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -z "$TARGET" ] && TARGET="$(pwd)"
[ -d "$TARGET/.git" ] || { printf 'not a git repo: %s\n' "$TARGET" >&2; exit 1; }

INSTALL_ROOT="$TARGET/.safeguard"
mkdir -p "$INSTALL_ROOT/core/lib" "$INSTALL_ROOT/core/cmd" "$INSTALL_ROOT/core/guards"

# sync_sh_dir <src_dir> <dest_dir> — mirror *.sh from src into dest.
sync_sh_dir() {
  local src="$1" dest="$2"
  # shellcheck disable=SC2206
  local files=( "$src"/*.sh )
  if [ ! -e "${files[0]}" ]; then
    printf 'install: no *.sh files in %s\n' "$src" >&2
    exit 1
  fi
  rm -f "$dest"/*.sh
  cp "${files[@]}" "$dest/" || {
    printf 'install: copy failed %s -> %s\n' "$src" "$dest" >&2
    exit 1
  }
}

printf '[install] copying core to %s\n' "$INSTALL_ROOT/core"
sync_sh_dir "$SCRIPT_DIR/core/lib"    "$INSTALL_ROOT/core/lib"
sync_sh_dir "$SCRIPT_DIR/core/cmd"    "$INSTALL_ROOT/core/cmd"
sync_sh_dir "$SCRIPT_DIR/core/guards" "$INSTALL_ROOT/core/guards"
chmod +x "$INSTALL_ROOT/core/cmd/"*.sh "$INSTALL_ROOT/core/guards/"*.sh

if [ "$WITH_CC" -eq 1 ]; then
  ADAPTER_DIR="$INSTALL_ROOT/adapter"
  mkdir -p "$ADAPTER_DIR/hooks"
  printf '[install] copying Claude Code adapter to %s\n' "$ADAPTER_DIR"
  sync_sh_dir "$SCRIPT_DIR/adapters/claude-code/hooks" "$ADAPTER_DIR/hooks"
  chmod +x "$ADAPTER_DIR/hooks/"*.sh

  SNIPPET="$SCRIPT_DIR/adapters/claude-code/settings-hooks.json"
  SETTINGS="$TARGET/.claude/settings.json"
  mkdir -p "$TARGET/.claude"

  MERGER="$SCRIPT_DIR/core/lib/json-merge.py"
  if ! command -v python3 >/dev/null 2>&1; then
    printf '[install] ERROR: python3 required to merge hooks into settings.json.\n' >&2
    exit 1
  fi
  printf '[install] merging hooks into %s\n' "$SETTINGS"
  python3 "$MERGER" "$SETTINGS" "$SNIPPET"
fi

printf '[install] done.\n'
printf '  core installed at: %s\n' "$INSTALL_ROOT/core"
[ "$WITH_CC" -eq 1 ] && printf '  claude-code adapter: %s\n' "$INSTALL_ROOT/adapter"
printf '\n  Commit .safeguard/ (and .claude/settings.json if using Claude Code)\n'
printf '  so that guards are available in worktrees.\n'
