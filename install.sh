#!/bin/sh
# Dev install: link (or copy) aliprehook into ALIPREHOOK_HOME.
set -eu

mode=link
case "${1:-}" in
  "") ;;
  --copy) mode=copy ;;
  *) echo "usage: $0 [--copy]" >&2; exit 2 ;;
esac

src=$(cd "$(dirname "$0")" && pwd -P)
dest=${ALIPREHOOK_HOME:-$HOME/.config/aliprehook}

mkdir -p "$dest/hooks"

for f in lib.zsh README.md; do
  rm -f "$dest/$f"
  if [ "$mode" = link ]; then
    ln -s "$src/$f" "$dest/$f"
  else
    cp "$src/$f" "$dest/$f"
  fi
done

# User data: create if missing, never overwrite.
for f in registry allowed; do
  [ -e "$dest/$f" ] || cp "$src/templates/$f" "$dest/$f"
done
[ -e "$dest/hooks/example_echo.sh" ] || cp "$src/hooks/example_echo.sh" "$dest/hooks/example_echo.sh"

echo "aliprehook installed to $dest ($mode)"
