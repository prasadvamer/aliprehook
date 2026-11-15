# `aliprehook explain`: why did / didn't my hook run?

Design for a dry run that prints, for one command in one project, what aliprehook would do and why, without running anything. Work items: [03_roadmap.md](./03_roadmap.md) Phase 8.

> Status: implemented (Phase 8).

## Problem

The run summary ([08_run-summary.md](./08_run-summary.md)) shows what **did** run. When a hook does **not** run, it shows nothing, and the usual causes are invisible:

- the project key is not the one the hook is registered on (fork, other remote, folder without git);
- the command is not an aliprehook command in this shell (no `aliprehook_define`, a plain alias);
- the hook line is under another key or another command name;
- the repo is not allowed, or `.aliprehook.yml` has no entry for this command;
- the hook file is missing or not executable (the run would fail).

## Usage

```text
aliprehook explain [<cmd>] [--path <dir> | --key <key>]
```

- `<cmd>`: the command to explain. Without it, list the commands that have anything for this key (see [All commands](#all-commands)).
- `--path <dir>`: explain for the project at `<dir>` (key and project layer from there).
- `--key <key>`: explain for a key; the project layer is not checked (no repo to look at), and the output says so. `hooks.map` hooks of that key are still checked (missing, not executable).
- At most one of `--path` / `--key`; `--all` is rejected (a run always has a key). Wrong calls: `error:`, usage line, `(see: aliprehook explain --help)`, exit 2.
- Nothing runs: no hook, no command, no file is written. Only the reads a real run does (key, `hooks.map`, `commands.map`, `allowed-repos`, `.aliprehook.yml`), plus `whence` for the definition.

## Output

```text
$ aliprehook explain Dbuild
Dbuild in github.com/org/sample_app_web (git remote origin)
defined: aliprehook_define Dbuild docker compose build

hooks, in run order:
  1. all_Dbuild.sh          hooks.map:2 (*)
  2. aws_login.sh           hooks.map:5
  -  .aliprehook/build.sh   project: skipped (repo not allowed; run: aliprehook allow)

command: commands.map:3
  DOCKER_BUILDKIT=1 docker compose build --no-cache

not matching here:
  hooks.map:9     github.com/org/other_app  Dbuild  hooks/other_build.sh

variables passed by hooks are known only when they run (run: ALIPREHOOK_VERBOSE=detail Dbuild)
```

### 1. Key and its source

`<cmd> in <key> (<source>)`, source one of `git remote origin`, `git remote <name>` (first remote), `git repo without remote; directory path`, `no git repo; directory path`, `--key; project layer not checked`. With `--path`, the directory is added (`; --path <dir>`).

### 2. Definition

How `<cmd>` resolves in **this** shell:

| Case | Line |
|---|---|
| `aliprehook_define` wrapper | `defined: aliprehook_define [--keep-env] <cmd> <default…>` |
| Function calling `aliprehook_run` (Case B) | `defined: function <cmd> (calls aliprehook_run)` |
| Anything else (alias, other function, program, builtin) | `warning: <cmd> is not an aliprehook command here (<what it is>); nothing below runs` + `@hint=(run: aliprehook_define <cmd> …)` |
| Not found | same warning, `not found` |

`aliprehook_define` records each name with its options and default words, so `explain` prints them as written; it never parses function bodies, except to look for the words `aliprehook_run` and `aliprehook_command` in Case B.

### 3. Hooks, in run order

Exactly the order a run uses (`*` lines first, then the key's lines, file order; then the project hook):

- Each hook: number, file name, source (`hooks.map:<line>`, `(*)` for `*` lines; `project (.aliprehook.yml)`).
- Project hook not used: a `-` line with the same reason as `detail` (`none (not a git repo)`, `none (no .aliprehook.yml)`, `skipped (repo not allowed; run: aliprehook allow)`, `none for <cmd> in .aliprehook.yml`).
- No hooks at all: `hooks: none in hooks.map for <cmd> here`.

### 4. Problems

Anything that would make the run fail or warn, next to the item it concerns.

As `warning:` lines (checked by `explain`):

- hook file missing or not executable;
- a Case B function with a `commands.map` line but no `aliprehook_command` call (the line is never used);
- old user file names still present (`registry`, …), every time (a run warns once per shell);
- invalid verbose level in `ALIPREHOOK_VERBOSE` / `settings`;
- invalid entries in an allowed repo's `.aliprehook.yml`.

As the run's own `error:` lines, because `explain` calls the same checks a run does (the row then says `error (see above); the run stops before any hook`):

- project hook outside the repo, or an absolute path in `.aliprehook.yml`;
- `commands.map` group/world-writable, or with a `*` / empty line.

### 5. Command

- `command: commands.map:<line>` and the line on the next line, as written (variables not expanded, values never printed).
- No line: `command: (default) <default…>` for a wrapper; `command: (set by the function)` for Case B, plus the `commands.map` line if one exists (`aliprehook_command` would use it).

### 6. Not matching here

Lines in `hooks.map` and `commands.map` for the same `<cmd>` under **other** keys, with file and line number. This is the answer to "I registered it, why doesn't it run?": wrong key, fork, changed remote. Omitted when there are none.

### 7. Variables

One closing line: passed variables are only known when the hooks run; point to `ALIPREHOOK_VERBOSE=detail <cmd>`.

## All commands

`aliprehook explain` without `<cmd>` lists every command name that has a `hooks.map` line (`*` or this key), a `commands.map` line for this key, or an entry in this repo's `.aliprehook.yml`, one per line with counts:

```text
$ aliprehook explain
github.com/org/sample_app_web (git remote origin)
  Dbuild   2 hooks (1 *), project hook (skipped: repo not allowed), command: commands.map:3
  Dup      1 hook
(see: aliprehook explain <cmd>)
```

Names with something registered but not defined in this shell get `(not defined here)`.

## Rules

- **Same code as a run:** `explain` uses the same lookups as `aliprehook_run` and the wrapper (key, hook lookup, `_aliprehook_project_plan`, `commands.map` lookup), so the two cannot drift. A run's behaviour change shows up in `explain` without extra work.
- Output on **stdout** (it is what was asked for), through `_aliprehook_msg` and theme roles; warnings on stderr as usual. Names, never values.
- Exit codes: 0 the run would work; 1 a problem was found (warning in § 4, or `<cmd>` not an aliprehook command); 2 usage error.
- Independent of `ALIPREHOOK_VERBOSE`: always the full explanation.
- `--help` with usage, options and an example; listed in `aliprehook help`.
- The run summary stays what *did* happen; `explain` is what *would* happen.

## Out of scope

- Arguments (`aliprehook explain Dbuild -- --pull`) to show the full command line: `ALIPREHOOK_VERBOSE=detail` already does this in a real run.
- Suggesting likely typos (a similar command name under the same key).
- Running hooks in a sandbox to learn their variables.
