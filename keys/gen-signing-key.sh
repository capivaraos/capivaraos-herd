#!/bin/bash
# =============================================================================
# Cerimônia de chave de ASSINATURA do repositório do CapivaraOS Herd (PROD-104).
# =============================================================================
# Gera o par de chaves GPG que assina os RPMs e os metadados do repositório.
#
# ATENÇÃO — EXECUTE OFFLINE, uma única vez, numa máquina de confiança (de
# preferência air-gapped ou um live USB dedicado). A chave PRIVADA resultante é
# o ativo mais sensível do projeto: quem a tem pode empurrar update malicioso
# para TODOS os servidores Herd. Ela NUNCA deve:
#   - ser commitada neste (ou em qualquer) repositório;
#   - ficar numa máquina exposta à internet sem necessidade;
#   - ser copiada para o servidor/CDN que hospeda o repo.
#
# Depois de gerar: exporte a PÚBLICA para o repo (é o que o pacote
# capivaraos-herd-repos distribui) e guarde a PRIVADA em HSM/YubiKey ou num
# cofre (Bitwarden) com passphrase forte. Ver keys/README.md.
# =============================================================================
set -euo pipefail

KEY_NAME="CapivaraOS Herd (repo signing key)"
KEY_EMAIL="capivaraos-bot@users.noreply.github.com"
KEY_COMMENT="https://capivaraos.org"
OUTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GNUPGHOME_TMP="$(mktemp -d)"
export GNUPGHOME="$GNUPGHOME_TMP"
chmod 700 "$GNUPGHOME_TMP"

echo "== Gerando chave de assinatura do repositório Herd =="
echo "   GNUPGHOME temporário: $GNUPGHOME_TMP"
echo "   (a chave privada NÃO será deixada no seu ~/.gnupg)"
echo

# RSA 4096 + SHA-512: universalmente aceito pelo rpm/createrepo em qualquer
# distro/ferramenta (ed25519 é ótimo mas nem toda cadeia legada valida). Sem
# data de expiração na chave-mestra; rotação é decisão de processo (ver README).
cat > "${GNUPGHOME_TMP}/keyparams" <<EOF
%echo Gerando par RSA 4096 para assinatura de RPM/metadados...
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: ${KEY_NAME}
Name-Comment: ${KEY_COMMENT}
Name-Email: ${KEY_EMAIL}
Expire-Date: 0
%ask-passphrase
%commit
%echo Concluído.
EOF

gpg --batch --full-gen-key "${GNUPGHOME_TMP}/keyparams"

KEYID="$(gpg --list-keys --with-colons "$KEY_EMAIL" | awk -F: '/^pub:/{print $5; exit}')"
echo
echo "== Chave gerada: ${KEYID} =="

# Exporta a PÚBLICA (ASCII-armored) para dentro do repo — este arquivo PODE ser
# commitado; é o que o pacote capivaraos-herd-repos entrega aos clientes.
PUB_OUT="${OUTDIR}/RPM-GPG-KEY-capivaraos-herd"
gpg --armor --export "$KEYID" > "$PUB_OUT"
echo "Pública exportada -> ${PUB_OUT}  (COMMITAR este arquivo)"

# Exporta a PRIVADA para um arquivo FORA do repo, para você mover ao cofre/HSM.
PRIV_OUT="${HOME}/capivaraos-herd-repo-signing-PRIVATE-${KEYID}.asc"
gpg --armor --export-secret-keys "$KEYID" > "$PRIV_OUT"
chmod 600 "$PRIV_OUT"

cat <<EOF

== PRÓXIMOS PASSOS (faça agora, ainda offline) ==
1. GUARDE a chave privada com segurança e APAGUE o arquivo temporário:
     ${PRIV_OUT}
   -> importe num HSM/YubiKey OU cole no cofre (Bitwarden) e destrua o arquivo:
        shred -u "${PRIV_OUT}"    # (ou apague com segurança)
2. Anote o Key ID/fingerprint (publique o fingerprint na página de Segurança):
     gpg --fingerprint ${KEYID}
3. Commite APENAS a pública: keys/RPM-GPG-KEY-capivaraos-herd
4. Na máquina de PUBLICAÇÃO (assina o repo), importe a privada só quando for
   assinar, via publish-repo.sh, e configure %_gpg_name (ver keys/README.md).

Limpando o GNUPGHOME temporário...
EOF
rm -rf "$GNUPGHOME_TMP"
echo "Feito. NÃO esqueça de proteger a chave privada."
