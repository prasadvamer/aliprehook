# aliprehook

Optional prehooks for opt-in shell commands, based on which project you are in.

Status: early development (zsh only). Design docs are in [doc/](./doc/).

## 1. What aliprehook is

You keep typing your own short commands (`Dup`, `serve`, …). aliprehook lets a command run a **prehook** first, depending on the project you are in:

```text
You type: Dup --watch
    │
    ├─ 1) User layer: your hook for (this project, Dup)? → run it
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
#   aliprehook_run hello "$@" || return $?   ← runs hooks for "hello" first (none yet)
#   echo hello from aliprehook "$@"         ← then your command, with your arguments
# }
```

No hooks are registered yet, so `hello` behaves exactly like the command. Hooks are added in [6. Add a user hook](#6-add-a-user-hook) and [7. Try the example](#7-try-the-example).

A real one, for Docker:

```zsh
aliprehook_define Dup docker compose up
Dup --watch    # same as: docker compose up --watch (plus hooks for this project, once you add some)
```

If `Dup` was already an alias, `aliprehook_define` replaces it.

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
github.com/org/sample_app_web     Dup      hooks/sample_app_web_Dup.sh
github.com/org/sample_app_web     serve    hooks/sample_app_web_serve.sh
/home/me/scratch/playground       Dup      hooks/scratch_Dup.sh
```

- Columns are separated by spaces or tabs. No spaces inside a column.
- Hook paths are relative to `~/.config/aliprehook/` (or absolute).
- Lines starting with `#` and blank lines are ignored.
- The first matching line wins.
- User hooks apply to every clone with the same key.

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
| Working directory | Where you ran the command |

Exit non-zero to stop the command. Print to stderr (`>&2`) to keep the command's stdout clean.

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

**Case C — mix:** same as B, `aliprehook_run` first, then your logic.

| Situation | Use |
|---|---|
| Optional prehook + one command | `aliprehook_define Name cmd…` |
| Function with its own logic | Keep function + `aliprehook_run Name "$@"` at top |
| No prehook needed | Normal function/alias |

## Commands

| Command | Does |
|---|---|
| `aliprehook_define <name> <command...>` | Define an opt-in command |
| `aliprehook_run <name> [args...]` | Run hooks for `<name>` (used inside functions) |
| `aliprehook allow` | Allow this repo's `.aliprehook.yml` hooks |
| `aliprehook revoke` | Stop allowing them |
| `aliprehook key` | Print the project key for the current directory |
| `aliprehook help` | Usage |

## Uninstall

```sh
./uninstall.sh   # removes lib.zsh and README.md; keeps registry, allowed, hooks/
```

Then remove the `source` and `aliprehook_define` lines from `~/.zshrc`. For full removal: `rm -rf ~/.config/aliprehook`.

## Development

```sh
./install.sh --copy   # copy instead of symlink (default links back to this repo)
zsh tests/run.zsh     # run the tests
```

Set `ALIPREHOOK_HOME` to use a directory other than `~/.config/aliprehook/`.
