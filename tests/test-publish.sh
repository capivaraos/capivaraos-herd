#!/bin/bash
# =============================================================================
# publish-repo.sh: pages and release against a local copy of the Pages
# repository, in a Fedora 45 container, with throwaway keys and no network.
# =============================================================================
# Checks that:
#   1. pages publishes signed metadata to f<rel>/<arch>, leaves every other
#      path alone, and a rerun commits nothing;
#   2. pages refuses: missing, foreign or stale signatures, metadata whose
#      packages do not all point at the repo-herd Releases, stray .rpm files,
#      bad --rel/--arch values and the older staging layout; it accepts
#      metadata signed by the reserve key;
#   3. release refuses a channel whose index is not signed by a Herd key.
#
# Usage (from the repository root):  ./tests/test-publish.sh
# Requires: podman.
# =============================================================================
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v podman >/dev/null || { echo "ERROR: podman required" >&2; exit 1; }

podman run -i --rm \
    -v "${PROJECT_DIR}":/src:ro \
    --security-opt label=disable \
    registry.fedoraproject.org/fedora:45 bash -s <<'EOS'
set -euo pipefail; export LC_ALL=C
ok() { echo "  [OK] $*"; }
fail() { echo "  [FAIL] $*"; exit 1; }
say() { echo; echo "=== $* ==="; }

say "0. Tools"
dnf install -y -q --setopt=install_weak_deps=False createrepo_c gnupg2 git rsync \
    rpm-build zstd >/dev/null 2>&1 \
    || dnf install -y -q createrepo_c gnupg2 git rsync rpm-build zstd >/dev/null
git config --global user.email test@example.invalid
git config --global user.name test
git config --global init.defaultBranch main

say "1. Throwaway keys, package, local Pages repositories"
export GNUPGHOME=/root/.gnupg-test; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
for n in current reserve other; do
    printf '%s\n' '%no-protection' 'Key-Type: RSA' 'Key-Length: 2048' 'Key-Usage: sign' \
        "Name-Real: $n" "Name-Email: $n@example.invalid" 'Expire-Date: 0' '%commit' > /root/k
    gpg --batch --gen-key /root/k 2>/dev/null
    gpg --armor --export "$n@example.invalid" > "/root/$n.asc"
done
printf '%s\n' 'Name: dm' 'Version: 1' 'Release: 1' 'Summary: t' 'License: MIT' \
    'BuildArch: noarch' '%description' 't' '%files' > /root/dm.spec
rpmbuild -bb /root/dm.spec >/dev/null 2>&1
RPM=~/rpmbuild/RPMS/noarch/dm-1-1.noarch.rpm
git init -q --bare /root/pages.git; git clone -q /root/pages.git /root/seed 2>/dev/null
( cd /root/seed
  mkdir -p f44/x86_64; echo old > f44/x86_64/x; echo c > CNAME
  git add -A; git commit -qm seed; git push -q origin HEAD:main )
ok "ready"

URL=https://github.com/capivaraos/repo-herd/releases/download/herd-f45-x86_64-stable/
export HERD_TEST=1 HERD_REPO_ROOT=/root/out/repo HERD_REL_ROOT=/root/out/releases \
       HERD_PAGES_REPO=/root/pages.git \
       HERD_PUBKEY=/root/current.asc HERD_RESERVE_PUBKEY=/root/reserve.asc
M=$HERD_REPO_ROOT/f45/x86_64/stable; P=$HERD_REL_ROOT/f45/x86_64/stable
mk() {  # mk [xml:base] [signing key]
    rm -rf /root/out; mkdir -p "$M" "$P"; cp "$RPM" "$P/"
    if [ "${1-$URL}" = none ]; then createrepo_c -q -o "$M" "$P"
    else createrepo_c -q -u "${1:-$URL}" -o "$M" "$P"; fi
    gpg --batch -q --detach-sign --armor -u "${2:-current}@example.invalid" "$M/repodata/repomd.xml"
}
run() { /src/publish-repo.sh "$@" >/root/log 2>&1; }
refused() {  # refused <label> <args...>
    local label="$1"; shift
    if run "$@"; then cat /root/log; fail "$label: accepted"; fi
    ok "$label: refused ($(tail -1 /root/log))"
}
commits() { git --git-dir="/root/$1.git" rev-list --count main; }

say "2. pages, good input"
mk; run pages --rel 45 || { cat /root/log; fail "pages failed"; }
git clone -q /root/pages.git /root/chk
[ -f /root/chk/f45/x86_64/stable/repodata/repomd.xml.asc ] && ok "stable metadata published" \
    || fail "stable metadata missing"
[ "$(cat /root/chk/f44/x86_64/x)" = old ] && [ -f /root/chk/CNAME ] \
    && ok "other paths left alone" || fail "other paths changed"
n=$(commits pages); run pages --rel 45
[ "$(commits pages)" = "$n" ] && ok "rerun commits nothing" || fail "rerun committed"
[ -z "$(ls /tmp)" ] && ok "no temporary files left" || fail "temporary files left: $(ls /tmp)"

say "3. pages refuses bad input"
mk; rm "$M/repodata/repomd.xml.asc"; refused "unsigned" pages --rel 45
mk "" other;                         refused "signed by an unknown key" pages --rel 45
mk; echo '<!-- x -->' >> "$M/repodata/repomd.xml"; refused "stale signature" pages --rel 45
mk https://example.invalid/;         refused "foreign xml:base" pages --rel 45
mk none;                             refused "no xml:base" pages --rel 45
mk; cp "$RPM" "$M/";                 refused "stray .rpm" pages --rel 45
mk;                                  refused "--rel with a path" pages --rel '45/../../f44'
grep -q 'must be a number' /root/log || { cat /root/log; fail "--rel refused by the wrong check"; }
mk;                                  refused "--arch with a path" pages --rel 45 --arch 'x86_64/../..'
grep -q 'must be x86_64 or aarch64' /root/log || { cat /root/log; fail "--arch refused by the wrong check"; }
mk; mkdir -p /root/out/repo/herd;    refused "older staging layout" pages --rel 45
[ "$(commits pages)" = 2 ] && ok "Pages repository: only the one good commit" || fail "Pages repository changed"

say "4. pages accepts metadata signed by the reserve key"
mk "" reserve
run pages --rel 45 || { cat /root/log; fail "pages refused reserve-signed metadata"; }
[ "$(commits pages)" = 3 ] && ok "reserve-signed metadata published (Herd 2.x trusts it)" \
    || fail "pages did not publish reserve-signed metadata"

say "5. release refuses an index that is not signed by a Herd key"
mk; rm "$M/repodata/repomd.xml.asc"; refused "release, unsigned index" release --rel 45 --channel stable
mk "" other;                         refused "release, unknown key" release --rel 45 --channel stable
grep -q 'not signed by a Herd key' /root/log && ok "refused before any upload" || { cat /root/log; fail "wrong error"; }

say "RESULT: ALL TESTS PASSED"
EOS
