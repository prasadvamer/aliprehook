source $ALIPREHOOK_ROOT/tests/helpers.zsh

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
export ALIPREHOOK_HOME=$tmp/aliprehook

# Fresh install creates the user layer.
$ALIPREHOOK_ROOT/install.sh >/dev/null || fail "install.sh exited non-zero"
assert_link $ALIPREHOOK_HOME/lib.zsh
assert_link $ALIPREHOOK_HOME/README.md
assert_link $ALIPREHOOK_HOME/bin/aliprehook_env_pass
assert_link $ALIPREHOOK_HOME/themes/purple.theme
assert_link $ALIPREHOOK_HOME/themes/none.theme
assert_file $ALIPREHOOK_HOME/hooks.map
assert_file $ALIPREHOOK_HOME/allowed-repos
assert_file $ALIPREHOOK_HOME/commands.map
[[ -n $(find $ALIPREHOOK_HOME/commands.map -perm -g+w -o -perm -o+w) ]] && fail "commands writable by group/others"
assert_dir  $ALIPREHOOK_HOME/hooks
assert_file $ALIPREHOOK_HOME/hooks/example_echo.sh
[[ -x $ALIPREHOOK_HOME/hooks/example_echo.sh ]] || fail "example_echo.sh not executable"
grep -q 'hooks/example_echo.sh' $ALIPREHOOK_HOME/hooks.map || fail "registry template missing example line"

# lib.zsh loads cleanly.
out=$(zsh -fc "source $ALIPREHOOK_HOME/lib.zsh && print -r -- \$ALIPREHOOK_HOME" 2>&1)
assert_eq $ALIPREHOOK_HOME "$out" "source lib.zsh"

# Reinstall keeps user data.
print 'github.com/org/sample_app_web  Dup hooks/x.sh' >> $ALIPREHOOK_HOME/hooks.map
print '# edited' >> $ALIPREHOOK_HOME/hooks/example_echo.sh
print 'github.com/org/sample_app_web  Dbuild  make build' >> $ALIPREHOOK_HOME/commands.map
$ALIPREHOOK_ROOT/install.sh >/dev/null || fail "reinstall exited non-zero"
grep -q sample_app_web $ALIPREHOOK_HOME/hooks.map || fail "reinstall overwrote registry"
grep -q '# edited' $ALIPREHOOK_HOME/hooks/example_echo.sh || fail "reinstall overwrote example_echo.sh"
grep -q 'make build' $ALIPREHOOK_HOME/commands.map || fail "reinstall overwrote commands"

# --copy installs real files.
rm -rf $ALIPREHOOK_HOME
$ALIPREHOOK_ROOT/install.sh --copy >/dev/null || fail "install.sh --copy exited non-zero"
[[ ! -L $ALIPREHOOK_HOME/lib.zsh ]] || fail "--copy made a symlink"
assert_file $ALIPREHOOK_HOME/lib.zsh
[[ ! -L $ALIPREHOOK_HOME/bin/aliprehook_env_pass && -x $ALIPREHOOK_HOME/bin/aliprehook_env_pass ]] || fail "--copy: aliprehook_env_pass not an executable copy"

[[ -f $ALIPREHOOK_HOME/themes/purple.theme && ! -L $ALIPREHOOK_HOME/themes/purple.theme ]] || fail "--copy: theme not copied"

# Copy install: lib.zsh finds bin/ next to itself.
out=$(zsh -fc "source $ALIPREHOOK_HOME/lib.zsh && print -r -- \$ALIPREHOOK_LIB_DIR" 2>&1)
assert_eq ${ALIPREHOOK_HOME:A} "$out" "copy install: ALIPREHOOK_LIB_DIR"

# Unknown flag is rejected.
$ALIPREHOOK_ROOT/install.sh --bogus 2>/dev/null && fail "unknown flag accepted"

finish
