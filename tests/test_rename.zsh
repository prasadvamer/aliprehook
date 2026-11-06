# Renamed user files: registry → hooks.map, commands → commands.map,
# allowed → allowed-repos, theme → theme-overrides.
source $ALIPREHOOK_ROOT/tests/helpers.zsh

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
tmp=${tmp:A}
export HOME=$tmp/home ZDOTDIR=$tmp/home GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export ALIPREHOOK_HOME=$tmp/aliprehook
mkdir -p $HOME $ALIPREHOOK_HOME

typeset -A pairs
pairs=(registry hooks.map commands commands.map allowed allowed-repos theme theme-overrides)

# --- install renames old files (content kept) ---
for old new in ${(kv)pairs}; do print -r -- "old $old" > $ALIPREHOOK_HOME/$old; done
out=$($ALIPREHOOK_ROOT/install.sh) || fail "install.sh exited non-zero"
for old new in ${(kv)pairs}; do
  [[ ! -e $ALIPREHOOK_HOME/$old ]] || fail "install: $old still there"
  assert_eq "old $old" "$(<$ALIPREHOOK_HOME/$new)" "install: $old renamed to $new"
  [[ $out == *"renamed $ALIPREHOOK_HOME/$old -> $new"* ]] || fail "install: message for $old: '$out'"
done

# --- install never overwrites an existing new file ---
print -r -- "stale" > $ALIPREHOOK_HOME/registry
$ALIPREHOOK_ROOT/install.sh >/dev/null
assert_eq "old registry" "$(<$ALIPREHOOK_HOME/hooks.map)" "install: hooks.map not overwritten"
assert_eq "stale" "$(<$ALIPREHOOK_HOME/registry)" "install: old file left when new exists"

# --- lib.zsh warns once per shell about an old file without its new name ---
mv $ALIPREHOOK_HOME/hooks.map $tmp/hooks.map.bak
out=$(zsh -fc "
  source $ALIPREHOOK_HOME/lib.zsh
  aliprehook_run X 2>&1
  aliprehook key >/dev/null 2>&1
  aliprehook_run X 2>&1
  print -r -- ---
  ALIPREHOOK_HOME=$tmp/other
  aliprehook_run X 2>&1")
w="warning: $ALIPREHOOK_HOME/registry is not read anymore; it is now hooks.map (run ./install.sh from the aliprehook repo, or: mv $ALIPREHOOK_HOME/registry $ALIPREHOOK_HOME/hooks.map)"
assert_eq "aliprehook: $w
---" "$out" "warning once per shell, only for the old file without its new one"
out=$(zsh -fc "source $ALIPREHOOK_HOME/lib.zsh; aliprehook key 2>&1 >/dev/null")
[[ $out == *"$w"* ]] || fail "aliprehook CLI also warns: '$out'"

# Old files are not read: a hook only listed in the old registry does not run.
print -r -- '#!/bin/sh
echo RAN' > $ALIPREHOOK_HOME/hooks/r.sh; chmod +x $ALIPREHOOK_HOME/hooks/r.sh
print -r -- "*  X  hooks/r.sh" > $ALIPREHOOK_HOME/registry
out=$(zsh -fc "source $ALIPREHOOK_HOME/lib.zsh; aliprehook_run X 2>/dev/null")
assert_eq "" "$out" "old registry not read"
mv $tmp/hooks.map.bak $ALIPREHOOK_HOME/hooks.map
out=$(zsh -fc "source $ALIPREHOOK_HOME/lib.zsh; aliprehook_run X 2>&1")
[[ $out != *"not read anymore"* ]] || fail "no warning once the new file exists: '$out'"

# --- uninstall removes old names, keeps the new ones ---
for old new in ${(kv)pairs}; do print -r -- "leftover" > $ALIPREHOOK_HOME/$old; done
before=$(cd $ALIPREHOOK_HOME && cat hooks.map commands.map allowed-repos theme-overrides)
out=$($ALIPREHOOK_ROOT/uninstall.sh 2>&1) || fail "uninstall.sh exited non-zero"
for old new in ${(kv)pairs}; do
  [[ ! -e $ALIPREHOOK_HOME/$old ]] || fail "uninstall: old $old kept"
  [[ $out == *"removed $ALIPREHOOK_HOME/$old (old name)"* ]] || fail "uninstall: message for $old: '$out'"
  [[ $out == *"kept    $ALIPREHOOK_HOME/$new"* ]] || fail "uninstall: kept message for $new: '$out'"
done
assert_eq "$before" "$(cd $ALIPREHOOK_HOME && cat hooks.map commands.map allowed-repos theme-overrides)" "uninstall: new files unchanged"
[[ -d $ALIPREHOOK_HOME/hooks ]] || fail "uninstall: hooks/ kept"

# --- fresh install creates only the new names ---
fresh=$tmp/fresh
ALIPREHOOK_HOME=$fresh $ALIPREHOOK_ROOT/install.sh >/dev/null
for old new in ${(kv)pairs}; do
  [[ ! -e $fresh/$old ]] || fail "fresh install: $old created"
done
for f in hooks.map commands.map allowed-repos; do assert_file $fresh/$f; done

finish
