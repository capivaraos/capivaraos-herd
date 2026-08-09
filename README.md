# CapivaraOS HERD

Linha de **servidor** do CapivaraOS. Este repositório contém a infraestrutura de
build das imagens do **HERD Community** (edição gratuita), com base **Fedora 44**
— a mesma geração das spins de desktop (Marsh/Pup/Snout 1.x). O **Fedora 45**
fica reservado para a **geração 2** (HERD 2.x + próxima leva das spins), lançada
em conjunto quando o F45 estiver maduro.

> **Fase de lançamento:** apenas o **HERD Community**. (Jira: épico **PROD-4**;
> build/CI = **PROD-40**; escopo técnico = **PROD-38**; hardening = **PROD-41**.)

## O que é gerado

A partir de uma **blueprint osbuild** única (`blueprints/capivaraos-herd.toml`),
o `build.sh` produz:

| Imagem            | Uso                                   |
|-------------------|---------------------------------------|
| `qcow2`           | Nuvem/VM (com cloud-init)             |
| `image-installer` | ISO instalador headless (bare-metal)  |

Para **x86_64** e **aarch64** (um builder osbuild por arquitetura — o osbuild
compõe para a arquitetura do host; para aarch64, rode num host/VM aarch64).

## Por que osbuild / Image Builder (e não kickstart+livemedia)

Os desktops (Marsh/Pup/Snout) usam kickstart + `livemedia-creator`, ótimo para
ISO live. O HERD precisa de **qcow2 e ISO** como cidadãos de primeira classe,
**multi-arch** e reprodutível — terreno do **osbuild**, que ainda é a rampa
natural para a variante **bootc/imutável** (fase 2). Ver PROD-40.

## Pré-requisitos

- Host **Fedora 44** (mesma base das spins) — builda direto na máquina de dev,
  sem VM.
- osbuild-composer + composer-cli:
  ```bash
  sudo dnf install -y osbuild-composer composer-cli rpm-build createrepo_c
  sudo systemctl enable --now osbuild-composer.socket
  ```

## Build

```bash
# 1. Branding do HERD (RPM) e repo local para o composer consumir
./rpm/build-rpm.sh
NEVRA=$(rpmspec -q --qf '%{name}-%{version}-%{release}.%{arch}\n' \
    rpm/capivaraos-herd-branding.spec | head -1)
mkdir -p /var/tmp/capivaraos-herd-repo
cp ~/rpmbuild/RPMS/noarch/${NEVRA}.rpm /var/tmp/capivaraos-herd-repo/
createrepo_c /var/tmp/capivaraos-herd-repo

# 2. Imagens (qcow2 + ISO) para a arquitetura do host
./build.sh
```

Saída em `out/`.

## Perfil do sistema (v1)

Headless · SELinux **enforcing** · `firewalld` restritivo (só SSH) · SSH
endurecido · cloud-init na qcow2 · locale pt_BR/en_US · timezone configurável.
Detalhes e finalização de hardening: **PROD-41**.

## Estrutura

```
blueprints/capivaraos-herd.toml   # fonte de verdade do build
build.sh                          # pipeline osbuild (qcow2 + ISO)
rpm/                              # RPM de branding (os-release, issue, motd)
branding/                        # assets textuais do branding
```
