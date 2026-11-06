# Managing hooks and commands from the CLI

Design for `aliprehook hook …` and `aliprehook command …`, so you never hand-write `hooks.map` or `commands.map` lines (or look up the project key) yourself. Work items: [03_roadmap.md](./03_roadmap.md) Phase 8, Improvements from dogfooding.

> Status: implemented (Phase 8, Improvements from dogfooding).

## Problem

Adding a hook today means remembering a long command:

```zsh
print -r -- "$(aliprehook key)  Dup  hooks/sample_app_web_Dup.sh" >> ~/.config/aliprehook/hooks.map
```

plus creating the hook file and running `chmod +x`. A per-project command needs the same with `commands.map`, and you must get the quoting right. Removing or listing lines means opening the files and finding the key.

## Commands

All of them work on the **current project key** (as `aliprehook key` prints it), unless another project is chosen ([Choosing the project](#choosing-the-project)).

Argument style: **required** values are positional (`hook add Dup aws.sh`), **optional** ones are `--` options (`hook new Dup --hook aws.sh`), so an optional value is never confused with the next positional one.

### Hooks (`hooks.map`)

| Command | Does |
|---|---|
| `aliprehook hook new <cmd> [--hook <file>] [--edit] [project]` | Create a hook from a template, make it executable, add `hooks.map` line, print its path (`--edit` opens it in `$EDITOR`). `--hook` sets the file name; default below |
| `aliprehook hook add <cmd> <hook> [project]` | Add a `hooks.map` line for an existing hook |
| `aliprehook hook rm <cmd> [--hook <file>] [project]` | Remove the line(s) for the project and `<cmd>`; with `--hook` only that one. The hook file is kept |
| `aliprehook hook ls [<cmd>] [project]` | List the hooks that run for the project, in run order (`*` first), marking `*` lines |

`[project]` is one of `--all`, `--key <key>`, `--path <dir>` (see below).

```zsh
cd ~/src/sample_app_web
aliprehook hook new Dup
# aliprehook: created ~/.config/aliprehook/hooks/sample_app_web_Dup.sh
# aliprehook: added github.com/org/sample_app_web  Dup  hooks/sample_app_web_Dup.sh

aliprehook hook new Dbuild --all
# aliprehook: created ~/.config/aliprehook/hooks/all_Dbuild.sh
# aliprehook: added *  Dbuild  hooks/all_Dbuild.sh

aliprehook hook new Dup --hook aws_login.sh
# aliprehook: created ~/.config/aliprehook/hooks/aws_login.sh
# aliprehook: added github.com/org/sample_app_web  Dup  hooks/aws_login.sh
```

- **New hook name:** `--hook <file>`, using the same path rules as below (`aws_login.sh` → `hooks/aws_login.sh`; no extension is added). Without it: `hooks/<repo>_<cmd>.sh`, where `<repo>` is the last part of the key (`sample_app_web`), or `all_<cmd>.sh` with `--all`. If the file already exists, it is reused (not overwritten) and only the line is added, so one hook can be shared by several commands or projects.
- **Template:** a `#!/bin/sh` hook with comments showing `$ALIPREHOOK_PROJECT_KEY`, `$ALIPREHOOK_COMMAND`, `"$@"` and an `aliprehook_env_pass` example; it exits 0 and prints nothing until edited.
- **`<hook>` paths:** a bare name (`aws.sh`) means `hooks/aws.sh`; a path relative to `~/.config/aliprehook/` or absolute is stored as given. The file must exist and be executable (else error with a `chmod +x` hint).
- **Same line twice:** `add` reports "already registered" and changes nothing.
- **Order:** new lines go at the end, so they run after the existing hooks for that command. To reorder, edit the file (`aliprehook edit hooks`).

### Per-project commands (`commands.map`)

| Command | Does |
|---|---|
| `aliprehook command set <cmd> '<command line>' [--key <key> \| --path <dir>]` | Set the project's command line for `<cmd>` (replaces an existing one) |
| `aliprehook command rm <cmd> [--key <key> \| --path <dir>]` | Remove it; the `aliprehook_define` default runs again |
| `aliprehook command ls [--key <key> \| --path <dir>]` | List the project's command lines |

```zsh
aliprehook command set Dbuild 'DOCKER_BUILDKIT=1 REVISION=$(git rev-parse --short HEAD) docker compose -f docker-compose.dev.yml build'
# aliprehook: Dbuild in github.com/org/sample_app_web now runs: DOCKER_BUILDKIT=1 …
```

- **One argument:** the command line is a single quoted string, stored exactly as given. More than one argument is an error ("quote the command line"), since joining words would lose your quoting. Single quotes keep `$(…)` and `$VAR` for run time.
- **Replace, not add:** only one line per project and command exists (a command is replaced, not added up), so `set` overwrites and says what it replaced.
- **No `--all`:** the default for all projects is the `aliprehook_define` command; `set` with `--all` or a `*` key is an error saying so.
- Only for names you defined: `set` warns if `<cmd>` is not a defined function.

### Other

| Command | Does |
|---|---|
| `aliprehook edit [hooks\|commands\|allowed\|theme\|settings]` | Open the file in `$EDITOR` (default `hooks.map`) |
| `aliprehook key [--path <dir>]` | Print the project key for the current directory, or for `<dir>` |

## Choosing the project

| Option | Key used | Example |
|---|---|---|
| (none) | The current directory's key | `cd ~/src/sample_app_web && aliprehook hook new Dup` |
| `--path <dir>` | The key `<dir>` would have (its git remote, else its path), as if you ran it there | `aliprehook hook new Dup --path ~/src/sample_app_web` |
| `--key <key>` | Exactly this key, no lookup | `aliprehook hook add Dup aws.sh --key github.com/org/sample_app_web` |
| `--all` | `*`, every project (hooks only) | `aliprehook hook new Dbuild --all` |

- At most one of them; two together is an error.
- `--path`: the directory must exist. Useful for a repo you are not in, or a non-git directory (key = its `pwd -P` path).
- `--key`: for a project not cloned on this machine yet, or a key copied from `aliprehook key` elsewhere. It must not be empty, contain whitespace or be `*` (use `--all`). A key that does not look like a normalized remote or an absolute path gets a warning (probably a typo), but is accepted.
- Every message shows the key that was used, so a wrong project is visible right away.

## Help

No need to open the README for the syntax:

| Command | Shows |
|---|---|
| `aliprehook help` (or `-h`, `--help`, no arguments) | All subcommands, one line each |
| `aliprehook hook help`, `aliprehook command help` | The subcommands of that group with their options |
| `aliprehook hook new --help` (any subcommand) | Usage, options and one example for that subcommand |

Every help text explains the options it accepts, including the project options (`--path`, `--key`, and `--all` only where allowed; `command` help says why there is no `--all`). Example:

```text
$ aliprehook hook new --help
usage: aliprehook hook new <cmd> [--hook <file>] [--edit] [--all | --key <key> | --path <dir>]

Create a hook for <cmd> from a template, make it executable and register it.
Runs before <cmd> in the chosen project, after hooks already registered.

  --hook <file>   hook file name (default: hooks/<repo>_<cmd>.sh, or all_<cmd>.sh with --all);
                  a bare name goes in hooks/; an existing file is reused, not overwritten
  --edit          open the hook in $EDITOR afterwards
  --all           every project (*)
  --key <key>     this project key, no lookup
  --path <dir>    the project key of <dir>
                  (default: the current directory's key; at most one of --all/--key/--path)

example: aliprehook hook new Dup --hook aws_login.sh --path ~/src/sample_app_web
```

A wrong call (missing argument, unknown option) prints an `error:` plus that subcommand's usage line and `(see: aliprehook hook help)`, exits 2, and changes nothing.

## Rules

- **Never lose your edits:** comments, blank lines and other lines are kept untouched; only the affected line is added, replaced or removed.
- **Safe writes:** write a temp file next to the original, then `mv` (no half-written file on Ctrl-C or a full disk); the file's permissions are kept (`commands.map` stays not group/world-writable).
- **User layer only:** these commands never write to a repo's `.aliprehook.yml`.
- **Messages** through the theme (`@command=`, `@key=`, `@hook=`); every change prints what it did, so `rm` never silently removes the wrong line.
- **Outside a git repo** the key is the directory (`pwd -P`), same as everywhere else; the message shows it.
- Tab completion for subcommands and command names: later, with the zsh completion in Distribution.
