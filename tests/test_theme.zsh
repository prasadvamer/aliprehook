source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh
zmodload zsh/zpty || { fail "zsh/zpty not available"; finish; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset NO_COLOR ALIPREHOOK_COLOR ALIPREHOOK_THEME

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
tmp=${tmp:A}
export ALIPREHOOK_HOME=$tmp/home
mkdir -p $ALIPREHOOK_HOME/hooks $tmp/proj
cd $tmp/proj

E=$'\e'
has_esc() { [[ $1 == *$E* ]]; }

# Run a zsh snippet in a pseudo-terminal (stderr/stdout are a TTY). Prints output.
pty() {
  print -r -- "source $ALIPREHOOK_ROOT/lib.zsh; $1" > $tmp/pty.zsh
  zpty t "env $2 TERM=${3:-xterm-256color} zsh -f $tmp/pty.zsh"
  local out= line
  while zpty -r t line; do out+=$line; done
  zpty -d t
  print -r -- ${out//$'\r'/}
}
warn='_aliprehook_msg warning "@hook=h.sh" ": " "@var=X" " has no value; not passed to " "@command=T"'

# --- when to color ---
out=$(eval $warn 2>&1)
has_esc "$out" && fail "not a TTY: escape codes present"
assert_eq "aliprehook: warning: h.sh: X has no value; not passed to T" "$out" "plain text when not a TTY"

has_esc "$(pty $warn)" || fail "TTY: no escape codes"
has_esc "$(pty $warn NO_COLOR=1)" && fail "NO_COLOR: escape codes present"
has_esc "$(pty $warn ALIPREHOOK_COLOR=never)" && fail "ALIPREHOOK_COLOR=never: escape codes present"
has_esc "$(pty $warn '' dumb)" && fail "TERM=dumb: escape codes present"
has_esc "$(ALIPREHOOK_COLOR=always eval $warn 2>&1)" || fail "ALIPREHOOK_COLOR=always: no escape codes"

# --- exact purple output ---
B="${E}[1;38;5;177maliprehook:${E}[0m "
c() { print -rn -- "${E}[$1m$2${E}[0m"; }
expected="$B$(c '1;33' 'warning:') $(c 36 h.sh)$(c 33 ': ')$(c 1 X)$(c 33 ' has no value; not passed to ')$(c '1;32' T)"
assert_eq "$expected" "$(ALIPREHOOK_COLOR=always eval $warn 2>&1)" "purple warning: label/text yellow, items keep colors"

expected="$B$(c '1;31' 'error:') $(c 31 'user hook not executable: ')$(c 34 /x.sh)$(c 31 ' ')$(c 90 '(run: chmod +x /x.sh)')"
assert_eq "$expected" "$(ALIPREHOOK_COLOR=always _aliprehook_msg error "user hook not executable: " "@key=/x.sh" " " "@hint=(run: chmod +x /x.sh)" 2>&1)" "purple error"

expected="$B$(c '1;32' allowed) $(c 34 github.com/org/x)"
assert_eq "$expected" "$(ALIPREHOOK_COLOR=always _aliprehook_msg success "@success=allowed" " " "@key=github.com/org/x")" "success: no label, default text"
expected="${B}project hooks from $(c 34 /r/.aliprehook.yml) will now run"
assert_eq "$expected" "$(ALIPREHOOK_COLOR=always _aliprehook_msg info "project hooks from " "@key=/r/.aliprehook.yml" " will now run")" "info: default text color"

expected="$B$(c '1;32' Dup)$(c 31 ' aborted: required variable missing: ')$(c 1 A)$(c 31 ', ')$(c 1 B)"
assert_eq "$expected" "$(ALIPREHOOK_COLOR=always _aliprehook_msg_missing Dup A B A 2>&1)" "aborted: no label, names deduplicated"

# --- streams: warning/error → stderr, info/success → stdout ---
assert_eq "" "$(_aliprehook_msg error x 2>/dev/null)" "error goes to stderr"
assert_eq "aliprehook: x" "$(_aliprehook_msg info x 2>/dev/null)" "info goes to stdout"

# --- theme switching without touching code ---
export ALIPREHOOK_COLOR=always
has_esc "$(ALIPREHOOK_THEME=none eval $warn 2>&1)" && fail "theme none: escape codes present"
ALIPREHOOK_THEME=none; _aliprehook_msg info x >/dev/null; unset ALIPREHOOK_THEME
has_esc "$(eval $warn 2>&1)" || fail "switching back to purple without re-source"

# Partial custom theme: only brand colored.
print 'brand=35' > $tmp/mine.theme
assert_eq "${E}[35maliprehook:${E}[0m warning: h.sh: X has no value; not passed to T" \
  "$(ALIPREHOOK_THEME=$tmp/mine.theme eval $warn 2>&1)" "partial custom theme: missing roles uncolored"

# User override: one role changes, the rest stays purple.
print '# my tweak\nhook = 35   # magenta hooks' > $ALIPREHOOK_HOME/theme
_aliprehook_theme_key=   # as after a new `source`
out=$(eval $warn 2>&1)
[[ $out == *"${E}[35mh.sh${E}[0m"* ]] || fail "user override: hook color not applied: ${(q+)out}"
[[ $out == "$B"* ]] || fail "user override: brand changed"
rm $ALIPREHOOK_HOME/theme; _aliprehook_theme_key=

# Theme files are parsed, never sourced; bad codes are ignored.
print 'brand=$(touch '$tmp'/pwned)\nhook=31;evil\nkey=34' > $tmp/bad.theme
out=$(ALIPREHOOK_THEME=$tmp/bad.theme _aliprehook_msg info "@hook=h" " " "@key=k")
[[ ! -e $tmp/pwned ]] || fail "theme file was executed"
assert_eq "aliprehook: h ${E}[34mk${E}[0m" "$out" "invalid theme codes ignored"

# Unknown theme: warning, no colors.
err=$(ALIPREHOOK_THEME=nope _aliprehook_msg info x 2>&1 >/dev/null)
[[ $err == *"theme not found"*"nope.theme"* ]] || fail "unknown theme warning: '$err'"
_aliprehook_theme_key=

# --- aliprehook_env_pass uses the same theme and rules ---
print -r -- '#!/bin/sh
aliprehook_env_pass X' > $ALIPREHOOK_HOME/hooks/h.sh
chmod +x $ALIPREHOOK_HOME/hooks/h.sh
print -r -- "$tmp/proj  T  hooks/h.sh" > $ALIPREHOOK_HOME/registry
lib_line=$(eval '_aliprehook_msg warning "@hook=h.sh" ": " "@var=X" " has no value (unset, empty or not exported); not passed to " "@command=T"' 2>&1)
hook_line=$(aliprehook_run T 2>&1)
assert_eq "$lib_line" "$hook_line" "aliprehook_env_pass output identical to lib.zsh (always)"
has_esc "$hook_line" || fail "aliprehook_env_pass: no colors with always"
assert_eq "aliprehook: warning: h.sh: X has no value (unset, empty or not exported); not passed to T" \
  "$(ALIPREHOOK_COLOR=never aliprehook_run T 2>&1)" "aliprehook_env_pass: never"
ALIPREHOOK_COLOR=never   # not exported: still reaches the hook
assert_eq 0 "${#${(M)$(aliprehook_run T 2>&1)##*$E*}}" "unexported ALIPREHOOK_COLOR reaches hooks"
ALIPREHOOK_THEME=none
unset ALIPREHOOK_COLOR; export ALIPREHOOK_COLOR=always
has_esc "$(aliprehook_run T 2>&1)" && fail "aliprehook_env_pass: theme none still colored"
unset ALIPREHOOK_THEME

# Every failure carries an error: label.
print '#!/bin/sh' > $ALIPREHOOK_HOME/hooks/noexec.sh
print -r -- "$tmp/proj  N  hooks/noexec.sh" > $ALIPREHOOK_HOME/registry
ALIPREHOOK_COLOR=never
[[ "$(aliprehook_run N 2>&1)" == "aliprehook: error: user hook not executable: "* ]] || fail "not executable: no error: label"

finish
