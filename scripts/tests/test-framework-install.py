#!/usr/bin/env python3
"""Non-destructive tests for the Framework installer CLI and disk validator.

Only argument paths that exit before disk discovery are run through Bash. The
embedded Python validator runs against JSON and a fake /sys tree, never devices.
Run: python3 scripts/tests/test-framework-install.py
"""

import ast
import io
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "framework-install"
GIB = 1024**3
DISK = "/dev/framework-test-disk"
PARTITION = DISK + "-part1"


def block(name=DISK, kind="disk", size=128 * GIB, **attributes):
    node = {
        "name": name,
        "type": kind,
        "size": size,
        "ro": False,
        "mountpoints": [None],
        "label": None,
    }
    node.update(attributes)
    return node


def extract_validator(source):
    """Extract the exact quoted Python body, failing closed if its shape changes."""
    match = re.search(
        r"^validate_disk\(\) \{\n.*?python3 -c '(.*?)' \"\$disk\" \"\$swap_gib\"\n\}",
        source,
        re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise AssertionError("Could not locate validate_disk's embedded Python")
    code = match.group(1)
    return compile(ast.parse(code, filename=str(SCRIPT) + ":validate_disk"),
                   str(SCRIPT) + ":validate_disk", "exec")


class FakeSysPath:
    """Only the validator's holders paths exist; no real filesystem is queried."""

    def __init__(self, path, holders):
        self.path = PurePosixPath(path)
        self.holders = holders

    @property
    def name(self):
        return self.path.name

    def __truediv__(self, other):
        return FakeSysPath(self.path / other, self.holders)

    def exists(self):
        self._check_holder_path()
        return str(self.path) in self.holders

    def iterdir(self):
        self._check_holder_path()
        return iter(self.holders[str(self.path)])

    def _check_holder_path(self):
        if self.path.parent.parent != PurePosixPath("/sys/class/block"):
            raise AssertionError("Unexpected filesystem access: " + str(self.path))
        if self.name != "holders":
            raise AssertionError("Unexpected filesystem access: " + str(self.path))


class DiskValidatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = extract_validator(SCRIPT.read_text())

    def validate(self, nodes, disk=DISK, swap=32, holders=None):
        holder_paths = {
            "/sys/class/block/" + PurePosixPath(name).name + "/holders": entries
            for name, entries in (holders or {}).items()
        }
        with patch("sys.stdin", io.StringIO(json.dumps({"blockdevices": nodes}))), \
                patch("sys.argv", ["validator", disk, str(swap)]), \
                patch("pathlib.Path", side_effect=lambda path: FakeSysPath(path, holder_paths)):
            try:
                exec(self.code, {"__name__": "__main__"})
            except SystemExit as error:
                return error.code
        return None

    def assert_rejected(self, nodes, message, **arguments):
        error = self.validate(nodes, **arguments)
        self.assertIsInstance(error, str)
        self.assertIn("ERROR: " + message, error)

    def test_valid_empty_disk(self):
        self.assertIsNone(self.validate([block()]))

    def test_valid_unmounted_existing_partitions_and_own_labels(self):
        children = [
            block(DISK + "-part" + str(index), "part", label=label,
                  mountpoints=mountpoints)
            for index, (label, mountpoints) in enumerate(
                [("NIXOS_BOOT", []), ("NIXOS_ROOT", [None]), ("NIXOS_SWAP", None)], 1)
        ]
        self.assertIsNone(self.validate([block(children=children)]))

    def test_other_mounted_disk_is_not_selected(self):
        self.assertIsNone(self.validate([
            block(), block("/dev/unrelated-test-disk", mountpoints=["/"])
        ]))

    def test_missing_target(self):
        for nodes in ([], [block("/dev/unrelated-test-disk")]):
            with self.subTest(nodes=nodes):
                self.assert_rejected(nodes, "Select a whole disk")

    def test_partition_target(self):
        self.assert_rejected(
            [block(children=[block(PARTITION, "part")])],
            "Select a whole disk", disk=PARTITION)
        self.assert_rejected([block(kind="part")], "Select a whole disk")

    def test_virtual_target(self):
        for kind in ("crypt", "lvm", "raid1", "loop", "rom", "mpath"):
            with self.subTest(kind=kind):
                self.assert_rejected([block(kind=kind)], "Select a whole disk")

    def test_read_only_target(self):
        for read_only in (True, 1):
            with self.subTest(read_only=read_only):
                self.assert_rejected([block(ro=read_only)], "Disk is read-only")

    def test_minimum_capacity_boundary_for_multiple_swap_sizes(self):
        for swap in (1, 32, 64, 9999):
            minimum = (swap + 34) * GIB
            with self.subTest(swap=swap):
                self.assert_rejected([block(size=minimum - 1)],
                                     "Disk needs room for swap", swap=swap)
                self.assertIsNone(self.validate([block(size=minimum)], swap=swap))

    def test_mounts_and_active_swap_on_disk_or_partition(self):
        for mountpoints in (["/"], [None, "/home"], ["[SWAP]"], ["/run/iso"]):
            for nested in (False, True):
                with self.subTest(mountpoints=mountpoints, nested=nested):
                    node = block(PARTITION if nested else DISK,
                                 "part" if nested else "disk", mountpoints=mountpoints)
                    nodes = [block(children=[node])] if nested else [node]
                    self.assert_rejected(nodes, "Disk has mounted filesystems or active swap")

    def test_nested_mount(self):
        nested = block(DISK + "-part2", "part", mountpoints=["/mnt"])
        self.assert_rejected([block(children=[block(PARTITION, "part", children=[nested])])],
                             "Disk has mounted filesystems or active swap")

    def test_active_mapped_or_raid_descendants(self):
        for kind in ("crypt", "lvm", "raid1", "mpath"):
            with self.subTest(kind=kind):
                mapped = block("/dev/framework-test-mapped", kind)
                self.assert_rejected([block(children=[block(PARTITION, "part", children=[mapped])])],
                                     "Disk has active mapped/RAID devices")

    def test_active_sysfs_holders(self):
        nodes = [block(children=[block(PARTITION, "part")])]
        for name in (DISK, PARTITION):
            with self.subTest(name=name):
                self.assert_rejected(nodes, "Disk has active holders: " + name,
                                     holders={name: ["framework-test-holder"]})

    def test_empty_sysfs_holders_are_allowed(self):
        self.assertIsNone(self.validate([block(children=[block(PARTITION, "part")])],
                                        holders={DISK: [], PARTITION: []}))

    def test_duplicate_labels_on_other_disk_or_nested_partition(self):
        for label in ("NIXOS_BOOT", "NIXOS_ROOT", "NIXOS_SWAP"):
            for nested in (False, True):
                with self.subTest(label=label, nested=nested):
                    conflicting = block("/dev/other-test-disk-part1" if nested else
                                        "/dev/other-test-disk", "part" if nested else "disk",
                                        label=label)
                    other = block("/dev/other-test-disk", children=[conflicting]) if nested else conflicting
                    self.assert_rejected([block(), other], "Another disk has a conflicting NixOS label")

    def test_unrelated_label_is_allowed(self):
        self.assertIsNone(self.validate([block(), block("/dev/other-test-disk", label="DATA")]))


class CliTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bash = shutil.which("bash")
        if cls.bash is None:
            raise unittest.SkipTest("Bash is unavailable")

    def run_cli(self, *arguments):
        # No external executable can run even if an early-exit case regresses.
        # Bash startup injection is excluded by supplying a minimal environment.
        return subprocess.run([self.bash, "--noprofile", "--norc", str(SCRIPT), *arguments],
                              env={"PATH": "", "LC_ALL": "C"},
                              stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, timeout=5, check=False)

    def test_help(self):
        for flag in ("--help", "-h"):
            with self.subTest(flag=flag):
                result = self.run_cli(flag)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Usage: framework-install", result.stdout)
                self.assertIn("Erases the entire disk", result.stdout)
                self.assertIn("--dry-run", result.stdout)
                self.assertEqual(result.stderr, "")

    def test_bad_arguments_exit_before_disk_discovery(self):
        cases = [
            ([], "Usage:"),
            (["--dry-run"], "Usage:"),
            (["--unknown"], "Unknown argument:"),
            (["--disk"], "Missing value for --disk"),
            (["--swap-gib"], "Missing value for --swap-gib"),
            (["--disk", DISK], "Usage:"),
            (["--swap-gib", "32"], "Usage:"),
            (["--disk", "relative-disk", "--swap-gib", "32"], "Use a /dev/ disk path"),
        ]
        cases.extend((["--disk", DISK, "--swap-gib", value], "Usage:")
                     for value in ("", "0", "-1", "01", "1.5", "abc", "10000"))
        for arguments, message in cases:
            with self.subTest(arguments=arguments):
                result = self.run_cli(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertNotIn("command not found", result.stderr)
                self.assertNotIn("Plan: ERASE", result.stdout)


class EmbeddedSourceTests(unittest.TestCase):
    def test_packaged_launcher_uses_etc_source(self):
        configuration = (SCRIPT.parents[1] / "hosts/framework-installer/configuration.nix").read_text()
        self.assertIn('"framework-dotfiles".source = dotfiles;', configuration)
        self.assertIn("export FRAMEWORK_INSTALL_SOURCE=/etc/framework-dotfiles\n", configuration)
        self.assertNotIn("toString dotfiles", configuration)

    def test_symlink_source_copies_contents_into_writable_directory(self):
        bash = shutil.which("bash")
        if bash is None:
            self.skipTest("Bash is unavailable")
        source = SCRIPT.read_text()
        command = next(line for line in source.splitlines() if line.startswith("cp -a -- "))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = root / "store-source"
            store.mkdir()
            flake = store / "flake.nix"
            flake.write_text("original")
            flake.chmod(0o444)
            link = root / "etc-source"
            link.symlink_to(store, target_is_directory=True)
            repo = root / "copied-repo"
            result = subprocess.run(
                [bash, "--noprofile", "--norc", "-c", command],
                env={"PATH": str(Path(shutil.which("cp")).parent),
                     "source_dir": str(link), "repo": str(repo)},
                capture_output=True, text=True, timeout=5, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(repo.is_symlink())
            copied = repo / "flake.nix"
            copied.chmod(0o644)
            copied.write_text("patched")
            self.assertEqual(flake.read_text(), "original")
            self.assertEqual(flake.stat().st_mode & 0o777, 0o444)

    def test_source_check_accepts_complete_flake_and_reports_missing_files(self):
        bash = shutil.which("bash")
        if bash is None:
            self.skipTest("Bash is unavailable")
        source = SCRIPT.read_text()
        start = source.index("source_dir=${FRAMEWORK_INSTALL_SOURCE:")
        end = source.index("\n\n", start)
        # Execute only the exact source guard, never disk discovery or installation.
        guard = "fail() { printf '%s\\n' \"$*\" >&2; exit 1; }\n" + source[start:end]
        with tempfile.TemporaryDirectory(prefix="framework source ") as directory:
            for files in ((), ("flake.nix",), ("flake.lock",), ("flake.nix", "flake.lock")):
                with self.subTest(files=files):
                    for name in ("flake.nix", "flake.lock"):
                        path = Path(directory) / name
                        if name in files:
                            path.touch()
                        elif path.exists():
                            path.unlink()
                    result = subprocess.run(
                        [bash, "--noprofile", "--norc", "-c", guard],
                        env={"PATH": "", "FRAMEWORK_INSTALL_SOURCE": directory},
                        capture_output=True, text=True, timeout=5, check=False)
                    if len(files) == 2:
                        self.assertEqual(result.returncode, 0, result.stderr)
                    else:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn("Embedded flake is missing at " + directory, result.stderr)


class SafetyOrderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SCRIPT.read_text()

    def test_preflight_and_confirmation_precede_all_destructive_commands(self):
        source = self.source
        preflight = re.search(
            r'^nix build "path:\$repo#nixosConfigurations\.framework\.config\.system\.build\.toplevel" '
            r'\\\n  --no-write-lock-file --dry-run$', source, re.MULTILINE)
        self.assertIsNotNone(preflight)
        confirm = source.index('[[ $confirmation == "ERASE $disk" ]] || fail')
        revalidate = source.index("\nvalidate_disk\n", confirm)
        first_wipe = source.index('\nwipefs --all "$disk"')
        self.assertLess(preflight.end(), source.index("IFS= read -r confirmation"))
        self.assertLess(confirm, revalidate)
        self.assertLess(revalidate, first_wipe)
        operations = re.findall(
            r"^(wipefs|parted|partprobe|mkfs\.fat|mkswap|mkfs\.btrfs|mount|umount|nixos-install)\b",
            source[:first_wipe], re.MULTILINE)
        self.assertEqual(operations, [])

    def test_target_flake_install_occurs_after_wipe_and_mounts(self):
        source = self.source
        install = re.search(
            r'^nixos-install --root /mnt --flake "path:\$repo#framework" '
            r'\\\n  --no-write-lock-file --no-root-passwd --no-channel-copy$',
            source, re.MULTILINE)
        self.assertIsNotNone(install)
        self.assertLess(source.index('\nwipefs --all "$disk"'), install.start())
        for mount in (
            'mount -o "subvol=@,$options" "$root" /mnt',
            'mount -o "subvol=@home,$options" "$root" /mnt/home',
            'mount -o "subvol=@nix,$options" "$root" /mnt/nix',
            'mount -o "subvol=@log,$options" "$root" /mnt/var/log',
            'mount -o fmask=0077,dmask=0077 "$efi" /mnt/boot',
        ):
            with self.subTest(mount=mount):
                self.assertLess(source.index(mount), install.start())
        self.assertNotIn('system=$(readlink -e "$work/system")', source)
        self.assertNotIn('nixos-install --root /mnt --system', source)

    def test_single_install_lock_precedes_identity_snapshot_and_build(self):
        source = self.source
        dry_exit = source.index("$dry_run && exit 0")
        lock_open = source.index("exec 9>/run/framework-install.lock")
        lock_acquire = source.index(
            "flock --nonblock 9 || fail 'Another Framework installation is running.'")
        snapshot = source.index("disk_identity=$(lsblk ")
        build = source.index("nix build ")
        self.assertLess(dry_exit, lock_open)
        self.assertLess(lock_open, lock_acquire)
        self.assertLess(lock_acquire, snapshot)
        self.assertLess(snapshot, build)
        # Keep the lock descriptor for the entire destructive install path.
        self.assertNotRegex(source[lock_acquire:], r"exec\s+9[<>]&-")

    def test_identity_and_mount_rechecks_follow_confirmation_before_wipe(self):
        source = self.source
        query = 'lsblk --json --bytes --nodeps --output NAME,SIZE,MODEL,SERIAL,WWN "$disk"'
        snapshot = source.index("disk_identity=$(" + query + ")")
        build = source.index("nix build ")
        confirm = source.index('[[ $confirmation == "ERASE $disk" ]] || fail')
        revalidate = source.index("\nvalidate_disk\n", confirm)
        identity_recheck = source.index(
            '[[ $(' + query + ') == "$disk_identity" ]] || fail '
            "'Disk identity changed during the build.'")
        mounts_recheck = source.index(
            "[[ -z $(findmnt -rn -o TARGET | grep -E '^/mnt(/|$)' || true) ]] || fail "
            "'/mnt acquired mounts during the build.'")
        files_recheck = source.index(
            "[[ ! -d /mnt || -z $(ls -A /mnt) ]] || fail "
            "'/mnt acquired files during the build.'")
        first_wipe = source.index('\nwipefs --all "$disk"')
        self.assertLess(snapshot, build)
        self.assertLess(build, confirm)
        self.assertLess(confirm, revalidate)
        self.assertLess(revalidate, identity_recheck)
        self.assertLess(identity_recheck, mounts_recheck)
        self.assertLess(mounts_recheck, files_recheck)
        self.assertLess(files_recheck, first_wipe)

    def test_dry_run_exits_before_installation_prerequisites_and_build(self):
        source = self.source
        initial_validation = source.index("\nvalidate_disk\n")
        dry_exit = source.index("$dry_run && exit 0")
        self.assertLess(initial_validation, dry_exit)
        self.assertLess(dry_exit, source.index("[[ $EUID == 0 ]]"))
        self.assertLess(dry_exit, source.index("nix build "))

    def test_local_installer_and_mount_guards_precede_build(self):
        source = self.source
        build = source.index("nix build ")
        guards = (
            "[[ $EUID == 0 ]]",
            "[[ -f /etc/framework-installer ]]",
            "[[ -d /sys/firmware/efi/efivars ]]",
            "[[ -t 0 && -t 1 ]]",
            "'/mnt already has mounts.'",
            "'/mnt must be empty.'",
            '"Embedded flake is missing at $source_dir',
        )
        for guard in guards:
            with self.subTest(guard=guard):
                self.assertLess(source.index(guard), build)


if __name__ == "__main__":
    unittest.main(verbosity=2)
