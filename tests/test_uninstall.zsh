source $ALIPREHOOK_ROOT/tests/helpers.zsh

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
export HOME=$tmp/home ZDOTDIR=$tmp/home
export ALIPREHOOK_HOME=$tmp/aliprehook
mkdir -p $HOME

$ALIPREHOOK_ROOT/install.sh >/dev/null || fail "install.sh exited non-zero"

# User data to protect.
print 'github.com/org/sample_app_web  Dup hooks/sample_app_web_Dup.sh' >> $ALIPREHOOK_HOME/registry
print 'github.com/org/sample_app_web' >> $ALIPREHOOK_HOME/allowed
print 'echo hi' > $ALIPREHOOK_HOME/hooks/sample_app_web_Dup.sh
before=$(cd $ALIPREHOOK_HOME && cat registry allowed hooks/sample_app_web_Dup.sh)

# Uninstall removes managed files only.
$ALIPREHOOK_ROOT/uninstall.sh >/dev/null 2>&1 || fail "uninstall.sh exited non-zero"
[[ ! -e $ALIPREHOOK_HOME/lib.zsh && ! -L $ALIPREHOOK_HOME/lib.zsh ]] || fail "lib.zsh not removed"
[[ ! -e $ALIPREHOOK_HOME/README.md && ! -L $ALIPREHOOK_HOME/README.md ]] || fail "README.md not removed"
after=$(cd $ALIPREHOOK_HOME && cat registry allowed hooks/sample_app_web_Dup.sh)
assert_eq "$before" "$after" "user data unchanged"

# Second run is a no-op.
$ALIPREHOOK_ROOT/uninstall.sh >/dev/null 2>&1 || fail "second uninstall exited non-zero"

# Not installed at all is fine.
ALIPREHOOK_HOME=$tmp/none $ALIPREHOOK_ROOT/uninstall.sh >/dev/null || fail "uninstall with no install dir failed"

# Copy install is removed too.
$ALIPREHOOK_ROOT/install.sh --copy >/dev/null
$ALIPREHOOK_ROOT/uninstall.sh >/dev/null 2>&1
[[ ! -e $ALIPREHOOK_HOME/lib.zsh ]] || fail "copied lib.zsh not removed"

# Warns about ~/.zshrc, without editing it.
print 'source ~/.config/aliprehook/lib.zsh' > $HOME/.zshrc
$ALIPREHOOK_ROOT/install.sh >/dev/null
err=$($ALIPREHOOK_ROOT/uninstall.sh 2>&1 >/dev/null)
[[ $err == *warning*zshrc* ]] || fail "no .zshrc warning: '$err'"
assert_eq 'source ~/.config/aliprehook/lib.zsh' "$(<$HOME/.zshrc)" ".zshrc untouched"

# Reinstall after uninstall works and keeps data.
$ALIPREHOOK_ROOT/install.sh >/dev/null || fail "reinstall failed"
assert_link $ALIPREHOOK_HOME/lib.zsh
after=$(cd $ALIPREHOOK_HOME && cat registry allowed hooks/sample_app_web_Dup.sh)
assert_eq "$before" "$after" "user data kept across reinstall"

# Unknown argument is rejected.
$ALIPREHOOK_ROOT/uninstall.sh --purge 2>/dev/null && fail "unknown argument accepted"

finish
