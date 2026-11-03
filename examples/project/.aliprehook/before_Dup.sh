#!/bin/sh
# Example project hook for Dup: create .env from .env.example on first run.
cd "$ALIPREHOOK_PROJECT_ROOT" || exit 1

if [ -f .env.example ] && [ ! -f .env ]; then
  cp .env.example .env
  echo "aliprehook: created .env from .env.example" >&2
fi
