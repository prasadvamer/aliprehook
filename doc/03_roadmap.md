# aliprehook roadmap

What to build, in order. Behavior is defined in [01_shell-aliprehook-system.md](./01_shell-aliprehook-system.md); packaging and positioning in [02_aliprehook-as-a-tool.md](./02_aliprehook-as-a-tool.md).

Each phase ends with a **Done when** check. Do not start the next phase until it passes.

## Phase 0 — Repo setup

- [x] Repo layout: `lib.zsh`, `hooks/`, `README.md`, `tests/`, `doc/`
- [x] Pick a test runner for zsh: plain zsh scripts, `zsh tests/run.zsh`
- [x] `install.sh` (dev only) that copies/symlinks into `~/.config/aliprehook/`
- [x] `uninstall.sh` (dev only), the reverse of `install.sh`:
  - Removes only what `install.sh` manages: `lib.zsh` and `README.md` (symlink or copy)
  - **Never** removes user data: `registry`, `allowed`, `hooks/`
  - Respects `ALIPREHOOK_HOME`, same as `install.sh`
  - Safe to run twice; no error if already uninstalled
  - Warns if `~/.zshrc` still sources `lib.zsh` (does not edit `~/.zshrc`)
  - Prints what was kept and the manual full-removal command (`rm -rf ~/.config/aliprehook`)
- [x] `tests/test_uninstall.zsh`: managed files removed, user data untouched, second run is a no-op, reinstall after uninstall works

**Done when:** `install.sh` creates `~/.config/aliprehook/{README.md,lib.zsh,registry,allowed,hooks/}`, `source ~/.config/aliprehook/lib.zsh` loads with no errors, and `uninstall.sh` removes `lib.zsh` + `README.md` while `registry`, `allowed` and `hooks/` stay exactly as they were.

## Phase 1 — Project key resolution

- [x] `aliprehook_normalize_remote <url>`
  - Strip `https://`, `http://`, `ssh://`, `git@` / userinfo
  - SCP-style `host:org/repo` → `host/org/repo`
  - Drop trailing `.git` and `/`
  - Lowercase host
- [x] `aliprehook_project_key`: `origin` → first fetch remote → `pwd -P`
- [x] Tests for every row of the normalization table in 01, plus: no git, git with no remotes, non-`origin` remote only

**Done when:** all four URL forms of `sample_app_web` give `github.com/org/sample_app_web`, and a folder with no git gives its `pwd -P` path.

## Phase 2 — User layer (MVP)

- [x] `registry` parser: three whitespace-separated columns, skip blank lines and `#` comments
- [x] `aliprehook_run <cmd_name>`: look up `(key, cmd)` → run hook; non-zero exit aborts
- [x] `aliprehook_define <name> <command...>`: creates the wrapper function from 01
- [x] `hooks/example_echo.sh` (safe: prints that aliprehook ran, key, command; exit 0)
- [x] `registry` ships with a commented example line pointing at `example_echo.sh`
- [x] Tests: match, no match, failing hook stops the main command, args pass through via `"$@"`

**Done when:** `aliprehook_define Dup docker compose up` in `~/.zshrc` runs the user hook in a registered repo and plain `docker compose up` everywhere else.

## Phase 3 — Project layer + allow gate

- [x] `allowed` file: one normalized key per line
- [x] `aliprehook allow` / `aliprehook revoke` for the current project key
- [x] Read `.aliprehook.yml` `hooks:` map (minimal parser; no full YAML dependency)
- [x] Resolve hook paths relative to the repo root; reject paths that leave the repo
- [x] Run order: user hook → project hook (only if allowed) → main command
- [x] Tests: not allowed → project hook skipped, allowed → runs, revoke → skipped again

**Done when:** cloning a repo with `.aliprehook.yml` runs nothing until `aliprehook allow`, and `aliprehook revoke` turns it off again.

## Phase 4 — README + existing functions

- [x] `README.md` covers the 7 sections listed in 01 (what it is, setup, key order, registry, project layer + allow, adding a hook, try the example)
- [x] Document example `.aliprehook.yml`; stub in `examples/project/` (copy into any repo to try)
- [x] Convert existing `.zshrc` functions using Case A / B / C from 01 (none to convert yet; cases documented in README)
- [x] Wire `source` + `aliprehook_define Dup docker compose up` into `~/.zshrc`

**Done when:** someone new can open `~/.config/aliprehook/README.md`, add a hook, and see `example_echo.sh` run without reading these docs.

## Phase 5 — Hook chaining + environment

Do 5a first: 5b builds on several user hooks running in order.

### 5a — Multiple user hooks + common (`*`) hook

Design: [01_shell-aliprehook-system.md](./01_shell-aliprehook-system.md) § Multiple hooks and the common (`*`) hook.

- [x] Registry: `*` as project key matches every project (user `registry` only)
- [x] Project layer rejects `*`: `aliprehook allow` refuses, an already-allowed repo gets a warning and the entry is ignored (done early, `tests/test_project_wildcard.zsh`)
- [x] Run **all** matching lines: `*` lines first, then exact-key lines, file order within each group (replaces "first match wins")
- [x] First failing hook stops later hooks, the project layer and the main command
- [x] Same (key, command, hook) listed twice runs once
- [x] Update README § User registry, `templates/registry` comment and the Phase 2 test that checks "first line wins"
- [x] Tests: `*` only; several `*` lines for one command in file order; `*` for `Dup` does not run for `serve`; `*` + exact key order; several exact-key lines in file order; failure in `*` hook stops the rest; `*` hook runs in a project with no other lines; path-key projects match `*`; duplicates run once

**Done when:** with a `*` line and two `sample_app_web` lines for `Dup`, running `Dup` in `sample_app_web` runs all three in order and then the main command, and in any other project runs only the `*` hook.

### 5b — Hook environment (`ALIPREHOOK_ENV_FILE`)

Hooks run as child processes, so `export` in a hook never reaches the main command. Design and open decisions: [04_hook-env.md](./04_hook-env.md).

- [x] Decide the open items in 04 (scope A / B / C, precedence, denylist): C, user wins, denylist as listed
- [x] Before each hook: create a `0600` temp file (`$XDG_RUNTIME_DIR`, else `$TMPDIR`), pass its path as `ALIPREHOOK_ENV_FILE`; always delete it, also on failure / Ctrl-C
- [x] Parser: `NAME=value` and `NAME<<DELIM` … `DELIM`; literal values; never `source`; bad line → error with hook + line number, command does not run
- [x] Merge: later user hooks see earlier user hooks' variables; later (more specific) user hook wins; user beats project; project hooks do not see user-hook variables
- [x] Project-hook denylist (`PATH`, `LD_*`, `DYLD_*`, `BASH_ENV`, `ENV`, `ZDOTDIR`, `IFS`, `PS4`, `PROMPT_COMMAND`, `HOME`, `SHELL`, `GIT_SSH_COMMAND`, `GIT_EXEC_PATH`); `ALIPREHOOK_*` reserved for both layers
- [x] Limits: 64 KiB file, 100 variables
- [x] `bin/aliprehook_env_pass` command (POSIX sh): `aliprehook_env_pass [--allow-empty] NAME|NAME=value... [--required NAME...] [--optional NAME...]`; reads exported variables; optional by default (warn on unset/empty/not exported); `--required` / `--optional` switch mode for the names after them; check all names and report every missing one; missing required → marker in `$ALIPREHOOK_ENV_FILE` + non-zero exit; invalid or `ALIPREHOOK_*` names rejected, newline values written as `NAME<<DELIM` blocks, error if `$ALIPREHOOK_ENV_FILE` is not set
- [x] After each hook: a required-missing marker aborts the main command even if the hook exited 0
- [x] Put aliprehook's `bin/` first on `PATH` for every hook (no load line in hooks) and set `$ALIPREHOOK_ENV_PASS_BIN` to its absolute path; `install.sh` / `uninstall.sh` manage `bin/` like `lib.zsh`
- [x] `aliprehook_with_env <command...>`: run the command with the collected variables via `local -x` (works for binaries, functions and aliases); clears them after use
- [x] `aliprehook_define` passes the variables to the main command (declares them in the wrapper instead of calling `aliprehook_with_env`, so alias main commands keep working)
- [x] If scope C is chosen: `aliprehook_define --keep-env` (user-layer only)
- [x] Messages and `explain` show variable names, never values
- [x] README: `ALIPREHOOK_ENV_FILE` example, Case B usage, Docker Compose `environment:` note; replace the manual `source`-a-file workaround
- [x] Tests: `aliprehook_env_pass` with several names; `NAME=value` form; mixed forms; exported / unset / empty / not exported (warning); `--required` / `--optional` switches in both orders; several missing names reported together; missing required aborts main command even when hook exits 0; `--allow-empty` anywhere in the call; multi-line; invalid name; works from sh, bash and a non-shell hook; works when the hook resets `PATH` (via `$ALIPREHOOK_ENV_PASS_BIN`); variable reaches main command; terminal unchanged afterwards; failing hook's file ignored; malformed line stops command; multi-line value; user beats project; project hook cannot read user-hook vars; denylisted name from project hook rejected; temp file removed on success, failure and interrupt; function and alias main commands work

**Done when:** a user hook that writes `TOKEN=…` to `$ALIPREHOOK_ENV_FILE` makes `TOKEN` visible to `docker compose up` via `Dup`, `echo $TOKEN` in the same terminal afterwards prints nothing (unless `--keep-env`), and no temp file is left behind.

## Phase 6 — Output theme (purple)

Design and palette: [05_theme.md](./05_theme.md).

- [x] `themes/purple.theme` (default) and `themes/none.theme`: `role=code` files for `brand`, `info`, `success`, `warning`, `error`, `command`, `hook`, `key`, `var`, `hint`
- [x] Theme loader (parse, never source): `ALIPREHOOK_THEME` name or path; `~/.config/aliprehook/theme` overrides single roles; missing roles → no color
- [x] `_aliprehook_msg <level> …` + inline role helper in `lib.zsh`; route **every** message through it (no hard-coded colors anywhere); message text in the level's color (info: default, warning: yellow, error: red), named items (command, hook, key, var) keep their own colors
- [x] Pass the resolved theme to hooks (`ALIPREHOOK_THEME_CODES`); `msg` helper in `bin/aliprehook_env_pass` uses it
- [x] Color only when stderr is a TTY, `NO_COLOR` unset, `TERM` not `dumb`; `ALIPREHOOK_COLOR=auto|always|never`
- [x] Keep `warning:` / `error:` words so meaning never depends on color; add an `error:` label to every failure message that lacks one today (`hook not found`, `hook not executable`, `project hook outside the repo`, …)
- [x] `install.sh` / `uninstall.sh` manage `themes/`; README section on themes and turning color off
- [x] Tests: no escape codes when not a TTY, with `NO_COLOR`, or `ALIPREHOOK_COLOR=never`; codes present with `always`; custom theme file and user override change only the listed roles; partial theme falls back to no color; same colors from `aliprehook_env_pass`; existing tests' message assertions unaffected (plain output in tests)

**Done when:** with the default theme, warnings, errors and `aliprehook allow` messages show in the purple palette in a terminal, piping or `NO_COLOR=1` gives plain text, and switching to `ALIPREHOOK_THEME=none` (or editing one role in `~/.config/aliprehook/theme`) changes the output without touching any code.

## Phase 7 — Per-project commands (`commands` file)

Same command name, different command line per project (`Dbuild` → `docker compose build` in most projects, a long project-specific line in others). Design: [06_commands.md](./06_commands.md).

- [ ] `~/.config/aliprehook/commands` parser: `project_key  command  rest-of-line`; `#` comments and blank lines skipped; `templates/commands` with commented examples, created by `install.sh` if missing (never overwritten, kept by `uninstall.sh`)
- [ ] Lookup: exact project key → `aliprehook_define` default; exactly one command runs; duplicate lines → first wins + warning with file and line
- [ ] No `*` in `commands`: a `*` line is ignored with an error (file + line) telling the user to change the `aliprehook_define` default instead
- [ ] `aliprehook_define` wrappers: after prehooks, run the chosen line with `eval` in a subshell, with hook-passed variables set
- [ ] Arguments: appended as `"$@"` unless the line contains `"$@"` / `$@` / `$*` itself
- [ ] Exit code is the command's; `--keep-env` behaves as before
- [ ] `aliprehook_command <name> <default...>` for hand-written (Case B) functions
- [ ] User layer only: `.aliprehook.yml` `commands:` section ignored with a warning
- [ ] Refuse a `commands` file writable by group or others (error, file ignored)
- [ ] Messages through the theme (`@command=`, `@key=` for file paths)
- [ ] README section; doc 01 summary marked implemented
- [ ] Tests: exact key beats default; `*` line rejected with error and ignored; no file / no match → default; env prefix and `$(…)` work; hook-passed variable usable in the line; arguments appended; `"$@"` placement; arguments with spaces intact; `cd`/assignments in the line do not change the shell; exit code passed through; failing hook → command not run; duplicate-line warning; group-writable file refused; `.aliprehook.yml` `commands:` ignored; hook-only (`:`) command overridden per project; `aliprehook_command` in a Case B function

**Done when:** `aliprehook_define Dbuild docker compose build` plus a `commands` line for `sample_app_web` makes `Dbuild` run that line there (with `DOCKER_BUILDKIT=1 REVISION=$(…)` working) and `docker compose build` in every other project, and adding or removing the line needs no change to `.zshrc`.

## Phase 8 — Dogfood

- [ ] Use it daily for 2+ weeks across several repos
- [ ] Note friction: slow shell startup, confusing errors, missing commands
- [ ] Add `aliprehook explain <cmd>`: print the key, which hooks would run, which command line will run (and which `commands` line chose it), and why (dry run)

**Done when:** no open friction notes that block daily use, and `explain` answers "why did / didn't my hook run?".

## Phase 9 — Public v1 (open source)

- [ ] `aliprehook init` (create user layer) and `aliprehook doctor` (check setup, permissions, sourcing)
- [ ] Clear allow / revoke / explain UX, direnv-style messages when a repo has an un-allowed `.aliprehook.yml`
- [ ] README warning: allowing a repo runs that repo's scripts
- [ ] Content-bound allow (re-ask on change, direnv-style). Today `allowed` stores only the project key, so after `git pull` a changed `.aliprehook.yml` or hook script runs without asking.
  - `allowed` stores key + clone root path (`pwd -P` of the repo root) + content hash: hash of `.aliprehook.yml` plus every hook script it references
  - **Per clone, not per key (decided):** allowing one clone does not allow other clones of the same remote. A new clone is blocked until `aliprehook allow` is run in it.
  - Hash changed → project hooks are skipped, with a message: `.aliprehook.yml changed; run aliprehook allow to review and re-allow`
  - `aliprehook allow` shows the yml and hook list (or a diff vs the last allowed version) before recording the new hash
  - **Existing key-only `allowed` lines need a re-allow (decided):** they no longer enable project hooks; the user runs `aliprehook allow` again in each clone. Show a message pointing at this when a key-only line matches.
  - Tests: edit yml → skipped; edit a hook script → skipped; re-allow → runs; unrelated repo files changing → still allowed; second clone of an allowed remote → skipped until allowed there; old key-only line → skipped with re-allow message
- [ ] Local hooks only; no remote script download
- [ ] Document identity edge cases: forks (`origin` vs `upstream`), GitHub Enterprise / self-hosted GitLab, monorepos
- [ ] License, CONTRIBUTING, changelog

**Done when:** a fresh machine can go from install to a working hook using only the README, and changing an allowed repo's `.aliprehook.yml` or hook scripts blocks its project hooks until `aliprehook allow` is run again.

## Phase 10 — Distribution

- [ ] GitHub Releases: tagged versions + checksums
- [ ] `curl -fsSL … | sh` install script pointing at Releases
- [ ] Homebrew tap (core formula later) as the recommended Mac path
- [ ] Project site: docs + both install paths (`brew install …` and `curl … | sh`)
- [ ] Versioned upgrades that do not break `registry` / `allowed` (format version + migration)

### Uninstall

Rule for every install path: **uninstall removes the program, never user data.** User data (`registry`, `allowed`, `hooks/`) lives in `~/.config/aliprehook/` and is only removed by the user.

- [ ] Split program files from user data:
  - Program (`lib.zsh`, README): Brew prefix (`$(brew --prefix)/share/aliprehook/`) or install-script dir (e.g. `~/.local/share/aliprehook/`)
  - User data: `~/.config/aliprehook/`, created by `aliprehook init`
  - `~/.zshrc` sources the program path, not `~/.config`
- [ ] Install script: `--uninstall` removes only the program files it installed; keeps user data; warns about the `~/.zshrc` line
- [ ] Homebrew: `brew uninstall aliprehook` removes the program (Brew never touches `~/.config`)
  - Formula `caveats` text: user data is kept in `~/.config/aliprehook/`; remove the `source` line from `~/.zshrc`; `rm -rf ~/.config/aliprehook` for full removal
- [ ] `aliprehook doctor` detects a leftover `~/.zshrc` `source` line pointing at a missing `lib.zsh`
- [ ] README + site **Uninstall** section covering all three paths:

  | Installed with | Remove program | Remove user data (optional) |
  |---|---|---|
  | Dev (`install.sh`) | `./uninstall.sh` | `rm -rf ~/.config/aliprehook` |
  | Install script | `curl -fsSL … \| sh -s -- --uninstall` | `rm -rf ~/.config/aliprehook` |
  | Homebrew | `brew uninstall aliprehook` | `rm -rf ~/.config/aliprehook` |

  Plus, for every path: remove `source …/lib.zsh` from `~/.zshrc` and open a new shell.

- [ ] Tests: install → uninstall → reinstall keeps existing hooks working, for the install script and the Brew formula (`brew test`)

**Done when:** `brew install` and the install script both install the same tagged release, an upgrade keeps existing config working, and both uninstall paths remove the program while `~/.config/aliprehook/` stays intact.

## Phase 11 — Multi-shell

- [ ] bash support
- [ ] fish support
- [ ] Shell completions (zsh, bash, fish)
- [ ] Optional: Oh My Zsh / fish plugin as an alternate install

**Done when:** the Phase 2–3, 5, 6 and 7 test suites pass on zsh, bash and fish.

## Later (not v1)

- Prefer `upstream` over `origin` for forks (opt-in)
- Monorepo keys: remote + path-within-repo
- Shared hook packs (`aliprehook add org/compose-prep`) with pinning/signing, permissions and review

## Out of scope

From 01 and 02:

- Matching by folder basename only
- Auto-running project hooks without allow
- Downloading remote scripts without pin + allow
- Replacing Make/just as the team task runner
- Complex monorepo matrices on day one
- npm / cargo or a zip download page as the primary install
