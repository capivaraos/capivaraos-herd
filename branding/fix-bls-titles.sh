#!/bin/sh
# =============================================================================
# Corrige os títulos das entradas BLS do GRUB para a marca do CapivaraOS HERD.
# =============================================================================
# O kernel-install grava o título da entrada BLS a partir do os-release NO
# MOMENTO em que o kernel é instalado — que, tanto no osbuild (qcow2) quanto no
# Anaconda (ISO), acontece ANTES de o nosso os-release entrar no lugar do
# Fedora. E o kernel-install NÃO reescreve uma entrada já existente. Resultado:
# o menu de boot fica "Fedora Linux (<kver>) 44 (Cloud Edition)".
#
# Este script reescreve a linha 'title' de TODAS as entradas, derivando
# NAME/VERSION do /etc/os-release e preservando o primeiro token entre
# parênteses (a versão do kernel nas entradas normais; "0-rescue-<id>" na de
# recuperação). Só toca no texto do título — não mexe em kernel/initramfs.
#
# Single source of this fix: called from %posttrans (osbuild/qcow2 path),
# %transfiletriggerin (updates that rewrite os-release) and the kickstart %post
# (ISO/Anaconda path). Idempotent: skips entries that already carry our NAME.
# =============================================================================
set -eu

[ -r /etc/os-release ] || exit 0
# shellcheck disable=SC1091
. /etc/os-release

for e in /boot/loader/entries/*.conf; do
    [ -f "$e" ] || continue
    # Já está com a nossa marca? nada a fazer (idempotência).
    grep -q "^title ${NAME} " "$e" && continue
    # Primeiro token entre parênteses: <kver> (normal) ou 0-rescue-<id> (rescue).
    tok="$(sed -n 's/^title [^(]*(\([^)]*\)).*/\1/p' "$e")"
    if [ -n "$tok" ]; then
        sed -i "s|^title .*|title ${NAME} (${tok}) ${VERSION}|" "$e"
    else
        sed -i "s|^title .*|title ${NAME} ${VERSION}|" "$e"
    fi
done
exit 0
