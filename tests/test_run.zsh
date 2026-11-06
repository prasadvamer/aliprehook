source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
tmp=${tmp:A}
ALIPREHOOK_HOME=$tmp/home
mkdir -p $ALIPREHOOK_HOME/hooks $tmp/other

git init -q $tmp/repo
git -C $tmp/repo remote add origin git@github.com:org/sample_app_web.git
key=github.com/org/sample_app_web

log=$tmp/log
hook() {  # name exit_code
  print -r -- "#!/bin/sh
echo \"hook:\$ALIPREHOOK_PROJECT_KEY:\$ALIPREHOOK_COMMAND:\$*\" >> $log
exit $2" > $ALIPREHOOK_HOME/hooks/$1
  chmod +x $ALIPREHOOK_HOME/hooks/$1
}
hook ok.sh 0
hook ok2.sh 0
hook fail.sh 3
print '#!/bin/sh' > $ALIPREHOOK_HOME/hooks/noexec.sh

cat > $ALIPREHOOK_HOME/hooks.map <<REG
# comment line
   # indented comment

$key  Dup     hooks/ok.sh
$key  Dup     hooks/ok2.sh
$key  Fail    hooks/fail.sh
$key  Missing hooks/nope.sh
$key  NoExec  hooks/noexec.sh
$key  Abs     $ALIPREHOOK_HOME/hooks/ok2.sh
$tmp/other  Dup  hooks/ok2.sh
REG

reset() { : > $log; }
logged() { print -r -- "$(<$log)"; }

# --- aliprehook_run ---

cd $tmp/repo

reset; aliprehook_run Dup a "b c"; rc=$?
assert_eq 0 $rc "match: exit 0"
assert_eq "hook:${key}:Dup:a b c
hook:${key}:Dup:a b c" "$(logged)" "match: all matching lines run, env + args"

reset; aliprehook_run Other; rc=$?
assert_eq 0 $rc "unknown command: exit 0"
assert_eq "" "$(logged)" "unknown command: no hook"

reset; aliprehook_run Fail 2>/dev/null; rc=$?
assert_eq 3 $rc "failing hook: exit code passed through"

reset; err=$(aliprehook_run Missing 2>&1); rc=$?
assert_eq 1 $rc "missing hook: exit 1"
[[ $err == *"hook not found"* ]] || fail "missing hook: message '$err'"

reset; err=$(aliprehook_run NoExec 2>&1); rc=$?
assert_eq 1 $rc "non-executable hook: exit 1"
[[ $err == *"chmod +x"* ]] || fail "non-executable hook: message '$err'"

reset; aliprehook_run Abs
assert_eq "hook:${key}:Abs:" "$(logged)" "absolute hook path"

cd $tmp/repo/.. && mkdir -p unregistered && cd unregistered
reset; aliprehook_run Dup
assert_eq "" "$(logged)" "no match in other project"

cd $tmp/other
reset; aliprehook_run Dup
assert_eq "hook:${tmp}/other:Dup:" "$(logged)" "path-key match"

# No registry at all.
cd $tmp/repo
mv $ALIPREHOOK_HOME/hooks.map $tmp/registry.bak
reset; aliprehook_run Dup; rc=$?
assert_eq 0 $rc "no registry: exit 0"
assert_eq "" "$(logged)" "no registry: no hook"
mv $tmp/registry.bak $ALIPREHOOK_HOME/hooks.map

# --- aliprehook_define ---

main() { print -r -- "main:${(j:|:)@}" >> $log; }

aliprehook_define Dup main up
reset; Dup --watch "x y"; rc=$?
assert_eq 0 $rc "define: exit 0"
assert_eq "hook:${key}:Dup:--watch x y
hook:${key}:Dup:--watch x y
main:up|--watch|x y" "$(logged)" "define: hooks then main, args pass through"

aliprehook_define Fail main up
reset; Fail 2>/dev/null; rc=$?
assert_eq 3 $rc "define: failing hook exit code"
assert_eq "hook:${key}:Fail:" "$(logged)" "define: main not run after failing hook"

cd $tmp/unregistered
reset; Dup -d
assert_eq "main:up|-d" "$(logged)" "define: no hook, main still runs"
cd $tmp/repo

# Same name as the wrapped command does not recurse.
aliprehook_define printf printf
assert_eq "x-y" "$(printf '%s-%s' x y)" "define: same-name command"

# Replaces an existing alias.
alias Al='print alias'
aliprehook_define Al main al
reset; eval 'Al'
assert_eq "main:al" "$(logged)" "define: replaces alias"

# Arguments with special characters survive.
aliprehook_define Quote main "it's" '$HOME' 'a;b'
reset; Quote
assert_eq 'main:it'"'"'s|$HOME|a;b' "$(logged)" "define: quoting"

# Usage errors.
aliprehook_define 2>/dev/null && fail "define with no args accepted"
aliprehook_define Lonely 2>/dev/null && fail "define with no command accepted"
aliprehook_define 'bad name' x 2>/dev/null && fail "define with invalid name accepted"

# --- example hook ---
out=$(ALIPREHOOK_PROJECT_KEY=k ALIPREHOOK_COMMAND=Dup $ALIPREHOOK_ROOT/hooks/example_echo.sh --watch 2>&1 >/dev/null); rc=$?
assert_eq 0 $rc "example_echo exit 0"
[[ $out == *"project key: k"*"command:     Dup --watch"* ]] || fail "example_echo output: '$out'"

finish
