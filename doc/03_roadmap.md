# aliprehook roadmap

What to build, in order. Behavior is defined in [01_shell-aliprehook-system.md](./01_shell-aliprehook-system.md); packaging and positioning in [02_aliprehook-as-a-tool.md](./02_aliprehook-as-a-tool.md).

Each phase ends with a **Done when** check. Do not start the next phase until it passes.

## Phase 0 — Repo setup

- [x] Repo layout: `lib.zsh`, `hooks/`, `README.md`, `tests/`, `doc/`
- [x] Pick a test runner for zsh: plain zsh scripts, `zsh tests/run.zsh`
- [x] `install.sh` (dev only) that copies/symlinks into `~/.config/aliprehook/`

**Done when:** `install.sh` creates `~/.config/aliprehook/{README.md,lib.zsh,registry,allowed,hooks/}` and `source ~/.config/aliprehook/lib.zsh` loads with no errors.

## Phase 1 — Project key resolution

- [ ] `aliprehook_normalize_remote <url>`
  - Strip `https://`, `http://`, `ssh://`, `git@` / userinfo
  - SCP-style `host:org/repo` → `host/org/repo`
  - Drop trailing `.git` and `/`
  - Lowercase host
- [ ] `aliprehook_project_key`: `origin` → first fetch remote → `pwd -P`
- [ ] Tests for every row of the normalization table in 01, plus: no git, git with no remotes, non-`origin` remote only

**Done when:** all four URL forms of `sample_app_web` give `github.com/org/sample_app_web`, and a folder with no git gives its `pwd -P` path.

## Phase 2 — User layer (MVP)

- [ ] `registry` parser: three whitespace-separated columns, skip blank lines and `#` comments
- [ ] `aliprehook_run <cmd_name>`: look up `(key, cmd)` → run hook; non-zero exit aborts
- [ ] `aliprehook_define <name> <command...>`: creates the wrapper function from 01
- [ ] `hooks/example_echo.sh` (safe: prints that aliprehook ran, key, command; exit 0)
- [ ] `registry` ships with a commented example line pointing at `example_echo.sh`
- [ ] Tests: match, no match, failing hook stops the main command, args pass through via `"$@"`

**Done when:** `aliprehook_define Dup docker compose up` in `~/.zshrc` runs the user hook in a registered repo and plain `docker compose up` everywhere else.

## Phase 3 — Project layer + allow gate

- [ ] `allowed` file: one normalized key per line
- [ ] `aliprehook allow` / `aliprehook revoke` for the current project key
- [ ] Read `.aliprehook.yml` `hooks:` map (minimal parser; no full YAML dependency)
- [ ] Resolve hook paths relative to the repo root; reject paths that leave the repo
- [ ] Run order: user hook → project hook (only if allowed) → main command
- [ ] Tests: not allowed → project hook skipped, allowed → runs, revoke → skipped again

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
- [ ] Local hooks only; no remote script download
- [ ] Document identity edge cases: forks (`origin` vs `upstream`), GitHub Enterprise / self-hosted GitLab, monorepos
- [ ] License, CONTRIBUTING, changelog

**Done when:** a fresh machine can go from install to a working hook using only the README.

## Phase 7 — Distribution

- [ ] GitHub Releases: tagged versions + checksums
- [ ] `curl -fsSL … | sh` install script pointing at Releases
- [ ] Homebrew tap (core formula later) as the recommended Mac path
- [ ] Project site: docs + both install paths (`brew install …` and `curl … | sh`)
- [ ] Versioned upgrades that do not break `registry` / `allowed` (format version + migration)

**Done when:** `brew install` and the install script both install the same tagged release, and an upgrade keeps existing config working.

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
