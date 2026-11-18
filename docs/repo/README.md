# Herd update repository: design, layout and publishing

An installed CapivaraOS Herd system receives its Fedora updates from Fedora and
the project's own packages (`capivaraos-herd-*`, including
`capivaraos-herd-hardening`, which provides `herd-harden` and
`herd-compliance-scan`) from this signed update repository. This guide
describes how the repository is built, signed, served and published.

All publishing goes through `publish-repo.sh` at the root of this repository.

## Trust model

**Integrity comes from the signature, not from the host.** The project signs
with its own GPG keys (see `keys/README.md`):

- each **RPM** is signed (`rpmsign --addsign`);
- the repository **index** (`repodata/repomd.xml`) is signed
  (`repomd.xml.asc`);
- the client checks both: `gpgcheck=1` (packages) and `repo_gpgcheck=1`
  (metadata).

A Herd 2.0 client is configured to refuse an index that is not signed by one
of the two Herd keys it ships with, and a package whose signature rpm does not
trust or whose checksum does not match that index (`tests/test-repo-signing.sh`
shows the refusal). Whoever controls the host or a CDN in front of it can
withhold updates, but cannot make a client accept an altered package or index. The private keys are
never in this repository.

## Where it is served

The repository is split in two, both in the GitHub repository
`capivaraos/repo-herd`:

- **Metadata** (`repodata/`, small and signed) is served by GitHub Pages at
  `https://repo-herd.capivaraos.org/`. The client's `baseurl` is
  `https://repo-herd.capivaraos.org/f$releasever/$basearch/stable/`.
- **Packages** (`.rpm`) are attached to GitHub Releases of the same
  repository, one tag per release, architecture and channel:
  `herd-f<rel>-<arch>-<channel>`, for example `herd-f45-x86_64-stable`.

The link between them is the `xml:base` that `createrepo_c -u` writes into
`primary.xml`: dnf5 reads the index from Pages and downloads each package
from the Releases URL. The `.repo` file does not change, and `gpgcheck` and
`repo_gpgcheck` apply to both, wherever the bytes come from.

Herd 1.0.1 has no Herd repository. A 1.0.1 system reaches this repository
only by installing `capivaraos-herd-repos` from it, as the upgrade guide in
the docs describes.

## Layout

```
repo-herd.capivaraos.org/              (GitHub Pages of capivaraos/repo-herd)
├── RPM-GPG-KEY-capivaraos-herd          current public key
├── RPM-GPG-KEY-capivaraos-herd-reserve  reserve public key
└── f45/                               Fedora base release ($releasever)
    └── x86_64/                        (one directory per architecture; x86_64 only today)
        ├── testing/repodata/          QA channel (enabled=0 on clients)
        │     repomd.xml, repomd.xml.asc, primary, filelists, ...
        └── stable/repodata/           production channel (enabled=1)
              repomd.xml, repomd.xml.asc, primary, ...,
              updateinfo (when advisories exist)

github.com/capivaraos/repo-herd/releases
└── herd-f45-x86_64-testing, herd-f45-x86_64-stable   the .rpm files
```

The two public keys at the Pages root are there for people to download and
check against the fingerprints in `keys/README.md`. Clients do not fetch them:
the `capivaraos-herd-repos` package ships both, and `gpgkey=` points at the
local files.

The tree is organised by **Fedora base release** (`f45`), not by product
version, because the base is what decides RPM compatibility. On the client,
`$releasever` is the Fedora base release (from `fedora-release`, not the
os-release `VERSION_ID`). During `dnf system-upgrade --releasever=46` it becomes
`46`, and the `baseurl` follows to `f46/` without editing the `.repo` file.

Locally, `publish-repo.sh` builds the same split under `out/` (ignored by git):

```
out/repo/f<rel>/<arch>/<channel>/repodata/   published by `pages`
out/releases/f<rel>/<arch>/<channel>/*.rpm   uploaded by `release`
```

## The client package (`capivaraos-herd-repos`)

- Installs `/etc/yum.repos.d/capivaraos-herd.repo` with two repositories:
  `capivaraos-herd` (stable, enabled) and `capivaraos-herd-testing`
  (disabled). Both use `skip_if_unavailable=1`, so an unreachable repository
  is skipped with a warning instead of stopping the whole dnf transaction.
- Installs both public keys in `/etc/pki/rpm-gpg/`.
- Installs a drop-in for `dnf5-automatic.service` that, before each
  unattended run, imports both keys into the rpm keyring (a failure stops the
  run) and runs a `makecache` of the two Herd repositories so that dnf5
  stores them (a failure there does not stop the run; if dnf5 has not stored
  the keys in an earlier run, that run cannot verify the Herd repositories).
  `keys/README.md` explains why both stores need them.
- Ships in both image builds: the kickstart `%packages` (ISO) and the osbuild
  blueprint (qcow2).

`capivaraos-herd-autoupdate` installs a dnf5 automatic policy in
`/etc/dnf/automatic.conf` (`upgrade_type = security`, `apply_updates = yes`,
`reboot = never`), only if that file does not exist yet. The images enable
`dnf5-automatic.timer` (the kickstart `services` line and the blueprint
`[customizations.services]`); the package does not. That policy tells an
unattended run to apply only updates that a repository marks as security
fixes, and not to reboot. The admin can change the policy in that file, for
example `apply_updates = no` to only download.

## Security advisories

dnf5 knows that an update is a security fix only from an advisory in the
repository index (`updateinfo`). In the Fedora 45 container test
(`tests/test-updateinfo.sh`), with the shipped policy, an unattended run
updates a Herd package only when the repository lists a security advisory for
a version newer than the installed one; it then installs the newest version
available. An update without an advisory still reaches an interactive
`dnf upgrade`, but not the unattended one.

Record one advisory for each security fix, from the fixed package:

```bash
./publish-repo.sh advisory --id HERD-2026-0001 --type security \
    --severity Important --title "herd-harden: ..." \
    [--description "..."] [--cve CVE-2026-1234] \
    ~/rpmbuild/RPMS/noarch/<fixed package>.rpm
```

This writes `advisories/HERD-2026-0001.xml` from the package headers (name,
epoch, version, release, architecture, file name). An existing advisory is
never rewritten. The title and description state the corrected behaviour, not
the flaw.

Advisories are published with the **stable channel only**: a public advisory
goes out once the fix is in stable. `add` publishes to testing only, so the
stable index is rebuilt only by `promote`. `promote` rebuilds `updateinfo`
from every advisory whose packages are all in stable with the same NEVRA and
file name, attaches it, and only then signs the index. The testing channel
never carries advisories. The run stops when an advisory is malformed, names a
file present in stable with a different NEVRA, or matches only some of its
packages. An advisory whose packages are not in stable is skipped. To withdraw
an advisory, run `git rm advisories/<ID>.xml`, commit, and run `promote`
again; it then leaves the index.

`promote` reads the advisories as committed in `HEAD`, and stops if
`advisories/` has untracked, ignored or modified files. Commit
`advisories/<ID>.xml` before `promote`, and push that commit only once the fix
is published in stable.

## Publishing flow

```
build RPMs → add (testing) → release testing → pages → QA
           → VM test → promote → release stable → pages
```

Order matters: `release` (packages) runs **before** `pages` (index), so the
published index never points at a package that is not yet in Releases.

## Deployment order

An image that ships `capivaraos-herd-repos` expects the repository to exist.
`skip_if_unavailable=1` keeps dnf working if it does not, but the system then
receives no Herd updates, and `herd-upgrade` refuses to upgrade to a base
release that has no Herd repository, unless run with
`--allow-missing-herd-repo`. So a signed stable index for the target base
release is published before any image that includes the package.

## Testing before publishing

The mechanics are tested in Fedora 45 containers with **throwaway keys**,
never the production key:

- `tests/test-repo-signing.sh`: package and index signatures, refusal of a
  tampered package or index, and trust of the reserve key;
- `tests/test-publish.sh`: the `pages` and `release` checks
  against local bare repositories;
- `tests/test-updateinfo.sh`: advisories (stable only, committed only,
  refusal of bad ones, withdrawal) and the shipped security-only policy under
  dnf5 automatic;
- `tests/test-autoupdate.sh` and `tests/test-upgrade.sh`: the autoupdate
  and upgrade packages.

Containers do not replace a test on a clean install: the publishing flow above
includes a VM test before `promote`.

## One-time host setup

1. `capivaraos/repo-herd` serves GitHub Pages from its default branch, with a
   `CNAME` file (`repo-herd.capivaraos.org`) and `.nojekyll` at the root.
2. `capivaraos-bot` has write access to `capivaraos/repo-herd`.
3. `pages` clones the Pages repository, replaces only `f<rel>/<arch>/`, keeps
   the rest of the site root (`CNAME`, `.nojekyll`, `index.html`), copies the
   two public keys, and pushes one commit. `HERD_PAGES_REPO` points it at
   another repository, for example a local bare one in tests.
