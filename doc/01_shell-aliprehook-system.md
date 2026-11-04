# Generic shell aliprehook system

## Goal

A **generic** wrapper so any opt-in command can run optional prehooks based on where you are. Project identity prefers **git remote** (portable across clone paths), then falls back to `$PWD`. Commands that do not opt in stay normal aliases/functions. `Dup` (docker compose up) is only one example consumer.

Config is split into two layers:

- **User layer** — your personal shortcuts and hooks under `~/.config/aliprehook/`
- **Project layer** — optional in-repo suggestions (e.g. `.aliprehook.yml`), **off until allowed**

## Naming

- System name: **aliprehook**
- User config dir: `~/.config/aliprehook/`
- Opt-in helper: `aliprehook_define`
- Runtime lookup: `aliprehook_run` (internal)
- Allow project layer: `aliprehook allow` / `aliprehook revoke` (direnv-style)

Daily use stays the **command name** you define (`Dup`, `serve`, …), not typing `aliprehook` every time.

## Config layers

Two different places config can live — owned by different people:

| Layer | Where it lives | Who writes it | Purpose |
|---|---|---|---|
| **User layer** | `~/.config/aliprehook/` | You | *Your* commands (`Dup`), *your* registry, *your* hooks |
| **Project layer** (optional) | Inside the git repo, e.g. `.aliprehook.yml` (+ optional scripts) | You or the team | Prep for *this* project (“before compose, copy `.env.example`”) |

**Why both?**

- Personal `Dup` should not be forced into every company repo.
- Project tips should not require every developer to hand-edit `~/.config`.
- **Security:** cloning a repo must not silently run project hooks. Project layer is **off until `aliprehook allow`**.

**Run order when you type `Dup --watch`:**

```text
You type: Dup --watch
    │
    ├─ 1) User layer: registry hook for (project key, Dup)? → run if any
    ├─ 2) Project layer: only if this repo was allowed → hook from .aliprehook.yml for Dup?
    └─ 3) docker compose up --watch
```

If a hook exits non-zero, abort before the next step / main command.

### Allow list (project layer gate)

Allowed repos are recorded under the user layer, e.g.:

```text
~/.config/aliprehook/allowed
# one normalized project key per line
github.com/org/sample_app_web
```

- `aliprehook allow` — add current project key to `allowed`
- `aliprehook revoke` — remove it
- No entry → skip project layer entirely (user layer still runs)

## Layout

### User layer

```text
~/.config/aliprehook/
  README.md            # how it works, setup, layers, allow, how to add a hook
  lib.zsh              # sourced from ~/.zshrc
  registry             # user lookup table: project_key + command → hook
  allowed              # project keys that may run project-layer hooks
  hooks/               # user prehook scripts
    example_echo.sh    # initial example (safe; prints project key + cmd)
    sample_app_web_Dup.sh
```

### Project layer (in a repo)

```text
<repo>/
  .aliprehook.yml     # declares command → hook (relative paths)
  .aliprehook/        # optional scripts referenced by the yml
    before_Dup.sh
```

Example `.aliprehook.yml`:

```yaml
# Only used after: aliprehook allow
hooks:
  Dup: .aliprehook/before_Dup.sh
  serve: .aliprehook/before_serve.sh
```

Each key under `hooks:` must be a command name. A repo **cannot** define `*` (all-projects) hooks; those exist only in the user `registry`, so a repo can never run code in other projects.

- `aliprehook allow` refuses a yml with a `*` (or otherwise invalid) entry and prints the line number.
- If an allowed repo's yml later gains one, the entry is ignored and every run prints a warning; the repo's valid hooks still run.

### README.md (required in user layer)

Ships with the install so anyone opening `~/.config/aliprehook/` can learn the system. Cover:

1. **What aliprehook is** — optional prehooks; user + project layers
2. **Setup** — `source` lib in `~/.zshrc`, then `aliprehook_define …`
3. **Project key order** — origin → first remote → PWD + normalization
4. **User registry** — three columns; commented examples
5. **Project layer + allow** — `.aliprehook.yml`, `aliprehook allow` / `revoke`
6. **How to add a user hook** — copy `example_echo.sh`, register, reload
7. **Try the example** — register current repo to `example_echo.sh`, run, see echo

### Initial example hook (user layer)

`hooks/example_echo.sh` is safe (no docker, no side effects): print that aliprehook ran, print project key and command name, exit 0.

`registry` ships with a **commented** example line pointing at it.

## How the project key is resolved

When you run an opt-in command, aliprehook picks a **project key** in this order:

1. **`origin` remote** — if `git remote get-url origin` succeeds
2. **Else first remote** — first URL from `git remote -v` (fetch)
3. **Else `$PWD`** — `pwd -P`

For steps 1–2, the remote URL is **normalized** before lookup/compare. User `registry` and `allowed` store the **normalized** form.

```mermaid
flowchart TD
  start["Resolve project key"]
  inGit{"Inside a git work tree?"}
  origin{"origin remote URL exists?"}
  first{"Any other remote URL?"}
  norm["Normalize remote URL string"]
  pwdKey["Use pwd -P"]
  done["Use key for user registry + allow check"]

  start --> inGit
  inGit -->|no| pwdKey --> done
  inGit -->|yes| origin
  origin -->|yes| norm --> done
  origin -->|no| first
  first -->|yes| norm
  first -->|no| pwdKey
```

### Remote URL normalization

| Raw remote | After normalize (example) |
|---|---|
| `git@github.com:org/sample_app_web.git` | `github.com/org/sample_app_web` |
| `https://github.com/org/sample_app_web.git` | `github.com/org/sample_app_web` |
| `https://github.com/org/sample_app_web` | `github.com/org/sample_app_web` |
| `ssh://git@github.com/org/sample_app_web.git` | `github.com/org/sample_app_web` |

Rules (in `lib.zsh`):

- Strip `https://`, `http://`, `ssh://`, and `git@` / userinfo
- Turn `host:org/repo` (SCP-style) into `host/org/repo`
- Drop trailing `.git` and trailing `/`
- Lowercase host

## User registry

Plain text file under the user layer. Answers:

> “When I am in **this project** and I run **this command**, which **user** hooks should run first?”

| Column | Meaning | Example |
|---|---|---|
| 1. Project key | Normalized remote, path fallback, or `*` for every project | `github.com/org/sample_app_web` |
| 2. Command name | Which alias/function | `Dup` |
| 3. Hook script | Path under user `hooks/` | `hooks/sample_app_web_Dup.sh` |

### Multiple hooks and the common (`*`) hook

A command can have **several user hooks**, and a **common hook** that runs in every project:

```text
*                              Dup  hooks/common_Dup.sh
github.com/org/sample_app_web  Dup  hooks/sample_app_web_Dup.sh
github.com/org/sample_app_web  Dup  hooks/sample_app_web_db.sh
```

Rules:

- **All matching lines run**, not just the first.
- **Order:** `*` lines first, then lines for the exact project key; within each group, file order.
- **First failure stops everything:** later hooks, the project layer and the main command do not run.
- `*` matches every project key (remote or path). It is the only wildcard; no partial patterns like `github.com/org/*`.
- `*` lines live **only** in the user `registry` (`~/.config/aliprehook/registry`), with scripts in the user `hooks/`. A repo's `.aliprehook.yml` cannot define them (see § Project layer); the project layer applies only to its own repo.
- `*` replaces only the project key: the command column must still match. `*  Dup  …` runs before `Dup` everywhere, never before `serve`.
- A command can have several `*` lines; all of them run, in file order, before the exact-key lines.
- Duplicate lines (same key, command and hook) run once.
- Hook environment ([04_hook-env.md](./04_hook-env.md)): a later user hook sees variables written by earlier user hooks; for the main command, the later (more specific) user hook wins.

Run order for `Dup` in `sample_app_web`:

```text
1) hooks/common_Dup.sh              (* line)
2) hooks/sample_app_web_Dup.sh      (exact key, file order)
3) hooks/sample_app_web_db.sh
4) .aliprehook.yml hook for Dup     (project layer, only if allowed)
5) docker compose up
```

Opting a project out of `*` hooks (e.g. `github.com/org/x  Dup  -`) is **not** planned yet; add it only if needed.

### Example user `registry`

```text
# project_key  command  hook_relative_path

github.com/org/sample_app_web  Dup hooks/sample_app_web_Dup.sh
github.com/org/sample_app_api  Dup hooks/sample_app_api_Dup.sh
github.com/org/sample_app_web  serve hooks/sample_app_web_serve.sh

# Fallback: no remotes — key is absolute path
# /Users/me/scratch/local-compose-playground  Dup hooks/scratch_Dup.sh
```

| You are here | You type | What runs |
|---|---|---|
| Any clone of `sample_app_web` | `Dup --watch` | user hooks (`*`, then this key) → project hook if allowed → `docker compose up --watch` |
| Same, but project not allowed | `Dup` | user hook only → main command |
| Other project, no user line, not allowed | `Dup` | main command only |

```bash
git remote get-url origin  # preferred
git remote -v              # else first fetch URL
```

## How opt-in works

In `~/.zshrc`:

```bash
source ~/.config/aliprehook/lib.zsh

aliprehook_define Dup docker compose up
aliprehook_define serve pnpm dev

alias ll='ls -la'   # no aliprehook
```

`aliprehook_define Dup docker compose up` creates a **shell function** (not an alias):

```bash
Dup() {
  aliprehook_run Dup || return $?  # user layer then project layer
  docker compose up "$@"
}
```

- Opt-in commands use `aliprehook_define` (or Case B + `aliprehook_run`).
- Plain aliases stay fine when no prehook is needed.

What `aliprehook_run Dup` does each call:

1. Resolve project key (origin → first remote → PWD, normalized)
2. **User layer:** run every `registry` hook for `(*, Dup)`, then for `(key, Dup)`, in file order; first failure stops
3. **Project layer:** if `key` is in `allowed` and `.aliprehook.yml` maps `Dup` → run that hook
4. Return; caller then runs the main command

```mermaid
flowchart TD
  call["User runs cmd with args"]
  opt{"Defined via aliprehook_define or aliprehook_run?"}
  key["Resolve key: origin / first remote / PWD"]
  user{"User registry match?"}
  userHook["Run user hook"]
  allow{"Project key in allowed?"}
  proj{"Project yml maps cmd?"}
  projHook["Run project hook"]
  main["Run underlying command"]
  plain["Normal alias or function"]

  call --> opt
  opt -->|no| plain
  opt -->|yes| key --> user
  user -->|yes| userHook --> allow
  user -->|no| allow
  allow -->|yes| proj
  allow -->|no| main
  proj -->|yes| projHook --> main
  proj -->|no| main
```

## Passing environment to the main command

A hook runs as a child process, so `export` inside a hook never reaches the main command. Instead, the hook hands variables to aliprehook with **`aliprehook_env_pass`**, a command that is always on the hook's `PATH` (nothing to load or source). aliprehook collects them and runs the main command with those variables.

`aliprehook_env_pass` takes **one or more** arguments, each either:

- `NAME`: pass an **exported** variable that already exists in the hook, or
- `NAME=value`: set and pass in one step.

**Example 1: a tool that exports variables (AWS)**

```sh
#!/bin/sh
# hooks/sample_app_web_Dup.sh
# The AWS CLI prints `export AWS_…=…` lines; eval sets and exports them in this hook.
eval "$(aws configure export-credentials --profile dev --format env)" || exit 1

# Pass three variables in one call.
aliprehook_env_pass AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

**Example 2: values from your own commands**

```sh
#!/bin/sh
# hooks/sample_app_web_serve.sh
# Placeholders: replace `my-token-tool` / `my-secrets-cli` with your real commands.
aliprehook_env_pass \
  API_TOKEN="$(my-token-tool --profile dev)" \
  DB_PASSWORD="$(my-secrets-cli get sample_app_web/db)" \
  APP_ENV=development
```

**Example 3: required and optional in one call**

By default every name is **optional**: if it has no value you get a warning, it is skipped, and the command still runs. Put `--required` before names the command cannot work without; `--optional` switches back. Each switch applies to all names after it.

```sh
#!/bin/sh
export REGION=eu-west-1

# REGION and API_TOKEN are required; DEBUG_LEVEL is optional.
aliprehook_env_pass --required REGION API_TOKEN="$(my-token-tool)" --optional DEBUG_LEVEL

# Same meaning, optional names first:
# aliprehook_env_pass DEBUG_LEVEL --required REGION API_TOKEN="$(my-token-tool)"
```

What happens when a value is missing:

| Missing | Output | `docker compose up` runs? |
|---|---|---|
| `DEBUG_LEVEL` (optional) | `aliprehook: warning: sample_app_web_Dup.sh: DEBUG_LEVEL has no value (unset, empty or not exported); not passed to Dup` | Yes, without `DEBUG_LEVEL` |
| `API_TOKEN` (required), e.g. `my-token-tool` failed | `aliprehook: error: sample_app_web_Dup.sh: API_TOKEN has no value (required)`<br>`aliprehook: Dup aborted: required variable missing: API_TOKEN` | **No** |

- All missing names are reported at once, so you can fix them together.
- aliprehook stops the main command itself; the hook does **not** need `|| exit $?`. Add it only if you want the hook to stop right there.

- Variables apply to the **main command** only by default; the terminal is unchanged afterwards
- Values are literal (no expansion); aliprehook never `source`s what hooks write
- User hook wins over project hook for the same variable name; project hooks do not see user-hook variables
- Project hooks cannot set dangerous names (`PATH`, `LD_PRELOAD`, …)

Full design, issues and open decisions: [04_hook-env.md](./04_hook-env.md).

## Per-project commands

> Implemented (roadmap Phase 7). Full design: [06_commands.md](./06_commands.md).

The same command name can run a **different command line per project**. You always type `Dbuild`; the line in `~/.config/aliprehook/commands` decides what runs:

```text
# project_key                     command  what runs (rest of the line, shell syntax)
github.com/org/sample_app_web     Dbuild   DOCKER_BUILDKIT=1 REVISION=$(git rev-parse --short HEAD) docker compose -f docker-compose.dev.yml build
github.com/org/legacy_app         Dbuild   make docker-build
```

- Which command runs: this project's line, else the `aliprehook_define` default. Exactly one runs.
- No `*` in `commands`: the default for all other projects is the `aliprehook_define` command (a `*` line is an error and the command does not run).
- The `commands` file is checked first (errors stop before any hook); then prehooks run as usual and the line can use variables they passed.
- The line is shell syntax (`VAR=… cmd`, `$(…)`, `&&`), run in a subshell so it cannot change your terminal.
- Your arguments are appended, unless the line places `"$@"` itself.
- User layer only: repos cannot define commands; a group- or world-writable `commands` file is refused.

## lib.zsh responsibilities

- `aliprehook_normalize_remote <url>`
- `aliprehook_project_key` — origin → first remote → `pwd -P`, remotes normalized
- `aliprehook_run <cmd_name>` — user hook then (if allowed) project hook
- `aliprehook_define [--keep-env] <name> <command...>` — function wrapper around `aliprehook_run` + command
- `aliprehook_with_env [--keep-env] <command...>` — run a command with the variables hooks wrote to `ALIPREHOOK_ENV_FILE` (Case B functions; `aliprehook_define` wrappers declare them directly so aliases still work)
- `bin/aliprehook_env_pass` (POSIX sh command, on every hook's `PATH`) — `aliprehook_env_pass [--allow-empty] [NAME|NAME=value...] [--required NAME... ] [--optional NAME...]`
- `aliprehook allow` / `aliprehook revoke` — manage `allowed` for current project key
- Planned: `commands` lookup for `aliprehook_define` wrappers and `aliprehook_command <name> <default...>` for Case B functions (see [06_commands.md](./06_commands.md))
- Optional later: `aliprehook explain <cmd>` — print what would run

## Adding hooks

### User layer

1. Write `~/.config/aliprehook/hooks/<name>.sh`, `chmod +x`
2. Add a `registry` line: normalized key, command, hook path
3. Command must use `aliprehook_define` or call `aliprehook_run`

### Project layer

1. Add `.aliprehook.yml` (and scripts under `.aliprehook/` if needed) in the repo
2. From that repo: `aliprehook allow`
3. Same opt-in command names (`Dup`, etc.) as in the yml keys

No user registry line and no allowed project hook → command still runs normally.

## Converting an existing `.zshrc` function

### Case A — Mostly “do stuff, then one command”

Move prep into a **user** (or project) hook; use `aliprehook_define`.

### Case B — Real logic (branches, many steps)

Keep the function; call `aliprehook_run` at the top (runs both layers):

```bash
Dclear() {
  aliprehook_run Dclear || return $?
  # existing logic…
}
```

### Case C — Mix

Same as B: `aliprehook_run` first, then your logic.

| Situation | Use |
|---|---|
| Optional prehook + one underlying command | `aliprehook_define Name cmd…` |
| Function with its own logic | Keep function + `aliprehook_run Name` at top |
| No prehook needed | Normal function/alias |

## Out of scope (for now)

- Changing sample_app_web Docker/Make as part of this work
- Matching by folder basename only
- Preferring `upstream` over `origin` for forks (can add later)
- Signed/shared remote hook packs / marketplace (see as-a-tool doc)

## Implementation checklist

1. Create user layer: `~/.config/aliprehook/{README.md,lib.zsh,registry,allowed,hooks/}`
2. Write `README.md` covering setup, key resolution, both layers, allow, example hook
3. Implement normalize, project key, user registry lookup, project yml lookup, allow/revoke, `aliprehook_run`, `aliprehook_define`
4. Add `hooks/example_echo.sh` + commented user registry line
5. Document example `.aliprehook.yml` in README (optional stub in a personal test repo)
6. Wire `source` + `aliprehook_define Dup docker compose up` into `~/.zshrc`
