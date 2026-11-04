#!/bin/sh
# Dev uninstall: remove what install.sh manages. Never touches user data.
set -eu

[ $# -eq 0 ] || { echo "usage: $0" >&2; exit 2; }

dest=${ALIPREHOOK_HOME:-$HOME/.config/aliprehook}

if [ ! -d "$dest" ]; then
  echo "aliprehook not installed at $dest"
  exit 0
fi

for f in lib.zsh README.md bin/aliprehook_env_pass themes/purple.theme themes/none.theme; do
  if [ -L "$dest/$f" ] || [ -f "$dest/$f" ]; then
    rm -f "$dest/$f"
    echo "removed $dest/$f"
  fi
done
rmdir "$dest/bin" "$dest/themes" 2>/dev/null || true

for f in registry allowed hooks theme; do
  [ -e "$dest/$f" ] && echo "kept    $dest/$f"
done

zshrc=${ZDOTDIR:-$HOME}/.zshrc
if [ -f "$zshrc" ] && grep -q 'aliprehook/lib\.zsh' "$zshrc"; then
  echo "warning: $zshrc still sources aliprehook/lib.zsh; remove that line" >&2
fi

echo "user data kept; for full removal: rm -rf $dest"
