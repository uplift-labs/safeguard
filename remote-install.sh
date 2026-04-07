#!/bin/bash
# remote-install.sh — fetch safeguard and install into the current repo.
#
# Usage:
#   bash <(curl -sSL https://raw.githubusercontent.com/sergey-akhalkov/safeguard/main/remote-install.sh) [--with-claude-code]
#
# Clones the repo into a temp dir, runs install.sh, cleans up.

set -u

REPO_URL="https://github.com/sergey-akhalkov/safeguard.git"
TARGET="$(pwd)"
PASSTHROUGH_ARGS=("--target" "$TARGET")

for arg in "$@"; do
  PASSTHROUGH_ARGS+=("$arg")
done

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

printf '[remote-install] cloning safeguard...\n'
git clone --depth 1 "$REPO_URL" "$TMPDIR/safeguard" 2>/dev/null || {
  printf 'failed to clone %s\n' "$REPO_URL" >&2
  exit 1
}

bash "$TMPDIR/safeguard/install.sh" "${PASSTHROUGH_ARGS[@]}"
