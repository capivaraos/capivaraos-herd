# =============================================================================
# Kickstart do Herd by CapivaraOS (Community) — instalador de servidor headless.
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
services --enabled=sshd,chronyd,firewalld,cloud-init.target,cockpit.socket,dnf5-automatic.timer

# ── Bootloader ──────────────────────────────────────────────────────────────
bootloader --location=mbr --append="audit_backlog_limit=8192"

# DISCO: interativo — sem clearpart/part/autopart, o admin escolhe o destino.
# USUÁRIO/ROOT: interativo — sem rootpw/user, o admin cria na instalação.
# NB (PROD-41): PasswordAuthentication no exige chave SSH; um usuário criado só
# com senha loga no CONSOLE (físico/IPMI) e adiciona a chave depois.
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
# (rede) — roadmap/Enterprise. NÃO use LUKS em imagem de nuvem (qcow2).
#
# NUNCA versione uma senha real aqui. Prefira o fluxo interativo, ou gere a ISO
# por cliente com a senha injetada no momento do build.

%packages
@core
kernel
capivaraos-herd-branding
capivaraos-herd-hardening
# Configuração do repositório de updates assinado (PROD-105): faz o sistema
# INSTALADO receber os pacotes próprios do projeto (não só os do Fedora). Instala
# só o .repo + chave GPG (import offline no %post), então não precisa de rede no
# install. GUARDRAIL: não cortar ISO com este pacote antes de
# repo.capivaraos.org/herd/ estar no ar (ver docs/repo/README.md).
capivaraos-herd-repos
# Atualização automática de segurança (PROD-106): política do dnf5 automatic +
# habilita dnf5-automatic.timer (na linha services acima). Puxa dnf5-plugin-
# automatic. Aplica só updates de segurança, sem auto-reboot.
capivaraos-herd-autoupdate
# Upgrade de versão in-place (PROD-107): ferramenta `herd-upgrade`, invólucro
# auditável do dnf5 system-upgrade (F44->F45 e além, sem formatar). Só entrega
# o comando; o upgrade é sempre disparado pelo admin. Mesmo guardrail do repos:
# o pré-voo falha fechado enquanto herd/f<destino>/ não estiver publicado.
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
