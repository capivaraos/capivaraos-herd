# capivaraos-herd-autoupdate — automatic server updates
#
# Configures dnf5 automatic to apply SECURITY updates on its own (no reboot).
# Depends on the signed repository from capivaraos-herd-repos so the project's
# own packages are updated too; together they provide continuous, signed
# updates on the installed server.
#
# Entrega só a política (config). Quem executa é o dnf5-plugin-automatic
# (dependência) via o timer dnf5-automatic.timer, habilitado no kickstart/
# blueprint (mesmo idioma dos outros serviços do Herd — sshd, cockpit.socket…).
#
# A config /etc/dnf/automatic.conf é %config(noreplace) GHOST do plugin (não
# existe em disco). Para não conflitar no ownership, NÃO a declaramos no %files:
# guardamos a nossa versão num datadir privado e o %posttrans a instala em /etc
# só se ainda não existir (edições do admin persistem = "configurável").

Name:           capivaraos-herd-autoupdate
Version:        2.0.0
# ".herd" suffix: same convention as the other spins (avoids NEVRA collisions
# in a shared ~/rpmbuild).
Release:        2%{?dist}.herd
Summary:        Atualização automática de segurança (dnf5 automatic) do CapivaraOS Herd

License:        GPL-3.0-or-later
URL:            https://capivaraos.org
BuildArch:      noarch

Source0:        automatic.conf

# Quem baixa/aplica os updates é o plugin automatic do dnf5.
Requires:       dnf5-plugin-automatic
# The signed Herd repository, from the first version that ships the
# dnf5-automatic.service drop-in that imports both Herd keys before each
# unattended run. An older capivaraos-herd-repos has no such step.
Requires:       capivaraos-herd-repos >= 2.0.0-0.4.alpha1

Provides:       system-autoupdate-config = %{version}-%{release}

%description
Política de atualização automática do CapivaraOS Herd Community: configura o
dnf5 automatic para baixar e aplicar as atualizações de SEGURANÇA diariamente,
sem reiniciar o servidor (reboot fica a cargo do administrador). A configuração
vai para /etc/dnf/automatic.conf apenas na primeira instalação, então edições
do administrador são preservadas. O timer dnf5-automatic.timer é habilitado
pela imagem (kickstart/blueprint).

%install
# Guardamos a nossa política num datadir privado; o %posttrans a copia para
# /etc/dnf/automatic.conf se ainda não existir (ver cabeçalho).
install -D -m 0644 %{SOURCE0} %{buildroot}%{_datadir}/%{name}/automatic.conf

%posttrans
# Instala a nossa política só se o admin ainda não tem um /etc/dnf/automatic.conf
# (o arquivo é ghost do plugin, então normalmente não existe). Idempotente e
# preserva edições do administrador em updates futuros.
if [ ! -f %{_sysconfdir}/dnf/automatic.conf ]; then
    install -D -m 0644 %{_datadir}/%{name}/automatic.conf \
        %{_sysconfdir}/dnf/automatic.conf
fi

%files
%dir %{_datadir}/%{name}
%{_datadir}/%{name}/automatic.conf

%changelog
* Wed Nov 18 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-2.herd
- Package description and changelog text revised. No functional change.

* Tue Nov 17 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-1.herd
- Herd 2.0.0 release. No functional change.

* Mon Nov 16 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-0.3.alpha1.herd
- Require capivaraos-herd-repos 2.0.0-0.4.alpha1 or later, the first version
  that ships the dnf5-automatic.service drop-in that imports both Herd keys
  before each unattended run.

* Thu Nov 12 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-0.2.alpha1.herd
- Rebuild from the current sources. No functional change.

* Mon Sep 21 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-0.1.alpha1.herd
- Geração 2.x (Fedora 45): bump de versão. dnf-automatic é agnóstico de
  release; sem mudança funcional.

* Sat Aug 29 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-1.herd
- Pacote inicial de atualização automática: configura o dnf5 automatic
  (upgrade_type=security, apply_updates=yes, reboot=never, emit_via=motd,stdio).
  Requires dnf5-plugin-automatic + capivaraos-herd-repos. A config é instalada em
  /etc/dnf/automatic.conf via %posttrans só se ausente (preserva edição do admin,
  já que o caminho é %config ghost do plugin). Timer dnf5-automatic.timer
  habilitado no kickstart/blueprint.
