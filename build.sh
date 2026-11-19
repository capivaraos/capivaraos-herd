#!/bin/bash
# =============================================================================
# Builds the CapivaraOS Herd Community images with osbuild / Image Builder.
# =============================================================================
# From blueprints/capivaraos-herd.toml (the source of truth) it produces:
#   - qcow2            (cloud/VM, cloud-init)
#   - image-installer  (headless installer ISO)
# for the HOST architecture. For aarch64, run this script on an aarch64 host
# or VM (osbuild composes for the host architecture).
#
# PREREQUISITES:
#   - A Fedora 45 host; the image is Fedora 45 (distro = "fedora-45" in the
#     blueprint). Builds directly on the machine, no VM.
#   - osbuild-composer and composer-cli installed, service running:
#       sudo dnf install -y osbuild-composer composer-cli
#       sudo systemctl enable --now osbuild-composer.socket
#   - The capivaraos-herd-branding RPM built (rpm/build-rpm.sh) and served
#     from a local repository (createrepo_c); see README.md.
#
# Usage:
#   ./build.sh                 # qcow2 and ISO
#   ./build.sh qcow2           # qcow2 only
#   ./build.sh image-installer # ISO only
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINT_TOML="$SCRIPT_DIR/blueprints/capivaraos-herd.toml"
BLUEPRINT_NAME="capivaraos-herd"
VERSION="$(awk -F'"' '/^version[[:space:]]*=/{print $2; exit}' "$BLUEPRINT_TOML")"
ARCH="$(uname -m)"
RESULT_DIR="$SCRIPT_DIR/out"
BRANDING_REPO="/var/tmp/capivaraos-herd-repo"   # local repository with the branding RPM

# Image types to build (default: both)
TYPES=("$@")
[ ${#TYPES[@]} -eq 0 ] && TYPES=(qcow2 image-installer)

echo "==> Herd by CapivaraOS ${VERSION} (${ARCH})"

# ── Target base: Fedora 45, whatever the host release ──────────────────────
# The blueprint sets `distro = "fedora-45"`, so osbuild-composer composes F45
# images on an F44 host too (it ships fedora-45.json in
# /usr/share/osbuild-composer/repositories/), with no mock or container.
OSVER="$(. /etc/os-release && echo "${VERSION_ID:-?}")"
[ "$OSVER" != "45" ] && echo "Note: Fedora ${OSVER} host; the image is F45 (distro = fedora-45 in the blueprint)." >&2

command -v composer-cli >/dev/null || {
    echo "ERROR: composer-cli not found. Install osbuild-composer and composer-cli." >&2
    exit 1
}

# ── 1. Composer source with the Herd branding (served over local HTTP) ─────
# osbuild downloads sources through org.osbuild.curl. With a file:// source,
# curl returns no HTTP status, the result parser records nothing, osbuild
# raises IndexError in sources.py and the compose fails with "did not return
# any output". The branding repo is therefore served over local HTTP. It
# serves only the Herd RPM, so branding from another spin cannot be picked up.
HTTP_PID=""
cleanup() { [ -n "$HTTP_PID" ] && kill "$HTTP_PID" 2>/dev/null || true; }
trap cleanup EXIT

if [ -d "$BRANDING_REPO" ]; then
    BRANDING_PORT="${BRANDING_PORT:-8099}"
    python3 -m http.server "$BRANDING_PORT" --bind 127.0.0.1 \
        --directory "$BRANDING_REPO" >/dev/null 2>&1 &
    HTTP_PID=$!

    # Wait for the server to answer before registering the source.
    for _ in $(seq 1 20); do
        if curl -sf "http://127.0.0.1:${BRANDING_PORT}/repodata/repomd.xml" -o /dev/null; then
            break
        fi
        sleep 0.5
    done
    curl -sf "http://127.0.0.1:${BRANDING_PORT}/repodata/repomd.xml" -o /dev/null || {
        echo "ERROR: the branding HTTP server did not answer on port ${BRANDING_PORT}." >&2
        echo "       (set BRANDING_PORT=<free port> if 8099 is in use.)" >&2
        exit 1
    }

    SRC_TOML="$(mktemp)"
    cat > "$SRC_TOML" <<EOF
id = "capivaraos-herd-branding"
name = "CapivaraOS HERD branding (local)"
type = "yum-baseurl"
url = "http://127.0.0.1:${BRANDING_PORT}/"
check_gpg = false
check_ssl = false
system = false
EOF
    # Remove an older source of the same name (e.g. file:// from an earlier run)
    # so that the HTTP URL really replaces it.
    sudo composer-cli sources delete capivaraos-herd-branding 2>/dev/null || true
    sudo composer-cli sources add "$SRC_TOML"
    rm -f "$SRC_TOML"
else
    echo "WARNING: branding repository not found in ${BRANDING_REPO}." >&2
    echo "         Run rpm/build-rpm.sh and createrepo_c first (see README.md)." >&2
fi

# ── 1b. Fedora updates repository ───────────────────────────────────────────
# osbuild-composer's fedora-45 definition only has the release repository, so
# the qcow2 would ship the packages of the Fedora 45 release and start with
# every later update pending. The ISO build already uses updates
# (build-iso.sh). A composer source is not enough: it only serves the
# blueprint's own packages, and the base packages would still come from the
# release, which conflicts. So this writes a host override of the fedora-45
# repository list in /etc/osbuild-composer/repositories/ that adds the updates
# repository, checked with the same Fedora key as the release repository. The
# override stays on this host and applies to every fedora-45 compose here.
FEDORA_REPOS_JSON="/usr/share/osbuild-composer/repositories/fedora-45.json"
OVERRIDE_JSON="/etc/osbuild-composer/repositories/fedora-45.json"
[ -f "$FEDORA_REPOS_JSON" ] || { echo "ERROR: $FEDORA_REPOS_JSON not found" >&2; exit 1; }
NEW_JSON="$(mktemp)"
python3 -I - "$FEDORA_REPOS_JSON" > "$NEW_JSON" <<'PY'
import copy, json, sys
data = json.load(open(sys.argv[1]))
for arch, repos in data.items():
    base = next(r for r in repos if r.get("name") == "fedora")
    if not base.get("check_gpg") or not base.get("gpgkey"):
        sys.exit(f"fedora repository for {arch} has no signature check")
    if any(r.get("name") == "updates" for r in repos):
        continue
    upd = copy.deepcopy(base)
    upd["name"] = "updates"
    upd["metalink"] = (
        f"https://mirrors.fedoraproject.org/metalink?repo=updates-released-f45&arch={arch}")
    repos.append(upd)
json.dump(data, sys.stdout, indent=2)
PY
if ! sudo cmp -s "$NEW_JSON" "$OVERRIDE_JSON" 2>/dev/null; then
    sudo install -D -m 0644 -o root -g root "$NEW_JSON" "$OVERRIDE_JSON"
    sudo systemctl restart osbuild-composer.service
    sleep 3
fi
rm -f "$NEW_JSON"
# A fedora-45-updates composer source, if one is defined on this host,
# would add the updates repository a second time; remove it.
sudo composer-cli sources delete fedora-45-updates 2>/dev/null || true

# ── 2. Push or update the blueprint ─────────────────────────────────────────
sudo composer-cli blueprints push "$BLUEPRINT_TOML"
sudo composer-cli blueprints depsolve "$BLUEPRINT_NAME"

# ── 3. Compose each image type ──────────────────────────────────────────────
mkdir -p "$RESULT_DIR"
for TYPE in "${TYPES[@]}"; do
    echo "==> Composing ${TYPE}..."
    COMPOSE_ID="$(sudo composer-cli compose start "$BLUEPRINT_NAME" "$TYPE" \
        | awk '/Compose/{print $2}')"
    [ -n "$COMPOSE_ID" ] || { echo "ERROR: no compose id returned" >&2; exit 1; }

    # Wait for the compose to finish
    while :; do
        STATUS="$(sudo composer-cli compose status \
            | awk -v id="$COMPOSE_ID" '$1==id{print $2}')"
        case "$STATUS" in
            FINISHED) break ;;
            FAILED)   echo "ERROR: compose ${COMPOSE_ID} FAILED" >&2
                      sudo composer-cli compose log "$COMPOSE_ID" || true
                      exit 1 ;;
            *)        sleep 20 ;;
        esac
    done

    # File extension: qcow2 -> .qcow2, image-installer -> .iso
    case "$TYPE" in
        qcow2)           EXT="qcow2" ;;
        image-installer) EXT="iso" ;;
        *)               EXT="${TYPE}.img" ;;
    esac
    OUTFILE="$RESULT_DIR/CapivaraOS-HERD-${VERSION}-${ARCH}.${EXT}"
    # 'compose image' refuses to overwrite ("exists, skipping download"),
    # so remove the earlier output (it may be root's, hence the sudo fallback).
    rm -f "$OUTFILE" 2>/dev/null || sudo rm -f "$OUTFILE"
    sudo composer-cli compose image "$COMPOSE_ID" --filename "$OUTFILE"
    echo "==> ${TYPE} ready in ${OUTFILE}"
done

echo
echo "==> Done. Images in ${RESULT_DIR}/"
ls -lh "$RESULT_DIR"
