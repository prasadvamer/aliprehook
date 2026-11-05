source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
tmp=${tmp:A}
ALIPREHOOK_HOME=$tmp/home
mkdir -p $ALIPREHOOK_HOME/hooks $tmp/rt
export XDG_RUNTIME_DIR=$tmp/rt   # temp files land here, so leftovers can be checked
cp $ALIPREHOOK_ROOT/templates/allowed $ALIPREHOOK_HOME/allowed

repo=$tmp/repo
key=github.com/org/sample_app_web
git init -q $repo
git -C $repo remote add origin git@github.com:org/sample_app_web.git
cd $repo

uhook() {  # name body (sh)
  print -r -- "#!/bin/sh
$2" > $ALIPREHOOK_HOME/hooks/$1
  chmod +x $ALIPREHOOK_HOME/hooks/$1
}
reg() { print -rl -- "$@" > $ALIPREHOOK_HOME/registry; }

# Main command: print selected variables.
show() { local v; for v in "$@"; do print -r -- "$v=${(P)v-<unset>}"; done; }
leftovers() { print -r -- ${#${(@f)"$(command ls -A $tmp/rt)"}:#}; }

# --- basic: several names, NAME=value, mixed ---
uhook a.sh 'export A=1 B="two words"; aliprehook_env_pass A B C=three'
reg "$key  T  hooks/a.sh"
aliprehook_define T show A B C
assert_eq "A=1
B=two words
C=three" "$(T)" "several names + NAME=value reach main command"

# Terminal unchanged afterwards.
T >/dev/null
assert_eq "<unset>" "${A-<unset>}" "A not left in shell"
assert_eq "<unset>" "${C-<unset>}" "C not left in shell"
assert_eq 0 "$(leftovers)" "temp file removed after success"

# --- missing optional: warning, still runs ---
uhook opt.sh 'NOTEXP=x; export EMPTY=; aliprehook_env_pass UNSET_ONE NOTEXP EMPTY OK=1'
reg "$key  T  hooks/opt.sh"
aliprehook_define T show OK NOTEXP
out=$(T 2>$tmp/err); rc=$?
assert_eq 0 $rc "optional missing: command runs"
assert_eq "OK=1
NOTEXP=<unset>" "$out" "optional missing: only present ones passed"
err=$(<$tmp/err)
for v in UNSET_ONE NOTEXP EMPTY; do
  [[ $err == *"warning: opt.sh: $v has no value (unset, empty or not exported); not passed to T"* ]] || fail "warning for $v: '$err'"
done

# --- --allow-empty anywhere ---
uhook empty.sh 'export E=; aliprehook_env_pass E --allow-empty F='
reg "$key  T  hooks/empty.sh"
aliprehook_define T show E F
assert_eq "E=
F=" "$(T 2>&1)" "--allow-empty passes empty values"

# --- required / optional switches, both orders; all missing reported; hook exits 0 ---
typeset -i i=0
for args in '--required R1 R2 --optional O1' 'O1 --required R1 R2'; do
  (( i++ ))
  uhook req$i.sh "export R1=ok; aliprehook_env_pass $args; echo after >> $tmp/after$i; exit 0"
  reg "$key  T  hooks/req$i.sh"
  aliprehook_define T show R1
  out=$(T 2>$tmp/err); rc=$?
  err=$(<$tmp/err)
  assert_eq 1 $rc "required missing ($args): exit 1"
  assert_eq "" "$out" "required missing ($args): main not run"
  [[ $err == *"error: req$i.sh: R2 has no value (required)"* ]] || fail "required error ($args): '$err'"
  [[ $err == *"warning: req$i.sh: O1 has no value"* ]] || fail "optional warning ($args): '$err'"
  [[ $err == *"T aborted: required variable missing: R2"* ]] || fail "abort message ($args): '$err'"
  [[ -f $tmp/after$i ]] || fail "hook kept running after the call ($args)"
done

uhook req_many.sh 'aliprehook_env_pass --required X1 X2 X3'
reg "$key  T  hooks/req_many.sh"
err=$(T 2>&1)
[[ $err == *"required variable missing: X1, X2, X3"* ]] || fail "all missing reported together: '$err'"

# Required present: runs.
uhook req_ok.sh 'export R=1; aliprehook_env_pass --required R'
reg "$key  T  hooks/req_ok.sh"
aliprehook_define T show R
assert_eq "R=1" "$(T)" "required present: runs"

# --- --hint: shown after required errors only, placement anywhere ---
for args in '--hint "run: aws-login" O1 --required R1 R2' 'O1 --required R1 R2 --hint "run: aws-login"' '--required R1 --hint "run: aws-login" R2 --optional O1'; do
  uhook hint.sh "aliprehook_env_pass $args; echo hook-rc=\$? >&2"
  reg "$key  T  hooks/hint.sh"
  aliprehook_define T show R1
  out=$(T 2>$tmp/err); rc=$?
  err=$(<$tmp/err)
  assert_eq 1 $rc "hint ($args): exit 1"
  assert_eq "" "$out" "hint ($args): main not run"
  [[ $err == *"hook-rc=1"* ]] || fail "hint ($args): helper exit: '$err'"
  for v in R1 R2; do
    [[ $err == *"error: hint.sh: $v has no value (required) (run: aws-login)"* ]] || fail "hint ($args) for $v: '$err'"
  done
  [[ $err == *"O1 has no value (unset, empty or not exported); not passed to T"$'\n'* ]] || fail "hint ($args): optional warning: '$err'"
  [[ $err == *"not passed to T ("* ]] && fail "hint ($args): shown for optional: '$err'"
  [[ $err == *"T aborted: required variable missing: R1, R2"* ]] || fail "hint ($args): aborted: '$err'"
done
# Hint value is not taken as a variable name; present values still pass.
uhook hint_ok.sh 'export R=1; aliprehook_env_pass --hint "run: x" --required R'
reg "$key  T  hooks/hint_ok.sh"
aliprehook_define T show R
assert_eq "R=1" "$(T 2>&1)" "hint: present value passes, no message"

# --- multi-line values ---
uhook multi.sh 'aliprehook_env_pass M="line one
line two" TRAIL="x
"'
reg "$key  T  hooks/multi.sh"
aliprehook_define T show M
assert_eq "M=line one
line two" "$(T)" "multi-line value"
aliprehook_define T2 :
reg "$key  T2  hooks/multi.sh"
aliprehook_run T2
assert_eq $'x\n' "${_aliprehook_env[TRAIL]}" "trailing newline kept"
_aliprehook_env=()

# --- usage errors in the helper ---
uhook bad.sh 'aliprehook_env_pass 9BAD'
reg "$key  T  hooks/bad.sh"
err=$(T 2>&1) && fail "invalid name accepted"
[[ $err == *"invalid variable name: 9BAD"* ]] || fail "invalid name message: '$err'"
uhook resv.sh 'aliprehook_env_pass ALIPREHOOK_X=1'
reg "$key  T  hooks/resv.sh"
err=$(T 2>&1) && fail "reserved name accepted"
[[ $err == *"reserved variable name: ALIPREHOOK_X"* ]] || fail "reserved message: '$err'"
for args in '--hint a --hint b R' 'R --hint' "--hint '' R" '--hint x'; do
  uhook badhint.sh "aliprehook_env_pass $args; echo rc=\$?"
  reg "$key  T  hooks/badhint.sh"
  aliprehook_define T show R
  out=$(T 2>$tmp/err)
  [[ $out == *"rc=2"* ]] || fail "bad --hint ($args): want exit 2, got '$out' / '$(<$tmp/err)'"
done
[[ $(T 2>&1) == *"usage: aliprehook_env_pass [--allow-empty] [--hint TEXT]"* ]] || fail "usage shows --hint"
err=$(env -u ALIPREHOOK_ENV_FILE $ALIPREHOOK_ROOT/bin/aliprehook_env_pass A 2>&1); rc=$?
assert_eq 2 $rc "outside a hook: exit 2"
[[ $err == *"must be run from an aliprehook hook"* ]] || fail "outside hook message: '$err'"

# --- bash, python, and a hook that resets PATH ---
print -r -- '#!/usr/bin/env bash
declare -x BASHVAR=b; aliprehook_env_pass BASHVAR' > $ALIPREHOOK_HOME/hooks/b.sh
print -r -- '#!/usr/bin/env python3
import os, subprocess
subprocess.run([os.environ["ALIPREHOOK_ENV_PASS_BIN"], "PYVAR=p"], check=True)' > $ALIPREHOOK_HOME/hooks/p.py
uhook nopath.sh 'PATH=/nonexistent; export NP=n; "$ALIPREHOOK_ENV_PASS_BIN" NP'
chmod +x $ALIPREHOOK_HOME/hooks/b.sh $ALIPREHOOK_HOME/hooks/p.py
reg "$key  T  hooks/b.sh" "$key  T  hooks/p.py" "$key  T  hooks/nopath.sh"
aliprehook_define T show BASHVAR PYVAR NP
assert_eq "BASHVAR=b
PYVAR=p
NP=n" "$(T)" "bash, python and PATH-resetting hooks"

# --- hooks writing the file directly; malformed line stops command ---
uhook direct.sh 'printf "D=direct\n" >> "$ALIPREHOOK_ENV_FILE"'
reg "$key  T  hooks/direct.sh"
aliprehook_define T show D
assert_eq "D=direct" "$(T)" "direct write"
uhook malformed.sh 'printf "D=ok\nnot a valid line\n" >> "$ALIPREHOOK_ENV_FILE"'
reg "$key  T  hooks/malformed.sh"
out=$(T 2>$tmp/err); rc=$?
assert_eq 1 $rc "malformed: exit 1"
assert_eq "" "$out" "malformed: main not run"
[[ $(<$tmp/err) == *"malformed.sh: ALIPREHOOK_ENV_FILE: line 2: expected NAME=value"* ]] || fail "malformed message: '$(<$tmp/err)'"
uhook unclosed.sh 'printf "M<<END\nx\n" >> "$ALIPREHOOK_ENV_FILE"'
reg "$key  T  hooks/unclosed.sh"
err=$(T 2>&1) && fail "unclosed block accepted"
[[ $err == *"M<<END block is not closed"* ]] || fail "unclosed message: '$err'"

# --- failing hook: its variables are ignored; temp file removed ---
uhook failing.sh 'aliprehook_env_pass F=1; exit 3'
reg "$key  T  hooks/failing.sh"
out=$(T 2>/dev/null); rc=$?
assert_eq 3 $rc "failing hook: exit code"
assert_eq "" "$out" "failing hook: main not run"
assert_eq 0 "$(leftovers)" "temp file removed after failure"

# --- limits ---
uhook big.sh 'i=0; while [ $i -le 100 ]; do aliprehook_env_pass V$i=x; i=$((i+1)); done'
reg "$key  T  hooks/big.sh"
err=$(T 2>&1) && fail "more than 100 variables accepted"
[[ $err == *"more than 100 variables"* ]] || fail "count limit message: '$err'"
uhook huge.sh 'head -c 70000 /dev/zero | tr "\0" x | sed "s/^/H=/" >> "$ALIPREHOOK_ENV_FILE"; echo >> "$ALIPREHOOK_ENV_FILE"'
reg "$key  T  hooks/huge.sh"
err=$(T 2>&1) && fail "file over 64 KiB accepted"
[[ $err == *"larger than 65536 bytes"* ]] || fail "size limit message: '$err'"

# --- several user hooks: later sees earlier; later wins ---
uhook u1.sh 'aliprehook_env_pass SHARED=common ONLY1=1'
uhook u2.sh 'aliprehook_env_pass SEEN="$SHARED" SHARED=specific'
reg "*  T  hooks/u1.sh" "$key  T  hooks/u2.sh"
aliprehook_define T show SHARED ONLY1 SEEN
assert_eq "SHARED=specific
ONLY1=1
SEEN=common" "$(T)" "later user hook sees earlier and wins"

# --- project layer: user wins, isolation, denylist ---
mkdir -p .aliprehook
cat > .aliprehook.yml <<'YML'
hooks:
  P: .aliprehook/p.sh
  Deny: .aliprehook/deny.sh
YML
print -r -- '#!/bin/sh
aliprehook_env_pass SHARED=project PONLY=p LEAK="${USERSECRET-none}"' > .aliprehook/p.sh
print -r -- '#!/bin/sh
aliprehook_env_pass PATH=/evil' > .aliprehook/deny.sh
chmod +x .aliprehook/*.sh
aliprehook allow >/dev/null

uhook up.sh 'aliprehook_env_pass SHARED=user USERSECRET=s3cret'
reg "$key  P  hooks/up.sh"
aliprehook_define P show SHARED PONLY USERSECRET LEAK
assert_eq "SHARED=user
PONLY=p
USERSECRET=s3cret
LEAK=none" "$(P)" "user beats project; project hook cannot read user vars"

reg
aliprehook_define Deny show PATH
err=$(Deny 2>&1); rc=$?
assert_eq 1 $rc "denylisted name from project hook: exit 1"
[[ $err == *"project hooks may not set PATH"* ]] || fail "denylist message: '$err'"
[[ $err != */evil* ]] || fail "denylist message leaked the value"
uhook upath.sh 'aliprehook_env_pass MYPATH_OK=1 LD_LIBRARY_PATH=/opt/lib'
reg "$key  Deny  hooks/upath.sh"
aliprehook_define Deny show LD_LIBRARY_PATH
err=$(Deny 2>&1)
[[ $err == *"project hooks may not set PATH"* ]] || fail "project denylist still applies with user hook"
reg "$key  U  hooks/upath.sh"
aliprehook_define U show LD_LIBRARY_PATH
assert_eq "LD_LIBRARY_PATH=/opt/lib" "$(U)" "user hooks may set denylisted names"
aliprehook revoke >/dev/null

# --- --keep-env: user vars stay, project vars do not ---
aliprehook allow >/dev/null
uhook keep.sh 'aliprehook_env_pass KEEP_ME=yes'
reg "$key  P  hooks/keep.sh"
aliprehook_define --keep-env P show KEEP_ME PONLY
P >/dev/null
assert_eq "yes" "${KEEP_ME-<unset>}" "--keep-env: user var kept"
assert_eq "<unset>" "${PONLY-<unset>}" "--keep-env: project var not kept"
[[ ${(t)KEEP_ME} == *export* ]] || fail "--keep-env: var not exported"
unset KEEP_ME
aliprehook revoke >/dev/null

# --- main command is a function, an alias and a binary ---
uhook fn.sh 'aliprehook_env_pass FNV=f'
reg "$key  Fn  hooks/fn.sh" "$key  Al  hooks/fn.sh" "$key  Bin  hooks/fn.sh"
myfn() { print -r -- "fn:$FNV"; }
aliprehook_define Fn myfn
alias myalias='print -r -- alias:'
aliprehook_define Al myalias
aliprehook_define Bin sh -c 'echo "bin:$FNV"'
assert_eq "fn:f" "$(Fn)" "function main command"
assert_eq "alias:" "$(Al)" "alias main command runs"
assert_eq "bin:f" "$(Bin)" "binary main command"

# --- Case B: aliprehook_run + aliprehook_with_env; nothing leaks to a later command ---
reg "$key  Dclear  hooks/fn.sh"
Dclear() {
  aliprehook_run Dclear "$@" || return $?
  aliprehook_with_env sh -c 'echo "caseb:$FNV"'
}
assert_eq "caseb:f" "$(Dclear)" "Case B with aliprehook_with_env"
aliprehook_run Dclear
aliprehook_with_env true
assert_eq "caseb:" "$(aliprehook_with_env sh -c 'echo "caseb:$FNV"')" "variables used once, then cleared"

# --- interrupt: temp file still removed ---
uhook slow.sh "aliprehook_env_pass S=1; kill -INT \$PPID; sleep 1"
reg "$key  Slow  hooks/slow.sh"
print -r -- "source $ALIPREHOOK_ROOT/lib.zsh; aliprehook_define Slow true; Slow" > $tmp/int.zsh
ALIPREHOOK_HOME=$ALIPREHOOK_HOME zsh -fi $tmp/int.zsh >/dev/null 2>&1 </dev/null
assert_eq 0 "$(leftovers)" "temp file removed after interrupt"

# Temp files are private.
uhook mode.sh 'stat -c %a "$ALIPREHOOK_ENV_FILE" > '"$tmp/mode"
reg "$key  M  hooks/mode.sh"
aliprehook_run M
assert_eq 600 "$(<$tmp/mode)" "temp file mode 0600"
[[ $(<$tmp/mode) ]] && [[ -n ${XDG_RUNTIME_DIR} ]]

assert_eq 0 "$(leftovers)" "no temp files left at the end"
finish
