source $ALIPREHOOK_ROOT/tests/helpers.zsh

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
export ALIPREHOOK_HOME=$tmp/aliprehook

# Fresh install creates the user layer.
$ALIPREHOOK_ROOT/install.sh >/dev/null || fail "install.sh exited non-zero"
assert_link $ALIPREHOOK_HOME/lib.zsh
assert_link $ALIPREHOOK_HOME/README.md
assert_file $ALIPREHOOK_HOME/registry
assert_file $ALIPREHOOK_HOME/allowed
assert_dir  $ALIPREHOOK_HOME/hooks

# lib.zsh loads cleanly.
out=$(zsh -fc "source $ALIPREHOOK_HOME/lib.zsh && print -r -- \$ALIPREHOOK_HOME" 2>&1)
assert_eq $ALIPREHOOK_HOME "$out" "source lib.zsh"

# Reinstall keeps user data.
print 'github.com/org/sample_app_web  Dup hooks/x.sh' >> $ALIPREHOOK_HOME/registry
$ALIPREHOOK_ROOT/install.sh >/dev/null || fail "reinstall exited non-zero"
grep -q sample_app_web $ALIPREHOOK_HOME/registry || fail "reinstall overwrote registry"

# --copy installs real files.
rm -rf $ALIPREHOOK_HOME
$ALIPREHOOK_ROOT/install.sh --copy >/dev/null || fail "install.sh --copy exited non-zero"
[[ ! -L $ALIPREHOOK_HOME/lib.zsh ]] || fail "--copy made a symlink"
assert_file $ALIPREHOOK_HOME/lib.zsh

# Unknown flag is rejected.
$ALIPREHOOK_ROOT/install.sh --bogus 2>/dev/null && fail "unknown flag accepted"

finish
