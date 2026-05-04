# AGENTS.md

## Project

- `safeguard` is a Bash-only safety layer. The stable public API is `core/cmd/safeguard-run.sh`; `core/guards/` and `core/lib/` are internal.
- Product source is `core/`, `adapters/`, `tests/`, `install.sh`, and `remote-install.sh`. Do not make product changes in the checked-in `.safeguard/` local install copy or `.uplift/sandbox/` worktree-sandbox tooling unless that artifact is the task.

## Commands

```bash
bash tests/run.sh                 # all fixtures + unit tests
bash tests/run.sh fixtures        # fixture tests only
bash tests/run.sh unit            # unit tests only
bash tests/run.sh damage-control  # one guard's fixtures

bash install.sh --target <git-repo> [--prefix <dir>] [--with-claude-code] [--with-codex]
```

- On native Windows, run tests with Git Bash/MSYS bash rather than PowerShell shell semantics.
- Adapter installs merge host hook config and require `python3`; core-only install is Bash/Git only.

## Core Contract

- `safeguard-run.sh <group>` reads raw hook JSON on stdin, emits only `BLOCK:`, `ASK:`, `WARN:`, or empty stdout, and always exits `0` (fail-open).
- Guard groups: `pre-bash` = damage-control/no-push-to-main/loop-detector; `pre-edit` = sensitive-file-guard/error-suppression-scanner; `pre-read` = input-sanitizer; `post-bash` = loop-detector.
- Multiplexer priority is `BLOCK` > `ASK` > `WARN`; it short-circuits on `BLOCK` and owns the `CI=true`, `SAFEGUARD_DISABLED=1`, and `SAFEGUARD_DISABLE_<GUARD>=1` bypasses.
- If `core/cmd/` behavior or tagged output semantics change, update `CONTRACT.md`.

## Adapter Boundaries

- Keep guard logic host-neutral in `core/guards`; adapters only translate host JSON/protocol to and from the core text contract.
- Source adapters live in `adapters/claude-code/` and `adapters/codex/`; install paths are `.uplift/safeguard/adapter` and `.uplift/safeguard/adapter-codex`.
- Codex `PreToolUse` cannot enforce `ask`, so Codex maps core `ASK:` to deny unless `SAFEGUARD_CODEX_ASK_MODE=warn`; `PermissionRequest` `ASK:` returns empty so Codex can show its normal approval prompt.
- Codex edit protection depends on `adapters/codex/hooks/pre-apply-patch.sh` parsing `apply_patch` paths/added lines and calling the core `pre-edit` group.
- Project-local Codex hooks require `.codex/hooks.json` plus `[features] codex_hooks = true` in `.codex/config.toml`.

## Bash And Tests

- Use `#!/bin/bash`; avoid GNU-only regex tokens that break MSYS (`\b`, `\s`, `\w`); prefer POSIX classes like `[[:space:]]`.
- User-visible guard messages should keep the `[safeguard:<guard-name>]` prefix.
- Fixture tests use `tp-*` for expected trigger and `tn-*` for expected pass; add or update fixtures when guard decisions change.
- Loop detector state lives in `/tmp/safeguard-loop-*`; the test runner cleans it, but clear it manually when reproducing loop tests outside `tests/run.sh`.
- When changing hook protocol translation, update the adapter unit tests (`tests/unit/test-adapters.sh` or `tests/unit/test-adapter-codex.sh`) as well as any affected guard fixtures.
