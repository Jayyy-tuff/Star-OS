#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Static checks of the Star OS shell sources in shell/ (M0.2, ADR-0008).

- Plasma package metadata is valid JSON with the expected structure, and each
  KPlugin Id matches its directory.
- Every file has an SPDX licence line or a .license sidecar.
- No file mentions 'org.kde.plasma.private' (private Plasma QML API).
- StarOS.Shell imports only QtQuick and QtQuick.Templates, and its qmldir
  lists exactly the module's QML files.

Prints one CHECK line per check. Exit status 0 if all passed, 1 otherwise.
"""

import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SHELL = os.path.join(ROOT, "shell")
MODULE = os.path.join(SHELL, "qml", "StarOS", "Shell")
MODULE_IMPORTS = {"QtQuick", "QtQuick.Templates"}
PACKAGE_KINDS = {"shells": "Plasma/Shell", "plasmoids": "Plasma/Applet"}
SPDX = "SPDX-License-Identifier:"
PRIVATE = "org.kde.plasma.private"


def shell_files(top=SHELL):
    for dirpath, _, names in os.walk(top):
        for name in sorted(names):
            yield os.path.join(dirpath, name)


def rel(path):
    return os.path.relpath(path, ROOT)


def check_licences(files):
    problems = []
    for path in files:
        if path.endswith(".license"):
            continue
        if os.path.exists(path + ".license"):
            with open(path + ".license", encoding="utf-8") as f:
                if SPDX not in f.read():
                    problems.append(f"{rel(path)}.license has no SPDX line")
            continue
        with open(path, encoding="utf-8") as f:
            head = "".join(f.readline() for _ in range(5))
        if SPDX not in head:
            problems.append(f"{rel(path)} has no SPDX line and no .license sidecar")
    return problems


def check_private_api(files):
    problems = []
    for path in files:
        with open(path, encoding="utf-8") as f:
            if PRIVATE in f.read():
                problems.append(f"{rel(path)} mentions {PRIVATE}")
    return problems


def check_metadata():
    problems = []
    found = 0
    for kind, structure in PACKAGE_KINDS.items():
        base = os.path.join(SHELL, "plasma", kind)
        for name in sorted(os.listdir(base)):
            path = os.path.join(base, name, "metadata.json")
            found += 1
            try:
                with open(path, encoding="utf-8") as f:
                    data = json.load(f)
            except (OSError, ValueError) as err:
                problems.append(f"{rel(path)}: {err}")
                continue
            plugin = data.get("KPlugin", {})
            if plugin.get("Id") != name:
                problems.append(f"{rel(path)}: KPlugin Id {plugin.get('Id')!r} != {name!r}")
            if data.get("KPackageStructure") != structure:
                problems.append(f"{rel(path)}: KPackageStructure is not {structure}")
            if plugin.get("License") != "GPL-3.0-or-later":
                problems.append(f"{rel(path)}: License is not GPL-3.0-or-later")
            if kind == "plasmoids":
                if data.get("X-Plasma-ContainmentType") not in ("Panel", "Desktop"):
                    problems.append(f"{rel(path)}: not a Panel or Desktop containment")
                main = os.path.join(base, name, "contents", "ui", "main.qml")
                if not os.path.isfile(main):
                    problems.append(f"{rel(main)} is missing")
            else:
                for needed in ("defaults", "layout.js", os.path.join("views", "Panel.qml"),
                               os.path.join("views", "Desktop.qml")):
                    if not os.path.isfile(os.path.join(base, name, "contents", needed)):
                        problems.append(f"{rel(path)}: contents/{needed} is missing")
    if found != 3:
        problems.append(f"expected 3 Plasma packages, found {found}")
    return problems


def qml_imports(path):
    imports = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            match = re.match(r"\s*import\s+([A-Za-z][\w.]*)", line)
            if match:
                imports.add(match.group(1))
    return imports


def check_module():
    problems = []
    qml = sorted(n for n in os.listdir(MODULE) if n.endswith(".qml"))
    for name in qml:
        extra = qml_imports(os.path.join(MODULE, name)) - MODULE_IMPORTS
        if extra:
            problems.append(f"StarOS.Shell/{name} imports {', '.join(sorted(extra))}")
    listed = set()
    with open(os.path.join(MODULE, "qmldir"), encoding="utf-8") as f:
        for line in f:
            words = line.split()
            if words and words[-1].endswith(".qml"):
                listed.add(words[-1])
    if listed != set(qml):
        problems.append(f"qmldir lists {sorted(listed)}, the module has {qml}")
    return problems


def main():
    files = list(shell_files())
    checks = [
        ("Plasma package metadata", check_metadata()),
        ("SPDX licence lines", check_licences(files)),
        (f"no {PRIVATE} in shell/", check_private_api(files)),
        ("StarOS.Shell imports and qmldir", check_module()),
    ]
    failed = False
    for name, problems in checks:
        print(f"CHECK {'FAIL' if problems else 'PASS'} {name}")
        for problem in problems:
            print(f"    {problem}")
        failed = failed or bool(problems)
    print(f"{len(files)} files under shell/")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
