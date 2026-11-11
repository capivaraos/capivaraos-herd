# In-place version upgrade of Herd: `herd-upgrade`

## What it does

Continuous updates keep Herd Community patched **within the current version**. `herd-upgrade` moves a server to the **next version** (F44 → F45 and onwards) **without reinstalling**, keeping data, configuration and hardening. It is the headless-server counterpart of the desktop's "new version available".

## How it works

`herd-upgrade` is an **auditable wrapper** around `dnf5 system-upgrade`, Fedora's **offline** upgrade mechanism: everything is downloaded while the system is running and applied on the next boot, in an isolated environment with no services running. From Fedora 44 the subcommand is **built into `dnf5`** (there is no separate plugin).

The target is **not hard-coded**: it comes from `rpm -E %fedora` (current version + 1) or from `--to N`. Because the repository `baseurl` uses `$releasever` (`herd/f$releasever/...`), the same tool and the same `.repo` file work for every later upgrade without changes.

## Usage

```sh
# 1. Pre-flight check (default, safe: no download, no reboot):
herd-upgrade                 # or: herd-upgrade check --to 45

# 2. Download the transaction (the server stays up):
sudo herd-upgrade download   # or: sudo herd-upgrade download --to 45

# 3. Apply (reboots into offline mode):
sudo herd-upgrade reboot

# Shortcut: download + reboot, with confirmation
sudo herd-upgrade run --to 45

# Utilities: status | log | clean (shortcuts to dnf5 system-upgrade)
```

## Safety guarantees

1. **Safe by default.** With no argument it runs only the **pre-flight check**; nothing changes. Downloading and rebooting are **separate, explicit** steps.
2. **Fails closed.** The pre-flight check **refuses** the upgrade if the signed Herd repository (`capivaraos-herd`) does **not yet exist** for the target version. Without this check the server would move to the new Fedora base and leave the Herd packages (branding, hardening, repos, autoupdate) **behind**. Until `repo.capivaraos.org/herd/f45/` is published, `herd-upgrade` stops at f45 on purpose. (For a transient network error, `--allow-missing-herd-repo` overrides the check at your own risk.)
3. **Trust in the signature, not the host.** The transaction honours the repository's `gpgcheck=1` and `repo_gpgcheck=1`: it rejects any package **or metadata** not signed by the project key, even if the host is compromised (covered by `tests/test-repo-signing.sh`).
4. **Snapshot first, when possible.** If the root filesystem is **btrfs + snapper**, an automatic snapshot is taken before the upgrade. On **LVM** (the Herd 1.x default with an encrypted disk), no automatic snapshot is taken, because LVM rollback requires a merge at reboot; the tool **prints** the manual command:

   ```sh
   sudo lvcreate -s -n root_pre_f45 -L 5G /dev/mapper/<vg>-<root>
   # rollback: sudo lvconvert --merge <snapshot> && reboot
   ```

   Without compatible storage, it reminds you to take a **backup** first.

## Rollback

- **snapper/btrfs:** `snapper rollback` from the pre-upgrade snapshot.
- **LVM:** `lvconvert --merge` on the manually created snapshot, then reboot.
- **No snapshot:** restore from backup. This is why the pre-flight check asks
  for a backup when there is no snapshot.

## Tests

`tests/test-upgrade.sh` (Fedora 44 container) covers building and installing the package, argument checks, refusal when the target repository does not exist, approval when it does, and a safe abort of `download` when the pre-flight check fails.

## Packaging

- Package **`capivaraos-herd-upgrade`** → `/usr/bin/herd-upgrade`.
- `Requires: dnf5` (system-upgrade built in) and `capivaraos-herd-repos` (ensures the `.repo` file and key are present for the target).
- Included in the kickstart `%packages` and in the osbuild blueprint.
- Build: `./rpm/build-rpm-upgrade.sh` → `~/rpmbuild/RPMS/noarch/`.
