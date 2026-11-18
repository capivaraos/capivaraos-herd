# capivaraos-herd-repos: configuration of the Herd update repository
#
# Points the installed system at the signed CapivaraOS Herd update repository
# and ships the public keys that verify its packages and metadata. Without it
# an installed Herd receives Fedora updates but not the Herd packages. Both
# build paths (kickstart %packages and the osbuild blueprint) include it.
#
# Config files and public keys only, no scriptlets. rpm refuses to import a
# key from a scriptlet (it cannot take the keyring lock during the
# transaction). Instead a dnf5-automatic.service drop-in (Source3) imports
# both keys before each unattended run: into the rpm keyring, for package
# signatures, and, through a makecache of the two Herd repositories, into
# dnf5's key store for repository metadata (a step that can fail without
# stopping the run). An interactive dnf asks and imports them from gpgkey=.

Name:           capivaraos-herd-repos
Version:        2.0.0
# ".herd" suffix, as in branding, hardening and logos: keeps the NEVRA apart
# from the other editions' packages in a shared ~/rpmbuild.
Release:        1%{?dist}.herd
Summary:        Signed update repository configuration for CapivaraOS Herd

# Our configuration and our public keys only. GPLv3 covers the configuration;
# the keys are the project's cryptographic material (no software licence).
License:        GPL-3.0-or-later
URL:            https://capivaraos.org
BuildArch:      noarch

# Plain files, not a tarball: build-rpm-repos.sh copies them to
# ~/rpmbuild/SOURCES.
Source0:        capivaraos-herd.repo
Source1:        RPM-GPG-KEY-capivaraos-herd
# Reserve signing key (public part), trusted alongside the current one.
Source2:        RPM-GPG-KEY-capivaraos-herd-reserve
Source3:        50-capivaraos-herd-keys.conf

# Canonical "*-release" name that other packages or documentation may require.
Provides:       capivaraos-herd-release = %{version}-%{release}

%description
Configuration of the signed CapivaraOS Herd update repository: installs
/etc/yum.repos.d/capivaraos-herd.repo (stable and testing channels), the two
public Herd signing keys in /etc/pki/rpm-gpg/, and a drop-in for
dnf5-automatic.service that imports those keys before each unattended run.
Packages and repository metadata are signature-checked (gpgcheck and
repo_gpgcheck). Only public keys are distributed here.

# No %prep or %build: the sources are plain files, with nothing to unpack or build.

%install
install -D -m 0644 %{SOURCE0} \
    %{buildroot}%{_sysconfdir}/yum.repos.d/capivaraos-herd.repo
install -D -m 0644 %{SOURCE1} \
    %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd
install -D -m 0644 %{SOURCE2} \
    %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd-reserve
install -D -m 0644 %{SOURCE3} \
    %{buildroot}%{_prefix}/lib/systemd/system/dnf5-automatic.service.d/50-capivaraos-herd-keys.conf

%files
%config(noreplace) %{_sysconfdir}/yum.repos.d/capivaraos-herd.repo
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd-reserve
%dir %{_prefix}/lib/systemd/system/dnf5-automatic.service.d
%{_prefix}/lib/systemd/system/dnf5-automatic.service.d/50-capivaraos-herd-keys.conf

%changelog
* Tue Nov 17 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-1.herd
- Herd 2.0.0 release. No functional change.

* Sun Nov 15 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-0.4.alpha1.herd
- Ships the Herd reserve signing key (fingerprint
  F4EF73FAF6157390BB6538FFA765804F4ADA507E) next to the current one, and
  lists both in gpgkey=.
- A drop-in for dnf5-automatic.service imports both keys before each
  unattended run: into the rpm keyring, and through a makecache of the two
  Herd repositories into dnf5's key store for metadata checks (a step that
  can fail without stopping the run).
- %%post no longer tries to import the keys; rpm refuses key imports from a
  scriptlet.

* Sun Nov 15 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-0.3.alpha1.herd
- No functional change to the repository configuration.

* Tue Nov 10 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-0.2.alpha1.herd
- Repository address is https://repo-herd.capivaraos.org/f$releasever/, the
  dedicated Herd update host. Same signing key; $releasever still follows a
  system upgrade.

* Mon Sep 21 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 2.0.0-0.1.alpha1.herd
- Geração 2.x (Fedora 45): bump de versão. baseurl usa
  $releasever (via system-release), então o repo acompanha sozinho o system-upgrade
  F44->F45 — sem mudança funcional.

* Sat Aug 29 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-1.herd
- Pacote inicial de configuração de repositório: instala o
  capivaraos-herd.repo (canais stable + testing, gpgcheck + repo_gpgcheck) e a
  chave GPG pública em /etc/pki/rpm-gpg/, importada no chaveiro do rpm no %post.
  Fecha a lacuna crítica em que um Herd instalado não recebia os pacotes próprios
  do projeto (só os do Fedora). baseurl usa $releasever (base Fedora, via
  system-release(releasever)) → acompanha sozinho o system-upgrade F44->F45.
  ATENÇÃO: não embarcar numa ISO antes de repo.capivaraos.org/herd/ estar no ar
  (senão todo `dnf` no sistema instalado avisa repo inacessível). Ver
  docs/repo/README.md.
