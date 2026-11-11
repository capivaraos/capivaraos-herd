# =============================================================================
# Kickstart do Herd by CapivaraOS (Community) — instalador de servidor headless.
# =============================================================================
# PARCIAL de propósito: define o PERFIL do sistema (locale, timezone, rede,
# firewall, serviços, hardening, pacotes) mas deixa DISCO e USUÁRIO/ROOT
# INTERATIVOS — o admin decide na hora da instalação (comportamento esperado de
# um instalador distribuível).
#
# Mirrors the osbuild blueprint profile (blueprints/capivaraos-herd.toml).
# KEEP BOTH IN SYNC.
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
services --enabled=sshd,chronyd,firewalld,cloud-init.target,cockpit.socket,dnf5-automatic.timer

# ── Bootloader ──────────────────────────────────────────────────────────────
bootloader --location=mbr --append="audit_backlog_limit=8192"

# DISCO: interativo — sem clearpart/part/autopart, o admin escolhe o destino.
# USUÁRIO/ROOT: interativo — sem rootpw/user, o admin cria na instalação.
# NB: PasswordAuthentication no requires an SSH key; a user created with only
# a password logs in on the CONSOLE (physical/IPMI) and adds a key later.
#
# ── OPÇÃO: criptografia de disco em repouso (LUKS) ───────────────────────────
# Por padrão o disco é INTERATIVO: na tela de particionamento do Anaconda o
# admin pode marcar "Criptografar meus dados" e definir a senha — este é o
# caminho recomendado, sem mexer no kickstart.
#
# Para uma instalação AUTOMÁTICA e já criptografada, descomente UM dos blocos
# abaixo (particionamento deixa de ser interativo):
#
#   # a) simples — LVM criptografado ocupando o disco:
#   # clearpart --all --initlabel
#   # autopart --type=lvm --encrypted --passphrase=TROQUE-ESTA-SENHA
#
#   # b) manual — /boot em claro (exigido) e o resto no PV cifrado:
#   # clearpart --all --initlabel
#   # part /boot     --fstype=xfs --size=1024
#   # part /boot/efi --fstype=efi --size=600          # só em UEFI
#   # part pv.01     --grow --encrypted --passphrase=TROQUE-ESTA-SENHA
#   # volgroup vg00 pv.01
#   # logvol /       --vgname=vg00 --name=root --fstype=xfs --grow
#
# ATENÇÃO (servidor headless): um volume LUKS pede a SENHA no boot. Sem console
# (físico/IPMI/serial) a máquina NÃO sobe sozinha após reiniciar. Para auto-
# desbloqueio em servidor, avalie NBDE: Clevis + TPM2 (selo local) ou Tang
# (rede). NÃO use LUKS em imagem de nuvem (qcow2).
#
# NEVER commit a real passphrase here. Prefer the interactive flow, or inject
# the passphrase when building the ISO.

%packages
@core
kernel
capivaraos-herd-branding
capivaraos-herd-hardening
# Signed update repository configuration: lets the INSTALLED system receive
# the project's own packages, not only Fedora's. Installs only the .repo file
# and GPG key (imported offline in %post), so no network is needed at install
# time. Do not build an ISO with this package before repo.capivaraos.org/herd/
# is online (see docs/repo/README.md).
capivaraos-herd-repos
# Automatic security updates: dnf5 automatic policy; dnf5-automatic.timer is
# enabled on the services line above. Pulls in dnf5-plugin-automatic. Applies
# security updates only, no automatic reboot.
capivaraos-herd-autoupdate
# In-place version upgrade: `herd-upgrade`, an auditable wrapper around dnf5
# system-upgrade (F44->F45 and later, no reinstall). Ships only the command;
# the upgrade is always started by the administrator. Like the repos package,
# the pre-flight check fails closed until herd/f<target>/ is published.
capivaraos-herd-upgrade
cloud-init
qemu-guest-agent
openssh-server
firewalld
chrony
cockpit
glibc-langpack-pt
glibc-langpack-en
# cryptsetup: necessário para instalar/bootar com disco cifrado (LUKS). Sem ele
# no payload/repo offline, um install criptografado falha ("Nenhuma correspondência
# para o argumento: cryptsetup"). Pequeno; entra sempre (LUKS é opção documentada).
cryptsetup
%end

# O hardening (SSH, senha, umask, compliance) vem do pacote
# capivaraos-herd-hardening no %packages — fonte única, não replicar aqui.
%post
# ── Corrige os títulos do GRUB (senão ficam "Fedora Linux") ──────────────────
# O kernel-install do Anaconda gera as entradas BLS a partir do os-release ANTES
# do nosso branding, e o Anaconda ainda regenera o bootloader como passo final —
# por isso o %transfiletriggerin do RPM não pega aqui. O %post roda por ÚLTIMO
# (após o Anaconda configurar o bootloader), então a correção não é sobrescrita.
# Usamos o MESMO script do RPM de branding (fonte única — normais + rescue);
# /etc/os-release já é o nosso (branding instalado no payload).
sh /usr/share/capivaraos-herd/fix-bls-titles.sh 2>/dev/null || true
%end
