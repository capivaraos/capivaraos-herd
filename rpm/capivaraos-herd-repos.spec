# capivaraos-herd-repos — configuração do repositório de updates do Herd
#
# Entrega, ao sistema INSTALADO, o apontamento para o repositório de atualizações
# assinado do CapivaraOS Herd + a chave GPG pública que valida pacotes e
# metadados (PROD-105). É o pacote que FECHA A LACUNA: sem ele, um Herd instalado
# recebe updates do Fedora mas NUNCA os nossos (os RPMs próprios só existiam
# offline dentro da ISO). Embarcado na imagem via %packages do kickstart e via
# blueprint osbuild — os dois caminhos de build.
#
# Só arquivos de config + chave (sem scriptlets que toquem arquivos de
# terceiros). O %post apenas importa a chave pública no chaveiro do rpm, para o
# gpgcheck funcionar de imediato, sem o prompt de "importar chave?".

Name:           capivaraos-herd-repos
Version:        1.0.0
# Sufixo ".herd": mesma convenção do branding/hardening/logos — evita colisão de
# NEVRA no ~/rpmbuild compartilhado entre as spins (ver BUG-30).
Release:        1%{?dist}.herd
Summary:        Repositório de atualizações assinado do CapivaraOS Herd (Community)

# Só config nossa (.repo) + a nossa chave pública. GPLv3 cobre a config; a chave
# é material criptográfico do projeto (sem licença de software).
License:        GPL-3.0-or-later
URL:            https://capivaraos.org
BuildArch:      noarch

# Arquivos soltos (não um tarball): o .repo e a chave pública são copiados para
# ~/rpmbuild/SOURCES pelo build-rpm-repos.sh.
Source0:        capivaraos-herd.repo
Source1:        RPM-GPG-KEY-capivaraos-herd

# Nome canônico "*-release" que outros pacotes/documentação podem exigir.
Provides:       capivaraos-herd-release = %{version}-%{release}

%description
Configuração do repositório de atualizações assinado do CapivaraOS Herd
Community: instala /etc/yum.repos.d/capivaraos-herd.repo (canais stable e
testing) e a chave GPG pública em /etc/pki/rpm-gpg/, importando-a no chaveiro
do rpm. A partir daí um Herd instalado recebe automaticamente os pacotes
próprios do projeto (capivaraos-herd-*, herd-harden, herd-compliance-scan e
correções de segurança), com verificação de assinatura de pacote e de metadados
(gpgcheck + repo_gpgcheck). A chave privada de assinatura permanece offline; só
a pública é distribuída aqui.

# Sem %prep/%build: os sources são arquivos soltos, não há o que extrair/compilar.

%install
install -D -m 0644 %{SOURCE0} \
    %{buildroot}%{_sysconfdir}/yum.repos.d/capivaraos-herd.repo
install -D -m 0644 %{SOURCE1} \
    %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd

%post
# Importa a chave pública no chaveiro do rpm para o gpgcheck funcionar sem o
# prompt interativo "importar esta chave GPG?" no primeiro update. Idempotente
# (reimportar a mesma chave é no-op). Funciona OFFLINE (a chave está no disco),
# então roda bem também no %post do install via ISO.
if [ -x /usr/bin/rpmkeys ]; then
    rpmkeys --import %{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd \
        >/dev/null 2>&1 || true
fi

%files
%config(noreplace) %{_sysconfdir}/yum.repos.d/capivaraos-herd.repo
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd

%changelog
* Sat Aug 29 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-1.herd
- Pacote inicial de configuração de repositório (PROD-105): instala o
  capivaraos-herd.repo (canais stable + testing, gpgcheck + repo_gpgcheck) e a
  chave GPG pública em /etc/pki/rpm-gpg/, importada no chaveiro do rpm no %post.
  Fecha a lacuna crítica em que um Herd instalado não recebia os pacotes próprios
  do projeto (só os do Fedora). baseurl usa $releasever (base Fedora, via
  system-release(releasever)) → acompanha sozinho o system-upgrade F44->F45.
  ATENÇÃO: não embarcar numa ISO antes de repo.capivaraos.org/herd/ estar no ar
  (senão todo `dnf` no sistema instalado avisa repo inacessível). Ver
  docs/repo/README.md.
