#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Summarises the idle reports of several boot_test.py --wait-idle runs (T0-25).

Reads result-*.json files below the given directories, prints the median,
minimum and maximum of each figure, and appends the same table to
$GITHUB_STEP_SUMMARY when it is set. There is no threshold: these numbers
describe CI virtual machines and are not performance claims.

Exit status: 0 if at least one run had an idle report, 1 otherwise.
"""

import glob
import json
import os
import statistics
import sys

LABEL = ("CI QEMU/KVM, 4 vCPU, 4 GiB, renderer as reported (llvmpipe without a GPU). "
         "Not a performance claim.")
FIGURES = (
    ("session_pss_mib", "Session PSS (MiB, all UID 1000 processes)"),
    ("plasmashell_pss_mib", "plasmashell PSS (MiB)"),
    ("kwin_pss_mib", "kwin_wayland PSS (MiB)"),
    ("mem_used_mib", "System memory in use (MiB, MemTotal - MemAvailable)"),
    ("session_cpu_pct", "Session CPU (% of one CPU, 60 s window)"),
    ("process_count", "Session processes"),
)


def load_reports(paths):
    reports = []
    for top in paths:
        for path in sorted(glob.glob(os.path.join(top, "**", "result-*.json"), recursive=True)):
            try:
                with open(path) as f:
                    result = json.load(f)
            except (OSError, ValueError) as err:
                print(f"warning: {path}: {err}", file=sys.stderr)
                continue
            idle = (result.get("session") or {}).get("idle")
            if isinstance(idle, dict):
                reports.append((path, idle))
            else:
                print(f"warning: {path} has no idle report", file=sys.stderr)
    return reports


def summarise(reports):
    rows = []
    for key, title in FIGURES:
        values = [r[key] for _, r in reports if isinstance(r.get(key), (int, float))]
        if values:
            rows.append((title, statistics.median(values), min(values), max(values), len(values)))
    return rows


def markdown(rows, reports):
    renderers = sorted({str(r.get("renderer")) for _, r in reports})
    lines = [
        "### Idle session figures (T0-25)",
        "",
        LABEL,
        "",
        f"Runs: {len(reports)}. Renderer: {', '.join(renderers)}.",
        "",
        "| Figure | Median | Min | Max | Runs |",
        "|---|---:|---:|---:|---:|",
    ]
    for title, median, low, high, count in rows:
        lines.append(f"| {title} | {median:g} | {low:g} | {high:g} | {count} |")
    return "\n".join(lines) + "\n"


def main(argv=None):
    paths = (argv if argv is not None else sys.argv[1:]) or ["."]
    reports = load_reports(paths)
    if not reports:
        print("error: no idle reports found", file=sys.stderr)
        return 1
    text = markdown(summarise(reports), reports)
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
