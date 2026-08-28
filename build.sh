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
#   - Host Fedora 44 (HERD 1.x = F44, mesma base das spins). Builda direto na
#     máquina de dev — sem VM. O Fedora 45 fica para a geração 2 (HERD 2.x).
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

echo "==> Herd by CapivaraOS ${VERSION} (${ARCH})"

# ── Sanidade: estamos num host F44? ─────────────────────────────────────────
# osbuild compõe para o release do host; HERD 1.x tem base F44.
OSVER="$(. /etc/os-release && echo "${VERSION_ID:-?}")"
if [ "$OSVER" != "44" ]; then
    echo "AVISO: host é Fedora ${OSVER}, não 44. O HERD 1.x tem base F44; a" >&2
    echo "       imagem sairia sobre F${OSVER}. Rode num host Fedora 44." >&2
fi

command -v composer-cli >/dev/null || {
    echo "ERRO: composer-cli não encontrado. Instale osbuild-composer + composer-cli." >&2
    exit 1
}

# ── 1. Source do composer com o branding do HERD (servido por HTTP local) ───
# IMPORTANTE: o osbuild baixa as fontes via org.osbuild.curl. Um source
# `file://` faz o parser de resultado do curl não registrar o item (o curl não
# devolve status HTTP p/ file://) → lista de resultados vazia → o osbuild
# estoura `IndexError` em sources.py e a composição falha com "did not return
# any output". Por isso servimos o repo de branding por HTTP local (forma
# suportada). Aponta SÓ para o RPM correto do HERD (evita branding de outra
# spin — BUG-30).
HTTP_PID=""
cleanup() { [ -n "$HTTP_PID" ] && kill "$HTTP_PID" 2>/dev/null || true; }
trap cleanup EXIT

if [ -d "$BRANDING_REPO" ]; then
    BRANDING_PORT="${BRANDING_PORT:-8099}"
    python3 -m http.server "$BRANDING_PORT" --bind 127.0.0.1 \
        --directory "$BRANDING_REPO" >/dev/null 2>&1 &
    HTTP_PID=$!

    # Espera o servidor responder antes de registrar o source.
    for _ in $(seq 1 20); do
        if curl -sf "http://127.0.0.1:${BRANDING_PORT}/repodata/repomd.xml" -o /dev/null; then
            break
        fi
        sleep 0.5
    done
    curl -sf "http://127.0.0.1:${BRANDING_PORT}/repodata/repomd.xml" -o /dev/null || {
        echo "ERRO: servidor HTTP do branding não respondeu na porta ${BRANDING_PORT}." >&2
        echo "      (defina BRANDING_PORT=<livre> se 8099 estiver em uso.)" >&2
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
    # Remove um source homônimo antigo (ex.: file:// de um run anterior) para
    # garantir que a URL HTTP substitua de fato.
    sudo composer-cli sources delete capivaraos-herd-branding 2>/dev/null || true
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

    # Extensão amigável: qcow2 -> .qcow2, image-installer -> .iso
    case "$TYPE" in
        qcow2)           EXT="qcow2" ;;
        image-installer) EXT="iso" ;;
        *)               EXT="${TYPE}.img" ;;
    esac
    OUTFILE="$RESULT_DIR/CapivaraOS-HERD-${VERSION}-${ARCH}.${EXT}"
    # 'compose image' se recusa a sobrescrever ("exists, skipping download"),
    # então removemos a saída anterior (pode ser root, daí o fallback com sudo).
    rm -f "$OUTFILE" 2>/dev/null || sudo rm -f "$OUTFILE"
    sudo composer-cli compose image "$COMPOSE_ID" --filename "$OUTFILE"
    echo "==> ${TYPE} pronto em ${OUTFILE}"
done

echo
echo "==> Concluído. Imagens em ${RESULT_DIR}/"
ls -lh "$RESULT_DIR"
