source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
ALIPREHOOK_HOME=$tmp/home
mkdir -p $ALIPREHOOK_HOME

# examples/project works as documented in its README.
git init -q $tmp/try
cp -r $ALIPREHOOK_ROOT/examples/project/. $tmp/try/
cd $tmp/try

main() { :; }
aliprehook_define Dup main

Dup 2>/dev/null
[[ ! -e .env ]] || fail "example hook ran before allow"

aliprehook allow >/dev/null
err=$(Dup 2>&1)
assert_file .env
assert_eq "$(<.env.example)" "$(<.env)" ".env copied from .env.example"
[[ $err == *"created .env"* ]] || fail "example hook message: '$err'"

# Second run leaves an existing .env alone.
print 'APP_ENV=mine' > .env
Dup 2>/dev/null
assert_eq "APP_ENV=mine" "$(<.env)" ".env not overwritten"

finish
