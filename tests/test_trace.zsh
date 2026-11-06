# Run summary (ALIPREHOOK_VERBOSE, settings, aliprehook verbose).
source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh
unset ALIPREHOOK_VERBOSE

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
tmp=${tmp:A}
ALIPREHOOK_HOME=$tmp/home
mkdir -p $ALIPREHOOK_HOME/hooks
: > $ALIPREHOOK_HOME/allowed-repos
: > $ALIPREHOOK_HOME/hooks.map
S=$ALIPREHOOK_HOME/settings

repo=$tmp/repo
key=github.com/org/sample_app_web
git init -q $repo
git -C $repo remote add origin git@github.com:org/sample_app_web.git
plain=$tmp/plain
mkdir -p $plain
cd $repo

uhook() {  # name body
  print -r -- "#!/bin/sh
$2" > $ALIPREHOOK_HOME/hooks/$1
  chmod +x $ALIPREHOOK_HOME/hooks/$1
}
reg() { print -rl -- "$@" > $ALIPREHOOK_HOME/hooks.map; }
cmds() { print -rl -- "$@" > $ALIPREHOOK_HOME/commands.map; chmod 600 $ALIPREHOOK_HOME/commands.map; }
run() {  # cmd args… → stdout in $out, stderr in $err, exit in $rc
  "$@" >$tmp/out 2>$tmp/err; rc=$?
  out=$(<$tmp/out) err=$(<$tmp/err)
}

aliprehook_define D print -r -- main

# --- summary (default): nothing happened → no line ---
run D
assert_eq "main" "$out" "nothing: command runs"
assert_eq "" "$err" "nothing: no summary line"

# --- hooks, * marker, env names (never values), stderr only ---
uhook common.sh 'echo common-out >&2'
uhook a.sh 'aliprehook_env_pass TOKEN=s3cret-value MODE=dev'
reg "*  D  hooks/common.sh" "$key  D  hooks/a.sh"
run D x
assert_eq "main x" "$out" "summary never on stdout"
assert_eq "common-out
aliprehook: D · hooks: common.sh (*), a.sh · env: TOKEN, MODE" "$err" "summary line after hook output"
[[ $err != *s3cret* ]] || fail "value printed"

# Same name from two hooks: listed once.
uhook a2.sh 'aliprehook_env_pass TOKEN=other EXTRA=1'
reg "$key  D  hooks/a.sh" "$key  D  hooks/a2.sh"
run D
assert_eq "aliprehook: D · hooks: a.sh, a2.sh · env: TOKEN, MODE, EXTRA" "$err" "env names once, in run order"

# Hooks only.
reg "$key  D  hooks/common.sh"
run D
assert_eq "common-out
aliprehook: D · hooks: common.sh" "$err" "hooks only"

# --- command from commands.map ---
reg
cmds "# comment" "$key  D  print -r -- from-map"
run D
assert_eq "from-map" "$out" "map line runs"
assert_eq "aliprehook: D · command: commands.map:2" "$err" "command part"
cd $plain; run D; cd $repo
assert_eq "" "$err" "default command: no command part"
rm $ALIPREHOOK_HOME/commands.map

# --- project hook marker, --keep-env (kept) ---
mkdir -p $repo/.aliprehook
print -r -- '#!/bin/sh
aliprehook_env_pass PV=1' > $repo/.aliprehook/p.sh; chmod +x $repo/.aliprehook/p.sh
print -r -- "hooks:
  K: .aliprehook/p.sh" > $repo/.aliprehook.yml
print -r -- $key > $ALIPREHOOK_HOME/allowed-repos
uhook k.sh 'aliprehook_env_pass KV=1'
reg "$key  K  hooks/k.sh"
aliprehook_define --keep-env K print -r -- main
run K
assert_eq "aliprehook: K · hooks: k.sh, p.sh (project) · env: KV (kept), PV" "$err" "project marker and kept"
unset KV

# --- no summary on failure ---
uhook fail.sh 'exit 3'
reg "$key  D  hooks/a.sh" "$key  D  hooks/fail.sh"
run D
assert_eq 3 $rc "failing hook: exit code"
[[ $err != *"D · hooks"* ]] || fail "summary printed on failure: '$err'"
uhook req.sh 'aliprehook_env_pass --required NOPE'
reg "$key  D  hooks/req.sh"
run D
[[ $err != *"D · hooks"* ]] || fail "summary printed on missing required: '$err'"

# --- Case B: aliprehook_run + aliprehook_with_env / aliprehook_command ---
reg "$key  CB  hooks/a.sh"
CB() { aliprehook_run CB "$@" || return $?; aliprehook_with_env print -r -- cb; }
run CB
assert_eq "cb" "$out" "Case B runs"
assert_eq "aliprehook: CB · hooks: a.sh · env: TOKEN, MODE" "$err" "Case B: one summary line"
CC() { aliprehook_run CC "$@" || return $?; aliprehook_command CC print -r dflt -- "$@"; }
reg "$key  CC  hooks/a.sh"
cmds "$key  CC  print -r -- mapped"
run CC
assert_eq "mapped" "$out" "aliprehook_command line"
assert_eq "aliprehook: CC · hooks: a.sh · env: TOKEN, MODE
aliprehook: CC · command: commands.map:1" "$err" "aliprehook_command adds the command part"
rm $ALIPREHOOK_HOME/commands.map

# --- quiet ---
reg "*  D  hooks/common.sh" "$key  D  hooks/a.sh"
ALIPREHOOK_VERBOSE=quiet run D
assert_eq "common-out" "$err" "quiet: no trace"

# --- detail ---
cmds "$key  M  print -r -- \"\$@\" end"
aliprehook_define M print -r -- dflt
reg "*  D  hooks/common.sh" "$key  D  hooks/a.sh"
ALIPREHOOK_VERBOSE=detail run D 'a b' c
assert_eq "aliprehook: D in $key
aliprehook:   hook common.sh (*)
common-out
aliprehook:   hook a.sh
aliprehook:     passed TOKEN, MODE
aliprehook:   project hook: none for D in .aliprehook.yml
aliprehook:   command (default): print -r -- main 'a b' c" "$err" "detail: steps in order, hook line before its output"
[[ $err != *s3cret* ]] || fail "detail: value printed"
ALIPREHOOK_VERBOSE=detail run M x
assert_eq "aliprehook: M in $key
aliprehook:   hooks.map: no hooks for M here
aliprehook:   project hook: none for M in .aliprehook.yml
aliprehook:   command (commands.map:1): print -r -- \"\$@\" end  [arguments: x]" "$err" "detail: commands.map line with \$@"
reg "$key  K  hooks/k.sh"
ALIPREHOOK_VERBOSE=detail run K
[[ $err == *"  project hook .aliprehook/p.sh"$'\n'"aliprehook:     passed PV"*"  kept in shell: KV"$'\n'"aliprehook:   command (default): print -r -- main" ]] || fail "detail: project hook, kept: '$err'"
unset KV
: > $ALIPREHOOK_HOME/allowed-repos
ALIPREHOOK_VERBOSE=detail run K
[[ $err == *"project hook: skipped (repo not allowed; run: aliprehook allow)"* ]] || fail "detail: not allowed: '$err'"
cd $plain
ALIPREHOOK_VERBOSE=detail run D
[[ $err == *"project hook: none (not a git repo)"* ]] || fail "detail: not git: '$err'"
cd $repo
mv $repo/.aliprehook.yml $tmp/yml
ALIPREHOOK_VERBOSE=detail run D
[[ $err == *"project hook: none (no .aliprehook.yml)"* ]] || fail "detail: no yml: '$err'"
ALIPREHOOK_VERBOSE=detail run CB
[[ $err == *"  command: print -r -- cb" ]] || fail "detail: aliprehook_with_env command: '$err'"

# --- invalid level: warning once, summary used ---
reg "$key  D  hooks/common.sh"
ALIPREHOOK_VERBOSE=loud run D
[[ $err == *"warning: invalid verbose level 'loud' in ALIPREHOOK_VERBOSE; using summary (levels: quiet, summary, detail)"*"D · hooks:"* ]] || fail "invalid level: '$err'"
ALIPREHOOK_VERBOSE=loud run D
[[ $err != *invalid* ]] || fail "invalid level warned twice"

# --- trace color: theme role, themable ---
ALIPREHOOK_COLOR=always run D
[[ $err == *$'\e[90mD · hooks:'* ]] || fail "trace color 90: '$err'"
print 'trace=35' > $ALIPREHOOK_HOME/theme-overrides
_aliprehook_theme_key=
ALIPREHOOK_COLOR=always run D
[[ $err == *$'\e[35mD · hooks:'* ]] || fail "trace override: '$err'"
rm $ALIPREHOOK_HOME/theme-overrides; _aliprehook_theme_key=
ALIPREHOOK_THEME=none ALIPREHOOK_COLOR=always run D
[[ $err == *"D · hooks:"* && $err != *$'\e[90m'* ]] || fail "theme none: '$err'"

# --- aliprehook verbose ---
reg
assert_eq "summary (default)" "$(aliprehook verbose)" "show default"
run aliprehook verbose detail
assert_eq 0 $rc "save: exit 0"
[[ $out == *"verbose level is now detail (saved in $S)"* ]] || fail "save message: '$out'"
assert_eq "verbose=detail" "$(<$S)" "settings file"
assert_eq "detail (from $S)" "$(aliprehook verbose)" "show saved"
reg "$key  D  hooks/common.sh"
run D
[[ $err == *"aliprehook:   hook common.sh"* ]] || fail "saved level used: '$err'"

# Another shell saves: this shell sees it on the next command.
print -r -- "# mine
verbose=quiet
other=1" > $S
run D
assert_eq "common-out" "$err" "settings change seen without restart"
aliprehook verbose summary >/dev/null
assert_eq "# mine
verbose=summary
other=1" "$(<$S)" "save keeps other lines"

# Env var wins; show warns that the saved level is hidden.
ALIPREHOOK_VERBOSE=quiet run aliprehook verbose
assert_eq "quiet (from ALIPREHOOK_VERBOSE)" "$out" "show env source"
[[ $err == *"warning: saved level summary in $S is hidden by ALIPREHOOK_VERBOSE=quiet (run: unset ALIPREHOOK_VERBOSE)"* ]] || fail "hidden warning: '$err'"
ALIPREHOOK_VERBOSE=quiet run aliprehook verbose detail
[[ $err == *"ALIPREHOOK_VERBOSE=quiet overrides it in this shell"* ]] || fail "save hidden warning: '$err'"

# --shell / --reset.
aliprehook verbose quiet --shell >/dev/null
assert_eq quiet "$ALIPREHOOK_VERBOSE" "--shell sets ALIPREHOOK_VERBOSE"
[[ $(<$S) == *"verbose=detail"* ]] || fail "--shell does not touch settings"
aliprehook verbose --reset --shell >/dev/null
assert_eq "<unset>" "${ALIPREHOOK_VERBOSE-<unset>}" "--reset --shell unsets"
run aliprehook verbose --reset
[[ $out == *"saved level removed"* ]] || fail "reset message: '$out'"
assert_eq "# mine
other=1" "$(<$S)" "reset removes only verbose"
assert_eq "summary (default)" "$(aliprehook verbose)" "after reset: default"
run aliprehook verbose --reset
[[ $out == *"no saved level"* ]] || fail "reset again: '$out'"

# Invalid level in settings: warning, summary used.
print 'verbose=chatty' > $S
run D
[[ $err == *"invalid verbose level 'chatty' in $S"*"D · hooks: common.sh" ]] || fail "invalid settings level: '$err'"

# Usage errors.
for call in 'verbose loud' 'verbose detail quiet' 'verbose --reset detail' 'verbose --shell' 'verbose --bogus'; do
  aliprehook ${=call} >/dev/null 2>&1
  assert_eq 2 $? "'$call': exit 2"
done
[[ $(aliprehook verbose --help) == "usage: aliprehook verbose"*"quiet"*"summary"*"detail"* ]] || fail "verbose --help"
[[ $(aliprehook help) == *"verbose [<level>]"* ]] || fail "help lists verbose"

# edit settings
print -r -- "#!/bin/sh
echo \"\$@\" > $tmp/edited" > $tmp/ed; chmod +x $tmp/ed
EDITOR=$tmp/ed VISUAL= aliprehook edit settings
assert_eq "$S" "$(<$tmp/edited)" "edit settings"

finish
