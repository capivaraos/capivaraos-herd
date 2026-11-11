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
Version:        1.0.0
# ".herd" suffix: same convention as the other spins (avoids NEVRA collisions
# in a shared ~/rpmbuild).
Release:        1%{?dist}.herd
Summary:        Atualização automática de segurança (dnf5 automatic) do CapivaraOS Herd

License:        GPL-3.0-or-later
URL:            https://capivaraos.org
BuildArch:      noarch

Source0:        automatic.conf

# Quem baixa/aplica os updates é o plugin automatic do dnf5.
Requires:       dnf5-plugin-automatic
# Faz sentido junto do repositório assinado (senão só atualiza o Fedora, não os
# nossos pacotes). Não é um acoplamento rígido de funcionamento, mas de propósito.
Requires:       capivaraos-herd-repos

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
* Sat Aug 29 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-1.herd
- Pacote inicial de atualização automática: configura o dnf5 automatic
  (upgrade_type=security, apply_updates=yes, reboot=never, emit_via=motd,stdio).
  Requires dnf5-plugin-automatic + capivaraos-herd-repos. A config é instalada em
  /etc/dnf/automatic.conf via %posttrans só se ausente (preserva edição do admin,
  já que o caminho é %config ghost do plugin). Timer dnf5-automatic.timer
  habilitado no kickstart/blueprint.
