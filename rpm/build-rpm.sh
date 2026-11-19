#!/bin/bash
# Packs branding/ into a tarball and builds the capivaraos-herd-branding RPM.
#
# Usage:
#   sudo dnf install -y rpm-build createrepo_c
#   ./build-rpm.sh
#
# The RPM goes to ~/rpmbuild/RPMS/noarch/. Then serve it from a local
# repository for build.sh (osbuild):
#   NEVRA=$(rpmspec -q --qf '%{name}-%{version}-%{release}.%{arch}\n' \
#       rpm/capivaraos-herd-branding.spec | head -1)
#   mkdir -p /var/tmp/capivaraos-herd-repo
#   cp ~/rpmbuild/RPMS/noarch/${NEVRA}.rpm /var/tmp/capivaraos-herd-repo/
#   createrepo_c /var/tmp/capivaraos-herd-repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NAME="capivaraos-herd-branding"

# VERSION comes from the .spec; do not hard-code it: a stale same-named tarball
# in the shared ~/rpmbuild/SOURCES would be picked up silently.
VERSION="$(rpmspec -q --qf '%{version}\n' "${SCRIPT_DIR}/${NAME}.spec" 2>/dev/null | head -1)"
[ -n "$VERSION" ] || { echo "ERROR: cannot read Version: from the spec" >&2; exit 1; }

WORKDIR="$(mktemp -d)"
SRCDIR="${WORKDIR}/${NAME}-${VERSION}"
mkdir -p "$SRCDIR"
cp "${PROJECT_DIR}/branding/os-release"        "$SRCDIR/"
cp "${PROJECT_DIR}/branding/issue"             "$SRCDIR/"
cp "${PROJECT_DIR}/branding/motd"              "$SRCDIR/"
cp "${PROJECT_DIR}/branding/fix-bls-titles.sh" "$SRCDIR/"
# Cockpit (web console) branding: CSS and source artwork (built in %build).
cp -r "${PROJECT_DIR}/branding/cockpit" "$SRCDIR/"
# fastfetch logo: ASCII art and config.jsonc.
cp -r "${PROJECT_DIR}/branding/fastfetch" "$SRCDIR/"

mkdir -p "$HOME/rpmbuild/SOURCES" "$HOME/rpmbuild/SPECS"
# Remove a same-name tarball from an earlier build before writing the new one.
rm -f "$HOME/rpmbuild/SOURCES/${NAME}-${VERSION}.tar.gz"
tar -C "$WORKDIR" -czf "$HOME/rpmbuild/SOURCES/${NAME}-${VERSION}.tar.gz" "${NAME}-${VERSION}"
cp "${SCRIPT_DIR}/${NAME}.spec" "$HOME/rpmbuild/SPECS/"
rm -rf "$WORKDIR"

rpmbuild -bb "$HOME/rpmbuild/SPECS/${NAME}.spec"

echo
echo "RPM written to: $HOME/rpmbuild/RPMS/noarch/"
find "$HOME/rpmbuild/RPMS/noarch/" -maxdepth 1 -name "${NAME}*.rpm" -printf '%f\n'
