# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Project

`safeguard` is a tool-agnostic bash layer that protects AI coding sessions from destructive actions. Zero runtime dependencies beyond `bash` and `git`. Target environments: Linux, macOS, Git Bash / WSL on Windows.

## Commands

```bash
bash tests/run.sh              # run all tests (fixtures + unit)
bash tests/run.sh fixtures     # fixture tests only
bash tests/run.sh unit         # unit tests only
bash tests/run.sh <guard>      # single guard (e.g. damage-control)

bash install.sh --target <repo>                     # install core only
bash install.sh --target <repo> --with-claude-code  # install core + CC adapter
```

## Architecture

### Two-layer split: `core/` is the contract, `adapters/` are translators

- **`core/cmd/safeguard-run.sh`** — single public entry point (multiplexer). Takes a guard group name, reads JSON on stdin, runs guards, emits tagged text (`BLOCK:`, `ASK:`, `WARN:`, or empty). Always exits `0` (fail-open).
- **`core/guards/*.sh`** — 6 independent guard scripts. Each reads JSON on stdin and emits tagged text. Internal, not public API.
- **`core/lib/json-field.sh`** — shared JSON field extraction. Internal helper.
- **`adapters/claude-code/hooks/*.sh`** — thin translation layer (~20 lines per hook) that converts between Claude Code's JSON protocol and core's text protocol.

### Fail-open safety-net policy

All guards exit `0` on error. A broken guard must never block a user's workflow.

### Guard output contract

- `BLOCK:<reason>` — hard deny
- `ASK:<reason>` — escalate to user
- `WARN:<context>` — informational, non-blocking
- Empty — allow

### Multiplexer priority

`BLOCK` > `ASK` > `WARN` > pass. Short-circuits on `BLOCK`.

## Conventions

- Shebang is `#!/bin/bash` everywhere, never `#!/bin/sh`.
- POSIX regex only — no `\b`, `\s`, `\w` (MSYS grep compatibility).
- `[[:space:]]` instead of `\s` in grep/sed.
- When changing `core/cmd/` behavior, update `CONTRACT.md` in the same commit.
- Guard tag prefix in user-visible messages: `[safeguard:<guard-name>]`.
- No CI skip in individual guards — the multiplexer handles it once.
