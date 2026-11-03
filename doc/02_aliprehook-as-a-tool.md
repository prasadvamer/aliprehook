# aliprehook as a public tool

This note is separate from the **system design** in [01_shell-aliprehook-system.md](./01_shell-aliprehook-system.md).

The system plan already includes **user layer + project layer** (with `aliprehook allow`).
This file is only about what changes when shipping aliprehook as a **public product** others install (Brew, site, trust at scale, positioning).

## Personal dogfood vs public product (summary)

| | Dogfood / early use | Public product |
|---|---|---|
| Audience | You (and maybe a few friends) | Many users / maybe teams |
| Trust | Your files + local `allow` | Stronger allow UX, explain/dry-run, no remote script fetch by default |
| Config layers | Already in system plan | Same model; polish packaging and docs |
| Success | `Dup` works with prep | Safe, explainable, installable, distinct from direnv/just |

Config layers are **not** redefined here — see [01_shell-aliprehook-system.md](./01_shell-aliprehook-system.md) § Config layers.

## What stays the same

The core idea still works as a product pitch:

> Optional “before this command” hooks, keyed by project identity (git remote), with personal hooks in `$HOME` and optional in-repo project hooks that stay off until allowed.

## What must change for a public tool

### 1. Trust and security become the product

Even with `allow`, a public audience needs:

- Very clear `aliprehook allow` / `revoke` / `explain` UX (direnv-style)
- Prefer local hooks only in v1 — not arbitrary remote script download
- Optional later: pinned/signed hook packs
- Docs that warn: allowing a repo runs that repo’s scripts

Without that, the tool is a security footgun and will not be trusted.

### 2. Project identity gets harder at scale

Normalized `origin` is the system default. As a wider product also document:

- Forks: `origin` vs `upstream`
- GitHub Enterprise / GitLab self-hosted URL variants
- Monorepos (one remote, many apps — may need remote + path-within-repo later)
- No git at all (path fallback already in the system plan)

### 3. Distribution and UX

Product UX still needs:

- `aliprehook init`, `aliprehook doctor`
- Support beyond zsh (bash, fish at minimum)
- Shell completions
- Versioned upgrades that do not silently break registries / `allowed`

#### Distribution decision (locked in)

**Not either-or.** Same pattern as direnv, starship, mise, etc.:

| Channel | Role |
|---|---|
| **Homebrew** (`brew install aliprehook` or a tap) | **Primary** for macOS (and Linuxbrew). Versioned, easy upgrade/uninstall, trusted install path. |
| **Project site / GitHub Releases** | **Companion**: docs + `curl -fsSL … \| sh` install script for people without Brew, CI images, quick try. |
| npm / cargo as *the* install | **Not** the main story for a shell wrapper. |

So:

1. **CLI tool with Brew first**, not a browser web app.
2. The **site** is marketing, docs, and a **direct install script** — not instead of Brew.
3. Ship **GitHub Releases** (tagged versions, checksums); Brew and the install script both point at those.

Phased:

1. GitHub repo + Releases + install script
2. Homebrew tap (or core formula later) as the recommended Mac path
3. Site documents both: `brew install …` and `curl … | sh`

**Not** aiming at for v1: zip-only download page; or npm as the primary install.

### 4. Sharing model

**B. Team workflow tool** (later)
Shared hook packs: e.g. `aliprehook add org/compose-prep`. Needs packaging, permissions, review.

### 5. Positioning vs existing tools

Users will ask: why not direnv / just / tramp?

Wedge:

> Keep your personal aliases. Attach per-repo prep by git remote — user hooks in `$HOME`, optional project hooks in the repo only after `allow`.

| Tool | Overlap |
|---|---|
| direnv | Project env on `cd`, not on each personal command |
| just / Make / Task | In-repo named recipes for the team |
| tramp | Command pre/post hooks; usually path/cwd + binary rules |
| zsh chpwd / envoke | On directory enter/leave |
| Git `includeIf` by remote URL | Same identity idea, only for git config |

### 6. What not to put in a public v1

- Auto-running project hooks without allow (system already forbids this)
- Downloading remote scripts without pin + allow
- Replacing Make/just as the team task runner
- Complex monorepo matrices on day one

## Possible product shapes

1. **“direnv for commands”** — trigger on command invoke, not on `cd`
2. **Package the system plan** — user + project layers, Brew + site
3. **Hook packs** — later team sharing
4. **Shell plugin** — Oh My Zsh / fish plugin as an alternate install

(1) and (2) match best.

## Suggested product roadmap

1. Implement [01_shell-aliprehook-system.md](./01_shell-aliprehook-system.md) (user + project layers + allow)
2. Dogfood personally
3. Open-source with README + allow/explain
4. Multi-shell + install script / Homebrew
5. Later: signed/shared hook packs for teams

## Relation to the system plan

- **Source of truth for behavior:** [01_shell-aliprehook-system.md](./01_shell-aliprehook-system.md)
- **This file:** packaging, distribution, market positioning, public trust polish
