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
# ALIPREHOOK_THEME), with single roles overridden by ALIPREHOOK_HOME/theme.
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
  [[ -r $ALIPREHOOK_HOME/theme ]] && _aliprehook_theme_read $ALIPREHOOK_HOME/theme
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
    [[ $level == (warning|error) ]] && fd=2 || fd=1
  fi
  _aliprehook_theme_ensure
  _aliprehook_color_on $fd && color=1
  tcode=
  [[ $level == (warning|error) ]] && tcode=${_aliprehook_theme[$level]-}

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
aliprehook_registry_lookup() {
  emulate -L zsh -o extended_glob
  local key=$1 cmd=$2 k c h id
  local registry=$ALIPREHOOK_HOME/registry
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
  print -rl -- $common $exact
}

# Exit 0 if <key> is listed in ALIPREHOOK_HOME/allowed.
aliprehook_is_allowed() {
  emulate -L zsh -o extended_glob
  local key=$1 line
  local allowed=$ALIPREHOOK_HOME/allowed

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
# `*` (all-projects) hooks are user-registry only: a repo must not define them.
aliprehook_project_check() {
  emulate -L zsh -o extended_glob
  local root=$1 entry n name value
  local -a problems

  for entry in "${(@f)$(_aliprehook_project_entries $root)}"; do
    [[ -n $entry ]] || continue
    n=${entry%%$'\t'*}; entry=${entry#*$'\t'}
    name=${entry%%$'\t'*}; value=${entry#*$'\t'}
    if [[ $name == '*' ]]; then
      problems+=(".aliprehook.yml:$n: '*' hooks are not allowed in a repo; only in your user registry ($ALIPREHOOK_HOME/registry)")
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
  local -a missing
  local -A vars

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

# Run prehooks for <cmd_name>: user layer, then project layer if allowed.
# Extra args are passed to the hooks. Returns non-zero if a hook fails.
aliprehook_run() {
  emulate -L zsh -o extended_glob
  local cmd=$1 key hook root rel
  shift

  [[ -n $cmd ]] || { _aliprehook_msg error "aliprehook_run: missing command name"; return 2; }

  key=$(aliprehook_project_key)
  _aliprehook_env_user=() _aliprehook_env_project=() _aliprehook_env=()

  # User layer: every matching registry hook, in order; first failure stops.
  local -a hooks
  hooks=("${(@f)$(aliprehook_registry_lookup $key $cmd)}")
  for hook in $hooks; do
    [[ -n $hook ]] || continue
    _aliprehook_exec user $key $cmd $hook "$@" || return $?
  done

  _aliprehook_run_project $key $cmd "$@" || return $?

  # For the main command: user values win over project values.
  _aliprehook_env=("${(@kv)_aliprehook_env_project}" "${(@kv)_aliprehook_env_user}")
  return 0
}

# Project layer for aliprehook_run: git repos only, and only if allowed.
_aliprehook_run_project() {
  emulate -L zsh -o extended_glob
  local key=$1 cmd=$2 root rel hook
  shift 2

  root=$(command git rev-parse --show-toplevel 2>/dev/null) || return 0
  [[ -n $root && -f $root/.aliprehook.yml ]] || return 0
  aliprehook_is_allowed $key || return 0
  local problems
  if ! problems=$(aliprehook_project_check $root); then
    local p
    for p in "${(@f)problems}"; do
      _aliprehook_msg warning "$p"
    done
    _aliprehook_msg warning "invalid entries ignored; fix " "@key=$root/.aliprehook.yml"
  fi
  rel=$(aliprehook_project_lookup $root $cmd) || return 0

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
  ALIPREHOOK_PROJECT_ROOT=$root _aliprehook_exec project $key $cmd $hook "$@"
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
  for k in ${(k)_aliprehook_env}; do
    if (( keep && ${+_aliprehook_env_user[$k]} )); then
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
  "$@"
}

# aliprehook allow | revoke | key | help
aliprehook() {
  emulate -L zsh -o extended_glob
  local sub=$1 key root allowed=$ALIPREHOOK_HOME/allowed tmp line
  (( $# )) && shift

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
    key)
      aliprehook_project_key
      ;;
    help|-h|--help|'')
      print "usage: aliprehook <allow|revoke|key|help>"
      print "  allow   run project hooks from this repo's .aliprehook.yml"
      print "  revoke  stop running them"
      print "  key     print the project key for the current directory"
      ;;
    *)
      _aliprehook_msg error "unknown command: " "@command=$sub" " " "@hint=(see: aliprehook help)"
      return 2
      ;;
  esac
}

# Define <name> as a shell function that runs prehooks, then <command...> "$@"
# with the variables the hooks passed. --keep-env keeps user-layer variables
# in the shell afterwards.
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

  body="aliprehook_run ${(q)name} \"\$@\" || return \$?
  _aliprehook_env_decl $keep; eval \"\$_aliprehook_env_code\"
  ${(j: :)${(q)@}} \"\$@\""
  unalias $name 2>/dev/null
  eval "function ${(q)name} { $body; }"
}
