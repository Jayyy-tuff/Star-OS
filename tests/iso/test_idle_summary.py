# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for idle_summary.py."""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import idle_summary  # noqa: E402


def write_result(directory, name, idle):
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, name), "w") as f:
        json.dump({"session": {"idle": idle} if idle is not None else None}, f)


class IdleSummaryTest(unittest.TestCase):
    def test_median_min_max(self):
        with tempfile.TemporaryDirectory() as top:
            for run, pss in enumerate((600.0, 640.5, 610.0), start=1):
                write_result(os.path.join(top, f"idle-run-{run}"), "result-uefi.json",
                             {"session_pss_mib": pss, "session_cpu_pct": run * 0.5,
                              "renderer": "llvmpipe"})
            reports = idle_summary.load_reports([top])
            rows = {r[0]: r[1:] for r in idle_summary.summarise(reports)}
        self.assertEqual(len(reports), 3)
        self.assertEqual(rows["Session PSS (MiB, all UID 1000 processes)"],
                         (610.0, 600.0, 640.5, 3))
        self.assertEqual(rows["Session CPU (% of one CPU, 60 s window)"], (1.0, 0.5, 1.5, 3))

    def test_runs_without_idle_report_are_skipped(self):
        with tempfile.TemporaryDirectory() as top:
            write_result(os.path.join(top, "a"), "result-uefi.json", None)
            write_result(os.path.join(top, "b"), "result-uefi.json", {"session_pss_mib": 1})
            self.assertEqual(len(idle_summary.load_reports([top])), 1)

    def test_no_reports_is_an_error(self):
        with tempfile.TemporaryDirectory() as top:
            self.assertEqual(idle_summary.main([top]), 1)

    def test_markdown_has_label_and_table(self):
        reports = [("x", {"session_pss_mib": 5, "renderer": "llvmpipe"})]
        text = idle_summary.markdown(idle_summary.summarise(reports), reports)
        self.assertIn("Not a performance claim", text)
        self.assertIn("| Session PSS (MiB, all UID 1000 processes) | 5 | 5 | 5 | 1 |", text)


if __name__ == "__main__":
    unittest.main()
