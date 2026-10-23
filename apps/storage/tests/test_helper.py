#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for staros-storage-helper (ADR-0011): which disks are offered,
what format and boot refuse, and the exact commands they run. No command is
ever executed: the tests pass a recording runner."""

import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "helper",
                      "staros-storage-helper")


def load_helper():
    loader = importlib.machinery.SourceFileLoader("staros_storage_helper", HELPER)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


helper = load_helper()

GIB = 1024 ** 3
MEDIUM_UUID = "2026-10-23-02-32-00-00"
CMDLINE = (f"BOOT_IMAGE=/arch/boot/x86_64/vmlinuz-linux archisobasedir=arch "
           f"archisosearchuuid={MEDIUM_UUID} cow_spacesize=50%")


def disk(name, size, children=(), **fields):
    device = {"name": name, "path": f"/dev/{name}", "type": "disk", "size": size, "ro": False,
              "rm": False, "tran": None, "vendor": None, "model": None, "fstype": None,
              "label": None, "uuid": None, "mountpoints": [None]}
    device.update(fields)
    if children:
        device["children"] = list(children)
    return device


def part(name, size, **fields):
    node = {"name": name, "path": f"/dev/{name}", "type": "part", "size": size, "ro": False,
            "rm": False, "fstype": None, "label": None, "uuid": None, "mountpoints": [None]}
    node.update(fields)
    return node


# What lsblk --json --bytes prints on a test machine.
DEVICES = [
    {"name": "sr0", "path": "/dev/sr0", "type": "rom", "size": 2 * GIB, "ro": True,
     "fstype": "iso9660", "uuid": MEDIUM_UUID, "mountpoints": ["/run/archiso/bootmnt"]},
    disk("loop0", 2 * GIB, type="loop", mountpoints=["/run/archiso/airootfs"]),
    disk("zram0", 4 * GIB, mountpoints=["[SWAP]"]),
    # A blank virtual disk: usable.
    disk("vdb", 10 * GIB, tran="virtio"),
    # Too small.
    disk("vdc", 4 * GIB),
    # A USB stick with the ISO written to it, booted with copytoram.
    disk("sda", 32 * GIB, [part("sda1", 2 * GIB, fstype="iso9660", uuid=MEDIUM_UUID),
                           part("sda2", 15 * 1024 ** 2, fstype="vfat", label="ARCHISO_EFI")],
         rm=True, tran="usb", vendor="SanDisk ", model="Ultra"),
    # An internal disk with a mounted partition.
    disk("nvme0n1", 512 * GIB, [part("nvme0n1p1", GIB, fstype="vfat", mountpoints=["/mnt/efi"]),
                                part("nvme0n1p2", 511 * GIB, fstype="ext4")],
         tran="nvme", model="WD Blue SN580"),
    # A read-only card.
    disk("mmcblk0", 16 * GIB, ro=True),
    # A SATA disk with Windows data: usable, its partitions listed.
    disk("sdc", 64 * GIB, [part("sdc1", 64 * GIB, fstype="ntfs", label="Data")],
         tran="sata", vendor="ATA     ", model="Samsung SSD 870"),
]


class Recorder:
    """Records the commands instead of running them."""

    def __init__(self, outputs=None):
        self.calls = []
        self.outputs = outputs or {}

    def __call__(self, argv, stdin=None):
        self.calls.append((argv, stdin))
        return self.outputs.get(os.path.basename(argv[0]), "")


class ListTest(unittest.TestCase):
    def disks(self, devices=DEVICES):
        return {d["name"]: d for d in helper.list_disks(devices, CMDLINE)}

    def test_only_whole_disks_with_accepted_names(self):
        self.assertEqual(sorted(self.disks()), ["mmcblk0", "nvme0n1", "sda", "sdc", "vdb", "vdc"])

    def test_reasons(self):
        disks = self.disks()
        self.assertEqual({name: d["reason"] for name, d in disks.items()}, {
            "vdb": "", "vdc": "too-small", "sda": "medium", "nvme0n1": "mounted",
            "mmcblk0": "read-only", "sdc": "",
        })
        self.assertTrue(disks["vdb"]["usable"])
        self.assertFalse(disks["sda"]["usable"])
        self.assertEqual(disks["sda"]["reasonText"], "This is the Star OS medium.")

    def test_medium_found_by_uuid_alone(self):
        stick = disk("sdd", 32 * GIB, [part("sdd1", GIB, fstype="vfat", uuid=MEDIUM_UUID)])
        self.assertEqual(self.disks([stick])["sdd"]["reason"], "medium")

    def test_star_storage_in_use(self):
        storage = disk("vdb", 10 * GIB, [part("vdb1", 10 * GIB, fstype="ext4", label="STAROS_DATA",
                                              mountpoints=["/run/archiso/cowspace"])])
        listed = helper.list_command([storage], CMDLINE, {"uefi": True, "systemdBoot": True,
                                                           "default": ""})
        self.assertEqual(listed["existing"], ["vdb"])
        self.assertEqual(listed["disks"][0]["reason"], "star-storage-in-use")
        self.assertFalse(listed["always"])

    def test_names_models_and_partitions(self):
        disks = self.disks()
        self.assertEqual(disks["sda"]["model"], "SanDisk Ultra")
        self.assertEqual(disks["sdc"]["model"], "Samsung SSD 870")
        self.assertEqual(disks["nvme0n1"]["model"], "WD Blue SN580")
        self.assertTrue(disks["sda"]["removable"])
        self.assertEqual(disks["sda"]["transport"], "usb")
        self.assertEqual(disks["sdc"]["partitions"], [
            {"name": "sdc1", "path": "/dev/sdc1", "size": 64 * GIB, "fstype": "ntfs", "label": "Data"},
        ])

    def test_older_lsblk_flags_and_sizes_as_strings(self):
        old = disk("vdb", str(10 * GIB), ro="0", rm="1")
        listed = self.disks([old])["vdb"]
        self.assertTrue(listed["usable"])
        self.assertTrue(listed["removable"])
        self.assertEqual(listed["size"], 10 * GIB)

    def test_always_reflects_the_default_entry(self):
        listed = helper.list_command([], CMDLINE, {"uefi": True, "systemdBoot": True,
                                                   "default": helper.ENTRY})
        self.assertTrue(listed["always"])


class FormatTest(unittest.TestCase):
    def refused(self, name, confirm, devices=DEVICES):
        run = Recorder()
        with self.assertRaises(helper.Refused) as caught:
            helper.format_disk(name, confirm, devices, CMDLINE, run=run, emit=lambda **_: None)
        self.assertEqual(run.calls, [], "nothing runs when the request is refused")
        return str(caught.exception)

    def test_refusals(self):
        for name in ("../sda", "sda; reboot", "sda1", "loop0", "zram0", "sr0", "", "dm-0"):
            with self.subTest(name=name):
                self.assertIn("not a disk name", self.refused(name, name))
        self.assertIn("is not the disk's name", self.refused("vdb", "vdc"))
        self.assertIn("is not the disk's name", self.refused("vdb", "VDB"))
        self.assertIn("There is no disk sdz", self.refused("sdz", "sdz"))
        self.assertIn("This is the Star OS medium", self.refused("sda", "sda"))
        self.assertIn("mounted", self.refused("nvme0n1", "nvme0n1"))
        self.assertIn("smaller than 8 GiB", self.refused("vdc", "vdc"))
        self.assertIn("read-only", self.refused("mmcblk0", "mmcblk0"))

    def test_second_star_storage_is_refused(self):
        existing = disk("vdd", 10 * GIB, [part("vdd1", 10 * GIB, fstype="ext4", label="STAROS_DATA")])
        message = self.refused("vdb", "vdb", DEVICES + [existing])
        self.assertIn("vdd already has Star Storage", message)

    def test_commands(self):
        run = Recorder({"blkid": "STAROS_DATA\n"})
        steps = []
        result = helper.format_disk("sdc", "sdc", DEVICES, CMDLINE, run=run,
                                    emit=lambda **fields: steps.append(fields["step"]),
                                    exists=lambda path: path == "/dev/sdc1", sleep=lambda _: None)
        self.assertEqual(result, {"done": True, "disk": "sdc", "partition": "/dev/sdc1",
                                  "label": "STAROS_DATA"})
        self.assertEqual(steps, ["wipe", "partition", "format", "verify"])
        self.assertEqual(run.calls, [
            (["/usr/bin/wipefs", "--all", "--quiet", "/dev/sdc1"], None),
            (["/usr/bin/wipefs", "--all", "--quiet", "/dev/sdc"], None),
            (["/usr/bin/sfdisk", "--quiet", "--wipe", "always", "--wipe-partitions", "always",
              "/dev/sdc"], "label: gpt\ntype=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=STAROS_DATA\n"),
            (["/usr/bin/udevadm", "settle", "--timeout=30"], None),
            (["/usr/bin/mkfs.ext4", "-F", "-q", "-m", "0", "-L", "STAROS_DATA", "/dev/sdc1"], None),
            (["/usr/bin/udevadm", "settle", "--timeout=30"], None),
            (["/usr/bin/blkid", "-p", "-o", "value", "-s", "LABEL", "/dev/sdc1"], None),
        ])

    def test_reformatting_star_storage_that_is_not_in_use(self):
        existing = disk("vdb", 10 * GIB, [part("vdb1", 10 * GIB, fstype="ext4", label="STAROS_DATA")])
        run = Recorder({"blkid": "STAROS_DATA\n"})
        result = helper.format_disk("vdb", "vdb", [existing], CMDLINE, run=run,
                                    emit=lambda **_: None, exists=lambda _: True)
        self.assertEqual(result["partition"], "/dev/vdb1")

    def test_nvme_partition_name(self):
        blank = disk("nvme1n1", 256 * GIB)
        run = Recorder({"blkid": "STAROS_DATA\n"})
        result = helper.format_disk("nvme1n1", "nvme1n1", [blank], CMDLINE, run=run,
                                    emit=lambda **_: None, exists=lambda _: True)
        self.assertEqual(result["partition"], "/dev/nvme1n1p1")

    def test_missing_partition_and_wrong_label_fail(self):
        with self.assertRaisesRegex(helper.Refused, "did not appear"):
            helper.format_disk("vdb", "vdb", DEVICES, CMDLINE, run=Recorder(), emit=lambda **_: None,
                               exists=lambda _: False, sleep=lambda _: None)
        with self.assertRaisesRegex(helper.Refused, "instead of STAROS_DATA"):
            helper.format_disk("vdb", "vdb", DEVICES, CMDLINE, run=Recorder({"blkid": "OTHER\n"}),
                               emit=lambda **_: None, exists=lambda _: True)


class BootTest(unittest.TestCase):
    EFI = {"uefi": True, "systemdBoot": True, "default": ""}

    def test_modes(self):
        for mode, argv in (("next", ["set-oneshot", helper.ENTRY]),
                           ("always", ["set-default", helper.ENTRY]),
                           ("never", ["set-default", ""])):
            with self.subTest(mode=mode):
                run = Recorder()
                self.assertEqual(helper.boot(mode, self.EFI, run=run), {"done": True, "boot": mode})
                self.assertEqual(run.calls, [(["/usr/bin/bootctl", *argv], None)])

    def test_refusals(self):
        run = Recorder()
        with self.assertRaisesRegex(helper.Refused, "not next, always or never"):
            helper.boot("sometimes", self.EFI, run=run)
        with self.assertRaisesRegex(helper.Refused, "without UEFI"):
            helper.boot("next", {"uefi": False, "systemdBoot": False, "default": ""}, run=run)
        with self.assertRaisesRegex(helper.Refused, "not started from its own boot menu"):
            helper.boot("next", {"uefi": True, "systemdBoot": False, "default": ""}, run=run)
        self.assertEqual(run.calls, [])
        # Unknown (variables not readable) is left to bootctl.
        helper.boot("next", {"uefi": True, "systemdBoot": None, "default": ""}, run=run)
        self.assertEqual(len(run.calls), 1)


class EfiStateTest(unittest.TestCase):
    def write(self, efi_dir, name, text):
        path = os.path.join(efi_dir, "efivars", f"{name}-{helper.LOADER_GUID}")
        with open(path, "wb") as f:
            f.write(b"\x06\x00\x00\x00" + (text + "\0").encode("utf-16-le"))

    def test_states(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(helper.efi_state(os.path.join(tmp, "missing")),
                             {"uefi": False, "systemdBoot": False, "default": ""})
            os.mkdir(os.path.join(tmp, "efivars"))
            self.assertEqual(helper.efi_state(tmp), {"uefi": True, "systemdBoot": False, "default": ""})
            self.write(tmp, "LoaderInfo", "systemd-boot 258.1-1-arch")
            self.write(tmp, "LoaderEntryDefault", helper.ENTRY)
            self.assertEqual(helper.efi_state(tmp),
                             {"uefi": True, "systemdBoot": True, "default": helper.ENTRY})


class MainTest(unittest.TestCase):
    def main(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = helper.main(["staros-storage-helper", *args])
        return code, out.getvalue(), err.getvalue()

    def test_usage(self):
        for args in ((), ("format", "vdb"), ("boot",), ("erase", "vdb", "vdb"), ("list", "extra")):
            with self.subTest(args=args):
                code, out, err = self.main(*args)
                self.assertEqual(code, 2)
                self.assertEqual(out, "")
                self.assertIn("staros-storage-helper list", err)

    @unittest.skipIf(os.geteuid() == 0, "running as root")
    def test_changes_need_root(self):
        for args in (("format", "vdb", "vdb"), ("boot", "next")):
            with self.subTest(args=args):
                code, out, _ = self.main(*args)
                self.assertEqual(code, 1)
                self.assertEqual(json.loads(out), {"error": "This needs to run as root, through pkexec."})


if __name__ == "__main__":
    unittest.main()
