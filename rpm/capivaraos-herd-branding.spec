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
Release:        2%{?dist}.herd
Summary:        Identidade (os-release, issue, motd) do CapivaraOS HERD Community

License:        CC-BY-SA-4.0
URL:            https://capivaraos.org
BuildArch:      noarch

Source0:        %{name}-%{version}.tar.gz

Provides:       system-release-branding = %{version}-%{release}

%description
Pacote de identidade do CapivaraOS HERD Community: /etc/os-release,
/etc/issue e mensagem do dia (/etc/motd.d/capivaraos-herd). Voltado a
servidor headless com base Fedora 44.

%prep
%setup -q

%install
# os-release e issue NÃO vão para /etc no %files (ver NOTA abaixo). Ficam num
# datadir privado como fonte de verdade, e os scriptlets copiam para /etc.
install -d %{buildroot}%{_datadir}/capivaraos-herd
install -m 0644 os-release %{buildroot}%{_datadir}/capivaraos-herd/os-release
install -m 0644 issue      %{buildroot}%{_datadir}/capivaraos-herd/issue
# motd.d/capivaraos-herd é um arquivo NOVO (ninguém mais o possui) — pode ir
# normalmente no %files.
install -D -m 0644 motd    %{buildroot}%{_sysconfdir}/motd.d/capivaraos-herd

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
# Caso comum: nosso os-release intacto → nada a fazer.
grep -q '^NAME="CapivaraOS HERD"' %{_sysconfdir}/os-release 2>/dev/null && exit 0
cp -f %{_datadir}/capivaraos-herd/os-release %{_sysconfdir}/os-release
cp -f %{_datadir}/capivaraos-herd/issue      %{_sysconfdir}/issue
for kver in $(ls /lib/modules 2>/dev/null); do
    [ -f "/lib/modules/${kver}/vmlinuz" ] && \
        kernel-install add "${kver}" "/lib/modules/${kver}/vmlinuz" >/dev/null 2>&1 || true
done

%files
%dir %{_datadir}/capivaraos-herd
%{_datadir}/capivaraos-herd/os-release
%{_datadir}/capivaraos-herd/issue
%{_sysconfdir}/motd.d/capivaraos-herd

%changelog
* Sun Aug 09 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-2.herd
- Não declara mais /etc/os-release e /etc/issue no %files: eram donos do
  fedora-release-common e o rpm --install do osbuild falhava com conflito de
  arquivo (exit 2). Agora o conteúdo é escrito em %posttrans e reaplicado por
  %transfiletriggerin -- /usr/lib (com kernel-install para o título BLS),
  mesmo padrão já validado nos desktops.

* Sat Aug 08 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-1.herd
- Branding inicial do HERD Community (os-release, issue, motd).
