# aliprehook: optional prehooks for opt-in shell commands.
# Load from ~/.zshrc:
#   source ~/.config/aliprehook/lib.zsh

typeset -g ALIPREHOOK_VERSION=0.0.0
typeset -g ALIPREHOOK_HOME=${ALIPREHOOK_HOME:-$HOME/.config/aliprehook}
# Directory of this file (symlinks resolved); bin/ next to it holds hook helpers.
typeset -g ALIPREHOOK_LIB_DIR=${${(%):-%x}:A:h}

# Variables hooks passed via ALIPREHOOK_ENV_FILE, consumed by aliprehook_with_env.
typeset -gA _aliprehook_env_user _aliprehook_env_project _aliprehook_env

# Names project hooks may not pass (patterns).
typeset -ga _aliprehook_env_denylist
_aliprehook_env_denylist=(PATH 'LD_*' 'DYLD_*' BASH_ENV ENV ZDOTDIR IFS PS4
  PROMPT_COMMAND HOME SHELL GIT_SSH_COMMAND GIT_EXEC_PATH)
typeset -gi _aliprehook_env_max_bytes=65536 _aliprehook_env_max_vars=100

# --- Output theme -----------------------------------------------------------
# Colors come from one theme file (themes/<name>.theme, or a path in
# ALIPREHOOK_THEME), with single roles overridden by ALIPREHOOK_HOME/theme-overrides.
# No message hard-codes a color: everything goes through _aliprehook_msg.
typeset -gA _aliprehook_theme
typeset -g _aliprehook_theme_key=

# Parse role=code lines from a theme file into _aliprehook_theme (never sourced).
_aliprehook_theme_read() {
  emulate -L zsh -o extended_glob
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%\#*}
    if [[ $line == [[:space:]]#(#b)([a-z_]##)[[:space:]]#=[[:space:]]#([0-9\;]#)[[:space:]]# ]]; then
      _aliprehook_theme[$match[1]]=$match[2]
    fi
  done < $1
}

# Load the theme if ALIPREHOOK_THEME or ALIPREHOOK_HOME changed since last time.
_aliprehook_theme_ensure() {
  emulate -L zsh
  local name=${ALIPREHOOK_THEME:-purple} file
  [[ "$name|$ALIPREHOOK_HOME" == "$_aliprehook_theme_key" ]] && return 0
  _aliprehook_theme_key="$name|$ALIPREHOOK_HOME"
  _aliprehook_theme=()
  if [[ $name == */* ]]; then
    file=$name
  else
    file=$ALIPREHOOK_LIB_DIR/themes/$name.theme
  fi
  if [[ -r $file ]]; then
    _aliprehook_theme_read $file
  else
    print -u2 "aliprehook: warning: theme not found: $file (using no colors)"
  fi
  [[ -r $ALIPREHOOK_HOME/theme-overrides ]] && _aliprehook_theme_read $ALIPREHOOK_HOME/theme-overrides
  return 0
}

# Exit 0 if output on file descriptor <fd> should be colored.
_aliprehook_color_on() {
  case ${ALIPREHOOK_COLOR:-auto} in
    always) return 0 ;;
    never) return 1 ;;
  esac
  [[ -z ${NO_COLOR-} && ${TERM-} != dumb && -t $1 ]]
}

# Append <text> in color <code> to the caller's $out (zsh dynamic scope).
_aliprehook_paint() {
  if (( color )) && [[ -n $1 ]]; then
    out+=$'\e['"$1"m"$2"$'\e[0m'
  else
    out+=$2
  fi
}

# Print one message:  _aliprehook_msg [-n] [-1|-2] <level> <part>...
#   level  info | success | warning | error
#   part   plain text (drawn in the level's color: info/success default,
#          warning yellow, error red) or @role=text for a named item
#          (@command= @hook= @key= @var= @hint= @success=), which keeps its
#          own color. Parts are joined as given (include spaces yourself).
#   -n     no "warning:" / "error:" label
#   -1/-2  force stdout/stderr (default: warning/error → stderr, else stdout)
_aliprehook_msg() {
  emulate -L zsh -o extended_glob
  local label=1 fd= level part out= tcode
  integer color=0
  while [[ $1 == -[n12] ]]; do
    case $1 in
      -n) label=0 ;;
      -1) fd=1 ;;
      -2) fd=2 ;;
    esac
    shift
  done
  level=$1
  shift
  if [[ -z $fd ]]; then
    [[ $level == (warning|error|trace) ]] && fd=2 || fd=1
  fi
  _aliprehook_theme_ensure
  _aliprehook_color_on $fd && color=1
  tcode=
  [[ $level == (warning|error|trace) ]] && tcode=${_aliprehook_theme[$level]-}

  _aliprehook_paint "${_aliprehook_theme[brand]-}" aliprehook:
  out+=' '
  if (( label )) && [[ $level == (warning|error) ]]; then
    _aliprehook_paint "${tcode:+1;$tcode}" "$level:"
    out+=' '
  fi
  for part in "$@"; do
    if [[ $part == '@'(#b)([a-z]##)=(*) ]]; then
      _aliprehook_paint "${_aliprehook_theme[$match[1]]-}" "$match[2]"
    else
      _aliprehook_paint "$tcode" "$part"
    fi
  done
  print -u$fd -r -- $out
}

# The resolved theme as "role=code ..." for hooks (aliprehook_env_pass).
_aliprehook_theme_codes() {
  emulate -L zsh
  _aliprehook_theme_ensure
  local k
  local -a pairs
  for k in ${(k)_aliprehook_theme}; do
    pairs+=("$k=${_aliprehook_theme[$k]}")
  done
  print -r -- "${pairs[*]}"
}

# Normalize a git remote URL to host/path form, e.g.
#   git@github.com:org/repo.git -> github.com/org/repo
# Prints the result; returns 1 on empty input.
aliprehook_normalize_remote() {
  emulate -L zsh -o extended_glob
  local url=$1 host rest

  [[ -n $url ]] || return 1

  if [[ $url == [A-Za-z][A-Za-z0-9+.-]#://* ]]; then
    # scheme://[userinfo@]host/path
    url=${url#*://}
    host=${url%%/*}
    rest=${url#$host}
    host=${host##*@}
  elif [[ $url == [^/]#:* ]]; then
    # SCP-style [user@]host:path
    host=${url%%:*}
    rest=/${url#*:}
    host=${host##*@}
  else
    # No host (e.g. local path): only trim the end.
    host=
    rest=$url
  fi

  while [[ $rest == */ || $rest == *.git ]]; do
    rest=${rest%/}
    rest=${rest%.git}
  done

  print -r -- "${host:l}$rest"
}

# Print the project key for the current directory:
# normalized origin URL, else first fetch remote, else `pwd -P`.
aliprehook_project_key() {
  emulate -L zsh -o extended_glob
  local url

  if [[ $(command git rev-parse --is-inside-work-tree 2>/dev/null) == true ]]; then
    url=$(command git remote get-url origin 2>/dev/null)
    if [[ -z $url ]]; then
      url=$(command git remote -v 2>/dev/null | while read -r _ u kind; do
        [[ $kind == '(fetch)' ]] && { print -r -- $u; break; }
      done)
    fi
    if [[ -n $url ]]; then
      aliprehook_normalize_remote $url
      return
    fi
  fi

  pwd -P
}

# Print every hook registered for (project key, command), one path per line:
# `*` lines first, then lines for the exact key; file order within each group.
# The same (key, command, hook) line listed twice is printed once.
# Relative paths are under ALIPREHOOK_HOME. Returns 1 if nothing matches.
# --mark (3rd argument): print "*<TAB>path" for * lines, "<TAB>path" otherwise.
aliprehook_registry_lookup() {
  emulate -L zsh -o extended_glob
  local key=$1 cmd=$2 k c h id
  local registry=$ALIPREHOOK_HOME/hooks.map
  local -a common exact
  local -A seen

  [[ -r $registry ]] || return 1

  while read -r k c h _; do
    [[ -z $k || $k == \#* ]] && continue
    [[ $c == "$cmd" && -n $h ]] || continue
    [[ $k == '*' || $k == "$key" ]] || continue
    id="$k"$'\t'"$h"
    (( ${+seen[$id]} )) && continue
    seen[$id]=1
    [[ $h == /* ]] || h=$ALIPREHOOK_HOME/$h
    if [[ $k == '*' ]]; then
      common+=($h)
    else
      exact+=($h)
    fi
  done < $registry

  (( $#common + $#exact )) || return 1
  if [[ $3 == --mark ]]; then
    print -rl -- ${common/#/*$'\t'} ${exact/#/$'\t'}
  else
    print -rl -- $common $exact
  fi
}

# Exit 0 if <key> is listed in ALIPREHOOK_HOME/allowed-repos.
aliprehook_is_allowed() {
  emulate -L zsh -o extended_glob
  local key=$1 line
  local allowed=$ALIPREHOOK_HOME/allowed-repos

  [[ -n $key && -r $allowed ]] || return 1
  while read -r line; do
    [[ $line == "$key" ]] && return 0
  done < $allowed
  return 1
}

# Print every entry under `hooks:` in <root>/.aliprehook.yml as
# "<line>\t<name>\t<value>". Minimal parser for:
#   hooks:
#     Dup: .aliprehook/before_Dup.sh
_aliprehook_project_entries() {
  emulate -L zsh -o extended_glob
  local root=$1 line name value in_hooks=0
  local yml=$root/.aliprehook.yml
  integer n=0

  [[ -r $yml ]] || return 1

  while IFS= read -r line || [[ -n $line ]]; do
    (( n++ ))
    line=${line%%[[:space:]]##\#*}       # inline comment
    [[ $line == [[:space:]]#(\#*|) ]] && continue
    if [[ $line != [[:space:]]* ]]; then  # top-level key
      [[ $line == hooks:[[:space:]]# ]] && in_hooks=1 || in_hooks=0
      continue
    fi
    (( in_hooks )) || continue
    [[ $line == [[:space:]]##(#b)([^:[:space:]]##):[[:space:]]#(*) ]] || continue
    name=$match[1]
    value=${match[2]%%[[:space:]]#}
    [[ $name == \"*\" || $name == \'*\' ]] && name=${${name#?}%?}
    [[ $value == \"*\" || $value == \'*\' ]] && value=${${value#?}%?}
    print -r -- "$n"$'\t'"$name"$'\t'"$value"
  done < $yml
}

# Print problems in <root>/.aliprehook.yml, one per line. Exit 1 if any.
# `*` (all-projects) hooks are hooks.map only: a repo must not define them.
aliprehook_project_check() {
  emulate -L zsh -o extended_glob
  local root=$1 entry n name value
  local -a problems

  for entry in "${(@f)$(_aliprehook_project_entries $root)}"; do
    [[ -n $entry ]] || continue
    n=${entry%%$'\t'*}; entry=${entry#*$'\t'}
    name=${entry%%$'\t'*}; value=${entry#*$'\t'}
    if [[ $name == '*' ]]; then
      problems+=(".aliprehook.yml:$n: '*' hooks are not allowed in a repo; only in your own $ALIPREHOOK_HOME/hooks.map")
    elif [[ $name != [A-Za-z_][A-Za-z0-9_-]# ]]; then
      problems+=(".aliprehook.yml:$n: invalid command name: $name")
    elif [[ -z $value ]]; then
      problems+=(".aliprehook.yml:$n: missing hook path for $name")
    fi
  done

  (( $#problems )) || return 0
  print -rl -- $problems
  return 1
}

# Print the hook path for <cmd> from <root>/.aliprehook.yml, if any.
# Invalid entries (e.g. `*`) never match.
aliprehook_project_lookup() {
  emulate -L zsh -o extended_glob
  local root=$1 cmd=$2 entry name value

  [[ $cmd == [A-Za-z_][A-Za-z0-9_-]# ]] || return 1
  for entry in "${(@f)$(_aliprehook_project_entries $root)}"; do
    entry=${entry#*$'\t'}
    name=${entry%%$'\t'*}; value=${entry#*$'\t'}
    if [[ $name == "$cmd" && -n $value ]]; then
      print -r -- $value
      return 0
    fi
  done
  return 1
}

# Warn if <root>/.aliprehook.yml has a `commands:` section: per-project
# command lines are shell code, so only the user's commands.map may set them.
_aliprehook_project_commands_warn() {
  emulate -L zsh -o extended_glob
  local root=$1 line
  local yml=$root/.aliprehook.yml
  [[ -r $yml ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == commands:[[:space:]]#(\#*|) ]]; then
      _aliprehook_msg warning "@key=$yml" ": commands: section ignored; per-project commands go in your own " "@key=$ALIPREHOOK_HOME/commands.map"
      return 0
    fi
  done < $yml
}

# --- Per-project commands ---------------------------------------------------
# ALIPREHOOK_HOME/commands.map: "project_key  command  rest-of-line (shell syntax)".
# Print "<line number><TAB><command line>" for <cmd> in the current project.
# Exit 0 if found, 1 if none
# (use the default), 2 on an error (already reported; do not run anything).
_aliprehook_command_lookup() {
  emulate -L zsh -o extended_glob
  local cmd=$1 key k c rest line found file=$ALIPREHOOK_HOME/commands.map
  integer n=0 at=0 bad=0
  local -a st

  [[ -e $file ]] || return 1
  if [[ ! -f $file || ! -r $file ]]; then
    _aliprehook_msg error "cannot read " "@key=$file"
    return 2
  fi
  zmodload -F zsh/stat b:zstat 2>/dev/null
  if ! zstat -A st +mode -- $file 2>/dev/null; then
    _aliprehook_msg error "cannot check permissions of " "@key=$file"
    return 2
  fi
  if (( st[1] & 8#022 )); then
    _aliprehook_msg error "@key=$file" " is writable by group or others; ignored " "@hint=(run: chmod go-w $file)"
    _aliprehook_msg -n error "@command=$cmd" " aborted"
    return 2
  fi

  key=$(aliprehook_project_key)
  while IFS= read -r line || [[ -n $line ]]; do
    (( n++ ))
    [[ $line == [[:space:]]#(\#*|) ]] && continue
    [[ $line == [[:space:]]#(#b)([^[:space:]]##)[[:space:]]##([^[:space:]]##)(*) ]] || continue
    k=$match[1] c=$match[2] rest=$match[3]
    [[ $c == "$cmd" ]] || continue
    rest=${${rest##[[:space:]]#}%%[[:space:]]#}
    if [[ $k == '*' ]]; then
      _aliprehook_msg error "@key=$file:$n" ": '*' is not allowed in commands; change the default in " "@hint=aliprehook_define $cmd …" " instead"
      bad=1
      continue
    fi
    [[ $k == "$key" ]] || continue
    if [[ -z $rest ]]; then
      _aliprehook_msg error "@key=$file:$n" ": no command line for " "@command=$cmd"
      bad=1
    elif (( at )); then
      _aliprehook_msg warning "@key=$file:$n" ": duplicate line for " "@command=$cmd" " in this project; using line $at"
    else
      found=$rest at=$n
    fi
  done < $file

  if (( bad )); then
    _aliprehook_msg -n error "@command=$cmd" " aborted: fix " "@key=$file"
    return 2
  fi
  (( at )) || return 1
  print -r -- "$at"$'\t'"$found"
}

# Run command line <line> in a subshell with the remaining arguments: appended
# as "$@", unless the line uses $@ / $* itself. No emulate: the line runs with
# your shell's options, as if typed.
_aliprehook_command_eval() {
  local _aliprehook_l=$1
  shift
  case $_aliprehook_l in
    (*'$@'*|*'${@}'*|*'$*'*|*'${*}'*) ( eval "$_aliprehook_l" ) ;;
    (*) ( eval "$_aliprehook_l \"\$@\"" ) ;;
  esac
}

# For hand-written functions (README Case B), after aliprehook_run:
#   aliprehook_command [--keep-env] <name> <default command...> -- "$@"
# Runs this project's line from commands.map, else the default; either
# way with the arguments after `--` and the variables the hooks passed.
aliprehook_command() {
  local _aliprehook_keep= _aliprehook_name _aliprehook_line
  local -a _aliprehook_def
  if [[ $1 == --keep-env ]]; then
    _aliprehook_keep=--keep-env
    shift
  fi
  _aliprehook_name=$1
  (( $# )) && shift
  while (( $# )) && [[ $1 != -- ]]; do
    _aliprehook_def+=("$1")
    shift
  done
  (( $# )) && shift
  if [[ -z $_aliprehook_name || $#_aliprehook_def -eq 0 ]]; then
    _aliprehook_msg error "usage: aliprehook_command [--keep-env] <name> <default command...> -- \"\$@\""
    return 2
  fi

  _aliprehook_line=$(_aliprehook_command_lookup $_aliprehook_name)
  (( $? < 2 )) || return 1
  _aliprehook_env_decl $_aliprehook_keep
  eval "$_aliprehook_env_code"
  _aliprehook_trace_command $_aliprehook_name "$_aliprehook_line" "${(j: :)${(q-)_aliprehook_def}}" "$@"
  if [[ -n $_aliprehook_line ]]; then
    _aliprehook_command_eval "${_aliprehook_line#*$'\t'}" "$@"
  else
    "${_aliprehook_def[@]}" "$@"
  fi
}

# Create a private (0600) temp file for one hook's variables. Prints its path.
_aliprehook_tmpfile() {
  emulate -L zsh
  local dir=${XDG_RUNTIME_DIR:-}
  [[ -n $dir && -d $dir && -w $dir ]] || dir=${TMPDIR:-/tmp}
  (umask 077; command mktemp "${dir%/}/aliprehook.XXXXXXXX")
}

# "<cmd> aborted: required variable missing: A, B" (names deduplicated).
_aliprehook_msg_missing() {
  emulate -L zsh
  local cmd=$1 v
  shift
  local -a names parts
  names=(${(u)@})
  for v in $names; do
    (( $#parts )) && parts+=(", ")
    parts+=("@var=$v")
  done
  _aliprehook_msg -n error "@command=$cmd" " aborted: required variable missing: " $parts
}

# Parse a hook's ALIPREHOOK_ENV_FILE into _aliprehook_env_<layer>.
# Never sources the file. Returns 1 (command must not run) on any problem.
_aliprehook_env_load() {
  emulate -L zsh -o extended_glob
  local layer=$1 cmd=$2 hook=$3 file=$4 line name value delim pat
  integer n=0 closed
  local -a missing order
  local -A vars

  _aliprehook_last_passed=()
  [[ -s $file ]] || return 0
  if (( $(command wc -c < $file) > _aliprehook_env_max_bytes )); then
    _aliprehook_msg error "@hook=${hook:t}" ": ALIPREHOOK_ENV_FILE is larger than $_aliprehook_env_max_bytes bytes"
    return 1
  fi

  while IFS= read -r line || [[ -n $line ]]; do
    (( n++ ))
    [[ -z $line ]] && continue
    if [[ $line == '!required-missing '* ]]; then
      missing+=(${line#* })
      continue
    fi
    if [[ $line == (#b)([A-Za-z_][A-Za-z0-9_]#)'<<'(?##) ]]; then
      name=$match[1] delim=$match[2] value= closed=0
      local -a block=()
      while IFS= read -r line; do
        (( n++ ))
        if [[ $line == "$delim" ]]; then closed=1; break; fi
        block+=("$line")
      done
      if (( ! closed )); then
        _aliprehook_msg error "@hook=${hook:t}" ": ALIPREHOOK_ENV_FILE: " "@var=$name" "<<$delim block is not closed"
        return 1
      fi
      value=${(pj:\n:)block}
    elif [[ $line == (#b)([A-Za-z_][A-Za-z0-9_]#)=(*) ]]; then
      name=$match[1] value=$match[2]
    else
      _aliprehook_msg error "@hook=${hook:t}" ": ALIPREHOOK_ENV_FILE: line $n: expected NAME=value"
      return 1
    fi

    if [[ $name == ALIPREHOOK_* ]]; then
      _aliprehook_msg error "@hook=${hook:t}" ": ALIPREHOOK_ENV_FILE: line $n: reserved variable name: " "@var=$name"
      return 1
    fi
    if [[ $layer == project ]]; then
      for pat in $_aliprehook_env_denylist; do
        if [[ $name == ${~pat} ]]; then
          _aliprehook_msg error "@hook=${hook:t}" ": ALIPREHOOK_ENV_FILE: line $n: project hooks may not set " "@var=$name"
          return 1
        fi
      done
    fi
    (( ${+vars[$name]} )) || order+=($name)
    vars[$name]=$value
  done < $file

  if (( ${#vars} > _aliprehook_env_max_vars )); then
    _aliprehook_msg error "@hook=${hook:t}" ": ALIPREHOOK_ENV_FILE: more than $_aliprehook_env_max_vars variables"
    return 1
  fi
  if (( $#missing )); then
    _aliprehook_msg_missing $cmd $missing
    return 1
  fi

  for name in ${(k)vars}; do
    if [[ $layer == user ]]; then
      _aliprehook_env_user[$name]=$vars[$name]
    else
      _aliprehook_env_project[$name]=$vars[$name]
    fi
  done
  _aliprehook_last_passed=($order)
  return 0
}

# Run one hook with the aliprehook environment. Returns its exit code,
# or 1 if the variables it passed are invalid or a required one is missing.
_aliprehook_exec() {
  emulate -L zsh
  local layer=$1 key=$2 cmd=$3 hook=$4 rc envfile k
  shift 4

  if [[ ! -f $hook ]]; then
    _aliprehook_msg error "$layer hook not found: " "@key=$hook"
    return 1
  fi
  if [[ ! -x $hook ]]; then
    _aliprehook_msg error "$layer hook not executable: " "@key=$hook" " " "@hint=(run: chmod +x $hook)"
    return 1
  fi
  if ! envfile=$(_aliprehook_tmpfile); then
    _aliprehook_msg error "cannot create a temp file for " "@key=$hook"
    return 1
  fi

  {
    (
      # User hooks see variables passed by earlier user hooks; project hooks do not.
      if [[ $layer == user ]]; then
        for k in ${(k)_aliprehook_env_user}; do
          export "$k=${_aliprehook_env_user[$k]}"
        done
      fi
      export ALIPREHOOK_PROJECT_KEY=$key ALIPREHOOK_COMMAND=$cmd ALIPREHOOK_HOOK=$hook \
        ALIPREHOOK_ENV_FILE=$envfile \
        ALIPREHOOK_ENV_PASS_BIN=$ALIPREHOOK_LIB_DIR/bin/aliprehook_env_pass \
        ALIPREHOOK_THEME_CODES="$(_aliprehook_theme_codes)" \
        ALIPREHOOK_COLOR=${ALIPREHOOK_COLOR:-auto} \
        PATH=$ALIPREHOOK_LIB_DIR/bin:$PATH
      exec $hook "$@"
    )
    rc=$?
    if (( rc != 0 )); then
      local -a missing
      local line
      while IFS= read -r line; do
        [[ $line == '!required-missing '* ]] && missing+=(${line#* })
      done < $envfile
      if (( $#missing )); then
        _aliprehook_msg_missing $cmd $missing
      else
        _aliprehook_msg -n error "@command=$cmd" " aborted: $layer hook exited $rc (" "@key=$hook" ")"
      fi
      return $rc
    fi
    _aliprehook_env_load $layer $cmd $hook $envfile
  } always {
    command rm -f -- $envfile
  }
}

# --- Run summary (ALIPREHOOK_VERBOSE / settings) -----------------------------
# Design: doc/08_run-summary.md. What the current run did, for the summary line.
typeset -g _aliprehook_trace_level=summary _aliprehook_trace_source=default
typeset -ga _aliprehook_trace_hooks _aliprehook_trace_env _aliprehook_trace_kept _aliprehook_last_passed
typeset -gA _aliprehook_settings _aliprehook_verbose_warned

# Load ALIPREHOOK_HOME/settings (name=value lines, parsed, never sourced).
# Read on every command (a tiny file), so a save from another shell applies
# right away; mtime alone misses two saves within one second.
_aliprehook_settings_load() {
  emulate -L zsh -o extended_glob
  local file=$ALIPREHOOK_HOME/settings line
  _aliprehook_settings=()
  [[ -r $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == [[:space:]]#(\#*|) ]] && continue
    [[ $line == [[:space:]]#(#b)([a-z_]##)[[:space:]]#=[[:space:]]#(*) ]] || continue
    _aliprehook_settings[$match[1]]=${match[2]%%[[:space:]]#}
  done < $file
}

# Set _aliprehook_trace_level / _aliprehook_trace_source:
# ALIPREHOOK_VERBOSE → settings (verbose=) → summary.
_aliprehook_verbose_resolve() {
  emulate -L zsh
  local v src
  if [[ -n ${ALIPREHOOK_VERBOSE-} ]]; then
    v=$ALIPREHOOK_VERBOSE src=env
  else
    _aliprehook_settings_load
    v=${_aliprehook_settings[verbose]-} src=settings
    [[ -n $v ]] || v=summary src=default
  fi
  if [[ $v != (quiet|summary|detail) ]]; then
    if (( ! ${+_aliprehook_verbose_warned[$src:$v]} )); then
      _aliprehook_verbose_warned[$src:$v]=1
      local where=ALIPREHOOK_VERBOSE
      [[ $src == settings ]] && where=$ALIPREHOOK_HOME/settings
      _aliprehook_msg warning "invalid verbose level '$v' in " "@key=$where" "; using summary " "@hint=(levels: quiet, summary, detail)"
    fi
    v=summary
  fi
  _aliprehook_trace_level=$v _aliprehook_trace_source=$src
}

# One trace line (theme role `trace`, stderr).
_aliprehook_trace() { _aliprehook_msg trace "$@"; }
_aliprehook_trace_detail() { [[ $_aliprehook_trace_level == detail ]] && _aliprehook_msg trace "$@"; return 0; }

# Remember names passed by the last hook (run order, once each).
_aliprehook_trace_add_passed() {
  local n
  for n in $_aliprehook_last_passed; do
    (( ${_aliprehook_trace_env[(Ie)$n]} )) || _aliprehook_trace_env+=($n)
  done
  if (( $#_aliprehook_last_passed )); then
    _aliprehook_trace_detail "    passed ${(j:, :)_aliprehook_last_passed}"
  fi
}

# Summary line for <cmd> [command source], level summary only; then the
# collected state is cleared so it is reported once.
_aliprehook_trace_summary() {
  emulate -L zsh
  local cmd=$1 src=$2 n
  local -a parts names
  if [[ $_aliprehook_trace_level == summary ]]; then
    (( $#_aliprehook_trace_hooks )) && parts+=("hooks: ${(j:, :)_aliprehook_trace_hooks}")
    for n in $_aliprehook_trace_env; do
      (( ${_aliprehook_trace_kept[(Ie)$n]} )) && names+=("$n (kept)") || names+=($n)
    done
    (( $#names )) && parts+=("env: ${(j:, :)names}")
    [[ -n $src ]] && parts+=("command: $src")
    (( $#parts )) && _aliprehook_trace "$cmd · ${(j: · :)parts}"
  fi
  _aliprehook_trace_hooks=() _aliprehook_trace_env=() _aliprehook_trace_kept=()
  return 0
}

# Before the main command runs: summary (summary level) or the command line
# (detail level). <lookup> is "<line no><TAB><line>" from commands.map or
# empty; <default> the aliprehook_define command; then the arguments.
_aliprehook_trace_command() {
  emulate -L zsh
  local cmd=$1 lookup=$2 def=$3 line src
  shift 3
  [[ -n $lookup ]] && src=commands.map:${lookup%%$'\t'*} line=${lookup#*$'\t'}
  if [[ $_aliprehook_trace_level == detail ]]; then
    (( $#_aliprehook_trace_kept )) && _aliprehook_trace "  kept in shell: ${(j:, :)_aliprehook_trace_kept}"
    if [[ -n $line ]]; then
      case $line in
        (*'$@'*|*'${@}'*|*'$*'*|*'${*}'*)
          _aliprehook_trace "  command ($src): $line${@:+  [arguments: ${(j: :)${(q-)@}}]}" ;;
        (*) _aliprehook_trace "  command ($src): $line${@:+ ${(j: :)${(q-)@}}}" ;;
      esac
    else
      _aliprehook_trace "  command (default): $def${@:+ ${(j: :)${(q-)@}}}"
    fi
    _aliprehook_trace_hooks=() _aliprehook_trace_env=() _aliprehook_trace_kept=()
  else
    _aliprehook_trace_summary $cmd $src
  fi
}

# Files renamed in 0.x: warn once per shell if an old one is still there
# without its new name (install.sh renames them). Old files are not read.
typeset -g _aliprehook_old_names_warned=
_aliprehook_old_names_check() {
  emulate -L zsh
  [[ $_aliprehook_old_names_warned == $ALIPREHOOK_HOME ]] && return 0
  _aliprehook_old_names_warned=$ALIPREHOOK_HOME
  local old new
  for old new in registry hooks.map commands commands.map allowed allowed-repos theme theme-overrides; do
    if [[ -f $ALIPREHOOK_HOME/$old && ! -e $ALIPREHOOK_HOME/$new ]]; then
      _aliprehook_msg warning "@key=$ALIPREHOOK_HOME/$old" " is not read anymore; it is now " "@key=$new" " " "@hint=(run ./install.sh from the aliprehook repo, or: mv $ALIPREHOOK_HOME/$old $ALIPREHOOK_HOME/$new)"
    fi
  done
}

# Run prehooks for <cmd_name>: user layer, then project layer if allowed.
# Extra args are passed to the hooks. Returns non-zero if a hook fails.
aliprehook_run() {
  emulate -L zsh -o extended_glob
  local cmd=$1 key hook root rel
  shift

  [[ -n $cmd ]] || { _aliprehook_msg error "aliprehook_run: missing command name"; return 2; }
  _aliprehook_old_names_check

  key=$(aliprehook_project_key)
  _aliprehook_env_user=() _aliprehook_env_project=() _aliprehook_env=()
  _aliprehook_verbose_resolve
  _aliprehook_trace_hooks=() _aliprehook_trace_env=() _aliprehook_trace_kept=()
  _aliprehook_trace_detail "$cmd in $key"

  # User layer: every matching hooks.map hook, in order; first failure stops.
  local -a hooks
  local entry label
  hooks=("${(@f)$(aliprehook_registry_lookup $key $cmd --mark)}")
  [[ -n ${hooks[1]} ]] || _aliprehook_trace_detail "  hooks.map: no hooks for $cmd here"
  for entry in $hooks; do
    [[ -n $entry ]] || continue
    hook=${entry#*$'\t'}
    label=${hook:t}
    [[ $entry == '*'$'\t'* ]] && label+=' (*)'
    _aliprehook_trace_detail "  hook $label"
    _aliprehook_exec user $key $cmd $hook "$@" || return $?
    _aliprehook_trace_hooks+=($label)
    _aliprehook_trace_add_passed
  done

  _aliprehook_run_project $key $cmd "$@" || return $?

  # For the main command: user values win over project values.
  _aliprehook_env=("${(@kv)_aliprehook_env_project}" "${(@kv)_aliprehook_env_user}")

  # aliprehook_define wrappers report once, right before the command runs.
  [[ ${_aliprehook_trace_defer-} == "$cmd" ]] || _aliprehook_trace_summary $cmd
  return 0
}

# Project layer for aliprehook_run: git repos only, and only if allowed.
_aliprehook_run_project() {
  emulate -L zsh -o extended_glob
  local key=$1 cmd=$2 root rel hook
  shift 2

  root=$(command git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z $root ]]; then
    _aliprehook_trace_detail "  project hook: none (not a git repo)"
    return 0
  fi
  if [[ ! -f $root/.aliprehook.yml ]]; then
    _aliprehook_trace_detail "  project hook: none (no .aliprehook.yml)"
    return 0
  fi
  if ! aliprehook_is_allowed $key; then
    _aliprehook_trace_detail "  project hook: skipped (repo not allowed; run: aliprehook allow)"
    return 0
  fi
  _aliprehook_project_commands_warn $root
  local problems
  if ! problems=$(aliprehook_project_check $root); then
    local p
    for p in "${(@f)problems}"; do
      _aliprehook_msg warning "$p"
    done
    _aliprehook_msg warning "invalid entries ignored; fix " "@key=$root/.aliprehook.yml"
  fi
  if ! rel=$(aliprehook_project_lookup $root $cmd); then
    _aliprehook_trace_detail "  project hook: none for $cmd in .aliprehook.yml"
    return 0
  fi

  root=${root:A}
  if [[ $rel == /* ]]; then
    _aliprehook_msg error "project hook must be a relative path: " "@key=$rel"
    return 1
  fi
  hook=${${:-$root/$rel}:A}
  if [[ $hook != $root/* ]]; then
    _aliprehook_msg error "project hook outside the repo: " "@key=$rel"
    return 1
  fi
  _aliprehook_trace_detail "  project hook $rel"
  ALIPREHOOK_PROJECT_ROOT=$root _aliprehook_exec project $key $cmd $hook "$@" || return $?
  _aliprehook_trace_hooks+=("${hook:t} (project)")
  _aliprehook_trace_add_passed
}

# Build shell code in $_aliprehook_env_code that declares the variables hooks
# passed in the last aliprehook_run, then clear them so they are used once.
# Evaluated by the caller: `local -x` makes them visible to the command it runs
# and gone when the caller returns. --keep-env: user-layer variables are
# exported globally instead (they stay in the shell); project ones stay local.
_aliprehook_env_decl() {
  emulate -L zsh
  local keep=0 k
  [[ $1 == --keep-env ]] && keep=1
  local -a code
  _aliprehook_trace_kept=()
  for k in ${(k)_aliprehook_env}; do
    if (( keep && ${+_aliprehook_env_user[$k]} )); then
      _aliprehook_trace_kept+=($k)
      code+=("typeset -gx ${(q)k}=${(q)_aliprehook_env[$k]}")
    else
      code+=("local -x ${(q)k}=${(q)_aliprehook_env[$k]}")
    fi
  done
  _aliprehook_env_user=() _aliprehook_env_project=() _aliprehook_env=()
  typeset -g _aliprehook_env_code=${(pj:\n:)code}
}

# Run <command...> with the variables hooks passed in the last aliprehook_run,
# for this command only (for your own functions, see README Case B).
# --keep-env: user-layer variables stay set in the shell afterwards.
aliprehook_with_env() {
  if [[ $1 == --keep-env ]]; then
    shift
    _aliprehook_env_decl --keep-env
  else
    _aliprehook_env_decl
  fi
  eval "$_aliprehook_env_code"
  if [[ $_aliprehook_trace_level == detail ]]; then
    (( $#_aliprehook_trace_kept )) && _aliprehook_trace "  kept in shell: ${(j:, :)_aliprehook_trace_kept}"
    _aliprehook_trace "  command: ${(j: :)${(q-)@}}"
  fi
  _aliprehook_trace_hooks=() _aliprehook_trace_env=() _aliprehook_trace_kept=()
  "$@"
}

# --- CLI: manage hooks.map / commands.map (aliprehook hook|command|edit) ---------
# Design: doc/07_cli-manage-hooks-and-commands.md

typeset -gA _aliprehook_usage
_aliprehook_usage=(
  'hook new'       'aliprehook hook new <cmd> [--hook <file>] [--edit] [--all | --key <key> | --path <dir>]'
  'hook add'       'aliprehook hook add <cmd> <hook> [--all | --key <key> | --path <dir>]'
  'hook rm'        'aliprehook hook rm <cmd> [--hook <file>] [--all | --key <key> | --path <dir>]'
  'hook ls'        'aliprehook hook ls [<cmd>] [--all | --key <key> | --path <dir>]'
  'command set'    "aliprehook command set <cmd> '<command line>' [--key <key> | --path <dir>]"
  'command rm'     'aliprehook command rm <cmd> [--key <key> | --path <dir>]'
  'command ls'     'aliprehook command ls [--key <key> | --path <dir>]'
  'edit'           'aliprehook edit [hooks|commands|allowed|theme|settings]'
  'key'            'aliprehook key [--path <dir>]'
  'verbose'        'aliprehook verbose [quiet|summary|detail] [--shell] [--reset]'
)

_aliprehook_help_project() {
  if [[ $1 == all ]]; then
    print -r -- "  --all           every project (*)"
  fi
  print -r -- "  --key <key>     this project key, no lookup
  --path <dir>    the project key of <dir>
                  (default: the current directory's key; at most one of${1:+ --all/}--key/--path)"
}

# Print help for: (empty) | hook | command | "hook new" | … | edit | key
_aliprehook_help() {
  emulate -L zsh
  local t=$1
  case $t in
    '')
      print -r -- "usage: aliprehook <command> [args]

  allow                 run project hooks from this repo's .aliprehook.yml
  revoke                stop running them
  key [--path <dir>]    print the project key (here, or for <dir>)
  hook new|add|rm|ls    manage hooks in hooks.map           (aliprehook hook help)
  command set|rm|ls     manage per-project command lines in commands.map (aliprehook command help)
  edit [<file>]         open hooks.map, commands.map, allowed-repos, theme-overrides or settings in \$EDITOR
  verbose [<level>]     show or set what aliprehook prints about a run (quiet, summary, detail)
  help                  this help

Every subcommand takes --help, e.g. aliprehook hook new --help"
      ;;
    hook)
      print -r -- "usage: aliprehook hook <new|add|rm|ls> …   (hooks run before a command; file: hooks.map)

  $_aliprehook_usage[hook new]
  $_aliprehook_usage[hook add]
  $_aliprehook_usage[hook rm]
  $_aliprehook_usage[hook ls]

Project: current directory's key by default; --all = every project (*),
--key <key> = exactly this key, --path <dir> = the key of <dir>.
Details: aliprehook hook <sub> --help"
      ;;
    command)
      print -r -- "usage: aliprehook command <set|rm|ls> …   (per-project command lines; file: commands.map)

  $_aliprehook_usage[command set]
  $_aliprehook_usage[command rm]
  $_aliprehook_usage[command ls]

Project: current directory's key by default; --key <key> = exactly this key,
--path <dir> = the key of <dir>. No --all: the aliprehook_define command is the
default for every project. Details: aliprehook command <sub> --help"
      ;;
    'hook new')
      print -r -- "usage: $_aliprehook_usage[hook new]

Create a hook for <cmd> from a template, make it executable and register it.
Runs before <cmd> in the chosen project, after hooks already registered.

  --hook <file>   hook file name (default: hooks/<repo>_<cmd>.sh, or all_<cmd>.sh with --all);
                  a bare name goes in hooks/; an existing file is reused, not overwritten
  --edit          open the hook in \$EDITOR afterwards
$(_aliprehook_help_project all)

example: aliprehook hook new Dup --hook aws_login.sh --path ~/src/sample_app_web"
      ;;
    'hook add')
      print -r -- "usage: $_aliprehook_usage[hook add]

Register an existing, executable hook to run before <cmd> in the chosen project,
after hooks already registered. A bare name means hooks/<name>; other relative
paths are under ${ALIPREHOOK_HOME/#$HOME/~}/.

$(_aliprehook_help_project all)

example: aliprehook hook add Dbuild aws_login.sh --all"
      ;;
    'hook rm')
      print -r -- "usage: $_aliprehook_usage[hook rm]

Remove the hooks.map line(s) for <cmd> in the chosen project. The hook file is kept.

  --hook <file>   only the line for this hook
$(_aliprehook_help_project all)

example: aliprehook hook rm Dup --hook aws_login.sh"
      ;;
    'hook ls')
      print -r -- "usage: $_aliprehook_usage[hook ls]

List the hooks that run for the chosen project, in run order (* lines first).
With --all, only the * lines.

$(_aliprehook_help_project all)

example: aliprehook hook ls Dup"
      ;;
    'command set')
      print -r -- "usage: $_aliprehook_usage[command set]

Make <cmd> run this command line in the chosen project instead of its
aliprehook_define default. Replaces an existing line. Quote the whole line as one
argument; single quotes keep \$(…) and \$VAR for run time. Your arguments are
appended when <cmd> runs, unless the line uses \"\$@\" itself.

$(_aliprehook_help_project)
No --all: change the aliprehook_define command to change the default everywhere.

example: aliprehook command set Dbuild 'DOCKER_BUILDKIT=1 docker compose -f docker-compose.dev.yml build'"
      ;;
    'command rm')
      print -r -- "usage: $_aliprehook_usage[command rm]

Remove the chosen project's command line for <cmd>; the aliprehook_define
default runs again.

$(_aliprehook_help_project)

example: aliprehook command rm Dbuild"
      ;;
    'command ls')
      print -r -- "usage: $_aliprehook_usage[command ls]

List the chosen project's command lines.

$(_aliprehook_help_project)

example: aliprehook command ls --path ~/src/sample_app_web"
      ;;
    edit)
      print -r -- "usage: $_aliprehook_usage[edit]

Open a file of ${ALIPREHOOK_HOME/#$HOME/~}/ in \$VISUAL / \$EDITOR:
  hooks → hooks.map (default), commands → commands.map,
  allowed → allowed-repos, theme → theme-overrides, settings → settings

example: aliprehook edit commands"
      ;;
    verbose)
      print -r -- "usage: $_aliprehook_usage[verbose]

What aliprehook prints about a run (on stderr, never variable values):
  quiet     nothing (errors and warnings still print)
  summary   one line before the command, only if hooks ran, variables were
            passed or the command came from commands.map (default)
  detail    every step as it happens, skipped steps and why, the command line

  (no level)  show the current level and where it comes from
  <level>     save it in ${ALIPREHOOK_HOME/#$HOME/~}/settings (all shells)
  --shell     this shell only (sets ALIPREHOOK_VERBOSE)
  --reset     remove the saved level (with --shell: unset ALIPREHOOK_VERBOSE)
For one run: ALIPREHOOK_VERBOSE=detail <cmd>

example: aliprehook verbose detail"
      ;;
    key)
      print -r -- "usage: $_aliprehook_usage[key]

Print the project key: normalized git remote (origin, else the first remote),
else the directory path (pwd -P).

  --path <dir>    the key <dir> would have

example: aliprehook key --path ~/src/sample_app_web"
      ;;
  esac
}

# Report a wrong call of <topic>: error, usage line, pointer to help. Exit 2.
_aliprehook_cli_bad() {
  local topic=$1
  shift
  _aliprehook_msg error "$@"
  [[ -n $_aliprehook_usage[$topic] ]] && print -u2 -r -- "usage: $_aliprehook_usage[$topic]"
  _aliprehook_msg -2 info "@hint=(see: aliprehook ${topic% *} help)"
  return 2
}

# Parse the arguments of <topic> against <spec> (space-separated option names;
# a trailing ':' takes a value). Fills the caller's `opts` and `pos`.
_aliprehook_cli_args() {
  local topic=$1 spec=" $2 " a name
  shift 2
  while (( $# )); do
    a=$1
    shift
    case $a in
      -h|--help) opts[help]=1 ;;
      --) pos+=("$@"); break ;;
      --?*=*)
        name=${${a%%=*}#--}
        [[ $spec == *" $name: "* ]] || { _aliprehook_cli_bad $topic "unknown option: ${a%%=*}"; return 2; }
        opts[$name]=${a#*=}
        ;;
      --?*)
        name=${a#--}
        if [[ $spec == *" $name: "* ]]; then
          (( $# )) || { _aliprehook_cli_bad $topic "$a needs a value"; return 2; }
          opts[$name]=$1
          shift
        elif [[ $spec == *" $name "* ]]; then
          opts[$name]=1
        else
          _aliprehook_cli_bad $topic "unknown option: $a"
          return 2
        fi
        ;;
      -?*) _aliprehook_cli_bad $topic "unknown option: $a"; return 2 ;;
      *) pos+=("$a") ;;
    esac
  done
}

# Print the project key chosen by the caller's opts (--all/--key/--path, or
# the current directory). Exit 2 on a usage error (reported).
_aliprehook_cli_key() {
  emulate -L zsh -o extended_glob
  local topic=$1 key norm
  integer n=0
  (( ${+opts[all]} )) && (( n++ ))
  (( ${+opts[key]} )) && (( n++ ))
  (( ${+opts[path]} )) && (( n++ ))
  if (( n > 1 )); then
    _aliprehook_cli_bad $topic "use only one of --all, --key, --path"
    return 2
  fi

  if (( ${+opts[all]} )); then
    print -r -- '*'
    return 0
  elif (( ${+opts[key]} )); then
    key=$opts[key]
    if [[ -z $key ]]; then
      _aliprehook_cli_bad $topic "--key needs a non-empty key"; return 2
    elif [[ $key == '*' ]]; then
      _aliprehook_cli_bad $topic "--key '*' is not a project key; use --all"; return 2
    fi
    if [[ $key != /* ]]; then
      norm=$(aliprehook_normalize_remote $key)
      [[ $norm == "$key" ]] || _aliprehook_msg warning "--key " "@key=$key" " is not a normalized key (did you mean " "@key=$norm" "?); using it as given"
    fi
  elif (( ${+opts[path]} )); then
    if [[ ! -d $opts[path] ]]; then
      _aliprehook_cli_bad $topic "--path: no such directory: " "@key=$opts[path]"; return 2
    fi
    key=$(builtin cd -q -- $opts[path] && aliprehook_project_key) || return 2
  else
    key=$(aliprehook_project_key)
  fi

  if [[ $key == *[[:space:]]* ]]; then
    _aliprehook_msg error "project key contains whitespace, cannot be stored: " "@key=$key"
    return 2
  fi
  print -r -- $key
}

# Valid command name, or report a wrong call.
_aliprehook_cli_cmdname() {
  [[ $2 == [A-Za-z_][A-Za-z0-9_-]# ]] && return 0
  _aliprehook_cli_bad $1 "invalid command name: " "@command=$2"
}

# Resolve a hook argument into the caller's `stored` (hooks.map form) and
# `abs` (file path): /abs as is, bare name → hooks/<name>, else under HOME.
_aliprehook_cli_hookpath() {
  local topic=$1 arg=$2
  if [[ -z $arg || $arg == *[[:space:]]* ]]; then
    _aliprehook_cli_bad $topic "invalid hook path (empty or with whitespace): " "@key=$arg"
    return 2
  fi
  if [[ $arg == /* ]]; then
    stored=$arg abs=$arg
  elif [[ $arg != */* ]]; then
    stored=hooks/$arg abs=$ALIPREHOOK_HOME/hooks/$arg
  else
    stored=$arg abs=$ALIPREHOOK_HOME/$arg
  fi
  abs=${abs:a}
}

# Absolute path of a hooks.map hook column.
_aliprehook_cli_abs() {
  local h=$1
  [[ $h == /* ]] || h=$ALIPREHOOK_HOME/$h
  print -r -- ${h:a}
}

# Read <file> into the caller's `lines` (every line kept, including comments).
_aliprehook_read_lines() {
  local l
  lines=()
  [[ -r $1 ]] || return 0
  while IFS= read -r l || [[ -n $l ]]; do
    lines+=("$l")
  done < $1
}

# Replace <file> with <line>...: temp file next to it, then mv. Symlinks are
# followed (the target is written); an existing file keeps its permissions.
_aliprehook_write_lines() {
  emulate -L zsh
  local file=${1:A} tmp
  shift
  tmp=$file.tmp.$$
  command mkdir -p -- ${file:h} || return 1
  if [[ -e $file ]]; then
    command cp -p -- $file $tmp || return 1
  fi
  if (( $# )); then
    print -rl -- "$@" >| $tmp
  else
    : >| $tmp
  fi || { command rm -f -- $tmp; return 1; }
  command mv -f -- $tmp $file
}

# Short display form of a path (~ for HOME).
_aliprehook_tilde() { print -r -- ${1/#$HOME/\~}; }

# Add "<key>  <cmd>  <stored>" to hooks.map unless the same hook is there.
_aliprehook_cli_registry_add() {
  emulate -L zsh -o extended_glob
  local key=$1 cmd=$2 stored=$3 abs=$4 line
  local registry=$ALIPREHOOK_HOME/hooks.map
  local -a lines w
  _aliprehook_read_lines $registry
  for line in "${lines[@]}"; do
    [[ $line == [[:space:]]#(\#*|) ]] && continue
    w=(${=line})
    if [[ $w[1] == "$key" && $w[2] == "$cmd" && -n $w[3] && $(_aliprehook_cli_abs $w[3]) == "$abs" ]]; then
      _aliprehook_msg info "already registered: " "@key=$key" "  " "@command=$cmd" "  " "@hook=$w[3]"
      return 0
    fi
  done
  lines+=("$key  $cmd  $stored")
  _aliprehook_write_lines $registry "${lines[@]}" || { _aliprehook_msg error "cannot write " "@key=$registry"; return 1; }
  _aliprehook_msg success "@success=added" " " "@key=$key" "  " "@command=$cmd" "  " "@hook=$stored"
}

_aliprehook_hook_template() {  # key cmd
  print -r -- "#!/bin/sh
# aliprehook hook: runs before \`$2\` in $1.
# A non-zero exit stops the command.
#
# Available:
#   \$ALIPREHOOK_PROJECT_KEY   project key
#   \$ALIPREHOOK_COMMAND       command name ($2)
#   \"\$@\"                     the arguments given to the command
#
# Pass variables to the command (see: aliprehook_env_pass --help):
#   aliprehook_env_pass APP_ENV=development --required API_TOKEN --hint \"run: my-login\"

exit 0"
}

_aliprehook_cli_hook() {
  emulate -L zsh -o extended_glob
  local sub=$1 topic key stored abs line cmd
  local -A opts
  local -a pos lines w
  (( $# )) && shift

  case $sub in
    ''|help|-h|--help) _aliprehook_help hook; return 0 ;;
    new|add|rm|ls) topic="hook $sub" ;;
    *) _aliprehook_cli_bad hook "unknown subcommand: hook $sub"; return 2 ;;
  esac

  case $sub in
    new) _aliprehook_cli_args $topic 'hook: edit all key: path:' "$@" || return 2 ;;
    rm)  _aliprehook_cli_args $topic 'hook: all key: path:' "$@" || return 2 ;;
    *)   _aliprehook_cli_args $topic 'all key: path:' "$@" || return 2 ;;
  esac
  if (( ${+opts[help]} )); then
    _aliprehook_help $topic
    return 0
  fi

  case $sub in
    new|rm) (( $#pos == 1 )) || { _aliprehook_cli_bad $topic "expected <cmd>${pos[2]:+, got extra: $pos[2,-1]}"; return 2; } ;;
    add)    (( $#pos == 2 )) || { _aliprehook_cli_bad $topic "expected <cmd> <hook>"; return 2; } ;;
    ls)     (( $#pos <= 1 )) || { _aliprehook_cli_bad $topic "expected at most one <cmd>"; return 2; } ;;
  esac
  cmd=$pos[1]
  if [[ -n $cmd ]]; then
    _aliprehook_cli_cmdname $topic $cmd || return 2
  fi
  key=$(_aliprehook_cli_key $topic) || return 2

  case $sub in
    new)
      if (( ${+opts[hook]} )); then
        _aliprehook_cli_hookpath $topic $opts[hook] || return 2
      else
        if [[ $key == '*' ]]; then
          stored=hooks/all_$cmd.sh
        else
          stored=hooks/${${key:t}//[^A-Za-z0-9._-]/_}_$cmd.sh
        fi
        abs=$ALIPREHOOK_HOME/$stored
      fi
      if [[ -e $abs ]]; then
        if [[ ! -f $abs ]]; then
          _aliprehook_msg error "not a file: " "@key=$abs"
          return 1
        fi
        if [[ ! -x $abs ]]; then
          _aliprehook_msg error "hook not executable: " "@key=$abs" " " "@hint=(run: chmod +x $abs)"
          return 1
        fi
        _aliprehook_msg info "using existing hook " "@hook=$(_aliprehook_tilde $abs)"
      else
        command mkdir -p -- ${abs:h} &&
          _aliprehook_hook_template $key $cmd > $abs &&
          command chmod +x -- $abs || { _aliprehook_msg error "cannot create " "@key=$abs"; return 1; }
        _aliprehook_msg success "@success=created" " " "@hook=$(_aliprehook_tilde $abs)"
      fi
      _aliprehook_cli_registry_add $key $cmd $stored $abs || return 1
      if (( ${+opts[edit]} )); then
        ${=${VISUAL:-${EDITOR:-vi}}} $abs
      fi
      ;;

    add)
      _aliprehook_cli_hookpath $topic $pos[2] || return 2
      if [[ ! -f $abs ]]; then
        _aliprehook_msg error "hook not found: " "@key=$abs" " " "@hint=(create it with: aliprehook hook new $cmd --hook $pos[2])"
        return 1
      fi
      if [[ ! -x $abs ]]; then
        _aliprehook_msg error "hook not executable: " "@key=$abs" " " "@hint=(run: chmod +x $abs)"
        return 1
      fi
      _aliprehook_cli_registry_add $key $cmd $stored $abs
      ;;

    rm)
      local registry=$ALIPREHOOK_HOME/hooks.map
      local -a keep removed
      if (( ${+opts[hook]} )); then
        _aliprehook_cli_hookpath $topic $opts[hook] || return 2
      fi
      _aliprehook_read_lines $registry
      for line in "${lines[@]}"; do
        if [[ $line != [[:space:]]#(\#*|) ]]; then
          w=(${=line})
          if [[ $w[1] == "$key" && $w[2] == "$cmd" && -n $w[3] ]] &&
             { [[ -z $abs ]] || [[ $(_aliprehook_cli_abs $w[3]) == "$abs" ]]; }; then
            removed+=($w[3])
            continue
          fi
        fi
        keep+=("$line")
      done
      if (( ! $#removed )); then
        local -a parts=("nothing to remove: no hook for " "@command=$cmd" " in " "@key=$key")
        [[ -n $abs ]] && parts+=(" matching " "@hook=$stored")
        _aliprehook_msg info "${parts[@]}"
        return 1
      fi
      _aliprehook_write_lines $registry "${keep[@]}" || { _aliprehook_msg error "cannot write " "@key=$registry"; return 1; }
      for line in $removed; do
        _aliprehook_msg success "@success=removed" " " "@key=$key" "  " "@command=$cmd" "  " "@hook=$line"
      done
      ;;

    ls)
      local -a order common exact
      local -A seen
      local k c h id st out star gname
      integer color=0 width=0
      _aliprehook_read_lines $ALIPREHOOK_HOME/hooks.map
      for line in "${lines[@]}"; do
        [[ $line == [[:space:]]#(\#*|) ]] && continue
        w=(${=line})
        k=$w[1] c=$w[2] h=$w[3]
        [[ -n $h ]] || continue
        [[ -z $cmd || $c == "$cmd" ]] || continue
        if [[ $key == '*' ]]; then
          [[ $k == '*' ]] || continue
        else
          [[ $k == '*' || $k == "$key" ]] || continue
        fi
        id="$c"$'\t'"$k"$'\t'"$h"
        (( ${+seen[$id]} )) && continue
        seen[$id]=1
        (( ${order[(Ie)$c]} )) || order+=($c)
        (( $#c > width )) && width=$#c
        if [[ $k == '*' ]]; then
          common+=("$c"$'\t'"$h")
        else
          exact+=("$c"$'\t'"$h")
        fi
      done

      _aliprehook_theme_ensure
      _aliprehook_color_on 1 && color=1
      out=
      _aliprehook_paint "${_aliprehook_theme[key]-}" "$key"
      print -r -- $out
      if (( ! $#order )); then
        print -r -- "  (no hooks${cmd:+ for $cmd})"
        return 0
      fi
      for c in $order; do
        for star in 1 0; do
          (( star )) && gname=common || gname=exact
          for id in "${(@P)gname}"; do
            [[ ${id%%$'\t'*} == "$c" ]] || continue
            h=${id#*$'\t'}
            out='  '
            _aliprehook_paint "${_aliprehook_theme[command]-}" "${(r:width:)c}"
            out+='  '
            _aliprehook_paint "${_aliprehook_theme[hook]-}" "$h"
            st=
            (( star )) && [[ $key != '*' ]] && st='* every project'
            abs=$(_aliprehook_cli_abs $h)
            if [[ ! -f $abs ]]; then
              st+=${st:+, }missing
            elif [[ ! -x $abs ]]; then
              st+=${st:+, }'not executable'
            fi
            if [[ -n $st ]]; then
              out+='  '
              _aliprehook_paint "${_aliprehook_theme[hint]-}" "($st)"
            fi
            print -r -- $out
          done
        done
      done
      ;;
  esac
}

_aliprehook_cli_command() {
  emulate -L zsh -o extended_glob
  local sub=$1 topic key line cmd new old
  local file=$ALIPREHOOK_HOME/commands.map
  local -A opts
  local -a pos lines keep
  (( $# )) && shift

  case $sub in
    ''|help|-h|--help) _aliprehook_help command; return 0 ;;
    set|rm|ls) topic="command $sub" ;;
    *) _aliprehook_cli_bad command "unknown subcommand: command $sub"; return 2 ;;
  esac

  _aliprehook_cli_args $topic 'all key: path:' "$@" || return 2
  if (( ${+opts[help]} )); then
    _aliprehook_help $topic
    return 0
  fi
  if (( ${+opts[all]} )); then
    _aliprehook_cli_bad $topic "no --all for commands: the aliprehook_define command is already the default for every project; change it there"
    return 2
  fi

  case $sub in
    set)
      if (( $#pos > 2 )); then
        _aliprehook_cli_bad $topic "quote the command line as one argument: aliprehook command set ${pos[1]} '${pos[2,-1]}'"
        return 2
      fi
      (( $#pos == 2 )) || { _aliprehook_cli_bad $topic "expected <cmd> '<command line>'"; return 2; }
      new=$pos[2]
      if [[ $new == *$'\n'* ]]; then
        _aliprehook_cli_bad $topic "the command line must be one line (put longer commands in a script)"
        return 2
      fi
      new=${${new##[[:space:]]#}%%[[:space:]]#}
      [[ -n $new ]] || { _aliprehook_cli_bad $topic "empty command line"; return 2; }
      ;;
    rm) (( $#pos == 1 )) || { _aliprehook_cli_bad $topic "expected <cmd>"; return 2; } ;;
    ls) (( $#pos == 0 )) || { _aliprehook_cli_bad $topic "unexpected argument: $pos[1]"; return 2; } ;;
  esac
  cmd=$pos[1]
  if [[ -n $cmd ]]; then
    _aliprehook_cli_cmdname $topic $cmd || return 2
  fi
  key=$(_aliprehook_cli_key $topic) || return 2

  # Lines of this project and command: (#b) gives key, command, rest.
  local pat='[[:space:]]#(#b)([^[:space:]]##)[[:space:]]##([^[:space:]]##)(*)'
  _aliprehook_read_lines $file

  case $sub in
    set)
      local placed=0 existed=0
      [[ -e $file ]] && existed=1
      for line in "${lines[@]}"; do
        if [[ $line != [[:space:]]#(\#*|) && $line == ${~pat} && $match[1] == "$key" && $match[2] == "$cmd" ]]; then
          if (( ! placed )); then
            old=${${match[3]##[[:space:]]#}%%[[:space:]]#}
            if [[ $old == "$new" ]]; then
              _aliprehook_msg info "already set: " "@command=$cmd" " in " "@key=$key" " runs: $new"
              return 0
            fi
            keep+=("$key  $cmd  $new")
            placed=1
          else
            _aliprehook_msg info "removed duplicate line: $line"
          fi
          continue
        fi
        keep+=("$line")
      done
      (( placed )) || keep+=("$key  $cmd  $new")
      _aliprehook_write_lines $file "${keep[@]}" || { _aliprehook_msg error "cannot write " "@key=$file"; return 1; }
      (( existed )) || command chmod go-w -- ${file:A}
      _aliprehook_msg success "@command=$cmd" " in " "@key=$key" " now runs: $new"
      [[ -n $old ]] && _aliprehook_msg info "was: $old"
      if (( ! ${+functions[$cmd]} )); then
        _aliprehook_msg warning "@command=$cmd" " is not defined in this shell; the line runs only for commands defined with aliprehook_define (or using aliprehook_command)"
      fi
      ;;

    rm)
      local -a removed
      for line in "${lines[@]}"; do
        if [[ $line != [[:space:]]#(\#*|) && $line == ${~pat} && $match[1] == "$key" && $match[2] == "$cmd" ]]; then
          removed+=("${${match[3]##[[:space:]]#}%%[[:space:]]#}")
          continue
        fi
        keep+=("$line")
      done
      if (( ! $#removed )); then
        _aliprehook_msg info "nothing to remove: no command line for " "@command=$cmd" " in " "@key=$key"
        return 1
      fi
      _aliprehook_write_lines $file "${keep[@]}" || { _aliprehook_msg error "cannot write " "@key=$file"; return 1; }
      for line in "${removed[@]}"; do
        _aliprehook_msg success "@success=removed" " " "@command=$cmd" " in " "@key=$key" ": $line"
      done
      _aliprehook_msg info "@command=$cmd" " runs its aliprehook_define default here again"
      ;;

    ls)
      local -a found
      local out
      integer color=0 width=0
      for line in "${lines[@]}"; do
        if [[ $line != [[:space:]]#(\#*|) && $line == ${~pat} && $match[1] == "$key" ]]; then
          found+=("$match[2]"$'\t'"${${match[3]##[[:space:]]#}%%[[:space:]]#}")
          (( $#match[2] > width )) && width=$#match[2]
        fi
      done
      _aliprehook_theme_ensure
      _aliprehook_color_on 1 && color=1
      out=
      _aliprehook_paint "${_aliprehook_theme[key]-}" "$key"
      print -r -- $out
      if (( ! $#found )); then
        print -r -- "  (no command lines; every command runs its aliprehook_define default)"
        return 0
      fi
      for line in "${found[@]}"; do
        out='  '
        cmd=${line%%$'\t'*}
        _aliprehook_paint "${_aliprehook_theme[command]-}" "${(r:width:)cmd}"
        out+="  ${line#*$'\t'}"
        print -r -- $out
      done
      ;;
  esac
}

_aliprehook_cli_edit() {
  emulate -L zsh
  local -A opts
  local -a pos
  _aliprehook_cli_args edit '' "$@" || return 2
  if (( ${+opts[help]} )); then
    _aliprehook_help edit
    return 0
  fi
  (( $#pos <= 1 )) || { _aliprehook_cli_bad edit "expected at most one file"; return 2; }
  local f
  case ${pos[1]:-hooks} in
    hooks) f=hooks.map ;;
    commands) f=commands.map ;;
    allowed) f=allowed-repos ;;
    theme) f=theme-overrides ;;
    settings) f=settings ;;
    *) _aliprehook_cli_bad edit "unknown file: $pos[1] (hooks, commands, allowed, theme, settings)"; return 2 ;;
  esac
  command mkdir -p -- $ALIPREHOOK_HOME
  ${=${VISUAL:-${EDITOR:-vi}}} $ALIPREHOOK_HOME/$f
}

_aliprehook_cli_verbose() {
  emulate -L zsh -o extended_glob
  local -A opts
  local -a pos lines keep
  local file=$ALIPREHOOK_HOME/settings level line saved
  _aliprehook_cli_args verbose 'shell reset' "$@" || return 2
  if (( ${+opts[help]} )); then
    _aliprehook_help verbose
    return 0
  fi
  (( $#pos <= 1 )) || { _aliprehook_cli_bad verbose "expected at most one level"; return 2; }
  level=$pos[1]
  if [[ -n $level && $level != (quiet|summary|detail) ]]; then
    _aliprehook_cli_bad verbose "unknown level: $level (quiet, summary, detail)"
    return 2
  fi
  if (( ${+opts[reset]} )) && [[ -n $level ]]; then
    _aliprehook_cli_bad verbose "--reset takes no level"
    return 2
  fi
  _aliprehook_settings_load
  saved=${_aliprehook_settings[verbose]-}

  # Show.
  if [[ -z $level ]] && (( ! ${+opts[reset]} )); then
    if (( ${+opts[shell]} )); then
      _aliprehook_cli_bad verbose "--shell needs a level (or --reset)"
      return 2
    fi
    _aliprehook_verbose_resolve
    case $_aliprehook_trace_source in
      env) print -r -- "$_aliprehook_trace_level (from ALIPREHOOK_VERBOSE)" ;;
      settings) print -r -- "$_aliprehook_trace_level (from $(_aliprehook_tilde $file))" ;;
      *) print -r -- "$_aliprehook_trace_level (default)" ;;
    esac
    if [[ $_aliprehook_trace_source == env && -n $saved ]]; then
      _aliprehook_msg warning "saved level $saved in " "@key=$(_aliprehook_tilde $file)" " is hidden by ALIPREHOOK_VERBOSE=$ALIPREHOOK_VERBOSE " "@hint=(run: unset ALIPREHOOK_VERBOSE)"
    fi
    return 0
  fi

  # This shell only.
  if (( ${+opts[shell]} )); then
    if (( ${+opts[reset]} )); then
      unset ALIPREHOOK_VERBOSE
      _aliprehook_verbose_resolve
      _aliprehook_msg success "ALIPREHOOK_VERBOSE unset in this shell; level is $_aliprehook_trace_level ($_aliprehook_trace_source)"
    else
      typeset -gx ALIPREHOOK_VERBOSE=$level
      _aliprehook_msg success "verbose level is now $level in this shell only"
    fi
    return 0
  fi

  # Save or reset in the settings file (other lines kept).
  _aliprehook_read_lines $file
  local placed=0
  for line in "${lines[@]}"; do
    if [[ $line == [[:space:]]#verbose[[:space:]]#=* ]]; then
      if [[ -n $level ]] && (( ! placed )); then
        keep+=("verbose=$level")
        placed=1
      fi
      continue
    fi
    keep+=("$line")
  done
  if [[ -n $level ]]; then
    (( placed )) || keep+=("verbose=$level")
  elif [[ -z $saved ]]; then
    _aliprehook_msg info "no saved level; level is the default (summary)"
    return 0
  fi
  _aliprehook_write_lines $file "${keep[@]}" || { _aliprehook_msg error "cannot write " "@key=$file"; return 1; }
  if [[ -n $level ]]; then
    _aliprehook_msg success "verbose level is now $level (saved in " "@key=$(_aliprehook_tilde $file)" ")"
  else
    _aliprehook_msg success "saved level removed; level is the default (summary)"
  fi
  if [[ -n ${ALIPREHOOK_VERBOSE-} ]]; then
    _aliprehook_msg warning "ALIPREHOOK_VERBOSE=$ALIPREHOOK_VERBOSE overrides it in this shell " "@hint=(run: unset ALIPREHOOK_VERBOSE)"
  fi
}

_aliprehook_cli_keycmd() {
  emulate -L zsh
  local -A opts
  local -a pos
  _aliprehook_cli_args key 'path:' "$@" || return 2
  if (( ${+opts[help]} )); then
    _aliprehook_help key
    return 0
  fi
  (( $#pos == 0 )) || { _aliprehook_cli_bad key "unexpected argument: $pos[1]"; return 2; }
  if (( ${+opts[path]} )); then
    [[ -d $opts[path] ]] || { _aliprehook_cli_bad key "--path: no such directory: " "@key=$opts[path]"; return 2; }
    ( builtin cd -q -- $opts[path] && aliprehook_project_key )
  else
    aliprehook_project_key
  fi
}

# aliprehook allow | revoke | key | hook | command | edit | verbose | help
aliprehook() {
  emulate -L zsh -o extended_glob
  local sub=$1 key root allowed=$ALIPREHOOK_HOME/allowed-repos tmp line
  (( $# )) && shift
  _aliprehook_old_names_check

  case $sub in
    allow)
      root=$(command git rev-parse --show-toplevel 2>/dev/null)
      if [[ -z $root || ! -f $root/.aliprehook.yml ]]; then
        _aliprehook_msg error "allow: no " "@key=.aliprehook.yml" " in this git repo"
        return 1
      fi
      if ! line=$(aliprehook_project_check $root); then
        local p
        for p in "${(@f)line}"; do
          _aliprehook_msg error "allow: $p"
        done
        _aliprehook_msg error "allow: not allowed; fix " "@key=$root/.aliprehook.yml" " first"
        return 1
      fi
      _aliprehook_project_commands_warn $root
      key=$(aliprehook_project_key)
      if aliprehook_is_allowed $key; then
        _aliprehook_msg info "already allowed: " "@key=$key"
        return 0
      fi
      mkdir -p $ALIPREHOOK_HOME
      print -r -- $key >> $allowed
      _aliprehook_msg success "@success=allowed" " " "@key=$key"
      _aliprehook_msg info "project hooks from " "@key=$root/.aliprehook.yml" " will now run"
      ;;
    revoke)
      key=$(aliprehook_project_key)
      if ! aliprehook_is_allowed $key; then
        _aliprehook_msg info "not allowed: " "@key=$key"
        return 0
      fi
      tmp=$allowed.tmp.$$
      while IFS= read -r line; do
        [[ ${line//[[:space:]]/} == "$key" ]] || print -r -- $line
      done < $allowed > $tmp && mv $tmp $allowed
      _aliprehook_msg success "@success=revoked" " " "@key=$key"
      ;;
    key) _aliprehook_cli_keycmd "$@" ;;
    hook) _aliprehook_cli_hook "$@" ;;
    command) _aliprehook_cli_command "$@" ;;
    edit) _aliprehook_cli_edit "$@" ;;
    verbose) _aliprehook_cli_verbose "$@" ;;
    help|-h|--help|'')
      _aliprehook_help
      ;;
    *)
      _aliprehook_msg error "unknown command: " "@command=$sub" " " "@hint=(see: aliprehook help)"
      return 2
      ;;
  esac
}

# Define <name> as a shell function that runs prehooks, then <command...> "$@"
# (or this project's line from ALIPREHOOK_HOME/commands.map) with the variables
# the hooks passed. --keep-env keeps user-layer variables in the shell afterwards.
# commands.map is checked first, so a broken one stops before any hook.
aliprehook_define() {
  emulate -L zsh -o extended_glob
  local keep= name body
  if [[ $1 == --keep-env ]]; then
    keep=--keep-env
    shift
  fi
  name=$1
  (( $# )) && shift

  if [[ -z $name || $# -eq 0 ]]; then
    _aliprehook_msg error "usage: aliprehook_define [--keep-env] <name> <command...>"
    return 2
  fi
  if [[ $name != [A-Za-z_][A-Za-z0-9_-]# ]]; then
    _aliprehook_msg error "aliprehook_define: invalid name: " "@command=$name"
    return 2
  fi

  # Calling the same name inside the wrapper would recurse.
  [[ $1 == $name ]] && set -- command "$@"

  body="local _aliprehook_line _aliprehook_trace_defer=${(q)name}
  _aliprehook_line=\$(_aliprehook_command_lookup ${(q)name})
  (( \$? < 2 )) || return 1
  aliprehook_run ${(q)name} \"\$@\" || return \$?
  _aliprehook_env_decl $keep; eval \"\$_aliprehook_env_code\"
  _aliprehook_trace_command ${(q)name} \"\$_aliprehook_line\" ${(q)${(j: :)${(q-)@}}} \"\$@\"
  if [[ -n \$_aliprehook_line ]]; then
    _aliprehook_command_eval \"\${_aliprehook_line#*\$'\\t'}\" \"\$@\"
  else
    ${(j: :)${(q)@}} \"\$@\"
  fi"
  unalias $name 2>/dev/null
  eval "function ${(q)name} { $body; }"
}
