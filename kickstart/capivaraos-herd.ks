# =============================================================================
# Kickstart of Herd by CapivaraOS (Community): headless server installer.
# =============================================================================
# PARTIAL on purpose: it sets the system PROFILE (locale, timezone, network,
# firewall, services, hardening, packages) and leaves DISK and USER/ROOT
# INTERACTIVE, so the admin decides them during the installation, as expected
# of a distributable installer.
#
# Mirrors the profile of the osbuild blueprint (blueprints/capivaraos-herd.toml).
# Keep the two in sync.
#
# Packages come from the OFFLINE repository inside the ISO; Anaconda is pointed
# at it by the command line inst.repo=hd:LABEL=<volid>:/repo (see build-iso.sh).
# =============================================================================

text

# ── Localization ────────────────────────────────────────────────────────────
lang pt_BR.UTF-8 --addsupport=en_US.UTF-8
keyboard --vckeymap=br-abnt2 --xlayouts=''
timezone America/Sao_Paulo --utc

# ── Network: DHCP by default (the admin changes it during or after install) ─
network --bootproto=dhcp --activate

# ── Security and services (mirrors the blueprint) ───────────────────────────
firewall --enabled --service=ssh,cockpit
selinux --enforcing
services --enabled=sshd,chronyd,firewalld,cloud-init.target,cockpit.socket,dnf5-automatic.timer

# ── Bootloader ──────────────────────────────────────────────────────────────
bootloader --location=mbr --append="audit_backlog_limit=8192"

# DISK: interactive. With no clearpart/part/autopart, the admin picks the target.
# USER/ROOT: interactive. With no rootpw/user, the admin creates them.
# Note: PasswordAuthentication no requires an SSH key; a user created with a
# password only logs in on the CONSOLE (physical/IPMI) and adds a key later.
#
# ── OPTION: disk encryption at rest (LUKS) ──────────────────────────────────
# By default the disk is INTERACTIVE: on Anaconda's partitioning screen the
# admin can tick "Encrypt my data" and set the passphrase. This is the
# recommended way, with no change to the kickstart.
#
# For an AUTOMATED install that is already encrypted, uncomment ONE of the
# blocks below (partitioning is then no longer interactive):
#
#   # a) simple: encrypted LVM over the whole disk:
#   # clearpart --all --initlabel
#   # autopart --type=lvm --encrypted --passphrase=CHANGE-THIS-PASSPHRASE
#
#   # b) manual: /boot unencrypted (required) and the rest on the encrypted PV:
#   # clearpart --all --initlabel
#   # part /boot     --fstype=xfs --size=1024
#   # part /boot/efi --fstype=efi --size=600          # UEFI only
#   # part pv.01     --grow --encrypted --passphrase=CHANGE-THIS-PASSPHRASE
#   # volgroup vg00 pv.01
#   # logvol /       --vgname=vg00 --name=root --fstype=xfs --grow
#
# WARNING (headless server): a LUKS volume asks for the PASSPHRASE at boot.
# Without a console (physical/IPMI/serial) the machine does NOT come back on its
# own after a reboot. For unattended unlocking on a server, consider NBDE:
# Clevis with TPM2 (local seal) or Tang (network). Do NOT use LUKS in a cloud
# image (qcow2).
#
# NEVER commit a real passphrase here. Prefer the interactive flow, or build the
# ISO per deployment with the passphrase injected at build time.

%packages
@core
kernel
capivaraos-herd-branding
capivaraos-herd-hardening
# Signed Herd update repository: lets the installed system receive the Herd
# packages, not only Fedora's. Ships only the .repo and public keys, so the
# install needs no network. Do not cut an ISO with this package before
# repo-herd.capivaraos.org serves the target release (see docs/repo/README.md).
capivaraos-herd-repos
# Automatic security updates: the dnf5 automatic policy (security updates
# only, no reboot); dnf5-automatic.timer is enabled on the services line above.
# Pulls in dnf5-plugin-automatic.
capivaraos-herd-autoupdate
# In-place version upgrade: the herd-upgrade command, an auditable wrapper
# around dnf5 system-upgrade. It only ships the command; the administrator
# always starts the upgrade. The pre-flight check fails closed while the target
# release is not published in the Herd update repository.
capivaraos-herd-upgrade
cloud-init
qemu-guest-agent
openssh-server
firewalld
chrony
cockpit
# Storage, Networking and Software updates pages: weak dependencies of
# cockpit, listed because the ISO repository has no weak dependencies.
cockpit-storaged
cockpit-networkmanager
cockpit-packagekit
# systemd-pam and kmscon: weak dependencies, listed because the image has
# no weak dependencies. systemd-pam gives each login a user session, which
# Cockpit needs to switch to administrative access with a password. kmscon
# shows the login prompt on the screen: Fedora 45 uses it in place of getty
# on the virtual consoles.
systemd-pam
kmscon
glibc-langpack-pt
glibc-langpack-en
# fastfetch: system summary in the terminal with the project logo. The art and
# config come with capivaraos-herd-branding; it does not run on its own, only
# when the admin runs `fastfetch`.
fastfetch
# cryptsetup: needed to install and boot with an encrypted disk (LUKS). Without
# it in the payload and offline repository, an encrypted install fails ("No match
# for argument: cryptsetup"). Always included, as LUKS is a documented option.
cryptsetup
%end

# Hardening (SSH, passwords, umask, compliance) comes from the
# capivaraos-herd-hardening package in %packages, the single source; do not
# repeat it here.
%post
# ── Fix the GRUB entry titles (otherwise they read "Fedora Linux") ──────────
# Anaconda's kernel-install writes the BLS entries from os-release BEFORE the
# branding is installed, and Anaconda regenerates the bootloader as its last
# step, so the RPM's %transfiletriggerin does not apply here. %post runs LAST
# (after Anaconda configures the bootloader), so the fix is not overwritten.
# It uses the SAME script as the branding RPM (normal and rescue entries);
# /etc/os-release is already the project's (branding is in the payload).
sh /usr/share/capivaraos-herd/fix-bls-titles.sh 2>/dev/null || true
# Trust the Herd signing keys from the first boot. This %post runs after the
# installation transaction, so rpm can import them here; the dnf5-automatic
# drop-in from capivaraos-herd-repos does the same before each unattended
# update.
rpmkeys --import /etc/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd \
    /etc/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd-reserve
%end
