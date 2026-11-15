# Wrapping real commands (`docker compose up` without `Dup`)

Design for using aliprehook on a real command (`docker`, `git`, `npm`, …) instead of a short alias, with hooks and command lines per **subcommand** (`docker compose up`). Roadmap: [03_roadmap.md](./03_roadmap.md) § Later (not v1).

> Status: parked (Later, not v1), not implemented.

## Problem

aliprehook is built around names you define: `aliprehook_define Dup docker compose up`. Some users do not want a new name; they want their hooks, `commands.map` lines, variables and the run summary on the command they already type:

```zsh
docker compose up -d
```

## What works today

A defined name may be the real command's own name:

```zsh
aliprehook_define docker docker
```

The wrapper calls `command docker`, so it does not call itself. But:

1. Hooks and `commands.map` lines are keyed by `docker`, so they apply to **every** docker call (`docker ps`, `docker logs`, …). A hook has to filter its own arguments (`case "$*" in "compose up"*) …`).
2. Every call pays for the lookup (project key, git calls), even when nothing is registered for that subcommand.

## Design

### 1. `aliprehook_wrap`

```zsh
aliprehook_wrap docker            # in ~/.zshrc
aliprehook_wrap --keep-env aws
aliprehook_wrap docker --value-opts '-f --file -p --project-name --env-file --profile --project-directory --context -H --host'
```

- Same as `aliprehook_define docker docker`, but says what it means.
- Fails with an error if `docker` is not an installed program (`whence -p`), so a typo does not create a useless function.
- Only your interactive shell sees the wrapper (it lives in `.zshrc`). Scripts, `make`, IDEs and other programs run the real command, untouched. Completion keeps working.
- aliprehook itself calls `command git`, so wrapping `git` is safe.
- `--value-opts '<options>'`: the options of this command that take a value as the next word (see Matching). Optional; without it, no option is known to take a value.

### 2. Subcommand keys: `docker:compose:up`

The command column of `hooks.map` and `commands.map` (and the CLI's `<cmd>`) can name a subcommand path, words joined by `:`:

```text
# hooks.map
*                               docker               hooks/docker_any.sh
*                               docker:compose:up    hooks/vpn_check.sh
github.com/org/sample_app_web   docker:compose       hooks/web_compose_env.sh
github.com/org/sample_app_web   docker:compose:up    hooks/web_db_ready.sh
```

```zsh
aliprehook hook new docker:compose:up --hook vpn_check.sh --all
aliprehook command set docker:compose:up 'docker compose -f docker-compose.dev.yml up'
```

**Matching:** a key `docker:w1:w2…` matches when the **positional words** of the typed arguments start with `w1 w2 …`. Positional words are what is left after skipping options:

- A word starting with `-` is an option and is skipped. `--opt=value` and `-fvalue` (value attached) are one word.
- An option listed in `--value-opts` also takes the **next** word as its value; it is skipped too.
- `--` ends options: every word after it is positional.
- A lone `-` is positional (often means stdin).

| Typed | Positional words | Matches `docker:compose:up` |
|---|---|---|
| `docker compose up -d` | `compose up` | yes (exact prefix) |
| `docker compose -f dev.yml up` | `compose up` | yes, with `-f` in `--value-opts` |
| `docker --context prod compose up` | `compose up` | yes, with `--context` in `--value-opts` |
| `docker compose --dry-run up` | `compose up` | yes (`--dry-run` takes no value) |
| `docker compose -f dev.yml up` | `compose dev.yml up` | **no**, without `-f` in `--value-opts` |
| `docker compose run web up` | `compose run web up` | no (`run` where `up` is expected) |

- Key words must follow each other in the positional words, from the start; they are never searched for further on, so an option value or a later argument that happens to equal a key word (`-p up`, `run web up`) never causes a match.
- An option missing from `--value-opts` can only cause a missed match, never a wrong one. Add it, or register the hook on a shorter key (`docker:compose`) and check `"$@"` in it.
- aliprehook does not ship option lists for any tool; each wrap declares its own, so nothing breaks when a tool adds options.
- A key word may not contain `:` or whitespace; the base command follows the usual name rule.

**Hooks add up**, as everywhere: every matching line runs. Order: all `*` lines first, then the project's lines; within each, general to specific (`docker`, then `docker:compose`, then `docker:compose:up`); file order within the same key. So the example runs `docker_any.sh`, `vpn_check.sh`, `web_compose_env.sh`, `web_db_ready.sh`.

**Commands replace**, as everywhere: only the **most specific** matching `commands.map` line runs. How your arguments reach it depends on whether options were skipped to match:

- **Exact prefix** (the key's words are the first typed words, no option before or between them): the matched words are replaced by the line, and the rest of your arguments are appended (or go where the line puts `"$@"`):

```text
github.com/org/sample_app_web  docker:compose:up  docker compose -f docker-compose.dev.yml up
```

`docker compose up -d` → `docker compose -f docker-compose.dev.yml up -d`. `docker compose ps` → unchanged (no matching line; the real command runs).

- **Options skipped** (`docker compose -f dev.yml up -d`): where your options belong in the line is ambiguous (appending `-f dev.yml` after `up` would break compose), so aliprehook does not place them. The line is used only if it places `"$@"` itself; `"$@"` is then your arguments with the matched words removed, in typed order (`-f dev.yml -d`):

  ```text
  github.com/org/sample_app_web  docker:compose:up  docker compose "$@" up
  ```

  `docker compose -f dev.yml up -d` → `docker compose -f dev.yml -d up`. A line without `"$@"` is not used for such a call: the next less specific matching line is tried the same way, and if none applies, the real command runs unchanged. `detail` says why (`command commands.map:4 not used (options before the subcommand; the line has no "$@")`).

- Inside the line, the wrapped name means the **real** command (the line runs in a subshell with the wrapper removed), so `docker …` in a `docker:…` line cannot loop.

**Hook environment:** `ALIPREHOOK_COMMAND` stays the base command (`docker`); new `ALIPREHOOK_MATCH` is the key of the line that ran this hook (`docker:compose:up`). Hooks get all your arguments, as today.

**Project layer:** `.aliprehook.yml` accepts the same keys, quoted because of the `:` (`"docker:compose:up": .aliprehook/db_ready.sh`), with the same matching and order. `*` stays forbidden there.

**Visibility:** the run summary names the matched path, e.g. `aliprehook: docker compose up → hooks: vpn_check.sh (*), web_db_ready.sh · command: commands.map:4`; `detail` lists which keys matched, the options skipped to match them, and any `commands.map` line not used and why. `aliprehook hook ls` / `command ls` show subcommand keys as they are.

### 3. Fast path

Before computing the project key, aliprehook checks cheaply whether anything could apply to this command:

- a line in `hooks.map` or `commands.map` whose command is `docker` or starts with `docker:`, or
- a `.aliprehook.yml` in this directory or a parent (found by walking up the path, no git call).

If none, the real command runs right away: no git calls, no summary line (`detail` prints one line: `docker: nothing registered; running it directly`). This makes wrapping a busy command (`docker`, `git`, `npm`) nearly free, and also speeds up every `aliprehook_define` command that has nothing registered.

## Rules

- Nothing changes for existing setups: a plain command name in the column means exactly what it does today; `aliprehook_define` is unchanged.
- `aliprehook_wrap` and `aliprehook_define` share one implementation; `aliprehook_define X X` keeps working.
- Subcommand keys work for any defined command, not only wrapped ones (`Dup:logs` is valid, if rarely useful).

## Out of scope

- Built-in option lists for known tools (each wrap declares `--value-opts`)
- Moving skipped options into a `commands.map` line automatically (the line places `"$@"`)
- Wildcards inside keys (`docker:*:up`)
- Wrapping shell builtins or keywords (`cd`, `echo`)
