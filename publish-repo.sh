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
# Destino de PRODUÇÃO: Cloudflare R2 (egress grátis; ideal p/ repo = muito
# download, pouco storage). Configure o remote uma vez com:
#   rclone config   # tipo "s3", provider "Cloudflare", endpoint do R2, chaves
# e aponte o domínio repo.capivaraos.org para o bucket (custom domain do R2).
# BOOTSTRAP alternativo (enquanto não há R2): Fedora Copr, grátis, assina/hospeda.
RCLONE_REMOTE="${HERD_RCLONE_REMOTE:-r2:capivaraos-herd}" # destino do upload
GPG_KEY_NAME="${HERD_GPG_NAME:-CapivaraOS Herd (repo signing key)}"
# Cache na CDN: RPMs são imutáveis (cache longo); o índice muda a cada publicação
# e NÃO pode ficar velho na borda (cache curto + revalidação). Evita cliente
# baixar repomd antigo apontando p/ pacote que já saiu.
CACHE_RPM="${HERD_CACHE_RPM:-public, max-age=31536000, immutable}"
CACHE_META="${HERD_CACHE_META:-public, max-age=300, must-revalidate}"

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
        DEST="${RCLONE_REMOTE}/herd/f${REL}/${ARCH}"
        echo "upload ${BASE} -> ${DEST}"
        # Ordem importa: sobem-se os RPMs (imutáveis, cache longo) ANTES do índice,
        # senão o repodata poderia, por segundos, apontar p/ um RPM ainda ausente.
        rclone copy --checksum --exclude 'repodata/**' \
            --header-upload "Cache-Control: ${CACHE_RPM}" \
            "$BASE" "$DEST"
        # Índice por último, com cache curto (a borda não pode servir repomd velho).
        for ch in stable testing; do
            [ -d "$BASE/$ch/repodata" ] || continue
            rclone copy --checksum \
                --header-upload "Cache-Control: ${CACHE_META}" \
                "$BASE/$ch/repodata" "$DEST/$ch/repodata"
        done
        echo "OK: upload concluído"
        ;;
    *)
        die "comando inválido. Use: add | promote | upload (ver cabeçalho)"
        ;;
esac
