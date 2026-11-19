#!/bin/bash
# Builds the capivaraos-herd-repos RPM (repository configuration, the two
# public Herd keys and the dnf5-automatic drop-in).
#
# Usage:
#   sudo dnf install -y rpm-build createrepo_c
#   ./build-rpm-repos.sh
#
# PREREQUISITE: the public keys must exist in keys/ (RPM-GPG-KEY-capivaraos-herd
# and RPM-GPG-KEY-capivaraos-herd-reserve). The private keys never enter the
# repository. Without the public keys this build stops with instructions, on
# purpose: no placeholder key is ever packaged.
#
# The RPM goes to ~/rpmbuild/RPMS/noarch/. Serve it from the local repository
# with the others:
#   cp ~/rpmbuild/RPMS/noarch/capivaraos-herd-repos-*.rpm /var/tmp/capivaraos-herd-repo/
#   createrepo_c /var/tmp/capivaraos-herd-repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NAME="capivaraos-herd-repos"

REPO_FILE="${PROJECT_DIR}/repo/capivaraos-herd.repo"
KEY_FILE="${PROJECT_DIR}/keys/RPM-GPG-KEY-capivaraos-herd"
# Reserve key (public part only), shipped and trusted next to the current one.
RESERVE_KEY_FILE="${PROJECT_DIR}/keys/RPM-GPG-KEY-capivaraos-herd-reserve"

[ -f "$REPO_FILE" ] || { echo "ERROR: ${REPO_FILE} not found" >&2; exit 1; }
if [ ! -f "$KEY_FILE" ]; then
    cat >&2 <<EOF
ERROR: public key missing: ${KEY_FILE}

The repository signing key is generated once with:
    ./keys/gen-signing-key.sh
Then export the PUBLIC key to keys/RPM-GPG-KEY-capivaraos-herd (the private key
never enters the repository). Only then can this package be built.
See keys/README.md.
EOF
    exit 1
fi

[ -s "$RESERVE_KEY_FILE" ] || { echo "ERROR: reserve public key missing: ${RESERVE_KEY_FILE}" >&2; exit 1; }
if grep -q "PRIVATE KEY" "$KEY_FILE" "$RESERVE_KEY_FILE"; then
    echo "ERROR: a key file in keys/ contains private key material; stop." >&2; exit 1
fi

# VERSION comes from the spec; do not hard-code it here.
VERSION="$(rpmspec -q --qf '%{version}\n' "${SCRIPT_DIR}/${NAME}.spec" 2>/dev/null | head -1)"
[ -n "$VERSION" ] || { echo "ERROR: cannot read Version: from the spec" >&2; exit 1; }

mkdir -p "$HOME/rpmbuild/SOURCES" "$HOME/rpmbuild/SPECS"
# Plain source files, not a tarball: copied straight to SOURCES.
install -m 0644 "$REPO_FILE" "$HOME/rpmbuild/SOURCES/capivaraos-herd.repo"
install -m 0644 "$KEY_FILE"  "$HOME/rpmbuild/SOURCES/RPM-GPG-KEY-capivaraos-herd"
install -m 0644 "$RESERVE_KEY_FILE" "$HOME/rpmbuild/SOURCES/RPM-GPG-KEY-capivaraos-herd-reserve"
install -m 0644 "${PROJECT_DIR}/repo/50-capivaraos-herd-keys.conf" "$HOME/rpmbuild/SOURCES/"
cp "${SCRIPT_DIR}/${NAME}.spec" "$HOME/rpmbuild/SPECS/"

rpmbuild -bb "$HOME/rpmbuild/SPECS/${NAME}.spec"

echo
echo "RPM written to: $HOME/rpmbuild/RPMS/noarch/"
find "$HOME/rpmbuild/RPMS/noarch/" -maxdepth 1 -name "${NAME}*.rpm" -printf '%f\n'
