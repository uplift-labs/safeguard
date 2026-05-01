# AGENTS.md

Project guidance for Codex and other coding agents working in this repository.

## Project

`safeguard` is a tool-agnostic bash safety layer for AI coding sessions. The
stable public API is `core/cmd/safeguard-run.sh`; host-specific code belongs in
`adapters/`.

## Commands

```bash
bash tests/run.sh              # run all tests
bash tests/run.sh unit         # unit tests only
bash tests/run.sh <guard>      # single guard fixtures

bash install.sh --target <repo> --with-codex
bash install.sh --target <repo> --with-claude-code
```

On native Windows, prefer Git Bash when running tests.

## Architecture

- `core/cmd/safeguard-run.sh` reads JSON on stdin and emits `BLOCK:`, `ASK:`,
  `WARN:`, or empty output. It always exits `0`.
- `core/guards/*.sh` are internal guard implementations.
- `adapters/claude-code/` translates Claude Code hook protocol.
- `adapters/codex/` translates Codex hook protocol.

Keep core behavior host-neutral. If a host has different hook semantics, handle
that in its adapter.

## Codex Adapter Notes

- Codex `PreToolUse` supports hard deny, but `ask` decisions are not enforced
  today. The Codex adapter maps Safeguard `ASK:` to deny by default.
- `SAFEGUARD_CODEX_ASK_MODE=warn` downgrades `ASK:` to a `systemMessage`.
- Codex file edits are checked through `apply_patch` parsing in
  `adapters/codex/hooks/pre-apply-patch.sh`.
- Project-local Codex hooks require `[features] codex_hooks = true` in
  `.codex/config.toml`.

## Conventions

- Use `#!/bin/bash`, not `#!/bin/sh`.
- Avoid GNU-only regex features where MSYS compatibility matters.
- Keep adapters thin; do not duplicate guard logic outside `core/guards`.
- Update tests when changing hook protocol translation.
