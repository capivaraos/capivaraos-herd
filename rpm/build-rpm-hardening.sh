#!/bin/bash
# Empacota hardening/ num tarball e constrói o RPM capivaraos-herd-hardening.
#
# Uso:
#   sudo dnf install -y rpm-build createrepo_c
#   ./build-rpm-hardening.sh
#
# O RPM fica em ~/rpmbuild/RPMS/noarch/. Sirva-o no repo local junto do branding:
#   cp ~/rpmbuild/RPMS/noarch/capivaraos-herd-hardening-*.rpm /var/tmp/capivaraos-herd-repo/
#   createrepo_c /var/tmp/capivaraos-herd-repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NAME="capivaraos-herd-hardening"

# VERSION sai do próprio .spec — NÃO cravar aqui (mesma lição do BUG-30).
VERSION="$(rpmspec -q --qf '%{version}\n' "${SCRIPT_DIR}/${NAME}.spec" 2>/dev/null | head -1)"
[ -n "$VERSION" ] || { echo "ERRO: não consegui ler Version: do spec" >&2; exit 1; }

WORKDIR="$(mktemp -d)"
SRCDIR="${WORKDIR}/${NAME}-${VERSION}"
mkdir -p "$SRCDIR"
# Leva a árvore de config de hardening inteira para dentro do tarball.
cp -r "${PROJECT_DIR}/hardening/." "$SRCDIR/"

mkdir -p "$HOME/rpmbuild/SOURCES" "$HOME/rpmbuild/SPECS"
rm -f "$HOME/rpmbuild/SOURCES/${NAME}-${VERSION}.tar.gz"
tar -C "$WORKDIR" -czf "$HOME/rpmbuild/SOURCES/${NAME}-${VERSION}.tar.gz" "${NAME}-${VERSION}"
cp "${SCRIPT_DIR}/${NAME}.spec" "$HOME/rpmbuild/SPECS/"
rm -rf "$WORKDIR"

rpmbuild -bb "$HOME/rpmbuild/SPECS/${NAME}.spec"

echo
echo "RPM gerado em: $HOME/rpmbuild/RPMS/noarch/"
ls -1 "$HOME/rpmbuild/RPMS/noarch/" | grep "^${NAME}"
