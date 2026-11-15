# aliprehook explain: dry run of what a command would do, and why.
source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 ALIPREHOOK_COLOR=never
unset ALIPREHOOK_VERBOSE

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
tmp=${tmp:A}
ALIPREHOOK_HOME=$tmp/home
H=$ALIPREHOOK_HOME
mkdir -p $H/hooks
: > $H/allowed-repos

repo=$tmp/repo
key=github.com/org/sample_app_web
git init -q $repo
git -C $repo remote add origin git@github.com:org/sample_app_web.git
mkdir -p $repo/.aliprehook
plain=$tmp/plain
mkdir -p $plain
cd $repo

marker=$tmp/ran
uhook() {  # name [mode]
  print -r -- "#!/bin/sh
echo \$0 >> $marker" > $H/hooks/$1
  chmod ${2:-755} $H/hooks/$1
}
reg() { print -rl -- "$@" > $H/hooks.map; }
cmds() { print -rl -- "$@" > $H/commands.map; chmod 600 $H/commands.map; }
run() {  # → stdout $out, stderr $err, exit $rc
  "$@" >$tmp/out 2>$tmp/err; rc=$?
  out=$(<$tmp/out) err=$(<$tmp/err)
}

uhook all_Dbuild.sh
uhook aws_login.sh
print -r -- "#!/bin/sh
echo project >> $marker" > $repo/.aliprehook/build.sh
chmod 755 $repo/.aliprehook/build.sh
print -rl -- 'hooks:' '  Dbuild: .aliprehook/build.sh' > $repo/.aliprehook.yml
reg '# comment' "*  Dbuild  hooks/all_Dbuild.sh" "$key  Dbuild  hooks/aws_login.sh" \
  "github.com/org/other_app  Dbuild  hooks/other.sh" "*  Dup  hooks/all_Dbuild.sh"
cmds "$key  Dbuild  DOCKER_BUILDKIT=1 docker compose build \$TOKEN" "github.com/org/other_app  Dbuild  make build"
aliprehook_define Dbuild docker compose build

# --- full explanation, repo not allowed ---
run aliprehook explain Dbuild
assert_eq 0 $rc "not allowed: exit 0"
assert_eq "Dbuild in $key (git remote origin)
defined: aliprehook_define Dbuild docker compose build

hooks, in run order:
  1. all_Dbuild.sh          hooks.map:2 (*)
  2. aws_login.sh           hooks.map:3
  -  .aliprehook/build.sh   project: skipped (repo not allowed; run: aliprehook allow)

command: commands.map:1
  DOCKER_BUILDKIT=1 docker compose build \$TOKEN

not matching here:
  hooks.map:4     github.com/org/other_app  Dbuild  hooks/other.sh
  commands.map:2  github.com/org/other_app  Dbuild  make build

variables passed by hooks are known only when they run (run: ALIPREHOOK_VERBOSE=detail Dbuild)" "$out" "full output"
assert_eq "" "$err" "no warnings"
[[ ! -e $marker ]] || fail "explain ran a hook: $(<$marker)"

# --- allowed: project hook in run order ---
aliprehook allow >/dev/null
run aliprehook explain Dbuild
[[ $out == *"  3. .aliprehook/build.sh   project (.aliprehook.yml)"* ]] || fail "allowed: project hook listed: '$out'"
[[ ! -e $marker ]] || fail "explain ran a hook (allowed)"

# --- problems: missing and non-executable hooks → exit 1 ---
chmod 644 $H/hooks/aws_login.sh
run aliprehook explain Dbuild
assert_eq 1 $rc "non-executable: exit 1"
assert_eq "aliprehook: warning: user hook not executable: $H/hooks/aws_login.sh (run: chmod +x $H/hooks/aws_login.sh)" "$err" "non-executable warning"
chmod 755 $H/hooks/aws_login.sh
rm $repo/.aliprehook/build.sh
run aliprehook explain Dbuild
assert_eq 1 $rc "missing project hook: exit 1"
assert_eq "aliprehook: warning: project hook not found: $repo/.aliprehook/build.sh" "$err" "missing project hook warning"
print -r -- '#!/bin/sh' > $repo/.aliprehook/build.sh; chmod 755 $repo/.aliprehook/build.sh

# Project hook outside the repo: the run's error, the run would stop.
print -rl -- 'hooks:' '  Dbuild: ../outside.sh' > $repo/.aliprehook.yml
run aliprehook explain Dbuild
assert_eq 1 $rc "outside repo: exit 1"
[[ $err == *"error: project hook outside the repo: ../outside.sh"* ]] || fail "outside repo: error '$err'"
[[ $out == *"project: error (see above); the run stops before any hook"* ]] || fail "outside repo: row '$out'"
print -rl -- 'hooks:' '  Dbuild: .aliprehook/build.sh' > $repo/.aliprehook.yml

# commands.map writable by others.
chmod 666 $H/commands.map
run aliprehook explain Dbuild
assert_eq 1 $rc "unsafe commands.map: exit 1"
[[ $out == *"command: commands.map error (see above)"* ]] || fail "unsafe commands.map: '$out'"
[[ $err == *"writable by group or others"* ]] || fail "unsafe commands.map: error '$err'"
chmod 600 $H/commands.map

# Old file names and an invalid verbose level are reported every time.
print -r -- x > $H/registry
mv $H/hooks.map $tmp/hooks.map.bak
print -r -- verbose=loud > $H/settings
run aliprehook explain Dbuild
assert_eq 1 $rc "old names: exit 1"
[[ $err == *"registry is not read anymore"* ]] || fail "old names warning: '$err'"
[[ $err == *"invalid verbose level 'loud'"* ]] || fail "verbose warning: '$err'"
run aliprehook explain Dbuild
[[ $err == *"registry is not read anymore"* ]] || fail "old names warned again: '$err'"
rm $H/registry $H/settings
mv $tmp/hooks.map.bak $H/hooks.map

# --- definitions ---
cb_cmd() { aliprehook_run cb_cmd "$@" && aliprehook_command cb_cmd echo -- "$@"; }
cb_run() { aliprehook_run cb_run "$@" && echo x; }
alias al='echo hi'
aliprehook_define --keep-env Dk command ls -l
run aliprehook explain Dk
[[ $out == *"defined: aliprehook_define --keep-env Dk command ls -l"* ]] || fail "define with options: '$out'"
[[ $out == *"command: (default) command ls -l"* ]] || fail "default command: '$out'"
[[ $out == *"  none in hooks.map for Dk here"* ]] || fail "no hooks: '$out'"
[[ $out != *"variables passed"* ]] || fail "no hooks: no variables line"
run aliprehook explain cb_cmd
assert_eq 0 $rc "Case B: exit 0"
[[ $out == *"defined: function cb_cmd (calls aliprehook_run)"* ]] || fail "Case B: '$out'"
[[ $out == *"command: (set by the function)"* ]] || fail "Case B command: '$out'"
cmds "$key  cb_run  echo other"
run aliprehook explain cb_run
assert_eq 1 $rc "Case B without aliprehook_command: exit 1"
[[ $err == *"commands.map:1 is not used: cb_run does not call aliprehook_command"* ]] || fail "unused line: '$err'"
run aliprehook explain al
assert_eq 1 $rc "alias: exit 1"
[[ $err == *"al is not an aliprehook command here (an alias: al='echo hi'); nothing below runs (run: aliprehook_define al <command...>)"* ]] || fail "alias: '$err'"
run aliprehook explain nosuchcmd
[[ $err == *"(not found)"* ]] || fail "not found: '$err'"
run aliprehook explain ls
[[ $err == *"(a program: "* ]] || fail "program: '$err'"
[[ $out == *"command: none (not an aliprehook command)"* ]] || fail "program command: '$out'"
cmds "$key  Dbuild  DOCKER_BUILDKIT=1 docker compose build \$TOKEN" "github.com/org/other_app  Dbuild  make build"

# --- project layer reasons ---
cd $plain
run aliprehook explain Dbuild
[[ $out == "Dbuild in $plain (no git repo; directory path)"* ]] || fail "plain: header '$out'"
[[ $out == *"  -  (project)       project: none (not a git repo)"* ]] || fail "plain: project reason '$out'"
[[ $out == *"command: (default) docker compose build"* ]] || fail "plain: default command '$out'"
[[ $out == *"commands.map:1  $key  Dbuild"* ]] || fail "plain: own key listed as not matching '$out'"
cd $repo
run aliprehook explain Dup
[[ $out == *"project: none for Dup in .aliprehook.yml"* ]] || fail "no entry: '$out'"

# --- --path / --key ---
cd $plain
run aliprehook explain Dbuild --path $repo
[[ $out == "Dbuild in $key (git remote origin; --path $repo)"* ]] || fail "--path header: '$out'"
[[ $out == *"3. .aliprehook/build.sh"* ]] || fail "--path: project layer from <dir>: '$out'"
run aliprehook explain Dbuild --key github.com/org/other_app
assert_eq 1 $rc "--key: exit 1 (hook of that key missing)"
assert_eq "aliprehook: warning: user hook not found: $H/hooks/other.sh" "$err" "--key: that key's hooks checked"
[[ $out == "Dbuild in github.com/org/other_app (--key; project layer not checked)"* ]] || fail "--key header: '$out'"
[[ $out == *"project: not checked (--key; no repo to look at)"* ]] || fail "--key project: '$out'"
[[ $out == *"command: commands.map:2"*"  make build"* ]] || fail "--key command: '$out'"
cd $repo
run aliprehook explain Dbuild --key a --path $repo
assert_eq 2 $rc "--key + --path: exit 2"
[[ $err == *"use only one of --key, --path"* ]] || fail "conflict message: '$err'"
run aliprehook explain Dbuild --all
assert_eq 2 $rc "--all: exit 2"
[[ $err == *"no --all"* && $err == *"usage: aliprehook explain"* ]] || fail "--all message: '$err'"
run aliprehook explain a b
assert_eq 2 $rc "two commands: exit 2"
run aliprehook explain 'bad name'
assert_eq 2 $rc "invalid name: exit 2"
run aliprehook explain Dbuild --path $tmp/none
assert_eq 2 $rc "missing --path dir: exit 2"
run aliprehook explain --help
[[ $out == "usage: aliprehook explain [<cmd>] [--path <dir> | --key <key>]"* ]] || fail "--help: '$out'"
run aliprehook explain help
[[ $out == "usage: aliprehook explain"* ]] || fail "explain help: '$out'"
run aliprehook help
[[ $out == *"explain [<cmd>]"* ]] || fail "listed in aliprehook help"

# --- all commands ---
aliprehook revoke >/dev/null
run aliprehook explain
assert_eq 0 $rc "list: exit 0"
assert_eq "$key (git remote origin)
  Dbuild   2 hooks (1 *), project hook (skipped: repo not allowed), command: commands.map:1
  Dup      1 hook (1 *), (not defined here)
(see: aliprehook explain <cmd>)" "$out" "list output"
run aliprehook explain --key github.com/org/none
[[ $out == *"  Dup      1 hook (1 *), (not defined here)"* ]] || fail "list --key: * lines apply: '$out'"
[[ $out == *"  Dbuild   1 hook (1 *)"* ]] || fail "list --key: only * hook, no other key's lines: '$out'"
reg
: > $H/commands.map
cd $plain
run aliprehook explain
assert_eq "$plain (no git repo; directory path)
  nothing registered for this project
(see: aliprehook explain <cmd>)" "$out" "list: nothing registered"

[[ ! -e $marker ]] || fail "explain ran a hook: $(<$marker)"
finish
