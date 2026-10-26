#!/usr/bin/python3 -I
# SPDX-License-Identifier: GPL-3.0-or-later
"""AT-SPI helper for the session test (test-time only, never shipped).

Run as the live user through runas.py.

  atspi_probe.py enable
      Sets org.a11y.Status IsEnabled=true on the session bus, as Orca does,
      so Qt applications turn on their accessibility bridge.
  atspi_probe.py walk APP [SECONDS]
      Waits up to SECONDS for an application named APP on the AT-SPI desktop
      (or, failing that, one whose program is APP) and prints its tree as
      JSON: role, name, description, states and window-relative extents of
      every object.
  atspi_probe.py focused [SECONDS]
      Prints the currently focused object (role and name) as JSON, waiting up
      to SECONDS for one to exist.
"""

import json
import os
import sys
import time

import gi

gi.require_version("Atspi", "2.0")
gi.require_version("Gio", "2.0")
from gi.repository import Atspi, Gio, GLib  # noqa: E402

STATES = ("focused", "focusable", "active", "showing", "visible", "selected", "editable")


def enable():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    bus.call_sync("org.a11y.Bus", "/org/a11y/bus", "org.freedesktop.DBus.Properties", "Set",
                  GLib.Variant("(ssv)", ("org.a11y.Status", "IsEnabled", GLib.Variant("b", True))),
                  None, Gio.DBusCallFlags.NONE, 5000, None)
    print(json.dumps({"enabled": True}))
    return 0


def describe(obj):
    states = obj.get_state_set()
    names = [s for s in STATES
             if states.contains(getattr(Atspi.StateType, s.upper()))]
    try:
        ext = obj.get_extents(Atspi.CoordType.WINDOW)
        extents = [ext.x, ext.y, ext.width, ext.height]
    except GLib.Error:
        extents = None
    return {
        "role": obj.get_role_name(),
        "name": obj.get_name() or "",
        "description": obj.get_description() or "",
        "states": names,
        "extents": extents,
    }


def tree(obj, depth=0, limit=40):
    node = describe(obj)
    if depth < limit:
        children = []
        for i in range(obj.get_child_count()):
            child = obj.get_child_at_index(i)
            if child is not None:
                children.append(tree(child, depth + 1, limit))
        node["children"] = children
    return node


def applications():
    desktop = Atspi.get_desktop(0)
    apps = (desktop.get_child_at_index(i) for i in range(desktop.get_child_count()))
    return [app for app in apps if app is not None]


def program(app):
    """The program an application runs, for those (such as KDE's greeters)
    whose AT-SPI name may not be it. The command line and the short name stay
    readable for processes that refuse ptrace."""
    try:
        pid = app.get_process_id()
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            argv0 = f.read().split(b"\0")[0].decode(errors="replace")
        if argv0:
            return os.path.basename(argv0.split()[0])
        with open(f"/proc/{pid}/comm") as f:
            return f.read().strip()
    except (GLib.Error, OSError, IndexError):
        return ""


def find_app(name):
    apps = applications()
    for app in apps:
        if app.get_name() == name:
            return app
    for app in apps:
        found = program(app)
        # The kernel's short name keeps 15 characters.
        if found == name or (len(found) == 15 and name.startswith(found)):
            return app
    return None


def walk(name, seconds):
    deadline = time.monotonic() + seconds
    while True:
        app = find_app(name)
        if app is not None and app.get_child_count() > 0:
            print(json.dumps(tree(app)))
            return 0
        if time.monotonic() > deadline:
            names = [f"{app.get_name()} ({program(app)})" for app in applications()]
            print(json.dumps({"error": f"no application {name!r} on the AT-SPI desktop", "applications": names}))
            return 1
        time.sleep(1)


def find_focused(obj, depth=0):
    """Returns the deepest focused object below OBJ.

    Qt also marks focus scopes (the launcher pane, the taskbar) as focused
    while one of their children has focus, so the first match is not enough.
    """
    if depth > 40:
        return None
    for i in range(obj.get_child_count()):
        child = obj.get_child_at_index(i)
        if child is not None:
            found = find_focused(child, depth + 1)
            if found is not None:
                return found
    if obj.get_state_set().contains(Atspi.StateType.FOCUSED):
        return obj
    return None


def focused(seconds):
    deadline = time.monotonic() + seconds
    while True:
        desktop = Atspi.get_desktop(0)
        for i in range(desktop.get_child_count()):
            app = desktop.get_child_at_index(i)
            if app is None:
                continue
            obj = find_focused(app)
            if obj is not None:
                result = describe(obj)
                result["application"] = app.get_name()
                print(json.dumps(result))
                return 0
        if time.monotonic() > deadline:
            print(json.dumps({"error": "nothing focused"}))
            return 1
        time.sleep(0.5)


def main(argv):
    if len(argv) >= 2 and argv[1] == "enable":
        return enable()
    if len(argv) >= 3 and argv[1] == "walk":
        return walk(argv[2], float(argv[3]) if len(argv) > 3 else 30)
    if len(argv) >= 2 and argv[1] == "focused":
        return focused(float(argv[2]) if len(argv) > 2 else 5)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
