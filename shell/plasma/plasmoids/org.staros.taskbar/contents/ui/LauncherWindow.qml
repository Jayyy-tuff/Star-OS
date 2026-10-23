// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import StarOS.Shell
import StarOS.System

// Full-screen launcher surface: a layer-shell Overlay window hosting the
// Plasma-free Launcher. KWin creates a new surface on every show and activates
// it, so the search field receives real keyboard focus.
Window {
    id: win

    required property Item catalogue
    property Component iconFallback: null

    // Set once the surface was activated, so that only a later deactivation
    // (Alt+Tab, a click elsewhere) hides it.
    property bool hadFocus: false

    visible: false
    transientParent: null
    title: qsTr("Star OS applications")
    color: Theme.launcherBackdrop

    // An unknown scope gives a normal layer window in KWin; KWin 6.7.5 keeps
    // only whether the surface accepts focus, so Exclusive acts like OnDemand.
    LayerShell.Window.scope: "staros-launcher"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
        | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
    LayerShell.Window.activateOnShow: true

    function toggleLauncher() {
        if (win.visible) {
            win.hideLauncher();
        } else {
            win.showLauncher();
        }
    }

    function showLauncher() {
        launcher.reset();
        win.hadFocus = false;
        win.visible = true;
        console.info("STAROS-SHELL launcher=open");
    }

    function hideLauncher() {
        if (!win.visible) {
            return;
        }
        win.visible = false;
        console.info("STAROS-SHELL launcher=closed");
    }

    onActiveChanged: {
        if (win.active) {
            win.hadFocus = true;
        } else if (win.visible && win.hadFocus) {
            win.hideLauncher();
        }
    }

    Launcher {
        id: launcher
        anchors.fill: parent
        focus: true
        catalogue: win.catalogue
        iconFallback: win.iconFallback
        onCloseRequested: win.hideLauncher()
        onAnswerCopied: text => console.info("STAROS-SHELL answer=" + text)
        // Notes typed as "note: ..." go to the desktop's notes, cascading.
        onNoteRequested: text => {
            const offset = (NotesStore.count % 8) * 0.04;
            const noteId = NotesStore.addNote(text);
            if (noteId !== "") {
                NotesStore.moveNote(noteId, 0.04 + offset, 0.06 + offset);
            }
            console.info("STAROS-SHELL note=" + (noteId !== "" ? "added" : "full"));
        }
    }
}
