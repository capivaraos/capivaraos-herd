#!/bin/bash
# Empacota logos/ num tarball e constrói o RPM capivaraos-herd-logos (arte do
# instalador Anaconda). Requer ImageMagick (gera os pixmaps no %build).
#
# Uso:
#   sudo dnf install -y rpm-build ImageMagick
#   ./build-rpm-logos.sh
#
# O RPM fica em ~/rpmbuild/RPMS/noarch/ e é consumido pelo build da ISO (lorax).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NAME="capivaraos-herd-logos"

# VERSION sai do próprio .spec (mesma lição do branding: não cravar aqui).
VERSION="$(rpmspec -q --qf '%{version}\n' "${SCRIPT_DIR}/${NAME}.spec" 2>/dev/null | head -1)"
[ -n "$VERSION" ] || { echo "ERRO: não consegui ler Version: do spec" >&2; exit 1; }

WORKDIR="$(mktemp -d)"
SRCDIR="${WORKDIR}/${NAME}-${VERSION}"
mkdir -p "$SRCDIR/src"
cp "${PROJECT_DIR}/logos/src/"*.png     "$SRCDIR/src/"
cp "${PROJECT_DIR}/logos/capivaraos-herd.css" "$SRCDIR/"

mkdir -p "$HOME/rpmbuild/SOURCES" "$HOME/rpmbuild/SPECS"
# Remove tarball homônimo de build anterior antes de gravar o novo.
rm -f "$HOME/rpmbuild/SOURCES/${NAME}-${VERSION}.tar.gz"
tar -C "$WORKDIR" -czf "$HOME/rpmbuild/SOURCES/${NAME}-${VERSION}.tar.gz" "${NAME}-${VERSION}"
cp "${SCRIPT_DIR}/${NAME}.spec" "$HOME/rpmbuild/SPECS/"
rm -rf "$WORKDIR"

rpmbuild -bb "$HOME/rpmbuild/SPECS/${NAME}.spec"

echo
echo "RPM gerado em: $HOME/rpmbuild/RPMS/noarch/"
find "$HOME/rpmbuild/RPMS/noarch/" -maxdepth 1 -name "${NAME}*.rpm" -printf '%f\n'
