source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
tmp=${tmp:A}
ALIPREHOOK_HOME=$tmp/home
mkdir -p $ALIPREHOOK_HOME/hooks $tmp/plain

log=$tmp/log
reset() { : > $log; }
logged() { print -r -- "$(<$log)"; }
hook() {  # name [exit]
  print -r -- "#!/bin/sh
echo \"$1:\$ALIPREHOOK_COMMAND:\$*\" >> $log
exit ${2:-0}" > $ALIPREHOOK_HOME/hooks/$1.sh
  chmod +x $ALIPREHOOK_HOME/hooks/$1.sh
}
for h in vpn login web web_db serve_common other; do hook $h; done
hook common_fail 5

git init -q $tmp/web
git -C $tmp/web remote add origin git@github.com:org/sample_app_web.git
git init -q $tmp/api
git -C $tmp/api remote add origin git@github.com:org/sample_app_api.git
web=github.com/org/sample_app_web

# Exact-key lines are listed before * lines on purpose: * must still run first.
cat > $ALIPREHOOK_HOME/hooks.map <<REG
$web  Dup    hooks/web.sh
*     Dup    hooks/vpn.sh
$web  Dup    hooks/web_db.sh
*     Dup    hooks/login.sh
*     serve  hooks/serve_common.sh
$web  Dup    hooks/web.sh
*     Dup    hooks/vpn.sh
github.com/org/other  Dup  hooks/other.sh
*     Fail   hooks/common_fail.sh
$web  Fail   hooks/web.sh
REG

main() { print -r -- "main:$*" >> $log; }
aliprehook_define Dup main up
aliprehook_define serve main serve
aliprehook_define Fail main fail

# * first (file order), then exact key (file order); duplicates once; main last.
cd $tmp/web
reset; Dup -d
assert_eq "vpn:Dup:-d
login:Dup:-d
web:Dup:-d
web_db:Dup:-d
main:up -d" "$(logged)" "web: * hooks, then exact hooks, then main"

# Another project: only * hooks.
cd $tmp/api
reset; Dup
assert_eq "vpn:Dup:
login:Dup:
main:up" "$(logged)" "other project: only * hooks"

# Path-key project (no git) also matches *.
cd $tmp/plain
reset; Dup
assert_eq "vpn:Dup:
login:Dup:
main:up" "$(logged)" "path key: * hooks"

# * is per command.
cd $tmp/web
reset; serve
assert_eq "serve_common:serve:
main:serve" "$(logged)" "* for serve only runs for serve"

# Failing * hook stops the exact-key hook and main.
reset; Fail 2>/dev/null; rc=$?
assert_eq 5 $rc "failing * hook: exit code"
assert_eq "common_fail:Fail:" "$(logged)" "failing * hook: nothing after it ran"

# No match at all: main only.
reset; aliprehook_define Nothing main nothing; Nothing
assert_eq "main:nothing" "$(logged)" "no registry match: main only"

# Lookup output order.
assert_eq "$ALIPREHOOK_HOME/hooks/vpn.sh
$ALIPREHOOK_HOME/hooks/login.sh
$ALIPREHOOK_HOME/hooks/web.sh
$ALIPREHOOK_HOME/hooks/web_db.sh" "$(aliprehook_registry_lookup $web Dup)" "lookup order"
aliprehook_registry_lookup $web Unknown >/dev/null && fail "lookup matched unknown command"

finish
