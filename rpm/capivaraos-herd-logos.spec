# capivaraos-herd-logos — identidade do INSTALADOR (Anaconda) do CapivaraOS HERD
#
# Substitui o fedora-logos NO AMBIENTE DO INSTALADOR (lorax), removendo a marca
# Fedora das telas do Anaconda. Modelado no generic-logos (o pacote de-brandado
# oficial do Fedora): fornece os virtuais system-logos/redhat-logos e conflita
# com fedora-logos, então o Anaconda (que requer o virtual system-logos) usa o
# nosso. NÃO é instalado no sistema alvo — entra só na lista de pacotes do lorax.
#
# Os pixmaps são gerados no %build a partir da logo da capivara (branca) sobre a
# cor da marca (#6B4F36), nas dimensões que o Anaconda espera.

Name:           capivaraos-herd-logos
Version:        1.0.0
# Sufixo ".herd": mesma convenção do capivaraos-herd-branding (evita colisão de
# NEVRA em ~/rpmbuild compartilhado — ver BUG-30).
Release:        2%{?dist}.herd
Summary:        Identidade do instalador (Anaconda) do CapivaraOS HERD

License:        CC-BY-SA-4.0
URL:            https://capivaraos.org
BuildArch:      noarch

Source0:        %{name}-%{version}.tar.gz

BuildRequires:  ImageMagick

# Substitui o fedora-logos no ambiente do instalador. O lorax deriva o pacote de
# logos do release (fedora-release-server) e instala "fedora-logos" POR NOME
# (treebuilder.py). Por isso FORNECEMOS e OBSOLETAMOS fedora-logos: quando o
# lorax pede fedora-logos, o dnf instala o nosso no lugar. Versões espelham a do
# fedora-logos atual para satisfazer requisitos versionados.
Provides:       system-logos = 42.0.1
Provides:       redhat-logos = 42.0.1
Provides:       fedora-logos = 42.0.1
Obsoletes:      fedora-logos < 42.0.2

%description
Arte de identidade do CapivaraOS HERD para o instalador Anaconda: logo e fundo
da barra lateral, barra superior, cabeçalho e splash de boot, além do CSS de
tema. Usado no build da ISO instaladora (lorax) para que o instalador não exiba
a marca Fedora. Não faz parte do sistema instalado.

%prep
%setup -q

%build
# Logo da barra lateral (branca sobre transparente), ajustada à área da sidebar.
convert src/capivaraos-logo-branca.png -resize 240x110 sidebar-logo.png
# Fundos sólidos na cor da marca.
convert -size 406x767  xc:'#6B4F36' sidebar-bg.png
convert -size 1040x132 xc:'#6B4F36' topbar-bg.png
# Cabeçalho legado (pequeno).
convert src/capivaraos-logo-branca.png -resize 119x36 anaconda_header.png
# Splash de boot: logo centralizada sobre a cor da marca.
convert -size 640x480 xc:'#6B4F36' \
    \( src/capivaraos-logo-branca.png -resize 420x \) \
    -gravity center -composite splash.png
cp splash.png syslinux-splash.png

%install
install -d %{buildroot}%{_datadir}/anaconda/pixmaps
install -m 0644 sidebar-logo.png sidebar-bg.png topbar-bg.png anaconda_header.png \
    %{buildroot}%{_datadir}/anaconda/pixmaps/
# O Anaconda carrega fedora.css por padrão; como conflitamos com o fedora-logos,
# somos os donos desse caminho e entregamos o nosso tema nele.
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
* Mon Aug 10 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-2.herd
- Substitui fedora-logos por Provides+Obsoletes (não Conflicts): o lorax instala
  "fedora-logos" por nome (derivado do release), então precisamos que o dnf
  escolha o nosso no lugar. Conflicts+`-e fedora-logos` quebrava o lorax
  (removepkg de pacote não instalado).

* Mon Aug 10 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-1.herd
- Pacote inicial de logos do instalador (Anaconda) do CapivaraOS HERD:
  sidebar-logo/bg, topbar, cabeçalho, splash e CSS de tema (marrom #6B4F36).
