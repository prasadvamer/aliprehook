# Run summary: show what aliprehook did

Design for printing a short, subdued line that says what aliprehook did before your command ran: which hooks ran, which variables were passed, and where the command line came from. Work items: [03_roadmap.md](./03_roadmap.md) Phase 8, Improvements from dogfooding.

> Status: implemented (Phase 8, Improvements from dogfooding).

## Problem

aliprehook works like a ghost. When you type `Dbuild`:

- you cannot tell whether hooks ran, and which;
- you cannot tell whether `aliprehook_env_pass` passed anything;
- you cannot tell whether the command came from `commands.map` or is the `aliprehook_define` default.

When it works, that is invisible; when something is off (wrong project key, a hook not registered, a stale `commands.map` line), you have nothing to go on.

## The summary line

After the hooks and before the command, aliprehook prints **one line** to stderr, in a subdued color, **only if it did something**:

```text
aliprehook: Dbuild · hooks: all_Dbuild.sh (*), aws_login.sh · env: AWS_ACCESS_KEY_ID, AWS_SESSION_TOKEN · command: commands.map:3
```

| Part | Shown when | Says |
|---|---|---|
| `hooks:` | at least one hook ran | Hook file names in run order; `(*)` for `*` lines, `(project)` for the repo's `.aliprehook.yml` hook |
| `env:` | at least one variable was passed | Variable **names** (never values); `(kept)` after names kept in the terminal by `--keep-env` |
| `command:` | the command line came from `commands.map` | `commands.map:<line>`; nothing is shown for the `aliprehook_define` default |

- **Nothing to report → no line.** A command with no hooks, no variables and the default command line prints nothing extra, so plain commands look exactly like before.
- One line, no matter how many hooks: it never pushes your command's output away.
- Hooks' own output is printed as before, above the summary.
- Failures are unchanged: a failing hook or a missing required variable already prints an `error:` and the command does not run; no summary is printed then.

## Levels: `ALIPREHOOK_VERBOSE`

| Value | Prints |
|---|---|
| `quiet` | Nothing (errors and warnings still print) |
| `summary` (default) | The one line above |
| `detail` | One line per step, as it happens, then the full command line |

`detail` example:

```text
aliprehook: Dbuild in github.com/org/sample_app_web
aliprehook:   hook all_Dbuild.sh (*)
aliprehook:   hook aws_login.sh
aliprehook:     passed AWS_ACCESS_KEY_ID, AWS_SESSION_TOKEN
aliprehook:   project hook: skipped (repo not allowed; run: aliprehook allow)
aliprehook:   command (commands.map:3): DOCKER_BUILDKIT=1 docker compose -f docker-compose.dev.yml build --no-cache
```

- `detail` prints each hook line **before** the hook runs, so a slow or hanging hook is visible, and the hook's own output appears under its line. A `passed …` line follows when the hook passed variables; a failure prints the usual `error:` instead.
- `detail` also says why something did *not* happen: no hooks in `hooks.map`, project hook none/skipped (not a git repo, no `.aliprehook.yml`, repo not allowed, no entry for this command), `command (default)` when no `commands.map` line applies. With `--keep-env` it lists the names kept in the shell.
- `detail` shows the command line with your arguments, as it will run (when the line places `"$@"` itself, the arguments are listed after it). Variable values are still never printed.

### Setting it: `aliprehook verbose`

No need to edit `~/.zshrc`:

| Command | Effect |
|---|---|
| `aliprehook verbose` | Print the current level and where it comes from (`default`, `settings`, `ALIPREHOOK_VERBOSE`) |
| `aliprehook verbose <quiet\|summary\|detail>` | Save the level: every shell, from the next command on, and after restarts |
| `aliprehook verbose <level> --shell` | This shell only (sets `ALIPREHOOK_VERBOSE`); other shells unchanged |
| `aliprehook verbose --reset` | Remove the saved level (back to the default `summary`) |
| `ALIPREHOOK_VERBOSE=detail Dbuild` | One run only |

```text
$ aliprehook verbose detail
aliprehook: verbose level is now detail (saved in ~/.config/aliprehook/settings)
$ aliprehook verbose
detail (from ~/.config/aliprehook/settings)
```

- The level is a value, not a flag: `aliprehook verbose quiet`, not `--quiet`. A wrong value is a usage error listing the three levels.
- Saved in `~/.config/aliprehook/settings`, a plain `name=value` file (`verbose=detail`), read by aliprehook (parsed, never sourced). Created on first save, kept by `uninstall.sh`.
- Precedence: `ALIPREHOOK_VERBOSE` (one run, `--shell`, or `.zshrc`) → `settings` → default `summary`. `aliprehook verbose` warns when a saved level is hidden by `ALIPREHOOK_VERBOSE`, so the setting never seems to be ignored.
- Every shell sees a save right away: aliprehook reads `settings` (a tiny file) on every command.
- `aliprehook verbose --help` explains the levels; it is listed in `aliprehook help`. `aliprehook edit settings` opens the file.
- An invalid level (in `ALIPREHOOK_VERBOSE` or `settings`) prints a warning once per shell and `summary` is used.

## Look

- Drawn with a new theme role **`trace`**, default the same grey as `hint` (`90`), so it is clearly secondary to your command's output and to warnings/errors. Override it like any role in `theme-overrides` (`trace=2` for dim, `trace=` for the default text color).
- Same color rules as every message: no color in pipes, with `NO_COLOR`, `ALIPREHOOK_COLOR=never` or `TERM=dumb`; the words are the same either way.
- Always on stderr, so `$(Dbuild)` and pipes get only the command's output.

## Rules

- Names only, never values: the same rule as every other aliprehook message.
- The summary describes what happened in **this** run; it does not read files again or run anything extra (no slowdown beyond printing one line).
- Hand-written (Case B) functions: `aliprehook_run` prints the `hooks:` / `env:` line when it finishes (it does not know the command yet); `aliprehook_command` adds a `command: commands.map:<line>` line when a line is used. In `detail`, `aliprehook_with_env` / `aliprehook_command` print the command line. `aliprehook_define` wrappers print everything in one line, right before the command.
- `aliprehook explain <cmd>` (Phase 8) stays the dry run: what *would* happen, without running anything. The summary is what *did* happen.
