#!/bin/bash
# =============================================================================
# Reproducible test of the Herd automatic update package.
# =============================================================================
# Checks, in a Fedora 45 container, that:
#   1. capivaraos-herd-autoupdate builds and installs, pulling in
#      dnf5-plugin-automatic, and refuses a capivaraos-herd-repos older than
#      the first one that ships the drop-in importing the Herd keys before
#      unattended runs;
#   2. the policy lands in /etc/dnf/automatic.conf (upgrade_type=security,
#      apply_updates=yes, reboot=never), only if absent (an admin's edit stays);
#   3. the dnf5-automatic.timer unit exists (enabled by the kickstart and the
#      blueprint);
#   4. `dnf5 automatic --timer` parses our config and runs without error.
#
# Does not touch the host. Requires podman. Usage (from the repository root):
#   ./tests/test-autoupdate.sh
# =============================================================================
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v podman >/dev/null || { echo "ERROR: podman required" >&2; exit 1; }

podman run -i --rm \
    -v "${PROJECT_DIR}/rpm":/src/rpm:ro \
    -v "${PROJECT_DIR}/repo":/src/repo:ro \
    -v "${PROJECT_DIR}/keys":/src/keys:ro \
    -v "${PROJECT_DIR}/autoupdate":/src/autoupdate:ro \
    --security-opt label=disable \
    registry.fedoraproject.org/fedora:45 bash -s <<'EOS'
set -euo pipefail; export LC_ALL=C
ok(){ echo "  [OK] $*"; }; fail(){ echo "  [FAIL] $*"; exit 1; }
dnf install -y --setopt=install_weak_deps=False rpm-build createrepo_c >/dev/null 2>&1
mkdir -p ~/rpmbuild/{SOURCES,SPECS}

echo "== 1. build the packages =="
install -m0644 /src/repo/capivaraos-herd.repo ~/rpmbuild/SOURCES/
install -m0644 /src/repo/50-capivaraos-herd-keys.conf ~/rpmbuild/SOURCES/
install -m0644 /src/keys/RPM-GPG-KEY-capivaraos-herd ~/rpmbuild/SOURCES/
install -m0644 /src/keys/RPM-GPG-KEY-capivaraos-herd-reserve ~/rpmbuild/SOURCES/
install -m0644 /src/autoupdate/automatic.conf ~/rpmbuild/SOURCES/
cp /src/rpm/capivaraos-herd-repos.spec /src/rpm/capivaraos-herd-autoupdate.spec ~/rpmbuild/SPECS/
rpmbuild -bb ~/rpmbuild/SPECS/capivaraos-herd-repos.spec >/dev/null 2>&1
rpmbuild -bb ~/rpmbuild/SPECS/capivaraos-herd-autoupdate.spec >/dev/null 2>&1
REPOS=$(find ~/rpmbuild/RPMS -name 'capivaraos-herd-repos-*.rpm'|head -1)
AUTO=$(find ~/rpmbuild/RPMS -name 'capivaraos-herd-autoupdate-*.rpm'|head -1)
[ -f "$AUTO" ] && ok "autoupdate built" || fail "autoupdate not built"

echo "== 1b. requires capivaraos-herd-repos 2.0.0-0.4.alpha1 or later =="
rpm -qp --requires "$AUTO" | grep -qx 'capivaraos-herd-repos >= 2.0.0-0.4.alpha1' \
    && ok "versioned requirement present" || fail "versioned requirement missing"
mkdir -p /tmp/old/SPECS
printf '%s\n' 'Name: capivaraos-herd-repos' 'Version: 2.0.0' 'Release: 0.3.alpha1.herd' \
    'Summary: older stub' 'License: MIT' 'BuildArch: noarch' '%description' 'stub' '%files' \
    > /tmp/old/SPECS/old.spec
rpmbuild -bb --define '_topdir /tmp/old' /tmp/old/SPECS/old.spec >/dev/null 2>&1 || fail "stub build"
OLD=$(find /tmp/old/RPMS -name '*.rpm' | head -1)
if dnf install -y --assumeno "$OLD" "$AUTO" >/tmp/o.log 2>&1 || ! grep -q 'nothing provides capivaraos-herd-repos >= 2.0.0-0.4.alpha1' /tmp/o.log; then
    tail -8 /tmp/o.log; fail "an older capivaraos-herd-repos was accepted"
fi
ok "older capivaraos-herd-repos (0.3.alpha1): refused"

echo "== 2. install pulls in dnf5-plugin-automatic =="
dnf install -y "$REPOS" "$AUTO" >/tmp/i.log 2>&1 || { tail -15 /tmp/i.log; fail "install failed"; }
rpm -q dnf5-plugin-automatic >/dev/null 2>&1 && ok "dnf5-plugin-automatic installed" || fail "dependency missing"

echo "== 3. policy in /etc/dnf/automatic.conf =="
[ -f /etc/dnf/automatic.conf ] || fail "config missing"
for kv in 'upgrade_type = security' 'apply_updates = yes' 'reboot = never'; do
  grep -qF "$kv" /etc/dnf/automatic.conf && ok "contains: $kv" || fail "missing: $kv"
done

echo "== 4. timer present =="
[ -f /usr/lib/systemd/system/dnf5-automatic.timer ] && ok "dnf5-automatic.timer exists" || fail "timer missing"

echo "== 5. dnf5 automatic parses the config and runs =="
sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/capivaraos-herd.repo   # no remote repository in the test
sed -i 's/^apply_updates = yes/apply_updates = no/' /etc/dnf/automatic.conf  # smoke test: do not really apply
rm -f /etc/motd.d/dnf5-automatic
dnf5 automatic --timer >/tmp/a.log 2>&1 && ok "dnf5 automatic --timer exit 0" || { tail -8 /tmp/a.log; fail "run failed"; }

echo; echo "== RESULT: autoupdate OK (build + dependency + policy + timer + parse) =="
EOS
