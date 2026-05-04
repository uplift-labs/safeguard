#!/bin/bash
# install.sh — install safeguard into a target git repo.
#
# Usage:
#   bash install.sh [--target <repo-dir>] [--prefix <dir>] [--with-claude-code] [--with-codex] [--with-opencode]
#
# By default installs only the core guards. Adapter flags install host-specific
# hooks and merge their config into the host's project settings.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET=""
PREFIX=".uplift"
WITH_CC=0
WITH_CODEX=0
WITH_OPENCODE=0
TMP_FILES=""

cleanup_tmp_files() {
  # shellcheck disable=SC2086
  [ -n "$TMP_FILES" ] && rm -f $TMP_FILES
}
trap cleanup_tmp_files EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --target)           TARGET="$2"; shift 2 ;;
    --prefix)           PREFIX="$2"; shift 2 ;;
    --with-claude-code) WITH_CC=1; shift ;;
    --with-codex)       WITH_CODEX=1; shift ;;
    --with-opencode)    WITH_OPENCODE=1; shift ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -z "$TARGET" ] && TARGET="$(pwd)"
# .git is a directory in normal repos, a file in worktrees
[ -d "$TARGET/.git" ] || [ -f "$TARGET/.git" ] || { printf 'not a git repo: %s\n' "$TARGET" >&2; exit 1; }

# --- Migration from legacy path ---
migrate_old_path() {
  local old="$1" new="$2"
  [ -d "$old" ] || return 0
  [ -d "$new" ] && { printf '[migrate] both %s and %s exist — manual merge needed\n' "$old" "$new" >&2; return 1; }
  mkdir -p "$(dirname "$new")"
  mv "$old" "$new"
  printf '[migrate] moved %s → %s\n' "$old" "$new"
}

INSTALL_ROOT="$TARGET/$PREFIX/safeguard"
migrate_old_path "$TARGET/.safeguard" "$INSTALL_ROOT"
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

sync_js_dir() {
  local src="$1" dest="$2"
  # shellcheck disable=SC2206
  local files=( "$src"/*.js )
  if [ ! -e "${files[0]}" ]; then
    printf 'install: no *.js files in %s\n' "$src" >&2
    exit 1
  fi
  rm -f "$dest"/*.js
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

MERGER="$SCRIPT_DIR/core/lib/json-merge.py"
OPENCODE_TUI_MERGER="$SCRIPT_DIR/core/lib/opencode-tui-merge.py"

require_python3_for_json_merge() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf '[install] ERROR: python3 required to merge hook config.\n' >&2
    exit 1
  fi
}

enable_codex_hooks_feature() {
  local config="$1"
  mkdir -p "$(dirname "$config")"

  if [ ! -f "$config" ]; then
    {
      printf '[features]\n'
      printf 'codex_hooks = true\n'
    } > "$config"
    return 0
  fi

  if grep -qE '^[[:space:]]*codex_hooks[[:space:]]*=' "$config"; then
    tmp=$(mktemp)
    sed 's/^\([[:space:]]*codex_hooks[[:space:]]*=[[:space:]]*\).*/\1true/' "$config" > "$tmp"
    mv "$tmp" "$config"
    return 0
  fi

  tmp=$(mktemp)
  awk '
    BEGIN { inserted = 0 }
    /^\[features\][[:space:]]*$/ && inserted == 0 {
      print
      print "codex_hooks = true"
      inserted = 1
      next
    }
    { print }
    END {
      if (inserted == 0) {
        print ""
        print "[features]"
        print "codex_hooks = true"
      }
    }
  ' "$config" > "$tmp"
  mv "$tmp" "$config"
}

if [ "$WITH_CC" -eq 1 ]; then
  ADAPTER_DIR="$INSTALL_ROOT/adapter"
  mkdir -p "$ADAPTER_DIR/hooks"
  printf '[install] copying Claude Code adapter to %s\n' "$ADAPTER_DIR"
  sync_sh_dir "$SCRIPT_DIR/adapters/claude-code/hooks" "$ADAPTER_DIR/hooks"
  chmod +x "$ADAPTER_DIR/hooks/"*.sh

  # Patch settings-hooks.json template for the actual PREFIX before merging.
  _SRC_SNIPPET="$SCRIPT_DIR/adapters/claude-code/settings-hooks.json"
  PATCHED_SNIPPET=$(mktemp)
  TMP_FILES="$TMP_FILES $PATCHED_SNIPPET"
  sed "s|/\\.safeguard/adapter/hooks/|/$PREFIX/safeguard/adapter/hooks/|g" "$_SRC_SNIPPET" > "$PATCHED_SNIPPET"

  SETTINGS="$TARGET/.claude/settings.json"
  mkdir -p "$TARGET/.claude"

  require_python3_for_json_merge
  printf '[install] merging hooks into %s\n' "$SETTINGS"
  python3 "$MERGER" "$SETTINGS" "$PATCHED_SNIPPET"
fi

if [ "$WITH_CODEX" -eq 1 ]; then
  CODEX_ADAPTER_DIR="$INSTALL_ROOT/adapter-codex"
  mkdir -p "$CODEX_ADAPTER_DIR/hooks"
  printf '[install] copying Codex adapter to %s\n' "$CODEX_ADAPTER_DIR"
  sync_sh_dir "$SCRIPT_DIR/adapters/codex/hooks" "$CODEX_ADAPTER_DIR/hooks"
  chmod +x "$CODEX_ADAPTER_DIR/hooks/"*.sh

  _SRC_CODEX_HOOKS="$SCRIPT_DIR/adapters/codex/hooks.json"
  PATCHED_CODEX_HOOKS=$(mktemp)
  TMP_FILES="$TMP_FILES $PATCHED_CODEX_HOOKS"
  sed "s|__SAFEGUARD_PREFIX__|$PREFIX|g" "$_SRC_CODEX_HOOKS" > "$PATCHED_CODEX_HOOKS"

  CODEX_DIR="$TARGET/.codex"
  CODEX_HOOKS="$CODEX_DIR/hooks.json"
  CODEX_CONFIG="$CODEX_DIR/config.toml"
  mkdir -p "$CODEX_DIR"

  require_python3_for_json_merge
  printf '[install] merging Codex hooks into %s\n' "$CODEX_HOOKS"
  python3 "$MERGER" "$CODEX_HOOKS" "$PATCHED_CODEX_HOOKS"
  printf '[install] enabling Codex hooks in %s\n' "$CODEX_CONFIG"
  enable_codex_hooks_feature "$CODEX_CONFIG"
fi

if [ "$WITH_OPENCODE" -eq 1 ]; then
  OPENCODE_ADAPTER_DIR="$INSTALL_ROOT/adapter-opencode"
  mkdir -p "$OPENCODE_ADAPTER_DIR/plugins"
  printf '[install] copying OpenCode adapter to %s\n' "$OPENCODE_ADAPTER_DIR"
  sync_js_dir "$SCRIPT_DIR/adapters/opencode/plugins" "$OPENCODE_ADAPTER_DIR/plugins"

  OPENCODE_DIR="$TARGET/.opencode"
  OPENCODE_PLUGINS="$OPENCODE_DIR/plugins"
  OPENCODE_TUI_PLUGIN_DIR="$OPENCODE_PLUGINS/safeguard-tui"
  mkdir -p "$OPENCODE_PLUGINS" "$OPENCODE_TUI_PLUGIN_DIR"

  JS_PREFIX=$(printf '%s' "$PREFIX" | sed "s|\\\\|/|g; s|'|\\\\'|g")
  printf '%s\n' \
    "'use strict'" \
    "module.exports = require('../../$JS_PREFIX/safeguard/adapter-opencode/plugins/safeguard-server.js')" \
    > "$OPENCODE_PLUGINS/safeguard-server.js"
  printf '%s\n' \
    "'use strict'" \
    "module.exports = require('../../../$JS_PREFIX/safeguard/adapter-opencode/plugins/safeguard-tui.js')" \
    > "$OPENCODE_TUI_PLUGIN_DIR/index.js"

  require_python3_for_json_merge
  printf '[install] enabling OpenCode TUI plugin in %s\n' "$OPENCODE_DIR/tui.json"
  python3 "$OPENCODE_TUI_MERGER" "$OPENCODE_DIR/tui.json" "./plugins/safeguard-tui"
fi

printf '[install] done.\n'
printf '  core installed at: %s\n' "$INSTALL_ROOT/core"
[ "$WITH_CC" -eq 1 ] && printf '  claude-code adapter: %s\n' "$INSTALL_ROOT/adapter"
[ "$WITH_CODEX" -eq 1 ] && printf '  codex adapter: %s\n' "$INSTALL_ROOT/adapter-codex"
[ "$WITH_OPENCODE" -eq 1 ] && printf '  opencode adapter: %s\n' "$INSTALL_ROOT/adapter-opencode"
printf '\n  Commit %s/ (and host config such as .claude/settings.json, .codex/, or .opencode/ if used)\n' "$INSTALL_ROOT"
printf '  so that guards are available in worktrees.\n'
