#!/bin/bash
# Constrói o RPM capivaraos-herd-repos (config do repositório + chave pública).
#
# Uso:
#   sudo dnf install -y rpm-build createrepo_c
#   ./build-rpm-repos.sh
#
# PRÉ-REQUISITO: a chave pública precisa existir em keys/RPM-GPG-KEY-capivaraos-herd.
# Ela é gerada UMA vez, OFFLINE, pela cerimônia keys/gen-signing-key.sh (a chave
# PRIVADA nunca entra no repositório). Sem a pública, este build para com
# instruções — de propósito: não empacotamos chave de placeholder.
#
# O RPM fica em ~/rpmbuild/RPMS/noarch/. Sirva-o no repo local junto dos demais:
#   cp ~/rpmbuild/RPMS/noarch/capivaraos-herd-repos-*.rpm /var/tmp/capivaraos-herd-repo/
#   createrepo_c /var/tmp/capivaraos-herd-repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NAME="capivaraos-herd-repos"

REPO_FILE="${PROJECT_DIR}/repo/capivaraos-herd.repo"
KEY_FILE="${PROJECT_DIR}/keys/RPM-GPG-KEY-capivaraos-herd"

[ -f "$REPO_FILE" ] || { echo "ERRO: não achei ${REPO_FILE}" >&2; exit 1; }
if [ ! -f "$KEY_FILE" ]; then
    cat >&2 <<EOF
ERRO: chave pública ausente: ${KEY_FILE}

The repository signing key is generated ONCE, OFFLINE, with:
    ./keys/gen-signing-key.sh
Then export the PUBLIC key to keys/RPM-GPG-KEY-capivaraos-herd (the private
key NEVER goes into the repository; it is kept offline). Only then can this
package be built. See keys/README.md.
EOF
    exit 1
fi

# VERSION comes from the .spec; do not hard-code it here.
VERSION="$(rpmspec -q --qf '%{version}\n' "${SCRIPT_DIR}/${NAME}.spec" 2>/dev/null | head -1)"
[ -n "$VERSION" ] || { echo "ERRO: não consegui ler Version: do spec" >&2; exit 1; }

mkdir -p "$HOME/rpmbuild/SOURCES" "$HOME/rpmbuild/SPECS"
# Sources soltos (não tarball): copiados diretos para SOURCES.
install -m 0644 "$REPO_FILE" "$HOME/rpmbuild/SOURCES/capivaraos-herd.repo"
install -m 0644 "$KEY_FILE"  "$HOME/rpmbuild/SOURCES/RPM-GPG-KEY-capivaraos-herd"
cp "${SCRIPT_DIR}/${NAME}.spec" "$HOME/rpmbuild/SPECS/"

rpmbuild -bb "$HOME/rpmbuild/SPECS/${NAME}.spec"

echo
echo "RPM gerado em: $HOME/rpmbuild/RPMS/noarch/"
find "$HOME/rpmbuild/RPMS/noarch/" -maxdepth 1 -name "${NAME}*.rpm" -printf '%f\n'
