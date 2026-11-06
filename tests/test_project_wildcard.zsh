source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
tmp=${tmp:A}
ALIPREHOOK_HOME=$tmp/home
mkdir -p $ALIPREHOOK_HOME
cp $ALIPREHOOK_ROOT/templates/allowed-repos $ALIPREHOOK_HOME/allowed-repos

log=$tmp/log
reset() { : > $log; }
logged() { print -r -- "$(<$log)"; }
mkhook() {
  mkdir -p ${1:h}
  print -r -- "#!/bin/sh
echo \"$2\" >> $log" > $1
  chmod +x $1
}

repo=$tmp/repo
git init -q $repo
git -C $repo remote add origin git@github.com:org/sample_app_web.git
mkhook $repo/.aliprehook/dup.sh dup
mkhook $repo/.aliprehook/all.sh all
cd $repo

valid='hooks:
  Dup: .aliprehook/dup.sh'

# --- allow refuses a yml with a * entry ---
for star in '*' '"*"' "'*'"; do
  print -r -- "hooks:
  Dup: .aliprehook/dup.sh
  $star: .aliprehook/all.sh" > .aliprehook.yml
  err=$(aliprehook allow 2>&1); rc=$?
  assert_eq 1 $rc "allow with $star: refused"
  [[ $err == *".aliprehook.yml:3:"*"'*' hooks are not allowed in a repo"*"hooks.map"* ]] || fail "allow with $star: message '$err'"
  aliprehook_is_allowed github.com/org/sample_app_web && fail "allow with $star: key recorded"
done

# Other invalid names are refused too.
print -r -- "hooks:
  foo/bar: .aliprehook/all.sh
  Empty:" > .aliprehook.yml
err=$(aliprehook allow 2>&1) && fail "allow with invalid names accepted"
[[ $err == *":2: invalid command name: foo/bar"* ]] || fail "invalid name message: '$err'"
[[ $err == *":3: missing hook path for Empty"* ]] || fail "missing path message: '$err'"

# --- allowed repo whose yml later gains a * entry ---
print -r -- $valid > .aliprehook.yml
aliprehook allow >/dev/null || fail "allow valid yml failed"
print -r -- "$valid
  '*': .aliprehook/all.sh" > .aliprehook.yml

reset; err=$(aliprehook_run Dup 2>&1); rc=$?
assert_eq 0 $rc "run with * entry: valid hooks still run"
assert_eq dup "$(logged)" "run with * entry: only Dup hook ran"
[[ $err == *"warning: .aliprehook.yml:3: '*' hooks are not allowed in a repo"* ]] || fail "run warning: '$err'"
[[ $err == *"invalid entries ignored"* ]] || fail "run warning footer: '$err'"

reset; aliprehook_run serve 2>/dev/null
assert_eq "" "$(logged)" "* entry never runs for other commands"

# The * entry cannot be reached as a command name either.
aliprehook_project_lookup $repo '*' >/dev/null && fail "lookup matched *"

# --- valid yml: no warnings ---
print -r -- $valid > .aliprehook.yml
reset; err=$(aliprehook_run Dup 2>&1)
assert_eq "" "$err" "valid yml: no warning"
assert_eq dup "$(logged)" "valid yml: hook ran"

# Not allowed: no warnings even with a * entry (project layer is off).
aliprehook revoke >/dev/null
print -r -- "$valid
  '*': .aliprehook/all.sh" > .aliprehook.yml
err=$(aliprehook_run Dup 2>&1)
assert_eq "" "$err" "not allowed: silent"

finish
