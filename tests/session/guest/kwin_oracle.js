// SPDX-License-Identifier: GPL-3.0-or-later
// Test-time KWin script (never shipped): reports KWin's own view of the
// windows and the active window to the test listener over D-Bus, because
// KWin script output is not logged at the default level.

function report(event) {
    const active = workspace.activeWindow;
    const windows = workspace.windowList()
        .filter(w => w.normalWindow)
        .map(w => ({resourceClass: String(w.resourceClass), caption: String(w.caption),
                    minimized: w.minimized, skipTaskbar: w.skipTaskbar}));
    callDBus("org.staros.TestOracle", "/org/staros/TestOracle", "org.staros.TestOracle",
             "Report", JSON.stringify({
                 event: event,
                 active: active ? String(active.resourceClass) : null,
                 activeNormal: active ? active.normalWindow : false,
                 windows: windows
             }));
}

workspace.windowAdded.connect(() => report("added"));
workspace.windowRemoved.connect(() => report("removed"));
workspace.windowActivated.connect(() => report("activated"));
report("loaded");
