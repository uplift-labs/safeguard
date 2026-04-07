# Public CLI Contract

`core/cmd/safeguard-run.sh` is the single stable public entry point. Scripts
under `core/guards/` and `core/lib/` are internal and may change without notice.

## Conventions

- **Input:** JSON on stdin (the raw hook payload from the host tool).
- **Output:** tagged plain text on stdout (see Output Tags below).
- **Exit codes:** always `0`. Safeguard is a fail-open safety net — errors
  in guards are swallowed, never propagated.
- **No state files** except `/tmp/safeguard-loop-*` for loop-detector
  counters (session-isolated, auto-decaying after 10 minutes of inactivity).

## Output Tags

| Tag | Meaning | Host action |
|-----|---------|-------------|
| `BLOCK:<reason>` | Hard deny — the action must not proceed | Block / deny |
| `ASK:<reason>` | Dangerous but possibly intentional — ask the user | Show confirmation dialog |
| `WARN:<context>` | Informational warning — does not block | Inject as advisory context |
| *(empty)* | All guards passed — allow | Proceed normally |

## Command

### `safeguard-run`

Run a group of guards against a single tool invocation.

```
safeguard-run.sh <group>
```

| Group | Guards | Hook event |
|-------|--------|------------|
| `pre-bash` | damage-control, no-push-to-main, loop-detector | PreToolUse Bash |
| `pre-edit` | sensitive-file-guard, error-suppression-scanner | PreToolUse Edit/Write |
| `pre-read` | input-sanitizer | PreToolUse Read |
| `post-bash` | loop-detector | PostToolUse Bash |

**Priority:** `BLOCK` > `ASK` > `WARN` > pass. On `BLOCK`, remaining guards
are short-circuited.

## Configuration (environment variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `SAFEGUARD_DISABLED` | unset | Set to `1` to disable all guards |
| `SAFEGUARD_DISABLE_<GUARD>` | unset | Disable a specific guard (e.g. `SAFEGUARD_DISABLE_DAMAGE_CONTROL=1`) |
| `SAFEGUARD_LOOP_THRESHOLD` | 25 (30 for git) | Loop detector repetition threshold |
| `CI` | unset | Set to `true` to skip all guards (CI environments) |

## Guards

### damage-control

Blocks or escalates destructive shell commands.

- **BLOCK:** recursive rm of system paths, filesystem format ops, raw device writes,
  kill-all, world-writable permissions, system power ops, fork bombs.
- **ASK:** `git reset --hard`, `git push --force`, `docker system prune`,
  `terraform destroy`, SQL DROP/TRUNCATE/DELETE-without-WHERE, Redis flush,
  MongoDB drop, and similar.

### sensitive-file-guard

Blocks writes to credential and secret files.

- **BLOCK:** `.env` (not `.env.example`), `.ssh/*`, `*.pem`, `*.key`, `.aws/*`,
  `.config/gcloud/*`, `.azure/*`, `.kube/*`, `*.tfstate`, service account JSON,
  `.npmrc`, `.pypirc`, `.git-credentials`, `.netrc`.

### input-sanitizer

Warns about potential prompt injection patterns in files being read.

- **WARN:** Files containing `ignore previous`, `system:`, `<system>`,
  `new instructions`, `disregard`, `forget everything`.
- Only scans `.md`, `.txt`, `.json`, `.yaml`, `.yml`, `.xml`, `.html`, `.csv`.

### loop-detector

Blocks repeated identical commands (loop detection).

- **BLOCK:** Same normalized command executed 25+ times (30 for git commands).
- Counter resets after 10 minutes of inactivity.
- Session-isolated via session_id from input JSON.

### error-suppression-scanner

Blocks code edits that introduce error suppression patterns.

- **BLOCK:** Empty catch blocks, `except: pass`, `.unwrap()`,
  `#[allow(unused)]`, `// eslint-disable`, `# type: ignore`, `rescue => nil`.
- Allows intentional suppression with preceding comment containing
  `intentional`, `safe here`, `TODO`, or `SAFETY`.

### no-push-to-main

Escalates git push to main/master with context.

- **ASK:** Any `git push` targeting `main` or `master` (explicit, refspec,
  or bare push from main branch). Shows commit count, diff stats, and
  GitHub compare URL.
