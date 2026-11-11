# Herd update repository: usage and publishing

The update repository delivers the project's own packages (`capivaraos-herd-*`, `herd-harden`, `herd-compliance-scan` and security fixes) to an installed Herd Community system, in addition to Fedora updates.

## Trust model

**Integrity comes from the signature, not from the host.** Packages and repository metadata are signed with the project's GPG key; only the public key is distributed (see `keys/README.md`):

- every **RPM** is signed (`rpm --addsign`);
- the repository **index** (`repodata/repomd.xml`) is signed (`repomd.xml.asc`);
- the client checks both: `gpgcheck=1` (packages) and `repo_gpgcheck=1` (metadata).

A package or metadata file not signed by this key is rejected, even if the file server is compromised.

The repository is served at **`repo.capivaraos.org`**.

## Layout

```
repo.capivaraos.org/
└── herd/
    └── f44/                 # Fedora base (= $releasever on the client)
        └── x86_64/
            ├── testing/      # QA channel (enabled=0 on the client)
            │   ├── *.rpm
            │   └── repodata/{repomd.xml, repomd.xml.asc, ...}
            └── stable/       # production channel (enabled=1)
                ├── *.rpm
                └── repodata/{repomd.xml, repomd.xml.asc, ...}
```

Directories follow the **Fedora base** (`f44`), not the product version, because the base determines RPM compatibility. On the client, `$releasever` resolves to `44` (through `system-release(releasever)` from `fedora-release`, **not** from `VERSION_ID` in os-release), and during `dnf system-upgrade --releasever=45` it becomes `45`, so `baseurl` points to `herd/f45/` without editing the `.repo` file.

## Publishing flow

```
build RPM  →  add to TESTING  →  QA in a VM  →  PROMOTE to STABLE  →  upload
```

Everything goes through `publish-repo.sh` at the repository root:

```bash
# 1) sign, add to testing, generate and sign the index
./publish-repo.sh add     --rel 44 --arch x86_64 --channel testing ~/rpmbuild/RPMS/noarch/*.rpm
# 2) after validating in a VM, promote to stable
./publish-repo.sh promote --rel 44 --arch x86_64
# 3) upload the tree to storage (rclone remote in HERD_RCLONE_REMOTE)
./publish-repo.sh upload  --rel 44 --arch x86_64
```

Prerequisites: `rpm-sign`, `createrepo_c`, `gnupg2` and, for the upload, `rclone` with an S3-compatible remote configured (`rclone config`). The signing key must be available to `gpg-agent`, with `%_gpg_name` set in `~/.rpmmacros` (see `keys/README.md`).

During upload, **RPMs go up before** `repodata/`, so the index never points to a package that is not there yet. RPMs are sent with a long cache lifetime (immutable) and `repodata/` with a short one plus revalidation, so a stale index is not served after a publication. The headers can be changed with `HERD_CACHE_RPM` and `HERD_CACHE_META`.

## The client (`capivaraos-herd-repos` package)

- Installs `/etc/yum.repos.d/capivaraos-herd.repo` (`stable` enabled, `testing` disabled) and the public key in `/etc/pki/rpm-gpg/`, imported into the rpm keyring in `%post` (no prompt on the first update).
- Included in both build paths: the kickstart `%packages` and the osbuild blueprint.
- **Automatic updates:** the `capivaraos-herd-autoupdate` package configures **dnf5 automatic** (`/etc/dnf/automatic.conf`: `upgrade_type=security`, `apply_updates=yes`, `reboot=never`) and enables `dnf5-automatic.timer` (daily, around 06:00). The server **applies security updates on its own**, from both Fedora and this repository, **without rebooting**; rebooting is left to the administrator. The policy can be edited in `/etc/dnf/automatic.conf` (for example, download only: `apply_updates=no`).

## Deployment order

**Do not ship `capivaraos-herd-repos` in an ISO before `repo.capivaraos.org/herd/...` is online**; otherwise every `dnf` run on the installed system warns that the repository is unreachable. Order:

1. have the public key in this repository (`keys/`);
2. publish to `stable` (at least an empty signed index);
3. only then build an ISO that includes the repos package.

## End-to-end check

`tests/test-repo-signing.sh` checks the whole chain in a Fedora 44 container with a throwaway key: it signs a test RPM, builds and signs `repomd.xml`, serves the tree from a local directory, installs `capivaraos-herd-repos`, and confirms that valid signatures pass and that a tampered package or metadata file is **rejected**.
