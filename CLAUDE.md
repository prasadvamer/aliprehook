# aliprehook

A zsh tool that runs optional prehooks (and per-project command lines) for opt-in shell commands, keyed by project (normalized git remote → first remote → `pwd -P`). User layer in `~/.config/aliprehook/`, project layer in a repo's `.aliprehook.yml` (off until `aliprehook allow`).

## Workflow

Three separate steps, each only on the user's word:

1. **Discuss.** Questions, ideas and "is it possible…?" get an answer in chat: how it works today, options, trade-offs, a recommendation. **No file changes** while discussing, not even docs.
2. **Document**, only when the user confirms (e.g. "add it", "add to the doc/roadmap"): write the agreed design into the right design doc and `doc/03_roadmap.md` (Phase 8, "Improvements from dogfooding"), marked planned. Ending a discussion with "should I add this to the docs?" is fine; adding it without a yes is not.
3. **Implement**, only when the user says so (e.g. "implement it"). Do not touch code before that.

- Answering a question may require reading or searching the repo; that is fine. Editing is not.
- When implementing: code + tests + README + design doc status ("implemented") + roadmap checkboxes, in the same change.
- If the implementation deviates from the doc (a better or necessary choice), update the doc and say so.
- The user stages files and asks for commits. Commit only what is staged; message describes the code change only.

## Layout

| Path | What |
|---|---|
| `lib.zsh` | Everything sourced by `~/.zshrc`: key, lookups, run, env, theme, CLI |
| `bin/aliprehook_env_pass` | POSIX `sh` helper put on every hook's `PATH` |
| `themes/*.theme` | `role=code` color files (`purple` default, `none`) |
| `templates/` | Initial user files (`hooks.map`, `commands.map`, `allowed-repos`) |
| `install.sh` / `uninstall.sh` | Dev install (symlink or `--copy`) / removal; never delete user data |
| `examples/project/` | Example project layer |
| `tests/` | `test_*.zsh`, run by `zsh tests/run.zsh` |
| `doc/01` system design, `02` positioning, `03` roadmap, `04` hook env, `05` theme, `06` commands.map, `07` CLI, `08` run summary, `09` wrapping real commands, `10` explain | |

User files: `hooks.map`, `commands.map`, `allowed-repos`, `theme-overrides`, `settings`, `hooks/`. Never overwrite or remove them from install/uninstall.

## Portability: Linux and macOS

Every change must work on **both Linux (GNU tools) and macOS (BSD tools, `/bin/zsh` 5.8+, `/bin/sh` = bash 3.2 in POSIX mode)**. GNU tools are lenient, so a Linux-only test run hides these bugs. Past bugs: `stat -c` in a test (GNU only), `chmod +x -- file` (BSD reads `--` after the mode as a file name).

Rules:

- **Prefer zsh builtins** over external tools: `zstat` (`zmodload -F zsh/stat b:zstat`) for modes/mtime, `${file:A}` / `${file:a}` instead of `readlink -f` / `realpath`, `${var:t}` / `${var:h}` instead of `basename` / `dirname`, globbing instead of `find` where possible.
- **External commands:** only options that exist in both GNU and BSD. Known traps:
  - `stat -c` (GNU) vs `stat -f` (BSD): use `zstat`, or `ls -ln … | cut -c1-10` in sh.
  - `sed -i` differs (`-i ''` on BSD): never edit files with `sed -i` in code or tests; rewrite via temp file + `mv`.
  - `--` must come **before** the operands of every option-taking argument and before a mode: `chmod -- +x "$f"`, `cp -p -- "$a" "$b"`. BSD tools stop option parsing at the first operand.
  - `readlink -f`, `date -d`, `grep -P`, `find -perm /mode`, `base64 -w`, `xargs -r`, `cp --…` long options: not on macOS.
  - `mktemp`: use `mktemp -d` / `mktemp "$dir/x.XXXXXX"` with an explicit template.
- **POSIX sh** (`bin/aliprehook_env_pass`, hooks we ship, `install.sh`, `uninstall.sh`): no bashisms (no `[[`, arrays, `local`, `$'…'`, `echo -e`); `printf` over `echo` for data.
- **macOS paths:** `$TMPDIR` is under `/var/folders`, a symlink to `/private/var/…`. In tests, resolve temp dirs with `tmp=${tmp:A}` before comparing paths.
- **Case-insensitive filesystem** on macOS by default: never rely on two names differing only in case.
- Tests must not depend on the user's environment: `tests/helpers.zsh` sets `ALIPREHOOK_VERBOSE=quiet`; tests set `ALIPREHOOK_HOME`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, and anything else they compare on (colors, editor) explicitly.
- When adding a tool call, check its man page on both systems; when unsure, use a zsh builtin.

## Code rules (lib.zsh)

- Every function starts with `emulate -L zsh` (add `-o extended_glob` when using `#`, `##`, `(#b)`). Exceptions: functions that `eval` a user's command line, which must run with the user's options.
- **All output through `_aliprehook_msg [-n] [-1|-2] <level> <part>…`** (`info`, `success`, `warning`, `error`, `trace`); parts are text or `@role=text`. Never hard-code colors. Every failure says `error:`, every non-fatal problem `warning:`. Hints as `@hint=(run: …)`.
- **Names, never values** of variables in any message.
- **No ghost behaviour:** anything that changes what runs (a hook, a passed variable, a `commands.map` line, a skipped step) must show up in the run summary (`ALIPREHOOK_VERBOSE=summary`: what will run, announced before any hook runs; passed variables after the hooks) and in `detail` (one line per step, with the reason for skips), via `_aliprehook_trace` / `_aliprehook_trace_detail`. `quiet` prints nothing but warnings and errors. See `doc/08_run-summary.md`.
- **Parse, never source** user or repo files (`hooks.map`, `commands.map`, `settings`, themes, `.aliprehook.yml`, env files).
- **Writing user files:** `_aliprehook_write_lines` (temp file next to the target + `mv`, follows symlinks, keeps permissions, keeps comments and other lines). `commands.map` must never be group/world-writable.
- **Security model:** shell code (`commands.map` lines) only from the user layer; repos (`.aliprehook.yml`) never define `*` hooks, commands, or protected env names (denylist); project hooks never see user-hook variables.
- **Semantics to keep consistent:** hooks add up (every match runs, `*` lines first); commands replace (exactly one runs, no `*` in `commands.map`); user layer wins over project layer.
- Call external tools with `command` (`command git`) so user functions or wrappers of the same name are never hit.
- Wrappers generated by `aliprehook_define` must keep working when the main command is an alias or function (main command stays in command position).

## CLI conventions

- `aliprehook <group> <sub> …`; required values positional, optional ones as `--opt value` (also `--opt=value`).
- Project selection: `--path <dir>`, `--key <key>`, `--all` (`*`, hooks only), at most one.
- Every group and subcommand has `--help` with usage, options and an example; `aliprehook help` lists all. Wrong calls: `error:`, usage line, `(see: aliprehook <group> help)`, exit 2, nothing changed.
- Every change prints what it did. Exit codes: 0 ok, 1 nothing to do / failed, 2 usage error.

## Tests

- `zsh tests/run.zsh` runs each `tests/test_*.zsh` in a fresh `zsh -f`. Plain zsh scripts using `tests/helpers.zsh` (`assert_eq expected actual message`, `fail`, `finish`).
- Each test uses its own `mktemp -d` dir (removed by `trap`) and `ALIPREHOOK_HOME`; never touch the real `~/.config/aliprehook`.
- Test new behaviour, error paths and messages; after writing tests, break the code on purpose (mutation check) to confirm a test fails.
- Before saying "done": the full suite passes. Mention that macOS was not run when changes touch external tools, so the user can run it there.

## Docs

- README: user-facing, numbered sections, only implemented behaviour (planned features go in `doc/`).
- Design docs start with a status line (`planned, not implemented` / `implemented (Phase N)`); keep examples consistent with real output.
- Generic placeholders only (`github.com/org/sample_app_web`); no real company, repo or personal names.
