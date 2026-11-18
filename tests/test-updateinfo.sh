#!/bin/bash
# =============================================================================
# Herd advisories (updateinfo) and the security-only automatic update policy.
# =============================================================================
# In a Fedora 45 container, with a throwaway key and the shipped
# autoupdate/automatic.conf (upgrade_type = security), checks that:
#   1. `publish-repo.sh advisory` writes an advisory from the package headers,
#      does not overwrite an existing file and refuses bad input;
#   2. `add` publishes to testing only and attaches no advisory; `promote`
#      attaches it to stable, and the signed repomd.xml covers it;
#   3. dnf5 automatic installs the update named in a security advisory and
#      leaves an update without an advisory alone, including a newer version
#      of a package whose advisory names the installed version; with an
#      advisory for version 2 and a version 3 available, it installs 3;
#   4. an advisory whose packages are not in the channel is left out; one that
#      matches only partly, names a file in the channel with a different NEVRA
#      or is malformed stops the run, and `release` then refuses the unsigned
#      index; a withdrawn advisory leaves the index;
#   5. outside the tests, `promote` reads advisories as committed in HEAD (export
#      attributes and replace refs do not apply) and stops on untracked,
#      ignored or modified files, anything but plain files, or a file name
#      that is not an advisory id, under advisories/.
#
# Never uses the production key. Does not touch the host.
# Usage (from the repository root):  ./tests/test-updateinfo.sh
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
dnf install -y -q --setopt=install_weak_deps=False rpm-build rpm-sign createrepo_c \
    gnupg2 python3 dnf5-plugin-automatic zstd git >/dev/null 2>&1 \
    || dnf install -y -q rpm-build rpm-sign createrepo_c gnupg2 python3 dnf5-plugin-automatic zstd git >/dev/null

say "1. Throwaway key and packages"
export GNUPGHOME=/root/.gnupg-test; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
printf '%s\n' '%no-protection' 'Key-Type: RSA' 'Key-Length: 3072' 'Key-Usage: sign' \
  'Name-Real: Herd TEST throwaway' 'Name-Email: test@example.invalid' \
  'Expire-Date: 0' '%commit' > /root/kp
gpg --batch --gen-key /root/kp 2>/dev/null
gpg --armor --export test@example.invalid > /root/pub.asc
printf '%s\n' '%_gpg_name Herd TEST throwaway' '%_gpg_digest_algo sha512' > ~/.rpmmacros
mkdir -p /root/specs
for p in herd-fixed herd-plain herd-other; do
    for v in 1 2 3; do
        printf '%s\n' "Name: $p" "Version: $v" 'Release: 1' 'Summary: t' 'License: MIT' \
            'BuildArch: noarch' '%description' 't' '%files' > "/root/specs/$p-$v.spec"
        rpmbuild -bb "/root/specs/$p-$v.spec" >/dev/null 2>&1 || fail "build $p-$v"
    done
done
R=~/rpmbuild/RPMS/noarch
ok "packages built"

export HERD_TEST=1 HERD_REPO_ROOT=/root/out/repo HERD_REL_ROOT=/root/out/releases \
       HERD_ADVISORY_DIR=/root/advisories HERD_GPG_NAME='Herd TEST throwaway' \
       HERD_PKG_BASEURL=file:///root/pkgs
PUB=/src/publish-repo.sh

say "2. advisory writes the file from the package headers"
$PUB advisory --id HERD-2026-0001 --type security --severity Important \
    --title "herd-fixed: test fix" --cve CVE-2026-0001 "$R/herd-fixed-2-1.noarch.rpm" >/dev/null
A=/root/advisories/HERD-2026-0001.xml
[ -f "$A" ] && ok "advisory written" || fail "no advisory file"
grep -q 'name="herd-fixed" epoch="0" version="2" release="1" arch="noarch"' "$A" \
    && ok "advisory names herd-fixed-2-1.noarch" || { cat "$A"; fail "wrong package in advisory"; }
# An advisory for a package that never reaches a channel.
$PUB advisory --id HERD-2026-0002 --type security --severity Low \
    --title "herd-other: not published" "$R/herd-other-2-1.noarch.rpm" >/dev/null
if $PUB advisory --id HERD-2026-0001 --type security --severity Low --title x \
    "$R/herd-fixed-2-1.noarch.rpm" >/dev/null 2>&1; then
    fail "an existing advisory was rewritten"
fi
ok "advisory does not overwrite an existing file"
bad_new() {  # bad_new <label> <args...>
    local label="$1"; shift
    if $PUB advisory --type security --severity Low "$@" "$R/herd-fixed-2-1.noarch.rpm" >/dev/null 2>&1; then
        fail "$label: accepted"
    fi
    ok "$label: refused"
}
bad_new "malformed advisory id" --id BAD --title x
bad_new "control character in the title" --id HERD-2026-0090 --title "$(printf 'a\001b')"
bad_new "blank title" --id HERD-2026-0091 --title "   "
bad_new "control character in the description" --id HERD-2026-0092 --title x \
    --description "$(printf 'a\033b')"
ls /root/advisories/HERD-2026-009* >/dev/null 2>&1 && fail "a refused advisory left a file"
ok "refused advisories leave no file"

say "3. add (testing) attaches no advisory; promote attaches it to stable"
cp "$R"/herd-{fixed,plain}-2-1.noarch.rpm /root/
$PUB add --rel 45 --arch x86_64 --channel testing /root/herd-fixed-2-1.noarch.rpm \
    /root/herd-plain-2-1.noarch.rpm >/root/add.log 2>&1 || { cat /root/add.log; fail "add failed"; }
if $PUB add --rel 45 --arch x86_64 --channel stable /root/herd-plain-2-1.noarch.rpm >/root/p.log 2>&1; then
    fail "add --channel stable accepted"
fi
ok "add --channel stable: refused ($(tail -1 /root/p.log))"
T=$HERD_REPO_ROOT/f45/x86_64/testing
grep -q 'type="updateinfo"' "$T/repodata/repomd.xml" && fail "testing index has updateinfo"
ok "testing index has no advisory"
$PUB promote --rel 45 --arch x86_64 >/root/promote.log 2>&1 || { cat /root/promote.log; fail "promote failed"; }
S=$HERD_REPO_ROOT/f45/x86_64/stable
ui() { local f; f=$(find "$S/repodata" -name '*updateinfo.xml*'); [ -n "$f" ] && zstdcat -f "$f" 2>/dev/null; }
grep -q 'type="updateinfo"' "$S/repodata/repomd.xml" && ok "stable repomd.xml lists updateinfo" \
    || { cat /root/promote.log; fail "no updateinfo in stable"; }
ui | grep -q HERD-2026-0001 && ok "stable updateinfo has HERD-2026-0001" || fail "HERD-2026-0001 missing"
ui | grep -q HERD-2026-0002 && fail "HERD-2026-0002 attached although herd-other is not in stable"
ok "advisory for a package not in the channel is left out"
gpg --batch --verify "$S/repodata/repomd.xml.asc" "$S/repodata/repomd.xml" 2>/dev/null \
    && ok "repomd.xml (with updateinfo) signature verifies" || fail "bad repomd signature"

say "4. dnf5 automatic, shipped security-only policy"
mkdir -p /root/pkgs/herd-f45-x86_64-stable
cp "$HERD_REL_ROOT"/f45/x86_64/stable/*.rpm /root/pkgs/herd-f45-x86_64-stable/
rpmkeys --import /root/pub.asc
rpm -i --nosignature "$R/herd-fixed-1-1.noarch.rpm" "$R/herd-plain-1-1.noarch.rpm"
cat > /etc/yum.repos.d/herd-t.repo <<EOF
[herd-t]
name=Herd TEST
baseurl=file://$S
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///root/pub.asc
EOF
mkdir -p /etc/dnf; cp /src/autoupdate/automatic.conf /etc/dnf/automatic.conf
grep -qx 'upgrade_type = security' /etc/dnf/automatic.conf || fail "shipped policy is not security-only"
dnf5 -y --repo=herd-t makecache >/dev/null 2>&1
dnf5 automatic --disablerepo='*' --enablerepo=herd-t </dev/null >/root/auto.log 2>&1 || true
rpm -q herd-fixed-2-1 >/dev/null 2>&1 && ok "update in a security advisory: installed" \
    || { cat /root/auto.log; fail "herd-fixed-2 not installed"; }
rpm -q herd-plain-1-1 >/dev/null 2>&1 && ! rpm -q herd-plain-2-1 >/dev/null 2>&1 \
    && ok "update without an advisory: left alone" || fail "herd-plain changed"

say "4b. Advisory for the installed version, newer version without one"
# herd-fixed-2-1 is installed and HERD-2026-0001 names 2-1; publish 3-1 with no
# advisory and see whether the unattended run takes it.
$PUB add --rel 45 --arch x86_64 --channel testing "$R/herd-fixed-3-1.noarch.rpm" >/root/p.log 2>&1 \
    && $PUB promote --rel 45 --arch x86_64 >>/root/p.log 2>&1 || { cat /root/p.log; fail "publish 3-1 failed"; }
cp "$HERD_REL_ROOT"/f45/x86_64/stable/*.rpm /root/pkgs/herd-f45-x86_64-stable/
dnf5 -y --repo=herd-t makecache --refresh >/dev/null 2>&1
dnf5 -q --repo=herd-t repoquery --available herd-fixed-3-1 2>/dev/null | grep -q herd-fixed \
    && ok "herd-fixed-3-1 is visible in the repository" || fail "herd-fixed-3-1 not visible; the check below would prove nothing"
dnf5 automatic --disablerepo='*' --enablerepo=herd-t </dev/null >/root/auto2.log 2>&1 || true
echo "  MEASURED: after the run, $(rpm -q herd-fixed)"
rpm -q herd-fixed-2-1 >/dev/null 2>&1 \
    && ok "advisory for the installed version: newer version without an advisory left alone" \
    || { cat /root/auto2.log; fail "herd-fixed-3 installed without an advisory naming a newer version"; }

say "5. Bad advisories stop the run"
cp -a /root/advisories /root/adv-good
# Partly in the channel: herd-fixed-2 is there, herd-other-2 is not.
$PUB advisory --id HERD-2026-0003 --type security --severity Low --title "partial" \
    "$R/herd-fixed-2-1.noarch.rpm" "$R/herd-other-2-1.noarch.rpm" >/dev/null
if $PUB promote --rel 45 --arch x86_64 >/root/p.log 2>&1; then fail "partial advisory accepted"; fi
grep -q 'only part of its packages' /root/p.log && ok "partly matching advisory: refused" || { cat /root/p.log; fail "wrong error"; }
rm /root/advisories/HERD-2026-0003.xml
# Same file name, different build.
sed -i 's/name="herd-fixed" epoch="0" version="2" release="1"/name="herd-fixed" epoch="0" version="2" release="9"/' \
    /root/advisories/HERD-2026-0001.xml
if $PUB promote --rel 45 --arch x86_64 >/root/p.log 2>&1; then fail "mismatched build accepted"; fi
grep -q 'different build' /root/p.log && ok "advisory naming a different build: refused" || { cat /root/p.log; fail "wrong error"; }
# Malformed XML.
echo '<update><id>' > /root/advisories/HERD-2026-0001.xml
if $PUB promote --rel 45 --arch x86_64 >/root/p.log 2>&1; then fail "malformed advisory accepted"; fi
grep -q 'not valid XML' /root/p.log && ok "malformed advisory: refused" || { cat /root/p.log; fail "wrong error"; }
gpg --batch --verify "$S/repodata/repomd.xml.asc" "$S/repodata/repomd.xml" >/dev/null 2>&1 \
    && fail "a signature was left next to an index it does not cover"
ok "no stale signature left after a failed run"
if $PUB release --rel 45 --arch x86_64 --channel stable >/root/p.log 2>&1; then fail "release accepted an unsigned index"; fi
grep -q 'not signed by a Herd key' /root/p.log && ok "release after a failed promote: refused" \
    || { cat /root/p.log; fail "wrong error"; }
# Hand-edited advisory files with bad fields.
G=/root/adv-good/HERD-2026-0001.xml
bad_file() {  # bad_file <label> <error text> <sed expression>
    rm -rf /root/advisories; mkdir /root/advisories
    sed "$3" "$G" > /root/advisories/HERD-2026-0001.xml
    if $PUB promote --rel 45 --arch x86_64 >/root/p.log 2>&1; then fail "$1: accepted"; fi
    grep -q "$2" /root/p.log && ok "$1: refused" || { cat /root/p.log; fail "$1: wrong error"; }
}
bad_file "<id> not matching the file name" "matching the file name" 's/<id>HERD-2026-0001</<id>HERD-2026-0009</'
bad_file "unknown type" "is not one of" 's/type="security"/type="urgent"/'
bad_file "unknown severity" "is not one of" 's/<severity>Important</<severity>High</'
bad_file "control character in the title" "control characters" 's/<title>herd-fixed/<title>\&#127;herd-fixed/'
bad_file "bad source package name" "incomplete" 's/src="[^"]*"/src="..\/x"/'

say "6. A withdrawn advisory leaves the index"
rm -rf /root/advisories; cp -a /root/adv-good /root/advisories
rm /root/advisories/HERD-2026-0001.xml
$PUB promote --rel 45 --arch x86_64 >/root/p.log 2>&1 || { cat /root/p.log; fail "promote failed"; }
grep -q 'type="updateinfo"' "$S/repodata/repomd.xml" && fail "withdrawn advisory still in the stable index"
ok "stable index has no updateinfo after the advisory is withdrawn"
[ -z "$(find "$S/repodata" -name '*updateinfo*')" ] && ok "no orphan updateinfo file left in repodata" \
    || fail "orphan updateinfo file: $(ls "$S/repodata")"
gpg --batch --verify "$S/repodata/repomd.xml.asc" "$S/repodata/repomd.xml" 2>/dev/null \
    && ok "re-signed index verifies" || fail "bad signature after withdrawal"

say "6b. Advisory for version 2, version 3 available: the newest is installed"
# HERD-2026-0002 names herd-other-2-1; herd-other-1-1 is installed.
rpm -i --nosignature "$R/herd-other-1-1.noarch.rpm"
$PUB add --rel 45 --arch x86_64 --channel testing "$R/herd-other-2-1.noarch.rpm" \
    "$R/herd-other-3-1.noarch.rpm" >/root/p.log 2>&1 \
    && $PUB promote --rel 45 --arch x86_64 >>/root/p.log 2>&1 || { cat /root/p.log; fail "publish herd-other failed"; }
ui | grep -q HERD-2026-0002 && ok "HERD-2026-0002 attached" || fail "HERD-2026-0002 missing"
cp "$HERD_REL_ROOT"/f45/x86_64/stable/*.rpm /root/pkgs/herd-f45-x86_64-stable/
dnf5 -y --repo=herd-t makecache --refresh >/dev/null 2>&1
dnf5 automatic --disablerepo='*' --enablerepo=herd-t </dev/null >/root/auto3.log 2>&1 || true
echo "  MEASURED: after the run, $(rpm -q herd-other)"
rpm -q herd-other-3-1 >/dev/null 2>&1 && ok "advisory for version 2: version 3 installed" \
    || { cat /root/auto3.log; fail "herd-other-3 not installed"; }

say "7. Outside the tests, promote reads only committed advisories"
cp -a /src /root/proj; rm -rf /root/proj/.git /root/proj/advisories
git -C /root/proj init -q; git -C /root/proj add -A
git -C /root/proj -c user.name=t -c user.email=t@example.invalid commit -qm base
NP() { env -u HERD_TEST -u HERD_ADVISORY_DIR -u HERD_PKG_BASEURL /root/proj/publish-repo.sh "$@"; }
NP advisory --id HERD-2026-0010 --type security --severity Low --title "herd-fixed: x" \
    "$R/herd-fixed-2-1.noarch.rpm" >/dev/null
if NP promote --rel 45 --arch x86_64 >/root/p.log 2>&1; then fail "untracked advisory accepted"; fi
grep -q 'uncommitted or ignored' /root/p.log && ok "untracked advisory: refused" || { cat /root/p.log; fail "wrong error"; }
git -C /root/proj add advisories
git -C /root/proj -c user.name=t -c user.email=t@example.invalid commit -qm adv
NP promote --rel 45 --arch x86_64 >/root/p.log 2>&1 || { cat /root/p.log; fail "committed advisory refused"; }
ui | grep -q HERD-2026-0010 && ok "committed advisory: attached" || fail "HERD-2026-0010 missing"
# An edit git does not report (assume-unchanged) is not published: HEAD is read.
git -C /root/proj update-index --assume-unchanged advisories/HERD-2026-0010.xml
sed -i 's/herd-fixed: x/herd-fixed: EDITED/' /root/proj/advisories/HERD-2026-0010.xml
NP promote --rel 45 --arch x86_64 >/root/p.log 2>&1 || { cat /root/p.log; fail "promote failed"; }
ui | grep -q 'herd-fixed: x' && ! ui | grep -q EDITED && ok "hidden edit (assume-unchanged): not published" \
    || fail "an edit hidden from git status was published"
git -C /root/proj update-index --no-assume-unchanged advisories/HERD-2026-0010.xml
git -C /root/proj checkout -q -- advisories
# An advisory file that git ignores stops the run.
echo 'advisories/HERD-2026-0011.xml' >> /root/proj/.git/info/exclude
NP advisory --id HERD-2026-0011 --type security --severity Low --title "herd-fixed: y" \
    "$R/herd-fixed-2-1.noarch.rpm" >/dev/null
if NP promote --rel 45 --arch x86_64 >/root/p.log 2>&1; then fail "ignored advisory accepted"; fi
grep -q 'ignored' /root/p.log && ok "ignored advisory: refused" || { cat /root/p.log; fail "wrong error"; }
rm /root/proj/advisories/HERD-2026-0011.xml
GC() { git -C /root/proj -c user.name=t -c user.email=t@example.invalid "$@"; }
# Export attributes do not hide a committed advisory.
echo 'advisories/* export-ignore' > /root/proj/.gitattributes
GC add .gitattributes; GC commit -qm attrs
NP promote --rel 45 --arch x86_64 >/root/p.log 2>&1 || { cat /root/p.log; fail "promote failed"; }
ui | grep -q HERD-2026-0010 && ok "export-ignore attribute: advisory still attached" \
    || fail "an export-ignore attribute hid a committed advisory"
# A committed symlink under advisories/ stops the run.
ln -s /etc/hostname /root/proj/advisories/HERD-2026-0012.xml
GC add advisories; GC commit -qm link
if NP promote --rel 45 --arch x86_64 >/root/p.log 2>&1; then fail "committed symlink accepted"; fi
grep -q 'other than plain files' /root/p.log && ok "committed symlink: refused" || { cat /root/p.log; fail "wrong error"; }
GC rm -q advisories/HERD-2026-0012.xml; GC commit -qm unlink
# A replace ref does not change what is published.
OID=$(GC rev-parse HEAD:advisories/HERD-2026-0010.xml)
NEW=$(GC show "$OID" | sed 's/herd-fixed: x/herd-fixed: REPLACED/' | GC hash-object -w --stdin)
GC replace "$OID" "$NEW"
NP promote --rel 45 --arch x86_64 >/root/p.log 2>&1 || { cat /root/p.log; fail "promote failed"; }
ui | grep -q 'herd-fixed: x' && ! ui | grep -q REPLACED && ok "replace ref: original advisory published" \
    || fail "a replace ref changed the published advisory"
GC replace -d "$OID" >/dev/null
# A committed .xml file whose name is not an advisory id stops the run.
cp /root/proj/advisories/HERD-2026-0010.xml /root/proj/advisories/notes.xml
GC add advisories; GC commit -qm badname
if NP promote --rel 45 --arch x86_64 >/root/p.log 2>&1; then fail "badly named advisory accepted"; fi
grep -q 'is not HERD-YYYY-NNNN.xml' /root/p.log && ok "badly named advisory file: refused" || { cat /root/p.log; fail "wrong error"; }
GC rm -q advisories/notes.xml; GC commit -qm rmbad
echo '<!-- edit -->' >> /root/proj/advisories/HERD-2026-0010.xml
if NP promote --rel 45 --arch x86_64 >/root/p.log 2>&1; then fail "modified advisory accepted"; fi
grep -q 'uncommitted or ignored' /root/p.log && ok "modified advisory: refused" || { cat /root/p.log; fail "wrong error"; }

say "RESULT: ALL TESTS PASSED"
EOS
