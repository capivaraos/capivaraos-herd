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
Release:        5%{?dist}.herd
Summary:        Identidade (os-release, issue, motd, Cockpit) do CapivaraOS HERD Community

License:        CC-BY-SA-4.0
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
# ── Arte do branding do Cockpit ─────────────────────────────────────────────
# Badge do login: logo horizontal, marrom p/ tema claro e branca p/ tema escuro
# (modelo RHEL/CentOS). Renderizada em 2x (450x160) para telas hidpi; o CSS usa
# background-size: contain na caixa de 225x80.
cd cockpit
convert src/capivaraos-logo-marrom.png -resize 450x160 logo.png
convert src/capivaraos-logo-branca.png -resize 450x160 logo-dark.png
# Ícones (cabeça da capivara), quadrados: aba do navegador e atalho iOS.
convert src/capivaraos-cabeca-marrom.png -resize 180x180 apple-touch-icon.png
convert src/capivaraos-cabeca-marrom.png -define icon:auto-resize=16,32,48 favicon.ico
cd -

%install
# os-release e issue NÃO vão para /etc no %files (ver NOTA abaixo). Ficam num
# datadir privado como fonte de verdade, e os scriptlets copiam para /etc.
install -d %{buildroot}%{_datadir}/capivaraos-herd
install -m 0644 os-release %{buildroot}%{_datadir}/capivaraos-herd/os-release
install -m 0644 issue      %{buildroot}%{_datadir}/capivaraos-herd/issue
# motd.d/capivaraos-herd é um arquivo NOVO (ninguém mais o possui) — pode ir
# normalmente no %files.
install -D -m 0644 motd    %{buildroot}%{_sysconfdir}/motd.d/capivaraos-herd

# ── Branding do Cockpit (console web) ───────────────────────────────────────
# Diretório escolhido pelo Cockpit via ID=capivaraos-herd do /etc/os-release.
# Só possuímos o NOSSO subdiretório (o /usr/share/cockpit/branding é do cockpit).
install -d %{buildroot}%{_datadir}/cockpit/branding/capivaraos-herd
install -m 0644 cockpit/branding.css cockpit/logo.png cockpit/logo-dark.png \
    cockpit/apple-touch-icon.png cockpit/favicon.ico \
    %{buildroot}%{_datadir}/cockpit/branding/capivaraos-herd/

# NOTA CapivaraOS: /etc/os-release e /etc/issue pertencem ao
# fedora-release-common. Tê-los no %files causa "conflito de arquivo" no rpm
# durante a instalação (o build da imagem falha com exit 2). Por isso são
# escritos direto no sistema em %posttrans (roda no fim da transação, então
# nosso conteúdo prevalece) e reaplicados por %transfiletriggerin após updates.

%posttrans
# Grava nossa identidade sobre a do Fedora (fim da transação).
cp -f %{_datadir}/capivaraos-herd/os-release %{_sysconfdir}/os-release
cp -f %{_datadir}/capivaraos-herd/issue      %{_sysconfdir}/issue

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
# A entrada de RESCUE é gerada uma única vez por um plugin próprio e não é
# regravada pelo kernel-install acima; seu título fica com a marca antiga
# ("Fedora Linux ..."). Corrigimos só a linha 'title' (não toca kernel/initramfs),
# preservando o token "0-rescue-<id>", derivando o nome do nosso os-release.
if [ -r %{_sysconfdir}/os-release ]; then
    ( . %{_sysconfdir}/os-release
      for e in /boot/loader/entries/*rescue*.conf; do
          [ -f "$e" ] || continue
          grep -q "^title ${NAME} " "$e" && continue
          rid="$(sed -n 's/^title .*(\(0-rescue-[^)]*\)).*/\1/p' "$e")"
          if [ -n "$rid" ]; then
              sed -i "s|^title .*|title ${NAME} (${rid}) ${VERSION}|" "$e"
          else
              sed -i "s|^title .*|title ${NAME} (rescue) ${VERSION}|" "$e"
          fi
      done ) 2>/dev/null || true
fi

%files
%dir %{_datadir}/capivaraos-herd
%{_datadir}/capivaraos-herd/os-release
%{_datadir}/capivaraos-herd/issue
%{_sysconfdir}/motd.d/capivaraos-herd
%dir %{_datadir}/cockpit/branding/capivaraos-herd
%{_datadir}/cockpit/branding/capivaraos-herd/branding.css
%{_datadir}/cockpit/branding/capivaraos-herd/logo.png
%{_datadir}/cockpit/branding/capivaraos-herd/logo-dark.png
%{_datadir}/cockpit/branding/capivaraos-herd/apple-touch-icon.png
%{_datadir}/cockpit/branding/capivaraos-herd/favicon.ico

%changelog
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
