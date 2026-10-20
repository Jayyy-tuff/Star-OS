#!/usr/bin/python3 -I
# SPDX-License-Identifier: GPL-3.0-or-later
"""Receives the KWin oracle's reports on the session bus (test-time helper).

Owns org.staros.TestOracle on the live user's session bus and appends each
Report(s) payload as one line to the output file. Run it as the live user
through runas.py. It is never shipped in the image.

Usage: oracle_listener.py OUTPUT_FILE
"""

import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

XML = """
<node>
  <interface name="org.staros.TestOracle">
    <method name="Report"><arg type="s" name="payload" direction="in"/></method>
  </interface>
</node>
"""


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    output = open(argv[1], "a", buffering=1)
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    loop = GLib.MainLoop()

    def on_call(connection, sender, path, interface, method, params, invocation):
        output.write(params.unpack()[0] + "\n")
        invocation.return_value(None)

    def on_bus(connection, name):
        connection.register_object("/org/staros/TestOracle", node.interfaces[0], on_call, None, None)

    def on_name(connection, name):
        output.write('{"event": "listener-ready"}\n')

    def on_lost(connection, name):
        output.write('{"event": "listener-name-lost"}\n')
        loop.quit()

    Gio.bus_own_name(Gio.BusType.SESSION, "org.staros.TestOracle", Gio.BusNameOwnerFlags.NONE,
                     on_bus, on_name, on_lost)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
