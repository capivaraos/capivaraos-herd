#!/bin/bash
# Constrói o RPM capivaraos-herd-autoupdate (política do dnf5 automatic).
#
# Uso:
#   sudo dnf install -y rpm-build
#   ./build-rpm-autoupdate.sh
#
# O RPM fica em ~/rpmbuild/RPMS/noarch/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NAME="capivaraos-herd-autoupdate"

CONF="${PROJECT_DIR}/autoupdate/automatic.conf"
[ -f "$CONF" ] || { echo "ERRO: não achei ${CONF}" >&2; exit 1; }

# VERSION sai do próprio .spec — NÃO cravar aqui (lição do BUG-30).
VERSION="$(rpmspec -q --qf '%{version}\n' "${SCRIPT_DIR}/${NAME}.spec" 2>/dev/null | head -1)"
[ -n "$VERSION" ] || { echo "ERRO: não consegui ler Version: do spec" >&2; exit 1; }

mkdir -p "$HOME/rpmbuild/SOURCES" "$HOME/rpmbuild/SPECS"
install -m 0644 "$CONF" "$HOME/rpmbuild/SOURCES/automatic.conf"
cp "${SCRIPT_DIR}/${NAME}.spec" "$HOME/rpmbuild/SPECS/"

rpmbuild -bb "$HOME/rpmbuild/SPECS/${NAME}.spec"

echo
echo "RPM gerado em: $HOME/rpmbuild/RPMS/noarch/"
find "$HOME/rpmbuild/RPMS/noarch/" -maxdepth 1 -name "${NAME}*.rpm" -printf '%f\n'
