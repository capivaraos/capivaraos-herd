# Herd by CapivaraOS

Linha de **servidor** do CapivaraOS. Este repositório contém a infraestrutura de
build das imagens do **Herd Community** (edição gratuita), com base **Fedora 44**
— a mesma geração das spins de desktop (Marsh/Pup/Snout 1.x).

> **Fase de lançamento:** apenas o **Herd Community**. (Jira: épico **PROD-4**;
> build/CI = **PROD-40**; escopo técnico = **PROD-38**; hardening = **PROD-41**.)

## Como funcionam os releases (o que é estável)

Este repositório se desenvolve **em aberto**: a branch `main` recebe trabalho
contínuo e **não é um release**. Não coloque um servidor em produção compilando
da `main`.

O que é **estável e suportado**:

- **Imagens oficiais (ISO/qcow2):** publicadas no SourceForge e no site
  (docs.capivaraos.org). É o que se instala em produção.
- **Atualizações:** o canal **`stable`** do repositório assinado
  (`repo.capivaraos.org`), consumido pelo pacote `capivaraos-herd-repos`. O canal
  `testing` é pré-produção (QA).
- **Marcos no git:** cada release corresponde a uma **tag** (ex.: `herd-1.0.1`).

Ou seja: código na `main` = em evolução e auditável; **release = ISO publicada +
canal `stable` + tag**. Ver `docs/repo/README.md` para o fluxo de publicação.

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
ISO live. O Herd precisa de **qcow2 e ISO** como cidadãos de primeira classe,
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
# 1. Branding do Herd (RPM) e repo local para o composer consumir
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

## ISO instaladora brandeada (lorax) — PROD-66

O `image-installer` do osbuild acima é funcional, mas o **instalador** (menu de
boot + Anaconda) herda a marca Fedora, que o osbuild não deixa sobrescrever.
Para uma ISO instaladora **sem marca Fedora**, use o fluxo lorax:

```bash
# 1. RPMs de branding E de logos do instalador, servidos no repo local
./rpm/build-rpm.sh
./rpm/build-rpm-logos.sh
mkdir -p /var/tmp/capivaraos-herd-repo
cp ~/rpmbuild/RPMS/noarch/capivaraos-herd-branding-*.rpm \
   ~/rpmbuild/RPMS/noarch/capivaraos-herd-logos-*.rpm \
   /var/tmp/capivaraos-herd-repo/
createrepo_c /var/tmp/capivaraos-herd-repo

# 2. ISO instaladora offline e brandeada (precisa root)
sudo dnf install -y lorax createrepo_c
sudo ./build-iso.sh
```

- `capivaraos-herd-logos` substitui o `fedora-logos` no ambiente do Anaconda.
- `lorax -p "Herd by CapivaraOS"` brandeia o nome de produto (menu/`.buildstamp`).
- `mkksiso` embute o `kickstart/capivaraos-herd.ks` (perfil de servidor) e um
  repo offline, tornando a instalação autossuficiente.

Saída: `out/CapivaraOS-HERD-<versão>-<arch>.installer.iso`.

## Perfil do sistema (v1)

Headless · SELinux **enforcing** · `firewalld` restritivo (só SSH) · SSH
endurecido · cloud-init na qcow2 · locale pt_BR/en_US · timezone configurável.
Detalhes e finalização de hardening: **PROD-41**.

## Estrutura

```
blueprints/capivaraos-herd.toml   # fonte de verdade do build (osbuild)
build.sh                          # pipeline osbuild (qcow2 + ISO)
build-iso.sh                      # ISO instaladora brandeada (lorax) — PROD-66
kickstart/capivaraos-herd.ks      # perfil de servidor (ISO/Anaconda)
rpm/                              # specs: branding, logos (instalador), hardening
branding/                         # os-release/issue/motd, arte do Cockpit, fix BLS
hardening/                        # SSH/senha/umask + herd-compliance-scan (PROD-41)
```

## Licença e marca

- **Código** (scripts de build, kickstart, specs, configs): **GPLv3** — ver
  [LICENSE](LICENSE).
- **Nome e logotipo** "CapivaraOS" / "Herd": **marca protegida**, todos os
  direitos reservados — ver [TRADEMARK.md](TRADEMARK.md). Você pode usar e
  redistribuir o software; para redistribuir versões **modificadas**, remova a
  identidade visual (logo, nome, `os-release`).
- Conteúdo de terceiros embarcado mantém sua licença de origem (ex.:
  `hardening/scap/ssg-fedora-ds.xml` sob BSD-3-Clause).
