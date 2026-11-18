#!/bin/bash
# =============================================================================
# Builds the BRANDED, OFFLINE CapivaraOS Herd installer ISO.
# =============================================================================
# Unlike build.sh (osbuild: qcow2 + image-installer, whose installer carries
# fixed Fedora branding), this ISO is built with lorax + mkksiso so that the
# INSTALLER (boot menu and Anaconda screens) carries the CapivaraOS brand:
#
#   1. lorax   → branded installer (product name "Herd by CapivaraOS" and the
#      artwork of capivaraos-herd-logos in place of fedora-logos).
#   2. dnf     → downloads @core + the Herd package set (+ deps) into a local
#      repository (makes the installation OFFLINE).
#   3. mkksiso → injects the server kickstart and the repository into the lorax
#      boot.iso, pointing Anaconda at it (inst.repo=hd:LABEL=...:/repo).
#
# PREREQUISITES (needs root for lorax/dnf):
#   sudo dnf install -y lorax createrepo_c
#   The six Herd RPMs (branding, hardening, logos, repos, autoupdate, upgrade)
#   built and served from the repository:
#       for s in "" -hardening -logos -repos -autoupdate -upgrade; do
#           ./rpm/build-rpm${s}.sh
#       done
#       mkdir -p /var/tmp/capivaraos-herd-repo
#       cp ~/rpmbuild/RPMS/noarch/capivaraos-herd-{branding,hardening,logos}-*.rpm \
#          ~/rpmbuild/RPMS/noarch/capivaraos-herd-{repos,autoupdate,upgrade}-*.rpm \
#          /var/tmp/capivaraos-herd-repo/
#       createrepo_c /var/tmp/capivaraos-herd-repo
#
# Usage:  sudo ./build-iso.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINT_TOML="$SCRIPT_DIR/blueprints/capivaraos-herd.toml"
VERSION="$(awk -F'"' '/^version[[:space:]]*=/{print $2; exit}' "$BLUEPRINT_TOML")"
ARCH="$(uname -m)"
RELEASEVER=45                       # Herd 2.x = Fedora 45 (see build.sh)
PRODUCT="Herd by CapivaraOS"
VARIANT="Server"
VOLID="CapivaraOS-HERD-${VERSION}"  # <= 32 chars (ISO9660); matches inst.repo
# Kickstart embedded in the ISO. Override with KS=/path/other.ks ./build-iso.sh
# (for example a variant with autopart --encrypted already set).
KS="${KS:-$SCRIPT_DIR/kickstart/capivaraos-herd.ks}"
BRANDING_REPO="/var/tmp/capivaraos-herd-repo"
OUT="$SCRIPT_DIR/out"
WORK="/var/tmp/herd-iso"
ISO_OUT="$OUT/CapivaraOS-HERD-${VERSION}-${ARCH}.installer.iso"

# Payload package set (MIRRORS the kickstart %packages). Keep them in sync:
# this is what goes into the offline repository; the kickstart is what Anaconda
# installs from it.
PAYLOAD_PKGS=(
    kernel capivaraos-herd-branding capivaraos-herd-hardening
    capivaraos-herd-repos capivaraos-herd-autoupdate capivaraos-herd-upgrade
    cloud-init qemu-guest-agent openssh-server fastfetch
    firewalld chrony cockpit cockpit-storaged cockpit-networkmanager
    cockpit-packagekit glibc-langpack-pt glibc-langpack-en
    systemd-pam kmscon cryptsetup
)

echo "==> Herd by CapivaraOS installer ISO ${VERSION} (${ARCH})"

# ── Sanity checks ────────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo (lorax and dnf need root)." >&2; exit 1; }
OSVER="$(. /etc/os-release && echo "${VERSION_ID:-?}")"
[ "$OSVER" = "$RELEASEVER" ] || echo "WARNING: host is Fedora ${OSVER}, not ${RELEASEVER}." >&2
for t in lorax mkksiso createrepo_c dnf; do
    command -v "$t" >/dev/null || { echo "ERROR: '$t' not found (dnf install lorax createrepo_c)." >&2; exit 1; }
done
for rpm in capivaraos-herd-branding capivaraos-herd-hardening capivaraos-herd-logos \
           capivaraos-herd-repos capivaraos-herd-autoupdate capivaraos-herd-upgrade; do
    ls "$BRANDING_REPO/${rpm}"-*.rpm >/dev/null 2>&1 || {
        echo "ERROR: ${rpm} is not in ${BRANDING_REPO}. Run the build-rpm scripts and createrepo_c (see the header)." >&2
        exit 1
    }
done

mkdir -p "$WORK" "$OUT"
BOOT_ISO="$WORK/lorax/images/boot.iso"

# ── 1. Branded installer (lorax) ─────────────────────────────────────────────
# -i capivaraos-herd-logos: lorax installs "fedora-logos" by name (derived from
#    the release). Our package Provides fedora-logos and the real fedora-logos
#    is excluded from the Fedora repositories below, so dnf installs ours and
#    Anaconda gets our artwork. Do NOT use -e fedora-logos (lorax removepkg
#    fails on a package that is not installed).
#    -p/-v/-t: product name in the boot menu and in .buildstamp.
# lorax requires that the output directory does NOT exist.
# Reuses an installer already built (lorax is the longest step). To force a
# rebuild, delete $WORK/lorax or run with FORCE_LORAX=1.
if [ -f "$BOOT_ISO" ] && [ -z "${FORCE_LORAX:-}" ]; then
    echo "==> 1/3: reusing the existing lorax output ($BOOT_ISO). (FORCE_LORAX=1 rebuilds it)"
else
rm -rf "$WORK/lorax"
echo "==> 1/3: lorax (branded installer)..."
# Repositories as .repo files: the real fedora-logos is EXCLUDED from the
# Fedora repositories, so our capivaraos-herd-logos (Provides fedora-logos) is
# the ONLY provider when lorax runs "installpkg fedora-logos".
REPODIR="$WORK/repos.d"
mkdir -p "$REPODIR"
# metalink, not a fixed baseurl: it brings the mirror list with checksums and
# fails over automatically. A single baseurl hits one mirror and, if that
# mirror is incomplete, returns 404 with no alternative.
cat > "$REPODIR/fedora.repo" <<EOF
[fedora]
name=Fedora ${RELEASEVER} - ${ARCH}
metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-${RELEASEVER}&arch=${ARCH}
enabled=1
gpgcheck=0
exclude=fedora-logos
EOF
cat > "$REPODIR/updates.repo" <<EOF
[updates]
name=Fedora ${RELEASEVER} - ${ARCH} - Updates
metalink=https://mirrors.fedoraproject.org/metalink?repo=updates-released-f${RELEASEVER}&arch=${ARCH}
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
fi

[ -f "$BOOT_ISO" ] || { echo "ERROR: lorax did not produce ${BOOT_ISO}." >&2; exit 1; }

# ── 2. Offline repository (payload) ──────────────────────────────────────────
# Reuses the repository if it exists (FORCE_REPO=1 rebuilds it), so a change to
# the kickstart only reruns mkksiso (seconds). Reused only when COMPLETE
# (repomd.xml AND at least one RPM): $WORK is persistent under /var/tmp, and an
# EMPTY repository left by an earlier run would give an ISO with an empty /repo
# (Anaconda: "Nothing useful found", installation stuck).
if [ -f "$WORK/repo/repodata/repomd.xml" ] && ls "$WORK/repo"/*.rpm >/dev/null 2>&1 \
   && [ -z "${FORCE_REPO:-}" ]; then
    echo "==> 2/3: reusing the existing offline repository ($(ls "$WORK/repo"/*.rpm | wc -l) RPMs). (FORCE_REPO=1 rebuilds it)"
else
rm -rf "$WORK/repo" "$WORK/dnfcache" "$WORK/instroot"
# dnf5 'install --downloadonly' accepts GROUPS (@core) and resolves the whole
# transaction; packages go to a dedicated cachedir (keepcache) and are collected
# from there. kernel and bootloader are listed explicitly: they are not @core
# dependencies, but Anaconda needs them for a bootable offline installation.
echo "==> 2/3: downloading payload packages into the offline repository..."
mkdir -p "$WORK/repo"
DNFCACHE="$WORK/dnfcache"
# --use-host-config: uses the host repositories (fedora/updates with metalink)
# besides our herd-local; without it, with an empty --installroot dnf5 loads no
# repository at all ("No repositories were loaded from the installroot").
dnf -y --releasever="$RELEASEVER" \
    --installroot="$WORK/instroot" --use-host-config \
    --repofrompath="herd-local,file://${BRANDING_REPO}" \
    --setopt=herd-local.gpgcheck=0 \
    --setopt=install_weak_deps=False \
    --setopt=cachedir="$DNFCACHE" --setopt=keepcache=1 \
    install --downloadonly \
    @core NetworkManager kernel dracut \
    grub2-pc grub2-pc-modules grub2-efi-x64 grub2-efi-x64-modules shim-x64 \
    grub2-tools grub2-tools-minimal grub2-tools-extra efibootmgr \
    lvm2 mdadm dosfstools xfsprogs e2fsprogs btrfs-progs \
    "${PAYLOAD_PKGS[@]}"
# Collect the downloaded RPMs from the cache.
find "$DNFCACHE" -name '*.rpm' -exec cp -n {} "$WORK/repo/" \;
# file:// packages (our RPMs) may not reach the cache; copy them directly.
# Includes the project packages the INSTALLED system uses (branding, hardening,
# repos, autoupdate, upgrade). Does NOT include capivaraos-herd-logos: it is
# for the installer only (lorax), Provides fedora-logos, and must not enter the
# installed system's repository. fastfetch comes from Fedora, via the cache.
cp -n "$BRANDING_REPO"/capivaraos-herd-branding-*.rpm \
      "$BRANDING_REPO"/capivaraos-herd-hardening-*.rpm \
      "$BRANDING_REPO"/capivaraos-herd-repos-*.rpm \
      "$BRANDING_REPO"/capivaraos-herd-autoupdate-*.rpm \
      "$BRANDING_REPO"/capivaraos-herd-upgrade-*.rpm "$WORK/repo/" 2>/dev/null || true
# comps (groups) so that the kickstart @core resolves in Anaconda.
COMPS_ZST="$(find /var/cache/libdnf5 -path '*fedora*' -name '*comps-Everything*.xml.zst' 2>/dev/null | head -1)"
if [ -n "$COMPS_ZST" ]; then
    zstd -dc "$COMPS_ZST" > "$WORK/comps.xml"
    createrepo_c -g "$WORK/comps.xml" "$WORK/repo" >/dev/null
else
    echo "WARNING: Fedora comps not found in the cache; @core may not resolve in Anaconda." >&2
    createrepo_c "$WORK/repo" >/dev/null
fi
echo "    $(ls "$WORK/repo"/*.rpm 2>/dev/null | wc -l) RPMs in the offline repository."
fi

# Sanity lock: the offline repository must NOT reach the ISO empty (installation
# would fail with "Nothing useful found for the HDD source" in Anaconda).
# Requires repomd and at least 50 RPMs.
RPM_COUNT=$(ls "$WORK/repo"/*.rpm 2>/dev/null | wc -l)
[ -f "$WORK/repo/repodata/repomd.xml" ] && [ "$RPM_COUNT" -ge 50 ] || {
    echo "ERROR: offline repository invalid or empty (${RPM_COUNT} RPMs, repomd $([ -f "$WORK/repo/repodata/repomd.xml" ] && echo ok || echo MISSING))." >&2
    echo "       Run with FORCE_REPO=1 and check the download in step 2/3." >&2
    exit 1
}

# ── 3. Inject kickstart + repository into the ISO (mkksiso) ─────────────────
# -a adds the repository at /repo on the ISO; -c points Anaconda at it; --ks
# embeds the kickstart (adds inst.ks= to the boot command line).
echo "==> 3/3: mkksiso (kickstart and offline repository)..."
rm -f "$ISO_OUT"
mkksiso --ks "$KS" \
    -a "$WORK/repo" \
    -c "inst.repo=hd:LABEL=${VOLID}:/repo" \
    -V "$VOLID" \
    "$BOOT_ISO" "$ISO_OUT"

echo
echo "==> Done: $ISO_OUT"
ls -lh "$ISO_OUT"
