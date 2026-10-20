# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests that staros-session-report's lines are what boot_test.py expects.

The report runs inside the live image; here its formatting functions run with
the system facts replaced by fixed values.
"""

import importlib.machinery
import importlib.util
import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import boot_test  # noqa: E402

REPORT_PATH = os.path.join(HERE, "..", "..", "distro", "archiso", "staros", "airootfs",
                           "usr", "local", "libexec", "staros-session-report")


def load_report():
    loader = importlib.machinery.SourceFileLoader("staros_session_report", REPORT_PATH)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


GOOD_LAYOUT = {
    "panels": [{"type": "org.staros.taskbar", "location": "bottom", "height": 40,
                "floating": False}],
    "desktops": [{"type": "org.staros.desktop", "wallpaper": "org.kde.color"}],
}


class SessionReportFormatTest(unittest.TestCase):
    def setUp(self):
        self.report = load_report()
        r = self.report
        r.find_process = {"plasmashell": 901, "kwin_wayland": 850}.get
        r.renderer = lambda: "llvmpipe (LLVM 21.1.4, 256 bits)"
        r.grant_ok = lambda: True
        r.shell_package_override = lambda: None
        r.environ_value = lambda pid, key: "org.staros.shell"
        r.environ_names = lambda pid: ["KDE_FULL_SESSION", "QT_QPA_PLATFORM"]

    def facts(self, **session):
        base = {"Type": "wayland", "Seat": "seat0", "VTNr": "1", "Class": "user"}
        base.update(session)
        return {"session": base, "shell": "org.staros.shell", "layout": GOOD_LAYOUT}

    def parse(self, *lines):
        return boot_test.parse_session("\n".join(lines) + "\n")

    def test_good_check_line_passes_boot_test(self):
        line = self.report.check_line(self.facts(), 95.2)
        session = self.parse(line, "STAROS-SESSION-OK")
        self.assertEqual(session["check"]["renderer"], "llvmpipe_(LLVM_21.1.4,_256_bits)")
        self.assertEqual(boot_test.check_session(session, {"FORBIDDEN_X"}), [])

    def test_wrong_session_type_is_caught(self):
        line = self.report.check_line(self.facts(Type="tty"), 95)
        problems = boot_test.check_session(self.parse(line, "STAROS-SESSION-OK"), set())
        self.assertEqual(problems, ["logind_type is 'tty', expected 'wayland'"])

    def test_missing_facts_are_reported_not_crashing(self):
        r = self.report
        r.find_process = lambda name: None
        r.renderer = lambda: None
        line = r.check_line({"session": {}, "shell": None, "layout": None}, 300)
        session = self.parse(line, "STAROS-SESSION-FAIL reason=no logind session")
        problems = boot_test.check_session(session, set())
        self.assertIn("session report failed: no logind session", problems)
        self.assertIn("the layout is missing or unreadable", problems)

    def test_report_and_boot_test_agree_on_layout(self):
        bad = json.loads(json.dumps(GOOD_LAYOUT))
        bad["panels"][0]["floating"] = True
        self.assertEqual(self.report.layout_problems(GOOD_LAYOUT), [])
        self.assertEqual(boot_test.layout_problems(GOOD_LAYOUT), [])
        self.assertTrue(self.report.layout_problems(bad))
        self.assertTrue(boot_test.layout_problems(bad))

    def test_idle_report_is_one_compact_json_line(self):
        r = self.report
        r.IDLE_WINDOW = 0.2
        r.uid_pids = lambda uid=None: [os.getpid()]
        r.run = lambda cmd, **kwargs: (0, "kwin 6.7.5-3\n" if cmd[0] == "pacman" else "kvm\n")
        idle = r.idle_report("llvmpipe")
        line = "STAROS-IDLE-REPORT " + json.dumps(idle, separators=(",", ":"))
        self.assertNotIn("\n", line)
        session = self.parse(line, "STAROS-SESSION-STABLE plasmashell_pid=1 kwin_pid=2")
        self.assertEqual(boot_test.check_idle(session), [])
        self.assertEqual(session["idle"]["process_count"], 1)
        self.assertEqual(session["idle"]["versions"], {"kwin": "6.7.5-3"})
        self.assertEqual(session["idle"]["virt"], "kvm")

    def test_layout_script_prints_json(self):
        self.assertIn("print(JSON.stringify(", self.report.LAYOUT_SCRIPT)


if __name__ == "__main__":
    unittest.main()
