#!/usr/bin/env zsh
# Run every tests/test_*.zsh in a fresh zsh. Exit non-zero if any fail.

root=${0:A:h:h}
typeset -i failed=0 total=0

for t in $root/tests/test_*.zsh(N); do
  (( total++ ))
  if ALIPREHOOK_ROOT=$root zsh -f $t; then
    print "ok   ${t:t}"
  else
    print "FAIL ${t:t}"
    (( failed++ ))
  fi
done

print "$(( total - failed ))/$total passed"
(( failed == 0 ))
