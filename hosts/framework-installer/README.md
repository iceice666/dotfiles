# Framework reinstall ISO

A UEFI-only x86_64 installer for the **existing AMD Framework laptop**, not a
portable new-host installer. It embeds the flake source used to build the ISO,
including encrypted SOPS files, but no SSH/age identities or plaintext keys.
Installation requires internet access and rebuilds the selected disk from scratch.
Nothing runs automatically at boot. This is **not** a backup or an offline image.

## Build

From the repository root on x86_64 Linux (or with an appropriate remote builder):

```sh
just framework-install-test
just framework-iso
ls -lh result-framework-iso/iso/*.iso
```

Only Git-tracked files enter a Git flake source. Add new implementation files
before building. Review the source and ensure no plaintext credentials are tracked;
anyone with the ISO can read its embedded repo. The snapshot has no original Git
history. Linux `[linux]` is a recipe guard, not automatic cross-compilation support.
Write the resulting ISO to a spare USB using your usual image writer, carefully
checking the USB target. Writing the USB also destroys its contents.

The installed OS is the Framework configuration from that snapshot, including
Home Manager, Niri/AGS, themegen, Rime and Pi. The live installer is deliberately
minimal and does not start the desktop or provision credentials.

## Back up first

Full-disk installation destroys **all partitions and all Btrfs subvolumes**,
including `/home`, `/nix`, logs and snapshots. Store and verify an external backup
of personal data and any identities needed to decrypt SOPS (in particular
`~/.ssh/id_ed25519`). Keep private keys on separate trusted media, never in the
repo, ISO, or Nix store. This installer does not preserve `/home`, set up LUKS,
or restore data. Do not proceed if you cannot recover your credentials/data.

## Boot and install

1. Boot the USB in **UEFI mode**. Secure Boot must permit this unsigned image.
2. Connect wired networking, or run `nmtui` for Wi-Fi. Keep AC power connected.
3. Inspect disks and RAM:

   ```sh
   lsblk -d -o NAME,SIZE,MODEL,SERIAL
   ls -l /dev/disk/by-id/
   free -h
   ```

4. Choose the internal whole-disk path, preferably its `/dev/disk/by-id/` name.
   Specify swap explicitly. For the configured suspend-then-hibernate behavior,
   use at least the installed RAM size; that is a sizing guideline, not a guarantee
   that every workload can hibernate. For example, **replace the placeholder**:

   ```sh
   sudo framework-install --disk /dev/disk/by-id/<internal-disk> --swap-gib 64 --dry-run
   sudo framework-install --disk /dev/disk/by-id/<internal-disk> --swap-gib 64
   ```

5. The tool first evaluates the target and checks its build plan using a dry run,
   while the old disk is intact. This is **not** a full build/download check:
   actual installation builds into the target disk's store **after erasure**, avoiding
   the Live ISO's RAM-backed store filling up. Installation disables the Nix evaluation
   cache so it does not reuse preflight derivation paths absent from the target store.
   Before erasure, the installer requires an open-file hard limit of at least 65536
   and sets its soft limit to 65536. Target builds use at most two concurrent jobs.
   After mounting the SSD, it explicitly places temporary builds and caches under
   `/mnt/var/tmp/framework-install.*`, overriding inherited Live ISO settings. Download/build failures after erasure
   cannot restore old data. Review the displayed model/serial and backup; enter the
   exact `ERASE /dev/...` confirmation shown. Only then does partitioning start. It rejects mounted disks, active swap or
   mapped devices, read-only disks, competing NixOS filesystem labels, and nonempty
   `/mnt`. The boot USB is mounted and must never be selected. These checks reduce
   mistakes; they are not an OS security boundary or a substitute for backup.
6. Set the **iceice666** password at the interactive prompt. This is needed for
   desktop login and sudo before fingerprint enrollment. The tool does not set a
   root password or enable remote password login.
7. On success, unmount and reboot; remove the USB:

   ```sh
   sudo umount -R /mnt
   sudo reboot
   ```

Never remove the USB or interrupt power during installation. Once erasure begins,
errors do not roll back. A failed install leaves `/mnt` mounted for inspection;
there is no automatic reboot, unmount, or retry that re-erases a disk. Resolve the
error before rebooting. The installer prints filesystem capacity and inode usage on failure. `No space
left on device` can mean a full Live overlay, target filesystem, ESP or exhausted
inodes; the message alone does not identify which. Do not delete store paths or
rerun the erasing installer to recover. After mounting the target, the patched
source is preserved at `/mnt/root/framework-install-recovery` and build temporary
files are retained on failure for inspection. Temporary builds/caches are removed
only after successful installation, password setup and source copy.

If only password setup failed after successful installation,
use `sudo nixos-enter --root /mnt -c 'passwd iceice666'`.

## Embedded source troubleshooting

The packaged installer reads `/etc/framework-dotfiles`, the ISO-managed source
link. If it reports a missing embedded flake, check both files before proceeding:

```sh
ls -l /etc/framework-dotfiles/flake.nix /etc/framework-dotfiles/flake.lock
readlink -f /etc/framework-dotfiles
```

Older images may contain these files but have a launcher that exports a different,
missing store path. Rebuild and rewrite the ISO with the corrected launcher; simply
rebooting the old USB does not update it. This error occurs before disk erasure.
`--dry-run` only checks the disk and prints the plan; it does not check the source.

## Disk layout

| Partition | Size / format | Label / mounts |
| --- | --- | --- |
| EFI | 1 GiB FAT32 | `NIXOS_BOOT` → `/boot` |
| Swap | explicit `--swap-gib` | `NIXOS_SWAP`, existing resume configuration |
| Root | remaining space, Btrfs | `NIXOS_ROOT` |

Btrfs subvolumes are `@` → `/`, `@home` → `/home`, `@nix` → `/nix`, and
`@log` → `/var/log`, with existing compression/mount options. At least 32 GiB
is reserved for root by the size preflight; the actual desktop and data can need
considerably more space.

The installer patches the **copied** hardware configuration to mount EFI by
`NIXOS_BOOT` instead of the old FAT UUID `26D2-8AF4`. It does not change the
running system's hardware configuration. Other host-specific hardware settings
remain intact. Reusing this ISO for different hardware is not supported.

## After reboot

The editable snapshot is in `~/dotfiles`, with files staged in a newly initialized
Git repo (no original commits/remotes). It contains the installed EFI-label change.
Use it for `just build` / `just switch`. When reconnecting to the upstream Git repo,
keep that hardware change: blindly replacing it with the old UUID breaks `/boot`.
The preflight patch intentionally fails if the source EFI setting changes; update
that small installer transformation when migrating the upstream hardware config.

SOPS Home Manager secrets may fail until the existing authorized SSH identity is
restored, but their absence is not meant to block local password login. Pi API and
search credentials will not work without it. Restore the key via trusted media
with user ownership, `0700` on `~/.ssh`, and `0600` on private keys, then:

```sh
systemctl --user restart sops-nix.service
cd ~/dotfiles
just switch
fprintd-enroll
sudo tailscale up
```

If using a **new** identity, have a workstation that can decrypt the existing
secrets add the new recipient to `.sops.yaml` and refresh the relevant ciphertext
before switching. A newly generated SSH key cannot decrypt old ciphertext.
Fingerprint enrollment, Tailscale state and Wi-Fi profiles are not copied from
the old installation. SSH root/password login remains disabled.

## Validation

`just framework-install-test` checks shell syntax, arguments, read-only disk
validation fixtures, packaged source-path wiring, source-file guards and guard ordering. The preflight is an evaluation/build-plan
check, not proof that every required download or build will succeed. Packaging uses `writeShellApplication`
for ShellCheck. `just framework-iso` builds the image; `just check` checks flake
wiring. These do not test a real disk erase or firmware boot. Before relying on
the installer, boot the ISO in a UEFI VM and exercise an installation onto a
**disposable, backed-by-a-file VM disk**, including failed confirmation and password
login. Do not use the laptop's actual disk as a test target.
