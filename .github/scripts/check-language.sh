#!/usr/bin/env bash
# Commit messages are written in English. Text quoted with backticks or double
# quotes (for example a user-interface string) is not checked.
set -euo pipefail
# shellcheck source=common.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

bad=0
for c in $(commits); do
    text=$(git log -1 --format=%B "$c" | sed -E 's/`[^`]*`//g; s/"[^"]*"//g')
    if grep -qE '[ãõçáéíóúâêôàÃÕÇÁÉÍÓÚÂÊÔÀ]' <<<"$text"; then
        echo "::error::commit $(git rev-parse --short "$c"): commit messages must be written in English"
        bad=1
    fi
done
exit "$bad"
