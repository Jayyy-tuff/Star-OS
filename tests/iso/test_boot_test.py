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
        for profile in boot_test.PROFILES:
            cmd = self.build("bios", profile=profile)
            for disk_option in ("-hda", "-hdb", "-sda", "-blockdev"):
                self.assertNotIn(disk_option, cmd)
            devices = [cmd[i + 1] for i, arg in enumerate(cmd) if arg == "-device"]
            self.assertTrue(all(d.startswith("VGA,") for d in devices), devices)
            self.assertEqual(cmd[cmd.index("-cdrom") + 1], "/tmp/s.iso")

    def test_minimal_profile_is_unchanged(self):
        cmd = self.build("bios")
        self.assertEqual(cmd[cmd.index("-smp") + 1], "2")
        self.assertEqual(cmd[cmd.index("-vga") + 1], "std")

    def test_graphical_profile(self):
        cmd = self.build("uefi", profile="graphical", memory_mib=4096,
                         ovmf_code="/fw/code.fd", ovmf_vars="/tmp/vars.fd")
        self.assertEqual(cmd[cmd.index("-smp") + 1], "4")
        self.assertEqual(cmd[cmd.index("-m") + 1], "4096")
        self.assertEqual(cmd[cmd.index("-vga") + 1], "none")
        self.assertIn("xres=1920,yres=1080", cmd[cmd.index("-device") + 1])

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


LAYOUT = ('{"desktops":[{"type":"org.staros.desktop","wallpaper":"org.kde.color"}],'
          '"panels":[{"floating":false,"height":40,"location":"bottom",'
          '"type":"org.staros.taskbar"}]}')
CHECK = ("STAROS-SESSION-CHECK seconds=95 user=liveuser logind_type=wayland seat=seat0 vt=1 "
         "class=user shell=org.staros.shell layout=" + LAYOUT + " renderer=llvmpipe_(LLVM) "
         "grant=ok shellrc_override=none plasmashell_pid=901 kwin_pid=850 "
         "plasma_default_shell=org.staros.shell env_kwin=KDE_FULL_SESSION,QT_QPA_PLATFORM "
         "env_plasmashell=PLASMA_DEFAULT_SHELL")
FORBIDDEN = {"BAD_ONE", "BAD_TWO"}


class SessionTest(unittest.TestCase):
    def session(self, *lines):
        return boot_test.parse_session("\r\n".join(lines) + "\r\n")

    def test_good_session_passes(self):
        session = self.session("boot noise", CHECK, "STAROS-SESSION-OK")
        self.assertEqual(session["status"], "ok")
        self.assertEqual(boot_test.check_session(session, FORBIDDEN), [])

    def test_no_verdict_yet(self):
        session = self.session(CHECK)
        self.assertIsNone(session["status"])
        self.assertEqual(len(boot_test.check_session(session, FORBIDDEN)), 1)

    def test_fail_line_carries_reason(self):
        session = self.session(CHECK.replace("shell=org.staros.shell ", "shell=none "),
                               "STAROS-SESSION-FAIL reason=plasmashell loaded shell 'x'")
        self.assertEqual(session["reason"], "plasmashell loaded shell 'x'")
        problems = boot_test.check_session(session, FORBIDDEN)
        self.assertTrue(any("session report failed" in p for p in problems))
        self.assertTrue(any(p.startswith("shell is") for p in problems))

    def test_x11_session_fails(self):
        session = self.session(CHECK.replace("logind_type=wayland", "logind_type=tty"),
                               "STAROS-SESSION-OK")
        self.assertIn("logind_type is 'tty', expected 'wayland'",
                      boot_test.check_session(session, FORBIDDEN))

    def test_forbidden_variable_fails(self):
        session = self.session(CHECK.replace("env_kwin=KDE_FULL_SESSION", "env_kwin=BAD_ONE"),
                               "STAROS-SESSION-OK")
        problems = boot_test.check_session(session, FORBIDDEN)
        self.assertEqual(problems, ["env_kwin contains forbidden variables: BAD_ONE"])

    def test_missing_grant_fails(self):
        session = self.session(CHECK.replace("grant=ok", "grant=missing"), "STAROS-SESSION-OK")
        self.assertEqual(len(boot_test.check_session(session, FORBIDDEN)), 1)

    def test_floating_panel_fails(self):
        session = self.session(CHECK.replace('"floating":false', '"floating":true'),
                               "STAROS-SESSION-OK")
        self.assertEqual(len(boot_test.check_session(session, FORBIDDEN)), 1)

    def test_plasma_desktop_fallback_fails(self):
        session = self.session(CHECK.replace("org.staros.desktop", "org.kde.plasma.folder"),
                               "STAROS-SESSION-OK")
        self.assertEqual(len(boot_test.check_session(session, FORBIDDEN)), 1)

    def test_unreadable_layout_fails(self):
        session = self.session(CHECK.replace(LAYOUT, "{broken"), "STAROS-SESSION-OK")
        self.assertIn("the layout is missing or unreadable",
                      boot_test.check_session(session, FORBIDDEN))

    def test_idle_and_stable(self):
        session = self.session(CHECK, "STAROS-SESSION-OK",
                               'STAROS-IDLE-REPORT {"session_pss_mib": 612.4}',
                               "STAROS-IDLE-DONE",
                               "STAROS-SESSION-STABLE plasmashell_pid=901 kwin_pid=850")
        self.assertEqual(session["idle"]["session_pss_mib"], 612.4)
        self.assertEqual(boot_test.check_idle(session), [])

    def test_unstable_session_fails(self):
        session = self.session('STAROS-IDLE-REPORT {"session_pss_mib": 1}',
                               "STAROS-SESSION-UNSTABLE plasmashell_pid=7 kwin_pid=850 "
                               "reason=plasmashell pid 901 -> 7")
        self.assertEqual(boot_test.check_idle(session),
                         ["session unstable: plasmashell pid 901 -> 7"])

    def test_truncated_idle_report_fails(self):
        session = self.session('STAROS-IDLE-REPORT {"session_pss', "STAROS-SESSION-STABLE")
        self.assertEqual(len(boot_test.check_idle(session)), 1)

    def test_missing_idle_phases_fail(self):
        self.assertEqual(len(boot_test.check_idle(self.session(CHECK, "STAROS-SESSION-OK"))), 2)

    def test_repository_forbidden_list_is_read(self):
        names = boot_test.read_forbidden_env()
        self.assertGreaterEqual(len(names), 1)
        self.assertFalse(any(n.startswith("#") or " " in n for n in names))


class MainTest(unittest.TestCase):
    def test_missing_iso_is_a_setup_error(self):
        self.assertEqual(boot_test.main(["--iso", "/nonexistent.iso", "--firmware", "bios"]), 2)

    def test_wait_idle_needs_session(self):
        with self.assertRaises(SystemExit):
            boot_test.main(["--iso", "x.iso", "--firmware", "bios", "--wait-idle"])

    def test_missing_qemu_is_a_setup_error(self):
        with tempfile.NamedTemporaryFile(suffix=".iso") as iso:
            code = boot_test.main(["--iso", iso.name, "--firmware", "bios",
                                   "--qemu", "definitely-not-qemu"])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
