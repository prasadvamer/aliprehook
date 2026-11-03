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

# Print the hook path registered for (project key, command), if any.
# First matching registry line wins. Relative paths are under ALIPREHOOK_HOME.
aliprehook_registry_lookup() {
  emulate -L zsh -o extended_glob
  local key=$1 cmd=$2 k c h
  local registry=$ALIPREHOOK_HOME/registry

  [[ -r $registry ]] || return 1

  while read -r k c h _; do
    [[ -z $k || $k == \#* ]] && continue
    if [[ $k == "$key" && $c == "$cmd" && -n $h ]]; then
      [[ $h == /* ]] || h=$ALIPREHOOK_HOME/$h
      print -r -- $h
      return 0
    fi
  done < $registry

  return 1
}

# Run prehooks for <cmd_name>. Extra args are passed to the hook.
# Returns non-zero (the hook's exit code) if a hook fails.
aliprehook_run() {
  emulate -L zsh -o extended_glob
  local cmd=$1 key hook rc
  shift

  [[ -n $cmd ]] || { print -u2 "aliprehook_run: missing command name"; return 2; }

  key=$(aliprehook_project_key)

  # User layer.
  if hook=$(aliprehook_registry_lookup $key $cmd); then
    if [[ ! -f $hook ]]; then
      print -u2 "aliprehook: hook not found: $hook (registry: $key $cmd)"
      return 1
    fi
    if [[ ! -x $hook ]]; then
      print -u2 "aliprehook: hook not executable: $hook (run: chmod +x $hook)"
      return 1
    fi
    ALIPREHOOK_PROJECT_KEY=$key ALIPREHOOK_COMMAND=$cmd $hook "$@"
    rc=$?
    if (( rc != 0 )); then
      print -u2 "aliprehook: $cmd aborted: hook exited $rc ($hook)"
      return $rc
    fi
  fi

  return 0
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
