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

- [ ] `README.md` covers the 7 sections listed in 01 (what it is, setup, key order, registry, project layer + allow, adding a hook, try the example)
- [ ] Document example `.aliprehook.yml`; add a stub in a personal test repo
- [ ] Convert existing `.zshrc` functions using Case A / B / C from 01
- [ ] Wire `source` + `aliprehook_define Dup docker compose up` into `~/.zshrc`

**Done when:** someone new can open `~/.config/aliprehook/README.md`, add a hook, and see `example_echo.sh` run without reading these docs.

## Phase 5 — Dogfood

- [ ] Use it daily for 2+ weeks across several repos
- [ ] Note friction: slow shell startup, confusing errors, missing commands
- [ ] Add `aliprehook explain <cmd>`: print the key, which hooks would run, and why (dry run)

**Done when:** no open friction notes that block daily use, and `explain` answers "why did / didn't my hook run?".

## Phase 6 — Public v1 (open source)

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

## Phase 7 — Distribution

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

## Phase 8 — Multi-shell

- [ ] bash support
- [ ] fish support
- [ ] Shell completions (zsh, bash, fish)
- [ ] Optional: Oh My Zsh / fish plugin as an alternate install

**Done when:** the Phase 2–3 test suite passes on zsh, bash and fish.

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
