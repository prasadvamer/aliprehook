# aliprehook: optional prehooks for opt-in shell commands.
# Load from ~/.zshrc:
#   source ~/.config/aliprehook/lib.zsh

typeset -g ALIPREHOOK_VERSION=0.0.0
typeset -g ALIPREHOOK_HOME=${ALIPREHOOK_HOME:-$HOME/.config/aliprehook}

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

# Run one hook with the aliprehook environment. Returns its exit code.
_aliprehook_exec() {
  emulate -L zsh
  local layer=$1 key=$2 cmd=$3 hook=$4 rc
  shift 4

  if [[ ! -f $hook ]]; then
    print -u2 "aliprehook: $layer hook not found: $hook"
    return 1
  fi
  if [[ ! -x $hook ]]; then
    print -u2 "aliprehook: $layer hook not executable: $hook (run: chmod +x $hook)"
    return 1
  fi
  ALIPREHOOK_PROJECT_KEY=$key ALIPREHOOK_COMMAND=$cmd $hook "$@"
  rc=$?
  if (( rc != 0 )); then
    print -u2 "aliprehook: $cmd aborted: $layer hook exited $rc ($hook)"
  fi
  return $rc
}

# Run prehooks for <cmd_name>: user layer, then project layer if allowed.
# Extra args are passed to the hooks. Returns non-zero if a hook fails.
aliprehook_run() {
  emulate -L zsh -o extended_glob
  local cmd=$1 key hook root rel
  shift

  [[ -n $cmd ]] || { print -u2 "aliprehook_run: missing command name"; return 2; }

  key=$(aliprehook_project_key)

  # User layer: every matching registry hook, in order; first failure stops.
  local -a hooks
  hooks=("${(@f)$(aliprehook_registry_lookup $key $cmd)}")
  for hook in $hooks; do
    [[ -n $hook ]] || continue
    _aliprehook_exec user $key $cmd $hook "$@" || return $?
  done

  # Project layer: git repos only, and only if allowed.
  root=$(command git rev-parse --show-toplevel 2>/dev/null) || return 0
  [[ -n $root && -f $root/.aliprehook.yml ]] || return 0
  aliprehook_is_allowed $key || return 0
  local problems
  if ! problems=$(aliprehook_project_check $root); then
    print -u2 -r -- "${(F)${(@f)problems/#/aliprehook: warning: }}"
    print -u2 "aliprehook: warning: invalid entries ignored; fix $root/.aliprehook.yml"
  fi
  rel=$(aliprehook_project_lookup $root $cmd) || return 0

  root=${root:A}
  if [[ $rel == /* ]]; then
    print -u2 "aliprehook: project hook must be a relative path: $rel"
    return 1
  fi
  hook=${${:-$root/$rel}:A}
  if [[ $hook != $root/* ]]; then
    print -u2 "aliprehook: project hook outside the repo: $rel"
    return 1
  fi
  ALIPREHOOK_PROJECT_ROOT=$root _aliprehook_exec project $key $cmd $hook "$@"
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
        print -u2 "aliprehook allow: no .aliprehook.yml in this git repo"
        return 1
      fi
      if ! line=$(aliprehook_project_check $root); then
        print -u2 -r -- "${(F)${(@f)line/#/aliprehook allow: }}"
        print -u2 "aliprehook allow: not allowed; fix $root/.aliprehook.yml first"
        return 1
      fi
      key=$(aliprehook_project_key)
      if aliprehook_is_allowed $key; then
        print "aliprehook: already allowed: $key"
        return 0
      fi
      mkdir -p $ALIPREHOOK_HOME
      print -r -- $key >> $allowed
      print "aliprehook: allowed $key"
      print "  project hooks from $root/.aliprehook.yml will now run"
      ;;
    revoke)
      key=$(aliprehook_project_key)
      if ! aliprehook_is_allowed $key; then
        print "aliprehook: not allowed: $key"
        return 0
      fi
      tmp=$allowed.tmp.$$
      while IFS= read -r line; do
        [[ ${line//[[:space:]]/} == "$key" ]] || print -r -- $line
      done < $allowed > $tmp && mv $tmp $allowed
      print "aliprehook: revoked $key"
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
      print -u2 "aliprehook: unknown command: $sub (see: aliprehook help)"
      return 2
      ;;
  esac
}

# Define <name> as a shell function that runs prehooks, then <command...> "$@".
aliprehook_define() {
  emulate -L zsh -o extended_glob
  local name=$1 body
  shift

  if [[ -z $name || $# -eq 0 ]]; then
    print -u2 "usage: aliprehook_define <name> <command...>"
    return 2
  fi
  if [[ $name != [A-Za-z_][A-Za-z0-9_-]# ]]; then
    print -u2 "aliprehook_define: invalid name: $name"
    return 2
  fi

  # Calling the same name inside the wrapper would recurse.
  [[ $1 == $name ]] && set -- command "$@"

  body="aliprehook_run ${(q)name} \"\$@\" || return \$?; ${(j: :)${(q)@}} \"\$@\""
  unalias $name 2>/dev/null
  eval "function ${(q)name} { $body; }"
}
