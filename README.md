# aliprehook

Optional prehooks for opt-in shell commands, keyed by project (git remote, then `$PWD`).

Status: early development. Design docs are in [doc/](./doc/).

## Dev install

```sh
./install.sh          # symlink lib.zsh and README.md into ~/.config/aliprehook/
./install.sh --copy   # copy instead of symlink
```

Set `ALIPREHOOK_HOME` to install somewhere else. Existing `registry` and `allowed` files are never overwritten.

Then add to `~/.zshrc`:

```zsh
source ~/.config/aliprehook/lib.zsh
```

## Tests

```sh
zsh tests/run.zsh
```
