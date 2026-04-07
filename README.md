# Safeguard

AI coding safety net. Protects your sessions from destructive actions, credential leaks, prompt injection, infinite loops, and swallowed errors.

Pure bash. Zero dependencies. Install and forget.

## Quickstart

```bash
# Install into your project (with Claude Code hooks)
bash install.sh --target /path/to/repo --with-claude-code

# Or one-liner from GitHub (pinned to v1.0.0)
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/safeguard/v1.0.0/remote-install.sh) --with-claude-code

# Latest from main (may include unreleased changes)
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/safeguard/main/remote-install.sh) --with-claude-code
```

## What It Protects Against

| Guard | Threat | Action |
|-------|--------|--------|
| **damage-control** | Destructive shell commands (`rm -rf /`, `DROP TABLE`, `terraform destroy`, `vault kv destroy`, `helm uninstall`, `rsync --delete`, 40+ patterns) | Block or ask |
| **sensitive-file-guard** | Writes to credentials (`.env`, `.ssh/*`, `*.pem`, `*.tfstate`) | Block |
| **input-sanitizer** | Prompt injection patterns in files being read | Warn |
| **loop-detector** | Same command repeated 25+ times (AI stuck in loop) | Block |
| **error-suppression-scanner** | Swallowed errors (`except: pass`, `.unwrap()`, empty catch) | Block |
| **no-push-to-main** | `git push` to main/master without review | Ask with diff context |

## Architecture

Two-layer design: tool-agnostic core + host-specific adapters.

```
Your Project
  .safeguard/
    core/              <-- tool-agnostic guards + multiplexer
      cmd/safeguard-run.sh   (single entry point)
      guards/*.sh            (6 independent guards)
      lib/json-field.sh      (shared JSON parser)
    adapter/           <-- Claude Code hooks (thin translators)
      hooks/pre-bash.sh, pre-edit.sh, pre-read.sh, post-bash.sh
```

**Core** receives JSON on stdin, emits tagged text (`BLOCK:`, `ASK:`, `WARN:`, or empty).
**Adapter** translates between the host tool's format and core's text protocol.

Adding a new host (Cursor, Windsurf, etc.) = write 4 adapter hooks (~20 lines each), zero changes to core.

## Configuration

Environment variables only — no config files.

| Variable | Default | Description |
|----------|---------|-------------|
| `SAFEGUARD_DISABLED` | unset | `1` to disable all guards |
| `SAFEGUARD_DISABLE_DAMAGE_CONTROL` | unset | `1` to disable a specific guard |
| `SAFEGUARD_DISABLE_SENSITIVE_FILE` | unset | (same pattern for each guard) |
| `SAFEGUARD_LOOP_THRESHOLD` | 25 / 30 | Loop detector threshold |
| `CI` | unset | `true` skips all guards |

## Install

```bash
bash install.sh [--target <repo-dir>] [--with-claude-code]
```

- `--target`: Path to target git repo (default: current directory)
- `--with-claude-code`: Also install Claude Code adapter hooks and merge into `.claude/settings.json`
- Idempotent: re-running updates files in place
- Adds `/.safeguard/` to `.gitignore`

## Testing

```bash
bash tests/run.sh              # all tests (fixtures + unit)
bash tests/run.sh fixtures     # fixture tests only
bash tests/run.sh unit         # unit tests only
bash tests/run.sh damage-control  # single guard
```

## Platform Support

- **Windows (Git Bash / MSYS2):** fully supported
- **Linux / macOS / WSL:** supported

## Why Bash?

- Zero runtime dependencies (bash + git are already everywhere)
- Guard hooks are bash scripts by convention in Claude Code
- Small surface area (~500 lines of production code across 6 guards + multiplexer)
- Portable across all platforms without compilation

## Related

- [singularity-sandbox](https://github.com/uplift-labs/singularity-sandbox) — Worktree isolation for AI coding sessions (complementary product)

## License

MIT
