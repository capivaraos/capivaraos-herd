# capivaraos-herd-upgrade — upgrade de versão in-place do servidor (PROD-107)
#
# Entrega a ferramenta `herd-upgrade`, um invólucro auditável do
# `dnf5 system-upgrade` (transação offline no reboot) pensado para o servidor
# headless: pré-voo com FALHA FECHADA (recusa se o nosso repo assinado ainda não
# existir para a versão de destino), download e reboot como passos SEPARADOS e
# explícitos, e snapshot pré-upgrade quando o storage suporta.
#
# Fecha, com PROD-104/105 (repo assinado) e PROD-106 (updates automáticos), o
# ciclo do PROD-102: além de receber correções contínuas, o Herd instalado passa
# a poder SUBIR DE VERSÃO sem formatar. A UI (agendar/aplicar pela página de
# Updates do Herd Control) é o PROD-108 e reusa esta mesma ferramenta.
#
# O subcomando `system-upgrade` é embutido no core do dnf5 no Fedora 44+ (não há
# pacote de plugin separado) — por isso a dependência é só `dnf5`.

Name:           capivaraos-herd-upgrade
Version:        1.0.0
# Sufixo ".herd": convenção das outras spins (evita colisão de NEVRA em
# ~/rpmbuild compartilhado — BUG-30).
Release:        1%{?dist}.herd
Summary:        Upgrade de versão in-place (dnf5 system-upgrade) do CapivaraOS Herd

License:        GPL-3.0-or-later
URL:            https://capivaraos.org
BuildArch:      noarch

Source0:        herd-upgrade

# O comando system-upgrade é embutido no core do dnf5 (Fedora 44+).
Requires:       dnf5
# Garante que o .repo assinado e a chave GPG estejam presentes: sem eles o
# pré-voo não tem como confirmar o repositório do Herd na versão de destino.
Requires:       capivaraos-herd-repos

Provides:       system-version-upgrade = %{version}-%{release}

%description
Ferramenta `herd-upgrade` do CapivaraOS Herd Community: sobe o servidor para a
próxima versão SEM formatar, usando a transação offline do dnf5
(`dnf5 system-upgrade`). Segue a marca de auditabilidade: por padrão só faz
verificação (pré-voo); baixar e reiniciar são passos explícitos e separados; o
pré-voo FALHA FECHADA se o repositório assinado do Herd ainda não existir para a
versão de destino (para não deixar os pacotes do Herd para trás); e cria snapshot
antes do upgrade quando o storage é compatível (snapper/btrfs). A confiança vem
da assinatura GPG do repositório (gpgcheck + repo_gpgcheck): a transação recusa
pacote ou metadado não assinado pela nossa chave.

%install
install -D -m 0755 %{SOURCE0} %{buildroot}%{_bindir}/herd-upgrade

%files
%{_bindir}/herd-upgrade

%changelog
* Mon Aug 31 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-1.herd
- Pacote inicial de upgrade de versão in-place (PROD-107): ferramenta
  `herd-upgrade`, invólucro auditável do dnf5 system-upgrade (download + reboot
  offline). Pré-voo com falha fechada quando o repo assinado do Herd não existe
  na versão de destino; destino derivado de `rpm -E %%fedora` (atual+1) ou --to N;
  snapshot pré-upgrade via snapper quando disponível (LVM é reportado). Requires
  dnf5 + capivaraos-herd-repos. Fecha, com PROD-104/105/106, o ciclo do PROD-102.
