#!/bin/bash
# =============================================================================
# publish-repo.sh — pipeline de publicação do repositório assinado do Herd.
# =============================================================================
# PROD-104. Assina RPMs, monta o layout por release/canal, gera e ASSINA o índice
# do repositório (repomd.xml -> repomd.xml.asc) e, opcionalmente, sobe para o
# object storage. A confiança vem da assinatura, não do host (ver keys/README.md).
#
# Layout publicado (raiz -> repo.capivaraos.org/herd/):
#   herd/f<rel>/<arch>/testing/     canal de QA (repo enabled=0 no cliente)
#   herd/f<rel>/<arch>/stable/      canal de produção (enabled=1)
#     └── repodata/{repomd.xml,repomd.xml.asc,...}
#
# Fluxo recomendado:
#   build RPM  ->  add ao TESTING  ->  QA em VM  ->  PROMOTE p/ STABLE  ->  upload
#
# Uso:
#   # 1) adicionar RPMs ao canal testing (assina + createrepo + assina repomd)
#   ./publish-repo.sh add    --rel 44 --arch x86_64 --channel testing ~/rpmbuild/RPMS/noarch/*.rpm
#   # 2) promover o que passou no QA para stable
#   ./publish-repo.sh promote --rel 44 --arch x86_64
#   # 3) subir a árvore para o object storage (rclone remote configurável)
#   ./publish-repo.sh upload  --rel 44 --arch x86_64
#
# Pré-req: rpm-sign (rpmsign), createrepo_c, gnupg2; rclone p/ upload. A chave
# privada precisa estar disponível ao gpg-agent e o %_gpg_name em ~/.rpmmacros
# (ver keys/README.md).
# =============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${HERD_REPO_ROOT:-${PROJECT_DIR}/out/repo}"   # raiz local do repo
RCLONE_REMOTE="${HERD_RCLONE_REMOTE:-r2:capivaraos-herd}" # destino do upload
GPG_KEY_NAME="${HERD_GPG_NAME:-CapivaraOS Herd (repo signing key)}"

die() { echo "ERRO: $*" >&2; exit 1; }

# --- parse comum ------------------------------------------------------------
CMD="${1:-}"; shift || true
REL=""; ARCH="x86_64"; CHANNEL="testing"; RPMS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --rel)     REL="$2"; shift 2;;
        --arch)    ARCH="$2"; shift 2;;
        --channel) CHANNEL="$2"; shift 2;;
        *)         RPMS+=("$1"); shift;;
    esac
done
[ -n "$REL" ] || die "informe --rel (ex.: 44)"
case "$CHANNEL" in testing|stable) ;; *) die "--channel deve ser testing ou stable";; esac

chan_dir() { echo "${REPO_ROOT}/herd/f${REL}/${ARCH}/$1"; }

sign_rpms() {
    command -v rpmsign >/dev/null || die "rpmsign ausente (dnf install rpm-sign)"
    grep -q '%_gpg_name' ~/.rpmmacros 2>/dev/null \
        || die "configure %_gpg_name em ~/.rpmmacros (ver keys/README.md)"
    for r in "$@"; do
        echo "  assinando $(basename "$r")"
        rpmsign --addsign "$r" >/dev/null
    done
}

build_index() {
    local dir="$1"
    command -v createrepo_c >/dev/null || die "createrepo_c ausente"
    echo "  createrepo_c $dir"
    createrepo_c --update "$dir"
    # Assina o índice (repo_gpgcheck no cliente valida ISTO).
    echo "  assinando repomd.xml"
    rm -f "${dir}/repodata/repomd.xml.asc"
    gpg --detach-sign --armor -u "$GPG_KEY_NAME" "${dir}/repodata/repomd.xml"
}

case "$CMD" in
    add)
        [ "${#RPMS[@]}" -gt 0 ] || die "passe ao menos um .rpm"
        DIR="$(chan_dir "$CHANNEL")"; mkdir -p "$DIR"
        sign_rpms "${RPMS[@]}"
        for r in "${RPMS[@]}"; do cp -f "$r" "$DIR/"; done
        build_index "$DIR"
        echo "OK: ${#RPMS[@]} pacote(s) em ${CHANNEL} (${DIR})"
        ;;
    promote)
        SRC="$(chan_dir testing)"; DST="$(chan_dir stable)"
        [ -d "$SRC" ] || die "canal testing vazio: $SRC"
        mkdir -p "$DST"
        echo "promovendo testing -> stable (f${REL}/${ARCH})"
        # Copia os RPMs (já assinados) do testing p/ stable e reindexa o stable.
        find "$SRC" -maxdepth 1 -name '*.rpm' -exec cp -f {} "$DST/" \;
        build_index "$DST"
        echo "OK: stable atualizado (${DST})"
        ;;
    upload)
        command -v rclone >/dev/null || die "rclone ausente (para o upload)"
        BASE="${REPO_ROOT}/herd/f${REL}/${ARCH}"
        [ -d "$BASE" ] || die "nada para subir em $BASE"
        echo "upload ${BASE} -> ${RCLONE_REMOTE}/herd/f${REL}/${ARCH}"
        # --checksum: sobe só o que mudou; repodata primeiro poderia deixar
        # metadado apontando p/ RPM ausente — então subimos RPMs ANTES do índice.
        rclone copy --checksum --exclude 'repodata/**' \
            "$BASE" "${RCLONE_REMOTE}/herd/f${REL}/${ARCH}"
        rclone copy --checksum \
            "$BASE/stable/repodata"  "${RCLONE_REMOTE}/herd/f${REL}/${ARCH}/stable/repodata"  2>/dev/null || true
        rclone copy --checksum \
            "$BASE/testing/repodata" "${RCLONE_REMOTE}/herd/f${REL}/${ARCH}/testing/repodata" 2>/dev/null || true
        echo "OK: upload concluído"
        ;;
    *)
        die "comando inválido. Use: add | promote | upload (ver cabeçalho)"
        ;;
esac
