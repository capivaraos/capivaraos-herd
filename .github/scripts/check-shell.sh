#!/usr/bin/env bash
# shellcheck disable=SC2154  # base and head are set by common.sh
# Syntax and ShellCheck (error level) on the shell files changed in this range.
set -euo pipefail
# shellcheck source=common.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

bad=0
while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    bash -n "$f" || bad=1
    shellcheck -S error "$f" || bad=1
done < <(git diff --name-only -z --diff-filter=ACMR "$base" "$head" -- '*.sh')
exit "$bad"
