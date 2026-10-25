// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import org.kde.coreaddons as KCoreAddons
import org.kde.layershell as LayerShell
import StarOS.Shell
import StarOS.System

// The surface of the taskbar's panels: a transparent layer-shell Overlay
// window over the whole screen hosting one of the Plasma-free start menu,
// quick settings or calendar panels, each drawing a light dim and its glass
// panel above the taskbar. KWin creates a new surface on every show and
// activates it, so the panel receives real keyboard focus.
Window {
    id: win

    required property var catalogue
    property var systemStatus: null
    property var audio: null
    property var display: null
    property var network: null
    property var notifications: null
    property var pinnedIds: []
    property Component iconFallback: null
    property bool doNotDisturb: false
    // The taskbar's right end, in screen coordinates.
    property real anchorRight: win.width
    // "start", "quick" or "calendar".
    property string panel: "start"
    readonly property bool open: win.visible && win.current !== null && win.current.shown
    readonly property Item current: win.panel === "quick" ? quick : win.panel === "calendar" ? calendar : menu

    // Set once the surface was activated, so that only a later deactivation
    // (Alt+Tab, a click elsewhere) hides it.
    property bool hadFocus: false

    signal lockRequested()
    signal logoutRequested()
    signal restartRequested()
    signal shutdownRequested()
    signal powerRequested()
    signal doNotDisturbToggled()
    signal launchRequested(string desktopId)
    signal notificationsSeen()
    signal notificationCloseRequested(int row)
    signal notificationDefaultActionRequested(int row)
    signal notificationActionRequested(int row, string actionName)
    signal clearAllRequested()

    visible: false
    transientParent: null
    title: win.panel === "quick" ? qsTr("Quick settings")
        : win.panel === "calendar" ? qsTr("Calendar and notifications") : qsTr("Star OS applications")
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

    // Opens the named panel, or closes it when it is the one open.
    function toggle(name) {
        if (win.open && win.panel === name) {
            win.hidePanel();
        } else {
            win.showPanel(name);
        }
    }

    function showPanel(name) {
        hideTimer.stop();
        for (const item of [menu, quick, calendar]) {
            item.shown = false;
        }
        win.panel = name;
        win.current.reset();
        win.hadFocus = false;
        win.visible = true;
        win.current.shown = true;
        win.current.forceActiveFocus();
        win.current.reset();
        if (name === "calendar") {
            win.notificationsSeen();
        }
        console.info("STAROS-SHELL panel=" + name);
        if (name === "start") {
            console.info("STAROS-SHELL launcher=open");
        }
    }

    // The panel fades out, then the surface goes.
    function hidePanel() {
        if (!win.open) {
            return;
        }
        win.current.shown = false;
        hideTimer.restart();
        console.info("STAROS-SHELL panel=closed");
        if (win.panel === "start") {
            console.info("STAROS-SHELL launcher=closed");
        }
    }

    function launch(desktopId) {
        win.hidePanel();
        win.launchRequested(desktopId);
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
            win.hidePanel();
        }
    }

    KCoreAddons.KUser {
        id: user
    }

    StartMenu {
        id: menu
        anchors.fill: parent
        visible: win.panel === "start"
        focus: win.panel === "start"
        shown: false
        catalogue: win.catalogue
        iconFallback: win.iconFallback
        pinnedIds: win.pinnedIds
        userName: user.fullName !== "" ? user.fullName : user.loginName
        userDetail: !win.systemStatus ? ""
            : win.systemStatus.storageMode === "live" ? qsTr("Live session · changes are kept in memory")
            : win.systemStatus.storageMode === "star-storage" ? qsTr("Star Storage · your changes are kept")
            : ""
        onCloseRequested: win.hidePanel()
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
            win.hidePanel();
            win.lockRequested();
        }
        onLogoutRequested: {
            win.hidePanel();
            win.logoutRequested();
        }
        onRestartRequested: {
            win.hidePanel();
            win.restartRequested();
        }
        onShutdownRequested: {
            win.hidePanel();
            win.shutdownRequested();
        }
    }

    QuickSettings {
        id: quick
        anchors.fill: parent
        visible: win.panel === "quick"
        focus: win.panel === "quick"
        shown: false
        audio: win.audio
        display: win.display
        network: win.network
        status: win.systemStatus
        doNotDisturb: win.doNotDisturb
        anchorRight: win.anchorRight
        onCloseRequested: win.hidePanel()
        onDoNotDisturbToggled: win.doNotDisturbToggled()
        onLensRequested: win.launch("org.staros.lens.desktop")
        onStorageRequested: win.launch("org.staros.storage.desktop")
        onSettingsRequested: win.launch("systemsettings.desktop")
        onPowerRequested: {
            win.hidePanel();
            win.powerRequested();
        }
    }

    CalendarPanel {
        id: calendar
        anchors.fill: parent
        visible: win.panel === "calendar"
        focus: win.panel === "calendar"
        shown: false
        notifications: win.notifications
        iconFallback: win.iconFallback
        doNotDisturb: win.doNotDisturb
        anchorRight: win.anchorRight
        onCloseRequested: win.hidePanel()
        onNotificationCloseRequested: row => win.notificationCloseRequested(row)
        onNotificationDefaultActionRequested: row => {
            win.notificationDefaultActionRequested(row);
            win.hidePanel();
        }
        onNotificationActionRequested: (row, actionName) => {
            win.notificationActionRequested(row, actionName);
            win.hidePanel();
        }
        onClearAllRequested: win.clearAllRequested()
    }
}
