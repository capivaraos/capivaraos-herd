#!/usr/bin/env bash
# shellcheck disable=SC2154  # base and head are set by common.sh
# Checks added lines, new file paths, commit messages, the branch name and the
# pull request title and description against the project text policy. The
# policy is supplied by the environment; without it (pull requests from forks)
# the check is skipped and a maintainer reviews by hand.
set -euo pipefail
# shellcheck source=common.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [ -z "${POLICY_DENY_B64:-}" ]; then
    echo "::notice::text policy not available in this context; skipped"
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '%s' "$POLICY_DENY_B64" | base64 -d >"$tmp/deny"
printf '%s' "${POLICY_ALLOW_B64:-}" | base64 -d >"$tmp/allow" 2>/dev/null || : >"$tmp/allow"

# scan <label> <file of "location<TAB>text" lines>
# Exemptions are matched against "location:text", the policy against the text
# alone. Reports locations only: matched text and rule stay out of the log.
scan() {
    local label=$1 in=$2 hits
    cut -f1 "$in" >"$tmp/loc"
    cut -f2- "$in" >"$tmp/txt"
    paste -d: "$tmp/loc" "$tmp/txt" >"$tmp/joined"
    : >"$tmp/exempt"
    if [ -s "$tmp/allow" ]; then grep -nE -f "$tmp/allow" "$tmp/joined" | cut -d: -f1 >"$tmp/exempt" || true; fi
    grep -niE -f "$tmp/deny" "$tmp/txt" | cut -d: -f1 >"$tmp/hit" || true
    hits=$(awk 'FILENAME == ARGV[1] { skip[$1] = 1; next }
                FILENAME == ARGV[2] { if (!($1 in skip)) want[$1] = 1; next }
                (FNR in want) { print }' "$tmp/exempt" "$tmp/hit" "$tmp/loc" | sort -u)
    [ -z "$hits" ] && return 0
    while IFS= read -r loc; do echo "::error::$label: $loc does not follow the writing guidelines"; done <<<"$hits"
    return 1
}

bad=0

git diff --unified=0 --no-color --diff-filter=ACMR "$base" "$head" | awk '
    /^\+\+\+ /  { f = ($2 == "/dev/null") ? "" : substr($0, 7); next }
    /^--- /     { next }
    /^@@ /      { if (match($0, /\+[0-9]+/)) n = substr($0, RSTART + 1, RLENGTH - 1) - 1; next }
    /^\+/       { n++; if (f != "") print f ":" n "\t" substr($0, 2); next }
    /^ /        { n++ }
' >"$tmp/diff"
scan "file" "$tmp/diff" || bad=1

git diff --name-only --diff-filter=AR "$base" "$head" | awk '{ print "new path " NR "\t" $0 }' >"$tmp/paths"
scan "path" "$tmp/paths" || bad=1

: >"$tmp/msgs"
for c in $(commits); do
    short=$(git rev-parse --short "$c")
    git log -1 --format=%B "$c" |
        sed -E '/^Refs: ((BUG|FEAT|DOC|PKG|REL)-[0-9]+)(, (BUG|FEAT|DOC|PKG|REL)-[0-9]+)*$/d' |
        sed "s/^/commit $short\t/" >>"$tmp/msgs"
done
scan "message" "$tmp/msgs" || bad=1

if [ -n "${HEAD_REF:-}" ]; then
    printf 'branch\t%s\n' "$HEAD_REF" >"$tmp/branch"
    scan "name" "$tmp/branch" || bad=1
fi

if [ -n "${PR_TITLE:-}${PR_BODY:-}" ]; then
    {
        printf 'title\t%s\n' "${PR_TITLE:-}"
        printf '%s\n' "${PR_BODY:-}" | tr -d '\r' | awk '{ print "description line " NR "\t" $0 }'
    } >"$tmp/pr"
    scan "pull request" "$tmp/pr" || bad=1
fi

exit "$bad"
