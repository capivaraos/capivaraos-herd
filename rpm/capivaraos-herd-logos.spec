# capivaraos-herd-logos: identity of the CapivaraOS Herd INSTALLER (Anaconda)
#
# Replaces fedora-logos IN THE INSTALLER ENVIRONMENT (lorax), removing the
# Fedora brand from the Anaconda screens. Modelled on generic-logos (Fedora's
# official unbranded package): it provides the system-logos/redhat-logos/
# fedora-logos names, and build-iso.sh excludes the real fedora-logos, so
# Anaconda (which requires the system-logos virtual) uses ours. It is NOT installed on the target system; it
# is only in the lorax package list.
#
# The pixmaps are generated in %build from the (white) capybara logo on the
# brand colour (#6B4F36), at the sizes Anaconda expects.

Name:           capivaraos-herd-logos
Version:        2.0.0
# ".herd" suffix: same convention as the other spins (avoids NEVRA collisions
# in a shared ~/rpmbuild).
Release:        1%{?dist}.herd
Summary:        Identidade do instalador (Anaconda) do CapivaraOS HERD

# The logo is a trademark of the project (see TRADEMARK.md), not an open licence.
License:        LicenseRef-CapivaraOS-Trademark
URL:            https://capivaraos.org
BuildArch:      noarch

Source0:        %{name}-%{version}.tar.gz

BuildRequires:  ImageMagick

# Replaces fedora-logos in the installer environment. lorax derives the logos
# package from the release (fedora-release-server) and installs "fedora-logos"
# BY NAME (treebuilder.py). We PROVIDE the virtuals and the fedora-logos name
# itself; build-iso.sh EXCLUDES the real fedora-logos from the Fedora
# repositories, so ours is the only "fedora-logos" provider and is chosen. (No
# Obsoletes: with an explicit -i, dnf reported "conflicting requests" against
# the real fedora-logos.)
Provides:       system-logos = 42.0.1
Provides:       redhat-logos = 42.0.1
Provides:       fedora-logos = 42.0.1

%description
Arte de identidade do CapivaraOS HERD para o instalador Anaconda: logo e fundo
da barra lateral, barra superior, cabeçalho e splash de boot, além do CSS de
tema. Usado no build da ISO instaladora (lorax) para que o instalador não exiba
a marca Fedora. Não faz parte do sistema instalado.

%prep
%setup -q

%build
# Sidebar logo (white on transparent), fitted to the sidebar area.
convert src/capivaraos-logo-branca.png -resize 240x110 sidebar-logo.png
# Solid backgrounds in the brand colour.
convert -size 406x767  xc:'#6B4F36' sidebar-bg.png
convert -size 1040x132 xc:'#6B4F36' topbar-bg.png
# Legacy header (small).
convert src/capivaraos-logo-branca.png -resize 119x36 anaconda_header.png
# Boot splash: logo centred on the brand colour.
convert -size 640x480 xc:'#6B4F36' \
    \( src/capivaraos-logo-branca.png -resize 420x \) \
    -gravity center -composite splash.png
cp splash.png syslinux-splash.png

%install
install -d %{buildroot}%{_datadir}/anaconda/pixmaps
install -m 0644 sidebar-logo.png sidebar-bg.png topbar-bg.png anaconda_header.png \
    %{buildroot}%{_datadir}/anaconda/pixmaps/
# Anaconda loads fedora.css by default; since build-iso.sh excludes
# fedora-logos, we own that path and ship our theme in it.
install -m 0644 capivaraos-herd.css %{buildroot}%{_datadir}/anaconda/pixmaps/fedora.css
install -d %{buildroot}%{_datadir}/anaconda/boot
install -m 0644 splash.png syslinux-splash.png %{buildroot}%{_datadir}/anaconda/boot/

%files
%dir %{_datadir}/anaconda/pixmaps
%{_datadir}/anaconda/pixmaps/sidebar-logo.png
%{_datadir}/anaconda/pixmaps/sidebar-bg.png
%{_datadir}/anaconda/pixmaps/topbar-bg.png
%{_datadir}/anaconda/pixmaps/anaconda_header.png
%{_datadir}/anaconda/pixmaps/fedora.css
%dir %{_datadir}/anaconda/boot
%{_datadir}/anaconda/boot/splash.png
%{_datadir}/anaconda/boot/syslinux-splash.png

%changelog
* Tue Nov 17 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-1.herd
- Herd 2.0.0 release. No functional change.

* Sun Sep 20 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-0.1.alpha1.herd
- Geração 2.x (Fedora 45). Nenhuma mudança de arte: o
  fedora-logos do F45 continua Version 42.0.1, então os Provides
  system-logos/redhat-logos/fedora-logos = 42.0.1 seguem casando com o virtual
  que o Anaconda exige. Só bump de versão para a série 2.x (0.1.alpha1).

* Mon Aug 10 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-3.herd
- Remove Obsoletes fedora-logos (causava "conflicting requests" no lorax com o
  -i explícito). Mantém Provides fedora-logos; o build-iso.sh passa a excluir o
  fedora-logos real dos repos Fedora, tornando o nosso o único provedor.

* Mon Aug 10 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-2.herd
- Substitui fedora-logos por Provides+Obsoletes (não Conflicts): o lorax instala
  "fedora-logos" por nome (derivado do release), então precisamos que o dnf
  escolha o nosso no lugar. Conflicts+`-e fedora-logos` quebrava o lorax
  (removepkg de pacote não instalado).

* Mon Aug 10 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-1.herd
- Pacote inicial de logos do instalador (Anaconda) do CapivaraOS HERD:
  sidebar-logo/bg, topbar, cabeçalho, splash e CSS de tema (marrom #6B4F36).
