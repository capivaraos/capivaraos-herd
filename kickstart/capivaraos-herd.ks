# =============================================================================
# Kickstart do CapivaraOS HERD Community — instalador de servidor headless.
# =============================================================================
# PARCIAL de propósito: define o PERFIL do sistema (locale, timezone, rede,
# firewall, serviços, hardening, pacotes) mas deixa DISCO e USUÁRIO/ROOT
# INTERATIVOS — o admin decide na hora da instalação (comportamento esperado de
# um instalador distribuível).
#
# Espelha o perfil da blueprint osbuild (blueprints/capivaraos-herd.toml).
# MANTER OS DOIS EM SINCRONIA (ver PROD-66/PROD-41). Consolidação futura: mover
# o hardening SSH para dentro do RPM capivaraos-herd-branding, fonte única.
#
# A origem dos pacotes é o repo OFFLINE embutido na ISO — o Anaconda é apontado
# a ele pela linha de comando inst.repo=hd:LABEL=<volid>:/repo (ver build-iso.sh).
# =============================================================================

text

# ── Localização ─────────────────────────────────────────────────────────────
lang pt_BR.UTF-8 --addsupport=en_US.UTF-8
keyboard --vckeymap=br-abnt2 --xlayouts=''
timezone America/Sao_Paulo --utc

# ── Rede: DHCP por padrão (admin ajusta na instalação ou depois) ─────────────
network --bootproto=dhcp --activate

# ── Segurança / serviços (espelha a blueprint) ──────────────────────────────
firewall --enabled --service=ssh,cockpit
selinux --enforcing
services --enabled=sshd,chronyd,firewalld,cloud-init.target,cockpit.socket

# ── Bootloader ──────────────────────────────────────────────────────────────
bootloader --location=mbr

# DISCO: interativo — sem clearpart/part/autopart, o admin escolhe o destino.
# USUÁRIO/ROOT: interativo — sem rootpw/user, o admin cria na instalação.
# NB (PROD-41): PasswordAuthentication no exige chave SSH; um usuário criado só
# com senha loga no CONSOLE (físico/IPMI) e adiciona a chave depois.

%packages
@core
kernel
capivaraos-herd-branding
cloud-init
qemu-guest-agent
openssh-server
firewalld
chrony
cockpit
glibc-langpack-pt
glibc-langpack-en
%end

# ── Hardening SSH — espelha o drop-in da blueprint (customizations.files) ────
# TODO(PROD-41): mover para dentro do capivaraos-herd-branding (fonte única).
%post
install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/50-capivaraos-herd.conf <<'EOF'
# CapivaraOS HERD — baseline de hardening SSH (ver PROD-41)
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
AllowAgentForwarding no
EOF
chmod 0600 /etc/ssh/sshd_config.d/50-capivaraos-herd.conf

# ── Corrige os títulos do GRUB (senão ficam "Fedora Linux") ──────────────────
# O kernel-install do Anaconda gera as entradas BLS a partir do os-release ANTES
# do nosso branding, e o Anaconda ainda regenera o bootloader como passo final —
# por isso o %transfiletriggerin do RPM não pega aqui. O %post roda por ÚLTIMO
# (após o Anaconda configurar o bootloader), então a correção não é sobrescrita.
# Usamos o MESMO script do RPM de branding (fonte única — normais + rescue);
# /etc/os-release já é o nosso (branding instalado no payload).
sh /usr/share/capivaraos-herd/fix-bls-titles.sh 2>/dev/null || true
%end
