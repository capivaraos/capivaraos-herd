#!/bin/bash
# =============================================================================
# Build FINAL de release do Herd by CapivaraOS (Community, x86_64).
# =============================================================================
# Produz os dois artefatos de release + checksums:
#   - out/CapivaraOS-HERD-${VERSION}-x86_64.qcow2           (nuvem/VM, cloud-init)
#   - out/CapivaraOS-HERD-${VERSION}-x86_64.installer.iso   (instalador brandeado, lorax)
#   - out/SHA256SUMS
#
# Pré-requisitos JÁ feitos antes de rodar: os 3 RPMs (branding, hardening, logos
# — nas versões atuais) construídos e o repo local /var/tmp/capivaraos-herd-repo
# populado + createrepo. Este script só faz a parte que precisa de root.
#
# USO (num terminal com sudo):
#   cd /home/dp/capivaraos/capivaraos-herd && sudo ./release-build.sh
# =============================================================================
set -euo pipefail

REPO_DIR=/home/dp/capivaraos/capivaraos-herd
OWNER=dp
cd "$REPO_DIR"

# Versão vem do blueprint (fonte única) — não cravar aqui.
VERSION="$(awk -F'"' '/^version[[:space:]]*=/{print $2; exit}' blueprints/capivaraos-herd.toml)"
[ -n "$VERSION" ] || { echo "ERRO: não consegui ler a versão do blueprint" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || { echo "ERRO: rode com sudo -> sudo ./release-build.sh" >&2; exit 1; }

echo "########## 1/3: qcow2 (osbuild) ##########"
./build.sh qcow2

echo "########## 2/3: ISO instaladora brandeada (lorax + repo, REBUILD forcado) ##########"
# Forca refazer o lorax e o repo offline porque os RPMs mudaram.
FORCE_LORAX=1 FORCE_REPO=1 ./build-iso.sh

echo "########## limpeza: remove ISO osbuild antiga (nao e artefato de release) ##########"
rm -f "$REPO_DIR/out/CapivaraOS-HERD-${VERSION}-x86_64.iso"

echo "########## 3/3: dono + checksums ##########"
chown -R "$OWNER":"$OWNER" "$REPO_DIR/out"
cd "$REPO_DIR/out"
sha256sum CapivaraOS-HERD-${VERSION}-x86_64.qcow2 \
          CapivaraOS-HERD-${VERSION}-x86_64.installer.iso > SHA256SUMS
chown "$OWNER":"$OWNER" SHA256SUMS

echo
echo "==> Artefatos de release:"
ls -lh CapivaraOS-HERD-${VERSION}-x86_64.qcow2 CapivaraOS-HERD-${VERSION}-x86_64.installer.iso
echo
echo "==> SHA256SUMS:"
cat SHA256SUMS
