# Herd repository signing keys

This directory holds **only the public keys** that sign the CapivaraOS Herd
update repository. Trust in updates does not depend on the host that serves
the files: `repo_gpgcheck` refuses repository metadata that is not signed by
one of these keys, and `gpgcheck` refuses a package whose signature rpm does
not trust; an altered package also fails the checksum in the signed index,
even if the server or CDN is compromised.

## Files

| File | Commit? | What it is |
|---|---|---|
| `gen-signing-key.sh` | yes | Generates a signing key pair. |
| `RPM-GPG-KEY-capivaraos-herd` | **yes** | Current signing key, public part. Fingerprint `C852 6722 0A81 18C9 864F  0648 BE5B 82AD C8A2 85C0`. |
| `RPM-GPG-KEY-capivaraos-herd-reserve` | **yes** | Reserve signing key, public part. Fingerprint `F4EF 73FA F615 7390 BB65  38FF A765 804F 4ADA 507E`. |
| private keys | **never** | Never stored in this repository. |

Check a key file with `gpg --show-keys <file>`.

## Trust model

- A private key signs each RPM (`rpmsign --addsign`) and the repository's
  `repomd.xml` (detached signature `repomd.xml.asc`).
- Both public keys ship in the `capivaraos-herd-repos` package, installed in
  `/etc/pki/rpm-gpg/` and listed in `gpgkey=` of both Herd repositories.
- On the client, `gpgcheck=1` checks each package signature and
  `repo_gpgcheck=1` checks the repository index signature. A forged or altered
  update is refused.
- rpm keeps package-signature keys in its keyring; dnf5 keeps
  repository-metadata keys in a separate store per repository. An interactive
  `dnf` asks before importing the keys from `gpgkey=`. Before each unattended
  run, the package's drop-in
  `/usr/lib/systemd/system/dnf5-automatic.service.d/50-capivaraos-herd-keys.conf`
  imports both files into the rpm keyring and runs a `makecache` of the two
  Herd repositories, so dnf5 stores them too.
- That is why the host is irrelevant to integrity (see `docs/repo/README.md`).

## Generating a key

`gen-signing-key.sh` generates an RSA 4096 signing key and exports its public
part to `keys/RPM-GPG-KEY-capivaraos-herd`. The fingerprints of both keys are
in the table above and on the Security page of the documentation.

## Rotation and compromise

- **Reserve key:** current `capivaraos-herd-repos` packages import the reserve
  key next to the current one. If you edited
  `/etc/yum.repos.d/capivaraos-herd.repo`, merge the `.rpmnew` file that an
  update leaves next to it, so `gpgkey=` lists both keys.
- **Planned rotation:** move signing to the reserve key only once installed
  systems trust it. After the move, ship a new reserve key in a
  `capivaraos-herd-repos` update.
- **Compromise of either key:** publish its revocation certificate, sign with
  the other key, and ship a `capivaraos-herd-repos` update that removes the
  compromised key file, removes it from `gpgkey=` in `capivaraos-herd.repo`,
  **and** changes the drop-in so that it no longer imports it. Removing the
  file alone is not enough: a key already trusted stays in the rpm keyring and
  in dnf5's per-repository store until the admin deletes it explicitly
  (`rpmkeys --delete <fingerprint>`, and deleting
  `/var/cache/libdnf5/<repo>-<hash>/pubring/<16-hex-digit key ID>.pub`).
  Announce it on the Security page, with those commands.
- **Local override:** an admin can replace the drop-in with a file of the same
  name in `/etc/systemd/system/dnf5-automatic.service.d/`. That copy keeps its
  own key list: if a later update removes a key file it still names, its strict
  `rpmkeys` line fails and stops every unattended run until the copy is fixed.

> These keys sign the **repository, the RPMs and the image checksum file
> (`SHA256SUMS`)** (RSA). Any other project key has a different purpose; do not
> reuse one for another.
