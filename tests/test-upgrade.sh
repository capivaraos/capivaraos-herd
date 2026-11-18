#!/bin/bash
# =============================================================================
# Reproducible test of the Herd in-place version upgrade tool.
# =============================================================================
# Checks the LOGIC of herd-upgrade in a Fedora 45 container:
#   1. capivaraos-herd-upgrade builds and installs /usr/bin/herd-upgrade
#      (pulling in capivaraos-herd-repos);
#   2. --help exits 0; an invalid option and a target <= current exit != 0;
#   3. FAILS CLOSED: `check` refuses (exit 1) when the signed Herd repository
#      does not exist for the target release, the central safety behaviour;
#   4. RELEASES: with a local file:// repository holding capivaraos-herd-repos
#      for the target release, `check` passes the pre-flight (exit 0);
#   5. `download` with a failed pre-flight stops before touching dnf.
#
# Signature checks (gpgcheck/repo_gpgcheck) are covered by
# test-repo-signing.sh; the local repository here is unsigned on purpose, to
# isolate the tool's gate and version logic. Does not touch the host.
#
# Requires podman. Usage (from the repository root):
#   ./tests/test-upgrade.sh
# =============================================================================
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v podman >/dev/null || { echo "ERROR: podman required" >&2; exit 1; }

podman run -i --rm \
    -v "${PROJECT_DIR}/rpm":/src/rpm:ro \
    -v "${PROJECT_DIR}/repo":/src/repo:ro \
    -v "${PROJECT_DIR}/keys":/src/keys:ro \
    -v "${PROJECT_DIR}/upgrade":/src/upgrade:ro \
    --security-opt label=disable \
    registry.fedoraproject.org/fedora:45 bash -s <<'EOS'
set -euo pipefail; export LC_ALL=C
ok(){ echo "  [OK] $*"; }; fail(){ echo "  [FAIL] $*"; exit 1; }
# runs a command that is EXPECTED to fail; ok if exit != 0
expect_fail(){ if "$@" >/tmp/ef.log 2>&1; then fail "expected failure, but it passed: $*"; fi; }

dnf install -y --setopt=install_weak_deps=False rpm-build createrepo_c >/dev/null 2>&1
mkdir -p ~/rpmbuild/{SOURCES,SPECS}
CUR="$(rpm -E %fedora)"; TGT=$((CUR + 1))

echo "== 1. build and install capivaraos-herd-upgrade =="
install -m0644 /src/repo/capivaraos-herd.repo ~/rpmbuild/SOURCES/
install -m0644 /src/repo/50-capivaraos-herd-keys.conf ~/rpmbuild/SOURCES/
install -m0644 /src/keys/RPM-GPG-KEY-capivaraos-herd ~/rpmbuild/SOURCES/
install -m0644 /src/keys/RPM-GPG-KEY-capivaraos-herd-reserve ~/rpmbuild/SOURCES/
install -m0755 /src/upgrade/bin/herd-upgrade ~/rpmbuild/SOURCES/
cp /src/rpm/capivaraos-herd-repos.spec /src/rpm/capivaraos-herd-upgrade.spec ~/rpmbuild/SPECS/
rpmbuild -bb ~/rpmbuild/SPECS/capivaraos-herd-repos.spec   >/dev/null 2>&1
rpmbuild -bb ~/rpmbuild/SPECS/capivaraos-herd-upgrade.spec >/dev/null 2>&1
REPOS=$(find ~/rpmbuild/RPMS -name 'capivaraos-herd-repos-*.rpm'|head -1)
UPG=$(find ~/rpmbuild/RPMS -name 'capivaraos-herd-upgrade-*.rpm'|head -1)
[ -f "$UPG" ] || fail "capivaraos-herd-upgrade not built"
dnf install -y "$REPOS" "$UPG" >/tmp/i.log 2>&1 || { tail -15 /tmp/i.log; fail "install failed"; }
[ -x /usr/bin/herd-upgrade ] && ok "/usr/bin/herd-upgrade installed and executable" || fail "binary missing"
rpm -q --requires capivaraos-herd-upgrade | grep -q '^dnf5' && ok "Requires dnf5" || fail "Requires dnf5 missing"

echo "== 2. argument guards =="
herd-upgrade --help >/tmp/h.log 2>&1 && grep -q 'in-place' /tmp/h.log && ok "--help exits 0" || fail "--help"
expect_fail herd-upgrade --invalid-option;             ok "invalid option refused"
expect_fail herd-upgrade --to "$CUR";                  ok "target == current refused"
expect_fail herd-upgrade --to abc;                     ok "non-numeric target refused"

echo "== 3. FAILS CLOSED: no Herd repository for f$TGT, check refuses =="
# A file:// baseurl that does not exist: the gate fails deterministically (no network or DNS).
cat >/etc/yum.repos.d/capivaraos-herd.repo <<'REPO'
[capivaraos-herd]
name=CapivaraOS Herd test (missing) $releasever
baseurl=file:///srv/repo-missing/herd/f$releasever/$basearch/stable/
enabled=1
gpgcheck=0
repo_gpgcheck=0
REPO
if herd-upgrade check --to "$TGT" >/tmp/c1.log 2>&1; then
  cat /tmp/c1.log; fail "check should have refused (repository missing)"
fi
# herd-upgrade reports in Portuguese: AUSENTE = missing.
grep -qi 'AUSENTE' /tmp/c1.log && ok "check fails the pre-flight (no Herd repository for f$TGT)" \
  || { cat /tmp/c1.log; fail "expected a missing-repository report"; }

echo "== 4. RELEASES: local file:// repository with capivaraos-herd-repos for f$TGT =="
ARCH="$(rpm -E %{_arch})"
REPO_ROOT="/srv/repo/herd/f${TGT}/${ARCH}/stable"
mkdir -p "$REPO_ROOT"; cp "$REPOS" "$REPO_ROOT/"
createrepo_c "$REPO_ROOT" >/dev/null 2>&1
# Test .repo (no gpg; signatures are covered by test-repo-signing.sh), with a
# baseurl whose $releasever/$basearch resolve to the local repository.
cat >/etc/yum.repos.d/capivaraos-herd.repo <<REPO
[capivaraos-herd]
name=CapivaraOS Herd test \$releasever
baseurl=file:///srv/repo/herd/f\$releasever/\$basearch/stable/
enabled=1
gpgcheck=0
repo_gpgcheck=0
REPO
if herd-upgrade check --to "$TGT" >/tmp/c2.log 2>&1; then
  grep -qi 'Pronto para upgrade' /tmp/c2.log && ok "check passes with the repository present for f$TGT" \
    || { cat /tmp/c2.log; fail "passed, but without the expected message"; }
else
  cat /tmp/c2.log; fail "check should pass (repository present)"
fi

echo "== 5. download stops when the pre-flight fails (dnf untouched) =="
# Point the repository at a missing path (enabled=0 would not do: --repo forces
# it on). The pre-flight then fails and download must stop BEFORE touching dnf.
cat >/etc/yum.repos.d/capivaraos-herd.repo <<'REPO'
[capivaraos-herd]
name=CapivaraOS Herd test (missing) $releasever
baseurl=file:///srv/repo-missing/herd/f$releasever/$basearch/stable/
enabled=1
gpgcheck=0
repo_gpgcheck=0
REPO
expect_fail herd-upgrade download --to "$TGT" --yes
grep -qi 'pré-voo reprovado\|Upgrade abortado' /tmp/ef.log && ok "download stopped at the pre-flight (nothing downloaded)" \
  || { cat /tmp/ef.log; fail "expected a stop at the pre-flight"; }

echo; echo "== RESULT: upgrade OK (build+install, guards, fail-closed, release, safe stop) =="
EOS
