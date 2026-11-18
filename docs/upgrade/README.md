# In-place version upgrade: `herd-upgrade`

`herd-upgrade` moves an installed Herd to a later Fedora base release. It
does not reinstall the system. It wraps `dnf5 system-upgrade`, Fedora's
offline upgrade: the transaction is downloaded while the server runs and
applied on the next boot, in dnf5's offline upgrade mode.

Its messages are in Portuguese.

The target release is not fixed in the code. It is the current release plus
one (`rpm -E %fedora` + 1), or the value of `--to N`. The Herd repository's
`baseurl` uses `$releasever`
(`https://repo-herd.capivaraos.org/f$releasever/$basearch/stable/`), so dnf
fills in the target release; the file does not name one.

## Usage

```sh
# 1. Pre-flight (the default; downloads nothing and does not reboot):
herd-upgrade                 # or: herd-upgrade check --to 46

# 2. Download the transaction (the server keeps running):
sudo herd-upgrade download   # or: sudo herd-upgrade download --to 46

# 3. Apply it (reboots into the offline upgrade):
sudo herd-upgrade reboot

# Shortcut: download, then reboot after a confirmation
sudo herd-upgrade run --to 46

# dnf5 system-upgrade shortcuts: status | log | clean
```

Options: `--to N` (or `--releasever N`) sets the target; `--no-snapshot`
skips the snapshot step; `-y`/`--yes` skips the reboot confirmation;
`--allow-missing-herd-repo` lets `download` and `run` continue past a failed
repository check.

## What it checks

1. **Nothing changes by default.** With no argument it runs only the
   pre-flight. Download and reboot are separate, explicit steps.
2. **It refuses when the Herd repository is missing.** The pre-flight asks the
   `capivaraos-herd` repository for `capivaraos-herd-repos` at the target
   release. If the repository does not answer, or has no
   `capivaraos-herd-repos` for the target release, the upgrade is refused
   (exit 1), because it would move the Fedora base and leave the Herd packages
   behind. `--allow-missing-herd-repo` overrides this for `download` and
   `run`, for a transient network error only.
3. **Signatures.** The Herd repository is configured with `gpgcheck=1` and
   `repo_gpgcheck=1`. `tests/test-repo-signing.sh` shows a dnf install
   refusing tampered metadata. The upgrade transaction itself is not tested.
4. **Free space.** It warns when `/var/cache` has less than 5 GiB free. This is
   a warning, not a refusal.
5. **Snapshot when the storage allows it.** Herd does not install or
   configure Snapper or LVM snapshots.
   - Btrfs root where the administrator set up Snapper with a `root` config:
     a Snapper snapshot is taken before the download. If the snapshot fails,
     the tool warns and continues.
   - Root on LVM: no automatic snapshot. It prints the `lvcreate -s` command to
     run by hand.
   - Anything else, such as the ext4 root of the Herd 2.0 qcow2 image: no
     snapshot. Take a backup first.

## Rollback

- **Snapper:** see the Snapper documentation.
- **LVM:** the pre-flight prints the hint `lvconvert --merge` on the snapshot
  you created, then reboot. This path is not tested.
- **No snapshot:** restore from backup.

## Packaging

- Package `capivaraos-herd-upgrade` installs `/usr/bin/herd-upgrade`.
- `Requires: dnf5` and `capivaraos-herd-repos` (the `.repo` file and the keys).
- Included in the kickstart `%packages` and the osbuild blueprint.
- Build: `./rpm/build-rpm-upgrade.sh`, output in `~/rpmbuild/RPMS/noarch/`.

## Tests

`tests/test-upgrade.sh` runs in a Fedora 45 container. It builds and installs
the package, checks the argument guards, checks that the pre-flight refuses a
target with no Herd repository and passes one with a local repository that
holds `capivaraos-herd-repos`, and checks that `download` stops before dnf when
the pre-flight fails.
