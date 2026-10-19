# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for boot_test.py. They do not start QEMU."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import boot_test  # noqa: E402

REPORT = "STAROS-BOOT-CHECK id=staros firmware=uefi kernel=6.17.1-arch1-1"


class ParseBootReportTest(unittest.TestCase):
    def test_report_followed_by_marker(self):
        text = f"noise\r\n{REPORT}\r\nSTAROS-LIVE-BOOT-OK\r\n"
        self.assertEqual(
            boot_test.parse_boot_report(text),
            {"id": "staros", "firmware": "uefi", "kernel": "6.17.1-arch1-1"})

    def test_report_after_firmware_output_on_same_line(self):
        text = f"\x1b[0mBdsDxe: loading Boot0001{REPORT}\nSTAROS-LIVE-BOOT-OK\n"
        self.assertEqual(boot_test.parse_boot_report(text)["id"], "staros")

    def test_marker_without_report_is_not_a_pass(self):
        self.assertIsNone(boot_test.parse_boot_report("STAROS-LIVE-BOOT-OK\n"))

    def test_report_without_marker_is_not_a_pass(self):
        self.assertIsNone(boot_test.parse_boot_report(REPORT + "\n"))

    def test_marker_before_report_is_not_a_pass(self):
        self.assertIsNone(boot_test.parse_boot_report(f"STAROS-LIVE-BOOT-OK\n{REPORT}\n"))

    def test_partial_line_is_not_a_pass(self):
        self.assertIsNone(boot_test.parse_boot_report(f"{REPORT}\nSTAROS-LIVE-BO"))


class CheckReportTest(unittest.TestCase):
    def test_pass(self):
        report = {"id": "staros", "firmware": "bios"}
        self.assertEqual(boot_test.check_report(report, "staros", "bios"), [])

    def test_missing_report(self):
        self.assertEqual(len(boot_test.check_report(None, "staros", "uefi")), 1)

    def test_wrong_id_and_firmware(self):
        report = {"id": "unknown", "firmware": "bios"}
        problems = boot_test.check_report(report, "staros", "uefi")
        self.assertEqual(len(problems), 2)


class FindOvmfTest(unittest.TestCase):
    def test_first_complete_pair_wins(self):
        candidates = (("a-code", "a-vars"), ("b-code", "b-vars"), ("c-code", "c-vars"))
        present = {"a-code", "b-code", "b-vars", "c-code", "c-vars"}
        self.assertEqual(
            boot_test.find_ovmf(candidates, exists=present.__contains__), ("b-code", "b-vars"))

    def test_none_found(self):
        self.assertIsNone(boot_test.find_ovmf((("x", "y"),), exists=lambda _: False))


class BuildQemuCommandTest(unittest.TestCase):
    def build(self, firmware, **kwargs):
        args = dict(qemu="qemu", iso="/tmp/s.iso", firmware=firmware, accel="kvm",
                    memory_mib=2048, serial_log="/tmp/serial.log", qmp_socket="/tmp/q.sock")
        args.update(kwargs)
        return boot_test.build_qemu_command(**args)

    def drives(self, cmd):
        return [cmd[i + 1] for i, arg in enumerate(cmd) if arg == "-drive"]

    def test_uefi_uses_read_only_code_and_writable_vars(self):
        cmd = self.build("uefi", ovmf_code="/fw/code.fd", ovmf_vars="/tmp/vars.fd")
        self.assertEqual(self.drives(cmd), [
            "if=pflash,format=raw,unit=0,readonly=on,file=/fw/code.fd",
            "if=pflash,format=raw,unit=1,file=/tmp/vars.fd",
        ])

    def test_bios_has_no_firmware_drives(self):
        self.assertEqual(self.drives(self.build("bios")), [])

    def test_only_the_iso_is_attached_and_never_a_disk(self):
        cmd = self.build("bios")
        for disk_option in ("-hda", "-hdb", "-sda", "-blockdev", "-device"):
            self.assertNotIn(disk_option, cmd)
        self.assertEqual(cmd[cmd.index("-cdrom") + 1], "/tmp/s.iso")

    def test_guest_network_is_isolated(self):
        cmd = self.build("bios")
        self.assertIn("restrict=on", cmd[cmd.index("-nic") + 1])

    def test_tcg_fallback(self):
        cmd = self.build("bios", accel="tcg")
        self.assertEqual(cmd[cmd.index("-accel") + 1], "tcg")
        self.assertEqual(cmd[cmd.index("-cpu") + 1], "max")

    def test_uefi_without_firmware_is_an_error(self):
        with self.assertRaises(boot_test.SetupError):
            self.build("uefi")

    def test_comma_in_path_is_an_error(self):
        with self.assertRaises(boot_test.SetupError):
            self.build("bios", iso="/tmp/a,b.iso")


class MainTest(unittest.TestCase):
    def test_missing_iso_is_a_setup_error(self):
        self.assertEqual(boot_test.main(["--iso", "/nonexistent.iso", "--firmware", "bios"]), 2)

    def test_missing_qemu_is_a_setup_error(self):
        with tempfile.NamedTemporaryFile(suffix=".iso") as iso:
            code = boot_test.main(["--iso", iso.name, "--firmware", "bios",
                                   "--qemu", "definitely-not-qemu"])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
