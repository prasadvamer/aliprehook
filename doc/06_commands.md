# Per-project commands (`commands` file)

Design for running a **different command per project** behind the same name. You always type `Dbuild`; what runs depends on the project key. Summary in [01_shell-aliprehook-system.md](./01_shell-aliprehook-system.md) § Per-project commands; work items in [03_roadmap.md](./03_roadmap.md) Phase 7.

> Status: implemented (Phase 7).

## Problem

Prehooks change what happens *before* a command, and `aliprehook_env_pass` changes its *environment*, but the command itself is fixed by `aliprehook_define`. Some projects need a different command line altogether:

```text
most projects:     docker compose build
sample_app_web:    DOCKER_BUILDKIT=1 REVISION=$(git rev-parse --short HEAD) docker compose -f docker-compose.dev.yml build
legacy_app:        make docker-build
```

Inserting arguments at a position (`@ARGS`) depends too much on each tool's argument order, so it was rejected. Instead, a project can **replace the whole command line**.

## The `commands` file

`~/.config/aliprehook/commands`, next to `registry`:

```text
# project_key                     command  what runs (rest of the line, shell syntax)
github.com/org/sample_app_web     Dbuild   DOCKER_BUILDKIT=1 REVISION=$(git rev-parse --short HEAD) docker compose -f docker-compose.dev.yml build
github.com/org/legacy_app         Dbuild   make docker-build
/home/me/scratch/playground       Dbuild   ./build.sh "$@" --local
```

```zsh
aliprehook_define Dbuild docker compose build     # default when no line matches
```

Format:

- Column 1: a project key. No `*`: the default for all other projects is the `aliprehook_define` command (see [No `*` here](#no--here)).
- Column 2: command name (as given to `aliprehook_define`).
- Rest of the line (leading whitespace trimmed): the command to run, in **shell syntax**.
- Lines starting with `#` and blank lines are ignored.
- One line per entry. Long commands: put them in a script and point to it (`… Dbuild ~/.config/aliprehook/cmds/web_build.sh`).

## Which command runs

For `Dbuild` in project `K`, the first of these that exists:

| Priority | Source | Meaning |
|---|---|---|
| 1 | `K  Dbuild  …` line | This project's own command |
| 2 | `aliprehook_define Dbuild …` | Default, for every other project |

- Exactly one command runs (unlike hooks, where every match runs).
- Several lines for the same key and command: the first one wins; later ones print a warning naming the file and line.

### No `*` here

Unlike `registry`, `commands` has no `*` key. Hooks add up (every match runs), so a `*` hook means something extra. A command is replaced (only one runs), so a `*` command would just be a second place for the default, which `aliprehook_define` already is. One default, in one place.

A `*` line in `commands` is an error: aliprehook prints the file and line, says to change the `aliprehook_define` command instead, and that command does not run until the line is removed. A `*` line for another command does not affect it.

| Where you type `Dbuild --no-cache` | Runs |
|---|---|
| `sample_app_web` | `DOCKER_BUILDKIT=1 REVISION=<hash> docker compose -f docker-compose.dev.yml build --no-cache` |
| `legacy_app` | `make docker-build --no-cache` |
| Any other project | `docker compose build --no-cache` (the `aliprehook_define` default) |

## How it runs

1. aliprehook looks up the command (table above). The `commands` file is checked first, so a broken or refused file stops before any hook runs.
2. Prehooks run, exactly as before (`*` hooks, project hooks, project layer). A failing hook stops everything; the command does not run.
3. The command line runs in a **subshell** with `eval`:
   - Shell syntax works: `VAR=… cmd`, `$(…)`, `&&`, `|`, quotes.
   - Variables passed by hooks (`aliprehook_env_pass`) are set, so the line can use them (`$TOKEN`).
   - Being a subshell, `cd`, `export` or assignments in the line never change your terminal.
4. Your arguments:
   - By default they are appended at the end (as `"$@"`, each argument kept intact).
   - If the line contains `"$@"` (or `$@` / `$*`) itself, your arguments go there instead and are not appended again: `./build.sh "$@" --local`.
5. `Dbuild` exits with the command's exit code.
6. `--keep-env` still works: user-hook variables are kept in the terminal as before; the command line itself never changes the terminal.

## Rules and safety

- **User layer only.** A command line is shell code, more powerful than a hook, so only the user's `commands` file can define one. A repo's `.aliprehook.yml` cannot (a `commands:` section there is ignored with a warning).
- **File permissions:** if `commands` is writable by group or others, aliprehook refuses it with an error and the command does not run, so another user cannot change what your commands run. `install.sh` creates it with `chmod go-w`.
- **Only for `aliprehook_define` commands.** A line for a name that is not defined does nothing (`aliprehook doctor` reports it). Hand-written Case B functions can opt in with a helper, after `aliprehook_run`: `aliprehook_command Dbuild docker compose build -- "$@"` (runs the `commands` line if there is one, else the given default; your arguments come after the first `--`, so the default itself cannot contain `--`). Like `aliprehook_with_env`, it sets the variables the hooks passed and accepts `--keep-env`.
- **Hook-only commands** (`aliprehook_define X :`) can get a real command in some projects.
- **Visibility:** `aliprehook explain Dbuild` (Phase 8) prints which command will run here and which line chose it.
- Errors (`*` line, empty command part, unreadable or refused file) name the file and line; the command does not run. Problems in lines for other commands are not reported.

## Examples

Different default plus one exception: change the default in `aliprehook_define`, keep the exception in `commands`:

```zsh
aliprehook_define Dup docker compose up --remove-orphans
```
```text
github.com/org/legacy_app      Dup   docker-compose -f old/docker-compose.yml up
```

Using a variable passed by a hook:

```sh
# hooks/sample_app_web_Dbuild.sh
aliprehook_env_pass REVISION="$(git rev-parse --short HEAD)"
```
```text
github.com/org/sample_app_web  Dbuild  docker compose build --build-arg REVISION=$REVISION
```

Arguments in the middle:

```text
github.com/org/sample_app_api  Test  pytest "$@" -m "not slow"
```

`Test tests/unit` → `pytest tests/unit -m "not slow"`.

## Out of scope

- Commands defined by repos (`.aliprehook.yml`)
- Multi-line entries (use a script)
- Wildcards of any kind (`*`, `github.com/org/*`): the default belongs in `aliprehook_define`
