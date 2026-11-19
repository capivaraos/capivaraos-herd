# Herd by CapivaraOS

Herd is the **server** line of CapivaraOS. This repository builds the
**Herd Community** images, based on **Fedora 45**.

## Releases (what is stable)

This repository is developed **in the open**: the `main` branch receives
ongoing work and **is not a release**. Do not put a server into production by
building from `main`.

What is **stable and supported**:

- **Official images (ISO and qcow2):** published on SourceForge and linked from
  the website. This is what you install in production.
- **Updates:** the **`stable`** channel of the signed repository
  (`repo-herd.capivaraos.org`), configured by the `capivaraos-herd-repos`
  package. The `testing` channel is pre-release (QA).
- **Git:** each release has a **tag** (for example `herd-2.0.0`). The Herd
  1.0.1 sources (Fedora 44) are at the `herd-1.0.1` tag.

In short: code on `main` is evolving and auditable; **a release is a published
image, the `stable` channel and a tag**. See `docs/repo/README.md` for how the
repository is laid out and signed.

## What is built

From a single **osbuild blueprint** (`blueprints/capivaraos-herd.toml`),
`build.sh` produces:

| Image             | Use                                   |
|-------------------|---------------------------------------|
| `qcow2`           | Cloud and virtual machines            |
| `image-installer` | Headless installer ISO (bare metal)   |

osbuild composes for the architecture of the host it runs on. The published
images are x86_64.

## Why osbuild (and not kickstart and livemedia-creator)

Herd needs **qcow2 and an installer ISO** as first-class outputs from one
blueprint, which is what **osbuild** is for.

## Requirements

- A Fedora **45** host. The blueprint sets `distro = "fedora-45"`; the build
  runs directly on the build machine, with no mock or container.
- osbuild-composer and composer-cli:
  ```bash
  sudo dnf install -y osbuild-composer composer-cli rpm-build createrepo_c
  sudo systemctl enable --now osbuild-composer.socket
  ```

## Build

```bash
# 1. The Herd branding RPM, in a local repository for the composer
./rpm/build-rpm.sh
NEVRA=$(rpmspec -q --qf '%{name}-%{version}-%{release}.%{arch}\n' \
    rpm/capivaraos-herd-branding.spec | head -1)
REPO=/var/tmp/capivaraos-herd-repo
mkdir -p "$REPO"
[ -O "$REPO" ] && [ ! -L "$REPO" ] || { echo "$REPO is not yours"; exit 1; }
cp ~/rpmbuild/RPMS/noarch/${NEVRA}.rpm "$REPO"/
createrepo_c "$REPO"

# 2. Images (qcow2 and ISO) for the host architecture
./build.sh
```

Output goes to `out/`.

## Branded installer ISO (lorax)

The osbuild `image-installer` above works, but its **installer** (boot menu and
Anaconda) carries the Fedora brand; this build does not change it there. For an
installer ISO **without the Fedora brand**, use the lorax flow:

```bash
# 1. Branding and installer logo RPMs, served from the local repository
./rpm/build-rpm.sh
./rpm/build-rpm-logos.sh
REPO=/var/tmp/capivaraos-herd-repo
mkdir -p "$REPO"
[ -O "$REPO" ] && [ ! -L "$REPO" ] || { echo "$REPO is not yours"; exit 1; }
cp ~/rpmbuild/RPMS/noarch/capivaraos-herd-branding-*.rpm \
   ~/rpmbuild/RPMS/noarch/capivaraos-herd-logos-*.rpm \
   "$REPO"/
createrepo_c "$REPO"

# 2. Offline, branded installer ISO (needs root)
sudo dnf install -y lorax createrepo_c
sudo ./build-iso.sh
```

- `capivaraos-herd-logos` replaces `fedora-logos` in the Anaconda environment.
- `lorax -p "Herd by CapivaraOS"` sets the product name (boot menu and
  `.buildstamp`).
- `mkksiso` embeds `kickstart/capivaraos-herd.ks` (the server profile) and an
  offline repository.

Output: `out/CapivaraOS-HERD-<version>-<arch>.installer.iso`.

## System profile (Herd Community 2.0)

Cockpit web console · automatic security updates from the signed
repository · `herd-upgrade` pre-flight for later Fedora base releases (none is
available for Herd 2.0 yet).

## Layout

```
blueprints/capivaraos-herd.toml   # build source of truth (osbuild)
build.sh                          # osbuild pipeline (qcow2 and ISO)
build-iso.sh                      # branded installer ISO (lorax)
kickstart/capivaraos-herd.ks      # server profile (ISO / Anaconda)
rpm/                              # specs: branding, logos, hardening, repos, autoupdate, upgrade
branding/                         # os-release/issue/motd, Cockpit artwork, BLS fix, fastfetch
hardening/                        # SSH, password, umask, herd-compliance-scan, herd-harden
repo/, keys/, publish-repo.sh     # signed update repository and its public keys
autoupdate/, upgrade/             # automatic security updates, herd-upgrade
tools/, tests/                    # advisory metadata tool and tests
```

## Licence and trademark

- **Code** (build scripts, kickstart, specs, configuration): **GPLv3**; see
  [LICENSE](LICENSE).
- **The "CapivaraOS" and "Herd" names and logo** are **trademarks of the
  CapivaraOS project**, all rights reserved; see [TRADEMARK.md](TRADEMARK.md). You may use and
  redistribute the software; to redistribute **modified** versions, remove the
  visual identity (logo, name, `os-release`).
- Bundled third-party content keeps its original licence (for example
  `hardening/scap/ssg-fedora-ds.xml` under BSD-3-Clause).
