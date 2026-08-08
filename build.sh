#!/bin/bash
# =============================================================================
# Build das imagens do CapivaraOS HERD Community via osbuild / Image Builder.
# =============================================================================
# Produz, a partir de blueprints/capivaraos-herd.toml (fonte de verdade):
#   - qcow2            (nuvem/VM, cloud-init)
#   - image-installer  (ISO instalador headless)
# para a arquitetura DO HOST. Para gerar aarch64, rode este script num host/VM
# aarch64 (o osbuild compõe para a arch do host).
#
# PRÉ-REQUISITOS:
#   - Host Fedora 45 (HERD nasce no F45). Nesta fase pré-GA, use um host/VM com
#     o Fedora 45 pré-release (Branched/Rawhide).
#   - osbuild-composer + composer-cli instalados e o serviço ativo:
#       sudo dnf install -y osbuild-composer composer-cli
#       sudo systemctl enable --now osbuild-composer.socket
#   - O RPM capivaraos-herd-branding já construído (rpm/build-rpm.sh), servido
#     por um repositório local (createrepo_c) — ver PREPARO abaixo.
#
# Uso:
#   ./build.sh                # gera qcow2 + iso
#   ./build.sh qcow2          # só a qcow2
#   ./build.sh image-installer# só a ISO
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINT_TOML="$SCRIPT_DIR/blueprints/capivaraos-herd.toml"
BLUEPRINT_NAME="capivaraos-herd"
VERSION="$(awk -F'"' '/^version[[:space:]]*=/{print $2; exit}' "$BLUEPRINT_TOML")"
ARCH="$(uname -m)"
RESULT_DIR="$SCRIPT_DIR/out"
BRANDING_REPO="/var/tmp/capivaraos-herd-repo"   # repo local com o RPM de branding

# Tipos de imagem a construir (default: os dois)
TYPES=("$@")
[ ${#TYPES[@]} -eq 0 ] && TYPES=(qcow2 image-installer)

echo "==> CapivaraOS HERD Community ${VERSION} (${ARCH})"

# ── Sanidade: estamos num host F45? ─────────────────────────────────────────
OSVER="$(. /etc/os-release && echo "${VERSION_ID:-?}")"
if [ "$OSVER" != "45" ]; then
    echo "AVISO: host é Fedora ${OSVER}, não 45. O HERD nasce no F45; a" >&2
    echo "       composição deve rodar num host/VM Fedora 45." >&2
fi

command -v composer-cli >/dev/null || {
    echo "ERRO: composer-cli não encontrado. Instale osbuild-composer + composer-cli." >&2
    exit 1
}

# ── 1. Source do composer com o branding do HERD ────────────────────────────
# Aponta SÓ para o nosso repo local, garantindo o RPM correto do HERD (evita a
# armadilha de branding de outra spin — BUG-30).
if [ -d "$BRANDING_REPO" ]; then
    SRC_TOML="$(mktemp)"
    cat > "$SRC_TOML" <<EOF
id = "capivaraos-herd-branding"
name = "CapivaraOS HERD branding (local)"
type = "yum-baseurl"
url = "file://${BRANDING_REPO}"
check_gpg = false
check_ssl = false
system = false
EOF
    sudo composer-cli sources add "$SRC_TOML"
    rm -f "$SRC_TOML"
else
    echo "AVISO: repo de branding não encontrado em ${BRANDING_REPO}." >&2
    echo "       Rode rpm/build-rpm.sh e createrepo_c antes (ver README)." >&2
fi

# ── 2. Registra/atualiza a blueprint ────────────────────────────────────────
sudo composer-cli blueprints push "$BLUEPRINT_TOML"
sudo composer-cli blueprints depsolve "$BLUEPRINT_NAME"

# ── 3. Compõe cada tipo de imagem ───────────────────────────────────────────
mkdir -p "$RESULT_DIR"
for TYPE in "${TYPES[@]}"; do
    echo "==> Compondo ${TYPE}..."
    COMPOSE_ID="$(sudo composer-cli compose start "$BLUEPRINT_NAME" "$TYPE" \
        | awk '/Compose/{print $2}')"
    [ -n "$COMPOSE_ID" ] || { echo "ERRO: não obtive o compose id" >&2; exit 1; }

    # Espera a composição terminar
    while :; do
        STATUS="$(sudo composer-cli compose status \
            | awk -v id="$COMPOSE_ID" '$1==id{print $2}')"
        case "$STATUS" in
            FINISHED) break ;;
            FAILED)   echo "ERRO: compose ${COMPOSE_ID} FALHOU" >&2
                      sudo composer-cli compose log "$COMPOSE_ID" || true
                      exit 1 ;;
            *)        sleep 20 ;;
        esac
    done

    sudo composer-cli compose image "$COMPOSE_ID" --filename \
        "$RESULT_DIR/CapivaraOS-HERD-${VERSION}-${ARCH}.${TYPE}.img"
    echo "==> ${TYPE} pronto em ${RESULT_DIR}/"
done

echo
echo "==> Concluído. Imagens em ${RESULT_DIR}/"
ls -lh "$RESULT_DIR"
