# ADR 0001 — Herd Control: stack e arquitetura de fundação

- **Status:** Aceito (Fase 0)
- **Data:** 2026-08-28
- **Jira:** PROD-84 (spike) · épico PROD-83 · relaciona PROD-85 (licença), PROD-87 (página Compliance), PROD-75/PROD-77 (aarch64)
- **Substitui:** PROD-37 (spike antigo "HERD Control")

> ADR = registro de decisão de arquitetura. Documenta **o quê** foi decidido e
> **por quê**, para não re-litigar depois. Só se revisa com um novo ADR que o
> supersede.

## Contexto

O **Herd Control** é o painel de administração **próprio** do Herd by CapivaraOS.
Ele sustenta o modelo **open-core**: o sistema operacional e a segurança são
**gratuitos**; a monetização vem de **serviços e features pagas** no painel
(frota, evidência de compliance agendada, backup orquestrado, etc.), nunca do SO.

O painel precisa:

- Rodar num **servidor headless** (bare-metal e nuvem), inclusive **air-gapped**.
- Executar **ações privilegiadas** (serviços, pacotes, firewall, usuários,
  storage/LUKS, SELinux) e orquestrar nossas ferramentas `herd-harden` e
  `herd-compliance-scan`.
- Sustentar a marca de **segurança e auditabilidade** — o painel não pode ser o
  elo fraco de um SO endurecido.
- Suportar **licença assinada offline** (sem phone-home) para separar Community de
  Enterprise.
- Ser distribuível para **x86_64 e aarch64**.

## Decisões

### 1. Cockpit — **conviver**, não substituir (no dia 1)

O Herd já embarca o **Cockpit**. O Herd Control **não** o remove no lançamento.
Ele entra primeiro pela **página de Compliance** (PROD-87) — a isca de adoção,
que expõe `herd-harden`/`herd-compliance-scan` na UI — e vai ganhando as demais
telas de forma **incremental**. O Cockpit segue cobrindo o resto até termos
paridade. Sem big-bang, sem regressão de capacidade para o usuário.

Reavaliação: depois da Fase 1, decidir se e quando aposentar o Cockpit.

### 2. Agente — **Go**

O componente privilegiado é escrito em **Go**. Motivos, por ordem de peso:

1. **Superfície de ataque mínima.** É um **daemon privilegiado**. Go produz um
   **binário único estático**, sem interpretador nem árvore de dependências de
   runtime para auditar/atualizar. Coerente com a marca; um agente Python
   privilegiado puxando dezenas de libs é exatamente o que vendemos contra.
2. **Licença offline resistente a adulteração (PROD-85).** Chave pública embutida
   e verificação de assinatura dentro de um **binário compilado** é bem mais
   difícil de burlar do que fonte legível ao lado do `.key`.
3. **Daemon enxuto.** Baixo consumo de memória, startup instantâneo, concorrência
   nativa para servir API + operações simultâneas.
4. **aarch64 de graça.** Cross-compile trivial (`GOARCH=arm64`), sem empacotar
   runtime — destrava PROD-75/PROD-77.

**Contra reconhecido:** Python é a zona de conforto do time (COS Dev Center,
Capivara Fetch). Mas ali é **desktop/GUI**; aqui é **daemon de segurança no
servidor**, onde (1) e (2) mandam. Além disso o agente sobretudo **orquestra**
(exec + D-Bus), com pouca lógica de dados onde Python brilharia.

### 3. Frontend — **Svelte/SvelteKit**

SPA em **Svelte**: bundle menor e mais simples que React para um painel
**embarcado** servido pelo próprio servidor headless (menos JS trafegando). React
fica como **plano B** se ecossistema/contratação virarem gargalo. A SPA é estática
(build-time) e servida pela camada web do agente.

### 4. Modelo de privilégio — **dois processos** (privilégio separado)

Servir uma UI web **como root** é o antipadrão clássico. Seguimos o princípio do
Cockpit (privilégio separado), com implementação própria:

- **`herd-controld`** — serviço **privilegiado** (root), systemd. Expõe **apenas
  operações vetadas** por um socket **Unix de dono root**. É quem fala com
  systemd/dnf/firewalld/etc. e aplica **RBAC**. Não fala HTTP com a rede.
- **`herd-control-web`** — camada **web, não privilegiada**. Serve a SPA e termina
  a conexão TLS com o navegador; **autentica o humano via PAM**; repassa as
  chamadas ao `herd-controld` pelo socket local, carregando a identidade já
  autenticada. Um bug aqui **não é root**.

A identidade entre as camadas é provada por **`SO_PEERCRED`** no socket Unix +
token de sessão por conexão. (No PoC as duas camadas podem colapsar num processo
só, **somente leitura** — ver "PoC".)

### 5. Autenticação e autorização

- **AuthN: PAM.** Login com **contas do sistema** (nada de banco de usuários
  próprio). Sessões com expiração.
- **AuthZ: RBAC** mapeado de **grupos Unix** — proposta inicial: `herd-admin`
  (tudo), `herd-operator` (operar sem mexer em política/segurança), `herd-audit`
  (só leitura + relatórios de compliance). Enforçado no `herd-controld`.
- **polkit** para as ações mais sensíveis: além do RBAC, as operações críticas
  passam por **actions polkit**, de modo que a decisão fique **auditável** e o
  site possa sobrepor política sem recompilar.

### 6. Transporte

- **Navegador ↔ `herd-control-web`:** HTTPS numa porta **configurável**
  (default proposto **9080**, para não colidir com o Cockpit em 9090),
  **certificado autoassinado** por padrão (como o Cockpit), documentado para ficar
  **atrás de VPN/túnel**, nunca aberto à internet.
- **`herd-control-web` ↔ `herd-controld`:** **socket Unix** root-only
  (`/run/herd-control/controld.sock`), sem exposição de rede.
- Firewalld: abrimos a porta do Herd Control **ao lado** da do Cockpit (decisão 1).

### 7. Como o agente atua (contratos de sistema)

| Domínio | Mecanismo |
|---|---|
| Serviços | **D-Bus** `org.freedesktop.systemd1` |
| Pacotes/updates | `dnf` / libdnf5 (exec), respeitando `gpgcheck=1` |
| Firewall | **D-Bus** `org.fedoraproject.FirewallD1` |
| Usuários/grupos | exec (`useradd`/`passwd`/`getent`) sob RBAC |
| Storage/LUKS | exec (`lsblk`/`cryptsetup`), leitura + operações vetadas |
| SELinux | libselinux/exec (`getenforce`/`semanage`) |
| **Compliance** | exec de **`herd-harden`** e **`herd-compliance-scan`**; coleta os artefatos (HTML/XCCDF/**ARF**) e os expõe/baixa pela UI |

A página de Compliance (PROD-87) é a **primeira** tela — reaproveita 100% do que
já existe (FEAT-97) e é a isca de adoção.

### 8. Licença offline assinada (fundação; detalhe em PROD-85)

`/etc/herd/license.key` verificado pelo **`herd-controld`** com **chave pública
embutida** (assinatura **ed25519**), contendo features + validade + binding.
**Sem phone-home**; **degradação graciosa** para Community se ausente/inválida.
As features Enterprise ficam **gated** por essa verificação.

> **Nota FIPS:** a verificação usa o **crypto do próprio Go** (estático), que é
> **independente da crypto-policy do SO** — logo **não quebra** com `fips=1` no
> host (diferente do SSH/ed25519, que é governado pela política do sistema). Se um
> cliente exigir **módulo FIPS-validado no próprio agente**, isso é item futuro de
> Enterprise/gov, não bloqueia a fundação.

### 9. Empacotamento

- **`herd-control`** (Community) — as duas camadas + features gratuitas
  (overview/serviços/updates/firewall/usuários/logs/terminal + **Compliance**).
- **`herd-control-enterprise`** — drop-in que **habilita** as features pagas, que
  ainda assim exigem **licença válida**. Sem licença ⇒ Community.

## Divisão open-core (guardrail)

- **Grátis:** overview, serviços, updates, firewall, usuários, logs, terminal e a
  **página de Compliance** (herd-harden/scan na UI).
- **Pago:** frota (PROD-90), compliance agendado + evidência ARF/PDF (PROD-88),
  patch central, backup orquestrado, monitoramento/alertas, runner Ansible, NBDE
  key mgmt, RBAC/auditoria avançada (PROD-91).
- **SO e segurança-base NUNCA entram no paywall.**

## PoC mínimo (próximo passo do PROD-84)

Escopo deliberadamente pequeno para validar a fundação **antes** de investir:

1. `herd-controld` sobe como serviço systemd, socket Unix root-only.
2. `herd-control-web` autentica via PAM e serve a SPA Svelte.
3. UI lista **serviços systemd** (via D-Bus) em **somente leitura**.
4. Empacotado como RPM `herd-control` e instalado numa **VM Herd**.

Aceite do spike: este ADR aprovado + PoC rodando na VM + caminho de RPM validado.
No PoC as duas camadas **podem** colapsar num processo (só leitura); a separação
de privilégio da decisão 4 é obrigatória **antes** de qualquer operação de escrita.

## Consequências

**Positivas:** fundação alinhada à marca (superfície mínima, auditável, offline);
aarch64 sem custo extra; licença robusta; reaproveita FEAT-97 já pronto.

**Negativas / riscos:** UI própria é **grande** e é a maior aposta de esforço do
épico (nota de realismo registrada em PROD-83 — reavaliar após a Fase 1 se
compensa vs. alavancar componentes existentes); Go é curva de aprendizado para o
time; conviver com o Cockpit significa **dois painéis** temporariamente (custo de
UX até a paridade).

## Alternativas consideradas

- **Estender o Cockpit** (plugins). Rejeitada na decisão de produto do épico
  (PROD-83): marca/controle totais pesaram mais, ciente do maior esforço.
- **Agente em Python.** Rejeitada aqui (decisão 2): superfície de ataque e licença
  em binário mandaram, apesar da familiaridade do time.
- **React no front.** Mantida como **plano B** (decisão 3).
- **Daemon único rodando como root e servindo HTTP.** Rejeitada (decisão 4):
  antipadrão de segurança; um bug viraria RCE root.
