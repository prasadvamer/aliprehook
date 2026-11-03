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
  emulate -L zsh
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
