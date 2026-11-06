source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
tmp=${tmp:A}
ALIPREHOOK_HOME=$tmp/home
mkdir -p $ALIPREHOOK_HOME/hooks
cp $ALIPREHOOK_ROOT/templates/allowed-repos $ALIPREHOOK_HOME/allowed-repos

log=$tmp/log
reset() { : > $log; }
logged() { print -r -- "$(<$log)"; }
mkhook() {  # path tag [exit]
  mkdir -p ${1:h}
  print -r -- "#!/bin/sh
echo \"$2:\$ALIPREHOOK_COMMAND:\$ALIPREHOOK_PROJECT_ROOT:\$*\" >> $log
exit ${3:-0}" > $1
  chmod +x $1
}

repo=$tmp/repo
key=github.com/org/sample_app_web
git init -q $repo
git -C $repo remote add origin git@github.com:org/sample_app_web.git
mkhook $repo/.aliprehook/before_Dup.sh project
mkhook $repo/.aliprehook/fail.sh project 4
mkhook $tmp/outside.sh outside
ln -s $tmp/outside.sh $repo/.aliprehook/link_out.sh
print '#!/bin/sh' > $repo/.aliprehook/noexec.sh
cat > $repo/.aliprehook.yml <<'YML'
# Only used after: aliprehook allow
hooks:
  Dup: .aliprehook/before_Dup.sh   # inline comment
  # commented: .aliprehook/nope.sh
  Quoted: ".aliprehook/before_Dup.sh"
  Single: '.aliprehook/before_Dup.sh'
  Fail: .aliprehook/fail.sh
  Up: ../outside.sh
  Abs: /bin/echo
  Link: .aliprehook/link_out.sh
  NoExec: .aliprehook/noexec.sh
  Missing: .aliprehook/missing.sh
other:
  Late: .aliprehook/before_Dup.sh
YML

mkhook $ALIPREHOOK_HOME/hooks/user.sh user
print "$key  Dup  hooks/user.sh" > $ALIPREHOOK_HOME/hooks.map

# --- parser ---
assert_eq .aliprehook/before_Dup.sh "$(aliprehook_project_lookup $repo Dup)" "yml: plain + inline comment"
assert_eq .aliprehook/before_Dup.sh "$(aliprehook_project_lookup $repo Quoted)" "yml: double quotes"
assert_eq .aliprehook/before_Dup.sh "$(aliprehook_project_lookup $repo Single)" "yml: single quotes"
aliprehook_project_lookup $repo commented >/dev/null && fail "yml: commented entry used"
aliprehook_project_lookup $repo Late >/dev/null && fail "yml: key outside hooks: used"
aliprehook_project_lookup $repo Nope >/dev/null && fail "yml: unknown command matched"

cd $repo

# --- not allowed: project hook skipped, user hook still runs ---
reset; aliprehook_run Dup a; rc=$?
assert_eq 0 $rc "not allowed: exit 0"
assert_eq "user:Dup::a" "$(logged)" "not allowed: only user hook"

# --- allow ---
out=$(aliprehook allow); rc=$?
assert_eq 0 $rc "allow: exit 0"
[[ $out == *"allowed $key"* ]] || fail "allow: message '$out'"
assert_eq "$key" "$(grep -v '^#' $ALIPREHOOK_HOME/allowed-repos)" "allow: key recorded"
aliprehook allow >/dev/null
assert_eq 1 "$(grep -c "^$key\$" $ALIPREHOOK_HOME/allowed-repos)" "allow twice: no duplicate"

reset; aliprehook_run Dup a "b c"; rc=$?
assert_eq 0 $rc "allowed: exit 0"
assert_eq "user:Dup::a b c
project:Dup:${repo}:a b c" "$(logged)" "allowed: user then project hook"

# Works from a subdirectory too.
mkdir -p $repo/src/deep && cd $repo/src/deep
reset; aliprehook_run Dup
assert_eq "user:Dup::
project:Dup:${repo}:" "$(logged)" "allowed: from subdirectory"
cd $repo

# Through aliprehook_define: hooks then main.
main() { print -r -- "main:$*" >> $log; }
aliprehook_define Dup main up
reset; Dup --watch
assert_eq "user:Dup::--watch
project:Dup:${repo}:--watch
main:up --watch" "$(logged)" "define: user, project, main"

# Failing project hook stops main.
aliprehook_define Fail main up
reset; Fail 2>/dev/null; rc=$?
assert_eq 4 $rc "project hook failure: exit code"
assert_eq "project:Fail:${repo}:" "$(logged)" "project hook failure: main not run"

# Path safety.
for c in Up Abs Link; do
  reset; err=$(aliprehook_run $c 2>&1); rc=$?
  assert_eq 1 $rc "$c: rejected"
  assert_eq "" "$(logged)" "$c: nothing ran"
done
err=$(aliprehook_run NoExec 2>&1) && fail "non-executable project hook accepted"
[[ $err == *"chmod +x"* ]] || fail "NoExec message: '$err'"
err=$(aliprehook_run Missing 2>&1) && fail "missing project hook accepted"
[[ $err == *"not found"* ]] || fail "Missing message: '$err'"

# Another clone of the same remote is allowed too (key is the remote).
git -C $repo add -A && git -C $repo -c user.name=t -c user.email=t@t commit -qm init
git clone -q $repo $tmp/clone 2>/dev/null
git -C $tmp/clone remote set-url origin https://github.com/org/sample_app_web.git
cd $tmp/clone
reset; aliprehook_run Dup
assert_eq "user:Dup::
project:Dup:${tmp}/clone:" "$(logged)" "second clone shares allow"
cd $repo

# --- revoke ---
print '# keep me' >> $ALIPREHOOK_HOME/allowed-repos
print 'github.com/org/other' >> $ALIPREHOOK_HOME/allowed-repos
out=$(aliprehook revoke); rc=$?
assert_eq 0 $rc "revoke: exit 0"
[[ $out == *"revoked $key"* ]] || fail "revoke: message '$out'"
grep -qx "$key" $ALIPREHOOK_HOME/allowed-repos && fail "revoke: key still present"
grep -qx 'github.com/org/other' $ALIPREHOOK_HOME/allowed-repos || fail "revoke: removed other key"
grep -qx '# keep me' $ALIPREHOOK_HOME/allowed-repos || fail "revoke: removed comment"

reset; aliprehook_run Dup
assert_eq "user:Dup::" "$(logged)" "revoked: project hook skipped again"
[[ "$(aliprehook revoke)" == *"not allowed"* ]] || fail "revoke twice: message"

# --- allow needs a yml ---
git init -q $tmp/bare_repo
cd $tmp/bare_repo
aliprehook allow 2>/dev/null && fail "allow without .aliprehook.yml accepted"
cd $tmp
aliprehook allow 2>/dev/null && fail "allow outside git accepted"

# --- misc ---
cd $repo
assert_eq "$key" "$(aliprehook key)" "aliprehook key"
aliprehook bogus 2>/dev/null; assert_eq 2 $? "unknown subcommand"
[[ "$(aliprehook help)" == usage:* ]] || fail "help"

finish
