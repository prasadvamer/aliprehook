source $ALIPREHOOK_ROOT/tests/helpers.zsh
source $ALIPREHOOK_ROOT/lib.zsh

check() { assert_eq "$2" "$(aliprehook_normalize_remote $1)" "normalize $1"; }

# Table from doc/01.
check git@github.com:org/sample_app_web.git        github.com/org/sample_app_web
check https://github.com/org/sample_app_web.git    github.com/org/sample_app_web
check https://github.com/org/sample_app_web        github.com/org/sample_app_web
check ssh://git@github.com/org/sample_app_web.git  github.com/org/sample_app_web

# Other schemes and userinfo.
check http://github.com/org/sample_app_web         github.com/org/sample_app_web
check https://user:token@github.com/org/repo.git   github.com/org/repo
check ssh://github.com/org/repo.git                github.com/org/repo
check git://github.com/org/repo.git                github.com/org/repo

# SCP-style without user, nested groups.
check github.com:org/repo.git                      github.com/org/repo
check git@gitlab.com:group/sub/repo.git            gitlab.com/group/sub/repo

# Trailing slash / .git combos.
check https://github.com/org/repo/                 github.com/org/repo
check https://github.com/org/repo.git/             github.com/org/repo
check git@github.com:org/repo.git/                 github.com/org/repo

# Host lowercased, path case kept.
check git@GitHub.COM:Org/Repo.git                  github.com/Org/Repo
check HTTPS://GitHub.com/Org/Repo                  github.com/Org/Repo

# Self-hosted with port (port kept).
check ssh://git@git.example.com:2222/org/repo.git  git.example.com:2222/org/repo

# Local path remote: only the end is trimmed.
check /srv/git/repo.git                            /srv/git/repo

# Empty input fails.
aliprehook_normalize_remote '' >/dev/null && fail "empty input accepted"

finish
