#!/bin/bash
# remote-install.sh — fetch safeguard and install into the current repo.
#
# Usage:
#   bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/safeguard/main/remote-install.sh) [--prefix <dir>] [--with-codex] [--with-claude-code]
#
# Clones the repo into a temp dir, runs install.sh, cleans up.
# Set SAFEGUARD_VERSION to pin a specific tag or branch (default: main).
# Default --prefix is .uplift (installs to <target>/.uplift/safeguard).

set -u

REPO_URL="https://github.com/uplift-labs/safeguard.git"
VERSION="${SAFEGUARD_VERSION:-main}"
TARGET="$(pwd)"
PASSTHROUGH_ARGS=("--target" "$TARGET")

for arg in "$@"; do
  PASSTHROUGH_ARGS+=("$arg")
done

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

printf '[remote-install] cloning safeguard@%s...\n' "$VERSION"
git clone --depth 1 --branch "$VERSION" "$REPO_URL" "$TMPDIR/safeguard" 2>/dev/null || {
  printf 'failed to clone %s\n' "$REPO_URL" >&2
  exit 1
}

bash "$TMPDIR/safeguard/install.sh" "${PASSTHROUGH_ARGS[@]}"
