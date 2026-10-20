# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for the pure helpers of session_test.py (no QEMU)."""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import session_test  # noqa: E402

TREE = {
    "role": "application", "name": "plasmashell", "children": [
        {"role": "frame", "name": "", "children": [
            {"role": "tool bar", "name": "Taskbar", "description": "", "children": [
                {"role": "push button", "name": "Applications", "description": "x", "children": []},
                {"role": "list", "name": "Open windows", "description": "", "children": [
                    {"role": "push button", "name": "Konsole", "description": "Window",
                     "children": []},
                    {"role": "push button", "name": "System Settings",
                     "description": "Active window", "children": []},
                ]},
                {"role": "push button", "name": "Leave", "description": "", "children": []},
            ]},
        ]},
    ],
}


class HelperTest(unittest.TestCase):
    def test_find_by_role_and_name(self):
        self.assertEqual(len(session_test.find(TREE, role="tool bar", name="Taskbar")), 1)
        self.assertEqual(len(session_test.find(TREE, role="push button")), 4)
        windows = session_test.find(TREE, role="list", name="Open windows")[0]
        self.assertEqual([b["name"] for b in session_test.find(windows, role="push button")],
                         ["Konsole", "System Settings"])
        self.assertEqual(session_test.find(TREE, description="Active window")[0]["name"],
                         "System Settings")
        self.assertEqual(session_test.find(TREE, role="dialog"), [])

    def test_is_active(self):
        self.assertTrue(session_test.is_active({"active": "org.kde.konsole"}, "konsole"))
        self.assertFalse(session_test.is_active({"active": None}, "konsole"))
        self.assertFalse(session_test.is_active({}, "systemsettings"))

    def test_qcode(self):
        self.assertEqual([session_test.qcode(c) for c in "Kon 1"], ["k", "o", "n", "spc", "1"])
        with self.assertRaises(KeyError):
            session_test.qcode("@")


if __name__ == "__main__":
    unittest.main()
