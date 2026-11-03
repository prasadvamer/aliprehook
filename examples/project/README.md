# Example project layer

Files a repo would ship to give `Dup` a project prehook:

```text
.aliprehook.yml            # Dup → .aliprehook/before_Dup.sh
.aliprehook/before_Dup.sh  # creates .env from .env.example if missing
.env.example
```

Try it in a throwaway repo:

```sh
mkdir /tmp/try-aliprehook && cd /tmp/try-aliprehook && git init
cp -r ~/path/to/aliprehook/examples/project/. .
rm README.md
```

```zsh
Dup --version       # hook does not run: repo not allowed yet
aliprehook allow
Dup --version       # hook runs: "created .env from .env.example"
aliprehook revoke
```
