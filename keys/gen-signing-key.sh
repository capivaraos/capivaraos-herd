#!/bin/bash
# =============================================================================
# Generates the CapivaraOS Herd repository signing key pair.
# =============================================================================
# Generates the GPG key pair that signs the repository's RPMs and metadata.
#
# Run once. Whoever holds the resulting PRIVATE key can sign an update that
# every Herd system trusting this key accepts, so it never goes into this
# repository.
#
# Afterwards: commit the PUBLIC key (the capivaraos-herd-repos package ships
# it). The private key never goes into the repository. See keys/README.md.
# =============================================================================
set -euo pipefail
# Every file this script creates is readable by its owner only, from the
# moment it is created (the public key is opened up afterwards), and no
# redirection replaces an existing regular file or follows a symlink to one.
umask 077
set -o noclobber

KEY_NAME="CapivaraOS Herd (repo signing key)"
KEY_EMAIL="capivaraos-bot@users.noreply.github.com"
KEY_COMMENT="https://capivaraos.org"
OUTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUB_OUT="${OUTDIR}/RPM-GPG-KEY-capivaraos-herd"
PRIV_OUT=""
REV_OUT=""
PUB_WRITTEN=0

# Never replace the committed public key: a new one would become the trust
# anchor that capivaraos-herd-repos ships.
if [ -e "$PUB_OUT" ] || [ -L "$PUB_OUT" ]; then
    echo "ERROR: ${PUB_OUT} already exists; this script does not replace it." >&2
    exit 1
fi

GNUPGHOME_TMP="$(mktemp -d)"
export GNUPGHOME="$GNUPGHOME_TMP"

# On any exit: stop the GnuPG daemons of the temporary home and remove it. If
# the run stopped early, say which secret files were already written. The
# original exit status is kept.
cleanup() {
    local rc=$?
    gpgconf --homedir "$GNUPGHOME_TMP" --kill all 2>/dev/null || true
    rm -rf "$GNUPGHOME_TMP"
    if [ "$rc" -ne 0 ]; then
        echo "ERROR: the key generation stopped (exit ${rc})." >&2
        for f in "$PRIV_OUT" "$REV_OUT"; do
            [ -n "$f" ] && [ -e "$f" ] && echo "  A partial key file remains: $f" >&2
        done
        if [ "$PUB_WRITTEN" = 1 ]; then
            echo "  Delete ${PUB_OUT} before running this script again." >&2
        fi
    fi
    exit "$rc"
}
trap cleanup EXIT

# Refuses to write over an existing file or symlink.
new_file() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        echo "ERROR: $1 already exists; move it away first." >&2
        exit 1
    fi
}

echo "== Generating the Herd repository signing key =="
echo "   Temporary GNUPGHOME: $GNUPGHOME_TMP"
echo "   (the private key is NOT left in your ~/.gnupg)"
echo

# RSA 4096, the type of the current Herd key (C852 6722 ... 85C0); older tool
# chains may not verify ed25519 signatures. The digest for RPM signatures is
# set by %_gpg_digest_algo in ~/.rpmmacros. The primary key has no expiry
# date; rotation is covered in keys/README.md.
cat > "${GNUPGHOME_TMP}/keyparams" <<EOF
%echo Generating an RSA 4096 key pair to sign RPMs and metadata...
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: ${KEY_NAME}
Name-Comment: ${KEY_COMMENT}
Name-Email: ${KEY_EMAIL}
Expire-Date: 0
%ask-passphrase
%commit
%echo Done.
EOF

gpg --batch --full-gen-key "${GNUPGHOME_TMP}/keyparams"

KEYID="$(gpg --list-keys --with-colons "$KEY_EMAIL" | awk -F: '/^pub:/{print $5; exit}')"
FPR="$(gpg --list-keys --with-colons "$KEY_EMAIL" | awk -F: '/^fpr:/{print $10; exit}')"
[ -n "$KEYID" ] && [ -n "$FPR" ] || { echo "ERROR: cannot read the new key" >&2; exit 1; }
echo
echo "== Key generated: ${KEYID} =="

# Exports the PUBLIC key (ASCII-armored) into the repository. This file may be
# committed; the capivaraos-herd-repos package ships it to clients.
# Each output file is opened once, as a new file, and written through that
# descriptor; a failed export still reports the file.
exec 3> "$PUB_OUT"
PUB_WRITTEN=1
gpg --armor --export "$KEYID" >&3
exec 3>&-
chmod 644 "$PUB_OUT"
echo "Public key exported -> ${PUB_OUT}  (COMMIT this file)"

# Exports the PRIVATE key to a file OUTSIDE the repository.
# The name is recorded only once the file is known to be new, so the exit
# message never names a file this run did not write.
f="${HOME}/capivaraos-herd-repo-signing-PRIVATE-${KEYID}.asc"
new_file "$f"
exec 3> "$f"
PRIV_OUT="$f"
gpg --armor --export-secret-keys "$KEYID" >&3
exec 3>&-

# gpg wrote a revocation certificate when it generated the key; copy it out
# too, before the temporary GNUPGHOME is removed.
f="${HOME}/capivaraos-herd-repo-signing-REVOCATION-${KEYID}.rev"
new_file "$f"
exec 3> "$f"
REV_OUT="$f"
cat "${GNUPGHOME_TMP}/openpgp-revocs.d/${FPR}.rev" >&3
exec 3>&-

cat <<EOF

== NEXT STEPS (do them now) ==
1. The private key and its revocation certificate were written to:
     ${PRIV_OUT}
     ${REV_OUT}
2. Record the key ID and fingerprint, and publish the fingerprint on the
   Security page:
     ${FPR}
3. Commit ONLY the public key: keys/RPM-GPG-KEY-capivaraos-herd

EOF
echo "Done. Protect the private key."
