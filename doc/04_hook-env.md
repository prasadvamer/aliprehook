# Hook environment: passing variables to the main command

Design note for `ALIPREHOOK_ENV_FILE`. Behavior summary lives in [01_shell-aliprehook-system.md](./01_shell-aliprehook-system.md) § Passing environment to the main command; work items in [03_roadmap.md](./03_roadmap.md) Phase 5.

## Problem

A hook often needs to prepare **environment variables** for the main command:

```sh
# hooks/my_app_Dup.sh
export TOKEN="$(my-token-tool --profile dev)"   # placeholder command; docker compose up needs TOKEN
```

This does not work. aliprehook runs a hook as a **child process**. A child gets a copy of the shell's environment; its `export`s change only that copy and are gone when it exits. `docker compose up` is started later by the shell, without `TOKEN`.

```text
your shell (Dup function)
  ├─ hook.sh          export TOKEN=… → lives only inside hook.sh
  └─ docker compose   started by the shell → no TOKEN
```

Rejected alternatives:

| Option | Why not |
|---|---|
| Hook writes a `.env` file | Only helps Docker Compose; not every command is compose |
| `source` the hook into the shell | Hook can change anything in the shell (cwd, vars, functions); unacceptable, especially for project hooks |

## Design: `ALIPREHOOK_ENV_FILE` file

Same idea as GitHub Actions' `GITHUB_ENV`.

1. Before each hook, aliprehook creates an empty temp file and passes its path as `ALIPREHOOK_ENV_FILE`.
2. The hook passes variables with the `aliprehook_env_pass` command, which is always on the hook's `PATH` (see [Hook helper](#hook-helper-aliprehook_env_pass)):
   ```sh
   export TOKEN="$(my-token-tool --profile dev)"   # placeholder: any command that prints a value
   aliprehook_env_pass TOKEN
   ```
   Under the hood this appends `NAME=value` lines to the file; hooks may also write them directly.
3. After the hook **succeeds**, aliprehook **parses** the file (never `source`s it).
4. The main command runs with those variables set.
5. The temp file is deleted in every case (success, failure, Ctrl-C).

If the hook fails, its file is ignored and the command stops as today.

### File format

```text
NAME=value                 # one variable; value is everything after the first '='
EMPTY=                     # empty string
MULTI<<END_7f3a            # multi-line value, until a line equal to the delimiter
line one
line two
END_7f3a
```

- `NAME` must match `[A-Za-z_][A-Za-z0-9_]*`.
- Values are **literal**: no `$VAR` expansion, no `$(...)`, no quote handling. `A="x"` sets `A` to `"x"` including the quotes.
- Blank lines are ignored. No comments (a `#` is part of a value).
- Any other line → error with the hook name and line number; the command does not run.
- Multi-line delimiter is chosen by the hook; it should be random so a value cannot end the block early (`END_$(od -An -N4 -tx1 /dev/urandom | tr -d ' ')`).

## Hook helper: `aliprehook_env_pass`

Writing the file by hand means the same loop in every hook (read each variable, skip empty ones, handle newlines, append). aliprehook ships a helper command instead.

### Always available, nothing to load

For every hook, aliprehook puts its own `bin/` directory first on the hook's `PATH`, so `aliprehook_env_pass` is available like any other command. Hooks do **not** need to load or source anything. The absolute path is also in `$ALIPREHOOK_ENV_PASS_BIN`, for hooks that reset `PATH`.

Because it is a separate command, it reads the hook's **exported** variables (a child process only inherits exported ones):

| In the hook | Seen by `aliprehook_env_pass`? |
|---|---|
| `export TOKEN=abc` | Yes |
| `eval "$(aws configure export-credentials --format env)"` | Yes (the tool prints `export …` lines) |
| `TOKEN=abc` (not exported) | No → use `export`, or the `NAME=value` form below |

Alternatives considered for making a helper available without a load line, and why they were rejected:

| Approach | Problem |
|---|---|
| Shell function + `. "$ALIPREHOOK_HOOK_LIB"` in each hook | The load line in every hook, which is what we want to avoid |
| `BASH_ENV` (bash auto-loads a file for scripts) | bash only; `sh`/dash and zsh hooks ignore it |
| zsh `.zshenv` via `ZDOTDIR` | zsh only, and replaces the user's own `.zshenv` |
| aliprehook sources the hook into a prepared `sh` | Breaks the hook's shebang: bash/python hooks would run as `sh` |

A command on `PATH` is the only option that works the same for `sh`, bash, zsh, Python or any other hook.

### Usage

Pass several variables by name in one call:

```sh
#!/bin/sh
# hooks/sample_app_web_Dup.sh
# The AWS tool prints `export AWS_…=…` lines; eval sets and exports them in this hook.
eval "$(aws configure export-credentials --profile dev --format env)" || exit 1

aliprehook_env_pass AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

Set and pass in one step with `NAME=value` (no `export` needed):

```sh
#!/bin/sh
# Placeholders: replace `my-token-tool` / `my-secrets-cli` with your real commands.
aliprehook_env_pass \
  API_TOKEN="$(my-token-tool --profile dev)" \
  DB_PASSWORD="$(my-secrets-cli get sample_app_web/db)" \
  APP_ENV=development
```

Mix both forms in one call:

```sh
export REGION=eu-west-1
aliprehook_env_pass REGION BUILD_ID="$(date +%s)"
```

For each argument:

| Argument | Result |
|---|---|
| `NAME`, variable exported and non-empty | Passed |
| `NAME`, variable unset, empty or not exported | Optional: **warning**, not passed. Required: **error**, main command stopped (see below) |
| `NAME=value` with a non-empty value | Passed as given |
| `NAME=` (empty) | Counts as missing (unless `--allow-empty`) |
| Invalid name, or reserved `ALIPREHOOK_*` | Error; command returns non-zero |

Warning example:

```text
aliprehook: warning: sample_app_web_Dup.sh: AWS_SESSION_TOKEN has no value (unset, empty or not exported); not passed to Dup
```

### Required and optional variables

By default every name is **optional**: a missing value prints a warning, the variable is skipped and the command still runs.

Mark names as **required** with mode switches in the same call:

> `--required` and `--optional` switch the mode for **all names after them**, until the next switch. Names before any switch are optional.

```sh
aliprehook_env_pass --required VAR1 VAR2 VAR3 --optional VAR4
aliprehook_env_pass VAR4 --required VAR1 VAR2 VAR3            # same thing
aliprehook_env_pass --required API_TOKEN="$(my-token-tool)" REGION --optional DEBUG_LEVEL
```

| Missing value for | Result |
|---|---|
| Optional name | Warning; not passed; command still runs |
| Required name | Error; aliprehook **stops the main command** after the hook finishes |

How required is enforced:

1. `aliprehook_env_pass` checks **all** names first and reports every missing one in one go (not just the first).
2. For a missing required name it writes a marker to `$ALIPREHOOK_ENV_FILE` and returns non-zero.
3. When the hook finishes, aliprehook sees the marker and aborts the main command, **even if the hook exited 0**. No `|| exit $?` is needed.

```text
aliprehook: error: sample_app_web_Dup.sh: API_TOKEN has no value (required)
aliprehook: Dup aborted: required variable missing: API_TOKEN
```

The hook itself keeps running after the call. To stop it immediately (e.g. before slow work that is pointless without the token), add `|| exit $?`; this is optional.

The marker is written only by `aliprehook_env_pass` (a reserved line that `NAME=value` parsing never produces), so hooks writing the file directly keep working.

`--allow-empty` is a **global** option for the whole call, wherever it is placed: empty values (`FOO=`) are passed instead of counting as missing.

### Checking variables that are already set

`--required` also works as a **prerequisite check** for variables your terminal already has (e.g. exported by an earlier `aws-login`). Nothing new is passed: the hook only checks what it inherited.

```text
terminal (AWS_* exported by an earlier login)
   │  inherits (exported variables only)
   ▼
hook: aliprehook_env_pass --required AWS_ACCESS_KEY_ID …
   │  missing → error, the command does not run
   │  present → written to the env file (no effect: the command inherits it anyway)
   ▼
Dbuild runs
```

```sh
#!/bin/sh
# hooks/require_aws.sh   (registry: *  Dbuild  hooks/require_aws.sh)
aliprehook_env_pass --required AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

Nothing ever goes back to the terminal (unless `--keep-env`). This checks presence only; an expired session still passes, so add a real check (`aws sts get-caller-identity`) in the same hook if needed.

Put the check in its own hook and register it with `*` (or first for the project), so it runs before slower hooks. No separate "requires" declaration is planned: hooks already run in order, can check anything (presence, validity), and `--required` covers the common case.

### Fix hint: `--hint`

A missing required value says *what* is missing; `--hint` says *how to fix it*:

```sh
aliprehook_env_pass --required AWS_ACCESS_KEY_ID AWS_SESSION_TOKEN --hint "run: aws-login"
```

```text
aliprehook: error: require_aws.sh: AWS_ACCESS_KEY_ID has no value (required) (run: aws-login)
aliprehook: error: require_aws.sh: AWS_SESSION_TOKEN has no value (required) (run: aws-login)
aliprehook: Dbuild aborted: required variable missing: AWS_ACCESS_KEY_ID, AWS_SESSION_TOKEN
```

- `--hint TEXT` is a **global** option for the call, wherever it is placed (like `--allow-empty`); at most once per call (twice → usage error, exit 2).
- Shown in parentheses, in the `hint` color, after each **required** name's error. Optional names' warnings do not show it.
- Display text only, never run. A hook needing different hints for different variables makes one call per group.

### How it works

- `aliprehook_env_pass` is a small POSIX `sh` script installed in aliprehook's `bin/` (managed by `install.sh` / `uninstall.sh` like `lib.zsh`).
- It writes the file format above; a value with a newline is written as a `NAME<<DELIM` block with a random delimiter, so hook authors never deal with quoting or delimiters.
- It only writes the file; the checks in [Issues and solutions](#issues-and-solutions) (denylist, limits, precedence) still apply when aliprehook reads it.
- Outside a hook (no `$ALIPREHOOK_ENV_FILE`) it is an error, not a silent no-op.
- Hooks in any language can call it (e.g. `subprocess.run(["aliprehook_env_pass", "TOKEN=" + token])` in Python), or write `NAME=value` lines to `$ALIPREHOOK_ENV_FILE` directly.

### Where the variables end up

`aliprehook_env_pass` hands variables to the **main command** (`docker compose up`), not the terminal. They stay in the terminal afterwards only for commands defined with `--keep-env` (see issue 1).

### Common tool patterns

| Tool | In the hook |
|---|---|
| Prints `export …` lines (`aws configure export-credentials --format env`) | `eval "$(tool …)"`, then `aliprehook_env_pass NAME…` |
| Prints just a value | `aliprehook_env_pass NAME="$(tool …)"` |
| Shell script meant to be sourced | `. ./script.sh`, then `aliprehook_env_pass NAME…` (export the names first if the script does not) |
| Runs a child with the variables (`aws-vault exec prof -- cmd`) | No hook needed: `aliprehook_define Dup aws-vault exec prof -- docker compose up` |
| Writes credential files (`aws sso login`) | Usually nothing to pass; tools read the files |

## Issues and solutions

### 1. Where do the variables end up? (decided: C)

| Option | Main command sees them | Terminal afterwards |
|---|---|---|
| **A. Command only** | Yes | Unchanged |
| **B. Kept in terminal** | Yes | Variables stay set |
| **C. A by default, B opt-in per command** | Yes | Only for opted-in commands |

Recommendation: **C**, with A as the default.

- A is predictable: running `Dup` does not silently change the shell for every later command.
- Secrets (tokens) do not linger in the terminal or get inherited by unrelated commands.
- B is still available where it is really wanted: `aliprehook_define --keep-env Dup docker compose up`.
- Project hooks can never use B (see 3).

### 2. User hook vs project hook

Both layers can write variables. Two sub-issues:

**Precedence.** If both set `FOO`, which wins? → **User wins.** The user layer is the user's own config and must be able to override a repo's defaults. Precedence is fixed, independent of run order.

**Several user hooks** (common `*` hook + project-specific ones, see 01 § Multiple hooks): each later user hook sees the variables written by earlier user hooks, so a common hook can prepare something a specific one uses. For the main command, the later (more specific) user hook wins.

**Leaking user secrets to repo scripts.** The user hook runs first. If its variables were passed to the project hook, any allowed repo could read the user's tokens. → **Project hooks do not see variables written by user hooks.** Variables are merged only for the main command.

### 3. Dangerous variables from project hooks

A project hook could set variables that change how later programs behave: `PATH`, `LD_PRELOAD`, `LD_*`, `DYLD_*`, `BASH_ENV`, `ENV`, `ZDOTDIR`, `IFS`, `PS4`, `PROMPT_COMMAND`, `HOME`, `SHELL`, `GIT_SSH_COMMAND`, `GIT_EXEC_PATH`.

→ **Denylist for project hooks:** these names are rejected (error, command does not run). User hooks may set anything.

Honest scope: with option A, an allowed project hook already runs arbitrary code, so the denylist mainly prevents mistakes and surprising behavior. It matters more for anything that outlives the command, which is why project hooks never get `--keep-env`.

Names starting with `ALIPREHOOK_` are reserved for aliprehook in both layers.

### 4. Secrets on disk

The temp file may hold tokens.

- Create it with `mktemp` and mode `0600`, under `$XDG_RUNTIME_DIR` when available (RAM-backed, per-user), else `$TMPDIR`.
- Delete it with an `always` block / trap so Ctrl-C does not leave it behind.
- `aliprehook explain` and error messages print **names only, never values**.

### 5. How the main command gets the variables

The main command may be a shell function or alias, not just a binary, so `env FOO=bar cmd` does not work. Use zsh's function-scoped exports, declared **in the wrapper itself**:

```zsh
# generated by aliprehook_define
Dup () {
  aliprehook_run Dup "$@" || return $?
  _aliprehook_env_decl                 # builds `local -x NAME=value` lines, clears the collected set
  eval "$_aliprehook_env_code"         # declares them in this function
  docker compose up "$@"
}
# The exports vanish when Dup returns. With --keep-env, user-layer variables
# are declared with `typeset -gx` instead and stay in the shell.
```

Why not `aliprehook_with_env docker compose up "$@"` in the wrapper: the command would become an *argument*, and zsh only expands aliases in command position, so `aliprehook_define X myalias` would break. Declaring the variables in the wrapper keeps the main command where it was.

For Case B/C functions (own logic + `aliprehook_run`), the public helper runs one command with the variables:

```zsh
Dclear() {
  aliprehook_run Dclear "$@" || return $?
  aliprehook_with_env ./scripts/clear.sh "$@"
}
```

`aliprehook_run` stores the collected variables in global associative arrays; the next declaration (`aliprehook_with_env` or the generated wrapper) consumes and clears them, and the next `aliprehook_run` resets them, so values never leak to a later, unrelated command.

### 6. Unsetting variables

Not in the first version. `NAME=` sets an empty string; real unset (e.g. `-NAME`) can be added later if needed.

### 7. Size and abuse

Cap the file (e.g. 64 KiB) and the number of variables (e.g. 100). Over the cap → error, command does not run.

### 8. Docker Compose detail

Variables reaching `docker compose` are **not** automatically inside the container. Compose uses them for `${VAR}` interpolation in `compose.yaml`; to pass one into a container, list it:

```yaml
services:
  app:
    environment:
      - TOKEN          # value taken from the environment aliprehook set
```

Documented in the README (§ 8. Pass variables to the command).

### 9. Other shells and languages

The protocol is "append lines to a file", so hooks can be written in any language, and the same format works when bash/fish support lands (Phase 11).

## Decisions

All decided and implemented (roadmap Phase 5b).

| # | Decision | Chosen |
|---|---|---|
| 1 | Scope: A / B / C | C (A default, `--keep-env` opt-in for user-layer commands) |
| 2 | Precedence when both layers set a name | User wins |
| 3 | Project hooks see user-hook variables | No |
| 4 | Project-hook denylist | Yes, list in issue 3 |
| 6 | Unset support in v1 | No |
| 7 | Hook helper | Yes: `aliprehook_env_pass` command on the hook's `PATH` (no load line); `NAME` and `NAME=value` forms; optional by default (warning), `--required` / `--optional` mode switches in one call; aliprehook stops the main command on a missing required value (no `\|\| exit $?`) |
