# Shared helpers for the guard scripts. Sourced, not executed.
# shellcheck shell=bash

zero=0000000000000000000000000000000000000000
base=${BASE_SHA:-}
head=${HEAD_SHA:-HEAD}

if [ -z "$base" ] || [ "$base" = "$zero" ] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
    base=$(git rev-list --max-parents=0 "$head" | tail -n1)
fi

commits() { git rev-list --no-merges "$base..$head"; }
