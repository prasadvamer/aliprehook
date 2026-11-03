source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh

# Isolate from the user's git config (e.g. url.insteadOf).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
tmp=${tmp:A}

key_in() { (cd $1 && aliprehook_project_key); }

# No git: physical path, even through a symlink.
mkdir -p $tmp/plain
ln -s $tmp/plain $tmp/link
assert_eq $tmp/plain "$(key_in $tmp/plain)" "no git"
assert_eq $tmp/plain "$(key_in $tmp/link)" "no git via symlink"

# Git with no remotes: path fallback.
git init -q $tmp/noremote
assert_eq $tmp/noremote "$(key_in $tmp/noremote)" "git, no remotes"

# origin wins over other remotes.
git init -q $tmp/both
git -C $tmp/both remote add aaa https://github.com/org/first.git
git -C $tmp/both remote add origin git@github.com:org/sample_app_web.git
assert_eq github.com/org/sample_app_web "$(key_in $tmp/both)" "origin preferred"

# Non-origin remote only: first fetch remote.
git init -q $tmp/upstream
git -C $tmp/upstream remote add upstream ssh://git@github.com/org/sample_app_api.git
assert_eq github.com/org/sample_app_api "$(key_in $tmp/upstream)" "non-origin remote"

# Subdirectory of a repo gives the same key.
mkdir -p $tmp/both/a/b
assert_eq github.com/org/sample_app_web "$(key_in $tmp/both/a/b)" "subdirectory"

# Inside .git (not a work tree): path fallback.
assert_eq $tmp/both/.git "$(key_in $tmp/both/.git)" "inside .git dir"

finish
