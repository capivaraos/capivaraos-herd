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
#   - Auditoria (auditd)       (/etc/audit/rules.d/*.rules — ruleset SSG standard)
#   - cramfs desabilitado      (/etc/modprobe.d/cramfs.conf)
#   - herd-compliance-scan     (relatório OpenSCAP — perfil 'standard' do SSG)
#   - herd-harden              (endurecimento em 1 comando — OpenSCAP + Ansible)
#
# SELinux fica em Enforcing pela config do instalador/blueprint; num servidor
# mínimo os booleans vêm nos padrões seguros — não mexemos aqui (mudar boolean à
# toa quebra serviço). O perfil CIS completo + remediação é do Enterprise (fase 2).

Name:           capivaraos-herd-hardening
Version:        1.0.0
# Sufixo ".herd": mesma convenção do branding/logos (evita colisão de NEVRA em
# ~/rpmbuild compartilhado — ver BUG-30).
Release:        9%{?dist}.herd
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
# herd-harden aplica a remediação via os playbooks Ansible que o oscap gera
# (fix-type ansible). ansible-core SOZINHO NÃO BASTA: os playbooks do SSG usam
# módulos das coleções community.general (ini_file etc.), ansible.posix
# (mount/sysctl/seboolean) e community.crypto — que não vêm no ansible-core.
# Somados são ~28 MiB (core 15.7 + coleções ~12), aceitável para o carro-chefe
# de conformidade e mantém o herd-harden funcional OFFLINE (sem baixar coleção).
Requires:       ansible-core
Requires:       ansible-collection-community-general
Requires:       ansible-collection-ansible-posix
Requires:       ansible-collection-community-crypto
# O módulo package_facts (usado logo no início dos playbooks do SSG) precisa de
# um binding Python de gerenciador de pacotes. A imagem mínima não traz nenhum
# (o dnf5 é compilado, sem python3-libdnf5). python3-rpm é o mais enxuto
# (~180 KiB) e satisfaz o gerenciador 'rpm' do package_facts.
Requires:       python3-rpm
# Já o módulo dnf (perfis do SSG instalam pacotes: rng-tools etc.) exige
# python3-libdnf5 — inclusive em check mode (dry-run), onde não pode
# auto-instalar. ~9.9 MiB, mas sem ele o harden não roda offline.
Requires:       python3-libdnf5

Provides:       system-hardening-config = %{version}-%{release}

%description
Perfil básico de segurança do CapivaraOS HERD Community: SSH endurecido,
política de qualidade de senha (pwquality), umask restritivo em sessões de
login e os utilitários herd-compliance-scan (relatório de conformidade
OpenSCAP, perfil "standard" do SCAP Security Guide do Fedora) e herd-harden
(endurecimento em 1 comando: aplica um perfil SSG via Ansible, com dry-run por
padrão). Voltado a servidor headless com base Fedora 44.

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
install -D -m 0755 bin/herd-harden \
    %{buildroot}%{_bindir}/herd-harden
# Regras de auditoria (auditd): ruleset do SSG (perfil standard) + sub-regras
# que o remediador não emite (deleção/rename e watch em /etc/group). Instaladas
# em /etc/audit/rules.d/; o augenrules as mescla no boot (com -e 2 por último).
# NÃO enviamos o audit.rules base (é do pacote 'audit'); ele traz o -D inicial.
for r in audit.rules.d/*.rules; do
    install -D -m 0640 "$r" %{buildroot}%{_sysconfdir}/audit/rules.d/"$(basename "$r")"
done
# cramfs desabilitado (blacklist + install /bin/false).
install -D -m 0644 modprobe.d/cramfs.conf \
    %{buildroot}%{_sysconfdir}/modprobe.d/cramfs.conf
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
# Retenção/ação do auditd (auditd.conf é do pacote 'audit', sem .d) — valores do
# perfil 'standard' do SSG. Idempotente: substitui a chave se existir, senão anexa.
AC=%{_sysconfdir}/audit/auditd.conf
if [ -f "$AC" ]; then
    for kv in "max_log_file 6" "num_logs 5" "max_log_file_action rotate" \
              "space_left_action email" "action_mail_acct root" \
              "admin_space_left 50" "admin_space_left_action single" \
              "disk_error_action SUSPEND" "overflow_action SYSLOG"; do
        k="${kv%% *}"; v="${kv#* }"
        if grep -qE "^[[:space:]]*${k}[[:space:]]*=" "$AC"; then
            sed -ri "s|^([[:space:]]*${k})[[:space:]]*=.*|\1 = ${v}|" "$AC"
        else
            printf '%s = %s\n' "$k" "$v" >> "$AC"
        fi
    done
fi
# Regras de auditoria para binários privilegiados (setuid/setgid) — GERADAS aqui,
# não estáticas: o conjunto de binários varia por imagem/instalação, e uma regra
# "-a ... -F path=<binário ausente>" faz o augenrules ABORTAR o load antes do -e 2
# (deixando a auditoria mutável, enabled 1). Visto no install via ISO (mínimo, sem
# polkit-agent-helper-1). Gerar da lista real de setuid/setgid garante que todo
# path existe e o -e 2 (imutável) aplica em qualquer imagem.
PRIV=%{_sysconfdir}/audit/rules.d/privileged.rules
{
    echo "## Gerado por capivaraos-herd-hardening (%posttrans): binários setuid/setgid presentes."
    find / -xdev -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | sort -u | while read -r f; do
        printf -- '-a always,exit -F path=%s -F perm=x -F auid>=1000 -F auid!=unset -F key=privileged\n' "$f"
    done
} > "$PRIV" 2>/dev/null || true
chmod 0640 "$PRIV" 2>/dev/null || true
# Plugin audispd->syslog (regra auditd_audispd_syslog_plugin_activated).
SP=%{_sysconfdir}/audit/plugins.d/syslog.conf
[ -f "$SP" ] && sed -ri 's/^([[:space:]]*active[[:space:]]*=[[:space:]]*)no/\1yes/' "$SP" || true
# audit_backlog_limit=8192 no kernel cmdline (regra grub2_audit_backlog_limit_argument).
if [ -f %{_sysconfdir}/default/grub ] && ! grep -q 'audit_backlog_limit=' %{_sysconfdir}/default/grub; then
    sed -ri 's/^(GRUB_CMDLINE_LINUX="?)/\1audit_backlog_limit=8192 /' %{_sysconfdir}/default/grub
fi
for e in /boot/loader/entries/*.conf; do
    [ -f "$e" ] || continue
    grep -q 'audit_backlog_limit=' "$e" || sed -ri 's/^(options .*)$/\1 audit_backlog_limit=8192/' "$e"
done

%files
%config(noreplace) %{_sysconfdir}/ssh/sshd_config.d/50-capivaraos-herd.conf
%config(noreplace) %{_sysconfdir}/security/pwquality.conf.d/50-capivaraos-herd.conf
%config(noreplace) %{_sysconfdir}/audit/rules.d/*.rules
%config(noreplace) %{_sysconfdir}/modprobe.d/cramfs.conf
%{_sysconfdir}/profile.d/capivaraos-herd-umask.sh
%{_bindir}/herd-compliance-scan
%{_bindir}/herd-harden
%{_datadir}/%{name}/ssg-fedora-ds.xml
# Licença do datastream do SCAP Security Guide vendorado (BSD-3-Clause):
# o BSD-3 exige reproduzir copyright + condições junto do material redistribuído.
%license scap/LICENSE.SCAP-Security-Guide

%changelog
* Fri Aug 28 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-9.herd
- herd-harden: após --apply, imprime aviso para confirmar o acesso SSH antes de
  encerrar a sessão, mostrando a crypto-policy atual. Validado em VM que o perfil
  ospp troca a política p/ FIPS, o que RECUSA chaves ed25519 (login novo cai) —
  o aviso orienta abrir uma nova sessão com chave RSA/ECDSA antes de desconectar.
  Sem mudança funcional no harden em si.

* Thu Aug 27 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-8.herd
- Corrige o herd-harden: os playbooks Ansible do SSG usam módulos fora do
  ansible-core. Adiciona Requires das coleções ansible-collection-community-general,
  ansible-collection-ansible-posix e ansible-collection-community-crypto (~12 MiB),
  para o herd-harden aplicar os perfis offline sem "No module named
  ansible_collections.community". Sem isso o dry-run/apply aborta na 1ª tarefa
  que usa community.general.ini_file (visto no teste do perfil ospp).
- Também adiciona python3-rpm (~180 KiB) e python3-libdnf5 (~9.9 MiB): o
  package_facts (início dos playbooks do SSG) exige um binding Python de
  gerenciador de pacotes (rpm), e o módulo dnf — usado para instalar pacotes de
  hardening (rng-tools etc.) — exige libdnf5 mesmo em check mode. Ambos ausentes
  na imagem mínima (dnf5 é compilado, sem bindings Python). Sem eles o harden
  falha com "Could not detect a supported package manager" e "python3-libdnf5
  must be installed to use check mode".

* Thu Aug 27 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-7.herd
- Adiciona o herd-harden: endurecimento em 1 comando (FEAT-123). Aplica um
  perfil do SSG do Fedora via os playbooks Ansible que o oscap gera
  (fix-type ansible), com DRY-RUN por padrão (ansible-playbook --check --diff)
  e --apply explícito para efetivar. Apelidos de perfil: standard, ospp,
  cis-l1, cis-l2 (cis) e pci (pci-dss); aceita também o id técnico completo.
- Requires: ansible-core (runtime mínimo do Ansible; sem coleções extras).
- Guardrail de conformidade: CIS = rascunho do SSG p/ Fedora (sem benchmark
  oficial); não há STIG p/ Fedora (ospp é o baseline DoD-adjacente). Sem
  alegação de "certificado".

* Fri Aug 14 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-6.herd
- Empacota a licença do SCAP Security Guide (BSD-3-Clause, (c) Red Hat, Inc.)
  como %license, ao lado do datastream ssg-fedora-ds.xml vendorado. O BSD-3
  exige reproduzir o copyright e as condições junto do material redistribuído;
  a atribuição também consta na documentação (docs.capivaraos.org, página de
  Segurança). Sem mudança funcional — só conformidade de licença.

* Thu Aug 13 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-5.herd
- Corrige a auditoria no install via ISO (mínimo): a privileged.rules estática
  trazia "-F path=" para binários ausentes (ex.: polkit-agent-helper-1), o que
  fazia o augenrules abortar antes do "-e 2" (auditoria ficava mutável,
  enabled 1). Agora a privileged.rules é GERADA no %posttrans a partir dos
  setuid/setgid realmente presentes → todo path existe, o -e 2 aplica e a
  auditoria fica imutável (enabled 2) tanto na qcow2 quanto no ISO.
- audit_backlog_limit=8192 também no kickstart (bootloader --append), porque o
  Anaconda regenera o bootloader depois do %posttrans (o backlog não ia pro
  cmdline no sistema instalado via ISO). qcow2 já vinha OK pelo %posttrans.

* Thu Aug 13 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-4.herd
- Auditoria (auditd) endurecida: ruleset do perfil 'standard' do SSG em
  /etc/audit/rules.d/ (perm_mod, privileged, time-change, modules, logins,
  MAC-policy, networkconfig, session, export, actions) + sub-regras de
  deleção/rename e watch em /etc/group; retenção/ações no auditd.conf e plugin
  audispd->syslog via %posttrans idempotente; -e 2 (imutável) por último. Sobe
  a auditoria de "desligada" (stub do Fedora) para ~70 regras efetivas no boot.
- cramfs desabilitado (/etc/modprobe.d/cramfs.conf: install /bin/false + blacklist).
- audit_backlog_limit=8192 no kernel cmdline (default/grub + entradas BLS).
- Perfil 'standard' do SSG sobe de ~60% para ~74%; o restante é AIDE/libreswan/
  pam_namespace (fora do escopo do 1.0.0 Community) ou quirk de relatório do OVAL
  no Fedora (estado real endurecido, ex.: cramfs/backlog/rename já aplicados).

* Wed Aug 12 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-3.herd
- Alinha a idade de senha aos valores do perfil 'standard' do SSG (o mesmo que
  o herd-compliance-scan roda por padrão), pra imagem passar no próprio perfil:
  PASS_MAX_DAYS 90 (era 365) e PASS_MIN_DAYS 7 (era 1). Fecha as regras
  accounts_{maximum,minimum}_age_login_defs, que falhavam com 365/1.

* Wed Aug 12 2026 CapivaraOS <capivaraos-bot@users.noreply.github.com> - 1.0.0-2.herd
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
