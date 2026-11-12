#!/usr/bin/env bash
# Commits from project branches must carry the project identity.
set -euo pipefail
# shellcheck source=common.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

allowed='^(capivaraos-bot@users\.noreply\.github\.com|[0-9]+\+capivaraos@users\.noreply\.github\.com|noreply@github\.com)$'
bad=0
for c in $(commits); do
    for e in "$(git log -1 --format=%ae "$c")" "$(git log -1 --format=%ce "$c")"; do
        if ! [[ $e =~ $allowed ]]; then
            echo "::error::commit $(git rev-parse --short "$c") uses an identity outside the project policy"
            bad=1
        fi
    done
done
exit "$bad"
