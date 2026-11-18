# capivaraos-herd-branding: identity of CapivaraOS Herd (headless server)
#
# Unlike the desktop branding (wallpapers, SDDM, Plasma theme), Herd is
# headless: its branding is text (/etc/os-release, /etc/issue, motd) plus the
# web console (Cockpit). It also sets the boot menu titles (GRUB/BLS) to the
# CapivaraOS name through a single script.

Name:           capivaraos-herd-branding
Version:        2.0.0
# ".herd" suffix, as in the other Herd packages: keeps the NEVRA apart from
# the other editions' packages in a shared ~/rpmbuild.
Release:        3%{?dist}.herd
Summary:        Identidade (os-release, issue, motd, Cockpit) do CapivaraOS HERD Community

# Code (os-release/issue/motd, BLS script) under GPLv3; the Cockpit logo artwork
# is a trademark of the project (see TRADEMARK.md).
License:        GPL-3.0-or-later AND LicenseRef-CapivaraOS-Trademark
URL:            https://capivaraos.org
BuildArch:      noarch

Source0:        %{name}-%{version}.tar.gz

# Builds the Cockpit branding artwork (logo and icons) from the brand logos.
BuildRequires:  ImageMagick

Provides:       system-release-branding = %{version}-%{release}

# No "Requires: cockpit-ws". The branding directory does nothing without
# Cockpit, and Cockpit is already in the Herd payload (kickstart/blueprint). A
# Requires would tie this identity package to the Cockpit install for no gain.

%description
Pacote de identidade do CapivaraOS HERD Community: /etc/os-release,
/etc/issue e mensagem do dia (/etc/motd.d/capivaraos-herd). Voltado a
servidor headless com base Fedora 45.

%prep
%setup -q

%build
# ── Cockpit branding artwork (Herd navy identity) ───────────────────────────
# Login badge = the brand avatar (src/avatar-navy-branca.png): navy #1E2F4E
# square with the WHITE capybara + "CapivaraOS". The CSS paints the login page
# in the SAME navy, so the avatar edge disappears and only the white logo shows
# on the navy background. Normalised to PNG; the CSS uses a square badge with
# background-size: contain.
cd cockpit
convert src/avatar-navy-branca.png -resize 400x400 logo.png
# Square icons (white head on a navy tile): browser tab and iOS.
convert -size 180x180 xc:none \
    -fill '#1E2F4E' -draw 'roundrectangle 0,0,179,179,32,32' \
    \( src/capivaraos-cabeca-branca.png -resize 132x \) -gravity center -composite \
    apple-touch-icon.png
convert apple-touch-icon.png -define icon:auto-resize=16,32,48 favicon.ico
cd -

%install
# os-release and issue do not go to /etc in %files (see the note below). They
# live in a private datadir as the source, and the scriptlets copy them to /etc.
install -d %{buildroot}%{_datadir}/capivaraos-herd
install -m 0644 os-release %{buildroot}%{_datadir}/capivaraos-herd/os-release
# VERSION_ID is the Fedora release this package is built for, not the Herd
# version. PackageKit (the Cockpit "Software updates" page) uses VERSION_ID as
# the Fedora release for the Fedora mirrors, so it must be the same number as
# %%{fedora}. The Herd version is in VERSION, PRETTY_NAME and CPE_NAME.
[ -n "%{?fedora}" ] || { echo "%%{fedora} is not set: build on Fedora" >&2; exit 1; }
sed -i 's/^VERSION_ID=@FEDORA_VERSION@$/VERSION_ID=%{fedora}/' %{buildroot}%{_datadir}/capivaraos-herd/os-release
grep -qx 'VERSION_ID=%{fedora}' %{buildroot}%{_datadir}/capivaraos-herd/os-release
grep -qx 'PLATFORM_ID="platform:f%{fedora}"' %{buildroot}%{_datadir}/capivaraos-herd/os-release
install -m 0644 issue      %{buildroot}%{_datadir}/capivaraos-herd/issue
# Single script that fixes the GRUB BLS titles (called by the scriptlets and by
# the kickstart %post; see the comments in %posttrans/%transfiletriggerin).
install -m 0755 fix-bls-titles.sh %{buildroot}%{_datadir}/capivaraos-herd/fix-bls-titles.sh
# motd.d/capivaraos-herd is a new file that no other package owns, so it goes
# in %files as usual.
install -D -m 0644 motd    %{buildroot}%{_sysconfdir}/motd.d/capivaraos-herd

# ── Cockpit (web console) branding ──────────────────────────────────────────
# Cockpit picks this directory from ID=capivaraos-herd in /etc/os-release.
# We own only our subdirectory (/usr/share/cockpit/branding belongs to cockpit).
install -d %{buildroot}%{_datadir}/cockpit/branding/capivaraos-herd
install -m 0644 cockpit/branding.css cockpit/logo.png \
    cockpit/apple-touch-icon.png cockpit/favicon.ico \
    %{buildroot}%{_datadir}/cockpit/branding/capivaraos-herd/

# ── Cockpit manifest overrides ──────────────────────────────────────────────
# Removes the documentation links to docs.redhat.com from the Help menu
# (Cockpit's documented mechanism: /etc/cockpit/<package>.override.json, merged
# over the package's manifest.json). The menu then keeps our docs link (from
# DOCUMENTATION_URL in os-release) and "About", without Red Hat links.
# Covers the 6 packages that carry docs.redhat.com links: shell, systemd, users,
# networkmanager, storaged and packagekit. Installed with a glob to pick up any new override.
install -d %{buildroot}%{_sysconfdir}/cockpit
install -m 0644 cockpit/overrides/*.override.json %{buildroot}%{_sysconfdir}/cockpit/

# ── fastfetch logo ──────────────────────────────────────────────────────────
# fastfetch shows the Fedora ASCII logo (chosen from ID_LIKE in os-release). We
# replace it with the brand's capybara head and "Herd by CapivaraOS". The art
# goes to /usr/share/capivaraos-herd/fastfetch/ and config.jsonc (the logo and
# a module list for a headless server) to /etc/xdg and /etc/skel. /etc/xdg is what counts on a
# headless server: fastfetch reads XDG_CONFIG_DIRS=/etc/xdg when the user
# (root included) has no ~/.config/fastfetch, so the admin sees the brand with
# no setup. No auto-run: it shows only when the admin runs `fastfetch`.
install -d %{buildroot}%{_datadir}/capivaraos-herd/fastfetch
install -m 0644 fastfetch/capivara.txt %{buildroot}%{_datadir}/capivaraos-herd/fastfetch/capivara.txt
for FDIR in %{buildroot}%{_sysconfdir}/skel/.config %{buildroot}%{_sysconfdir}/xdg; do
    install -d "$FDIR/fastfetch"
    install -m 0644 fastfetch/config.jsonc "$FDIR/fastfetch/config.jsonc"
done

# /etc/os-release and /etc/issue belong to fedora-release-common. Listing them
# in %files causes an rpm file conflict during install (the image build fails
# with exit 2). So they are written straight to the system in %posttrans (which
# runs at the end of the transaction, so our content wins) and written again by
# %transfiletriggerin after updates.

%posttrans
# Write our identity over Fedora's (end of the transaction).
cp -f %{_datadir}/capivaraos-herd/os-release %{_sysconfdir}/os-release
cp -f %{_datadir}/capivaraos-herd/issue      %{_sysconfdir}/issue
# Fix the boot menu titles (GRUB/BLS). On the osbuild path (qcow2),
# kernel-install has already created the entries with the Fedora name BEFORE
# this %posttrans; that path has no kickstart, so the fix must happen HERE.
# The os-release above is already ours, so the script derives the right title.
sh %{_datadir}/capivaraos-herd/fix-bls-titles.sh 2>/dev/null || true

# ── Write os-release/issue again after any later system update ─────────────
# /etc/os-release still belongs to Fedora in the rpmdb, so a "dnf update" that
# touches the owning package writes Fedora's defaults back. If that happens in
# the SAME transaction as a new kernel, that kernel's GRUB/BLS title (made by
# kernel-install from NAME/VERSION in os-release) is saved as "Fedora Linux ..."
# and stays that way. So we write ours again and regenerate the BLS entries.
#
# WARNING: do not replace the prefix with an exact file path. Tested on
# fedora:44: %transfiletriggerin matches DIRECTORY prefixes only, never a file
# path. So we watch %{_prefix}/lib (where Fedora's own os-release lives).
%transfiletriggerin -- %{_prefix}/lib
# Guard: we check /usr/lib/os-release, which we NEVER rewrite (we only touch
# /etc/os-release). It always keeps Fedora's NAME, so this condition does NOT
# short-circuit, and the trigger always writes again and runs kernel-install.
# THIS IS INTENDED: kernel-install must run AFTER os-release is fixed to write
# the right BLS title (otherwise GRUB shows "Fedora Linux ..."; this was the
# installer bug, since Anaconda's kernel-install runs before our %posttrans).
# Do NOT switch to /etc/os-release: that would exit early and skip
# kernel-install, bringing the bug back.
grep -q '^NAME="Herd"' %{_prefix}/lib/os-release 2>/dev/null && exit 0
cp -f %{_datadir}/capivaraos-herd/os-release %{_sysconfdir}/os-release
cp -f %{_datadir}/capivaraos-herd/issue      %{_sysconfdir}/issue
for kver in $(ls /lib/modules 2>/dev/null); do
    [ -f "/lib/modules/${kver}/vmlinuz" ] && \
        kernel-install add "${kver}" "/lib/modules/${kver}/vmlinuz" >/dev/null 2>&1 || true
done
# Fix the title of ALL entries (normal and rescue) to our name. The
# kernel-install above does not rewrite existing entries; the script sets the
# title from /etc/os-release (already fixed above). Same script as %posttrans
# and the kickstart %post.
sh %{_datadir}/capivaraos-herd/fix-bls-titles.sh 2>/dev/null || true

%files
%dir %{_datadir}/capivaraos-herd
%{_datadir}/capivaraos-herd/os-release
%{_datadir}/capivaraos-herd/issue
%{_datadir}/capivaraos-herd/fix-bls-titles.sh
%{_sysconfdir}/motd.d/capivaraos-herd
%dir %{_datadir}/cockpit/branding/capivaraos-herd
%{_datadir}/cockpit/branding/capivaraos-herd/branding.css
%{_datadir}/cockpit/branding/capivaraos-herd/logo.png
%{_datadir}/cockpit/branding/capivaraos-herd/apple-touch-icon.png
%{_datadir}/cockpit/branding/capivaraos-herd/favicon.ico
%config(noreplace) %{_sysconfdir}/cockpit/*.override.json
%dir %{_datadir}/capivaraos-herd/fastfetch
%{_datadir}/capivaraos-herd/fastfetch/capivara.txt
%{_sysconfdir}/skel/.config/fastfetch/
%{_sysconfdir}/xdg/fastfetch/

%changelog
* Wed Nov 18 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-3.herd
- Changelog text revised. No functional change.

* Tue Nov 17 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-2.herd
- os-release VERSION_ID is the Fedora release (45). The Herd version stays in
  VERSION, PRETTY_NAME and CPE_NAME.
- A Cockpit manifest override for packagekit removes its docs.redhat.com Help
  link, as for the other Cockpit packages.

* Tue Nov 17 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-1.herd
- Herd 2.0.0 release: os-release names the release "2.0.0 (Community)".

* Thu Nov 12 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-0.5.alpha1.herd
- Comments in the Cockpit CSS, the fastfetch config and the spec are in
  English. No change to colours, layout or behaviour.
- Cockpit CSS: SPDX tag set to GPL-3.0-or-later, matching the package License.

* Tue Oct 13 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-0.3.alpha1.herd
- Identidade azul-marinho do Herd: Cockpit e fastfetch passam de verde
  para azul-marinho #1E2F4E + logo BRANCA, como o avatar da marca. Cockpit: fundo
  de login e accent do host -> navy; badge passa a usar o avatar da marca
  (src/avatar-navy-branca.png) — como a página é do mesmo navy, fica só a logo
  branca sobre o fundo navy; favicon/apple-touch com tile navy.
- fastfetch: config.jsonc passa a listar "modules" (conjunto de
  servidor) — sem isso, nesta versão do fastfetch um config carregado imprimia SÓ
  o logo, sem as infos do sistema. Cor do logo (silhueta + nome) -> BRANCA.
  Testado em VM.

* Tue Oct 13 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-0.2.alpha1.herd
- Logo próprio do CapivaraOS no fastfetch: o painel ASCII do
  terminal deixa de mostrar o logo do Fedora (que o fastfetch escolhia por ID_LIKE
  do os-release) e passa a exibir a cabeça de capivara da marca + "Herd by
  CapivaraOS" em VERDE (#15B22C). Arte em /usr/share/capivaraos-herd/fastfetch/
  capivara.txt; config.jsonc (só o logo) em /etc/xdg/fastfetch/ (vale p/ root e
  todos os usuários via XDG_CONFIG_DIRS, sem precisar configurar) e em
  /etc/skel/.config/fastfetch/ (novos usuários). SEM auto-run — aparece só quando
  o admin roda `fastfetch` (pacote fastfetch adicionado ao payload no
  kickstart/blueprint).
- O config.jsonc lista os "modules" (conjunto voltado a servidor: os/host/kernel/
  uptime/load/packages/shell/cpu/memory/swap/disk/localip/locale): sem a chave o
  fastfetch imprimiria SÓ o logo (nesta versão um config carregado define todo o
  output). A silhueta da capivara usa a cor da marca (verde #15B22C), não a cor
  default do fastfetch. Testado em VM (render com logo verde + infos do sistema).

* Sun Sep 20 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-0.1.alpha1.herd
- Início da geração 2.x (rebase para Fedora 45). os-release/issue/motd para
  2.0.0 pré-lançamento; VERSION_ID/VERSION/CPE -> 2.0.0; PLATFORM_ID ->
  platform:f45. Release 0.1.alpha1 (NEVRA < 2.0.0-1). IDs técnicos (ID, ID_LIKE,
  LOGO) inalterados.

* Fri Aug 28 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-10.herd
- Rebrand da identidade para a linha "Herd by CapivaraOS" + versão do produto
  1.0.0 -> 1.0.1. Esquema misto: os-release NAME="Herd" (GRUB/Cockpit curtos)
  e PRETTY_NAME="Herd by CapivaraOS 1.0.1 (Community)"; /etc/issue e MOTD com a
  forma completa "Herd by CapivaraOS 1.0.1". VERSION_ID/VERSION/CPE -> 1.0.1.
  IDs técnicos (ID, ID_LIKE, PLATFORM_ID, LOGO) inalterados. Guarda do
  %transfiletriggerin ajustada para o novo NAME (comportamento idêntico — o
  /usr/lib/os-release segue sendo o do Fedora, então nunca curto-circuita).
  fix-bls-titles.sh deriva o título do GRUB do os-release → "Herd (kver) 1.0.1
  (Community)".
- Aponta a documentação para o local real: DOCUMENTATION_URL e a linha do MOTD
  passam a https://docs.capivaraos.org/pt/herd/ (antes capivaraos.org/docs/herd,
  link morto). SUPPORT_URL passa a .../pt/herd/suporte/. Os links de docs do
  os-release e do Cockpit deixam de ser mortos.

* Wed Aug 12 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-8.herd
- Cockpit: cobre TODOS os pacotes que traziam links docs.redhat.com no menu
  Ajuda. Além de shell e systemd, adiciona overrides para users, networkmanager
  e storaged (a página de Contas ainda mostrava "Managing user accounts" → Red
  Hat). Instalação por glob de /etc/cockpit/*.override.json (pega overrides
  futuros). Também reclassifica License (código GPLv3, arte = trademark do
  projeto — ver TRADEMARK.md), resolvendo o CC-BY-SA-4.0 anterior.

* Tue Aug 11 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-7.herd
- Corrige o corte da logo no badge do Cockpit: a logo branca era redimensionada
  só pela largura e ficava mais alta que o tile, cortando em cima/embaixo. Agora
  limita largura E altura (cabe inteira); tile ajustado (640x360, 2x).
- Remove do menu Ajuda do Cockpit os links que iam para docs.redhat.com
  (shell "Web Console" e systemd "Configurando/Managing/Reviewing"): overrides
  /etc/cockpit/{shell,systemd}.override.json zeram os "docs" desses manifests.
  Sobra o link de docs do CapivaraOS (via DOCUMENTATION_URL do os-release).

* Tue Aug 11 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-6.herd
- Corrige o título do menu de boot (GRUB/BLS) também no caminho osbuild/qcow2,
  que ficava "Fedora Linux ... Cloud Edition": a correção dos títulos vira um
  script único (fix-bls-titles.sh) chamado pelo %posttrans (qcow2), pelo
  %transfiletriggerin (updates) e pelo %post do kickstart (ISO). Reescreve
  normais + rescue, preservando o token do kernel/rescue; idempotente.
- Cockpit passa a IDENTIDADE VERDE (cor do site): fundo de login verde #2f7a3d,
  badge com tile verde-escuro #163d1e e a logo BRANCA da capivara, accent do
  host verde. Um único logo.png serve claro/escuro (dispensa logo-dark.png);
  favicon/apple-touch viram a cabeça branca sobre tile verde.

* Tue Aug 11 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-5.herd
- Adiciona branding visual do Cockpit (console web): instala
  /usr/share/cockpit/branding/capivaraos-herd/ (escolhido pelo ID do os-release)
  com branding.css (accent marrom #6B4F36, título de login), logo.png (tema
  claro) e logo-dark.png (tema escuro), favicon.ico e apple-touch-icon.png,
  gerados no %build a partir das logos da marca (BuildRequires ImageMagick).

* Mon Aug 10 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-4.herd
- Corrige também o título da entrada de RESCUE no GRUB (ficava "Fedora Linux"):
  o trigger passa a reescrever a linha 'title' das entradas *rescue*.conf
  derivando NAME/VERSION do nosso os-release, preservando o token 0-rescue-<id>.
  Só edita o texto do título (não mexe em kernel/initramfs); idempotente.

* Mon Aug 10 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-3.herd
- Corrige título "Fedora Linux" no GRUB do sistema instalado pela ISO: a guarda
  do %transfiletriggerin passa a checar /usr/lib/os-release (nunca reescrito por
  nós) em vez de /etc/os-release. Assim o trigger não sai cedo e sempre roda o
  kernel-install DEPOIS do os-release corrigido, gravando o título BLS certo.
  (No Anaconda o kernel-install roda antes do nosso %posttrans; a guarda em
  /etc curto-circuitava e pulava a correção do BLS.)

* Sun Aug 09 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-2.herd
- Não declara mais /etc/os-release e /etc/issue no %files: eram donos do
  fedora-release-common e o rpm --install do osbuild falhava com conflito de
  arquivo (exit 2). Agora o conteúdo é escrito em %posttrans e reaplicado por
  %transfiletriggerin -- /usr/lib (com kernel-install para o título BLS),
  mesmo padrão já validado nos desktops.

* Sat Aug 08 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-1.herd
- Branding inicial do HERD Community (os-release, issue, motd).
