#!/bin/bash
# =============================================================================
# publish-repo.sh: publishing pipeline of the signed Herd update repository.
# =============================================================================
# Signs the RPMs, keeps PACKAGES apart from METADATA, builds and SIGNS the
# index (repomd.xml -> repomd.xml.asc) and publishes both. Trust comes from the
# signature, not from the host (see keys/README.md).
#
# Packages and metadata are served from different places:
#   - METADATA (repodata/, a few KB, SIGNED) -> GitHub Pages
#       repo-herd.capivaraos.org/f<rel>/<arch>/<channel>/repodata/
#   - PACKAGES (.rpm) -> GitHub Releases (capivaraos/repo-herd), one tag per
#       release/arch/channel: herd-f<rel>-<arch>-<channel>
#       (e.g. herd-f45-x86_64-stable)
#
# `xml:base` links the two: `createrepo_c -u <releases-url>` records the
# package location in primary.xml (href is the bare file name, which is what
# Releases serves). The client reads the index from Pages (baseurl) and the
# packages from the Releases URL with no change to the `.repo`, and `gpgcheck`
# and `repo_gpgcheck` still apply, because trust comes from the key, not from
# where the bytes are stored.
#
# LOCAL layout:
#   out/repo/f<rel>/<arch>/<channel>/repodata/   <- Pages (pages command)
#   out/releases/f<rel>/<arch>/<channel>/*.rpm   <- Releases (release command)
#
# Flow (see docs/repo/README.md):
#   build RPM -> add (testing) -> release testing -> pages -> QA in a VM
#            -> promote -> release stable -> pages
#
# Usage:
#   # 1) sign and index into the testing channel (LOCAL; writes xml:base)
#   ./publish-repo.sh add     --rel 45 --arch x86_64 --channel testing ~/rpmbuild/RPMS/noarch/*.rpm
#   # 2) upload the channel's PACKAGES to its Release tag (network; needs gh)
#   ./publish-repo.sh release --rel 45 --arch x86_64 --channel testing
#   # 3) publish the METADATA to GitHub Pages (network; commit+push to capivaraos/repo-herd)
#   ./publish-repo.sh pages   --rel 45 --arch x86_64
#   # 4) after QA, promote testing -> stable and run release and pages for stable
#   ./publish-repo.sh promote --rel 45 --arch x86_64
#   ./publish-repo.sh release --rel 45 --arch x86_64 --channel stable
#   ./publish-repo.sh pages   --rel 45 --arch x86_64
#
# Advisories: under the shipped policy (upgrade_type = security), dnf5
# automatic updates a Herd package only when the repository lists a security
# advisory (updateinfo) for a version newer than the installed one; it then
# installs the newest version available. Record one for each security fix:
#   ./publish-repo.sh advisory --id HERD-2026-0001 --type security \
#       --severity Important --title "herd-harden: ..." [--cve CVE-2026-1234] \
#       ~/rpmbuild/RPMS/noarch/<fixed package>.rpm
# The title and description state the corrected behaviour, not the flaw.
# Advisories are attached to the STABLE channel only, by `promote` (`add`
# publishes to testing only), and the index is signed after that. An advisory
# that names a file present in the channel with a different NEVRA, or only
# some of whose packages are there, stops the run. `promote` reads advisories
# as committed in HEAD and stops on untracked, ignored or modified files
# under advisories/: commit advisories/<ID>.xml before `promote`, and push
# that commit only once the fix is in stable. An
# update without an advisory still reaches an interactive `dnf upgrade`.
#
# ORDER MATTERS when publishing: `release` (uploads the packages) runs BEFORE
# `pages` (publishes the index), so the index never points, even briefly, at a
# package that is not in Releases yet.
#
# Prerequisites: rpm-sign (rpmsign), createrepo_c (with modifyrepo_c), python3,
# gnupg2, zstd; `gh` (GitHub CLI, logged in as capivaraos-bot with write access
# to capivaraos/repo-herd) for `release`; git+rsync for `pages`.
# The private key must be available to gpg-agent, and %_gpg_name set in
# ~/.rpmmacros.
# =============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${HERD_REPO_ROOT:-${PROJECT_DIR}/out/repo}"        # METADATA tree (Pages)
REL_ROOT="${HERD_REL_ROOT:-${PROJECT_DIR}/out/releases}"      # PACKAGES staging (Releases)
# GitHub repository dedicated to Herd: Pages (metadata) and Releases (packages).
GH_REPO="${HERD_GH_REPO:-capivaraos/repo-herd}"
PAGES_REPO="${HERD_PAGES_REPO:-https://github.com/capivaraos/repo-herd.git}"
# Herd public keys. `pages` also places them at the Pages root, for anyone who
# checks signatures by hand; installed systems use the copies that
# capivaraos-herd-repos ships.
PUBKEY="${PROJECT_DIR}/keys/RPM-GPG-KEY-capivaraos-herd"
RESERVE_PUBKEY="${PROJECT_DIR}/keys/RPM-GPG-KEY-capivaraos-herd-reserve"
# Overrides for the container tests only, honoured with HERD_TEST=1.
if [ "${HERD_TEST:-0}" = 1 ]; then
    PUBKEY="${HERD_PUBKEY:-$PUBKEY}"
    RESERVE_PUBKEY="${HERD_RESERVE_PUBKEY:-$RESERVE_PUBKEY}"
fi
GPG_KEY_NAME="${HERD_GPG_NAME:-CapivaraOS Herd (repo signing key)}"
ADVISORY_DIR="${PROJECT_DIR}/advisories"
UPDATEINFO_TOOL="${PROJECT_DIR}/tools/herd-updateinfo.py"
# Where clients download packages from (the xml:base). check_xml_base always
# checks against the production value.
PROD_PKG_BASEURL="https://github.com/capivaraos/repo-herd/releases/download"
PKG_BASEURL="$PROD_PKG_BASEURL"
if [ "${HERD_TEST:-0}" = 1 ]; then
    ADVISORY_DIR="${HERD_ADVISORY_DIR:-$ADVISORY_DIR}"
    PKG_BASEURL="${HERD_PKG_BASEURL:-$PKG_BASEURL}"
fi

die() { echo "ERROR: $*" >&2; exit 1; }

# --- common argument parsing ----------------------------------------------
CMD="${1:-}"; shift || true
REL=""; ARCH="x86_64"; CHANNEL="testing"; RPMS=(); ADV=()
while [ $# -gt 0 ]; do
    case "$1" in
        --rel)     REL="$2"; shift 2;;
        --arch)    ARCH="$2"; shift 2;;
        --channel) CHANNEL="$2"; shift 2;;
        --id|--type|--severity|--title|--description|--cve)
                   [ $# -ge 2 ] || die "$1 needs a value"
                   ADV+=("$1" "$2"); shift 2;;
        *)         RPMS+=("$1"); shift;;
    esac
done
if [ "$CMD" = advisory ]; then
    [ "${#RPMS[@]}" -gt 0 ] || die "pass the fixed package(s) as .rpm files"
    command -v python3 >/dev/null || die "python3 missing (for advisory)"
    python3 -I "$UPDATEINFO_TOOL" new "$ADVISORY_DIR" "${ADV[@]}" "${RPMS[@]}"
    echo "OK: advisory written. Commit it before 'promote'; push that commit only once the fix is in stable."
    exit 0
fi
[ "${#ADV[@]}" -eq 0 ] || die "--id/--type/--severity/--title/--description/--cve are for 'advisory' only"
[ -n "$REL" ] || die "pass --rel (e.g. 45)"
case "$REL" in ''|*[!0-9]*) die "--rel must be a number (e.g. 45)";; esac
case "$ARCH" in x86_64|aarch64) ;; *) die "--arch must be x86_64 or aarch64";; esac
case "$CHANNEL" in testing|stable) ;; *) die "--channel must be testing or stable";; esac
# An out/{repo,releases}/herd/ tree is an older staging layout. Refuse to run
# on it: a new index built next to it would leave out every earlier package.
for old in "${REPO_ROOT}/herd" "${REL_ROOT}/herd"; do
    [ ! -e "$old" ] || die "old staging layout found: $old (move its f<rel>/ directories one level up first)"
done

# Metadata (Pages) and package (Releases) directories of a channel. No "herd/"
# prefix: repo-herd only holds Herd.
chan_meta() { echo "${REPO_ROOT}/f${REL}/${ARCH}/$1"; }
chan_pkgs() { echo "${REL_ROOT}/f${REL}/${ARCH}/$1"; }
# Release tag and download URL (the packages' xml:base) of a channel.
rel_tag()   { echo "herd-f${REL}-${ARCH}-$1"; }
rel_url()   { echo "${PKG_BASEURL}/$(rel_tag "$1")/"; }

# Checks a channel's repomd.xml.asc against the given public key files, in a
# temporary keyring that holds nothing else.
verify_repomd() {
    local repodata="$1"; shift
    local gh
    command -v gpg >/dev/null || die "gpg missing"
    gh="$(mktemp -d)"
    if gpg --homedir "$gh" --batch --quiet --import "$@" 2>/dev/null \
        && gpg --homedir "$gh" --batch --quiet --verify \
            "${repodata}/repomd.xml.asc" "${repodata}/repomd.xml" 2>/dev/null; then
        rm -rf "$gh"; return 0
    fi
    rm -rf "$gh"; return 1
}

# Checks that every package in a channel's primary.xml points at the
# production Releases URL of that channel (never a test or foreign URL).
check_xml_base() {
    local meta="$1" ch="$2" repomd prim dec n_loc n_base want
    repomd="$meta/repodata/repomd.xml"
    prim="$meta/$(sed -n '/<data type="primary">/,/<\/data>/s/.*<location href="\([^"]*\)".*/\1/p' "$repomd")"
    [ -f "$prim" ] || die "$repomd names no primary file present in $meta"
    case "$prim" in
        *.zst) dec="zstdcat" ;; *.gz) dec="zcat" ;; *.xz) dec="xzcat" ;; *) dec="cat" ;;
    esac
    command -v "$dec" >/dev/null || die "$dec missing (to read $prim)"
    # grep -c reads the whole stream (grep -q could exit early and, with
    # pipefail, fail the pipeline on the decompressor's SIGPIPE).
    n_loc="$("$dec" "$prim" | grep -c '<location ' || true)"
    want="${PROD_PKG_BASEURL}/$(rel_tag "$ch")/"
    n_base="$("$dec" "$prim" | grep '<location ' | grep -cF "xml:base=\"${want}\"" || true)"
    [ "${n_loc:-0}" -gt 0 ] || die "$ch primary.xml lists no packages"
    [ "$n_base" = "$n_loc" ] \
        || die "only $n_base of $n_loc packages in $ch primary.xml point at ${want}"
}

# Prints the directory to read advisories from. Outside the tests this is a
# copy of the advisories/*.xml blobs committed in HEAD, read with git cat-file
# (no export attributes apply), so only committed bytes are ever published;
# untracked, ignored or modified files under advisories/ stop the run instead
# of being left out silently.
committed_advisories() {
    local out="$1"
    if [ "${HERD_TEST:-0}" = 1 ]; then echo "$ADVISORY_DIR"; return 0; fi
    command -v git >/dev/null || die "git missing (to read advisories/)"
    # Replace refs (refs/replace/*) are ignored, and no GIT_* variable from
    # the caller's shell may point git at other objects or settings.
    local g=(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY
             -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_COMMON_DIR -u GIT_NAMESPACE
             -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_GLOBAL
             -u GIT_CONFIG_SYSTEM -u GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS=1
             git -C "$PROJECT_DIR")
    local st entry meta mode type oid path name
    st="$("${g[@]}" status --porcelain --untracked-files=all --ignored -- advisories)" \
        || die "cannot read the git status of advisories/"
    [ -z "$st" ] || die "advisories/ has uncommitted or ignored files; commit or remove them first:
$st"
    mkdir -p "$out/files"
    "${g[@]}" ls-tree -z HEAD advisories/ > "$out/tree" \
        || die "cannot list advisories/ in HEAD"
    # Each entry is "<mode> <type> <oid><TAB><path>", NUL-terminated; the path
    # is taken as it is, without trimming.
    while IFS= read -r -d '' entry; do
        meta="${entry%%$'\t'*}"; path="${entry#*$'\t'}"
        read -r mode type oid <<<"$meta"
        name="${path#advisories/}"
        [ "$type" = blob ] && [ "$mode" = 100644 ] && [[ "$name" != */* ]] \
            || die "advisories/ in HEAD holds something other than plain files: $path"
        case "$name" in *.xml) ;; *) continue ;; esac
        [[ "$name" =~ ^HERD-[0-9]{4}-[0-9]{4}\.xml$ ]] \
            || die "advisory file name is not HERD-YYYY-NNNN.xml: $path"
        "${g[@]}" cat-file blob "$oid" > "$out/files/$name" || die "cannot read $path from HEAD"
    done < "$out/tree"
    echo "$out/files"
}

sign_rpms() {
    command -v rpmsign >/dev/null || die "rpmsign missing (dnf install rpm-sign)"
    grep -q '%_gpg_name' ~/.rpmmacros 2>/dev/null \
        || die "set %_gpg_name in ~/.rpmmacros"
    for r in "$@"; do
        echo "  signing $(basename "$r")"
        rpmsign --addsign "$r" >/dev/null
    done
}

# Builds a channel's index: reads the RPMs from the PACKAGES directory
# (chan_pkgs) and writes repodata into the METADATA tree (chan_meta), with
# xml:base set to the channel's Releases URL. Then SIGNS repomd.xml, which
# repo_gpgcheck checks on the client.
build_index() {
    local ch="$1"
    command -v createrepo_c >/dev/null || die "createrepo_c missing"
    local pkgs meta url
    pkgs="$(chan_pkgs "$ch")"; meta="$(chan_meta "$ch")"; url="$(rel_url "$ch")"
    mkdir -p "$meta"
    # No signature may survive next to a repomd.xml it does not cover, even if a
    # later step fails.
    rm -f "${meta}/repodata/repomd.xml.asc"
    echo "  createrepo_c -u ${url} -o ${meta} ${pkgs}"
    createrepo_c --update --discard-additional-metadata -u "$url" -o "$meta" "$pkgs"
    # Advisories (updateinfo) are published with the STABLE channel only: a
    # public advisory goes out once the fix is in stable. createrepo_c runs with
    # --discard-additional-metadata, so an advisory that is withdrawn, or whose
    # packages are not in the channel, leaves the index.
    if [ "$ch" = stable ]; then
        command -v modifyrepo_c >/dev/null || die "modifyrepo_c missing (createrepo_c)"
        command -v python3 >/dev/null || die "python3 missing (for advisories)"
        local uidir n advdir
        uidir="$(mktemp -d)"
        advdir="$(committed_advisories "$uidir/head")" || { rm -rf "$uidir"; exit 1; }
        if ! n="$(python3 -I "$UPDATEINFO_TOOL" build "$advdir" "$pkgs" "$uidir/updateinfo.xml")"; then
            rm -rf "$uidir"; die "advisories do not match the stable packages (see above)"
        fi
        if [ "$n" -gt 0 ]; then
            echo "  attaching ${n} advisory(ies)"
            modifyrepo_c --mdtype=updateinfo "$uidir/updateinfo.xml" "${meta}/repodata" >/dev/null \
                || { rm -rf "$uidir"; die "modifyrepo_c failed"; }
        else
            echo "  no advisory for stable"
        fi
        rm -rf "$uidir"
    fi
    echo "  signing repomd.xml"
    gpg --detach-sign --armor -u "$GPG_KEY_NAME" "${meta}/repodata/repomd.xml"
}

case "$CMD" in
    add)
        [ "$CHANNEL" = testing ] \
            || die "add publishes to testing only; stable is reached through 'promote'"
        [ "${#RPMS[@]}" -gt 0 ] || die "pass at least one .rpm"
        PKGS="$(chan_pkgs "$CHANNEL")"; mkdir -p "$PKGS"
        sign_rpms "${RPMS[@]}"
        for r in "${RPMS[@]}"; do cp -f "$r" "$PKGS/"; done
        build_index "$CHANNEL"
        echo "OK: ${#RPMS[@]} package(s) indexed in ${CHANNEL}."
        echo "    next: './publish-repo.sh release --rel ${REL} --arch ${ARCH} --channel ${CHANNEL}', then 'pages'."
        ;;
    promote)
        SRC="$(chan_pkgs testing)"; DST="$(chan_pkgs stable)"
        ls "$SRC"/*.rpm >/dev/null 2>&1 || die "testing channel is empty: $SRC"
        mkdir -p "$DST"
        echo "promoting testing -> stable (f${REL}/${ARCH})"
        # Copies the (already signed) RPMs from testing to stable and rebuilds
        # the stable index (xml:base points at the stable Release tag).
        find "$SRC" -maxdepth 1 -name '*.rpm' -exec cp -f {} "$DST/" \;
        build_index stable
        echo "OK: stable reindexed. Next: 'release --channel stable', then 'pages'."
        ;;
    release)
        # Uploads the channel's PACKAGES to its Release tag.
        PKGS="$(chan_pkgs "$CHANNEL")"
        ls "$PKGS"/*.rpm >/dev/null 2>&1 || die "no .rpm in $PKGS (run 'add' or 'promote' first)"
        # Upload only packages whose channel index is signed: after a failed
        # 'add' or 'promote' the index has no valid signature.
        verify_repomd "$(chan_meta "$CHANNEL")/repodata" "$PUBKEY" "$RESERVE_PUBKEY" \
            || die "the ${CHANNEL} index is not signed by a Herd key; rerun 'add' or 'promote' first"
        command -v gh >/dev/null || die "gh missing (GitHub CLI; log in as capivaraos-bot)"
        TAG="$(rel_tag "$CHANNEL")"
        # GitHub Releases rejects assets over 2 GiB.
        big="$(find "$PKGS" -name '*.rpm' -size +2G -printf '%f ' 2>/dev/null)"
        [ -z "$big" ] || die "RPM(s) over 2 GiB (the Releases limit): $big"
        if ! gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
            echo "creating release ${TAG} in ${GH_REPO}…"
            gh release create "$TAG" --repo "$GH_REPO" \
                --title "Herd f${REL} ${ARCH} — canal ${CHANNEL}" \
                --notes "CapivaraOS Herd packages (${CHANNEL} channel, Fedora ${REL}, ${ARCH}). The signed metadata is at https://repo-herd.capivaraos.org/f${REL}/${ARCH}/${CHANNEL}/. Trust comes from the GPG signature, not from the host."
        fi
        n="$(find "$PKGS" -maxdepth 1 -name '*.rpm' | wc -l)"
        echo "uploading ${n} package(s) to ${TAG} (--clobber)…"
        # --clobber: replaces assets of the same name (the same NEVRA published again).
        gh release upload "$TAG" "$PKGS"/*.rpm --repo "$GH_REPO" --clobber
        echo "OK: packages at https://github.com/${GH_REPO}/releases/tag/${TAG}"
        ;;
    pages)
        # Publishes ONLY the signed METADATA to GitHub Pages (the packages went to
        # Releases through 'release'). Clones Pages, syncs only f<rel>/<arch> (the
        # root index.html, CNAME, .nojekyll and public keys stay), commits and
        # pushes. A single commit is atomic.
        command -v git >/dev/null   || die "git missing (for pages)"
        command -v rsync >/dev/null || die "rsync missing (for pages)"
        BASE="${REPO_ROOT}/f${REL}/${ARCH}"
        [ -d "$BASE" ] || die "nothing to publish in $BASE (run 'add' or 'promote' first)"
        # Packages never go to Pages: stop if any .rpm is in the metadata tree.
        stray="$(find "$BASE" -name '*.rpm' -printf '%f ' 2>/dev/null)"
        [ -z "$stray" ] || die "metadata tree contains .rpm files: $stray"
        for rd in "$BASE"/*/repodata; do
            [ -f "$rd/repomd.xml.asc" ] && verify_repomd "$rd" "$PUBKEY" "$RESERVE_PUBKEY" \
                || die "$rd: repomd.xml.asc missing or not valid for the Herd keys"
            ch="$(basename "$(dirname "$rd")")"
            case "$ch" in testing|stable) ;; *) die "unexpected channel directory: $rd";; esac
            check_xml_base "$(dirname "$rd")" "$ch"
        done
        WORK="$(mktemp -d)"
        echo "cloning ${PAGES_REPO}…"
        git clone --quiet --depth 1 "$PAGES_REPO" "$WORK" || die "cannot clone $PAGES_REPO"
        DST="$WORK/f${REL}/${ARCH}"
        mkdir -p "$DST"
        # --delete limited to f<rel>/<arch>: the site root stays as it is.
        rsync -a --delete "$BASE/" "$DST/"
        # Herd public keys at the Pages ROOT, for anyone who checks signatures by
        # hand (installed systems use the keys capivaraos-herd-repos ships).
        # Idempotent.
        if [ -f "$PUBKEY" ]; then
            cp -f "$PUBKEY" "$WORK/RPM-GPG-KEY-capivaraos-herd"
        else
            echo "WARNING: public key not found at $PUBKEY; publish it at the Pages root." >&2
        fi
        if [ -f "$RESERVE_PUBKEY" ]; then
            cp -f "$RESERVE_PUBKEY" "$WORK/RPM-GPG-KEY-capivaraos-herd-reserve"
        else
            echo "WARNING: reserve public key not found at $RESERVE_PUBKEY" >&2
        fi
        ( cd "$WORK"
          git add -A
          if git diff --cached --quiet; then
              echo "nothing changed, no commit."; exit 0
          fi
          git -c user.name="CapivaraOS Bot" \
              -c user.email="capivaraos-bot@users.noreply.github.com" \
              commit -q -m "publish: f${REL}/${ARCH} metadata ($(date -u +%FT%TZ))"
          git push --quiet )
        rm -rf "$WORK"
        echo "OK: metadata published at https://repo-herd.capivaraos.org/f${REL}/${ARCH}/"
        ;;
    *)
        die "invalid command. Use: advisory | add | release | pages | promote (see the header)"
        ;;
esac
