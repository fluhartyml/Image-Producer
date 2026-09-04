#!/bin/sh
# Installs this repo's git hooks. Run ONCE per clone, per machine.
#
# Git deliberately does not copy hooks when a repository is cloned, so a hook that lives
# only in .git/hooks is one machine away from not existing at all. Keeping the real copy
# in Scripts/ and installing from there means the behaviour travels with the repository.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cp "$ROOT/Scripts/post-commit" "$ROOT/.git/hooks/post-commit"
chmod +x "$ROOT/.git/hooks/post-commit"
echo "installed: .git/hooks/post-commit -> Scripts/stamp-build.sh"
