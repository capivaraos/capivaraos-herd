# capivaraos-herd-hardening — perfil básico de segurança do CapivaraOS HERD
#
# Entrega a configuração de hardening do HERD Community como ARQUIVOS (sem
# scriptlets que mexam em arquivos de terceiros), instalada nos DOIS caminhos de
# build (qcow2/osbuild via blueprint, ISO via kickstart) — fonte ÚNICA, acabando
# com a duplicação do drop-in de SSH que vivia no blueprint e no %post (PROD-41).
#
# Conteúdo:
#   - SSH endurecido           (/etc/ssh/sshd_config.d/50-capivaraos-herd.conf)
#   - Política de senha        (/etc/security/pwquality.conf.d/50-capivaraos-herd.conf)
#   - umask 027 em login       (/etc/profile.d/capivaraos-herd-umask.sh)
#   - herd-compliance-scan     (relatório OpenSCAP — perfil 'standard' do SSG)
#
# SELinux fica em Enforcing pela config do instalador/blueprint; num servidor
# mínimo os booleans vêm nos padrões seguros — não mexemos aqui (mudar boolean à
# toa quebra serviço). O perfil CIS completo + remediação é do Enterprise (fase 2).

Name:           capivaraos-herd-hardening
Version:        1.0.0
# Sufixo ".herd": mesma convenção do branding/logos (evita colisão de NEVRA em
# ~/rpmbuild compartilhado — ver BUG-30).
Release:        3%{?dist}.herd
Summary:        Perfil básico de segurança (SSH, senha, umask, compliance) do CapivaraOS HERD

# GPL-3.0-or-later = nossa config/scripts; BSD-3-Clause = datastream SSG vendorado.
License:        GPL-3.0-or-later AND BSD-3-Clause
URL:            https://capivaraos.org
BuildArch:      noarch

Source0:        %{name}-%{version}.tar.gz

# O drop-in de SSH só faz sentido com o servidor SSH presente (já no payload).
Requires:       openssh-server
# Compliance embarcado ENXUTO (decisão de produto 2026-08-11): puxamos só o
# scanner (openscap-scanner, ~pequeno) e VENDORAMOS apenas o datastream do
# Fedora (ssg-fedora-ds.xml, 21 MB) — NÃO o pacote scap-security-guide inteiro,
# que instala 708 MB (datastreams/guias de todos os produtos). Assim o
# herd-compliance-scan roda de fábrica sem quase dobrar a imagem.
Requires:       openscap-scanner

Provides:       system-hardening-config = %{version}-%{release}

%description
Perfil básico de segurança do CapivaraOS HERD Community: SSH endurecido,
política de qualidade de senha (pwquality), umask restritivo em sessões de
login e o utilitário herd-compliance-scan, que gera um relatório de
conformidade OpenSCAP (perfil "standard" do SCAP Security Guide do Fedora).
Voltado a servidor headless com base Fedora 44.

%prep
%setup -q

%install
install -D -m 0600 sshd_config.d/50-capivaraos-herd.conf \
    %{buildroot}%{_sysconfdir}/ssh/sshd_config.d/50-capivaraos-herd.conf
install -D -m 0644 pwquality.conf.d/50-capivaraos-herd.conf \
    %{buildroot}%{_sysconfdir}/security/pwquality.conf.d/50-capivaraos-herd.conf
install -D -m 0644 profile.d/capivaraos-herd-umask.sh \
    %{buildroot}%{_sysconfdir}/profile.d/capivaraos-herd-umask.sh
install -D -m 0755 bin/herd-compliance-scan \
    %{buildroot}%{_bindir}/herd-compliance-scan
# Datastream do Fedora vendorado, em diretório PRÓPRIO (não no caminho do
# scap-security-guide) para não conflitar caso o admin instale o pacote completo
# depois. O herd-compliance-scan prefere o caminho padrão do SSG se existir e
# cai para este senão.
install -D -m 0644 scap/ssg-fedora-ds.xml \
    %{buildroot}%{_datadir}/%{name}/ssg-fedora-ds.xml

# Alguns ajustes de compliance vivem em arquivos de OUTROS pacotes que NÃO têm
# drop-in (.d): /etc/login.defs (shadow-utils) e /etc/dnf/dnf.conf (dnf). Editamos
# em %posttrans (fim da transação, arquivos já presentes do @core), de forma
# IDEMPOTENTE. Ambos são %config(noreplace) dos donos → nossa edição persiste em
# updates futuros. (SSH/pwquality/umask seguem como drop-ins próprios acima.)
%posttrans
# gpgcheck=1 explícito no [main] do dnf.conf (regra SSG ensure_gpgcheck_globally_activated).
if [ -f %{_sysconfdir}/dnf/dnf.conf ] && ! grep -q '^gpgcheck' %{_sysconfdir}/dnf/dnf.conf; then
    sed -i '/^\[main\]/a gpgcheck=1' %{_sysconfdir}/dnf/dnf.conf
fi
# Idade de senha no login.defs (regras accounts_{maximum,minimum}_age_login_defs).
# Valores = os que o perfil 'standard' do SSG exige (o mesmo que o
# herd-compliance-scan roda por padrão): a imagem passa no próprio perfil.
# MAX 90 (rotação trimestral), MIN 7 (evita troca em ciclo p/ burlar histórico).
if [ -f %{_sysconfdir}/login.defs ]; then
    sed -ri 's/^(PASS_MAX_DAYS)[[:space:]]+.*/\1\t90/' %{_sysconfdir}/login.defs
    sed -ri 's/^(PASS_MIN_DAYS)[[:space:]]+.*/\1\t7/'  %{_sysconfdir}/login.defs
fi

%files
%config(noreplace) %{_sysconfdir}/ssh/sshd_config.d/50-capivaraos-herd.conf
%config(noreplace) %{_sysconfdir}/security/pwquality.conf.d/50-capivaraos-herd.conf
%{_sysconfdir}/profile.d/capivaraos-herd-umask.sh
%{_bindir}/herd-compliance-scan
%{_datadir}/%{name}/ssg-fedora-ds.xml

%changelog
* Tue Aug 12 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-3.herd
- Alinha a idade de senha aos valores do perfil 'standard' do SSG (o mesmo que
  o herd-compliance-scan roda por padrão), pra imagem passar no próprio perfil:
  PASS_MAX_DAYS 90 (era 365) e PASS_MIN_DAYS 7 (era 1). Fecha as regras
  accounts_{maximum,minimum}_age_login_defs, que falhavam com 365/1.

* Tue Aug 12 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-2.herd
- Ganhos rápidos de compliance no 1.0.0 (PROD-70): PermitEmptyPasswords no no
  drop-in SSH; gpgcheck=1 explícito no [main] do dnf.conf; PASS_MAX_DAYS 365 /
  PASS_MIN_DAYS 1 no login.defs (via %posttrans idempotente — arquivos sem .d).
  nullok/pam_lastlog/securetty/auditd ficam para passes futuros/Enterprise.

* Tue Aug 11 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-1.herd
- Pacote inicial de hardening do HERD Community (PROD-41): SSH endurecido
  (movido do blueprint/kickstart para cá — fonte única), política de senha
  pwquality (minlen 12/minclass 3), umask 027 em login e o herd-compliance-scan
  (relatório OpenSCAP, perfil 'standard'). Compliance embarcado de forma ENXUTA:
  Requires openscap-scanner e VENDORA só o ssg-fedora-ds.xml (21 MB) em vez do
  scap-security-guide completo (708 MB). Datastream do SSG 0.1.81 (BSD-3-Clause).
