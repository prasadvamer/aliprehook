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

mkdir -p "$dest/hooks" "$dest/bin" "$dest/themes"

for f in lib.zsh README.md bin/aliprehook_env_pass themes/purple.theme themes/none.theme; do
  rm -f "$dest/$f"
  if [ "$mode" = link ]; then
    ln -s "$src/$f" "$dest/$f"
  else
    cp "$src/$f" "$dest/$f"
  fi
done

# Renamed user files (0.x): move an old file to its new name if the new one
# does not exist yet. Never overwrites.
for pair in registry:hooks.map commands:commands.map allowed:allowed-repos theme:theme-overrides; do
  old=${pair%%:*} new=${pair#*:}
  if [ -f "$dest/$old" ] && [ ! -e "$dest/$new" ]; then
    mv "$dest/$old" "$dest/$new"
    echo "renamed $dest/$old -> $new"
  fi
done

# User data: create if missing, never overwrite.
for f in hooks.map allowed-repos commands.map; do
  [ -e "$dest/$f" ] || { cp "$src/templates/$f" "$dest/$f" && chmod go-w "$dest/$f"; }
done
[ -e "$dest/hooks/example_echo.sh" ] || cp "$src/hooks/example_echo.sh" "$dest/hooks/example_echo.sh"

echo "aliprehook installed to $dest ($mode)"
