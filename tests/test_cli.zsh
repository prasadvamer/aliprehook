source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
tmp=${tmp:A}
ALIPREHOOK_HOME=$tmp/home
mkdir -p $ALIPREHOOK_HOME/hooks
cp $ALIPREHOOK_ROOT/templates/registry $ALIPREHOOK_HOME/registry
cp $ALIPREHOOK_ROOT/templates/commands $ALIPREHOOK_HOME/commands
chmod 600 $ALIPREHOOK_HOME/registry $ALIPREHOOK_HOME/commands

repo=$tmp/repo
key=github.com/org/sample_app_web
git init -q $repo
git -C $repo remote add origin git@github.com:org/sample_app_web.git
other=$tmp/other
git init -q $other
git -C $other remote add origin https://github.com/org/other_app.git
plain=$tmp/plain
mkdir -p $plain
cd $repo

R=$ALIPREHOOK_HOME/registry
C=$ALIPREHOOK_HOME/commands
entries() { grep -v '^#' $1 | grep -v '^$'; }   # non-comment lines
mode() { zmodload -F zsh/stat b:zstat; local -a m; zstat -A m +mode -- $1; printf '%o' $(( m[1] & 8#777 )); }
mkx() { print -r -- '#!/bin/sh' > $1; chmod +x $1; }

# --- help ---
out=$(aliprehook help); rc=$?
assert_eq 0 $rc "help: exit 0"
for w in allow revoke key 'hook new|add|rm|ls' 'command set|rm|ls' edit; do
  [[ $out == *"$w"* ]] || fail "help lists '$w'"
done
assert_eq "$out" "$(aliprehook)" "no arguments = help"
[[ $(aliprehook hook help) == *"aliprehook hook new <cmd> [--hook <file>]"*"aliprehook hook ls"* ]] || fail "hook help"
assert_eq "$(aliprehook hook help)" "$(aliprehook hook)" "hook without sub = hook help"
[[ $(aliprehook command help) == *"No --all"* ]] || fail "command help explains no --all"
for t in 'hook new' 'hook add' 'hook rm' 'hook ls' 'command set' 'command rm' 'command ls' edit key; do
  out=$(aliprehook ${=t} --help); rc=$?
  assert_eq 0 $rc "$t --help: exit 0"
  [[ $out == "usage: $_aliprehook_usage[$t]"* && $out == *example:* ]] || fail "$t --help: '$out'"
done
[[ $(aliprehook hook new --help) == *"--path <dir>"*"--all"* ]] || fail "hook new help: project options"
[[ $(aliprehook command set -h) != *"--all           every project"* ]] || fail "command set help: no --all option"

# Wrong calls: error, usage line, hint; exit 2; nothing changed.
before=$(<$R)
for call in 'hook new' 'hook new Dup extra' 'hook add Dup' 'hook new 9bad' 'hook new Dup --bogus' 'hook new Dup --hook' \
            'hook frob' 'command frob' 'command set Dbuild' 'command rm' 'command ls x' 'key x' 'edit nope'; do
  err=$(aliprehook ${=call} 2>&1 >/dev/null); rc=$?
  assert_eq 2 $rc "'$call': exit 2"
  [[ $err == *"error: "* ]] || fail "'$call': error label: '$err'"
done
err=$(aliprehook hook new Dup --bogus 2>&1)
[[ $err == *"unknown option: --bogus"*"usage: aliprehook hook new"*"(see: aliprehook hook help)"* ]] || fail "usage error output: '$err'"
assert_eq "$before" "$(<$R)" "wrong calls change nothing"

# --- hook new ---
out=$(aliprehook hook new Dup 2>&1); rc=$?
assert_eq 0 $rc "hook new: exit 0"
h=$ALIPREHOOK_HOME/hooks/sample_app_web_Dup.sh
[[ -x $h ]] || fail "hook new: executable file created"
[[ $(<$h) == "#!/bin/sh"*"runs before \`Dup\` in $key"*"aliprehook_env_pass"*"exit 0" ]] || fail "hook new: template: '$(<$h)'"
[[ $out == *"created "*"sample_app_web_Dup.sh"*"added $key  Dup  hooks/sample_app_web_Dup.sh"* ]] || fail "hook new: messages: '$out'"
assert_eq "$key  Dup  hooks/sample_app_web_Dup.sh" "$(entries $R)" "hook new: registry line"
[[ $(<$R) == "# aliprehook user registry"* ]] || fail "hook new: comments kept"
assert_eq 600 "$(mode $R)" "registry permissions kept"

# Template runs and does nothing; the command still works.
aliprehook_define Dup print -r -- main
assert_eq main "$(Dup 2>&1)" "new hook runs silently"

# Again: existing file reused, line not duplicated.
print '# edited' >> $h
out=$(aliprehook hook new Dup 2>&1)
[[ $out == *"using existing hook"*"already registered"* ]] || fail "hook new again: '$out'"
[[ $(<$h) == *"# edited" ]] || fail "hook new: existing file not overwritten"
assert_eq 1 "$(entries $R | wc -l | tr -d ' ')" "hook new again: no duplicate line"

# --hook name, --all default name.
aliprehook hook new Dup --hook aws_login.sh >/dev/null
[[ -x $ALIPREHOOK_HOME/hooks/aws_login.sh ]] || fail "--hook: file"
aliprehook hook new Dbuild --all >/dev/null
[[ -x $ALIPREHOOK_HOME/hooks/all_Dbuild.sh ]] || fail "--all: all_<cmd>.sh"
aliprehook hook new Dup --hook=sub/x.sh >/dev/null
[[ -x $ALIPREHOOK_HOME/sub/x.sh ]] || fail "--hook=relative/path under home"
assert_eq "$key  Dup  hooks/sample_app_web_Dup.sh
$key  Dup  hooks/aws_login.sh
*  Dbuild  hooks/all_Dbuild.sh
$key  Dup  sub/x.sh" "$(entries $R)" "registry after several new"

# Existing but not executable: error, no line.
print '#!/bin/sh' > $ALIPREHOOK_HOME/hooks/noexec.sh
err=$(aliprehook hook new Dup --hook noexec.sh 2>&1); rc=$?
assert_eq 1 $rc "hook new non-executable: exit 1"
[[ $err == *"error: hook not executable"*"(run: chmod +x"* ]] || fail "hook new non-executable: '$err'"
[[ $(<$R) != *noexec* ]] || fail "hook new non-executable: no line"

# --edit opens $EDITOR (with arguments) on the hook.
print -r -- "#!/bin/sh
echo \"\$@\" > $tmp/edited" > $tmp/ed; chmod +x $tmp/ed
EDITOR="$tmp/ed -w" VISUAL= aliprehook hook new Dclear --edit >/dev/null
assert_eq "-w $ALIPREHOOK_HOME/hooks/sample_app_web_Dclear.sh" "$(<$tmp/edited)" "--edit runs \$EDITOR"

# --- hook add ---
mkx $ALIPREHOOK_HOME/hooks/shared.sh
mkx $tmp/abs.sh
cp $R $tmp/r.before
out=$(aliprehook hook add Dbuild shared.sh 2>&1)
[[ $out == *"added $key  Dbuild  hooks/shared.sh"* ]] || fail "hook add: '$out'"
aliprehook hook add Dbuild $tmp/abs.sh >/dev/null
assert_eq "$key  Dbuild  hooks/shared.sh
$key  Dbuild  $tmp/abs.sh" "$(diff $tmp/r.before $R | sed -n 's/^> //p')" "hook add: bare and absolute"
out=$(aliprehook hook add Dbuild hooks/shared.sh 2>&1)
[[ $out == *"already registered"* ]] || fail "hook add duplicate (other spelling): '$out'"
err=$(aliprehook hook add Dbuild missing.sh 2>&1); rc=$?
assert_eq 1 $rc "hook add missing: exit 1"
[[ $err == *"hook not found"*"(create it with: aliprehook hook new Dbuild --hook missing.sh)"* ]] || fail "hook add missing: '$err'"
err=$(aliprehook hook add Dbuild noexec.sh 2>&1); rc=$?
assert_eq 1 $rc "hook add non-executable: exit 1"
err=$(aliprehook hook add Dbuild 'a b.sh' 2>&1); rc=$?
assert_eq 2 $rc "hook add path with space: exit 2"

# --- project selection ---
aliprehook hook add Dup shared.sh --path $other >/dev/null
aliprehook hook add Dup shared.sh --key github.com/org/remote_only >/dev/null
aliprehook hook add Dup shared.sh --path $plain >/dev/null
[[ $(<$R) == *"github.com/org/other_app  Dup  hooks/shared.sh"* ]] || fail "--path: other repo's key"
[[ $(<$R) == *"github.com/org/remote_only  Dup  hooks/shared.sh"* ]] || fail "--key: as given"
[[ $(<$R) == *"$plain  Dup  hooks/shared.sh"* ]] || fail "--path: non-git dir key is its path"
assert_eq "$repo" "$PWD" "--path does not change directory"
assert_eq "github.com/org/other_app" "$(aliprehook key --path $other)" "key --path"
assert_eq "$key" "$(aliprehook key)" "key"
err=$(aliprehook hook add Dup shared.sh --key git@github.com:org/x.git 2>&1)
[[ $err == *"warning: --key git@github.com:org/x.git is not a normalized key (did you mean github.com/org/x?)"* ]] || fail "--key warning: '$err'"
[[ $(<$R) == *"git@github.com:org/x.git  Dup"* ]] || fail "--key with warning still used"
for bad in "--all --key k" "--key k --path $plain" "--all --path $plain" "--key *" "--key=" "--path $tmp/nope"; do
  aliprehook hook ls ${=bad} >/dev/null 2>&1
  assert_eq 2 $? "project options '$bad': exit 2"
done
[[ $(aliprehook hook ls --all --key k 2>&1) == *"use only one of --all, --key, --path"* ]] || fail "conflict message"
[[ $(aliprehook hook ls --key '*' 2>&1) == *"use --all"* ]] || fail "--key * message"

# --- hook ls ---
chmod -x $ALIPREHOOK_HOME/sub/x.sh
mkx $ALIPREHOOK_HOME/hooks/all_Dup.sh
print '*  Dup  hooks/all_Dup.sh' >> $R
print "$key  Dup  hooks/gone.sh" >> $R
out=$(aliprehook hook ls)
assert_eq "$key
  Dup     hooks/all_Dup.sh  (* every project)
  Dup     hooks/sample_app_web_Dup.sh
  Dup     hooks/aws_login.sh
  Dup     sub/x.sh  (not executable)
  Dup     hooks/gone.sh  (missing)
  Dbuild  hooks/all_Dbuild.sh  (* every project)
  Dbuild  hooks/shared.sh
  Dbuild  $tmp/abs.sh
  Dclear  hooks/sample_app_web_Dclear.sh" "$out" "hook ls: run order, markers"
assert_eq "$key
  Dbuild  hooks/all_Dbuild.sh  (* every project)
  Dbuild  hooks/shared.sh
  Dbuild  $tmp/abs.sh" "$(aliprehook hook ls Dbuild)" "hook ls <cmd>"
assert_eq "*
  Dbuild  hooks/all_Dbuild.sh
  Dup     hooks/all_Dup.sh" "$(aliprehook hook ls --all)" "hook ls --all"
assert_eq "github.com/org/nothing
  (no hooks for Zz)" "$(aliprehook hook ls Zz --key github.com/org/nothing)" "hook ls: none"
[[ $(ALIPREHOOK_COLOR=always aliprehook hook ls) == *$'\e['* ]] || fail "hook ls: colored with always"
[[ $(aliprehook hook ls) != *$'\e['* ]] || fail "hook ls: plain in a pipe"

# --- hook rm ---
out=$(aliprehook hook rm Dup --hook aws_login.sh 2>&1)
[[ $out == *"removed $key  Dup  hooks/aws_login.sh"* ]] || fail "hook rm --hook: '$out'"
[[ -f $ALIPREHOOK_HOME/hooks/aws_login.sh ]] || fail "hook rm keeps the file"
[[ $(<$R) == *"$key  Dup  hooks/sample_app_web_Dup.sh"* ]] || fail "hook rm --hook: others kept"
out=$(aliprehook hook rm Dup 2>&1)
[[ $out == *"hooks/sample_app_web_Dup.sh"*"sub/x.sh"*"hooks/gone.sh"* ]] || fail "hook rm: all for cmd: '$out'"
[[ $(entries $R) != *"$key  Dup "* ]] || fail "hook rm: project's Dup lines gone"
[[ $(<$R) == *"*  Dup  hooks/all_Dup.sh"* ]] || fail "hook rm: * line kept"
[[ $(<$R) == *"github.com/org/other_app  Dup"* ]] || fail "hook rm: other project kept"
[[ $(<$R) == "# aliprehook user registry"* ]] || fail "hook rm: comments kept"
aliprehook hook rm Dup >/dev/null 2>&1
assert_eq 1 $? "hook rm nothing: exit 1"
aliprehook hook rm Dup --all >/dev/null
[[ $(entries $R) != *"*  Dup "* ]] || fail "hook rm --all"
assert_eq 600 "$(mode $R)" "registry permissions kept after rm"

# Symlinked registry: the target is written, the link stays.
mv $R $tmp/real_registry
ln -s $tmp/real_registry $R
aliprehook hook add Dx shared.sh >/dev/null
[[ -L $R ]] || fail "symlinked registry still a link"
[[ $(<$tmp/real_registry) == *"$key  Dx  hooks/shared.sh"* ]] || fail "symlink target written"
rm $R; mv $tmp/real_registry $R

# --- command set / rm / ls ---
cp $C $tmp/c.before
line='DOCKER_BUILDKIT=1 REV=$(print -r rev) sh -c '"'"'echo "$REV $0 $1 $2"'"'"' x'
out=$(aliprehook command set Dbuild $line 2>&1); rc=$?
assert_eq 0 $rc "command set: exit 0"
[[ $out == *"Dbuild in $key now runs: $line"* ]] || fail "command set message: '$out'"
assert_eq "$key  Dbuild  $line" "$(entries $C)" "command set: stored exactly"
[[ $(<$C) == "$(<$tmp/c.before)"* ]] || fail "command set: comments kept"
assert_eq 600 "$(mode $C)" "commands permissions kept"
aliprehook_define Dbuild print default
assert_eq "rev x a b" "$(Dbuild a b)" "command set line runs"
assert_eq default "$(cd $plain && Dbuild)" "other project: default"

out=$(aliprehook command set Dbuild 'make build' 2>&1)
[[ $out == *"now runs: make build"*"was: $line"* ]] || fail "command set replace: '$out'"
assert_eq "$key  Dbuild  make build" "$(entries $C)" "command set replaces"
out=$(aliprehook command set Dbuild 'make build' 2>&1)
[[ $out == *"already set"* ]] || fail "command set same: '$out'"
print "$key  Dbuild  dup line" >> $C
out=$(aliprehook command set Dbuild 'make b2' 2>&1)
[[ $out == *"removed duplicate line: $key  Dbuild  dup line"* ]] || fail "command set dedup: '$out'"
assert_eq "$key  Dbuild  make b2" "$(entries $C)" "command set: one line left"
[[ $(aliprehook command set Undefined_x 'echo' 2>&1) == *"warning: Undefined_x is not defined"* ]] || fail "not-defined warning"
aliprehook command set Dbuild 'make o' --path $other >/dev/null
[[ $(<$C) == *"github.com/org/other_app  Dbuild  make o"* ]] || fail "command set --path"

err=$(aliprehook command set Dbuild docker compose build 2>&1); rc=$?
assert_eq 2 $rc "command set unquoted: exit 2"
[[ $err == *"quote the command line as one argument: aliprehook command set Dbuild 'docker compose build'"* ]] || fail "unquoted message: '$err'"
aliprehook command set Dbuild $'a\nb' >/dev/null 2>&1; assert_eq 2 $? "command set newline: exit 2"
aliprehook command set Dbuild '   ' >/dev/null 2>&1; assert_eq 2 $? "command set empty: exit 2"
err=$(aliprehook command set Dbuild x --all 2>&1); rc=$?
assert_eq 2 $rc "command set --all: exit 2"
[[ $err == *"no --all for commands"*"aliprehook_define"* ]] || fail "--all message: '$err'"
aliprehook command ls --all >/dev/null 2>&1; assert_eq 2 $? "command ls --all: exit 2"

assert_eq "$key
  Dbuild       make b2
  Undefined_x  echo" "$(aliprehook command ls)" "command ls"
out=$(aliprehook command rm Dbuild 2>&1)
[[ $out == *"removed Dbuild in $key: make b2"*"default here again"* ]] || fail "command rm: '$out'"
assert_eq default "$(Dbuild)" "after rm: default runs"
[[ $(<$C) == *"github.com/org/other_app  Dbuild  make o"* ]] || fail "command rm: other project kept"
aliprehook command rm Dbuild >/dev/null 2>&1; assert_eq 1 $? "command rm nothing: exit 1"
aliprehook command rm Undefined_x >/dev/null
assert_eq "$key
  (no command lines; every command runs its aliprehook_define default)" "$(aliprehook command ls)" "command ls: none"

# New commands file: not group/world-writable even with a loose umask.
rm $C
( umask 000; aliprehook command set Dbuild 'make n' >/dev/null )
assert_eq 644 "$(mode $C)" "new commands file: go-w"
assert_eq "make n" "$(sed -n 's/.*Dbuild  //p' $C)" "new commands file: line"

# --- edit ---
EDITOR=$tmp/ed VISUAL= aliprehook edit
assert_eq "$R" "$(<$tmp/edited)" "edit: default registry"
VISUAL=$tmp/ed aliprehook edit commands
assert_eq "$C" "$(<$tmp/edited)" "edit commands, VISUAL first"

finish
