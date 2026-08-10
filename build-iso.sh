#!/bin/bash
# =============================================================================
# Build da ISO instaladora BRANDEADA e OFFLINE do CapivaraOS HERD (PROD-66).
# =============================================================================
# Diferente do build.sh (osbuild → qcow2 + image-installer, cujo instalador tem
# marca Fedora fixa), esta ISO é construída com lorax + mkksiso para remover a
# marca Fedora do INSTALADOR (menu de boot + telas do Anaconda):
#
#   1. lorax  → instalador brandeado (nome de produto "CapivaraOS HERD" e a arte
#      do pacote capivaraos-herd-logos no lugar do fedora-logos).
#   2. dnf    → baixa @core + o conjunto de pacotes do HERD (+ deps) num repo
#      local (torna a instalação OFFLINE).
#   3. mkksiso → injeta o kickstart de servidor e o repo na boot.iso do lorax,
#      apontando o Anaconda para o repo embutido (inst.repo=hd:LABEL=...:/repo).
#
# PRÉ-REQUISITOS (precisa root — lorax/dnf):
#   sudo dnf install -y lorax createrepo_c
#   O RPM de branding (capivaraos-herd-branding) E o de logos
#   (capivaraos-herd-logos) já construídos e servidos no repo local:
#       ./rpm/build-rpm.sh && ./rpm/build-rpm-logos.sh
#       mkdir -p /var/tmp/capivaraos-herd-repo
#       cp ~/rpmbuild/RPMS/noarch/capivaraos-herd-branding-*.rpm \
#          ~/rpmbuild/RPMS/noarch/capivaraos-herd-logos-*.rpm \
#          /var/tmp/capivaraos-herd-repo/
#       createrepo_c /var/tmp/capivaraos-herd-repo
#
# Uso:  sudo ./build-iso.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINT_TOML="$SCRIPT_DIR/blueprints/capivaraos-herd.toml"
VERSION="$(awk -F'"' '/^version[[:space:]]*=/{print $2; exit}' "$BLUEPRINT_TOML")"
ARCH="$(uname -m)"
RELEASEVER=44                       # HERD 1.x = Fedora 44 (ver build.sh)
PRODUCT="CapivaraOS HERD"
VARIANT="Server"
VOLID="CapivaraOS-HERD-${VERSION}"  # <= 32 chars (ISO9660); casa com inst.repo
KS="$SCRIPT_DIR/kickstart/capivaraos-herd.ks"
BRANDING_REPO="/var/tmp/capivaraos-herd-repo"
OUT="$SCRIPT_DIR/out"
WORK="/var/tmp/herd-iso"
ISO_OUT="$OUT/CapivaraOS-HERD-${VERSION}-${ARCH}.installer.iso"

# Conjunto de pacotes do payload (ESPELHA o %packages do kickstart). Mantê-los
# em sincronia: este é o que baixamos pro repo offline; o kickstart é o que o
# Anaconda instala a partir dele.
PAYLOAD_PKGS=(
    kernel capivaraos-herd-branding cloud-init qemu-guest-agent openssh-server
    firewalld chrony cockpit glibc-langpack-pt glibc-langpack-en
)

echo "==> CapivaraOS HERD installer ISO ${VERSION} (${ARCH})"

# ── Sanidade ─────────────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || { echo "ERRO: rode com sudo (lorax/dnf precisam de root)." >&2; exit 1; }
OSVER="$(. /etc/os-release && echo "${VERSION_ID:-?}")"
[ "$OSVER" = "$RELEASEVER" ] || echo "AVISO: host é Fedora ${OSVER}, não ${RELEASEVER}." >&2
for t in lorax mkksiso createrepo_c dnf; do
    command -v "$t" >/dev/null || { echo "ERRO: '$t' não encontrado (dnf install lorax createrepo_c)." >&2; exit 1; }
done
for rpm in capivaraos-herd-branding capivaraos-herd-logos; do
    ls "$BRANDING_REPO/${rpm}"-*.rpm >/dev/null 2>&1 || {
        echo "ERRO: ${rpm} não está em ${BRANDING_REPO}. Rode os build-rpm e o createrepo_c (ver cabeçalho)." >&2
        exit 1
    }
done

rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"

# ── 1. Instalador brandeado (lorax) ──────────────────────────────────────────
# -i capivaraos-herd-logos: o lorax instala "fedora-logos" por nome (derivado do
#    release); como o nosso pacote Provides+Obsoletes fedora-logos, o dnf instala
#    o nosso no lugar, trazendo a nossa arte para o Anaconda. NÃO usar -e
#    fedora-logos (o removepkg do lorax quebra em pacote não instalado).
#    -p/-v/-t: nome de produto no menu e no .buildstamp.
# NB: lorax exige que o diretório de saída NÃO exista.
echo "==> 1/3: lorax (instalador brandeado)..."
# Repos como arquivos .repo: EXCLUÍMOS o fedora-logos real dos repos Fedora, para
# o nosso capivaraos-herd-logos (Provides fedora-logos) ser o ÚNICO provedor
# quando o lorax fizer "installpkg fedora-logos" (nome derivado do release).
REPODIR="$WORK/repos.d"
mkdir -p "$REPODIR"
cat > "$REPODIR/fedora.repo" <<EOF
[fedora]
name=Fedora ${RELEASEVER} - ${ARCH}
baseurl=https://download.fedoraproject.org/pub/fedora/linux/releases/${RELEASEVER}/Everything/${ARCH}/os/
enabled=1
gpgcheck=0
exclude=fedora-logos
EOF
cat > "$REPODIR/updates.repo" <<EOF
[updates]
name=Fedora ${RELEASEVER} - ${ARCH} - Updates
baseurl=https://download.fedoraproject.org/pub/fedora/linux/updates/${RELEASEVER}/Everything/${ARCH}/
enabled=1
gpgcheck=0
exclude=fedora-logos
EOF
cat > "$REPODIR/herd-local.repo" <<EOF
[herd-local]
name=CapivaraOS HERD local
baseurl=file://${BRANDING_REPO}
enabled=1
gpgcheck=0
EOF

lorax -p "$PRODUCT" -v "$VERSION" -r "$VERSION" -t "$VARIANT" \
    --volid "$VOLID" \
    --isfinal \
    -i capivaraos-herd-logos \
    --repo "$REPODIR/fedora.repo" \
    --repo "$REPODIR/updates.repo" \
    --repo "$REPODIR/herd-local.repo" \
    "$WORK/lorax"

BOOT_ISO="$WORK/lorax/images/boot.iso"
[ -f "$BOOT_ISO" ] || { echo "ERRO: lorax não gerou ${BOOT_ISO}." >&2; exit 1; }

# ── 2. Repo offline (payload) ────────────────────────────────────────────────
# --installroot vazio força o dnf a baixar TUDO para uma instalação limpa (não
# só o que falta no host). Sem weak deps para um servidor enxuto.
echo "==> 2/3: baixando pacotes do payload para repo offline..."
mkdir -p "$WORK/repo"
dnf -y --releasever="$RELEASEVER" \
    --installroot="$WORK/instroot" \
    --repofrompath="herd-local,file://${BRANDING_REPO}" \
    --setopt=herd-local.gpgcheck=0 \
    --setopt=install_weak_deps=False \
    install --downloadonly --downloaddir="$WORK/repo" \
    @core "${PAYLOAD_PKGS[@]}"
createrepo_c "$WORK/repo" >/dev/null
echo "    $(ls "$WORK/repo"/*.rpm | wc -l) RPMs no repo offline."

# ── 3. Injeta kickstart + repo na ISO (mkksiso) ──────────────────────────────
# -a adiciona o repo em /repo na ISO; -c aponta o Anaconda para ele; --ks embute
# o kickstart (adiciona inst.ks= à linha de comando de boot).
echo "==> 3/3: mkksiso (kickstart + repo offline)..."
rm -f "$ISO_OUT"
mkksiso --ks "$KS" \
    -a "$WORK/repo" \
    -c "inst.repo=hd:LABEL=${VOLID}:/repo" \
    -V "$VOLID" \
    "$BOOT_ISO" "$ISO_OUT"

echo
echo "==> Concluído: $ISO_OUT"
ls -lh "$ISO_OUT"
