#!/bin/bash
# =============================================================================
# Build FINAL de release do CapivaraOS HERD Community 1.0.0 (x86_64).
# =============================================================================
# Produz os dois artefatos de release + checksums:
#   - out/CapivaraOS-HERD-1.0.0-x86_64.qcow2           (nuvem/VM, cloud-init)
#   - out/CapivaraOS-HERD-1.0.0-x86_64.installer.iso   (instalador brandeado, lorax)
#   - out/SHA256SUMS
#
# Pré-requisitos JÁ feitos por esta sessão: os 3 RPMs (branding-9, hardening-3,
# logos-3) foram construídos e o repo local /var/tmp/capivaraos-herd-repo está
# populado + createrepo. Este script só faz a parte que precisa de root.
#
# USO (num terminal com sudo):
#   cd /home/dp/capivaraos/capivaraos-herd && sudo ./release-build.sh
# =============================================================================
set -euo pipefail

REPO_DIR=/home/dp/capivaraos/capivaraos-herd
OWNER=dp
cd "$REPO_DIR"

[ "$(id -u)" -eq 0 ] || { echo "ERRO: rode com sudo -> sudo ./release-build.sh" >&2; exit 1; }

echo "########## 1/3: qcow2 (osbuild) ##########"
./build.sh qcow2

echo "########## 2/3: ISO instaladora brandeada (lorax + repo, REBUILD forcado) ##########"
# Forca refazer o lorax e o repo offline porque os RPMs mudaram (branding -9).
FORCE_LORAX=1 FORCE_REPO=1 ./build-iso.sh

echo "########## limpeza: remove ISO osbuild antiga (nao e artefato de release) ##########"
rm -f "$REPO_DIR/out/CapivaraOS-HERD-1.0.0-x86_64.iso"

echo "########## 3/3: dono + checksums ##########"
chown -R "$OWNER":"$OWNER" "$REPO_DIR/out"
cd "$REPO_DIR/out"
sha256sum CapivaraOS-HERD-1.0.0-x86_64.qcow2 \
          CapivaraOS-HERD-1.0.0-x86_64.installer.iso > SHA256SUMS
chown "$OWNER":"$OWNER" SHA256SUMS

echo
echo "==> Artefatos de release:"
ls -lh CapivaraOS-HERD-1.0.0-x86_64.qcow2 CapivaraOS-HERD-1.0.0-x86_64.installer.iso
echo
echo "==> SHA256SUMS:"
cat SHA256SUMS
