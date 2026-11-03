#!/bin/sh
# Example aliprehook hook: safe, no side effects.
# Output goes to stderr so it never mixes with the main command's stdout.
{
  echo "aliprehook: example_echo.sh ran"
  echo "  project key: ${ALIPREHOOK_PROJECT_KEY:-?}"
  echo "  command:     ${ALIPREHOOK_COMMAND:-?} $*"
} >&2
exit 0
