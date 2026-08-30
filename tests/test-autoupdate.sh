#!/bin/bash
# =============================================================================
# Teste reprodutível da atualização automática do Herd (PROD-106).
# =============================================================================
# Prova, isolado num contêiner Fedora 44, que:
#   1. capivaraos-herd-autoupdate constrói e instala, puxando dnf5-plugin-automatic;
#   2. a política cai em /etc/dnf/automatic.conf (upgrade_type=security,
#      apply_updates=yes, reboot=never) — só se ausente (preserva edição do admin);
#   3. a unidade dnf5-automatic.timer existe (habilitada no kickstart/blueprint);
#   4. `dnf5 automatic --timer` parseia a nossa config e roda sem erro.
#
# Não toca o host. Requer podman. Uso (a partir da raiz do repo):
#   ./tests/test-autoupdate.sh
# =============================================================================
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v podman >/dev/null || { echo "ERRO: podman necessário" >&2; exit 1; }

podman run -i --rm \
    -v "${PROJECT_DIR}/rpm":/src/rpm:ro \
    -v "${PROJECT_DIR}/repo":/src/repo:ro \
    -v "${PROJECT_DIR}/keys":/src/keys:ro \
    -v "${PROJECT_DIR}/autoupdate":/src/autoupdate:ro \
    --security-opt label=disable \
    registry.fedoraproject.org/fedora:44 bash -s <<'EOS'
set -euo pipefail; export LC_ALL=C
ok(){ echo "  [OK] $*"; }; fail(){ echo "  [FALHA] $*"; exit 1; }
dnf install -y --setopt=install_weak_deps=False rpm-build createrepo_c >/dev/null 2>&1
mkdir -p ~/rpmbuild/{SOURCES,SPECS}

echo "== 1. build dos pacotes =="
install -m0644 /src/repo/capivaraos-herd.repo ~/rpmbuild/SOURCES/
install -m0644 /src/keys/RPM-GPG-KEY-capivaraos-herd ~/rpmbuild/SOURCES/
install -m0644 /src/autoupdate/automatic.conf ~/rpmbuild/SOURCES/
cp /src/rpm/capivaraos-herd-repos.spec /src/rpm/capivaraos-herd-autoupdate.spec ~/rpmbuild/SPECS/
rpmbuild -bb ~/rpmbuild/SPECS/capivaraos-herd-repos.spec >/dev/null 2>&1
rpmbuild -bb ~/rpmbuild/SPECS/capivaraos-herd-autoupdate.spec >/dev/null 2>&1
REPOS=$(find ~/rpmbuild/RPMS -name 'capivaraos-herd-repos-*.rpm'|head -1)
AUTO=$(find ~/rpmbuild/RPMS -name 'capivaraos-herd-autoupdate-*.rpm'|head -1)
[ -f "$AUTO" ] && ok "autoupdate construído" || fail "não construiu autoupdate"

echo "== 2. install puxa dnf5-plugin-automatic =="
dnf install -y "$REPOS" "$AUTO" >/tmp/i.log 2>&1 || { tail -15 /tmp/i.log; fail "install falhou"; }
rpm -q dnf5-plugin-automatic >/dev/null 2>&1 && ok "dnf5-plugin-automatic instalado" || fail "dep não veio"

echo "== 3. política em /etc/dnf/automatic.conf =="
[ -f /etc/dnf/automatic.conf ] || fail "config ausente"
for kv in 'upgrade_type = security' 'apply_updates = yes' 'reboot = never'; do
  grep -qF "$kv" /etc/dnf/automatic.conf && ok "contém: $kv" || fail "faltou: $kv"
done

echo "== 4. timer presente =="
[ -f /usr/lib/systemd/system/dnf5-automatic.timer ] && ok "dnf5-automatic.timer existe" || fail "timer ausente"

echo "== 5. dnf5 automatic parseia a config e roda =="
sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/capivaraos-herd.repo   # repo remoto não existe no teste
sed -i 's/^apply_updates = yes/apply_updates = no/' /etc/dnf/automatic.conf  # smoke: não aplicar de verdade
rm -f /etc/motd.d/dnf5-automatic
dnf5 automatic --timer >/tmp/a.log 2>&1 && ok "dnf5 automatic --timer exit 0" || { tail -8 /tmp/a.log; fail "run falhou"; }

echo; echo "== RESULTADO: PROD-106 OK (build + dep + política + timer + parse) =="
EOS
