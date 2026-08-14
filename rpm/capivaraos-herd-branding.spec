# capivaraos-herd-branding — identidade do CapivaraOS HERD (servidor headless)
#
# Diferente do branding dos desktops (wallpapers, SDDM, tema Plasma), o HERD é
# headless: o branding é textual (/etc/os-release, /etc/issue, motd) + o console
# web (Cockpit). Também corrige os títulos do menu de boot (GRUB/BLS) para a
# marca CapivaraOS via um script único (PROD-66/PROD-67).

Name:           capivaraos-herd-branding
Version:        1.0.0
# Sufixo ".herd": todas as spins constroem um pacote de branding e compartilham
# ~/rpmbuild na mesma máquina. Sem um sufixo de linha, duas na mesma
# Version-Release gerariam nomes de arquivo idênticos — já causou incidentes
# nos desktops (BUG-30). Com o sufixo a colisão é impossível por construção.
Release:        9%{?dist}.herd
Summary:        Identidade (os-release, issue, motd, Cockpit) do CapivaraOS HERD Community

# Código (os-release/issue/motd, script BLS) sob GPLv3; a arte de logo do Cockpit
# é marca registrada do projeto (ver TRADEMARK.md).
License:        GPL-3.0-or-later AND LicenseRef-CapivaraOS-Trademark
URL:            https://capivaraos.org
BuildArch:      noarch

Source0:        %{name}-%{version}.tar.gz

# Gera a arte do branding do Cockpit (logo/ícones) a partir das logos da marca.
BuildRequires:  ImageMagick

Provides:       system-release-branding = %{version}-%{release}

# NB: NÃO declaramos "Requires: cockpit-ws". O diretório de branding é inerte sem
# o Cockpit, e o Cockpit já entra no payload do HERD (kickstart/blueprint). Um
# Requires acoplaria este pacote de identidade à instalação do Cockpit sem ganho.

%description
Pacote de identidade do CapivaraOS HERD Community: /etc/os-release,
/etc/issue e mensagem do dia (/etc/motd.d/capivaraos-herd). Voltado a
servidor headless com base Fedora 44.

%prep
%setup -q

%build
# ── Arte do branding do Cockpit (identidade VERDE, cor do site) ─────────────
# Badge do login: tile verde arredondado (verde-escuro #163d1e) com a logo
# BRANCA da capivara centralizada — "logo com fundo verde", que lê bem tanto na
# página de login (fundo verde #2f7a3d) quanto no shell interno (fundo claro).
# Um único asset serve aos dois temas (claro/escuro), sem precisar de logo-dark.
# Renderizado em 2x (640x360) p/ hidpi; o CSS usa background-size: contain.
# IMPORTANTE: a logo é redimensionada limitando LARGURA **e ALTURA** (560x300)
# para caber inteira no tile — só limitar a largura a deixava mais alta que o
# tile e cortava em cima/embaixo (bug visto no -6).
cd cockpit
convert -size 640x360 xc:none \
    -fill '#163d1e' -draw 'roundrectangle 0,0,639,359,52,52' \
    \( src/capivaraos-logo-branca.png -resize 560x300 \) -gravity center -composite \
    logo.png
# Ícones (cabeça branca sobre tile verde), quadrados: aba do navegador e iOS.
convert -size 180x180 xc:none \
    -fill '#163d1e' -draw 'roundrectangle 0,0,179,179,32,32' \
    \( src/capivaraos-cabeca-branca.png -resize 132x \) -gravity center -composite \
    apple-touch-icon.png
convert apple-touch-icon.png -define icon:auto-resize=16,32,48 favicon.ico
cd -

%install
# os-release e issue NÃO vão para /etc no %files (ver NOTA abaixo). Ficam num
# datadir privado como fonte de verdade, e os scriptlets copiam para /etc.
install -d %{buildroot}%{_datadir}/capivaraos-herd
install -m 0644 os-release %{buildroot}%{_datadir}/capivaraos-herd/os-release
install -m 0644 issue      %{buildroot}%{_datadir}/capivaraos-herd/issue
# Script único de correção dos títulos BLS do GRUB (chamado pelos scriptlets e
# pelo %post do kickstart — ver comentários no %posttrans/%transfiletriggerin).
install -m 0755 fix-bls-titles.sh %{buildroot}%{_datadir}/capivaraos-herd/fix-bls-titles.sh
# motd.d/capivaraos-herd é um arquivo NOVO (ninguém mais o possui) — pode ir
# normalmente no %files.
install -D -m 0644 motd    %{buildroot}%{_sysconfdir}/motd.d/capivaraos-herd

# ── Branding do Cockpit (console web) ───────────────────────────────────────
# Diretório escolhido pelo Cockpit via ID=capivaraos-herd do /etc/os-release.
# Só possuímos o NOSSO subdiretório (o /usr/share/cockpit/branding é do cockpit).
install -d %{buildroot}%{_datadir}/cockpit/branding/capivaraos-herd
install -m 0644 cockpit/branding.css cockpit/logo.png \
    cockpit/apple-touch-icon.png cockpit/favicon.ico \
    %{buildroot}%{_datadir}/cockpit/branding/capivaraos-herd/

# ── Overrides de manifest do Cockpit ────────────────────────────────────────
# Remove os links de documentação que apontam para docs.redhat.com no menu Ajuda
# (mecanismo oficial e estável do Cockpit: /etc/cockpit/<pacote>.override.json,
# mesclado sobre o manifest.json do pacote). Assim o menu fica com o nosso link
# de docs (derivado do DOCUMENTATION_URL do os-release) + "Sobre", sem Red Hat.
# Cobre os 5 pacotes que trazem links docs.redhat.com: shell, systemd, users,
# networkmanager e storaged. Instala via glob p/ pegar qualquer override novo.
install -d %{buildroot}%{_sysconfdir}/cockpit
install -m 0644 cockpit/overrides/*.override.json %{buildroot}%{_sysconfdir}/cockpit/

# NOTA CapivaraOS: /etc/os-release e /etc/issue pertencem ao
# fedora-release-common. Tê-los no %files causa "conflito de arquivo" no rpm
# durante a instalação (o build da imagem falha com exit 2). Por isso são
# escritos direto no sistema em %posttrans (roda no fim da transação, então
# nosso conteúdo prevalece) e reaplicados por %transfiletriggerin após updates.

%posttrans
# Grava nossa identidade sobre a do Fedora (fim da transação).
cp -f %{_datadir}/capivaraos-herd/os-release %{_sysconfdir}/os-release
cp -f %{_datadir}/capivaraos-herd/issue      %{_sysconfdir}/issue
# Corrige os títulos do menu de boot (GRUB/BLS). No caminho osbuild (qcow2) o
# kernel-install já criou as entradas com a marca Fedora ANTES deste %posttrans;
# como não há kickstart nesse caminho, é AQUI que a correção precisa acontecer.
# O os-release acima já é o nosso, então o script deriva o título certo.
sh %{_datadir}/capivaraos-herd/fix-bls-titles.sh 2>/dev/null || true

# ── Reaplica os-release/issue após qualquer atualização futura do sistema ───
# Como /etc/os-release continua pertencendo ao Fedora no rpmdb, um "dnf update"
# que toque o pacote dono reescreve tudo de volta para o padrão do Fedora. Se
# isso ocorrer na MESMA transação de um kernel novo, o título GRUB/BLS desse
# kernel (gerado por kernel-install a partir de NAME/VERSION do os-release)
# fica gravado como "Fedora Linux ..." — e preso assim para sempre. Por isso
# reaplicamos e regravamos o BLS.
#
# ATENÇÃO — NÃO troque o prefixo por um caminho de arquivo exato: verificado
# empiricamente (fedora:44) que %transfiletriggerin casa APENAS com prefixos
# de DIRETÓRIO, nunca com caminho de arquivo. Por isso vigiamos o diretório
# %{_prefix}/lib (onde vive o os-release "real" do Fedora). Ver
# [[reference_rpm_filetriggers]].
%transfiletriggerin -- %{_prefix}/lib
# Guarda: checamos o /usr/lib/os-release (que NUNCA é reescrito por nós — só
# mexemos no /etc/os-release). Como ele fica sempre com o NAME do Fedora, esta
# condição NÃO curto-circuita, e o trigger sempre reaplica + roda kernel-install.
# ISSO É PROPOSITAL: o kernel-install precisa rodar DEPOIS do os-release estar
# corrigido para gravar o título BLS certo (senão o GRUB fica "Fedora Linux ..."
# — foi o bug do instalador, o kernel-install do Anaconda roda antes do nosso
# %posttrans). NÃO troque para /etc/os-release: isso faria sair cedo e pular o
# kernel-install, reintroduzindo o bug.
grep -q '^NAME="CapivaraOS HERD"' %{_prefix}/lib/os-release 2>/dev/null && exit 0
cp -f %{_datadir}/capivaraos-herd/os-release %{_sysconfdir}/os-release
cp -f %{_datadir}/capivaraos-herd/issue      %{_sysconfdir}/issue
for kver in $(ls /lib/modules 2>/dev/null); do
    [ -f "/lib/modules/${kver}/vmlinuz" ] && \
        kernel-install add "${kver}" "/lib/modules/${kver}/vmlinuz" >/dev/null 2>&1 || true
done
# Corrige o título de TODAS as entradas (normais + rescue) para a nossa marca.
# O kernel-install acima não reescreve entradas já existentes; o script força o
# título a partir do /etc/os-release (já corrigido acima). Fonte única com o
# %posttrans e o %post do kickstart.
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

%changelog
* Wed Aug 12 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-9.herd
- Aponta a documentação para o local real: DOCUMENTATION_URL e a linha do MOTD
  passam a https://docs.capivaraos.org/pt/herd/ (antes capivaraos.org/docs/herd,
  link morto). SUPPORT_URL passa a .../pt/herd/suporte/. Os links de docs do
  os-release e do Cockpit deixam de ser mortos (docs publicados em PROD-71).

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
