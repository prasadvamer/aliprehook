source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
tmp=${tmp:A}
ALIPREHOOK_HOME=$tmp/home
mkdir -p $ALIPREHOOK_HOME/hooks
cp $ALIPREHOOK_ROOT/templates/allowed-repos $ALIPREHOOK_HOME/allowed-repos
: > $ALIPREHOOK_HOME/hooks.map

repo=$tmp/repo
key=github.com/org/sample_app_web
git init -q $repo
git -C $repo remote add origin git@github.com:org/sample_app_web.git
other=$tmp/other
mkdir -p $other
cd $repo

cmds() { print -rl -- "$@" > $ALIPREHOOK_HOME/commands.map; chmod 600 $ALIPREHOOK_HOME/commands.map; }
reg() { print -rl -- "$@" > $ALIPREHOOK_HOME/hooks.map; }
uhook() {  # name body (sh)
  print -r -- "#!/bin/sh
$2" > $ALIPREHOOK_HOME/hooks/$1
  chmod +x $ALIPREHOOK_HOME/hooks/$1
}
args() { print -r -- "${(j:|:)@}"; }   # main command default: show arguments

aliprehook_define B args default

# --- no file / no match → default ---
assert_eq "default|x" "$(B x)" "no commands file: default"
cmds "github.com/org/other_repo  B  echo other"
assert_eq "default|x" "$(B x)" "no matching key: default"
cmds "$key  Other  echo other"
assert_eq "default|x" "$(B x)" "no matching command: default"

# --- exact key wins; other projects get the default ---
cmds "# comment" "" "$key  B  args line"
assert_eq "line|x|y z" "$(B x 'y z')" "exact key: line runs, args appended intact"
assert_eq "default|x" "$(cd $other && B x)" "other project: default"

# --- shell syntax: env prefix, $(…), && ---
cmds "$key  B  FOO=bar REV=\$(print -r abc) sh -c 'echo \$FOO-\$REV' && echo done"
assert_eq "bar-abc
done" "$(B)" "env prefix, \$(…) and && work"

# --- "$@" placement: not appended again ---
cmds "$key  B  args first \"\$@\" last"
assert_eq "first|a|b c|last" "$(B a 'b c')" "\"\$@\" placement"
cmds "$key  B  args \$*"
assert_eq "a|b" "$(B a b)" "\$* placement"

# --- subshell: cd and assignments do not leak ---
cmds "$key  B  cd / && LEAK=1 && export LEAK2=1 && pwd"
assert_eq "/" "$(B)" "cd inside line"
B >/dev/null
assert_eq "$repo" "$PWD" "cd did not change the shell"
assert_eq "<unset>|<unset>" "${LEAK-<unset>}|${LEAK2-<unset>}" "assignments did not leak"

# --- exit code passed through ---
cmds "$key  B  return 7"
B; assert_eq 7 $? "exit code from line"
cmds "$key  B  sh -c 'exit 5'"
B; assert_eq 5 $? "exit code from program"

# --- hook-passed variable usable in the line, not left in the shell ---
uhook rev.sh 'aliprehook_env_pass REVISION=abc123'
reg "$key  B  hooks/rev.sh"
cmds "$key  B  echo rev=\$REVISION"
assert_eq "rev=abc123" "$(B)" "hook variable in line"
B >/dev/null
assert_eq "<unset>" "${REVISION-<unset>}" "hook variable not left in shell"

# --- failing hook → command not run ---
uhook fail.sh 'exit 3'
reg "$key  B  hooks/fail.sh"
cmds "$key  B  echo SHOULD-NOT-RUN"
out=$(B 2>/dev/null); rc=$?
assert_eq 3 $rc "failing hook exit code"
assert_eq "" "$out" "failing hook: line not run"
reg

# --- --keep-env still keeps user vars; line itself never changes the shell ---
uhook keep.sh 'aliprehook_env_pass KEPT=1'
reg "$key  K  hooks/keep.sh"
aliprehook_define --keep-env K args default
cmds "$key  K  echo kept=\$KEPT; MINE=1"
assert_eq "kept=1" "$(K)" "--keep-env: line sees var"
K >/dev/null
assert_eq "1|<unset>" "${KEPT-<unset>}|${MINE-<unset>}" "--keep-env: var kept, line assignment not"
unset KEPT
reg

# --- duplicate lines: first wins + warning ---
cmds "$key  B  echo first" "$key  B  echo second"
out=$(B 2>$tmp/err)
assert_eq "first" "$out" "duplicate: first wins"
[[ $(<$tmp/err) == *"warning: $ALIPREHOOK_HOME/commands.map:2: duplicate line for B in this project; using line 1"* ]] || fail "duplicate warning: '$(<$tmp/err)'"

# --- `*` line: error, nothing runs (not even hooks) ---
uhook mark.sh "touch $tmp/hook-ran"
reg "$key  B  hooks/mark.sh"
cmds "*  B  echo star"
out=$(B 2>$tmp/err); rc=$?
assert_eq 1 $rc "* line: non-zero"
assert_eq "" "$out" "* line: nothing runs"
[[ ! -e $tmp/hook-ran ]] || fail "* line: hook ran"
err=$(<$tmp/err)
[[ $err == *"error: $ALIPREHOOK_HOME/commands.map:1: '*' is not allowed in commands; change the default in aliprehook_define B … instead"* ]] || fail "* error: '$err'"
[[ $err == *"B aborted: fix $ALIPREHOOK_HOME/commands.map"* ]] || fail "* aborted: '$err'"
# A `*` line for another command does not affect B.
cmds "*  Other  echo star"
assert_eq "default" "$(B 2>/dev/null)" "* for other command ignored"
reg

# --- empty command part: error ---
cmds "$key  B"
out=$(B 2>$tmp/err); rc=$?
assert_eq 1 $rc "empty line: non-zero"
[[ $(<$tmp/err) == *"error: $ALIPREHOOK_HOME/commands.map:1: no command line for B"* ]] || fail "empty error: '$(<$tmp/err)'"

# --- group- or world-writable file refused ---
for m in 620 602; do
  cmds "$key  B  echo line"
  chmod $m $ALIPREHOOK_HOME/commands.map
  out=$(B 2>$tmp/err); rc=$?
  assert_eq 1 $rc "mode $m: refused"
  assert_eq "" "$out" "mode $m: nothing runs"
  [[ $(<$tmp/err) == *"is writable by group or others; ignored (run: chmod go-w $ALIPREHOOK_HOME/commands.map)"* ]] || fail "mode $m error: '$(<$tmp/err)'"
done
chmod 644 $ALIPREHOOK_HOME/commands.map
assert_eq "line" "$(B)" "mode 644 accepted"

# --- hook-only command overridden per project ---
aliprehook_define H :
cmds "$key  H  echo real"
assert_eq "real" "$(H)" "hook-only: line runs here"
assert_eq "" "$(cd $other && H)" "hook-only: : elsewhere"

# --- aliprehook_command in a Case B function ---
uhook cb.sh 'aliprehook_env_pass CBV=v'
reg "$key  C  hooks/cb.sh"
C() {
  aliprehook_run C "$@" || return $?
  aliprehook_command C args default -- "$@"
}
cmds "$key  C  echo cb=\$CBV \"\$@\""
assert_eq "cb=v a b" "$(C a b)" "aliprehook_command: line with var and args"
assert_eq "default|a|b c" "$(cd $other && C a 'b c')" "aliprehook_command: default + args"
aliprehook_command C 2>/dev/null; assert_eq 2 $? "aliprehook_command: usage error"
reg

# --- .aliprehook.yml commands: section ignored with a warning ---
cat > $repo/.aliprehook.yml <<'YML'
hooks:
  Dup: .aliprehook/x.sh
commands:
  B: rm -rf /
YML
: > $ALIPREHOOK_HOME/commands.map
aliprehook allow >/dev/null 2>$tmp/err || fail "allow failed"
[[ $(<$tmp/err) == *"warning: $repo/.aliprehook.yml: commands: section ignored"* ]] || fail "allow warning: '$(<$tmp/err)'"
out=$(B 2>$tmp/err)
assert_eq "default" "$out" "yml commands: ignored"
[[ $(<$tmp/err) == *"commands: section ignored"* ]] || fail "run warning: '$(<$tmp/err)'"

finish
