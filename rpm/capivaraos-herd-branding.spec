# capivaraos-herd-branding — identidade do CapivaraOS HERD (servidor headless)
#
# Diferente do branding dos desktops (wallpapers, SDDM, tema Plasma), o HERD é
# headless: aqui o branding é textual — /etc/os-release, /etc/issue e a
# mensagem do dia (/etc/motd.d/). Assets gráficos (logo de console) podem
# entrar depois via PROD-36.

Name:           capivaraos-herd-branding
Version:        1.0.0
# Sufixo ".herd": todas as spins constroem um pacote de branding e compartilham
# ~/rpmbuild na mesma máquina. Sem um sufixo de linha, duas na mesma
# Version-Release gerariam nomes de arquivo idênticos — já causou incidentes
# nos desktops (BUG-30). Com o sufixo a colisão é impossível por construção.
Release:        1%{?dist}.herd
Summary:        Identidade (os-release, issue, motd) do CapivaraOS HERD Community

License:        CC-BY-SA-4.0
URL:            https://capivaraos.org
BuildArch:      noarch

Source0:        %{name}-%{version}.tar.gz

# Fornecemos nosso próprio /etc/os-release no lugar do genérico do Fedora.
Conflicts:      fedora-release-identity-server
Provides:       system-release-branding = %{version}-%{release}

%description
Pacote de identidade do CapivaraOS HERD Community: /etc/os-release,
/etc/issue e mensagem do dia (/etc/motd.d/capivaraos-herd). Voltado a
servidor headless nascido no Fedora 45.

%prep
%setup -q

%install
install -D -m 0644 os-release %{buildroot}%{_sysconfdir}/os-release
install -D -m 0644 issue      %{buildroot}%{_sysconfdir}/issue
install -D -m 0644 motd       %{buildroot}%{_sysconfdir}/motd.d/capivaraos-herd

%files
%{_sysconfdir}/os-release
%{_sysconfdir}/issue
%{_sysconfdir}/motd.d/capivaraos-herd

%changelog
* Sat Aug 08 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-1.herd
- Branding inicial do HERD Community (os-release, issue, motd).
