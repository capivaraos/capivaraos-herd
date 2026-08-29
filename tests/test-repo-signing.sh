#!/bin/bash
# =============================================================================
# Teste reprodutível da assinatura do repositório do Herd (PROD-104/PROD-105).
# =============================================================================
# Prova, de ponta a ponta e ISOLADO num contêiner Fedora 44, que:
#   1. o pacote capivaraos-herd-repos constrói a partir do nosso spec;
#   2. a assinatura de PACOTE (rpmsign) valida e adulteração é RECUSADA (rpm -K);
#   3. a assinatura de METADADOS (repomd.xml.asc) valida;
#   4. metadado adulterado é RECUSADO na TRANSAÇÃO de install (dnf, exit != 0).
#
# Usa uma CHAVE DESCARTÁVEL gerada na hora — NUNCA a chave de produção (essa é
# gerada offline por keys/gen-signing-key.sh). Não toca o sistema do host.
#
# Uso (a partir da raiz do repo):  ./tests/test-repo-signing.sh
# Requer: podman. Baixa a imagem fedora:44 e ferramentas de build no contêiner.
#
# NOTA DE COMPORTAMENTO (dnf5 5.4.x, Fedora 44): `dnf makecache` sozinho apenas
# AVISA sobre repomd com assinatura ruim (exit 0); é a TRANSAÇÃO (install/upgrade)
# que aplica o repo_gpgcheck e aborta. Por isso o gate de integridade deve ser a
# operação de update, não o exit do makecache. Este teste valida a transação.
# =============================================================================
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v podman >/dev/null || { echo "ERRO: podman necessário" >&2; exit 1; }

podman run -i --rm \
    -v "${PROJECT_DIR}/rpm":/src/rpm:ro \
    -v "${PROJECT_DIR}/repo":/src/repo:ro \
    --security-opt label=disable \
    registry.fedoraproject.org/fedora:44 bash -s <<'EOS'
set -euo pipefail; export LC_ALL=C
ok() { echo "  [OK] $*"; }
fail() { echo "  [FALHA] $*"; exit 1; }
say() { echo; echo "=== $* ==="; }

say "0. Ferramentas"
dnf install -y --setopt=install_weak_deps=False \
    rpm-build rpm-sign createrepo_c gnupg2 >/dev/null 2>&1 \
    || dnf install -y rpm-build rpm-sign createrepo_c gnupg2 >/dev/null
echo "  $(rpmsign --version | head -1) | $(createrepo_c --version|head -1) | dnf5 $(rpm -q --qf '%{version}' dnf5)"

say "1. Chave DESCARTÁVEL (só para o teste; produção é offline)"
export GNUPGHOME=/root/.gnupg-test; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
printf '%s\n' '%no-protection' 'Key-Type: RSA' 'Key-Length: 3072' 'Key-Usage: sign' \
  'Name-Real: Herd TEST throwaway' 'Name-Email: test@example.invalid' \
  'Expire-Date: 0' '%commit' > /root/kp
gpg --batch --gen-key /root/kp 2>/dev/null
KID=$(gpg --list-keys --with-colons test@example.invalid | awk -F: '/^pub:/{print $5;exit}')
gpg --armor --export "$KID" > /root/pub.asc
ok "chave descartável $KID"

say "2. Constrói capivaraos-herd-repos (pública descartável como Source1)"
mkdir -p ~/rpmbuild/{SOURCES,SPECS}
install -m0644 /src/repo/capivaraos-herd.repo ~/rpmbuild/SOURCES/
install -m0644 /root/pub.asc ~/rpmbuild/SOURCES/RPM-GPG-KEY-capivaraos-herd
cp /src/rpm/capivaraos-herd-repos.spec ~/rpmbuild/SPECS/
rpmbuild -bb ~/rpmbuild/SPECS/capivaraos-herd-repos.spec >/dev/null 2>&1
RPM=$(find ~/rpmbuild/RPMS -name 'capivaraos-herd-repos-*.rpm' | head -1)
[ -f "$RPM" ] && ok "RPM: $(basename "$RPM")" || fail "build não produziu RPM"

say "3. Assina o PACOTE e monta+assina o repo (como o publish-repo.sh)"
printf '%s\n' '%_gpg_name Herd TEST throwaway' '%_gpg_digest_algo sha512' >> ~/.rpmmacros
rpmsign --addsign "$RPM" >/dev/null 2>&1
D=/root/repo/herd/f$(rpm -E %{fedora})/x86_64/stable; mkdir -p "$D"; cp "$RPM" "$D/"
createrepo_c --quiet "$D"
gpg --detach-sign --armor -u "$KID" "$D/repodata/repomd.xml"
[ -f "$D/repodata/repomd.xml.asc" ] && ok "repomd.xml assinado" || fail "repomd não assinado"

say "4. PACOTE íntegro valida; adulterado é RECUSADO (rpm -K)"
rpmkeys --import /root/pub.asc
rpm -K "$D"/*.rpm >/dev/null 2>&1 && ok "pacote íntegro: rpm -K exit 0" || fail "íntegro deveria passar"
BAD=/root/bad.rpm; cp "$D"/*.rpm "$BAD"
SZ=$(stat -c%s "$BAD"); printf 'CORROMPIDO' | dd of="$BAD" bs=1 seek=$((SZ-120)) conv=notrunc status=none
if rpm -K "$BAD" >/dev/null 2>&1; then fail "adulteração de pacote NÃO detectada"; else ok "pacote adulterado: RECUSADO (rpm -K exit != 0)"; fi

say "5. METADADO íntegro: importa a chave no dnf5 e valida"
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
    && ok "repomd íntegro aceito + chave importada no dnf5" || fail "makecache íntegro falhou"
# install íntegro deve funcionar
dnf -y --disablerepo='*' --enablerepo=herd-test install capivaraos-herd-repos >/dev/null 2>&1 \
    && ok "install do pacote assinado: OK (gpgcheck)" || fail "install íntegro falhou"
dnf -y remove capivaraos-herd-repos >/dev/null 2>&1 || true

say "6. METADADO adulterado: TRANSAÇÃO de install deve ABORTAR (repo_gpgcheck)"
echo "<!-- adulterado -->" >> "$D/repodata/repomd.xml"   # invalida repomd.xml.asc
set +e
OUT=$(dnf --refresh -y --disablerepo='*' --enablerepo=herd-test install capivaraos-herd-repos 2>&1)
RC=$?
set -e
echo "$OUT" | grep -iq 'bad pgp signature' && ok "dnf detectou: Bad PGP signature"
if [ "$RC" -ne 0 ] && ! rpm -q capivaraos-herd-repos >/dev/null 2>&1; then
    ok "install ABORTADO (exit $RC) e pacote NÃO instalado — repo_gpgcheck aplicado"
else
    fail "install NÃO foi barrado (exit $RC) — repo_gpgcheck não aplicado!"
fi

say "RESULTADO: TODOS OS TESTES PASSARAM"
echo "  Pipeline (spec + assinatura de pacote + repomd) provado com chave descartável."
echo "  Lembrete: gate de integridade = transação de install/upgrade, não makecache."
EOS
