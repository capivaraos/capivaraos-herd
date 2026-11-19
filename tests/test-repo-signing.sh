#!/bin/bash
# =============================================================================
# Reproducible test of the Herd repository signing.
# =============================================================================
# Checks, end to end in a Fedora 45 container, that:
#   1. capivaraos-herd-repos builds from our spec;
#   2. the PACKAGE signature (rpmsign) verifies and tampering is REFUSED (rpm -K);
#   3. the METADATA signature (repomd.xml.asc) verifies;
#   4. tampered metadata is REFUSED in the install TRANSACTION (dnf, exit != 0);
#   5. the reserve key and the dnf5-automatic drop-in let dnf5 automatic apply
#      a reserve-signed update with no prompt;
#   6. the kickstart passes ksvalidator.
#
# Uses THROWAWAY keys generated on the spot, never the production keys. Does
# not touch the host.
#
# Usage (from the repository root):  ./tests/test-repo-signing.sh
# Requires: podman. Downloads the fedora:45 image and build tools in the container.
#
# BEHAVIOUR NOTE (dnf5 5.4.x, Fedora 45): `dnf makecache` alone only WARNS
# about a repomd with a bad signature (exit 0); the TRANSACTION (install or
# upgrade) applies repo_gpgcheck and stops. So the integrity gate is the update
# operation, not the makecache exit code. This test checks the transaction.
# =============================================================================
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v podman >/dev/null || { echo "ERROR: podman required" >&2; exit 1; }

podman run -i --rm \
    -v "${PROJECT_DIR}/rpm":/src/rpm:ro \
    -v "${PROJECT_DIR}/repo":/src/repo:ro \
    -v "${PROJECT_DIR}/kickstart":/src/kickstart:ro \
    --security-opt label=disable \
    registry.fedoraproject.org/fedora:45 bash -s <<'EOS'
set -euo pipefail; export LC_ALL=C
ok() { echo "  [OK] $*"; }
fail() { echo "  [FAIL] $*"; exit 1; }
say() { echo; echo "=== $* ==="; }

say "0. Tools"
dnf install -y --setopt=install_weak_deps=False \
    rpm-build rpm-sign createrepo_c gnupg2 dnf5-plugin-automatic systemd pykickstart >/dev/null 2>&1 \
    || dnf install -y rpm-build rpm-sign createrepo_c gnupg2 dnf5-plugin-automatic systemd pykickstart >/dev/null
echo "  $(rpmsign --version | head -1) | $(createrepo_c --version|head -1) | dnf5 $(rpm -q --qf '%{version}' dnf5)"

say "1. THROWAWAY keys (for this test only)"
export GNUPGHOME=/root/.gnupg-test; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
printf '%s\n' '%no-protection' 'Key-Type: RSA' 'Key-Length: 3072' 'Key-Usage: sign' \
  'Name-Real: Herd TEST throwaway' 'Name-Email: test@example.invalid' \
  'Expire-Date: 0' '%commit' > /root/kp
gpg --batch --gen-key /root/kp 2>/dev/null
KID=$(gpg --list-keys --with-colons test@example.invalid | awk -F: '/^pub:/{print $5;exit}')
gpg --armor --export "$KID" > /root/pub.asc
ok "throwaway key $KID"
# Throwaway reserve key, standing in for the real reserve key.
printf '%s\n' '%no-protection' 'Key-Type: RSA' 'Key-Length: 3072' 'Key-Usage: sign' \
  'Name-Real: Herd TEST reserve' 'Name-Email: reserve@example.invalid' \
  'Expire-Date: 0' '%commit' > /root/kr
gpg --batch --gen-key /root/kr 2>/dev/null
RKID=$(gpg --list-keys --with-colons reserve@example.invalid | awk -F: '/^pub:/{print $5;exit}')
RFPR=$(gpg --list-keys --with-colons reserve@example.invalid | awk -F: '/^fpr:/{print $10;exit}')
gpg --armor --export "$RKID" > /root/reserve.asc
ok "throwaway reserve key $RKID"

say "2. Build capivaraos-herd-repos (throwaway public keys as Source1 and Source2)"
mkdir -p ~/rpmbuild/{SOURCES,SPECS}
install -m0644 /src/repo/capivaraos-herd.repo ~/rpmbuild/SOURCES/
install -m0644 /root/pub.asc ~/rpmbuild/SOURCES/RPM-GPG-KEY-capivaraos-herd
install -m0644 /root/reserve.asc ~/rpmbuild/SOURCES/RPM-GPG-KEY-capivaraos-herd-reserve
install -m0644 /src/repo/50-capivaraos-herd-keys.conf ~/rpmbuild/SOURCES/
cp /src/rpm/capivaraos-herd-repos.spec ~/rpmbuild/SPECS/
rpmbuild -bb ~/rpmbuild/SPECS/capivaraos-herd-repos.spec >/dev/null 2>&1
RPM=$(find ~/rpmbuild/RPMS -name 'capivaraos-herd-repos-*.rpm' | head -1)
[ -f "$RPM" ] && ok "RPM: $(basename "$RPM")" || fail "build produced no RPM"

say "3. Sign the PACKAGE, then build and sign the repository (as publish-repo.sh does)"
printf '%s\n' '%_gpg_name Herd TEST throwaway' '%_gpg_digest_algo sha512' >> ~/.rpmmacros
rpmsign --addsign "$RPM" >/dev/null 2>&1
D=/root/repo/herd/f$(rpm -E %{fedora})/x86_64/stable; mkdir -p "$D"; cp "$RPM" "$D/"
createrepo_c --quiet "$D"
gpg --detach-sign --armor -u "$KID" "$D/repodata/repomd.xml"
[ -f "$D/repodata/repomd.xml.asc" ] && ok "repomd.xml signed" || fail "repomd not signed"

say "4. Intact PACKAGE verifies; tampered one is REFUSED (rpm -K)"
rpmkeys --import /root/pub.asc
rpm -K "$D"/*.rpm >/dev/null 2>&1 && ok "intact package: rpm -K exit 0" || fail "intact package should pass"
BAD=/root/bad.rpm; cp "$D"/*.rpm "$BAD"
SZ=$(stat -c%s "$BAD"); printf 'CORRUPTED' | dd of="$BAD" bs=1 seek=$((SZ-120)) conv=notrunc status=none
if rpm -K "$BAD" >/dev/null 2>&1; then fail "package tampering NOT detected"; else ok "tampered package: REFUSED (rpm -K exit != 0)"; fi

say "5. Intact METADATA: dnf5 imports the key and verifies"
cat > /etc/yum.repos.d/herd-test.repo <<EOF
[herd-test]
name=Herd TEST
baseurl=file://$D
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///root/pub.asc
EOF
dnf -y --disablerepo='*' --enablerepo=herd-test makecache >/dev/null 2>&1 \
    && ok "intact repomd accepted, key imported by dnf5" || fail "makecache of intact repository failed"
# an intact install must work
dnf -y --disablerepo='*' --enablerepo=herd-test install capivaraos-herd-repos >/dev/null 2>&1 \
    && ok "install of the signed package: OK (gpgcheck)" || fail "intact install failed"
dnf -y remove capivaraos-herd-repos >/dev/null 2>&1 || true

say "6. Tampered METADATA: the install TRANSACTION must STOP (repo_gpgcheck)"
echo "<!-- tampered -->" >> "$D/repodata/repomd.xml"   # invalidates repomd.xml.asc
set +e
OUT=$(dnf --refresh -y --disablerepo='*' --enablerepo=herd-test install capivaraos-herd-repos 2>&1)
RC=$?
set -e
echo "$OUT" | grep -iq 'bad pgp signature' && ok "dnf detected: Bad PGP signature"
if [ "$RC" -ne 0 ] && ! rpm -q capivaraos-herd-repos >/dev/null 2>&1; then
    ok "install STOPPED (exit $RC), package NOT installed: repo_gpgcheck applied"
else
    fail "install NOT stopped (exit $RC): repo_gpgcheck not applied"
fi

say "7. Reserve key and unattended updates (dnf5-automatic drop-in)"
DROPIN=/usr/lib/systemd/system/dnf5-automatic.service.d/50-capivaraos-herd-keys.conf
WANT1='/usr/bin/rpmkeys --import /etc/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd /etc/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd-reserve'
WANT2='-/usr/bin/dnf5 -y --repo=capivaraos-herd --repo=capivaraos-herd-testing makecache'
# rpm 6 names a trusted key by its full fingerprint, rpm 4 by its short key ID.
rkid_lc=$(echo "$RKID" | tr 'A-F' 'a-f' | tail -c 9)
rfpr_lc=$(echo "$RFPR" | tr 'A-F' 'a-f')
trusted() { rpm -q gpg-pubkey --qf '%{VERSION}\n' | grep -qxE "${rfpr_lc}|${rkid_lc}"; }
[ -z "$(rpm -qp --scripts "$RPM" 2>/dev/null)" ] && ok "repos package has no scriptlets" \
    || fail "repos package has a scriptlet"
if trusted; then
    fail "reserve key already trusted before install; test would prove nothing"
fi
rpm -i "$RPM" >/dev/null 2>&1 || fail "rpm -i of capivaraos-herd-repos failed"
grep -q 'RPM-GPG-KEY-capivaraos-herd-reserve' /etc/yum.repos.d/capivaraos-herd.repo \
    && ok ".repo lists the reserve key in gpgkey" || fail ".repo does not list the reserve key"
[ -f "$DROPIN" ] && ok "drop-in installed" || fail "drop-in not installed at $DROPIN"
PRE=$(sed -n 's/^ExecStartPre=//p' "$DROPIN")
[ "$PRE" = "$(printf '%s\n%s' "$WANT1" "$WANT2")" ] \
    && ok "drop-in: fixed key paths, Herd repositories only, no glob; '-' only on makecache" \
    || fail "unexpected ExecStartPre lines: $PRE"
for id in capivaraos-herd capivaraos-herd-testing; do
    dnf5 -q repo list --all 2>/dev/null | awk '{print $1}' | grep -qx "$id" \
        && ok "the drop-in's repository $id exists in the shipped .repo" \
        || fail "repository $id named in the drop-in is not defined"
done
if OUT=$(systemd-analyze verify dnf5-automatic.service 2>&1); then
    ok "systemd-analyze verify accepts dnf5-automatic.service with the drop-in"
else
    echo "$OUT"; fail "systemd-analyze verify failed"
fi

# An update signed ONLY by the reserve key, in a repository signed by it.
mkdir -p /root/dummy /root/r7
for v in 1 2; do
    printf '%s\n' 'Name: herd-dummy' "Version: $v" 'Release: 1' 'Summary: d' \
        'License: MIT' 'BuildArch: noarch' '%description' 'd' '%files' > /root/dummy/d$v.spec
    rpmbuild -bb /root/dummy/d$v.spec >/dev/null 2>&1 || fail "dummy v$v build failed"
done
V1=$(find ~/rpmbuild/RPMS -name 'herd-dummy-1-*.rpm'); V2=$(find ~/rpmbuild/RPMS -name 'herd-dummy-2-*.rpm')
rpm -i --nosignature "$V1" >/dev/null 2>&1 || fail "could not install herd-dummy-1"
rpmsign --addsign --define '_gpg_name Herd TEST reserve' "$V2" >/dev/null 2>&1
rpm -qp --qf '%{RSAHEADER:pgpsig}\n' "$V2" 2>/dev/null | grep -qi "$rkid_lc" \
    || fail "herd-dummy-2 is not signed by the reserve key"
cp "$V2" /root/r7/; createrepo_c --quiet /root/r7
gpg --detach-sign --armor -u "$RKID" /root/r7/repodata/repomd.xml
cat > /etc/yum.repos.d/herd-r7.repo <<EOF
[herd-r7]
name=Herd TEST reserve-signed
baseurl=file:///root/r7
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd file:///etc/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd-reserve
EOF
mkdir -p /etc/dnf
printf '%s\n' '[commands]' 'upgrade_type = default' 'download_updates = yes' \
    'apply_updates = yes' 'reboot = never' > /etc/dnf/automatic.conf
auto() { dnf5 automatic --disablerepo='*' --enablerepo=herd-r7 </dev/null >/root/auto.log 2>&1 || true; }

auto
if rpm -q herd-dummy-2 >/dev/null 2>&1; then
    fail "update applied without the drop-in command; test would prove nothing"
fi
ok "without the drop-in command: dnf5 automatic does not apply the update"

# Run the drop-in commands, with the test repository standing in for the
# Herd ones (the real Herd repositories are not reachable from here).
read -ra PRE1 <<<"$WANT1"
"${PRE1[@]}" || fail "rpmkeys command failed"
trusted && ok "rpmkeys command made rpm trust the reserve key" || fail "reserve key still not trusted"
"${PRE1[@]}" && ok "rpmkeys command is idempotent (second run exit 0)" || fail "second run failed"
auto
if rpm -q herd-dummy-2 >/dev/null 2>&1; then
    fail "update applied with rpm trust only; repository key step would be untested"
fi
ok "rpm trust alone is not enough: dnf5 keeps repository keys separately"
W2="${WANT2#-}"
read -ra PRE2 <<<"${W2//--repo=capivaraos-herd --repo=capivaraos-herd-testing/--repo=herd-r7}"
"${PRE2[@]}" </dev/null >/dev/null 2>&1 || fail "makecache command failed"
ok "makecache imported the repository keys from gpgkey="
auto
if rpm -q herd-dummy-2 >/dev/null 2>&1; then
    ok "with the drop-in command: dnf5 automatic applied the reserve-signed update, no prompt"
else
    cat /root/auto.log; fail "dnf5 automatic did not apply the reserve-signed update"
fi

say "8. Kickstart passes ksvalidator"
if OUT=$(ksvalidator /src/kickstart/capivaraos-herd.ks 2>&1); then
    ok "ksvalidator: kickstart OK"
else
    echo "$OUT"; fail "ksvalidator rejected the kickstart"
fi

say "RESULT: ALL TESTS PASSED"
echo "  Spec, package signature, repomd signature and reserve-key trust checked with throwaway keys, in a container."
echo "  Reminder: the integrity gate is the install/upgrade transaction, not makecache."
EOS
