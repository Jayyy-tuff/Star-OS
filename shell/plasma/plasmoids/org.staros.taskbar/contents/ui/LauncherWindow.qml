// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import org.kde.coreaddons as KCoreAddons
import org.kde.layershell as LayerShell
import StarOS.Shell
import StarOS.System

// The start menu's surface: a transparent layer-shell Overlay window over the
// whole screen hosting the Plasma-free StartMenu, which draws a light dim and
// its panel above the taskbar. KWin creates a new surface on every show and
// activates it, so the search field receives real keyboard focus.
Window {
    id: win

    required property var catalogue
    property var systemStatus: null
    property var pinnedIds: []
    property Component iconFallback: null

    // Set once the surface was activated, so that only a later deactivation
    // (Alt+Tab, a click elsewhere) hides it.
    property bool hadFocus: false

    signal lockRequested()
    signal logoutRequested()
    signal restartRequested()
    signal shutdownRequested()

    visible: false
    transientParent: null
    title: qsTr("Star OS applications")
    color: "transparent"

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
        if (win.visible && menu.shown) {
            win.hideLauncher();
        } else {
            win.showLauncher();
        }
    }

    function showLauncher() {
        hideTimer.stop();
        menu.shown = false;
        menu.reset();
        win.hadFocus = false;
        win.visible = true;
        menu.shown = true;
        console.info("STAROS-SHELL launcher=open");
    }

    // The panel fades out, then the surface goes.
    function hideLauncher() {
        if (!win.visible || !menu.shown) {
            return;
        }
        menu.shown = false;
        hideTimer.restart();
        console.info("STAROS-SHELL launcher=closed");
    }

    Timer {
        id: hideTimer
        interval: Theme.durationMedium
        onTriggered: win.visible = false
    }

    onActiveChanged: {
        if (win.active) {
            win.hadFocus = true;
        } else if (win.visible && win.hadFocus) {
            win.hideLauncher();
        }
    }

    KCoreAddons.KUser {
        id: user
    }

    StartMenu {
        id: menu
        anchors.fill: parent
        focus: true
        shown: false
        catalogue: win.catalogue
        iconFallback: win.iconFallback
        pinnedIds: win.pinnedIds
        userName: user.fullName !== "" ? user.fullName : user.loginName
        userDetail: !win.systemStatus ? ""
            : win.systemStatus.storageMode === "live" ? qsTr("Live session · changes are kept in memory")
            : win.systemStatus.storageMode === "star-storage" ? qsTr("Star Storage · your changes are kept")
            : ""
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
        onLockRequested: {
            win.hideLauncher();
            win.lockRequested();
        }
        onLogoutRequested: {
            win.hideLauncher();
            win.logoutRequested();
        }
        onRestartRequested: {
            win.hideLauncher();
            win.restartRequested();
        }
        onShutdownRequested: {
            win.hideLauncher();
            win.shutdownRequested();
        }
    }
}
