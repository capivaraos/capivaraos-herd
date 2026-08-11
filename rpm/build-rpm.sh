#!/bin/bash
# Empacota branding/ num tarball e constrói o RPM capivaraos-herd-branding.
#
# Uso:
#   sudo dnf install -y rpm-build createrepo_c
#   ./build-rpm.sh
#
# O RPM resultante fica em ~/rpmbuild/RPMS/noarch/. Depois, sirva-o num repo
# local para o build.sh (osbuild) consumir:
#   NEVRA=$(rpmspec -q --qf '%{name}-%{version}-%{release}.%{arch}\n' \
#       rpm/capivaraos-herd-branding.spec | head -1)
#   mkdir -p /var/tmp/capivaraos-herd-repo
#   cp ~/rpmbuild/RPMS/noarch/${NEVRA}.rpm /var/tmp/capivaraos-herd-repo/
#   createrepo_c /var/tmp/capivaraos-herd-repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NAME="capivaraos-herd-branding"

# VERSION sai do próprio .spec — NÃO cravar aqui. (Mesma lição do branding dos
# desktops: cravar a versão fazia o rpmbuild pegar em silêncio um tarball
# homônimo VELHO de ~/rpmbuild/SOURCES, compartilhado entre as spins.)
VERSION="$(rpmspec -q --qf '%{version}\n' "${SCRIPT_DIR}/${NAME}.spec" 2>/dev/null | head -1)"
[ -n "$VERSION" ] || { echo "ERRO: não consegui ler Version: do spec" >&2; exit 1; }

WORKDIR="$(mktemp -d)"
SRCDIR="${WORKDIR}/${NAME}-${VERSION}"
mkdir -p "$SRCDIR"
cp "${PROJECT_DIR}/branding/os-release" "$SRCDIR/"
cp "${PROJECT_DIR}/branding/issue"      "$SRCDIR/"
cp "${PROJECT_DIR}/branding/motd"       "$SRCDIR/"
# Branding do Cockpit (console web): CSS + arte de origem (gerada no %build).
cp -r "${PROJECT_DIR}/branding/cockpit" "$SRCDIR/"

mkdir -p "$HOME/rpmbuild/SOURCES" "$HOME/rpmbuild/SPECS"
# Remove um tarball homônimo de build anterior antes de gravar o novo.
rm -f "$HOME/rpmbuild/SOURCES/${NAME}-${VERSION}.tar.gz"
tar -C "$WORKDIR" -czf "$HOME/rpmbuild/SOURCES/${NAME}-${VERSION}.tar.gz" "${NAME}-${VERSION}"
cp "${SCRIPT_DIR}/${NAME}.spec" "$HOME/rpmbuild/SPECS/"
rm -rf "$WORKDIR"

rpmbuild -bb "$HOME/rpmbuild/SPECS/${NAME}.spec"

echo
echo "RPM gerado em: $HOME/rpmbuild/RPMS/noarch/"
ls -1 "$HOME/rpmbuild/RPMS/noarch/" | grep "^${NAME}"
