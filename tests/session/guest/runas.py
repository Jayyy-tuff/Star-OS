#!/usr/bin/python3 -I
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runs a command as the live user with plasmashell's session environment.

Test-time helper for tests/session/session_test.py. It is copied into
/run/staros-test (tmpfs) through the guest agent and never ships in the image.

Usage: runas.py COMMAND [ARG...]
"""

import os
import sys

UID = 1000
KEEP = ("WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "XDG_SESSION_TYPE",
        "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "XDG_SEAT", "XDG_SESSION_ID",
        "XDG_DATA_DIRS", "XDG_CONFIG_DIRS", "LANG", "HOME", "USER", "LOGNAME", "PATH",
        "DISPLAY", "QT_QPA_PLATFORM", "KDE_FULL_SESSION", "KDE_SESSION_VERSION")


def session_environment():
    for name in sorted(os.listdir("/proc"), key=lambda n: int(n) if n.isdigit() else 0):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/comm") as f:
                if f.read().strip() != "plasmashell":
                    continue
            if os.stat(f"/proc/{name}").st_uid != UID:
                continue
            with open(f"/proc/{name}/environ", "rb") as f:
                items = f.read().split(b"\0")
        except OSError:
            continue
        env = {}
        for item in items:
            key, sep, value = item.decode("utf-8", "replace").partition("=")
            if sep and key in KEEP:
                env[key] = value
        return env
    env = {"XDG_RUNTIME_DIR": f"/run/user/{UID}",
           "DBUS_SESSION_BUS_ADDRESS": f"unix:path=/run/user/{UID}/bus",
           "HOME": "/home/liveuser", "WAYLAND_DISPLAY": "wayland-0"}
    return env


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    env = session_environment()
    env.setdefault("PATH", "/usr/local/bin:/usr/bin")
    env.setdefault("HOME", "/home/liveuser")
    os.setgroups([])
    os.setgid(UID)
    os.setuid(UID)
    os.chdir(env["HOME"])
    os.execvpe(argv[1], argv[1:], env)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
