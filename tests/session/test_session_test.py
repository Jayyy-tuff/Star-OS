# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for the pure helpers of session_test.py (no QEMU)."""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import session_test  # noqa: E402

TREE = {
    "role": "application", "name": "plasmashell", "children": [
        {"role": "frame", "name": "", "children": [
            {"role": "tool bar", "name": "Taskbar", "description": "", "children": [
                {"role": "button", "name": "Applications", "description": "x", "children": []},
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
        self.assertEqual(len(session_test.find(TREE, role=session_test.BUTTON)), 4)
        self.assertEqual(len(session_test.find(TREE, role="push button")), 3)
        windows = session_test.find(TREE, role="list", name="Open windows")[0]
        self.assertEqual([b["name"] for b in session_test.find(windows, role=session_test.BUTTON)],
                         ["Konsole", "System Settings"])
        self.assertEqual(session_test.find(TREE, description="Active window")[0]["name"],
                         "System Settings")
        self.assertEqual(session_test.find(TREE, role="dialog"), [])

    def test_is_active(self):
        self.assertTrue(session_test.is_active({"active": "org.kde.konsole"}, "konsole"))
        self.assertFalse(session_test.is_active({"active": None}, "konsole"))
        self.assertFalse(session_test.is_active({}, "systemsettings"))

    def test_launcher_geometry(self):
        def tree(*tiles, window=(0, 0, 1920, 1080)):
            return {"role": "application", "children": [
                {"role": "frame", "name": "Star OS applications", "extents": list(window),
                 "children": [{"role": "push button", "name": n, "extents": list(e),
                               "children": []} for n, e in tiles]}]}
        ok, _ = session_test.launcher_geometry(tree(("A", (36, 117, 162, 126)),
                                                    ("B", (207, 117, 162, 126))))
        self.assertTrue(ok)
        ok, detail = session_test.launcher_geometry(tree(("A", (36, 117, 162, 126)),
                                                         ("B", (100, 117, 162, 126))))
        self.assertFalse(ok)
        self.assertIn("overlaps", detail)
        ok, detail = session_test.launcher_geometry(tree(("A", (1900, 0, 162, 126)),
                                                         ("B", (0, 0, 10, 10))))
        self.assertFalse(ok)
        self.assertIn("outside", detail)
        self.assertFalse(session_test.launcher_geometry({"role": "application"})[0])

    def test_outline_lists_named_objects(self):
        outline = json.loads(session_test.outline(TREE))
        self.assertEqual(outline[0], ["application", "plasmashell"])
        self.assertIn(["list", "Open windows"], outline)
        self.assertNotIn(["frame", ""], outline)
        self.assertEqual(len(json.loads(session_test.outline(TREE, limit=2))), 2)

    def test_qcode(self):
        self.assertEqual([session_test.qcode(c) for c in "Kon 1"], ["k", "o", "n", "spc", "1"])
        with self.assertRaises(KeyError):
            session_test.qcode("@")


if __name__ == "__main__":
    unittest.main()
