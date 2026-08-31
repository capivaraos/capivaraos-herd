# Upgrade de versão in-place do Herd — `herd-upgrade`

- **Jira:** PROD-107 (upgrade de versão in-place)
- **Épico:** PROD-102 (atualização automática do servidor)
- **Relaciona:** PROD-104/105 (repo assinado), PROD-106 (updates automáticos), PROD-108 (página de Updates do Herd Control), FEAT-111 (trilha do desktop)

## O que isto resolve

Os updates contínuos (PROD-105/106) mantêm o Herd corrigido **dentro da versão
atual**. Falta o salto: subir para a **próxima versão** (F44 → F45, e daí em
diante) **sem formatar**, preservando dados, configuração e o hardening. É o que
a ferramenta `herd-upgrade` faz — o análogo, no servidor headless, do "nova
versão disponível" do desktop.

## Como funciona

`herd-upgrade` é um **invólucro auditável** do `dnf5 system-upgrade`, o mecanismo
de upgrade **offline** do Fedora: baixa tudo com o sistema no ar e aplica no
próximo boot, num ambiente isolado (sem meio-termo com serviços rodando). No
Fedora 44+ o subcomando é **embutido no core do `dnf5`** (não há plugin
separado).

O destino **não é cravado no código**: sai de `rpm -E %fedora` (versão atual + 1)
ou de `--to N`. Como o `baseurl` do nosso repositório usa `$releasever`
(`herd/f$releasever/...`), a mesma ferramenta e o mesmo `.repo` servem para todos
os saltos futuros, sem editar nada.

## Fluxo de uso

```sh
# 1. Pré-voo (padrão, seguro — não baixa nem reinicia):
herd-upgrade                 # ou: herd-upgrade check --to 45

# 2. Baixar a transação (o servidor continua no ar):
sudo herd-upgrade download   # ou: sudo herd-upgrade download --to 45

# 3. Aplicar (reinicia no modo offline):
sudo herd-upgrade reboot

# Atalho: download + reboot com confirmação
sudo herd-upgrade run --to 45

# Utilidades: status | log | clean (atalhos do dnf5 system-upgrade)
```

## Garantias de segurança (a razão de existir o invólucro)

1. **Seguro por padrão.** Sem argumento, roda só o **pré-voo**; nada muda.
   Baixar e reiniciar são passos **separados e explícitos**.
2. **Falha fechada.** O pré-voo **recusa** o upgrade se o nosso repositório
   assinado (`capivaraos-herd`) ainda **não existir** para a versão de destino.
   Sem essa trava, o servidor subiria a base Fedora e deixaria os pacotes do Herd
   (branding, hardening, repos, autoupdate) **para trás**. Enquanto
   `repo.capivaraos.org/herd/f45/` não estiver publicado, `herd-upgrade` para em
   f45 — de propósito. (Escape consciente para erro transitório de rede:
   `--allow-missing-herd-repo`, por conta e risco.)
3. **Confiança na assinatura, não no host.** A transação respeita
   `gpgcheck=1` + `repo_gpgcheck=1` do repositório: recusa qualquer pacote **ou
   metadado** não assinado pela nossa chave, mesmo com host/CDN comprometido
   (provado em `tests/test-repo-signing.sh`).
4. **Snapshot antes, quando dá.** Se a raiz for **btrfs + snapper**, cria um
   snapshot automático antes do upgrade. Em **LVM** (padrão do Herd 1.x com disco
   cifrado), o snapshot automático **não** é feito — o rollback de LVM exige merge
   no reboot; a ferramenta **reporta** o comando manual:
   ```sh
   sudo lvcreate -s -n root_pre_f45 -L 5G /dev/mapper/<vg>-<root>
   # rollback: sudo lvconvert --merge <snapshot> && reboot
   ```
   Sem storage compatível, avisa para fazer **backup** antes.

## Rollback

- **snapper/btrfs:** `snapper rollback` a partir do snapshot pré-upgrade.
- **LVM:** `lvconvert --merge` no snapshot criado manualmente e reiniciar.
- **Sem snapshot:** restauração a partir do backup (ver o esquema de backup do
  projeto). Por isso o pré-voo insiste em backup quando não há snapshot.

## Estado de validação

- ✅ **Lógica provada** de forma reprodutível (`tests/test-upgrade.sh`, contêiner
  Fedora 44): build/install do pacote, guardas de argumento, **falha fechada**
  quando o repo do destino não existe, **liberação** com o repo presente, e
  **aborto seguro** do `download` quando o pré-voo reprova (sem tocar o dnf).
- ⏳ **Teste de upgrade cross-release real em VM** (F44→F45): **gate de QA**
  pendente. Depende de (1) o repositório assinado `herd/f45/` publicado e (2) a
  próxima versão empacotada e publicada nesse repo. Enquanto não existirem, `herd-upgrade` **recusa**
  corretamente o salto — que é o comportamento auditável desejado. Nada é
  liberado como "pronto" sem esse teste ponta a ponta.

## Empacotamento

- Pacote **`capivaraos-herd-upgrade`** → `/usr/bin/herd-upgrade`.
- `Requires: dnf5` (system-upgrade embutido) + `capivaraos-herd-repos` (garante o
  `.repo` e a chave no destino).
- Incluído no `%packages` do kickstart e na blueprint osbuild.
- Build: `./rpm/build-rpm-upgrade.sh` → `~/rpmbuild/RPMS/noarch/`.
