# Output theme

Design for colored aliprehook messages with one central, swappable theme. Default theme: **purple**. Work items: [03_roadmap.md](./03_roadmap.md) Phase 6.

## Goals

- One place defines every color; changing the theme never means editing message code.
- Same look from `lib.zsh` (zsh) and `bin/aliprehook_env_pass` (POSIX sh).
- Purple identity, but errors and warnings stay instantly recognizable.
- Never breaks scripts, logs or pipes: color only when it is safe.

## Purple palette

Every color has **one meaning**. Purple marks aliprehook itself; status uses the same basic terminal colors as Oh My Zsh's `robbyrussell` theme; each kind of item gets its own color, so a message can be read at a glance.

| Role | Meaning | Example | Color | Code |
|---|---|---|---|---|
| `brand` | "This message is from aliprehook" | `aliprehook:` | Orchid, bold | `1;38;5;177` |
| `info` | Text of informational messages, nothing wrong | `project hooks from … will now run` | Default text color | (empty) |
| `success` | It worked | `allowed-repos`, `revoked` | Green, bold (robbyrussell success `➜`) | `1;32` |
| `warning` | Look, but the command continues | `warning:` and the warning's text | Yellow (robbyrussell dirty `✗`) | `33` |
| `error` | Stopped; the command did not run | `error:`, `aborted` and the error's text | Red (robbyrussell failure `➜`) | `31` |
| `command` | The command you typed | `Dup` | Green, bold (same as `success`) | `1;32` |
| `hook` | A script that runs | `sample_app_web_Dup.sh` | Cyan (robbyrussell directory) | `36` |
| `key` | Where: project key or path | `github.com/org/sample_app_web` | Blue (robbyrussell `git:`) | `34` |
| `var` | A variable name | `API_TOKEN` | Bold, default text color | `1` |
| `hint` | Optional advice, how to fix | `(run: chmod +x …)` | Grey | `90` |
| `trace` | What aliprehook did (run summary, [08_run-summary.md](./08_run-summary.md)) | `hooks: aws_login.sh · env: API_TOKEN` | Grey (same as `hint`) | `90` |

Design rules:

- **Purple only in the prefix:** bold orchid `aliprehook:` is the single purple, so purple always means "aliprehook speaking".
- **Message text takes its level's color:** an informational message is in the default color, a warning's text is yellow, an error's text is red (including `aborted`). Labels (`warning:`, `error:`) are the same color in bold. Named items inside a message (command, hook, key, variable) always keep their own colors.
- **Every failure says `error:`**, every non-fatal problem says `warning:`.
- **Status colors are the basic 16 terminal colors** (`31` red, `32` green, `33` yellow), like robbyrussell. They follow the user's terminal color scheme, so they match the prompt and are never harsher than the terminal's own red/yellow.
- **Items differ by hue, not shade:** command (green), hook (cyan), key (blue), variable (bold) never look alike. Command shares bold green with `success` on purpose: both are "the good path you asked for".

Example (roles in brackets; unmarked text uses the default color):

```text
[brand]aliprehook:[/] [warning]warning:[/] [hook]sample_app_web_Dup.sh[/][warning]:[/] [var]DEBUG_LEVEL[/] [warning]has no value; not passed to[/] [command]Dup[/]
[brand]aliprehook:[/] [error]error:[/] [hook]sample_app_web_Dup.sh[/][error]:[/] [var]API_TOKEN[/] [error]has no value (required)[/]
[brand]aliprehook:[/] [command]Dup[/] [error]aborted: required variable missing:[/] [var]API_TOKEN[/]
[brand]aliprehook:[/] [error]error: hook not executable:[/] [key]~/.config/aliprehook/hooks/x.sh[/] [hint](run: chmod +x …)[/]
[brand]aliprehook:[/] [success]allowed[/] [key]github.com/org/sample_app_web[/]
[brand]aliprehook:[/] project hooks from [key]…/.aliprehook.yml[/] will now run
```

## Central definition

Themes are plain `role=code` files, readable by both zsh and sh (parsed, never sourced):

```text
# themes/purple.theme
brand=1;38;5;177
info=
success=1;32
warning=33
error=31
command=1;32
hook=36
key=34
var=1
hint=90
trace=90
```

- Values are ANSI SGR parameters (what goes between `\e[` and `m`); empty means default color.
- `warning:` / `error:` labels are drawn with the role's color plus bold; the message text uses the role's color as is.
- Shipped themes live in `themes/` next to `lib.zsh`: `purple` (default) and `none` (no colors).
- A missing role falls back to no color, so a partial theme still works.

Choosing a theme:

| Setting | Effect |
|---|---|
| `ALIPREHOOK_THEME=purple` | Shipped theme by name (default) |
| `ALIPREHOOK_THEME=/path/to/my.theme` | Your own file |
| `~/.config/aliprehook/theme-overrides` | User overrides on top of the chosen theme (only the roles listed) |

A new `ALIPREHOOK_THEME` value takes effect on the next message; edits to theme files take effect in a new shell (or after `source ~/.zshrc`).

## One message function per side

All output goes through one function, so no message hard-codes a color:

- zsh: `_aliprehook_msg [-n] [-1|-2] <level> <part>...` in `lib.zsh`. Levels: `info`, `success`, `warning`, `error`. A part is plain text (drawn in the level's color) or `@role=text` for a named item (`@command=`, `@hook=`, `@key=`, `@var=`, `@hint=`, `@success=`), which keeps its own color. `-n` drops the `warning:`/`error:` label (used for `… aborted: …`). Warnings and errors go to stderr, info and success to stdout.
- sh: `msg <level> <part>...` in `bin/aliprehook_env_pass`, same part syntax.

```zsh
_aliprehook_msg error "user hook not executable: " "@key=$hook" " " "@hint=(run: chmod +x $hook)"
```

`lib.zsh` loads the theme on first use. Hooks run as separate programs, so aliprehook passes the resolved theme to them in `ALIPREHOOK_THEME_CODES` (`role=code ...`) and the color setting in `ALIPREHOOK_COLOR`; `aliprehook_env_pass` uses those instead of reading files, so its messages look exactly like `lib.zsh`'s.

## When to color

Color is used only if all of these hold:

1. stderr is a terminal (`[[ -t 2 ]]`); pipes, logs and `$(…)` captures stay plain
2. `NO_COLOR` is not set (see <https://no-color.org>)
3. `ALIPREHOOK_COLOR` is not `never` (`always` forces color, e.g. for screenshots; default `auto`)
4. `TERM` is not `dumb`

Words like `warning:` and `error:` are always printed, so meaning never depends on color alone (color-blind users, plain logs).

## Out of scope

- Truecolor (24-bit) themes: possible later as a theme value (`38;2;175;95;255`), not needed for v1
- Coloring hook output: hooks print what they print
- Icons / emoji
