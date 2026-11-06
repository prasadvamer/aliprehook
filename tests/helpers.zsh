# Assertion helpers for aliprehook tests. Each test file runs in its own zsh.

typeset -gi ALIPREHOOK_TEST_FAILS=0

# Run summary off by default; tests/test_trace.zsh covers it.
export ALIPREHOOK_VERBOSE=quiet

fail() {
  print -u2 "  FAIL: $*"
  (( ALIPREHOOK_TEST_FAILS++ ))
}

assert_eq() {  # expected actual [message]
  [[ $1 == "$2" ]] || fail "${3:-assert_eq}: expected '$1', got '$2'"
}

assert_file() { [[ -f $1 ]] || fail "missing file: $1"; }
assert_dir()  { [[ -d $1 ]] || fail "missing dir: $1"; }
assert_link() { [[ -L $1 ]] || fail "not a symlink: $1"; }

finish() { exit $(( ALIPREHOOK_TEST_FAILS > 0 )); }
