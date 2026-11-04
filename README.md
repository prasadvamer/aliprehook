# aliprehook

Optional prehooks for opt-in shell commands, based on which project you are in.

Status: early development (zsh only). Design docs are in [doc/](./doc/).

## 1. What aliprehook is

You keep typing your own short commands (`Dup`, `serve`, …). aliprehook lets a command run a **prehook** first, depending on the project you are in:

```text
You type: Dup --watch
    │
    ├─ 1) User layer: your hooks for Dup (all projects `*`, then this project) → run them
    ├─ 2) Project layer: repo's .aliprehook.yml hook for Dup? → run it, only if you allowed this repo
    └─ 3) docker compose up --watch
```

- **User layer:** your personal hooks in `~/.config/aliprehook/`. Nobody else sees them.
- **Project layer:** hooks a repo ships in `.aliprehook.yml`. **Off until you run `aliprehook allow`.**
- If a hook fails (non-zero exit), the command stops there.
- Commands you do not opt in stay normal aliases/functions.

## 2. Setup

From a clone of this repo:

```sh
./install.sh
```

This creates `~/.config/aliprehook/`:

```text
~/.config/aliprehook/
  README.md          # this file
  lib.zsh            # sourced from ~/.zshrc
  registry           # your hooks: project_key + command → hook
  allowed            # repos whose project hooks may run
  hooks/
    example_echo.sh  # safe example hook
  bin/
    aliprehook_env_pass  # used by hooks to pass variables (see 8.)
  themes/
    purple.theme     # default colors (see 9.)
    none.theme       # no colors
```

### Try it in your current shell first

Nothing is changed permanently yet. Load aliprehook into this shell only:

```zsh
source ~/.config/aliprehook/lib.zsh
```

Make your first opt-in command. `aliprehook_define` takes two things:

```text
aliprehook_define  hello      echo hello from aliprehook
                   └─ name    └─ command it runs
                   (what you   (anything you would
                    type)       normally type)

aliprehook_define  Dup        docker compose up
                   └─ name    └─ command it runs
                   (you type   (what actually runs:
                    Dup)        docker compose up)
```

```zsh
aliprehook_define hello echo hello from aliprehook
hello
# hello from aliprehook

hello and more
# hello from aliprehook and more    (extra arguments are passed on)
```

`hello` is now a shell function. See what it does:

```zsh
functions hello
# hello () {
#   local _aliprehook_line
#   _aliprehook_line=$(_aliprehook_command_lookup hello)   ← this project's line in `commands`, if any (none yet)
#   (( $? < 2 )) || return 1
#   aliprehook_run hello "$@" || return $?   ← runs hooks for "hello" first (none yet)
#   _aliprehook_env_decl                     ← picks up variables the hooks passed (none yet)
#   eval "$_aliprehook_env_code"
#   if [[ -n $_aliprehook_line ]]; then
#     _aliprehook_command_eval "$_aliprehook_line" "$@"   ← per-project command (see 10.)
#   else
#     echo hello from aliprehook "$@"       ← else your command, with your arguments
#   fi
# }
```

No hooks are registered yet, so `hello` behaves exactly like the command. Hooks are added in [6. Add a user hook](#6-add-a-user-hook) and [7. Try the example](#7-try-the-example).

A real one, for Docker:

```zsh
aliprehook_define Dup docker compose up
Dup --watch    # same as: docker compose up --watch (plus hooks for this project, once you add some)
```

If `Dup` was already an alias, `aliprehook_define` replaces it.

Add `--keep-env` before the name to keep variables your hooks pass in the terminal afterwards (see [8. Pass variables to the command](#8-pass-variables-to-the-command)):

```zsh
aliprehook_define --keep-env Dup docker compose up
```

### Make it permanent

When you are happy with it, add the same lines to `~/.zshrc`:

```zsh
source ~/.config/aliprehook/lib.zsh

aliprehook_define Dup docker compose up
aliprehook_define serve pnpm dev
```

Open a new shell (or `source ~/.zshrc`). `Dup` and `serve` are now available in every shell.

## 3. Project key

Hooks are matched by a **project key** for the current directory, picked in this order:

1. `origin` remote URL
2. Else the first remote URL (`git remote -v`, fetch)
3. Else the directory path (`pwd -P`)

Remote URLs are normalized, so every clone of a repo gets the same key:

| Remote | Key |
|---|---|
| `git@github.com:org/sample_app_web.git` | `github.com/org/sample_app_web` |
| `https://github.com/org/sample_app_web.git` | `github.com/org/sample_app_web` |
| `ssh://git@github.com/org/sample_app_web.git` | `github.com/org/sample_app_web` |

See the key for where you are:

```zsh
aliprehook key
```

## 4. User registry

`~/.config/aliprehook/registry` is a plain text file, one hook per line:

```text
# project_key                     command  hook
*                                 Dup      hooks/common_Dup.sh
github.com/org/sample_app_web     Dup      hooks/sample_app_web_Dup.sh
github.com/org/sample_app_web     Dup      hooks/sample_app_web_db.sh
github.com/org/sample_app_web     serve    hooks/sample_app_web_serve.sh
/home/me/scratch/playground       Dup      hooks/scratch_Dup.sh
```

- Columns are separated by spaces or tabs. No spaces inside a column.
- Hook paths are relative to `~/.config/aliprehook/` (or absolute).
- Lines starting with `#` and blank lines are ignored.
- **Every** matching line runs, not just the first.
- User hooks apply to every clone with the same key.

### Common hooks: `*`

A `*` key matches **every** project, for that command only. Use it for steps every project needs (VPN check, registry login, …):

```text
*  Dup  hooks/common_vpn_check.sh
*  Dup  hooks/common_docker_login.sh
```

- Run order: all `*` lines first, then the lines for the current project; file order within each group. With the example above, `Dup` in `sample_app_web` runs `common_Dup.sh`, `sample_app_web_Dup.sh`, `sample_app_web_db.sh`, then the project hook (if allowed), then `docker compose up`.
- The first failing hook stops everything after it, including the main command.
- The same line listed twice runs once.
- `*` is the only wildcard (no `github.com/org/*`), and it works only here in your registry, never in a repo's `.aliprehook.yml`.

## 5. Project layer and `aliprehook allow`

A repo can ship hooks in `.aliprehook.yml` at its root:

```yaml
# Only used after: aliprehook allow
hooks:
  Dup: .aliprehook/before_Dup.sh
  serve: .aliprehook/before_serve.sh
```

```text
<repo>/
  .aliprehook.yml
  .aliprehook/
    before_Dup.sh
```

Nothing in it runs until you allow the repo:

```zsh
cd ~/code/sample_app_web
aliprehook allow    # project hooks now run (after your user hook)
aliprehook revoke   # stop running them
```

- Each key under `hooks:` is a command name. `*` (all-projects) hooks are **not allowed** in a repo: `aliprehook allow` refuses such a file, and if one appears later the entry is ignored with a warning.
- Hook paths must be relative and stay inside the repo (no `../`, no absolute paths, no symlinks pointing out).
- Hook scripts must be executable (`chmod +x`, committed to git with the executable bit).
- Project hooks run in your current directory, with `ALIPREHOOK_PROJECT_ROOT` set to the repo root.

> **Warning:** allowing a repo means running that repo's scripts on your machine. Read `.aliprehook.yml` and the scripts it points to before `aliprehook allow`.
>
> Current limits (planned to change): an allow applies to every clone with the same project key, and later changes to the yml or scripts (e.g. after `git pull`) run without asking again. Run `aliprehook revoke` if you stop trusting a repo.

A ready-made example is in [examples/project/](./examples/project/).

## 6. Add a user hook

1. Write the hook:
   ```sh
   cp ~/.config/aliprehook/hooks/example_echo.sh ~/.config/aliprehook/hooks/my_app_Dup.sh
   $EDITOR ~/.config/aliprehook/hooks/my_app_Dup.sh
   chmod +x ~/.config/aliprehook/hooks/my_app_Dup.sh
   ```
2. Register it, from inside the project:
   ```zsh
   echo "$(aliprehook key)  Dup  hooks/my_app_Dup.sh" >> ~/.config/aliprehook/registry
   ```
3. Make sure the command is defined with `aliprehook_define` (or calls `aliprehook_run`, see below).

A hook gets:

| | |
|---|---|
| Arguments | The command's arguments (`Dup --watch` → `--watch`) |
| `ALIPREHOOK_PROJECT_KEY` | Project key |
| `ALIPREHOOK_COMMAND` | Command name (`Dup`) |
| `ALIPREHOOK_PROJECT_ROOT` | Repo root (project hooks only) |
| `ALIPREHOOK_HOOK` | Path of the running hook |
| `ALIPREHOOK_ENV_FILE` | File for passing variables to the command (use `aliprehook_env_pass`) |
| `ALIPREHOOK_ENV_PASS_BIN` | Full path of `aliprehook_env_pass` |
| `aliprehook_env_pass` on `PATH` | See [8. Pass variables to the command](#8-pass-variables-to-the-command) |
| Working directory | Where you ran the command |

Exit non-zero to stop the command. Print to stderr (`>&2`) to keep the command's stdout clean.

`export` in a hook does **not** reach the command (a hook is a separate program); use `aliprehook_env_pass`.

## 7. Try the example

```zsh
cd ~/any/project
echo "$(aliprehook key)  Dup  hooks/example_echo.sh" >> ~/.config/aliprehook/registry
Dup --version
```

Output:

```text
aliprehook: example_echo.sh ran
  project key: github.com/org/any_project
  command:     Dup --version
Docker Compose version …
```

Remove that line from `registry` when done.

## 8. Pass variables to the command

A hook is a separate program, so `export FOO=…` inside it is gone when it exits. To hand variables to the main command, call **`aliprehook_env_pass`** from the hook. It is always on the hook's `PATH`; nothing to load.

It takes one or more arguments:

- `NAME`: pass an **exported** variable from the hook
- `NAME=value`: set and pass in one step

```sh
#!/bin/sh
# hooks/sample_app_web_Dup.sh
# The AWS CLI prints `export AWS_…=…` lines; eval sets and exports them here.
eval "$(aws configure export-credentials --profile dev --format env)" || exit 1
aliprehook_env_pass AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

```sh
#!/bin/sh
# Placeholders: replace `my-token-tool` with your real command.
aliprehook_env_pass API_TOKEN="$(my-token-tool --profile dev)" APP_ENV=development
```

**Required and optional.** Names are optional by default: a missing value (unset, empty or not exported) prints a warning and the command still runs. `--required` and `--optional` switch the mode for all names after them:

```sh
aliprehook_env_pass DEBUG_LEVEL --required API_TOKEN REGION
```

```text
aliprehook: warning: sample_app_web_Dup.sh: DEBUG_LEVEL has no value (unset, empty or not exported); not passed to Dup
aliprehook: error: sample_app_web_Dup.sh: API_TOKEN has no value (required)
aliprehook: Dup aborted: required variable missing: API_TOKEN
```

A missing required value stops the main command even if the hook exits 0; no `|| exit $?` needed. `--allow-empty` (anywhere in the call) passes empty values instead of treating them as missing.

**Where the variables go:**

- To the **main command only**. Your terminal is unchanged afterwards, unless the command was defined with `aliprehook_define --keep-env` (then your user hooks' variables stay set; project hooks' never do).
- Several user hooks: a later one sees variables from earlier ones, and the later value wins.
- User hooks win over the repo's project hook for the same name. Project hooks never see your hooks' variables.
- Project hooks may not pass `PATH`, `LD_*`, `DYLD_*`, `BASH_ENV`, `ENV`, `ZDOTDIR`, `IFS`, `PS4`, `PROMPT_COMMAND`, `HOME`, `SHELL`, `GIT_SSH_COMMAND` or `GIT_EXEC_PATH`. Names starting with `ALIPREHOOK_` are reserved.
- Limits: 100 variables, 64 KiB per hook. Messages show names, never values.

**Docker Compose:** variables reaching `docker compose` are not automatically inside the container. Compose uses them for `${VAR}` in `compose.yaml`; to pass one into a container, list it:

```yaml
services:
  app:
    environment:
      - API_TOKEN      # value from the environment aliprehook set
```

Hooks in other languages can call `"$ALIPREHOOK_ENV_PASS_BIN" NAME=value`, or write `NAME=value` lines to `$ALIPREHOOK_ENV_FILE` themselves. Design details: [doc/04_hook-env.md](./doc/04_hook-env.md).

## 9. Colors and themes

aliprehook messages are colored with a purple theme. Each color has one meaning:

| Color | Meaning | Example |
|---|---|---|
| Bold orchid | From aliprehook | `aliprehook:` |
| Default text | Information, nothing wrong | `project hooks from … will now run` |
| Bold green | It worked | `allowed`, `revoked` |
| Yellow | Look, but the command continues (label and text) | `warning: … has no value` |
| Red | Stopped, the command did not run (label and text) | `error: …`, `aborted` |
| Bold green | The command you typed | `Dup` |
| Cyan | A hook script | `sample_app_web_Dup.sh` |
| Blue | Where: project key or path | `github.com/org/sample_app_web` |
| Bold | A variable name | `API_TOKEN` |
| Grey | How to fix it | `(run: chmod +x …)` |

`warning:` and `error:` are always written out, so the meaning never depends on color.

**Turn color off or on:**

| Setting | Effect |
|---|---|
| (nothing) | Color only when output goes to a terminal |
| `NO_COLOR=1` | No color ([no-color.org](https://no-color.org)) |
| `ALIPREHOOK_COLOR=never` | No color |
| `ALIPREHOOK_COLOR=always` | Always color, even in pipes (e.g. for screenshots) |
| `ALIPREHOOK_THEME=none` | Theme with no colors |

**Change colors.** Override single roles in `~/.config/aliprehook/theme` (open a new shell after editing):

```text
# ~/.config/aliprehook/theme
hook=35      # magenta hook names
key=1;34     # bold blue paths
```

Roles: `brand`, `info`, `success`, `warning`, `error`, `command`, `hook`, `key`, `var`, `hint`. Values are ANSI codes (the part between `ESC[` and `m`, e.g. `31` red, `1;32` bold green, `38;5;177` 256-color); empty means default color.

For a complete theme of your own, copy `themes/purple.theme`, edit it, and set `ALIPREHOOK_THEME=/path/to/my.theme`. Theme files are read as plain `role=code` lines, never executed. Design: [doc/05_theme.md](./doc/05_theme.md).

## 10. Per-project commands

The same name can run a **different command line per project**. Keep the default in `.zshrc`:

```zsh
aliprehook_define Dbuild docker compose build
```

and list the exceptions in `~/.config/aliprehook/commands` (created by `install.sh`):

```text
# project_key                     command  what runs (rest of the line, shell syntax)
github.com/org/sample_app_web     Dbuild   DOCKER_BUILDKIT=1 REVISION=$(git rev-parse --short HEAD) docker compose -f docker-compose.dev.yml build
github.com/org/legacy_app         Dbuild   make docker-build
github.com/org/sample_app_api     Test     pytest "$@" -m "not slow"
```

| Where you type `Dbuild --no-cache` | Runs |
|---|---|
| `sample_app_web` | `DOCKER_BUILDKIT=1 REVISION=<hash> docker compose -f docker-compose.dev.yml build --no-cache` |
| `legacy_app` | `make docker-build --no-cache` |
| Any other project | `docker compose build --no-cache` (the default) |

- One command runs: this project's line, else the `aliprehook_define` default. Adding or removing a line needs no `.zshrc` change.
- Prehooks still run first, and the line can use the variables they passed (`$REVISION`).
- The line is shell syntax, run in a subshell: `cd` or assignments in it never change your terminal. The exit code is the line's.
- Your arguments are appended, unless the line uses `"$@"` itself (`pytest "$@" -m "not slow"`).
- No `*` key: to change the command everywhere, change the `aliprehook_define` line. A `*` line is an error and the command does not run.
- Several lines for the same project and command: the first wins, with a warning.
- User layer only: a repo's `.aliprehook.yml` cannot define commands (a `commands:` section is ignored with a warning).
- The file must not be writable by group or others (`chmod go-w ~/.config/aliprehook/commands`), or the command refuses to run.
- Works for hook-only commands too: `aliprehook_define Rpep :` can run a real command in some projects.

In your own functions (Case B), use `aliprehook_command` after `aliprehook_run`; your arguments go after `--`:

```zsh
Dbuild() {
  aliprehook_run Dbuild "$@" || return $?
  aliprehook_command Dbuild docker compose build -- "$@"
}
```

Design: [doc/06_commands.md](./doc/06_commands.md).

## Converting existing `.zshrc` functions

**Case A — "do some prep, then one command":** move the prep into a hook, replace the function with `aliprehook_define`.

```zsh
# before
Dup() { cp -n .env.example .env; docker compose up "$@"; }

# after: prep goes in hooks/<project>_Dup.sh + a registry line (or the repo's .aliprehook.yml)
aliprehook_define Dup docker compose up
```

**Case B — real logic (branches, many steps):** keep the function, call `aliprehook_run` at the top.

```zsh
Dclear() {
  aliprehook_run Dclear "$@" || return $?
  # existing logic…
}
```

To give a command in your function the variables the hooks passed, run it through `aliprehook_with_env` (once per `aliprehook_run`):

```zsh
Dclear() {
  aliprehook_run Dclear "$@" || return $?
  aliprehook_with_env ./scripts/clear.sh "$@"
}
```

**Case C — mix:** same as B, `aliprehook_run` first, then your logic.

| Situation | Use |
|---|---|
| Optional prehook + one command | `aliprehook_define Name cmd…` |
| Function with its own logic | Keep function + `aliprehook_run Name "$@"` at top |
| No prehook needed | Normal function/alias |

## Commands

| Command | Does |
|---|---|
| `aliprehook_define [--keep-env] <name> <command...>` | Define an opt-in command |
| `aliprehook_run <name> [args...]` | Run hooks for `<name>` (used inside functions) |
| `aliprehook_with_env [--keep-env] <command...>` | Run a command with the variables the last `aliprehook_run` collected |
| `aliprehook_command [--keep-env] <name> <default...> -- [args...]` | Like `aliprehook_with_env`, but runs this project's line from `commands` if there is one |
| `aliprehook_env_pass [--allow-empty] [NAME\|NAME=value...] [--required …] [--optional …]` | In a hook: pass variables to the main command |
| `aliprehook allow` | Allow this repo's `.aliprehook.yml` hooks |
| `aliprehook revoke` | Stop allowing them |
| `aliprehook key` | Print the project key for the current directory |
| `aliprehook help` | Usage |

## Uninstall

```sh
./uninstall.sh   # removes lib.zsh, README.md, bin/, themes/; keeps registry, allowed, commands, hooks/, theme
```

Then remove the `source` and `aliprehook_define` lines from `~/.zshrc`. For full removal: `rm -rf ~/.config/aliprehook`.

## Development

```sh
./install.sh --copy   # copy instead of symlink (default links back to this repo)
zsh tests/run.zsh     # run the tests
```

Set `ALIPREHOOK_HOME` to use a directory other than `~/.config/aliprehook/`.
