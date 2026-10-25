#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Static checks of the Star OS shell sources in shell/ (M0.2, ADR-0008; M0.3).

- Plasma package metadata is valid JSON with the expected structure, and each
  KPlugin Id matches its directory.
- Every file has an SPDX licence line or a .license sidecar.
- No file mentions 'org.kde.plasma.private' (private Plasma QML API).
- StarOS.Shell imports only QtQuick, QtQuick.Templates, QtQuick.Effects and
  QtQuick.Window, and its qmldir lists exactly the module's QML files.
- SVG artwork is well-formed, starts with a CC-BY-SA-4.0 SPDX comment, keeps
  to what Qt's SVG renderer draws (no filters, masks, clip paths, patterns,
  images, text or CSS), and stays under its size limit; the icons are the seven
  256x256 Star OS icons; every wallpaper colour lies between Theme.qml's
  wallpaperDarkest and wallpaperLightest, channel by channel, and both are used;
  the symbols (M0.5) are 24x24, white only, and exactly the names Icons.qml
  lists; the logo is brand/star.svg, 64x64.

Prints one CHECK line per check. Exit status 0 if all passed, 1 otherwise.
"""

import json
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SHELL = os.path.join(ROOT, "shell")
MODULE = os.path.join(SHELL, "qml", "StarOS", "Shell")
MODULE_IMPORTS = {"QtQuick", "QtQuick.Templates", "QtQuick.Effects", "QtQuick.Window"}
PACKAGE_KINDS = {"shells": "Plasma/Shell", "plasmoids": "Plasma/Applet"}
SPDX = "SPDX-License-Identifier:"
PRIVATE = "org.kde.plasma.private"
ARTWORK_SPDX = re.compile(r"\A\s*<!--\s*SPDX-License-Identifier:\s*CC-BY-SA-4\.0\s*-->")
ICONS = {"terminal.svg", "settings.svg", "files.svg", "sun-store.svg", "moon-browser.svg",
         "lens.svg", "storage.svg"}
ICON_LIMIT = 8 * 1024
WALLPAPER = os.path.join(MODULE, "wallpaper", "star-os-glass.svg")
WALLPAPER_LIMIT = 64 * 1024
SYMBOLS = os.path.join(MODULE, "symbols")
SYMBOL_LIMIT = 2 * 1024
LOGO = os.path.join(MODULE, "brand", "star.svg")
LOGO_LIMIT = 4 * 1024
# Elements and attributes outside what the M0.3 artwork may use.
SVG_ELEMENTS = {"svg", "defs", "g", "path", "rect", "circle", "ellipse", "line", "polyline",
                "polygon", "linearGradient", "radialGradient", "stop"}
SVG_ATTRIBUTES_FORBIDDEN = {"style", "class", "filter", "mask", "clip-path"}
COLOUR_ATTRIBUTES = ("fill", "stroke", "stop-color")


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


def svg_tag(element):
    return element.tag.split("}", 1)[-1]


def check_svg(path, limit):
    """Problems of one artwork file, and its parsed root (None if unreadable)."""
    problems = []
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if not ARTWORK_SPDX.match(text):
        problems.append(f"{rel(path)} does not start with a CC-BY-SA-4.0 SPDX comment")
    size = len(text.encode("utf-8"))
    if size >= limit:
        problems.append(f"{rel(path)} is {size} bytes, limit {limit}")
    try:
        root = ET.fromstring(text)
    except ET.ParseError as err:
        return problems + [f"{rel(path)}: {err}"], None
    for element in root.iter():
        tag = svg_tag(element)
        if tag not in SVG_ELEMENTS:
            problems.append(f"{rel(path)}: element <{tag}> is not allowed")
        for name in element.attrib:
            if name.split("}", 1)[-1] in SVG_ATTRIBUTES_FORBIDDEN:
                problems.append(f"{rel(path)}: attribute {name!r} on <{tag}> is not allowed")
    return problems, root


def hex_colour(value):
    """(r, g, b) of '#rgb' or '#rrggbb', or None."""
    match = re.fullmatch(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})", value.strip())
    if not match:
        return None
    digits = match.group(1)
    if len(digits) == 3:
        digits = "".join(c * 2 for c in digits)
    return tuple(int(digits[i:i + 2], 16) for i in (0, 2, 4))


def theme_colour(name):
    with open(os.path.join(MODULE, "Theme.qml"), encoding="utf-8") as f:
        match = re.search(r"property color " + name + r': "(#[0-9a-fA-F]{6})"', f.read())
    return hex_colour(match.group(1)) if match else None


def listed_symbols():
    with open(os.path.join(MODULE, "Icons.qml"), encoding="utf-8") as f:
        text = f.read()
    match = re.search(r"property var symbols: \[(.*?)\]", text, re.S)
    return set(re.findall(r'"([a-z-]+)"', match.group(1))) if match else set()


def check_symbols():
    problems = []
    names = {n[:-4] for n in os.listdir(SYMBOLS) if n.endswith(".svg")} if os.path.isdir(SYMBOLS) else set()
    listed = listed_symbols()
    if names != listed:
        problems.append(f"symbols/ has {sorted(names - listed)} not in Icons.qml, "
                        f"Icons.qml lists {sorted(listed - names)} without a file")
    for name in sorted(names):
        path = os.path.join(SYMBOLS, name + ".svg")
        found, root = check_svg(path, SYMBOL_LIMIT)
        problems += found
        if root is None:
            continue
        if root.get("viewBox") != "0 0 24 24":
            problems.append(f"{rel(path)}: viewBox is not '0 0 24 24'")
        for element in root.iter():
            for attribute in ("fill", "stroke"):
                value = element.get(attribute)
                if value not in (None, "none", "#ffffff"):
                    problems.append(f"{rel(path)}: {attribute}={value!r}; symbols are white")
    return problems


def check_artwork():
    problems = []
    icon_dir = os.path.join(MODULE, "icons")
    names = set(os.listdir(icon_dir)) if os.path.isdir(icon_dir) else set()
    if names != ICONS:
        problems.append(f"StarOS.Shell/icons has {sorted(names)}, expected {sorted(ICONS)}")
    for name in sorted(names & ICONS):
        found, root = check_svg(os.path.join(icon_dir, name), ICON_LIMIT)
        problems += found
        if root is not None and root.get("viewBox") != "0 0 256 256":
            problems.append(f"StarOS.Shell/icons/{name}: viewBox is not '0 0 256 256'")
    artwork_dirs = (icon_dir, os.path.dirname(WALLPAPER), SYMBOLS, os.path.dirname(LOGO))
    for path in shell_files():
        if path.endswith(".svg") and os.path.dirname(path) not in artwork_dirs:
            problems.append(f"{rel(path)}: artwork belongs in StarOS.Shell/icons, symbols, brand or wallpaper")
    problems += check_symbols()
    if not os.path.isfile(LOGO):
        problems.append(f"{rel(LOGO)} is missing")
    else:
        found, root = check_svg(LOGO, LOGO_LIMIT)
        problems += found
        if root is not None and root.get("viewBox") != "0 0 64 64":
            problems.append(f"{rel(LOGO)}: viewBox is not '0 0 64 64'")
    if not os.path.isfile(WALLPAPER):
        return problems + [f"{rel(WALLPAPER)} is missing"]
    found, root = check_svg(WALLPAPER, WALLPAPER_LIMIT)
    problems += found
    darkest, lightest = theme_colour("wallpaperDarkest"), theme_colour("wallpaperLightest")
    if darkest is None or lightest is None:
        return problems + ["Theme.qml lacks wallpaperDarkest or wallpaperLightest"]
    if root is None:
        return problems
    used = set()
    for element in root.iter():
        for name in COLOUR_ATTRIBUTES:
            value = element.get(name)
            if value is None or value == "none" or value.startswith("url(#"):
                continue
            colour = hex_colour(value)
            if colour is None:
                problems.append(f"{rel(WALLPAPER)}: {name}={value!r} is not a hex colour")
            elif not all(lo <= c <= hi for lo, c, hi in zip(darkest, colour, lightest)):
                problems.append(f"{rel(WALLPAPER)}: {value} is outside wallpaperDarkest.."
                                "wallpaperLightest")
            else:
                used.add(colour)
    for name, colour in (("wallpaperDarkest", darkest), ("wallpaperLightest", lightest)):
        if colour not in used:
            problems.append(f"{rel(WALLPAPER)} does not use Theme.{name}")
    return problems


def main():
    files = list(shell_files())
    checks = [
        ("Plasma package metadata", check_metadata()),
        ("SPDX licence lines", check_licences(files)),
        (f"no {PRIVATE} in shell/", check_private_api(files)),
        ("StarOS.Shell imports and qmldir", check_module()),
        ("Artwork (licence, SVG subset, sizes, wallpaper colours)", check_artwork()),
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
